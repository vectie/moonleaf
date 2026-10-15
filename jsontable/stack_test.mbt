///|
test "stack aligns reordered headers and retains copies provenance and types" {
  let a = @jsontable.parse_delimited("id,value\n001,\n")
  let b = @jsontable.parse(
    "[{\"value\":false,\"id\":\"東京\"},{\"id\":\"003\",\"value\":0}]",
  )
  let result = @jsontable.stack(
    [a, b],
    sources=["csv", "json"],
    mode=StrictHeaders,
  )
  assert_eq(result.columns, ["id", "value", "_source", "_source_row"])
  assert_eq(result.rows[0], [Text("001"), Text(""), Text("csv"), Number("1")])
  assert_eq(result.rows[1], [
    Text("東京"),
    Boolean(false),
    Text("json"),
    Number("1"),
  ])
  assert_eq(result.rows[2][1], Number("0"))
  assert_eq(@jsontable.parse(result.export_json(omit_empty=true)), result)
  let workbook = @xlsx.read(@opc.open(result.export_xlsx()))
  assert_true(
    workbook.sheets[0].cells.any(cell => cell.value == Boolean(false)),
  )
  result.rows[0][0] = Text("changed")
  assert_eq(a.rows[0][0], Text("001"))
}

///|
test "union retains missing versus empty and first seen header order" {
  let a = @jsontable.parse_delimited("id,amount\n001,\n")
  let b = @jsontable.parse("[{\"id\":\"002\",\"active\":false}]")
  let result = @jsontable.stack([a, b], sources=["a", "b"], mode=UnionHeaders)
  assert_eq(result.columns, ["id", "amount", "active", "_source", "_source_row"])
  assert_eq(result.rows[0][1], Text(""))
  assert_eq(result.rows[0][2], Empty)
  assert_eq(result.rows[1][1], Empty)
  let reopened = @jsontable.parse(result.export_json(omit_empty=true))
  assert_eq(reopened.columns, [
    "id", "amount", "_source", "_source_row", "active",
  ])
  assert_eq(reopened.rows[0][1], Text(""))
  assert_eq(reopened.rows[1][1], Empty)
  assert_eq(reopened.rows[1][4], Boolean(false))
  assert_true(
    try @jsontable.stack([a, b], sources=["a", "b"], mode=StrictHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "stack rejects ambiguity unsupported cells and bad shapes" {
  let a = @jsontable.parse_delimited("id\n001\n")
  assert_true(
    try @jsontable.stack([], sources=[], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @jsontable.stack([a], sources=[], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @jsontable.stack([a, a], sources=["a", "a"], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @jsontable.stack(
        [a],
        sources=["a"],
        mode=UnionHeaders,
        source_column="id",
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let ragged : @jsontable.Table = { columns: ["x"], rows: [[]], }
  assert_true(
    try @jsontable.stack([ragged], sources=["a"], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let formula : @jsontable.Table = {
    columns: ["x"],
    rows: [[Formula(expression="A1", cached=None)]],
  }
  assert_true(
    try @jsontable.stack([formula], sources=["a"], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "stack bounds and header only sources" {
  let empty = @jsontable.parse_delimited("id,value\n")
  let result = @jsontable.stack([empty], sources=["a"], mode=StrictHeaders)
  assert_eq(result.rows.length(), 0)
  assert_eq(result.columns, ["id", "value", "_source", "_source_row"])
  let large : @jsontable.Table = {
    columns: ["id"],
    rows: Array::makei(10_000, _ => [Text("x")]),
  }
  assert_eq(
    @jsontable.stack([large], sources=["a"], mode=StrictHeaders).rows.length(),
    10_000,
  )
  large.rows.push([Text("x")])
  assert_true(
    try @jsontable.stack([large], sources=["a"], mode=StrictHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "stack refuses duplicate headers empty labels error cells and strict omissions" {
  let a = @jsontable.parse_delimited("id,value\n001,\n")
  let b = @jsontable.parse_delimited("id\n002\n")
  assert_true(
    try @jsontable.stack([a, b], sources=["a", "b"], mode=StrictHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @jsontable.stack([a], sources=[""], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @jsontable.stack(
        [a],
        sources=["a"],
        mode=UnionHeaders,
        source_column="x",
        row_column="x",
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let duplicate : @jsontable.Table = { columns: ["x", "x"], rows: [], }
  assert_true(
    try @jsontable.stack([duplicate], sources=["a"], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let error : @jsontable.Table = { columns: ["x"], rows: [[Error("#VALUE!")]], }
  assert_true(
    try @jsontable.stack([error], sources=["a"], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let collision = @jsontable.parse_delimited("_source\na\n")
  assert_true(
    try @jsontable.stack([collision], sources=["a"], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_eq(
    @jsontable.stack(
      [collision],
      sources=["a"],
      mode=UnionHeaders,
      source_column="file",
    ).columns,
    ["_source", "file", "_source_row"],
  )
}

///|
test "stack enforces combined source column and cell budgets" {
  let a = @jsontable.parse_delimited("id\n001\n")
  assert_true(
    try
      @jsontable.stack(
        Array::make(65, a),
        sources=Array::makei(65, i => i.to_string()),
        mode=UnionHeaders,
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let wide : @jsontable.Table = {
    columns: Array::makei(255, i => i.to_string()),
    rows: [],
  }
  assert_true(
    try @jsontable.stack([wide], sources=["a"], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let cells : @jsontable.Table = {
    columns: Array::makei(8, i => i.to_string()),
    rows: Array::makei(10_000, _ => Array::make(8, Empty)),
  }
  assert_true(
    try @jsontable.stack([cells], sources=["a"], mode=UnionHeaders) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}
