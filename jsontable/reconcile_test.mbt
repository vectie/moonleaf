///|
test "reconcile classifies four outcomes aligns columns and preserves provenance" {
  let before = @jsontable.parse_delimited(
    "id,region,amount\n001,北,10\n002,南,20\n003,東,30\n",
  )
  let after = @jsontable.parse_delimited(
    "amount,region,id\n25,南,002\n10,北,001\n40,西,004\n",
  )
  let result = before.reconcile(after, key_columns=["id"])
  assert_eq(result.columns, [
    "id", "_change", "_before_row", "_after_row", "before.region", "after.region",
    "before.amount", "after.amount",
  ])
  assert_eq(result.text_rows(), [
    ["001", "unchanged", "1", "2", "北", "北", "10", "10"],
    ["002", "changed", "2", "1", "南", "南", "20", "25"],
    ["003", "removed", "3", "", "東", "", "30", ""],
    ["004", "added", "", "3", "", "西", "", "40"],
  ])
  assert_eq(result.rows[2][3], @scene.Empty)
  assert_eq(result.rows[3][2], @scene.Empty)
  let filtered = before.reconcile(
    after,
    key_columns=["id"],
    include_unchanged=false,
  )
  assert_eq(filtered.rows, result.rows[1:].to_array())
  result.rows[0][0] = @scene.Text("mutated")
  result.columns[0] = "mutated"
  assert_eq(before.rows[0][0], @scene.Text("001"))
  assert_eq(before.columns[0], "id")
  assert_eq(after.columns[2], "id")
}

///|
test "reconcile composite keys are collision safe and caller ordered" {
  let before = @jsontable.parse(
    "[{\"a\":\"a|b\",\"b\":\"c\",\"v\":1},{\"a\":\"a\",\"b\":\"b|c\",\"v\":2},{\"a\":\"quote\\\"\",\"b\":\"\\n東京\",\"v\":3}]",
  )
  let result = before.reconcile(before, key_columns=["b", "a"])
  assert_eq(result.columns[0:2].to_array(), ["b", "a"])
  assert_eq(result.rows.length(), 3)
  assert_true(result.rows.all(row => row[2] == @scene.Text("unchanged")))
}

///|
test "reconcile exact matching does not trim fold case or coerce identifiers" {
  let before = @jsontable.parse_delimited("id\n001\n1\n A \na\nA\n")
  let after = @jsontable.parse_delimited("id\nA\na\n A \n1\n001\n")
  let result = before.reconcile(after, key_columns=["id"])
  assert_eq(result.rows.length(), 5)
  assert_true(result.rows.all(row => row[1] == @scene.Text("unchanged")))
  assert_eq(result.rows[0][3], @scene.Number("5"))
}

///|
test "reconcile distinguishes scalar types representations and absent values" {
  let before : @jsontable.Table = {
    columns: ["id", "value"],
    rows: [
      [@scene.Text("missing"), @scene.Empty],
      [@scene.Text("typed"), @scene.Number("1")],
      [@scene.Text("representation"), @scene.Number("1")],
      [@scene.Text("boolean"), @scene.Boolean(false)],
      [@scene.Text("formula-text"), @scene.Text("=1+1")],
    ],
  }
  let after : @jsontable.Table = {
    columns: ["id", "value"],
    rows: [
      [@scene.Text("missing"), @scene.Text("")],
      [@scene.Text("typed"), @scene.Text("1")],
      [@scene.Text("representation"), @scene.Number("1.0")],
      [@scene.Text("boolean"), @scene.Boolean(false)],
      [@scene.Text("formula-text"), @scene.Text("=1+1")],
    ],
  }
  let result = before.reconcile(after, key_columns=["id"])
  assert_eq(result.rows.map(row => row[1]), [
    @scene.Text("changed"),
    @scene.Text("changed"),
    @scene.Text("changed"),
    @scene.Text("unchanged"),
    @scene.Text("unchanged"),
  ])
  assert_eq(result.rows[0][4], @scene.Empty)
  assert_eq(result.rows[0][5], @scene.Text(""))
  assert_eq(result.rows[1][4], @scene.Number("1"))
  assert_eq(result.rows[1][5], @scene.Text("1"))
}

