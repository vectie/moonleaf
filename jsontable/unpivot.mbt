///|
pub(all) suberror UnpivotError {
  InvalidUnpivot(String)
  UnknownUnpivotColumn(String)
  UnsupportedUnpivotValue(row~ : Int, column~ : String)
} derive(Debug, Eq)

///|
fn unpivot_column(table : Table, name : String) -> Int raise UnpivotError {
  for index, column in table.columns {
    if column == name {
      return index
    }
  }
  raise UnknownUnpivotColumn(name)
}

///|
fn unpivot_scalar(
  value : @scene.CellValue,
  row~ : Int,
  column~ : String,
) -> Unit raise UnpivotError {
  match value {
    Empty | Text(_) | Number(_) | Boolean(_) => ()
    _ => raise UnsupportedUnpivotValue(row~, column~)
  }
}

///|
/// Turn selected value columns into name/value rows while repeating identifier
/// columns. Output follows input row order, then value_columns order. All arrays
/// are fresh; scalar types and exact column names are retained. Unselected fields
/// are omitted. drop_empty skips Empty and Text("") only, never zero or false.
pub fn Table::unpivot(
  self : Table,
  id_columns~ : Array[String],
  value_columns~ : Array[String],
  names_to? : String = "variable",
  values_to? : String = "value",
  drop_empty? : Bool = false,
) -> Table raise UnpivotError {
  validate_lookup_table(self) catch {
    _ =>
      raise InvalidUnpivot(
        "Expected unique nonempty columns and rectangular rows",
      )
  }
  if self.columns.length() > 256 ||
    self.rows.length() > 10_000 ||
    self.columns.length() * self.rows.length() > 100_000 {
    raise InvalidUnpivot(
      "Input exceeds 256 columns, 10000 rows or 100000 cells",
    )
  }
  if value_columns.is_empty() || id_columns.length() + 2 > 256 {
    raise InvalidUnpivot(
      "Expected value columns and at most 256 output columns",
    )
  }
  let selected : Array[String] = []
  let identifiers : Array[Int] = []
  for column in id_columns {
    if selected.contains(column) {
      raise InvalidUnpivot("Duplicate identifier column: " + column)
    }
    identifiers.push(unpivot_column(self, column))
    selected.push(column)
  }
  let values : Array[Int] = []
  for column in value_columns {
    if selected.contains(column) {
      raise InvalidUnpivot("Repeated or overlapping value column: " + column)
    }
    values.push(unpivot_column(self, column))
    selected.push(column)
  }
  let columns = id_columns.copy()
  for name in [names_to, values_to] {
    if name == "" || columns.contains(name) {
      raise InvalidUnpivot("Empty or duplicate output column: " + name)
    }
    columns.push(name)
  }
  let rows : Array[Array[@scene.CellValue]] = []
  for row_index, row in self.rows {
    for index in identifiers {
      unpivot_scalar(row[index], row=row_index + 1, column=self.columns[index])
    }
    for index in values {
      let value = row[index]
      unpivot_scalar(value, row=row_index + 1, column=self.columns[index])
      if drop_empty && (value is Empty || value is Text("")) {
        continue
      }
      if rows.length() >= 10_000 ||
        (rows.length() + 2) * columns.length() > 100_000 {
        raise InvalidUnpivot(
          "Result exceeds 10000 rows or 100000 cells including header",
        )
      }
      let output = identifiers.map(index => row[index])
      output.push(@scene.Text(self.columns[index]))
      output.push(value)
      rows.push(output)
    }
  }
  { columns, rows, }
}
