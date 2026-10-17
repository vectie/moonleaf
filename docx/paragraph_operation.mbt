///|
fn operation_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn operation_prefix(element : @xml.Element) -> String {
  match element.name.find(":") {
    Some(index) => element.name.unsafe_substring(start=0, end=index + 1)
    None => ""
  }
}

///|
fn operation_element(
  name : String,
  attributes : Array[@xml.Attribute],
  children : Array[@xml.Node],
) -> @xml.Element {
  { name, attributes, children, }
}

///|
fn operation_property(
  parent : @xml.Element,
  local_name : String,
  value : String,
) -> @xml.Element {
  let prefix = operation_prefix(parent)
  let children : Array[@xml.Node] = []
  let mut found = false
  for child in parent.children {
    if child is Element(existing) && existing.local_name() == local_name {
      let attributes = existing.attributes.filter(attribute => {
        attribute.name != prefix + "val" &&
        !(local_name == "color" &&
        ["themeColor", "themeTint", "themeShade"].any(key => {
          attribute.name == prefix + key
        }))
      })
      attributes.push({ name: prefix + "val", value, })
      children.push(
        Element(operation_element(existing.name, attributes, existing.children)),
      )
      found = true
    } else {
      children.push(child)
    }
  }
  if !found {
    let property : @xml.Node = Element(
      operation_element(
        prefix + local_name,
        [{ name: prefix + "val", value, }],
        [],
      ),
    )
    let mut position = children.length()
    if local_name == "pStyle" {
      position = 0
    } else {
      for index, child in children {
        if child is Element(element) &&
          (
            ["rPr", "sectPr", "pPrChange", "rPrChange"].contains(
              element.local_name(),
            ) ||
            (
              local_name == "jc" &&
              [
                "textDirection", "textAlignment", "textboxTightWrap", "outlineLvl",
                "divId", "cnfStyle",
              ].contains(element.local_name())
            ) ||
            (
              local_name == "outlineLvl" &&
              ["divId", "cnfStyle"].contains(element.local_name())
            )
          ) {
          position = index
          break
        }
      }
    }
    children.insert(position, property)
  }
  operation_element(parent.name, parent.attributes, children)
}

///|
fn operation_styles(
  element : @xml.Element,
  style : Json,
  paragraph : Bool,
) -> @xml.Element raise DocxError {
  let prefix = operation_prefix(element)
  let property_name = if paragraph { "pPr" } else { "rPr" }
  let mut properties = element
    .first_child(property_name)
    .unwrap_or(operation_element(prefix + property_name, [], []))
  let mut modified = false
  if style is Object(values) {
    for key, value in values {
      if value is Null {
        continue
      }
      if paragraph && key == "alignment" {
        guard value is String(alignment) &&
          ["left", "center", "right", "justify"].contains(alignment) else {
          raise InvalidReplacement(
            "alignment must be left, center, right or justify",
          )
        }
        properties = operation_property(
          properties,
          "jc",
          if alignment == "justify" {
            "both"
          } else {
            alignment
          },
        )
        modified = true
      } else if paragraph && key == "heading" {
        guard value is Number(level, ..) &&
          level >= 0.0 &&
          level <= 6.0 &&
          level.to_int().to_double() == level else {
          raise InvalidReplacement("heading must be integer 0..6")
        }
        properties = operation_property(
          properties,
          "pStyle",
          if level == 0.0 {
            "Normal"
          } else {
            "Heading" + level.to_int().to_string()
          },
        )
        properties = operation_property(
          properties,
          "outlineLvl",
          if level == 0.0 {
            "9"
          } else {
            (level.to_int() - 1).to_string()
          },
        )
        modified = true
      } else if !paragraph && ["bold", "italic", "underline"].contains(key) {
        guard value is (True | False) else {
          raise InvalidReplacement(key + " must be boolean")
        }
        let name = if key == "bold" {
          "b"
        } else if key == "italic" {
          "i"
        } else {
          "u"
        }
        let flag = if key == "underline" {
          if value is True {
            "single"
          } else {
            "none"
          }
        } else if value is True {
          "1"
        } else {
          "0"
        }
        properties = operation_property(properties, name, flag)
        if key == "bold" {
          properties = operation_property(properties, "bCs", flag)
        }
        if key == "italic" {
          properties = operation_property(properties, "iCs", flag)
        }
        modified = true
      } else if !paragraph && key == "font_size_pt" {
        guard value is Number(size, ..) &&
          !size.is_nan() &&
          !size.is_inf() &&
          size > 0.0 &&
          size * 2.0 <= 2147483647.0 &&
          (size * 2.0).to_int().to_double() == size * 2.0 else {
          raise InvalidReplacement(
            "font_size_pt must be positive and a multiple of 0.5pt",
          )
        }
        properties = operation_property(
          properties,
          "sz",
          (size * 2.0).to_int().to_string(),
        )
        properties = operation_property(
          properties,
          "szCs",
          (size * 2.0).to_int().to_string(),
        )
        modified = true
      } else if !paragraph && key == "color" {
        guard value is String(color) &&
          color.length() == 6 &&
          color.all(c => {
            (c >= '0' && c <= '9') ||
            (c >= 'a' && c <= 'f') ||
            (c >= 'A' && c <= 'F')
          }) else {
          raise InvalidReplacement(
            "color must be a six-digit RGB hexadecimal value",
          )
        }
        properties = operation_property(properties, "color", color.to_upper())
        modified = true
      }
    }
  }
  if !modified {
    return element
  }
  let children = element.children.copy()
  let mut found = false
  for index, child in children {
    if child is Element(existing) && existing.local_name() == property_name {
      children[index] = Element(properties)
      found = true
    }
  }
  if !found {
    children.insert(0, Element(properties))
  }
  operation_element(element.name, element.attributes, children)
}

