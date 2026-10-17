///|
/// An Excel Table definition, resolved through its owning worksheet relationship.
/// `reference` includes header/totals; `import_reference` excludes totals.
/// A headerless totals-only table has no import rectangle.
pub(all) struct NamedTable {
  name : String
  sheet_name : String
  table_part : String
  reference : String
  import_reference : String?
  columns : Array[String]
  header_rows : Int32
  totals_rows : Int32
  data_rows : Int32
  calculated_columns : Bool
} derive(Debug, Eq)

///|
fn table_count(
  element : @xml.Element,
  name : String,
  default : Int32,
) -> Int32 raise XlsxError {
  match element.attribute(name) {
    None => default
    Some(value) =>
      match parse_decimal(value, 1) {
        Some(count) => count
        None =>
          raise InvalidWorkbook("unsupported table " + name + ": " + value)
      }
  }
}

///|
fn table_relationships(
  archive : @opc.Package,
  part : String,
) -> Array[@opc.Relationship] raise XlsxError {
  let relationships = archive.relationships(part) catch {
    error => raise PackageFailure(part~, message="\{Repr(error)}")
  }
  let ids : Map[String, Bool] = Map([])
  for relationship in relationships {
    if ids.contains(relationship.id) {
      raise InvalidWorkbook("duplicate relationship id in " + part)
    }
    ids[relationship.id] = true
  }
  relationships
}

