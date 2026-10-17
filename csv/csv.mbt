///|
/// A bounded, Unicode-aware delimited table for CSV and TSV previews.
pub(all) struct Table {
  rows : Array[Array[String]]
  delimiter : Char
}

///|
pub(all) suberror CsvError {
  InvalidDelimiter
  InvalidQuote(row~ : Int32, column~ : Int32)
  InvalidCoordinates(row~ : Int32, column~ : Int32)
  UnterminatedQuote
  TooLarge
}

///|
/// Parse RFC 4180 quotes, escaped quotes and CRLF. TSV uses the same quoting.
pub fn parse(text : String, delimiter~ : Char = ',') -> Table raise CsvError {
  if delimiter != ',' && delimiter != '\t' {
    raise InvalidDelimiter
  }
  if text.length() > 8_388_608 {
    raise TooLarge
  }
  let delimiter_unit = delimiter.to_int().to_uint16()
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut field = StringBuilder()
  let mut quoted = false
  let mut closed_quote = false
  let mut at_field_start = true
  let mut index = if text.length() > 0 && text[0] == '\u{FEFF}' { 1 } else { 0 }
  let mut row_number = 1
  let mut cells = 0
  for ; index < text.length(); {
    let char = text[index]
    if quoted {
      if char == '"' {
        if index + 1 < text.length() && text[index + 1] == '"' {
          field.write_char('"')
          index += 2
        } else {
          quoted = false
          closed_quote = true
          index += 1
        }
      } else {
        let start = index
        while index < text.length() && text[index] != '"' {
          index += 1
        }
        field.write_string(text[start:index].to_owned())
      }
    } else if char == '"' {
      if !at_field_start {
        raise InvalidQuote(row=row_number, column=row.length() + 1)
      }
      quoted = true
      at_field_start = false
      index += 1
    } else if char == delimiter_unit || char == '\n' || char == '\r' {
      row.push(field.to_string())
      cells += 1
      if cells > 500_000 || row.length() > 256 {
        raise TooLarge
      }
      field = StringBuilder()
      at_field_start = true
      closed_quote = false
      if char == delimiter_unit {
        index += 1
      } else {
        rows.push(row)
        if rows.length() > 50_000 {
          raise TooLarge
        }
        row = []
        row_number += 1
        if char == '\r' && index + 1 < text.length() && text[index + 1] == '\n' {
          index += 2
        } else {
          index += 1
        }
      }
    } else {
      if closed_quote {
        raise InvalidQuote(row=row_number, column=row.length() + 1)
      }
      let start = index
      while index < text.length() &&
            text[index] != delimiter_unit &&
            text[index] != '\n' &&
            text[index] != '\r' &&
            text[index] != '"' {
        index += 1
      }
      field.write_string(text[start:index].to_owned())
      at_field_start = false
    }
  }
  if quoted {
    raise UnterminatedQuote
  }
  if row.length() > 0 ||
    !at_field_start ||
    (text.length() > 0 && text[text.length() - 1] == delimiter_unit) {
    row.push(field.to_string())
    cells += 1
    if cells > 500_000 || row.length() > 256 || rows.length() >= 50_000 {
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
    // A final empty row needs an explicit quoted field; otherwise it is
    // indistinguishable from the line terminator before it on reopening.
    if row_index == self.rows.length() - 1 && row == [""] {
      output.write_string("\"\"")
      continue
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
      write_csv_span(output, value, escape)
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
      write_csv_span(output, value, true)
      output.write_char('"')
    }
  }
  output.to_string()
}

///|
/// Write unchanged spans in bulk; only literal quotation marks need doubling.
fn write_csv_span(output : StringBuilder, value : String, quote : Bool) -> Unit {
  if !quote {
    output.write_string(value)
    return
  }
  let mut first = true
  for span in value.split("\"") {
    if !first {
      output.write_string("\"\"")
    }
    output.write_string(span.to_owned())
    first = false
  }
}

///|
/// Return an edited copy of a table, keeping blank intermediate cells.
pub fn Table::set_cell_text(
  self : Table,
  row : Int32,
  column : Int32,
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
    rows.push([""])
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
  if cells > 100_000 || text_size > 8_388_608 {
    raise TooLarge
  }
  { rows, delimiter: self.delimiter, }
}

///|
/// Insert blank rows before the 1-based row coordinate. A distant insertion
/// materializes intervening blank rows because CSV has no sparse row syntax.
pub fn Table::insert_rows(
  self : Table,
  at : Int32,
  count : Int32,
) -> Table raise CsvError {
  if at < 1 ||
    at > 10_000 ||
    count < 1 ||
    count > 100 ||
    at + count - 1 > 10_000 ||
    self.rows.length() + count > 10_000 {
    raise InvalidCoordinates(row=at, column=1)
  }
  let rows : Array[Array[String]] = []
  for index in 0..<(at - 1) {
    if index < self.rows.length() {
      rows.push(self.rows[index].copy())
    } else {
      rows.push([""])
    }
  }
  for _ in 0..<count {
    rows.push([""])
  }
  for index in (at - 1)..<self.rows.length() {
    rows.push(self.rows[index].copy())
  }
  if rows.length() > 10_000 {
    raise TooLarge
  }
  let mut cells = 0
  for item in rows {
    cells += item.length()
  }
  if cells > 100_000 {
    raise TooLarge
  }
  { rows, delimiter: self.delimiter, }
}

///|
/// Delete up to `count` rows, shifting following CSV rows up. The source
/// table is unchanged and a deletion beyond its last row is a no-op.
pub fn Table::delete_rows(
  self : Table,
  at : Int32,
  count : Int32,
) -> (Table, Int32) raise CsvError {
  if at < 1 ||
    at > 10_000 ||
    count < 1 ||
    count > 100 ||
    at + count - 1 > 10_000 {
    raise InvalidCoordinates(row=at, column=1)
  }
  if at > self.rows.length() {
    return (self, 0)
  }
  let changed = if count < self.rows.length() - at + 1 {
    count
  } else {
    self.rows.length() - at + 1
  }
  let rows : Array[Array[String]] = []
  for index, row in self.rows {
    if index < at - 1 || index >= at - 1 + changed {
      rows.push(row.copy())
    }
  }
  ({ rows, delimiter: self.delimiter, }, changed)
}

///|
/// Insert blank columns before a 1-based column, materializing any gap in
/// each existing row. The original table remains unchanged.
pub fn Table::insert_columns(
  self : Table,
  at : Int32,
  count : Int32,
) -> Table raise CsvError {
  if at < 1 || at > 256 || count < 1 || count > 100 || at + count - 1 > 256 {
    raise InvalidCoordinates(row=1, column=at)
  }
  let rows : Array[Array[String]] = []
  let mut cells = 0
  for row in self.rows {
    let width = if row.length() >= at { row.length() } else { at - 1 }
    if width + count > 256 {
      raise TooLarge
    }
    let edited : Array[String] = []
    for index in 0..<(at - 1) {
      edited.push(row.get(index).unwrap_or(""))
    }
    for _ in 0..<count {
      edited.push("")
    }
    for index in (at - 1)..<row.length() {
      edited.push(row[index])
    }
    cells += edited.length()
    if cells > 100_000 {
      raise TooLarge
    }
    rows.push(edited)
  }
  { rows, delimiter: self.delimiter, }
}

///|
/// Delete existing columns at a 1-based coordinate and shift later values
/// left. The count reports the maximum existing column span removed across
/// ragged rows; deleting beyond every row is a no-op.
pub fn Table::delete_columns(
  self : Table,
  at : Int32,
  count : Int32,
) -> (Table, Int32) raise CsvError {
  if at < 1 || at > 256 || count < 1 || count > 100 || at + count - 1 > 256 {
    raise InvalidCoordinates(row=1, column=at)
  }
  let rows : Array[Array[String]] = []
  let mut changed = 0
  for row in self.rows {
    let available = if row.length() >= at { row.length() - at + 1 } else { 0 }
    let removed = if available < count { available } else { count }
    if removed > changed {
      changed = removed
    }
    let edited : Array[String] = []
    for index, value in row {
      if index < at - 1 || index >= at - 1 + count {
        edited.push(value)
      }
    }
    // A CSV row has at least one field even when every column was removed.
    if edited.is_empty() {
      edited.push("")
    }
    rows.push(edited)
  }
  ({ rows, delimiter: self.delimiter, }, changed)
}

///|
/// Apply several cell edits to one copied table. Coordinates are 1-based and
/// must be unique; either every edit succeeds or the source table is unchanged.
pub fn Table::set_cells_text(
  self : Table,
  edits : Array[(Int32, Int32, String)],
) -> Table raise CsvError {
  if edits.is_empty() {
    return self
  }
  if edits.length() > 1_000 {
    raise TooLarge
  }
  let seen : Map[Int32, Bool] = Map([])
  for (row, column, value) in edits {
    if row < 1 || row > 10_000 || column < 1 || column > 256 {
      raise InvalidCoordinates(row~, column~)
    }
    if value.length() > 32_768 {
      raise TooLarge
    }
    let coordinate = (row - 1) * 256 + column
    if seen.get(coordinate) is Some(_) {
      raise InvalidCoordinates(row~, column~)
    }
    seen[coordinate] = true
  }
  let rows = self.rows.map(item => item.copy())
  let mut cells = 0
  let mut text_size = 0
  for item in rows {
    cells += item.length()
    for value in item {
      text_size += value.length()
    }
  }
  for (row, column, value) in edits {
    while rows.length() < row {
      rows.push([""])
      cells += 1
      if cells > 100_000 {
        raise TooLarge
      }
    }
    let target = rows[row - 1]
    if target.length() < column {
      cells += column - target.length()
      if cells > 100_000 {
        raise TooLarge
      }
      while target.length() < column {
        target.push("")
      }
    }
    text_size += value.length() - target[column - 1].length()
    if text_size > 8_388_608 {
      raise TooLarge
    }
    target[column - 1] = value
  }
  { rows, delimiter: self.delimiter, }
}

///|
/// Project a table into MoonLeaf's neutral spreadsheet scene.
pub fn Table::workbook(
  self : Table,
  name~ : String = "工作表1",
) -> @scene.Workbook {
  let cells : Array[@scene.Cell] = []
  for row_index, row in self.rows {
    for column_index, value in row {
      cells.push({
        row: row_index + 1,
        column: column_index + 1,
        value: if value == "" {
          Empty
        } else {
          Text(value)
        },
        style_id: None,
      })
    }
  }
  { sheets: [{ name, cells, merged_ranges: [], }], warnings: [], }
}
