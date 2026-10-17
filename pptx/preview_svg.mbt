///|
fn preview_shape_id(element : @xml.Element) -> String {
  match first_descendant(element, "cNvPr") {
    Some(id) => id.attribute("id").unwrap_or("")
    None => ""
  }
}

///|
fn preview_paint(
  properties : @xml.Element?,
  palette : Map[String, String],
  fallback : String,
) -> String {
  match properties {
    Some(properties) =>
      if properties.first_child("noFill") is Some(_) {
        "none"
      } else {
        match properties.first_child("solidFill") {
          Some(fill) => "#" + preview_color(fill, palette, fallback)
          None => if fallback == "" { "none" } else { "#" + fallback }
        }
      }
    None => if fallback == "" { "none" } else { "#" + fallback }
  }
}

///|
fn preview_geometry(
  kind : String,
  bounds : @scene.Rect,
  paint : String,
  stroke : String,
  stroke_width : Int32,
) -> String {
  let x = bounds.x.to_double()
  let y = bounds.y.to_double()
  let w = bounds.width.max(0).to_double()
  let h = bounds.height.max(0).to_double()
  let style = "fill=\"\{paint}\" stroke=\"\{stroke}\" stroke-width=\"\{stroke_width}\""
  match kind {
    "ellipse" =>
      "<ellipse cx=\"\{x+w/2.0}\" cy=\"\{y+h/2.0}\" rx=\"\{w/2.0}\" ry=\"\{h/2.0}\" \{style}/>"
    "line" =>
      "<path d=\"M\{x},\{y} L\{x+w},\{y+h}\" fill=\"none\" stroke=\"\{stroke}\" stroke-width=\"\{stroke_width}\"/>"
    "triangle" =>
      "<path d=\"M\{x+w/2.0},\{y} L\{x+w},\{y+h} L\{x},\{y+h} Z\" \{style}/>"
    "diamond" =>
      "<path d=\"M\{x+w/2.0},\{y} L\{x+w},\{y+h/2.0} L\{x+w/2.0},\{y+h} L\{x},\{y+h/2.0} Z\" \{style}/>"
    _ =>
      "<rect x=\"\{x}\" y=\"\{y}\" width=\"\{w}\" height=\"\{h}\" rx=\"\{if kind=="roundRect"{w.min(h)*0.12}else{0.0}}\" \{style}/>"
  }
}

///|
fn preview_source_warning(
  element : @xml.Element,
  part : String,
  warnings : Array[String],
) -> Unit {
  match element.first_child("spPr") {
    Some(properties) => {
      if properties.first_child("gradFill") is Some(_) ||
        properties.first_child("pattFill") is Some(_) ||
        properties.first_child("blipFill") is Some(_) {
        warnings.push(
          part + ": non-solid shape fill not reproduced in neutral preview.",
        )
      }
      match properties.first_child("xfrm") {
        Some(transform) =>
          if transform.attribute("rot").unwrap_or("0") != "0" ||
            bool_attribute(transform, "flipH") ||
            bool_attribute(transform, "flipV") {
            warnings.push(
              part +
              ": source transform bounds are retained; rotated/flipped glyph or image orientation is approximated.",
            )
          }
        None => ()
      }
    }
    None => ()
  }
}

