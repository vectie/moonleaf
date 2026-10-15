///|
test "batch text edits keep exact coordinates across out-of-order rows" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData>
      #|<row r="5"><c r="C5" t="inlineStr"><is><t>five</t></is></c><c r="A2" t="inlineStr"><is><t>two</t></is></c></row>
      #|<row r="1"><c r="A1" t="inlineStr"><is><t>one</t></is></c></row>
      #|</sheetData></worksheet>
    ),
  )
  let original = @moonleaf.open_session("coordinate-batch.xlsx", bytes)
  let before = review_cells(original)
  let changed = original.set_cells_text("Sheet1", [
    (5, 3, "updated C5"),
    (2, 1, "updated A2"),
  ])
  assert_true(scene_cell_is_text(changed.scene(), 5, 3, "updated C5"))
  assert_true(scene_cell_is_text(changed.scene(), 2, 1, "updated A2"))
  assert_true(review_cells(original) == before)
  let saved = changed.save_as_copy().bytes()
  let reopened = @moonleaf.open_session("coordinate-batch.xlsx", saved)
  assert_true(scene_cell_is_text(reopened.scene(), 5, 3, "updated C5"))
  assert_true(scene_cell_is_text(reopened.scene(), 2, 1, "updated A2"))
  review_unchanged_parts(bytes, saved)
}

///|
test "coordinate edits reject only duplicate targets and preserve the original" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData>
      #|<row r="1"><c r="A1" t="inlineStr"><is><t>one</t></is></c><c r="C1"><v>3</v></c></row>
      #|<row r="1"><c r="A1" t="inlineStr"><is><t>another</t></is></c></row>
      #|</sheetData></worksheet>
    ),
  )
  let original = @moonleaf.open_session("duplicates.xlsx", bytes)
  let original_copy = original.save_as_copy().bytes()
  let before = original.scene()
  try original.set_cell_text("Sheet1", 1, 1, "ambiguous") catch {
    Render(message) =>
      assert_true(message.contains("duplicate target cell: A1"))
    _ => fail("expected a duplicate-target diagnostic")
  } noraise {
    _ => fail("duplicate target must not be edited")
  }
  try @xlsx.set_cell_number(@opc.open(bytes), "Sheet1", 1, 1, 9.0) catch {
    @xlsx.InvalidWorkbook(message) =>
      assert_eq(message, "worksheet has duplicate target cell: A1")
    _ => fail("expected a duplicate-target diagnostic")
  } noraise {
    _ => fail("duplicate numeric target must not be edited")
  }
  assert_true(original.scene() == before)
  assert_eq(original.save_as_copy().bytes(), original_copy)
  assert_eq(original.revision(), 0)
  assert_false(original.is_dirty())
  // A duplicate elsewhere does not make this distinct coordinate ambiguous.
  review_one_edit(bytes, 1, 3)
}

///|
test "missing coordinates in descending layouts do not move implicit neighbors" {
  let fixtures = [
    (
      #|<worksheet><sheetData>
      #|<row r="5"><c r="C5"><v>3</v></c><c><f>C5+1</f><v>4</v></c><c r="A5" t="inlineStr"><is><t>five</t></is></c></row>
      #|<row r="1"><c r="A1" t="inlineStr"><is><t>one</t></is></c><c><f>A5</f><v>5</v></c></row>
      #|<row><c t="inlineStr"><is><t>two</t></is></c></row>
      #|</sheetData></worksheet>
    ),
    (
      #|<worksheet><sheetData>
      #|<row><c r="A5" t="inlineStr"><is><t>five</t></is></c><c t="inlineStr"><is><t>B1</t></is></c></row>
      #|<row><c t="inlineStr"><is><t>two</t></is></c></row>
      #|</sheetData></worksheet>
    ),
  ]
  for xml in fixtures {
    let bytes = review_worksheet(xml)
    let original = @moonleaf.open_session("insert.xlsx", bytes)
    let before = review_cells(original)
    let changed = original
      .set_cell_text("Sheet1", 5, 2, "new B5")
      .set_cell_text("Sheet1", 3, 1, "new A3")
      .set_cell_text("Sheet1", 1, 4, "new D1")
    let copy = changed.save_as_copy()
    let after = review_cells(
      @moonleaf.open_session("insert.xlsx", copy.bytes()),
    )
    assert_eq(after.length(), before.length() + 3)
    for cell in before {
      assert_true(
        after.filter(other => {
          other.row == cell.row && other.column == cell.column
        }) ==
        [cell],
      )
    }
    assert_true(scene_cell_is_text(copy.session().scene(), 5, 2, "new B5"))
    assert_true(scene_cell_is_text(copy.session().scene(), 3, 1, "new A3"))
    assert_true(scene_cell_is_text(copy.session().scene(), 1, 4, "new D1"))
    assert_true(review_cells(original) == before)
    review_unchanged_parts(bytes, copy.bytes())
  }
}

///|
test "numeric edit and recalculation keep explicit cell identities in implicit descending rows" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData>
      #|<row r="4"><c r="C4"><f>A5*2</f><v>999</v></c><c r="A4"><v>4</v></c></row>
      #|<row><c r="A5" s="3"><v>5</v></c></row>
      #|<row r="1"><c r="A1" t="inlineStr"><is><t>one</t></is></c></row>
      #|</sheetData></worksheet>
    ),
  )
  let original = @opc.open(bytes)
  let changed = @xlsx.set_cell_number(original, "Sheet1", 5, 1, 9.0)
  let saved = @opc.save(@xlsx.recalculate(changed))
  let cells = @xlsx.inspect(@opc.open(saved))
  assert_eq(cells.length(), 4)
  assert_true(
    cells.map(cell => (cell.row, cell.column)) ==
    [(4, 3), (4, 1), (5, 1), (1, 1)],
  )
  assert_eq(cells[0].formula, Some("A5*2"))
  assert_eq(cells[0].cached_value, Some("18"))
  assert_eq(cells[2].raw_value, Some("9"))
  assert_eq(cells[2].style_id, Some(3))
  assert_eq(@xlsx.inspect(original)[2].raw_value, Some("5"))
  review_unchanged_parts(bytes, saved)
}
