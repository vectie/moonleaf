///|
/// An ordinary slide table in presentation and shape-tree order. A refusal
/// leaves rows empty. References must be bound to the exact source digest.
pub(all) struct SlideTable {
  id : String
  slide_number : Int
  part : String
  shape_id : String
  hidden_slide : Bool
  rows : Array[Array[String]]
  refusal : String?
} derive(Debug, Eq, ToJson)

///|
let table_p_namespace : String = "http://schemas.openxmlformats.org/presentationml/2006/main"

///|
let table_a_namespace : String = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
let table_r_namespace : String = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

///|
fn table_namespace_check(
  element : @xml.Element,
  part : String,
) -> Unit raise PptxError {
  for attribute in element.attributes {
    let expected = match attribute.name {
      "xmlns:p" => Some(table_p_namespace)
      "xmlns:a" => Some(table_a_namespace)
      "xmlns:r" => Some(table_r_namespace)
      _ => None
    }
    if expected is Some(expected) && attribute.value != expected {
      raise InvalidSlide(
        part~,
        message="rebound standard namespace is unsupported",
      )
    }
  }
  for child in element.child_elements() {
    table_namespace_check(child, part)
  }
}

///|
fn table_children(
  element : @xml.Element,
  part : String,
) -> Array[@xml.Element] raise PptxError {
  if element.children.any(node => {
      node is Text(text) && text.trim().to_owned() != ""
    }) {
    raise InvalidSlide(part~, message="unexpected text outside a:t")
  }
  element.child_elements()
}

///|
fn table_one(
  element : @xml.Element,
  name : String,
  part : String,
) -> @xml.Element raise PptxError {
  let matches = element.child_elements().filter(child => child.name == name)
  guard matches is [found] else {
    raise InvalidSlide(part~, message="requires exactly one " + name)
  }
  found
}

///|
fn table_selected_properties(
  element : @xml.Element,
  part : String,
) -> Unit raise PptxError {
  if ["a:fld", "a:hlinkClick", "a:hlinkMouseOver", "a:extLst"].contains(
      element.name,
    ) {
    raise InvalidSlide(
      part~,
      message="unsupported selected content: " + element.name,
    )
  }
  for child in element.child_elements() {
    table_selected_properties(child, part)
  }
}

///|
fn table_paragraph(
  paragraph : @xml.Element,
  part : String,
) -> String raise PptxError {
  let result = StringBuilder()
  for child in table_children(paragraph, part) {
    match child.name {
      "a:pPr" | "a:endParaRPr" => ()
      "a:br" => {
        if table_children(child, part).any(e => e.name != "a:rPr") {
          raise InvalidSlide(part~, message="unsupported break content")
        }
        result.write_char('\n')
      }
      "a:r" => {
        let text = table_one(child, "a:t", part)
        if !text.child_elements().is_empty() ||
          table_children(child, part).any(e => {
            e.name != "a:rPr" && e.name != "a:t"
          }) {
          raise InvalidSlide(part~, message="unsupported selected text run")
        }
        result.write_string(text.text_content())
      }
      _ =>
        raise InvalidSlide(
          part~,
          message="unsupported paragraph content: " + child.name,
        )
    }
  }
  result.to_string()
}

///|
fn table_cell(cell : @xml.Element, part : String) -> String raise PptxError {
  if cell.attributes.any(a => {
      ["gridSpan", "rowSpan", "hMerge", "vMerge"].contains(a.name)
    }) {
    raise InvalidSlide(
      part~,
      message="merged or explicitly spanned cells are unsupported",
    )
  }
  if table_children(cell, part).any(e => {
      e.name != "a:txBody" && e.name != "a:tcPr"
    }) {
    raise InvalidSlide(part~, message="unsupported cell content")
  }
  let body = table_one(cell, "a:txBody", part)
  let paragraphs : Array[String] = []
  for child in table_children(body, part) {
    match child.name {
      "a:bodyPr" | "a:lstStyle" => ()
      "a:p" => paragraphs.push(table_paragraph(child, part))
      _ =>
        raise InvalidSlide(
          part~,
          message="unsupported text body content: " + child.name,
        )
    }
  }
  if paragraphs.is_empty() {
    raise InvalidSlide(part~, message="cell requires at least one paragraph")
  }
  paragraphs.join("\n")
}

///|
fn table_values(
  table : @xml.Element,
  part : String,
) -> Array[Array[String]] raise PptxError {
  table_selected_properties(table, part)
  let grid = table_one(table, "a:tblGrid", part)
  let grid_columns = table_children(grid, part)
  let width = grid_columns.length()
  if width < 1 || width > 128 || grid_columns.any(e => e.name != "a:gridCol") {
    raise InvalidSlide(part~, message="table grid must have 1 to 128 columns")
  }
  let result : Array[Array[String]] = []
  let mut units = 0
  for child in table_children(table, part) {
    match child.name {
      "a:tblPr" | "a:tblGrid" => ()
      "a:tr" => {
        if result.length() >= 1000 || (result.length() + 1) * width > 100000 {
          raise InvalidSlide(
            part~,
            message="table exceeds 1000 rows or 100000 cells",
          )
        }
        let cells = table_children(child, part)
        if cells.length() != width || cells.any(e => e.name != "a:tc") {
          raise InvalidSlide(
            part~,
            message="table rows must match the rectangular grid",
          )
        }
        let row = cells.map(cell => table_cell(cell, part))
        for text in row {
          units += text.length()
          if units > 2_000_000 {
            raise InvalidSlide(
              part~,
              message="table exceeds 2000000 text units",
            )
          }
        }
        result.push(row)
      }
      _ =>
        raise InvalidSlide(
          part~,
          message="unsupported table content: " + child.name,
        )
    }
  }
  if result.is_empty() {
    raise InvalidSlide(part~, message="table has no rows")
  }
  result
}

