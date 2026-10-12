///|
/// One text shape or table, in XML shape-tree order. IDs are source-local.
pub(all) struct OutlineBlock {
  kind : String
  shape_id : String
  paragraphs : Array[String]
  rows : Array[Array[String]]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct SlideOutline {
  number : Int
  part : String
  name : String
  hidden : Bool
  title : String
  blocks : Array[OutlineBlock]
  notes_part : String?
  notes : Array[OutlineBlock]
} derive(Debug, Eq, ToJson)

///|
/// Read-only content extraction; not a visual or complete-source representation.
pub(all) struct PresentationOutline {
  slides : Array[SlideOutline]
  warnings : Array[String]
} derive(Debug, Eq, ToJson)

///|
fn outline_paragraphs(body : @xml.Element) -> Array[String] {
  body
  .children_named("p")
  .map(paragraph => {
    let text = StringBuilder()
    for node in paragraph.child_elements() {
      match node.local_name() {
        "r" | "fld" =>
          match node.first_child("t") {
            Some(value) => text.write_string(value.text_content())
            None => ()
          }
        "br" => text.write_char('\n')
        _ => ()
      }
    }
    text.to_string()
  })
}

///|
fn outline_shape_info(shape : @xml.Element) -> (String, String) {
  match shape.first_child("nvSpPr") {
    Some(properties) => {
      let id = match properties.first_child("cNvPr") {
        Some(value) => value.attribute("id").unwrap_or("")
        None => ""
      }
      let placeholder = match properties.first_child("nvPr") {
        Some(value) =>
          match value.first_child("ph") {
            Some(ph) => ph.attribute("type").unwrap_or("obj")
            None => ""
          }
        None => ""
      }
      (id, placeholder)
    }
    None => ("", "")
  }
}

///|
fn outline_charge(text : String, budget : Ref[Int]) -> Unit raise PptxError {
  budget.val += text.length()
  if budget.val > 2_000_000 {
    raise InvalidPresentation(
      message="outline exceeds 2000000 UTF-16 text units",
    )
  }
}

///|
fn outline_blocks(
  tree : @xml.Element,
  part : String,
  notes~ : Bool,
  title : Ref[String],
  blocks : Array[OutlineBlock],
  warnings : Array[String],
  text_budget : Ref[Int],
  item_budget : Ref[Int],
) -> Unit raise PptxError {
  for child in tree.child_elements() {
    item_budget.val += 1
    if item_budget.val > 100_000 {
      raise InvalidPresentation(
        message="outline exceeds 100000 shapes and table cells",
      )
    }
    match child.local_name() {
      "sp" => {
        let (id, placeholder) = outline_shape_info(child)
        if notes && placeholder != "" && placeholder != "body" {
          // Notes slide thumbnails, dates, footers and slide numbers are not
          // speaker content. The notes master is intentionally not traversed.
          continue
        }
        match child.first_child("txBody") {
          Some(body) => {
            let paragraphs = outline_paragraphs(body)
            for text in paragraphs {
              outline_charge(text, text_budget)
            }
            if !notes &&
              title.val == "" &&
              (placeholder == "title" || placeholder == "ctrTitle") {
              title.val = paragraphs.join("\n")
            }
            blocks.push({ kind: "text", shape_id: id, paragraphs, rows: [], })
          }
          None => ()
        }
      }
      "grpSp" =>
        outline_blocks(
          child,
          part,
          notes~,
          title,
          blocks,
          warnings,
          text_budget,
          item_budget,
        )
      "graphicFrame" => {
        let data = match child.first_child("graphic") {
          Some(graphic) => graphic.first_child("graphicData")
          None => None
        }
        let table = match data {
          Some(data) => data.first_child("tbl")
          None => None
        }
        match table {
          Some(table) => {
            let rows : Array[Array[String]] = []
            let mut merged = false
            for row in table.children_named("tr") {
              if rows.length() >= 1000 {
                raise InvalidSlide(
                  part~,
                  message="outline table exceeds 1000 rows",
                )
              }
              let cells : Array[String] = []
              for cell in row.children_named("tc") {
                item_budget.val += 1
                if cells.length() >= 256 || item_budget.val > 100_000 {
                  raise InvalidSlide(
                    part~,
                    message="outline table exceeds cell or column limit",
                  )
                }
                if cell.attribute("gridSpan").unwrap_or("1") != "1" ||
                  cell.attribute("rowSpan").unwrap_or("1") != "1" ||
                  bool_attribute(cell, "hMerge") ||
                  bool_attribute(cell, "vMerge") {
                  merged = true
                }
                let text = match cell.first_child("txBody") {
                  Some(body) => outline_paragraphs(body).join("\n")
                  None => ""
                }
                outline_charge(text, text_budget)
                cells.push(text)
              }
              rows.push(cells)
            }
            if merged {
              warnings.push(
                "\{part}: merged table cells are emitted as stored grid cells; spans are not reconstructed.",
              )
            }
            let id = match child.first_child("nvGraphicFramePr") {
              Some(properties) =>
                match properties.first_child("cNvPr") {
                  Some(value) => value.attribute("id").unwrap_or("")
                  None => ""
                }
              None => ""
            }
            blocks.push({ kind: "table", shape_id: id, paragraphs: [], rows, })
          }
          None =>
            warnings.push(
              "\{part}: non-table graphic frame omitted (for example chart or SmartArt).",
            )
        }
      }
      "pic" =>
        warnings.push("\{part}: picture omitted; no image OCR is performed.")
      "nvGrpSpPr" | "grpSpPr" => ()
      _ =>
        warnings.push(
          "\{part}: unsupported shape-tree item \{child.local_name()} omitted.",
        )
    }
  }
}

///|
fn outline_tree(
  root : @xml.Element,
  part : String,
) -> @xml.Element raise PptxError {
  match root.first_child("cSld") {
    Some(common) =>
      match common.first_child("spTree") {
        Some(tree) => tree
        None =>
          raise InvalidSlide(part~, message="outline is missing shape tree")
      }
    None =>
      raise InvalidSlide(part~, message="outline is missing common slide data")
  }
}

///|
fn outline_notes_part(
  container : @opc.Package,
  part : String,
) -> String? raise PptxError {
  if !container.has_part(@opc.relationships_part_name(part)) {
    return None
  }
  let relationships = container.relationships(part) catch {
    _ => raise InvalidSlide(part~, message="invalid slide relationships")
  }
  let mut result = None
  for rel in relationships {
    if rel.relationship_type ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" ||
      rel.relationship_type ==
      "http://purl.oclc.org/ooxml/officeDocument/relationships/notesSlide" {
      if rel.external || result != None {
        raise InvalidSlide(
          part~,
          message="external or duplicate notes relationship",
        )
      }
      result = Some(
        @opc.resolve_target(part, rel.target) catch {
          _ =>
            raise InvalidSlide(
              part~,
              message="invalid notes relationship target",
            )
        },
      )
    }
  }
  result
}

///|
/// Extract slide text, ordinary tables and speaker notes without rendering or
/// modifying the package. Includes hidden slides; follows presentation order.
/// Hard ceilings: 200 slides, 100000 shape/cell items, 2M UTF-16 text units,
/// 1000 rows and 256 columns per table. OPC/XML policies apply separately.
pub fn read_outline(
  container : @opc.Package,
) -> PresentationOutline raise PptxError {
  let root = parse_xml_part(container, presentation_part, presentation=true)
  if root.local_name() != "presentation" {
    raise InvalidPresentation(message="expected p:presentation root")
  }
  let parts = ordered_slide_parts(root, presentation_relationships(container))
  if parts.length() > 200 {
    raise InvalidPresentation(message="outline exceeds 200 slides")
  }
  let warnings = [
    "Read-only extraction in XML shape-tree order, not visual reading order. Hidden slides are included and marked.",
    "Master/layout text, charts, SmartArt, images/OCR, comments, animations, media, hyperlinks and formatting are not reproduced. External resources are never fetched.",
    "Notes include body placeholders and ordinary text shapes; notes master, slide thumbnails, dates, headers, footers and slide numbers are omitted. Field text is cached, not recalculated.",
    "Source-local slide/shape references apply only to the accompanying source digest. Extraction does not establish Office fidelity, factual truth, print readiness or acceptance.",
  ]
  let slides : Array[SlideOutline] = []
  let text_budget = Ref(0)
  let item_budget = Ref(0)
  for index, part in parts {
    let slide = parse_xml_part(container, part, presentation=false)
    if slide.local_name() != "sld" {
      raise InvalidSlide(part~, message="expected p:sld root")
    }
    let title = Ref("")
    let blocks : Array[OutlineBlock] = []
    outline_blocks(
      outline_tree(slide, part),
      part,
      notes=false,
      title,
      blocks,
      warnings,
      text_budget,
      item_budget,
    )
    let notes_part = outline_notes_part(container, part)
    let notes : Array[OutlineBlock] = []
    match notes_part {
      Some(part) => {
        let root = parse_xml_part(container, part, presentation=false)
        if root.local_name() != "notes" {
          raise InvalidSlide(part~, message="expected p:notes root")
        }
        outline_blocks(
          outline_tree(root, part),
          part,
          notes=true,
          Ref(""),
          notes,
          warnings,
          text_budget,
          item_budget,
        )
      }
      None => ()
    }
    let name = match slide.first_child("cSld") {
      Some(common) => common.attribute("name").unwrap_or(part_stem(part))
      None => part_stem(part)
    }
    outline_charge(name, text_budget)
    slides.push({
      number: index + 1,
      part,
      name,
      hidden: slide.attribute("show") == Some("0") ||
      slide.attribute("show") == Some("false"),
      title: title.val,
      blocks,
      notes_part,
      notes,
    })
  }
  { slides, warnings, }
}

///|
pub extend OutlineBlock with Debug::{to_repr}

///|
pub extend OutlineBlock with Eq::{equal, not_equal}

///|
pub extend OutlineBlock with ToJson::{to_json}

///|
pub extend SlideOutline with Debug::{to_repr}

///|
pub extend SlideOutline with Eq::{equal, not_equal}

///|
pub extend SlideOutline with ToJson::{to_json}

///|
pub extend PresentationOutline with Debug::{to_repr}

///|
pub extend PresentationOutline with Eq::{equal, not_equal}

///|
pub extend PresentationOutline with ToJson::{to_json}
