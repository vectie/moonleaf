///|
/// A view filter never changes the workbook or renumbers its source rows.
pub(all) enum RowFilter {
  Contains
  Equals
  NotEmpty
  Empty
}

///|
/// Return zero-based source row indices in their original order. The first
/// row remains visible when it is a header, regardless of the predicate.
/// For example, filtering `["Name", "Alpha", "Beta"]` with `Contains`,
/// query `"alpha"`, and a header returns `[0, 1]`.
pub fn filter_row_indices(
  values : Array[String],
  mode : RowFilter,
  query : String,
  has_header : Bool,
) -> Array[Int] {
  let result : Array[Int] = []
  let needle = query.to_lower()
  for index, value in values {
    if index == 0 && has_header {
      result.push(index)
      continue
    }
    let text = value.to_lower()
    let matches = match mode {
      Contains => text.contains(needle)
      Equals => text == needle
      NotEmpty => !value.trim().is_empty()
      Empty => value.trim().is_empty()
    }
    if matches {
      result.push(index)
    }
  }
  result
}
