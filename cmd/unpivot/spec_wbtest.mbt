///|
test "unpivot spec defaults and explicit options" {
  assert_eq(
    parse_spec(
      (
        #|{"id_columns":[],"value_columns":["Jan"]}
      ),
    ),
    ([], ["Jan"], "variable", "value", false),
  )
  assert_eq(
    parse_spec(
      (
        #|{"id_columns":["id"],"value_columns":["Jan","Feb"],"names_to":"month","values_to":"sales","drop_empty":true}
      ),
    ),
    (["id"], ["Jan", "Feb"], "month", "sales", true),
  )
}

///|
test "unpivot spec requires correctly typed selection fields" {
  for
    input in [
      "[]",
      "{}",
      (
        #|{"id_columns":[],"value_columns":"Jan"}
      ),
      (
        #|{"id_columns":[1],"value_columns":["Jan"]}
      ),
      (
        #|{"id_columns":[],"value_columns":["Jan"],"drop_empty":"true"}
      ),
      (
        #|{"id_columns":[],"value_columns":["Jan"],"names_to":1}
      ),
      (
        #|{"id_columns":[],"value_columns":["Jan"],"values_to":false}
      ),
      (
        #|{"id_columns":[],"value_columns":["Jan"],"drop_blank":true}
      ),
    ] {
    assert_true((try? parse_spec(input)) is Err(_))
  }
}
