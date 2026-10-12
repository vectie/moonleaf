///|
test "insert and delete XLSX columns preserve values, styles and other parts" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Name"), @scene.Text("Value")],
      [@scene.Text("Alpha"), @scene.Number("42")],
    ]),
  )
  let source = source
    .replace_text(
      "xl/worksheets/sheet1.xml",
      source
      .text("xl/worksheets/sheet1.xml")
      .replace(old="<sheetData>", new="<dimension ref=\"A1:B2\"/><sheetData>"),
    )
    .replace_text("custom/operator-note.txt", "keep exactly")
  let original_sheet = source.text("xl/worksheets/sheet1.xml")
  let original_styles = source.text("xl/styles.xml")
  let (inserted, count) = @xlsx.insert_sheet_columns(
    source, "研究证据", 2, 2,
  )
  assert_eq(count, 2)
  assert_eq(source.text("xl/worksheets/sheet1.xml"), original_sheet)
  assert_eq(inserted.text("xl/styles.xml"), original_styles)
  assert_eq(inserted.text("custom/operator-note.txt"), "keep exactly")
  assert_true(
    inserted
    .text("xl/worksheets/sheet1.xml")
    .contains("<dimension ref=\"A1:D2\"/>"),
  )
  let cells = @xlsx.read(inserted).sheets[0].cells
  assert_eq(cells[0].column, 1)
  assert_eq(cells[0].style_id, Some(1))
  assert_eq(cells[1].column, 3)
  assert_eq(cells[1].value, @scene.Empty)
  assert_eq(cells[2].column, 4)
  assert_eq(cells[2].value, @scene.Text("Value"))
  let (restored, deleted) = @xlsx.delete_sheet_columns(
    inserted, "研究证据", 2, 2,
  )
  assert_eq(deleted, 2)
  assert_eq(@xlsx.read(restored), @xlsx.read(source))
  assert_eq(restored.text("xl/styles.xml"), original_styles)
  assert_eq(restored.text("custom/operator-note.txt"), "keep exactly")
}

///|
test "XLSX column edit handles sparse coordinates and absent columns" {
  let source = @opc.open(@xlsx.create([])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><dimension ref=\"A1:D3\"/><sheetData><row r=\"1\"><c r=\"A1\"><v>1</v></c><c r=\"D1\"><v>4</v></c></row><row r=\"3\"><c r=\"C3\"><v>3</v></c></row></sheetData></worksheet>",
  )
  let (inserted, count) = @xlsx.insert_sheet_columns(
    source, "研究证据", 2, 1,
  )
  assert_eq(count, 1)
  let cells = @xlsx.read(inserted).sheets[0].cells
  assert_eq(cells[0].column, 1)
  assert_eq(cells[1].column, 2)
  assert_eq(cells[1].value, @scene.Empty)
  assert_eq(cells[2].column, 5)
  assert_eq(cells[3].column, 2)
  assert_eq(cells[4].column, 4)
  let (unchanged, deleted) = @xlsx.delete_sheet_columns(
    source, "研究证据", 9, 1,
  )
  assert_eq(deleted, 0)
  assert_eq(
    unchanged.text("xl/worksheets/sheet1.xml"),
    source.text("xl/worksheets/sheet1.xml"),
  )
}

///|
test "XLSX column edit rejects formulas, column widths and overflow" {
  let formula = @opc.open(
    @xlsx.create([[@scene.Formula(expression="B1", cached=Some("1"))]]),
  )
  assert_true(
    try {
      ignore(@xlsx.insert_sheet_columns(formula, "研究证据", 1, 1))
      false
    } catch {
      @xlsx.InvalidWorkbook(_) => true
      _ => false
    },
  )
  let widths = @opc.open(@xlsx.create([[@scene.Text("A")]])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cols><col min=\"1\" max=\"2\" width=\"12\" customWidth=\"1\"/></cols><sheetData><row r=\"1\"><c r=\"A1\"/></row></sheetData></worksheet>",
  )
  assert_true(
    try {
      ignore(@xlsx.delete_sheet_columns(widths, "研究证据", 1, 1))
      false
    } catch {
      @xlsx.InvalidWorkbook(_) => true
      _ => false
    },
  )
  let limit = @opc.open(@xlsx.create([])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"XFD1\"><v>1</v></c></row></sheetData></worksheet>",
  )
  assert_true(
    try {
      ignore(@xlsx.insert_sheet_columns(limit, "研究证据", 1, 1))
      false
    } catch {
      @xlsx.InvalidWorkbook(_) => true
      _ => false
    },
  )
}
