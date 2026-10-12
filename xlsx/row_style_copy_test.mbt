///|
test "row style copy preserves destination values and copies effective cell formats" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Name"), @scene.Text("Amount"), @scene.Text("Note")],
      [@scene.Text("Alpha"), @scene.Number("12.5"), @scene.Text("Long")],
      [@scene.Text("Beta"), @scene.Number("34.5"), @scene.Text("Keep")],
    ]),
  ).replace_text("custom/operator-note.txt", "untouched")
  let (bold, _) = @xlsx.set_font_decoration_range(
    source,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.Bold,
    true,
  )
  let (wrapped, _) = @xlsx.set_wrap_text_range(
    bold, "研究证据", 2, 3, 2, 3, true,
  )
  let (aligned, _) = @xlsx.set_horizontal_alignment_range(
    wrapped,
    "研究证据",
    2,
    3,
    2,
    3,
    @xlsx.Right,
  )
  let (number, _) = @xlsx.set_number_format_range(
    aligned,
    "研究证据",
    2,
    2,
    2,
    2,
    @xlsx.FormatNumber,
  )
  let (old_target, _) = @xlsx.set_font_decoration_range(
    number,
    "研究证据",
    3,
    3,
    3,
    3,
    @xlsx.Italic,
    true,
  )
  let original_styles = old_target.text("xl/styles.xml")
  let original_sheet = old_target.text("xl/worksheets/sheet1.xml")
  let original_cells = @xlsx.read(old_target).sheets[0].cells
  let (copied, changed) = @xlsx.copy_sheet_row_styles(
    old_target, "研究证据", 2, 3,
  )
  assert_true(changed > 0)
  assert_eq(old_target.text("xl/worksheets/sheet1.xml"), original_sheet)
  assert_eq(copied.text("xl/styles.xml"), original_styles)
  assert_eq(copied.text("custom/operator-note.txt"), "untouched")
  let cells = @xlsx.read(copied).sheets[0].cells
  assert_eq(cells.length(), original_cells.length())
  for index in 0..<cells.length() {
    assert_eq(cells[index].value, original_cells[index].value)
  }
  assert_eq(cells[3].style_id, cells[6].style_id)
  assert_eq(cells[4].style_id, cells[7].style_id)
  assert_eq(cells[5].style_id, cells[8].style_id)
  assert_true(
    @xlsx.font_decoration_cells(copied, "研究证据", @xlsx.Bold).contains(
      (3, 1),
    ),
  )
  assert_true(@xlsx.wrapped_cells(copied, "研究证据").contains((3, 3)))
  assert_true(
    @xlsx.horizontal_alignment_cells(copied, "研究证据").contains(
      (3, 3, "right"),
    ),
  )
  assert_true(
    @xlsx.number_format_cells(copied, "研究证据").contains((3, 2, "number")),
  )
  assert_true(
    !@xlsx.font_decoration_cells(copied, "研究证据", @xlsx.Italic).contains(
      (3, 3),
    ),
  )
  let bytes = @opc.save(copied)
  let reopened = @opc.open(bytes)
  assert_eq(@xlsx.read(reopened), @xlsx.read(copied))
  let (again, unchanged) = @xlsx.copy_sheet_row_styles(
    copied, "研究证据", 2, 3,
  )
  assert_eq(unchanged, 0)
  assert_eq(
    again.text("xl/worksheets/sheet1.xml"),
    copied.text("xl/worksheets/sheet1.xml"),
  )
}

///|
test "row style copy adds styled blank cells and rejects invalid row requests" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Heading"), @scene.Text("Extra")],
      [@scene.Text("Source")],
      [@scene.Text("Destination")],
    ]),
  )
  let (styled, _) = @xlsx.set_wrap_text_range(
    source, "研究证据", 2, 2, 2, 2, true,
  )
  let (copied, changed) = @xlsx.copy_sheet_row_styles(
    styled, "研究证据", 2, 3,
  )
  assert_eq(changed, 1)
  let cells = @xlsx.read(copied).sheets[0].cells
  assert_true(
    cells.any(cell => {
      cell.row == 3 && cell.column == 2 && cell.value == @scene.Empty
    }),
  )
  assert_true(@xlsx.wrapped_cells(copied, "研究证据").contains((3, 2)))
  let invalid = try {
    ignore(@xlsx.copy_sheet_row_styles(styled, "研究证据", 2, 4))
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(invalid)
}

///|
test "row style copy clears unmatched destination styles and copies row style" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Header"), @scene.Text("Other")],
      [@scene.Text("Source"), @scene.Text("Plain")],
      [@scene.Text("Destination"), @scene.Text("Styled")],
    ]),
  )
  let (styled, _) = @xlsx.set_font_decoration_range(
    source,
    "研究证据",
    3,
    2,
    3,
    2,
    @xlsx.Italic,
    true,
  )
  let with_row_style = styled.replace_text(
    "xl/worksheets/sheet1.xml",
    styled
    .text("xl/worksheets/sheet1.xml")
    .replace(
      old="<row r=\"2\">",
      new="<row r=\"2\" s=\"1\" customFormat=\"1\">",
    )
    .replace(
      old="<c r=\"B2\" t=\"inlineStr\" s=\"0\">",
      new="<c r=\"B2\" t=\"inlineStr\">",
    ),
  )
  let (copied, changed) = @xlsx.copy_sheet_row_styles(
    with_row_style, "研究证据", 2, 3,
  )
  assert_eq(changed, 2)
  let xml = copied.text("xl/worksheets/sheet1.xml")
  assert_true(xml.contains("<row r=\"3\" s=\"1\" customFormat=\"1\">"))
  let cells = @xlsx.read(copied).sheets[0].cells
  assert_eq(cells[5].value, @scene.Text("Styled"))
  assert_eq(cells[5].style_id, None)
  assert_true(
    !@xlsx.font_decoration_cells(copied, "研究证据", @xlsx.Italic).contains(
      (3, 2),
    ),
  )
}
