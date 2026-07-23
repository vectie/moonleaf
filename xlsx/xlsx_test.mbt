///|
fn text_part(name : String, content : String) -> @opc.Part {
  { name, content: @utf8.encode(content).to_fixedarray() }
}

///|
fn sample_package() -> @opc.Package {
  {
    parts: [
      text_part(
        "xl/workbook.xml",
        (
          #|<?xml version="1.0" encoding="UTF-8"?>
          #|<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          #| xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          #|  <sheets><sheet name="Budget &amp; Plan" sheetId="1" r:id="rId1"/></sheets>
          #|</workbook>
          #|
        ),
      ),
      text_part(
        "xl/_rels/workbook.xml.rels",
        (
          #|<?xml version="1.0" encoding="UTF-8"?>
          #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          #|  <Relationship Id="rId1"
          #|   Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
          #|   Target="worksheets/sheet1.xml"/>
          #|  <Relationship Id="rId2"
          #|   Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings"
          #|   Target="sharedStrings.xml"/>
          #|  <Relationship Id="rId3"
          #|   Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"
          #|   Target="styles.xml"/>
          #|</Relationships>
          #|
        ),
      ),
      text_part(
        "xl/sharedStrings.xml",
        (
          #|<?xml version="1.0" encoding="UTF-8"?>
          #|<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          #|  <si><r><t>Hello </t></r><r><t>Moon</t></r></si>
          #|</sst>
          #|
        ),
      ),
      text_part(
        "xl/worksheets/sheet1.xml",
        (
          #|<?xml version="1.0" encoding="UTF-8"?>
          #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          #|  <sheetData>
          #|    <row r="1">
          #|      <c r="A1" t="s" s="5"><v>0</v></c>
          #|      <c r="B1" t="inlineStr"><is><r><t>Inline</t></r><r><t> text</t></r></is></c>
          #|      <c r="C1" t="str"><v>plain string</v></c>
          #|      <c r="D1"><v>42.5</v></c>
          #|      <c r="E1" t="b"><v>1</v></c>
          #|      <c r="F1" t="e"><v>#DIV/0!</v></c>
          #|      <c r="G1"><f>SUM(D1,1)</f><v>43.5</v></c>
          #|      <c r="H1"/>
          #|    </row>
          #|  </sheetData>
          #|  <mergeCells count="1"><mergeCell ref="A2:B3"/></mergeCells>
          #|</worksheet>
          #|
        ),
      ),
      text_part("custom/preserved.txt", "leave me alone"),
    ],
  }
}

