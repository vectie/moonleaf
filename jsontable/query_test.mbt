///|
fn recipe(
  filters : String,
  sort : String,
  select : String,
  limit~ : Int32 = 10000,
) -> @jsontable.QueryRecipe raise {
  @jsontable.parse_query_recipe(
    "{\"version\":1,\"filters\":" +
    filters +
    ",\"sort\":" +
    sort +
    ",\"select\":" +
    select +
    ",\"limit\":\{limit}}",
  )
}

///|
test "query reusable AND filtering numeric multicolumn stable sort and projection" {
  let input = @jsontable.parse_delimited(
    "id,team,score,note\n001,A,2,yes\n002,A,10,yes\n003,B,10,yes\n004,A,10,yes\n005,A,99,no\n",
  )
  let saved = input.export_json()
  let r = recipe(
    "[{\"column\":\"note\",\"mode\":\"text\",\"op\":\"eq\",\"value\":\"yes\"},{\"column\":\"score\",\"mode\":\"number\",\"op\":\"ge\",\"value\":2}]",
    "[{\"column\":\"team\",\"mode\":\"text\",\"direction\":\"asc\",\"blanks\":\"last\"},{\"column\":\"score\",\"mode\":\"number\",\"direction\":\"desc\",\"blanks\":\"first\"}]",
    "[\"id\",\"score\"]",
    limit=3,
  )
  let result = input.query(r)
  assert_eq(result.source_rows, [2, 4, 1])
  assert_eq(result.matched_rows, 4)
  assert_eq(result.table.columns, ["id", "score"])
  assert_eq(result.table.rows[0], [Text("002"), Text("10")])
  assert_eq(input.query(r), result)
  assert_eq(input.export_json(), saved)
  result.table.rows[0][0] = Text("changed copy")
  result.table.columns[0] = "changed header"
  assert_eq(input.export_json(), saved)
  assert_eq(input.query(r).table.columns, ["id", "score"])
}

///|
test "query text order differs from explicit numeric order without changing values" {
  let input = @jsontable.parse_delimited("id,v\na,2\nb,10\nc,1e1\n")
  let text = input.query(
    recipe(
      "[]", "[{\"column\":\"v\",\"mode\":\"text\",\"direction\":\"asc\",\"blanks\":\"last\"}]",
      "[\"id\"]",
    ),
  )
  assert_eq(text.source_rows, [2, 3, 1])
  let number = input.query(
    recipe(
      "[]", "[{\"column\":\"v\",\"mode\":\"number\",\"direction\":\"asc\",\"blanks\":\"last\"}]",
      "[\"id\",\"v\"]",
    ),
  )
  assert_eq(number.source_rows, [1, 2, 3])
  assert_eq(number.table.rows[2][1], Text("1e1"))
}

///|
test "query blanks missing and null with direction independent blank order" {
  let input = @jsontable.parse(
    "[{\"id\":\"missing\"},{\"id\":\"empty\",\"v\":\"\"},{\"id\":\"null\",\"v\":null},{\"id\":\"space\",\"v\":\" \"},{\"id\":\"a\",\"v\":\"a\"}]",
  )
  assert_eq(
    input.query(
      recipe(
        "[]", "[{\"column\":\"v\",\"mode\":\"text\",\"direction\":\"desc\",\"blanks\":\"last\"}]",
        "[\"id\"]",
      ),
    ).source_rows,
    [3, 5, 4, 1, 2],
  )
  assert_eq(
    input.query(
      recipe(
        "[]", "[{\"column\":\"v\",\"mode\":\"text\",\"direction\":\"desc\",\"blanks\":\"first\"}]",
        "[\"id\"]",
      ),
    ).source_rows,
    [1, 2, 3, 5, 4],
  )
  for (op, expected) in [("is_blank", [1, 2]), ("not_blank", [3, 4, 5])] {
    assert_eq(
      input.query(
        recipe(
          "[{\"column\":\"v\",\"mode\":\"number\",\"op\":\"\{op}\",\"value\":null}]",
          "[]",
          "[\"id\"]",
        ),
      ).source_rows,
      expected,
    )
  }
  assert_eq(
    input.query(
      recipe(
        "[{\"column\":\"v\",\"mode\":\"text\",\"op\":\"eq\",\"value\":\"null\"}]",
        "[]", "[\"id\"]",
      ),
    ).source_rows,
    [3],
  )
}

