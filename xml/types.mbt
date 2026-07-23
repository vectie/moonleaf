///|
pub(all) suberror XmlError {
  InvalidXml(offset~ : Int, message~ : String)
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
pub fn Element::local_name(self : Element) -> String {
  match self.name.rev_find(":") {
    Some(index) =>
      self.name.unsafe_substring(start=index + 1, end=self.name.length())
    None => self.name
  }
}

///|
pub fn Element::attribute(self : Element, name : String) -> String? {
  for attribute in self.attributes {
    if attribute.name == name || attribute.name.has_suffix(":" + name) {
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
  parse_document(source)
}

///|
pub fn serialize(element : Element) -> String {
  serialize_element(element)
}
