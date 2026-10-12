///|
pub(all) enum PptxHeader {
  FirstSlideTableRow
  SlideTableColumns(Array[String])
} derive(Debug, Eq)

///|
pub(all) suberror PptxTableError {
  InvalidPptxSelection(String)
} derive(Debug, Eq)

///|
pub(all) struct PptxTable {
  table : Table
  table_id : String
  slide_number : Int
  part : String
  shape_id : String
  hidden_slide : Bool
  source_rows : Array[Int]
  warnings : Array[String]
} derive(Debug, Eq)

///|
/// Import one unmerged presentation table as exact literal text. No numeric,
/// Boolean, date or formula inference is applied. Source rows are one-based.
pub fn extract_pptx(
  archive : @opc.Package,
  table_id~ : String,
  header~ : PptxHeader,
) -> PptxTable raise PptxTableError {
  let tables = @pptx.read_tables(archive) catch {
    error => raise InvalidPptxSelection("\{Repr(error)}")
  }
  let selected = tables.filter(table => table.id == table_id)
  guard selected is [selected] else {
    raise InvalidPptxSelection("unknown slide table ID: " + table_id)
  }
  if selected.refusal is Some(reason) {
    raise InvalidPptxSelection(reason)
  }
  let values = selected.rows
  let columns = match header {
    FirstSlideTableRow => values[0].copy()
    SlideTableColumns(names) => names.copy()
  }
  if columns.length() != values[0].length() {
    raise InvalidPptxSelection("header count must match table width")
  }
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  for name in columns {
    if name == "" || seen.contains(name) {
      raise InvalidPptxSelection("headers must be exact unique nonempty text")
    }
    seen[name] = true
    units += name.length()
  }
  let offset = if header is FirstSlideTableRow { 1 } else { 0 }
  let rows : Array[Array[@scene.CellValue]] = values[offset:]
    .to_owned()
    .map(row => {
      row.map(text => {
        units += text.length()
        @scene.Text(text)
      })
    })
  if units > 2_000_000 {
    raise InvalidPptxSelection("import exceeds 2000000 header/data text units")
  }
  {
    table: { columns, rows, },
    table_id,
    slide_number: selected.slide_number,
    part: selected.part,
    shape_id: selected.shape_id,
    hidden_slide: selected.hidden_slide,
    source_rows: Array::makei(rows.length(), i => i + offset + 1),
    warnings: [
      "Only the selected ordinary slide table is imported. Hidden slides and grouped tables are included; XML order is not visual reading order. Notes, layouts, masters, charts and other objects are not imported.",
      "All cells remain literal text. Runs concatenate; paragraphs and explicit line breaks retain newlines. Merges, fields, hyperlinks and unknown selected content are refused; styles, bullets and layout are not rendered.",
      "Slide/table IDs, shape IDs, parts and row numbers belong to this exact source snapshot. Retain the original and source SHA-256; extraction is not a complete-source or factual verification claim.",
      "CSV may be interpreted as formulas by spreadsheet applications. Use XLSX for literal text typing. No source rewrite, recalculation, Office visual fidelity, print-ready or customer acceptance claim.",
    ],
  }
}

///|
pub extend PptxHeader with Eq::{equal, not_equal}

///|
pub extend PptxHeader with @debug.Debug::{to_repr}

///|
pub extend PptxTableError with Eq::{equal, not_equal}

///|
pub extend PptxTableError with @debug.Debug::{to_repr}

///|
pub extend PptxTable with Eq::{equal, not_equal}

///|
pub extend PptxTable with @debug.Debug::{to_repr}
