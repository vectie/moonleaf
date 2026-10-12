///|
fn fixture_schema() -> @jsontable.FixedWidthSchema raise {
  @jsontable.parse_fixed_width_schema(
    (
      #|{"version":1,"skip_lines":1,"blank_lines":"skip","columns":[{"name":"id","width":3,"trim":false},{"name":"name","width":8,"trim":true},{"name":"cost","width":5,"trim":true}]}
    ),
  )
}

///|
test "fixed width preserves identifiers and physical source lines" {
  let result = @jsontable.parse_fixed_width(
    "SUPPLIER EXPORT\r\n001Acme    12.50\r\n\r\n002Beta     9.00\r\n",
    fixture_schema(),
  )
  assert_eq(result.table.text_rows(), [
    ["001", "Acme", "12.50"],
    ["002", "Beta", "9.00"],
  ])
  assert_eq(result.source_lines, [2, 4])
  assert_eq(result.skipped_lines, [1, 3])
}

///|
test "fixed width query retains source mapping and formula text" {
  let result = @jsontable.parse_fixed_width(
    "HEADER\n001=1+1     9.00\n002Beta    12.50",
    fixture_schema(),
  )
  let q = @jsontable.parse_query_recipe(
    (
      #|{"version":1,"filters":[],"sort":[{"column":"cost","mode":"number","direction":"desc","blanks":"last"}],"select":["id","name"],"limit":10}
    ),
  )
  let output = result.table.query(q)
  assert_eq(output.source_rows.map(i => result.source_lines[i - 1]), [3, 2])
  assert_eq(output.table.text_rows(), [["002", "Beta"], ["001", "=1+1"]])
}

///|
test "fixed width refuses ragged and unsupported encodings" {
  for
    value in [
      "HEADER\n001short", "HEADER\n001Acme    12.500", "HEADER\n001Acme\t   12.50",
      "HEADER\n001Café    12.50", "HEADER\n001Acme    12.50\r",
    ] {
    assert_true(
      (try? @jsontable.parse_fixed_width(value, fixture_schema())) is Err(_),
    )
  }
}

///|
test "fixed width refuses malformed schemas" {
  for
    value in [
      (
        #|{"version":1,"skip_lines":0,"blank_lines":"skip","columns":[{"name":"id","width":0,"trim":true}]}
      ),
      (
        #|{"version":1,"skip_lines":0,"blank_lines":"skip","columns":[{"name":"id","width":1.5,"trim":true}]}
      ),
      (
        #|{"version":1,"skip_lines":0,"blank_lines":"skip","columns":[{"name":"id","width":3,"trim":true},{"name":"id","width":3,"trim":false}]}
      ),
      (
        #|{"version":1,"skip_lines":0,"blank_lines":"skip","columns":[{"name":"id","width":4096,"trim":true},{"name":"x","width":1,"trim":true}]}
      ),
      (
        #|{"version":1,"skip_lines":0,"blank_lines":"skip","columns":[],"extra":true}
      ),
    ] {
    assert_true((try? @jsontable.parse_fixed_width_schema(value)) is Err(_))
  }
}

///|
test "fixed width empty data and explicit blank handling" {
  let result = @jsontable.parse_fixed_width("HEADER\n", fixture_schema())
  assert_eq(result.table.rows.length(), 0)
  assert_eq(result.table.columns, ["id", "name", "cost"])
  assert_true(
    (try? @jsontable.parse_fixed_width("", fixture_schema())) is Err(_),
  )
  let schema = @jsontable.parse_fixed_width_schema(
    (
      #|{"version":1,"skip_lines":0,"blank_lines":"reject","columns":[{"name":"x","width":3,"trim":false}]}
    ),
  )
  assert_eq(@jsontable.parse_fixed_width("   ", schema).table.text_rows(), [
    ["   "],
  ])
  assert_true((try? @jsontable.parse_fixed_width("\n", schema)) is Err(_))
}
