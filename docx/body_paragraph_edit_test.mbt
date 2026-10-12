///|
test "body paragraph edit targets one paragraph and retains formatting" {
  let source : @opc.Package = { parts: [], }
  let source = source
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>重复</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>表格</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>旧</w:t></w:r><w:r><w:t>公司</w:t></w:r></w:p><w:p><w:r><w:t>重复</w:t></w:r></w:p></w:body></w:document>",
    )
    .replace_text("custom/untouched.txt", "keep")
  let result = @docx.replace_body_paragraph(
    source, 1, "旧公司", " 新 & 名称 ",
  )
  let xml = result.text("word/document.xml")
  assert_true(xml.contains("<w:pStyle w:val=\"Heading1\"/>"))
  assert_true(
    xml.contains(
      "<w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\"> 新 &amp; 名称 </w:t>",
    ),
  )
  assert_true(xml.contains("<w:t>表格</w:t>"))
  assert_eq(xml.split("<w:t>重复</w:t>").length(), 3)
  assert_eq(result.text("custom/untouched.txt"), "keep")
  assert_eq(source.text("word/document.xml").contains("旧</w:t>"), true)
}

///|
test "body paragraph edit rejects stale text, unsafe runs and invalid index" {
  let source : @opc.Package = { parts: [], }
  let source = source.replace_text(
    "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>正文</w:t></w:r></w:p><w:p><w:hyperlink><w:r><w:t>链接</w:t></w:r></w:hyperlink></w:p></w:body></w:document>",
  )
  let mut rejected = 0
  try @docx.replace_body_paragraph(source, 0, "过期", "新") catch {
    _ => rejected += 1
  } noraise {
    _ => ()
  }
  try @docx.replace_body_paragraph(source, 1, "链接", "新") catch {
    _ => rejected += 1
  } noraise {
    _ => ()
  }
  try @docx.replace_body_paragraph(source, 2, "", "新") catch {
    _ => rejected += 1
  } noraise {
    _ => ()
  }
  try @docx.replace_body_paragraph(source, 0, "正文", "带\n换行") catch {
    _ => rejected += 1
  } noraise {
    _ => ()
  }
  assert_eq(rejected, 4)
  assert_eq(@docx.replace_body_paragraph(source, 0, "正文", "正文"), source)
}
