///|
let presentation_part : String = "ppt/presentation.xml"

///|
fn presentation_relationships(
  container : @opc.Package,
) -> Array[@opc.Relationship] raise PptxError {
  container.relationships(presentation_part) catch {
    _ => raise InvalidPackagePart(part=presentation_part)
  }
}

///|
fn relationship_by_id(
  relationships : Array[@opc.Relationship],
  id : String,
) -> @opc.Relationship? {
  for relationship in relationships {
    if relationship.id == id {
      return Some(relationship)
    }
  }
  None
}

///|
fn slide_dimensions(root : @xml.Element) -> (Int, Int) raise PptxError {
  match first_descendant(root, "sldSz") {
    None => raise InvalidPresentation(message="presentation is missing p:sldSz")
    Some(size) =>
      (
        numeric_attribute(size, "cx", presentation_part, default=0),
        numeric_attribute(size, "cy", presentation_part, default=0),
      )
  }
}

///|
fn ordered_slide_parts(
  root : @xml.Element,
  relationships : Array[@opc.Relationship],
) -> Array[String] raise PptxError {
  let parts = []
  match first_descendant(root, "sldIdLst") {
    None => parts
    Some(list) => {
      for slide_id in list.children_named("sldId") {
        let relationship_id = match relationship_id_attribute(slide_id) {
          Some(id) => id
          None => raise InvalidPresentation(message="slide id is missing r:id")
        }
        match relationship_by_id(relationships, relationship_id) {
          Some(relationship) if !relationship.external =>
            parts.push(resolve_target(presentation_part, relationship.target))
          _ => raise MissingSlide(relationship_id~)
        }
      }
      parts
    }
  }
}

///|
/// Read the presentation, slide order, slide dimensions, text boxes, basic
/// preset shapes, image relationship ids, and element transforms from a PPTX
/// package.
///
/// Parsing and layout behavior were independently adapted from the permissive
/// MIT-licensed PptxGenJS project and the ECMA-376 PresentationML model. No
/// PptxGenJS source is included.
pub fn read(container : @opc.Package) -> @scene.Presentation raise PptxError {
  let root = parse_xml_part(container, presentation_part, presentation=true)
  if root.local_name() != "presentation" {
    raise InvalidPresentation(message="expected p:presentation root")
  }
  let relationships = presentation_relationships(container)
  let (width, height) = slide_dimensions(root)
  let slides = []
  for part in ordered_slide_parts(root, relationships) {
    slides.push(parse_slide(container, part, width, height))
  }
  { slides, warnings: [] }
}
