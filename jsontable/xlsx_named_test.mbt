///|
fn named_fixture(header? : Int = 1, totals? : Int = 1) -> @opc.Package raise {
  let source = @opc.open(@xlsx.create([], sheet_name="Orders"))
  source
  .replace_text(
    "xl/worksheets/sheet1.xml",
    "<worksheet><sheetData>" +
    "<row r=\"3\"><c r=\"B3\" t=\"str\"><v>id</v></c><c r=\"C3\" t=\"str\"><v>amount</v></c></row>" +
    "<row r=\"4\"><c r=\"B4\" t=\"str\"><v>001</v></c><c r=\"C4\"><v>12.50</v></c></row>" +
    "<row r=\"5\"><c r=\"B5\" t=\"str\"><v>002</v></c><c r=\"C5\"><v>8</v></c></row>" +
    "<row r=\"6\"><c r=\"B6\" t=\"str\"><v>Total</v></c><c r=\"C6\"><f>SUM(C4:C5)</f><v>20.5</v></c></row>" +
    "</sheetData><tableParts count=\"1\"><tablePart r:id=\"table1\"/></tableParts></worksheet>",
  )
  .replace_text(
    "xl/worksheets/_rels/sheet1.xml.rels", "<Relationships><Relationship Id=\"table1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/table\" Target=\"../tables/orders.xml\"/></Relationships>",
  )
  .replace_text(
    "xl/tables/orders.xml",
    "<table id=\"1\" displayName=\"OrdersTable\" ref=\"B3:C6\" headerRowCount=\"\{header}\" totalsRowCount=\"\{totals}\"><tableColumns count=\"2\"><tableColumn id=\"1\" name=\"id\"/><tableColumn id=\"2\" name=\"amount\"><totalsRowFormula>SUM(C4:C5)</totalsRowFormula></tableColumn></tableColumns></table>",
  )
}

///|
fn named_refuses(
  source : @opc.Package,
  name? : String = "OrdersTable",
) -> Unit raise {
  try @jsontable.extract_xlsx_named_table(source, table_name=name) catch {
    _ => ()
  } noraise {
    _ => fail("expected named table import refusal")
  }
}

///|
test "named Excel Table resolves metadata and imports data excluding totals" {
  let source = named_fixture()
  let original = @opc.save(source)
  let tables = @xlsx.named_tables(source)
  assert_eq(tables.length(), 1)
  assert_eq(tables[0].name, "OrdersTable")
  assert_eq(tables[0].sheet_name, "Orders")
  assert_eq(tables[0].table_part, "xl/tables/orders.xml")
  assert_eq(tables[0].reference, "B3:C6")
  assert_eq(tables[0].import_reference, Some("B3:C5"))
  assert_eq(tables[0].data_rows, 2)
  let imported = @jsontable.extract_xlsx_named_table(
    source,
    table_name="OrdersTable",
  )
  assert_eq(imported.table.columns, ["id", "amount"])
  assert_eq(imported.source_rows, [4, 5])
  assert_eq(imported.table.rows, [
    [Text("001"), Number("12.50")],
    [Text("002"), Number("8")],
  ])
  imported.table.columns[0] = "changed"
  imported.table.rows[0][0] = Text("changed")
  assert_eq(imported.definition.columns, ["id", "amount"])
  assert_eq(@opc.save(source), original)
  named_refuses(source, name="orderstable")
}

///|
test "named Excel Table headerless data uses metadata and current range" {
  let source = named_fixture(header=0)
  let table_xml = source
    .text("xl/tables/orders.xml")
    .replace(old="B3:C6", new="B4:C6")
  let imported = @jsontable.extract_xlsx_named_table(
    source.replace_text("xl/tables/orders.xml", table_xml),
    table_name="OrdersTable",
  )
  assert_eq(imported.source_rows, [4, 5])
  assert_eq(imported.table.columns, ["id", "amount"])
  assert_eq(imported.table.rows[0], [Text("001"), Number("12.50")])
  let smaller = table_xml.replace(old="B4:C6", new="B4:C5")
  assert_eq(
    @jsontable.extract_xlsx_named_table(
      source.replace_text("xl/tables/orders.xml", smaller),
      table_name="OrdersTable",
    ).source_rows,
    [4],
  )
}

