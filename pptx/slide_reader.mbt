///|
priv struct LocalTransform {
  x : Int
  y : Int
  width : Int
  height : Int
  // Exact affine scale, retained as a ratio through nested groups.
  scale_x_num : Int
  scale_x_den : Int
  scale_y_num : Int
  scale_y_den : Int
  group_width : Int
  group_height : Int
  rotation : Int
  flip_h : Bool
  flip_v : Bool
}

///|
fn identity_transform() -> LocalTransform {
  {
    x: 0,
    y: 0,
    width: 1,
    height: 1,
    scale_x_num: 1,
    scale_x_den: 1,
    scale_y_num: 1,
    scale_y_den: 1,
    group_width: 0,
    group_height: 0,
    rotation: 0,
    flip_h: false,
    flip_v: false,
  }
}

///|
fn item_transform(
  element : @xml.Element,
  part : String,
) -> LocalTransform raise PptxError {
  // Transforms are schema-local. A group owns only grpSpPr/xfrm, while
  // shapes and pictures own only spPr/xfrm; never borrow a descendant's xfrm.
  let properties_name = if element.local_name() == "grpSp" {
    "grpSpPr"
  } else {
    "spPr"
  }
  let transform = match element.first_child(properties_name) {
    Some(properties) => properties.first_child("xfrm")
    None => None
  }
  match transform {
    None => identity_transform()
    Some(transform) => {
      let offset = transform.first_child("off")
      let extent = transform.first_child("ext")
      {
        x: match offset {
          Some(v) => numeric_attribute(v, "x", part, default=0)
          None => 0
        },
        y: match offset {
          Some(v) => numeric_attribute(v, "y", part, default=0)
          None => 0
        },
        width: match extent {
          Some(v) => numeric_attribute(v, "cx", part, default=0)
          None => 0
        },
        height: match extent {
          Some(v) => numeric_attribute(v, "cy", part, default=0)
          None => 0
        },
        scale_x_num: 1,
        scale_x_den: 1,
        scale_y_num: 1,
        scale_y_den: 1,
        group_width: 0,
        group_height: 0,
        rotation: numeric_attribute(transform, "rot", part, default=0),
        flip_h: bool_attribute(transform, "flipH"),
        flip_v: bool_attribute(transform, "flipV"),
      }
    }
  }
}

///|
fn transformed_bounds(
  item : LocalTransform,
  parent : LocalTransform,
) -> @scene.Rect {
  let x = parent.x + item.x
  let y = parent.y + item.y
  let quarter_turn = item.rotation / 5400000 % 2 != 0
  if quarter_turn {
    {
      x: x + (item.width - item.height) / 2,
      y: y + (item.height - item.width) / 2,
      width: item.height,
      height: item.width,
    }
  } else {
    { x, y, width: item.width, height: item.height }
  }
}

