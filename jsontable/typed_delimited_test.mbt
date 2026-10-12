///|
fn typed_schema() -> @jsontable.DelimitedSchema raise {
  @jsontable.parse_delimited_schema(
    (
      #|{"version":1,"columns":[
      #| {"source":"ID","name":"id","kind":{"type":"text"},"trim":false,"nulls":[]},
      #| {"source":"Amount","name":"amount","kind":{"type":"number"},"trim":true,"nulls":["","NULL"]},
      #| {"source":"Active","name":"active","kind":{"type":"boolean","true":"YES","false":"NO"},"trim":true,"nulls":["NULL"]},
      #| {"source":"Note","name":"note","kind":{"type":"text"},"trim":false,"nulls":["NULL"]}
      #|]}
    ),
  )
}

///|
fn one_typed_schema(
  kind : String,
  trim : Bool,
  nulls : String,
) -> @jsontable.DelimitedSchema raise {
  @jsontable.parse_delimited_schema(
    "{\"version\":1,\"columns\":[{\"source\":\"v\",\"name\":\"value\",\"kind\":" +
    kind +
    ",\"trim\":" +
    trim.to_string() +
    ",\"nulls\":" +
    nulls +
    "}]}",
  )
}

///|
test "typed delimited selects renames preserves IDs and converts explicit values" {
  let input = "ID,Active,Amount,Note,ignored\r\n001, YES , 12.50 ,\"a,b\",x\r\n002,NO,NULL,,y\r\n1,NULL,-2e1,NULL,z\r\n"
  let table = @jsontable.parse_typed_delimited(input, typed_schema())
  assert_eq(table.columns, ["id", "amount", "active", "note"])
  assert_eq(table.rows, [
    [
      @scene.Text("001"),
      @scene.Number("12.50"),
      @scene.Boolean(true),
      @scene.Text("a,b"),
    ],
    [@scene.Text("002"), @scene.Empty, @scene.Boolean(false), @scene.Text("")],
    [@scene.Text("1"), @scene.Number("-2e1"), @scene.Empty, @scene.Empty],
  ])
  assert_eq(@jsontable.parse_typed_delimited(input, typed_schema()), table)
  // Existing Boolean queries can now consume delimited data without per-cell edits.
  let query = @jsontable.parse_query_recipe(
    (
      #|{"version":1,"filters":[{"column":"active","mode":"boolean","op":"eq","value":true}],"sort":[],"select":["id","amount"],"limit":100}
    ),
  )
  let selected = table.query(query)
  assert_eq(selected.source_rows, [1])
  assert_eq(selected.table.rows, [[@scene.Text("001"), @scene.Number("12.50")]])
}

///|
test "typed delimited quoted multiline Unicode TSV BOM and zero rows" {
  let input = "\u{FEFF}ID\tAmount\tActive\tNote\r\n001\t2\tYES\t\"北\nsecond\"\r\n"
  let table = @jsontable.parse_typed_delimited(
    input,
    typed_schema(),
    delimiter='\t',
  )
  assert_eq(table.rows[0][3], @scene.Text("北\nsecond"))
  let empty = @jsontable.parse_typed_delimited(
    "ID,Amount,Active,Note\n",
    typed_schema(),
  )
  assert_eq(empty.columns, ["id", "amount", "active", "note"])
  assert_eq(empty.rows, [])
}

///|
test "typed delimited literal null empty whitespace and formula looking text are explicit" {
  let literal = one_typed_schema("{\"type\":\"text\"}", false, "[]")
  let table = @jsontable.parse_typed_delimited(
    "v\nnull\nNULL\n\"\"\n\"  a  \"\n=1+1\n", literal,
  )
  assert_eq(table.rows, [
    [@scene.Text("null")],
    [@scene.Text("NULL")],
    [@scene.Text("")],
    [@scene.Text("  a  ")],
    [@scene.Text("=1+1")],
  ])
  let normalized = one_typed_schema(
    "{\"type\":\"text\"}", true, "[\"\",\"NULL\"]",
  )
  assert_eq(
    @jsontable.parse_typed_delimited(
      "v\n\"  \"\nNULL\nnull\n\"  a  \"\n", normalized,
    ).rows,
    [[@scene.Empty], [@scene.Empty], [@scene.Text("null")], [@scene.Text("a")]],
  )
}

