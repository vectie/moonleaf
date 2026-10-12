///|
fn correction_recipe() -> @jsontable.CorrectionRecipe raise {
  @jsontable.parse_correction_recipe(
    (
      #|{"key_columns":["id"],"edits":[
      #|{"key":["002"],"column":"name","before":{"type":"text","value":"old"},"after":{"type":"text","value":"東京 🐈\n=1+1"}},
      #|{"key":["001"],"column":"amount","before":{"type":"number","value":"12.5"},"after":{"type":"number","value":"20"}},
      #|{"key":["002"],"column":"active","before":{"type":"boolean","value":false},"after":{"type":"boolean","value":true}},
      #|{"key":["001"],"column":"note","before":{"type":"empty"},"after":{"type":"text","value":""}},
      #|{"key":["002"],"column":"note","before":{"type":"text","value":"remove"},"after":{"type":"empty"}},
      #|{"key":["001"],"column":"name","before":{"type":"text","value":"keep"},"after":{"type":"text","value":"keep"}}]}
    ),
  )
}

///|
fn correction_source() -> @jsontable.Table raise {
  @jsontable.parse(
    (
      #|[{"id":"001","name":"keep","amount":12.5,"active":true},{"id":"002","name":"old","amount":0,"active":false,"note":"remove"}]
    ),
  )
}

///|
test "correction performs typed batch in source order and report in recipe order" {
  let source = correction_source()
  let result = source.correct(correction_recipe())
  assert_eq(result.table.rows, [
    [
      @scene.Text("001"),
      @scene.Text("keep"),
      @scene.Number("20"),
      @scene.Boolean(true),
      @scene.Text(""),
    ],
    [
      @scene.Text("002"),
      @scene.Text("東京 🐈\n=1+1"),
      @scene.Number("0"),
      @scene.Boolean(true),
      @scene.Empty,
    ],
  ])
  assert_eq(result.report.text_rows().map(row => row[1]), [
    "2", "1", "2", "1", "2", "1",
  ])
  assert_eq(result.report.rows[3][5], @scene.Empty)
  assert_eq(result.report.rows[3][7], @scene.Text(""))
  assert_eq(result.report.text_rows()[5][8], "unchanged")
  assert_eq(source, correction_source())
  result.table.rows[0][1] = @scene.Text("mutated")
  result.table.columns[0] = "mutated"
  result.report.rows[0][7] = @scene.Text("mutated")
  assert_eq(source, correction_source())
  assert_eq(result.table.rows[1][1], @scene.Text("東京 🐈\n=1+1"))
}

///|
test "correction rejects late conflict without mutation and supports valid retry" {
  let source = correction_source()
  source.rows[0][1] = @scene.Text("changed externally")
  assert_true(
    (try? source.correct(correction_recipe()))
    is Err(@jsontable.CorrectionConflict(edit=6, row=1, column="name")),
  )
  assert_eq(source.rows[1][1], @scene.Text("old"))
  assert_eq(source.rows[0][2], @scene.Number("12.5"))
  source.rows[0][1] = @scene.Text("keep")
  assert_eq(
    source.correct(correction_recipe()).table.rows[0][2],
    @scene.Number("20"),
  )
  let numeric : @jsontable.Table = {
    columns: ["id", "value"],
    rows: [[@scene.Text("x"), @scene.Number("1.0")]],
  }
  let recipe = @jsontable.parse_correction_recipe(
    (
      #|{"key_columns":["id"],"edits":[{"key":["x"],"column":"value","before":{"type":"number","value":"1"},"after":{"type":"number","value":"2"}}]}
    ),
  )
  assert_true(
    (try? numeric.correct(recipe)) is Err(@jsontable.CorrectionConflict(..)),
  )
}

