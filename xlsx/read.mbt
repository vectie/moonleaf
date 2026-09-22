///|
priv struct SheetDescriptor {
  name : String
  relationship_id : String
}

///|
fn workbook_sheets(
  root : @xml.Element,
) -> Array[SheetDescriptor] raise XlsxError {
  guard root.local_name() == "workbook" else {
    raise InvalidWorkbook("root element is not workbook")
  }
  guard root.first_child("sheets") is Some(sheets) else {
    raise InvalidWorkbook("workbook has no sheets element")
  }
  let result = []
  for sheet in sheets.children_named("sheet") {
    guard (sheet.attribute("name"), sheet.attribute("id"))
      is (Some(name), Some(relationship_id)) else {
      raise InvalidWorkbook("a sheet is missing name or relationship id")
    }
    result.push({ name, relationship_id, })
  }
  result
}

///|
fn shared_strings(root : @xml.Element?) -> Array[String] {
  let result = []
  match root {
    None => ()
    Some(root) =>
      for item in root.children_named("si") {
        result.push(descendant_text(item))
      }
  }
  result
}

///|
fn parse_cell_value(
  cell : @xml.Element,
  strings : Array[String],
) -> @scene.CellValue raise XlsxError {
  let formula = child_text(cell, "f")
  let cached = child_text(cell, "v")
  if formula is Some(expression) {
    return Formula(expression~, cached~)
  }
  match cell.attribute("t") {
    Some("inlineStr") =>
      match cell.first_child("is") {
        Some(inline) => Text(descendant_text(inline))
        None => Empty
      }
    Some("s") =>
      match cached {
        Some(index_text) =>
          match parse_decimal(index_text, strings.length()) {
            Some(index) if index < strings.length() => Text(strings[index])
            Some(index) => raise InvalidSharedStringIndex(index)
            None =>
              raise InvalidWorkbook(
                "invalid shared string index: \{index_text}",
              )
          }
        None => Empty
      }
    Some("str") =>
      match cached {
        Some(value) => Text(value)
        None => Empty
      }
    Some("b") =>
      match cached {
        Some("1") | Some("true") => Boolean(true)
        Some("0") | Some("false") => Boolean(false)
        Some(value) => raise InvalidWorkbook("invalid boolean cell: \{value}")
        None => Empty
      }
    Some("e") =>
      match cached {
        Some(value) => Error(value)
        None => Error("")
      }
    Some("n") | None =>
      match cached {
        Some(value) => Number(value)
        None => Empty
      }
    Some(_) =>
      match cached {
        Some(value) => Text(value)
        None => Empty
      }
  }
}

///|
fn parse_cells(
  root : @xml.Element,
  strings : Array[String],
) -> Array[@scene.Cell] raise XlsxError {
  let cells : Array[@scene.Cell] = []
  match root.first_child("sheetData") {
    None => ()
    Some(sheet_data) => {
      let fallback_row = Ref(0)
      for row_element in sheet_data.children_named("row") {
        fallback_row.val = fallback_row.val + 1
        let row = integer_attribute(row_element, "r", max_row).unwrap_or(
          fallback_row.val,
        )
        fallback_row.val = row
        let fallback_column = Ref(0)
        for cell in row_element.children_named("c") {
          fallback_column.val = fallback_column.val + 1
          let (cell_row, column) = match cell.attribute("r") {
            Some(reference) =>
              match parse_cell_reference(reference) {
                Some(position) => position
                None => raise InvalidCellReference(reference)
              }
            None => (row, fallback_column.val)
          }
          fallback_column.val = column
          let style_id = integer_attribute(cell, "s", 2147483647)
          cells.push({
            row: cell_row,
            column,
            value: parse_cell_value(cell, strings),
            style_id,
          })
        }
      }
    }
  }
  cells
}

///|
fn parse_merged_ranges(
  root : @xml.Element,
) -> Array[@scene.CellRange] raise XlsxError {
  let ranges = []
  match root.first_child("mergeCells") {
    None => ()
    Some(merge_cells) =>
      for merge_cell in merge_cells.children_named("mergeCell") {
        guard merge_cell.attribute("ref") is Some(reference) else {
          raise InvalidWorkbook("mergeCell has no ref attribute")
        }
        match parse_range_reference(reference) {
          Some(range) => ranges.push(range)
          None => raise InvalidCellReference(reference)
        }
      }
  }
  ranges
}

///|
fn workbook_relationships(
  xlsx_package : @opc.Package,
) -> Array[@opc.Relationship] raise XlsxError {
  xlsx_package.relationships("xl/workbook.xml") catch {
    error =>
      raise PackageFailure(
        part="xl/_rels/workbook.xml.rels",
        message="\{Repr(error)}",
      )
  }
}

///|
fn find_relationship(
  relationships : Array[@opc.Relationship],
  relationship_id : String,
) -> @opc.Relationship? {
  for relationship in relationships {
    if relationship.id == relationship_id {
      return Some(relationship)
    }
  }
  None
}

///|
fn worksheet_part_name(
  relationships : Array[@opc.Relationship],
  sheet : SheetDescriptor,
) -> String raise XlsxError {
  guard find_relationship(relationships, sheet.relationship_id)
    is Some(relationship) &&
    !relationship.external &&
    (
      relationship.relationship_type ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ||
      relationship.relationship_type ==
      "http://purl.oclc.org/ooxml/officeDocument/relationships/worksheet"
    ) else {
    raise MissingWorksheet(
      sheet=sheet.name,
      relationship_id=sheet.relationship_id,
    )
  }
  @opc.resolve_target("xl/workbook.xml", relationship.target) catch {
    @opc.PackageError::InvalidPackage(message) =>
      raise XlsxError::PackageFailure(
        part="xl/_rels/workbook.xml.rels",
        message~,
      )
    @opc.PackageError::MissingPart(part) =>
      raise XlsxError::PackageFailure(part~, message="missing package part")
    @opc.PackageError::InvalidTextPart(part) =>
      raise XlsxError::PackageFailure(
        part~,
        message="package part is not valid UTF-8",
      )
  }
}

///|
/// Read the supported workbook structure from an already opened OPC package.
///
/// This first release covers sheet names, shared and inline strings, scalar
/// cell values, formulas with cached values, styles ids, and merged ranges.
pub fn read(xlsx_package : @opc.Package) -> @scene.Workbook raise XlsxError {
  if !xlsx_package.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let workbook = parse_part(xlsx_package, "xl/workbook.xml")
  let descriptors = workbook_sheets(workbook)
  let relationships = workbook_relationships(xlsx_package)
  let strings = shared_strings(
    resolved_metadata_part(
      xlsx_package, relationships, shared_strings_relationship_types,
    ),
  )
  let sheets : Array[@scene.Sheet] = []
  for descriptor in descriptors {
    let part_name = worksheet_part_name(relationships, descriptor)
    if !xlsx_package.has_part(part_name) {
      raise MissingWorksheet(
        sheet=descriptor.name,
        relationship_id=descriptor.relationship_id,
      )
    }
    let worksheet = parse_part(xlsx_package, part_name)
    if worksheet.local_name() != "worksheet" {
      raise InvalidWorkbook("worksheet part has an invalid root: \{part_name}")
    }
    sheets.push({
      name: descriptor.name,
      cells: parse_cells(worksheet, strings),
      merged_ranges: parse_merged_ranges(worksheet),
    })
  }
  { sheets, warnings: [], }
}
