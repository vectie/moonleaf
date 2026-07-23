///|
fn package_with(document : String) -> @opc.Package {
  let document_package : @opc.Package = { parts: [] }
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
test "missing main document reports a DOCX error" {
  let document_package : @opc.Package = { parts: [] }
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
