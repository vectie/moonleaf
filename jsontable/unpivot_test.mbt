///|
test "wide sales become reusable rows and monthly totals" {
  let source = @jsontable.parse_delimited(
    "store,region,Jan,Feb,Mar\n001,North,100,120,\n002,West,0,75,80\n003,North,50,,-10\n",
  )
  let result = source.unpivot(
    id_columns=["store", "region"],
    value_columns=["Jan", "Feb", "Mar"],
    names_to="month",
    values_to="sales",
    drop_empty=true,
  )
  assert_eq(result.columns, ["store", "region", "month", "sales"])
  assert_eq(result.text_rows(), [
    ["001", "North", "Jan", "100"],
    ["001", "North", "Feb", "120"],
    ["002", "West", "Jan", "0"],
    ["002", "West", "Feb", "75"],
    ["002", "West", "Mar", "80"],
    ["003", "North", "Jan", "50"],
    ["003", "North", "Mar", "-10"],
  ])
  let totals = result.summarize(group_by=["month"], measures=[
    { name: "reported_stores", operation: CountRows, },
    { name: "total", operation: Sum("sales"), },
  ])
  assert_eq(totals.text_rows(), [
    ["Jan", "3", "150"],
    ["Feb", "2", "195"],
    ["Mar", "2", "70"],
  ])
  assert_eq(@jsontable.parse_delimited(result.export_csv()), result)
  assert_eq(@jsontable.parse(result.export_json()), result)
  let workbook = @xlsx.read(@opc.open(result.export_xlsx()))
  assert_eq(workbook.sheets[0].cells[4].value, Text("001"))
  assert_eq(workbook.sheets[0].cells[6].value, Text("Jan"))
  assert_eq(source.rows.length(), 3)
  assert_eq(source.rows[0][2], Text("100"))
}

///|
test "unpivot retains typed values and exact Unicode labels in requested order" {
  let source = @jsontable.parse(
    (
      #|[{"id":"001","一月":12.5,"二月":false,"note":"ignore"},{"id":"東京 🐈","二月":0}]
    ),
  )
  let result = source.unpivot(id_columns=["id"], value_columns=[
    "二月", "一月",
  ])
  assert_eq(result.rows, [
    [Text("001"), Text("二月"), Boolean(false)],
    [Text("001"), Text("一月"), Number("12.5")],
    [Text("東京 🐈"), Text("二月"), Number("0")],
    [Text("東京 🐈"), Text("一月"), Empty],
  ])
  assert_eq(@jsontable.parse(result.export_json(omit_empty=true)), result)
  let cells = @xlsx.read(@opc.open(result.export_xlsx())).sheets[0].cells
  assert_true(cells.any(cell => cell.value == Boolean(false)))
  assert_true(cells.any(cell => cell.value == Number("12.5")))
  assert_true(cells.any(cell => cell.value == Text("東京 🐈")))
  assert_eq(result.columns, ["id", "variable", "value"])
}

///|
test "drop_empty drops only missing and exact empty text" {
  let source : @jsontable.Table = {
    columns: ["a", "b", "c", "d", "e", "f"],
    rows: [
      [Empty, Text(""), Text(" "), Number("0"), Boolean(false), Text("null")],
    ],
  }
  let all = source.unpivot(id_columns=[], value_columns=source.columns)
  assert_eq(all.rows.length(), 6)
  let nonempty = source.unpivot(
    id_columns=[],
    value_columns=source.columns,
    drop_empty=true,
  )
  assert_eq(nonempty.text_rows(), [
    ["c", " "],
    ["d", "0"],
    ["e", "false"],
    ["f", "null"],
  ])
}

///|
test "unpivot rows and columns are independent copies" {
  let source = @jsontable.parse_delimited("id,a,b\n001,10,20\n")
  let ids = ["id"]
  let values = ["a", "b"]
  let result = source.unpivot(id_columns=ids, value_columns=values)
  result.columns[0] = "changed"
  result.rows[0][0] = Text("changed")
  assert_eq(source.columns, ["id", "a", "b"])
  assert_eq(source.rows[0][0], Text("001"))
  assert_eq(result.rows[1][0], Text("001"))
  assert_eq(ids, ["id"])
  assert_eq(values, ["a", "b"])
}