///|
test "correction rejects unknown keys columns duplicates and unsupported source cells" {
  let recipe = correction_recipe()
  let source = correction_source()
  source.rows.push(source.rows[0].copy())
  assert_true((try? source.correct(recipe)) is Err(_))
  source.rows.remove(source.rows.length() - 1) |> ignore
  source.rows[1][0] = @scene.Text("absent")
  assert_true((try? source.correct(recipe)) is Err(_))
  source.rows[1][0] = @scene.Text("")
  assert_true((try? source.correct(recipe)) is Err(_))
  source.rows[1][0] = @scene.Number("2")
  assert_true((try? source.correct(recipe)) is Err(_))
  source.rows[1][0] = @scene.Text("002")
  source.rows[1][2] = @scene.Error("#N/A")
  assert_true((try? source.correct(recipe)) is Err(_))
  source.rows[1][2] = @scene.Number("1e999")
  assert_true((try? source.correct(recipe)) is Err(_))
  source.rows[1][2] = @scene.Number("0")
  source.columns[1] = "renamed"
  assert_true((try? source.correct(recipe)) is Err(_))
  source.columns[0] = "renamed"
  assert_true((try? source.correct(recipe)) is Err(_))
}

///|
test "correction strict recipe and repeated target refusal" {
  for
    text in [
      "{}",
      "[]",
      "{",
      (
        #|{"key_columns":["id"],"edits":[]}
      ),
      (
        #|{"key_columns":["id","id"],"edits":[]}
      ),
      (
        #|{"key_columns":["id"],"edits":[{"key":["001"],"column":"id","before":{"type":"text","value":"001"},"after":{"type":"text","value":"003"}}]}
      ),
      (
        #|{"key_columns":["id"],"edits":[{"key":["001"],"column":"name","before":{"type":"empty","value":null},"after":{"type":"empty"}}]}
      ),
      (
        #|{"key_columns":["id"],"edits":[{"key":["001"],"column":"name","before":{"type":"number","value":1},"after":{"type":"empty"}}]}
      ),
      (
        #|{"key_columns":["id"],"edits":[{"key":["001"],"column":"name","before":{"type":"number","value":"NaN"},"after":{"type":"empty"}}]}
      ),
      (
        #|{"key_columns":["id"],"edits":[{"key":["001"],"column":"name","before":{"type":"text","value":"keep"},"after":{"type":"empty"},"typo":true}]}
      ),
    ] {
    assert_true((try? @jsontable.parse_correction_recipe(text)) is Err(_))
  }
  let repeated = @jsontable.parse_correction_recipe(
    (
      #|{"key_columns":["id"],"edits":[{"key":["001"],"column":"name","before":{"type":"text","value":"keep"},"after":{"type":"text","value":"first"}},{"key":["001"],"column":"name","before":{"type":"text","value":"keep"},"after":{"type":"text","value":"second"}}]}
    ),
  )
  assert_true((try? correction_source().correct(repeated)) is Err(_))
}

///|
test "correction exact composite keys do not collide and no normalization occurs" {
  let table : @jsontable.Table = {
    columns: ["a", "b", "v"],
    rows: [
      [@scene.Text("a|b"), @scene.Text("c"), @scene.Text("old")],
      [@scene.Text("a"), @scene.Text("b|c"), @scene.Text("old")],
      [@scene.Text("é"), @scene.Text("東京\n\""), @scene.Text("old")],
    ],
  }
  let recipe = @jsontable.parse_correction_recipe(
    (
      #|{"key_columns":["a","b"],"edits":[{"key":["a","b|c"],"column":"v","before":{"type":"text","value":"old"},"after":{"type":"text","value":"new"}}]}
    ),
  )
  assert_eq(table.correct(recipe).table.text_rows(), [
    ["a|b", "c", "old"],
    ["a", "b|c", "new"],
    ["é", "東京\n\"", "old"],
  ])
}

///|
test "correction exports reopen with types and formula-looking text kept inline" {
  let result = correction_source().correct(correction_recipe())
  assert_eq(
    @csv.parse(result.table.export_csv()).rows,
    [result.table.columns] + result.table.text_rows(),
  )
  assert_eq(
    @jsontable.parse(result.table.export_json(omit_empty=true)),
    result.table,
  )
  let workbook = @xlsx.read(@opc.open(result.table.export_xlsx()))
  assert_true(
    workbook.sheets[0].cells.any(cell => {
      cell.value == @scene.Text("東京 🐈\n=1+1")
    }),
  )
  assert_true(
    workbook.sheets[0].cells.any(cell => cell.value == @scene.Number("20")),
  )
  assert_true(
    !workbook.sheets[0].cells.any(cell => cell.value is @scene.Formula(..)),
  )
  assert_eq(
    @jsontable.parse(result.report.export_json(omit_empty=true)),
    result.report,
  )
}

