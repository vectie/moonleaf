///|
test "root viewer and session explicit policy paths fail closed" {
  let bytes = document_session_docx_fixture()
  let strict = { ..@moonleaf.ArchivePolicy::default(), max_entries: 1 }
  try @moonleaf.open_with_policy("fixture.docx", bytes, strict) catch {
    @moonleaf.MoonLeafError::Package(message) =>
      assert_true(message.contains("max_entries"))
    _ => fail("expected root package-policy failure")
  } noraise {
    _ => fail("expected root open to reject")
  }
  try @moonleaf.open_session_with_policy("fixture.docx", bytes, strict) catch {
    @moonleaf.DocumentSessionError::Package(message) =>
      assert_true(message.contains("max_entries"))
    _ => fail("expected session package-policy failure")
  } noraise {
    _ => fail("expected session open to reject")
  }
}
