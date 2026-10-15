///|
pub(all) enum XlsxHeader {
  FirstRow
  Columns(Array[String])
} derive(Debug, Eq)

///|
pub(all) suberror XlsxTableError {
  InvalidXlsxSelection(String)
} derive(Debug, Eq)

///|
pub(all) struct XlsxTable {
  table : Table
  sheet_name : String
  range : @scene.CellRange
  source_rows : Array[Int]
  warnings : Array[String]
} derive(Debug, Eq)

///|
/// Import an explicit worksheet rectangle into the typed Table pipeline.
/// FirstRow requires distinct nonempty text headers; Columns treats all selected
/// rows as data. Blank rows and trailing empty positions are never trimmed.
pub fn extract_xlsx(
  archive : @opc.Package,
  sheet_name~ : String,
  range~ : String,
  header~ : XlsxHeader,
) -> XlsxTable raise XlsxTableError {
  let selection = @xlsx.read_range(archive, sheet_name~, range~) catch {
    error => raise InvalidXlsxSelection("\{Repr(error)}")
  }
  let columns = match header {
    FirstRow =>
      selection.rows[0].map(value => {
        guard value is Text(text) else {
          raise InvalidXlsxSelection(
            "first selected row must contain text headers",
          )
        }
        text
      })
    Columns(names) => names.copy()
  }
  if columns.length() !=
    selection.range.end_column - selection.range.start_column + 1 {
    raise InvalidXlsxSelection(
      "explicit header count must match selected width",
    )
  }
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  for name in columns {
    if name == "" || seen.contains(name) {
      raise InvalidXlsxSelection("headers must be exact unique nonempty text")
    }
    seen[name] = true
    units += name.length()
  }
  let offset = if header is FirstRow { 1 } else { 0 }
  let rows = selection.rows[offset:].to_owned()
  if rows.length() > 10000 {
    raise InvalidXlsxSelection("selection exceeds 10000 data rows")
  }
  for row in rows {
    for value in row {
      match value {
        Text(text) | Number(text) => units += text.length()
        _ => ()
      }
    }
  }
  if units > 4000000 {
    raise InvalidXlsxSelection("headers and data exceed 4000000 text units")
  }
  {
    table: { columns, rows, },
    sheet_name,
    range: selection.range,
    source_rows: Array::makei(rows.length(), i => {
      selection.range.start_row + offset + i
    }),
    warnings: [
      "Value-only extraction; formulas and intersecting merges are refused. No workbook rewrite or recalculation.",
      "Numbers are raw finite numeric tokens, including date/time serials. Styles, display formats, date epoch, hidden/filter state and rich-text formatting are not applied.",
      "Selected styled cells: \{selection.styled_cells}. Only the explicit worksheet range is returned; other sheets and values are not qualified.",
    ],
  }
}

///|
pub extend XlsxHeader with @debug.Debug::{to_repr}

///|
pub extend XlsxHeader with Eq::{not_equal, equal}

///|
pub extend XlsxTableError with @debug.Debug::{to_repr}

///|
pub extend XlsxTableError with Eq::{not_equal, equal}

///|
pub extend XlsxTable with @debug.Debug::{to_repr}

///|
pub extend XlsxTable with Eq::{not_equal, equal}
