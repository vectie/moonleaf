///|
fn wrap_attribute(
  attributes : Array[@xml.Attribute],
  name : String,
  value : String,
) -> Array[@xml.Attribute] {
  let updated = attributes.filter(attribute => attribute.name != name)
  updated.push({ name, value, })
  updated
}

///|
priv enum CellStyleEdit {
  Wrap(Bool)
  Horizontal(String)
  NumberFormat(Int)
}

///|
fn style_creates_blank(edit : CellStyleEdit) -> Bool {
  match edit {
    Wrap(enabled) => enabled
    Horizontal(_) | NumberFormat(_) => true
  }
}

///|
fn style_matches(xf : @xml.Element, edit : CellStyleEdit) -> Bool {
  match edit {
    Wrap(enabled) => xf_wraps(xf) == enabled
    Horizontal(value) =>
      match xf.first_child("alignment") {
        Some(alignment) => alignment.attribute("horizontal") == Some(value)
        None => false
      }
    NumberFormat(id) =>
      integer_attribute(xf, "numFmtId", 65535).unwrap_or(0) == id
  }
}

///|
fn with_cell_style(xf : @xml.Element, edit : CellStyleEdit) -> @xml.Element {
  let (field, value) = match edit {
    NumberFormat(id) =>
      return {
        name: xf.name,
        attributes: wrap_attribute(
          wrap_attribute(xf.attributes, "numFmtId", id.to_string()),
          "applyNumberFormat",
          "1",
        ),
        children: xf.children,
      }
    Wrap(enabled) => ("wrapText", if enabled { "1" } else { "0" })
    Horizontal(value) => ("horizontal", value)
  }
  let mut found = false
  let children : Array[@xml.Node] = xf.children.map(child => {
    match child {
      Element(alignment) if alignment.local_name() == "alignment" => {
        found = true
        Element({
          name: alignment.name,
          attributes: wrap_attribute(alignment.attributes, field, value),
          children: alignment.children,
        })
      }
      _ => child
    }
  })
  if !found {
    let mut inserted = false
    let ordered : Array[@xml.Node] = []
    for child in children {
      match child {
        Element(item) if !inserted &&
          (item.local_name() == "protection" || item.local_name() == "extLst") => {
          ordered.push(
            Element(element("alignment", [attribute(field, value)], [])),
          )
          inserted = true
        }
        _ => ()
      }
      ordered.push(child)
    }
    if !inserted {
      ordered.push(Element(element("alignment", [attribute(field, value)], [])))
    }
    return {
      name: xf.name,
      attributes: wrap_attribute(xf.attributes, "applyAlignment", "1"),
      children: ordered,
    }
  }
  {
    name: xf.name,
    attributes: wrap_attribute(xf.attributes, "applyAlignment", "1"),
    children,
  }
}

///|
/// Report one-based coordinates of cells whose XLSX style enables automatic
/// wrapping. This lets a preview render the saved workbook's actual state.
pub fn wrapped_cells(
  xlsx_package : @opc.Package,
  sheet_name : String,
) -> Array[(Int, Int)] raise XlsxError {
  if !xlsx_package.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let descriptors = workbook_sheets(parse_part(xlsx_package, "xl/workbook.xml"))
  guard descriptor_named(descriptors, sheet_name) is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let relationships = workbook_relationships(xlsx_package)
  let sheet_part = worksheet_part_name(relationships, descriptor)
  if !relationships.any(relationship => {
      !relationship.external &&
      styles_relationship_types.contains(relationship.relationship_type)
    }) {
    return []
  }
  let style_part = wrap_styles_part(xlsx_package, relationships)
  guard parse_part(xlsx_package, style_part).first_child("cellXfs")
    is Some(cell_xfs) else {
    raise InvalidWorkbook("workbook has no cell styles")
  }
  let styles = cell_xfs.children_named("xf")
  let worksheet = parse_part(xlsx_package, sheet_part)
  let result : Array[(Int, Int)] = []
  match worksheet.first_child("sheetData") {
    Some(data) => {
      let mut previous_row = 0
      for row_element in data.children_named("row") {
        let row = row_number(row_element).unwrap_or(previous_row + 1)
        previous_row = row
        let inherited_style = integer_attribute(row_element, "s", 65535).unwrap_or(
          0,
        )
        let mut previous_column = 0
        for cell in row_element.children_named("c") {
          let column = cell_column_or_implicit(cell, row, previous_column)
          previous_column = column
          let style_id = integer_attribute(cell, "s", 65535).unwrap_or(
            inherited_style,
          )
          if style_id >= styles.length() {
            raise InvalidWorkbook("cell has an invalid style index")
          }
          if xf_wraps(styles[style_id]) {
            result.push((row, column))
          }
        }
      }
    }
    None => ()
  }
  result
}

