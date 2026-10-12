///|
test "number formats preserve numeric values, formulas, wrap and alignment" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Price"), @scene.Text("Rate")],
      [@scene.Number("12.345"), @scene.Number("0.257")],
      [@scene.Formula(expression="A2*2", cached=Some("24.69")), @scene.Empty],
    ]),
  )
  let (wrapped, _) = @xlsx.set_wrap_text_range(
    source, "研究证据", 2, 1, 2, 1, true,
  )
  let (right, _) = @xlsx.set_horizontal_alignment_range(
    wrapped,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.Right,
  )
  let (number, number_count) = @xlsx.set_number_format_range(
    right,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.FormatNumber,
  )
  assert_eq(number_count, 1)
  let (percent, percent_count) = @xlsx.set_number_format_range(
    number,
    "研究证据",
    2,
    2,
    2,
    2,
    @xlsx.FormatPercent,
  )
  assert_eq(percent_count, 1)
  assert_eq(@xlsx.number_format_cells(percent, "研究证据"), [
    (2, 1, "number"),
    (2, 2, "percent"),
  ])
  assert_eq(@xlsx.wrapped_cells(percent, "研究证据"), [(2, 1)])
  assert_eq(@xlsx.horizontal_alignment_cells(percent, "研究证据"), [
    (2, 1, "right"),
  ])
  let cells = @xlsx.read(percent).sheets[0].cells
  assert_eq(cells[2].value, @scene.Number("12.345"))
  assert_eq(cells[3].value, @scene.Number("0.257"))
  assert_eq(
    cells[4].value,
    @scene.Formula(expression="A2*2", cached=Some("24.69")),
  )
  assert_eq(@xlsx.font_decoration_cells(percent, "研究证据", @xlsx.Bold), [
    (1, 1),
    (1, 2),
  ])
  let (again, unchanged) = @xlsx.set_number_format_range(
    percent,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.FormatNumber,
  )
  assert_eq(unchanged, 0)
  assert_eq(again.text("xl/styles.xml"), percent.text("xl/styles.xml"))
  let (general, reset) = @xlsx.set_number_format_range(
    percent,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.FormatGeneral,
  )
  assert_eq(reset, 1)
  assert_eq(@xlsx.number_format_cells(general, "研究证据"), [
    (2, 2, "percent"),
  ])
  assert_eq(@xlsx.wrapped_cells(general, "研究证据"), [(2, 1)])
}

