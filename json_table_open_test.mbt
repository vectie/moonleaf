///|
test "open JSON arrays and JSONL as workbook scenes" {
  for name in ["data.json", "data.jsonl", "data.ndjson"] {
    let data = if name == "data.json" {
      "[{\"名\":\"猫\"}]"
    } else {
      "{\"名\":\"猫\"}\n"
    }
    guard @moonleaf.open(name, @utf8.encode(data).to_fixedarray())
      is WorkbookDocument(book) else {
      fail("expected workbook")
    }
    assert_eq(book.sheets[0].cells.length(), 2)
    assert_eq(book.sheets[0].cells[1].value, Text("猫"))
  }
}