///|
test "reconcile exports supported JSON CSV and typed XLSX" {
  let before = @jsontable.parse(
    "[{\"id\":\"001\",\"active\":false,\"amount\":0,\"note\":\"=1+1\"}]",
  )
  let after = @jsontable.parse(
    "[{\"id\":\"001\",\"active\":true,\"amount\":12,\"note\":\"=1+1\"}]",
  )
  let result = before.reconcile(after, key_columns=["id"])
  assert_eq(@jsontable.parse(result.export_json(omit_empty=true)), result)
  assert_eq(
    @jsontable.parse_delimited(result.export_csv()).text_rows(),
    result.text_rows(),
  )
  let workbook = @xlsx.read(@opc.open(result.export_xlsx()))
  let cells = workbook.sheets[0].cells
  assert_true(cells.any(cell => cell.value == @scene.Text("001")))
  assert_true(cells.any(cell => cell.value == @scene.Boolean(false)))
  assert_true(cells.any(cell => cell.value == @scene.Boolean(true)))
  assert_true(cells.any(cell => cell.value == @scene.Number("0")))
  assert_true(cells.any(cell => cell.value == @scene.Text("=1+1")))
  assert_true(!cells.any(cell => cell.value is @scene.Formula(..)))
}

///|
test "reconcile duplicate keys identify side and one based rows" {
  let unique = @jsontable.parse_delimited("id,v\na,1\n")
  let duplicate = @jsontable.parse_delimited("id,v\nb,2\nb,3\n")
  assert_eq(
    try? unique.reconcile(
      duplicate,
      key_columns=["id"],
      include_unchanged=false,
    ),
    Err(@jsontable.DuplicateReconcileKey(side="after", first_row=1, row=2)),
  )
  assert_eq(
    try? duplicate.reconcile(unique, key_columns=["id"]),
    Err(@jsontable.DuplicateReconcileKey(side="before", first_row=1, row=2)),
  )
}

///|
test "reconcile refuses missing empty numeric boolean and partial composite keys" {
  let good : @jsontable.Table = {
    columns: ["a", "b"],
    rows: [[@scene.Text("x"), @scene.Text("y")]],
  }
  for
    value in [
      @scene.CellValue::Empty,
      @scene.CellValue::Text(""),
      @scene.Number("1"),
      @scene.Boolean(true),
    ] {
    let bad : @jsontable.Table = {
      columns: ["a", "b"],
      rows: [[@scene.Text("x"), value]],
    }
    assert_eq(
      try? good.reconcile(bad, key_columns=["a", "b"]),
      Err(@jsontable.InvalidReconcileKey(side="after", row=1, column="b")),
    )
    assert_eq(
      try? bad.reconcile(good, key_columns=["a", "b"]),
      Err(@jsontable.InvalidReconcileKey(side="before", row=1, column="b")),
    )
  }
}

///|
test "reconcile validates unsupported cells even if unchanged rows excluded" {
  for
    value in [
      @scene.Formula(expression="A1", cached=None),
      @scene.Error("#VALUE!"),
    ] {
    let bad : @jsontable.Table = {
      columns: ["id", "v"],
      rows: [[@scene.Text("x"), value]],
    }
    assert_eq(
      try? bad.reconcile(bad, key_columns=["id"], include_unchanged=false),
      Err(
        @jsontable.UnsupportedReconcileValue(side="before", row=1, column="v"),
      ),
    )
    let good = @jsontable.parse_delimited("id,v\nx,ok\n")
    assert_eq(
      try? good.reconcile(bad, key_columns=["id"]),
      Err(@jsontable.UnsupportedReconcileValue(side="after", row=1, column="v")),
    )
  }
}

