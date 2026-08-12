///|
fn parse_part(
  xlsx_package : @opc.Package,
  part_name : String,
) -> @xml.Element raise XlsxError {
  let source = xlsx_package.text(part_name) catch {
    error => raise PackageFailure(part=part_name, message="\{Repr(error)}")
  }
  @xml.parse(source) catch {
    error => raise InvalidXml(part=part_name, message="\{Repr(error)}")
  }
}

///|
fn descendant_text(element : @xml.Element) -> String {
  let output = StringBuilder()
  fn append_text_nodes(element : @xml.Element, output : StringBuilder) -> Unit {
    for child in element.child_elements() {
      match child.local_name() {
        "t" => output.write_string(child.text_content())
        "r" => append_text_nodes(child, output)
        _ => ()
      }
    }
  }
  append_text_nodes(element, output)
  output.to_string()
}

///|
fn child_text(element : @xml.Element, name : String) -> String? {
  match element.first_child(name) {
    Some(child) => Some(child.text_content())
    None => None
  }
}

///|
fn integer_attribute(
  element : @xml.Element,
  name : String,
  limit : Int,
) -> Int? {
  match element.attribute(name) {
    Some(value) => parse_decimal(value, limit)
    None => None
  }
}