///|
fn operation_format_runs(
  element : @xml.Element,
  style : Json,
) -> @xml.Element raise DocxError {
  if element.local_name() == "r" {
    return operation_styles(element, style, false)
  }
  let children : Array[@xml.Node] = element.children.map(child => {
    match child {
      Element(part) if part.local_name() != "pPr" =>
        Element(operation_format_runs(part, style))
      _ => child
    }
  })
  operation_element(element.name, element.attributes, children)
}

///|
fn operation_text_nodes(prefix : String, text : String) -> Array[@xml.Node] {
  let nodes : Array[@xml.Node] = []
  let pending = Ref(StringBuilder())
  fn flush(
    prefix : String,
    pending : Ref[StringBuilder],
    nodes : Array[@xml.Node],
  ) -> Unit {
    let text = pending.val.to_string()
    if !text.is_empty() {
      nodes.push(
        Element(
          operation_element(
            prefix + "t",
            [{ name: "xml:space", value: "preserve", }],
            [Text(text)],
          ),
        ),
      )
      pending.val = StringBuilder()
    }
  }
  for
    character in text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n") {
    if character == '\t' || character == '\n' {
      flush(prefix, pending, nodes)
      nodes.push(
        Element(
          operation_element(
            prefix + (if character == '\t' { "tab" } else { "br" }),
            [],
            [],
          ),
        ),
      )
    } else {
      pending.val.write_char(character)
    }
  }
  flush(prefix, pending, nodes)
  if nodes.is_empty() {
    nodes.push(
      Element(
        operation_element(
          prefix + "t",
          [{ name: "xml:space", value: "preserve", }],
          [Text("")],
        ),
      ),
    )
  }
  nodes
}

///|
fn operation_replace_runs(
  element : @xml.Element,
  replacement : String,
  written : Ref[Bool],
) -> @xml.Element {
  if element.local_name() == "r" {
    let has_text = element
      .child_elements()
      .any(part => ["t", "tab", "br", "cr"].contains(part.local_name()))
    if !has_text {
      return element
    }
    let children = element.children.filter(child => {
      match child {
        Element(part) => !["t", "tab", "br", "cr"].contains(part.local_name())
        _ => true
      }
    })
    if !written.val {
      for child in operation_text_nodes(operation_prefix(element), replacement) {
        children.push(child)
      }
      written.val = true
    }
    return operation_element(element.name, element.attributes, children)
  }
  let children : Array[@xml.Node] = element.children.map(child => {
    match child {
      Element(part) if part.local_name() != "pPr" =>
        Element(operation_replace_runs(part, replacement, written))
      _ => child
    }
  })
  operation_element(element.name, element.attributes, children)
}

///|
fn operation_complex(element : @xml.Element) -> String? {
  let name = element.local_name()
  if [
      "drawing", "pict", "object", "fldChar", "instrText", "fldSimple", "ins", "del",
      "moveFrom", "moveTo", "AlternateContent", "sdt",
    ].contains(name) {
    return Some(name)
  }
  for child in element.child_elements() {
    if child.local_name() == "pPr" {
      continue
    }
    if operation_complex(child) is Some(name) {
      return Some(name)
    }
  }
  None
}

///|
fn operation_paragraph_text(element : @xml.Element) -> String {
  let out = StringBuilder()
  for child in element.child_elements() {
    if child.local_name() == "r" {
      out.write_string(operation_run_text(child))
    } else if child.local_name() != "pPr" {
      out.write_string(operation_paragraph_text(child))
    }
  }
  out.to_string()
}