///|
test "correction bounded tables and reusable recipe" {
  let recipe = @jsontable.parse_correction_recipe(
    (
      #|{"key_columns":["id"],"edits":[{"key":["0"],"column":"v","before":{"type":"text","value":"old"},"after":{"type":"text","value":"new"}}]}
    ),
  )
  let table : @jsontable.Table = {
    columns: ["id", "v"],
    rows: Array::makei(10000, i => {
      [@scene.Text(i.to_string()), @scene.Text("old")]
    }),
  }
  assert_eq(table.correct(recipe).table.rows.length(), 10000)
  table.rows.push([@scene.Text("extra"), @scene.Text("old")])
  assert_true((try? table.correct(recipe)) is Err(_))
  let wide : @jsontable.Table = {
    columns: ["id", "v"] + Array::makei(126, i => i.to_string()),
    rows: [],
  }
  assert_true((try? wide.correct(recipe)) is Err(_)) // absent key, no partial result
  wide.columns.push("extra")
  assert_true((try? wide.correct(recipe)) is Err(_))
}

///|
test "correction inclusive edit column cell and text budgets reject only beyond boundary" {
  let edit = fn(id : String) {
    "{\"key\":[\"" +
    id +
    "\"],\"column\":\"v\",\"before\":{\"type\":\"text\",\"value\":\"old\"},\"after\":{\"type\":\"text\",\"value\":\"new\"}}"
  }
  let edits = Array::makei(1000, i => edit(i.to_string()))
  let recipe_text = "{\"key_columns\":[\"id\"],\"edits\":[" +
    edits.join(",") +
    "]}"
  let recipe = @jsontable.parse_correction_recipe(recipe_text)
  let table : @jsontable.Table = {
    columns: ["id", "v"],
    rows: Array::makei(1000, i => {
      [@scene.Text(i.to_string()), @scene.Text("old")]
    }),
  }
  assert_eq(table.correct(recipe).report.rows.length(), 1000)
  edits.push(edit("1000"))
  assert_true(
    (try? @jsontable.parse_correction_recipe(
      "{\"key_columns\":[\"id\"],\"edits\":[" + edits.join(",") + "]} ",
    ))
    is Err(_),
  )
  let one = @jsontable.parse_correction_recipe(
    "{\"key_columns\":[\"id\"],\"edits\":[" + edit("0") + "]}",
  )
  let wide : @jsontable.Table = {
    columns: ["id", "v"] + Array::makei(126, i => i.to_string()),
    rows: [
      [@scene.Text("0"), @scene.Text("old")] + Array::make(126, @scene.Empty),
    ],
  }
  assert_eq(wide.correct(one).table.columns.length(), 128)
  wide.columns.push("extra")
  wide.rows[0].push(@scene.Empty)
  assert_true((try? wide.correct(one)) is Err(_))
  let cells : @jsontable.Table = {
    columns: ["id", "v"] + Array::makei(8, i => i.to_string()),
    rows: Array::makei(9999, i => {
      [@scene.Text(i.to_string()), @scene.Text("old")] +
      Array::make(8, @scene.Empty)
    }),
  }
  assert_eq(cells.correct(one).table.rows.length(), 9999)
  cells.rows.push(
    [@scene.Text("extra"), @scene.Text("old")] + Array::make(8, @scene.Empty),
  )
  assert_true((try? cells.correct(one)) is Err(_))
  let huge = String::make(3_999_992, 'x')
  let text_table : @jsontable.Table = {
    columns: ["id", "v", "x"],
    rows: [[@scene.Text("0"), @scene.Text("old"), @scene.Text(huge)]],
  }
  assert_eq(text_table.correct(one).table.rows[0][1], @scene.Text("new"))
  text_table.rows[0][2] = @scene.Text(huge + "x")
  assert_true((try? text_table.correct(one)) is Err(_))
  assert_true(
    (try? @jsontable.parse_correction_recipe(String::make(1_048_577, ' ')))
    is Err(_),
  )
}
