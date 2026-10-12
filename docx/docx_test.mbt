///|
fn package_with(document : String) -> @opc.Package {
  let document_package : @opc.Package = { parts: [], }
  document_package.replace_text("word/document.xml", document)
}

///|
test "read paragraphs, headings, run styles, lists, and tables" {
  let document_package = package_with(
    (
      #|<w:document xmlns:w="urn:w">
      #|  <w:body>
      #|    <w:p>
      #|      <w:pPr><w:pStyle w:val="Heading2"/></w:pPr>
      #|      <w:r><w:rPr><w:b/><w:i/><w:u w:val="single"/><w:sz w:val="28"/><w:color w:val="C00000"/></w:rPr><w:t>Title</w:t></w:r>
      #|    </w:p>
      #|    <w:p><w:r><w:t>Plain text</w:t></w:r></w:p>
      #|    <w:p>
      #|      <w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="7"/></w:numPr></w:pPr>
      #|      <w:r><w:t>Bullet</w:t></w:r>
      #|    </w:p>
      #|    <w:p>
      #|      <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="8"/></w:numPr></w:pPr>
      #|      <w:r><w:t>Numbered</w:t></w:r>
      #|    </w:p>
      #|    <w:tbl><w:tr><w:tc><w:p><w:r><w:t>A1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B1</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
      #|  </w:body>
      #|</w:document>
    ),
  ).replace_text(
    "word/numbering.xml",
    (
      #|<w:numbering xmlns:w="urn:w">
      #|  <w:abstractNum w:abstractNumId="3"><w:lvl w:ilvl="1"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>
      #|  <w:abstractNum w:abstractNumId="4"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>
      #|  <w:num w:numId="7"><w:abstractNumId w:val="3"/></w:num>
      #|  <w:num w:numId="8"><w:abstractNumId w:val="4"/></w:num>
      #|</w:numbering>
    ),
  )
  let document = try @docx.read(document_package) catch {
    error => fail(repr(error))
  } noraise {
    document => document
  }
  debug_inspect(
    document,
    content=(
      #|{
      #|  blocks: [
      #|    Heading(
      #|      2,
      #|      [
      #|        {
      #|          text: "Title",
      #|          style: {
      #|            bold: true,
      #|            italic: true,
      #|            underline: true,
      #|            font_size_half_points: Some(28),
      #|            color: Some("C00000"),
      #|          },
      #|        },
      #|      ],
      #|    ),
      #|    Paragraph(
      #|      [
      #|        {
      #|          text: "Plain text",
      #|          style: {
      #|            bold: false,
      #|            italic: false,
      #|            underline: false,
      #|            font_size_half_points: None,
      #|            color: None,
      #|          },
      #|        },
      #|      ],
      #|    ),
      #|    ListItem(
      #|      level=1,
      #|      ordered=false,
      #|      [
      #|        {
      #|          text: "Bullet",
      #|          style: {
      #|            bold: false,
      #|            italic: false,
      #|            underline: false,
      #|            font_size_half_points: None,
      #|            color: None,
      #|          },
      #|        },
      #|      ],
      #|    ),
      #|    ListItem(
      #|      level=0,
      #|      ordered=true,
      #|      [
      #|        {
      #|          text: "Numbered",
      #|          style: {
      #|            bold: false,
      #|            italic: false,
      #|            underline: false,
      #|            font_size_half_points: None,
      #|            color: None,
      #|          },
      #|        },
      #|      ],
      #|    ),
      #|    Table([["A1", "B1"]]),
      #|  ],
      #|  warnings: [],
      #|}
    ),
  )
}

