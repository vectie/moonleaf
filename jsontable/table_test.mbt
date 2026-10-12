///|
test "JSON table unions keys and preserves values through CSV and XLSX" {
  let table = @jsontable.parse(
    (
      #|[{"name":"東京 🐈","amount":12.50,"enabled":true,"meta":{"kind":"a,b"}},
      #| {"name":"Zoë","note":"line\n\"two\"","amount":-2e3,"tags":[1,"好"]},
      #| {"name":"=literal","amount":null,"enabled":false}]
    ),
  )
  assert_eq(table.columns, ["name", "amount", "enabled", "meta", "note", "tags"])
  assert_eq(table.text_rows()[0], [
    "東京 🐈", "12.5", "true", "{\"kind\":\"a,b\"}", "", "",
  ])
  assert_eq(table.text_rows()[1], [
    "Zoë", "-2000", "", "", "line\n\"two\"", "[1,\"好\"]",
  ])
  assert_eq(table.text_rows()[2][1], "null")
  let csv = @csv.parse(table.export_csv())
  assert_eq(csv.rows, [table.columns] + table.text_rows())
  let workbook = @xlsx.read(@opc.open(table.export_xlsx()))
  assert_eq(workbook.sheets[0].cells[6].value, @scene.Text("東京 🐈"))
  assert_eq(workbook.sheets[0].cells[7].value, @scene.Number("12.5"))
  assert_eq(workbook.sheets[0].cells[8].value, @scene.Boolean(true))
  assert_true(
    workbook.sheets[0].cells.any(cell => cell.value == @scene.Text("=literal")),
  )
  assert_true(
    workbook.sheets[0].cells.any(cell => {
      cell.value == @scene.Text("[1,\"好\"]")
    }),
  )
}

///|
test "JSONL allows blank lines and unions optional fields" {
  let table = @jsontable.parse(
    "{\"a\":1}\r\n\n{\"b\":\"中文\",\"a\":2}\n",
    jsonl=true,
  )
  assert_eq(table.columns, ["a", "b"])
  assert_eq(table.text_rows(), [["1", ""], ["2", "中文"]])
  assert_eq(@jsontable.parse("[]").rows.length(), 0)
  assert_eq(@jsontable.parse("\n", jsonl=true).rows.length(), 0)
  assert_true((try? @jsontable.parse("{}")) is Err(@jsontable.ExpectedArray))
  assert_true(
    (try? @jsontable.parse("[{},42]")) is Err(@jsontable.ExpectedObject(2)),
  )
  assert_true(
    (try? @jsontable.parse("{}\n42", jsonl=true))
    is Err(@jsontable.ExpectedObject(2)),
  )
}
