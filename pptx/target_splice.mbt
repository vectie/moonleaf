// Lexical edit helpers follow the existing DOCX targeted-edit implementation.
// Keep source outside the selected validated text element byte-for-byte.

///|
fn validate_target_text(text : String) -> Unit raise PptxError {
  if text.length() > 32_768 {
    raise InvalidPresentation(
      message="target replacement exceeds 32768 UTF-16 units",
    )
  }
  let mut i = 0
  while i < text.length() {
    let value = text[i].to_int()
    if value >= 0xD800 && value <= 0xDBFF {
      if i + 1 >= text.length() ||
        text[i + 1].to_int() < 0xDC00 ||
        text[i + 1].to_int() > 0xDFFF {
        raise InvalidPresentation(
          message="replacement contains an unpaired surrogate",
        )
      }
      i += 2
    } else {
      if (value < 0x20 && value != 9 && value != 10 && value != 13) ||
        (value >= 0xDC00 && value <= 0xDFFF) ||
        value == 0xFFFE ||
        value == 0xFFFF {
        raise InvalidPresentation(
          message="replacement contains a character forbidden by XML 1.0",
        )
      }
      i += 1
    }
  }
}

///|
fn element_count(element : @xml.Element) -> Int32 {
  let mut count = 1
  for child in element.child_elements() {
    count += element_count(child)
  }
  count
}

///|
fn target_ordinal(
  element : @xml.Element,
  path : Array[Int32],
  depth : Int32,
  ordinal : Int32,
) -> Int32 {
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
fn has_xml_prefix(source : String, offset : Int32, prefix : String) -> Bool {
  offset + prefix.length() <= source.length() &&
  source.unsafe_substring(start=offset, end=offset + prefix.length()) == prefix
}

///|
fn skip_markup(
  source : String,
  start : Int32,
  marker : String,
) -> Int32 raise PptxError {
  for offset = start
      offset + marker.length() <= source.length()
      offset = offset + 1 {
    if has_xml_prefix(source, offset, marker) {
      return offset + marker.length()
    }
  }
  raise InvalidPresentation(message="unterminated XML markup")
}

///|
// The XML parser establishes structure first. This lexical pass locates that
// exact element while skipping comments, CDATA, processing instructions and
// quoted attributes. Splicing leaves every other source character untouched.
fn target_source_span(
  source : String,
  wanted : Int32,
) -> (Int32, Int32) raise PptxError {
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
        raise InvalidPresentation(message="unterminated XML tag")
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
  raise InvalidPresentation(
    message="target text element could not be located in source",
  )
}

///|
fn replacement_element(element : @xml.Element, replacement : String) -> String {
  let output = StringBuilder()
  output.write_string("<a:t")
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
  output.write_string("</a:t>")
  output.to_string()
}

///|
fn element_at_path(
  element : @xml.Element,
  path : Array[Int32],
  depth : Int32,
) -> @xml.Element {
  if depth == path.length() {
    return element
  }
  match element.children[path[depth]] {
    Element(child) => element_at_path(child, path, depth + 1)
    _ => abort("validated target path disappeared")
  }
}
