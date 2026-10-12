///|
test "consolidation selects whole first and last rows with a complete disposition report" {
  let table = @jsontable.parse_delimited(
    "id,part,value\n001,A,old\n002,A,unique\n001,A,new\n001,B,other\n001,A,newest\n",
  )
  let first = table.consolidate(
    key_columns=["id", "part"],
    retention=@jsontable.KeepFirst,
  )
  let last = table.consolidate(
    key_columns=["id", "part"],
    retention=@jsontable.KeepLast,
  )
  assert_eq(first.kept.rows, [table.rows[0], table.rows[1], table.rows[3]])
  assert_eq(last.kept.rows, [table.rows[1], table.rows[3], table.rows[4]])
  assert_eq(first.report.columns, [
    "id", "part", "value", "_input_row", "_disposition", "_kept_input_row", "_group_size",
  ])
  assert_eq(first.report.text_rows(), [
    ["001", "A", "old", "1", "kept", "1", "3"],
    ["002", "A", "unique", "2", "unique", "2", "1"],
    ["001", "A", "new", "3", "discarded", "1", "3"],
    ["001", "B", "other", "4", "unique", "4", "1"],
    ["001", "A", "newest", "5", "discarded", "1", "3"],
  ])
  assert_eq(last.report.text_rows(), [
    ["001", "A", "old", "1", "discarded", "5", "3"],
    ["002", "A", "unique", "2", "unique", "2", "1"],
    ["001", "A", "new", "3", "discarded", "5", "3"],
    ["001", "B", "other", "4", "unique", "4", "1"],
    ["001", "A", "newest", "5", "kept", "5", "3"],
  ])
  first.kept.rows[0][0] = @scene.Text("edited")
  first.kept.columns[0] = "edited"
  first.report.rows[0][1] = @scene.Text("edited")
  first.report.columns[1] = "edited"
  assert_eq(table.columns, ["id", "part", "value"])
  assert_eq(table.rows[0], [
    @scene.Text("001"),
    @scene.Text("A"),
    @scene.Text("old"),
  ])
  assert_eq(first.report.rows[0][0], @scene.Text("001"))
  assert_eq(first.kept.rows[0][1], @scene.Text("A"))
}

///|
test "consolidation composite identities resist separator quote unicode and newline collisions" {
  let table : @jsontable.Table = {
    columns: ["a", "b"],
    rows: [
      [@scene.Text("a|b"), @scene.Text("c")],
      [@scene.Text("a"), @scene.Text("b|c")],
      [@scene.Text("\""), @scene.Text("\n東京")],
      [@scene.Text("\""), @scene.Text("\n東京")],
      [@scene.Text("é"), @scene.Text("x")],
      [@scene.Text("é"), @scene.Text("x")],
    ],
  }
  let result = table.consolidate(
    key_columns=["b", "a"],
    retention=@jsontable.KeepLast,
  )
  assert_eq(result.kept.rows, [
    table.rows[0],
    table.rows[1],
    table.rows[3],
    table.rows[4],
    table.rows[5],
  ])
  assert_eq(result.report.text_rows().map(row => row[4]), [
    "1", "2", "4", "4", "5", "6",
  ])
}

///|
test "consolidation does not infer numeric case or trimmed identities" {
  let table = @jsontable.parse_delimited("id\n001\n1\n A \na\nA\n \n")
  for retention in [@jsontable.KeepFirst, @jsontable.KeepLast] {
    let result = table.consolidate(key_columns=["id"], retention~)
    assert_eq(result.kept, table)
    assert_true(result.report.rows.all(row => row[2] == @scene.Text("unique")))
  }
}

///|
test "consolidation preserves union source provenance complete scalar values and missing cells" {
  let one = @jsontable.parse(
    "[{\"id\":\"001\",\"note\":\"=1+1\",\"n\":1.0,\"active\":false}]",
  )
  let two = @jsontable.parse(
    "[{\"active\":true,\"id\":\"001\",\"note\":\"\",\"extra\":\"new\"}]",
  )
  let stacked = @jsontable.stack(
    [one, two],
    sources=["older", "newer"],
    mode=@jsontable.UnionHeaders,
  )
  let first = stacked.consolidate(
    key_columns=["id"],
    retention=@jsontable.KeepFirst,
  )
  let last = stacked.consolidate(
    key_columns=["id"],
    retention=@jsontable.KeepLast,
  )
  assert_eq(first.kept.rows, [stacked.rows[0]])
  assert_eq(last.kept.rows, [stacked.rows[1]])
  assert_eq(first.kept.rows[0][4], @scene.Empty)
  assert_eq(last.kept.rows[0][2], @scene.Empty)
  assert_eq(last.kept.rows[0][1], @scene.Text(""))
  for i, row in first.report.rows {
    assert_eq(row[0:7].to_array(), stacked.rows[i])
    assert_eq(row[7], @scene.Number((i + 1).to_string()))
  }
}

///|
test "consolidation exports both tables as CSV JSON and typed XLSX" {
  let table = @jsontable.parse(
    "[{\"id\":\"001\",\"note\":\"=1+1\",\"n\":12,\"active\":false},{\"id\":\"001\",\"note\":\"discarded\",\"n\":13,\"active\":true}]",
  )
  let result = table.consolidate(
    key_columns=["id"],
    retention=@jsontable.KeepFirst,
  )
  for output in [result.kept, result.report] {
    assert_eq(@jsontable.parse(output.export_json(omit_empty=true)), output)
    assert_eq(
      @jsontable.parse_delimited(output.export_csv()).text_rows(),
      output.text_rows(),
    )
    let cells = @xlsx.read(@opc.open(output.export_xlsx())).sheets[0].cells
    assert_true(cells.any(cell => cell.value == @scene.Text("=1+1")))
    assert_true(cells.any(cell => cell.value == @scene.Text("001")))
    assert_true(cells.any(cell => cell.value == @scene.Number("12")))
    assert_true(cells.any(cell => cell.value == @scene.Boolean(false)))
    assert_true(!cells.any(cell => cell.value is @scene.Formula(..)))
  }
}

