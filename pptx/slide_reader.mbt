///|
fn parse_bounds(
  element : @xml.Element,
  part : String,
) -> @scene.Rect raise PptxError {
  match first_descendant(element, "xfrm") {
    None => { x: 0, y: 0, width: 0, height: 0 }
    Some(transform) => {
      let offset = transform.first_child("off")
      let extent = transform.first_child("ext")
      {
        x: match offset {
          Some(value) => numeric_attribute(value, "x", part, default=0)
          None => 0
        },
        y: match offset {
          Some(value) => numeric_attribute(value, "y", part, default=0)
          None => 0
        },
        width: match extent {
          Some(value) => numeric_attribute(value, "cx", part, default=0)
          None => 0
        },
        height: match extent {
          Some(value) => numeric_attribute(value, "cy", part, default=0)
          None => 0
        },
      }
    }
  }
}

///|
fn is_text_box(shape : @xml.Element) -> Bool {
  match first_descendant(shape, "cNvSpPr") {
    Some(properties) => bool_attribute(properties, "txBox")
    None => false
  }
}

///|
fn shape_kind(shape : @xml.Element) -> String {
  match first_descendant(shape, "prstGeom") {
    Some(geometry) =>
      match geometry.attribute("prst") {
        Some(kind) => kind
        None => "shape"
      }
    None => "shape"
  }
}

///|
fn parse_shape(
  shape : @xml.Element,
  part : String,
) -> @scene.SlideElement raise PptxError {
  let bounds = parse_bounds(shape, part)
  let runs = match first_descendant(shape, "txBody") {
    Some(body) => text_runs(body, part)
    None => []
  }
  if is_text_box(shape) {
    TextBox(bounds~, runs~)
  } else {
    Shape(kind=shape_kind(shape), bounds~, text=runs)
  }
}

///|
fn parse_image(
  picture : @xml.Element,
  part : String,
) -> @scene.SlideElement raise PptxError {
  let relationship_id = match first_descendant(picture, "blip") {
    Some(blip) =>
      match blip.attribute("embed") {
        Some(id) => id
        None =>
          match blip.attribute("link") {
            Some(id) => id
            None => ""
          }
      }
    None => ""
  }
  Image(bounds=parse_bounds(picture, part), relationship_id~)
}

///|
fn append_slide_elements(
  shape_tree : @xml.Element,
  part : String,
  elements : Array[@scene.SlideElement],
) -> Unit raise PptxError {
  for element in shape_tree.child_elements() {
    match element.local_name() {
      "sp" => elements.push(parse_shape(element, part))
      "pic" => elements.push(parse_image(element, part))
      "grpSp" => append_slide_elements(element, part, elements)
      _ => ()
    }
  }
}

///|
fn parse_slide(
  container : @opc.Package,
  part : String,
  width : Int,
  height : Int,
) -> @scene.Slide raise PptxError {
  let root = parse_xml_part(container, part, presentation=false)
  if root.local_name() != "sld" {
    raise InvalidSlide(part~, message="expected p:sld root")
  }
  let common_slide_data = match first_descendant(root, "cSld") {
    Some(value) => value
    None => raise InvalidSlide(part~, message="missing common slide data")
  }
  let shape_tree = match first_descendant(common_slide_data, "spTree") {
    Some(value) => value
    None => raise InvalidSlide(part~, message="missing shape tree")
  }
  let elements : Array[@scene.SlideElement] = []
  append_slide_elements(shape_tree, part, elements)
  let name = match common_slide_data.attribute("name") {
    Some(value) if value != "" => value
    _ => part_stem(part)
  }
  { name, width, height, elements }
}
