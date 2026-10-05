///|
test "CSV preserves Unicode, quotes, newlines and trailing blanks" {
  let table = @csv.parse(
    "\u{FEFF}公司,说明,空\r\n风语筑,\"甲,\"\"乙\"\"\n丙\",\r\n",
  )
  assert_eq(table.rows.length(), 2)
  assert_eq(table.rows[0][0], "公司")
  assert_eq(table.rows[1][1], "甲,\"乙\"\n丙")
  assert_eq(table.rows[1][2], "")
  let again = @csv.parse(table.serialize())
  assert_eq(again.rows, table.rows)
  let workbook = table.workbook()
  assert_eq(workbook.sheets[0].cells.length(), 6)
}

///|
test "TSV and malformed quotes" {
  let table = @csv.parse("A\tB\n1\t2", delimiter='\t')
  assert_eq(table.rows[1][1], "2")
  let invalid = try {
    ignore(@csv.parse("a,b\"c"))
    false
  } catch {
    @csv.CsvError::InvalidQuote(..) => true
    _ => false
  }
  assert_true(invalid)
  let unterminated = try {
    ignore(@csv.parse("\"open"))
    false
  } catch {
    @csv.CsvError::UnterminatedQuote => true
    _ => false
  }
  assert_true(unterminated)
  let after_quote = try {
    ignore(@csv.parse("\"a\"b"))
    false
  } catch {
    @csv.CsvError::InvalidQuote(..) => true
    _ => false
  }
  assert_true(after_quote)
}

///|
test "cell edit returns a copy with blank intermediate cells" {
  let original = @csv.parse("A,B\r\n1,2")
  let edited = original.set_cell_text(3, 4, "甲,\"乙\"")
  assert_eq(original.rows.length(), 2)
  assert_eq(edited.rows[2].length(), 4)
  assert_eq(edited.rows[2][0], "")
  assert_eq(@csv.parse(edited.serialize()).rows[2][3], "甲,\"乙\"")
  let invalid = try {
    ignore(original.set_cell_text(0, 1, "bad"))
    false
  } catch {
    @csv.CsvError::InvalidCoordinates(..) => true
    _ => false
  }
  assert_true(invalid)
}

///|
test "quoted CSV serialization preserves dangerous leading text as data" {
  let table : @csv.Table = {
    rows: [["标题", "摘录"], ["=1+1", "债券,\"公司\"\n下一行"]],
    delimiter: ',',
  }
  let encoded = table.serialize_quoted()
  assert_eq(
    encoded, "\"标题\",\"摘录\"\r\n\"=1+1\",\"债券,\"\"公司\"\"\n下一行\"",
  )
  assert_eq(@csv.parse(encoded).rows, table.rows)
}
