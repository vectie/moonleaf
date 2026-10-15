///|
test "markdown discovers exact source lines and skips fenced and indented examples" {
  let source = "\uFEFF# Notes\r\n\r\n```md\r\n| demo |\r\n| --- |\r\n```\r\n    | code |\r\n    | --- |\r\n\r\n| id | name |\r\n| :--- | ---: |\r\n| 001 | 桜 🌙 |\r\n\r\nteam | owner\r\n--- | :---:\r\nOps | Ada\r\n"
  let tables = @jsontable.parse_markdown_tables(source)
  assert_eq(tables.length(), 2)
  assert_eq(tables[0].id, "table-1")
  assert_eq(tables[0].header_line, 10)
  assert_eq(tables[0].separator_line, 11)
  assert_eq(tables[0].source_lines, [12])
  assert_eq(tables[0].table.text_rows(), [["001", "桜 🌙"]])
  assert_eq(tables[1].id, "table-2")
  assert_eq(tables[1].source_lines, [16])
}

///|
test "markdown escaped pipes backslashes empty cells and inline syntax stay literal" {
  let source =
    #|| ID | Notes | Path | Empty |
    #|| --- | --- | --- | --- |
    #|| 001 | `a\|b` **bold** &amp; [x](url) | C:\\tmp\q | |
    #|| =SUM(1) | final\| | tail\\ | |
  let table = @jsontable.parse_markdown_tables(source)[0].table
  assert_eq(table.text_rows(), [
    ["001", "`a|b` **bold** &amp; [x](url)", "C:\\tmp\\q", ""],
    ["=SUM(1)", "final|", "tail\\", ""],
  ])
  assert_eq(table.rows[0][0], Text("001"))
  assert_eq(table.rows[1][0], Text("=SUM(1)"))
  assert_true(
    try
      @jsontable.parse_markdown_tables(
        "| a | b |\n| --- | --- |\n| `a|b` | c |",
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "markdown selected data queries and exports preserve row provenance and literal values" {
  let imported = @jsontable.parse_markdown_tables(
      "id | cost | note\n--- | --- | ---\n001 | 20 | =literal\n002 | 8 | hold\n003 | 12 | 桜\n",
    )[0]
  let before = imported.table.export_json()
  let query = @jsontable.parse_query_recipe(
    "{\"version\":1,\"filters\":[{\"column\":\"cost\",\"mode\":\"number\",\"op\":\"ge\",\"value\":10}],\"sort\":[{\"column\":\"cost\",\"mode\":\"number\",\"direction\":\"asc\",\"blanks\":\"last\"}],\"select\":[\"id\",\"note\"],\"limit\":10}",
  )
  let result = imported.table.query(query)
  assert_eq(result.table.text_rows(), [["003", "桜"], ["001", "=literal"]])
  assert_eq(result.source_rows.map(i => imported.source_lines[i - 1]), [5, 3])
  assert_eq(@jsontable.parse_delimited(result.table.export_csv()), result.table)
  assert_eq(@jsontable.parse(result.table.export_json()), result.table)
  let archive = @opc.open(result.table.export_xlsx())
  let reopened = @jsontable.extract_xlsx(
    archive,
    sheet_name="JSON data",
    range="A1:B3",
    header=FirstRow,
  )
  assert_eq(reopened.table, result.table)
  result.table.rows[0][0] = Text("copy")
  assert_eq(imported.table.export_json(), before)
}

///|
test "markdown rejects ambiguous headers and ragged selected or later rows" {
  for
    source in [
      "a | a\n--- | ---\nx | y", "| | a |\n| --- | --- |", "a | b\n--- | --- | ---",
      "a | b\n--- | ---\nx | y\nz | z | extra",
    ] {
    assert_true(
      try @jsontable.parse_markdown_tables(source) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  try @jsontable.parse_markdown_tables("a | b\n--- | ---\nx | y | z") catch {
    error =>
      assert_eq(
        error,
        InvalidMarkdownTable(
          line=3,
          reason="Ragged row: expected 2 cells, found 3",
        ),
      )
  } noraise {
    _ => fail("expected operation to fail")
  }
  assert_true(
    try
      @jsontable.parse_markdown_tables(
        "| good |\n| --- |\n| yes |\n\n| bad | bad |\n| --- | --- |",
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "markdown allows header only and one column with explicit pipe syntax" {
  let tables = @jsontable.parse_markdown_tables(
    "| Name |\n| :---: |\n\nleft | right\n--- | ---\n| | |\n",
  )
  assert_eq(tables.length(), 2)
  assert_eq(tables[0].table.columns, ["Name"])
  assert_eq(tables[0].table.rows, [])
  assert_eq(tables[1].table.text_rows(), [["", ""]])
}

///|
test "markdown requires bounded cell and row counts and explicit line endings" {
  for
    source in [
      "| a |\n| --- |\n| a\rb |", "| a |\r\r\n| --- |", "| a |\n| --- |\n| \u0000 |",
    ] {
    assert_true(
      try @jsontable.parse_markdown_tables(source) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let large = StringBuilder()
  large.write_string("| h |\n| --- |\n| ")
  for _ in 0..<16385 {
    large.write_char('x')
  }
  large.write_string(" |")
  assert_true(
    try @jsontable.parse_markdown_tables(large.to_string()) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let rows = StringBuilder()
  rows.write_string("| h |\n| --- |\n")
  for _ in 0..<10001 {
    rows.write_string("| x |\n")
  }
  assert_true(
    try @jsontable.parse_markdown_tables(rows.to_string()) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "markdown fence closure honors marker length and trailing content" {
  let source = "~~~~md\n| skip |\n| --- |\n~~~\n```\n~~~~ trailing\n| still |\n| --- |\n~~~~\n| actual |\n| --- |\n| value |\n```unclosed\n| ignored |\n| --- |"
  let tables = @jsontable.parse_markdown_tables(source)
  assert_eq(tables.length(), 1)
  assert_eq(tables[0].header_line, 10)
  assert_eq(tables[0].source_lines, [12])
}

///|
test "markdown no table is distinct from an empty selected table" {
  assert_eq(@jsontable.parse_markdown_tables("# Notes\nno tables\n"), [])
  assert_eq(@jsontable.parse_markdown_tables("a | b\n-- | ---\nx | y"), [])
  let empty = @jsontable.parse_markdown_tables("| a | b |\n| --- | --- |")
  assert_eq(empty.length(), 1)
  assert_eq(empty[0].table.export_json(), "[]")
  assert_eq(empty[0].source_lines, [])
}
