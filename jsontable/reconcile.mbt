///|
pub(all) suberror ReconcileError {
  InvalidReconcile(String)
  InvalidReconcileKey(side~ : String, row~ : Int32, column~ : String)
  DuplicateReconcileKey(side~ : String, first_row~ : Int32, row~ : Int32)
  UnsupportedReconcileValue(side~ : String, row~ : Int32, column~ : String)
} derive(Debug, Eq)

///|
fn reconcile_shape(table : Table, side : String) -> Unit raise ReconcileError {
  if table.columns.is_empty() ||
    table.columns.length() > 256 ||
    table.rows.length() > 10_000 ||
    (table.rows.length() + 1) * table.columns.length() > 100_000 {
    raise InvalidReconcile(
      "Input " +
      side +
      " needs 1–256 columns, at most 10000 rows and 100000 cells including header",
    )
  }
  validate_lookup_table(table) catch {
    _ =>
      raise InvalidReconcile(
        "Input " + side + " needs unique nonempty headers and rectangular rows",
      )
  }
}

///|
fn reconcile_column(table : Table, name : String) -> Int32 raise ReconcileError {
  lookup_column(table, name) catch {
    _ => raise InvalidReconcile("Unknown column: " + name)
  }
}

///|
fn reconcile_index(
  table : Table,
  keys : Array[Int32],
  side : String,
) -> (Map[String, Int32], Array[String]) raise ReconcileError {
  let index : Map[String, Int32] = Map([])
  let identities : Array[String] = []
  for i, row in table.rows {
    for c, value in row {
      match value {
        Empty | Text(_) | Number(_) | Boolean(_) => ()
        _ =>
          raise UnsupportedReconcileValue(
            side~,
            row=i + 1,
            column=table.columns[c],
          )
      }
    }
    let encoded : Array[Json] = []
    for c in keys {
      match row[c] {
        Text(value) if value != "" => encoded.push(Json::string(value))
        _ =>
          raise InvalidReconcileKey(side~, row=i + 1, column=table.columns[c])
      }
    }
    // JSON array encoding prevents separators, quotes and Unicode in one key
    // component from colliding with another component's boundary.
    let identity = Json::array(encoded).stringify()
    match index.get(identity) {
      Some(first) =>
        raise DuplicateReconcileKey(side~, first_row=first + 1, row=i + 1)
      None => index[identity] = i
    }
    identities.push(identity)
  }
  (index, identities)
}

///|
fn reconcile_append(
  rows : Array[Array[@scene.CellValue]],
  row : Array[@scene.CellValue],
) -> Unit raise ReconcileError {
  if rows.length() >= 10_000 || (rows.length() + 2) * row.length() > 100_000 {
    raise InvalidReconcile(
      "Result exceeds 10000 rows or 100000 cells including header",
    )
  }
  rows.push(row)
}

///|
/// Compare two scalar snapshots with the same exact header set. Unique nonempty
/// text keys may be composite. All non-key fields are compared with CellValue
/// equality, without numeric coercion, whitespace normalization or rounding.
/// Rows follow before order, then additions in after order. Key columns lead;
/// status and one-based input row references precede paired before/after fields.
/// Inputs are not mutated. Filtering unchanged rows never skips input validation.
pub fn Table::reconcile(
  self : Table,
  after : Table,
  key_columns~ : Array[String],
  include_unchanged~ : Bool = true,
) -> Table raise ReconcileError {
  reconcile_shape(self, "before")
  reconcile_shape(after, "after")
  if self.columns.length() != after.columns.length() ||
    self.columns.any(name => !after.columns.contains(name)) {
    raise InvalidReconcile(
      "Snapshots need identical header sets; reordered columns are allowed",
    )
  }
  if key_columns.is_empty() {
    raise InvalidReconcile("At least one key column is required")
  }
  let keys : Array[String] = []
  for name in key_columns {
    if keys.contains(name) {
      raise InvalidReconcile("Duplicate key column: " + name)
    }
    keys.push(name)
  }
  let before_keys = keys.map(name => reconcile_column(self, name))
  let after_keys = keys.map(name => reconcile_column(after, name))
  let values = self.columns.filter(name => !keys.contains(name))
  let before_values = values.map(name => reconcile_column(self, name))
  let after_values = values.map(name => reconcile_column(after, name))
  let columns = keys.copy()
  for name in ["_change", "_before_row", "_after_row"] {
    if columns.contains(name) {
      raise InvalidReconcile("Output column collision: " + name)
    }
    columns.push(name)
  }
  for value in values {
    for prefix in ["before.", "after."] {
      let name = prefix + value
      if columns.contains(name) {
        raise InvalidReconcile("Output column collision: " + name)
      }
      columns.push(name)
    }
  }
  if columns.length() > 256 {
    raise InvalidReconcile("Result exceeds 256 columns")
  }
  let (before_index, before_ids) = reconcile_index(self, before_keys, "before")
  let (after_index, after_ids) = reconcile_index(after, after_keys, "after")
  let rows : Array[Array[@scene.CellValue]] = []
  for i, row in self.rows {
    let found = after_index.get(before_ids[i])
    let change = match found {
      None => "removed"
      Some(j) => {
        let same = before_values
          .mapi((v, c) => row[c] == after.rows[j][after_values[v]])
          .all(value => value)
        if same {
          "unchanged"
        } else {
          "changed"
        }
      }
    }
    if include_unchanged || change != "unchanged" {
      let output = before_keys.map(c => row[c])
      output.push(Text(change))
      output.push(Number((i + 1).to_string()))
      output.push(
        match found {
          Some(j) => Number((j + 1).to_string())
          None => Empty
        },
      )
      for v, c in before_values {
        output.push(row[c])
        output.push(
          match found {
            Some(j) => after.rows[j][after_values[v]]
            None => Empty
          },
        )
      }
      reconcile_append(rows, output)
    }
  }
  for j, row in after.rows {
    if !before_index.contains(after_ids[j]) {
      let output = after_keys.map(c => row[c])
      output.push(Text("added"))
      output.push(Empty)
      output.push(Number((j + 1).to_string()))
      for c in after_values {
        output.push(Empty)
        output.push(row[c])
      }
      reconcile_append(rows, output)
    }
  }
  { columns, rows, }
}

///|
pub extend ReconcileError with @debug.Debug::{to_repr}

///|
pub extend ReconcileError with Eq::{not_equal, equal}
