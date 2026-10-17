///|
/// Font controls exposed by the spreadsheet Home ribbon.
pub(all) enum FontDecoration {
  Bold
  Italic
  Underline
}

///|
fn decoration_tag(decoration : FontDecoration) -> String {
  match decoration {
    Bold => "b"
    Italic => "i"
    Underline => "u"
  }
}

///|
fn font_has_decoration(
  font : @xml.Element,
  decoration : FontDecoration,
) -> Bool {
  match font.first_child(decoration_tag(decoration)) {
    None => false
    Some(mark) =>
      match mark.attribute("val") {
        Some("0") | Some("false") | Some("none") => false
        _ => true
      }
  }
}

///|
fn decorated_font(
  font : @xml.Element,
  decoration : FontDecoration,
  enabled : Bool,
) -> @xml.Element {
  let tag = decoration_tag(decoration)
  let children = font.children.filter(child => {
    match child {
      Element(element) => element.local_name() != tag
      _ => true
    }
  })
  if enabled {
    children.push(
      Element(
        element(
          tag,
          match decoration {
            Underline => [attribute("val", "single")]
            Bold | Italic => []
          },
          [],
        ),
      ),
    )
  }
  { name: font.name, attributes: font.attributes, children, }
}

///|
fn font_style_id(
  xf : @xml.Element,
  font_count : Int32,
) -> Int32 raise XlsxError {
  let id = integer_attribute(xf, "fontId", 65535).unwrap_or(0)
  if id >= font_count {
    raise InvalidWorkbook("cell style has an invalid font index")
  }
  id
}

