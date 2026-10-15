///|
test "preview_document preserves flow order and resolved DOCX layout metadata" {
  let document_package : @opc.Package = { parts: [], }
  let document_package = document_package
    .replace_text(
      "word/document.xml",
      (
        #|<w:document xmlns:w="urn:w"><w:body>
        #|<w:p><w:pPr><w:pStyle w:val="Centered"/><w:ind w:left="240" w:firstLine="480"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="32"/><w:rFonts w:eastAsia="方正小标宋简体"/></w:rPr><w:t>中文合同标题</w:t><w:br w:type="page"/></w:r></w:p>
        #|<w:tbl><w:tblGrid><w:gridCol w:w="1800"/><w:gridCol w:w="3600"/></w:tblGrid><w:tr><w:trPr><w:trHeight w:val="781" w:hRule="atLeast"/></w:trPr><w:tc><w:tcPr><w:tcW w:w="1800"/><w:tcMar><w:top w:w="60"/><w:left w:w="120"/><w:bottom w:w="30"/><w:right w:w="120"/></w:tcMar><w:vAlign w:val="center"/></w:tcPr><w:p><w:r><w:t>甲方</w:t></w:r></w:p></w:tc><w:tc><w:tcPr><w:tcW w:w="3600"/><w:gridSpan w:val="2"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="28"/></w:rPr><w:t>青年政策运营方</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
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
  assert_true(table.rows[0].height_twips is Some(781))
  assert_true(table.rows[0].height_rule is Some("atLeast"))
  assert_true(table.rows[0].cells[0].margin_left_twips is Some(120))
  assert_true(table.rows[0].cells[0].vertical_alignment is Some("center"))
  assert_eq(table.rows[0].cells[1].grid_span, 2)
  assert_true(table.rows[0].cells[1].width_twips is Some(3600))
  assert_true(
    table.rows[0].cells[1].paragraphs[0].metadata.alignment is Some("center"),
  )
  assert_true(
    table.rows[0].cells[1].paragraphs[0].runs[0].font_size_half_points
    is Some(28),
  )
  assert_true(section.page_width_twips is Some(11906))
  assert_true(section.margin_left_twips is Some(1440))
}

///|
test "DOCX preview retains bullet and restarted numbered list metadata" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive
    .replace_text(
      "word/document.xml",
      "<w:document xmlns:w=\"urn:w\"><w:body>" +
      "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"5\"/></w:numPr></w:pPr><w:r><w:t>收入</w:t></w:r></w:p>" +
      "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"6\"/></w:numPr></w:pPr><w:r><w:t>第一项</w:t></w:r></w:p>" +
      "<w:p><w:r><w:t>普通段落</w:t></w:r></w:p>" +
      "</w:body></w:document>",
    )
    .replace_text(
      "word/numbering.xml",
      "<w:numbering xmlns:w=\"urn:w\">" +
      "<w:abstractNum w:abstractNumId=\"1\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/></w:lvl></w:abstractNum>" +
      "<w:abstractNum w:abstractNumId=\"2\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1)\"/></w:lvl></w:abstractNum>" +
      "<w:num w:numId=\"5\"><w:abstractNumId w:val=\"1\"/></w:num>" +
      "<w:num w:numId=\"6\"><w:abstractNumId w:val=\"2\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"3\"/></w:lvlOverride></w:num>" +
      "</w:numbering>",
    )
  let preview = @docx.preview_document(archive)
  guard preview.blocks
    is [FlowParagraph(bullet), FlowParagraph(numbered), FlowParagraph(plain)] else {
    fail("expected three paragraphs")
  }
  guard bullet.list is Some(bullet_list) else { fail("missing bullet list") }
  assert_eq(bullet_list.num_id, "5")
  assert_eq(bullet_list.format, "bullet")
  assert_eq(bullet_list.label_template, "•")
  assert_eq(bullet_list.start, 1)
  guard numbered.list is Some(numbered_list) else {
    fail("missing numbered list")
  }
  assert_eq(numbered_list.num_id, "6")
  assert_eq(numbered_list.format, "decimal")
  assert_eq(numbered_list.label_template, "%1)")
  assert_eq(numbered_list.start, 3)
  assert_true(plain.list is None)
}

///|
test "preview keeps a leading page break before its paragraph text" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:pPr><w:rPr><w:sz w:val=\"52\"/></w:rPr></w:pPr></w:p><w:p><w:r><w:br w:type=\"page\"/></w:r><w:r><w:t>文件4</w:t></w:r></w:p></w:body></w:document>",
    )
    .replace_text("word/styles.xml", "<w:styles xmlns:w=\"urn:w\"/>")
  let preview = @docx.preview_document(archive)
  guard preview.blocks
    is [FlowParagraph(spacer), FlowPageBreak, FlowParagraph(heading)] else {
    fail("expected spacer, leading page break, then heading")
  }
  assert_true(spacer.runs[0].font_size_half_points is Some(52))
  assert_eq(spacer.runs[0].text, "")
  assert_eq(heading.runs.map(run => run.text).join(""), "文件4")
}

///|
test "preview retains soft line breaks and tabs within runs" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive.replace_text(
    "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>first</w:t><w:tab/><w:t>column</w:t><w:br/><w:t>second</w:t></w:r></w:p></w:body></w:document>",
  )
  let preview = @docx.preview_document(archive)
  guard preview.blocks is [FlowParagraph(paragraph)] else {
    fail("expected one paragraph with inline breaks")
  }
  assert_eq(
    paragraph.runs.map(run => run.text).join(""),
    "first\tcolumn\nsecond",
  )
}