///|
test "empty unpivot retains output header and all blank input can be dropped" {
  let source = @jsontable.parse_delimited("id,a,b\n")
  let result = source.unpivot(id_columns=["id"], value_columns=["a", "b"])
  assert_eq(result.columns, ["id", "variable", "value"])
  assert_eq(result.rows.length(), 0)
  assert_eq(@jsontable.parse_delimited(result.export_csv()), result)
  let blank = @jsontable.parse_delimited("id,a,b\n001,,\n")
  assert_eq(
    blank.unpivot(id_columns=["id"], value_columns=["a", "b"], drop_empty=true).rows.length(),
    0,
  )
}

///|
test "unpivot reports ambiguous selections and names before producing rows" {
  let source = @jsontable.parse_delimited("id,a,b\n001,10,20\n")
  assert_true(
    try source.unpivot(id_columns=["missing"], value_columns=["a"]) catch {
      value => value is UnknownUnpivotColumn("missing")
    } noraise {
      _ => false
    },
  )
  assert_true(
    try source.unpivot(id_columns=[], value_columns=["missing"]) catch {
      value => value is UnknownUnpivotColumn("missing")
    } noraise {
      _ => false
    },
  )
  assert_true(
    try source.unpivot(id_columns=["id", "id"], value_columns=["a"]) catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try source.unpivot(id_columns=["id"], value_columns=["id"]) catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try source.unpivot(id_columns=[], value_columns=["a", "a"]) catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try source.unpivot(id_columns=[], value_columns=[]) catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      source.unpivot(id_columns=["id"], value_columns=["a"], names_to="id")
    catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      source.unpivot(
        id_columns=[],
        value_columns=["a"],
        names_to="x",
        values_to="x",
      )
    catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try source.unpivot(id_columns=[], value_columns=["a"], values_to="") catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
}

///|
test "unpivot rejects ragged tables and relocating formula cells" {
  let ragged : @jsontable.Table = { columns: ["a"], rows: [[]], }
  assert_true(
    try ragged.unpivot(id_columns=[], value_columns=["a"]) catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  let duplicate : @jsontable.Table = { columns: ["a", "a"], rows: [], }
  assert_true(
    try duplicate.unpivot(id_columns=[], value_columns=["a"]) catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  let formula : @jsontable.Table = {
    columns: ["id", "a"],
    rows: [[Text("001"), Formula(expression="B1+1", cached=Some("2"))]],
  }
  assert_true(
    try formula.unpivot(id_columns=["id"], value_columns=["a"]) catch {
      value => value is UnsupportedUnpivotValue(row=1, column="a")
    } noraise {
      _ => false
    },
  )
  let error : @jsontable.Table = {
    columns: ["id", "a"],
    rows: [[Error("#VALUE!"), Text("1")]],
  }
  assert_true(
    try error.unpivot(id_columns=["id"], value_columns=["a"]) catch {
      value => value is UnsupportedUnpivotValue(row=1, column="id")
    } noraise {
      _ => false
    },
  )
}

///|
test "unpivot supports documented row limit and counts only emitted rows" {
  let source : @jsontable.Table = {
    columns: ["a", "b"],
    rows: Array::makei(5_000, _ => [Text("1"), Text("")]),
  }
  assert_eq(
    source.unpivot(id_columns=[], value_columns=["a", "b"]).rows.length(),
    10_000,
  )
  source.rows.push([Text("1"), Text("")])
  assert_true(
    try source.unpivot(id_columns=[], value_columns=["a", "b"]) catch {
      value => value is InvalidUnpivot(_)
    } noraise {
      _ => false
    },
  )
  assert_eq(
    source.unpivot(id_columns=[], value_columns=["a", "b"], drop_empty=true).rows.length(),
    5_001,
  )
}
