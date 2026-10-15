///|
/// Aggregate long financial observations before widening categories. Reuses
/// compensated numeric summary and the existing deterministic pivot engine.
/// Column categories use their displayed scalar labels, including blank cells.
pub fn Table::pivot_summary(
  self : Table,
  row_columns~ : Array[String],
  column_column~ : String,
  operation~ : SummaryOperation,
) -> Table raise PivotError {
  let category_index = pivot_column(self, column_column)
  let columns = self.columns.copy()
  let rows : Array[Array[@scene.CellValue]] = []
  for row_index, row in self.rows {
    let copy = row.copy()
    let label = match row.get(category_index) {
      Some(Empty) | Some(Text("")) => "(blank)"
      Some(Text(text)) | Some(Number(text)) => text
      Some(Boolean(flag)) => if flag { "TRUE" } else { "FALSE" }
      _ => raise UnsupportedPivotValue(row=row_index + 1, column=column_column)
    }
    copy[category_index] = Text(label)
    rows.push(copy)
  }
  let normalized : Table = { columns, rows, }
  let group_by = row_columns.copy()
  group_by.push(column_column)
  let mut measure_name = "Pivot Value"
  while self.columns.contains(measure_name) {
    measure_name += "_"
  }
  let summary = normalized.summarize(group_by~, measures=[
    { name: measure_name, operation, },
  ]) catch {
    error => raise InvalidPivot("Pivot aggregation: " + repr(error))
  }
  summary.pivot(
    id_columns=row_columns,
    key_column=column_column,
    value_column=measure_name,
  )
}
