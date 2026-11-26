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
          None =>
            match properties.first_child("gradFill") {
              Some(grad) =>
                match first_descendant(grad, "gs") {
                  Some(stop) => "#" + preview_color(stop, palette, fallback)
                  None => if fallback == "" { "none" } else { "#" + fallback }
                }
              None => if fallback == "" { "none" } else { "#" + fallback }
            }
        }
      }
    None => if fallback == "" { "none" } else { "#" + fallback }
  }
}

///|
fn preview_bg_from_root(
  root : @xml.Element,
  palette : Map[String, String],
) -> String? {
  guard root.first_child("cSld") is Some(common) else { return None }
  guard common.first_child("bg") is Some(bg) else { return None }
  match bg.first_child("bgPr") {
    Some(bg_pr) => {
      let paint = preview_paint(Some(bg_pr), palette, "")
      if paint != "none" {
        return Some(paint)
      }
    }
    None => ()
  }
  match bg.first_child("bgRef") {
    Some(bg_ref) => {
      let color = preview_color(bg_ref, palette, "")
      if color != "" {
        return Some("#" + color)
      }
    }
    None => ()
  }
  None
}

///|
fn preview_related_part(
  part : String,
  relationships : Array[@opc.Relationship],
  suffix : String,
) -> String? {
  for rel in relationships {
    if !rel.external && rel.relationship_type.has_suffix(suffix) {
      let target = rel.target
      if target.has_prefix("/") {
        return Some(target[1:].to_owned())
      }
      if target.has_prefix("ppt/") {
        return Some(target)
      }
      let base = match part.rev_find("/") {
        Some(idx) => part[:idx + 1].to_owned()
        None => ""
      }
      if target.has_prefix("../") {
        let up = match base[:base.length() - 1].to_owned().rev_find("/") {
          Some(idx) => base[:idx + 1].to_owned()
          None => ""
        }
        return Some(up + target[3:].to_owned())
      }
      return Some(base + target)
    }
  }
  None
}

///|
fn preview_inherited_background(
  container : @opc.Package,
  root : @xml.Element,
  part : String,
  relationships : Array[@opc.Relationship],
  palette : Map[String, String],
) -> String {
  if preview_bg_from_root(root, palette) is Some(bg) {
    return bg
  }
  if preview_related_part(part, relationships, "/slideLayout")
    is Some(layout_part) {
    if (container.text(layout_part) catch { _ => "" }) is layout_xml &&
      !layout_xml.is_empty() {
      if (@xml.parse(layout_xml) catch { _ => root }) is layout_root {
        if preview_bg_from_root(layout_root, palette) is Some(bg) {
          return bg
        }
        let layout_rels = container.relationships(layout_part) catch { _ => [] }
        if preview_related_part(layout_part, layout_rels, "/slideMaster")
          is Some(master_part) {
          if (container.text(master_part) catch { _ => "" }) is master_xml &&
            !master_xml.is_empty() {
            if (@xml.parse(master_xml) catch { _ => root }) is master_root {
              if preview_bg_from_root(master_root, palette) is Some(bg) {
                return bg
              }
            }
          }
        }
      }
    }
  }
  "#FFFFFF"
}

///|
fn preview_layout_decor(
  container : @opc.Package,
  part : String,
  relationships : Array[@opc.Relationship],
  palette : Map[String, String],
) -> String {
  guard preview_related_part(part, relationships, "/slideLayout")
    is Some(layout_part) else {
    return ""
  }
  let layout_xml = container.text(layout_part) catch { _ => return "" }
  let layout_root = @xml.parse(layout_xml) catch { _ => return "" }
  guard layout_root.first_child("cSld") is Some(csld) else { return "" }
  guard csld.first_child("spTree") is Some(tree) else { return "" }
  let layout_rels = container.relationships(layout_part) catch { _ => [] }
  let out = StringBuilder()
  for child in tree.child_elements() {
    if child.local_name() == "pic" {
      let id = match first_descendant(child, "blip") {
        Some(blip) =>
          blip
          .attribute("embed")
          .unwrap_or(blip.attribute("link").unwrap_or(""))
        None => ""
      }
      if image_relationship_part(container, layout_part, layout_rels, id)
        is Some(image_part) {
        if container.part(image_part) is Some(image) {
          if child.first_child("spPr") is Some(sp_pr) &&
            sp_pr.first_child("xfrm") is Some(xfrm) &&
            xfrm.first_child("off") is Some(off) &&
            xfrm.first_child("ext") is Some(ext) {
            let x = pptx_parse_int_or(off.attribute("x").unwrap_or("0"), 0)
            let y = pptx_parse_int_or(off.attribute("y").unwrap_or("0"), 0)
            let w = pptx_parse_int_or(ext.attribute("cx").unwrap_or("0"), 0)
            let h = pptx_parse_int_or(ext.attribute("cy").unwrap_or("0"), 0)
            if w > 0 && h > 0 {
              let mime = image_content_type(container, image_part).unwrap_or(
                "image/png",
              )
              let encoded = @base64.encode(Bytes::from_array(image.content)[:])
              out.write_string(
                preview_image_svg(
                  preview_pt(x.to_double()),
                  preview_pt(y.to_double()),
                  preview_pt(w.to_double()),
                  preview_pt(h.to_double()),
                  mime,
                  encoded,
                  Some(child),
                ),
              )
            }
          }
        }
      }
    } else if child.local_name() == "sp" {
      // Only render non-placeholder decorative shapes from the layout
      let is_placeholder = match child.first_child("nvSpPr") {
        Some(nv) =>
          match nv.first_child("nvPr") {
            Some(nvp) => nvp.first_child("ph") is Some(_)
            None => false
          }
        None => false
      }
      if !is_placeholder {
        if child.first_child("spPr") is Some(sp_pr) &&
          sp_pr.first_child("xfrm") is Some(xfrm) &&
          xfrm.first_child("off") is Some(off) &&
          xfrm.first_child("ext") is Some(ext) {
          let x = pptx_parse_int_or(off.attribute("x").unwrap_or("0"), 0)
          let y = pptx_parse_int_or(off.attribute("y").unwrap_or("0"), 0)
          let w = pptx_parse_int_or(ext.attribute("cx").unwrap_or("0"), 0)
          let h = pptx_parse_int_or(ext.attribute("cy").unwrap_or("0"), 0)
          let paint = preview_paint(Some(sp_pr), palette, "")
          let line = sp_pr.first_child("ln")
          let stroke = preview_paint(line, palette, "")
          if w > 0 && h > 0 && (paint != "none" || stroke != "none") {
            let kind = match sp_pr.first_child("prstGeom") {
              Some(g) => g.attribute("prst").unwrap_or("rect")
              None => "rect"
            }
            out.write_string(
              preview_geometry(
                kind,
                { x, y, width: w, height: h, },
                paint,
                stroke,
                12700,
              ),
            )
          }
        }
      }
    }
  }
  out.to_string()
}

