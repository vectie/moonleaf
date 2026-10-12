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
test "distant CSV edits round trip through blank intermediate rows" {
  let original = @csv.parse("A,B\r\n1,2")
  let single = original.set_cell_text(5, 3, "远端")
  assert_eq(single.rows[2], [""])
  assert_eq(single.rows[3], [""])
  assert_eq(@csv.parse(single.serialize()).rows, single.rows)
  let batch = original.set_cells_text([(5, 3, "远端"), (3, 1, "中间")])
  assert_eq(batch.rows[3], [""])
  assert_eq(@csv.parse(batch.serialize()).rows, batch.rows)
  assert_eq(original.rows.length(), 2)
}

///|
test "batch paste expands CSV once and rejects duplicate coordinates" {
  let original = @csv.parse("A,B\r\n1,2")
  let edited = original.set_cells_text([
    (2, 2, "甲,乙"),
    (3, 3, "新行"),
    (2, 1, "=1+1"),
  ])
  assert_eq(original.rows[1], ["1", "2"])
  assert_eq(edited.rows[1], ["=1+1", "甲,乙"])
  assert_eq(edited.rows[2], ["", "", "新行"])
  assert_eq(@csv.parse(edited.serialize()).rows, edited.rows)
  let duplicate = try {
    ignore(original.set_cells_text([(1, 1, "x"), (1, 1, "y")]))
    false
  } catch {
    @csv.CsvError::InvalidCoordinates(..) => true
    _ => false
  }
  assert_true(duplicate)
  let oversized : Array[(Int, Int, String)] = []
  for row in 1..<=400 {
    oversized.push((row, 256, "x"))
  }
  let overflow = try {
    ignore(original.set_cells_text(oversized))
    false
  } catch {
    @csv.CsvError::TooLarge => true
    _ => false
  }
  assert_true(overflow)
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

///|
test "column insert and delete preserve ragged CSV and source values" {
  let source = @csv.parse("名称,值,备注\r\n甲,10\r\n乙,20,带,逗号")
  let inserted = source.insert_columns(2, 2)
  assert_eq(inserted.rows[0], ["名称", "", "", "值", "备注"])
  assert_eq(inserted.rows[1], ["甲", "", "", "10"])
  assert_eq(inserted.rows[2], ["乙", "", "", "20", "带", "逗号"])
  assert_eq(@csv.parse(inserted.serialize()).rows, inserted.rows)
  assert_eq(source.rows[1], ["甲", "10"])
  let (restored, removed) = inserted.delete_columns(2, 2)
  assert_eq(removed, 2)
  assert_eq(restored.rows, source.rows)
  let (unchanged, absent) = source.delete_columns(10, 1)
  assert_eq(absent, 0)
  assert_eq(unchanged.rows, source.rows)
}

///|
test "column operations keep CSV limits and surviving blank rows" {
  let source = @csv.parse("A\r\n\r\nB")
  let inserted = source.insert_columns(3, 1)
  assert_eq(inserted.rows[1], ["", "", ""])
  assert_eq(@csv.parse(inserted.serialize()).rows, inserted.rows)
  let (deleted, removed) = source.delete_columns(1, 1)
  assert_eq(removed, 1)
  assert_eq(deleted.rows, [[""], [""], [""]])
  assert_eq(@csv.parse(deleted.serialize()).rows, deleted.rows)
  let invalid = try {
    ignore(source.insert_columns(256, 2))
    false
  } catch {
    @csv.CsvError::InvalidCoordinates(..) => true
    _ => false
  }
  assert_true(invalid)
  let columns : Array[String] = []
  for index in 0..<256 {
    columns.push(index.to_string())
  }
  let wide = @csv.parse(columns.join(","))
  let overflow = try {
    ignore(wide.insert_columns(1, 1))
    false
  } catch {
    @csv.CsvError::TooLarge => true
    _ => false
  }
  assert_true(overflow)
}

///|
test "TSV column edits keep tabs and quoted multiline cells" {
  let source = @csv.parse(
    "名称\t说明\n甲\t\"首行\n次行\"",
    delimiter='\t',
  )
  let inserted = source.insert_columns(2, 1)
  assert_eq(inserted.rows[1], ["甲", "", "首行\n次行"])
  let (restored, changed) = inserted.delete_columns(2, 1)
  assert_eq(changed, 1)
  assert_eq(restored.rows, source.rows)
  assert_eq(@csv.parse(restored.serialize(), delimiter='\t').rows, source.rows)
}
