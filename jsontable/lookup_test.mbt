///|
test "lookup enriches JSON orders with CSV customers and reopens both exports" {
  let orders = @jsontable.parse(
    "[{\"order\":\"A\",\"customer\":\"001\",\"amount\":42.5},{\"order\":\"B\",\"customer\":\"002\",\"amount\":10},{\"order\":\"C\",\"customer\":\"missing\",\"amount\":2},{\"order\":\"D\"}]",
  )
  let customers = @jsontable.parse_delimited(
    "id,name,active\r\n002,\"Acme, Inc\",yes\r\n001,東京 🐈,yes\r\n",
  )
  let before = orders.export_csv()
  let result = orders.lookup(
    customers,
    source_key="customer",
    lookup_key="id",
    columns=["name", "active"],
  )
  assert_eq(result.source_rows, [1, 2, 3, 4])
  assert_eq(result.lookup_rows, [Some(2), Some(1), None, None])
  assert_eq(result.table.text_rows()[0], [
    "A", "001", "42.5", "東京 🐈", "yes",
  ])
  assert_eq(result.table.text_rows()[2], ["C", "missing", "2", "", ""])
  assert_eq(orders.export_csv(), before)
  assert_eq(
    @csv.parse(result.table.export_csv()).rows,
    [result.table.columns] + result.table.text_rows(),
  )
  let workbook = @xlsx.read(@opc.open(result.table.export_xlsx()))
  assert_true(
    workbook.sheets[0].cells.any(cell => cell.value == @scene.Number("42.5")),
  )
  assert_true(
    workbook.sheets[0].cells.any(cell => cell.value == @scene.Text("001")),
  )
  assert_true(
    workbook.sheets[0].cells.any(cell => {
      cell.value == @scene.Text("東京 🐈")
    }),
  )
  let matched = orders.lookup(
    customers,
    source_key="customer",
    lookup_key="id",
    columns=["name"],
    prefix="",
    matched_only=true,
  )
  assert_eq(matched.source_rows, [1, 2])
  assert_eq(matched.lookup_rows, [Some(2), Some(1)])
  assert_eq(matched.table.columns, ["order", "customer", "amount", "name"])
  result.table.rows[0][0] = @scene.Text("changed")
  assert_eq(orders.export_csv(), before)
}

///|
test "lookup retains repeated source keys and typed JSON lookup fields" {
  let source = @jsontable.parse_delimited("sku\n01\n01\n1\n")
  let catalog = @jsontable.parse(
    "[{\"code\":\"01\",\"price\":3.5,\"stock\":true},{\"code\":\"1\",\"price\":99,\"stock\":false}]",
  )
  let result = source.lookup(catalog, source_key="sku", lookup_key="code", columns=[
    "price", "stock",
  ])
  assert_eq(result.lookup_rows, [Some(1), Some(1), Some(2)])
  assert_eq(result.table.rows[0], [
    @scene.Text("01"),
    @scene.Number("3.5"),
    @scene.Boolean(true),
  ])
  let tsv = @jsontable.parse_delimited(
    "id\tnote\n01\t\"hello\nworld\"\n",
    delimiter='\t',
  )
  assert_eq(tsv.text_rows(), [["01", "hello\nworld"]])
}

///|
test "lookup rejects ambiguous or malformed input without mutation" {
  let source = @jsontable.parse("[{\"id\":\"x\"}]")
  let duplicate = @jsontable.parse("[{\"id\":\"x\"},{\"id\":\"x\"}]")
  assert_true(
    (try? source.lookup(duplicate, source_key="id", lookup_key="id", columns=[]))
    is Err(@jsontable.DuplicateKey(1, 2)),
  )
  assert_true(
    (try? source.lookup(source, source_key="no", lookup_key="id", columns=[]))
    is Err(@jsontable.UnknownColumn("no")),
  )
  assert_true(
    (try? source.lookup(
      source,
      source_key="id",
      lookup_key="id",
      columns=["id"],
      prefix="",
    ))
    is Err(@jsontable.InvalidTable(_)),
  )
  assert_true(
    (try? source.lookup(source, source_key="id", lookup_key="id", columns=[
      "id", "id",
    ]))
    is Err(@jsontable.InvalidTable(_)),
  )
  assert_true(
    (try? @jsontable.parse_delimited("id,id\nx,y"))
    is Err(@jsontable.InvalidTable(_)),
  )
  assert_true(
    (try? @jsontable.parse_delimited("id,name\nx"))
    is Err(@jsontable.InvalidTable(_)),
  )
  let numbers = @jsontable.parse("[{\"id\":1}]")
  assert_true(
    (try? source.lookup(numbers, source_key="id", lookup_key="id", columns=[]))
    is Err(@jsontable.InvalidKey(1)),
  )
  assert_true(
    (try? numbers.lookup(source, source_key="id", lookup_key="id", columns=[]))
    is Err(@jsontable.InvalidKey(1)),
  )
  let blank = @jsontable.parse_delimited("id\n\"\"\n")
  assert_true(
    (try? source.lookup(blank, source_key="id", lookup_key="id", columns=[]))
    is Err(@jsontable.InvalidKey(1)),
  )
  let empty = @jsontable.parse_delimited("id,name\n")
  let unmatched = source.lookup(empty, source_key="id", lookup_key="id", columns=[
    "name",
  ])
  assert_eq(unmatched.lookup_rows, [None])
  assert_eq(source.text_rows(), [["x"]])
}

///|
test "lookup JSONL exact case and whitespace and empty matches" {
  let source = @jsontable.parse(
    "{\"key\":\"A\"}\n{\"key\":\"a\"}\n{\"key\":\" A \"}\n{\"key\":\"\"}\n{}\n",
    jsonl=true,
  )
  let reference = @jsontable.parse_delimited("key,value\nA,exact\n")
  let result = source.lookup(reference, source_key="key", lookup_key="key", columns=[
    "value",
  ])
  assert_eq(result.lookup_rows, [Some(1), None, None, None, None])
  let none = @jsontable.parse_delimited("key,value\nZ,none\n")
  let matched = source.lookup(
    none,
    source_key="key",
    lookup_key="key",
    columns=["value"],
    matched_only=true,
  )
  assert_eq(matched.source_rows, [])
  assert_eq(matched.table.columns, ["key", "lookup.value"])
  assert_eq(@csv.parse(matched.table.export_csv()).rows, [
    ["key", "lookup.value"],
  ])
  assert_true(
    (try? @jsontable.parse_delimited("id\n\"unfinished"))
    is Err(@jsontable.InvalidDelimited(_)),
  )
}