///|
fn group_child_transform(
  group : @xml.Element,
  parent : LocalTransform,
  part : String,
) -> LocalTransform raise PptxError {
  let group_xfrm = item_transform(group, part)
  let transform = match group.first_child("grpSpPr") {
    Some(properties) =>
      match properties.first_child("xfrm") {
        Some(v) => v
        None => return parent
      }
    None => return parent
  }
  let child_offset = transform.first_child("chOff")
  let child_extent = transform.first_child("chExt")
  let ch_x = match child_offset {
    Some(v) => numeric_attribute(v, "x", part, default=0)
    None => 0
  }
  let ch_y = match child_offset {
    Some(v) => numeric_attribute(v, "y", part, default=0)
    None => 0
  }
  let ch_width = match child_extent {
    Some(v) => numeric_attribute(v, "cx", part, default=group_xfrm.width)
    None => group_xfrm.width
  }
  let ch_height = match child_extent {
    Some(v) => numeric_attribute(v, "cy", part, default=group_xfrm.height)
    None => group_xfrm.height
  }
  if ch_width == 0 || ch_height == 0 {
    raise InvalidSlide(part~, message="group child extent must be non-zero")
  }
  // ECMA-376 affine group mapping (the 120-vs-230 regression):
  // mapped = group offset + (coordinate - child-space origin) * group extent /
  // child-space extent. Keep each scale as a rational through nested groups so
  // fractional factors compose before the final bounds conversion; flips are
  // subsequently reflected about this mapped group rectangle.
  let mapped_group_x = parent.x +
    group_xfrm.x * parent.scale_x_num / parent.scale_x_den
  let mapped_group_y = parent.y +
    group_xfrm.y * parent.scale_y_num / parent.scale_y_den
  {
    x: mapped_group_x -
    ch_x *
    parent.scale_x_num *
    group_xfrm.width /
    (parent.scale_x_den * ch_width),
    y: mapped_group_y -
    ch_y *
    parent.scale_y_num *
    group_xfrm.height /
    (parent.scale_y_den * ch_height),
    width: 1,
    height: 1,
    scale_x_num: parent.scale_x_num * group_xfrm.width,
    scale_x_den: parent.scale_x_den * ch_width,
    scale_y_num: parent.scale_y_num * group_xfrm.height,
    scale_y_den: parent.scale_y_den * ch_height,
    group_width: group_xfrm.width * parent.scale_x_num / parent.scale_x_den,
    group_height: group_xfrm.height * parent.scale_y_num / parent.scale_y_den,
    rotation: parent.rotation + group_xfrm.rotation,
    flip_h: parent.flip_h != group_xfrm.flip_h,
    flip_v: parent.flip_v != group_xfrm.flip_v,
  }
}

///|
fn element_bounds(
  element : @xml.Element,
  parent : LocalTransform,
  part : String,
) -> @scene.Rect raise PptxError {
  let item = item_transform(element, part)
  let scaled = {
    x: item.x * parent.scale_x_num / parent.scale_x_den,
    y: item.y * parent.scale_y_num / parent.scale_y_den,
    width: item.width * parent.scale_x_num / parent.scale_x_den,
    height: item.height * parent.scale_y_num / parent.scale_y_den,
    scale_x_num: 1,
    scale_x_den: 1,
    scale_y_num: 1,
    scale_y_den: 1,
    group_width: parent.group_width,
    group_height: parent.group_height,
    rotation: item.rotation + parent.rotation,
    // Item-local flips change content orientation only; parent group flips
    // control reflection of the child's outer AABB in mapped group space.
    flip_h: item.flip_h,
    flip_v: item.flip_v,
  }
  let bounds = transformed_bounds(scaled, parent)
  // A group flip reflects within its mapped extents, not around its offset.
  let x = if parent.flip_h {
    parent.x * 2 + parent.group_width - bounds.x - bounds.width
  } else {
    bounds.x
  }
  let y = if parent.flip_v {
    parent.y * 2 + parent.group_height - bounds.y - bounds.height
  } else {
    bounds.y
  }
  { x, y, width: bounds.width, height: bounds.height }
}

///|
fn is_text_box(shape : @xml.Element) -> Bool {
  match first_descendant(shape, "cNvSpPr") {
    Some(p) => bool_attribute(p, "txBox")
    None => false
  }
}

///|
fn shape_kind(shape : @xml.Element) -> String {
  match first_descendant(shape, "prstGeom") {
    Some(g) =>
      match g.attribute("prst") {
        Some(k) => k
        None => "shape"
      }
    None => "shape"
  }
}

