///|
test "pivot spec requires selections and defaults to rejecting duplicates" {
  assert_eq(
    parse_spec(
      (
        #|{"id_columns":["id"],"key_column":"month","value_column":"sales"}
      ),
    ),
    (["id"], "month", "sales", @jsontable.Reject, ""),
  )
  assert_eq(
    parse_spec(
      (
        #|{"id_columns":[],"key_column":"k","value_column":"v","duplicates":"last","prefix":"v."}
      ),
    ),
    ([], "k", "v", @jsontable.Last, "v."),
  )
  assert_eq(
    parse_spec(
      (
        #|{"id_columns":[],"key_column":"k","value_column":"v","duplicates":"first"}
      ),
    ),
    ([], "k", "v", @jsontable.First, ""),
  )
}

///|
test "pivot spec rejects unknown fields invalid types and guessed policies" {
  for
    input in [
      "[]",
      "{}",
      (
        #|{"id_columns":"id","key_column":"k","value_column":"v"}
      ),
      (
        #|{"id_columns":[1],"key_column":"k","value_column":"v"}
      ),
      (
        #|{"id_columns":[],"key_column":1,"value_column":"v"}
      ),
      (
        #|{"id_columns":[],"key_column":"k","value_column":false}
      ),
      (
        #|{"id_columns":[],"key_column":"k","value_column":"v","duplicates":"sum"}
      ),
      (
        #|{"id_columns":[],"key_column":"k","value_column":"v","prefix":1}
      ),
      (
        #|{"id_columns":[],"key_column":"k","value_column":"v","drop_empty":true}
      ),
    ] {
    assert_true(
      try parse_spec(input) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}
