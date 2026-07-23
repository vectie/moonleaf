///|
fn inspect_style_package(document : String, styles : String) -> @opc.Package {
  let document_package : @opc.Package = { parts: [] }
  document_package
  .replace_text("word/document.xml", document)
  .replace_text("word/styles.xml", styles)
}

///|
fn inspect_style_document(paragraph_pr : String, run_pr : String) -> String {
  "<w:document xmlns:w=\"urn:w\"><w:body><w:p>" +
  paragraph_pr +
  "<w:r>" +
  run_pr +
  "<w:t>Styled</w:t></w:r></w:p></w:body></w:document>"
}

///|
test "inspect_document applies docDefaults" {
  let document_package = inspect_style_package(
    inspect_style_document("", ""),
    "<w:styles xmlns:w=\"urn:w\"><w:docDefaults><w:pPrDefault><w:pPr><w:spacing w:before=\"120\"/></w:pPr></w:pPrDefault><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Default Font\"/><w:color w:val=\"112233\"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>",
  )
  let result = @docx.inspect_document(document_package)
  assert_true(result.paragraphs[0].metadata.spacing_before_twips is Some(120))
  assert_true(result.paragraphs[0].runs[0].font_ascii is Some("Default Font"))
  assert_true(result.paragraphs[0].runs[0].color is Some("112233"))
}

///|
test "inspect_document inherits basedOn and direct formatting wins" {
  let document_package = inspect_style_package(
    inspect_style_document(
      "<w:pPr><w:pStyle w:val=\"Child\"/><w:spacing w:before=\"300\"/></w:pPr>",
      "<w:rPr><w:color w:val=\"DIRECT\"/></w:rPr>",
    ),
    "<w:styles xmlns:w=\"urn:w\"><w:style w:type=\"paragraph\" w:styleId=\"Parent\"><w:pPr><w:spacing w:before=\"100\" w:after=\"200\"/></w:pPr><w:rPr><w:color w:val=\"PARENT\"/></w:rPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"Child\"><w:basedOn w:val=\"Parent\"/><w:pPr><w:jc w:val=\"center\"/></w:pPr></w:style></w:styles>",
  )
  let result = @docx.inspect_document(document_package)
  let paragraph = result.paragraphs[0]
  assert_true(paragraph.metadata.alignment is Some("center"))
  assert_true(paragraph.metadata.spacing_before_twips is Some(300))
  assert_true(paragraph.metadata.spacing_after_twips is Some(200))
  assert_true(paragraph.runs[0].color is Some("DIRECT"))
}

///|
test "inspect_document warns for a missing style parent" {
  let document_package = inspect_style_package(
    inspect_style_document("<w:pPr><w:pStyle w:val=\"Orphan\"/></w:pPr>", ""),
    "<w:styles xmlns:w=\"urn:w\"><w:style w:type=\"paragraph\" w:styleId=\"Orphan\"><w:basedOn w:val=\"Absent\"/></w:style></w:styles>",
  )
  let result = @docx.inspect_document(document_package)
  assert_eq(result.warnings[0].code, "DOCX_STYLE_PARENT_MISSING")
  assert_true(result.warnings[0].part is Some("word/styles.xml"))
}

///|
test "inspect_document warns for a basedOn cycle" {
  let document_package = inspect_style_package(
    inspect_style_document("<w:pPr><w:pStyle w:val=\"A\"/></w:pPr>", ""),
    "<w:styles xmlns:w=\"urn:w\"><w:style w:type=\"paragraph\" w:styleId=\"A\"><w:basedOn w:val=\"B\"/></w:style><w:style w:type=\"paragraph\" w:styleId=\"B\"><w:basedOn w:val=\"A\"/></w:style></w:styles>",
  )
  let result = @docx.inspect_document(document_package)
  assert_eq(result.warnings[0].code, "DOCX_STYLE_CYCLE")
  assert_true(result.warnings[0].part is Some("word/styles.xml"))
}

