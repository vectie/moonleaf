///|
let edit_ops_main_namespace : String = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

///|
priv struct BodyPara {
  ordinal : Int32
  child_index : Int32
  element : @xml.Element
  text : String
  level : Int32
}

///|
priv struct DocCtx {
  source : String
  root : @xml.Element
  body_index : Int32
  body : @xml.Element
  styles : Map[String, Int32]
}

///|
priv enum RangeMode {
  RangeFormat
  RangeReplace
  RangeComment(Int32)
}

///|
fn edit_heading_from_name(name : String) -> Int32 {
  let compact = name.replace_all(old=" ", new="").to_lower()
  if compact.length() == 8 && compact.has_prefix("heading") {
    let c = compact[7].to_int()
    if c >= 49 && c <= 57 {
      return c - 48
    }
  }
  0
}

///|
fn edit_heading_styles(container : @opc.Package) -> Map[String, Int32] {
  let result : Map[String, Int32] = Map([])
  if !container.has_part("word/styles.xml") {
    return result
  }
  let text = container.text("word/styles.xml") catch { _ => return result }
  let root = @xml.parse(text) catch { _ => return result }
  for style in root.child_elements() {
    if style.local_name() != "style" {
      continue
    }
    guard style.attribute("styleId") is Some(id) else { continue }
    let mut level = 0
    if style.first_child("pPr") is Some(properties) {
      match int_attr(properties.first_child("outlineLvl"), "val") {
        Some(value) if value < 9 => level = value + 1
        _ => ()
      }
    }
    if level == 0 {
      level = edit_heading_from_name(id)
    }
    if level == 0 && style.first_child("name") is Some(name) {
      level = edit_heading_from_name(name.attribute("val").unwrap_or(""))
    }
    if level > 0 {
      result[id] = level
    }
  }
  result
}

///|
fn edit_heading_style_id(styles : Map[String, Int32], level : Int32) -> String {
  let mut found : String? = None
  for id, value in styles {
    if value == level && found is None {
      found = Some(id)
    }
  }
  match found {
    Some(id) => id
    None => "Heading" + level.to_string()
  }
}

///|
fn edit_paragraph_level(
  styles : Map[String, Int32],
  paragraph : @xml.Element,
) -> Int32 {
  guard paragraph.first_child("pPr") is Some(properties) else { return 0 }
  match int_attr(properties.first_child("outlineLvl"), "val") {
    Some(value) => return if value < 9 { value + 1 } else { 0 }
    None => ()
  }
  match properties.first_child("pStyle") {
    Some(style) =>
      match style.attribute("val") {
        Some(id) =>
          match styles.get(id) {
            Some(level) => level
            None => edit_heading_from_name(id)
          }
        None => 0
      }
    None => 0
  }
}

