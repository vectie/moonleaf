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
  assert_eq(result.rows[2][3], Empty)
  assert_eq(result.rows[3][2], Empty)
  let filtered = before.reconcile(
    after,
    key_columns=["id"],
    include_unchanged=false,
  )
  assert_eq(filtered.rows, result.rows[1:].to_owned())
  result.rows[0][0] = Text("mutated")
  result.columns[0] = "mutated"
  assert_eq(before.rows[0][0], Text("001"))
  assert_eq(before.columns[0], "id")
  assert_eq(after.columns[2], "id")
}

///|
test "reconcile composite keys are collision safe and caller ordered" {
  let before = @jsontable.parse(
    "[{\"a\":\"a|b\",\"b\":\"c\",\"v\":1},{\"a\":\"a\",\"b\":\"b|c\",\"v\":2},{\"a\":\"quote\\\"\",\"b\":\"\\n東京\",\"v\":3}]",
  )
  let result = before.reconcile(before, key_columns=["b", "a"])
  assert_eq(result.columns[0:2].to_owned(), ["b", "a"])
  assert_eq(result.rows.length(), 3)
  assert_true(result.rows.all(row => row[2] == Text("unchanged")))
}

///|
test "reconcile exact matching does not trim fold case or coerce identifiers" {
  let before = @jsontable.parse_delimited("id\n001\n1\n A \na\nA\n")
  let after = @jsontable.parse_delimited("id\nA\na\n A \n1\n001\n")
  let result = before.reconcile(after, key_columns=["id"])
  assert_eq(result.rows.length(), 5)
  assert_true(result.rows.all(row => row[1] == Text("unchanged")))
  assert_eq(result.rows[0][3], Number("5"))
}

///|
test "reconcile distinguishes scalar types representations and absent values" {
  let before : @jsontable.Table = {
    columns: ["id", "value"],
    rows: [
      [Text("missing"), Empty],
      [Text("typed"), Number("1")],
      [Text("representation"), Number("1")],
      [Text("boolean"), Boolean(false)],
      [Text("formula-text"), Text("=1+1")],
    ],
  }
  let after : @jsontable.Table = {
    columns: ["id", "value"],
    rows: [
      [Text("missing"), Text("")],
      [Text("typed"), Text("1")],
      [Text("representation"), Number("1.0")],
      [Text("boolean"), Boolean(false)],
      [Text("formula-text"), Text("=1+1")],
    ],
  }
  let result = before.reconcile(after, key_columns=["id"])
  assert_eq(result.rows.map(row => row[1]), [
    Text("changed"),
    Text("changed"),
    Text("changed"),
    Text("unchanged"),
    Text("unchanged"),
  ])
  assert_eq(result.rows[0][4], Empty)
  assert_eq(result.rows[0][5], Text(""))
  assert_eq(result.rows[1][4], Number("1"))
  assert_eq(result.rows[1][5], Text("1"))
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
  assert_true(cells.any(cell => cell.value == Text("001")))
  assert_true(cells.any(cell => cell.value == Boolean(false)))
  assert_true(cells.any(cell => cell.value == Boolean(true)))
  assert_true(cells.any(cell => cell.value == Number("0")))
  assert_true(cells.any(cell => cell.value == Text("=1+1")))
  assert_true(!cells.any(cell => cell.value is Formula(..)))
}

///|
test "reconcile duplicate keys identify side and one based rows" {
  let unique = @jsontable.parse_delimited("id,v\na,1\n")
  let duplicate = @jsontable.parse_delimited("id,v\nb,2\nb,3\n")
  try
    unique.reconcile(duplicate, key_columns=["id"], include_unchanged=false)
  catch {
    error =>
      assert_eq(error, DuplicateReconcileKey(side="after", first_row=1, row=2))
  } noraise {
    _ => fail("expected operation to fail")
  }
  try duplicate.reconcile(unique, key_columns=["id"]) catch {
    error =>
      assert_eq(error, DuplicateReconcileKey(side="before", first_row=1, row=2))
  } noraise {
    _ => fail("expected operation to fail")
  }
}

