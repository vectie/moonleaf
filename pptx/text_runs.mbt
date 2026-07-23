///|
fn bool_attribute(element : @xml.Element, name : String) -> Bool {
  match element.attribute(name) {
    Some("1" | "true" | "on") => true
    _ => false
  }
}

///|
fn run_color(properties : @xml.Element) -> String? {
  match first_descendant(properties, "srgbClr") {
    Some(color) => color.attribute("val")
    None => None
  }
}

///|
fn text_style(
  run : @xml.Element,
  part : String,
) -> @scene.TextStyle raise PptxError {
  let properties = run.first_child("rPr")
  match properties {
    None => @scene.TextStyle::plain()
    Some(properties) => {
      let font_size_half_points = match properties.attribute("sz") {
        Some(value) => Some(parse_decimal(part, value) / 50)
        None => None
      }
      {
        bold: bool_attribute(properties, "b"),
        italic: bool_attribute(properties, "i"),
        underline: match properties.attribute("u") {
          Some("none" | "0" | "false") | None => false
          Some(_) => true
        },
        font_size_half_points,
        color: run_color(properties),
      }
    }
  }
}

///|
fn text_from_run(run : @xml.Element) -> String? {
  match first_descendant(run, "t") {
    Some(text) => Some(text.text_content())
    None => None
  }
}

///|
fn text_runs(
  text_body : @xml.Element,
  part : String,
) -> Array[@scene.TextRun] raise PptxError {
  let result : Array[@scene.TextRun] = []
  let paragraphs = text_body.children_named("p")
  for paragraph_index, paragraph in paragraphs {
    for child in paragraph.child_elements() {
      match child.local_name() {
        "r" | "fld" =>
          match text_from_run(child) {
            Some(text) => result.push({ text, style: text_style(child, part) })
            None => ()
          }
        "br" => result.push({ text: "\n", style: @scene.TextStyle::plain() })
        _ => ()
      }
    }
    if paragraph_index + 1 < paragraphs.length() {
      result.push({ text: "\n", style: @scene.TextStyle::plain() })
    }
  }
  result
}
