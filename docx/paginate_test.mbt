///|
test "paginator wraps CJK text, respects explicit breaks and splits tables" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:pPr><w:spacing w:line=\"560\" w:lineRule=\"exact\"/></w:pPr><w:r><w:rPr><w:sz w:val=\"32\"/></w:rPr><w:t>这是用于验证分页的中文段落这是用于验证分页的中文段落</w:t></w:r></w:p><w:p><w:r><w:br w:type=\"page\"/></w:r></w:p><w:tbl><w:tblGrid><w:gridCol w:w=\"2000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>第一行</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>第二行</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:sectPr><w:pgSz w:w=\"4000\" w:h=\"3000\"/><w:pgMar w:top=\"200\" w:right=\"200\" w:bottom=\"200\" w:left=\"200\"/></w:sectPr></w:body></w:document>",
    )
    .replace_text("word/styles.xml", "<w:styles xmlns:w=\"urn:w\"/>")
  let paged = @docx.paginate_document(archive, profile={
    ..@docx.PaginationProfile::default(),
    page_safety_twips: 0,
  })
  assert_true(paged.pages.length() >= 2)
  assert_eq(paged.page_width_twips, 4000)
  assert_eq(paged.content_height_twips, 2600)
  assert_true(paged.pages.all(page => !page.blocks.is_empty()))
}

///|
test "paginator ignores a trailing empty Word body sentinel" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>正文</w:t></w:r></w:p><w:p><w:pPr><w:spacing w:line=\"560\" w:lineRule=\"exact\"/></w:pPr></w:p><w:sectPr><w:pgSz w:w=\"4000\" w:h=\"1000\"/><w:pgMar w:top=\"200\" w:right=\"200\" w:bottom=\"200\" w:left=\"200\"/></w:sectPr></w:body></w:document>",
    )
    .replace_text("word/styles.xml", "<w:styles xmlns:w=\"urn:w\"/>")
  let paged = @docx.paginate_document(archive)
  assert_eq(paged.pages.length(), 1)
  assert_eq(paged.pages[0].blocks.length(), 1)
}

///|
test "paginator subtracts table cell insets before wrapping text" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:tbl><w:tblGrid><w:gridCol w:w=\"1900\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"1900\" w:type=\"dxa\"/><w:tcMar><w:left w:w=\"120\" w:type=\"dxa\"/><w:right w:w=\"120\" w:type=\"dxa\"/></w:tcMar></w:tcPr><w:p><w:pPr><w:spacing w:line=\"560\" w:lineRule=\"exact\"/></w:pPr><w:r><w:rPr><w:sz w:val=\"24\"/></w:rPr><w:t>一二三四五六七八</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:sectPr><w:pgSz w:w=\"4000\" w:h=\"1500\"/><w:pgMar w:top=\"200\" w:right=\"200\" w:bottom=\"200\" w:left=\"200\"/></w:sectPr></w:body></w:document>",
    )
    .replace_text("word/styles.xml", "<w:styles xmlns:w=\"urn:w\"/>")
  let paged = @docx.paginate_document(archive)
  assert_eq(paged.pages.length(), 1)
  assert_eq(paged.pages[0].used_height_twips, 1210)
}
