///|
/// Explicit handling for JSON null, which the Table scalar model cannot retain.
pub(all) enum JsonRecordNulls {
  RejectNull
  EmptyNull
  LiteralNull
} derive(Debug, Eq)

///|
pub(all) struct JsonRecordField {
  name : String
  path : Array[String]
  required : Bool
  nulls : JsonRecordNulls
} derive(Debug, Eq)

///|
pub(all) struct JsonRecordSpec {
  records_path : Array[String]
  fields : Array[JsonRecordField]
} derive(Debug, Eq)

///|
pub(all) suberror JsonRecordError {
  InvalidJsonRecordSpec(String)
  InvalidJsonRecords(String)
  JsonRecordFieldError(row~ : Int, column~ : String, reason~ : String)
} derive(Debug, Eq)

///|
fn json_record_path_valid(
  path : Array[String],
  empty : Bool,
) -> Unit raise JsonRecordError {
  if path.length() > 16 || (!empty && path.is_empty()) {
    raise InvalidJsonRecordSpec(
      "Paths need 1–16 object keys; record_path may be empty",
    )
  }
  for key in path {
    if key.length() > 256 {
      raise InvalidJsonRecordSpec("Path keys exceed 256 UTF-16 units")
    }
  }
}

///|
fn validate_json_record_spec(
  spec : JsonRecordSpec,
) -> Unit raise JsonRecordError {
  json_record_path_valid(spec.records_path, true)
  if spec.fields.is_empty() || spec.fields.length() > 128 {
    raise InvalidJsonRecordSpec("Expected 1–128 fields")
  }
  let seen : Map[String, Bool] = { "_record_row": true }
  for field in spec.fields {
    if field.name.trim().is_empty() ||
      field.name.length() > 256 ||
      seen.contains(field.name) {
      raise InvalidJsonRecordSpec(
        "Names must be unique, nonblank, at most 256 units; _record_row is reserved",
      )
    }
    seen[field.name] = true
    json_record_path_valid(field.path, false)
  }
}

///|
fn json_record_path(value : Json) -> Array[String] raise JsonRecordError {
  guard value is Array(values) else {
    raise InvalidJsonRecordSpec("Expected a path array")
  }
  let path : Array[String] = []
  for value in values {
    guard value is String(key) else {
      raise InvalidJsonRecordSpec("Path entries must be strings")
    }
    path.push(key)
  }
  path
}

///|
fn json_record_spec_keys(
  value : Json,
  allowed : Array[String],
) -> Unit raise JsonRecordError {
  guard value is Object(object) else {
    raise InvalidJsonRecordSpec("Expected an object")
  }
  for key, _ in object {
    if !allowed.contains(key) {
      raise InvalidJsonRecordSpec("Unknown specification key: " + key)
    }
  }
}

///|
fn json_record_fields(
  items : Array[Json],
) -> Array[JsonRecordField] raise JsonRecordError {
  let fields : Array[JsonRecordField] = []
  for item in items {
    json_record_spec_keys(item, ["name", "path", "required", "nulls"])
    guard item is { "name": String(name), "path": field_path, .. } else {
      raise InvalidJsonRecordSpec("Each field needs name and path")
    }
    let required = match item {
      { "required": True, .. } => true
      { "required": False, .. } => false
      { "required": _, .. } =>
        raise InvalidJsonRecordSpec("required must be Boolean")
      _ => false
    }
    let nulls = match item {
      { "nulls": String("reject"), .. } => RejectNull
      { "nulls": String("empty"), .. } => EmptyNull
      { "nulls": String("literal"), .. } => LiteralNull
      { "nulls": _, .. } =>
        raise InvalidJsonRecordSpec("nulls must be reject, empty or literal")
      _ => RejectNull
    }
    fields.push({ name, path: json_record_path(field_path), required, nulls, })
  }
  fields
}

