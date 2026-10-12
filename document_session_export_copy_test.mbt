///|
test "verified DOCX copy preserves CJK XML text and returns defensive download byte copies" {
  let original = document_session_docx_fixture()
  let session = @moonleaf.open_session("source.docx", original)
  let changed = session.replace_text("Hello fixture", "中文 & <咨询> 🌙")
  let saved = changed.save_as_copy()
  let bytes = saved.bytes()
  let reopened = @moonleaf.open_session("download.docx", bytes)
  assert_eq(reopened.scene(), changed.scene())
  assert_eq(reopened.diagnostics(), saved.session().diagnostics())
  let tampered = saved.bytes()
  tampered[0] = 0
  assert_eq(saved.bytes(), bytes)
  assert_eq(
    @moonleaf.open_session("source.docx", original).scene(),
    session.scene(),
  )
  assert_true((try? @moonleaf.open_session("corrupt.docx", tampered)) is Err(_))
}