///|
test "read rejects a sharedStrings relationship type with a malicious suffix" {
  let source = sample_package().replace_text(
    "xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings-malicious\" Target=\"sharedStrings.xml\"/></Relationships>",
  )
  let rejected = try @xlsx.read(source) catch {
    @xlsx.InvalidSharedStringIndex(0) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "read ignores an external sharedStrings relationship" {
  let source = sample_package().replace_text(
    "xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\" TargetMode=\"External\"/></Relationships>",
  )
  let rejected = try @xlsx.read(source) catch {
    @xlsx.InvalidSharedStringIndex(0) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "read resolves purl sharedStrings at its relationship target" {
  let source = sample_package().replace_text(
    "xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://purl.oclc.org/ooxml/officeDocument/relationships/sharedStrings\" Target=\"metadata/purl-strings.xml\"/></Relationships>",
  )
  source.parts.push(
    text_part(
      "xl/metadata/purl-strings.xml", "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>relocated purl text</t></si></sst>",
    ),
  )
  let workbook = @xlsx.read(source)
  assert_true(workbook.sheets[0].cells[0].value == Text("relocated purl text"))
}

///|
test "read reports a missing exact internal sharedStrings target" {
  let source = sample_package().replace_text(
    "xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"missing/sharedStrings.xml\"/></Relationships>",
  )
  let rejected = try @xlsx.read(source) catch {
    @xlsx.PackageFailure(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "read common XLSX workbook cells and merged ranges" {
  let workbook = @xlsx.read(sample_package())
  guard workbook.sheets is [sheet] else { fail("expected one sheet") }
  assert_eq(sheet.name, "Budget & Plan")
  assert_true(
    sheet.cells ==
    [
      { row: 1, column: 1, value: Text("Hello Moon"), style_id: Some(5) },
      { row: 1, column: 2, value: Text("Inline text"), style_id: None },
      { row: 1, column: 3, value: Text("plain string"), style_id: None },
      { row: 1, column: 4, value: Number("42.5"), style_id: None },
      { row: 1, column: 5, value: Boolean(true), style_id: None },
      { row: 1, column: 6, value: Error("#DIV/0!"), style_id: None },
      {
        row: 1,
        column: 7,
        value: Formula(expression="SUM(D1,1)", cached=Some("43.5")),
        style_id: None,
      },
      { row: 1, column: 8, value: Empty, style_id: None },
    ],
  )
  assert_true(
    sheet.merged_ranges ==
    [{ start_row: 2, start_column: 1, end_row: 3, end_column: 2 }],
  )
}

///|
test "set_cell_text preserves package parts and round trips basic text" {
  let original = sample_package()
  let updated = @xlsx.set_cell_text(
    original, "Budget & Plan", 2, 2, "New & <Moon>",
  )
  assert_eq(updated.text("custom/preserved.txt"), "leave me alone")
  assert_eq(
    original.text("xl/worksheets/sheet1.xml"),
    sample_package().text("xl/worksheets/sheet1.xml"),
  )
  let workbook = @xlsx.read(updated)
  guard workbook.sheets is [sheet] else { fail("expected one sheet") }
  assert_true(
    sheet.cells.any(cell => {
      cell.row == 2 && cell.column == 2 && cell.value == Text("New & <Moon>")
    }),
  )
  assert_eq(sheet.merged_ranges.length(), 1)
}

///|
test "set_cell_text replaces a shared string cell but preserves its style" {
  let updated = @xlsx.set_cell_text(
    sample_package(),
    "Budget & Plan",
    1,
    1,
    "Local text",
  )
  let workbook = @xlsx.read(updated)
  guard workbook.sheets is [sheet] else { fail("expected one sheet") }
  guard sheet.cells is [first, ..] else { fail("expected cells") }
  assert_true(first.value == Text("Local text"))
  assert_true(first.style_id == Some(5))
  assert_eq(
    updated.text("xl/sharedStrings.xml"),
    sample_package().text("xl/sharedStrings.xml"),
  )
}

///|
test "set_cell_text creates sheetData in schema order" {
  let source = sample_package().replace_text(
    "xl/worksheets/sheet1.xml",
    (
      #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      #|  <mergeCells count="1"><mergeCell ref="A2:B3"/></mergeCells>
      #|</worksheet>
      #|
    ),
  )
  let updated = @xlsx.set_cell_text(source, "Budget & Plan", 4, 3, "created")
  let worksheet = updated.text("xl/worksheets/sheet1.xml")
  guard (worksheet.find("<sheetData"), worksheet.find("<mergeCells"))
    is (Some(sheet_data_index), Some(merge_cells_index)) else {
    fail("expected sheetData and mergeCells")
  }
  assert_true(sheet_data_index < merge_cells_index)
  let workbook = @xlsx.read(updated)
  guard workbook.sheets is [sheet] else { fail("expected one sheet") }
  assert_true(
    sheet.cells.any(cell => {
      cell.row == 4 && cell.column == 3 && cell.value == Text("created")
    }),
  )
}

///|
test "set_cell_text rejects invalid coordinates" {
  try
    @xlsx.set_cell_text(sample_package(), "Budget & Plan", 0, 1, "bad")
  catch {
    InvalidCoordinates(row=0, column=1) => ()
    error => fail("unexpected error: \{to_repr(error)}")
  } noraise {
    _ => fail("expected invalid coordinates")
  }
}

///|
test "set_cell_text edits implicit prefixed cell without duplicating it" {
  let source = sample_package().replace_text(
    "xl/worksheets/sheet1.xml",
    (
      #|<?xml version="1.0" encoding="UTF-8"?>
      #|<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      #|  <x:sheetData><x:row r="1">
      #|    <x:c s="7" t="inlineStr"><x:is><x:t>first</x:t></x:is></x:c>
      #|    <x:c s="9" t="inlineStr"><x:is><x:t>old</x:t></x:is></x:c>
      #|    <x:c r="D1" s="11" t="inlineStr"><x:is><x:t>later</x:t></x:is></x:c>
      #|  </x:row></x:sheetData>
      #|</x:worksheet>
      #|
    ),
  )
  let updated = @xlsx.set_cell_text(source, "Budget & Plan", 1, 2, "new")
  let xml = updated.text("xl/worksheets/sheet1.xml")
  assert_true(xml.contains("<x:worksheet"))
  assert_true(xml.contains("xmlns:x="))
  assert_true(xml.contains("r=\"B1\""))
  assert_true(xml.contains("s=\"9\""))
  let reopened = @xlsx.read(updated)
  guard reopened.sheets is [sheet] else { fail("expected one sheet") }
  let logical_b1 = sheet.cells.filter(fn(cell) {
    cell.row == 1 && cell.column == 2
  })
  assert_eq(logical_b1.length(), 1)
  guard logical_b1 is [cell] else { fail("expected exactly one B1") }
  assert_true(cell.value == Text("new"))
  assert_true(cell.style_id == Some(9))
  assert_true(sheet.cells.map(fn(cell) { cell.column }) == [1, 2, 4])
}

///|
test "inspect preserves implicit styled-cell semantics in one row" {
  let source = sample_package()
  let parts = source.parts.filter(fn(part) {
    part.name != "xl/worksheets/sheet1.xml"
  })
  parts.push(
    text_part(
      "xl/styles.xml",
      (
        #|<?xml version="1.0" encoding="UTF-8"?>
        #|<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        #|  <cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs>
        #|</styleSheet>
        #|
      ),
    ),
  )
  parts.push(
    text_part(
      "xl/worksheets/sheet1.xml",
      (
        #|<?xml version="1.0" encoding="UTF-8"?>
        #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        #|  <sheetData><row r="1">
        #|    <c s="1" t="s"><v>0</v></c>
        #|    <c s="1"><f>60+1</f><v>61</v></c>
        #|    <c r="D1" s="0"><v>42</v></c>
        #|  </row></sheetData>
        #|</worksheet>
        #|
      ),
    ),
  )
  let opc_package : @opc.Package = { parts, }
  let cells = @xlsx.inspect(opc_package)
  assert_true(cells.map(fn(cell) { cell.column }) == [1, 2, 4])
  guard cells is [a1, b1, d1] else { fail("expected three cells") }
  assert_true(a1.date_time is None)
  assert_true(b1.formula is Some("60+1"))
  assert_true(b1.cached_value is Some("61"))
  assert_true(b1.date_time is Some(_))
  assert_true(d1.display_kind == @xlsx.DisplayKind::General)
  assert_false(
    d1.warnings.any(fn(warning) {
      warning is @xlsx.InspectWarning::UnsupportedNumberFormat(_, _)
    }),
  )
}
