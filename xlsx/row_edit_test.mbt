///|
test "insert then delete rows restores values, styles and unrelated OPC parts" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Header"), @scene.Text("Amount")],
      [@scene.Text("Alpha"), @scene.Number("12")],
      [@scene.Text("Beta"), @scene.Number("34")],
    ]),
  )
  let source = source
    .replace_text(
      "xl/worksheets/sheet1.xml",
      source
      .text("xl/worksheets/sheet1.xml")
      .replace(old="<sheetData>", new="<dimension ref=\"A1:B3\"/><sheetData>"),
    )
    .replace_text("custom/operator-note.txt", "keep exactly")
  let original_sheet = source.text("xl/worksheets/sheet1.xml")
  let original_styles = source.text("xl/styles.xml")
  let (inserted, count) = @xlsx.insert_sheet_rows(source, "研究证据", 2, 2)
  assert_eq(count, 2)
  assert_eq(source.text("xl/worksheets/sheet1.xml"), original_sheet)
  assert_eq(inserted.text("xl/styles.xml"), original_styles)
  assert_eq(inserted.text("custom/operator-note.txt"), "keep exactly")
  assert_true(
    inserted
    .text("xl/worksheets/sheet1.xml")
    .contains("<dimension ref=\"A1:B5\"/>"),
  )
  let cells = @xlsx.read(inserted).sheets[0].cells
  assert_eq(cells[0].row, 1)
  assert_eq(cells[0].style_id, Some(1))
  assert_eq(cells[2].row, 2)
  assert_eq(cells[2].column, 1)
  assert_eq(cells[2].value, @scene.Empty)
  assert_eq(cells[3].row, 3)
  assert_eq(cells[3].value, @scene.Empty)
  assert_eq(cells[4].row, 4)
  assert_eq(cells[4].value, @scene.Text("Alpha"))
  assert_eq(cells[5].value, @scene.Number("12"))
  assert_eq(cells[6].row, 5)
  assert_eq(cells[6].value, @scene.Text("Beta"))
  let (restored, deleted) = @xlsx.delete_sheet_rows(
    inserted, "研究证据", 2, 2,
  )
  assert_eq(deleted, 2)
  assert_eq(@xlsx.read(restored), @xlsx.read(source))
  assert_eq(restored.text("xl/styles.xml"), original_styles)
  assert_eq(restored.text("custom/operator-note.txt"), "keep exactly")
  assert_true(
    restored
    .text("xl/worksheets/sheet1.xml")
    .contains("<dimension ref=\"A1:B3\"/>"),
  )
}

///|
test "row edits handle sparse sheets and an insertion after the last row" {
  let source = @opc.open(@xlsx.create([])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><dimension ref=\"A1:C5\"/><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Start</t></is></c></row><row r=\"5\"><c r=\"C5\"><v>7</v></c></row></sheetData></worksheet>",
  )
  let (inserted, count) = @xlsx.insert_sheet_rows(source, "研究证据", 3, 1)
  assert_eq(count, 1)
  let cells = @xlsx.read(inserted).sheets[0].cells
  assert_eq(cells[0].row, 1)
  assert_eq(cells[1].row, 3)
  assert_eq(cells[1].value, @scene.Empty)
  assert_eq(cells[2].row, 6)
  assert_eq(cells[2].column, 3)
  assert_eq(cells[2].value, @scene.Number("7"))
  assert_true(
    inserted
    .text("xl/worksheets/sheet1.xml")
    .contains("<dimension ref=\"A1:C6\"/>"),
  )
  let (deleted, removed) = @xlsx.delete_sheet_rows(
    inserted, "研究证据", 2, 3,
  )
  assert_eq(removed, 3)
  let after = @xlsx.read(deleted).sheets[0].cells
  assert_eq(after.length(), 2)
  assert_eq(after[1].row, 3)
  assert_eq(after[1].value, @scene.Number("7"))
  let (appended, appended_count) = @xlsx.insert_sheet_rows(
    source, "研究证据", 8, 1,
  )
  assert_eq(appended_count, 1)
  assert_eq(@xlsx.read(appended).sheets[0].cells[2].row, 8)
}

///|
test "row editing rejects formulas, merged ranges and row overflow" {
  let formula = @opc.open(
    @xlsx.create([
      [@scene.Text("Header")],
      [@scene.Formula(expression="A1", cached=Some("Header"))],
    ]),
  )
  let formulas_rejected = try {
    ignore(@xlsx.insert_sheet_rows(formula, "研究证据", 2, 1))
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(formulas_rejected)
  let merged = @opc.open(@xlsx.create([[@scene.Text("A"), @scene.Text("B")]])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\"/><c r=\"B1\"/></row></sheetData><mergeCells count=\"1\"><mergeCell ref=\"A1:B1\"/></mergeCells></worksheet>",
  )
  let merged_rejected = try {
    ignore(@xlsx.delete_sheet_rows(merged, "研究证据", 1, 1))
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(merged_rejected)
  let at_limit = @opc.open(@xlsx.create([])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1048576\"><c r=\"A1048576\"><v>1</v></c></row></sheetData></worksheet>",
  )
  let overflow = try {
    ignore(@xlsx.insert_sheet_rows(at_limit, "研究证据", 1, 1))
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(overflow)
  let unknown_row_child = @opc.open(@xlsx.create([])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><extLst/></row></sheetData></worksheet>",
  )
  let unknown_rejected = try {
    ignore(@xlsx.insert_sheet_rows(unknown_row_child, "研究证据", 1, 1))
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(unknown_rejected)
}

///|
test "inserting into a sheet without sheetData creates a visible empty row" {
  let source = @opc.open(@xlsx.create([])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><pageMargins left=\"0.7\"/></worksheet>",
  )
  let (inserted, count) = @xlsx.insert_sheet_rows(source, "研究证据", 1, 1)
  assert_eq(count, 1)
  let xml = inserted.text("xl/worksheets/sheet1.xml")
  assert_true(xml.find("<sheetData>") is Some(_))
  assert_true(xml.find("<pageMargins") is Some(_))
  let cells = @xlsx.read(inserted).sheets[0].cells
  assert_eq(cells.length(), 1)
  assert_eq(cells[0].value, @scene.Empty)
}