///|
fn table_frames(
  tree : @xml.Element,
  frames : Array[@xml.Element],
  items : Ref[Int],
) -> Unit raise PptxError {
  for child in tree.child_elements() {
    items.val += 1
    if items.val > 100000 {
      raise InvalidPresentation(
        message="table discovery exceeds 100000 shape-tree items",
      )
    }
    if child.name == "p:grpSp" {
      table_frames(child, frames, items)
    } else if child.name == "p:graphicFrame" {
      // Only actual DrawingML table frames are candidates; charts are unrelated.
      if child
        .children_named("graphic")
        .any(g => {
          g
          .children_named("graphicData")
          .any(d => d.child_elements().any(t => t.name == "a:tbl"))
        }) {
        frames.push(child)
      }
    }
  }
}

///|
fn table_slide_parts(
  list : @xml.Element,
  relationships : Array[@opc.Relationship],
) -> Array[String] raise PptxError {
  let parts : Array[String] = []
  for slide in table_children(list, presentation_part) {
    guard slide.name == "p:sldId" && slide.attribute("r:id") is Some(id) else {
      raise InvalidPresentation(message="unsupported slide list content")
    }
    let relationship = relationship_by_id(relationships, id)
    guard relationship is Some(relationship) else {
      raise MissingSlide(relationship_id=id)
    }
    if relationship.external ||
      ![
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide",
        "http://purl.oclc.org/ooxml/officeDocument/relationships/slide",
      ].contains(relationship.relationship_type) {
      raise InvalidPresentation(message="invalid slide relationship " + id)
    }
    let part = @opc.resolve_target(presentation_part, relationship.target) catch {
      _ =>
        raise InvalidPresentation(
          message="invalid slide relationship target " + id,
        )
    }
    parts.push(part)
  }
  parts
}

///|
/// Discover source-local slide tables, including hidden slides and groups.
/// Parse the selected text subset conservatively; unrelated unsupported tables
/// are returned with refusal details rather than blocking usable tables.
pub fn read_tables(
  container : @opc.Package,
) -> Array[SlideTable] raise PptxError {
  let root = parse_xml_part(container, presentation_part, presentation=true)
  if root.name != "p:presentation" ||
    root.attribute("xmlns:p") != Some(table_p_namespace) ||
    root.attribute("xmlns:r") != Some(table_r_namespace) {
    raise InvalidPresentation(
      message="requires standard transitional p:presentation namespaces",
    )
  }
  table_namespace_check(root, presentation_part)
  if root.child_elements().filter(e => e.name == "p:sldIdLst").is_empty() {
    return []
  }
  let list = table_one(root, "p:sldIdLst", presentation_part)
  let parts = table_slide_parts(list, presentation_relationships(container))
  if parts.length() > 200 {
    raise InvalidPresentation(message="table discovery exceeds 200 slides")
  }
  let result : Array[SlideTable] = []
  let items = Ref(0)
  let mut text_units = 0
  let mut cells = 0
  for index, part in parts {
    let slide = parse_xml_part(container, part, presentation=false)
    if slide.name != "p:sld" ||
      slide.attribute("xmlns:p") != Some(table_p_namespace) ||
      slide.attribute("xmlns:a") != Some(table_a_namespace) {
      raise InvalidSlide(
        part~,
        message="requires standard transitional p:sld namespaces",
      )
    }
    table_namespace_check(slide, part)
    let common = table_one(slide, "p:cSld", part)
    let tree = table_one(common, "p:spTree", part)
    let frames : Array[@xml.Element] = []
    table_frames(tree, frames, items)
    for ordinal, frame in frames {
      if result.length() >= 1000 {
        raise InvalidPresentation(message="table discovery exceeds 1000 tables")
      }
      let id = "slide:" +
        (index + 1).to_string() +
        "/table:" +
        (ordinal + 1).to_string()
      let shape_id = match frame.first_child("nvGraphicFramePr") {
        Some(properties) =>
          match properties.first_child("cNvPr") {
            Some(value) => value.attribute("id").unwrap_or("")
            None => ""
          }
        None => ""
      }
      let parsed = try {
        let graphic = table_one(frame, "a:graphic", part)
        let data = table_one(graphic, "a:graphicData", part)
        if data.attribute("uri") !=
          Some("http://schemas.openxmlformats.org/drawingml/2006/table") ||
          table_children(data, part).any(e => e.name != "a:tbl") {
          raise InvalidSlide(
            part~,
            message="unsupported graphic data for selected table",
          )
        }
        table_values(table_one(data, "a:tbl", part), part)
      } catch {
        error => Err(error)
      } noraise {
        rows => Ok(rows)
      }
      let (rows, refusal) = match parsed {
        Ok(rows) => (rows, None)
        Err(error) => ([], Some(error.to_string()))
      }
      for row in rows {
        cells += row.length()
        if cells > 100000 {
          raise InvalidPresentation(
            message="discovered tables exceed 100000 cells",
          )
        }
        for text in row {
          text_units += text.length()
          if text_units > 2_000_000 {
            raise InvalidPresentation(
              message="discovered tables exceed 2000000 text units",
            )
          }
        }
      }
      result.push({
        id,
        slide_number: index + 1,
        part,
        shape_id,
        hidden_slide: slide.attribute("show") == Some("0") ||
        slide.attribute("show") == Some("false"),
        rows,
        refusal,
      })
    }
  }
  result
}

///|
pub extend SlideTable with Eq::{equal, not_equal}

///|
pub extend SlideTable with @debug.Debug::{to_repr}

///|
pub extend SlideTable with ToJson::{to_json}
