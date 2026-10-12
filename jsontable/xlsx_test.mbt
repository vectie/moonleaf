///|
fn xlsx_selection_fixture(xml : String) -> @opc.Package raise {
  @opc.open(@xlsx.create([], sheet_name="Sheet1")).replace_text(
    "xl/worksheets/sheet1.xml",
    "<worksheet><sheetData>" + xml + "</sheetData></worksheet>",
  )
}

///|
fn extract_range(
  archive : @opc.Package,
  range : String,
  header? : @jsontable.XlsxHeader = @jsontable.FirstRow,
) -> @jsontable.XlsxTable raise {
  @jsontable.extract_xlsx(archive, sheet_name="Sheet1", range~, header~)
}

///|
fn refuses_range(archive : @opc.Package, range : String) -> Unit raise {
  try extract_range(archive, range) catch {
    _ => ()
  } noraise {
    _ => fail("expected selected range refusal")
  }
}

///|
test "xlsx non-A1 dense typed positions and exact headers" {
  let archive = xlsx_selection_fixture(
    "<row r=\"3\"><c r=\"B3\" t=\"inlineStr\"><is><t>id</t></is></c><c r=\"C3\" t=\"str\"><v>amount</v></c><c r=\"D3\" t=\"str\"><v>active</v></c><c r=\"E3\" t=\"str\"><v>note</v></c></row>" +
    "<row r=\"4\"><c r=\"B4\" t=\"str\"><v>001</v></c><c r=\"C4\" s=\"1\"><v>12.50</v></c><c r=\"D4\" t=\"b\"><v>1</v></c><c r=\"E4\" t=\"inlineStr\"><is><t></t></is></c></row>" +
    "<row r=\"6\"><c r=\"B6\" t=\"str\"><v>002</v></c><c r=\"D6\" t=\"b\"><v>false</v></c></row>",
  )
  let before = @opc.save(archive)
  let imported = extract_range(archive, "B3:E7")
  assert_eq(imported.table.columns, ["id", "amount", "active", "note"])
  assert_eq(imported.source_rows, [4, 5, 6, 7])
  assert_eq(imported.table.rows, [
    [
      @scene.Text("001"),
      @scene.Number("12.50"),
      @scene.Boolean(true),
      @scene.Text(""),
    ],
    [@scene.Empty, @scene.Empty, @scene.Empty, @scene.Empty],
    [@scene.Text("002"), @scene.Empty, @scene.Boolean(false), @scene.Empty],
    [@scene.Empty, @scene.Empty, @scene.Empty, @scene.Empty],
  ])
  assert_true(imported.warnings[2].contains("1"))
  imported.table.rows[0][0] = @scene.Text("changed")
  assert_eq(@opc.save(archive), before)
  assert_eq(
    extract_range(archive, "B3:E7").table.rows[0][0],
    @scene.Text("001"),
  )
}

///|
test "xlsx supplied headers preserve first row and isolated arrays" {
  let archive = xlsx_selection_fixture(
    "<row r=\"5\"><c r=\"D5\"><v>60</v></c><c r=\"E5\" t=\"str\"><v>=1+1</v></c></row>",
  )
  let names = ["serial", "literal"]
  let value = extract_range(archive, "D5:E6", header=@jsontable.Columns(names))
  names[0] = "changed"
  assert_eq(value.table.columns, ["serial", "literal"])
  assert_eq(value.source_rows, [5, 6])
  assert_eq(value.table.rows[0], [@scene.Number("60"), @scene.Text("=1+1")])
  let reopened = @jsontable.extract_xlsx(
    @opc.open(value.table.export_xlsx()),
    sheet_name="JSON data",
    range="A1:B3",
    header=@jsontable.FirstRow,
  )
  assert_eq(reopened.table, value.table)
}

///|
test "xlsx selected formulas errors unknown values refused but outside ignored" {
  for
    cell in [
      "<f>1+1</f><v>2</v>", "<f t=\"shared\" si=\"0\"/><v>2</v>", "<v>NaN</v>", "<v>1e999</v>",
      "<v> 2 </v>", "<v>01</v>",
    ] {
    let archive = xlsx_selection_fixture(
      "<row><c r=\"A1\" t=\"str\"><v>h</v></c></row><row><c r=\"A2\">" +
      cell +
      "</c></row>",
    )
    refuses_range(archive, "A1:A2")
    assert_eq(
      extract_range(archive, "C1", header=@jsontable.Columns(["empty"])).table.rows,
      [[@scene.Empty]],
    )
  }
  for kind in ["e", "d", "unsupported"] {
    refuses_range(
      xlsx_selection_fixture(
        "<row><c r=\"A1\" t=\"" + kind + "\"><v>2020</v></c></row>",
      ),
      "A1",
    )
  }
}

///|
test "xlsx intersecting merge and external array formula anchor refused" {
  let archive = xlsx_selection_fixture("")
  let merged = archive.replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet><mergeCells><mergeCell ref=\"A1:C4\"/></mergeCells></worksheet>",
  )
  try extract_range(merged, "B2", header=@jsontable.Columns(["x"])) catch {
    _ => ()
  } noraise {
    _ => fail("merge intersection accepted")
  }
  assert_eq(
    extract_range(merged, "D2", header=@jsontable.Columns(["x"])).table.rows,
    [[@scene.Empty]],
  )
  let formula = xlsx_selection_fixture(
    "<row><c r=\"A1\"><f t=\"array\" ref=\"A1:C4\">1</f><v>1</v></c><c r=\"B2\"><v>1</v></c></row>",
  )
  try extract_range(formula, "B2", header=@jsontable.Columns(["x"])) catch {
    _ => ()
  } noraise {
    _ => fail("array follower accepted")
  }
}