///|
fn edit_ctx(container : @opc.Package) -> DocCtx raise DocxError {
  let source = container.text("word/document.xml") catch {
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  let mut body_index = -1
  let mut found : @xml.Element? = None
  for index, child in root.children {
    if child is Element(element) && element.local_name() == "body" {
      body_index = index
      found = Some(element)
      break
    }
  }
  guard found is Some(body) else {
    raise InvalidDocument("document body is missing")
  }
  { source, root, body_index, body, styles: edit_heading_styles(container), }
}

///|
fn edit_paragraphs(ctx : DocCtx) -> Array[BodyPara] {
  let result : Array[BodyPara] = []
  let mut ordinal = 0
  for index, child in ctx.body.children {
    if child is Element(element) && element.local_name() == "p" {
      result.push({
        ordinal,
        child_index: index,
        element,
        text: operation_paragraph_text(element),
        level: edit_paragraph_level(ctx.styles, element),
      })
      ordinal += 1
    }
  }
  result
}

///|
fn edit_child_span(
  ctx : DocCtx,
  child_index : Int32,
) -> (Int32, Int32) raise DocxError {
  operation_span(
    ctx.source,
    target_ordinal(ctx.root, [ctx.body_index, child_index], 0, 1),
  )
}

///|
fn edit_slice(source : String, start : Int32, end : Int32) -> String {
  source.unsafe_substring(start~, end~)
}

///|
fn edit_splice(
  source : String,
  start : Int32,
  end : Int32,
  replacement : String,
) -> String {
  edit_slice(source, 0, start) +
  replacement +
  edit_slice(source, end, source.length())
}

///|
fn edit_normalize(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if c != ' ' &&
      c != '\t' &&
      c != '\n' &&
      c != '\r' &&
      c != '\u{a0}' &&
      c != '\u{3000}' {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn edit_find_all(text : String, needle : String) -> Array[Int32] {
  let found : Array[Int32] = []
  if needle.is_empty() || needle.length() > text.length() {
    return found
  }
  for offset = 0; offset + needle.length() <= text.length(); offset = offset + 1 {
    if has_xml_prefix(text, offset, needle) {
      found.push(offset)
    }
  }
  found
}

///|
fn edit_resolve_target(
  paragraphs : Array[BodyPara],
  target : Json,
) -> BodyPara raise DocxError {
  let wanted_text = match operation_field(target, "text") {
    String(text) => text
    _ => ""
  }
  let wanted = edit_normalize(wanted_text)
  let index : Int32? = match operation_field(target, "paragraph_index") {
    Number(n, ..) if !n.is_nan() && n >= 0.0 && n < 2147483647.0 =>
      Some(n.to_int())
    _ => None
  }
  if index is Some(i) && i < paragraphs.length() {
    if wanted == "" || edit_normalize(paragraphs[i].text) == wanted {
      return paragraphs[i]
    }
  }
  if wanted == "" {
    raise InvalidReplacement("target paragraph was not found")
  }
  let exact = paragraphs.filter(p => edit_normalize(p.text) == wanted)
  if exact.length() == 1 {
    return exact[0]
  }
  if exact.length() > 1 {
    raise InvalidReplacement(
      "target text matches more than one paragraph; provide paragraph_index",
    )
  }
  if wanted.length() >= 6 {
    let prefixed = paragraphs.filter(p => {
      edit_normalize(p.text).has_prefix(wanted)
    })
    if prefixed.length() == 1 {
      return prefixed[0]
    }
  }
  raise InvalidReplacement("target paragraph was not found or is ambiguous")
}

///|
fn edit_target_json(op : Json) -> Json {
  match operation_field(op, "target") {
    Object(_) as target => target
    _ => op
  }
}

///|
fn edit_texts(op : Json) -> Array[String] raise DocxError {
  let texts : Array[String] = []
  match operation_field(op, "paragraphs") {
    Array(items) =>
      for item in items {
        guard item is String(text) else {
          raise InvalidReplacement("paragraphs must be an array of strings")
        }
        texts.push(text)
      }
    _ =>
      match operation_field(op, "text") {
        String(text) => texts.push(text)
        _ => raise InvalidReplacement("operation requires text or paragraphs")
      }
  }
  if texts.length() > 200 {
    raise InvalidReplacement("too many paragraphs in one operation")
  }
  for text in texts {
    validate_target_text(text)
  }
  texts
}

///|
fn edit_plain_paragraph(
  prefix : String,
  text : String,
  style : Json,
) -> @xml.Element raise DocxError {
  let run = operation_element(
    prefix + "r",
    [],
    operation_text_nodes(prefix, text),
  )
  let paragraph = operation_element(prefix + "p", [], [Element(run)])
  operation_format_runs(operation_styles(paragraph, style, true), style)
}

///|
fn edit_new_paragraph(
  template : @xml.Element?,
  prefix : String,
  text : String,
  style : Json,
) -> @xml.Element raise DocxError {
  match template {
    Some(paragraph) => operation_inserted(paragraph, text, style)
    None => edit_plain_paragraph(prefix, text, style)
  }
}

///|
fn edit_delegate(
  container : @opc.Package,
  paragraph : BodyPara,
  operation : String,
  text : String?,
  style : Json,
) -> @opc.Package raise DocxError {
  let fields : Map[String, Json] = {
    "operation": Json(operation),
    "paragraph_index": Json::number(paragraph.ordinal.to_double()),
    "expected_text": Json(paragraph.text),
    "style": style,
  }
  if text is Some(value) {
    fields["text"] = Json(value)
  }
  edit_body_paragraph(container, Json::object(fields))
}

///|
fn edit_insert_paragraphs(
  container : @opc.Package,
  ctx : DocCtx,
  anchor : BodyPara,
  after : Bool,
  texts : Array[String],
  style : Json,
) -> @opc.Package raise DocxError {
  let (start, end) = edit_child_span(ctx, anchor.child_index)
  let template = if anchor.level > 0 { None } else { Some(anchor.element) }
  let prefix = operation_prefix(anchor.element)
  let xml = StringBuilder()
  for text in texts {
    xml.write_string(
      @xml.serialize(edit_new_paragraph(template, prefix, text, style)),
    )
  }
  let offset = if after { end } else { start }
  container.replace_text(
    "word/document.xml",
    edit_splice(ctx.source, offset, offset, xml.to_string()),
  )
}

///|
fn edit_range_bounds(
  paragraph : BodyPara,
  op : Json,
  whole_allowed : Bool,
) -> (Int32, Int32) raise DocxError {
  let text = paragraph.text
  let selected = match operation_field(op, "selected_text") {
    String(value) => value
    _ => ""
  }
  let range = operation_field(op, "range")
  let has_range = range is Object(_)
  if has_range {
    let start = operation_index(range, "start")
    let end = operation_index(range, "end")
    if start < end && end <= text.length() {
      if selected == "" || edit_slice(text, start, end) == selected {
        return (start, end)
      }
    }
  }
  if selected != "" {
    let found = edit_find_all(text, selected)
    if found.length() == 1 {
      return (found[0], found[0] + selected.length())
    }
    raise InvalidReplacement(
      "selected text was not found exactly once in the paragraph",
    )
  }
  if !has_range && whole_allowed && !text.is_empty() {
    return (0, text.length())
  }
  raise InvalidReplacement("a valid text range is required")
}

///|
fn edit_run_with_text(part : @xml.Element, text : String) -> @xml.Element {
  let prefix = operation_prefix(part)
  let children : Array[@xml.Node] = []
  if part.first_child("rPr") is Some(properties) {
    children.push(Element(properties))
  }
  for node in operation_text_nodes(prefix, text) {
    children.push(node)
  }
  operation_element(part.name, part.attributes, children)
}

///|
fn edit_comment_marker(prefix : String, name : String, id : Int32) -> @xml.Node {
  Element(
    operation_element(
      prefix + name,
      [{ name: prefix + "id", value: id.to_string(), }],
      [],
    ),
  )
}

///|
fn edit_comment_reference(prefix : String, id : Int32) -> @xml.Node {
  Element(
    operation_element(prefix + "r", [], [
      Element(
        operation_element(
          prefix + "commentReference",
          [{ name: prefix + "id", value: id.to_string(), }],
          [],
        ),
      ),
    ]),
  )
}

///|
fn edit_range_runs(
  paragraph : @xml.Element,
  start : Int32,
  end : Int32,
  mode : RangeMode,
  style : Json,
  replacement : String,
) -> @xml.Element raise DocxError {
  if operation_complex(paragraph) is Some(name) {
    raise InvalidReplacement(
      "selected paragraph contains unsupported " + name + " content",
    )
  }
  let prefix = operation_prefix(paragraph)
  let children : Array[@xml.Node] = []
  let mut position = 0
  let mut replaced = false
  let mut opened = false
  let mut closed = false
  for child in paragraph.children {
    match child {
      Element(part) if part.local_name() == "r" => {
        let text = operation_run_text(part)
        let length = text.length()
        let run_start = position
        let run_end = position + length
        position = run_end
        if length == 0 || run_end <= start || run_start >= end {
          children.push(child)
          continue
        }
        let cover_start = (start - run_start).max(0)
        let cover_end = (end - run_start).min(length)
        let whole = cover_start == 0 && cover_end == length
        let splittable = part
          .child_elements()
          .all(c => c.local_name() == "rPr" || c.local_name() == "t")
        if !whole && !splittable {
          raise InvalidReplacement(
            "selected range cuts through a run containing tabs or line breaks",
          )
        }
        let before = edit_slice(text, 0, cover_start)
        let middle = edit_slice(text, cover_start, cover_end)
        let after = edit_slice(text, cover_end, length)
        if !before.is_empty() {
          children.push(Element(edit_run_with_text(part, before)))
        }
        match mode {
          RangeFormat => {
            let piece = if whole {
              part
            } else {
              edit_run_with_text(part, middle)
            }
            children.push(Element(operation_styles(piece, style, false)))
          }
          RangeReplace =>
            if !replaced {
              children.push(Element(edit_run_with_text(part, replacement)))
              replaced = true
            }
          RangeComment(id) => {
            if !opened {
              children.push(
                edit_comment_marker(prefix, "commentRangeStart", id),
              )
              opened = true
            }
            children.push(
              Element(
                if whole {
                  part
                } else {
                  edit_run_with_text(part, middle)
                },
              ),
            )
            if run_start + cover_end >= end && !closed {
              children.push(edit_comment_marker(prefix, "commentRangeEnd", id))
              children.push(edit_comment_reference(prefix, id))
              closed = true
            }
          }
        }
        if !after.is_empty() {
          children.push(Element(edit_run_with_text(part, after)))
        }
      }
      Element(part) if part.local_name() != "pPr" => {
        let length = operation_paragraph_text(part).length()
        let segment_start = position
        position += length
        if length > 0 && segment_start < end && position > start {
          raise InvalidReplacement(
            "selected range crosses unsupported inline content (" +
            part.local_name() +
            ")",
          )
        }
        children.push(child)
      }
      _ => children.push(child)
    }
  }
  match mode {
    RangeComment(id) =>
      if opened && !closed {
        children.push(edit_comment_marker(prefix, "commentRangeEnd", id))
        children.push(edit_comment_reference(prefix, id))
      }
    _ => ()
  }
  operation_element(paragraph.name, paragraph.attributes, children)
}

///|
fn edit_rfind(source : String, needle : String) -> Int32? {
  let mut i = source.length() - needle.length()
  while i >= 0 {
    if has_xml_prefix(source, i, needle) {
      return Some(i)
    }
    i -= 1
  }
  None
}

///|
fn edit_initials(author : String) -> String {
  let out = StringBuilder()
  let mut count = 0
  for word in author.split(" ") {
    if count >= 3 {
      break
    }
    for c in word {
      out.write_char(c)
      count += 1
      break
    }
  }
  out.to_string().to_upper()
}

///|
fn edit_comment_xml(
  prefix : String,
  id : Int32,
  author : String,
  date : String?,
  text : String,
) -> String {
  let paragraphs = StringBuilder()
  for line in text.replace_all(old="\r\n", new="\n").split("\n") {
    paragraphs.write_string(
      "<" +
      prefix +
      "p><" +
      prefix +
      "r><" +
      prefix +
      "t xml:space=\"preserve\">" +
      @xml.escape_text(line.to_owned()) +
      "</" +
      prefix +
      "t></" +
      prefix +
      "r></" +
      prefix +
      "p>",
    )
  }
  let date_attribute = match date {
    Some(value) =>
      " " + prefix + "date=\"" + @xml.escape_attribute(value) + "\""
    None => ""
  }
  "<" +
  prefix +
  "comment " +
  prefix +
  "id=\"" +
  id.to_string() +
  "\" " +
  prefix +
  "author=\"" +
  @xml.escape_attribute(author) +
  "\" " +
  prefix +
  "initials=\"" +
  @xml.escape_attribute(edit_initials(author)) +
  "\"" +
  date_attribute +
  ">" +
  paragraphs.to_string() +
  "</" +
  prefix +
  "comment>"
}

///|
fn edit_wire_comments_part(
  container : @opc.Package,
) -> @opc.Package raise DocxError {
  let relationship_type = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments"
  let rels_name = "word/_rels/document.xml.rels"
  let mut result = container
  if container.has_part(rels_name) {
    let rels = container.text(rels_name) catch {
      error => raise InvalidDocument(repr(error))
    }
    if !rels.contains("/comments\"") {
      let mut number = 1
      while rels.contains("Id=\"rId" + number.to_string() + "\"") {
        number += 1
      }
      let relationship = "<Relationship Id=\"rId" +
        number.to_string() +
        "\" Type=\"" +
        relationship_type +
        "\" Target=\"comments.xml\"/>"
      guard edit_rfind(rels, "</Relationships>") is Some(at) else {
        raise InvalidDocument("document relationships part is malformed")
      }
      result = result.replace_text(
        rels_name,
        edit_splice(rels, at, at, relationship),
      )
    }
  } else {
    result = result.replace_text(
      rels_name,
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"" +
      relationship_type +
      "\" Target=\"comments.xml\"/></Relationships>",
    )
  }
  if container.has_part("[Content_Types].xml") {
    let types = container.text("[Content_Types].xml") catch {
      error => raise InvalidDocument(repr(error))
    }
    if !types.contains("/word/comments.xml") {
      guard edit_rfind(types, "</Types>") is Some(at) else {
        raise InvalidDocument("content types part is malformed")
      }
      result = result.replace_text(
        "[Content_Types].xml",
        edit_splice(
          types, at, at, "<Override PartName=\"/word/comments.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml\"/>",
        ),
      )
    }
  }
  result
}

///|
fn edit_add_comment(
  container : @opc.Package,
  author : String,
  date : String?,
  text : String,
) -> (@opc.Package, Int32) raise DocxError {
  if text.trim().is_empty() {
    raise InvalidReplacement("comment text must not be empty")
  }
  validate_target_text(text)
  if container.has_part("word/comments.xml") {
    let existing = container.text("word/comments.xml") catch {
      error => raise InvalidDocument(repr(error))
    }
    let root = @xml.parse(existing) catch {
      error => raise InvalidDocument(repr(error))
    }
    let prefix = operation_prefix(root)
    let mut id = 0
    for comment in root.child_elements() {
      if comment.local_name() == "comment" {
        match int_attr(Some(comment), "id") {
          Some(value) => if value >= id { id = value + 1 }
          None => ()
        }
      }
    }
    guard edit_rfind(existing, "</" + prefix + "comments>") is Some(at) else {
      raise InvalidDocument("comments part has no closing tag")
    }
    let xml = edit_comment_xml(prefix, id, author, date, text)
    (
      container.replace_text(
        "word/comments.xml",
        edit_splice(existing, at, at, xml),
      ),
      id,
    )
  } else {
    let xml = edit_comment_xml("w:", 0, author, date, text)
    let part = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:comments xmlns:w=\"" +
      edit_ops_main_namespace +
      "\">" +
      xml +
      "</w:comments>"
    (
      edit_wire_comments_part(container).replace_text("word/comments.xml", part),
      0,
    )
  }
}

///|
fn edit_resolve_section(
  paragraphs : Array[BodyPara],
  section : Json,
) -> BodyPara raise DocxError {
  let wanted = match operation_field(section, "heading") {
    String(text) => edit_normalize(text)
    _ => ""
  }
  match operation_field(section, "heading_index") {
    Number(n, ..) if !n.is_nan() && n >= 0.0 && n < 2147483647.0 => {
      let i = n.to_int()
      if i < paragraphs.length() && paragraphs[i].level > 0 {
        if wanted == "" || edit_normalize(paragraphs[i].text) == wanted {
          return paragraphs[i]
        }
      }
    }
    _ => ()
  }
  if wanted == "" {
    raise InvalidReplacement("section heading was not found")
  }
  let headings = paragraphs.filter(p => p.level > 0)
  let exact = headings.filter(p => edit_normalize(p.text) == wanted)
  if exact.length() == 1 {
    return exact[0]
  }
  if exact.length() == 0 {
    let partial = headings.filter(p => edit_normalize(p.text).contains(wanted))
    if partial.length() == 1 {
      return partial[0]
    }
  }
  raise InvalidReplacement("section heading was not found or is ambiguous")
}

///|
fn edit_section_end(
  ctx : DocCtx,
  paragraphs : Array[BodyPara],
  heading : BodyPara,
  include_subsections : Bool,
) -> Int32 {
  let mut end = ctx.body.children.length()
  for index, child in ctx.body.children {
    if index > heading.child_index &&
      child is Element(element) &&
      element.local_name() == "sectPr" {
      end = index
      break
    }
  }
  for paragraph in paragraphs {
    if paragraph.child_index > heading.child_index &&
      paragraph.child_index < end &&
      paragraph.level > 0 &&
      (!include_subsections || paragraph.level <= heading.level) {
      end = paragraph.child_index
      break
    }
  }
  end
}

///|
/// Element children (child indexes) inside a section body.
fn edit_section_elements(
  ctx : DocCtx,
  heading : BodyPara,
  end : Int32,
) -> Array[Int32] {
  let indexes : Array[Int32] = []
  for index in (heading.child_index + 1)..<end {
    if ctx.body.children[index] is Element(_) {
      indexes.push(index)
    }
  }
  indexes
}

///|
fn edit_section_assert_safe(
  ctx : DocCtx,
  indexes : Array[Int32],
) -> Unit raise DocxError {
  for index in indexes {
    guard ctx.body.children[index] is Element(element) else { continue }
    if element.local_name() != "p" {
      raise InvalidReplacement(
        "section contains a " + element.local_name() + "; edit it manually",
      )
    }
    if operation_complex(element) is Some(name) {
      raise InvalidReplacement(
        "section contains unsupported " + name + " content",
      )
    }
    if element.first_child("pPr") is Some(properties) &&
      properties.first_child("sectPr") is Some(_) {
      raise InvalidReplacement("section contains a section break")
    }
  }
}

///|
fn edit_bool_field(op : Json, key : String, fallback : Bool) -> Bool {
  match operation_field(op, key) {
    True => true
    False => false
    _ => fallback
  }
}

///|
fn edit_section_op(
  container : @opc.Package,
  op : Json,
  name : String,
) -> (@opc.Package, Int32, String) raise DocxError {
  let ctx = edit_ctx(container)
  let paragraphs = edit_paragraphs(ctx)
  let heading = edit_resolve_section(paragraphs, operation_field(op, "section"))
  let include_subsections = edit_bool_field(op, "include_subsections", true)
  let end = edit_section_end(
    ctx,
    paragraphs,
    heading,
    if name == "insert_section_after" {
      true
    } else {
      include_subsections
    },
  )
  let indexes = edit_section_elements(ctx, heading, end)
  let prefix = operation_prefix(heading.element)
  let style = operation_field(op, "style")
  let (heading_start, heading_end) = edit_child_span(ctx, heading.child_index)
  let write = fn(source : String) {
    container.replace_text("word/document.xml", source)
  }
  let body_paragraph_at = fn(position : Int32) -> BodyPara? {
    for paragraph in paragraphs {
      if paragraph.child_index == position && paragraph.level == 0 {
        return Some(paragraph)
      }
    }
    None
  }
  let find_template = fn(from_end : Bool) -> @xml.Element? {
    let ordered = if from_end {
      let reversed : Array[Int32] = []
      for index in indexes {
        reversed.insert(0, index)
      }
      reversed
    } else {
      indexes
    }
    for index in ordered {
      if body_paragraph_at(index) is Some(paragraph) {
        return Some(paragraph.element)
      }
    }
    None
  }
  let build = fn(
    template : @xml.Element?,
    texts : Array[String],
  ) -> String raise DocxError {
    let xml = StringBuilder()
    for text in texts {
      xml.write_string(
        @xml.serialize(edit_new_paragraph(template, prefix, text, style)),
      )
    }
    xml.to_string()
  }
  match name {
    "insert_in_section" => {
      let texts = edit_texts(op)
      let at_start = match operation_field(op, "position") {
        String("start") => true
        _ => false
      }
      let offset = if at_start || indexes.is_empty() {
        heading_end
      } else {
        let (_, last_end) = edit_child_span(ctx, indexes[indexes.length() - 1])
        last_end
      }
      let template = find_template(!at_start)
      (
        write(edit_splice(ctx.source, offset, offset, build(template, texts))),
        heading.ordinal,
        "inserted " + texts.length().to_string() + " paragraph(s)",
      )
    }
    "replace_section" | "delete_section" => {
      edit_section_assert_safe(ctx, indexes)
      if name == "delete_section" &&
        operation_complex(heading.element) is Some(complex) {
        raise InvalidReplacement(
          "section heading contains unsupported " + complex + " content",
        )
      }
      let texts : Array[String] = if name == "replace_section" {
        edit_texts(op)
      } else {
        []
      }
      let template = find_template(false)
      let xml = build(template, texts)
      if indexes.is_empty() {
        if name == "delete_section" {
          (
            write(edit_splice(ctx.source, heading_start, heading_end, "")),
            heading.ordinal,
            "deleted section",
          )
        } else {
          (
            write(edit_splice(ctx.source, heading_end, heading_end, xml)),
            heading.ordinal,
            "replaced section body",
          )
        }
      } else {
        let (first_start, _) = edit_child_span(ctx, indexes[0])
        let (_, last_end) = edit_child_span(ctx, indexes[indexes.length() - 1])
        if name == "delete_section" {
          (
            write(edit_splice(ctx.source, heading_start, last_end, "")),
            heading.ordinal,
            "deleted section",
          )
        } else {
          (
            write(edit_splice(ctx.source, first_start, last_end, xml)),
            heading.ordinal,
            "replaced section body",
          )
        }
      }
    }
    "insert_section_after" => {
      let title = match operation_field(op, "heading_text") {
        String(text) if !text.trim().is_empty() => text
        _ => raise InvalidReplacement("heading_text is required")
      }
      validate_target_text(title)
      let level = match operation_field(op, "heading_level") {
        Number(n, ..) if n >= 1.0 && n <= 6.0 => n.to_int()
        _ => heading.level
      }
      let heading_xml = @xml.serialize(
        operation_element(prefix + "p", [], [
          Element(
            operation_element(prefix + "pPr", [], [
              Element(
                operation_element(
                  prefix + "pStyle",
                  [
                    {
                      name: prefix + "val",
                      value: edit_heading_style_id(ctx.styles, level),
                    },
                  ],
                  [],
                ),
              ),
              Element(
                operation_element(
                  prefix + "outlineLvl",
                  [{ name: prefix + "val", value: (level - 1).to_string(), }],
                  [],
                ),
              ),
            ]),
          ),
          Element(
            operation_element(
              prefix + "r",
              [],
              operation_text_nodes(prefix, title),
            ),
          ),
        ]),
      )
      let texts = match operation_field(op, "paragraphs") {
        Array(_) => edit_texts(op)
        _ => []
      }
      let body_xml = build(None, texts)
      let offset = if indexes.is_empty() {
        heading_end
      } else {
        let (_, last_end) = edit_child_span(ctx, indexes[indexes.length() - 1])
        last_end
      }
      (
        write(edit_splice(ctx.source, offset, offset, heading_xml + body_xml)),
        heading.ordinal,
        "inserted section",
      )
    }
    _ => raise InvalidReplacement("unknown section operation")
  }
}

///|
fn edit_apply_one(
  container : @opc.Package,
  op : Json,
  name : String,
  author : String,
  date : String?,
) -> (@opc.Package, Int32, String) raise DocxError {
  let style = operation_field(op, "style")
  match name {
    "insert_in_section"
    | "replace_section"
    | "delete_section"
    | "insert_section_after" => edit_section_op(container, op, name)
    "replace"
    | "delete"
    | "format"
    | "insert_after"
    | "insert_before"
    | "format_range"
    | "replace_range"
    | "comment" => {
      let ctx = edit_ctx(container)
      let paragraphs = edit_paragraphs(ctx)
      let target = edit_resolve_target(paragraphs, edit_target_json(op))
      match name {
        "replace" => {
          guard operation_field(op, "text") is String(text) else {
            raise InvalidReplacement("replace requires text")
          }
          (
            edit_delegate(container, target, "replace", Some(text), style),
            target.ordinal,
            "replaced paragraph",
          )
        }
        "delete" =>
          (
            edit_delegate(container, target, "delete", None, Json::null()),
            target.ordinal,
            "deleted paragraph",
          )
        "format" => {
          if style is Null {
            raise InvalidReplacement("format requires style")
          }
          (
            edit_delegate(container, target, "format", None, style),
            target.ordinal,
            "formatted paragraph",
          )
        }
        "insert_after" | "insert_before" => {
          let texts = edit_texts(op)
          (
            edit_insert_paragraphs(
              container,
              ctx,
              target,
              name == "insert_after",
              texts,
              style,
            ),
            target.ordinal,
            "inserted " + texts.length().to_string() + " paragraph(s)",
          )
        }
        _ => {
          let (start, end) = edit_range_bounds(target, op, name == "comment")
          let mut base = container
          let mut mode = RangeFormat
          let mut replacement = ""
          if name == "format_range" {
            if style is Null {
              raise InvalidReplacement("format_range requires style")
            }
          } else if name == "replace_range" {
            guard operation_field(op, "text") is String(text) else {
              raise InvalidReplacement("replace_range requires text")
            }
            validate_target_text(text)
            replacement = text
            mode = RangeReplace
          } else {
            guard operation_field(op, "text") is String(text) else {
              raise InvalidReplacement("comment requires text")
            }
            let (with_comment, id) = edit_add_comment(
              container, author, date, text,
            )
            base = with_comment
            mode = RangeComment(id)
          }
          let edited = edit_range_runs(
            target.element,
            start,
            end,
            mode,
            style,
            replacement,
          )
          let (paragraph_start, paragraph_end) = edit_child_span(
            ctx,
            target.child_index,
          )
          (
            base.replace_text(
              "word/document.xml",
              edit_splice(
                ctx.source,
                paragraph_start,
                paragraph_end,
                @xml.serialize(edited),
              ),
            ),
            target.ordinal,
            name + " applied",
          )
        }
      }
    }
    _ => raise InvalidReplacement("unknown operation")
  }
}

///|
/// Apply a bounded, atomic list of agent/user edit operations to a DOCX
/// package. Any failing operation aborts the whole request.
pub fn apply_edit_ops(
  container : @opc.Package,
  request : Json,
) -> (@opc.Package, Json) raise DocxError {
  guard operation_field(request, "ops") is Array(ops) else {
    raise InvalidReplacement("ops must be an array")
  }
  if ops.length() == 0 || ops.length() > 64 {
    raise InvalidReplacement("ops must contain between 1 and 64 operations")
  }
  let author = match operation_field(request, "author") {
    String(value) if !value.trim().is_empty() => value.trim().to_owned()
    _ => "MoonDesk AI"
  }
  let date : String? = match operation_field(request, "date") {
    String(value) if !value.is_empty() => Some(value)
    _ => None
  }
  let mut current = container
  let results : Array[Json] = []
  for index, op in ops {
    let name = match operation_field(op, "op") {
      String(value) => value
      _ =>
        raise InvalidReplacement(
          "op " + (index + 1).to_string() + ": operation name is missing",
        )
    }
    let (next, paragraph_index, message) = edit_apply_one(
      current, op, name, author, date,
    ) catch {
      InvalidReplacement(reason) =>
        raise InvalidReplacement(
          "op " + (index + 1).to_string() + " (" + name + "): " + reason,
        )
      error => raise error
    }
    current = next
    results.push({
      "op": name,
      "ok": true,
      "paragraph_index": Json::number(paragraph_index.to_double()),
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

///|
/// Heading outline in body-paragraph coordinates for agents and UI.
pub fn document_outline(container : @opc.Package) -> Json raise DocxError {
  let ctx = edit_ctx(container)
  let paragraphs = edit_paragraphs(ctx)
  let headings : Array[Json] = []
  for paragraph in paragraphs {
    if paragraph.level > 0 {
      headings.push({
        "paragraph_index": Json::number(paragraph.ordinal.to_double()),
        "level": Json::number(paragraph.level.to_double()),
        "text": paragraph.text,
      })
    }
  }
  let mut tables = 0
  for child in ctx.body.children {
    if child is Element(element) && element.local_name() == "tbl" {
      tables += 1
    }
  }
  {
    "paragraphs": Json::number(paragraphs.length().to_double()),
    "headings": Json::array(headings),
    "tables": Json::number(tables.to_double()),
  }
}

///|
fn edit_mentions_comment(element : @xml.Element, id : Int32) -> Bool {
  let name = element.local_name()
  if (name == "commentRangeStart" || name == "commentReference") &&
    int_attr(Some(element), "id") is Some(value) &&
    value == id {
    return true
  }
  element.child_elements().any(child => edit_mentions_comment(child, id))
}

///|
/// Word comments with the body paragraph that anchors each one.
pub fn list_comments(container : @opc.Package) -> Array[Json] raise DocxError {
  let result : Array[Json] = []
  if !container.has_part("word/comments.xml") {
    return result
  }
  let text = container.text("word/comments.xml") catch {
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(text) catch {
    error => raise InvalidDocument(repr(error))
  }
  let ctx = edit_ctx(container)
  let paragraphs = edit_paragraphs(ctx)
  for comment in root.child_elements() {
    if comment.local_name() != "comment" {
      continue
    }
    guard int_attr(Some(comment), "id") is Some(id) else { continue }
    let lines : Array[String] = []
    for paragraph in comment.child_elements() {
      if paragraph.local_name() == "p" {
        lines.push(operation_paragraph_text(paragraph))
      }
    }
    let mut anchor = -1
    for paragraph in paragraphs {
      if edit_mentions_comment(paragraph.element, id) {
        anchor = paragraph.ordinal
        break
      }
    }
    result.push({
      "id": Json::number(id.to_double()),
      "author": comment.attribute("author").unwrap_or(""),
      "text": lines.join("\n"),
      "paragraph_index": Json::number(anchor.to_double()),
    })
  }
  result
}
