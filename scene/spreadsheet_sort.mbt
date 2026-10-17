///|
fn finite_sort_number(value : String) -> Double? {
  let number = @string.parse_double(value.trim()[:]) catch { _ => return None }
  if number.is_nan() || number.is_inf() {
    None
  } else {
    Some(number)
  }
}

///|
fn compare_sort_text(left : String, right : String, descending : Bool) -> Int32 {
  if left.is_empty() && right.is_empty() {
    return 0
  }
  if left.is_empty() {
    return 1
  }
  if right.is_empty() {
    return -1
  }
  let comparison = match (finite_sort_number(left), finite_sort_number(right)) {
    (Some(a), Some(b)) => if a < b { -1 } else if a > b { 1 } else { 0 }
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => left.to_lower().compare(right.to_lower())
  }
  if descending {
    -comparison
  } else {
    comparison
  }
}

///| Return stable row indices sorted by one column's display values. Empty

///|
/// values remain last in either direction; numeric values sort numerically.
pub fn sort_row_indices(
  values : Array[String],
  descending : Bool,
) -> Array[Int32] {
  let order : Array[Int32] = []
  for index in 0..<values.length() {
    order.push(index)
  }
  order.sort_by((left, right) => {
    let comparison = compare_sort_text(values[left], values[right], descending)
    if comparison != 0 {
      comparison
    } else {
      left - right
    }
  })
  order
}
