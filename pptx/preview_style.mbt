///|
priv struct PreviewStyle {
  size : Double
  color : String
  family : String
  bold : Bool
  italic : Bool
  underline : Bool
} derive(Eq)

///|
priv struct PreviewGlyph {
  x : Double
  mut text : String
  style : PreviewStyle
}

///|
priv struct PreviewLine {
  glyphs : Array[PreviewGlyph]
  width : Double
  height : Double
  font_height : Double
  margin : Double
  alignment : String
  bullet : String
  bullet_x : Double
  bullet_style : PreviewStyle
}

///|
fn preview_palette(container : @opc.Package) -> Map[String, String] {
  let result : Map[String, String] = {
    "dk1": "000000",
    "lt1": "FFFFFF",
    "dk2": "1F2937",
    "lt2": "F3F4F6",
    "accent1": "4472C4",
    "accent2": "ED7D31",
    "accent3": "A5A5A5",
    "accent4": "FFC000",
    "accent5": "5B9BD5",
    "accent6": "70AD47",
    "hlink": "0563C1",
    "folHlink": "954F72",
  }
  for part in container.parts {
    if !part.name.has_prefix("ppt/theme/") || !part.name.has_suffix(".xml") {
      continue
    }
    let text = container.text(part.name) catch { _ => continue }
    let root = @xml.parse(text) catch { _ => continue }
    match first_descendant(root, "clrScheme") {
      Some(scheme) =>
        for color in scheme.child_elements() {
          let value = match color.first_child("srgbClr") {
            Some(rgb) => rgb.attribute("val")
            None =>
              match color.first_child("sysClr") {
                Some(system) => system.attribute("lastClr")
                None => None
              }
          }
          match value {
            Some(value) => result[color.local_name()] = value
            None => ()
          }
        }
      None => ()
    }
    break
  }
  result["tx1"] = result["dk1"]
  result["tx2"] = result["dk2"]
  result["bg1"] = result["lt1"]
  result["bg2"] = result["lt2"]
  result
}

///|
fn preview_hex(value : String, fallback : String) -> String {
  if value.length() != 6 ||
    !value
    .iter()
    .all(c => {
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    }) {
    fallback
  } else {
    value
  }
}

///|
fn preview_color(
  fill : @xml.Element,
  palette : Map[String, String],
  fallback : String,
) -> String {
  match fill.first_child("srgbClr") {
    Some(color) =>
      preview_hex(color.attribute("val").unwrap_or(fallback), fallback)
    None =>
      match fill.first_child("schemeClr") {
        Some(color) =>
          palette.get(color.attribute("val").unwrap_or("")).unwrap_or(fallback)
        None =>
          match fill.first_child("sysClr") {
            Some(color) =>
              preview_hex(
                color.attribute("lastClr").unwrap_or(fallback),
                fallback,
              )
            None => fallback
          }
      }
  }
}

///|
fn preview_style(
  properties : @xml.Element?,
  fallback : PreviewStyle,
  palette : Map[String, String],
  part : String,
) -> PreviewStyle raise PptxError {
  match properties {
    None => fallback
    Some(properties) => {
      let family = match properties.first_child("latin") {
        Some(font) => font.attribute("typeface").unwrap_or(fallback.family)
        None => fallback.family
      }
      let family = if family.has_prefix("+") { fallback.family } else { family }
      {
        size: match properties.attribute("sz") {
          Some(size) => parse_decimal(part, size).to_double() * 127.0
          None => fallback.size
        },
        color: match properties.first_child("solidFill") {
          Some(fill) => preview_color(fill, palette, fallback.color)
          None => fallback.color
        },
        family,
        bold: match properties.attribute("b") {
          Some("1" | "true" | "on") => true
          Some(_) => false
          None => fallback.bold
        },
        italic: match properties.attribute("i") {
          Some("1" | "true" | "on") => true
          Some(_) => false
          None => fallback.italic
        },
        underline: match properties.attribute("u") {
          Some("none" | "0" | "false") => false
          Some(_) => true
          None => fallback.underline
        },
      }
    }
  }
}

