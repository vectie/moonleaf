///|
fn serialize_element(element : Element) -> String {
  let output = StringBuilder()
  write_element(element, output)
  output.to_string()
}

///|
fn write_element(element : Element, output : StringBuilder) -> Unit {
  output.write_string("<")
  output.write_string(element.name)
  for attribute in element.attributes {
    output.write_string(" ")
    output.write_string(attribute.name)
    output.write_string("=\"")
    output.write_string(escape_attribute(attribute.value))
    output.write_string("\"")
  }
  if element.children.length() == 0 {
    output.write_string("/>")
  } else {
    output.write_string(">")
    for child in element.children {
      match child {
        Text(text) => output.write_string(escape_text(text))
        Element(nested) => write_element(nested, output)
      }
    }
    output.write_string("</")
    output.write_string(element.name)
    output.write_string(">")
  }
}
