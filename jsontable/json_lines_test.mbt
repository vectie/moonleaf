///|
fn line_spec() -> @jsontable.JsonLineSpec raise {
  @jsontable.parse_json_line_spec(
    (
      #|{"version":1,"record_path":["orders"],"items_path":["lines"],"parent_fields":[{"name":"order","path":["id"],"required":true}],"item_fields":[{"name":"sku","path":["sku"],"required":true},{"name":"qty","path":["qty"]},{"name":"active","path":["active"]},{"name":"note","path":["note"],"nulls":"empty"}],"empty_items":"skip"}
    ),
  )
}

///|
test "order lines keep parent metadata exact positions duplicates and typed values" {
  let imported = @jsontable.parse_json_lines(
    (
      #|{"orders":[{"id":"001","lines":[{"sku":"雪😀","qty":2,"active":false,"note":"=1+1"},{"sku":"雪😀","qty":2,"active":false,"note":"=1+1"}]},{"id":"empty","lines":[]},{"id":"003","lines":[{"sku":"0004","note":null}]}]}
    ),
    line_spec(),
  )
  assert_eq(imported.parent_count, 3)
  assert_eq(imported.empty_parent_rows, [2])
  let table = imported.table
  assert_eq(table.columns, [
    "_parent_row", "_item_row", "order", "sku", "qty", "active", "note",
  ])
  assert_eq(table.rows[0], [
    Number("1"),
    Number("1"),
    Text("001"),
    Text("雪😀"),
    Number("2"),
    Boolean(false),
    Text("=1+1"),
  ])
  assert_eq(table.rows[1][1], Number("2"))
  assert_eq(table.text_rows()[2], ["3", "1", "003", "0004", "", "", ""])
  // Each expanded row owns its own cells, even when parent metadata repeats.
  table.rows[0][2] = Text("changed")
  assert_eq(table.rows[1][2], Text("001"))
  assert_eq(
    @csv.parse(table.export_csv()).rows,
    [table.columns] + table.text_rows(),
  )
  assert_eq(@jsontable.parse(table.export_json(omit_empty=true)), table)
  let book = @xlsx.read(@opc.open(table.export_xlsx()))
  assert_true(book.sheets[0].cells.any(cell => cell.value == Text("=1+1")))
  assert_true(book.sheets[0].cells.any(cell => cell.value == Boolean(false)))
}

///|
test "line queries retain source locators when filtered sorted and projected" {
  let imported = @jsontable.parse_json_lines(
    (
      #|{"orders":[{"id":"a","lines":[{"sku":"a1","qty":1},{"sku":"a2","qty":3}]},{"id":"b","lines":[]},{"id":"c","lines":[{"sku":"c1","qty":5}]}]}
    ),
    line_spec(),
  )
  let query = @jsontable.parse_query_recipe(
    (
      #|{"version":1,"filters":[{"column":"qty","mode":"number","op":"ge","value":2}],"sort":[{"column":"qty","mode":"number","direction":"desc","blanks":"last"}],"select":["sku"],"limit":10}
    ),
  )
  let selected = imported.table.query(query)
  assert_eq(selected.table.text_rows(), [["c1"], ["a2"]])
  assert_eq(selected.source_rows, [3, 2])
  assert_eq(imported.table.rows[selected.source_rows[0] - 1][0], Number("3"))
  assert_eq(imported.table.rows[selected.source_rows[1] - 1][1], Number("2"))
}

