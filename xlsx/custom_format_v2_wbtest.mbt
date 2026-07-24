///|
test "custom format v2 exact classification matrix" {
  let cases : Array[(String, DisplayKind)] = [
    ("mmm/mm", Date),
    ("h:mm", Time),
    ("mm:ss", Time),
    ("yyyy-mm-dd h:mm", DateTime),
    ("[h]", Time),
    ("[hh]", Time),
    ("[m]", Time),
    ("[mm]", Time),
    ("[s]", Time),
    ("[ss]", Time),
    ("0\\d", Number),
    ("0_d", Number),
    ("0*d", Number),
    ("yyyy-mm-dd;;;@", Date),
    ("yyyy-mm-dd;;", Date),
    ("0;[Red]-0;0;@", Number),
  ]
  for item in cases {
    let (code, expected) = item
    let (kind, malformed, ambiguous) = custom_format_kind_v2(code)
    assert_true(kind == expected)
    assert_false(malformed)
    assert_false(ambiguous)
  }
}

///|
test "custom format v2 reports ambiguity separately" {
  for code in ["yyyy-mm-dd;0", "yyyy;hh"] {
    let (kind, malformed, ambiguous) = custom_format_kind_v2(code)
    assert_true(kind == Unsupported)
    assert_false(malformed)
    assert_true(ambiguous)
  }
}

///|
test "custom format v2 reports malformed syntax" {
  let malformed_cases = [
    "\"unterminated", "[unterminated", "0\\", "0_", "0*", "0;0;0;@;0",
  ]
  for code in malformed_cases {
    let (kind, malformed, ambiguous) = custom_format_kind_v2(code)
    assert_true(kind == Unsupported)
    assert_true(malformed)
    assert_false(ambiguous)
  }
}
