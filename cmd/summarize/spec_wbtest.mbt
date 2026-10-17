///|
test "summary CLI specification selects grouping and named measures" {
  let (keys, measures) = parse_spec(
    "{\"group_by\":[\"region\"],\"measures\":[{\"name\":\"n\",\"op\":\"count\"},{\"name\":\"total\",\"op\":\"sum\",\"column\":\"amount\"},{\"name\":\"average\",\"op\":\"mean\",\"column\":\"amount\"}]}",
  )
  assert_eq(keys, ["region"])
  assert_eq(measures, [
    { name: "n", operation: CountRows, },
    { name: "total", operation: Sum("amount"), },
    { name: "average", operation: Mean("amount"), },
  ])
}

///|
test "summary CLI specification errors are actionable" {
  for
    spec in [
      "{}", "{\"group_by\":[1],\"measures\":[]}", "{\"group_by\":[],\"measures\":[{}]}",
      "{\"group_by\":[],\"measures\":[{\"name\":\"x\",\"op\":\"sum\"}]}", "{\"group_by\":[],\"measures\":[{\"name\":\"x\",\"op\":\"median\",\"column\":\"amount\"}]}",
    ] {
    try parse_spec(spec) catch {
      _ => ()
    } noraise {
      _ => fail("Expected invalid spec to fail")
    }
  }
}
