///|
test "open dispatches a DOCX package by filename" {
  let content = @fzip.zip_sync([
    (
      "[Content_Types].xml",
      @fzip.str_to_u8("<Types xmlns=\"urn:content-types\"/>"),
    ),
    (
      "word/document.xml",
      @fzip.str_to_u8(
        "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>Hello</w:t></w:r></w:p></w:body></w:document>",
      ),
    ),
  ])
  guard @moonleaf.open("NOTES.DOCX", content)
    is @scene.Document::TextDocument(document) else {
    fail("expected a text document")
  }
  guard document.blocks is [@scene.TextBlock::Paragraph([run])] else {
    fail("expected one paragraph")
  }
  assert_eq(run.text, "Hello")
}

///|
test "open rejects unsupported extensions before reading the package" {
  try @moonleaf.open("notes.odt", []) catch {
    @moonleaf.MoonLeafError::UnsupportedExtension("notes.odt") => ()
    _ => fail("expected unsupported extension")
  } noraise {
    _ => fail("expected unsupported extension")
  }
}
