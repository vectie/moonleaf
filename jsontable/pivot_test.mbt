///|
test "long sales become a stable wide comparison and export cleanly" {
  let source = @jsontable.parse_delimited(
    "store,region,month,sales,note\n002,West,Feb,75,omit\n001,North,Jan,100,omit\n002,West,Jan,0,omit\n001,North,Mar,120,omit\n",
  )
  let wide = source.pivot(
    id_columns=["store", "region"],
    key_column="month",
    value_column="sales",
  )
  assert_eq(wide.columns, ["store", "region", "Feb", "Jan", "Mar"])
  assert_eq(wide.text_rows(), [
    ["002", "West", "75", "0", ""],
    ["001", "North", "", "100", "120"],
  ])
  assert_eq(wide.rows[0][4], Empty)
  assert_eq(
    @jsontable.parse_delimited(wide.export_csv()).text_rows(),
    wide.text_rows(),
  )
  assert_eq(@jsontable.parse(wide.export_json(omit_empty=true)), wide)
  let cells = @xlsx.read(@opc.open(wide.export_xlsx())).sheets[0].cells
  assert_true(
    cells.any(cell => {
      cell.row == 2 && cell.column == 1 && cell.value == Text("002")
    }),
  )
  assert_true(
    cells.any(cell => {
      cell.row == 3 && cell.column == 5 && cell.value == Text("120")
    }),
  )
  assert_eq(source.rows.length(), 4)
  assert_eq(source.columns, ["store", "region", "month", "sales", "note"])
}

///|
test "pivot duplicates reject by default and select first or last explicitly" {
  let source = @jsontable.parse_delimited(
    "id,k,v\na,Jan,\nb,Jan,7\na,Jan,9\na,Jan,10\n",
  )
  assert_true(
    try
      source.pivot(id_columns=["id"], key_column="k", value_column="v")
    catch {
      value => value is DuplicatePivotCell(first_row=1, row=3, key="Jan")
    } noraise {
      _ => false
    },
  )
  assert_eq(
    source
    .pivot(
      id_columns=["id"],
      key_column="k",
      value_column="v",
      duplicates=First,
    )
    .text_rows(),
    [["a", ""], ["b", "7"]],
  )
  assert_eq(
    source
    .pivot(id_columns=["id"], key_column="k", value_column="v", duplicates=Last)
    .text_rows(),
    [["a", "10"], ["b", "7"]],
  )
  let missing = @jsontable.parse(
    (
      #|[{"id":"a","k":"Jan"},{"id":"a","k":"Jan","v":1}]
    ),
  )
  assert_true(
    try
      missing.pivot(id_columns=["id"], key_column="k", value_column="v")
    catch {
      value => value is DuplicatePivotCell(first_row=1, row=2, key="Jan")
    } noraise {
      _ => false
    },
  )
}

///|
test "pivot preserves missing empty zero false null and Unicode values" {
  let source = @jsontable.parse(
    (
      #|[{"id":"001","k":"東京 🐈","v":0},{"id":"001","k":"enabled","v":false},{"id":"002","k":"東京 🐈","v":""},{"id":"002","k":"note","v":null},{"id":"003","k":"enabled"}]
    ),
  )
  let wide = source.pivot(id_columns=["id"], key_column="k", value_column="v")
  assert_eq(wide.rows, [
    [Text("001"), Number("0"), Boolean(false), Empty],
    [Text("002"), Text(""), Empty, Text("null")],
    [Text("003"), Empty, Empty, Empty],
  ])
  assert_eq(@jsontable.parse(wide.export_json(omit_empty=true)), wide)
  let cells = @xlsx.read(@opc.open(wide.export_xlsx())).sheets[0].cells
  assert_true(cells.any(cell => cell.value == Number("0")))
  assert_true(cells.any(cell => cell.value == Boolean(false)))
}