///|
fn preview_svg(
  container : @opc.Package,
  slide : @scene.Slide,
  root : @xml.Element,
  originals : Array[@xml.Element],
  part : String,
  relationships : Array[@opc.Relationship],
  palette : Map[String, String],
  warnings : Array[String],
) -> String raise PptxError {
  let out = StringBuilder()
  let background = match root.first_child("cSld") {
    Some(common) =>
      match common.first_child("bg") {
        Some(bg) => preview_paint(bg.first_child("bgPr"), palette, "FFFFFF")
        None => "#FFFFFF"
      }
    None => "#FFFFFF"
  }
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \{slide.width} \{slide.height}\" role=\"img\" aria-label=\"\{@xml.escape_attribute(slide.name)}\"><rect width=\"\{slide.width}\" height=\"\{slide.height}\" fill=\"\{background}\"/>",
  )
  for index, element in slide.elements {
    let source = originals.get(index)
    let shape_id = match source {
      Some(source) => preview_shape_id(source)
      None => ""
    }
    out.write_string("<g data-shape-id=\"\{@xml.escape_attribute(shape_id)}\">")
    match source {
      Some(source) => preview_source_warning(source, part, warnings)
      None => ()
    }
    match element {
      TextBox(bounds~, runs~) =>
        match source {
          Some(source) => {
            let properties = source.first_child("spPr")
            let line = match properties {
              Some(properties) => properties.first_child("ln")
              None => None
            }
            let line_width = match line {
              Some(line) => numeric_attribute(line, "w", part, default=12700)
              None => 0
            }
            out.write_string(
              preview_geometry(
                "rect",
                bounds,
                preview_paint(properties, palette, ""),
                preview_paint(line, palette, ""),
                line_width,
              ),
            )
            match source.first_child("txBody") {
              Some(body) =>
                out.write_string(
                  preview_text_svg(
                    body,
                    bounds,
                    palette,
                    part,
                    "text-" + index.to_string(),
                    warnings,
                  ),
                )
              None => out.write_string(preview_runs_fallback(runs, bounds))
            }
          }
          None => out.write_string(preview_runs_fallback(runs, bounds))
        }
      Shape(kind~, bounds~, text~) => {
        let properties = match source {
          Some(source) => source.first_child("spPr")
          None => None
        }
        let line = match properties {
          Some(properties) => properties.first_child("ln")
          None => None
        }
        let line_width = match line {
          Some(line) => numeric_attribute(line, "w", part, default=12700)
          None => 12700
        }
        out.write_string(
          preview_geometry(
            kind,
            bounds,
            preview_paint(properties, palette, "F3F4F6"),
            preview_paint(line, palette, "AEB8C5"),
            line_width,
          ),
        )
        if ![
            "rect", "roundRect", "ellipse", "line", "triangle", "diamond", "shape",
          ].contains(kind) {
          warnings.push(
            part +
            ": preset geometry " +
            kind +
            " shown as its neutral source bounding box.",
          )
        }
        match source {
          Some(source) =>
            match source.first_child("txBody") {
              Some(body) =>
                out.write_string(
                  preview_text_svg(
                    body,
                    bounds,
                    palette,
                    part,
                    "text-" + index.to_string(),
                    warnings,
                  ),
                )
              None => out.write_string(preview_runs_fallback(text, bounds))
            }
          None => out.write_string(preview_runs_fallback(text, bounds))
        }
      }
      Image(bounds~, relationship_id~) =>
        match
          image_relationship_part(
            container, part, relationships, relationship_id,
          ) {
          Some(image_part) =>
            match container.part(image_part) {
              Some(image) => {
                let mime = image_content_type(container, image_part).unwrap_or(
                  "image/png",
                )
                let encoded = @base64.encode(
                  Bytes::from_array(image.content)[:],
                )
                out.write_string(
                  "<image x=\"\{bounds.x}\" y=\"\{bounds.y}\" width=\"\{bounds.width.max(0)}\" height=\"\{bounds.height.max(0)}\" preserveAspectRatio=\"none\" href=\"data:\{mime};base64,\{encoded}\"/>",
                )
                match source {
                  Some(source) =>
                    if first_descendant(source, "srcRect") is Some(_) {
                      warnings.push(
                        part +
                        ": embedded image rendered at source bounds; source cropping is not reproduced.",
                      )
                    }
                  None => ()
                }
              }
              None =>
                warnings.push(
                  part + ": local embedded image part not available.",
                )
            }
          None =>
            warnings.push(
              part + ": unsupported or external image is not fetched.",
            )
        }
    }
    out.write_string("</g>")
  }
  out.write_string("</svg>")
  out.to_string()
}

///|
fn preview_runs_fallback(
  runs : Array[@scene.TextRun],
  bounds : @scene.Rect,
) -> String {
  let out = StringBuilder()
  let mut x = bounds.x.to_double()
  let mut y = bounds.y.to_double()
  for run in runs {
    let size = run.style.font_size_half_points.unwrap_or(36).to_double() *
      6350.0
    if y == bounds.y.to_double() {
      y += size
    }
    for line_index, line in run.text.split("\n") {
      if line_index > 0 {
        x = bounds.x.to_double()
        y += size * 1.2
      }
      out.write_string(
        "<text x=\"\{x}\" y=\"\{y}\" font-size=\"\{size}\" font-family=\"Arial,Microsoft YaHei,sans-serif\" fill=\"#\{preview_hex(run.style.color.unwrap_or("263445"),"263445")}\" font-weight=\"\{if run.style.bold{"700"}else{"400"}}\" font-style=\"\{if run.style.italic{"italic"}else{"normal"}}\">\{@xml.escape_text(line.to_owned())}</text>",
      )
      for char in line {
        x += preview_advance(char, size)
      }
    }
  }
  out.to_string()
}

///|
fn preview_outline_svg(
  slide : SlideOutline,
  width : Int32,
  height : Int32,
) -> String {
  let out = StringBuilder()
  let font = height.to_double() / 30.0
  let margin = width.to_double() / 18.0
  let mut y = font * 2.0
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \{width} \{height}\" role=\"img\"><rect width=\"\{width}\" height=\"\{height}\" fill=\"#FFFFFF\"/>",
  )
  for block in slide.blocks {
    for paragraph in block.paragraphs {
      out.write_string(
        "<text x=\"\{margin}\" y=\"\{y}\" font-size=\"\{font}\" fill=\"#263445\" font-family=\"Arial,Microsoft YaHei,sans-serif\">\{@xml.escape_text(paragraph)}</text>",
      )
      y += font * 1.3
    }
    for row in block.rows {
      out.write_string(
        "<text x=\"\{margin}\" y=\"\{y}\" font-size=\"\{font*0.75}\" fill=\"#263445\" font-family=\"Arial,Microsoft YaHei,sans-serif\">\{@xml.escape_text(row.join(" | "))}</text>",
      )
      y += font
    }
  }
  out.write_string("</svg>")
  out.to_string()
}
