///|
fn implicit_rows_fixture() -> FixedArray[Byte] raise {
  let original = @opc.open(document_session_xlsx_fixture())
  let worksheet =
    #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    #|<sheetData>
    #|<row><c t="inlineStr" s="3"><is><t>first</t></is></c><c><f>A1</f><v>1</v></c></row>
    #|<row r="4"><c t="inlineStr"><is><t>fourth</t></is></c><c r="C4"><v>7</v></c><c><f>C4+1</f><v>8</v></c></row>
    #|<row><c t="inlineStr" s="7"><is><t>fifth</t></is></c><c r="C5"><f>C4</f><v>7</v></c></row>
    #|<row><c t="inlineStr"><is><t>sixth</t></is></c></row>
    #|<row r="8"><c r="A8" t="inlineStr"><is><t>eighth</t></is></c></row>
    #|</sheetData></worksheet>
  @opc.save(original.replace_text("xl/worksheets/sheet1.xml", worksheet))
}

///|
fn implicit_rows_cells(
  session : @moonleaf.DocumentSession,
) -> Array[@scene.Cell] raise {
  guard session.scene() is WorkbookDocument({ sheets: [sheet], .. }) else {
    fail("expected one worksheet")
  }
  sheet.cells
}

///|
test "DocumentSession edits an initial implicit row without duplicate coordinates" {
  let bytes = implicit_rows_fixture()
  let original = @moonleaf.open_session("implicit.xlsx", bytes)
  let before = implicit_rows_cells(original)
  let changed = original.set_cell_text("Sheet1", 1, 1, "changed first")
  let copy = changed.save_as_copy()
  let reopened = @moonleaf.open_session("implicit.xlsx", copy.bytes())
  let after = implicit_rows_cells(reopened)
  let expected = before.map(cell => {
    if cell.row == 1 && cell.column == 1 {
      { ..cell, value: @scene.CellValue::Text("changed first"), }
    } else {
      cell
    }
  })
  assert_eq(after.length(), before.length())
  assert_true(after == expected)
  assert_true(implicit_rows_cells(original) == before)
  assert_eq(original.revision(), 0)
  assert_false(original.is_dirty())
  assert_eq(changed.revision(), 1)
  assert_false(copy.session().is_dirty())
}

///|
test "DocumentSession edits implicit rows after an explicit gap without shifting neighbors" {
  let bytes = implicit_rows_fixture()
  let original = @moonleaf.open_session("implicit.xlsx", bytes)
  let before = implicit_rows_cells(original)
  assert_true(before.map(cell => cell.row) == [1, 1, 4, 4, 4, 5, 5, 6, 8])
  let changed = original.set_cell_text("Sheet1", 5, 1, "changed fifth")
  let copy = changed.save_as_copy()
  let reopened = @moonleaf.open_session("implicit.xlsx", copy.bytes())
  let expected = before.map(cell => {
    if cell.row == 5 && cell.column == 1 {
      { ..cell, value: @scene.CellValue::Text("changed fifth"), }
    } else {
      cell
    }
  })
  let after = implicit_rows_cells(reopened)
  assert_eq(after.length(), before.length())
  assert_true(after == expected)
  let source_package = @opc.open(bytes)
  let saved_package = @opc.open(copy.bytes())
  let source_inspection = @xlsx.inspect(source_package)
  let saved_inspection = @xlsx.inspect(saved_package)
  assert_true(
    saved_inspection ==
    source_inspection.map(cell => {
      if cell.row == 5 && cell.column == 1 {
        { ..cell, resolved_text: Some("changed fifth"), }
      } else {
        cell
      }
    }),
  )
  for part in source_package.parts {
    if part.name != "xl/worksheets/sheet1.xml" {
      assert_eq(saved_package.part(part.name).unwrap().content, part.content)
    }
  }
  assert_eq(source_package.parts.length(), saved_package.parts.length())
  try original.set_cell_text("Sheet1", 5, 3, "cannot overwrite formula") catch {
    @moonleaf.DocumentSessionError::FormulaCell(_) => ()
    _ => fail("expected formula-cell refusal")
  } noraise {
    _ => fail("expected formula-cell refusal")
  }
  assert_true(implicit_rows_cells(original) == before)
}

///|
test "DocumentSession fills row and cell gaps without shifting implicit neighbors" {
  let original = @moonleaf.open_session(
    "implicit.xlsx",
    implicit_rows_fixture(),
  )
  let before = implicit_rows_cells(original)
  let changed = original
    .set_cell_text("Sheet1", 2, 1, "new second")
    .set_cell_text("Sheet1", 4, 2, "new B4")
  let copy = changed.save_as_copy()
  let after = implicit_rows_cells(
    @moonleaf.open_session("implicit.xlsx", copy.bytes()),
  )
  assert_eq(after.length(), before.length() + 2)
  for cell in before {
    assert_true(
      after.filter(other => other.row == cell.row && other.column == cell.column) ==
      [cell],
    )
  }
  assert_true(scene_cell_is_text(copy.session().scene(), 2, 1, "new second"))
  assert_true(scene_cell_is_text(copy.session().scene(), 4, 2, "new B4"))
  assert_eq(changed.revision(), 2)
  assert_true(implicit_rows_cells(original) == before)
}