///|
fn preview_advance(c : Char, size : Double) -> Double {
  if c == ' ' || c == '\t' {
    size * 0.28
  } else if c.to_int() >= 0x2E80 {
    size
  } else if ['i', 'l', 'I', '.', ',', '!', ':', ';'].contains(c) {
    size * 0.28
  } else if ['m', 'w', 'M', 'W'].contains(c) {
    size * 0.82
  } else {
    size * 0.53
  }
}

///|
fn preview_line(
  glyphs : Array[PreviewGlyph],
  width : Double,
  font : Double,
  margin : Double,
  alignment : String,
  bullet : String,
  bullet_x : Double,
  style : PreviewStyle,
  line_spacing : Double,
  after : Double,
) -> PreviewLine {
  {
    glyphs: glyphs.copy(),
    width,
    font_height: font,
    margin,
    alignment,
    bullet,
    bullet_x,
    bullet_style: style,
    height: font * line_spacing + after,
  }
}

///|
fn preview_text_lines(
  body : @xml.Element,
  width : Double,
  palette : Map[String, String],
  part : String,
) -> Array[PreviewLine] raise PptxError {
  let result : Array[PreviewLine] = []
  let plain : PreviewStyle = {
    size: 228600.0,
    color: "263445",
    family: "Aptos",
    bold: false,
    italic: false,
    underline: false,
  }
  let default_properties = match body.first_child("lstStyle") {
    Some(list) =>
      match list.first_child("lvl1pPr") {
        Some(properties) => properties.first_child("defRPr")
        None => None
      }
    None => None
  }
  let body_style = preview_style(default_properties, plain, palette, part)
  for paragraph in body.children_named("p") {
    let properties = paragraph.first_child("pPr")
    let paragraph_default = match properties {
      Some(p) => p.first_child("defRPr")
      None => None
    }
    let style = preview_style(
      paragraph_default,
      preview_style(
        paragraph.first_child("endParaRPr"),
        body_style,
        palette,
        part,
      ),
      palette,
      part,
    )
    let margin = match properties {
      Some(p) => numeric_attribute(p, "marL", part, default=0).to_double()
      None => 0.0
    }
    let indent = match properties {
      Some(p) => numeric_attribute(p, "indent", part, default=0).to_double()
      None => 0.0
    }
    let alignment = match properties {
      Some(p) => p.attribute("algn").unwrap_or("l")
      None => "l"
    }
    let mut bullet = match properties {
      Some(p) =>
        match p.first_child("buChar") {
          Some(b) => b.attribute("char").unwrap_or("•")
          None => if p.first_child("buAutoNum") is Some(_) { "•" } else { "" }
        }
      None => ""
    }
    let line_spacing = match properties {
      Some(p) =>
        match p.first_child("lnSpc") {
          Some(p) =>
            match p.first_child("spcPct") {
              Some(p) =>
                numeric_attribute(p, "val", part, default=120000).to_double() /
                100000.0
              None => 1.2
            }
          None => 1.2
        }
      None => 1.2
    }
    let after = match properties {
      Some(p) =>
        match p.first_child("spcAft") {
          Some(p) =>
            match p.first_child("spcPts") {
              Some(p) =>
                numeric_attribute(p, "val", part, default=0).to_double() * 127.0
              None => 0.0
            }
          None => 0.0
        }
      None => 0.0
    }
    let available = (width - margin).max(style.size)
    let mut glyphs : Array[PreviewGlyph] = []
    let mut x = 0.0
    let mut font = style.size
    for node in paragraph.child_elements() {
      let current = preview_style(node.first_child("rPr"), style, palette, part)
      let text = match node.local_name() {
        "r" | "fld" => text_from_run(node).unwrap_or("")
        "br" => "\n"
        _ => ""
      }
      for c in text {
        let advance = preview_advance(c, current.size)
        if c == '\n' || (x > 0 && x + advance > available) {
          result.push(
            preview_line(
              glyphs,
              x,
              font,
              margin,
              alignment,
              bullet,
              margin + indent,
              style,
              line_spacing,
              0.0,
            ),
          )
          glyphs = []
          x = 0.0
          font = style.size
          bullet = ""
          if c == '\n' {
            continue
          }
        }
        if c == '\r' {
          continue
        }
        if !glyphs.is_empty() && glyphs[glyphs.length() - 1].style == current {
          let last = glyphs[glyphs.length() - 1]
          last.text += c.to_string()
        } else {
          glyphs.push({ x, text: c.to_string(), style: current, })
        }
        x += advance
        font = font.max(current.size)
      }
    }
    result.push(
      preview_line(
        glyphs,
        x,
        font,
        margin,
        alignment,
        bullet,
        margin + indent,
        style,
        line_spacing,
        after,
      ),
    )
  }
  result
}

