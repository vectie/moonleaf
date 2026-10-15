///|
/// Resolve repeated identifier/key cells explicitly. Even identical or empty
/// values are duplicates. First/Last refer to input data row order.
pub(all) enum PivotDuplicates {
  Reject
  First
  Last
} derive(Debug, Eq)

///|
pub(all) suberror PivotError {
  InvalidPivot(String)
  UnknownPivotColumn(String)
  InvalidPivotKey(row~ : Int, column~ : String)
  UnsupportedPivotValue(row~ : Int, column~ : String)
  DuplicatePivotCell(first_row~ : Int, row~ : Int, key~ : String)
} derive(Debug, Eq)

///|
priv struct PivotGroup {
  ids : Array[@scene.CellValue]
  cells : Map[String, (Int, @scene.CellValue)]
}

///|
fn pivot_column(table : Table, name : String) -> Int raise PivotError {
  for index, column in table.columns {
    if column == name {
      return index
    }
  }
  raise UnknownPivotColumn(name)
}

///|
fn pivot_scalar(
  value : @scene.CellValue,
  row~ : Int,
  column~ : String,
) -> Json raise PivotError {
  // Typed JSON framing preserves exact scalar identities without delimiter
  // collisions or lossy numeric conversion. Number payloads remain lexical.
  match value {
    Empty => ["empty"]
    Text(text) => ["text", text]
    Number(text) => ["number", text]
    Boolean(flag) => ["boolean", flag]
    _ => raise UnsupportedPivotValue(row~, column~)
  }
}

///|
fn pivot_size(rows : Int, columns : Int) -> Unit raise PivotError {
  if columns > 256 || rows > 10_000 || (rows + 1) * columns > 100_000 {
    raise InvalidPivot(
      "Result exceeds 256 columns, 10000 rows or 100000 cells including header",
    )
  }
}

///|
/// Widen long observations into one row per exact typed identifier tuple and
/// one column per nonempty text key. IDs and keys follow first appearance;
/// selected ID order is retained. Absent cells are Empty; supplied Empty and
/// Text("") values are retained and participate in duplicate detection.
/// All arrays are fresh, unselected fields are omitted, and formulas/errors in
/// selected columns are rejected. Empty input yields ID columns and no rows.
pub fn Table::pivot(
  self : Table,
  id_columns~ : Array[String],
  key_column~ : String,
  value_column~ : String,
  duplicates? : PivotDuplicates = Reject,
  prefix? : String = "",
) -> Table raise PivotError {
  validate_lookup_table(self) catch {
    _ =>
      raise InvalidPivot(
        "Expected unique nonempty columns and rectangular rows",
      )
  }
  if self.columns.length() > 256 ||
    self.rows.length() > 10_000 ||
    self.columns.length() * self.rows.length() > 100_000 {
    raise InvalidPivot("Input exceeds 256 columns, 10000 rows or 100000 cells")
  }
  let selected : Array[String] = []
  let identifiers : Array[Int] = []
  for column in id_columns {
    if selected.contains(column) {
      raise InvalidPivot("Duplicate identifier column: " + column)
    }
    identifiers.push(pivot_column(self, column))
    selected.push(column)
  }
  for column in [key_column, value_column] {
    if selected.contains(column) {
      raise InvalidPivot("Repeated or overlapping selected column: " + column)
    }
    selected.push(column)
  }
  let key_index = pivot_column(self, key_column)
  let value_index = pivot_column(self, value_column)
  let columns = id_columns.copy()
  let key_names : Array[String] = []
  let seen_keys : Map[String, Bool] = Map([])
  let group_indices : Map[String, Int] = Map([])
  let groups : Array[PivotGroup] = []
  for row_index, row in self.rows {
    let data_row = row_index + 1
    let ids = identifiers.map(index => row[index])
    let encoded : Array[Json] = []
    for index, value in ids {
      encoded.push(pivot_scalar(value, row=data_row, column=id_columns[index]))
    }
    let identity = Json::array(encoded).stringify()
    guard row[key_index] is Text(key) && key != "" else {
      raise InvalidPivotKey(row=data_row, column=key_column)
    }
    let value = row[value_index]
    ignore(pivot_scalar(value, row=data_row, column=value_column))
    if !seen_keys.contains(key) {
      let name = prefix + key
      if columns.contains(name) {
        raise InvalidPivot("Output column collision: " + name)
      }
      pivot_size(groups.length(), columns.length() + 1)
      columns.push(name)
      key_names.push(key)
      seen_keys[key] = true
    }
    let index = match group_indices.get(identity) {
      Some(index) => index
      None => {
        let index = groups.length()
        pivot_size(index + 1, columns.length())
        groups.push({ ids, cells: {}, })
        group_indices[identity] = index
        index
      }
    }
    let cells = groups[index].cells
    match cells.get(key) {
      None => cells[key] = (data_row, value)
      Some((first_row, _)) =>
        match duplicates {
          Reject => raise DuplicatePivotCell(first_row~, row=data_row, key~)
          First => ()
          Last => cells[key] = (first_row, value)
        }
    }
  }
  let rows = groups.map(group => {
    let output = group.ids.copy()
    for key in key_names {
      output.push(
        match group.cells.get(key) {
          Some((_, value)) => value
          None => Empty
        },
      )
    }
    output
  })
  { columns, rows, }
}

///|
pub extend PivotDuplicates with @debug.Debug::{to_repr}

///|
pub extend PivotDuplicates with Eq::{not_equal, equal}

///|
pub extend PivotError with @debug.Debug::{to_repr}

///|
pub extend PivotError with Eq::{not_equal, equal}
