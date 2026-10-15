///|
test "atomic XLSX correction session increments once verifies copy and keeps failed original" {
  let bytes = @xlsx.create([[Text("Ada"), Text("Bo")]], sheet_name="Names")
  let session = @moonleaf.open_session("original.xlsx", bytes)
  let edits : Array[@xlsx.TextCellCorrection] = [
    {
      sheet: "Names",
      address: "A1",
      expected: "Ada",
      replacement: "Ada Lovelace",
    },
    { sheet: "Names", address: "B1", expected: "Bo", replacement: "Bo Li", },
  ]
  let changed = session.correct_xlsx_text_cells(edits)
  assert_eq(changed.revision(), 1)
  assert_true(changed.is_dirty())
  assert_eq(session.revision(), 0)
  assert_false(session.is_dirty())
  let copy = changed.save_as_copy()
  assert_false(copy.session().is_dirty())
  let archive = @opc.open(copy.bytes())
  assert_eq(
    @xlsx.inspect_text_cell(archive, sheet_name="Names", address="A1").text,
    "Ada Lovelace",
  )
  assert_eq(
    @xlsx.inspect_text_cell(archive, sheet_name="Names", address="B1").text,
    "Bo Li",
  )
  assert_eq(
    session.scene(),
    @moonleaf.open_session("original.xlsx", bytes).scene(),
  )
  assert_true(
    try changed.correct_xlsx_text_cells(edits) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let noop = changed.correct_xlsx_text_cells([
    {
      sheet: "Names",
      address: "A1",
      expected: "Ada Lovelace",
      replacement: "Ada Lovelace",
    },
  ])
  assert_eq(noop.revision(), 1)
  assert_true(noop.is_dirty())
}
