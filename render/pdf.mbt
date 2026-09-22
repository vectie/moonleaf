///|
pub(all) struct PdfDocument {
  bytes : Bytes
  page_count : Int
} derive(Debug)

///|
priv struct Glyph {
  face : Int
  code : Int
  size : Int
  x : Int
  advance : Int
  underline : Bool
}

///|
priv struct Line {
  glyphs : Array[Glyph]
  width : Int
  height : Int
  offset : Int
}

///|
fn hex4(value : Int) -> String {
  let s = value.to_string(radix=16)
  "0".repeat((4 - s.length()).max(0)) + s
}

///|
fn face_index(faces : Array[Face], family : String) -> Int raise PdfError {
  for i, face in faces {
    if face.input.family == family {
      return i
    }
  }
  raise InvalidFont("required font not supplied: " + family)
}

///|
/// Strict Chinese/Latin legal-document profile. Complex-script shaping is not supported.
fn paragraph_lines(
  p : @docx.ParagraphInfo,
  width : Int,
  faces : Array[Face],
  default_family : String,
) -> Array[Line] raise PdfError {
  let m = p.metadata
  let left = m.left_indent_twips.unwrap_or(0)
  let right = m.right_indent_twips.unwrap_or(0)
  let first = m.first_line_twips.unwrap_or(0) - m.hanging_twips.unwrap_or(0)
  let available = width - left - right
  guard available > 0 else {
    raise LayoutOverflow("paragraph indents exceed width")
  }
  let lines : Array[Line] = []
  let glyphs : Array[Glyph] = []
  let mut used = 0
  let mut size_max = 240
  let mut offset = left + first
  fn flush(
    lines : Array[Line],
    glyphs : Array[Glyph],
    used : Int,
    size_max : Int,
    offset : Int,
    p : @docx.ParagraphInfo,
  ) -> Unit raise PdfError {
    let natural = size_max * 13 / 10
    let height = match p.metadata.line_twips {
      Some(n) if p.metadata.line_rule == Some("exact") => n
      Some(n) if p.metadata.line_rule == Some("atLeast") => n.max(natural)
      Some(n) => natural * n / 240
      None => natural
    }
    guard height >= size_max else {
      raise LayoutOverflow("line spacing clips glyphs")
    }
    lines.push({ glyphs: glyphs.copy(), width: used, height, offset, })
    glyphs.clear()
  }
  for run in p.runs {
    guard !run.bold &&
      !run.italic &&
      !run.strike &&
      run.highlight is None &&
      (
        run.color is None ||
        run.color == Some("000000") ||
        run.color == Some("auto")
      ) else {
      raise Unsupported(
        "profile requires regular black text; styled font variants not yet supported",
      )
    }
    let size = run.font_size_half_points.unwrap_or(24) * 10
    guard size >= 100 && size <= 1440 else {
      raise Unsupported("font size outside profile")
    }
    let characters = run.text.iter().to_array()
    for character_index, c in characters {
      let code = c.to_int()
      if c == '\r' {
        continue
      }
      if c == '\n' {
        flush(lines, glyphs, used, size_max, offset, p)
        used = 0
        size_max = 240
        offset = left
        continue
      }
      guard (code >= 32 && code <= 126) ||
        (code >= 0x2000 && code <= 0x206f) ||
        (code >= 0x3000 && code <= 0x9fff) ||
        (code >= 0xff00 && code <= 0xffef) else {
        raise Unsupported(
          "complex-script/control character outside Chinese-Latin profile",
        )
      }
      let family = if code < 256 {
        run.font_ascii.unwrap_or(default_family)
      } else {
        run.font_east_asia.unwrap_or(default_family)
      }
      let index = face_index(faces, family)
      let g = faces[index].glyph(code)
      let advance = faces[index].advance(g, size)
      guard advance > 0 && advance <= available else {
        raise LayoutOverflow("glyph wider than content area")
      }
      let mut group_width = advance
      let latin_word_start = (c.is_ascii_alphabetic() || c.is_ascii_digit()) &&
        (
          character_index == 0 ||
          !(characters[character_index - 1].is_ascii_alphabetic() ||
          characters[character_index - 1].is_ascii_digit())
        )
      if latin_word_start {
        for next = character_index + 1
            next < characters.length()
            next = next + 1 {
          let nc = characters[next]
          if !(nc.is_ascii_alphabetic() || nc.is_ascii_digit()) {
            break
          }
          group_width += faces[index].advance(
            faces[index].glyph(nc.to_int()),
            size,
          )
        }
      } else if characters.get(character_index + 1) is Some(next) &&
        (
          "，。；：！？、）】》”’".contains(next.to_string()) ||
          "（【《“‘".contains(c.to_string())
        ) {
        let nf = if next.is_ascii() {
          run.font_ascii.unwrap_or(default_family)
        } else {
          run.font_east_asia.unwrap_or(default_family)
        }
        let ni = face_index(faces, nf)
        group_width += faces[ni].advance(faces[ni].glyph(next.to_int()), size)
      }
      let wrap_width = if group_width <= available {
        group_width
      } else {
        advance
      }
      if used > 0 &&
        offset - left + used + wrap_width > available &&
        !"，。；：！？、）】》”’".contains(c.to_string()) {
        flush(lines, glyphs, used, size_max, offset, p)
        used = 0
        size_max = 240
        offset = left
      }
      glyphs.push({
        face: index,
        code,
        size,
        x: used,
        advance,
        underline: run.underline,
      })
      used += advance
      size_max = size_max.max(size)
    }
  }
  if !glyphs.is_empty() || lines.is_empty() {
    flush(lines, glyphs, used, size_max, offset, p)
  }
  lines
}