///|
/// Discover bounded worksheet Excel Tables in workbook/worksheet tablePart order.
/// Does not infer tables from formatting or interpret workbook defined names.
/// Metadata is read without evaluating formulas or following external resources.
pub fn named_tables(
  archive : @opc.Package,
) -> Array[NamedTable] raise XlsxError {
  let workbook = parse_part(archive, "xl/workbook.xml")
  if workbook.children_named("sheets").length() != 1 {
    raise InvalidWorkbook("expected one workbook sheets element")
  }
  let relationships = table_relationships(archive, "xl/workbook.xml")
  let result : Array[NamedTable] = []
  let names : Map[String, Bool] = Map([])
  let parts : Map[String, Bool] = Map([])
  let sheets : Map[String, Bool] = Map([])
  for sheet in workbook_sheets(workbook) {
    if sheets.contains(sheet.name) {
      raise InvalidWorkbook("ambiguous worksheet name: " + sheet.name)
    }
    sheets[sheet.name] = true
    // Chartsheets share the workbook's sheet list but cannot own cell Tables.
    // Skip only recognized internal chartsheet relationships; other unresolved
    // or unsupported sheet relationships still use the existing refusal path.
    if find_relationship(relationships, sheet.relationship_id) is Some(link) &&
      !link.external &&
      (
        link.relationship_type ==
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/chartsheet" ||
        link.relationship_type ==
        "http://purl.oclc.org/ooxml/officeDocument/relationships/chartsheet"
      ) {
      continue
    }
    let worksheet_part = worksheet_part_name(relationships, sheet)
    let worksheet = parse_part(archive, worksheet_part)
    if worksheet.local_name() != "worksheet" ||
      worksheet.children_named("tableParts").length() > 1 {
      raise InvalidWorkbook("invalid worksheet/tableParts: " + worksheet_part)
    }
    let containers = worksheet.children_named("tableParts")
    if containers.is_empty() {
      continue
    }
    let links = table_relationships(archive, worksheet_part)
    let table_parts = containers[0].children_named("tablePart")
    if containers[0].attribute("count") is Some(count) &&
      parse_decimal(count, 256) != Some(table_parts.length()) {
      raise InvalidWorkbook("tableParts count does not match references")
    }
    for table_part in table_parts {
      if result.length() >= 256 {
        raise InvalidWorkbook("more than 256 Excel Tables")
      }
      guard table_part.attribute("id") is Some(id) &&
        find_relationship(links, id) is Some(link) &&
        !link.external &&
        (
          link.relationship_type ==
          "http://schemas.openxmlformats.org/officeDocument/2006/relationships/table" ||
          link.relationship_type ==
          "http://purl.oclc.org/ooxml/officeDocument/relationships/table"
        ) else {
        raise InvalidWorkbook(
          "missing, external or unsupported Excel Table relationship",
        )
      }
      let part = @opc.resolve_target(worksheet_part, link.target) catch {
        error =>
          raise PackageFailure(part=worksheet_part, message="\{Repr(error)}")
      }
      if parts.contains(part) {
        raise InvalidWorkbook("repeated Excel Table part: " + part)
      }
      parts[part] = true
      let root = parse_part(archive, part)
      guard root.local_name() == "table" &&
        root.attribute("displayName") is Some(name) &&
        name != "" &&
        name.length() <= 255 &&
        root.attribute("ref") is Some(reference) &&
        parse_range_reference(reference) is Some(bounds) else {
        raise InvalidWorkbook("invalid Excel Table definition: " + part)
      }
      if names.contains(name) {
        raise InvalidWorkbook("ambiguous Excel Table name: " + name)
      }
      names[name] = true
      if root.attribute("tableType").unwrap_or("worksheet") != "worksheet" ||
        root.attribute("connectionId") is Some(_) {
        raise InvalidWorkbook("only local worksheet Excel Tables are supported")
      }
      let header_rows = table_count(root, "headerRowCount", 1)
      let totals_rows = table_count(root, "totalsRowCount", 0)
      let height = bounds.end_row - bounds.start_row + 1
      let width = bounds.end_column - bounds.start_column + 1
      if height < header_rows + totals_rows ||
        height - header_rows - totals_rows > 10000 ||
        width > 128 ||
        (height - totals_rows) * width > 100000 {
        raise InvalidWorkbook("Excel Table dimensions exceed import bounds")
      }
      if root.children_named("tableColumns").length() != 1 {
        raise InvalidWorkbook("expected one tableColumns element")
      }
      let column_root = root.children_named("tableColumns")[0]
      let column_elements = column_root.children_named("tableColumn")
      if column_elements.length() != width ||
        (
          column_root.attribute("count") is Some(count) &&
          parse_decimal(count, 128) != Some(width)
        ) {
        raise InvalidWorkbook("Excel Table columns do not match its width")
      }
      let columns : Array[String] = []
      let seen_columns : Map[String, Bool] = Map([])
      let column_ids : Map[String, Bool] = Map([])
      let mut calculated_columns = false
      for column in column_elements {
        guard column.attribute("name") is Some(column_name) &&
          column_name != "" &&
          column_name.length() <= 255 &&
          column.attribute("id") is Some(column_id) &&
          parse_decimal(column_id, 2147483647) is Some(number) &&
          number > 0 else {
          raise InvalidWorkbook("invalid Excel Table column")
        }
        let canonical_id = number.to_string()
        if seen_columns.contains(column_name) ||
          column_ids.contains(canonical_id) {
          raise InvalidWorkbook("duplicate Excel Table column name/id")
        }
        seen_columns[column_name] = true
        column_ids[canonical_id] = true
        columns.push(column_name)
        if !column.children_named("calculatedColumnFormula").is_empty() {
          calculated_columns = true
        }
      }
      let end_row = bounds.end_row - totals_rows
      let import_reference = if end_row < bounds.start_row {
        None
      } else {
        Some(
          cell_reference(bounds.start_row, bounds.start_column) +
          ":" +
          cell_reference(end_row, bounds.end_column),
        )
      }
      result.push({
        name,
        sheet_name: sheet.name,
        table_part: part,
        reference,
        import_reference,
        columns,
        header_rows,
        totals_rows,
        data_rows: height - header_rows - totals_rows,
        calculated_columns,
      })
    }
  }
  result
}

///|
pub extend NamedTable with Eq::{equal, not_equal}

///|
pub extend NamedTable with @debug.Debug::{to_repr}
