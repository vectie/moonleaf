///|
pub(all) suberror XmlError {
  InvalidXml(offset~ : Int32, message~ : String)
} derive(Debug, Eq)

///|
pub fn XmlError::to_string(self : XmlError) -> String {
  match self {
    InvalidXml(offset~, message~) =>
      "invalid XML at offset \{offset}: \{message}"
  }
}

///|
pub(all) struct Attribute {
  name : String
  value : String
} derive(Debug, Eq)

///|
pub(all) enum Node {
  Element(Element)
  Text(String)
} derive(Debug, Eq)

///|
pub(all) struct Element {
  name : String
  attributes : Array[Attribute]
  children : Array[Node]
} derive(Debug, Eq)

///|
/// Parser resource ceilings. Values must be non-negative.
pub(all) struct ParseOptions {
  max_input_utf16 : Int32
  max_depth : Int32
  max_nodes : Int32
  max_attributes_per_element : Int32
  max_total_decoded_text : Int32
} derive(Debug, Eq)

///|
/// Conservative defaults suitable for untrusted package parts.
pub fn ParseOptions::safe_defaults() -> ParseOptions {
  {
    max_input_utf16: 16 * 1024 * 1024,
    max_depth: 256,
    max_nodes: 1000000,
    max_attributes_per_element: 1024,
    max_total_decoded_text: 16 * 1024 * 1024,
  }
}

///|
fn split_lexical_name(name : String) -> (String, String) {
  match name.find(":") {
    Some(index) =>
      (
        name.unsafe_substring(start=0, end=index),
        name.unsafe_substring(start=index + 1, end=name.length()),
      )
    None => ("", name)
  }
}

///|
pub fn Element::local_name(self : Element) -> String {
  match self.name.find(":") {
    Some(index) =>
      self.name.unsafe_substring(start=index + 1, end=self.name.length())
    None => self.name
  }
}

///|
/// Compatibility lookup by lexical/local name. This does not resolve namespace URIs;
/// URI-aware attribute lookup is not implemented.
pub fn Element::attribute(self : Element, name : String) -> String? {
  for attribute in self.attributes {
    if attribute.name == name || split_lexical_name(attribute.name).1 == name {
      return Some(attribute.value)
    }
  }
  None
}

///|
pub fn Element::child_elements(self : Element) -> Array[Element] {
  let elements = []
  for child in self.children {
    if child is Element(element) {
      elements.push(element)
    }
  }
  elements
}

///|
pub fn Element::children_named(
  self : Element,
  local_name : String,
) -> Array[Element] {
  self.child_elements().filter(element => element.local_name() == local_name)
}

///|
pub fn Element::first_child(self : Element, local_name : String) -> Element? {
  for child in self.child_elements() {
    if child.local_name() == local_name {
      return Some(child)
    }
  }
  None
}

///|
pub fn Element::text_content(self : Element) -> String {
  let output = StringBuilder()
  fn append_node(node : Node, output : StringBuilder) -> Unit {
    match node {
      Text(text) => output.write_string(text)
      Element(element) =>
        for child in element.children {
          append_node(child, output)
        }
    }
  }
  for child in self.children {
    append_node(child, output)
  }
  output.to_string()
}

///|
pub fn escape_text(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
pub fn escape_attribute(text : String) -> String {
  escape_text(text)
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&apos;")
}

///|
pub fn parse(source : String) -> Element raise XmlError {
  parse_with_options(source, ParseOptions::safe_defaults())
}

///|
/// Parse XML with explicit resource ceilings.
pub fn parse_with_options(
  source : String,
  options : ParseOptions,
) -> Element raise XmlError {
  parse_document_with_options(source, options)
}

///|
pub fn serialize(element : Element) -> String {
  serialize_element(element)
}