///|
test "query comparison operators boolean exact text and contains" {
  let input = @jsontable.parse(
    "[{\"v\":1,\"ok\":false},{\"v\":2,\"ok\":true},{\"v\":3,\"ok\":false},{}]",
  )
  for
    (op, expected) in [
      ("eq", [2]),
      ("ne", [1, 3]),
      ("lt", [1]),
      ("le", [1, 2]),
      ("gt", [3]),
      ("ge", [2, 3]),
    ] {
    assert_eq(
      input.query(
        recipe(
          "[{\"column\":\"v\",\"mode\":\"number\",\"op\":\"\{op}\",\"value\":2}]",
          "[]",
          "[\"v\"]",
        ),
      ).source_rows,
      expected,
    )
  }
  assert_eq(
    input.query(
      recipe(
        "[{\"column\":\"ok\",\"mode\":\"boolean\",\"op\":\"eq\",\"value\":false}]",
        "[{\"column\":\"v\",\"mode\":\"number\",\"direction\":\"desc\",\"blanks\":\"first\"}]",
        "[\"ok\",\"v\"]",
      ),
    ).source_rows,
    [3, 1],
  )
  let text = @jsontable.parse_delimited("v\nAlpha\nalpha\n日本語\n")
  assert_eq(
    text.query(
      recipe(
        "[{\"column\":\"v\",\"mode\":\"text\",\"op\":\"contains\",\"value\":\"日\"}]",
        "[]", "[\"v\"]",
      ),
    ).source_rows,
    [3],
  )
  assert_eq(
    text.query(
      recipe(
        "[{\"column\":\"v\",\"mode\":\"text\",\"op\":\"eq\",\"value\":\"alpha\"}]",
        "[]", "[\"v\"]",
      ),
    ).source_rows,
    [2],
  )
}