///|
test "replace_text changes only w:t content and preserves other parts" {
  let document_package = package_with(
    (
      #|<w:document xmlns:w="urn:w" xmlns:a="urn:a"><w:body><w:p><w:r><w:t>Hello Moon</w:t><w:instrText>Hello Moon</w:instrText></w:r></w:p><a:t>Hello Moon</a:t></w:body></w:document>
    ),
  ).replace_text("custom/payload.txt", "Hello Moon")
  let updated = try @docx.replace_text(document_package, "Moon", "Leaf") catch {
    error => fail(repr(error))
  } noraise {
    document_package => document_package
  }
  inspect(updated.text("custom/payload.txt"), content="Hello Moon")
  let updated_xml = updated.text("word/document.xml")
  inspect(
    updated_xml.find("<w:instrText>Hello Moon</w:instrText>") is Some(_),
    content="true",
  )
  inspect(updated_xml.find("<a:t>Hello Moon</a:t>") is Some(_), content="true")
  let document = @docx.read(updated)
  debug_inspect(
    document.blocks,
    content=(
      #|[
      #|  Paragraph(
      #|    [
      #|      {
      #|        text: "Hello Leaf",
      #|        style: {
      #|          bold: false,
      #|          italic: false,
      #|          underline: false,
      #|          font_size_half_points: None,
      #|          color: None,
      #|        },
      #|      },
      #|    ],
      #|  ),
      #|]
    ),
  )
}

///|
test "replace_text edits header and footer paragraphs without crossing parts" {
  let source = package_with(
      (
        #|<w:document xmlns:w="urn:w"><w:body><w:p><w:r><w:t>Body OLD</w:t></w:r></w:p></w:body></w:document>
      ),
    )
    .replace_text(
      "word/header1.xml",
      (
        #|<w:hdr xmlns:w="urn:w"><w:p><w:r><w:t>Header O</w:t></w:r><w:r><w:t>LD</w:t></w:r></w:p></w:hdr>
      ),
    )
    .replace_text(
      "word/footer1.xml",
      (
        #|<w:ftr xmlns:w="urn:w"><w:p><w:r><w:t>Footer OLD</w:t></w:r></w:p></w:ftr>
      ),
    )
    .replace_text("word/styles.xml", "OLD")
  let updated = @docx.replace_text(source, "OLD", "NEW")
  assert_true(updated.text("word/document.xml").contains("Body NEW"))
  assert_true(updated.text("word/header1.xml").contains("Header NEW"))
  assert_true(updated.text("word/footer1.xml").contains("Footer NEW"))
  assert_eq(updated.text("word/styles.xml"), "OLD")
  assert_true(updated.text("word/header1.xml").contains("<w:r>"))
}

///|
test "replace_text preserves inserted edge spaces and XML escaping" {
  let source = package_with(
    "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>OLD</w:t></w:r></w:p></w:body></w:document>",
  )
  let edited = @docx.replace_text(source, "OLD", " A&B ")
  let xml = edited.text("word/document.xml")
  assert_true(
    xml.find("<w:t xml:space=\"preserve\"> A&amp;B </w:t>") is Some(_),
  )
  let document = @docx.read(edited)
  assert_true(document.blocks is [Paragraph([{ text: " A&B ", .. }])])
  let unchanged = @docx.replace_text(source, "missing", "new")
  assert_eq(unchanged, source)
  let default_space = package_with(
    "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t xml:space=\"default\">OLD</w:t></w:r></w:p></w:body></w:document>",
  )
  let preserved = @docx.replace_text(default_space, "OLD", " A ")
  assert_true(
    preserved
    .text("word/document.xml")
    .find("<w:t xml:space=\"preserve\"> A </w:t>")
    is Some(_),
  )
}

///|
test "replace_text spans simple Word runs and keeps untouched run styles" {
  let source = package_with(
    "<w:document xmlns:w=\"urn:w\"><w:body>" +
    "<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>甲旧</w:t></w:r>" +
    "<w:r><w:rPr><w:i/></w:rPr><w:t>公司乙</w:t></w:r>" +
    "<w:r><w:t>旧</w:t></w:r><w:r><w:t>公司</w:t></w:r></w:p>" +
    "<w:p><w:r><w:t>旧</w:t></w:r></w:p>" +
    "<w:p><w:r><w:t>公司</w:t></w:r></w:p>" +
    "</w:body></w:document>",
  )
  let updated = @docx.replace_text(source, "旧公司", "新机构")
  assert_eq(@docx.replace_text(source, "旧公司", "旧公司"), source)
  let xml = updated.text("word/document.xml")
  assert_true(xml.find("<w:b/>") is Some(_))
  assert_true(xml.find("<w:i/>") is Some(_))
  assert_true(xml.find("<w:t>甲新机构</w:t>") is Some(_))
  assert_true(xml.find("<w:t>乙</w:t>") is Some(_))
  assert_true(xml.find("<w:t>新机构</w:t>") is Some(_))
  let document = @docx.read(updated)
  assert_eq(document.blocks.length(), 3)
}

