///|
fn validate_query_binding(binding : Json) -> Unit raise XlsxError {
  guard binding
    is {
      "contract": "moonsuite.query-binding.v1",
      "service_id": String(service),
      "query_id": String(query),
      "snapshot_id": String(snapshot),
      ..
    } &&
    service != "" &&
    query != "" &&
    snapshot != "" else {
    raise InvalidWorkbook(
      "Query binding requires contract, service_id, query_id and snapshot_id",
    )
  }
  if binding.stringify().length() > 262144 {
    raise InvalidWorkbook("Query binding metadata exceeds 256 Ki UTF-16 units")
  }
}

///|
fn query_binding_xml(binding : Json) -> String raise XlsxError {
  validate_query_binding(binding)
  let output = StringBuilder()
  output <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/custom-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><property fmtid=\"{D5CDD505-2E9C-101B-9397-08002B2CF9AE}\" pid=\"2\" name=\"MoonSuite.QueryBinding\"><vt:lpwstr>"
  write_created_xml_text(output, binding.stringify())
  output <+ "</vt:lpwstr></property></Properties>"
  output.to_string()
}

///|
/// Read a portable MoonSuite query/snapshot binding from XLSX custom properties.
/// This metadata does not execute queries, refresh the file or alter cells.
pub fn read_query_binding(archive : @opc.Package) -> Json? raise XlsxError {
  if !archive.has_part("docProps/custom.xml") {
    return None
  }
  let properties = parse_part(archive, "docProps/custom.xml")
  for property in properties.children_named("property") {
    if property.attribute("name") == Some("MoonSuite.QueryBinding") {
      let value = @json.parse(property.text_content()) catch {
        _ =>
          raise InvalidWorkbook(
            "Stored MoonSuite query binding is not valid JSON",
          )
      }
      validate_query_binding(value)
      return Some(value)
    }
  }
  None
}
