///|
test "spreadsheet filter keeps original row indices and header" {
  let values = ["Name", "Alpha", "beta", "ALPHABET", "", "西瓜"]
  assert_eq(@scene.filter_row_indices(values, Contains, "alpha", true), [
    0, 1, 3,
  ])
  assert_eq(@scene.filter_row_indices(values, Equals, "BETA", false), [2])
  assert_eq(@scene.filter_row_indices(values, NotEmpty, "", true), [
    0, 1, 2, 3, 5,
  ])
  assert_eq(@scene.filter_row_indices(values, Empty, "", true), [0, 4])
}
