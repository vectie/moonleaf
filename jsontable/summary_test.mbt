///|
test "summary groups CSV by multiple columns and reopens reusable outputs" {
  let source = @jsontable.parse_delimited(
    "region,product,amount\r\nEast,Tea,10.5\r\nWest,Tea,7\r\nEast,Tea,4.5\r\nEast,Coffee,\r\nEast,Tea,\r\n東京,Coffee,-2\r\n",
  )
  let before = source.export_csv()
  let result = source.summarize(group_by=["region", "product"], measures=[
    { name: "orders", operation: CountRows, },
    { name: "revenue", operation: Sum("amount"), },
    { name: "average", operation: Mean("amount"), },
  ])
  assert_eq(result.columns, [
    "region", "product", "orders", "revenue", "average",
  ])
  assert_eq(result.text_rows(), [
    ["East", "Tea", "3", "15", "7.5"],
    ["West", "Tea", "1", "7", "7"],
    ["East", "Coffee", "1", "0", ""],
    ["東京", "Coffee", "1", "-2", "-2"],
  ])
  assert_eq(
    @csv.parse(result.export_csv()).rows,
    [result.columns] + result.text_rows(),
  )
  let json = @json.parse(result.export_json())
  guard json is Array(items) else { fail("Expected JSON array") }
  assert_true(
    items[0]
    is {
      "orders": Number(3, ..),
      "revenue": Number(15, ..),
      "average": Number(7.5, ..),
      ..
    },
  )
  assert_true(items[2] is { "average": Null, .. })
  let workbook = @xlsx.read(@opc.open(result.export_xlsx()))
  assert_true(workbook.sheets[0].cells.any(cell => cell.value == Number("7.5")))
  assert_true(
    workbook.sheets[0].cells.any(cell => cell.value == Text("東京")),
  )
  result.rows[0][0] = Text("Changed")
  result.columns[0] = "Changed"
  assert_eq(source.export_csv(), before)
}

///|
test "summary exact typed keys have no delimiter collisions or text coercion" {
  let source = @jsontable.parse(
    "[{\"a\":\"001\",\"b\":\"x|y\"},{\"a\":\"1\",\"b\":\"x|y\"},{\"a\":1,\"b\":\"x|y\"},{\"a\":true,\"b\":\"x|y\"},{\"a\":\"\",\"b\":\"x|y\"},{\"b\":\"x|y\"},{\"a\":\"001\",\"b\":\"x|y\"},{\"a\":\"001|x\",\"b\":\"y\"}]",
  )
  let result = source.summarize(group_by=["a", "b"], measures=[
    { name: "n", operation: CountRows, },
  ])
  assert_eq(result.rows.length(), 7)
  assert_eq(result.rows[0], [Text("001"), Text("x|y"), Number("2")])
  assert_eq(result.rows[2][0], Number("1"))
  assert_eq(result.rows[3][0], Boolean(true))
  assert_eq(result.rows[4][0], Text(""))
  assert_eq(result.rows[5][0], Empty)
  let tsv = @jsontable.parse_delimited(
    "key\tamount\nA\t1\na\t2\n A \t3\n",
    delimiter='\t',
  )
  assert_eq(
    tsv.summarize(group_by=["key"], measures=[
      { name: "n", operation: CountRows, },
    ]).rows.length(),
    3,
  )
}

///|
test "summary totals include empty input and handle missing numeric values" {
  let empty = @jsontable.parse_delimited("region,amount\n")
  let measures : Array[@jsontable.SummaryMeasure] = [
    { name: "n", operation: CountRows, },
    { name: "total", operation: Sum("amount"), },
    { name: "average", operation: Mean("amount"), },
  ]
  assert_eq(empty.summarize(group_by=[], measures~).text_rows(), [
    ["0", "0", ""],
  ])
  assert_eq(empty.summarize(group_by=["region"], measures~).rows, [])
  let rows = @jsontable.parse(
    "{\"amount\":5}\n{}\n{\"amount\":\" \"}\n{\"amount\":\" -2.5e1 \"}\n",
    jsonl=true,
  )
  assert_eq(rows.summarize(group_by=[], measures~).text_rows(), [
    ["4", "-20", "-10"],
  ])
}

