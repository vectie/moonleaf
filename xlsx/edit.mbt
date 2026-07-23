///|
fn attribute(name : String, value : String) -> @xml.Attribute {
  { name, value }
}

///|
fn element(
  name : String,
  attributes : Array[@xml.Attribute],
  children : Array[@xml.Node],
) -> @xml.Element {
  { name, attributes, children }
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
fn cell_column(cell : @xml.Element) -> Int? {
  match cell.attribute("r") {
    Some(reference) =>
      match parse_cell_reference(reference) {
        Some((_, column)) => Some(column)
        None => None
      }
    None => None
  }
}

///|
/// Resolve columns for legal worksheet cells whose `r` attribute is omitted.
/// OOXML defines their position by document order, so editing must not append a
/// duplicate cell or reorder subsequent explicit coordinates.
fn cell_column_or_implicit(cell : @xml.Element, previous : Int) -> Int {
  cell_column(cell).unwrap_or(previous + 1)
}

///|
fn replace_or_insert_cell(
  row_element : @xml.Element,
  row : Int,
  column : Int,
  text : String,
) -> @xml.Element {
  let reference = cell_reference(row, column)
  let children : Array[@xml.Node] = []
  let inserted = Ref(false)
  let previous_column = Ref(0)
  for child in row_element.children {
    match child {
      Element(cell) if cell.local_name() == "c" => {
        let current_column = cell_column_or_implicit(cell, previous_column.val)
        previous_column.val = current_column
        if current_column == column {
          children.push(Element(inline_text_cell(reference, text, Some(cell))))
          inserted.val = true
        } else {
          if !inserted.val && current_column > column {
            children.push(Element(inline_text_cell(reference, text, None)))
            inserted.val = true
          }
          children.push(child)
        }
      }
      _ => children.push(child)
    }
  }
  if !inserted.val {
    children.push(Element(inline_text_cell(reference, text, None)))
  }
  { name: row_element.name, attributes: row_element.attributes, children }
}

///|
fn new_row(row : Int, column : Int, text : String) -> @xml.Element {
  element("row", [attribute("r", "\{row}")], [
    Element(inline_text_cell(cell_reference(row, column), text, None)),
  ])
}

///|
fn row_number(row : @xml.Element) -> Int? {
  integer_attribute(row, "r", max_row)
}

///|
fn replace_or_insert_row(
  sheet_data : @xml.Element,
  row : Int,
  column : Int,
  text : String,
) -> @xml.Element {
  let children : Array[@xml.Node] = []
  let inserted = Ref(false)
  for child in sheet_data.children {
    match child {
      Element(row_element) if row_element.local_name() == "row" => {
        let current_row = row_number(row_element)
        if current_row == Some(row) {
          children.push(
            Element(replace_or_insert_cell(row_element, row, column, text)),
          )
          inserted.val = true
        } else {
          if !inserted.val && current_row is Some(current) && current > row {
            children.push(Element(new_row(row, column, text)))
            inserted.val = true
          }
          children.push(child)
        }
      }
      _ => children.push(child)
    }
  }
  if !inserted.val {
    children.push(Element(new_row(row, column, text)))
  }
  { name: sheet_data.name, attributes: sheet_data.attributes, children }
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
  { name: worksheet.name, attributes: worksheet.attributes, children }
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
    @xml.serialize(update_worksheet(worksheet, row, column, text)),
  )
}