///|
test "typed delimited number syntax rejects guesses and nonfinite values" {
  let schema = one_typed_schema("{\"type\":\"number\"}", false, "[]")
  for
    value in [
      "01", "+1", "1,000", "$2", "NaN", "Infinity", "1e999", "null", "true", "1 ",
      " 1", "", "=1+1",
    ] {
    let csv = "v\n\"" + value + "\"\n"
    try @jsontable.parse_typed_delimited(csv, schema) catch {
      @jsontable.DelimitedConversion(row~, column~, ..) => {
        assert_eq(row, 1)
        assert_eq(column, "v")
      }
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected number refusal: " + value)
    }
  }
  let valid = @jsontable.parse_typed_delimited("v\n0\n-0\n1.25\n2E+3\n", schema)
  assert_eq(valid.rows, [
    [@scene.Number("0")],
    [@scene.Number("-0")],
    [@scene.Number("1.25")],
    [@scene.Number("2E+3")],
  ])
}

///|
test "typed delimited Boolean tokens are exact and late errors allow clean retry" {
  let schema = typed_schema()
  for value in ["yes", "true", "1", ""] {
    let bad = "ID,Amount,Active,Note\n001,2,YES,ok\n002,3," + value + ",bad\n"
    try @jsontable.parse_typed_delimited(bad, schema) catch {
      @jsontable.DelimitedConversion(row~, column~, ..) => {
        assert_eq(row, 2)
        assert_eq(column, "Active")
      }
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected Boolean refusal")
    }
  }
  let input = "ID,Amount,Active,Note\n001,2,YES,ok\n002,3,NO,good\n"
  let copy = @jsontable.parse_typed_delimited(input, schema)
  copy.rows[0][0] = @scene.Text("changed")
  copy.columns[0] = "changed"
  let retry = @jsontable.parse_typed_delimited(input, schema)
  assert_eq(retry.columns[0], "id")
  assert_eq(retry.rows[0][0], @scene.Text("001"))
}

///|
test "typed delimited refuses malformed schema contracts" {
  for
    schema in [
      "{}", "{\"version\":2,\"columns\":[]}", "{\"version\":1,\"columns\":[]}", "{\"version\":1,\"columns\":[],\"unknown\":true}",
      "{\"version\":1,\"columns\":[{}]}",
    ] {
    try @jsontable.parse_delimited_schema(schema) catch {
      @jsontable.InvalidDelimitedSchema(_) => ()
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected schema refusal")
    }
  }
  for
    kind in [
      "{\"type\":\"date\"}", "{\"type\":\"number\",\"extra\":true}", "{\"type\":\"boolean\"}",
      "{\"type\":\"boolean\",\"true\":\"x\",\"false\":\"x\"}", "{\"type\":\"boolean\",\"true\":\"\",\"false\":\"n\"}",
      "{\"type\":\"boolean\",\"true\":\" y \",\"false\":\"n\"}", "{\"type\":\"boolean\",\"true\":\"NULL\",\"false\":\"n\"}",
    ] {
    try one_typed_schema(kind, true, "[\"NULL\"]") catch {
      @jsontable.InvalidDelimitedSchema(_) => ()
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected kind refusal")
    }
  }
  for nulls in ["null", "[null]", "[1]", "[\"x\",\"x\"]", "[\" x \"]"] {
    try one_typed_schema("{\"type\":\"text\"}", true, nulls) catch {
      @jsontable.InvalidDelimitedSchema(_) => ()
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected null marker refusal")
    }
  }
}

///|
test "typed delimited rejects missing duplicate ragged and malformed input headers" {
  for
    input in [
      "", "v\n1\n", "ID,Amount,Active,Note,ID\n", "ID,Amount,Active,Note\n001,2,YES\n",
      "ID,Amount,Active,Note\n001,2,YES,\"bad",
    ] {
    try @jsontable.parse_typed_delimited(input, typed_schema()) catch {
      @jsontable.InvalidDelimitedSchema(_)
      | @jsontable.InvalidTypedDelimited(_) => ()
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected input refusal")
    }
  }
}

