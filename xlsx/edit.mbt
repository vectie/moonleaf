///|
fn attribute(name : String, value : String) -> @xml.Attribute {
  { name, value, }
}

///|
fn element(
  name : String,
  attributes : Array[@xml.Attribute],
  children : Array[@xml.Node],
) -> @xml.Element {
  { name, attributes, children, }
}

///|
fn text_element(name : String, text : String) -> @xml.Element {
  element(name, [], [
    Element(element("t", [attribute("xml:space", "preserve")], [Text(text)])),
  ])
}

///|
fn inline_text_cell(
  reference : String,
  text : String,
  existing : @xml.Element?,
) -> @xml.Element {
  let attributes = []
  match existing {
    Some(existing) =>
      for item in existing.attributes {
        if item.name != "t" && item.name != "r" {
          attributes.push(item)
        }
      }
    None => ()
  }
  attributes.push(attribute("r", reference))
  attributes.push(attribute("t", "inlineStr"))
  element("c", attributes, [Element(text_element("is", text))])
}

///|
/// Locate the exact XML node exposed at a logical coordinate by read/inspect.
/// Explicit cell references may differ from the enclosing row, and accepted
/// rows/cells need not be sorted. Only an ambiguous target prevents an edit.
fn cell_location(
  sheet_data : @xml.Element,
  row : Int,
  column : Int,
) -> (Int, Int)? raise XlsxError {
  let mut found = None
  let mut previous_row = 0
  for row_index, node in sheet_data.children {
    if node is Element(row_element) && row_element.local_name() == "row" {
      let logical_row = integer_attribute(row_element, "r", max_row).unwrap_or(
        previous_row + 1,
      )
      previous_row = logical_row
      let mut previous_column = 0
      for cell_index, node in row_element.children {
        if node is Element(cell) && cell.local_name() == "c" {
          let (cell_row, cell_column) = match cell.attribute("r") {
            None => (logical_row, previous_column + 1)
            Some(reference) =>
              match parse_cell_reference(reference) {
                Some(position) => position
                None => raise InvalidCellReference(reference)
              }
          }
          previous_column = cell_column
          if cell_row == row && cell_column == column {
            if found is Some(_) {
              raise InvalidWorkbook(
                "worksheet has duplicate target cell: " +
                cell_reference(row, column),
              )
            }
            found = Some((row_index, cell_index))
          }
        }
      }
    }
  }
  found
}

///|
fn insert_cell(
  row_element : @xml.Element,
  row : Int,
  column : Int,
  text : String,
) -> @xml.Element {
  let reference = cell_reference(row, column)
  let children : Array[@xml.Node] = []
  let inserted = Ref(false)
  for child in row_element.children {
    // Insert before an explicit reference, which resets the following implicit
    // column sequence. Otherwise append, leaving every existing position alone.
    if !inserted.val && child is Element(cell) && cell.local_name() == "c" {
      if cell.attribute("r") is Some(reference) &&
        parse_cell_reference(reference) is Some((_, current_column)) &&
        current_column > column {
        children.push(
          Element(inline_text_cell(cell_reference(row, column), text, None)),
        )
        inserted.val = true
      }
    }
    children.push(child)
  }
  if !inserted.val {
    children.push(Element(inline_text_cell(reference, text, None)))
  }
  { name: row_element.name, attributes: row_element.attributes, children, }
}

///|
fn new_row(row : Int, column : Int, text : String) -> @xml.Element {
  element("row", [attribute("r", "\{row}")], [
    Element(inline_text_cell(cell_reference(row, column), text, None)),
  ])
}