///|
test "pivot identifiers use exact typed and collision-free tuples" {
  let source : @jsontable.Table = {
    columns: ["a", "b", "k", "v"],
    rows: [
      [Empty, Text(""), Text("x"), Text("missing")],
      [Text(""), Text(""), Text("x"), Text("empty")],
      [Number("1"), Text(""), Text("x"), Text("number")],
      [Text("1"), Text(""), Text("x"), Text("text")],
      [Boolean(true), Text(""), Text("x"), Text("boolean")],
      [Text("a|b"), Text("c"), Text("x"), Text("first")],
      [Text("a"), Text("b|c"), Text("x"), Text("second")],
      [Number("1.0"), Text(""), Text("x"), Text("lexical")],
    ],
  }
  let wide = source.pivot(
    id_columns=["b", "a"],
    key_column="k",
    value_column="v",
  )
  assert_eq(wide.columns, ["b", "a", "x"])
  assert_eq(wide.rows.length(), 8)
  assert_eq(wide.rows[0][1], Empty)
  assert_eq(wide.rows[7][2], Text("lexical"))
}

///|
test "pivot empty input and no identifiers are explicit" {
  let empty = @jsontable.parse_delimited("id,k,v\n")
  let wide = empty.pivot(id_columns=["id"], key_column="k", value_column="v")
  assert_eq(wide.columns, ["id"])
  assert_eq(wide.rows.length(), 0)
  let source = @jsontable.parse_delimited("k,v\nb,2\na,1\n")
  let one = source.pivot(id_columns=[], key_column="k", value_column="v")
  assert_eq(one.columns, ["b", "a"])
  assert_eq(one.text_rows(), [["2", "1"]])
}

///|
test "pivot does not alias source identifiers or output rows" {
  let source = @jsontable.parse_delimited("id,k,v\na,x,1\nb,y,2\n")
  let ids = ["id"]
  let wide = source.pivot(id_columns=ids, key_column="k", value_column="v")
  wide.columns[0] = "changed"
  wide.rows[0][0] = Text("changed")
  wide.rows[0][1] = Text("changed")
  assert_eq(source.rows[0], [Text("a"), Text("x"), Text("1")])
  assert_eq(wide.rows[1][0], Text("b"))
  assert_eq(ids, ["id"])
}

///|
test "pivot rejects colliding output names and accepts an explicit prefix" {
  let source = @jsontable.parse_delimited("id,k,v\na,id,1\na, x ,2\n")
  assert_true(
    try
      source.pivot(id_columns=["id"], key_column="k", value_column="v")
    catch {
      value => value is InvalidPivot(_)
    } noraise {
      _ => false
    },
  )
  let wide = source.pivot(
    id_columns=["id"],
    key_column="k",
    value_column="v",
    prefix="value.",
  )
  assert_eq(wide.columns, ["id", "value.id", "value. x "])
  assert_eq(wide.text_rows(), [["a", "1", "2"]])
}

