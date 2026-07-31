///|
test "parse decimal handles coordinate edges and rejects malformed values" {
  let cases = [
    ("-2147483648", -2147483648),
    ("-1", -1),
    ("0", 0),
    ("2147483647", 2147483647),
  ]
  for pair in cases {
    assert_eq(parse_decimal("coordinate-test", pair.0), pair.1)
  }
  for malformed in ["", "-", "+1", "1.0", "2147483648", "-2147483649"] {
    try ignore(parse_decimal("coordinate-test", malformed)) catch {
      InvalidNumber(..) => continue
      _ => fail("expected InvalidNumber")
    } noraise {
      _ => fail("expected InvalidNumber")
    }
  }
}
