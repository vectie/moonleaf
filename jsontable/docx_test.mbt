///|
fn docx_table_fixture(body : String) -> @opc.Package {
  let archive : @opc.Package = { parts: [], }
  archive.replace_text(
    "word/document.xml",
    "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>" +
    body +
    "</w:body></w:document>",
  )
}

///|
fn docx_cell(text : String) -> String {
  "<w:tc><w:p><w:r><w:t>" + @xml.escape_text(text) + "</w:t></w:r></w:p></w:tc>"
}

///|
fn docx_row(cells : Array[String]) -> String {
  "<w:tr>" + cells.map(docx_cell).join("") + "</w:tr>"
}

///|
fn docx_import(
  body : String,
  header? : @jsontable.DocxHeader = FirstTableRow,
) -> @jsontable.DocxTable raise {
  @jsontable.extract_docx(
    docx_table_fixture(body),
    table_id="body/table:1",
    header~,
  )
}

///|
fn refuses_docx(body : String) -> Unit raise {
  let result = try? docx_import(body)
  assert_true(result is Err(_))
}

///|
test "docx tables preserve literal text blank cells order and source row mapping" {
  let source = docx_table_fixture(
    "<w:p/><w:tbl>" +
    docx_row(["id", "amount", "note"]) +
    docx_row(["001", "12.50", "=1+1"]) +
    docx_row(["002", "", "雪😀 & <tag>,\"quote\""]) +
    "</w:tbl><w:p/>",
  )
  let before = source.text("word/document.xml")
  let candidates = @jsontable.list_docx_tables(source)
  assert_eq(candidates.length(), 1)
  assert_eq(candidates[0].id, "body/table:1")
  assert_eq(candidates[0].first_row, ["id", "amount", "note"])
  assert_eq(candidates[0].refusal, None)
  let imported = @jsontable.extract_docx(
    source,
    table_id="body/table:1",
    header=FirstTableRow,
  )
  assert_eq(imported.source_rows, [2, 3])
  assert_eq(imported.table.text_rows(), [
    ["001", "12.50", "=1+1"],
    ["002", "", "雪😀 & <tag>,\"quote\""],
  ])
  assert_true(imported.table.rows[0][1] is @scene.Text("12.50"))
  imported.table.rows[0][0] = @scene.Text("changed")
  candidates[0].first_row[0] = "changed"
  assert_eq(source.text("word/document.xml"), before)
  assert_eq(@jsontable.list_docx_tables(source)[0].first_row[0], "id")
}

///|
test "docx extraction joins rich runs and preserves paragraphs tabs and breaks" {
  let body = "<w:tbl><w:tr><w:tc><w:tcPr/><w:p><w:pPr/><w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\"> A</w:t></w:r><w:r><w:t>B </w:t><w:tab/><w:t>C</w:t><w:br/><w:t>D</w:t><w:cr/><w:noBreakHyphen/><w:softHyphen/></w:r></w:p><w:p/><w:p><w:r><w:t>E</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
  let imported = docx_import(body, header=TableColumns(["text"]))
  assert_eq(imported.table.text_rows(), [[" AB \tC\nD\n\u2011\u00ad\n\nE"]])
  assert_eq(imported.source_rows, [1])
}

///|
test "docx explicit headers and header-only tables have unambiguous shape" {
  let names = ["renamed"]
  let body = "<w:tbl>" + docx_row(["header"]) + "</w:tbl>"
  let empty = docx_import(body)
  assert_eq(empty.table.rows, [])
  assert_eq(empty.source_rows, [])
  let data = docx_import(body, header=TableColumns(names))
  names[0] = "mutated"
  assert_eq(data.table.columns, ["renamed"])
  assert_eq(data.table.text_rows(), [["header"]])
  for
    header in [
      @jsontable.TableColumns([]),
      @jsontable.TableColumns([""]),
      @jsontable.TableColumns(["a", "b"]),
    ] {
    assert_true((try? docx_import(body, header~)) is Err(_))
  }
  refuses_docx("<w:tbl>" + docx_row(["duplicate", "duplicate"]) + "</w:tbl>")
  refuses_docx("<w:tbl>" + docx_row([""]) + "</w:tbl>")
}

///|
test "docx unsupported unrelated tables stay discoverable without blocking selected table" {
  let merged = "<w:tbl><w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr><w:p/></w:tc></w:tr></w:tbl>"
  let plain = "<w:tbl>" + docx_row(["h"]) + docx_row(["ok"]) + "</w:tbl>"
  let source = docx_table_fixture(merged + "<w:p/>" + plain)
  let candidates = @jsontable.list_docx_tables(source)
  assert_eq(candidates.length(), 2)
  assert_true(candidates[0].refusal is Some(_))
  assert_eq(candidates[1].id, "body/table:2")
  let selected = @jsontable.extract_docx(
    source,
    table_id="body/table:2",
    header=FirstTableRow,
  )
  assert_eq(selected.table.text_rows(), [["ok"]])
  assert_true(
    (try? @jsontable.extract_docx(
      source,
      table_id="body/table:01",
      header=FirstTableRow,
    ))
    is Err(_),
  )
}

