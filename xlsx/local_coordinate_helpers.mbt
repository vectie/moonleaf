///|
/// Compatibility helper for bounded local structure and style operations.
/// Their row-local edits reject explicit cell references belonging to another
/// row; the exact-coordinate text editors keep using cell_location instead.
fn cell_column_or_implicit(
  cell : @xml.Element,
  row : Int,
  previous : Int,
) -> Int raise XlsxError {
  match cell.attribute("r") {
    None => previous + 1
    Some(reference) =>
      match parse_cell_reference(reference) {
        Some((reference_row, column)) if reference_row == row => column
        _ => raise InvalidCellReference(reference)
      }
  }
}

///|
/// Preserve the local operations' explicit-row validation and fallback rules.
fn row_number(row : @xml.Element) -> Int? {
  integer_attribute(row, "r", max_row)
}
