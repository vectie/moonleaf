///|
fn pptx_json_field(value : Json, key : String) -> Json {
  match value {
    Object(map) => map.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn pptx_json_int(value : Json, key : String) -> Int32? {
  match pptx_json_field(value, key) {
    Number(n, ..) if !n.is_nan() && n >= 0.0 && n < 2147483647.0 =>
      Some(n.to_int())
    _ => None
  }
}

///|
fn pptx_json_string(value : Json, key : String) -> String? {
  match pptx_json_field(value, key) {
    String(s) => Some(s)
    _ => None
  }
}

///|
fn pptx_rfind(source : String, needle : String) -> Int32? {
  let mut i = source.length() - needle.length()
  while i >= 0 {
    if source[i:i + needle.length()].to_owned() == needle {
      return Some(i)
    }
    i -= 1
  }
  None
}

///|
fn pptx_splice(
  source : String,
  start : Int32,
  end : Int32,
  replacement : String,
) -> String {
  source[:start].to_owned() + replacement + source[end:].to_owned()
}

///|
fn pptx_rels_path(part : String) -> String {
  match pptx_rfind(part, "/") {
    Some(slash) =>
      part[:slash + 1].to_owned() +
      "_rels/" +
      part[slash + 1:].to_owned() +
      ".rels"
    None => "_rels/" + part + ".rels"
  }
}

///|
fn pptx_next_slide_number(container : @opc.Package) -> Int32 {
  let mut num = 1
  while container.has_part("ppt/slides/slide" + num.to_string() + ".xml") {
    num += 1
  }
  num
}

///|
fn pptx_next_notes_number(container : @opc.Package) -> Int32 {
  let mut num = 1
  while container.has_part(
          "ppt/notesSlides/notesSlide" + num.to_string() + ".xml",
        ) {
    num += 1
  }
  num
}

///|
fn pptx_next_rid(rels_xml : String) -> String {
  let mut num = 1
  while rels_xml.contains("\"rId" + num.to_string() + "\"") {
    num += 1
  }
  "rId" + num.to_string()
}

///|
fn pptx_ensure_content_type(
  container : @opc.Package,
  part_name : String,
  content_type : String,
) -> @opc.Package raise PptxError {
  if !container.has_part("[Content_Types].xml") {
    return container
  }
  let types = container.text("[Content_Types].xml") catch {
    _ => raise InvalidPackagePart(part="[Content_Types].xml")
  }
  let full = if part_name.has_prefix("/") { part_name } else { "/" + part_name }
  if types.contains("PartName=\"" + full + "\"") {
    return container
  }
  guard pptx_rfind(types, "</Types>") is Some(at) else {
    raise InvalidPackagePart(part="[Content_Types].xml")
  }
  let entry = "<Override PartName=\"" +
    full +
    "\" ContentType=\"" +
    content_type +
    "\"/>"
  container.replace_text(
    "[Content_Types].xml",
    pptx_splice(types, at, at, entry),
  )
}

///|
fn pptx_shape_name(shape : @xml.Element) -> String {
  match shape.first_child("nvSpPr") {
    Some(nv) =>
      match nv.first_child("cNvPr") {
        Some(cnv) => cnv.attribute("name").unwrap_or("")
        None => ""
      }
    None => ""
  }
}

///|
fn pptx_shape_text(shape : @xml.Element) -> String {
  match shape.first_child("txBody") {
    Some(body) => outline_paragraphs(body).join("\n")
    None => ""
  }
}

///|
fn pptx_slide_shapes(
  slide_xml : String,
  part : String,
) -> Array[@xml.Element] raise PptxError {
  let root = @xml.parse(slide_xml) catch {
    error => raise InvalidSlide(part~, message=error.to_string())
  }
  let shapes : Array[@xml.Element] = []
  guard root.first_child("cSld") is Some(csld) else { return shapes }
  guard csld.first_child("spTree") is Some(tree) else { return shapes }
  for child in tree.child_elements() {
    if child.local_name() == "sp" {
      shapes.push(child)
    }
  }
  shapes
}

///|
fn pptx_collect_slide_parts(
  container : @opc.Package,
) -> Array[String] raise PptxError {
  let root = parse_xml_part(container, presentation_part, presentation=true)
  let rels = presentation_relationships(container)
  ordered_slide_parts(root, rels)
}

///|
/// Return a compact structural summary of a PPTX template or deck for AI
/// agents and MoonDesk UI.
pub fn template_summary(container : @opc.Package) -> Json raise PptxError {
  let outline = read_outline(container)
  let slide_parts = pptx_collect_slide_parts(container)
  let slides_json : Array[Json] = []
  for idx, part in slide_parts {
    let xml = container.text(part) catch {
      _ => raise InvalidPackagePart(part~)
    }
    let shapes = pptx_slide_shapes(xml, part)
    let shapes_json : Array[Json] = []
    for s_idx, sp in shapes {
      let (id, placeholder) = outline_shape_info(sp)
      shapes_json.push({
        "index": Json::number(s_idx.to_double()),
        "id": id,
        "name": pptx_shape_name(sp),
        "placeholder": placeholder,
        "text": pptx_shape_text(sp),
      })
    }
    let notes_text = if idx < outline.slides.length() {
      outline.slides[idx].notes.map(b => b.paragraphs.join("\n")).join("\n")
    } else {
      ""
    }
    let title = if idx < outline.slides.length() {
      outline.slides[idx].title
    } else {
      ""
    }
    slides_json.push({
      "index": Json::number(idx.to_double()),
      "part": part,
      "title": title,
      "shapes": Json::array(shapes_json),
      "notes": notes_text,
    })
  }
  {
    "slide_count": Json::number(slide_parts.length().to_double()),
    "slides": Json::array(slides_json),
  }
}

///|
fn pptx_parse_int_or(text : String, fallback : Int32) -> Int32 {
  if text.is_empty() {
    return fallback
  }
  let mut acc = 0
  for ch in text {
    let code = ch.to_int()
    if code < 48 || code > 57 {
      return fallback
    }
    acc = acc * 10 + (code - 48)
  }
  acc
}

///|
fn pptx_max_slide_id(pres_root : @xml.Element) -> Int32 {
  let mut max_id = 255
  match first_descendant(pres_root, "sldIdLst") {
    Some(list) =>
      for child in list.child_elements() {
        if child.local_name() == "sldId" {
          match child.attribute("id") {
            Some(v) => {
              let parsed = pptx_parse_int_or(v, 0)
              if parsed > max_id {
                max_id = parsed
              }
            }
            None => ()
          }
        }
      }
    None => ()
  }
  max_id
}

///|
fn pptx_strip_notes_rel(rels_xml : String) -> String {
  let root = @xml.parse(rels_xml) catch { _ => return rels_xml }
  let kept : Array[@xml.Node] = []
  for child in root.children {
    match child {
      Element(el) if el.local_name() == "Relationship" => {
        let typ = el.attribute("Type").unwrap_or("")
        if typ.has_suffix("/notesSlide") {
          continue
        }
        kept.push(child)
      }
      _ => kept.push(child)
    }
  }
  let updated : @xml.Element = {
    name: root.name,
    attributes: root.attributes,
    children: kept,
  }
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
  @xml.serialize(updated)
}

///|
fn pptx_clone_slide(
  container : @opc.Package,
  op : Json,
) -> (@opc.Package, Int32, String) raise PptxError {
  let slide_parts = pptx_collect_slide_parts(container)
  let src_index = pptx_json_int(op, "template_slide").unwrap_or(0)
  if src_index < 0 || src_index >= slide_parts.length() {
    raise InvalidPresentation(message="template_slide out of range")
  }
  let src_part = slide_parts[src_index]
  let src_xml = container.text(src_part) catch {
    _ => raise InvalidPackagePart(part=src_part)
  }
  let new_num = pptx_next_slide_number(container)
  let new_part = "ppt/slides/slide" + new_num.to_string() + ".xml"
  let mut next = container.replace_text(new_part, src_xml)
  let src_rels = pptx_rels_path(src_part)
  if next.has_part(src_rels) {
    let rels_xml = next.text(src_rels) catch {
      _ => raise InvalidPackagePart(part=src_rels)
    }
    next = next.replace_text(
      pptx_rels_path(new_part),
      pptx_strip_notes_rel(rels_xml),
    )
  }
  next = pptx_ensure_content_type(
    next, new_part, "application/vnd.openxmlformats-officedocument.presentationml.slide+xml",
  )
  let pres_rels_path = pptx_rels_path(presentation_part)
  let pres_rels_xml = next.text(pres_rels_path) catch {
    _ => raise InvalidPackagePart(part=pres_rels_path)
  }
  let rid = pptx_next_rid(pres_rels_xml)
  guard pptx_rfind(pres_rels_xml, "</Relationships>") is Some(rel_at) else {
    raise InvalidPackagePart(part=pres_rels_path)
  }
  let rel_entry = "<Relationship Id=\"" +
    rid +
    "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide" +
    new_num.to_string() +
    ".xml\"/>"
  next = next.replace_text(
    pres_rels_path,
    pptx_splice(pres_rels_xml, rel_at, rel_at, rel_entry),
  )
  let pres_xml = next.text(presentation_part) catch {
    _ => raise InvalidPackagePart(part=presentation_part)
  }
  let pres_root = @xml.parse(pres_xml) catch {
    _ => raise InvalidPackagePart(part=presentation_part)
  }
  let new_id = pptx_max_slide_id(pres_root) + 1
  let insert_at = pptx_json_int(op, "insert_at").unwrap_or(slide_parts.length())
  let new_sld_id = @xml.Element::{
    name: "p:sldId",
    attributes: [
      { name: "id", value: new_id.to_string(), },
      { name: "r:id", value: rid, },
    ],
    children: [],
  }
  let updated_pres = pptx_update_sld_id_lst(pres_root, list => {
    let items : Array[@xml.Node] = []
    let mut sld_idx = 0
    let mut inserted = false
    for child in list.children {
      if child is Element(el) && el.local_name() == "sldId" {
        if sld_idx == insert_at && !inserted {
          items.push(Element(new_sld_id))
          inserted = true
        }
        sld_idx += 1
      }
      items.push(child)
    }
    if !inserted {
      items.push(Element(new_sld_id))
    }
    items
  })
  next = next.replace_text(
    presentation_part,
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
    @xml.serialize(updated_pres),
  )
  let final_idx = if insert_at < 0 {
    0
  } else if insert_at > slide_parts.length() {
    slide_parts.length()
  } else {
    insert_at
  }
  (next, final_idx, "cloned slide " + src_index.to_string())
}

///|
fn pptx_update_sld_id_lst(
  element : @xml.Element,
  transform : (@xml.Element) -> Array[@xml.Node] raise PptxError,
) -> @xml.Element raise PptxError {
  if element.local_name() == "sldIdLst" {
    return {
      name: element.name,
      attributes: element.attributes,
      children: transform(element),
    }
  }
  let next_children : Array[@xml.Node] = []
  for child in element.children {
    match child {
      Element(el) =>
        next_children.push(Element(pptx_update_sld_id_lst(el, transform)))
      _ => next_children.push(child)
    }
  }
  {
    name: element.name,
    attributes: element.attributes,
    children: next_children,
  }
}

///|
fn pptx_delete_slide(
  container : @opc.Package,
  op : Json,
) -> (@opc.Package, Int32, String) raise PptxError {
  let slide_parts = pptx_collect_slide_parts(container)
  guard pptx_json_int(op, "slide") is Some(target) &&
    target >= 0 &&
    target < slide_parts.length() else {
    raise InvalidPresentation(message="slide index out of range")
  }
  if slide_parts.length() <= 1 {
    raise InvalidPresentation(message="cannot delete the only remaining slide")
  }
  let pres_xml = container.text(presentation_part) catch {
    _ => raise InvalidPackagePart(part=presentation_part)
  }
  let pres_root = @xml.parse(pres_xml) catch {
    _ => raise InvalidPackagePart(part=presentation_part)
  }
  let updated_pres = pptx_update_sld_id_lst(pres_root, list => {
    let items : Array[@xml.Node] = []
    let mut idx = 0
    for child in list.children {
      if child is Element(el) && el.local_name() == "sldId" {
        if idx == target {
          idx += 1
          continue
        }
        idx += 1
      }
      items.push(child)
    }
    items
  })
  (
    container.replace_text(
      presentation_part,
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
      @xml.serialize(updated_pres),
    ),
    target,
    "deleted slide " + target.to_string(),
  )
}

///|
fn pptx_reorder_slides(
  container : @opc.Package,
  op : Json,
) -> (@opc.Package, Int32, String) raise PptxError {
  let slide_parts = pptx_collect_slide_parts(container)
  guard pptx_json_field(op, "order") is Array(order_json) else {
    raise InvalidPresentation(message="reorder_slides requires order array")
  }
  if order_json.length() != slide_parts.length() {
    raise InvalidPresentation(message="order length must match slide count")
  }
  let order : Array[Int32] = []
  let seen : Map[Int32, Bool] = Map([])
  for item in order_json {
    guard item is Number(n, ..) && !n.is_nan() && n >= 0.0 else {
      raise InvalidPresentation(message="order entries must be slide indices")
    }
    let idx = n.to_int()
    if idx < 0 || idx >= slide_parts.length() || seen.contains(idx) {
      raise InvalidPresentation(
        message="order must be a permutation of slide indices",
      )
    }
    seen[idx] = true
    order.push(idx)
  }
  let pres_xml = container.text(presentation_part) catch {
    _ => raise InvalidPackagePart(part=presentation_part)
  }
  let pres_root = @xml.parse(pres_xml) catch {
    _ => raise InvalidPackagePart(part=presentation_part)
  }
  let updated_pres = pptx_update_sld_id_lst(pres_root, list => {
    let existing : Array[@xml.Node] = []
    for child in list.children {
      if child is Element(el) && el.local_name() == "sldId" {
        existing.push(child)
      }
    }
    order.map(idx => existing[idx])
  })
  (
    container.replace_text(
      presentation_part,
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
      @xml.serialize(updated_pres),
    ),
    0,
    "reordered slides",
  )
}

///|
fn pptx_template_ppr_rpr(
  tx_body : @xml.Element,
) -> (@xml.Element?, @xml.Element?) {
  for child in tx_body.child_elements() {
    if child.local_name() == "p" {
      let ppr = child.first_child("pPr")
      let mut rpr : @xml.Element? = None
      match child.first_child("r") {
        Some(run) => rpr = run.first_child("rPr")
        None =>
          match child.first_child("endParaRPr") {
            Some(ep) =>
              rpr = Some({
                name: "a:rPr",
                attributes: ep.attributes,
                children: ep.children,
              })
            None => ()
          }
      }
      return (ppr, rpr)
    }
  }
  (None, None)
}

///|
fn pptx_build_tx_body(
  existing : @xml.Element,
  paragraphs : Array[String],
) -> @xml.Element {
  let (tpl_ppr, tpl_rpr) = pptx_template_ppr_rpr(existing)
  let children : Array[@xml.Node] = []
  match existing.first_child("bodyPr") {
    Some(bp) => children.push(Element(bp))
    None =>
      children.push(
        Element({ name: "a:bodyPr", attributes: [], children: [], }),
      )
  }
  match existing.first_child("lstStyle") {
    Some(ls) => children.push(Element(ls))
    None =>
      children.push(
        Element({ name: "a:lstStyle", attributes: [], children: [], }),
      )
  }
  let lines = if paragraphs.is_empty() { [""] } else { paragraphs }
  for line in lines {
    let p_children : Array[@xml.Node] = []
    if tpl_ppr is Some(ppr) {
      p_children.push(Element(ppr))
    }
    let r_children : Array[@xml.Node] = []
    if tpl_rpr is Some(rpr) {
      r_children.push(Element(rpr))
    }
    r_children.push(
      Element({ name: "a:t", attributes: [], children: [Text(line)], }),
    )
    p_children.push(
      Element({ name: "a:r", attributes: [], children: r_children, }),
    )
    children.push(
      Element({ name: "a:p", attributes: [], children: p_children, }),
    )
  }
  { name: existing.name, attributes: existing.attributes, children, }
}

///|
fn pptx_match_shape(shape : @xml.Element, idx : Int32, op : Json) -> Bool {
  if pptx_json_int(op, "shape_index") is Some(wanted) {
    return idx == wanted
  }
  let (id, placeholder) = outline_shape_info(shape)
  if pptx_json_string(op, "shape_id") is Some(wanted_id) &&
    !wanted_id.is_empty() {
    return id == wanted_id
  }
  if pptx_json_string(op, "shape_name") is Some(wanted_name) &&
    !wanted_name.is_empty() {
    return pptx_shape_name(shape) == wanted_name
  }
  if pptx_json_string(op, "placeholder") is Some(wanted_ph) &&
    !wanted_ph.is_empty() {
    return placeholder == wanted_ph
  }
  false
}

///|
fn pptx_replace_sp_in_tree(
  element : @xml.Element,
  op : Json,
  paragraphs : Array[String],
  sp_counter : Ref[Int32],
  matched : Ref[Bool],
) -> @xml.Element {
  if element.local_name() == "sp" {
    let idx = sp_counter.val
    sp_counter.val += 1
    if !matched.val && pptx_match_shape(element, idx, op) {
      matched.val = true
      let next_children : Array[@xml.Node] = []
      let mut replaced_body = false
      for child in element.children {
        match child {
          Element(el) if el.local_name() == "txBody" => {
            next_children.push(Element(pptx_build_tx_body(el, paragraphs)))
            replaced_body = true
          }
          _ => next_children.push(child)
        }
      }
      if !replaced_body {
        next_children.push(
          Element(
            pptx_build_tx_body(
              { name: "p:txBody", attributes: [], children: [], },
              paragraphs,
            ),
          ),
        )
      }
      return {
        name: element.name,
        attributes: element.attributes,
        children: next_children,
      }
    }
    return element
  }
  let next_children : Array[@xml.Node] = []
  for child in element.children {
    match child {
      Element(el) =>
        next_children.push(
          Element(
            pptx_replace_sp_in_tree(el, op, paragraphs, sp_counter, matched),
          ),
        )
      _ => next_children.push(child)
    }
  }
  {
    name: element.name,
    attributes: element.attributes,
    children: next_children,
  }
}

///|
fn pptx_replace_shape_text(
  container : @opc.Package,
  op : Json,
) -> (@opc.Package, Int32, String) raise PptxError {
  let slide_parts = pptx_collect_slide_parts(container)
  guard pptx_json_int(op, "slide") is Some(slide_idx) &&
    slide_idx >= 0 &&
    slide_idx < slide_parts.length() else {
    raise InvalidPresentation(message="slide index out of range")
  }
  let paragraphs : Array[String] = match pptx_json_field(op, "paragraphs") {
    Array(items) => {
      let out : Array[String] = []
      for item in items {
        guard item is String(s) else {
          raise InvalidPresentation(
            message="paragraphs entries must be strings",
          )
        }
        ignore(created_pptx_text(s))
        out.push(s)
      }
      out
    }
    _ =>
      match pptx_json_string(op, "text") {
        Some(s) => {
          ignore(created_pptx_text(s))
          s.split("\n").map(v => v.to_owned()).collect()
        }
        None =>
          raise InvalidPresentation(
            message="replace_shape_text requires paragraphs or text",
          )
      }
  }
  let part = slide_parts[slide_idx]
  let xml = container.text(part) catch { _ => raise InvalidPackagePart(part~) }
  let root = @xml.parse(xml) catch {
    error => raise InvalidSlide(part~, message=error.to_string())
  }
  let counter : Ref[Int32] = { val: 0, }
  let matched : Ref[Bool] = { val: false, }
  let updated = pptx_replace_sp_in_tree(root, op, paragraphs, counter, matched)
  if !matched.val {
    raise InvalidPresentation(
      message="target shape not found on slide " + slide_idx.to_string(),
    )
  }
  (
    container.replace_text(
      part,
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
      @xml.serialize(updated),
    ),
    slide_idx,
    "updated shape text on slide " + slide_idx.to_string(),
  )
}

///|
fn pptx_notes_xml(text : String) -> String {
  let paragraphs = text
    .split("\n")
    .map(line => {
      "<a:p><a:r><a:t>" +
      @xml.escape_text(line.to_owned()) +
      "</a:t></a:r></a:p>"
    })
    .join("")
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
  "<p:notes xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">" +
  "<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>" +
  "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Notes Placeholder\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/>" +
  "<p:txBody><a:bodyPr/><a:lstStyle/>" +
  paragraphs +
  "</p:txBody></p:sp></p:spTree></p:cSld></p:notes>"
}

///|
fn pptx_set_notes(
  container : @opc.Package,
  op : Json,
) -> (@opc.Package, Int32, String) raise PptxError {
  let slide_parts = pptx_collect_slide_parts(container)
  guard pptx_json_int(op, "slide") is Some(slide_idx) &&
    slide_idx >= 0 &&
    slide_idx < slide_parts.length() else {
    raise InvalidPresentation(message="slide index out of range")
  }
  guard pptx_json_string(op, "text") is Some(text) else {
    raise InvalidPresentation(message="set_notes requires text")
  }
  ignore(created_pptx_text(text))
  let slide_part = slide_parts[slide_idx]
  let slide_rels_path = pptx_rels_path(slide_part)
  let mut existing_notes : String? = None
  if container.has_part(slide_rels_path) {
    let rels = container.relationships(slide_part) catch { _ => [] }
    for rel in rels {
      if rel.relationship_type.has_suffix("/notesSlide") {
        existing_notes = Some(rel.target)
        break
      }
    }
  }
  match existing_notes {
    Some(notes_part) if container.has_part(notes_part) => {
      let notes_xml = container.text(notes_part) catch {
        _ => raise InvalidPackagePart(part=notes_part)
      }
      let root = @xml.parse(notes_xml) catch {
        error => raise InvalidSlide(part=notes_part, message=error.to_string())
      }
      let counter : Ref[Int32] = { val: 0, }
      let matched : Ref[Bool] = { val: false, }
      let paragraphs = text.split("\n").map(v => v.to_owned()).collect()
      let updated = pptx_replace_sp_in_tree(
        root,
        { "placeholder": "body" },
        paragraphs,
        counter,
        matched,
      )
      if matched.val {
        return (
          container.replace_text(
            notes_part,
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            @xml.serialize(updated),
          ),
          slide_idx,
          "updated notes on slide " + slide_idx.to_string(),
        )
      }
      (
        container.replace_text(notes_part, pptx_notes_xml(text)),
        slide_idx,
        "updated notes on slide " + slide_idx.to_string(),
      )
    }
    _ => {
      let num = pptx_next_notes_number(container)
      let notes_part = "ppt/notesSlides/notesSlide" + num.to_string() + ".xml"
      let mut next = container.replace_text(notes_part, pptx_notes_xml(text))
      next = pptx_ensure_content_type(
        next, notes_part, "application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml",
      )
      let slide_file = match pptx_rfind(slide_part, "/") {
        Some(slash) => slide_part[slash + 1:].to_owned()
        None => slide_part
      }
      let notes_rels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"../slides/" +
        slide_file +
        "\"/></Relationships>"
      next = next.replace_text(pptx_rels_path(notes_part), notes_rels)
      let rels_xml = if next.has_part(slide_rels_path) {
        next.text(slide_rels_path) catch {
          _ => raise InvalidPackagePart(part=slide_rels_path)
        }
      } else {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"></Relationships>"
      }
      let rid = pptx_next_rid(rels_xml)
      guard pptx_rfind(rels_xml, "</Relationships>") is Some(at) else {
        raise InvalidPackagePart(part=slide_rels_path)
      }
      let rel_entry = "<Relationship Id=\"" +
        rid +
        "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide\" Target=\"../notesSlides/notesSlide" +
        num.to_string() +
        ".xml\"/>"
      next = next.replace_text(
        slide_rels_path,
        pptx_splice(rels_xml, at, at, rel_entry),
      )
      (next, slide_idx, "added notes on slide " + slide_idx.to_string())
    }
  }
}

///|
/// Apply a bounded, atomic list of PresentationML edit operations (`clone_slide`,
/// `delete_slide`, `reorder_slides`, `replace_shape_text`, `set_notes`).
pub fn apply_edit_ops(
  container : @opc.Package,
  request : Json,
) -> (@opc.Package, Json) raise PptxError {
  guard pptx_json_field(request, "ops") is Array(ops) else {
    raise InvalidPresentation(message="ops must be an array")
  }
  if ops.is_empty() || ops.length() > 64 {
    raise InvalidPresentation(
      message="ops must contain between 1 and 64 operations",
    )
  }
  let mut current = container
  let results : Array[Json] = []
  for index, op in ops {
    let name = pptx_json_string(op, "op").unwrap_or("")
    let (next, slide_index, message) = match name {
      "clone_slide" => pptx_clone_slide(current, op)
      "delete_slide" => pptx_delete_slide(current, op)
      "reorder_slides" => pptx_reorder_slides(current, op)
      "replace_shape_text" => pptx_replace_shape_text(current, op)
      "set_notes" => pptx_set_notes(current, op)
      _ =>
        raise InvalidPresentation(
          message="op " +
            (index + 1).to_string() +
            ": unknown pptx operation '" +
            name +
            "'",
        )
    }
    current = next
    results.push({
      "op": name,
      "ok": true,
      "slide": Json::number(slide_index.to_double()),
      "message": message,
    })
  }
  (
    current,
    {
      "applied": Json::number(results.length().to_double()),
      "results": Json::array(results),
    },
  )
}