///|
test "reconcile refuses missing empty numeric boolean and partial composite keys" {
  let good : @jsontable.Table = {
    columns: ["a", "b"],
    rows: [[Text("x"), Text("y")]],
  }
  for value in [@scene.CellValue::Empty, Text(""), Number("1"), Boolean(true)] {
    let bad : @jsontable.Table = {
      columns: ["a", "b"],
      rows: [[Text("x"), value]],
    }
    try good.reconcile(bad, key_columns=["a", "b"]) catch {
      error =>
        assert_eq(error, InvalidReconcileKey(side="after", row=1, column="b"))
    } noraise {
      _ => fail("expected operation to fail")
    }
    try bad.reconcile(good, key_columns=["a", "b"]) catch {
      error =>
        assert_eq(error, InvalidReconcileKey(side="before", row=1, column="b"))
    } noraise {
      _ => fail("expected operation to fail")
    }
  }
}

///|
test "reconcile validates unsupported cells even if unchanged rows excluded" {
  for value in [@scene.Formula(expression="A1", cached=None), Error("#VALUE!")] {
    let bad : @jsontable.Table = {
      columns: ["id", "v"],
      rows: [[Text("x"), value]],
    }
    try bad.reconcile(bad, key_columns=["id"], include_unchanged=false) catch {
      error =>
        assert_eq(
          error,
          UnsupportedReconcileValue(side="before", row=1, column="v"),
        )
    } noraise {
      _ => fail("expected operation to fail")
    }
    let good = @jsontable.parse_delimited("id,v\nx,ok\n")
    try good.reconcile(bad, key_columns=["id"]) catch {
      error =>
        assert_eq(
          error,
          UnsupportedReconcileValue(side="after", row=1, column="v"),
        )
    } noraise {
      _ => fail("expected operation to fail")
    }
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
    assert_true(
      try good.reconcile(bad, key_columns=["id"]) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
    assert_true(
      try bad.reconcile(good, key_columns=["id"]) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  for keys in [[], ["absent"], ["id", "id"]] {
    assert_true(
      try good.reconcile(good, key_columns=keys) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  for name in ["_change", "_before_row", "_after_row"] {
    let collision : @jsontable.Table = { columns: [name], rows: [], }
    assert_true(
      try collision.reconcile(collision, key_columns=[name]) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let prefixed : @jsontable.Table = { columns: ["before.v", "v"], rows: [], }
  assert_true(
    try prefixed.reconcile(prefixed, key_columns=["before.v"]) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "reconcile handles header only snapshots and all key tables" {
  let empty = @jsontable.parse_delimited("id,v\n")
  assert_eq(empty.reconcile(empty, key_columns=["id"]).rows, [])
  let full = @jsontable.parse_delimited("id,v\nx,ok\n")
  assert_eq(empty.reconcile(full, key_columns=["id"]).rows[0][1], Text("added"))
  assert_eq(
    full.reconcile(empty, key_columns=["id"]).rows[0][1],
    Text("removed"),
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
    rows: Array::makei(10_000, i => [Text(i.to_string())]),
  }
  assert_eq(full.reconcile(full, key_columns=["id"]).rows.length(), 10_000)
  let other : @jsontable.Table = { columns: ["id"], rows: [[Text("extra")]], }
  assert_true(
    try full.reconcile(other, key_columns=["id"]) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  full.rows.push([Text("extra")])
  assert_true(
    try
      full.reconcile(full, key_columns=["id"], include_unchanged=false)
    catch {
      _ => true
    } noraise {
      _ => false
    },
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
  assert_true(
    try wide.reconcile(wide, key_columns=["0"]) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let cells : @jsontable.Table = {
    columns: Array::makei(10, i => i.to_string()),
    rows: Array::makei(9999, i => Array::make(10, Text(i.to_string()))),
  }
  assert_eq(
    cells.reconcile(cells, key_columns=["0"], include_unchanged=false).rows.length(),
    0,
  )
  assert_true(
    try cells.reconcile(cells, key_columns=["0"]) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  cells.rows.push(Array::make(10, Text("extra")))
  assert_true(
    try
      cells.reconcile(cells, key_columns=["0"], include_unchanged=false)
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}