///|
test "explicit decimal places reuse XLSX formats and keep values and styles" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Amount"), @scene.Text("Rate")],
      [@scene.Number("1234.5678"), @scene.Number("0.125")],
      [
        @scene.Formula(expression="A2*2", cached=Some("2469.1356")),
        @scene.Empty,
      ],
    ]),
  )
  let (wrapped, _) = @xlsx.set_wrap_text_range(
    source, "研究证据", 2, 1, 2, 1, true,
  )
  let (three, changed) = @xlsx.set_number_format_places_range(
    wrapped,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.FormatNumber,
    3,
  )
  assert_eq(changed, 1)
  let (rate, rate_changed) = @xlsx.set_number_format_places_range(
    three,
    "研究证据",
    2,
    2,
    2,
    2,
    @xlsx.FormatPercent,
    1,
  )
  assert_eq(rate_changed, 1)
  let (currency, currency_changed) = @xlsx.set_number_format_places_range(
    rate,
    "研究证据",
    3,
    1,
    3,
    1,
    @xlsx.FormatCurrency,
    0,
  )
  assert_eq(currency_changed, 1)
  assert_eq(@xlsx.number_format_cells(currency, "研究证据"), [
    (2, 1, "number"),
    (2, 2, "percent"),
    (3, 1, "currency"),
  ])
  assert_eq(@xlsx.number_format_places_cells(currency, "研究证据"), [
    (2, 1, 3),
    (2, 2, 1),
    (3, 1, 0),
  ])
  let styles = @xml.parse(currency.text("xl/styles.xml"))
  let formats = styles.first_child("numFmts").unwrap().children_named("numFmt")
  assert_eq(formats.length(), 3)
  assert_eq(formats[0].attribute("formatCode"), Some("#,##0.000"))
  assert_eq(formats[1].attribute("formatCode"), Some("0.0%"))
  assert_eq(
    formats[2].attribute("formatCode"),
    Some("\"¥\"#,##0;[Red]-\"¥\"#,##0"),
  )
  assert_eq(@xlsx.wrapped_cells(currency, "研究证据"), [(2, 1)])
  let cells = @xlsx.read(currency).sheets[0].cells
  assert_eq(cells[2].value, @scene.Number("1234.5678"))
  assert_eq(cells[3].value, @scene.Number("0.125"))
  assert_eq(
    cells[4].value,
    @scene.Formula(expression="A2*2", cached=Some("2469.1356")),
  )
  let (again, unchanged) = @xlsx.set_number_format_places_range(
    currency,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.FormatNumber,
    3,
  )
  assert_eq(unchanged, 0)
  assert_eq(again.text("xl/styles.xml"), currency.text("xl/styles.xml"))
  let (reused, new_cell) = @xlsx.set_number_format_places_range(
    currency,
    "研究证据",
    2,
    2,
    2,
    2,
    @xlsx.FormatNumber,
    3,
  )
  assert_eq(new_cell, 1)
  assert_eq(
    @xml.parse(reused.text("xl/styles.xml"))
    .first_child("numFmts")
    .unwrap()
    .children_named("numFmt")
    .length(),
    3,
  )
  let invalid_general = try {
    ignore(
      @xlsx.set_number_format_places_range(
        source,
        "研究证据",
        2,
        1,
        2,
        1,
        @xlsx.FormatGeneral,
        2,
      ),
    )
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(invalid_general)
  let invalid_places = try {
    ignore(
      @xlsx.set_number_format_places_range(
        source,
        "研究证据",
        2,
        1,
        2,
        1,
        @xlsx.FormatNumber,
        7,
      ),
    )
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(invalid_places)
  let (builtin_percent, _) = @xlsx.set_number_format_range(
    source,
    "研究证据",
    2,
    2,
    2,
    2,
    @xlsx.FormatPercent,
  )
  let (adjusted_percent, _) = @xlsx.set_number_format_places_range(
    builtin_percent,
    "研究证据",
    2,
    2,
    2,
    2,
    @xlsx.FormatPercent,
    3,
  )
  assert_eq(@xlsx.number_format_cells(adjusted_percent, "研究证据"), [
    (2, 2, "percent"),
  ])
}

///|
test "currency adds a valid custom format and reuses it across cells" {
  let source = @opc.open(
    @xlsx.create([
      [@scene.Text("Amount")],
      [@scene.Number("1234.5")],
      [@scene.Number("-5.25")],
    ]),
  )
  let (first, count) = @xlsx.set_number_format_range(
    source,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.FormatCurrency,
  )
  assert_eq(count, 1)
  let (second, more) = @xlsx.set_number_format_range(
    first,
    "研究证据",
    3,
    1,
    3,
    1,
    @xlsx.FormatCurrency,
  )
  assert_eq(more, 1)
  assert_eq(@xlsx.number_format_cells(second, "研究证据"), [
    (2, 1, "currency"),
    (3, 1, "currency"),
  ])
  let styles = @xml.parse(second.text("xl/styles.xml"))
  let formats = styles.first_child("numFmts").unwrap().children_named("numFmt")
  assert_eq(formats.length(), 1)
  assert_eq(formats[0].attribute("numFmtId"), Some("164"))
  assert_eq(
    formats[0].attribute("formatCode"),
    Some("\"¥\"#,##0.00;[Red]-\"¥\"#,##0.00"),
  )
  let inspected = @xlsx.inspect(second)
  assert_eq(inspected[1].number_format_id, Some(164))
  assert_eq(inspected[2].number_format_id, Some(164))
  assert_eq(inspected[1].raw_value, Some("1234.5"))
  assert_eq(inspected[2].raw_value, Some("-5.25"))
  let (again, unchanged) = @xlsx.set_number_format_range(
    second,
    "研究证据",
    2,
    1,
    3,
    1,
    @xlsx.FormatCurrency,
  )
  assert_eq(unchanged, 0)
  assert_eq(again.text("xl/styles.xml"), second.text("xl/styles.xml"))
  let (general, reset) = @xlsx.set_number_format_range(
    second,
    "研究证据",
    2,
    1,
    3,
    1,
    @xlsx.FormatGeneral,
  )
  assert_eq(reset, 2)
  assert_eq(@xlsx.number_format_cells(general, "研究证据"), [])
}

///|
test "currency avoids existing custom IDs and range limits are enforced" {
  let source = @opc.open(
    @xlsx.create([[@scene.Text("Amount")], [@scene.Number("7")]]),
  )
  let occupied = source.replace_text(
    "xl/styles.xml",
    source
    .text("xl/styles.xml")
    .replace(
      old="<fonts count=\"2\">",
      new="<numFmts count=\"1\"><numFmt numFmtId=\"164\" formatCode=\"0.0\"/></numFmts><fonts count=\"2\">",
    ),
  )
  let (formatted, count) = @xlsx.set_number_format_range(
    occupied,
    "研究证据",
    2,
    1,
    2,
    1,
    @xlsx.FormatCurrency,
  )
  assert_eq(count, 1)
  let formats = @xml.parse(formatted.text("xl/styles.xml"))
    .first_child("numFmts")
    .unwrap()
    .children_named("numFmt")
  assert_eq(formats.length(), 2)
  assert_eq(formats[0].attribute("numFmtId"), Some("164"))
  assert_eq(formats[1].attribute("numFmtId"), Some("165"))
  let oversized = try {
    ignore(
      @xlsx.set_number_format_range(
        source,
        "研究证据",
        1,
        1,
        100,
        11,
        @xlsx.FormatNumber,
      ),
    )
    false
  } catch {
    @xlsx.InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(oversized)
}
