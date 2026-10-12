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
  assert_eq(wide.rows[0][4], @scene.Empty)
  assert_eq(
    @jsontable.parse_delimited(wide.export_csv()).text_rows(),
    wide.text_rows(),
  )
  assert_eq(@jsontable.parse(wide.export_json(omit_empty=true)), wide)
  let cells = @xlsx.read(@opc.open(wide.export_xlsx())).sheets[0].cells
  assert_true(
    cells.any(cell => {
      cell.row == 2 && cell.column == 1 && cell.value == @scene.Text("002")
    }),
  )
  assert_true(
    cells.any(cell => {
      cell.row == 3 && cell.column == 5 && cell.value == @scene.Text("120")
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
    (try? source.pivot(id_columns=["id"], key_column="k", value_column="v"))
    is Err(@jsontable.DuplicatePivotCell(first_row=1, row=3, key="Jan")),
  )
  assert_eq(
    source
    .pivot(
      id_columns=["id"],
      key_column="k",
      value_column="v",
      duplicates=@jsontable.First,
    )
    .text_rows(),
    [["a", ""], ["b", "7"]],
  )
  assert_eq(
    source
    .pivot(
      id_columns=["id"],
      key_column="k",
      value_column="v",
      duplicates=@jsontable.Last,
    )
    .text_rows(),
    [["a", "10"], ["b", "7"]],
  )
  let missing = @jsontable.parse(
    (
      #|[{"id":"a","k":"Jan"},{"id":"a","k":"Jan","v":1}]
    ),
  )
  assert_true(
    (try? missing.pivot(id_columns=["id"], key_column="k", value_column="v"))
    is Err(@jsontable.DuplicatePivotCell(first_row=1, row=2, key="Jan")),
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
    [
      @scene.Text("001"),
      @scene.Number("0"),
      @scene.Boolean(false),
      @scene.Empty,
    ],
    [@scene.Text("002"), @scene.Text(""), @scene.Empty, @scene.Text("null")],
    [@scene.Text("003"), @scene.Empty, @scene.Empty, @scene.Empty],
  ])
  assert_eq(@jsontable.parse(wide.export_json(omit_empty=true)), wide)
  let cells = @xlsx.read(@opc.open(wide.export_xlsx())).sheets[0].cells
  assert_true(cells.any(cell => cell.value == @scene.Number("0")))
  assert_true(cells.any(cell => cell.value == @scene.Boolean(false)))
}

///|
test "pivot identifiers use exact typed and collision-free tuples" {
  let source : @jsontable.Table = {
    columns: ["a", "b", "k", "v"],
    rows: [
      [@scene.Empty, @scene.Text(""), @scene.Text("x"), @scene.Text("missing")],
      [@scene.Text(""), @scene.Text(""), @scene.Text("x"), @scene.Text("empty")],
      [
        @scene.Number("1"),
        @scene.Text(""),
        @scene.Text("x"),
        @scene.Text("number"),
      ],
      [@scene.Text("1"), @scene.Text(""), @scene.Text("x"), @scene.Text("text")],
      [
        @scene.Boolean(true),
        @scene.Text(""),
        @scene.Text("x"),
        @scene.Text("boolean"),
      ],
      [
        @scene.Text("a|b"),
        @scene.Text("c"),
        @scene.Text("x"),
        @scene.Text("first"),
      ],
      [
        @scene.Text("a"),
        @scene.Text("b|c"),
        @scene.Text("x"),
        @scene.Text("second"),
      ],
      [
        @scene.Number("1.0"),
        @scene.Text(""),
        @scene.Text("x"),
        @scene.Text("lexical"),
      ],
    ],
  }
  let wide = source.pivot(
    id_columns=["b", "a"],
    key_column="k",
    value_column="v",
  )
  assert_eq(wide.columns, ["b", "a", "x"])
  assert_eq(wide.rows.length(), 8)
  assert_eq(wide.rows[0][1], @scene.Empty)
  assert_eq(wide.rows[7][2], @scene.Text("lexical"))
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
  wide.rows[0][0] = @scene.Text("changed")
  wide.rows[0][1] = @scene.Text("changed")
  assert_eq(source.rows[0], [
    @scene.Text("a"),
    @scene.Text("x"),
    @scene.Text("1"),
  ])
  assert_eq(wide.rows[1][0], @scene.Text("b"))
  assert_eq(ids, ["id"])
}