///|
test "query validates filtered away rows and explicit modes without coercion" {
  for
    input in [
      "id,v\nx,10\ny,001\n", "id,v\nx,10\ny,NaN\n", "id,v\nx,10\ny,1e999\n", "id,v\nx,10\ny,abc\n",
    ] {
    let table = @jsontable.parse_delimited(input)
    let r = recipe(
      "[{\"column\":\"id\",\"mode\":\"text\",\"op\":\"eq\",\"value\":\"x\"}]",
      "[{\"column\":\"v\",\"mode\":\"number\",\"direction\":\"asc\",\"blanks\":\"last\"}]",
      "[\"id\"]",
      limit=0,
    )
    assert_true(
      try table.query(r) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let typed = @jsontable.parse("[{\"v\":2}]")
  assert_true(
    try
      typed.query(
        recipe(
          "[]", "[{\"column\":\"v\",\"mode\":\"text\",\"direction\":\"asc\",\"blanks\":\"last\"}]",
          "[\"v\"]",
        ),
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let strings = @jsontable.parse_delimited("v\ntrue\n")
  assert_true(
    try
      strings.query(
        recipe(
          "[]", "[{\"column\":\"v\",\"mode\":\"boolean\",\"direction\":\"asc\",\"blanks\":\"last\"}]",
          "[\"v\"]",
        ),
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "query recipe refuses malformed schema limits modes operations and duplicates" {
  for
    bad in [
      "{}", "[]", "broken", "{\"version\":2,\"filters\":[],\"sort\":[],\"select\":[\"v\"],\"limit\":1}",
      "{\"version\":1,\"filters\":[],\"sort\":[],\"select\":[\"v\"],\"limit\":1,\"typo\":0}",
      "{\"version\":1,\"filters\":[],\"sort\":[],\"select\":[\"v\"],\"limit\":1.5}",
    ] {
    assert_true(
      try @jsontable.parse_query_recipe(bad) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  for selected in ["[]", "[\"v\",\"v\"]", "[\"\"]", "[1]"] {
    assert_true(
      try recipe("[]", "[]", selected) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  for limit in [-1, 10001] {
    assert_true(
      try recipe("[]", "[]", "[\"v\"]", limit~) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  for mode in ["guess", "date", "Text"] {
    assert_true(
      try
        recipe(
          "[]",
          "[{\"column\":\"v\",\"mode\":\"\{mode}\",\"direction\":\"asc\",\"blanks\":\"last\"}]",
          "[\"v\"]",
        )
      catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  for
    filter in [
      "{\"column\":\"v\",\"mode\":\"number\",\"op\":\"contains\",\"value\":1}", "{\"column\":\"v\",\"mode\":\"text\",\"op\":\"regex\",\"value\":\"a\"}",
      "{\"column\":\"v\",\"mode\":\"text\",\"op\":\"eq\",\"value\":\"\"}", "{\"column\":\"v\",\"mode\":\"text\",\"op\":\"is_blank\",\"value\":\"x\"}",
    ] {
    assert_true(
      try recipe("[" + filter + "]", "[]", "[\"v\"]") catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "query input shape unknown columns unsupported cells zero rows and explicit zero limit" {
  let r = recipe("[]", "[]", "[\"v\"]")
  for
    bad in [
      @jsontable.Table::{ columns: [], rows: [], },
      { columns: ["v", "v"], rows: [], },
      { columns: ["v"], rows: [[]], },
      { columns: ["other"], rows: [], },
      { columns: ["v"], rows: [[Error("#VALUE!")]], },
    ] {
    assert_true(
      try bad.query(r) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let empty = @jsontable.parse_delimited("v\n")
  assert_eq(empty.query(r).table.columns, ["v"])
  assert_eq(empty.query(r).table.rows, [])
  let one = @jsontable.parse_delimited("v\na\n")
  let zero = one.query(recipe("[]", "[]", "[\"v\"]", limit=0))
  assert_eq(zero.matched_rows, 1)
  assert_eq(zero.source_rows, [])
}

///|
test "query row column and cell boundary validation occurs before limit" {
  let r = recipe("[]", "[]", "[\"0\"]", limit=0)
  let full : @jsontable.Table = {
    columns: ["0"],
    rows: Array::makei(10000, i => [Text(i.to_string())]),
  }
  assert_eq(full.query(r).matched_rows, 10000)
  full.rows.push([Text("extra")])
  assert_true(
    try full.query(r) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let wide : @jsontable.Table = {
    columns: Array::makei(256, i => i.to_string()),
    rows: [],
  }
  assert_eq(wide.query(r).table.rows, [])
  wide.columns.push("256")
  assert_true(
    try wide.query(r) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let cells : @jsontable.Table = {
    columns: Array::makei(10, i => i.to_string()),
    rows: Array::makei(9999, _ => Array::make(10, Empty)),
  }
  assert_eq(cells.query(r).matched_rows, 9999)
  cells.rows.push(Array::make(10, Empty))
  assert_true(
    try cells.query(r) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "query exports preserve projection typing formula looking text and reopen" {
  let input = @jsontable.parse(
    "[{\"id\":\"001\",\"n\":0,\"b\":false,\"s\":\"=1+1\"}]",
  )
  let result = input.query(recipe("[]", "[]", "[\"s\",\"id\",\"n\",\"b\"]")).table
  assert_eq(@jsontable.parse(result.export_json()), result)
  assert_eq(
    @jsontable.parse_delimited(result.export_csv()).text_rows(),
    result.text_rows(),
  )
  let book = @xlsx.read(@opc.open(result.export_xlsx()))
  assert_eq(book.sheets[0].cells[4].value, Text("=1+1"))
  assert_eq(book.sheets[0].cells[5].value, Text("001"))
  assert_eq(book.sheets[0].cells[6].value, Number("0"))
  assert_eq(book.sheets[0].cells[7].value, Boolean(false))
}

///|
test "query bounds recipe lists and rejects unknown filter and sort columns even without rows" {
  let f = "{\"column\":\"v\",\"mode\":\"text\",\"op\":\"eq\",\"value\":\"a\"}"
  assert_true(
    try
      recipe("[" + Array::make(33, f).join(",") + "]", "[]", "[\"v\"]")
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let sorts = Array::makei(9, i => {
    "{\"column\":\"c\{i}\",\"mode\":\"text\",\"direction\":\"asc\",\"blanks\":\"last\"}"
  })
  assert_true(
    try recipe("[]", "[" + sorts.join(",") + "]", "[\"v\"]") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let sort = "{\"column\":\"v\",\"mode\":\"text\",\"direction\":\"asc\",\"blanks\":\"last\"}"
  assert_true(
    try recipe("[]", "[" + sort + "," + sort + "]", "[\"v\"]") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let empty = @jsontable.parse_delimited("other\n")
  assert_true(
    try empty.query(recipe("[" + f + "]", "[]", "[\"other\"]")) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try empty.query(recipe("[]", "[" + sort + "]", "[\"other\"]")) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let input = @jsontable.parse("[{\"v\":true},{\"v\":false},{\"v\":true}]")
  assert_eq(
    input.query(
      recipe(
        "[]", "[{\"column\":\"v\",\"mode\":\"boolean\",\"direction\":\"asc\",\"blanks\":\"last\"}]",
        "[\"v\"]",
      ),
    ).source_rows,
    [2, 1, 3],
  )
}
