///|
test "XLSX sort moves complete rows and preserves cell styles" {
  let bytes = @xlsx.create(
    [
      [@scene.Text("Score"), @scene.Text("Company")],
      [@scene.Number("12"), @scene.Text("Twelve")],
      [@scene.Number("2"), @scene.Text("Two")],
      [@scene.Number("10"), @scene.Text("Ten")],
    ],
    sheet_name="Metrics",
  )
  let archive = @opc.open(bytes).replace_text(
    "xl/worksheets/sheet1.xml",
    (
      #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
      #|<row r="1"><c r="A1" t="inlineStr"><is><t>Score</t></is></c><c r="B1" t="inlineStr"><is><t>Company</t></is></c></row>
      #|<row r="2" ht="32"><c r="A2" s="3"><v>12</v></c><c r="B2" t="inlineStr"><is><t>Twelve</t></is></c></row>
      #|<row r="3" ht="28"><c r="A3" s="4"><v>2</v></c><c r="B3" t="inlineStr"><is><t>Two</t></is></c></row>
      #|<row r="4" ht="30"><c r="A4" s="5"><v>10</v></c><c r="B4" t="inlineStr"><is><t>Ten</t></is></c></row>
      #|</sheetData></worksheet>
    ),
  )
  let (sorted, count) = @xlsx.sort_sheet_rows(
    archive, "Metrics", 1, false, true,
  )
  assert_eq(count, 3)
  let sheet = @xlsx.read(sorted).sheets[0]
  assert_true(sheet.cells[2].value is @scene.Number("2"))
  assert_true(sheet.cells[2].style_id is Some(4))
  assert_true(sheet.cells[3].value is @scene.Text("Two"))
  assert_true(sheet.cells[4].value is @scene.Number("10"))
  assert_true(sheet.cells[6].value is @scene.Number("12"))
  assert_true(sheet.cells[6].style_id is Some(3))
  let xml = sorted.text("xl/worksheets/sheet1.xml")
  assert_true(
    xml.contains("<row r=\"2\" ht=\"28\">") ||
    xml.contains("<row ht=\"28\" r=\"2\">"),
  )
  assert_eq(@xlsx.read(archive).sheets[0].cells[2].row, 2)
  let reopened = @opc.open(@opc.save(sorted))
  assert_eq(@xlsx.read(reopened).sheets[0].cells[2].value, @scene.Number("2"))
}

///|
test "XLSX sort refuses formulas and row-anchored features" {
  let archive = @opc.open(
    @xlsx.create(
      [[@scene.Text("Score")], [@scene.Number("2")], [@scene.Number("1")]],
      sheet_name="Metrics",
    ),
  )
  let formula = archive.replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Score</t></is></c></row><row r=\"2\"><c r=\"A2\"><f>1+1</f><v>2</v></c></row><row r=\"3\"><c r=\"A3\"><v>1</v></c></row></sheetData></worksheet>",
  )
  let rejected = try
    @xlsx.sort_sheet_rows(formula, "Metrics", 1, false, true)
  catch {
    @xlsx.XlsxError::InvalidWorkbook(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
  let merged = archive.replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\"/></row><row r=\"2\"><c r=\"A2\"><v>2</v></c></row><row r=\"3\"><c r=\"A3\"><v>1</v></c></row></sheetData><mergeCells count=\"1\"><mergeCell ref=\"A2:A3\"/></mergeCells></worksheet>",
  )
  let rejected = try
    @xlsx.sort_sheet_rows(merged, "Metrics", 1, false, true)
  catch {
    @xlsx.XlsxError::InvalidWorkbook(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}