///|
/// Report one-based coordinates of existing cells with bold, italic or underline
/// enabled in their effective XLSX font style.
pub fn font_decoration_cells(
  xlsx_package : @opc.Package,
  sheet_name : String,
  decoration : FontDecoration,
) -> Array[(Int32, Int32)] raise XlsxError {
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
  let styles = parse_part(
    xlsx_package,
    wrap_styles_part(xlsx_package, relationships),
  )
  guard styles.first_child("fonts") is Some(fonts_element) &&
    styles.first_child("cellXfs") is Some(xfs_element) else {
    raise InvalidWorkbook("workbook has no font styles")
  }
  let fonts = fonts_element.children_named("font")
  let xfs = xfs_element.children_named("xf")
  let worksheet = parse_part(xlsx_package, sheet_part)
  let result : Array[(Int32, Int32)] = []
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
          if style_id >= xfs.length() {
            raise InvalidWorkbook("cell has an invalid style index")
          }
          let font_id = font_style_id(xfs[style_id], fonts.length())
          if font_has_decoration(fonts[font_id], decoration) {
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
fn decorate_cell(
  cell : @xml.Element,
  inherited_style : Int32,
  xfs : Array[@xml.Element],
  fonts : Array[@xml.Element],
  new_xfs : Array[@xml.Node],
  new_fonts : Array[@xml.Node],
  style_map : Map[Int32, Int32],
  font_map : Map[Int32, Int32],
  decoration : FontDecoration,
  enabled : Bool,
  changed : Ref[Int32],
) -> @xml.Element raise XlsxError {
  let style_id = integer_attribute(cell, "s", 65535).unwrap_or(inherited_style)
  if style_id >= xfs.length() {
    raise InvalidWorkbook("cell has an invalid style index")
  }
  let font_id = font_style_id(xfs[style_id], fonts.length())
  if font_has_decoration(fonts[font_id], decoration) == enabled {
    return cell
  }
  let new_font_id = match font_map.get(font_id) {
    Some(id) => id
    None => {
      let id = fonts.length() + new_fonts.length()
      if id >= 65536 {
        raise InvalidWorkbook("too many XLSX fonts")
      }
      new_fonts.push(
        Element(decorated_font(fonts[font_id], decoration, enabled)),
      )
      font_map[font_id] = id
      id
    }
  }
  let new_style_id = match style_map.get(style_id) {
    Some(id) => id
    None => {
      let id = xfs.length() + new_xfs.length()
      if id >= 65536 {
        raise InvalidWorkbook("too many XLSX styles")
      }
      new_xfs.push(
        Element({
          name: xfs[style_id].name,
          attributes: wrap_attribute(
            wrap_attribute(
              xfs[style_id].attributes,
              "fontId",
              new_font_id.to_string(),
            ),
            "applyFont",
            "1",
          ),
          children: xfs[style_id].children,
        }),
      )
      style_map[style_id] = id
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
fn decorated_blank_cell(
  row : Int32,
  column : Int32,
  inherited_style : Int32,
  xfs : Array[@xml.Element],
  fonts : Array[@xml.Element],
  new_xfs : Array[@xml.Node],
  new_fonts : Array[@xml.Node],
  style_map : Map[Int32, Int32],
  font_map : Map[Int32, Int32],
  decoration : FontDecoration,
  enabled : Bool,
  changed : Ref[Int32],
) -> @xml.Node? raise XlsxError {
  if !enabled {
    return None
  }
  Some(
    Element(
      decorate_cell(
        element("c", [attribute("r", cell_reference(row, column))], []),
        inherited_style,
        xfs,
        fonts,
        new_xfs,
        new_fonts,
        style_map,
        font_map,
        decoration,
        enabled,
        changed,
      ),
    ),
  )
}

///|
fn decorated_row(
  row_element : @xml.Element,
  row : Int32,
  start_column : Int32,
  end_column : Int32,
  xfs : Array[@xml.Element],
  fonts : Array[@xml.Element],
  new_xfs : Array[@xml.Node],
  new_fonts : Array[@xml.Node],
  style_map : Map[Int32, Int32],
  font_map : Map[Int32, Int32],
  decoration : FontDecoration,
  enabled : Bool,
  changed : Ref[Int32],
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
              decorated_blank_cell(
                row, gap, inherited_style, xfs, fonts, new_xfs, new_fonts, style_map,
                font_map, decoration, enabled, changed,
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
              decorate_cell(
                cell, inherited_style, xfs, fonts, new_xfs, new_fonts, style_map,
                font_map, decoration, enabled, changed,
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
        decorated_blank_cell(
          row, column, inherited_style, xfs, fonts, new_xfs, new_fonts, style_map,
          font_map, decoration, enabled, changed,
        ) {
        Some(blank) => children.push(blank)
        None => ()
      }
    }
  }
  { name: row_element.name, attributes: row_element.attributes, children, }
}

///|
fn decorated_new_row(
  row : Int32,
  start_column : Int32,
  end_column : Int32,
  xfs : Array[@xml.Element],
  fonts : Array[@xml.Element],
  new_xfs : Array[@xml.Node],
  new_fonts : Array[@xml.Node],
  style_map : Map[Int32, Int32],
  font_map : Map[Int32, Int32],
  decoration : FontDecoration,
  enabled : Bool,
  changed : Ref[Int32],
) -> @xml.Node? raise XlsxError {
  if !enabled {
    return None
  }
  let cells : Array[@xml.Node] = []
  for column in start_column..<=end_column {
    match
      decorated_blank_cell(
        row, column, 0, xfs, fonts, new_xfs, new_fonts, style_map, font_map, decoration,
        enabled, changed,
      ) {
      Some(blank) => cells.push(blank)
      None => ()
    }
  }
  Some(Element(element("row", [attribute("r", row.to_string())], cells)))
}

///|
/// Toggle bold, italic or underline on a bounded XLSX range. Cell values and all
/// unrelated font, cell style, and package properties are preserved.
pub fn set_font_decoration_range(
  xlsx_package : @opc.Package,
  sheet_name : String,
  start_row : Int32,
  start_column : Int32,
  end_row : Int32,
  end_column : Int32,
  decoration : FontDecoration,
  enabled : Bool,
) -> (@opc.Package, Int32) raise XlsxError {
  if start_row < 1 ||
    start_column < 1 ||
    end_row < start_row ||
    end_column < start_column ||
    end_row > max_row ||
    end_column > max_column ||
    (end_row - start_row + 1) * (end_column - start_column + 1) > 1_000 {
    raise InvalidWorkbook("font range exceeds bounds")
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
  guard style_sheet.local_name() == "styleSheet" &&
    worksheet.local_name() == "worksheet" &&
    style_sheet.first_child("fonts") is Some(fonts_element) &&
    style_sheet.first_child("cellXfs") is Some(xfs_element) else {
    raise InvalidWorkbook("workbook has no editable font styles")
  }
  let fonts = fonts_element.children_named("font")
  let xfs = xfs_element.children_named("xf")
  if fonts.is_empty() || xfs.is_empty() {
    raise InvalidWorkbook("workbook has no base font style")
  }
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
  let new_fonts : Array[@xml.Node] = []
  let new_xfs : Array[@xml.Node] = []
  let font_map : Map[Int32, Int32] = Map([])
  let style_map : Map[Int32, Int32] = Map([])
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
                    decorated_new_row(
                      gap, start_column, end_column, xfs, fonts, new_xfs, new_fonts,
                      style_map, font_map, decoration, enabled, changed,
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
                    decorated_row(
                      row_element, row, start_column, end_column, xfs, fonts, new_xfs,
                      new_fonts, style_map, font_map, decoration, enabled, changed,
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
              decorated_new_row(
                row, start_column, end_column, xfs, fonts, new_xfs, new_fonts, style_map,
                font_map, decoration, enabled, changed,
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
  let style_children : Array[@xml.Node] = style_sheet.children.map(child => {
    match child {
      Element(item) if item.local_name() == "fonts" => {
        let children = item.children.copy()
        children.append(new_fonts)
        Element({
          name: item.name,
          attributes: wrap_attribute(
            item.attributes,
            "count",
            (fonts.length() + new_fonts.length()).to_string(),
          ),
          children,
        })
      }
      Element(item) if item.local_name() == "cellXfs" => {
        let children = item.children.copy()
        children.append(new_xfs)
        Element({
          name: item.name,
          attributes: wrap_attribute(
            item.attributes,
            "count",
            (xfs.length() + new_xfs.length()).to_string(),
          ),
          children,
        })
      }
      _ => child
    }
  })
  let updated_sheet = xlsx_package.replace_text(
    sheet_part,
    @xml.serialize({
      name: worksheet.name,
      attributes: worksheet.attributes,
      children: sheet_children,
    }),
  )
  (
    updated_sheet.replace_text(
      styles_part,
      @xml.serialize({
        name: style_sheet.name,
        attributes: style_sheet.attributes,
        children: style_children,
      }),
    ),
    changed.val,
  )
}
