///|
test "CSV row insert and delete preserve quoted values and source table" {
  let source = @csv.parse(
    "\u{FEFF}公司,说明,空\r\n风语筑,\"甲,\"\"乙\"\"\n丙\",\r\n尾行,\"Q\",末",
  )
  let source_rows = source.rows.map(row => row.copy())
  let inserted = source.insert_rows(2, 2)
  assert_eq(source.rows, source_rows)
  assert_eq(inserted.rows.length(), 5)
  assert_eq(inserted.rows[1], [""])
  assert_eq(inserted.rows[2], [""])
  assert_eq(inserted.rows[3][1], "甲,\"乙\"\n丙")
  assert_eq(@csv.parse(inserted.serialize()).rows, inserted.rows)
  let (restored, removed) = inserted.delete_rows(2, 2)
  assert_eq(removed, 2)
  assert_eq(restored.rows, source.rows)
  assert_eq(@csv.parse(restored.serialize()).rows, source.rows)
}

///|
test "TSV trailing blank row and distant insertion survive serialization" {
  let source = @csv.parse("a\tb\r\n\"a\tb\"\t\"x\"\"y\"", delimiter='\t')
  let appended = source.insert_rows(3, 1)
  assert_eq(appended.rows[2], [""])
  assert_eq(
    @csv.parse(appended.serialize(), delimiter='\t').rows,
    appended.rows,
  )
  let distant = source.insert_rows(5, 1)
  assert_eq(distant.rows.length(), 5)
  assert_eq(@csv.parse(distant.serialize(), delimiter='\t').rows, distant.rows)
  let (restored, removed) = appended.delete_rows(3, 1)
  assert_eq(removed, 1)
  assert_eq(restored.rows, source.rows)
  let (unchanged, none) = source.delete_rows(5, 1)
  assert_eq(none, 0)
  assert_eq(unchanged.rows, source.rows)
}

///|
test "CSV row edits reject coordinates beyond preview limits" {
  let source = @csv.parse("a,b")
  let invalid = try {
    ignore(source.insert_rows(10_000, 2))
    false
  } catch {
    @csv.CsvError::InvalidCoordinates(..) => true
    _ => false
  }
  assert_true(invalid)
  let invalid_count = try {
    ignore(source.delete_rows(1, 101))
    false
  } catch {
    @csv.CsvError::InvalidCoordinates(..) => true
    _ => false
  }
  assert_true(invalid_count)
}