///|
test "xlsx coordinates match sparse unsorted explicit and implicit cells" {
  let archive = xlsx_selection_fixture(
    "<row r=\"8\"><c r=\"D4\" t=\"str\"><v>a</v></c><c t=\"b\"><v>0</v></c></row><row r=\"3\"><c r=\"E3\"><v>9</v></c></row>",
  )
  let result = extract_range(
    archive,
    "D3:E8",
    header=@jsontable.Columns(["a", "b"]),
  )
  assert_eq(result.table.rows[0], [@scene.Empty, @scene.Number("9")])
  assert_eq(result.table.rows[1], [@scene.Text("a"), @scene.Empty])
  assert_eq(result.table.rows[5], [@scene.Empty, @scene.Boolean(false)])
  for
    xml in [
      "<row r=\"0\"/>", "<row r=\"x\"/>", "<row><c r=\"a1\"/></row>", "<row><c r=\"XFE1\"/></row>",
    ] {
    refuses_range(xlsx_selection_fixture(xml), "A1")
  }
}

///|
test "xlsx duplicate selected coordinates and ambiguous payload refused" {
  for
    xml in [
      "<row><c r=\"A1\" t=\"str\"><v>x</v></c><c r=\"A1\"/></row>", "<row><c r=\"A1\" t=\"str\"><v>x</v><v>y</v></c></row>",
      "<row><c r=\"A1\" t=\"str\"><is><t>x</t></is></c></row>", "<row><c r=\"A1\" t=\"inlineStr\"><v>2</v></c></row>",
    ] {
    refuses_range(xlsx_selection_fixture(xml), "A1")
  }
}

///|
test "xlsx duplicate and nontext headers are never invented or renamed" {
  for
    xml in [
      "<row><c t=\"str\"><v>x</v></c><c t=\"str\"><v>x</v></c></row>", "<row><c><v>1</v></c><c t=\"str\"><v>x</v></c></row>",
      "<row><c t=\"str\"><v>x</v></c></row>",
    ] {
    refuses_range(xlsx_selection_fixture(xml), "A1:B2")
  }
}

///|
test "xlsx repeated structural containers refused" {
  let archive = xlsx_selection_fixture("")
  for
    xml in [
      "<worksheet><sheetData/><sheetData/></worksheet>", "<worksheet><mergeCells/><mergeCells><mergeCell ref=\"A1\"/></mergeCells></worksheet>",
    ] {
    refuses_range(archive.replace_text("xl/worksheets/sheet1.xml", xml), "A1")
  }
  refuses_range(
    archive.replace_text(
      "xl/workbook.xml", "<workbook><sheets/><sheets/></workbook>",
    ),
    "A1",
  )
}

///|
test "xlsx 128 column bound and extraction text bound" {
  let empty = xlsx_selection_fixture("")
  assert_eq(
    extract_range(
      empty,
      "A1:DX1",
      header=@jsontable.Columns(Array::makei(128, i => i.to_string())),
    ).table.columns.length(),
    128,
  )
  let data = "x".repeat(3999999)
  let archive = xlsx_selection_fixture(
    "<row><c r=\"A1\" t=\"str\"><v>h</v></c></row><row><c r=\"A2\" t=\"str\"><v>" +
    data +
    "</v></c></row>",
  )
  assert_eq(extract_range(archive, "A1:A2").table.rows[0][0], @scene.Text(data))
  let over = xlsx_selection_fixture(
    "<row><c r=\"A1\" t=\"str\"><v>hh</v></c></row><row><c r=\"A2\" t=\"str\"><v>" +
    data +
    "</v></c></row>",
  )
  refuses_range(over, "A1:A2")
}

///|
test "xlsx header policy and selection bounds" {
  let empty = xlsx_selection_fixture("")
  for
    range in [
      "", "a1", "$A$1", "A1:B0", "B2:A1", "A1,B2", "A1:B2:C3", "XFE1", "A1048577",
      "A1:DY1", "A1:A10002", "A1:CV1001",
    ] {
    refuses_range(empty, range)
  }
  refuses_range(empty, "A1")
  for names in [[""], ["x", "x"], [], ["x", "y", "z"]] {
    try extract_range(empty, "A1:B1", header=@jsontable.Columns(names)) catch {
      _ => ()
    } noraise {
      _ => fail("bad headers accepted")
    }
  }
  assert_eq(
    extract_range(empty, "A1:A10000", header=@jsontable.Columns(["x"])).table.rows.length(),
    10000,
  )
  assert_eq(
    extract_range(
      empty,
      "A1:CV1000",
      header=@jsontable.Columns(Array::makei(100, i => i.to_string())),
    ).table.rows.length(),
    1000,
  )
  assert_eq(
    extract_range(empty, "XFD1048576", header=@jsontable.Columns(["x"])).source_rows,
    [1048576],
  )
  try
    extract_range(empty, "A1:A10001", header=@jsontable.Columns(["x"]))
  catch {
    _ => ()
  } noraise {
    _ => fail("too many data rows")
  }
  let header_only = xlsx_selection_fixture(
    "<row><c r=\"A1\" t=\"str\"><v>h</v></c></row>",
  )
  assert_eq(extract_range(header_only, "A1").table.rows, [])
  assert_eq(extract_range(header_only, "A1:A10001").table.rows.length(), 10000)
}

///|
test "xlsx selected text bound includes supplied headers" {
  let empty = xlsx_selection_fixture("")
  let name = "x".repeat(4000000)
  assert_eq(
    extract_range(empty, "A1", header=@jsontable.Columns([name])).table.columns[0].length(),
    4000000,
  )
  try
    extract_range(empty, "A1", header=@jsontable.Columns([name + "x"]))
  catch {
    _ => ()
  } noraise {
    _ => fail("too much header text")
  }
}
