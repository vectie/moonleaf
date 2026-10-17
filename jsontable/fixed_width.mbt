///|
pub(all) suberror FixedWidthError {
  InvalidFixedWidthSchema(String)
  InvalidFixedWidth(line~ : Int32, reason~ : String)
} derive(Debug, Eq)

///|
priv struct FixedWidthField {
  name : String
  width : Int32
  trim : Bool
}

///|
pub struct FixedWidthSchema {
  priv fields : Array[FixedWidthField]
  priv skip_lines : Int32
  priv skip_blank : Bool
  priv width : Int32
}

///|
pub(all) struct FixedWidthTable {
  table : Table
  source_lines : Array[Int32]
  skipped_lines : Array[Int32]
} derive(Debug, Eq)

///|
fn fw_fields(
  value : Json,
  names : Array[String],
) -> Map[String, Json] raise FixedWidthError {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    names.all(name => fields.contains(name)) else {
    raise InvalidFixedWidthSchema("Expected exactly: " + names.join(", "))
  }
  fields
}

///|
fn fw_integer(
  value : Json,
  low : Int32,
  high : Int32,
) -> Int32 raise FixedWidthError {
  guard value is Number(number, ..) &&
    number >= low.to_double() &&
    number <= high.to_double() &&
    number == number.to_int().to_double() else {
    raise InvalidFixedWidthSchema("Expected bounded integer")
  }
  number.to_int()
}

///|
/// Parse ordered adjacent ASCII column widths; no delimiter or type inference.
pub fn parse_fixed_width_schema(
  text : String,
) -> FixedWidthSchema raise FixedWidthError {
  if text.length() > 65536 {
    raise InvalidFixedWidthSchema("Schema exceeds 65536 units")
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidFixedWidthSchema("Invalid JSON")
  }
  let root = fw_fields(value, [
    "version", "skip_lines", "blank_lines", "columns",
  ])
  guard root["version"] == Json::number(1) &&
    root["columns"] is Array(columns) &&
    columns.length() > 0 &&
    columns.length() <= 128 else {
    raise InvalidFixedWidthSchema("Expected version 1 and 1–128 columns")
  }
  let skip_lines = fw_integer(root["skip_lines"], 0, 100)
  let skip_blank = match root["blank_lines"] {
    String("skip") => true
    String("reject") => false
    _ => raise InvalidFixedWidthSchema("blank_lines must be skip or reject")
  }
  let fields : Array[FixedWidthField] = []
  let names : Array[String] = []
  let mut width = 0
  for column in columns {
    let entry = fw_fields(column, ["name", "width", "trim"])
    guard entry["name"] is String(name) &&
      name != "" &&
      name.length() <= 256 &&
      !names.contains(name) else {
      raise InvalidFixedWidthSchema(
        "Column names must be unique, nonempty and at most 256 units",
      )
    }
    let field_width = fw_integer(entry["width"], 1, 4096)
    let trim = match entry["trim"] {
      True => true
      False => false
      _ => raise InvalidFixedWidthSchema("trim must be Boolean")
    }
    width += field_width
    if width > 4096 {
      raise InvalidFixedWidthSchema("Total width exceeds 4096 ASCII columns")
    }
    names.push(name)
    fields.push({ name, width: field_width, trim, })
  }
  { fields, skip_lines, skip_blank, width, }
}

///|
/// Import printable ASCII records with exact widths and physical line provenance.
/// LF and CRLF are accepted. Tabs, bare CR, non-ASCII and ragged rows are refused.
pub fn parse_fixed_width(
  text : String,
  schema : FixedWidthSchema,
) -> FixedWidthTable raise FixedWidthError {
  if text.length() > 4_000_000 {
    raise InvalidFixedWidth(line=0, reason="Input exceeds 4000000 units")
  }
  let lines = if text == "" {
    []
  } else {
    text.split("\n").map(line => line.to_owned()).collect()
  }
  let count = if text.has_suffix("\n") {
    lines.length() - 1
  } else {
    lines.length()
  }
  if count < schema.skip_lines {
    raise InvalidFixedWidth(
      line=0,
      reason="Input has fewer lines than skip_lines",
    )
  }
  let rows : Array[Array[@scene.CellValue]] = []
  let source_lines : Array[Int32] = []
  let skipped_lines : Array[Int32] = []
  for i = 0; i < count; i = i + 1 {
    let raw = lines[i]
    let line = if raw.has_suffix("\r") && i < lines.length() - 1 {
      raw[:raw.length() - 1].to_owned()
    } else {
      raw
    }
    for c in line {
      if c < ' ' || c > '~' {
        raise InvalidFixedWidth(
          line=i + 1,
          reason="Only printable ASCII and LF/CRLF line endings are supported",
        )
      }
    }
    if i < schema.skip_lines ||
      (schema.skip_blank && line.trim(chars=" ").is_empty()) {
      skipped_lines.push(i + 1)
      continue
    }
    if line.length() != schema.width {
      raise InvalidFixedWidth(
        line=i + 1,
        reason="Record width differs from schema",
      )
    }
    if (rows.length() + 2) * schema.fields.length() > 100000 {
      raise InvalidFixedWidth(
        line=i + 1,
        reason="Output exceeds 100000 cells including header",
      )
    }
    let row : Array[@scene.CellValue] = []
    let mut start = 0
    for field in schema.fields {
      let value = line[start:start + field.width].to_owned()
      row.push(
        Text(if field.trim { value.trim(chars=" ").to_owned() } else { value }),
      )
      start += field.width
    }
    rows.push(row)
    source_lines.push(i + 1)
  }
  {
    table: { columns: schema.fields.map(field => field.name), rows, },
    source_lines,
    skipped_lines,
  }
}

///|
pub extend FixedWidthError with @debug.Debug::{to_repr}

///|
pub extend FixedWidthError with Eq::{not_equal, equal}

///|
pub extend FixedWidthTable with @debug.Debug::{to_repr}

///|
pub extend FixedWidthTable with Eq::{not_equal, equal}
