///|
test "truncated and invalid font tables fail closed without panics" {
  for n in 0..<64 {
    let bytes = Bytes::make(n, 0)
    try font_face({ family: "test", bytes, }) catch {
      PdfError::InvalidFont(_) => ()
      _ => fail("unexpected error")
    } noraise {
      _ => fail("invalid font accepted")
    }
  }
  let bytes : Bytes = b"\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00"
  try font_face({ family: "test", bytes, }) catch {
    PdfError::InvalidFont(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("truncated table accepted")
  }
}

///|
test "PDF renderer rejects absent and invalid fonts" {
  let p : @opc.Package = { parts: [], }
  try render_docx_pdf(p, [], default_family="Missing") catch {
    PdfError::InvalidFont(_) => ()
    _ => fail("unexpected failure")
  } noraise {
    _ => fail("fontless rendering accepted")
  }
}

///|
test "PDF byte writer emits cross reference and real page tree" {
  let bytes = pdf_bytes([""], 11906, 16838, [])
  assert_true(bytes.has_prefix(b"%PDF-1.7"))
  assert_true(bytes.find(b"/Type /Pages /Count 1") is Some(_))
  assert_true(bytes.find(b"xref\n0 5\n") is Some(_))
  assert_true(bytes.has_suffix(b"%%EOF\n"))
}

///|
test "Chinese numbering preserves configured starting counter" {
  assert_eq(chinese_number(5), "五")
  assert_eq(chinese_number(10), "十")
  assert_eq(chinese_number(21), "二十一")
  let source = "<w:document xmlns:w=\"w\"><w:body><w:p><w:pPr><w:numPr><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>甲</w:t></w:r></w:p><w:p><w:pPr><w:numPr><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>乙</w:t></w:r></w:p></w:body></w:document>"
  let numbering = "<w:numbering xmlns:w=\"w\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"5\"/><w:numFmt w:val=\"chineseCounting\"/><w:lvlText w:val=\"%1、\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
  let p : @opc.Package = {
    parts: [
      {
        name: "word/document.xml",
        content: @utf8.encode(source).to_fixedarray(),
      },
      {
        name: "word/numbering.xml",
        content: @utf8.encode(numbering).to_fixedarray(),
      },
    ],
  }
  let rewritten = numbered_document(p).text("word/document.xml")
  assert_true(rewritten.contains("五、"))
  assert_true(rewritten.contains("六、"))
  assert_eq(p.text("word/document.xml"), source)
}

///|
test "floating table anchors borders and margins survive profile extraction" {
  let source = "<w:document xmlns:w=\"w\"><w:body><w:tbl><w:tblPr><w:tblpPr w:horzAnchor=\"page\" w:vertAnchor=\"text\" w:tblpX=\"1999\" w:tblpY=\"494\"/><w:tblBorders><w:top w:val=\"single\" w:sz=\"4\"/></w:tblBorders><w:tblCellMar><w:left w:w=\"120\"/></w:tblCellMar></w:tblPr></w:tbl></w:body></w:document>"
  let p : @opc.Package = {
    parts: [
      {
        name: "word/document.xml",
        content: @utf8.encode(source).to_fixedarray(),
      },
    ],
  }
  let layout = table_layouts(p)[0]
  assert_eq(layout.x, Some(1999))
  assert_eq(layout.y_offset, 494)
  assert_eq(layout.border, 10)
  assert_eq(layout.left, 120)
}

///|
test "unknown semantic content is rejected before print evidence" {
  let p : @opc.Package = {
    parts: [
      {
        name: "word/document.xml",
        content: @utf8.encode(
          "<w:document xmlns:w=\"w\"><w:body><w:p><w:r><w:drawing/></w:r></w:p></w:body></w:document>",
        ).to_fixedarray(),
      },
    ],
  }
  try validate_profile(p) catch {
    PdfError::Unsupported(_) => ()
    _ => fail("unexpected failure")
  } noraise {
    _ => fail("drawing silently dropped")
  }
}