///|
fn replace_or_insert_row(
  sheet_data : @xml.Element,
  row : Int,
  column : Int,
  text : String,
) -> @xml.Element raise XlsxError {
  if cell_location(sheet_data, row, column) is Some((row_index, cell_index)) {
    let children = sheet_data.children.copy()
    guard children[row_index] is Element(existing_row) else {
      raise InvalidWorkbook("target row is missing")
    }
    let cells = existing_row.children.copy()
    guard cells[cell_index] is Element(existing_cell) else {
      raise InvalidWorkbook("target cell is missing")
    }
    cells[cell_index] = Element(
      inline_text_cell(cell_reference(row, column), text, Some(existing_cell)),
    )
    children[row_index] = Element({ ..existing_row, children: cells, })
    return { ..sheet_data, children, }
  }
  // A missing coordinate may be placed in an existing logical row, even when
  // rows are descending. Search before insertion so later rows are not doubled.
  let mut previous_row = 0
  for row_index, child in sheet_data.children {
    if child is Element(existing_row) && existing_row.local_name() == "row" {
      let current_row = integer_attribute(existing_row, "r", max_row).unwrap_or(
        previous_row + 1,
      )
      previous_row = current_row
      if current_row == row {
        let children = sheet_data.children.copy()
        children[row_index] = Element(
          insert_cell(existing_row, row, column, text),
        )
        return { ..sheet_data, children, }
      }
    }
  }
  let children : Array[@xml.Node] = []
  let inserted = Ref(false)
  for child in sheet_data.children {
    // An explicit row index is a safe insertion anchor: the rows after it keep
    // their old inferred positions. With no anchor, append after all old rows.
    if !inserted.val &&
      child is Element(row_element) &&
      row_element.local_name() == "row" {
      if integer_attribute(row_element, "r", max_row) is Some(current) &&
        current > row {
        children.push(Element(new_row(row, column, text)))
        inserted.val = true
      }
    }
    children.push(child)
  }
  if !inserted.val {
    children.push(Element(new_row(row, column, text)))
  }
  { name: sheet_data.name, attributes: sheet_data.attributes, children, }
}

///|
fn comes_after_sheet_data(local_name : String) -> Bool {
  match local_name {
    "sheetCalcPr"
    | "sheetProtection"
    | "protectedRanges"
    | "scenarios"
    | "autoFilter"
    | "sortState"
    | "dataConsolidate"
    | "customSheetViews"
    | "mergeCells"
    | "phoneticPr"
    | "conditionalFormatting"
    | "dataValidations"
    | "hyperlinks"
    | "printOptions"
    | "pageMargins"
    | "pageSetup"
    | "headerFooter"
    | "rowBreaks"
    | "colBreaks"
    | "customProperties"
    | "cellWatches"
    | "ignoredErrors"
    | "smartTags"
    | "drawing"
    | "legacyDrawing"
    | "legacyDrawingHF"
    | "picture"
    | "oleObjects"
    | "controls"
    | "webPublishItems"
    | "tableParts"
    | "extLst" => true
    _ => false
  }
}

///|
fn update_worksheet(
  worksheet : @xml.Element,
  row : Int,
  column : Int,
  text : String,
) -> @xml.Element raise XlsxError {
  guard worksheet.local_name() == "worksheet" else {
    raise InvalidWorkbook("worksheet part has an invalid root")
  }
  let children : Array[@xml.Node] = []
  let inserted = Ref(false)
  for child in worksheet.children {
    match child {
      Element(element) if element.local_name() == "sheetData" => {
        children.push(
          Element(replace_or_insert_row(element, row, column, text)),
        )
        inserted.val = true
      }
      Element(current) => {
        if !inserted.val && comes_after_sheet_data(current.local_name()) {
          children.push(
            Element(
              replace_or_insert_row(
                element("sheetData", [], []),
                row,
                column,
                text,
              ),
            ),
          )
          inserted.val = true
        }
        children.push(child)
      }
      _ => children.push(child)
    }
  }
  if !inserted.val {
    children.push(
      Element(
        replace_or_insert_row(element("sheetData", [], []), row, column, text),
      ),
    )
  }
  { name: worksheet.name, attributes: worksheet.attributes, children, }
}

///|
fn descriptor_named(
  descriptors : Array[SheetDescriptor],
  sheet_name : String,
) -> SheetDescriptor? {
  for descriptor in descriptors {
    if descriptor.name == sheet_name {
      return Some(descriptor)
    }
  }
  None
}

///|
/// Return a copy of `package` with one basic worksheet cell stored as an inline
/// string. Unrelated OPC parts and unrelated worksheet XML are preserved.
///
/// Rows and columns are one-based. This intentionally does not recalculate
/// formulas, shared strings, dimensions, tables, charts, or pivot caches.
pub fn set_cell_text(
  xlsx_package : @opc.Package,
  sheet_name : String,
  row : Int,
  column : Int,
  text : String,
) -> @opc.Package raise XlsxError {
  if row < 1 || row > max_row || column < 1 || column > max_column {
    raise InvalidCoordinates(row~, column~)
  }
  if !valid_xml_cell_text(text) {
    raise InvalidWorkbook("XLSX cell contains an invalid XML character")
  }
  if !xlsx_package.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let workbook = parse_part(xlsx_package, "xl/workbook.xml")
  let descriptors = workbook_sheets(workbook)
  guard descriptor_named(descriptors, sheet_name) is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let relationships = workbook_relationships(xlsx_package)
  let part_name = worksheet_part_name(relationships, descriptor)
  if !xlsx_package.has_part(part_name) {
    raise MissingWorksheet(
      sheet=descriptor.name,
      relationship_id=descriptor.relationship_id,
    )
  }
  let worksheet = parse_part(xlsx_package, part_name)
  xlsx_package.replace_text(
    part_name,
    // XML processors normalize literal CR/CRLF. A reference preserves the
    // exact decoded text in edited and untouched cells through Excel/openpyxl
    // reopen. Serialization has already escaped literal user entity spellings.
    @xml.serialize(update_worksheet(worksheet, row, column, text)).replace_all(
      old="\r",
      new="&#13;",
    ),
  )
}

