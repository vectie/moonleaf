///|
test "create XLSX roundtrips Unicode, numbers, literal formulas and header style" {
  let bytes = @xlsx.create(
    [
      [Text("标题"), Text("序号")],
      [Text("债券 & 公司"), Number("12")],
      [Text("=1+1"), Text("换行\n测试")],
    ],
    sheet_name="研究证据",
  )
  let workbook = @xlsx.read(@opc.open(bytes))
  assert_eq(workbook.sheets.length(), 1)
  assert_eq(workbook.sheets[0].name, "研究证据")
  assert_eq(workbook.sheets[0].cells[2].value, Text("债券 & 公司"))
  assert_eq(workbook.sheets[0].cells[3].value, Number("12"))
  assert_eq(workbook.sheets[0].cells[4].value, Text("=1+1"))
  assert_eq(workbook.sheets[0].cells[5].value, Text("换行\n测试"))
  assert_eq(workbook.sheets[0].cells[0].style_id, Some(1))
}

///|
test "created XLSX preserves CR CRLF and valid XML character edges" {
  let values = [
    "before\rafter", "before\r\nafter", "before\nafter", "before\tafter", "literal &#13; and <&>",
    "\u{20}\u{D7FF}\u{E000}\u{FFFD}\u{10000}\u{10FFFF}",
  ]
  let sheet_name = "Line\r\nTab\t"
  let bytes = @xlsx.create(values.map(text => [Text(text)]), sheet_name~)
  let pkg = @opc.open(bytes)
  let workbook = @xlsx.read(pkg)
  assert_eq(workbook.sheets[0].name, sheet_name)
  for i, text in values {
    assert_eq(workbook.sheets[0].cells[i].value, Text(text))
  }
  let worksheet = pkg.text("xl/worksheets/sheet1.xml")
  assert_true(worksheet.contains("before&#13;after"))
  assert_true(worksheet.contains("before&#13;\nafter"))
  assert_true(worksheet.contains("literal &amp;#13; and &lt;&amp;&gt;"))
  let book = pkg.text("xl/workbook.xml")
  assert_true(book.contains("Line&#13;&#10;Tab&#9;"))
}

///|
test "created XLSX rejects every XML forbidden control and noncharacter boundary" {
  let invalid : Array[String] = []
  for point in 0..<32 {
    if point != 9 && point != 10 && point != 13 {
      invalid.push(point.unsafe_to_char().to_string())
    }
  }
  invalid.push("\u{FFFE}")
  invalid.push("\u{FFFF}")
  for text in invalid {
    let cells : Array[@scene.CellValue] = [
      Text(text),
      Error(text),
      Number(text),
      Formula(expression=text, cached=None),
      Formula(expression="1+1", cached=Some(text)),
    ]
    for value in cells {
      try @xlsx.create([[Text("valid")], [value]]) catch {
        InvalidWorkbook(_) => ()
        error => fail("Unexpected error: \{Repr(error)}")
      } noraise {
        _ => fail("Expected invalid XML cell refusal")
      }
    }
    try @xlsx.create([[Text("valid")]], sheet_name="a" + text) catch {
      InvalidWorkbook(_) => ()
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected invalid XML attribute refusal")
    }
  }
}

///|
test "XLSX sheet names count characters rather than UTF-8 bytes" {
  let name = "一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一"
  let workbook = @xlsx.read(
    @opc.open(@xlsx.create([[Text("内容")]], sheet_name=name)),
  )
  assert_eq(workbook.sheets[0].name, name)
  let too_long = try {
    ignore(@xlsx.create([[Text("内容")]], sheet_name=name + "二"))
    false
  } catch {
    InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(too_long)
  let leading_apostrophe = try {
    ignore(@xlsx.create([[Text("内容")]], sheet_name="'研究"))
    false
  } catch {
    InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(leading_apostrophe)
}

///|
test "XLSX creation rejects XML control characters in cells" {
  let rejected = try {
    ignore(@xlsx.create([[Text("安全\u{0000}失败")]]))
    false
  } catch {
    InvalidWorkbook(_) => true
    _ => false
  }
  assert_true(rejected)
  let workbook = @xlsx.read(
    @opc.open(@xlsx.create([[Text("换行\n有效\t内容")]])),
  )
  assert_eq(workbook.sheets[0].cells[0].value, Text("换行\n有效\t内容"))
}
