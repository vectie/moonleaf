///|
test "clear range removes values and formulas but retains styles and unrelated parts" {
  let original = sample_package()
  let (cleared, count) = @xlsx.clear_sheet_range(
    original, "Budget & Plan", 1, 1, 1, 8,
  )
  assert_eq(count, 7)
  let sheet = @xlsx.read(cleared).sheets[0]
  assert_true(sheet.cells.all(fn(cell) { cell.value is Empty }))
  assert_eq(sheet.cells[0].style_id, Some(5))
  assert_eq(cleared.text("custom/preserved.txt"), "leave me alone")
  let (again, second_count) = @xlsx.clear_sheet_range(
    cleared, "Budget & Plan", 1, 1, 1, 8,
  )
  assert_eq(second_count, 0)
  assert_eq(
    again.text("xl/worksheets/sheet1.xml"),
    cleared.text("xl/worksheets/sheet1.xml"),
  )
}

///|
test "clear range rejects too-large rectangle without changing source" {
  let source = sample_package()
  let rejected = try {
    ignore(@xlsx.clear_sheet_range(source, "Budget & Plan", 1, 1, 100, 20))
    false
  } catch {
    @xlsx.XlsxError::InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(rejected)
  assert_true(@xlsx.read(source).sheets[0].cells[6].value is Formula(..))
}
