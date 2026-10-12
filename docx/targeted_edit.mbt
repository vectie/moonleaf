///|
/// A supported main-body text element. IDs are structural positions, meaningful
/// only for the exact source revision from which they were listed.
pub(all) struct TextTarget {
  id : String
  text : String
} derive(Eq, Debug)

///|
pub extend TextTarget with Eq::{equal, not_equal}

///|
pub extend TextTarget with @debug.Debug::{to_repr}

///|
priv struct TargetSlot {
  target : TextTarget
  path : Array[Int]
}

///|
fn target_root(document_package : @opc.Package) -> @xml.Element raise DocxError {
  let source = document_package.text("word/document.xml") catch {
    MissingPart(_) => raise MissingDocument
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  if root.name != "w:document" ||
    !root.attributes.any(a => {
      a.name == "xmlns:w" &&
      a.value == "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    }) {
    raise InvalidReplacement(
      "targeted editing requires a standard w:document namespace",
    )
  }
  validate_target_structure(root)
  root
}

///|
fn validate_target_structure(element : @xml.Element) -> Unit raise DocxError {
  for attribute in element.attributes {
    if attribute.name == "xmlns:w" &&
      attribute.value !=
      "http://schemas.openxmlformats.org/wordprocessingml/2006/main" {
      raise InvalidReplacement(
        "targeted editing does not support rebinding xmlns:w",
      )
    }
  }
  // Complex fields may span paragraphs. Do not offer their displayed results
  // as ordinary editable text, even when the start is in a different paragraph.
  if element.name == "w:fldChar" || element.name == "w:instrText" {
    raise InvalidReplacement(
      "targeted editing does not support complex-field documents",
    )
  }
  for child in element.child_elements() {
    validate_target_structure(child)
  }
}

///|
fn target_slots(root : @xml.Element) -> Array[TargetSlot] raise DocxError {
  let output = []
  let bodies = root.children.filter(child => {
    match child {
      Element(element) => element.name == "w:body"
      _ => false
    }
  })
  if bodies.length() != 1 {
    raise InvalidDocument("targeted editing requires exactly one w:body")
  }
  for index, child in root.children {
    if child is Element(body) && body.name == "w:body" {
      collect_target_slots(body, [index], "body", output)
    }
  }
  output
}

///|
fn collect_target_slots(
  parent : @xml.Element,
  path : Array[Int],
  id : String,
  output : Array[TargetSlot],
) -> Unit raise DocxError {
  let mut ordinal = 0
  for index, child in parent.children {
    guard child is Element(element) else { continue }
    ordinal += 1
    let eligible = match parent.name {
      "w:body" => element.name == "w:p" || element.name == "w:tbl"
      "w:tbl" => element.name == "w:tr"
      "w:tr" => element.name == "w:tc"
      "w:tc" => element.name == "w:p"
      "w:p" => element.name == "w:r"
      "w:r" => element.name == "w:t"
      _ => false
    }
    if !eligible {
      continue
    }
    let next_path = path.copy()
    next_path.push(index)
    let next_id = id + "/" + element.local_name() + ":" + ordinal.to_string()
    if element.name == "w:t" {
      if element.children.any(child => child is Element(_)) {
        raise InvalidReplacement("target text must not contain child elements")
      }
      if output.length() >= 10_000 {
        raise InvalidReplacement("targeted editing exceeds 10000 text elements")
      }
      output.push({
        target: { id: next_id, text: element.text_content(), },
        path: next_path,
      })
    } else {
      collect_target_slots(element, next_path, next_id, output)
    }
  }
}

///|
/// List ordinary direct-run text in main-body paragraphs and one-level tables.
/// Wrappers, hyperlinks, nested tables, drawings, headers and footers are omitted.
pub fn text_targets(
  document_package : @opc.Package,
) -> Array[TextTarget] raise DocxError {
  target_slots(target_root(document_package)).map(slot => slot.target)
}

///|
fn validate_target_text(text : String) -> Unit raise DocxError {
  if text.length() > 32_768 {
    raise InvalidReplacement("target replacement exceeds 32768 UTF-16 units")
  }
  let mut i = 0
  while i < text.length() {
    let value = text[i].to_int()
    if value >= 0xD800 && value <= 0xDBFF {
      if i + 1 >= text.length() ||
        text[i + 1].to_int() < 0xDC00 ||
        text[i + 1].to_int() > 0xDFFF {
        raise InvalidReplacement("replacement contains an unpaired surrogate")
      }
      i += 2
    } else {
      if (value < 0x20 && value != 9 && value != 10 && value != 13) ||
        (value >= 0xDC00 && value <= 0xDFFF) ||
        value == 0xFFFE ||
        value == 0xFFFF {
        raise InvalidReplacement(
          "replacement contains a character forbidden by XML 1.0",
        )
      }
      i += 1
    }
  }
}

///|
fn element_count(element : @xml.Element) -> Int {
  let mut count = 1
  for child in element.child_elements() {
    count += element_count(child)
  }
  count
}

///|
fn target_ordinal(
  element : @xml.Element,
  path : Array[Int],
  depth : Int,
  ordinal : Int,
) -> Int {
  if depth == path.length() {
    return ordinal
  }
  let mut next = ordinal + 1
  for index, child in element.children {
    if child is Element(child) {
      if index == path[depth] {
        return target_ordinal(child, path, depth + 1, next)
      }
      next += element_count(child)
    }
  }
  abort("validated target path disappeared")
}

///|
fn has_xml_prefix(source : String, offset : Int, prefix : String) -> Bool {
  offset + prefix.length() <= source.length() &&
  source.unsafe_substring(start=offset, end=offset + prefix.length()) == prefix
}

///|
fn skip_markup(
  source : String,
  start : Int,
  marker : String,
) -> Int raise DocxError {
  for offset = start
      offset + marker.length() <= source.length()
      offset = offset + 1 {
    if has_xml_prefix(source, offset, marker) {
      return offset + marker.length()
    }
  }
  raise InvalidDocument("unterminated XML markup")
}

///|
// The XML parser establishes structure first. This lexical pass locates that
// exact element while skipping comments, CDATA, processing instructions and
// quoted attributes. Splicing leaves every other source character untouched.
fn target_source_span(
  source : String,
  wanted : Int,
) -> (Int, Int) raise DocxError {
  let mut offset = 0
  let mut ordinal = 0
  let mut selected = -1
  while offset < source.length() {
    if source[offset] != '<' {
      offset += 1
      continue
    }
    if has_xml_prefix(source, offset, "<!--") {
      offset = skip_markup(source, offset + 4, "-->")
    } else if has_xml_prefix(source, offset, "<![CDATA[") {
      offset = skip_markup(source, offset + 9, "]]>")
    } else if has_xml_prefix(source, offset, "<?") {
      offset = skip_markup(source, offset + 2, "?>")
    } else {
      let start = offset
      let closing = has_xml_prefix(source, offset, "</")
      offset += 1
      let mut quote : UInt16? = None
      while offset < source.length() {
        let c = source[offset]
        match quote {
          Some(q) => if c == q { quote = None }
          None =>
            if c == '\'' || c == '"' {
              quote = Some(c)
            } else if c == '>' {
              break
            }
        }
        offset += 1
      }
      if offset >= source.length() {
        raise InvalidDocument("unterminated XML tag")
      }
      let self_closing = source[offset - 1] == '/'
      offset += 1
      if closing {
        if selected >= 0 {
          return (selected, offset)
        }
      } else {
        ordinal += 1
        if ordinal == wanted {
          if self_closing {
            return (start, offset)
          }
          selected = start
        }
      }
    }
  }
  raise InvalidDocument("target text element could not be located in source")
}

///|
fn replacement_element(element : @xml.Element, replacement : String) -> String {
  let output = StringBuilder()
  output.write_string("<w:t")
  for attribute in element.attributes {
    if attribute.name == "xml:space" {
      continue
    }
    let escaped = @xml.escape_attribute(attribute.value)
      .replace_all(old="\r", new="&#13;")
      .replace_all(old="\n", new="&#10;")
      .replace_all(old="\t", new="&#9;")
    output.write_string(" " + attribute.name + "=\"" + escaped + "\"")
  }
  output.write_string(" xml:space=\"preserve\">")
  output.write_string(
    @xml.escape_text(replacement).replace_all(old="\r", new="&#13;"),
  )
  output.write_string("</w:t>")
  output.to_string()
}

///|
fn element_at_path(
  element : @xml.Element,
  path : Array[Int],
  depth : Int,
) -> @xml.Element {
  if depth == path.length() {
    return element
  }
  match element.children[path[depth]] {
    Element(child) => element_at_path(child, path, depth + 1)
    _ => abort("validated target path disappeared")
  }
}

///|
/// Replace exactly one listed text element, checking its full expected text.
/// Other matches are untouched. No substring matching or cross-run replacement.
/// The input package and all non-document part payloads remain unchanged.
pub fn set_target_text(
  document_package : @opc.Package,
  id : String,
  expected : String,
  replacement : String,
) -> @opc.Package raise DocxError {
  validate_target_text(replacement)
  let root = target_root(document_package)
  let matches = target_slots(root).filter(slot => slot.target.id == id)
  guard matches is [slot] else {
    raise InvalidReplacement("unknown or unsupported text target: " + id)
  }
  if slot.target.text != expected {
    raise InvalidReplacement("text target no longer has the expected text")
  }
  if expected == replacement {
    return document_package
  }
  let source = document_package.text("word/document.xml") catch {
    error => raise InvalidDocument(repr(error))
  }
  let (start, end) = target_source_span(
    source,
    target_ordinal(root, slot.path, 0, 1),
  )
  let updated = source.unsafe_substring(start=0, end=start) +
    replacement_element(element_at_path(root, slot.path, 0), replacement) +
    source.unsafe_substring(start=end, end=source.length())
  document_package.replace_text("word/document.xml", updated)
}
