///|
test "inspect_document retains valid relationships and reports rejected targets" {
  let container = ({ parts: [] } : @opc.Package)
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\" xmlns:r=\"urn:r\"><w:body><w:p><w:hyperlink r:id=\"rLink\"><w:r><w:t>Moon</w:t></w:r></w:hyperlink></w:p></w:body></w:document>",
    )
    .replace_text(
      "word/_rels/document.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header1.xml\"/><Relationship Id=\"rExternalHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"https://example.com/header.xml\" TargetMode=\"External\"/><Relationship Id=\"rFooter\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"footer1.xml\"/><Relationship Id=\"rLink\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"https://moonbitlang.com\" TargetMode=\"External\"/><Relationship Id=\"rImage\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image1.png\"/><Relationship Id=\"rMissingImage\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/missing.png\"/><Relationship Id=\"rAboveRootImage\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../../image.png\"/></Relationships>",
    )
    .replace_text(
      "word/header1.xml", "<w:hdr xmlns:w=\"urn:w\"><w:p><w:r><w:t>Header</w:t></w:r></w:p></w:hdr>",
    )
    .replace_text(
      "word/footer1.xml", "<w:ftr xmlns:w=\"urn:w\"><w:p><w:r><w:t>Footer</w:t></w:r></w:p></w:ftr>",
    )
    .replace_text("word/media/image1.png", "PNG")
  let before = container.text("word/document.xml")
  let result = @docx.inspect_document(container)
  assert_eq(result.headers.length(), 1)
  assert_eq(result.footers.length(), 1)
  assert_eq(result.resources.length(), 3)
  assert_eq(result.resources[0].relationship_id, "rImage")
  assert_true(result.resources[0].media_part is Some("word/media/image1.png"))
  assert_eq(result.resources[1].relationship_id, "rMissingImage")
  assert_true(result.resources[1].media_part is None)
  assert_eq(result.resources[2].relationship_id, "rAboveRootImage")
  assert_true(result.resources[2].media_part is None)
  assert_true(result.paragraphs[0].runs[0].hyperlink is Some("rLink"))
  assert_true(
    result.warnings.map(fn(w) { w.code }) ==
    [
      "DOCX_EXTERNAL_RELATED_PART", "DOCX_IMAGE_SCENE_UNSUPPORTED", "DOCX_RELATED_PART_MISSING",
      "DOCX_RELATIONSHIP_TARGET_INVALID",
    ],
  )
  assert_eq(container.text("word/document.xml"), before)
}

///|
test "inspect_document reports malformed document relationships" {
  let container = ({ parts: [] } : @opc.Package)
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body/></w:document>",
    )
    .replace_text(
      "word/_rels/document.xml.rels", "<Relationships><Relationship",
    )
  let result = @docx.inspect_document(container)
  assert_true(
    result.warnings.map(fn(w) { w.code }) == ["DOCX_RELATIONSHIPS_INVALID"],
  )
}

///|
test "inspect_document exposes focused document structure metadata" {
  let container = ({ parts: [] } : @opc.Package).replace_text(
    "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:pPr><w:spacing w:before=\"-40\" w:after=\"120\"/><w:ind w:left=\"-240\" w:right=\"bad\" w:firstLine=\"-120\" w:hanging=\"60\"/></w:pPr><w:r><w:t>Indented</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/><w:vMerge w:val=\"restart\"/></w:tcPr><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1080\" w:bottom=\"1440\" w:left=\"1080\"/></w:sectPr></w:body></w:document>",
  )
  let result = @docx.inspect_document(container)
  let metadata = result.paragraphs[0].metadata
  assert_true(metadata.spacing_before_twips is None)
  assert_true(metadata.spacing_after_twips is Some(120))
  assert_true(metadata.left_indent_twips is Some(-240))
  assert_true(metadata.right_indent_twips is None)
  assert_true(metadata.first_line_twips is Some(-120))
  assert_true(metadata.hanging_twips is Some(60))
  assert_eq(result.tables[0].rows[0][0].grid_span, 2)
  assert_true(result.tables[0].rows[0][0].vertical_merge is Some("restart"))
  assert_true(result.tables[0].rows[1][0].vertical_merge is Some("continue"))
  assert_eq(result.sections.length(), 1)
  let section = result.sections[0]
  assert_true(section.page_width_twips is Some(12240))
  assert_true(section.page_height_twips is Some(15840))
  assert_true(section.margin_top_twips is Some(1440))
  assert_true(section.margin_right_twips is Some(1080))
  assert_true(section.margin_bottom_twips is Some(1440))
  assert_true(section.margin_left_twips is Some(1080))
}

