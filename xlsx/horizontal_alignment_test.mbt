///|
test "horizontal alignment preserves wrapping, fonts, values and formulas" {
  let source = @opc.open(
    @xlsx.create([
      [Text("Header"), Text("Other")],
      [Formula(expression="A1", cached=Some("Header")), Number("12")],
    ]),
  )
  let (wrapped, wrapped_count) = @xlsx.set_wrap_text_range(
    source, "研究证据", 1, 1, 1, 1, true,
  )
  assert_eq(wrapped_count, 1)
  let (centered, count) = @xlsx.set_horizontal_alignment_range(
    wrapped,
    "研究证据",
    1,
    1,
    2,
    1,
    Center,
  )
  assert_eq(count, 2)
  assert_eq(@xlsx.horizontal_alignment_cells(centered, "研究证据"), [
    (1, 1, "center"),
    (2, 1, "center"),
  ])
  assert_eq(@xlsx.wrapped_cells(centered, "研究证据"), [(1, 1)])
  assert_eq(@xlsx.font_decoration_cells(centered, "研究证据", Bold), [
    (1, 1),
    (1, 2),
  ])
  let cells = @xlsx.read(centered).sheets[0].cells
  assert_eq(cells[0].value, Text("Header"))
  assert_eq(cells[1].value, Text("Other"))
  assert_eq(cells[2].value, Formula(expression="A1", cached=Some("Header")))
  assert_eq(cells[3].value, Number("12"))
  assert_eq(source.text("xl/styles.xml").find("horizontal"), None)
  let (again, unchanged) = @xlsx.set_horizontal_alignment_range(
    centered,
    "研究证据",
    1,
    1,
    2,
    1,
    Center,
  )
  assert_eq(unchanged, 0)
  assert_eq(again.text("xl/styles.xml"), centered.text("xl/styles.xml"))
  let (right, changed) = @xlsx.set_horizontal_alignment_range(
    centered,
    "研究证据",
    2,
    1,
    2,
    1,
    Right,
  )
  assert_eq(changed, 1)
  assert_eq(@xlsx.horizontal_alignment_cells(right, "研究证据"), [
    (1, 1, "center"),
    (2, 1, "right"),
  ])
  let (left, left_count) = @xlsx.set_horizontal_alignment_range(
    right,
    "研究证据",
    1,
    1,
    1,
    1,
    Left,
  )
  assert_eq(left_count, 1)
  assert_eq(@xlsx.wrapped_cells(left, "研究证据"), [(1, 1)])
  assert_eq(@xlsx.horizontal_alignment_cells(left, "研究证据"), [
    (1, 1, "left"),
    (2, 1, "right"),
  ])
}

///|
test "horizontal alignment creates bounded styled blanks and rejects missing styles" {
  let source = @opc.open(@xlsx.create([[Text("A")]]))
  let (aligned, count) = @xlsx.set_horizontal_alignment_range(
    source,
    "研究证据",
    2,
    2,
    3,
    2,
    Right,
  )
  assert_eq(count, 2)
  assert_eq(@xlsx.horizontal_alignment_cells(aligned, "研究证据"), [
    (2, 2, "right"),
    (3, 2, "right"),
  ])
  assert_eq(@xlsx.read(aligned).sheets[0].cells[1].value, Empty)
  let oversized = try {
    ignore(
      @xlsx.set_horizontal_alignment_range(
        source,
        "研究证据",
        1,
        1,
        100,
        11,
        Left,
      ),
    )
    false
  } catch {
    InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(oversized)
  let no_styles = source.replace_text(
    "xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
  )
  assert_eq(@xlsx.horizontal_alignment_cells(no_styles, "研究证据"), [])
  let unavailable = try {
    ignore(
      @xlsx.set_horizontal_alignment_range(
        no_styles,
        "研究证据",
        1,
        1,
        1,
        1,
        Left,
      ),
    )
    false
  } catch {
    InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(unavailable)
}