///|
test "pivot selections must be present unique and disjoint" {
  let source = @jsontable.parse_delimited("id,k,v\na,x,1\n")
  for
    (ids, key, value) in [
      (["missing"], "k", "v"),
      (["id"], "missing", "v"),
      (["id"], "k", "missing"),
    ] {
    assert_true(
      try
        source.pivot(id_columns=ids, key_column=key, value_column=value)
      catch {
        value => value is UnknownPivotColumn("missing")
      } noraise {
        _ => false
      },
    )
  }
  for
    (ids, key, value) in [
      (["id", "id"], "k", "v"),
      (["id"], "id", "v"),
      (["id"], "k", "id"),
      (["id"], "k", "k"),
    ] {
    assert_true(
      try
        source.pivot(id_columns=ids, key_column=key, value_column=value)
      catch {
        value => value is InvalidPivot(_)
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "pivot requires nonempty text keys and valid rectangular input" {
  for key in [@scene.CellValue::Empty, Text(""), Number("1"), Boolean(false)] {
    let source : @jsontable.Table = {
      columns: ["k", "v"],
      rows: [[key, Text("v")]],
    }
    assert_true(
      try source.pivot(id_columns=[], key_column="k", value_column="v") catch {
        value => value is InvalidPivotKey(row=1, column="k")
      } noraise {
        _ => false
      },
    )
  }
  for
    source in [
      @jsontable.Table::{ columns: ["k", "v"], rows: [[Text("x")]], },
      { columns: ["k", "k"], rows: [], },
      { columns: ["", "v"], rows: [], },
    ] {
    assert_true(
      try source.pivot(id_columns=[], key_column="k", value_column="v") catch {
        value => value is InvalidPivot(_)
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "pivot rejects selected formulas and errors even in discarded duplicate rows" {
  for
    unsupported in [
      @scene.Error("#VALUE!"),
      Formula(expression="A1+1", cached=Some("2")),
    ] {
    for selected in [0, 2] {
      let row : Array[@scene.CellValue] = [Text("a"), Text("x"), Text("1")]
      row[selected] = unsupported
      let source : @jsontable.Table = {
        columns: ["id", "k", "v"],
        rows: [[Text("a"), Text("x"), Text("1")], row],
      }
      assert_true(
        try
          source.pivot(
            id_columns=["id"],
            key_column="k",
            value_column="v",
            duplicates=First,
          )
        catch {
          value => value is UnsupportedPivotValue(..)
        } noraise {
          _ => false
        },
      )
    }
  }
}

///|
test "pivot reverses a selected unpivot without inventing omitted cells" {
  let source = @jsontable.parse(
    (
      #|[{"id":"a","Jan":0,"Feb":false},{"id":"b","Jan":"","Feb":3}]
    ),
  )
  let long = source.unpivot(id_columns=["id"], value_columns=["Jan", "Feb"])
  assert_eq(
    long.pivot(id_columns=["id"], key_column="variable", value_column="value"),
    source,
  )
}

///|
test "pivot bounds dynamic columns and both growth directions of output cells" {
  let source : @jsontable.Table = {
    columns: ["id", "k", "v"],
    rows: Array::makei(255, i => [Text("a"), Text("k\{i}"), Number("1")]),
  }
  assert_eq(
    source.pivot(id_columns=["id"], key_column="k", value_column="v").columns.length(),
    256,
  )
  source.rows.push([Text("a"), Text("overflow"), Number("1")])
  assert_true(
    try
      source.pivot(id_columns=["id"], key_column="k", value_column="v")
    catch {
      value => value is InvalidPivot(_)
    } noraise {
      _ => false
    },
  )
  let rows : Array[Array[@scene.CellValue]] = Array::makei(999, i => {
    [Text("id\{i}"), Text("k0"), Number("1")]
  })
  for i = 1; i < 99; i = i + 1 {
    rows.push([Text("id0"), Text("k\{i}"), Number("1")])
  }
  let at_limit : @jsontable.Table = { columns: ["id", "k", "v"], rows, }
  assert_eq(
    at_limit.pivot(id_columns=["id"], key_column="k", value_column="v").rows.length(),
    999,
  )
  rows.push([Text("id999"), Text("k0"), Number("1")])
  assert_true(
    try
      at_limit.pivot(id_columns=["id"], key_column="k", value_column="v")
    catch {
      value => value is InvalidPivot(_)
    } noraise {
      _ => false
    },
  )
  ignore(rows.pop())
  rows.push([Text("id0"), Text("k99"), Number("1")])
  assert_true(
    try
      at_limit.pivot(id_columns=["id"], key_column="k", value_column="v")
    catch {
      value => value is InvalidPivot(_)
    } noraise {
      _ => false
    },
  )
}

///|
test "pivot accepts 10000 input rows and rejects the next" {
  let source : @jsontable.Table = {
    columns: ["id", "k", "v"],
    rows: Array::makei(10_000, i => [Number(i.to_string()), Text("x"), Empty]),
  }
  assert_eq(
    source.pivot(id_columns=["id"], key_column="k", value_column="v").rows.length(),
    10_000,
  )
  source.rows.push([Number("10000"), Text("x"), Empty])
  assert_true(
    try
      source.pivot(id_columns=["id"], key_column="k", value_column="v")
    catch {
      value => value is InvalidPivot(_)
    } noraise {
      _ => false
    },
  )
}