///|
test "summary rejects malformed measures and input with useful coordinates" {
  let source = @jsontable.parse_delimited("key,amount\nA,12\nB,nope\n")
  let before = source.export_csv()
  assert_true(
    try
      source.summarize(group_by=["key"], measures=[
        { name: "total", operation: Sum("amount"), },
      ])
    catch {
      value => value is InvalidSummaryNumber(row=2, column="amount")
    } noraise {
      _ => false
    },
  )
  assert_eq(source.export_csv(), before)
  assert_true(
    try
      source.summarize(group_by=["missing"], measures=[
        { name: "n", operation: CountRows, },
      ])
    catch {
      value => value is UnknownSummaryColumn("missing")
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      source.summarize(group_by=["key", "key"], measures=[
        { name: "n", operation: CountRows, },
      ])
    catch {
      value => value is InvalidSummary(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try source.summarize(group_by=[], measures=[]) catch {
      value => value is InvalidSummary(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      source.summarize(group_by=["key"], measures=[
        { name: "key", operation: CountRows, },
      ])
    catch {
      value => value is InvalidSummary(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      source.summarize(group_by=[], measures=[
        { name: "x", operation: Sum("missing"), },
      ])
    catch {
      value => value is UnknownSummaryColumn("missing")
    } noraise {
      _ => false
    },
  )
  let ragged : @jsontable.Table = {
    columns: ["key", "amount"],
    rows: [[Text("A")]],
  }
  assert_true(
    try
      ragged.summarize(group_by=[], measures=[
        { name: "n", operation: CountRows, },
      ])
    catch {
      value => value is InvalidSummary(_)
    } noraise {
      _ => false
    },
  )
}

///|
test "summary numbers use finite JSON decimal syntax and compensated addition" {
  let measures : Array[@jsontable.SummaryMeasure] = [
    { name: "total", operation: Sum("amount"), },
  ]
  for
    value in [
      "1,000", "$12", "NaN", "Infinity", "true", "null", "01", "+1", "0x10", "1e400",
    ] {
    let source : @jsontable.Table = {
      columns: ["amount"],
      rows: [[Text(value)]],
    }
    assert_true(
      try source.summarize(group_by=[], measures~) catch {
        value => value is InvalidSummaryNumber(row=1, column="amount")
      } noraise {
        _ => false
      },
    )
  }
  let source = @jsontable.parse_delimited("amount\n1e16\n1\n-1e16\n")
  assert_eq(source.summarize(group_by=[], measures~).text_rows(), [["1"]])
  let overflow = @jsontable.parse_delimited("amount\n1e308\n1e308\n")
  assert_true(
    try overflow.summarize(group_by=[], measures~) catch {
      value => value is SummaryOverflow(row=2, column="total")
    } noraise {
      _ => false
    },
  )
  let formula : @jsontable.Table = {
    columns: ["amount"],
    rows: [[Formula(expression="1+1", cached=Some("2"))]],
  }
  assert_true(
    try formula.summarize(group_by=[], measures~) catch {
      value => value is InvalidSummaryNumber(row=1, column="amount")
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      formula.summarize(group_by=["amount"], measures=[
        { name: "n", operation: CountRows, },
      ])
    catch {
      value => value is UnsupportedGroupValue(row=1, column="amount")
    } noraise {
      _ => false
    },
  )
}

///|
test "JSON export retains text booleans numbers and rejects invented values" {
  let source = @jsontable.parse(
    "[{\"id\":\"001\",\"value\":5,\"active\":true,\"nested\":{\"x\":1}},{}]",
  )
  let result = @json.parse(source.export_json())
  guard result is Array(items) else { fail("Expected array") }
  assert_true(
    items[0]
    is {
      "id": String("001"),
      "value": Number(5, ..),
      "active": True,
      "nested": String("{\"x\":1}"),
      ..
    },
  )
  assert_true(items[1] is { "id": Null, "value": Null, .. })
  for
    cell in [
      @scene.Number("NaN"),
      Number("true"),
      Error("#VALUE!"),
      Formula(expression="1+1", cached=None),
    ] {
    let unsupported : @jsontable.Table = { columns: ["value"], rows: [[cell]], }
    assert_true(
      try unsupported.export_json() catch {
        value => value is Export(_)
      } noraise {
        _ => false
      },
    )
  }
  let duplicate : @jsontable.Table = {
    columns: ["x", "x"],
    rows: [[Empty, Empty]],
  }
  assert_true(
    try duplicate.export_json() catch {
      value => value is Export(_)
    } noraise {
      _ => false
    },
  )
}

///|
test "summary numeric group keys normalize equivalent spellings but retain text identifiers" {
  let table : @jsontable.Table = {
    columns: ["key"],
    rows: [
      [Number("1")],
      [Number("1.0")],
      [Text("1")],
      [Number("-0")],
      [Number("0")],
    ],
  }
  assert_eq(
    table
    .summarize(group_by=["key"], measures=[{ name: "n", operation: CountRows, }])
    .text_rows(),
    [["1", "2"], ["1", "1"], ["-0", "2"]],
  )
}

///|
test "summary resource boundaries report input and output size limits" {
  let measures : Array[@jsontable.SummaryMeasure] = [
    { name: "n", operation: CountRows, },
  ]
  let table : @jsontable.Table = {
    columns: ["key"],
    rows: Array::makei(10_000, i => [Text(i.to_string())]),
  }
  assert_eq(table.summarize(group_by=[], measures~).text_rows(), [["10000"]])
  let many_measures : Array[@jsontable.SummaryMeasure] = Array::makei(10, i => {
    name: "count_\{i}",
    operation: CountRows,
  })
  assert_true(
    try table.summarize(group_by=["key"], measures=many_measures) catch {
      value => value is InvalidSummary(_)
    } noraise {
      _ => false
    },
  )
  table.rows.push([Text("extra")])
  assert_true(
    try table.summarize(group_by=[], measures~) catch {
      value => value is InvalidSummary(_)
    } noraise {
      _ => false
    },
  )
  let wide : @jsontable.Table = {
    columns: Array::makei(257, i => "column_\{i}"),
    rows: [],
  }
  assert_true(
    try wide.summarize(group_by=[], measures~) catch {
      value => value is InvalidSummary(_)
    } noraise {
      _ => false
    },
  )
  let no_columns : @jsontable.Table = { columns: [], rows: [], }
  assert_eq(no_columns.summarize(group_by=[], measures~).text_rows(), [["0"]])
}

///|
test "summary turns enriched orders into regional totals and can be regrouped" {
  let orders = @jsontable.parse(
    "[{\"customer\":\"001\",\"amount\":40},{\"customer\":\"002\",\"amount\":15},{\"customer\":\"001\",\"amount\":10},{\"customer\":\"unknown\",\"amount\":5}]",
  )
  let customers = @jsontable.parse_delimited("id,region\n001,East\n002,West\n")
  let prepared = orders.lookup(
    customers,
    source_key="customer",
    lookup_key="id",
    columns=["region"],
    prefix="",
  )
  let regional = prepared.table.summarize(group_by=["region"], measures=[
    { name: "orders", operation: CountRows, },
    { name: "revenue", operation: Sum("amount"), },
  ])
  assert_eq(regional.text_rows(), [
    ["East", "2", "50"],
    ["West", "1", "15"],
    ["", "1", "5"],
  ])
  assert_eq(
    regional
    .summarize(group_by=[], measures=[
      { name: "orders", operation: Sum("orders"), },
      { name: "revenue", operation: Sum("revenue"), },
    ])
    .text_rows(),
    [["4", "70"]],
  )
  assert_eq(prepared.lookup_rows, [Some(1), Some(2), Some(1), None])
}
