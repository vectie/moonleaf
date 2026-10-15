///|
fn comparison_fixture(cells : String) -> @opc.Package raise {
  let p = @opc.open(@xlsx.create([[Text("fixture")]], sheet_name="Budget"))
  p.replace_text(
    "xl/worksheets/sheet1.xml",
    "<worksheet><sheetData><row r=\"1\">" +
    cells +
    "</row></sheetData></worksheet>",
  )
}

///|
test "workbook comparison separates formula expression cached value and formula metadata" {
  let original = comparison_fixture(
    "<c r=\"A1\"><f>1+1</f><v>2</v></c>" +
    "<c r=\"B1\"><f>2+2</f><v>4</v></c>" +
    "<c r=\"C1\"><f t=\"shared\" si=\"1\"/><v>7</v></c>" +
    "<c r=\"D1\"><f>9+1</f></c>",
  )
  let copy = comparison_fixture(
    "<c r=\"D1\"><f>9+1</f><v></v></c>" +
    "<c r=\"C1\"><f t=\"shared\" si=\"2\"/><v>7</v></c>" +
    "<c r=\"B1\"><f>2+2</f><v>8</v></c>" +
    "<c r=\"A1\"><f>SUM(1,1)</f><v>2</v></c>",
  )
  let result = @xlsx.compare_workbooks(original, copy)
  assert_eq(result.changed_cells, 4)
  let cells = result.sheets[0].cells
  assert_eq(cells.map(c => c.address), ["A1", "B1", "C1", "D1"])
  assert_eq(cells[0].changes, ["formula"])
  assert_eq(cells[1].changes, ["cached_value"])
  assert_eq(cells[2].changes, ["formula_metadata"])
  assert_eq(cells[3].changes, ["cached_value"])
  assert_eq(cells[3].before.unwrap().value, None)
  assert_eq(cells[3].after.unwrap().value, Some(""))
  assert_eq(cells[2].before.unwrap().formula, Some(""))
  assert_eq(@xlsx.compare_workbooks(original, original).changed_cells, 0)
  let reordered_attributes = original.replace_text(
    "xl/worksheets/sheet1.xml",
    original
    .text("xl/worksheets/sheet1.xml")
    .replace(old="t=\"shared\" si=\"1\"", new="si=\"1\" t=\"shared\""),
  )
  assert_eq(
    @xlsx.compare_workbooks(original, reordered_attributes).changed_cells,
    0,
  )
}

///|
test "workbook comparison preserves typed values exact numbers explicit blanks and Unicode" {
  let a = comparison_fixture(
    "<c r=\"A1\" t=\"inlineStr\"><is><t>001</t></is></c>" +
    "<c r=\"B1\"><v>1.0</v></c><c r=\"C1\" t=\"b\"><v>1</v></c>" +
    "<c r=\"D1\" t=\"e\"><v>#N/A</v></c><c r=\"F1\"/>",
  )
  let b = comparison_fixture(
    "<c r=\"A1\"><v>1</v></c><c r=\"B1\"><v>1</v></c>" +
    "<c r=\"C1\" t=\"b\"><v>true</v></c>" +
    "<c r=\"D1\" t=\"inlineStr\"><is><t>#N/A</t></is></c>" +
    "<c r=\"E1\" t=\"inlineStr\"><is><t>雪😀 &amp; &lt;</t></is></c>" +
    "<c r=\"G1\" t=\"inlineStr\"><is><t></t></is></c>",
  )
  let original_bytes = @opc.save(a)
  let copy_bytes = @opc.save(b)
  let result = @xlsx.compare_workbooks(a, b)
  assert_eq(result.changed_cells, 6)
  let cells = result.sheets[0].cells
  assert_eq(cells.map(c => c.address), ["A1", "B1", "D1", "E1", "F1", "G1"])
  assert_eq(cells[0].before.unwrap().value_type, "text")
  assert_eq(cells[0].after.unwrap().value_type, "number")
  assert_eq(cells[3].changes, ["added"])
  assert_eq(cells[3].after.unwrap().value, Some("雪😀 & <"))
  assert_eq(cells[4].changes, ["removed"])
  assert_eq(cells[5].after.unwrap().value, Some(""))
  assert_eq(@opc.save(a), original_bytes)
  assert_eq(@opc.save(b), copy_bytes)
}