///|
fn parse_shape(
  shape : @xml.Element,
  parent : LocalTransform,
  part : String,
) -> @scene.SlideElement raise PptxError {
  let bounds = element_bounds(shape, parent, part)
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
fn image_content_type(container : @opc.Package, part_name : String) -> String? {
  let text = container.text("[Content_Types].xml") catch { _ => return None }
  let root = @xml.parse(text) catch { _ => return None }
  let absolute_name = "/" + part_name
  for entry in root.children_named("Override") {
    if entry.attribute("PartName") == Some(absolute_name) {
      return entry.attribute("ContentType")
    }
  }
  let extension = match part_name.rev_find(".") {
    Some(index) =>
      part_name.unsafe_substring(start=index + 1, end=part_name.length())
    None => return None
  }
  for entry in root.children_named("Default") {
    if entry.attribute("Extension") == Some(extension) {
      return entry.attribute("ContentType")
    }
  }
  None
}

///|
fn has_image_signature(
  content : FixedArray[Byte],
  content_type : String,
) -> Bool {
  if content_type == "image/png" {
    content.length() >= 8 &&
    content[0] == 0x89 &&
    content[1] == 0x50 &&
    content[2] == 0x4e &&
    content[3] == 0x47 &&
    content[4] == 0x0d &&
    content[5] == 0x0a &&
    content[6] == 0x1a &&
    content[7] == 0x0a
  } else if content_type == "image/jpeg" {
    content.length() >= 3 &&
    content[0] == 0xff &&
    content[1] == 0xd8 &&
    content[2] == 0xff
  } else if content_type == "image/gif" {
    content.length() >= 6 &&
    content[0] == 0x47 &&
    content[1] == 0x49 &&
    content[2] == 0x46 &&
    content[3] == 0x38 &&
    (content[4] == 0x37 || content[4] == 0x39) &&
    content[5] == 0x61
  } else {
    false
  }
}

///|
fn image_relationship_part(
  container : @opc.Package,
  slide_part : String,
  relationships : Array[@opc.Relationship],
  id : String,
) -> String? {
  for relationship in relationships {
    if relationship.id == id &&
      !relationship.external &&
      (
        relationship.relationship_type ==
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" ||
        relationship.relationship_type ==
        "http://purl.oclc.org/ooxml/officeDocument/relationships/image"
      ) {
      let resolved = @opc.resolve_target(slide_part, relationship.target) catch {
        _ => return None
      }
      match
        (container.part(resolved), image_content_type(container, resolved)) {
        (Some(part), Some(content_type)) if content_type.has_prefix("image/") &&
          has_image_signature(part.content, content_type) =>
          return Some(resolved)
        _ => ()
      }
      return None
    }
  }
  None
}

///|
fn append_slide_elements(
  container : @opc.Package,
  shape_tree : @xml.Element,
  parent : LocalTransform,
  part : String,
  relationships : Array[@opc.Relationship],
  elements : Array[@scene.SlideElement],
  warnings : Array[@scene.Warning],
) -> Unit raise PptxError {
  for element in shape_tree.child_elements() {
    match element.local_name() {
      "sp" => elements.push(parse_shape(element, parent, part))
      "pic" => {
        let id = match first_descendant(element, "blip") {
          Some(blip) =>
            match blip.attribute("embed") {
              Some(v) => v
              None =>
                match blip.attribute("link") {
                  Some(v) => v
                  None => ""
                }
            }
          None => ""
        }
        if image_relationship_part(container, part, relationships, id)
          is Some(_) {
          elements.push(
            Image(
              bounds=element_bounds(element, parent, part),
              relationship_id=id,
            ),
          )
        } else {
          warnings.push({
            code: "pptx.invalid-image-relationship",
            message: "picture relationship \{id} is missing or is not image type",
            part: Some(part),
          })
        }
      }
      "grpSp" =>
        append_slide_elements(
          container,
          element,
          group_child_transform(element, parent, part),
          part,
          relationships,
          elements,
          warnings,
        )
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
  warnings : Array[@scene.Warning],
) -> @scene.Slide raise PptxError {
  let root = parse_xml_part(container, part, presentation=false)
  if root.local_name() != "sld" {
    raise InvalidSlide(part~, message="expected p:sld root")
  }
  let common = match first_descendant(root, "cSld") {
    Some(v) => v
    None => raise InvalidSlide(part~, message="missing common slide data")
  }
  let tree = match first_descendant(common, "spTree") {
    Some(v) => v
    None => raise InvalidSlide(part~, message="missing shape tree")
  }
  let relationships = container.relationships(part) catch { _ => [] }
  let elements = []
  append_slide_elements(
    container,
    tree,
    identity_transform(),
    part,
    relationships,
    elements,
    warnings,
  )
  let name = match common.attribute("name") {
    Some(v) if v != "" => v
    _ => part_stem(part)
  }
  { name, width, height, elements }
}