///|
test "pivot rejects colliding output names and accepts an explicit prefix" {
  let source = @jsontable.parse_delimited("id,k,v\na,id,1\na, x ,2\n")
  assert_true(
    (try? source.pivot(id_columns=["id"], key_column="k", value_column="v"))
    is Err(@jsontable.InvalidPivot(_)),
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
      (try? source.pivot(id_columns=ids, key_column=key, value_column=value))
      is Err(@jsontable.UnknownPivotColumn("missing")),
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
      (try? source.pivot(id_columns=ids, key_column=key, value_column=value))
      is Err(@jsontable.InvalidPivot(_)),
    )
  }
}

///|
test "pivot requires nonempty text keys and valid rectangular input" {
  for
    key in [
      @scene.CellValue::Empty,
      @scene.CellValue::Text(""),
      @scene.Number("1"),
      @scene.Boolean(false),
    ] {
    let source : @jsontable.Table = {
      columns: ["k", "v"],
      rows: [[key, @scene.Text("v")]],
    }
    assert_true(
      (try? source.pivot(id_columns=[], key_column="k", value_column="v"))
      is Err(@jsontable.InvalidPivotKey(row=1, column="k")),
    )
  }
  for
    source in [
      @jsontable.Table::{ columns: ["k", "v"], rows: [[@scene.Text("x")]], },
      @jsontable.Table::{ columns: ["k", "k"], rows: [], },
      @jsontable.Table::{ columns: ["", "v"], rows: [], },
    ] {
    assert_true(
      (try? source.pivot(id_columns=[], key_column="k", value_column="v"))
      is Err(@jsontable.InvalidPivot(_)),
    )
  }
}

///|
test "pivot rejects selected formulas and errors even in discarded duplicate rows" {
  for
    unsupported in [
      @scene.Error("#VALUE!"),
      @scene.Formula(expression="A1+1", cached=Some("2")),
    ] {
    for selected in [0, 2] {
      let row : Array[@scene.CellValue] = [
        @scene.Text("a"),
        @scene.Text("x"),
        @scene.Text("1"),
      ]
      row[selected] = unsupported
      let source : @jsontable.Table = {
        columns: ["id", "k", "v"],
        rows: [[@scene.Text("a"), @scene.Text("x"), @scene.Text("1")], row],
      }
      assert_true(
        (try? source.pivot(
          id_columns=["id"],
          key_column="k",
          value_column="v",
          duplicates=@jsontable.First,
        ))
        is Err(@jsontable.UnsupportedPivotValue(..)),
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
    rows: Array::makei(255, i => {
      [@scene.Text("a"), @scene.Text("k\{i}"), @scene.Number("1")]
    }),
  }
  assert_eq(
    source.pivot(id_columns=["id"], key_column="k", value_column="v").columns.length(),
    256,
  )
  source.rows.push([
    @scene.Text("a"),
    @scene.Text("overflow"),
    @scene.Number("1"),
  ])
  assert_true(
    (try? source.pivot(id_columns=["id"], key_column="k", value_column="v"))
    is Err(@jsontable.InvalidPivot(_)),
  )
  let rows : Array[Array[@scene.CellValue]] = Array::makei(999, i => {
    [@scene.Text("id\{i}"), @scene.Text("k0"), @scene.Number("1")]
  })
  for i = 1; i < 99; i = i + 1 {
    rows.push([@scene.Text("id0"), @scene.Text("k\{i}"), @scene.Number("1")])
  }
  let at_limit : @jsontable.Table = { columns: ["id", "k", "v"], rows, }
  assert_eq(
    at_limit.pivot(id_columns=["id"], key_column="k", value_column="v").rows.length(),
    999,
  )
  rows.push([@scene.Text("id999"), @scene.Text("k0"), @scene.Number("1")])
  assert_true(
    (try? at_limit.pivot(id_columns=["id"], key_column="k", value_column="v"))
    is Err(@jsontable.InvalidPivot(_)),
  )
  ignore(rows.pop())
  rows.push([@scene.Text("id0"), @scene.Text("k99"), @scene.Number("1")])
  assert_true(
    (try? at_limit.pivot(id_columns=["id"], key_column="k", value_column="v"))
    is Err(@jsontable.InvalidPivot(_)),
  )
}

///|
test "pivot accepts 10000 input rows and rejects the next" {
  let source : @jsontable.Table = {
    columns: ["id", "k", "v"],
    rows: Array::makei(10_000, i => {
      [@scene.Number(i.to_string()), @scene.Text("x"), @scene.Empty]
    }),
  }
  assert_eq(
    source.pivot(id_columns=["id"], key_column="k", value_column="v").rows.length(),
    10_000,
  )
  source.rows.push([@scene.Number("10000"), @scene.Text("x"), @scene.Empty])
  assert_true(
    (try? source.pivot(id_columns=["id"], key_column="k", value_column="v"))
    is Err(@jsontable.InvalidPivot(_)),
  )
}
