///|
/// A field selects direct children relative to each record, then their leaf text
/// or one attribute. Names are local names or {namespace-uri}local names.
pub(all) struct XmlField {
  name : String
  path : Array[String]
  attribute : String?
  repeated : XmlRepeated
} derive(Debug, Eq)

///|
/// Repeated matches are an error unless a join separator is explicitly supplied.
pub(all) enum XmlRepeated {
  RejectRepeated
  JoinRepeated(String)
} derive(Debug, Eq)

///|
/// The record path starts at the document root. No XPath, wildcards or coercion.
pub(all) struct XmlRecordSpec {
  record_path : Array[String]
  fields : Array[XmlField]
} derive(Debug, Eq)

///|
pub(all) suberror XmlRecordError {
  InvalidXmlSpec(String)
  InvalidRecordXml(String)
  XmlRecordLimit(String)
  RepeatedXmlField(row~ : Int, column~ : String)
  NonLeafXmlField(row~ : Int, column~ : String)
} derive(Debug, Eq)

///|
priv struct RecordElement {
  name : String
  attributes : Map[String, String]
  children : Array[RecordElement]
  text : String
}

///|
fn xml_path_valid(
  path : Array[String],
  allow_empty : Bool,
) -> Unit raise XmlRecordError {
  if (!allow_empty && path.is_empty()) || path.length() > 16 {
    raise InvalidXmlSpec(
      "Paths need 1–16 direct element names; field paths may be empty",
    )
  }
  for name in path {
    xml_selector_valid(name)
  }
}

///|
fn validate_xml_spec(spec : XmlRecordSpec) -> Unit raise XmlRecordError {
  xml_path_valid(spec.record_path, false)
  if spec.fields.is_empty() || spec.fields.length() > 128 {
    raise InvalidXmlSpec("Expected 1–128 fields")
  }
  let seen : Map[String, Bool] = Map([])
  for field in spec.fields {
    if field.name.trim().is_empty() ||
      field.name.length() > 256 ||
      seen.contains(field.name) {
      raise InvalidXmlSpec(
        "Field names must be unique, nonblank and at most 256 UTF-16 units",
      )
    }
    seen[field.name] = true
    xml_path_valid(field.path, true)
    if field.attribute is Some(name) {
      xml_selector_valid(name)
      if name == "xmlns" || name.has_prefix("{http://www.w3.org/2000/xmlns/}") {
        raise InvalidXmlSpec("Namespace declarations are not data attributes")
      }
    }
    if field.repeated is JoinRepeated(separator) && separator.length() > 256 {
      raise InvalidXmlSpec("Join separators are limited to 256 UTF-16 units")
    }
  }
}

///|
fn xml_path_json(value : Json) -> Array[String] raise XmlRecordError {
  guard value is Array(values) else {
    raise InvalidXmlSpec("Expected a path array")
  }
  let path : Array[String] = []
  for value in values {
    guard value is String(name) else {
      raise InvalidXmlSpec("Path entries must be names")
    }
    path.push(name)
  }
  path
}

///|
fn xml_spec_keys(
  value : Json,
  allowed : Array[String],
) -> Unit raise XmlRecordError {
  guard value is Object(object) else {
    raise InvalidXmlSpec("Expected an object")
  }
  for key, _ in object {
    if !allowed.contains(key) {
      raise InvalidXmlSpec("Unknown specification key: " + key)
    }
  }
}

///|
/// Read the same strict JSON mapping used by cmd/xml_records. Unknown keys and
/// unknown repeated policies are rejected rather than silently ignored.
pub fn parse_xml_spec(text : String) -> XmlRecordSpec raise XmlRecordError {
  if text.length() > 65536 {
    raise XmlRecordLimit("Specification exceeds 65536 UTF-16 units")
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidXmlSpec("Invalid JSON mapping")
  }
  xml_spec_keys(value, ["record_path", "fields"])
  guard value is { "record_path": path, "fields": Array(items), .. } else {
    raise InvalidXmlSpec("Mapping requires record_path and fields arrays")
  }
  let fields : Array[XmlField] = []
  for item in items {
    xml_spec_keys(item, ["name", "path", "attribute", "repeated", "separator"])
    guard item is { "name": String(name), "path": field_path, .. } else {
      raise InvalidXmlSpec("Each field needs name and path")
    }
    let attribute = match item {
      { "attribute": String(name), .. } => Some(name)
      { "attribute": _, .. } => raise InvalidXmlSpec("attribute must be a name")
      _ => None
    }
    let repeated = match item {
      { "repeated": String("join"), "separator": String(separator), .. } =>
        JoinRepeated(separator)
      { "repeated": String("join"), .. } =>
        raise InvalidXmlSpec("join requires an explicit separator")
      { "separator": _, .. } =>
        raise InvalidXmlSpec("separator requires repeated=join")
      { "repeated": String("reject"), .. } => RejectRepeated
      { "repeated": _, .. } =>
        raise InvalidXmlSpec("repeated must be reject or join")
      _ => RejectRepeated
    }
    fields.push({ name, path: xml_path_json(field_path), attribute, repeated, })
  }
  let spec = { record_path: xml_path_json(path), fields, }
  validate_xml_spec(spec)
  spec
}