///|
test "reconcile refuses ambiguous schemas invalid key lists and collisions" {
  let good = @jsontable.parse_delimited("id,v\nx,ok\n")
  let bads : Array[@jsontable.Table] = [
    { columns: [], rows: [], },
    { columns: ["id", "id"], rows: [], },
    { columns: ["id", ""], rows: [], },
    { columns: ["id", "v"], rows: [[]], },
    { columns: ["id"], rows: [], },
    { columns: ["id", "different"], rows: [], },
  ]
  for bad in bads {
    assert_true((try? good.reconcile(bad, key_columns=["id"])) is Err(_))
    assert_true((try? bad.reconcile(good, key_columns=["id"])) is Err(_))
  }
  for keys in [[], ["absent"], ["id", "id"]] {
    assert_true((try? good.reconcile(good, key_columns=keys)) is Err(_))
  }
  for name in ["_change", "_before_row", "_after_row"] {
    let collision : @jsontable.Table = { columns: [name], rows: [], }
    assert_true(
      (try? collision.reconcile(collision, key_columns=[name])) is Err(_),
    )
  }
  let prefixed : @jsontable.Table = { columns: ["before.v", "v"], rows: [], }
  assert_true(
    (try? prefixed.reconcile(prefixed, key_columns=["before.v"])) is Err(_),
  )
}

///|
test "reconcile handles header only snapshots and all key tables" {
  let empty = @jsontable.parse_delimited("id,v\n")
  assert_eq(empty.reconcile(empty, key_columns=["id"]).rows, [])
  let full = @jsontable.parse_delimited("id,v\nx,ok\n")
  assert_eq(
    empty.reconcile(full, key_columns=["id"]).rows[0][1],
    @scene.Text("added"),
  )
  assert_eq(
    full.reconcile(empty, key_columns=["id"]).rows[0][1],
    @scene.Text("removed"),
  )
  let keys = @jsontable.parse_delimited("id\nx\n")
  assert_eq(keys.reconcile(keys, key_columns=["id"]).columns, [
    "id", "_change", "_before_row", "_after_row",
  ])
  assert_eq(
    keys.reconcile(keys, key_columns=["id"], include_unchanged=false).rows,
    [],
  )
}

///|
test "reconcile enforces row budgets after joining and at input boundary" {
  let full : @jsontable.Table = {
    columns: ["id"],
    rows: Array::makei(10_000, i => [@scene.Text(i.to_string())]),
  }
  assert_eq(full.reconcile(full, key_columns=["id"]).rows.length(), 10_000)
  let other : @jsontable.Table = {
    columns: ["id"],
    rows: [[@scene.Text("extra")]],
  }
  assert_true((try? full.reconcile(other, key_columns=["id"])) is Err(_))
  full.rows.push([@scene.Text("extra")])
  assert_true(
    (try? full.reconcile(full, key_columns=["id"], include_unchanged=false))
    is Err(_),
  )
}

///|
test "reconcile enforces paired output column and input output cell limits" {
  let wide : @jsontable.Table = {
    columns: Array::makei(127, i => i.to_string()),
    rows: [],
  }
  assert_eq(wide.reconcile(wide, key_columns=["0"]).columns.length(), 256)
  wide.columns.push("127")
  assert_true((try? wide.reconcile(wide, key_columns=["0"])) is Err(_))
  let cells : @jsontable.Table = {
    columns: Array::makei(10, i => i.to_string()),
    rows: Array::makei(9999, i => Array::make(10, @scene.Text(i.to_string()))),
  }
  assert_eq(
    cells.reconcile(cells, key_columns=["0"], include_unchanged=false).rows.length(),
    0,
  )
  assert_true((try? cells.reconcile(cells, key_columns=["0"])) is Err(_))
  cells.rows.push(Array::make(10, @scene.Text("extra")))
  assert_true(
    (try? cells.reconcile(cells, key_columns=["0"], include_unchanged=false))
    is Err(_),
  )
}