///|
test "workbook comparison follows resolved text instead of shared string index or formatting" {
  let shared = inspect_fixture(
    "",
    None,
    Some("<sst><si><t>same</t></si><si><t>other</t></si></sst>"),
    "<c r=\"A1\" t=\"s\"><v>0</v></c>",
  )
  let reindexed = inspect_fixture(
    "",
    None,
    Some("<sst><si><t>other</t></si><si><t>same</t></si></sst>"),
    "<c r=\"A1\" t=\"s\" s=\"9\"><v>1</v></c>",
  )
  let inline = inspect_fixture(
    "",
    None,
    None,
    "<c r=\"A1\" t=\"inlineStr\"><is><r><rPr><b/></rPr><t>sa</t></r><r><t>me</t></r></is></c>",
  )
  assert_eq(@xlsx.compare_workbooks(shared, reindexed).sheets, [])
  assert_eq(@xlsx.compare_workbooks(shared, inline).sheets, [])
  assert_true(@xlsx.compare_workbooks(shared, inline).warnings.length() > 0)
}

///|
test "workbook comparison detects visibility merges sheet addition and date system" {
  let a = comparison_fixture("<c r=\"A1\"><v>42</v></c>")
  let workbook = a.text("xl/workbook.xml")
  let b = a
    .replace_text(
      "xl/workbook.xml",
      workbook
      .replace(old="<sheets>", new="<workbookPr date1904=\"1\"/><sheets>")
      .replace(old="name=\"Budget\"", new="state=\"hidden\" name=\"Budget\""),
    )
    .replace_text(
      "xl/worksheets/sheet1.xml", "<worksheet><sheetData><row r=\"1\"><c r=\"A1\"><v>42</v></c></row></sheetData><mergeCells><mergeCell ref=\"A1:B1\"/></mergeCells></worksheet>",
    )
  let result = @xlsx.compare_workbooks(a, b)
  assert_eq(result.changed_cells, 0)
  assert_true(result.date_system_changed)
  assert_eq(result.sheets[0].changes, ["visibility", "merges"])
  assert_eq(result.sheets[0].after_merges, ["A1:B1"])
  let renamed = b.replace_text(
    "xl/workbook.xml",
    b.text("xl/workbook.xml").replace(old="Budget", new="budget"),
  )
  let names = @xlsx.compare_workbooks(a, renamed)
  assert_eq(names.sheets.map(s => s.name), ["Budget", "budget"])
  assert_eq(names.sheets[0].changes, ["removed", "cells"])
  assert_eq(names.sheets[1].changes, ["added", "cells"])
}

