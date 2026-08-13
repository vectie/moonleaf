///|
test "preview_document preserves flow order and resolved DOCX layout metadata" {
  let document_package : @opc.Package = { parts: [] }
  let document_package = document_package
    .replace_text(
      "word/document.xml",
      (
        #|<w:document xmlns:w="urn:w"><w:body>
        #|<w:p><w:pPr><w:pStyle w:val="Centered"/><w:ind w:left="240" w:firstLine="480"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="32"/><w:rFonts w:eastAsia="方正小标宋简体"/></w:rPr><w:t>中文合同标题</w:t><w:br w:type="page"/></w:r></w:p>
        #|<w:tbl><w:tblGrid><w:gridCol w:w="1800"/><w:gridCol w:w="3600"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="1800"/></w:tcPr><w:p><w:r><w:t>甲方</w:t></w:r></w:p></w:tc><w:tc><w:tcPr><w:tcW w:w="3600"/></w:tcPr><w:p><w:r><w:t>青年政策运营方</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        #|<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
        #|</w:body></w:document>
      ),
    )
    .replace_text(
      "word/styles.xml", "<w:styles xmlns:w=\"urn:w\"><w:style w:type=\"paragraph\" w:styleId=\"Centered\"><w:pPr><w:jc w:val=\"center\"/><w:spacing w:after=\"240\"/></w:pPr></w:style></w:styles>",
    )
  let preview = @docx.preview_document(document_package)
  guard preview.blocks
    is [
      FlowParagraph(paragraph),
      FlowPageBreak,
      FlowTable(table),
      FlowSection(section),
    ] else {
    fail("expected paragraph, page break, table and section in source order")
  }
  assert_true(paragraph.metadata.alignment is Some("center"))
  assert_true(paragraph.metadata.left_indent_twips is Some(240))
  assert_true(paragraph.metadata.first_line_twips is Some(480))
  assert_true(paragraph.metadata.spacing_after_twips is Some(240))
  assert_eq(paragraph.runs[0].text, "中文合同标题")
  assert_true(paragraph.runs[0].bold)
  assert_true(paragraph.runs[0].font_size_half_points is Some(32))
  assert_true(paragraph.runs[0].font_east_asia is Some("方正小标宋简体"))
  assert_eq(table.grid_widths_twips, [1800, 3600])
  assert_true(table.rows[0][1].width_twips is Some(3600))
  assert_true(section.page_width_twips is Some(11906))
  assert_true(section.margin_left_twips is Some(1440))
}
