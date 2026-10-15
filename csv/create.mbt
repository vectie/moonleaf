///|
/// Preserve literal text when a CSV consumer would otherwise interpret it
/// as a formula. Numeric cells use their original numeric representation.
pub fn safe_text(value : String) -> String {
  let mut first : Char? = None
  for char in value.iter() {
    if char != ' ' &&
      char != '\t' &&
      char != '\u{FEFF}' &&
      char != '\r' &&
      char != '\n' {
      first = Some(char)
      break
    }
  }
  match first {
    Some('=') | Some('+') | Some('-') | Some('@') => "'" + value
    _ => value
  }
}

///|
fn created_csv_cell(value : @scene.CellValue) -> String {
  match value {
    Text(text) | Error(text) => safe_text(text)
    Number(text) => text
    Boolean(flag) => if flag { "TRUE" } else { "FALSE" }
    Empty => ""
    Formula(expression~, ..) => safe_text("=" + expression)
  }
}

///|
/// Format one CSV cell with the same literal-text policy as CSV creation.
pub fn cell_text(value : @scene.CellValue) -> String {
  created_csv_cell(value)
}

///|
/// Create the same BOM-prefixed, quoted CSV used by MoonLeaf's CLI, without
/// filesystem access. The shared writer always quotes fields and doubles each
/// embedded quote, so creation does not parse its own complete output again.
pub fn create(
  rows : Array[Array[@scene.CellValue]],
) -> Result[FixedArray[Byte], String] {
  if rows.length() > 50000 {
    return Err("CSV exceeds 50000 rows")
  }
  let mut cells = 0
  let mut text_size = 0
  for row in rows {
    cells += row.length().max(1)
    if row.length() > 256 || cells > 500000 {
      return Err("CSV exceeds cell bounds")
    }
    for value in row {
      text_size += created_csv_cell(value).length()
    }
    if text_size > 8_388_608 {
      return Err("CSV exceeds 8 Mi UTF-16 units of cell text")
    }
  }
  let csv_rows = rows.map(row => {
    if row.is_empty() {
      [""]
    } else {
      row.map(created_csv_cell)
    }
  })
  let table : Table = { rows: csv_rows, delimiter: ',', }
  let line_end = if rows.is_empty() { "" } else { "\r\n" }
  let output = "\u{FEFF}" + table.serialize_quoted() + line_end
  let bytes = @utf8.encode(output).to_fixedarray()
  if bytes.length() > 8388608 {
    return Err("CSV export exceeds MoonLeaf's 8 MiB reader limit")
  }
  Ok(bytes)
}