///|
fn xf_wraps(xf : @xml.Element) -> Bool {
  match xf.first_child("alignment") {
    Some(alignment) =>
      alignment.attribute("wrapText") == Some("1") ||
      alignment.attribute("wrapText") == Some("true")
    None => false
  }
}

///|
fn wrap_styles_part(
  xlsx_package : @opc.Package,
  relationships : Array[@opc.Relationship],
) -> String raise XlsxError {
  let mut found : String? = None
  for relationship in relationships {
    if styles_relationship_types.contains(relationship.relationship_type) &&
      !relationship.external {
      if found is Some(_) {
        raise InvalidWorkbook("duplicate XLSX style relationships")
      }
      let part = @opc.resolve_target("xl/workbook.xml", relationship.target) catch {
        error =>
          raise PackageFailure(
            part="xl/_rels/workbook.xml.rels",
            message="\{Repr(error)}",
          )
      }
      found = Some(part)
    }
  }
  guard found is Some(part) && xlsx_package.has_part(part) else {
    raise InvalidWorkbook("workbook has no editable styles part")
  }
  part
}

///|
fn styled_cell(
  cell : @xml.Element,
  inherited_style : Int,
  styles : Array[@xml.Element],
  additions : Array[@xml.Node],
  mapping : Map[Int, Int],
  edit : CellStyleEdit,
  changed : Ref[Int],
) -> @xml.Element raise XlsxError {
  let style_id = integer_attribute(cell, "s", 65535).unwrap_or(inherited_style)
  if style_id >= styles.length() {
    raise InvalidWorkbook("cell has an invalid style index")
  }
  if style_matches(styles[style_id], edit) {
    return cell
  }
  let new_style_id = match mapping.get(style_id) {
    Some(id) => id
    None => {
      let id = styles.length() + additions.length()
      if id >= 65536 {
        raise InvalidWorkbook("too many XLSX styles")
      }
      additions.push(Element(with_cell_style(styles[style_id], edit)))
      mapping[style_id] = id
      id
    }
  }
  changed.val += 1
  {
    name: cell.name,
    attributes: wrap_attribute(cell.attributes, "s", new_style_id.to_string()),
    children: cell.children,
  }
}

///|
fn aligned_blank_cell(
  row : Int,
  column : Int,
  inherited_style : Int,
  styles : Array[@xml.Element],
  additions : Array[@xml.Node],
  mapping : Map[Int, Int],
  edit : CellStyleEdit,
  changed : Ref[Int],
) -> @xml.Node? raise XlsxError {
  if !style_creates_blank(edit) {
    return None
  }
  Some(
    Element(
      styled_cell(
        element("c", [attribute("r", cell_reference(row, column))], []),
        inherited_style,
        styles,
        additions,
        mapping,
        edit,
        changed,
      ),
    ),
  )
}

