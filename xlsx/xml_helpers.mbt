///|
fn parse_part(
  xlsx_package : @opc.Package,
  part_name : String,
) -> @xml.Element raise XlsxError {
  let source = xlsx_package.text(part_name) catch {
    error => raise PackageFailure(part=part_name, message="\{Repr(error)}")
  }
  // Public exchange workbooks can contain a full securities directory whose
  // worksheet XML is larger than the general XML parser's 16 MiB default.
  // Keep the structural limits and bound each XLSX part to 32 MiB.
  @xml.parse_with_options(source, {
    ..@xml.ParseOptions::safe_defaults(),
    max_input_utf16: 32 * 1024 * 1024,
    max_total_decoded_text: 32 * 1024 * 1024,
  }) catch {
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
  limit : Int32,
) -> Int32? {
  match element.attribute(name) {
    Some(value) => parse_decimal(value, limit)
    None => None
  }
}