///|
test "paragraph style run properties override docDefaults and direct run wins" {
  let styles = "<w:styles xmlns:w=\"urn:w\"><w:docDefaults><w:rPrDefault><w:rPr><w:color w:val=\"A\"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:styleId=\"ParagraphB\"><w:rPr><w:color w:val=\"B\"/></w:rPr></w:style></w:styles>"
  let inherited = @docx.inspect_document(
    inspect_style_package(
      inspect_style_document(
        "<w:pPr><w:pStyle w:val=\"ParagraphB\"/></w:pPr>", "",
      ),
      styles,
    ),
  )
  assert_true(inherited.paragraphs[0].runs[0].color is Some("B"))
  let direct = @docx.inspect_document(
    inspect_style_package(
      inspect_style_document(
        "<w:pPr><w:pStyle w:val=\"ParagraphB\"/></w:pPr>", "<w:rPr><w:color w:val=\"DIRECT\"/></w:rPr>",
      ),
      styles,
    ),
  )
  assert_true(direct.paragraphs[0].runs[0].color is Some("DIRECT"))
}

///|
test "character style precedence follows the run cascade" {
  let styles = "<w:styles xmlns:w=\"urn:w\"><w:docDefaults><w:rPrDefault><w:rPr><w:color w:val=\"A\"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:styleId=\"ParagraphB\"><w:rPr><w:color w:val=\"B\"/></w:rPr></w:style><w:style w:type=\"character\" w:styleId=\"CharacterC\"><w:rPr><w:color w:val=\"C\"/></w:rPr></w:style><w:style w:type=\"character\" w:styleId=\"CharacterNoColor\"><w:rPr><w:b/></w:rPr></w:style></w:styles>"
  let character = @docx.inspect_document(
    inspect_style_package(
      inspect_style_document(
        "<w:pPr><w:pStyle w:val=\"ParagraphB\"/></w:pPr>", "<w:rPr><w:rStyle w:val=\"CharacterC\"/></w:rPr>",
      ),
      styles,
    ),
  )
  assert_true(character.paragraphs[0].runs[0].color is Some("C"))
  let direct = @docx.inspect_document(
    inspect_style_package(
      inspect_style_document(
        "<w:pPr><w:pStyle w:val=\"ParagraphB\"/></w:pPr>", "<w:rPr><w:rStyle w:val=\"CharacterC\"/><w:color w:val=\"D\"/></w:rPr>",
      ),
      styles,
    ),
  )
  assert_true(direct.paragraphs[0].runs[0].color is Some("D"))
  let omitted = @docx.inspect_document(
    inspect_style_package(
      inspect_style_document(
        "<w:pPr><w:pStyle w:val=\"ParagraphB\"/></w:pPr>", "<w:rPr><w:rStyle w:val=\"CharacterNoColor\"/></w:rPr>",
      ),
      styles,
    ),
  )
  assert_true(omitted.paragraphs[0].runs[0].color is Some("B"))
}

///|
test "inspect_document applies default paragraph style over docDefaults" {
  let document_package = inspect_style_package(
    inspect_style_document("", ""),
    "<w:styles xmlns:w=\"urn:w\"><w:docDefaults><w:pPrDefault><w:pPr><w:spacing w:before=\"120\" w:after=\"80\"/></w:pPr></w:pPrDefault><w:rPrDefault><w:rPr><w:color w:val=\"DEFAULT\"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:styleId=\"Normal\" w:default=\"true\"><w:pPr><w:spacing w:before=\"240\"/></w:pPr><w:rPr><w:color w:val=\"NORMAL\"/></w:rPr></w:style></w:styles>",
  )
  let result = @docx.inspect_document(document_package)
  assert_true(result.paragraphs[0].metadata.spacing_before_twips is Some(240))
  assert_true(result.paragraphs[0].metadata.spacing_after_twips is Some(80))
  assert_true(result.paragraphs[0].runs[0].color is Some("NORMAL"))
}