///|
test "workbook comparison refuses ambiguous coordinates types and payloads before returning partial changes" {
  let valid = comparison_fixture("<c r=\"A1\"><v>1</v></c>")
  let cases = [
    "<c r=\"A1\"><v>2</v></c><c r=\"A01\"><v>3</v></c>", "<c r=\"A2\"><v>2</v></c>",
    "<c r=\"XFE1\"><v>2</v></c>", "<c r=\"A1\" t=\"unknown\"><v>2</v></c>", "<c r=\"A1\"><v>2</v><v>3</v></c>",
    "<c r=\"A1\"><f>1</f><f>2</f></c>", "<c r=\"A1\" t=\"inlineStr\"><is><t>x</t></is><v>3</v></c>",
    "<c r=\"A1\" t=\"s\"><v>999</v></c>",
  ]
  for cells in cases {
    assert_true(
      try @xlsx.compare_workbooks(valid, comparison_fixture(cells)) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  assert_eq(@xlsx.compare_workbooks(valid, valid).sheets, [])
}

///|
test "workbook comparison includes sparse edge coordinates and resolves implicit positions" {
  let a = comparison_fixture(
    "<c t=\"inlineStr\"><is><t>a</t></is></c><c><v>1</v></c>",
  )
  let b = comparison_fixture(
    "<c r=\"B1\"><v>2</v></c><c r=\"A1\" t=\"inlineStr\"><is><t>a</t></is></c>",
  )
  assert_eq(@xlsx.compare_workbooks(a, b).sheets[0].cells[0].address, "B1")
  let edge = a.replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet><sheetData><row r=\"1048576\"><c r=\"XFD1048576\"><v>9</v></c></row></sheetData></worksheet>",
  )
  let result = @xlsx.compare_workbooks(edge, edge)
  assert_eq(result.changed_cells, 0)
}

///|
test "workbook comparison keeps JSON optional fields unwrapped and exposes formula value transitions" {
  let a = comparison_fixture("<c r=\"A1\"><f>1+1</f><v>2</v></c>")
  let b = comparison_fixture(
    "<c r=\"A1\" t=\"inlineStr\"><is><t>2</t></is></c><c r=\"B1\"/>",
  )
  let result = @xlsx.compare_workbooks(a, b)
  assert_eq(result.sheets[0].cells[0].changes, ["formula", "value"])
  guard result.to_json()
    is {
      "sheets": [
        {
          "cells": [
            {
              "before": { "formula": String("1+1"), "value": String("2"), .. },
              "after": { "formula": Null, "value_type": String("text"), .. },
              ..
            },
            {
              "before": Null,
              "after": { "value": Null, "value_type": String("empty"), .. },
              ..
            },
          ],
          ..
        },
      ],
      ..
    } else {
    fail("comparison JSON must use null and scalar optional fields")
  }
}

///|
test "workbook comparison rejects duplicate names relationships and aliased worksheet parts" {
  let a = comparison_fixture("")
  let original_xml = a.text("xl/workbook.xml")
  let variants = [
    original_xml.replace(
      old="</sheets>",
      new="<sheet name=\"Budget\" sheetId=\"2\" r:id=\"rId1\"/></sheets>",
    ),
    original_xml.replace(
      old="</sheets>",
      new="<sheet name=\"Alias\" sheetId=\"2\" r:id=\"rId1\"/></sheets>",
    ),
    original_xml.replace(
      old="<sheets>",
      new="<workbookPr date1904=\"maybe\"/><sheets>",
    ),
    original_xml.replace(old="<sheets>", new="<sheets/><sheets>"),
  ]
  for xml in variants {
    try
      @xlsx.compare_workbooks(a, a.replace_text("xl/workbook.xml", xml))
    catch {
      _ => ()
    } noraise {
      _ => fail("ambiguous workbook comparison must refuse")
    }
  }
  let relationships = a.text("xl/_rels/workbook.xml.rels")
  let duplicate = relationships.replace(
    old="</Relationships>",
    new="<Relationship Id=\"rId1\" Type=\"unexpected\" Target=\"wrong.xml\"/></Relationships>",
  )
  try
    @xlsx.compare_workbooks(
      a,
      a.replace_text("xl/_rels/workbook.xml.rels", duplicate),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("duplicate relationship must refuse")
  }
}

///|
fn comparison_many_cells(count : Int) -> @opc.Package raise {
  let output = StringBuilder()
  output.write_string("<worksheet><sheetData>")
  for i in 0..<count {
    if i % 16384 == 0 {
      output.write_string("<row>")
    }
    output.write_string("<c/>")
    if i % 16384 == 16383 || i == count - 1 {
      output.write_string("</row>")
    }
  }
  output.write_string("</sheetData></worksheet>")
  comparison_fixture("").replace_text(
    "xl/worksheets/sheet1.xml",
    output.to_string(),
  )
}

///|
test "workbook comparison accepts its explicit cell boundary and refuses one over" {
  let empty = comparison_fixture("")
  let boundary = comparison_many_cells(100000)
  assert_eq(@xlsx.compare_workbooks(boundary, empty).changed_cells, 100000)
  try @xlsx.compare_workbooks(empty, comparison_many_cells(100001)) catch {
    @xlsx.InvalidWorkbook(message) =>
      assert_true(message.contains("100000 explicit cells"))
    _ => fail("expected explicit cell limit")
  } noraise {
    _ => fail("one over explicit cell limit must refuse")
  }
}

///|
test "workbook comparison refuses expanded shared text beyond its text budget" {
  let text = String::make(1000, 'x')
  let cells = StringBuilder()
  for _ in 0..<4001 {
    cells.write_string("<c t=\"s\"><v>0</v></c>")
  }
  let large = inspect_fixture(
    "",
    None,
    Some("<sst><si><t>" + text + "</t></si></sst>"),
    cells.to_string(),
  )
  try @xlsx.compare_workbooks(comparison_fixture(""), large) catch {
    @xlsx.InvalidWorkbook(message) =>
      assert_true(message.contains("4000000 text units"))
    _ => fail("expected expanded text budget")
  } noraise {
    _ => fail("expanded shared strings must count toward text budget")
  }
}
