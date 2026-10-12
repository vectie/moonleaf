///|
test "wrap selected XLSX cells retains values and distinct original styles" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Title"), @scene.Text("Other")],
      [@scene.Text("长文字\n第二行"), @scene.Number("12")],
    ]),
  )
  let sheet_before = source.text("xl/worksheets/sheet1.xml")
  let (wrapped, count) = @xlsx.set_wrap_text_range(
    source, "研究证据", 1, 1, 2, 1, true,
  )
  assert_eq(count, 2)
  assert_eq(source.text("xl/worksheets/sheet1.xml"), sheet_before)
  let cells = @xlsx.read(wrapped).sheets[0].cells
  assert_eq(cells[0].value, @scene.Text("Title"))
  assert_eq(cells[2].value, @scene.Text("长文字\n第二行"))
  assert_eq(cells[3].value, @scene.Number("12"))
  assert_eq(cells[0].style_id, Some(2))
  assert_eq(cells[1].style_id, Some(1))
  assert_eq(cells[2].style_id, Some(3))
  assert_eq(cells[3].style_id, Some(0))
  let styles = @xml.parse(wrapped.text("xl/styles.xml"))
    .first_child("cellXfs")
    .unwrap()
    .children_named("xf")
  assert_eq(styles.length(), 4)
  assert_eq(styles[0].first_child("alignment"), None)
  assert_eq(styles[1].first_child("alignment"), None)
  assert_eq(
    styles[2].first_child("alignment").unwrap().attribute("wrapText"),
    Some("1"),
  )
  assert_eq(
    styles[3].first_child("alignment").unwrap().attribute("wrapText"),
    Some("1"),
  )
  let (again, unchanged) = @xlsx.set_wrap_text_range(
    wrapped, "研究证据", 1, 1, 2, 1, true,
  )
  assert_eq(unchanged, 0)
  assert_eq(again.text("xl/styles.xml"), wrapped.text("xl/styles.xml"))
  let (unwrapped, reset) = @xlsx.set_wrap_text_range(
    wrapped, "研究证据", 1, 1, 2, 1, false,
  )
  assert_eq(reset, 2)
  let reset_styles = @xml.parse(unwrapped.text("xl/styles.xml"))
    .first_child("cellXfs")
    .unwrap()
    .children_named("xf")
  assert_eq(
    reset_styles[4].first_child("alignment").unwrap().attribute("wrapText"),
    Some("0"),
  )
}

///|
test "wrap range rejects oversized edits and missing styles" {
  let source = @opc.open(@xlsx.create([[@scene.Text("A")]]))
  let too_large = try {
    ignore(
      @xlsx.set_wrap_text_range(source, "研究证据", 1, 1, 100, 11, true),
    )
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(too_large)
  let no_styles = source.replace_text(
    "xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
  )
  let missing = try {
    ignore(
      @xlsx.set_wrap_text_range(no_styles, "研究证据", 1, 1, 1, 1, true),
    )
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(missing)
}

///|
test "wrap creates styled blank cells in existing and missing rows" {
  let source = @opc.open(
    @xlsx.create([[@scene.Text("A"), @scene.Text("B"), @scene.Text("C")]]),
  )
  let (formatted, count) = @xlsx.set_wrap_text_range(
    source, "研究证据", 2, 2, 3, 2, true,
  )
  assert_eq(count, 2)
  let cells = @xlsx.read(formatted).sheets[0].cells
  assert_eq(cells.length(), 5)
  assert_eq(cells[3].row, 2)
  assert_eq(cells[3].column, 2)
  assert_eq(cells[3].value, @scene.Empty)
  assert_eq(cells[4].row, 3)
  assert_eq(cells[4].column, 2)
  assert_eq(@xlsx.wrapped_cells(formatted, "研究证据"), [(2, 2), (3, 2)])
  let (again, unchanged) = @xlsx.set_wrap_text_range(
    formatted, "研究证据", 2, 2, 3, 2, true,
  )
  assert_eq(unchanged, 0)
  assert_eq(
    again.text("xl/worksheets/sheet1.xml"),
    formatted.text("xl/worksheets/sheet1.xml"),
  )
}

///|
test "wrap creates sheetData before trailing worksheet settings" {
  let source = @opc.open(@xlsx.create([])).replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><pageMargins left=\"0.7\"/></worksheet>",
  )
  let (formatted, count) = @xlsx.set_wrap_text_range(
    source, "研究证据", 1, 1, 1, 1, true,
  )
  assert_eq(count, 1)
  let xml = formatted.text("xl/worksheets/sheet1.xml")
  assert_true(xml.find("<sheetData>") is Some(_))
  assert_true(xml.find("<pageMargins") is Some(_))
  assert_eq(@xlsx.wrapped_cells(formatted, "研究证据"), [(1, 1)])
}
