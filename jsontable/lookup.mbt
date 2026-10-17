///|
pub(all) suberror LookupError {
  InvalidTable(String)
  UnknownColumn(String)
  DuplicateKey(Int32, Int32)
  InvalidKey(Int32)
  InvalidDelimited(String)
} derive(Debug, Eq)

///|
/// The prepared table and one-based data row identities in both inputs.
/// Missing lookup rows are None. Header rows are not counted.
pub(all) struct LookupResult {
  table : Table
  source_rows : Array[Int32]
  lookup_rows : Array[Int32?]
} derive(Debug, Eq)

///|
/// Read a header-bearing CSV/TSV without guessing number/date types.
pub fn parse_delimited(
  text : String,
  delimiter~ : Char = ',',
) -> Table raise LookupError {
  let parsed = @csv.parse(text, delimiter~) catch {
    InvalidDelimiter =>
      raise InvalidDelimited("Expected comma or tab delimiter")
    InvalidQuote(row~, column~) =>
      raise InvalidDelimited("Invalid quote at row \{row}, column \{column}")
    UnterminatedQuote => raise InvalidDelimited("Unterminated quote")
    TooLarge => raise InvalidDelimited("CSV/TSV parser size limit exceeded")
    _ => raise InvalidDelimited("Invalid delimited input")
  }
  guard parsed.rows.length() > 0 else { raise InvalidTable("Missing header") }
  let table : Table = {
    columns: parsed.rows[0].copy(),
    rows: parsed.rows[1:].to_owned().map(row => row.map(value => Text(value))),
  }
  validate_lookup_table(table)
  table
}

///|
fn validate_lookup_table(table : Table) -> Unit raise LookupError {
  let names : Map[String, Bool] = Map([])
  for name in table.columns {
    if name == "" || names.contains(name) {
      raise InvalidTable("Empty or duplicate column: " + name)
    }
    names[name] = true
  }
  for i, row in table.rows {
    if row.length() != table.columns.length() {
      raise InvalidTable("Ragged data row \{i + 1}")
    }
  }
}

///|
fn lookup_column(table : Table, name : String) -> Int32 raise LookupError {
  for i, column in table.columns {
    if column == name {
      return i
    }
  }
  raise UnknownColumn(name)
}

///|
/// Keys intentionally use exact nonempty text, preserving IDs and leading zeros.
/// Missing/empty left keys are unmatched; lookup keys must all be nonempty text.
fn text_lookup_key(
  value : @scene.CellValue,
  row : Int32,
) -> String? raise LookupError {
  match value {
    Empty | Text("") => None
    Text(text) => Some(text)
    _ => raise InvalidKey(row)
  }
}

///|
/// Enrich each source row with selected columns from a unique-key lookup table.
/// Defaults to a left lookup; matched_only=true omits unmatched source rows.
/// All source columns remain; appended names use prefix, with collisions rejected.
pub fn Table::lookup(
  self : Table,
  other : Table,
  source_key~ : String,
  lookup_key~ : String,
  columns~ : Array[String],
  prefix~ : String = "lookup.",
  matched_only~ : Bool = false,
) -> LookupResult raise LookupError {
  validate_lookup_table(self)
  validate_lookup_table(other)
  let left_key = lookup_column(self, source_key)
  let right_key = lookup_column(other, lookup_key)
  let selected = columns.map(name => lookup_column(other, name))
  let names = self.columns.copy()
  for name in columns {
    let output_name = prefix + name
    if output_name == "" || names.contains(output_name) {
      raise InvalidTable("Output column collision: " + output_name)
    }
    names.push(output_name)
  }
  let index : Map[String, Int32] = Map([])
  for i, row in other.rows {
    let key = lookup_key_value(row[right_key], i + 1)
    match index.get(key) {
      Some(previous) => raise DuplicateKey(previous + 1, i + 1)
      None => index[key] = i
    }
  }
  let rows : Array[Array[@scene.CellValue]] = []
  let source_rows : Array[Int32] = []
  let lookup_rows : Array[Int32?] = []
  for i, row in self.rows {
    let key = text_lookup_key(row[left_key], i + 1)
    let found = match key {
      Some(value) => index.get(value)
      None => None
    }
    if !matched_only || found is Some(_) {
      let output = row.copy()
      for column in selected {
        output.push(
          match found {
            Some(j) => other.rows[j][column]
            None => Empty
          },
        )
      }
      rows.push(output)
      source_rows.push(i + 1)
      lookup_rows.push(found.map(j => j + 1))
    }
  }
  { table: { columns: names, rows, }, source_rows, lookup_rows, }
}

///|
fn lookup_key_value(
  value : @scene.CellValue,
  row : Int32,
) -> String raise LookupError {
  match text_lookup_key(value, row) {
    Some(key) => key
    None => raise InvalidKey(row)
  }
}

///|
pub extend LookupError with @debug.Debug::{to_repr}

///|
pub extend LookupError with Eq::{not_equal, equal}

///|
pub extend LookupResult with @debug.Debug::{to_repr}

///|
pub extend LookupResult with Eq::{not_equal, equal}