///|
test "typed delimited actual CSV JSON and XLSX exports reopen" {
  let table = @jsontable.parse_typed_delimited(
    "ID,Amount,Active,Note\n001,12.5,YES,=1+1\n002,,NO,\n",
    typed_schema(),
  )
  assert_eq(
    @jsontable.parse_delimited(table.export_csv()).text_rows(),
    table.text_rows(),
  )
  let reparsed = @jsontable.parse(table.export_json(omit_empty=true))
  assert_eq(reparsed, table)
  let pkg = @opc.open(table.export_xlsx())
  let imported = @jsontable.extract_xlsx(
    pkg,
    sheet_name="JSON data",
    range="A1:D3",
    header=@jsontable.FirstRow,
  )
  assert_eq(imported.table, table)
}

///|
test "typed delimited schema and output bounds are enforced before returning a table" {
  let columns : Array[String] = []
  for i in 0..<128 {
    columns.push(
      "{\"source\":\"v\",\"name\":\"out" +
      i.to_string() +
      "\",\"kind\":{\"type\":\"text\"},\"trim\":false,\"nulls\":[]}",
    )
  }
  let recipe = "{\"version\":1,\"columns\":[" + columns.join(",") + "]}"
  let schema = @jsontable.parse_delimited_schema(recipe)
  let accepted = "v\n" + Array::make(780, "x\n").join("")
  assert_eq(
    @jsontable.parse_typed_delimited(accepted, schema).rows.length(),
    780,
  )
  try @jsontable.parse_typed_delimited(accepted + "x\n", schema) catch {
    @jsontable.InvalidTypedDelimited(_) => ()
    error => fail("Unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("Expected output cell limit")
  }
  let repeated = "v\n" + Array::make(40000, "x").join("") + "\n"
  try @jsontable.parse_typed_delimited(repeated, schema) catch {
    @jsontable.InvalidTypedDelimited(_) => ()
    error => fail("Unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("Expected expanded-output text limit")
  }
  columns.push(columns[0])
  for
    invalid in [
      "{\"version\":1,\"columns\":[" + columns.join(",") + "]}",
      "{\"version\":1,\"columns\":[" + columns[0] + "," + columns[0] + "]}",
      Array::make(65537, " ").join(""),
    ] {
    try @jsontable.parse_delimited_schema(invalid) catch {
      @jsontable.InvalidDelimitedSchema(_) => ()
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected schema bound or duplicate-name refusal")
    }
  }
}

///|
test "typed delimited source numeric text is not converted without explicit kind" {
  let raw = one_typed_schema("{\"type\":\"text\"}", false, "[]")
  assert_eq(
    @jsontable.parse_typed_delimited("v\n001\ntrue\n12.50\n", raw).rows,
    [[@scene.Text("001")], [@scene.Text("true")], [@scene.Text("12.50")]],
  )
  let no_trim = one_typed_schema(
    "{\"type\":\"boolean\",\"true\":\" YES \",\"false\":\" NO \"}", false, "[]",
  )
  assert_eq(
    @jsontable.parse_typed_delimited("v\n YES \n NO \n", no_trim).rows,
    [[@scene.Boolean(true)], [@scene.Boolean(false)]],
  )
}

///|
test "typed delimited retains CR but rejects XML controls only when exporting XLSX" {
  let schema = one_typed_schema("{\"type\":\"text\"}", false, "[]")
  let text = "before\r\nafter\rfinal"
  let table = @jsontable.parse_typed_delimited("v\n\"" + text + "\"\n", schema)
  let imported = @jsontable.extract_xlsx(
    @opc.open(table.export_xlsx()),
    sheet_name="JSON data",
    range="A1:A2",
    header=@jsontable.FirstRow,
  )
  assert_eq(imported.table.rows[0][0], @scene.Text(text))
  for control in ["\u{0}", "\u{1}", "\u{FFFE}", "\u{FFFF}"] {
    let data = "before" + control + "after"
    let table = @jsontable.parse_typed_delimited(
      "v\n\"" + data + "\"\n",
      schema,
    )
    assert_eq(
      @jsontable.parse(table.export_json()).rows[0][0],
      @scene.Text(data),
    )
    try table.export_xlsx() catch {
      @jsontable.Export(_) => ()
      error => fail("Unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("Expected XML-character export refusal")
    }
  }
}