///|
fn operation_run_text(
  element : @xml.Element,
  include_page_breaks~ : Bool = true,
) -> String {
  let out = StringBuilder()
  for child in element.child_elements() {
    match child.local_name() {
      "t" => out.write_string(child.text_content())
      "tab" => out.write_char('\t')
      "br" if !include_page_breaks && child.attribute("w:type") == Some("page") =>
        ()
      "br" | "cr" => out.write_char('\n')
      _ => ()
    }
  }
  out.to_string()
}

///|
fn operation_span(
  source : String,
  wanted : Int32,
) -> (Int32, Int32) raise DocxError {
  let mut offset = 0
  let mut ordinal = 0
  let mut depth = 0
  let mut selected_depth = -1
  let mut selected_start = -1
  while offset < source.length() {
    if source[offset] != '<' {
      offset += 1
      continue
    }
    if has_xml_prefix(source, offset, "<!--") {
      offset = skip_markup(source, offset + 4, "-->")
      continue
    }
    if has_xml_prefix(source, offset, "<![CDATA[") {
      offset = skip_markup(source, offset + 9, "]]>")
      continue
    }
    if has_xml_prefix(source, offset, "<?") {
      offset = skip_markup(source, offset + 2, "?>")
      continue
    }
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
      raise InvalidDocument("unterminated paragraph XML tag")
    }
    let self_closing = source[offset - 1] == '/'
    offset += 1
    if closing {
      depth -= 1
      if selected_start >= 0 && depth == selected_depth {
        return (selected_start, offset)
      }
    } else {
      ordinal += 1
      if ordinal == wanted {
        if self_closing {
          return (start, offset)
        }
        selected_start = start
        selected_depth = depth
      }
      if !self_closing {
        depth += 1
      }
    }
  }
  raise InvalidDocument("body paragraph source span unavailable")
}

///|
fn operation_index(request : Json, key : String) -> Int32 raise DocxError {
  match operation_field(request, key) {
    Number(n, ..) if !n.is_nan() &&
      !n.is_inf() &&
      n >= 0.0 &&
      n <= 2147483647.0 &&
      n.to_int().to_double() == n => n.to_int()
    _ => raise InvalidReplacement(key + " must be a nonnegative integer")
  }
}

///|
fn operation_child_at(
  parent : @xml.Element,
  name : String,
  wanted : Int32,
) -> (Int32, @xml.Element) raise DocxError {
  let mut ordinal = 0
  for position, child in parent.children {
    if child is Element(element) && element.local_name() == name {
      if ordinal == wanted {
        return (position, element)
      }
      ordinal += 1
    }
  }
  raise InvalidReplacement("selected " + name + " was not found")
}

///|
fn operation_inserted(
  paragraph : @xml.Element,
  text : String,
  style : Json,
) -> @xml.Element raise DocxError {
  let prefix = operation_prefix(paragraph)
  let children : Array[@xml.Node] = []
  if paragraph.first_child("pPr") is Some(properties) {
    children.push(
      Element(
        operation_element(
          properties.name,
          properties.attributes,
          properties.children.filter(child => {
            match child {
              Element(part) => part.local_name() != "sectPr"
              _ => true
            }
          }),
        ),
      ),
    )
  }
  let run_children : Array[@xml.Node] = []
  let runs = paragraph.child_elements().filter(part => part.local_name() == "r")
  if runs.get(0) is Some(run) && run.first_child("rPr") is Some(properties) {
    run_children.push(Element(properties))
  }
  for child in operation_text_nodes(prefix, text) {
    run_children.push(child)
  }
  children.push(Element(operation_element(prefix + "r", [], run_children)))
  let attrs = paragraph.attributes.filter(attribute => {
    attribute.name == "xmlns" || attribute.name.has_prefix("xmlns:")
  })
  let inserted = operation_element(paragraph.name, attrs, children)
  operation_format_runs(operation_styles(inserted, style, true), style)
}

