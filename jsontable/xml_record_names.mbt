///|
fn record_name_start(c : Int32) -> Bool {
  c == 0x5f ||
  (c >= 0x41 && c <= 0x5a) ||
  (c >= 0x61 && c <= 0x7a) ||
  (c >= 0xc0 && c <= 0xd6) ||
  (c >= 0xd8 && c <= 0xf6) ||
  (c >= 0xf8 && c <= 0x2ff) ||
  (c >= 0x370 && c <= 0x37d) ||
  (c >= 0x37f && c <= 0x1fff) ||
  (c >= 0x200c && c <= 0x200d) ||
  (c >= 0x2070 && c <= 0x218f) ||
  (c >= 0x2c00 && c <= 0x2fef) ||
  (c >= 0x3001 && c <= 0xd7ff) ||
  (c >= 0xf900 && c <= 0xfdcf) ||
  (c >= 0xfdf0 && c <= 0xfffd) ||
  (c >= 0x10000 && c <= 0xeffff)
}

///|
fn record_ncname(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  let mut first = true
  for c in name.iter() {
    let n = c.to_int()
    if !record_name_start(n) &&
      (
        first ||
        !(n == 0x2d ||
        n == 0x2e ||
        (n >= 0x30 && n <= 0x39) ||
        n == 0xb7 ||
        (n >= 0x300 && n <= 0x36f) ||
        (n >= 0x203f && n <= 0x2040))
      ) {
      return false
    }
    first = false
  }
  true
}

///|
fn xml_selector_valid(name : String) -> Unit raise XmlRecordError {
  if name.length() > 512 {
    raise InvalidXmlSpec("Expanded names exceed 512 UTF-16 units")
  }
  let local_name = if name.has_prefix("{") {
    guard name.find("}") is Some(end) && end > 1 else {
      raise InvalidXmlSpec(
        "Expected {namespace-uri}local or a plain local name",
      )
    }
    let uri = name.unsafe_substring(start=1, end~)
    if !record_namespace_value(uri) {
      raise InvalidXmlSpec("Invalid namespace URI in selector: " + name)
    }
    name.unsafe_substring(start=end + 1, end=name.length())
  } else {
    name
  }
  if !record_ncname(local_name) {
    raise InvalidXmlSpec("Invalid element or attribute selector: " + name)
  }
}

///|
fn record_namespace_value(uri : String) -> Bool {
  !uri.contains_char('}') &&
  !uri.contains_char('{') &&
  !uri.iter().any(c => c == ' ' || c == '\t' || c == '\n' || c == '\r')
}

///|
fn expanded_record_name(
  name : String,
  scope : Map[String, String],
  attribute : Bool,
) -> String raise XmlRecordError {
  let (prefix, local_name) = match name.find(":") {
    Some(index) =>
      (
        name.unsafe_substring(start=0, end=index),
        name.unsafe_substring(start=index + 1, end=name.length()),
      )
    None => ("", name)
  }
  if !record_ncname(local_name) || (prefix != "" && !record_ncname(prefix)) {
    raise InvalidRecordXml("Invalid qualified name: " + name)
  }
  let uri = if prefix == "" && attribute {
    ""
  } else {
    match scope.get(prefix) {
      Some(uri) => uri
      None =>
        if prefix == "" {
          ""
        } else {
          raise InvalidRecordXml("Undeclared namespace prefix: " + prefix)
        }
    }
  }
  if uri == "" {
    local_name
  } else {
    "{" + uri + "}" + local_name
  }
}

///|
fn record_element(
  element : @xml.Element,
  parent_scope : Map[String, String],
) -> RecordElement raise XmlRecordError {
  let scope = parent_scope.copy()
  for attribute in element.attributes {
    let prefix = if attribute.name == "xmlns" {
      Some("")
    } else if attribute.name.has_prefix("xmlns:") {
      Some(
        attribute.name.unsafe_substring(start=6, end=attribute.name.length()),
      )
    } else {
      None
    }
    if prefix is Some(prefix) {
      let uri = attribute.value
      if (prefix != "" && !record_ncname(prefix)) ||
        prefix == "xmlns" ||
        (prefix != "" && uri == "") ||
        (prefix == "xml" && uri != "http://www.w3.org/XML/1998/namespace") ||
        (prefix != "xml" && uri == "http://www.w3.org/XML/1998/namespace") ||
        uri == "http://www.w3.org/2000/xmlns/" ||
        !record_namespace_value(uri) {
        raise InvalidRecordXml(
          "Unsupported or invalid namespace declaration: " + attribute.name,
        )
      }
      scope[prefix] = uri
    }
  }
  let name = expanded_record_name(element.name, scope, false)
  let attributes : Map[String, String] = Map([])
  for attribute in element.attributes {
    if attribute.name != "xmlns" && !attribute.name.has_prefix("xmlns:") {
      let key = expanded_record_name(attribute.name, scope, true)
      if attributes.contains(key) {
        raise InvalidRecordXml("Duplicate expanded attribute: " + key)
      }
      attributes[key] = attribute.value
    }
  }
  let children : Array[RecordElement] = []
  let text = StringBuilder()
  for child in element.children {
    match child {
      Element(child) => children.push(record_element(child, scope))
      Text(value) => text.write_string(value)
    }
  }
  { name, attributes, children, text: text.to_string(), }
}