///|
fn aligned_row(
  row_element : @xml.Element,
  row : Int,
  start_column : Int,
  end_column : Int,
  styles : Array[@xml.Element],
  additions : Array[@xml.Node],
  mapping : Map[Int, Int],
  edit : CellStyleEdit,
  changed : Ref[Int],
) -> @xml.Element raise XlsxError {
  let inherited_style = integer_attribute(row_element, "s", 65535).unwrap_or(0)
  let children : Array[@xml.Node] = []
  let mut previous_column = 0
  for child in row_element.children {
    match child {
      Element(cell) if cell.local_name() == "c" => {
        let column = cell_column_or_implicit(cell, row, previous_column)
        for gap in start_column..<column {
          if gap > previous_column && gap <= end_column {
            match
              aligned_blank_cell(
                row, gap, inherited_style, styles, additions, mapping, edit, changed,
              ) {
              Some(blank) => children.push(blank)
              None => ()
            }
          }
        }
        previous_column = column
        if column >= start_column && column <= end_column {
          children.push(
            Element(
              styled_cell(
                cell, inherited_style, styles, additions, mapping, edit, changed,
              ),
            ),
          )
        } else {
          children.push(child)
        }
      }
      _ => children.push(child)
    }
  }
  for column in start_column..<=end_column {
    if column > previous_column {
      match
        aligned_blank_cell(
          row, column, inherited_style, styles, additions, mapping, edit, changed,
        ) {
        Some(blank) => children.push(blank)
        None => ()
      }
    }
  }
  { name: row_element.name, attributes: row_element.attributes, children, }
}

///|
fn aligned_new_row(
  row : Int,
  start_column : Int,
  end_column : Int,
  styles : Array[@xml.Element],
  additions : Array[@xml.Node],
  mapping : Map[Int, Int],
  edit : CellStyleEdit,
  changed : Ref[Int],
) -> @xml.Node? raise XlsxError {
  if !style_creates_blank(edit) {
    return None
  }
  let cells : Array[@xml.Node] = []
  for column in start_column..<=end_column {
    match
      aligned_blank_cell(
        row, column, 0, styles, additions, mapping, edit, changed,
      ) {
      Some(blank) => cells.push(blank)
      None => ()
    }
  }
  Some(Element(element("row", [attribute("r", row.to_string())], cells)))
}