///|
test "consolidation rejects invalid keys in all rows even a row that would be discarded" {
  for
    value in [
      @scene.CellValue::Empty,
      @scene.CellValue::Text(""),
      @scene.Number("1"),
      @scene.Boolean(true),
    ] {
    let table : @jsontable.Table = {
      columns: ["a", "b"],
      rows: [[@scene.Text("x"), @scene.Text("good")], [@scene.Text("x"), value]],
    }
    for retention in [@jsontable.KeepFirst, @jsontable.KeepLast] {
      assert_eq(
        try? table.consolidate(key_columns=["a", "b"], retention~),
        Err(@jsontable.InvalidConsolidateKey(row=2, column="b")),
      )
    }
  }
}

///|
test "consolidation rejects formulas and errors in discarded values" {
  for
    value in [
      @scene.Formula(expression="A1", cached=None),
      @scene.Error("#VALUE!"),
      @scene.Number("NaN"),
      @scene.Number("1e400"),
      @scene.Number("01"),
      @scene.Number("true"),
    ] {
    let table : @jsontable.Table = {
      columns: ["id", "v"],
      rows: [[@scene.Text("x"), @scene.Text("good")], [@scene.Text("x"), value]],
    }
    assert_eq(
      try? table.consolidate(key_columns=["id"], retention=@jsontable.KeepFirst),
      Err(@jsontable.UnsupportedConsolidateValue(row=2, column="v")),
    )
  }
}

///|
test "consolidation rejects malformed shapes unknown duplicate empty keys and report collisions" {
  let bads : Array[@jsontable.Table] = [
    { columns: [], rows: [], },
    { columns: ["id", "id"], rows: [], },
    { columns: ["id", ""], rows: [], },
    { columns: ["id"], rows: [[]], },
  ]
  for table in bads {
    assert_true(
      (try? table.consolidate(
        key_columns=["id"],
        retention=@jsontable.KeepFirst,
      ))
      is Err(_),
    )
  }
  let table = @jsontable.parse_delimited("id,v\n")
  for keys in [[], [""], ["absent"], ["id", "id"]] {
    assert_true(
      (try? table.consolidate(key_columns=keys, retention=@jsontable.KeepFirst))
      is Err(_),
    )
  }
  for name in ["_input_row", "_disposition", "_kept_input_row", "_group_size"] {
    let table : @jsontable.Table = { columns: ["id", name], rows: [], }
    assert_true(
      (try? table.consolidate(
        key_columns=["id"],
        retention=@jsontable.KeepFirst,
      ))
      is Err(_),
    )
  }
}

///|
test "consolidation header only all duplicate and all key tables are deterministic" {
  let empty = @jsontable.parse_delimited("id\n")
  let result = empty.consolidate(
    key_columns=["id"],
    retention=@jsontable.KeepLast,
  )
  assert_eq(result.kept, empty)
  assert_eq(result.report.columns.length(), 5)
  assert_eq(result.report.rows, [])
  let duplicate = @jsontable.parse_delimited("id\nx\nx\nx\n")
  let result = duplicate.consolidate(
    key_columns=["id"],
    retention=@jsontable.KeepLast,
  )
  assert_eq(result.kept.text_rows(), [["x"]])
  assert_eq(result.report.text_rows(), [
    ["x", "1", "discarded", "3", "3"],
    ["x", "2", "discarded", "3", "3"],
    ["x", "3", "kept", "3", "3"],
  ])
}

///|
test "consolidation enforces row column key and complete report cell limits" {
  let tall : @jsontable.Table = {
    columns: ["id"],
    rows: Array::makei(10_000, i => [@scene.Text(i.to_string())]),
  }
  assert_eq(
    tall.consolidate(key_columns=["id"], retention=@jsontable.KeepFirst).kept.rows.length(),
    10_000,
  )
  tall.rows.push([@scene.Text("over")])
  assert_true(
    (try? tall.consolidate(key_columns=["id"], retention=@jsontable.KeepFirst))
    is Err(_),
  )
  let wide : @jsontable.Table = {
    columns: Array::makei(252, i => i.to_string()),
    rows: [],
  }
  assert_eq(
    wide.consolidate(key_columns=["0"], retention=@jsontable.KeepFirst).report.columns.length(),
    256,
  )
  assert_eq(
    wide.consolidate(
      key_columns=wide.columns[0:32].to_array(),
      retention=@jsontable.KeepFirst,
    ).kept,
    wide,
  )
  assert_true(
    (try? wide.consolidate(
      key_columns=wide.columns[0:33].to_array(),
      retention=@jsontable.KeepFirst,
    ))
    is Err(_),
  )
  wide.columns.push("over")
  assert_true(
    (try? wide.consolidate(key_columns=["0"], retention=@jsontable.KeepFirst))
    is Err(_),
  )
  let cells : @jsontable.Table = {
    columns: ["id", "v", "w", "x", "y", "z"],
    rows: Array::makei(9999, _ => Array::make(6, @scene.Text("same"))),
  }
  assert_eq(
    cells.consolidate(key_columns=["id"], retention=@jsontable.KeepFirst).report.rows.length(),
    9999,
  )
  cells.rows.push(Array::make(6, @scene.Text("same")))
  assert_true(
    (try? cells.consolidate(key_columns=["id"], retention=@jsontable.KeepFirst))
    is Err(_),
  )
}
