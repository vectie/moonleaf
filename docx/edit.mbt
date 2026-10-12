///|
fn text_with_preserved_space(
  element : @xml.Element,
  value : String,
) -> @xml.Element {
  let attributes : Array[@xml.Attribute] = []
  let preserve = value.has_prefix(" ") ||
    value.has_suffix(" ") ||
    value.has_prefix("\t") ||
    value.has_suffix("\t")
  let mut found = false
  for attribute in element.attributes {
    if attribute.name == "xml:space" && preserve {
      attributes.push({ name: "xml:space", value: "preserve", })
      found = true
    } else {
      attributes.push(attribute)
    }
  }
  if preserve && !found {
    attributes.push({ name: "xml:space", value: "preserve", })
  }
  { name: element.name, attributes, children: [@xml.Text(value)], }
}

///|
// Only simple Word runs may be joined. A tab, break, field, drawing, hyperlink,
// or other paragraph child ends the search segment rather than being crossed.
fn simple_run_text(element : @xml.Element) -> String? {
  if element.name != "w:r" {
    return None
  }
  let mut value : String? = None
  for child in element.children {
    match child {
      Element(part) =>
        if part.name == "w:t" {
          if value is Some(_) {
            return None
          }
          value = Some(part.text_content())
        } else if part.name != "w:rPr" {
          return None
        }
      Text(raw) => if raw.trim() != "" { return None }
    }
  }
  value
}

///|
fn rewrite_run_text(element : @xml.Element, value : String) -> @xml.Element {
  let children : Array[@xml.Node] = []
  for child in element.children {
    match child {
      Element(part) if part.name == "w:t" =>
        children.push(Element(text_with_preserved_space(part, value)))
      _ => children.push(child)
    }
  }
  { name: element.name, attributes: element.attributes, children, }
}

