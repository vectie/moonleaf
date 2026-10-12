///|
test "spreadsheet filter keeps original row indices and header" {
  let values = ["Name", "Alpha", "beta", "ALPHABET", "", "西瓜"]
  assert_eq(@scene.filter_row_indices(values, @scene.Contains, "alpha", true), [
    0, 1, 3,
  ])
  assert_eq(@scene.filter_row_indices(values, @scene.Equals, "BETA", false), [2])
  assert_eq(@scene.filter_row_indices(values, @scene.NotEmpty, "", true), [
    0, 1, 2, 3, 5,
  ])
  assert_eq(@scene.filter_row_indices(values, @scene.Empty, "", true), [0, 4])
}