///|
fn draw_lines(
  out : StringBuilder,
  lines : Array[Line],
  x : Int,
  top : Int,
  width : Int,
  align : String?,
) -> Int raise PdfError {
  guard align is None ||
    align == Some("left") ||
    align == Some("center") ||
    align == Some("right") ||
    align == Some("both") else {
    raise Unsupported("paragraph alignment requires unsupported justification")
  }
  let mut y = top
  for line_index, line in lines {
    let shift = match align {
      Some("center") => (width - line.offset - line.width) / 2
      Some("right") => width - line.offset - line.width
      _ => 0
    }
    let baseline = y - line.height * 4 / 5
    let justify = align == Some("both") && line_index < lines.length() - 1
    let mut gap_count = 0
    for i, g in line.glyphs {
      if i < line.glyphs.length() - 1 &&
        (g.code == 32 || g.code >= 0x3000 || line.glyphs[i + 1].code >= 0x3000) {
        gap_count += 1
      }
    }
    let extra = if justify && gap_count > 0 {
      (width - line.offset - line.width).max(0)
    } else {
      0
    }
    let mut gaps_seen = 0
    for i, g in line.glyphs {
      let gx = x +
        line.offset +
        shift +
        g.x +
        (if gap_count > 0 { extra * gaps_seen / gap_count } else { 0 })
      out.write_string(
        "BT /F\{g.face} \{g.size} Tf 1 0 0 1 \{gx} \{baseline} Tm <\{hex4(g.code)}> Tj ET\n",
      )
      if g.underline {
        out.write_string(
          "\{gx} \{baseline - g.size / 8} m \{gx + g.advance} \{baseline - g.size / 8} l S\n",
        )
      }
      if i < line.glyphs.length() - 1 &&
        (g.code == 32 || g.code >= 0x3000 || line.glyphs[i + 1].code >= 0x3000) {
        gaps_seen += 1
      }
    }
    y -= line.height
  }
  top - y
}

