///|
fn json_intake_spec() -> @jsontable.JsonRecordSpec raise {
  @jsontable.parse_json_record_spec(
    (
      #|{"record_path":["response","items"],"fields":[{"name":"id","path":["id"],"required":true},{"name":"customer","path":["customer","name"]},{"name":"amount","path":["totals","net"]},{"name":"active","path":["active"]},{"name":"note","path":["note"],"nulls":"empty"}]}
    ),
  )
}

///|
test "nested envelope intake types order provenance and export reopen" {
  let table = @jsontable.parse_json_records(
    (
      #|{"response":{"items":[{"id":"001","customer":{"name":"東京 🐈"},"totals":{"net":12.5},"active":true,"note":null,"ignored":[1,2]},{"id":"002","customer":{"name":"=1+1"},"active":false,"note":"a,\"b\"\nnext"},{"id":"003"}]},"next":"not fetched"}
    ),
    json_intake_spec(),
  )
  assert_eq(table.columns, [
    "_record_row", "id", "customer", "amount", "active", "note",
  ])
  assert_eq(table.rows[0], [
    @scene.Number("1"),
    @scene.Text("001"),
    @scene.Text("東京 🐈"),
    @scene.Number("12.5"),
    @scene.Boolean(true),
    @scene.Empty,
  ])
  assert_eq(table.rows[2], [
    @scene.Number("3"),
    @scene.Text("003"),
    @scene.Empty,
    @scene.Empty,
    @scene.Empty,
    @scene.Empty,
  ])
  assert_eq(
    @csv.parse(table.export_csv()).rows,
    [table.columns] + table.text_rows(),
  )
  assert_eq(@jsontable.parse(table.export_json(omit_empty=true)), table)
  let book = @xlsx.read(@opc.open(table.export_xlsx()))
  assert_true(
    book.sheets[0].cells.any(cell => cell.value == @scene.Text("=1+1")),
  )
  assert_true(
    book.sheets[0].cells.any(cell => cell.value == @scene.Number("12.5")),
  )
  assert_true(
    book.sheets[0].cells.any(cell => cell.value == @scene.Boolean(false)),
  )
}

///|
test "exact literal object keys no dotted or numeric path interpretation" {
  let spec = @jsontable.parse_json_record_spec(
    (
      #|{"record_path":[],"fields":[{"name":"v","path":["a.b","0",""]}]}
    ),
  )
  let table = @jsontable.parse_json_records(
    (
      #|[{"a.b":{"0":{"":"🦊"}}},{"a":{"b":"wrong"}}]
    ),
    spec,
  )
  assert_eq(table.text_rows(), [["1", "🦊"], ["2", ""]])
  assert_true(
    (try? @jsontable.parse_json_records("[{\"a.b\":[]}]", spec)) is Err(_),
  )
}

///|
test "missing required null policies and blocked intermediate paths" {
  let required = @jsontable.parse_json_record_spec(
    (
      #|{"record_path":[],"fields":[{"name":"v","path":["v"],"required":true}]}
    ),
  )
  assert_true(
    (try? @jsontable.parse_json_records("[{}]", required))
    is Err(
      @jsontable.JsonRecordFieldError(
        row=1,
        column="v",
        reason="Required field is missing"
      )
    ),
  )
  assert_true(
    (try? @jsontable.parse_json_records("[{\"v\":null}]", required)) is Err(_),
  )
  for
    (policy, expected) in [
      ("empty", @scene.Empty),
      ("literal", @scene.Text("null")),
    ] {
    let spec : @jsontable.JsonRecordSpec = {
      records_path: [],
      fields: [
        {
          name: "v",
          path: ["v"],
          required: true,
          nulls: if policy == "empty" {
            @jsontable.EmptyNull
          } else {
            @jsontable.LiteralNull
          },
        },
      ],
    }
    assert_eq(
      @jsontable.parse_json_records("[{\"v\":null}]", spec).rows[0][1],
      expected,
    )
  }
  for
    input in [
      "{\"response\":null}", "{\"response\":{}}", "{\"response\":{\"items\":{}}}",
      "{\"response\":{\"items\":[{},7]}}", "bad",
    ] {
    assert_true(
      (try? @jsontable.parse_json_records(input, json_intake_spec())) is Err(_),
    )
  }
  for value in ["null", "[]", "7", "true", "\"text\""] {
    assert_true(
      (try? @jsontable.parse_json_records(
        "{\"response\":{\"items\":[{\"id\":\"a\",\"customer\":" + value + "}]}}",
        json_intake_spec(),
      ))
      is Err(_),
    )
  }
}

///|
test "late unsupported selected values fail whole intake and valid retry" {
  let spec = @jsontable.parse_json_record_spec(
    (
      #|{"record_path":[],"fields":[{"name":"v","path":["v"]}]}
    ),
  )
  for bad in ["[]", "{}", "null", "1e999"] {
    assert_true(
      (try? @jsontable.parse_json_records(
        "[{\"v\":\"good\"},{\"v\":" + bad + "}]",
        spec,
      ))
      is Err(_),
    )
  }
  assert_eq(
    @jsontable.parse_json_records("[{\"v\":\"retry\"}]", spec).text_rows(),
    [["1", "retry"]],
  )
  assert_eq(@jsontable.parse_json_records("[]", spec).columns, [
    "_record_row", "v",
  ])
}