///|
fn xml_walk_path(
  elements : Array[RecordElement],
  path : Array[String],
) -> Array[RecordElement] {
  let mut selected = elements
  for name in path {
    let next : Array[RecordElement] = []
    for element in selected {
      for child in element.children {
        if child.name == name {
          next.push(child)
        }
      }
    }
    selected = next
  }
  selected
}

///|
fn xml_field_cell(
  record : RecordElement,
  field : XmlField,
  row : Int,
) -> @scene.CellValue raise XmlRecordError {
  let selected = xml_walk_path([record], field.path)
  if selected.is_empty() {
    return Empty
  }
  if selected.length() > 1 && field.repeated == RejectRepeated {
    raise RepeatedXmlField(row~, column=field.name)
  }
  let values : Array[String] = []
  let mut present = false
  let mut length = 0
  for element in selected {
    let value = match field.attribute {
      Some(name) => element.attributes.get(name)
      None => {
        if !element.children.is_empty() {
          raise NonLeafXmlField(row~, column=field.name)
        }
        Some(element.text)
      }
    }
    if value is Some(_) {
      present = true
    }
    let text = value.unwrap_or("")
    length += text.length()
    if length > 65536 {
      raise XmlRecordLimit("Field exceeds 65536 UTF-16 units")
    }
    values.push(text)
  }
  if !present {
    return Empty
  }
  let separator = match field.repeated {
    RejectRepeated => ""
    JoinRepeated(separator) => separator
  }
  if length + separator.length() * (values.length() - 1) > 65536 {
    raise XmlRecordLimit("Joined field exceeds 65536 UTF-16 units")
  }
  Text(values.join(separator))
}

///|
/// Import a bounded XML business-record collection as a real Table. All present
/// values remain text (including 001); absent fields are Empty. Parsing never
/// resolves external resources. The root must match the first record-path name.
pub fn parse_xml_records(
  source : String,
  spec : XmlRecordSpec,
) -> Table raise XmlRecordError {
  validate_xml_spec(spec)
  if source.length() > 1_000_000 {
    raise XmlRecordLimit("XML exceeds 1000000 UTF-16 units")
  }
  let normalized = validate_record_xml_source(source)
  let root = @xml.parse_with_options(normalized, {
    max_input_utf16: 1_000_000,
    max_depth: 32,
    max_nodes: 50_000,
    max_attributes_per_element: 64,
    max_total_decoded_text: 1_000_000,
  }) catch {
    error => raise InvalidRecordXml(error.to_string())
  }
  let root = record_element(root, {
    "xml": "http://www.w3.org/XML/1998/namespace",
  })
  if root.name != spec.record_path[0] {
    raise InvalidRecordXml("Root does not match the record path")
  }
  let records = xml_walk_path([root], spec.record_path[1:].to_owned())
  if records.length() > 10_000 ||
    (records.length() + 1) * spec.fields.length() > 100_000 {
    raise XmlRecordLimit(
      "Table exceeds 10000 records or 100000 cells including header",
    )
  }
  let rows : Array[Array[@scene.CellValue]] = []
  let mut text_size = 0
  for field in spec.fields {
    text_size += field.name.length()
  }
  for i, record in records {
    let row : Array[@scene.CellValue] = []
    for field in spec.fields {
      let cell = xml_field_cell(record, field, i + 1)
      if cell is Text(value) {
        text_size += value.length()
      }
      if text_size > 2_000_000 {
        raise XmlRecordLimit("Output text exceeds 2000000 UTF-16 units")
      }
      row.push(cell)
    }
    rows.push(row)
  }
  { columns: spec.fields.map(field => field.name), rows, }
}

///|
pub extend XmlField with @debug.Debug::{to_repr}

///|
pub extend XmlField with Eq::{not_equal, equal}

///|
pub extend XmlRepeated with @debug.Debug::{to_repr}

///|
pub extend XmlRepeated with Eq::{not_equal, equal}

///|
pub extend XmlRecordSpec with @debug.Debug::{to_repr}

///|
pub extend XmlRecordSpec with Eq::{not_equal, equal}

///|
pub extend XmlRecordError with @debug.Debug::{to_repr}

///|
pub extend XmlRecordError with Eq::{not_equal, equal}
