///|
/// A bounded, Unicode-aware delimited table for CSV and TSV previews.
pub(all) struct Table {
  rows : Array[Array[String]]
  delimiter : Char
}

///|
pub(all) suberror CsvError {
  InvalidDelimiter
  InvalidQuote(row~ : Int, column~ : Int)
  InvalidCoordinates(row~ : Int, column~ : Int)
  UnterminatedQuote
  TooLarge
}

///|
/// Parse RFC 4180 quotes, escaped quotes and CRLF. TSV uses the same quoting.
pub fn parse(text : String, delimiter? : Char = ',') -> Table raise CsvError {
  if delimiter != ',' && delimiter != '\t' {
    raise InvalidDelimiter
  }
  if text.length() > 2_097_152 {
    raise TooLarge
  }
  let chars : Array[Char] = []
  for char in text.iter() {
    chars.push(char)
  }
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut field = StringBuilder()
  let mut quoted = false
  let mut closed_quote = false
  let mut at_field_start = true
  let mut index = if chars.length() > 0 && chars[0] == '\u{FEFF}' {
    1
  } else {
    0
  }
  let mut row_number = 1
  let mut cells = 0
  for ; index < chars.length(); {
    let char = chars[index]
    if quoted {
      if char == '"' {
        if index + 1 < chars.length() && chars[index + 1] == '"' {
          field.write_char('"')
          index += 2
        } else {
          quoted = false
          closed_quote = true
          index += 1
        }
      } else {
        field.write_char(char)
        index += 1
      }
    } else if char == '"' {
      if !at_field_start {
        raise InvalidQuote(row=row_number, column=row.length() + 1)
      }
      quoted = true
      at_field_start = false
      index += 1
    } else if char == delimiter || char == '\n' || char == '\r' {
      row.push(field.to_string())
      cells += 1
      if cells > 100_000 || row.length() > 256 {
        raise TooLarge
      }
      field = StringBuilder()
      at_field_start = true
      closed_quote = false
      if char == delimiter {
        index += 1
      } else {
        rows.push(row)
        if rows.length() > 10_000 {
          raise TooLarge
        }
        row = []
        row_number += 1
        if char == '\r' &&
          index + 1 < chars.length() &&
          chars[index + 1] == '\n' {
          index += 2
        } else {
          index += 1
        }
      }
    } else {
      if closed_quote {
        raise InvalidQuote(row=row_number, column=row.length() + 1)
      }
      field.write_char(char)
      at_field_start = false
      index += 1
    }
  }
  if quoted {
    raise UnterminatedQuote
  }
  if row.length() > 0 ||
    !at_field_start ||
    (chars.length() > 0 && chars[chars.length() - 1] == delimiter) {
    row.push(field.to_string())
    cells += 1
    if cells > 100_000 || row.length() > 256 || rows.length() >= 10_000 {
      raise TooLarge
    }
    rows.push(row)
  }
  { rows, delimiter, }
}

///|
/// Export a parsed table without changing its cell values.
pub fn Table::serialize(self : Table) -> String {
  let output = StringBuilder()
  for row_index, row in self.rows {
    if row_index > 0 {
      output.write_string("\r\n")
    }
    for column_index, value in row {
      if column_index > 0 {
        output.write_char(self.delimiter)
      }
      let mut escape = false
      for char in value.iter() {
        if char == self.delimiter || char == '"' || char == '\r' || char == '\n' {
          escape = true
          break
        }
      }
      if escape {
        output.write_char('"')
      }
      for char in value.iter() {
        if char == '"' {
          output.write_char('"')
        }
        output.write_char(char)
      }
      if escape {
        output.write_char('"')
      }
    }
  }
  output.to_string()
}

///|
/// Serialize every field in quotes for stable spreadsheet exports.
pub fn Table::serialize_quoted(self : Table) -> String {
  let output = StringBuilder()
  for row_index, row in self.rows {
    if row_index > 0 {
      output.write_string("\r\n")
    }
    for column_index, value in row {
      if column_index > 0 {
        output.write_char(self.delimiter)
      }
      output.write_char('"')
      for char in value.iter() {
        if char == '"' {
          output.write_char('"')
        }
        output.write_char(char)
      }
      output.write_char('"')
    }
  }
  output.to_string()
}

///|
/// Return an edited copy of a table, keeping blank intermediate cells.
pub fn Table::set_cell_text(
  self : Table,
  row : Int,
  column : Int,
  value : String,
) -> Table raise CsvError {
  if row < 1 || row > 10_000 || column < 1 || column > 256 {
    raise InvalidCoordinates(row~, column~)
  }
  if value.length() > 32_768 {
    raise TooLarge
  }
  let rows = self.rows.map(item => item.copy())
  while rows.length() < row {
    rows.push([])
  }
  let target = rows[row - 1]
  while target.length() < column {
    target.push("")
  }
  target[column - 1] = value
  let mut cells = 0
  let mut text_size = 0
  for item in rows {
    cells += item.length()
    for cell in item {
      text_size += cell.length()
    }
  }
  if cells > 100_000 || text_size > 2_000_000 {
    raise TooLarge
  }
  { rows, delimiter: self.delimiter, }
}

///|
/// Project a table into MoonLeaf's neutral spreadsheet scene.
pub fn Table::workbook(
  self : Table,
  name? : String = "工作表1",
) -> @scene.Workbook {
  let cells : Array[@scene.Cell] = []
  for row_index, row in self.rows {
    for column_index, value in row {
      cells.push({
        row: row_index + 1,
        column: column_index + 1,
        value: if value == "" {
          @scene.Empty
        } else {
          @scene.Text(value)
        },
        style_id: None,
      })
    }
  }
  { sheets: [{ name, cells, merged_ranges: [], }], warnings: [], }
}