///|
test "inspect_document treats an absent relationships part as empty" {
  let container = ({ parts: [] } : @opc.Package).replace_text(
    "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body/></w:document>",
  )
  let result = @docx.inspect_document(container)
  assert_false(
    result.warnings.any(fn(w) { w.code == "DOCX_RELATIONSHIPS_INVALID" }),
  )
}

///|
test "inspect_document ignores relationship type suffix spoofs" {
  let container = ({ parts: [] } : @opc.Package)
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body/></w:document>",
    )
    .replace_text(
      "word/_rels/document.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"h\" Type=\"https://attacker.invalid/header\" Target=\"header1.xml\"/><Relationship Id=\"f\" Type=\"https://attacker.invalid/footer\" Target=\"footer1.xml\"/><Relationship Id=\"i\" Type=\"https://attacker.invalid/image\" Target=\"media/image.png\"/></Relationships>",
    )
  let result = @docx.inspect_document(container)
  assert_eq(result.headers.length(), 0)
  assert_eq(result.footers.length(), 0)
  assert_eq(result.resources.length(), 0)
  assert_eq(result.warnings.length(), 0)
}

///|
test "inspect_document retains an exact external image without scene warning" {
  let container = ({ parts: [] } : @opc.Package)
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body/></w:document>",
    )
    .replace_text(
      "word/_rels/document.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"image\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"https://example.com/image.png\" TargetMode=\"External\"/></Relationships>",
    )
  let result = @docx.inspect_document(container)
  assert_eq(result.resources.length(), 1)
  assert_true(result.resources[0].media_part is None)
  assert_true(result.resources[0].external)
  assert_true(
    result.warnings.map(fn(w) { w.code }) == ["DOCX_EXTERNAL_RELATED_PART"],
  )
}

///|
test "inspect_document validates margins and grid spans" {
  let container = ({ parts: [] } : @opc.Package).replace_text(
    "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:tbl><w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"0\"/></w:tcPr><w:p/></w:tc><w:tc><w:tcPr><w:gridSpan w:val=\"-2\"/></w:tcPr><w:p/></w:tc><w:tc><w:tcPr><w:gridSpan w:val=\"bad\"/></w:tcPr><w:p/></w:tc></w:tr></w:tbl><w:sectPr><w:pgMar w:top=\"-1\" w:right=\"bad\" w:bottom=\"-2\" w:left=\"also-bad\"/></w:sectPr></w:body></w:document>",
  )
  let result = @docx.inspect_document(container)
  let section = result.sections[0]
  assert_true(section.margin_top_twips is Some(-1))
  assert_true(section.margin_right_twips is None)
  assert_true(section.margin_bottom_twips is Some(-2))
  assert_true(section.margin_left_twips is None)
  assert_eq(result.tables[0].rows[0][0].grid_span, 1)
  assert_eq(result.tables[0].rows[0][1].grid_span, 1)
  assert_eq(result.tables[0].rows[0][2].grid_span, 1)
  assert_eq(
    result.warnings
    .filter(fn(w) { w.code == "DOCX_GRID_SPAN_INVALID" })
    .length(),
    3,
  )
}
