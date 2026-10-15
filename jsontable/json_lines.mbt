///|
/// One explicitly selected child-object array per parent record.
pub(all) struct JsonLineSpec {
  records_path : Array[String]
  items_path : Array[String]
  parent_fields : Array[JsonRecordField]
  item_fields : Array[JsonRecordField]
} derive(Debug, Eq)

///|
pub(all) struct JsonLineTable {
  table : Table
  parent_count : Int
  empty_parent_rows : Array[Int]
} derive(Debug, Eq)

///|
pub(all) suberror JsonLineError {
  InvalidJsonLineSpec(String)
  InvalidJsonLines(String)
  JsonLineFieldError(
    parent_row~ : Int,
    item_row~ : Int?,
    column~ : String,
    reason~ : String
  )
} derive(Debug, Eq)

///|
fn validate_json_line_spec(spec : JsonLineSpec) -> Unit raise JsonLineError {
  try {
    json_record_path_valid(spec.records_path, true)
    json_record_path_valid(spec.items_path, false)
    let fields = spec.parent_fields + spec.item_fields
    if spec.item_fields.is_empty() || fields.length() > 128 {
      raise InvalidJsonLineSpec(
        "Need at least one item field and at most 128 total fields",
      )
    }
    let seen : Map[String, Bool] = { "_parent_row": true, "_item_row": true }
    for field in fields {
      if field.name.trim().is_empty() ||
        field.name.length() > 256 ||
        seen.contains(field.name) {
        raise InvalidJsonLineSpec(
          "Field names must be unique and nonblank, at most 256 units; row locators are reserved",
        )
      }
      seen[field.name] = true
      json_record_path_valid(field.path, false)
    }
  } catch {
    InvalidJsonRecordSpec(reason) => raise InvalidJsonLineSpec(reason)
    error => raise InvalidJsonLineSpec("\{Repr(error)}")
  }
}

///|
/// Parse an explicit v1 child-array mapping. Empty arrays are intentionally skipped
/// and their parent positions are retained in the result. No schema inference.
pub fn parse_json_line_spec(text : String) -> JsonLineSpec raise JsonLineError {
  if text.length() > 65536 {
    raise InvalidJsonLineSpec("Mapping exceeds 65536 UTF-16 units")
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidJsonLineSpec("Invalid mapping JSON")
  }
  let spec = try {
    json_record_spec_keys(value, [
      "version", "record_path", "items_path", "parent_fields", "item_fields", "empty_items",
    ])
    guard value
      is {
        "version": Number(1, ..),
        "record_path": path,
        "items_path": items_path,
        "parent_fields": Array(parents),
        "item_fields": Array(items),
        "empty_items": String("skip"),
        ..
      } else {
      raise InvalidJsonLineSpec(
        "Expected version:1, record_path, items_path, parent_fields, item_fields and empty_items:skip",
      )
    }
    JsonLineSpec::{
      records_path: json_record_path(path),
      items_path: json_record_path(items_path),
      parent_fields: json_record_fields(parents),
      item_fields: json_record_fields(items),
    }
  } catch {
    InvalidJsonRecordSpec(reason) => raise InvalidJsonLineSpec(reason)
    error => raise InvalidJsonLineSpec("\{Repr(error)}")
  }
  validate_json_line_spec(spec)
  spec
}

///|
fn json_line_cell(
  record : Json,
  field : JsonRecordField,
  parent : Int,
  item : Int?,
) -> @scene.CellValue raise JsonLineError {
  json_record_cell(record, field, parent) catch {
    JsonRecordFieldError(column~, reason~, ..) =>
      raise JsonLineFieldError(
        parent_row=parent,
        item_row=item,
        column~,
        reason~,
      )
    _ => raise InvalidJsonLines("Invalid selected field")
  }
}

