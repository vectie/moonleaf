///|
test "recalculate replaces stale caches and follows dependencies after edits" {
  let original = inspect_fixture(
    "",
    None,
    None,
    "<c r=\"A1\"><v>12.5</v></c><c r=\"B1\"><v>4</v></c><c r=\"C1\"><f>$A$1*B1</f><v>999</v></c><c r=\"D1\"><f>ROUND(SUM(A1:C1)*10%,2)</f><v>999</v></c><c r=\"E1\"><f>MIN(A1:C1)+MAX(A1:C1)</f></c>",
  )
  let recalculated = @xlsx.recalculate(original)
  let cells = @xlsx.inspect(recalculated)
  assert_eq(cells[2].cached_value, Some("50"))
  assert_eq(cells[3].cached_value, Some("6.65"))
  assert_eq(cells[4].cached_value, Some("54"))
  let changed = @xlsx.set_cell_text(recalculated, "Sheet1", 1, 2, "8")
  let second = @xlsx.inspect(@xlsx.recalculate(changed))
  assert_eq(second[2].cached_value, Some("100"))
  assert_eq(second[3].cached_value, Some("12.05"))
  assert_eq(original.text("xl/worksheets/sheet1.xml").contains("999"), true)
  assert_eq(@xlsx.recalculate(recalculated), recalculated)
}

///|
test "recalculate handles precedence blank references and negative rounding" {
  let formulas = [
    "2+3*4", "(2+3)*4", "ROUND(-2.5,0)", "ROUND(125,-1)", "Z9+2", "-(-3)+25%",
  ]
  let expected = ["14", "20", "-3", "130", "2", "3.25"]
  for index, formula in formulas {
    let input = inspect_fixture(
      "",
      None,
      None,
      "<c r=\"A1\"><f>" + formula + "</f><v>999</v></c>",
    )
    assert_eq(
      @xlsx.inspect(@xlsx.recalculate(input))[0].cached_value,
      Some(expected[index]),
    )
  }
}

///|
test "recalculate repairs old error caches but never trusts them" {
  let input = inspect_fixture(
    "",
    None,
    None,
    "<c r=\"A1\" t=\"e\"><f>B1*2</f><v>#DIV/0!</v></c><c r=\"B1\"><v>12</v></c>",
  )
  let result = @xlsx.recalculate(input)
  assert_eq(@xlsx.inspect(result)[0].cached_value, Some("24"))
  assert_false(result.text("xl/worksheets/sheet1.xml").contains("t=\"e\""))
}

///|
test "numeric editing preserves style and recalculation uses numeric inputs" {
  let input = inspect_fixture(
    "",
    None,
    None,
    "<c r=\"A1\" s=\"1\"><v>10</v></c><c r=\"B1\"><f>A1*2</f><v>20</v></c>",
  )
  let edited = @xlsx.set_cell_number(input, "Sheet1", 1, 1, 25.0)
  let cells = @xlsx.inspect(@xlsx.recalculate(edited))
  assert_eq(cells[0].raw_value, Some("25"))
  assert_eq(cells[0].resolved_text, None)
  assert_eq(cells[0].style_id, Some(1))
  assert_eq(cells[1].cached_value, Some("50"))
}

///|
test "recalculate rejects unsupported cyclic erroneous and unbounded formulas" {
  let formulas = [
    "A1+1", "1/0", "VLOOKUP(A2,A3,1)", "Sheet2!A1", "[book.xlsx]A1", "SUM(A1:XFD1048576)",
    "ROUND(1,100)", "SUM()", "1e999", "1+", "A1^2",
  ]
  for formula in formulas {
    let input = inspect_fixture(
      "",
      None,
      None,
      "<c r=\"A1\"><f>" + formula + "</f><v>999</v></c>",
    )
    try @xlsx.recalculate(input) catch {
      _ => ()
    } noraise {
      _ => fail("accepted unsupported formula: " + formula)
    }
  }
  for
    cells in [
      "<c r=\"A1\"><f>B1</f></c><c r=\"B1\"><f>A1</f></c>", "<c r=\"A1\"><f t=\"shared\" si=\"0\">1+2</f><v>3</v></c>",
      "<c r=\"A1\" t=\"e\"><v>#REF!</v></c>", "<c r=\"A1\"><v>1</v></c><c r=\"A1\"><v>2</v></c>",
      "<c r=\"A1\"><f>B1+1</f></c><c r=\"B1\" t=\"inlineStr\"><is><t>not money</t></is></c>",
    ] {
    try @xlsx.recalculate(inspect_fixture("", None, None, cells)) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid workbook")
    }
  }
}