///|
test "docx refuses merged skipped ragged and mismatched grid tables" {
  for property in ["gridSpan", "vMerge", "hMerge", "gridBefore", "gridAfter"] {
    refuses_docx(
      "<w:tbl><w:tr><w:trPr><w:" +
      property +
      " w:val=\"1\"/></w:trPr>" +
      docx_cell("h") +
      "</w:tr></w:tbl>",
    )
  }
  refuses_docx(
    "<w:tbl>" + docx_row(["a", "b"]) + docx_row(["one"]) + "</w:tbl>",
  )
  refuses_docx(
    "<w:tbl><w:tblGrid><w:gridCol/></w:tblGrid>" +
    docx_row(["a", "b"]) +
    "</w:tbl>",
  )
  refuses_docx("<w:tbl><w:tr/></w:tbl>")
  refuses_docx("<w:tbl/>")
}

///|
test "docx refuses selected wrappers nested content fields drawings and hidden text" {
  for
    content in [
      "<w:hyperlink><w:r><w:t>link</w:t></w:r></w:hyperlink>", "<w:sdt/>", "<w:ins/>",
      "<w:del/>", "<w:fldSimple/>", "<w:r><w:drawing/></w:r>", "<w:r><w:rPr><w:vanish/></w:rPr><w:t>secret</w:t></w:r>",
      "<w:r><w:rPr><w:rPrChange/></w:rPr><w:t>old</w:t></w:r>", "<w:r><w:br w:type=\"page\"/></w:r>",
      "<w:r><w:tab><w:t>lost</w:t></w:tab></w:r>",
    ] {
    refuses_docx(
      "<w:tbl><w:tr><w:tc><w:p>" + content + "</w:p></w:tc></w:tr></w:tbl>",
    )
  }
  refuses_docx("<w:tbl><w:tr><w:tc><w:p/><w:tbl/></w:tc></w:tr></w:tbl>")
  refuses_docx(
    "<w:tbl><w:tr><w:tc><w:p><w:r><w:t><w:t>nested</w:t></w:t></w:r></w:p></w:tc></w:tr></w:tbl>",
  )
}

///|
test "docx rejects global field scope rebound namespace and ambiguous body" {
  let table = "<w:tbl>" + docx_row(["h"]) + "</w:tbl>"
  refuses_docx(
    "<w:p><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r></w:p>" + table,
  )
  refuses_docx("<w:p xmlns:w=\"urn:wrong\"/>" + table)
  let archive = docx_table_fixture(table).replace_text(
    "word/document.xml", "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body/><w:body/></w:document>",
  )
  assert_true((try? @jsontable.list_docx_tables(archive)) is Err(_))
  assert_true(
    (try? @jsontable.list_docx_tables(
      docx_table_fixture(table).replace_text(
        "word/document.xml", "<document><body/></document>",
      ),
    ))
    is Err(_),
  )
}

///|
test "docx does not flatten wrapped body tables and preserves table order" {
  let plain = "<w:tbl>" + docx_row(["h"]) + "</w:tbl>"
  let source = docx_table_fixture("<w:sdt>" + plain + "</w:sdt>" + plain)
  assert_eq(@jsontable.list_docx_tables(source).length(), 1)
  assert_eq(@jsontable.list_docx_tables(docx_table_fixture("<w:p/>")), [])
}

///|
test "docx query export preserves source row identities and literal XLSX cells" {
  let value = docx_import(
    "<w:tbl>" +
    docx_row(["id", "text"]) +
    docx_row(["b", "=1+1"]) +
    docx_row(["a", "雪😀"]) +
    "</w:tbl>",
  )
  let query = @jsontable.parse_query_recipe(
    (
      #|{"version":1,"filters":[],"sort":[{"column":"id","mode":"text","direction":"asc","blanks":"last"}],"select":["id","text"],"limit":10}
    ),
  )
  let selected = value.table.query(query)
  assert_eq(selected.source_rows.map(i => value.source_rows[i - 1]), [3, 2])
  let reopened = @jsontable.extract_xlsx(
    @opc.open(selected.table.export_xlsx()),
    sheet_name="JSON data",
    range="A1:B3",
    header=FirstRow,
  )
  assert_eq(reopened.table, selected.table)
  assert_eq(reopened.table.text_rows(), [["a", "雪😀"], ["b", "=1+1"]])
}

///|
test "docx bounds columns rows cells and supplied header text" {
  refuses_docx(
    "<w:tbl>" + docx_row(Array::makei(129, i => i.to_string())) + "</w:tbl>",
  )
  let rows = Array::makei(10002, _ => docx_row(["x"]))
  refuses_docx("<w:tbl>" + rows.join("") + "</w:tbl>")
  let wide = docx_row(Array::makei(128, i => i.to_string()))
  refuses_docx("<w:tbl>" + Array::makei(782, _ => wide).join("") + "</w:tbl>")
  let body = "<w:tbl>" + docx_row(["x"]) + "</w:tbl>"
  let too_large = "a".repeat(4000001)
  assert_true(
    (try? docx_import(body, header=TableColumns([too_large]))) is Err(_),
  )
}
