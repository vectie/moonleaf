///|
fn alias_recalculation_fixture(cells : String) -> @opc.Package raise {
  let original = @opc.open(
    @xlsx.create([[Text("fixture")]], sheet_name="Sheet1"),
  )
  original.replace_text(
    "xl/worksheets/sheet1.xml",
    "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\">" +
    cells +
    "</row></sheetData></worksheet>",
  )
}

///|
test "recalculation canonicalizes cell and formula aliases without rewriting identities" {
  let original = alias_recalculation_fixture(
    "<c r=\"A01\" s=\"7\" t=\"inlineStr\"><is><t>5</t></is></c><c r=\"B01\" s=\"8\"><f>A1*2</f><v>999</v></c><c r=\"C01\"><f>$A$01+B01</f><v>999</v></c><c r=\"D1\"><f>SUM(A01:C01)</f><v>999</v></c>",
  )
  let before = original.text("xl/worksheets/sheet1.xml")
  let changed = @xlsx.recalculate(original)
  let reopened = @opc.open(@opc.save(changed))
  let cells = @xlsx.inspect(reopened)
  assert_eq(cells.length(), 4)
  assert_eq(cells[0].resolved_text, Some("5"))
  assert_eq(cells[0].style_id, Some(7))
  assert_eq(cells[1].cached_value, Some("10"))
  assert_eq(cells[1].formula, Some("A1*2"))
  assert_eq(cells[1].style_id, Some(8))
  assert_eq(cells[2].cached_value, Some("15"))
  assert_eq(cells[2].formula, Some("$A$01+B01"))
  assert_eq(cells[3].cached_value, Some("30"))
  assert_eq(cells[3].formula, Some("SUM(A01:C01)"))
  let xml = reopened.text("xl/worksheets/sheet1.xml")
  assert_true(xml.contains("r=\"A01\""))
  assert_true(xml.contains("r=\"B01\""))
  assert_true(xml.contains("r=\"C01\""))
  assert_eq(original.text("xl/worksheets/sheet1.xml"), before)
  for part in original.parts {
    if part.name != "xl/worksheets/sheet1.xml" {
      assert_eq(reopened.part(part.name).unwrap().content, part.content)
    }
  }
  assert_eq(@xlsx.recalculate(changed), changed)
}

///|
test "recalculation rejects logically duplicate aliases without choosing a value" {
  let original = alias_recalculation_fixture(
    "<c r=\"A1\"><v>5</v></c><c r=\"A01\"><v>6</v></c><c r=\"B1\"><f>A1*2</f><v>999</v></c>",
  )
  let before = @opc.save(original)
  try @xlsx.recalculate(original) catch {
    @xlsx.InvalidWorkbook(message) =>
      assert_eq(
        message, "recalculation requires unique explicit cell references",
      )
    _ => fail("expected ambiguous-coordinate refusal")
  } noraise {
    _ => fail("logical aliases must not select an arbitrary cell")
  }
  assert_eq(@opc.save(original), before)
}

///|
test "recalculation detects cycles through aliased references" {
  let original = alias_recalculation_fixture(
    "<c r=\"A01\"><f>$A$1+1</f><v>999</v></c>",
  )
  let before = @opc.save(original)
  try @xlsx.recalculate(original) catch {
    @xlsx.InvalidWorkbook(message) =>
      assert_eq(message, "circular formula reference")
    _ => fail("expected aliased-cycle refusal")
  } noraise {
    _ => fail("a coordinate alias must not hide a cycle")
  }
  assert_eq(@opc.save(original), before)
}

///|
test "recalculation retains reader coordinates despite mismatched container rows" {
  let original = alias_recalculation_fixture(
    "<c r=\"C09\"><f>A2*2+Z9</f><v>999</v></c><c r=\"A02\"><v>5</v></c>",
  )
  let cells = @xlsx.inspect(@xlsx.recalculate(original))
  assert_true(cells.map(cell => (cell.row, cell.column)) == [(9, 3), (2, 1)])
  assert_eq(cells[0].formula, Some("A2*2+Z9"))
  assert_eq(cells[0].cached_value, Some("10"))
  assert_eq(cells[1].raw_value, Some("5"))
}
