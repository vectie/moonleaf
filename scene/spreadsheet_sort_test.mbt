///|
test "spreadsheet sort orders numbers naturally and keeps blanks last" {
  let values = ["12", "2", "", "Alpha", "alpha", "10", ""]
  assert_eq(@scene.sort_row_indices(values, false), [1, 5, 0, 3, 4, 2, 6])
  assert_eq(@scene.sort_row_indices(values, true), [3, 4, 0, 5, 1, 2, 6])
}
