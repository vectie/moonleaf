///|
test "replace all text preserves Unicode and ignores ASCII letter case" {
  assert_eq(
    replace_visible_text("Alpha alpha，阿尔法 Alpha", "ALPHA", "研究"),
    "研究 研究，阿尔法 研究",
  )
  assert_eq(
    replace_visible_text("公司公告 公司", "公司", "企业"),
    "企业公告 企业",
  )
  assert_eq(replace_visible_text("untouched", "missing", "new"), "untouched")
}

///|
test "paste request keeps ragged rows and checks placement" {
  let request = @json.parse(
    "{\"sheet\":\"工作表1\",\"start_row\":2,\"start_column\":3,\"rows\":[[\"甲\",\"=1+1\"],[\"乙\"]]}",
  )
  let (sheet, edits) = paste_edits(request)
  assert_eq(sheet, "工作表1")
  assert_eq(edits, [(2, 3, "甲"), (2, 4, "=1+1"), (3, 3, "乙")])
  assert_eq(safe_csv_text(edits[1].2), "'=1+1")
}

///|
test "CSV preserves negative numeric values while protecting text formulas" {
  assert_eq(csv_cell_text(@scene.Number("-0.05")), "-0.05")
  assert_eq(csv_cell_text(@scene.Text("-0.05")), "'-0.05")
  assert_eq(csv_cell_text(@scene.Text("=1+1")), "'=1+1")
}

///|
test "CSV creation is readable and protects spreadsheet formula text" {
  let result = created_csv_bytes([
    [@scene.Text("标题"), @scene.Text("摘录")],
    [@scene.Text("=1+1"), @scene.Text("债券,\"公司\"\n下一行")],
  ]).unwrap()
  let output = @utf8.decode(Bytes::from_array(result))
  assert_true(output.has_prefix("\u{FEFF}"))
  let reopened = @csv.parse(output)
  assert_eq(reopened.rows[1][0], "'=1+1")
  assert_eq(reopened.rows[1][1], "债券,\"公司\"\n下一行")
}

///|
test "CSV creation rejects quoted output beyond its reader limit" {
  let long_text = "\"".repeat(1_100_000)
  let result = created_csv_bytes([[@scene.Text(long_text)]])
  assert_eq(
    result.unwrap_err(),
    "CSV export exceeds MoonLeaf's 2 MiB reader limit",
  )
}

///|
test "CSV creation keeps empty workbooks and blank rows reopenable" {
  let empty = @utf8.decode(Bytes::from_array(created_csv_bytes([]).unwrap()))
  assert_eq(@csv.parse(empty).rows.length(), 0)
  let blank = @utf8.decode(Bytes::from_array(created_csv_bytes([[]]).unwrap()))
  assert_eq(@csv.parse(blank).rows, [[""]])
}

///|
test "XLSX sheet CSV rows retain gaps, numbers and protected formulas" {
  let sheet : @scene.Sheet = {
    name: "研究证据",
    cells: [
      { row: 1, column: 1, value: @scene.Text("名称"), style_id: None, },
      { row: 1, column: 2, value: @scene.Text("数值"), style_id: None, },
      { row: 3, column: 1, value: @scene.Text("=2+2"), style_id: None, },
      { row: 3, column: 2, value: @scene.Number("-0.05"), style_id: None, },
      {
        row: 3,
        column: 3,
        value: @scene.Formula(expression="B3*2", cached=Some("-0.1")),
        style_id: None,
      },
    ],
    merged_ranges: [],
  }
  let (rows, columns, formulas) = sheet_csv_rows(sheet)
  assert_eq(rows.length(), 3)
  assert_eq(columns, 3)
  assert_eq(formulas, 1)
  let output = @utf8.decode(Bytes::from_array(created_csv_bytes(rows).unwrap()))
  assert_eq(@csv.parse(output).rows, [
    ["名称", "数值"],
    [""],
    ["'=2+2", "-0.05", "'=B3*2"],
  ])
}

///|
test "numeric preview metadata excludes numeric text, formulas and non-finite values" {
  assert_true(is_numeric_cell(@scene.Number("12.5")))
  assert_true(is_numeric_cell(@scene.Number("-0.05")))
  assert_true(is_numeric_cell(@scene.Number("1e3")))
  assert_true(!is_numeric_cell(@scene.Text("12.5")))
  assert_true(
    !is_numeric_cell(@scene.Formula(expression="A1*2", cached=Some("25"))),
  )
  assert_true(!is_numeric_cell(@scene.Boolean(true)))
  assert_true(!is_numeric_cell(@scene.Number("NaN")))
  assert_true(!is_numeric_cell(@scene.Number("Infinity")))
  assert_true(!is_numeric_cell(@scene.Number("not-a-number")))
}