///|
test "replace_text does not cross a Word break or field" {
  let source = package_with(
    "<w:document xmlns:w=\"urn:w\"><w:body><w:p>" +
    "<w:r><w:t>旧</w:t></w:r><w:r><w:br/></w:r>" +
    "<w:r><w:t>公司</w:t></w:r>" +
    "<w:r><w:instrText>旧</w:instrText></w:r>" +
    "</w:p></w:body></w:document>",
  )
  assert_eq(@docx.replace_text(source, "旧公司", "新机构"), source)
}

///|
test "replace_text leaves tracked revisions and field results intact" {
  let source = package_with(
    "<w:document xmlns:w=\"urn:w\"><w:body><w:p>" +
    "<w:ins><w:r><w:t>旧公司</w:t></w:r></w:ins>" +
    "<w:fldSimple w:instr=\"DATE\"><w:r><w:t>旧公司</w:t></w:r></w:fldSimple>" +
    "<w:r><w:t>旧公司</w:t></w:r>" +
    "</w:p></w:body></w:document>",
  )
  let updated = @docx.replace_text(source, "旧公司", "新机构")
  let xml = updated.text("word/document.xml")
  assert_true(
    xml.find("<w:ins><w:r><w:t>旧公司</w:t></w:r></w:ins>") is Some(_),
  )
  assert_true(
    xml.find(
      "<w:fldSimple w:instr=\"DATE\"><w:r><w:t>旧公司</w:t></w:r></w:fldSimple>",
    )
    is Some(_),
  )
  assert_true(xml.find("<w:r><w:t>新机构</w:t></w:r>") is Some(_))
}

///|
test "missing main document reports a DOCX error" {
  let document_package : @opc.Package = { parts: [], }
  try @docx.read(document_package) catch {
    error => debug_inspect(error, content="MissingDocument")
  } noraise {
    _ => fail("expected missing document error")
  }
}

///|
test "Heading1 through Heading6 map to scene heading levels" {
  let document_package = package_with(
    "<w:document xmlns:w=\"urn:w\"><w:body>" +
    "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr></w:p>" +
    "<w:p><w:pPr><w:pStyle w:val=\"Heading2\"/></w:pPr></w:p>" +
    "<w:p><w:pPr><w:pStyle w:val=\"Heading3\"/></w:pPr></w:p>" +
    "<w:p><w:pPr><w:pStyle w:val=\"Heading4\"/></w:pPr></w:p>" +
    "<w:p><w:pPr><w:pStyle w:val=\"Heading5\"/></w:pPr></w:p>" +
    "<w:p><w:pPr><w:pStyle w:val=\"Heading6\"/></w:pPr></w:p>" +
    "</w:body></w:document>",
  )
  let document = @docx.read(document_package)
  assert_true(
    document.blocks
    is [
      Heading(1, _),
      Heading(2, _),
      Heading(3, _),
      Heading(4, _),
      Heading(5, _),
      Heading(6, _),
    ],
  )
}

///|
test "empty replacement search is rejected" {
  let document_package = package_with(
    "<w:document xmlns:w=\"urn:w\"><w:body/></w:document>",
  )
  try @docx.replace_text(document_package, "", "anything") catch {
    error =>
      debug_inspect(
        error,
        content="InvalidReplacement(\"find text must not be empty\")",
      )
  } noraise {
    _ => fail("expected invalid replacement error")
  }
}