///|
/// Expand the selected child objects, preserving source order and typed scalars.
/// Parent fields are validated even when the selected child array is empty.
/// Null/missing/non-array child lists are refused, not silently treated as empty.
pub fn parse_json_lines(
  text : String,
  spec : JsonLineSpec,
) -> JsonLineTable raise JsonLineError {
  validate_json_line_spec(spec)
  if text.length() > 4000000 {
    raise InvalidJsonLines("Input exceeds 4000000 UTF-16 units")
  }
  let mut selected = @json.parse(text) catch {
    _ => raise InvalidJsonLines("Invalid JSON input")
  }
  for key in spec.records_path {
    guard selected is Object(object) else {
      raise InvalidJsonLines("record_path traverses a non-object")
    }
    selected = object
      .get(key)
      .unwrap_or_else(() => {
        raise InvalidJsonLines("Missing record_path key: " + key)
      })
  }
  guard selected is Array(parents) else {
    raise InvalidJsonLines("record_path must select an array")
  }
  if parents.length() > 10000 {
    raise InvalidJsonLines("At most 10000 parent records")
  }
  let width = spec.parent_fields.length() + spec.item_fields.length() + 2
  let columns = ["_parent_row", "_item_row"] +
    spec.parent_fields.map(field => field.name) +
    spec.item_fields.map(field => field.name)
  let mut expanded_units = columns.fold(init=0, (total, name) => {
    total + name.length()
  })
  let rows : Array[Array[@scene.CellValue]] = []
  let empty_parent_rows : Array[Int] = []
  for p, parent in parents {
    guard parent is Object(_) else {
      raise InvalidJsonLines("Parent \{p + 1} is not an object")
    }
    let parent_cells = spec.parent_fields.map(field => {
      json_line_cell(parent, field, p + 1, None)
    })
    let mut selected_items = parent
    for key in spec.items_path {
      guard selected_items is Object(object) else {
        raise JsonLineFieldError(
          parent_row=p + 1,
          item_row=None,
          column="items_path",
          reason="Child path traverses a non-object",
        )
      }
      selected_items = object
        .get(key)
        .unwrap_or_else(() => {
          raise JsonLineFieldError(
            parent_row=p + 1,
            item_row=None,
            column="items_path",
            reason="Missing child-array key: " + key,
          )
        })
    }
    guard selected_items is Array(items) else {
      raise JsonLineFieldError(
        parent_row=p + 1,
        item_row=None,
        column="items_path",
        reason="Child path must select an array; null is not an empty array",
      )
    }
    // Bound before expansion. No product of untrusted lengths can overflow.
    let remaining = 100000 / width - 1 - rows.length()
    if items.length() > 10000 - rows.length() || items.length() > remaining {
      raise InvalidJsonLines(
        "At most 10000 expanded rows and 100000 cells including headers",
      )
    }
    if items.is_empty() {
      empty_parent_rows.push(p + 1)
    }
    for i, item in items {
      guard item is Object(_) else {
        raise JsonLineFieldError(
          parent_row=p + 1,
          item_row=Some(i + 1),
          column="items_path",
          reason="Child item is not an object",
        )
      }
      let row : Array[@scene.CellValue] = [
        Number((p + 1).to_string()),
        Number((i + 1).to_string()),
      ]
      row.append(parent_cells)
      for field in spec.item_fields {
        row.push(json_line_cell(item, field, p + 1, Some(i + 1)))
      }
      for cell in row {
        expanded_units += match cell {
          Text(text) | Number(text) => text.length()
          Boolean(true) => 4
          Boolean(false) => 5
          _ => 0
        }
        if expanded_units > 4000000 {
          raise InvalidJsonLines(
            "Expanded scalar text exceeds 4000000 UTF-16 units including headers",
          )
        }
      }
      rows.push(row)
    }
  }
  {
    table: { columns, rows, },
    parent_count: parents.length(),
    empty_parent_rows,
  }
}

///|
pub extend JsonLineSpec with @debug.Debug::{to_repr}

///|
pub extend JsonLineSpec with Eq::{not_equal, equal}

///|
pub extend JsonLineTable with @debug.Debug::{to_repr}

///|
pub extend JsonLineTable with Eq::{not_equal, equal}

///|
pub extend JsonLineError with @debug.Debug::{to_repr}

///|
pub extend JsonLineError with Eq::{not_equal, equal}