///|
fn preview_image_svg(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  mime : String,
  encoded : String,
  element : @xml.Element?,
) -> String {
  let src_rect = match element {
    Some(el) => first_descendant(el, "srcRect")
    None => None
  }
  match src_rect {
    Some(sr) => {
      let l = pptx_parse_int_or(sr.attribute("l").unwrap_or("0"), 0)
        .max(0)
        .to_double()
      let t = pptx_parse_int_or(sr.attribute("t").unwrap_or("0"), 0)
        .max(0)
        .to_double()
      let r = pptx_parse_int_or(sr.attribute("r").unwrap_or("0"), 0)
        .max(0)
        .to_double()
      let b = pptx_parse_int_or(sr.attribute("b").unwrap_or("0"), 0)
        .max(0)
        .to_double()
      let vw = (100000.0 - l - r).max(1.0)
      let vh = (100000.0 - t - b).max(1.0)
      "<svg x=\"\{x}\" y=\"\{y}\" width=\"\{w}\" height=\"\{h}\" viewBox=\"\{l} \{t} \{vw} \{vh}\" preserveAspectRatio=\"none\"><image x=\"0\" y=\"0\" width=\"100000\" height=\"100000\" preserveAspectRatio=\"none\" href=\"data:\{mime};base64,\{encoded}\"/></svg>"
    }
    None =>
      "<image x=\"\{x}\" y=\"\{y}\" width=\"\{w}\" height=\"\{h}\" preserveAspectRatio=\"xMidYMid meet\" href=\"data:\{mime};base64,\{encoded}\"/>"
  }
}

///|
fn preview_pt(emu : Double) -> Double {
  emu / 12700.0
}

///|
fn preview_geometry(
  kind : String,
  bounds : @scene.Rect,
  paint : String,
  stroke : String,
  stroke_width : Int32,
) -> String {
  let x = preview_pt(bounds.x.to_double())
  let y = preview_pt(bounds.y.to_double())
  let w = preview_pt(bounds.width.max(0).to_double())
  let h = preview_pt(bounds.height.max(0).to_double())
  let sw = if stroke == "none" {
    0.0
  } else {
    preview_pt(stroke_width.to_double()).max(0.5)
  }
  let style = "fill=\"\{paint}\" stroke=\"\{stroke}\" stroke-width=\"\{sw}\""
  match kind {
    "ellipse" =>
      "<ellipse cx=\"\{x+w/2.0}\" cy=\"\{y+h/2.0}\" rx=\"\{w/2.0}\" ry=\"\{h/2.0}\" \{style}/>"
    "line" =>
      "<path d=\"M\{x},\{y} L\{x+w},\{y+h}\" fill=\"none\" stroke=\"\{stroke}\" stroke-width=\"\{sw}\"/>"
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
  let background = preview_inherited_background(
    container, root, part, relationships, palette,
  )
  let layout_decor = preview_layout_decor(
    container, part, relationships, palette,
  )
  let vw = preview_pt(slide.width.to_double())
  let vh = preview_pt(slide.height.to_double())
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \{vw} \{vh}\" role=\"img\" aria-label=\"\{@xml.escape_attribute(slide.name)}\"><rect width=\"\{vw}\" height=\"\{vh}\" fill=\"\{background}\"/>\{layout_decor}",
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
                  preview_image_svg(
                    preview_pt(bounds.x.to_double()),
                    preview_pt(bounds.y.to_double()),
                    preview_pt(bounds.width.max(0).to_double()),
                    preview_pt(bounds.height.max(0).to_double()),
                    mime,
                    encoded,
                    source,
                  ),
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
        "<text x=\"\{preview_pt(x)}\" y=\"\{preview_pt(y)}\" font-size=\"\{preview_pt(size)}\" font-family=\"Arial,Microsoft YaHei,sans-serif\" fill=\"#\{preview_hex(run.style.color.unwrap_or("263445"),"263445")}\" font-weight=\"\{if run.style.bold{"700"}else{"400"}}\" font-style=\"\{if run.style.italic{"italic"}else{"normal"}}\">\{@xml.escape_text(line.to_owned())}</text>",
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
  let vw = preview_pt(width.to_double())
  let vh = preview_pt(height.to_double())
  let font = vh / 30.0
  let margin = vw / 18.0
  let mut y = font * 2.0
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \{vw} \{vh}\" role=\"img\"><rect width=\"\{vw}\" height=\"\{vh}\" fill=\"#FFFFFF\"/>",
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
