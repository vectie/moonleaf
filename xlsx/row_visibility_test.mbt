///|
test "hide and show rows preserve cells, styles and original package" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Header")],
      [@scene.Text("Alpha")],
      [@scene.Text("Beta")],
    ]),
  ).replace_text("custom/operator-note.txt", "unchanged")
  let original = source.text("xl/worksheets/sheet1.xml")
  let (hidden, changed) = @xlsx.hide_sheet_rows(source, "研究证据", 2, 2)
  assert_eq(changed, 2)
  let saved_hidden = @opc.open(@opc.save(hidden))
  assert_eq(@xlsx.hidden_sheet_rows(saved_hidden, "研究证据"), [2, 3])
  assert_eq(source.text("xl/worksheets/sheet1.xml"), original)
  assert_eq(hidden.text("custom/operator-note.txt"), "unchanged")
  let hidden_xml = hidden.text("xl/worksheets/sheet1.xml")
  assert_true(hidden_xml.contains("hidden=\"1\""))
  assert_eq(
    @xlsx.read(hidden).sheets[0].cells,
    @xlsx.read(source).sheets[0].cells,
  )
  let (same, second_count) = @xlsx.hide_sheet_rows(hidden, "研究证据", 2, 2)
  assert_eq(second_count, 0)
  assert_eq(same.text("xl/worksheets/sheet1.xml"), hidden_xml)
  let (shown, shown_count) = @xlsx.show_sheet_rows(hidden, "研究证据", 2, 2)
  assert_eq(shown_count, 2)
  let saved_shown = @opc.open(@opc.save(shown))
  assert_eq(@xlsx.hidden_sheet_rows(saved_shown, "研究证据"), [])
  assert_true(!shown.text("xl/worksheets/sheet1.xml").contains("hidden=\"1\""))
  assert_eq(
    @xlsx.read(shown).sheets[0].cells,
    @xlsx.read(source).sheets[0].cells,
  )
}

///|
test "hiding sparse rows creates ordered metadata and showing only changes hidden rows" {
  let source = @opc.open(@xlsx.create([])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\"><v>1</v></c></row><row r=\"5\"><c r=\"B5\"><v>5</v></c></row></sheetData></worksheet>",
  )
  let (hidden, changed) = @xlsx.hide_sheet_rows(source, "研究证据", 2, 4)
  assert_eq(changed, 4)
  let xml = hidden.text("xl/worksheets/sheet1.xml")
  assert_eq(@xlsx.hidden_sheet_rows(hidden, "研究证据"), [2, 3, 4, 5])
  assert_true(xml.contains("<row r=\"2\" hidden=\"1\""))
  assert_true(xml.contains("<row r=\"4\" hidden=\"1\""))
  assert_true(xml.contains("<row r=\"5\" hidden=\"1\""))
  let (shown, shown_count) = @xlsx.show_sheet_rows(hidden, "研究证据", 3, 2)
  assert_eq(shown_count, 2)
  assert_eq(@xlsx.hidden_sheet_rows(shown, "研究证据"), [2, 5])
  assert_true(
    shown.text("xl/worksheets/sheet1.xml").contains("<row r=\"2\" hidden=\"1\""),
  )
  assert_eq(
    @xlsx.read(shown).sheets[0].cells,
    @xlsx.read(source).sheets[0].cells,
  )
  let (untouched, no_changes) = @xlsx.show_sheet_rows(
    source, "研究证据", 2, 2,
  )
  assert_eq(no_changes, 0)
  assert_eq(
    untouched.text("xl/worksheets/sheet1.xml"),
    source.text("xl/worksheets/sheet1.xml"),
  )
}

///|
test "row visibility rejects malformed row order and anchored workbook features" {
  let source = @opc.open(@xlsx.create([]))
  let malformed = source.replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"2\"/><row r=\"1\"/></sheetData></worksheet>",
  )
  let order_rejected = try {
    ignore(@xlsx.hide_sheet_rows(malformed, "研究证据", 1, 1))
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(order_rejected)
  let anchored = source.replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/><mergeCells count=\"1\"><mergeCell ref=\"A1:B1\"/></mergeCells></worksheet>",
  )
  let feature_rejected = try {
    ignore(@xlsx.hide_sheet_rows(anchored, "研究证据", 1, 1))
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(feature_rejected)
}

///|
test "row visibility accepts the full 100-row request limit" {
  let source = @opc.open(@xlsx.create([]))
  let (hidden, count) = @xlsx.hide_sheet_rows(source, "研究证据", 2, 100)
  assert_eq(count, 100)
  let rows = @xlsx.hidden_sheet_rows(
    @opc.open(@opc.save(hidden)),
    "研究证据",
  )
  assert_eq(rows.length(), 100)
  assert_eq(rows[0], 2)
  assert_eq(rows[99], 101)
}
