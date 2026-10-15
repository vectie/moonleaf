///|
pub(all) struct NamedXlsxTable {
  table : Table
  definition : @xlsx.NamedTable
  source_rows : Array[Int]
  warnings : Array[String]
} derive(Debug, Eq)

///|
/// Import an Excel Table by exact displayName. Header cells must agree with
/// metadata. Totals rows are excluded, filtered/hidden rows are included, and
/// calculated columns/formulas are refused rather than importing stale caches.
pub fn extract_xlsx_named_table(
  archive : @opc.Package,
  table_name~ : String,
) -> NamedXlsxTable raise XlsxTableError {
  let definitions = @xlsx.named_tables(archive) catch {
    error => raise InvalidXlsxSelection("\{Repr(error)}")
  }
  guard definitions.filter(table => table.name == table_name) is [definition] else {
    raise InvalidXlsxSelection("Excel Table not found: " + table_name)
  }
  if definition.calculated_columns {
    raise InvalidXlsxSelection(
      "calculated Excel Table columns cannot be imported as fresh values",
    )
  }
  let (table, source_rows, warnings) = match definition.import_reference {
    None => ({ columns: definition.columns.copy(), rows: [], }, [], [])
    Some(range) => {
      let imported = extract_xlsx(
        archive,
        sheet_name=definition.sheet_name,
        range~,
        header=if definition.header_rows == 1 {
          FirstRow
        } else {
          Columns(definition.columns)
        },
      )
      if imported.table.columns != definition.columns {
        raise InvalidXlsxSelection(
          "Excel Table header cells disagree with column metadata",
        )
      }
      (imported.table, imported.source_rows, imported.warnings)
    }
  }
  warnings.push(
    "Excel Table metadata selects the current rectangle; totals rows are excluded. Hidden and filtered data rows are included.",
  )
  warnings.push(
    "Table formatting, filters, sort state and external refresh are not applied. This is an extracted dataset, not a preserved workbook.",
  )
  { table, definition, source_rows, warnings, }
}

///|
pub extend NamedXlsxTable with @debug.Debug::{to_repr}

///|
pub extend NamedXlsxTable with Eq::{not_equal, equal}