///|
fn preview_style_attributes(style : PreviewStyle) -> String {
  "font-size=\"\{style.size}\" fill=\"#\{style.color}\" font-family=\"\{@xml.escape_attribute(style.family)},Microsoft YaHei,Arial,sans-serif\" font-weight=\"\{if style.bold {"700"}else{"400"}}\" font-style=\"\{if style.italic{"italic"}else{"normal"}}\" text-decoration=\"\{if style.underline{"underline"}else{"none"}}\""
}

///|
fn preview_text_svg(
  body : @xml.Element,
  bounds : @scene.Rect,
  palette : Map[String, String],
  part : String,
  clip_id : String,
  warnings : Array[String],
) -> String raise PptxError {
  let properties = body.first_child("bodyPr")
  let left = match properties {
    Some(p) => numeric_attribute(p, "lIns", part, default=91440).to_double()
    None => 91440.0
  }
  let right = match properties {
    Some(p) => numeric_attribute(p, "rIns", part, default=91440).to_double()
    None => 91440.0
  }
  let top = match properties {
    Some(p) => numeric_attribute(p, "tIns", part, default=45720).to_double()
    None => 45720.0
  }
  let bottom = match properties {
    Some(p) => numeric_attribute(p, "bIns", part, default=45720).to_double()
    None => 45720.0
  }
  let available = (bounds.width.to_double() - left - right).max(1.0)
  let lines = preview_text_lines(body, available, palette, part)
  let total = lines.fold(init=0.0, (sum, line) => sum + line.height)
  let height = bounds.height.to_double() - top - bottom
  let anchor = match properties {
    Some(p) => p.attribute("anchor").unwrap_or("t")
    None => "t"
  }
  let offset = if anchor == "ctr" {
    (height - total).max(0.0) / 2.0
  } else if anchor == "b" {
    (height - total).max(0.0)
  } else {
    0.0
  }
  if total > height && height > 0 {
    warnings.push(
      part +
      ": textbox " +
      clip_id +
      " exceeds its source bounds; full text remains in outline/targets.",
    )
  }
  let out = StringBuilder()
  out.write_string(
    "<defs><clipPath id=\"\{clip_id}\"><rect x=\"\{bounds.x}\" y=\"\{bounds.y}\" width=\"\{bounds.width.max(0)}\" height=\"\{bounds.height.max(0)}\"/></clipPath></defs><g clip-path=\"url(#\{clip_id})\">",
  )
  let mut y = bounds.y.to_double() + top + offset
  for line in lines {
    let align = if line.alignment == "ctr" {
      (available - line.margin - line.width).max(0.0) / 2.0
    } else if line.alignment == "r" {
      (available - line.margin - line.width).max(0.0)
    } else {
      0.0
    }
    let baseline = y + line.font_height * 0.85
    if line.bullet != "" {
      let bullet_x = if line.bullet_x == line.margin {
        line.margin - line.font_height * 0.75
      } else {
        line.bullet_x
      }
      out.write_string(
        "<text x=\"\{bounds.x.to_double()+left+bullet_x}\" y=\"\{baseline}\" \{preview_style_attributes(line.bullet_style)}>\{@xml.escape_text(line.bullet)}</text>",
      )
    }
    for glyph in line.glyphs {
      out.write_string(
        "<text x=\"\{bounds.x.to_double()+left+line.margin+align+glyph.x}\" y=\"\{baseline}\" xml:space=\"preserve\" \{preview_style_attributes(glyph.style)}>\{@xml.escape_text(glyph.text)}</text>",
      )
    }
    y += line.height
  }
  out.write_string("</g>")
  out.to_string()
}