///|
/// Apply a bounded XLSX style edit without changing cell values or formulas.
fn set_cell_style_range(
  xlsx_package : @opc.Package,
  sheet_name : String,
  start_row : Int,
  start_column : Int,
  end_row : Int,
  end_column : Int,
  edit : CellStyleEdit,
) -> (@opc.Package, Int) raise XlsxError {
  if start_row < 1 ||
    start_column < 1 ||
    end_row < start_row ||
    end_column < start_column ||
    end_row > max_row ||
    end_column > max_column ||
    (end_row - start_row + 1) * (end_column - start_column + 1) > 1_000 {
    raise InvalidWorkbook("style range exceeds bounds")
  }
  if !xlsx_package.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let descriptors = workbook_sheets(parse_part(xlsx_package, "xl/workbook.xml"))
  guard descriptor_named(descriptors, sheet_name) is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let relationships = workbook_relationships(xlsx_package)
  let sheet_part = worksheet_part_name(relationships, descriptor)
  if !xlsx_package.has_part(sheet_part) {
    raise MissingWorksheet(
      sheet=descriptor.name,
      relationship_id=descriptor.relationship_id,
    )
  }
  let styles_part = wrap_styles_part(xlsx_package, relationships)
  let style_sheet = parse_part(xlsx_package, styles_part)
  let worksheet = parse_part(xlsx_package, sheet_part)
  let worksheet = if worksheet.first_child("sheetData") is Some(_) {
    worksheet
  } else {
    let children : Array[@xml.Node] = []
    let inserted = Ref(false)
    for child in worksheet.children {
      match child {
        Element(item) if !inserted.val &&
          comes_after_sheet_data(item.local_name()) => {
          children.push(Element(element("sheetData", [], [])))
          inserted.val = true
        }
        _ => ()
      }
      children.push(child)
    }
    if !inserted.val {
      children.push(Element(element("sheetData", [], [])))
    }
    { name: worksheet.name, attributes: worksheet.attributes, children, }
  }
  guard style_sheet.local_name() == "styleSheet" &&
    worksheet.local_name() == "worksheet" &&
    style_sheet.first_child("cellXfs") is Some(cell_xfs) else {
    raise InvalidWorkbook("workbook has no cell styles")
  }
  let styles = cell_xfs.children_named("xf")
  if styles.is_empty() {
    raise InvalidWorkbook("workbook has no base cell style")
  }
  let additions : Array[@xml.Node] = []
  let mapping : Map[Int, Int] = Map([])
  let changed = Ref(0)
  let sheet_children : Array[@xml.Node] = worksheet.children.map(child => {
    match child {
      Element(data) if data.local_name() == "sheetData" => {
        let mut previous_row = 0
        let rows : Array[@xml.Node] = []
        for row_child in data.children {
          match row_child {
            Element(row_element) if row_element.local_name() == "row" => {
              let row = row_number(row_element).unwrap_or(previous_row + 1)
              let gap_limit = if row <= end_row { row } else { end_row + 1 }
              for gap in start_row..<gap_limit {
                if gap > previous_row && gap <= end_row {
                  match
                    aligned_new_row(
                      gap, start_column, end_column, styles, additions, mapping,
                      edit, changed,
                    ) {
                    Some(new_row) => rows.push(new_row)
                    None => ()
                  }
                }
              }
              previous_row = row
              if row < start_row || row > end_row {
                rows.push(row_child)
              } else {
                rows.push(
                  Element(
                    aligned_row(
                      row_element, row, start_column, end_column, styles, additions,
                      mapping, edit, changed,
                    ),
                  ),
                )
              }
            }
            _ => rows.push(row_child)
          }
        }
        for row in start_row..<=end_row {
          if row > previous_row {
            match
              aligned_new_row(
                row, start_column, end_column, styles, additions, mapping, edit,
                changed,
              ) {
              Some(new_row) => rows.push(new_row)
              None => ()
            }
          }
        }
        Element({
          name: data.name,
          attributes: data.attributes,
          children: rows,
        })
      }
      _ => child
    }
  })
  if changed.val == 0 {
    return (xlsx_package, 0)
  }
  let new_styles : Array[@xml.Node] = style_sheet.children.map(child => {
    match child {
      Element(xfs) if xfs.local_name() == "cellXfs" => {
        let children = xfs.children.copy()
        children.append(additions)
        Element({
          name: xfs.name,
          attributes: wrap_attribute(
            xfs.attributes,
            "count",
            (styles.length() + additions.length()).to_string(),
          ),
          children,
        })
      }
      _ => child
    }
  })
  let new_sheet = xlsx_package.replace_text(
    sheet_part,
    @xml.serialize({
      name: worksheet.name,
      attributes: worksheet.attributes,
      children: sheet_children,
    }),
  )
  (
    new_sheet.replace_text(
      styles_part,
      @xml.serialize({
        name: style_sheet.name,
        attributes: style_sheet.attributes,
        children: new_styles,
      }),
    ),
    changed.val,
  )
}

///|
/// Set Excel's automatic text wrapping on cells in a bounded range.
/// Values, formulas, unrelated styles, and other OPC parts remain intact.
/// The returned count is the number of cells whose effective wrap flag changed.
pub fn set_wrap_text_range(
  xlsx_package : @opc.Package,
  sheet_name : String,
  start_row : Int,
  start_column : Int,
  end_row : Int,
  end_column : Int,
  enabled : Bool,
) -> (@opc.Package, Int) raise XlsxError {
  set_cell_style_range(
    xlsx_package,
    sheet_name,
    start_row,
    start_column,
    end_row,
    end_column,
    Wrap(enabled),
  )
}
