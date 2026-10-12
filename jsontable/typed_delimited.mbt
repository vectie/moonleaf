///|
pub(all) suberror TypedDelimitedError {
  InvalidDelimitedSchema(String)
  InvalidTypedDelimited(String)
  DelimitedConversion(row~ : Int, column~ : String, reason~ : String)
} derive(Debug, Eq)

///|
priv enum DelimitedKind {
  TextKind
  NumberKind
  BooleanKind(String, String)
}

///|
priv struct DelimitedField {
  source : String
  name : String
  kind : DelimitedKind
  trim : Bool
  nulls : Array[String]
}

///|
/// An explicit reusable projection and typing recipe. No types are inferred.
pub struct DelimitedSchema {
  priv fields : Array[DelimitedField]
}

///|
fn schema_fields(
  value : Json,
  names : Array[String],
) -> Map[String, Json] raise TypedDelimitedError {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    names.all(name => fields.contains(name)) else {
    raise InvalidDelimitedSchema(
      "Expected exactly these fields: " + names.join(", "),
    )
  }
  fields
}

///|
fn schema_string(
  fields : Map[String, Json],
  key : String,
) -> String raise TypedDelimitedError {
  guard fields.get(key) is Some(String(value)) && value.length() <= 4096 else {
    raise InvalidDelimitedSchema(
      "Expected string of at most 4096 units: " + key,
    )
  }
  value
}

///|
/// Parse a version-1 JSON schema with ordered columns. Null markers and Boolean
/// spellings are explicit, case-sensitive strings; trim means ASCII whitespace.
pub fn parse_delimited_schema(
  text : String,
) -> DelimitedSchema raise TypedDelimitedError {
  if text.length() > 65536 {
    raise InvalidDelimitedSchema("Schema exceeds 65536 UTF-16 units")
  }
  let json = @json.parse(text) catch {
    _ => raise InvalidDelimitedSchema("Invalid schema JSON")
  }
  let root = schema_fields(json, ["version", "columns"])
  guard root.get("version") == Some(Json::number(1)) &&
    root.get("columns") is Some(Array(columns)) &&
    !columns.is_empty() &&
    columns.length() <= 128 else {
    raise InvalidDelimitedSchema("Expected version 1 and 1–128 columns")
  }
  let names : Array[String] = []
  let fields : Array[DelimitedField] = []
  for column in columns {
    let entry = schema_fields(column, [
      "source", "name", "kind", "trim", "nulls",
    ])
    let source = schema_string(entry, "source")
    let name = schema_string(entry, "name")
    guard source != "" && name != "" && !names.contains(name) else {
      raise InvalidDelimitedSchema(
        "Source/output names must be nonempty; output names must be unique",
      )
    }
    names.push(name)
    let trim = match entry["trim"] {
      True => true
      False => false
      _ => raise InvalidDelimitedSchema("trim must be a Boolean")
    }
    guard entry["nulls"] is Array(null_values) && null_values.length() <= 16 else {
      raise InvalidDelimitedSchema(
        "nulls must contain at most 16 exact strings",
      )
    }
    let nulls : Array[String] = []
    for marker in null_values {
      guard marker is String(value) &&
        value.length() <= 4096 &&
        !nulls.contains(value) else {
        raise InvalidDelimitedSchema(
          "Null markers must be distinct strings of at most 4096 units",
        )
      }
      if trim && value != value.trim(chars=" \t\r\n").to_owned() {
        raise InvalidDelimitedSchema(
          "Null markers must already be trimmed when trim is true",
        )
      }
      nulls.push(value)
    }
    let kind = match entry["kind"] {
      Object(k) if k.get("type") == Some(Json::string("text")) => {
        ignore(schema_fields(entry["kind"], ["type"]))
        TextKind
      }
      Object(k) if k.get("type") == Some(Json::string("number")) => {
        ignore(schema_fields(entry["kind"], ["type"]))
        NumberKind
      }
      Object(k) if k.get("type") == Some(Json::string("boolean")) => {
        let k = schema_fields(entry["kind"], ["type", "true", "false"])
        let yes = schema_string(k, "true")
        let no = schema_string(k, "false")
        if yes == "" ||
          no == "" ||
          yes == no ||
          nulls.contains(yes) ||
          nulls.contains(no) {
          raise InvalidDelimitedSchema(
            "Boolean tokens must be distinct, nonempty and not null markers",
          )
        }
        if trim &&
          (
            yes != yes.trim(chars=" \t\r\n").to_owned() ||
            no != no.trim(chars=" \t\r\n").to_owned()
          ) {
          raise InvalidDelimitedSchema(
            "Boolean tokens must already be trimmed when trim is true",
          )
        }
        BooleanKind(yes, no)
      }
      _ =>
        raise InvalidDelimitedSchema(
          "kind must explicitly select text, number or boolean",
        )
    }
    fields.push({ source, name, kind, trim, nulls, })
  }
  { fields, }
}

