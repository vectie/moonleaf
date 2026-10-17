///|
pub(all) enum DocxHeader {
  FirstTableRow
  TableColumns(Array[String])
} derive(Debug, Eq)

///|
pub(all) suberror DocxTableError {
  InvalidDocxSelection(String)
} derive(Debug, Eq)

///|
/// A direct main-body table. A refusal means this table cannot be imported.
/// IDs are one-based direct-body table ordinals, bound to the source snapshot.
pub(all) struct DocxTableCandidate {
  id : String
  rows : Int32
  columns : Int32
  first_row : Array[String]
  refusal : String?
} derive(Debug, Eq)

///|
pub(all) struct DocxTable {
  table : Table
  table_id : String
  source_rows : Array[Int32]
  warnings : Array[String]
} derive(Debug, Eq)

///|
fn docx_table_structure(element : @xml.Element) -> Unit raise DocxTableError {
  for attr in element.attributes {
    if attr.name == "xmlns:w" &&
      attr.value !=
      "http://schemas.openxmlformats.org/wordprocessingml/2006/main" {
      raise InvalidDocxSelection("rebound w namespace is unsupported")
    }
  }
  // Complex fields may span tables and paragraphs. Never import their cached
  // results as ordinary text even if the field start is outside the selection.
  if element.name == "w:fldChar" || element.name == "w:instrText" {
    raise InvalidDocxSelection("complex-field documents are unsupported")
  }
  for child in element.child_elements() {
    docx_table_structure(child)
  }
}

