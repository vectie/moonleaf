///|
let max_row : Int32 = 1048576

///|
let max_column : Int32 = 16384

///|
fn parse_decimal(source : String, limit : Int32) -> Int32? {
  if source.length() == 0 {
    return None
  }
  let value = Ref(0)
  for index in 0..<source.length() {
    let code = source[index]
    if code < '0' || code > '9' {
      return None
    }
    let digit = (code - '0').to_int()
    if digit > limit || value.val > (limit - digit) / 10 {
      return None
    }
    value.val = value.val * 10 + digit
  }
  Some(value.val)
}

///|
fn parse_cell_reference(reference : String) -> (Int32, Int32)? {
  let split = Ref(0)
  while split.val < reference.length() &&
        reference[split.val] >= 'A' &&
        reference[split.val] <= 'Z' {
    split.val = split.val + 1
  }
  if split.val == 0 || split.val == reference.length() {
    return None
  }
  let column = Ref(0)
  for index in 0..<split.val {
    let digit = (reference[index] - 'A').to_int() + 1
    if column.val > (max_column - digit) / 26 {
      return None
    }
    column.val = column.val * 26 + digit
  }
  let row_text = "\{reference[split.val:]}"
  match parse_decimal(row_text, max_row) {
    Some(row) if row > 0 && column.val > 0 && column.val <= max_column =>
      Some((row, column.val))
    _ => None
  }
}

///|
fn parse_range_reference(reference : String) -> @scene.CellRange? {
  match reference.find(":") {
    None =>
      match parse_cell_reference(reference) {
        Some((row, column)) =>
          Some({
            start_row: row,
            start_column: column,
            end_row: row,
            end_column: column,
          })
        None => None
      }
    Some(index) => {
      let start = "\{reference[:index]}"
      let finish = "\{reference[index + 1:]}"
      match (parse_cell_reference(start), parse_cell_reference(finish)) {
        (Some((start_row, start_column)), Some((end_row, end_column))) if start_row <=
          end_row &&
          start_column <= end_column =>
          Some({ start_row, start_column, end_row, end_column, })
        _ => None
      }
    }
  }
}

///|
fn column_name(column : Int32) -> String {
  let result : Array[Char] = []
  let value = Ref(column)
  while value.val > 0 {
    let digit = (value.val - 1) % 26
    result.push(Int32::to_char('A'.to_int() + digit).unwrap())
    value.val = (value.val - 1) / 26
  }
  let output = StringBuilder()
  for index = result.length() - 1; index >= 0; index = index - 1 {
    output.write_char(result[index])
  }
  output.to_string()
}

///|
fn cell_reference(row : Int32, column : Int32) -> String {
  "\{column_name(column)}\{row}"
}