///|
fn convert_delimited_cell(
  original : String,
  field : DelimitedField,
  row : Int,
) -> @scene.CellValue raise TypedDelimitedError {
  let text = if field.trim {
    original.trim(chars=" \t\r\n").to_owned()
  } else {
    original
  }
  if field.nulls.contains(text) {
    return @scene.Empty
  }
  match field.kind {
    TextKind => @scene.Text(text)
    BooleanKind(yes, no) =>
      if text == yes {
        @scene.Boolean(true)
      } else if text == no {
        @scene.Boolean(false)
      } else {
        raise DelimitedConversion(
          row~,
          column=field.source,
          reason="Expected an exact configured Boolean token",
        )
      }
    NumberKind => {
      // JSON parsing permits surrounding whitespace; require exact numeric text
      // unless the caller explicitly enabled ASCII trimming.
      if text == "" || text != text.trim(chars=" \t\r\n").to_owned() {
        raise DelimitedConversion(
          row~,
          column=field.source,
          reason="Expected finite JSON-number text without surrounding whitespace",
        )
      }
      let value = @json.parse(text) catch {
        _ =>
          raise DelimitedConversion(
            row~,
            column=field.source,
            reason="Expected finite JSON-number text",
          )
      }
      guard value is Number(number, ..) && !number.is_nan() && !number.is_inf() else {
        raise DelimitedConversion(
          row~,
          column=field.source,
          reason="Expected finite JSON-number text",
        )
      }
      @scene.Number(text)
    }
  }
}

///|
/// Import CSV/TSV with an explicit schema into a fresh typed Table. Schema order
/// determines output order; unselected input columns are dropped. All rows must
/// convert successfully, including the final row. No source content is changed.
pub fn parse_typed_delimited(
  text : String,
  schema : DelimitedSchema,
  delimiter? : Char = ',',
) -> Table raise TypedDelimitedError {
  let source = parse_delimited(text, delimiter~) catch {
    error => raise InvalidTypedDelimited("\{Repr(error)}")
  }
  let indices = schema.fields.map(field => {
    lookup_column(source, field.source) catch {
      _ =>
        raise InvalidDelimitedSchema("Missing source column: " + field.source)
    }
  })
  if (source.rows.length() + 1) * schema.fields.length() > 100000 {
    raise InvalidTypedDelimited("Output exceeds 100000 cells including header")
  }
  let rows : Array[Array[@scene.CellValue]] = []
  let mut units = schema.fields.fold(init=0, (total, field) => {
    total + field.name.length()
  })
  for i, row in source.rows {
    let output : Array[@scene.CellValue] = []
    for j, field in schema.fields {
      guard row[indices[j]] is Text(value) else {
        raise InvalidTypedDelimited("Expected text from the delimited parser")
      }
      let converted = convert_delimited_cell(value, field, i + 1)
      units += match converted {
        Text(text) | Number(text) => text.length()
        Boolean(true) => 4
        Boolean(false) => 5
        _ => 0
      }
      if units > 4_000_000 {
        raise InvalidTypedDelimited("Output exceeds 4000000 UTF-16 units")
      }
      output.push(converted)
    }
    rows.push(output)
  }
  { columns: schema.fields.map(field => field.name), rows, }
}
