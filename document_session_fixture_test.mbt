///|
/// Pure MoonBit OOXML package builder used only by root black-box tests.
fn ooxml_fixture(
  text_parts : Array[(String, String)],
  binary_parts : Array[(String, FixedArray[Byte])],
) -> FixedArray[Byte] {
  let parts : Array[(String, FixedArray[Byte])] = []
  text_parts.each(fn(part) { parts.push((part.0, @fzip.str_to_u8(part.1))) })
  binary_parts.each(fn(part) { parts.push(part) })
  @fzip.zip_sync(parts)
}

///|
/// A minimally realistic DOCX with nested relationships and opaque parts.
fn document_session_docx_fixture() -> FixedArray[Byte] {
  ooxml_fixture(
    [
      (
        "[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"bin\" ContentType=\"application/octet-stream\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>",
      ),
      (
        "_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
      ),
      (
        "word/document.xml", "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>Hello fixture</w:t></w:r></w:p></w:body></w:document>",
      ),
      (
        "word/_rels/document.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rMedia\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image.bin\"/></Relationships>",
      ),
      ("customXml/custom.xml", "<custom><value>preserve me</value></custom>"),
    ],
    [("word/media/image.bin", [0x00, 0xff, 0x80])],
  )
}

///|
/// A worksheet with text, a formula, a merge, custom XML, and binary media.
fn document_session_xlsx_fixture() -> FixedArray[Byte] {
  ooxml_fixture(
    [
      (
        "[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"bin\" ContentType=\"application/octet-stream\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>",
      ),
      (
        "_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>",
      ),
      (
        "xl/workbook.xml", "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
      ),
      (
        "xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
      ),
      (
        "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Hello sheet</t></is></c><c r=\"B1\"><f>1+1</f><v>2</v></c></row><row r=\"2\"><c r=\"A2\" t=\"inlineStr\"><is><t>Merged</t></is></c></row></sheetData><mergeCells count=\"1\"><mergeCell ref=\"A2:B2\"/></mergeCells></worksheet>",
      ),
      (
        "xl/worksheets/_rels/sheet1.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rMedia\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image.bin\"/></Relationships>",
      ),
      (
        "customXml/custom.xml", "<custom><value>spreadsheet custom</value></custom>",
      ),
    ],
    [("xl/media/image.bin", [0x00, 0xff, 0x80])],
  )
}

///|
/// A presentation containing one text slide, custom XML, and binary media.
fn document_session_pptx_fixture() -> FixedArray[Byte] {
  ooxml_fixture(
    [
      (
        "[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"bin\" ContentType=\"application/octet-stream\"/><Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/><Override PartName=\"/ppt/slides/slide1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/></Types>",
      ),
      (
        "_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>",
      ),
      (
        "ppt/presentation.xml", "<p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><p:sldIdLst><p:sldId id=\"256\" r:id=\"rId1\"/></p:sldIdLst><p:sldSz cx=\"12192000\" cy=\"6858000\"/></p:presentation>",
      ),
      (
        "ppt/_rels/presentation.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide1.xml\"/></Relationships>",
      ),
      (
        "ppt/slides/slide1.xml", "<p:sld xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><p:cSld><p:spTree><p:sp><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Hello slide</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>",
      ),
      (
        "ppt/slides/_rels/slide1.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rMedia\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image.bin\"/></Relationships>",
      ),
      (
        "customXml/custom.xml", "<custom><value>presentation custom</value></custom>",
      ),
    ],
    [("ppt/media/image.bin", [0x00, 0xff, 0x80])],
  )
}

///|
test "DocumentSession fixture is a valid DOCX package" {
  guard @moonleaf.open("fixture.docx", document_session_docx_fixture())
    is TextDocument(document) else {
    fail("expected DOCX text scene")
  }
  guard document.blocks is [Paragraph([run])] else {
    fail("expected one paragraph")
  }
  assert_eq(run.text, "Hello fixture")
}

///|
test "DocumentSession fixture is a valid XLSX package" {
  guard @moonleaf.open("fixture.xlsx", document_session_xlsx_fixture())
    is WorkbookDocument(workbook) else {
    fail("expected XLSX workbook scene")
  }
  guard workbook.sheets is [sheet] else { fail("expected one worksheet") }
  assert_eq(sheet.name, "Sheet1")
}

///|
test "DocumentSession fixture is a valid PPTX package" {
  guard @moonleaf.open("fixture.pptx", document_session_pptx_fixture())
    is PresentationDocument(presentation) else {
    fail("expected PPTX presentation scene")
  }
  guard presentation.slides is [slide] else { fail("expected one slide") }
  ignore(slide)
}

///|
test "DocumentSession fixture rejects malformed input" {
  try @moonleaf.open("fixture.docx", [0x50, 0x4b]) catch {
    _ => ()
  } noraise {
    _ => fail("expected malformed package rejection")
  }
}
