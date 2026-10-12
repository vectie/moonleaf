///|
/// An exact text correction in a source snapshot. Coordinates are canonical A1.
pub(all) struct TextCellCorrection {
  sheet : String
  address : String
  expected : String
  replacement : String
} derive(Debug, Eq)

///|
/// One supported ordinary text cell, with its existing cell style identifier.
pub(all) struct TextCellTarget {
  sheet : String
  address : String
  text : String
  style_id : Int?
} derive(Debug, Eq)

///|
fn correction_text(text : String) -> Unit raise XlsxError {
  validate_created_xml(text)
  if text.length() > 32767 {
    raise InvalidWorkbook("correction text exceeds 32767 UTF-16 units")
  }
  // SpreadsheetML escape tokens are not decoded by the current text reader.
  // Refuse them rather than claiming that a different Excel display was checked.
  for i = 0; i + 6 < text.length(); i = i + 1 {
    if text[i] == '_' && text[i + 1] == 'x' && text[i + 6] == '_' {
      let mut hex = true
      for j = i + 2; j < i + 6; j = j + 1 {
        if !(text[j] is ('0'..='9' | 'a'..='f' | 'A'..='F')) {
          hex = false
        }
      }
      if hex {
        raise InvalidWorkbook(
          "SpreadsheetML escaped text is outside the correction subset",
        )
      }
    }
  }
}

///|
fn correction_plain_text(container : @xml.Element) -> String raise XlsxError {
  guard container.attributes.is_empty() &&
    container.child_elements() is [text] &&
    text.name == "t" &&
    text.child_elements().is_empty() &&
    text.attributes.all(a => a.name == "xml:space") else {
    raise InvalidWorkbook(
      "selected text must be one ordinary t element; rich or phonetic text is unsupported",
    )
  }
  if container.children.any(node => {
      match node {
        Text(value) => value.trim() != ""
        _ => false
      }
    }) {
    raise InvalidWorkbook("unexpected text around selected string")
  }
  let value = text.text_content()
  correction_text(value)
  value
}

///|
/// Inspect one existing unmerged ordinary inline/shared string. Formula ranges,
/// nontext cells, rich strings and ambiguous identities are refused.
pub fn inspect_text_cell(
  archive : @opc.Package,
  sheet_name~ : String,
  address~ : String,
) -> TextCellTarget raise XlsxError {
  guard parse_cell_reference(address) is Some((row, column)) &&
    cell_reference(row, column) == address else {
    raise InvalidCellReference(address)
  }
  let selected = read_range(archive, sheet_name~, range=address)
  guard selected.rows[0][0] is Text(expected) else {
    raise InvalidWorkbook(
      "text correction requires an existing text cell at " + address,
    )
  }
  let workbook = parse_part(archive, "xl/workbook.xml")
  let descriptors = workbook_sheets(workbook)
  let relationships = workbook_relationships(archive)
  let descriptor = descriptor_named(descriptors, sheet_name).unwrap()
  let part = worksheet_part_name(relationships, descriptor)
  // An alias would let an edit affect another logical sheet as well.
  if descriptors
    .filter(d => worksheet_part_name(relationships, d) == part)
    .length() !=
    1 {
    raise InvalidWorkbook("worksheets alias the selected worksheet part")
  }
  let root = parse_part(archive, part)
  guard root.name == "worksheet" &&
    root.attribute("xmlns") ==
    Some("http://schemas.openxmlformats.org/spreadsheetml/2006/main") else {
    raise InvalidWorkbook(
      "text correction requires the standard default SpreadsheetML namespace",
    )
  }
  let data = root.first_child("sheetData").unwrap()
  guard data.name == "sheetData" &&
    data.attribute("xmlns") is None &&
    cell_location(data, row, column) is Some((ri, ci)) &&
    data.children[ri] is Element(row_node) &&
    row_node.name == "row" &&
    row_node.attribute("xmlns") is None &&
    row_node.children[ci] is Element(cell) &&
    cell.name == "c" &&
    cell.attributes.all(a => a.name == "r" || a.name == "s" || a.name == "t") else {
    raise InvalidWorkbook("selected cell has unsupported structure or metadata")
  }
  if cell.children.any(node => {
      match node {
        Text(value) => value.trim() != ""
        _ => false
      }
    }) {
    raise InvalidWorkbook("unexpected text around selected cell payload")
  }
  let text = match cell.attribute("t") {
    Some("inlineStr") => {
      guard cell.child_elements() is [inline] && inline.name == "is" else {
        raise InvalidWorkbook("selected inline string has unsupported children")
      }
      correction_plain_text(inline)
    }
    Some("s") => {
      guard cell.child_elements() is [value] &&
        value.name == "v" &&
        value.attributes.is_empty() &&
        value.child_elements().is_empty() &&
        parse_decimal(value.text_content(), 1000000) is Some(index) else {
        raise InvalidWorkbook("selected shared string index is unsupported")
      }
      guard resolved_metadata_part(
          archive, relationships, shared_strings_relationship_types,
        )
        is Some(strings) &&
        strings.name == "sst" &&
        strings.attribute("xmlns") == root.attribute("xmlns") &&
        strings.children_named("si").get(index) is Some(item) &&
        item.name == "si" else {
        raise InvalidWorkbook("selected shared string is unsupported")
      }
      correction_plain_text(item)
    }
    _ =>
      raise InvalidWorkbook(
        "only ordinary inline and shared string cells can be corrected",
      )
  }
  if text != expected {
    raise InvalidWorkbook("selected text differs from the worksheet value")
  }
  {
    sheet: sheet_name,
    address,
    text,
    style_id: integer_attribute(cell, "s", 2147483647),
  }
}

///|
/// Apply 1..100 distinct exact corrections atomically to a new package. All
/// expectations refer to the original package, including no-ops. Cell styles,
/// unrelated worksheet XML and other package payloads are retained.
pub fn correct_text_cells(
  archive : @opc.Package,
  edits : Array[TextCellCorrection],
) -> @opc.Package raise XlsxError {
  if edits.is_empty() || edits.length() > 100 {
    raise InvalidWorkbook("text correction requires 1 to 100 cells")
  }
  let seen : Map[String, Map[String, Bool]] = Map([])
  let mut units = 0
  for edit in edits {
    let addresses = seen.get_or_init(edit.sheet, () => Map([]))
    if addresses.contains(edit.address) {
      raise InvalidWorkbook(
        "duplicate correction target: " + edit.sheet + "!" + edit.address,
      )
    }
    addresses[edit.address] = true
    correction_text(edit.replacement)
    units += edit.expected.length() + edit.replacement.length()
    if units > 1000000 {
      raise InvalidWorkbook(
        "text correction exceeds 1000000 request text units",
      )
    }
    let target = inspect_text_cell(
      archive,
      sheet_name=edit.sheet,
      address=edit.address,
    )
    if target.text != edit.expected {
      raise InvalidWorkbook(
        "expected text differs at " + edit.sheet + "!" + edit.address,
      )
    }
  }
  let mut result = archive
  for edit in edits {
    if edit.expected != edit.replacement {
      let (row, column) = parse_cell_reference(edit.address).unwrap()
      result = set_cell_text(result, edit.sheet, row, column, edit.replacement)
    }
  }
  result
}
