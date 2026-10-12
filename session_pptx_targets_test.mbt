///|
test "targeted PPTX session saves one corrected copy without source mutation" {
  let archive = @opc.open(document_session_pptx_fixture())
  let source = @moonleaf.open_session("review.pptx", @opc.save(archive))
  let target = source.pptx_text_targets()[0]
  let edited = source.set_pptx_target_text(
    target.id,
    "Hello slide",
    "Client review",
  )
  assert_eq(edited.revision(), 1)
  assert_true(edited.is_dirty())
  assert_eq(source.revision(), 0)
  assert_eq(source.pptx_text_targets()[0].text, "Hello slide")
  let copy = edited.save_as_copy()
  let reopened = @moonleaf.open_session("client.pptx", copy.bytes())
  assert_eq(reopened.pptx_text_targets()[0].text, "Client review")
  for part in archive.parts {
    if part.name != "ppt/slides/slide1.xml" {
      assert_eq(@opc.open(copy.bytes()).part(part.name), Some(part))
    }
  }
  let noop = edited.set_pptx_target_text(
    target.id,
    "Client review",
    "Client review",
  )
  assert_eq(noop.revision(), 1)
  assert_true(noop.is_dirty())
  assert_true(
    (try? edited.set_pptx_target_text(target.id, "Hello slide", "wrong"))
    is Err(_),
  )
}

///|
test "targeted PPTX operations reject other document formats" {
  let session = @moonleaf.open_session(
    "sheet.xlsx",
    document_session_xlsx_fixture(),
  )
  assert_true((try? session.pptx_text_targets()) is Err(_))
  assert_true((try? session.set_pptx_target_text("x", "y", "z")) is Err(_))
}
