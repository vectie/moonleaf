///|
test "batch text edits preserve CR CRLF and untouched text through verified save reopen" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData><row r="1">
      #|<c r="A1" s="3" t="inlineStr"><is><t>first</t></is></c>
      #|<c r="B1" t="inlineStr"><is><t>second</t></is></c>
      #|<c r="C1" t="inlineStr"><is><t>untouched&#13;tail</t></is></c>
      #|<c r="D1"><f>1+1</f><v>2</v></c>
      #|</row></sheetData></worksheet>
    ),
  )
  let original = @moonleaf.open_session("batch-cr.xlsx", bytes)
  let before = review_cells(original)
  let original_copy = original.save_as_copy().bytes()
  assert_true(scene_cell_is_text(original.scene(), 1, 3, "untouched\rtail"))
  let cr = "before\rafter"
  let crlf = "before\r\nafter; literal &#13; and <&>"
  let changed = original.set_cells_text("Sheet1", [(1, 1, cr), (1, 2, crlf)])
  assert_eq(changed.revision(), 1)
  assert_true(changed.is_dirty())
  let copy = changed.save_as_copy()
  // Literal CR is normalized by standard XML consumers even though MoonLeaf's
  // current parser preserves it, so verified self-reopen alone cannot catch it.
  let worksheet = @opc.open(copy.bytes()).text("xl/worksheets/sheet1.xml")
  assert_false(worksheet.contains("\r"))
  let reopened = @moonleaf.open_session("batch-cr.xlsx", copy.bytes())
  let expected = before.map(cell => {
    if cell.row == 1 && cell.column == 1 {
      { ..cell, value: Text(cr), }
    } else if cell.row == 1 && cell.column == 2 {
      { ..cell, value: Text(crlf), }
    } else {
      cell
    }
  })
  assert_true(review_cells(copy.session()) == expected)
  assert_true(review_cells(reopened) == expected)
  assert_false(copy.session().is_dirty())
  assert_eq(copy.session().revision(), 1)
  assert_true(review_cells(original) == before)
  assert_eq(original.save_as_copy().bytes(), original_copy)
  assert_eq(original.revision(), 0)
  assert_false(original.is_dirty())
  review_unchanged_parts(bytes, copy.bytes())
}