///|
test "named Excel Table empty tables preserve columns" {
  let source = named_fixture(totals=0)
  let xml = source
    .text("xl/tables/orders.xml")
    .replace(old="B3:C6", new="B3:C3")
  let imported = @jsontable.extract_xlsx_named_table(
    source.replace_text("xl/tables/orders.xml", xml),
    table_name="OrdersTable",
  )
  assert_eq(imported.table.rows, [])
  assert_eq(imported.table.columns, ["id", "amount"])
  let totals_only = xml
    .replace(old="headerRowCount=\"1\"", new="headerRowCount=\"0\"")
    .replace(old="totalsRowCount=\"0\"", new="totalsRowCount=\"1\"")
  let empty = @jsontable.extract_xlsx_named_table(
    source.replace_text("xl/tables/orders.xml", totals_only),
    table_name="OrdersTable",
  )
  assert_eq(empty.definition.import_reference, None)
  assert_eq(empty.table.rows, [])
  assert_eq(empty.source_rows, [])
}

///|
test "named Excel Table header and calculated values must agree with import contract" {
  let source = named_fixture()
  let xml = source.text("xl/tables/orders.xml")
  for
    changed in [
      xml.replace(old="name=\"id\"", new="name=\"other\""),
      xml
      .replace(old="<totalsRowFormula>", new="<calculatedColumnFormula>")
      .replace(old="</totalsRowFormula>", new="</calculatedColumnFormula>"),
      xml.replace(old="totalsRowCount=\"1\"", new="totalsRowCount=\"0\""),
    ] {
    named_refuses(source.replace_text("xl/tables/orders.xml", changed))
  }
  let sheet = source.text("xl/worksheets/sheet1.xml")
  for
    changed in [
      sheet.replace(old="<v>12.50</v>", new="<f>1+1</f><v>2</v>"),
      sheet.replace(
        old="</sheetData>",
        new="</sheetData><mergeCells><mergeCell ref=\"B4:C4\"/></mergeCells>",
      ),
    ] {
    named_refuses(source.replace_text("xl/worksheets/sheet1.xml", changed))
  }
}

///|
test "named Excel Table invalid metadata refuses rather than guessing" {
  let source = named_fixture()
  let xml = source.text("xl/tables/orders.xml")
  for
    changed in [
      xml.replace(old="B3:C6", new="bad"),
      xml.replace(old="B3:C6", new="B3:D6"),
      xml.replace(old="B3:C6", new="B3:C10005"),
      xml.replace(old="headerRowCount=\"1\"", new="headerRowCount=\"2\""),
      xml.replace(old="totalsRowCount=\"1\"", new="totalsRowCount=\"2\""),
      xml.replace(old="count=\"2\"", new="count=\"3\""),
      xml.replace(old="name=\"amount\"", new="name=\"id\""),
      xml.replace(old="id=\"2\"", new="id=\"01\""),
      xml.replace(old="<table id", new="<table tableType=\"queryTable\" id"),
      xml.replace(old="<table id", new="<table connectionId=\"2\" id"),
    ] {
    named_refuses(source.replace_text("xl/tables/orders.xml", changed))
  }
}

///|
test "named Excel Table relationship identities resolve exactly" {
  let source = named_fixture()
  let part = "xl/worksheets/_rels/sheet1.xml.rels"
  let links = source.text(part)
  for
    changed in [
      links.replace(old="Target=", new="TargetMode=\"External\" Target="),
      links.replace(
        old="relationships/table",
        new="relationships/table-unsupported",
      ),
      links.replace(old="orders.xml", new="missing.xml"),
      links.replace(old="Id=\"table1\"", new="Id=\"missing\""),
      links.replace(
        old="</Relationships>",
        new="<Relationship Id=\"table1\" Type=\"other\" Target=\"other\"/></Relationships>",
      ),
    ] {
    named_refuses(source.replace_text(part, changed))
  }
  let strict = source.replace_text(
    part,
    links.replace(
      old="http://schemas.openxmlformats.org/officeDocument/2006/relationships/table",
      new="http://purl.oclc.org/ooxml/officeDocument/relationships/table",
    ),
  )
  assert_eq(@xlsx.named_tables(strict)[0].table_part, "xl/tables/orders.xml")
}