///|
/// Parse an explicit mapping; optional field required=false and nulls="reject".
pub fn parse_json_record_spec(
  text : String,
) -> JsonRecordSpec raise JsonRecordError {
  if text.length() > 65536 {
    raise InvalidJsonRecordSpec("Mapping exceeds 65536 UTF-16 units")
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidJsonRecordSpec("Invalid mapping JSON")
  }
  json_record_spec_keys(value, ["record_path", "fields"])
  guard value is { "record_path": path, "fields": Array(items), .. } else {
    raise InvalidJsonRecordSpec("Expected record_path and fields arrays")
  }
  let fields = json_record_fields(items)
  let spec = { records_path: json_record_path(path), fields, }
  validate_json_record_spec(spec)
  spec
}

///|
fn json_record_cell(
  record : Json,
  field : JsonRecordField,
  row : Int,
) -> @scene.CellValue raise JsonRecordError {
  let mut current = Some(record)
  for key in field.path {
    if current is Some(value) {
      guard value is Object(object) else {
        raise JsonRecordFieldError(
          row~,
          column=field.name,
          reason="Path traverses a non-object",
        )
      }
      current = object.get(key)
    }
  }
  match current {
    None => {
      if field.required {
        raise JsonRecordFieldError(
          row~,
          column=field.name,
          reason="Required field is missing",
        )
      }
      Empty
    }
    Some(Null) =>
      match field.nulls {
        RejectNull =>
          raise JsonRecordFieldError(
            row~,
            column=field.name,
            reason="Null requires an explicit conversion policy",
          )
        EmptyNull => Empty
        LiteralNull => Text("null")
      }
    Some(String(value)) => Text(value)
    Some(True) => Boolean(true)
    Some(False) => Boolean(false)
    Some(Number(value, ..) as number) => {
      if value.is_inf() || value.is_nan() {
        raise JsonRecordFieldError(
          row~,
          column=field.name,
          reason="Nonfinite number",
        )
      }
      Number(number.stringify())
    }
    _ =>
      raise JsonRecordFieldError(
        row~,
        column=field.name,
        reason="Selected field is an object or array",
      )
  }
}

///|
/// Offline nested JSON intake. Paths traverse exact object keys only, never arrays.
/// Every row includes its original one-based selected-array index in _record_row.
/// Missing optional fields become Empty. Null conversion must be opted into.
/// Objects/arrays at a selected field and non-object intermediate values fail.
pub fn parse_json_records(
  text : String,
  spec : JsonRecordSpec,
) -> Table raise JsonRecordError {
  validate_json_record_spec(spec)
  if text.length() > 4000000 {
    raise InvalidJsonRecords("Input exceeds 4000000 UTF-16 units")
  }
  let mut selected = @json.parse(text) catch {
    _ => raise InvalidJsonRecords("Invalid JSON input")
  }
  for key in spec.records_path {
    guard selected is Object(object) else {
      raise InvalidJsonRecords("record_path traverses a non-object")
    }
    selected = object
      .get(key)
      .unwrap_or_else(() => {
        raise InvalidJsonRecords("Missing record_path key: " + key)
      })
  }
  guard selected is Array(records) else {
    raise InvalidJsonRecords("record_path must select an array")
  }
  let width = spec.fields.length() + 1
  if records.length() > 10000 || (records.length() + 1) * width > 100000 {
    raise InvalidJsonRecords(
      "At most 10000 records and 100000 output cells including headers",
    )
  }
  let rows : Array[Array[@scene.CellValue]] = []
  for index, record in records {
    guard record is Object(_) else {
      raise InvalidJsonRecords("Record \{index + 1} is not an object")
    }
    let row : Array[@scene.CellValue] = [Number((index + 1).to_string())]
    for field in spec.fields {
      let cell = json_record_cell(record, field, index + 1)
      row.push(cell)
    }
    rows.push(row)
  }
  { columns: ["_record_row"] + spec.fields.map(field => field.name), rows, }
}

///|
pub extend JsonRecordNulls with @debug.Debug::{to_repr}

///|
pub extend JsonRecordNulls with Eq::{not_equal, equal}

///|
pub extend JsonRecordField with @debug.Debug::{to_repr}

///|
pub extend JsonRecordField with Eq::{not_equal, equal}

///|
pub extend JsonRecordSpec with @debug.Debug::{to_repr}

///|
pub extend JsonRecordSpec with Eq::{not_equal, equal}

///|
pub extend JsonRecordError with @debug.Debug::{to_repr}

///|
pub extend JsonRecordError with Eq::{not_equal, equal}