///|
/// Edit a direct body paragraph or a selected table-cell paragraph. Deleting
/// a cell's last paragraph retains the mandatory empty paragraph. Unselected
/// package content and cell/row/table properties remain untouched.
pub fn edit_body_paragraph(
  container : @opc.Package,
  request : Json,
) -> @opc.Package raise DocxError {
  guard request
    is {
      "operation": String(operation),
      "paragraph_index": Number(index, ..),
      "expected_text": String(expected),
      ..
    } &&
    !index.is_nan() &&
    !index.is_inf() &&
    index >= 0.0 &&
    index <= 2147483647.0 &&
    index.to_int().to_double() == index else {
    raise InvalidReplacement(
      "operation requires paragraph_index and expected_text",
    )
  }
  if !["replace", "format", "insert_before", "insert_after", "delete"].contains(
      operation,
    ) {
    raise InvalidReplacement("unknown paragraph operation")
  }
  let style = operation_field(request, "style")
  if !(style is Null || style is Object(_)) {
    raise InvalidReplacement("paragraph style must be an object")
  }
  if style is Object(values) {
    for key, _ in values {
      if ![
          "bold", "italic", "underline", "font_size_pt", "color", "alignment", "heading",
        ].contains(key) {
        raise InvalidReplacement("unsupported paragraph style property: " + key)
      }
    }
  }
  let source = container.text("word/document.xml") catch {
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  let mut path : Array[Int32] = []
  let mut paragraph : @xml.Element? = None
  let mut ordinal = 0
  let scope = operation_field(request, "scope")
  let table_cell = scope is String("table_cell")
  if !(scope is Null || scope is String("body") || table_cell) {
    raise InvalidReplacement("scope must be body or table_cell")
  }
  let mut cell_paragraph_count = 0
  for body_index, child in root.children {
    if child is Element(body) && body.local_name() == "body" {
      if table_cell {
        let (table_position, table) = operation_child_at(
          body,
          "tbl",
          operation_index(request, "table_index"),
        )
        let (row_position, row) = operation_child_at(
          table,
          "tr",
          operation_index(request, "row_index"),
        )
        let (cell_position, cell) = operation_child_at(
          row,
          "tc",
          operation_index(request, "cell_index"),
        )
        let (paragraph_position, selected) = operation_child_at(
          cell,
          "p",
          index.to_int(),
        )
        path = [
          body_index, table_position, row_position, cell_position, paragraph_position,
        ]
        paragraph = Some(selected)
        cell_paragraph_count = cell
          .child_elements()
          .filter(element => element.local_name() == "p")
          .length()
        continue
      }
      for child_index, node in body.children {
        if node is Element(current) && current.local_name() == "p" {
          if ordinal == index.to_int() {
            path = [body_index, child_index]
            paragraph = Some(current)
          }
          ordinal += 1
        }
      }
    }
  }
  guard paragraph is Some(paragraph) else {
    raise InvalidReplacement("body paragraph was not found")
  }
  if operation_paragraph_text(paragraph) != expected {
    raise InvalidReplacement("paragraph text changed since preview")
  }
  let (start, end) = operation_span(source, target_ordinal(root, path, 0, 1))
  let replacement = match operation {
    "replace" | "insert_before" | "insert_after" => {
      guard operation_field(request, "text") is String(text) else {
        raise InvalidReplacement("replacement/insertion requires text")
      }
      validate_target_text(text)
      text
    }
    _ => ""
  }
  if operation == "replace" &&
    replacement == expected &&
    (style is Null || (style is Object(values) && values.is_empty())) {
    return container
  }
  if operation == "format" &&
    (style is Null || (style is Object(values) && values.is_empty())) {
    return container
  }
  if operation == "replace" || operation == "delete" {
    if operation_complex(paragraph) is Some(name) {
      raise InvalidReplacement(
        "selected paragraph contains unsupported " +
        name +
        "; other document paragraphs remain editable",
      )
    }
  }
  let original = source.unsafe_substring(start~, end~)
  let changed = match operation {
    "insert_before" =>
      @xml.serialize(operation_inserted(paragraph, replacement, style)) +
      original
    "insert_after" =>
      original +
      @xml.serialize(operation_inserted(paragraph, replacement, style))
    "delete" =>
      if paragraph.first_child("pPr") is Some(properties) &&
        properties.first_child("sectPr") is Some(_) {
        @xml.serialize(
          operation_element(paragraph.name, paragraph.attributes, [
            Element(properties),
          ]),
        )
      } else if table_cell && cell_paragraph_count == 1 {
        @xml.serialize(
          operation_element(paragraph.name, paragraph.attributes, []),
        )
      } else {
        ""
      }
    _ => {
      let updated = if operation == "replace" {
        let written = Ref(false)
        let edited = operation_replace_runs(paragraph, replacement, written)
        if written.val {
          edited
        } else {
          let children = edited.children.copy()
          children.push(
            Element(
              operation_element(
                operation_prefix(paragraph) + "r",
                [],
                operation_text_nodes(operation_prefix(paragraph), replacement),
              ),
            ),
          )
          operation_element(edited.name, edited.attributes, children)
        }
      } else {
        paragraph
      }
      @xml.serialize(
        operation_format_runs(operation_styles(updated, style, true), style),
      )
    }
  }
  if changed == original {
    return container
  }
  container.replace_text(
    "word/document.xml",
    source.unsafe_substring(start=0, end=start) +
    changed +
    source.unsafe_substring(start=end, end=source.length()),
  )
}