///|
fn stream(data : Bytes, extra? : String = "") -> Bytes {
  @utf8.encode("<< /Length \{data.length()} \{extra} >>\nstream\n") +
  data +
  b"\nendstream"
}

///|
fn pdf_bytes(
  pages : Array[String],
  width : Int,
  height : Int,
  faces : Array[Face],
) -> Bytes raise PdfError {
  let objects : Array[Bytes] = [b"<< /Type /Catalog /Pages 2 0 R >>", b""]
  let resource = StringBuilder()
  for i, face in faces {
    let base = objects.length() + 1
    resource.write_string("/F\{i} \{base} 0 R ")
    objects.push(
      @utf8.encode(
        "<< /Type /Font /Subtype /Type0 /BaseFont /MoonLeaf\{i} /Encoding /Identity-H /DescendantFonts [\{base + 1} 0 R] /ToUnicode \{base + 4} 0 R >>",
      ),
    )
    let widths = StringBuilder()
    let max_code = face.used.keys().fold(init=0, (a, b) => a.max(b))
    let map = @buffer.Buffer()
    for code in 0..<=max_code {
      map.write_uint16_be(face.used.get(code).unwrap_or(0).to_uint16())
    }
    for code, glyph in face.used {
      widths.write_string("\{code} [\{face.advance(glyph, 1000)}] ")
    }
    objects.push(
      @utf8.encode(
        "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /MoonLeaf\{i} /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor \{base + 2} 0 R /CIDToGIDMap \{base + 5} 0 R /DW 1000 /W [\{widths}] >>",
      ),
    )
    objects.push(
      @utf8.encode(
        "<< /Type /FontDescriptor /FontName /MoonLeaf\{i} /Flags 4 /FontBBox [-200 -300 1200 1200] /ItalicAngle 0 /Ascent 1000 /Descent -300 /CapHeight 700 /StemV 80 /FontFile2 \{base + 3} 0 R >>",
      ),
    )
    objects.push(
      stream(face.input.bytes, extra="/Length1 \{face.input.bytes.length()}"),
    )
    let cmap = StringBuilder()
    cmap.write_string(
      "/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def /CMapName /MoonLeaf def /CMapType 2 def 1 begincodespacerange <0000> <FFFF> endcodespacerange\n",
    )
    for code, _ in face.used {
      cmap.write_string(
        "1 beginbfchar <\{hex4(code)}> <\{hex4(code)}> endbfchar\n",
      )
    }
    cmap.write_string(
      "endcmap CMapName currentdict /CMap defineresource pop end end",
    )
    objects.push(stream(@utf8.encode(cmap.to_string())))
    objects.push(stream(map.to_bytes()))
  }
  let kids = StringBuilder()
  for page in pages {
    let n = objects.length() + 1
    kids.write_string("\{n} 0 R ")
    objects.push(
      @utf8.encode(
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \{width.to_double() / 20.0} \{height.to_double() / 20.0}] /Resources << /Font << \{resource} >> >> /Contents \{n + 1} 0 R >>",
      ),
    )
    objects.push(
      stream(@utf8.encode("q 0.05 0 0 0.05 0 0 cm 8 w\n" + page + "Q\n")),
    )
  }
  objects[1] = @utf8.encode(
    "<< /Type /Pages /Count \{pages.length()} /Kids [\{kids}] >>",
  )
  let out = @buffer.Buffer()
  out.write_bytes(b"%PDF-1.7\n%MoonLeaf\n")
  let offsets : Array[Int] = []
  for i, object in objects {
    offsets.push(out.length())
    out.write_string_utf8("\{i + 1} 0 obj\n")
    out.write_bytes(object)
    out.write_bytes(b"\nendobj\n")
  }
  let xref = out.length()
  out.write_string_utf8(
    "xref\n0 \{objects.length() + 1}\n0000000000 65535 f \n",
  )
  for offset in offsets {
    let s = offset.to_string()
    out.write_string_utf8("0".repeat(10 - s.length()) + s + " 00000 n \n")
  }
  out.write_string_utf8(
    "trailer << /Size \{objects.length() + 1} /Root 1 0 R >>\nstartxref\n\{xref}\n%%EOF\n",
  )
  out.to_bytes()
}

