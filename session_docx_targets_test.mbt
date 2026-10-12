///|
test "session targeted DOCX creates one corrected reopened copy and leaves original" {
  let archive = @opc.open(document_session_docx_fixture()).replace_text(
    "word/document.xml", "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>Acme</w:t></w:r><w:r><w:t>Acme</w:t></w:r></w:p></w:body></w:document>",
  )
  let bytes = @opc.save(archive)
  let source = @moonleaf.open_session("proposal.docx", bytes)
  let targets = source.docx_text_targets()
  let edited = source.set_docx_target_text(targets[1].id, "Acme", "Client B")
  assert_eq(edited.revision(), 1)
  assert_true(edited.is_dirty())
  assert_eq(source.revision(), 0)
  assert_eq(source.docx_text_targets()[1].text, "Acme")
  let copy = edited.save_as_copy()
  let reopened = @moonleaf.open_session("client.docx", copy.bytes())
  assert_eq(reopened.docx_text_targets().map(t => t.text), ["Acme", "Client B"])
  assert_eq(@opc.open(bytes), archive)
  for part in archive.parts {
    if part.name != "word/document.xml" {
      assert_eq(@opc.open(copy.bytes()).part(part.name), Some(part))
    }
  }
  let unchanged = edited.set_docx_target_text(
    targets[1].id,
    "Client B",
    "Client B",
  )
  assert_eq(unchanged.revision(), 1)
  assert_true(
    (try? edited.set_docx_target_text(targets[1].id, "Acme", "wrong")) is Err(_),
  )
}

///|
test "targeted DOCX operations are unavailable for other session formats" {
  let session = @moonleaf.open_session(
    "sheet.xlsx",
    document_session_xlsx_fixture(),
  )
  assert_true((try? session.docx_text_targets()) is Err(_))
  assert_true((try? session.set_docx_target_text("x", "y", "z")) is Err(_))
}
