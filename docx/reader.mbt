///|
fn property_enabled(element : @xml.Element, name : String) -> Bool {
  match element.first_child(name) {
    None => false
    Some(property) =>
      match property.attribute("val") {
        None => true
        Some(value) => {
          let value = value.to_lower()
          value != "0" && value != "false" && value != "off" && value != "none"
        }
      }
  }
}

///|
fn parse_run_style(run : @xml.Element) -> @scene.TextStyle {
  match run.first_child("rPr") {
    None => @scene.TextStyle::plain()
    Some(properties) => {
      let size = match properties.first_child("sz") {
        None => None
        Some(size) => {
          let parsed = parse_int_or(size.attribute("val"), -1)
          if parsed >= 0 {
            Some(parsed)
          } else {
            None
          }
        }
      }
      let color = match properties.first_child("color") {
        Some(color) => color.attribute("val")
        None => None
      }
      {
        bold: property_enabled(properties, "b"),
        italic: property_enabled(properties, "i"),
        underline: property_enabled(properties, "u"),
        font_size_half_points: size,
        color,
      }
    }
  }
}

///|
fn parse_run(run : @xml.Element) -> @scene.TextRun? {
  let text = StringBuilder()
  for child in run.child_elements() {
    match child.local_name() {
      "t" => text.write_string(child.text_content())
      "tab" => text.write_string("\t")
      "br" | "cr" => text.write_string("\n")
      _ => ()
    }
  }
  if text.is_empty() {
    None
  } else {
    Some({ text: text.to_string(), style: parse_run_style(run), })
  }
}

///|
fn collect_runs(element : @xml.Element, output : Array[@scene.TextRun]) -> Unit {
  for child in element.child_elements() {
    if child.local_name() == "r" {
      match parse_run(child) {
        Some(run) => output.push(run)
        None => ()
      }
    } else if child.local_name() != "pPr" {
      collect_runs(child, output)
    }
  }
}

///|
fn heading_level(properties : @xml.Element?) -> Int32? {
  match properties {
    None => None
    Some(properties) =>
      match properties.first_child("pStyle") {
        None => None
        Some(style) =>
          match style.attribute("val") {
            None => None
            Some(value) => {
              let value = value.to_lower()
              for level in 1..<=6 {
                if value == "heading" + level.to_string() ||
                  value == "heading " + level.to_string() {
                  return Some(level)
                }
              }
              None
            }
          }
      }
  }
}

///|
fn list_properties(properties : @xml.Element?) -> (Int32, String)? {
  match properties {
    None => None
    Some(properties) =>
      match properties.first_child("numPr") {
        None => None
        Some(numbering) => {
          let level = match numbering.first_child("ilvl") {
            Some(level) => parse_int_or(level.attribute("val"), 0)
            None => 0
          }
          match numbering.first_child("numId") {
            Some(num_id) =>
              match num_id.attribute("val") {
                Some(num_id) => Some((level, num_id))
                None => Some((level, ""))
              }
            None => Some((level, ""))
          }
        }
      }
  }
}

///|
fn parse_paragraph(
  paragraph : @xml.Element,
  numbering : Numbering,
) -> @scene.TextBlock {
  let runs = []
  collect_runs(paragraph, runs)
  let properties = paragraph.first_child("pPr")
  match heading_level(properties) {
    Some(level) => Heading(level, runs)
    None =>
      match list_properties(properties) {
        Some((level, num_id)) =>
          ListItem(level~, ordered=numbering.is_ordered(num_id, level), runs)
        None => Paragraph(runs)
      }
  }
}

///|
fn collect_text(element : @xml.Element, output : StringBuilder) -> Unit {
  if element.local_name() == "t" {
    output.write_string(element.text_content())
  } else {
    for child in element.child_elements() {
      collect_text(child, output)
    }
  }
}

///|
fn parse_table(table : @xml.Element) -> @scene.TextBlock {
  let rows = []
  for row in table.children_named("tr") {
    let cells = []
    for cell in row.children_named("tc") {
      let paragraphs = []
      for paragraph in cell.children_named("p") {
        let text = StringBuilder()
        collect_text(paragraph, text)
        paragraphs.push(text.to_string())
      }
      cells.push(paragraphs.join("\n"))
    }
    rows.push(cells)
  }
  Table(rows)
}

///|
/// Read the main `word/document.xml` part of a DOCX package into MoonLeaf's
/// portable text scene. Unsupported WordprocessingML is ignored without
/// changing the source package.
pub fn read(
  document_package : @opc.Package,
) -> @scene.TextDocument raise DocxError {
  let source = document_package.text("word/document.xml") catch {
    MissingPart(_) => raise MissingDocument
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  let body = if root.local_name() == "body" {
    Some(root)
  } else {
    root.first_child("body")
  }
  let body = match body {
    Some(body) => body
    None => raise InvalidDocument("missing w:body")
  }
  let numbering = load_numbering(document_package)
  let blocks = []
  for child in body.child_elements() {
    match child.local_name() {
      "p" => blocks.push(parse_paragraph(child, numbering))
      "tbl" => blocks.push(parse_table(child))
      _ => ()
    }
  }
  { blocks, warnings: [], }
}
