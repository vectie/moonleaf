///|
fn pdf_offset(value : Int32) -> String {
  let text = value.to_string()
  let output = StringBuilder()
  for _ in 0..<(10 - text.length()) {
    output.write_char('0')
  }
  output.write_string(text)
  output.to_string()
}

///|
test "extracts a simple PDF text stream" {
  let content = "BT /F1 12 Tf 100 700 Td (Revenue up 18 percent) Tj ET"
  let objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Length \{content.length()} >>\nstream\n\{content}\nendstream",
  ]
  let output = StringBuilder()
  output.write_string("%PDF-1.4\n")
  let offsets : Array[Int32] = []
  for index, object in objects {
    offsets.push(output.to_string().length())
    output.write_string("\{index + 1} 0 obj\n\{object}\nendobj\n")
  }
  let xref = output.to_string().length()
  output.write_string("xref\n0 6\n0000000000 65535 f \n")
  for offset in offsets {
    output.write_string("\{pdf_offset(offset)} 00000 n \n")
  }
  output.write_string(
    "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\{xref}\n%%EOF",
  )
  let bytes = @utf8.encode(output.to_string()).to_fixedarray()
  assert_true(@pdf_text.extract(bytes).contains("Revenue up 18 percent"))
}
