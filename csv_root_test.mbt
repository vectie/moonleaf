///|
test "root viewer dispatches CSV and TSV to workbook scenes" {
  let csv = @moonleaf.open(
    "sample.csv",
    FixedArray::from_array([b'A', b',', b'B', b'\n', b'1', b',', b'2']),
  )
  guard csv is WorkbookDocument(workbook) else { fail("expected CSV workbook") }
  assert_eq(workbook.sheets[0].cells.length(), 4)
  assert_true(workbook.sheets[0].cells[3].value is Text("2"))
  let tsv = @moonleaf.open(
    "sample.tsv",
    FixedArray::from_array([b'A', b'\t', b'B']),
  )
  assert_true(tsv is WorkbookDocument(_))
}