///|
fn run_at_offset(offsets : Array[Int], position : Int) -> Int {
  let mut low = 0
  let mut high = offsets.length()
  for ;; {
    if low >= high {
      break
    }
    let middle = low + (high - low) / 2
    if offsets[middle] <= position {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low - 1
}

///|
fn append_original_range(
  values : Array[String],
  offsets : Array[Int],
  output : Array[StringBuilder],
  start : Int,
  end : Int,
) -> Unit {
  if start >= end {
    return
  }
  let mut index = run_at_offset(offsets, start)
  for ;; {
    if index >= values.length() || offsets[index] >= end {
      break
    }
    let left = offsets[index]
    let right = left + values[index].length()
    let from = if start > left { start } else { left }
    let until = if end < right { end } else { right }
    if from < until {
      output[index].write_string(
        values[index].unsafe_substring(start=from - left, end=until - left),
      )
    }
    index += 1
  }
}

///|
fn replace_run_segment(
  children : Array[@xml.Node],
  indices : Array[Int],
  values : Array[String],
  find : String,
  replacement : String,
  changed : Ref[Bool],
) -> Unit {
  if indices.is_empty() {
    return
  }
  let combined = StringBuilder()
  let offsets : Array[Int] = []
  let mut total = 0
  for value in values {
    offsets.push(total)
    total += value.length()
    combined.write_string(value)
  }
  let original = combined.to_string()
  if original.replace_all(old=find, new=replacement) == original {
    return
  }
  let output : Array[StringBuilder] = []
  for _ in indices {
    output.push(StringBuilder())
  }
  let mut cursor = 0
  for ;; {
    if cursor >= total {
      break
    }
    let remaining = original.unsafe_substring(start=cursor, end=total)
    match remaining.find(find) {
      None => break
      Some(relative) => {
        let position = cursor + relative
        append_original_range(values, offsets, output, cursor, position)
        output[run_at_offset(offsets, position)].write_string(replacement)
        cursor = position + find.length()
      }
    }
  }
  append_original_range(values, offsets, output, cursor, total)
  for index in 0..<indices.length() {
    match children[indices[index]] {
      Element(run) =>
        children[indices[index]] = Element(
          rewrite_run_text(run, output[index].to_string()),
        )
      _ => ()
    }
  }
  changed.val = true
}

///|
fn replace_in_paragraph(
  element : @xml.Element,
  find : String,
  replacement : String,
  changed : Ref[Bool],
) -> @xml.Element {
  let children : Array[@xml.Node] = []
  let indices : Array[Int] = []
  let values : Array[String] = []
  for child in element.children {
    match child {
      Element(run) =>
        match simple_run_text(run) {
          Some(value) => {
            indices.push(children.length())
            values.push(value)
            children.push(child)
          }
          None => {
            replace_run_segment(
              children, indices, values, find, replacement, changed,
            )
            indices.clear()
            values.clear()
            children.push(
              Element(replace_in_element(run, find, replacement, changed)),
            )
          }
        }
      Text(raw) if raw.trim() == "" => children.push(child)
      _ => {
        replace_run_segment(
          children, indices, values, find, replacement, changed,
        )
        indices.clear()
        values.clear()
        children.push(child)
      }
    }
  }
  replace_run_segment(children, indices, values, find, replacement, changed)
  { name: element.name, attributes: element.attributes, children, }
}

///|
fn replace_in_element(
  element : @xml.Element,
  find : String,
  replacement : String,
  changed : Ref[Bool],
) -> @xml.Element {
  if element.name == "w:ins" ||
    element.name == "w:del" ||
    element.name == "w:moveFrom" ||
    element.name == "w:moveTo" ||
    element.name == "w:fldSimple" {
    return element
  }
  if element.name == "w:p" {
    return replace_in_paragraph(element, find, replacement, changed)
  }
  if element.name == "w:t" {
    let original = element.text_content()
    let updated = original.replace_all(old=find, new=replacement)
    if updated != original {
      changed.val = true
      return text_with_preserved_space(element, updated)
    }
    return element
  }
  let children : Array[@xml.Node] = []
  for child in element.children {
    match child {
      Element(part) =>
        children.push(
          Element(replace_in_element(part, find, replacement, changed)),
        )
      _ => children.push(child)
    }
  }
  { name: element.name, attributes: element.attributes, children, }
}

///|
fn editable_text_part(name : String) -> Bool {
  name == "word/document.xml" ||
  (name.has_prefix("word/header") && name.has_suffix(".xml")) ||
  (name.has_prefix("word/footer") && name.has_suffix(".xml"))
}

///|
/// Replace literal text within a Word paragraph, including matches split
/// across adjacent simple runs. Replacement inherits the first run's style;
/// untouched prefixes and suffixes retain their original runs. Matches never
/// cross paragraph or structural boundaries. The document body and its header
/// and footer XML parts are edited independently; other package parts are kept.
pub fn replace_text(
  document_package : @opc.Package,
  find : String,
  replacement : String,
) -> @opc.Package raise DocxError {
  if find.is_empty() {
    raise InvalidReplacement("find text must not be empty")
  }
  if !document_package.has_part("word/document.xml") {
    raise MissingDocument
  }
  let mut result = document_package
  for part in document_package.parts {
    if !editable_text_part(part.name) {
      continue
    }
    let source = document_package.text(part.name) catch {
      error => raise InvalidDocument(repr(error))
    }
    let root = @xml.parse(source) catch {
      error => raise InvalidDocument(repr(error))
    }
    let changed = Ref(false)
    let updated = replace_in_element(root, find, replacement, changed)
    if changed.val {
      result = result.replace_text(part.name, @xml.serialize(updated))
    }
  }
  result
}

///|
/// Replace one body paragraph's visible text while retaining its paragraph
/// properties and first run's character style. The zero-based index counts
/// top-level `w:p` children of `w:body`, excluding table cell paragraphs.
/// The expected text guards against a stale preview. Complex runs and field
/// content are rejected so editing cannot silently discard document features.
pub fn replace_body_paragraph(
  document_package : @opc.Package,
  paragraph_index : Int,
  expected_text : String,
  replacement : String,
) -> @opc.Package raise DocxError {
  if paragraph_index < 0 ||
    paragraph_index >= 5000 ||
    replacement.length() > 32768 {
    raise InvalidReplacement("paragraph index or replacement exceeds limit")
  }
  for character in replacement {
    let code = character.to_int()
    if code < 32 && code != 9 {
      raise InvalidReplacement(
        "replacement contains unsupported control character",
      )
    }
  }
  let source = document_package.text("word/document.xml") catch {
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  let found = Ref(false)
  let ordinal = Ref(0)
  let updated = replace_body_paragraph_in_element(
    root, paragraph_index, expected_text, replacement, ordinal, found,
  )
  if !found.val {
    raise InvalidReplacement("body paragraph was not found")
  }
  if expected_text == replacement {
    document_package
  } else {
    document_package.replace_text("word/document.xml", @xml.serialize(updated))
  }
}

///|
fn replace_body_paragraph_in_element(
  element : @xml.Element,
  paragraph_index : Int,
  expected_text : String,
  replacement : String,
  ordinal : Ref[Int],
  found : Ref[Bool],
) -> @xml.Element raise DocxError {
  if element.local_name() == "body" {
    let children : Array[@xml.Node] = []
    for child in element.children {
      match child {
        Element(paragraph) if paragraph.local_name() == "p" => {
          let index = ordinal.val
          ordinal.val += 1
          children.push(
            Element(
              if index == paragraph_index {
                found.val = true
                replace_simple_paragraph(paragraph, expected_text, replacement)
              } else {
                paragraph
              },
            ),
          )
        }
        _ => children.push(child)
      }
    }
    { name: element.name, attributes: element.attributes, children, }
  } else {
    let children : Array[@xml.Node] = []
    for child in element.children {
      match child {
        Element(part) =>
          children.push(
            Element(
              replace_body_paragraph_in_element(
                part, paragraph_index, expected_text, replacement, ordinal, found,
              ),
            ),
          )
        _ => children.push(child)
      }
    }
    { name: element.name, attributes: element.attributes, children, }
  }
}

///|
fn replace_simple_paragraph(
  paragraph : @xml.Element,
  expected_text : String,
  replacement : String,
) -> @xml.Element raise DocxError {
  let current = StringBuilder()
  let mut first_run = -1
  for index, child in paragraph.children {
    match child {
      Element(part) if part.local_name() == "pPr" => ()
      Element(part) =>
        match simple_run_text(part) {
          Some(value) => {
            if first_run == -1 {
              first_run = index
            }
            current.write_string(value)
          }
          None =>
            raise InvalidReplacement(
              "paragraph contains fields, links, breaks or complex runs",
            )
        }
      Text(raw) if raw.trim() == "" => ()
      _ => raise InvalidReplacement("paragraph contains unsupported text")
    }
  }
  if current.to_string() != expected_text {
    raise InvalidReplacement("paragraph text changed since preview")
  }
  if first_run == -1 {
    raise InvalidReplacement("paragraph has no editable text run")
  }
  let children : Array[@xml.Node] = []
  for index, child in paragraph.children {
    match child {
      Element(run) if simple_run_text(run) is Some(_) =>
        children.push(
          Element(
            rewrite_run_text(
              run,
              if index == first_run {
                replacement
              } else {
                ""
              },
            ),
          ),
        )
      _ => children.push(child)
    }
  }
  { name: paragraph.name, attributes: paragraph.attributes, children, }
}
