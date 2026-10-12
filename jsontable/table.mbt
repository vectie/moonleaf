///|
/// A JSON object collection projected onto the union of its top-level keys.
/// Column order follows first appearance. Missing fields are blank; null is
/// literal "null". Nested arrays and objects remain compact JSON text.
pub(all) struct Table {
  columns : Array[String]
  rows : Array[Array[@scene.CellValue]]
} derive(Debug, Eq)

///|
pub(all) suberror TableError {
  InvalidJson(String)
  ExpectedArray
  ExpectedObject(Int)
  Export(String)
} derive(Debug, Eq)

///|
fn cell_value(value : Json) -> @scene.CellValue {
  match value {
    String(text) => Text(text)
    Number(_) => Number(value.stringify())
    True => Boolean(true)
    False => Boolean(false)
    _ => Text(value.stringify())
  }
}

///|
/// Parse an array of objects, or one object per nonblank line with jsonl=true.
pub fn parse(text : String, jsonl? : Bool = false) -> Table raise TableError {
  let objects : Array[Map[String, Json]] = []
  if jsonl {
    for line_index, line in text.split("\n").to_array() {
      let line = line.trim().to_string()
      if line != "" {
        let value = @json.parse(line) catch {
          _ => raise InvalidJson("Invalid JSON on line \{line_index + 1}")
        }
        guard value is Object(object) else {
          raise ExpectedObject(line_index + 1)
        }
        objects.push(object)
      }
    }
  } else {
    let value = @json.parse(text) catch {
      _ => raise InvalidJson("Expected a JSON array of objects")
    }
    guard value is Array(values) else { raise ExpectedArray }
    for index, value in values {
      guard value is Object(object) else { raise ExpectedObject(index + 1) }
      objects.push(object)
    }
  }
  let columns : Array[String] = []
  let seen : Map[String, Bool] = {}
  for object in objects {
    for key, _ in object {
      if !seen.contains(key) {
        seen[key] = true
        columns.push(key)
      }
    }
  }
  let rows = objects.map(object => {
    columns.map(key => {
      match object.get(key) {
        Some(value) => cell_value(value)
        None => @scene.Empty
      }
    })
  })
  { columns, rows, }
}

///|
pub fn Table::text_rows(self : Table) -> Array[Array[String]] {
  self.rows.map(row => {
    row.map(value => {
      match value {
        Empty => ""
        Text(text) | Number(text) | Error(text) => text
        Boolean(value) => if value { "true" } else { "false" }
        Formula(expression~, ..) => expression
      }
    })
  })
}

///|
pub fn Table::export_csv(self : Table) -> String {
  let table : @csv.Table = {
    rows: [self.columns] + self.text_rows(),
    delimiter: ',',
  }
  table.serialize_quoted()
}

///|
pub fn Table::export_xlsx(self : Table) -> FixedArray[Byte] raise TableError {
  @xlsx.create(
    [self.columns.map(column => @scene.Text(column))] + self.rows,
    sheet_name="JSON data",
  ) catch {
    error => raise Export("\{Repr(error)}")
  }
}

///|
pub fn Table::workbook(self : Table) -> @scene.Workbook {
  let cells : Array[@scene.Cell] = []
  let rows : Array[Array[@scene.CellValue]] = [
      self.columns.map(column => @scene.Text(column)),
    ] +
    self.rows
  for row_index, row in rows {
    for column_index, value in row {
      cells.push({
        row: row_index + 1,
        column: column_index + 1,
        value,
        style_id: None,
      })
    }
  }
  { sheets: [{ name: "JSON data", cells, merged_ranges: [], }], warnings: [], }
}