///|
/// Pure MoonLeaf layout and PDF emission. No system font substitution or external renderer.
pub fn render_docx_pdf(
  document_package : @opc.Package,
  fonts : Array[PdfFontInput],
  default_family~ : String,
) -> PdfDocument raise {
  guard fonts.length() > 0 && fonts.length() <= 16 else {
    raise InvalidFont("one to sixteen faces required")
  }
  let faces = fonts.map(font_face)
  ignore(face_index(faces, default_family))
  validate_profile(document_package)
  let preview = @docx.preview_document(numbered_document(document_package))
  let layouts = table_layouts(document_package)
  let mut table_index = 0
  guard preview.warnings.is_empty() &&
    preview.resources.is_empty() &&
    preview.headers.is_empty() &&
    preview.footers.is_empty() else {
    raise Unsupported(
      "warnings, images, external links, headers or footers require an expanded layout profile",
    )
  }
  let sections = preview.blocks.filter(block => block is @docx.FlowSection(_))
  guard sections.length() <= 1 else { raise Unsupported("multiple sections") }
  let section = preview.blocks.fold(init=None, (current, block) => {
    match block {
      @docx.FlowSection(s) => Some(s)
      _ => current
    }
  })
  let width = section
    .map(s => s.page_width_twips.unwrap_or(11906))
    .unwrap_or(11906)
  let height = section
    .map(s => s.page_height_twips.unwrap_or(16838))
    .unwrap_or(16838)
  let left = section
    .map(s => s.margin_left_twips.unwrap_or(1440))
    .unwrap_or(1440)
  let right = section
    .map(s => s.margin_right_twips.unwrap_or(1440))
    .unwrap_or(1440)
  let top = section.map(s => s.margin_top_twips.unwrap_or(1440)).unwrap_or(1440)
  let bottom = section
    .map(s => s.margin_bottom_twips.unwrap_or(1440))
    .unwrap_or(1440)
  let available = width - left - right
  guard width > 0 &&
    height > 0 &&
    width <= 40000 &&
    height <= 40000 &&
    left >= 0 &&
    right >= 0 &&
    top >= 0 &&
    bottom >= 0 &&
    available > 0 &&
    height - top - bottom > 0 else {
    raise LayoutOverflow("invalid page geometry")
  }
  let pages : Array[String] = []
  let mut out = StringBuilder()
  let mut y = height - top
  for block in preview.blocks {
    match block {
      @docx.FlowSection(_) => ()
      @docx.FlowPageBreak => {
        pages.push(out.to_string())
        out = StringBuilder()
        y = height - top
      }
      @docx.FlowParagraph(p) => {
        let lines = paragraph_lines(p, available, faces, default_family)
        let before = p.metadata.spacing_before_twips.unwrap_or(0).max(0)
        let after = p.metadata.spacing_after_twips.unwrap_or(0).max(0)
        let h = lines.fold(init=0, (h, l) => h + l.height)
        guard h + before + after <= height - top - bottom else {
          raise LayoutOverflow("paragraph exceeds page")
        }
        if y - h - before - after < bottom {
          pages.push(out.to_string())
          out = StringBuilder()
          y = height - top
        }
        y -= before
        y -= draw_lines(out, lines, left, y, available, p.metadata.alignment)
        y -= after
      }
      @docx.FlowTable(table) => {
        let layout = layouts[table_index]
        table_index += 1
        y -= layout.y_offset
        let table_x = layout.x.unwrap_or(left)
        guard table_x >= 0 && table_x < width else {
          raise LayoutOverflow("floating table x outside page")
        }
        for row in table.rows {
          let cell_lines : Array[Array[(Array[Line], @docx.ParagraphInfo)]] = []
          let widths : Array[Int] = []
          let content_heights : Array[Int] = []
          let mut column = 0
          let mut row_height = 0
          for cell in row.cells {
            guard cell.vertical_merge is None &&
              (
                cell.vertical_alignment is None ||
                cell.vertical_alignment == Some("top") ||
                cell.vertical_alignment == Some("center") ||
                cell.vertical_alignment == Some("bottom")
              ) else {
              raise Unsupported("vertical merged/aligned cells")
            }
            let mut w = 0
            for _ in 0..<cell.grid_span {
              w += table.grid_widths_twips
                .get(column)
                .unwrap_or(available / row.cells.length().max(1))
              column += 1
            }
            w = cell.width_twips.unwrap_or(w)
            let horizontal = cell.margin_left_twips.unwrap_or(layout.left) +
              cell.margin_right_twips.unwrap_or(layout.right)
            let vertical = cell.margin_top_twips.unwrap_or(layout.top) +
              cell.margin_bottom_twips.unwrap_or(layout.bottom)
            guard w > horizontal else {
              raise LayoutOverflow("table cell too narrow")
            }
            let pl : Array[(Array[Line], @docx.ParagraphInfo)] = []
            let mut h = vertical
            for p in cell.paragraphs {
              let lines = paragraph_lines(
                p,
                w - horizontal,
                faces,
                default_family,
              )
              h += lines.fold(init=0, (h, l) => h + l.height) +
                p.metadata.spacing_before_twips.unwrap_or(0).max(0) +
                p.metadata.spacing_after_twips.unwrap_or(0).max(0)
              pl.push((lines, p))
            }
            widths.push(w)
            content_heights.push(h)
            cell_lines.push(pl)
            row_height = row_height.max(h)
          }
          guard table_x + widths.fold(init=0, (a, b) => a + b) <= width else {
            raise LayoutOverflow("table wider than page")
          }
          if row.height_rule == Some("exact") &&
            row.height_twips.unwrap_or(row_height) < row_height {
            raise LayoutOverflow("exact row height clips text")
          }
          row_height = row_height.max(row.height_twips.unwrap_or(0))
          guard row_height <= height - top - bottom else {
            raise LayoutOverflow("row taller than page")
          }
          if y - row_height < bottom {
            pages.push(out.to_string())
            out = StringBuilder()
            y = height - top
          }
          let mut x = table_x
          for i, pl in cell_lines {
            let w = widths[i]
            if layout.border > 0 {
              out.write_string(
                "\{layout.border} w \{x} \{y - row_height} \{w} \{row_height} re S\n",
              )
            }
            let cell = row.cells[i]
            let horizontal = cell.margin_left_twips.unwrap_or(layout.left) +
              cell.margin_right_twips.unwrap_or(layout.right)
            let spare = row_height - content_heights[i]
            let shift = match cell.vertical_alignment {
              Some("center") => spare / 2
              Some("bottom") => spare
              _ => 0
            }
            let mut cy = y - cell.margin_top_twips.unwrap_or(layout.top) - shift
            for (lines, p) in pl {
              cy -= p.metadata.spacing_before_twips.unwrap_or(0).max(0)
              cy -= draw_lines(
                out,
                lines,
                x + cell.margin_left_twips.unwrap_or(layout.left),
                cy,
                w - horizontal,
                p.metadata.alignment,
              )
              cy -= p.metadata.spacing_after_twips.unwrap_or(0).max(0)
            }
            x += w
          }
          y -= row_height
        }
      }
    }
    guard pages.length() < 1000 else { raise LayoutOverflow("page limit") }
  }
  if !out.to_string().is_empty() || pages.is_empty() {
    pages.push(out.to_string())
  }
  { bytes: pdf_bytes(pages, width, height, faces), page_count: pages.length(), }
}