///|
fn docx_body_tables(
  archive : @opc.Package,
) -> Array[@xml.Element] raise DocxTableError {
  let source = archive.text("word/document.xml") catch {
    error => raise InvalidDocxSelection("\{Repr(error)}")
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocxSelection("\{Repr(error)}")
  }
  if root.name != "w:document" ||
    !root.attributes.any(a => {
      a.name == "xmlns:w" &&
      a.value == "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    }) {
    raise InvalidDocxSelection(
      "requires standard transitional w:document namespace",
    )
  }
  docx_table_structure(root)
  let bodies = root.child_elements().filter(e => e.name == "w:body")
  guard bodies is [body] else {
    raise InvalidDocxSelection("requires exactly one direct w:body")
  }
  let tables = body.child_elements().filter(e => e.name == "w:tbl")
  if tables.length() > 1000 {
    raise InvalidDocxSelection("more than 1000 direct body tables")
  }
  tables
}

///|
fn docx_selected_properties(
  element : @xml.Element,
) -> Unit raise DocxTableError {
  if [
      "w:gridSpan", "w:vMerge", "w:hMerge", "w:gridBefore", "w:gridAfter", "w:vanish",
      "w:webHidden", "w:specVanish",
    ].contains(element.name) ||
    element.name.has_suffix("Change") {
    raise InvalidDocxSelection(
      "unsupported selected table property: " + element.name,
    )
  }
  for child in element.child_elements() {
    docx_selected_properties(child)
  }
}

///|
fn docx_content_children(
  element : @xml.Element,
) -> Array[@xml.Element] raise DocxTableError {
  for child in element.children {
    if child is Text(text) && text.trim().to_owned() != "" {
      raise InvalidDocxSelection("unexpected text outside a w:t element")
    }
  }
  element.child_elements()
}

///|
fn docx_table_paragraph(
  paragraph : @xml.Element,
) -> String raise DocxTableError {
  let output = StringBuilder()
  for child in docx_content_children(paragraph) {
    if ["w:pPr", "w:bookmarkStart", "w:bookmarkEnd", "w:proofErr"].contains(
        child.name,
      ) {
      continue
    }
    if child.name != "w:r" {
      raise InvalidDocxSelection("unsupported paragraph content: " + child.name)
    }
    for run in docx_content_children(child) {
      if run.name != "w:rPr" && run.name != "w:t" && !run.children.is_empty() {
        raise InvalidDocxSelection("run control must be empty: " + run.name)
      }
      match run.name {
        "w:rPr" => ()
        "w:t" => {
          if !run.child_elements().is_empty() {
            raise InvalidDocxSelection("w:t must contain only text")
          }
          output.write_string(run.text_content())
        }
        "w:tab" => output.write_char('\t')
        "w:cr" => output.write_char('\n')
        "w:br" => {
          if run.attribute("w:type") is Some(kind) && kind != "textWrapping" {
            raise InvalidDocxSelection(
              "page/column breaks are unsupported in table cells",
            )
          }
          output.write_char('\n')
        }
        "w:noBreakHyphen" => output.write_char('\u2011')
        "w:softHyphen" => output.write_char('\u00ad')
        _ => raise InvalidDocxSelection("unsupported run content: " + run.name)
      }
    }
  }
  output.to_string()
}

///|
fn docx_table_rows(
  table : @xml.Element,
) -> Array[Array[String]] raise DocxTableError {
  docx_selected_properties(table)
  let rows : Array[Array[String]] = []
  let mut width = 0
  let mut units = 0
  let mut grid_width : Int32? = None
  for child in docx_content_children(table) {
    if child.name == "w:tblPr" {
      continue
    }
    if child.name == "w:tblGrid" {
      if grid_width is Some(_) {
        raise InvalidDocxSelection("duplicate table grid")
      }
      let grid = docx_content_children(child)
      if grid.any(e => e.name != "w:gridCol") {
        raise InvalidDocxSelection("unsupported table grid")
      }
      grid_width = Some(grid.length())
      continue
    }
    if child.name != "w:tr" {
      raise InvalidDocxSelection("unsupported table content: " + child.name)
    }
    if rows.length() >= 10001 {
      raise InvalidDocxSelection("table exceeds 10001 rows")
    }
    let row : Array[String] = []
    for cell in docx_content_children(child) {
      if cell.name == "w:trPr" {
        continue
      }
      if cell.name != "w:tc" {
        raise InvalidDocxSelection("unsupported row content: " + cell.name)
      }
      if row.length() >= 128 {
        raise InvalidDocxSelection("table exceeds 128 columns")
      }
      let paragraphs : Array[String] = []
      for paragraph in docx_content_children(cell) {
        if paragraph.name == "w:tcPr" {
          continue
        }
        if paragraph.name != "w:p" {
          raise InvalidDocxSelection(
            "unsupported cell content: " + paragraph.name,
          )
        }
        paragraphs.push(docx_table_paragraph(paragraph))
      }
      if paragraphs.is_empty() {
        raise InvalidDocxSelection(
          "cell requires at least one direct paragraph",
        )
      }
      let value = paragraphs.join("\n")
      units += value.length()
      if units > 4000000 {
        raise InvalidDocxSelection("table exceeds 4000000 text units")
      }
      row.push(value)
    }
    if row.is_empty() {
      raise InvalidDocxSelection("empty table row")
    }
    if rows.is_empty() {
      width = row.length()
    }
    if row.length() != width {
      raise InvalidDocxSelection("table rows must be rectangular")
    }
    rows.push(row)
    if rows.length() * width > 100000 {
      raise InvalidDocxSelection("table exceeds 100000 cells")
    }
  }
  if rows.is_empty() {
    raise InvalidDocxSelection("table has no rows")
  }
  if grid_width is Some(n) && n != width {
    raise InvalidDocxSelection("table grid width differs from cell count")
  }
  rows
}

///|
/// Discover direct body tables. Unsupported selected content is reported per
/// candidate, so an unrelated merged table does not block a supported table.
pub fn list_docx_tables(
  archive : @opc.Package,
) -> Array[DocxTableCandidate] raise DocxTableError {
  docx_body_tables(archive).mapi((index, table) => {
    let id = "body/table:" + (index + 1).to_string()
    try docx_table_rows(table) catch {
      InvalidDocxSelection(reason) =>
        {
          id,
          rows: table.child_elements().filter(e => e.name == "w:tr").length(),
          columns: 0,
          first_row: [],
          refusal: Some(reason),
        }
    } noraise {
      rows =>
        {
          id,
          rows: rows.length(),
          columns: rows[0].length(),
          first_row: rows[0],
          refusal: None,
        }
    }
  })
}

///|
/// Import a rectangular unmerged DOCX body table as literal text values.
/// No number, Boolean, date, formula or whitespace coercion is performed.
pub fn extract_docx(
  archive : @opc.Package,
  table_id~ : String,
  header~ : DocxHeader,
) -> DocxTable raise DocxTableError {
  let tables = docx_body_tables(archive)
  let mut selected : @xml.Element? = None
  for index, table in tables {
    if table_id == "body/table:" + (index + 1).to_string() {
      selected = Some(table)
    }
  }
  guard selected is Some(selected) else {
    raise InvalidDocxSelection("unknown direct body table ID: " + table_id)
  }
  let values = docx_table_rows(selected)
  let columns = match header {
    FirstTableRow => values[0].copy()
    TableColumns(names) => names.copy()
  }
  if columns.length() != values[0].length() {
    raise InvalidDocxSelection("header count must match table width")
  }
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  for name in columns {
    if name == "" || seen.contains(name) {
      raise InvalidDocxSelection("headers must be exact unique nonempty text")
    }
    seen[name] = true
    units += name.length()
  }
  let offset = if header is FirstTableRow { 1 } else { 0 }
  let rows : Array[Array[@scene.CellValue]] = values[offset:]
    .to_owned()
    .map(row => {
      row.map(text => {
        units += text.length()
        Text(text)
      })
    })
  if rows.length() > 10000 || units > 4000000 {
    raise InvalidDocxSelection(
      "import exceeds 10000 data rows or 4000000 text units",
    )
  }
  {
    table: { columns, rows, },
    table_id,
    source_rows: Array::makei(rows.length(), i => i + offset + 1),
    warnings: [
      "Only the selected direct body table is imported. Nested, wrapped, merged and unsupported selected content is refused; headers, footers and other tables are not imported.",
      "All cells are literal text. Adjacent runs are joined; tabs, line breaks and paragraph boundaries are retained. Styles, list labels, layout, links and Office display fidelity are not exported.",
      "Source row numbers and table IDs belong to this exact source snapshot. Keep the original and its SHA-256 alongside the output.",
      "CSV may be interpreted as formulas by spreadsheet applications. Use XLSX for explicit literal text cells. No source rewrite, recalculation, print-ready or customer acceptance claim.",
    ],
  }
}

///|
pub extend DocxHeader with Eq::{equal, not_equal}

///|
pub extend DocxHeader with @debug.Debug::{to_repr}

///|
pub extend DocxTableError with Eq::{equal, not_equal}

///|
pub extend DocxTableError with @debug.Debug::{to_repr}

///|
pub extend DocxTableCandidate with Eq::{equal, not_equal}

///|
pub extend DocxTableCandidate with @debug.Debug::{to_repr}

///|
pub extend DocxTable with Eq::{equal, not_equal}

///|
pub extend DocxTable with @debug.Debug::{to_repr}