///|
test "spreadsheet preview distinguishes numeric cells from formulas" {
  let sheet : @scene.Sheet = {
    name: "研究证据",
    cells: [
      { row: 1, column: 1, value: @scene.Number("12.5"), style_id: None, },
      { row: 1, column: 2, value: @scene.Text("12.5"), style_id: None, },
      {
        row: 1,
        column: 3,
        value: @scene.Formula(expression="A1*2", cached=Some("25")),
        style_id: None,
      },
      { row: 1, column: 4, value: @scene.Number("NaN"), style_id: None, },
    ],
    merged_ranges: [],
  }
  let preview = sheet_json(sheet, Ref(0), Ref(0), [], [], [], [], [], [], [], [
    1,
  ])
  guard preview
    is {
      "numeric_cells": Array(items),
      "formula_cells": Array(formulas),
      "rows": Array(rows),
      "hidden_rows": Array(hidden),
      ..
    } else {
    fail("missing numeric preview metadata")
  }
  let expected : Json = [1, 1]
  assert_eq(items, [expected])
  let formula : Json = [1, 3]
  assert_eq(formulas, [formula])
  assert_eq(rows.length(), 1)
  assert_eq(hidden, [@json.to_json(1)])
}

///|
test "delimited edit verifier preserves BOM and distant rows" {
  let source = "\u{FEFF}列,值\r\n甲,1"
  let table = @csv.parse(source)
  let edited = table.set_cell_text(5, 2, "新增")
  let bytes = verified_delimited_bytes(edited, source)
  let saved = @utf8.decode(Bytes::from_array(bytes))
  assert_true(saved.has_prefix("\u{FEFF}"))
  assert_eq(@csv.parse(saved).rows, edited.rows)
}

///|
test "delimited XLSX conversion preserves zeroes, formulas and Unicode as text" {
  let rows = delimited_xlsx_rows(
    "\u{FEFF}证券代码,说明\r\n001234,\"含,逗号\"\r\n=1+1,\"换行\n文本\"",
    ',',
  )
  let workbook = @xlsx.read(
    @opc.open(@xlsx.create(rows, sheet_name="导入数据")),
  )
  let cells = workbook.sheets[0].cells
  assert_eq(cells[0].value, @scene.Text("证券代码"))
  assert_eq(cells[2].value, @scene.Text("001234"))
  assert_eq(cells[3].value, @scene.Text("含,逗号"))
  assert_eq(cells[4].value, @scene.Text("=1+1"))
  assert_eq(cells[5].value, @scene.Text("换行\n文本"))
}

///|
test "TSV conversion rejects malformed quoting" {
  let rejected = try {
    ignore(delimited_xlsx_rows("a\t\"unterminated", '\t'))
    false
  } catch {
    @csv.CsvError::UnterminatedQuote => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "verified DOCX edit copy preserves non-document OPC parts" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive
    .replace_text("[Content_Types].xml", "<Types/>")
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>旧公司</w:t></w:r></w:p></w:body></w:document>",
    )
    .replace_text("custom/payload.txt", "旧公司")
  let source = @opc.save(archive)
  let result = verified_docx_edit_copy(source, "旧公司", " 新公司 ")
  let reopened = @opc.open(result)
  assert_eq(reopened.text("custom/payload.txt"), "旧公司")
  assert_true(
    reopened
    .text("word/document.xml")
    .find("<w:t xml:space=\"preserve\"> 新公司 </w:t>")
    is Some(_),
  )
  let document = @docx.read(reopened)
  assert_true(document.blocks is [Paragraph([{ text: " 新公司 ", .. }])])
}

///|
test "verified DOCX edit copy replaces a phrase split over styled runs" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive
    .replace_text("[Content_Types].xml", "<Types/>")
    .replace_text(
      "word/document.xml",
      "<w:document xmlns:w=\"urn:w\"><w:body><w:p>" +
      "<w:r><w:rPr><w:b/></w:rPr><w:t>旧</w:t></w:r>" +
      "<w:r><w:rPr><w:i/></w:rPr><w:t>公司</w:t></w:r>" +
      "</w:p></w:body></w:document>",
    )
  let result = verified_docx_edit_copy(
    @opc.save(archive),
    "旧公司",
    "新机构",
  )
  let xml = @opc.open(result).text("word/document.xml")
  assert_true(xml.find("<w:rPr><w:b/></w:rPr><w:t>新机构</w:t>") is Some(_))
  assert_true(xml.find("<w:rPr><w:i/></w:rPr><w:t></w:t>") is Some(_))
}

///|
test "verified DOCX edit copy also updates header and footer parts" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive
    .replace_text("[Content_Types].xml", "<Types/>")
    .replace_text(
      "word/document.xml", "<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>正文</w:t></w:r></w:p></w:body></w:document>",
    )
    .replace_text(
      "word/header1.xml", "<w:hdr xmlns:w=\"urn:w\"><w:p><w:r><w:t>旧公司页眉</w:t></w:r></w:p></w:hdr>",
    )
    .replace_text(
      "word/footer1.xml", "<w:ftr xmlns:w=\"urn:w\"><w:p><w:r><w:t>旧公司页脚</w:t></w:r></w:p></w:ftr>",
    )
  let result = verified_docx_edit_copy(
    @opc.save(archive),
    "旧公司",
    "新机构",
  )
  let reopened = @opc.open(result)
  assert_true(reopened.text("word/header1.xml").contains("新机构页眉"))
  assert_true(reopened.text("word/footer1.xml").contains("新机构页脚"))
  assert_true(reopened.text("word/document.xml").contains("正文"))
}
