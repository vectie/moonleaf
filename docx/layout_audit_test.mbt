///|
fn audit_package(document : String, pages : Int) -> @opc.Package {
  let archive : @opc.Package = { parts: [] }
  archive
  .replace_text("word/document.xml", document)
  .replace_text(
    "docProps/app.xml",
    "<Properties xmlns=\"urn:props\"><Pages>\{pages}</Pages></Properties>",
  )
  .replace_text("word/styles.xml", "<w:styles xmlns:w=\"urn:w\"/>")
}

///|
test "layout audit accepts text substitution while preserving format" {
  let reference = audit_package(
    "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:pPr><w:spacing w:line=\"560\"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>甲方</w:t></w:r></w:p><w:sectPr><w:pgSz w:w=\"11905\" w:h=\"16840\"/></w:sectPr></w:body></w:document>",
    18,
  )
  let candidate = audit_package(
    "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:pPr><w:spacing w:line=\"560\"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\">月桂算力服务有限公司</w:t></w:r></w:p><w:sectPr><w:pgSz w:w=\"11905\" w:h=\"16840\"/></w:sectPr></w:body></w:document>",
    18,
  )
  let result = @docx.audit_layout_equivalence(reference, candidate)
  assert_true(result.equivalent)
  assert_eq(result.reference_cached_page_count, Some(18))
  assert_eq(result.candidate_cached_page_count, Some(18))
}

///|
test "layout audit rejects geometry and stale page metadata" {
  let reference = audit_package(
    "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:pPr><w:spacing w:line=\"560\"/></w:pPr><w:r><w:t>合同</w:t></w:r></w:p><w:sectPr><w:pgSz w:w=\"11905\" w:h=\"16840\"/></w:sectPr></w:body></w:document>",
    18,
  )
  let candidate = audit_package(
    "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:pPr><w:spacing w:line=\"600\"/></w:pPr><w:r><w:t>合同</w:t></w:r></w:p><w:sectPr><w:pgSz w:w=\"11905\" w:h=\"16840\"/></w:sectPr></w:body></w:document>",
    19,
  )
  let result = @docx.audit_layout_equivalence(reference, candidate)
  assert_false(result.equivalent)
  assert_true(result.diagnostics.contains("MAIN_STRUCTURE_DIFFERS"))
  assert_true(result.diagnostics.contains("PARAGRAPH_LAYOUT_DIFFERS"))
  assert_true(
    result.diagnostics.contains("CACHED_PAGE_COUNT_DIFFERS_OR_MISSING"),
  )
}
