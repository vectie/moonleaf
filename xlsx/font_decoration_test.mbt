///|
test "font decoration preserves original fonts, formulas, and other styles" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Title"), @scene.Text("Plain")],
      [
        @scene.Formula(expression="A1", cached=Some("Title")),
        @scene.Number("42"),
      ],
    ]),
  )
  let original_styles = source.text("xl/styles.xml")
  let (italic, changed) = @xlsx.set_font_decoration_range(
    source,
    "研究证据",
    1,
    1,
    2,
    1,
    @xlsx.Italic,
    true,
  )
  assert_eq(changed, 2)
  assert_eq(source.text("xl/styles.xml"), original_styles)
  assert_eq(@xlsx.font_decoration_cells(italic, "研究证据", @xlsx.Italic), [
    (1, 1),
    (2, 1),
  ])
  assert_eq(
    @xlsx.font_decoration_cells(italic, "研究证据", @xlsx.Underline),
    [],
  )
  let cells = @xlsx.read(italic).sheets[0].cells
  assert_eq(cells[0].value, @scene.Text("Title"))
  assert_eq(cells[1].value, @scene.Text("Plain"))
  assert_eq(
    cells[2].value,
    @scene.Formula(expression="A1", cached=Some("Title")),
  )
  assert_eq(cells[3].value, @scene.Number("42"))
  let styles = @xml.parse(italic.text("xl/styles.xml"))
  let fonts = styles.first_child("fonts").unwrap().children_named("font")
  let xfs = styles.first_child("cellXfs").unwrap().children_named("xf")
  assert_eq(fonts.length(), 4)
  assert_eq(xfs.length(), 4)
  assert_eq(fonts[0].first_child("i"), None)
  assert_eq(fonts[1].first_child("i"), None)
  assert_true(fonts[2].first_child("i") is Some(_))
  assert_true(fonts[3].first_child("i") is Some(_))
  assert_eq(xfs[2].attribute("fontId"), Some("2"))
  assert_eq(xfs[3].attribute("fontId"), Some("3"))
  let (again, unchanged) = @xlsx.set_font_decoration_range(
    italic,
    "研究证据",
    1,
    1,
    2,
    1,
    @xlsx.Italic,
    true,
  )
  assert_eq(unchanged, 0)
  assert_eq(again.text("xl/styles.xml"), italic.text("xl/styles.xml"))
  let (underlined, underlined_count) = @xlsx.set_font_decoration_range(
    italic,
    "研究证据",
    1,
    1,
    1,
    1,
    @xlsx.Underline,
    true,
  )
  assert_eq(underlined_count, 1)
  assert_eq(
    @xlsx.font_decoration_cells(underlined, "研究证据", @xlsx.Underline),
    [(1, 1)],
  )
  assert_eq(
    @xlsx.font_decoration_cells(underlined, "研究证据", @xlsx.Italic),
    [(1, 1), (2, 1)],
  )
  let (not_italic, cleared) = @xlsx.set_font_decoration_range(
    underlined,
    "研究证据",
    1,
    1,
    2,
    1,
    @xlsx.Italic,
    false,
  )
  assert_eq(cleared, 2)
  assert_eq(
    @xlsx.font_decoration_cells(not_italic, "研究证据", @xlsx.Italic),
    [],
  )
  assert_eq(
    @xlsx.font_decoration_cells(not_italic, "研究证据", @xlsx.Underline),
    [(1, 1)],
  )
}

///|
test "font decoration handles blank cells and rejects invalid styles" {
  let source = @opc.open(@xlsx.create([[@scene.Text("A")]]))
  let (formatted, count) = @xlsx.set_font_decoration_range(
    source,
    "研究证据",
    2,
    2,
    3,
    2,
    @xlsx.Underline,
    true,
  )
  assert_eq(count, 2)
  assert_eq(
    @xlsx.font_decoration_cells(formatted, "研究证据", @xlsx.Underline),
    [(2, 2), (3, 2)],
  )
  let cells = @xlsx.read(formatted).sheets[0].cells
  assert_eq(cells.length(), 3)
  assert_eq(cells[1].value, @scene.Empty)
  let (again, unchanged) = @xlsx.set_font_decoration_range(
    formatted,
    "研究证据",
    2,
    2,
    3,
    2,
    @xlsx.Underline,
    true,
  )
  assert_eq(unchanged, 0)
  assert_eq(again.text("xl/styles.xml"), formatted.text("xl/styles.xml"))
  let (cleared, changed) = @xlsx.set_font_decoration_range(
    formatted,
    "研究证据",
    2,
    2,
    3,
    2,
    @xlsx.Underline,
    false,
  )
  assert_eq(changed, 2)
  assert_eq(
    @xlsx.font_decoration_cells(cleared, "研究证据", @xlsx.Underline),
    [],
  )
  let oversized = try {
    ignore(
      @xlsx.set_font_decoration_range(
        source,
        "研究证据",
        1,
        1,
        100,
        11,
        @xlsx.Italic,
        true,
      ),
    )
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(oversized)
  let bad_font = source.replace_text(
    "xl/styles.xml",
    source
    .text("xl/styles.xml")
    .replace(old="fontId=\"1\"", new="fontId=\"999\""),
  )
  let invalid = try {
    ignore(
      @xlsx.set_font_decoration_range(
        bad_font,
        "研究证据",
        1,
        1,
        1,
        1,
        @xlsx.Italic,
        true,
      ),
    )
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(invalid)
}

///|
test "bold changes one cell without dropping italic and underline" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Header"), @scene.Text("Other")],
      [@scene.Text("Evidence"), @scene.Number("8")],
    ]),
  )
  assert_eq(@xlsx.font_decoration_cells(source, "研究证据", @xlsx.Bold), [
    (1, 1),
    (1, 2),
  ])
  let (italic, italic_count) = @xlsx.set_font_decoration_range(
    source,
    "研究证据",
    1,
    1,
    2,
    1,
    @xlsx.Italic,
    true,
  )
  assert_eq(italic_count, 2)
  let (underlined, underline_count) = @xlsx.set_font_decoration_range(
    italic,
    "研究证据",
    1,
    1,
    1,
    1,
    @xlsx.Underline,
    true,
  )
  assert_eq(underline_count, 1)
  let (unbold, cleared) = @xlsx.set_font_decoration_range(
    underlined,
    "研究证据",
    1,
    1,
    1,
    1,
    @xlsx.Bold,
    false,
  )
  assert_eq(cleared, 1)
  assert_eq(@xlsx.font_decoration_cells(unbold, "研究证据", @xlsx.Bold), [
    (1, 2),
  ])
  assert_eq(@xlsx.font_decoration_cells(unbold, "研究证据", @xlsx.Italic), [
    (1, 1),
    (2, 1),
  ])
  assert_eq(
    @xlsx.font_decoration_cells(unbold, "研究证据", @xlsx.Underline),
    [(1, 1)],
  )
  let (bold, count) = @xlsx.set_font_decoration_range(
    unbold,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.Bold,
    true,
  )
  assert_eq(count, 1)
  assert_eq(@xlsx.font_decoration_cells(bold, "研究证据", @xlsx.Bold), [
    (1, 2),
    (2, 1),
  ])
  let (again, no_change) = @xlsx.set_font_decoration_range(
    bold,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.Bold,
    true,
  )
  assert_eq(no_change, 0)
  assert_eq(again.text("xl/styles.xml"), bold.text("xl/styles.xml"))
  assert_eq(@xlsx.read(bold).sheets[0].cells[2].value, @scene.Text("Evidence"))
}
