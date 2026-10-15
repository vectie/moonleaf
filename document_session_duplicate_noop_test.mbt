///|
test "session rejects identical-value duplicate aliases before same-value no-op" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>same</t></is></c></row><row r="4"><c r="A01" t="inlineStr"><is><t>same</t></is></c></row></sheetData></worksheet>
    ),
  )
  let original = @moonleaf.open_session("same-duplicates.xlsx", bytes)
  let before = original.scene()
  let saved = original.save_as_copy().bytes()
  try original.set_cell_text("Sheet1", 1, 1, "same") catch {
    Render(message) =>
      assert_true(message.contains("duplicate target cell: A1"))
    _ => fail("expected an ambiguous-target diagnostic")
  } noraise {
    _ => fail("identical-value duplicates must not bypass uniqueness")
  }
  assert_true(original.scene() == before)
  assert_eq(original.save_as_copy().bytes(), saved)
  assert_eq(original.revision(), 0)
  assert_false(original.is_dirty())
}

///|
test "session keeps a unique aliased target same-value request clean" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData><row><c r="A01" t="inlineStr"><is><t>same</t></is></c><c r="C1"><f>A1</f><v>2</v></c><c r="C3"><v>3</v></c><c r="C03"><v>4</v></c></row></sheetData></worksheet>
    ),
  )
  let original = @moonleaf.open_session("unique-alias.xlsx", bytes)
  let before = original.scene()
  let saved = original.save_as_copy().bytes()
  let unchanged = original.set_cell_text("Sheet1", 1, 1, "same")
  assert_true(unchanged.scene() == before)
  assert_eq(unchanged.save_as_copy().bytes(), saved)
  assert_eq(unchanged.revision(), 0)
  assert_false(unchanged.is_dirty())
}