///|
fn replace_existing_cells_in_worksheet(
  worksheet : @xml.Element,
  edits : Array[(Int, Int, String)],
  changed : Ref[Int],
) -> @xml.Element raise XlsxError {
  guard worksheet.local_name() == "worksheet" else {
    raise InvalidWorkbook("worksheet part has an invalid root")
  }
  let children : Array[@xml.Node] = []
  for child in worksheet.children {
    match child {
      Element(sheet_data) if sheet_data.local_name() == "sheetData" => {
        let mut updated = sheet_data
        for (row, column, text) in edits {
          if cell_location(updated, row, column)
            is Some((row_index, cell_index)) {
            let rows = updated.children.copy()
            guard rows[row_index] is Element(existing_row) else {
              raise InvalidWorkbook("target row is missing")
            }
            let cells = existing_row.children.copy()
            guard cells[cell_index] is Element(existing_cell) else {
              raise InvalidWorkbook("target cell is missing")
            }
            if existing_cell.children.any(fn(node) {
                match node {
                  Element(element) => element.local_name() == "f"
                  _ => false
                }
              }) {
              raise InvalidWorkbook("batch edit targets formula cell")
            }
            cells[cell_index] = Element(
              inline_text_cell(
                cell_reference(row, column),
                text,
                Some(existing_cell),
              ),
            )
            rows[row_index] = Element({ ..existing_row, children: cells, })
            updated = { ..updated, children: rows, }
            changed.val += 1
          }
        }
        children.push(Element(updated))
      }
      _ => children.push(child)
    }
  }
  { name: worksheet.name, attributes: worksheet.attributes, children, }
}

///|
/// Change existing cells in one worksheet parse and one archive update. This
/// deliberately does not create missing cells or change formula cells.
pub fn set_cells_text(
  xlsx_package : @opc.Package,
  sheet_name : String,
  edits : Array[(Int, Int, String)],
) -> @opc.Package raise XlsxError {
  if edits.is_empty() {
    return xlsx_package
  }
  let replacements : Map[Int, Map[Int, String]] = Map([])
  for (row, column, text) in edits {
    if row < 1 || row > max_row || column < 1 || column > max_column {
      raise InvalidCoordinates(row~, column~)
    }
    if !valid_xml_cell_text(text) {
      raise InvalidWorkbook("XLSX cell contains an invalid XML character")
    }
    let columns = match replacements.get(row) {
      Some(columns) => columns
      None => {
        let columns : Map[Int, String] = Map([])
        replacements[row] = columns
        columns
      }
    }
    if columns.get(column) is Some(_) {
      raise InvalidWorkbook("duplicate batch cell coordinate")
    }
    columns[column] = text
  }
  if !xlsx_package.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let workbook = parse_part(xlsx_package, "xl/workbook.xml")
  let descriptors = workbook_sheets(workbook)
  guard descriptor_named(descriptors, sheet_name) is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let relationships = workbook_relationships(xlsx_package)
  let part_name = worksheet_part_name(relationships, descriptor)
  if !xlsx_package.has_part(part_name) {
    raise MissingWorksheet(
      sheet=descriptor.name,
      relationship_id=descriptor.relationship_id,
    )
  }
  let worksheet = parse_part(xlsx_package, part_name)
  let changed = Ref(0)
  let updated = replace_existing_cells_in_worksheet(worksheet, edits, changed)
  if changed.val != edits.length() {
    raise InvalidWorkbook("batch edit references a missing cell")
  }
  xlsx_package.replace_text(
    part_name,
    @xml.serialize(updated).replace_all(old="\r", new="&#13;"),
  )
}
