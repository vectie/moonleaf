///|
test "numbering integer parsing preserves defaults and rejects malformed values" {
  assert_eq(parse_int_or(Some("12"), 1), 12)
  assert_eq(parse_int_or(Some("-3"), 1), -3)
  assert_eq(parse_int_or(None, 1), 1)
  assert_eq(parse_int_or(Some(""), 1), 1)
  assert_eq(parse_int_or(Some("12px"), 1), 1)
  assert_eq(parse_int_or(Some("999999999999999999999"), 1), 1)
}

///|
test "cached page count rejects non-positive malformed and overflowing values" {
  for value in ["0", "-1", "bad", "12pages", "999999999999999999999"] {
    let empty : @opc.Package = { parts: [], }
    let archive = empty.replace_text(
      "docProps/app.xml",
      "<Properties><Pages>" + value + "</Pages></Properties>",
    )
    assert_eq(cached_page_count(archive), None)
  }
  let empty : @opc.Package = { parts: [], }
  let archive = empty.replace_text(
    "docProps/app.xml", "<Properties><Pages>12</Pages></Properties>",
  )
  assert_eq(cached_page_count(archive), Some(12))
}