///|
test "mapping rejects unknown options malformed shape duplicate reserved names" {
  for
    bad in [
      "{}", "[]", "no", "{\"record_path\":[],\"fields\":[]}", "{\"record_path\":[],\"fields\":[{\"name\":\"v\",\"path\":[]}]}",
      "{\"record_path\":[],\"fields\":[{\"name\":\"_record_row\",\"path\":[\"v\"]}]}",
      "{\"record_path\":[],\"fields\":[{\"name\":\"v\",\"path\":[\"v\"],\"nulls\":\"ignore\"}]}",
      "{\"record_path\":[],\"fields\":[{\"name\":\"v\",\"path\":[\"v\"],\"required\":1}]}",
      "{\"record_path\":[],\"fields\":[{\"name\":\"v\",\"path\":[0]}]}", "{\"record_path\":[],\"fields\":[{\"name\":\"v\",\"path\":[\"v\"],\"typo\":true}]}",
      "{\"record_path\":[],\"fields\":[{\"name\":\"v\",\"path\":[\"v\"]},{\"name\":\"v\",\"path\":[\"b\"]}]}",
    ] {
    assert_true((try? @jsontable.parse_json_record_spec(bad)) is Err(_))
  }
}

///|
test "inclusive row cell and path bounds" {
  let field : @jsontable.JsonRecordField = {
    name: "v",
    path: ["v"],
    required: false,
    nulls: @jsontable.RejectNull,
  }
  let spec : @jsontable.JsonRecordSpec = { records_path: [], fields: [field], }
  let ten_k = "[" + Array::make(10000, "{}").join(",") + "]"
  assert_eq(@jsontable.parse_json_records(ten_k, spec).rows.length(), 10000)
  assert_true(
    (try? @jsontable.parse_json_records(
      "[" + Array::make(10001, "{}").join(",") + "]",
      spec,
    ))
    is Err(_),
  )
  let fields = Array::makei(9, i => { ..field, name: "v\{i}", })
  let wide : @jsontable.JsonRecordSpec = { records_path: [], fields, }
  assert_eq(
    @jsontable.parse_json_records(
      "[" + Array::make(9999, "{}").join(",") + "]",
      wide,
    ).rows.length(),
    9999,
  )
  assert_true((try? @jsontable.parse_json_records(ten_k, wide)) is Err(_))
  let deep : @jsontable.JsonRecordSpec = {
    records_path: [],
    fields: [{ ..field, path: Array::make(16, "a"), }],
  }
  assert_eq(
    @jsontable.parse_json_records("[{}]", deep).rows[0][1],
    @scene.Empty,
  )
  let too_deep : @jsontable.JsonRecordSpec = {
    ..deep,
    fields: [{ ..field, path: Array::make(17, "a"), }],
  }
  assert_true((try? @jsontable.parse_json_records("[]", too_deep)) is Err(_))
  let too_wide : @jsontable.JsonRecordSpec = {
    records_path: [],
    fields: Array::makei(129, i => { ..field, name: "v\{i}", }),
  }
  assert_true((try? @jsontable.parse_json_records("[]", too_wide)) is Err(_))
}

///|
test "spec bounds and numeric parser semantics are explicit" {
  let field : @jsontable.JsonRecordField = {
    name: "v",
    path: ["v"],
    required: false,
    nulls: @jsontable.RejectNull,
  }
  let max_columns : @jsontable.JsonRecordSpec = {
    records_path: [],
    fields: Array::makei(128, i => { ..field, name: "v\{i}", }),
  }
  assert_eq(
    @jsontable.parse_json_records("[]", max_columns).columns.length(),
    129,
  )
  for name in [" ", "_record_row", "x".repeat(257)] {
    let bad : @jsontable.JsonRecordSpec = {
      records_path: [],
      fields: [{ ..field, name, }],
    }
    assert_true((try? @jsontable.parse_json_records("[]", bad)) is Err(_))
  }
  let path_bound : @jsontable.JsonRecordSpec = {
    records_path: [],
    fields: [{ ..field, path: ["x".repeat(257)], }],
  }
  assert_true((try? @jsontable.parse_json_records("[]", path_bound)) is Err(_))
  assert_true(
    (try? @jsontable.parse_json_record_spec(" ".repeat(65537))) is Err(_),
  )
  assert_true(
    (try? @jsontable.parse_json_records(" ".repeat(4000001), max_columns))
    is Err(_),
  )
  let spec : @jsontable.JsonRecordSpec = { records_path: [], fields: [field], }
  let table = @jsontable.parse_json_records(
    "[{\"v\":1,\"v\":2},{\"v\":9007199254740993},{\"v\":\"9007199254740993\"}]",
    spec,
  )
  assert_eq(table.rows[0][1], @scene.Number("2"))
  assert_eq(table.rows[1][1], @scene.Number("9007199254740993"))
  assert_eq(table.rows[2][1], @scene.Text("9007199254740993"))
}