///|
test "named Excel Table discovery rejects duplicate references and ambiguous names" {
  let source = named_fixture()
  let sheet = source.text("xl/worksheets/sheet1.xml")
  named_refuses(
    source.replace_text(
      "xl/worksheets/sheet1.xml",
      sheet.replace(old="count=\"1\"", new="count=\"2\""),
    ),
  )
  let duplicate = sheet
    .replace(old="count=\"1\"", new="count=\"2\"")
    .replace(
      old="</tableParts>",
      new="<tablePart r:id=\"table1\"/></tableParts>",
    )
  named_refuses(source.replace_text("xl/worksheets/sheet1.xml", duplicate))
  let second = duplicate.replace(
    old="<tablePart r:id=\"table1\"/></tableParts>",
    new="<tablePart r:id=\"table2\"/></tableParts>",
  )
  let links = source
    .text("xl/worksheets/_rels/sheet1.xml.rels")
    .replace(
      old="</Relationships>",
      new="<Relationship Id=\"table2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/table\" Target=\"../tables/second.xml\"/></Relationships>",
    )
  let another = source
    .replace_text("xl/worksheets/sheet1.xml", second)
    .replace_text("xl/worksheets/_rels/sheet1.xml.rels", links)
    .replace_text("xl/tables/second.xml", source.text("xl/tables/orders.xml"))
  named_refuses(another)
  let renamed = another.replace_text(
    "xl/tables/second.xml",
    source
    .text("xl/tables/orders.xml")
    .replace(old="OrdersTable", new="SecondTable"),
  )
  assert_eq(@xlsx.named_tables(renamed).map(table => table.name), [
    "OrdersTable", "SecondTable",
  ])
}

///|
test "named Excel Table defaults and absent tables remain useful" {
  let source = named_fixture()
  let xml = source
    .text("xl/tables/orders.xml")
    .replace(old=" headerRowCount=\"1\"", new="")
    .replace(old=" totalsRowCount=\"1\"", new="")
    .replace(old="B3:C6", new="B3:C5")
  let imported = @jsontable.extract_xlsx_named_table(
    source.replace_text("xl/tables/orders.xml", xml),
    table_name="OrdersTable",
  )
  assert_eq(imported.source_rows, [4, 5])
  let no_tables = @opc.open(@xlsx.create([], sheet_name="Empty"))
  assert_eq(@xlsx.named_tables(no_tables), [])
  named_refuses(no_tables)
}

///|
test "named Excel Tables remain discoverable beside unrelated chartsheets" {
  let source = named_fixture()
  let workbook = source
    .text("xl/workbook.xml")
    .replace(
      old="</sheets>",
      new="<sheet name=\"Cost chart\" sheetId=\"2\" r:id=\"chart1\"/></sheets>",
    )
  let relationships = source.text("xl/_rels/workbook.xml.rels")
  let expected = @jsontable.extract_xlsx_named_table(
    source,
    table_name="OrdersTable",
  )
  for
    kind in [
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/chartsheet",
      "http://purl.oclc.org/ooxml/officeDocument/relationships/chartsheet",
    ] {
    let links = relationships.replace(
      old="</Relationships>",
      new="<Relationship Id=\"chart1\" Type=\"" +
        kind +
        "\" Target=\"chartsheets/sheet1.xml\"/></Relationships>",
    )
    let with_chart = source
      .replace_text("xl/workbook.xml", workbook)
      .replace_text("xl/_rels/workbook.xml.rels", links)
      .replace_text("xl/chartsheets/sheet1.xml", "<chartsheet/>")
    assert_eq(@xlsx.named_tables(with_chart), @xlsx.named_tables(source))
    assert_eq(
      @jsontable.extract_xlsx_named_table(with_chart, table_name="OrdersTable"),
      expected,
    )
    named_refuses(
      with_chart.replace_text(
        "xl/_rels/workbook.xml.rels",
        links.replace(old=kind, new=kind + "-unknown"),
      ),
    )
    named_refuses(
      with_chart.replace_text(
        "xl/_rels/workbook.xml.rels",
        links.replace(
          old="Id=\"chart1\"",
          new="Id=\"chart1\" TargetMode=\"External\"",
        ),
      ),
    )
  }
}