///|
test "empty arrays skip explicitly while null missing malformed lists refuse" {
  let spec = line_spec()
  let empty = @jsontable.parse_json_lines(
    "{\"orders\":[{\"id\":\"a\",\"lines\":[]}]}", spec,
  )
  assert_eq(empty.empty_parent_rows, [1])
  assert_eq(empty.table.rows, [])
  assert_eq(empty.table.columns.length(), 7)
  assert_eq(
    @jsontable.parse_json_lines("{\"orders\":[]}", spec).parent_count,
    0,
  )
  for
    input in [
      "{\"orders\":[{\"id\":\"a\"}]}", "{\"orders\":[{\"id\":\"a\",\"lines\":null}]}",
      "{\"orders\":[{\"id\":\"a\",\"lines\":{}}]}", "{\"orders\":[{\"id\":\"a\",\"lines\":[1]}]}",
      "{\"orders\":[{\"lines\":[]}]}", "{\"orders\":[null]}", "{\"orders\":{}}",
      "{}", "[]", "bad",
    ] {
    assert_true(
      try @jsontable.parse_json_lines(input, spec) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "selected field refusals report precise parent item and column before retry" {
  let spec = line_spec()
  let bad =
    #|{"orders":[{"id":"a","lines":[]},{"id":"b","lines":[{"sku":"ok"},{"qty":2}]}]}
  assert_true(
    try @jsontable.parse_json_lines(bad, spec) catch {
      value =>
        value
        is JsonLineFieldError(
          parent_row=2,
          item_row=Some(2),
          column="sku",
          reason="Required field is missing"
        )
    } noraise {
      _ => false
    },
  )
  for value in ["null", "[]", "{}", "1e999"] {
    assert_true(
      try
        @jsontable.parse_json_lines(
          "{\"orders\":[{\"id\":\"a\",\"lines\":[{\"sku\":" + value + "}]}]}",
          spec,
        )
      catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let retry = @jsontable.parse_json_lines(
    "{\"orders\":[{\"id\":\"a\",\"lines\":[{\"sku\":\"retry\"}]}]}", spec,
  )
  assert_eq(retry.table.rows.length(), 1)
}

///|
test "exact nested object paths and explicit null policies" {
  let spec = @jsontable.parse_json_line_spec(
    (
      #|{"version":1,"record_path":[],"items_path":["a.b","0"],"parent_fields":[],"item_fields":[{"name":"v","path":["","v"],"nulls":"literal","required":true}],"empty_items":"skip"}
    ),
  )
  assert_eq(
    @jsontable.parse_json_lines(
      "[{\"a.b\":{\"0\":[{\"\":{\"v\":null}}]}}]", spec,
    ).table.text_rows(),
    [["1", "1", "null"]],
  )
  for input in ["[{\"a.b\":null}]", "[{\"a.b\":{\"0\":[{\"\":null}]}}]"] {
    assert_true(
      try @jsontable.parse_json_lines(input, spec) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "line spec rejects ambiguous names paths options and unsupported empty policy" {
  let spec = line_spec()
  for
    field in [
      { ..spec.item_fields[0], name: "order", },
      { ..spec.item_fields[0], name: "_parent_row", },
      { ..spec.item_fields[0], name: "_item_row", },
      { ..spec.item_fields[0], name: " ", },
      { ..spec.item_fields[0], path: [], },
      { ..spec.item_fields[0], path: Array::make(17, "a"), },
    ] {
    assert_true(
      try
        @jsontable.parse_json_lines("[]", { ..spec, item_fields: [field], })
      catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  for
    mapping in [
      "{}",
      "bad",
      (
        #|{"version":1,"record_path":[],"items_path":[],"parent_fields":[],"item_fields":[{"name":"a","path":["a"]}],"empty_items":"skip"}
      ),
      (
        #|{"version":1,"record_path":[],"items_path":["lines"],"parent_fields":[],"item_fields":[],"empty_items":"skip"}
      ),
      (
        #|{"version":1,"record_path":[],"items_path":["lines"],"parent_fields":[],"item_fields":[{"name":"a","path":["a"]}],"empty_items":"retain"}
      ),
      (
        #|{"version":1,"record_path":[],"items_path":["lines"],"parent_fields":[],"item_fields":[{"name":"a","path":["a"],"typo":true}],"empty_items":"skip"}
      ),
    ] {
    assert_true(
      try @jsontable.parse_json_line_spec(mapping) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "expanded row and cell budgets apply across parents before output" {
  let field : @jsontable.JsonRecordField = {
    name: "v",
    path: ["v"],
    required: false,
    nulls: RejectNull,
  }
  let spec : @jsontable.JsonLineSpec = {
    records_path: [],
    items_path: ["lines"],
    parent_fields: [],
    item_fields: [field],
  }
  let many = "[{\"lines\":[" + Array::make(10000, "{}").join(",") + "]}]"
  assert_eq(@jsontable.parse_json_lines(many, spec).table.rows.length(), 10000)
  let overflow = "[{\"lines\":[{}]},{\"lines\":[" +
    Array::make(10000, "{}").join(",") +
    "]}]"
  assert_true(
    try @jsontable.parse_json_lines(overflow, spec) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let wide : @jsontable.JsonLineSpec = {
    ..spec,
    item_fields: Array::makei(8, i => { ..field, name: "v\{i}", }),
  }
  assert_true(
    try @jsontable.parse_json_lines(many, wide) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let exact = "[{\"lines\":[" + Array::make(9999, "{}").join(",") + "]}]"
  assert_eq(@jsontable.parse_json_lines(exact, wide).table.rows.length(), 9999)
  assert_true(
    try
      @jsontable.parse_json_lines(
        "[" + Array::make(10001, "{\"lines\":[]}").join(",") + "]",
        spec,
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "parent text amplification refuses before serialization" {
  let field : @jsontable.JsonRecordField = {
    name: "memo",
    path: ["memo"],
    required: false,
    nulls: RejectNull,
  }
  let spec : @jsontable.JsonLineSpec = {
    records_path: [],
    items_path: ["lines"],
    parent_fields: [field],
    item_fields: [{ ..field, name: "item_memo", }],
  }
  let input = "[{\"memo\":\"" +
    "x".repeat(100000) +
    "\",\"lines\":[" +
    Array::make(40, "{}").join(",") +
    "]}]"
  assert_true(
    try @jsontable.parse_json_lines(input, spec) catch {
      value =>
        value
        is InvalidJsonLines(
          "Expanded scalar text exceeds 4000000 UTF-16 units including headers"
        )
    } noraise {
      _ => false
    },
  )
}
