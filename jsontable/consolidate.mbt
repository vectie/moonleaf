///|
pub(all) enum Retention {
  KeepFirst
  KeepLast
} derive(Debug, Eq)

///|
pub(all) suberror ConsolidateError {
  InvalidConsolidate(String)
  InvalidConsolidateKey(row~ : Int, column~ : String)
  UnsupportedConsolidateValue(row~ : Int, column~ : String)
} derive(Debug, Eq)

///|
pub(all) struct Consolidation {
  kept : Table
  report : Table
} derive(Debug, Eq)

///|
/// Select complete rows by explicit, nonempty exact-text composite keys.
/// KeepFirst/KeepLast use input order. Kept rows retain their relative input
/// order. The report retains every complete input row, with one-based input
/// and selected input row references, group size and unique/kept/discarded status.
/// No values are merged, normalized or inferred. Both outputs are fresh copies.
pub fn Table::consolidate(
  self : Table,
  key_columns~ : Array[String],
  retention~ : Retention,
) -> Consolidation raise ConsolidateError {
  let metadata = [
    "_input_row", "_disposition", "_kept_input_row", "_group_size",
  ]
  // Bound the complete review report, even when almost all rows are discarded.
  if self.columns.is_empty() ||
    self.columns.length() > 252 ||
    self.rows.length() > 10_000 ||
    (self.rows.length() + 1) * (self.columns.length() + 4) > 100_000 {
    raise InvalidConsolidate(
      "Expected 1–252 input columns, at most 10000 rows and 100000 report cells including header",
    )
  }
  validate_lookup_table(self) catch {
    _ =>
      raise InvalidConsolidate(
        "Expected unique nonempty headers and rectangular rows",
      )
  }
  if key_columns.is_empty() || key_columns.length() > 32 {
    raise InvalidConsolidate("Expected 1–32 explicit key columns")
  }
  for name in metadata {
    if self.columns.contains(name) {
      raise InvalidConsolidate("Report column collision: " + name)
    }
  }
  let keys : Array[Int] = []
  for name in key_columns {
    let column = lookup_column(self, name) catch {
      _ => raise InvalidConsolidate("Unknown key column: " + name)
    }
    if keys.contains(column) {
      raise InvalidConsolidate("Duplicate key column: " + name)
    }
    keys.push(column)
  }
  let selected : Map[String, Int] = {}
  let counts : Map[String, Int] = {}
  let identities : Array[String] = []
  for i, row in self.rows {
    for c, value in row {
      match value {
        Empty | Text(_) | Boolean(_) => ()
        Number(text) => {
          let parsed = @json.parse(text) catch {
            _ =>
              raise UnsupportedConsolidateValue(
                row=i + 1,
                column=self.columns[c],
              )
          }
          guard parsed is Number(value, ..) &&
            !value.is_inf() &&
            !value.is_nan() else {
            raise UnsupportedConsolidateValue(row=i + 1, column=self.columns[c])
          }
        }
        _ =>
          raise UnsupportedConsolidateValue(row=i + 1, column=self.columns[c])
      }
    }
    let components : Array[Json] = []
    for c in keys {
      match row[c] {
        Text(value) if value != "" => components.push(Json::string(value))
        _ => raise InvalidConsolidateKey(row=i + 1, column=self.columns[c])
      }
    }
    // Same unambiguous tuple encoding as reconciliation; never join by a separator.
    let identity = Json::array(components).stringify()
    identities.push(identity)
    counts[identity] = counts.get(identity).unwrap_or(0) + 1
    if retention == KeepLast || !selected.contains(identity) {
      selected[identity] = i
    }
  }
  let kept_rows : Array[Array[@scene.CellValue]] = []
  let report_rows : Array[Array[@scene.CellValue]] = []
  for i, row in self.rows {
    let identity = identities[i]
    let winner = selected[identity]
    let size = counts[identity]
    if winner == i {
      kept_rows.push(row.copy())
    }
    let disposition = if size == 1 {
      "unique"
    } else if winner == i {
      "kept"
    } else {
      "discarded"
    }
    let report = row.copy()
    report.push(@scene.Number((i + 1).to_string()))
    report.push(@scene.Text(disposition))
    report.push(@scene.Number((winner + 1).to_string()))
    report.push(@scene.Number(size.to_string()))
    report_rows.push(report)
  }
  let report_columns = self.columns.copy()
  for name in metadata {
    report_columns.push(name)
  }
  {
    kept: { columns: self.columns.copy(), rows: kept_rows, },
    report: { columns: report_columns, rows: report_rows, },
  }
}
