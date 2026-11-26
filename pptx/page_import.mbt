///|
/// Pure MoonBit `.page` YAML parser, LaTeX-to-Unicode math normalizer, and
/// template-based PPTX builder (`build_presentation_from_pages`).

///|
fn page_color_value(val : String, default_hex : String) -> String {
  let s = val.trim().to_string()
  if s.is_empty() {
    return default_hex
  }
  let stripped = if (s.has_prefix("'") && s.has_suffix("'")) ||
    (s.has_prefix("\"") && s.has_suffix("\"")) {
    if s.length() >= 2 {
      s[1:s.length() - 1].to_string()
    } else {
      s
    }
  } else {
    s
  }
  match stripped {
    "$paper" => "F4F0E7"
    "$ink" => "252925"
    "$green" => "365A50"
    "$muted" => "777970"
    "$line" => "C8C5BB"
    "$light" => "E4E6DD"
    "$white" => "FFFFFF"
    "$blue" => "2F5597"
    _ => {
      let hex = if stripped.has_prefix("#") {
        stripped[1:].to_string()
      } else {
        stripped
      }
      if hex.length() == 6 {
        let mut ok = true
        for c in hex {
          if !(c >= '0' && c <= '9') &&
            !(c >= 'a' && c <= 'f') &&
            !(c >= 'A' && c <= 'F') {
            ok = false
            break
          }
        }
        if ok {
          hex.to_upper()
        } else {
          default_hex
        }
      } else {
        default_hex
      }
    }
  }
}

///|
fn page_parse_number(s : String) -> Double? {
  if s.is_empty() {
    return None
  }
  let mut idx = 0
  let mut sign = 1.0
  if s.has_prefix("-") {
    sign = -1.0
    idx = 1
  } else if s.has_prefix("+") {
    idx = 1
  }
  if idx >= s.length() {
    return None
  }
  let mut int_part = 0.0
  let mut frac_part = 0.0
  let mut frac_div = 1.0
  let mut seen_dot = false
  let mut seen_digit = false
  let chars = s.to_array()
  while idx < chars.length() {
    let c = chars[idx]
    if c >= '0' && c <= '9' {
      seen_digit = true
      let d = (c.to_int() - '0'.to_int()).to_double()
      if seen_dot {
        frac_div *= 10.0
        frac_part += d / frac_div
      } else {
        int_part = int_part * 10.0 + d
      }
    } else if c == '.' && !seen_dot {
      seen_dot = true
    } else {
      return None
    }
    idx += 1
  }
  if !seen_digit {
    None
  } else {
    Some(sign * (int_part + frac_part))
  }
}

///|
fn page_parse_scalar(raw : String) -> Json {
  let s = raw.trim().to_owned()
  if s == "true" || s == "True" {
    return Json::boolean(true)
  }
  if s == "false" || s == "False" {
    return Json::boolean(false)
  }
  if s == "null" || s == "~" || s.is_empty() {
    return Json::null()
  }
  if s.length() >= 2 &&
    (
      (s.has_prefix("'") && s.has_suffix("'")) ||
      (s.has_prefix("\"") && s.has_suffix("\""))
    ) {
    return Json::string(s[1:s.length() - 1].to_owned())
  }
  match page_parse_number(s) {
    Some(num) => Json::number(num)
    None => Json::string(s)
  }
}

///|
fn page_split_kv(line : String) -> (String, String)? {
  match line.find(":") {
    Some(idx) => {
      let k = line[:idx].to_string().trim().to_string()
      let v = line[idx + 1:].to_string().trim().to_string()
      Some((k, v))
    }
    None => None
  }
}

///|
fn page_unclosed_quote(v : String) -> Char? {
  if v.has_prefix("'") && !(v.length() > 1 && v.has_suffix("'")) {
    Some('\'')
  } else if v.has_prefix("\"") && !(v.length() > 1 && v.has_suffix("\"")) {
    Some('"')
  } else {
    None
  }
}

///|
fn page_consume_multiline(
  lines : Array[(Int32, String)],
  start_idx : Int32,
  first : String,
  quote : Char,
) -> (String, Int32) {
  let buf = StringBuilder::new()
  buf.write_string(first[1:].to_string())
  let mut idx = start_idx + 1
  let q_str = quote.to_string()
  while idx < lines.length() {
    let (_, cur) = lines[idx]
    idx += 1
    buf.write_char('\n')
    if cur.has_suffix(q_str) {
      if cur.length() >= 1 {
        buf.write_string(cur[:cur.length() - 1].to_string())
      }
      break
    }
    buf.write_string(cur)
  }
  (buf.to_string(), idx)
}

///|
fn page_parse_block(
  lines : Array[(Int32, String)],
  start_idx : Int32,
) -> (Json, Int32) {
  if start_idx >= lines.length() {
    return (Json::null(), start_idx)
  }
  let (first_indent, first_text) = lines[start_idx]
  if first_text.has_prefix("- ") || first_text == "-" {
    let arr : Array[Json] = []
    let mut idx = start_idx
    while idx < lines.length() &&
          lines[idx].0 == first_indent &&
          (lines[idx].1.has_prefix("- ") || lines[idx].1 == "-") {
      let item_str = if lines[idx].1 == "-" {
        ""
      } else {
        lines[idx].1[2:].to_string().trim().to_string()
      }
      if item_str.is_empty() {
        let (child, next_idx) = page_parse_block(lines, idx + 1)
        arr.push(child)
        idx = next_idx
      } else if item_str.contains(":") &&
        !item_str.has_prefix("'") &&
        !item_str.has_prefix("\"") {
        let obj : Map[String, Json] = {}
        match page_split_kv(item_str) {
          Some((k, v)) => {
            if v.is_empty() {
              let (child, next_idx) = page_parse_block(lines, idx + 1)
              obj[k] = child
              idx = next_idx
            } else {
              match page_unclosed_quote(v) {
                Some(q) => {
                  let (s, next_idx) = page_consume_multiline(lines, idx, v, q)
                  obj[k] = Json::string(s)
                  idx = next_idx
                }
                None => {
                  obj[k] = page_parse_scalar(v)
                  idx += 1
                }
              }
            }
            while idx < lines.length() && lines[idx].0 > first_indent {
              match page_split_kv(lines[idx].1) {
                None => idx += 1
                Some((sk, sv)) =>
                  if sv.is_empty() {
                    let (child, next_idx) = page_parse_block(lines, idx + 1)
                    obj[sk] = child
                    idx = next_idx
                  } else {
                    match page_unclosed_quote(sv) {
                      Some(q) => {
                        let (s, next_idx) = page_consume_multiline(
                          lines, idx, sv, q,
                        )
                        obj[sk] = Json::string(s)
                        idx = next_idx
                      }
                      None => {
                        obj[sk] = page_parse_scalar(sv)
                        idx += 1
                      }
                    }
                  }
              }
            }
          }
          None => idx += 1
        }
        arr.push(Json::object(obj))
      } else {
        arr.push(page_parse_scalar(item_str))
        idx += 1
      }
    }
    (Json::array(arr), idx)
  } else {
    let obj : Map[String, Json] = {}
    let mut idx = start_idx
    while idx < lines.length() &&
          lines[idx].0 == first_indent &&
          !lines[idx].1.has_prefix("- ") {
      match page_split_kv(lines[idx].1) {
        None => idx += 1
        Some((k, v)) =>
          if v.is_empty() {
            let (child, next_idx) = page_parse_block(lines, idx + 1)
            obj[k] = child
            idx = next_idx
          } else {
            match page_unclosed_quote(v) {
              Some(q) => {
                let (s, next_idx) = page_consume_multiline(lines, idx, v, q)
                obj[k] = Json::string(s)
                idx = next_idx
              }
              None => {
                obj[k] = page_parse_scalar(v)
                idx += 1
              }
            }
          }
      }
    }
    (Json::object(obj), idx)
  }
}

///|
/// Parse an indentation-based `.page` YAML document into a `Json` object.
pub fn parse_page_yaml(text : String) -> Json {
  let lines : Array[(Int32, String)] = []
  for raw_view in text.split("\n") {
    let raw = raw_view.to_string().trim_end(chars="\r").to_string()
    let trimmed = raw.trim().to_string()
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    let mut indent = 0
    for c in raw {
      if c == ' ' {
        indent += 1
      } else {
        break
      }
    }
    if trimmed.has_prefix("- - ") {
      lines.push((indent, "-"))
      lines.push((indent + 2, trimmed[2:].to_owned()))
    } else {
      lines.push((indent, trimmed))
    }
  }
  let (parsed, _) = page_parse_block(lines, 0)
  parsed
}

///|
/// Convert inline LaTeX math `\\(...\\)` to clean Unicode math typography.
pub fn clean_latex_math(text : String) -> String {
  if !text.contains("\\(") {
    return text
  }
  text
  .replace_all(old="\\(", new="")
  .replace_all(old="\\)", new="")
  .replace_all(old="\\frac{\\partial P}{\\partial D}", new="∂P/∂D")
  .replace_all(old="\\frac{\\beta D^2}{Q}", new="βD²/Q")
  .replace_all(old="\\frac{2\\beta D}{Q}", new="2βD/Q")
  .replace_all(old="\\alpha D", new="αD")
  .replace_all(old="\\alpha", new="α")
  .replace_all(old="\\beta", new="β")
  .replace_all(old="\\gamma", new="γ")
  .replace_all(old="D^2", new="D²")
  .replace_all(old="D Q", new="DQ")
  .replace_all(old="=", new=" = ")
  .replace_all(old="-", new=" − ")
}

///|
fn page_json_bounds(el : Json) -> (Double, Double, Double, Double) {
  match pptx_json_field(el, "bounds") {
    Array(arr) if arr.length() >= 4 => {
      let n = fn(v : Json, d : Double) -> Double {
        match v {
          Number(x, ..) => x
          _ => d
        }
      }
      (n(arr[0], 40.0), n(arr[1], 100.0), n(arr[2], 200.0), n(arr[3], 40.0))
    }
    _ => (40.0, 100.0, 200.0, 40.0)
  }
}

///|
fn page_map_bounds(
  bx : Double,
  by : Double,
  bw : Double,
  bh : Double,
) -> (Int32, Int32, Int32, Int32) {
  let emu = 12700.0
  let y_norm = (by - 20.0) / 485.0
  let ny = 84.0 + y_norm * 402.0
  let nh = {
    let scaled = bh * (402.0 / 485.0)
    if scaled < 8.0 {
      8.0
    } else {
      scaled
    }
  }
  let nx = 28.0 + bx / 960.0 * 904.0
  let nw = {
    let scaled = bw * (904.0 / 960.0)
    if scaled < 4.0 {
      4.0
    } else {
      scaled
    }
  }
  (
    (nx * emu).to_int(),
    (ny * emu).to_int(),
    (nw * emu).to_int(),
    (nh * emu).to_int(),
  )
}

///|
fn page_text_runs(
  text : String,
  sz_pt : Double,
  color_hex : String,
  bold : Bool,
  align_xml : String,
) -> String {
  let cleaned = clean_latex_math(text).replace_all(old="\r\n", new="\n")
  let sz = {
    let raw = (sz_pt * 82.0).round().to_int()
    if raw < 700 {
      700
    } else {
      raw
    }
  }
  let b_attr = if bold { " b=\"1\"" } else { "" }
  let rpr = "<a:rPr lang=\"zh-CN\" altLang=\"en-US\" sz=\"\{sz}\"\{b_attr} dirty=\"0\"><a:solidFill><a:srgbClr val=\"\{color_hex}\"/></a:solidFill><a:latin typeface=\"Microsoft YaHei\"/><a:ea typeface=\"Microsoft YaHei\"/><a:cs typeface=\"Microsoft YaHei\"/></a:rPr>"
  let ppr = if align_xml.is_empty() {
    ""
  } else {
    "<a:pPr algn=\"\{align_xml}\"/>"
  }
  let buf = StringBuilder::new()
  for line_view in cleaned.split("\n") {
    let line = line_view.to_string()
    buf.write_string(
      "<a:p>\{ppr}<a:r>\{rpr}<a:t>\{@xml.escape_text(line)}</a:t></a:r></a:p>",
    )
  }
  buf.to_string()
}

///|
fn page_json_double(v : Json, key : String, default_val : Double) -> Double {
  match pptx_json_field(v, key) {
    Number(n, ..) => n
    _ => default_val
  }
}

///|
fn page_json_bool(v : Json, key : String, default_val : Bool) -> Bool {
  match pptx_json_field(v, key) {
    True => true
    False => false
    _ => default_val
  }
}

///|
fn page_basename(path : String) -> String {
  match pptx_rfind(path, "/") {
    Some(idx) => path[idx + 1:].to_string()
    None => path
  }
}

///|
fn page_u16_be(bytes : FixedArray[Byte], offset : Int32) -> Int32 {
  (bytes[offset].to_int() << 8) | bytes[offset + 1].to_int()
}

///|
fn page_u32_be(bytes : FixedArray[Byte], offset : Int32) -> Int32 {
  (bytes[offset].to_int() << 24) |
  (bytes[offset + 1].to_int() << 16) |
  (bytes[offset + 2].to_int() << 8) |
  bytes[offset + 3].to_int()
}

///|
fn page_image_dimensions(bytes : FixedArray[Byte]) -> (Int32, Int32)? {
  let len = bytes.length()
  if len >= 24 &&
    bytes[0] == b'\x89' &&
    bytes[1] == b'P' &&
    bytes[2] == b'N' &&
    bytes[3] == b'G' {
    let iw = page_u32_be(bytes, 16)
    let ih = page_u32_be(bytes, 20)
    if iw > 0 && ih > 0 {
      return Some((iw, ih))
    }
  }
  if len >= 4 && bytes[0] == b'\xFF' && bytes[1] == b'\xD8' {
    let mut i = 2
    while i + 8 < len {
      if bytes[i] != b'\xFF' {
        i += 1
        continue
      }
      let marker = bytes[i + 1].to_int()
      if marker == 0xD9 || marker == 0xDA {
        break
      }
      if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 || marker == 0xC3 {
        let ih = page_u16_be(bytes, i + 5)
        let iw = page_u16_be(bytes, i + 7)
        if iw > 0 && ih > 0 {
          return Some((iw, ih))
        }
        break
      }
      let seg_len = page_u16_be(bytes, i + 2)
      if seg_len < 2 {
        break
      }
      i += 2 + seg_len
    }
  }
  None
}

///|
pub fn page_contain_rect(
  x : Int32,
  y : Int32,
  w : Int32,
  h : Int32,
  iw : Int32,
  ih : Int32,
) -> (Int32, Int32, Int32, Int32) {
  if iw <= 0 || ih <= 0 || w <= 0 || h <= 0 {
    return (x, y, w, h)
  }
  let sx = w.to_double() / iw.to_double()
  let sy = h.to_double() / ih.to_double()
  let scale = if sx < sy { sx } else { sy }
  let nw = (iw.to_double() * scale).round().to_int()
  let nh = (ih.to_double() * scale).round().to_int()
  let nx = x + (w - nw) / 2
  let ny = y + (h - nh) / 2
  (nx, ny, nw, nh)
}

///|
fn page_build_element(
  el : Json,
  sp_id : Int32,
  media : Map[String, FixedArray[Byte]],
  next_rid : () -> String,
) -> (String, (String, String, String, String)?) {
  let etype = pptx_json_string(el, "elementType").unwrap_or("")
  let (bx, by, bw, bh) = page_json_bounds(el)
  let (x, y, w, h) = page_map_bounds(bx, by, bw, bh)
  match etype {
    "shape" => {
      let fill = pptx_json_field(el, "fill")
      let fill_xml = match pptx_json_string(fill, "color") {
        Some(c) =>
          "<a:solidFill><a:srgbClr val=\"\{page_color_value(c, "FFFFFF")}\"/></a:solidFill>"
        None => "<a:noFill/>"
      }
      let border = pptx_json_field(el, "border")
      let ln_xml = match pptx_json_string(border, "color") {
        Some(c) => {
          let bw_emu = (page_json_double(border, "width", 1.0) * 12700.0).to_int()
          "<a:ln w=\"\{bw_emu}\"><a:solidFill><a:srgbClr val=\"\{page_color_value(c, "C8C5BB")}\"/></a:solidFill></a:ln>"
        }
        None => "<a:ln><a:noFill/></a:ln>"
      }
      let prst = if pptx_json_string(el, "shapeName").unwrap_or("") ==
        "roundRect" {
        "roundRect"
      } else {
        "rect"
      }
      (
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\{sp_id}\" name=\"Shape \{sp_id}\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{x}\" y=\"\{y}\"/><a:ext cx=\"\{w}\" cy=\"\{h}\"/></a:xfrm><a:prstGeom prst=\"\{prst}\"><a:avLst/></a:prstGeom>\{fill_xml}\{ln_xml}</p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang=\"zh-CN\"/></a:p></p:txBody></p:sp>",
        None,
      )
    }
    "line" => {
      if by >= 500.0 {
        return ("", None)
      }
      let stroke = pptx_json_field(el, "stroke")
      let sc = page_color_value(
        pptx_json_string(stroke, "color").unwrap_or(""),
        "C8C5BB",
      )
      let sw = (page_json_double(stroke, "width", 1.0) * 12700.0).to_int()
      (
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\{sp_id}\" name=\"Line \{sp_id}\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{x}\" y=\"\{y}\"/><a:ext cx=\"\{w}\" cy=\"\{h}\"/></a:xfrm><a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom><a:ln w=\"\{sw}\"><a:solidFill><a:srgbClr val=\"\{sc}\"/></a:solidFill></a:ln></p:spPr></p:sp>",
        None,
      )
    }
    "text" => {
      let c = pptx_json_field(el, "content")
      let text = pptx_json_string(c, "text").unwrap_or("")
      if text.trim().to_string().is_empty() {
        return ("", None)
      }
      if (by < 24.0 && bx > 650.0) || by >= 505.0 {
        return ("", None)
      }
      let sz_pt = page_json_double(c, "fontSize", 12.0)
      let col = page_color_value(
        pptx_json_string(c, "color").unwrap_or(""),
        "252925",
      )
      let bold = page_json_bool(c, "bold", false)
      let align_val = match pptx_json_field(c, "align") {
        Array(arr) if !arr.is_empty() =>
          match arr[0] {
            String("center") => "ctr"
            String("right") => "r"
            _ => "l"
          }
        _ => "l"
      }
      let paras = page_text_runs(text, sz_pt, col, bold, align_val)
      (
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\{sp_id}\" name=\"Text \{sp_id}\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{x}\" y=\"\{y}\"/><a:ext cx=\"\{w}\" cy=\"\{h}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"36000\" tIns=\"18000\" rIns=\"36000\" bIns=\"18000\"/><a:lstStyle/>\{paras}</p:txBody></p:sp>",
        None,
      )
    }
    "table" => {
      let rows = match pptx_json_field(el, "rows") {
        Array(arr) if !arr.is_empty() => arr
        _ => return ("", None)
      }
      let mut ncols = 1
      for row in rows {
        match row {
          Array(cells) if cells.length() > ncols => ncols = cells.length()
          _ => ()
        }
      }
      let col_widths : Array[Double] = []
      match pptx_json_field(el, "columnWidths") {
        Array(cw_arr) if cw_arr.length() == ncols =>
          for item in cw_arr {
            match item {
              Number(v, ..) if v > 0.0 => col_widths.push(v)
              _ => col_widths.push(1.0 / ncols.to_double())
            }
          }
        _ =>
          for _ in 0..<ncols {
            col_widths.push(1.0 / ncols.to_double())
          }
      }
      let row_heights : Array[Double] = []
      match pptx_json_field(el, "rowHeights") {
        Array(rh_arr) if rh_arr.length() == rows.length() =>
          for item in rh_arr {
            match item {
              Number(v, ..) if v > 0.0 => row_heights.push(v)
              _ => row_heights.push(1.0 / rows.length().to_double())
            }
          }
        _ =>
          for _ in 0..<rows.length() {
            row_heights.push(1.0 / rows.length().to_double())
          }
      }
      let cells_buf = StringBuilder()
      let mut cur_y = y
      let mut cell_seq = 0
      for r_idx, row in rows {
        guard row is Array(cells) else { continue }
        let rh = {
          let raw = (h.to_double() * row_heights[r_idx]).to_int()
          if raw < 1 {
            1
          } else {
            raw
          }
        }
        let is_hdr = r_idx == 0
        let bg = if is_hdr {
          "365A50"
        } else if r_idx % 2 == 1 {
          "FFFFFF"
        } else {
          "F4F0E7"
        }
        let fg = if is_hdr { "FFFFFF" } else { "252925" }
        let mut cur_x = x
        for c_idx in 0..<ncols {
          let cw = {
            let raw = (w.to_double() * col_widths[c_idx]).to_int()
            if raw < 1 {
              1
            } else {
              raw
            }
          }
          let (cell_text, cell_sz, cell_bold, cell_align) = if c_idx <
            cells.length() {
            match cells[c_idx] {
              { "text": String(t), .. } as cell_obj => {
                let sz = page_json_double(cell_obj, "fontSize", 14.0)
                let b = page_json_bool(cell_obj, "bold", is_hdr)
                let al = match pptx_json_field(cell_obj, "align") {
                  Array(arr) if !arr.is_empty() =>
                    match arr[0] {
                      String("center") => "ctr"
                      String("right") => "r"
                      _ => "l"
                    }
                  _ => "l"
                }
                (t, sz, b, al)
              }
              String(s) => (s, 14.0, is_hdr, "l")
              Number(n, ..) => (n.to_string(), 14.0, is_hdr, "l")
              _ => ("", 14.0, is_hdr, "l")
            }
          } else {
            ("", 14.0, is_hdr, "l")
          }
          let paras = page_text_runs(
            cell_text, cell_sz, fg, cell_bold, cell_align,
          )
          let cid = sp_id * 100 + cell_seq
          cell_seq += 1
          cells_buf.write_string(
            "<p:sp><p:nvSpPr><p:cNvPr id=\"\{cid}\" name=\"Cell \{cid}\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{cur_x}\" y=\"\{cur_y}\"/><a:ext cx=\"\{cw}\" cy=\"\{rh}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"\{bg}\"/></a:solidFill><a:ln w=\"6350\"><a:solidFill><a:srgbClr val=\"C8C5BB\"/></a:solidFill></a:ln></p:spPr><p:txBody><a:bodyPr wrap=\"square\" anchor=\"ctr\" lIns=\"45720\" tIns=\"22860\" rIns=\"45720\" bIns=\"22860\"/><a:lstStyle/>\{paras}</p:txBody></p:sp>",
          )
          cur_x += cw
        }
        cur_y += rh
      }
      (cells_buf.to_string(), None)
    }
    "image" => {
      let src = pptx_json_string(el, "src").unwrap_or("")
      if src.is_empty() {
        return ("", None)
      }
      let rel_src = if src.has_prefix("/") { src[1:].to_string() } else { src }
      let base = page_basename(rel_src)
      let media_name = "media/page_" + base
      let rid = next_rid()
      let (px, py, pw, ph) = match media.get(rel_src) {
        Some(img_bytes) =>
          match page_image_dimensions(img_bytes) {
            Some((iw, ih)) => page_contain_rect(x, y, w, h, iw, ih)
            None => (x, y, w, h)
          }
        None => (x, y, w, h)
      }
      (
        "<p:pic><p:nvPicPr><p:cNvPr id=\"\{sp_id}\" name=\"Image \{sp_id}\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\{rid}\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\{px}\" y=\"\{py}\"/><a:ext cx=\"\{pw}\" cy=\"\{ph}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>",
        Some((rid, "../" + media_name, rel_src, "ppt/" + media_name)),
      )
    }
    _ => ("", None)
  }
}

///|
fn page_replace_tag_block(
  source : String,
  open_tag : String,
  close_tag : String,
  replacement : String,
) -> String {
  match source.find(open_tag) {
    Some(start) =>
      match source[start:].to_string().find(close_tag) {
        Some(rel_end) =>
          pptx_splice(
            source,
            start,
            start + rel_end + close_tag.length(),
            replacement,
          )
        None => source
      }
    None => source
  }
}

///|
fn page_strip_slide_overrides(ct_xml : String) -> String {
  let buf = StringBuilder::new()
  let mut pos = 0
  while pos < ct_xml.length() {
    match ct_xml[pos:].to_string().find("<Override ") {
      None => {
        buf.write_string(ct_xml[pos:].to_string())
        break
      }
      Some(rel_start) => {
        let start = pos + rel_start
        buf.write_string(ct_xml[pos:start].to_string())
        match ct_xml[start:].to_string().find("/>") {
          None => {
            buf.write_string(ct_xml[start:].to_string())
            break
          }
          Some(rel_end) => {
            let tag = ct_xml[start:start + rel_end + 2].to_string()
            if !tag.contains("/ppt/slides/") &&
              !tag.contains("/ppt/notesSlides/") {
              buf.write_string(tag)
            }
            pos = start + rel_end + 2
          }
        }
      }
    }
  }
  buf.to_string()
}

///|
fn page_strip_slide_rels(rels_xml : String) -> String {
  let buf = StringBuilder::new()
  let mut pos = 0
  while pos < rels_xml.length() {
    match rels_xml[pos:].to_string().find("<Relationship ") {
      None => {
        buf.write_string(rels_xml[pos:].to_string())
        break
      }
      Some(rel_start) => {
        let start = pos + rel_start
        buf.write_string(rels_xml[pos:start].to_string())
        match rels_xml[start:].to_string().find("/>") {
          None => {
            buf.write_string(rels_xml[start:].to_string())
            break
          }
          Some(rel_end) => {
            let tag = rels_xml[start:start + rel_end + 2].to_string()
            if !tag.contains("relationships/slide\"") {
              buf.write_string(tag)
            }
            pos = start + rel_end + 2
          }
        }
      }
    }
  }
  buf.to_string()
}

///|
fn page_template_slide_for_index(pnum : Int32) -> String {
  if pnum == 1 {
    "ppt/slides/slide1.xml"
  } else if pnum >= 2 && pnum <= 6 {
    "ppt/slides/slide4.xml"
  } else if pnum >= 7 && pnum <= 15 {
    "ppt/slides/slide7.xml"
  } else if pnum >= 16 && pnum <= 23 {
    "ppt/slides/slide9.xml"
  } else if pnum == 24 {
    "ppt/slides/slide11.xml"
  } else {
    "ppt/slides/slide12.xml"
  }
}

///|
/// Build a complete `.pptx` presentation in pure MoonBit by merging an array of
/// `.page` YAML contents, speaker notes, and media bytes into a template `.pptx`.
pub fn build_presentation_from_pages(
  template_bytes : FixedArray[Byte],
  pages : Array[String],
  notes : Array[String],
  media : Map[String, FixedArray[Byte]],
) -> FixedArray[Byte] raise PptxError {
  let tpl = @opc.open(template_bytes) catch {
    _ => raise InvalidPresentation(message="failed to open template pptx")
  }
  let mut pkg = tpl
  let pres_rels_extra = StringBuilder::new()
  let sld_id_list = StringBuilder::new()
  let ct_overrides = StringBuilder::new()
  for idx, page_yaml in pages {
    let pnum = idx + 1
    let tpl_part = page_template_slide_for_index(pnum)
    let tpl_rels_part = pptx_rels_path(tpl_part)
    let slide_part = "ppt/slides/slide\{pnum}.xml"
    let slide_rels_part = pptx_rels_path(slide_part)
    let mut slide_xml = tpl.text(tpl_part) catch {
      _ => raise InvalidPackagePart(part=tpl_part)
    }
    let mut rels_xml = if tpl.has_part(tpl_rels_part) {
      tpl.text(tpl_rels_part) catch {
        _ => raise InvalidPackagePart(part=tpl_rels_part)
      }
    } else {
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"></Relationships>"
    }
    if pnum == 1 {
      let cover_title = "<p:sp><p:nvSpPr><p:cNvPr id=\"201\" name=\"CoverTitle\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"812800\" y=\"1500000\"/><a:ext cx=\"10500000\" cy=\"1050000\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/><a:lstStyle/><a:p><a:r><a:rPr lang=\"zh-CN\" altLang=\"en-US\" sz=\"2800\" b=\"1\" dirty=\"0\"><a:solidFill><a:srgbClr val=\"2F5597\"/></a:solidFill><a:latin typeface=\"Microsoft YaHei\"/><a:ea typeface=\"Microsoft YaHei\"/></a:rPr><a:t>OPC的发展及其成功因素：组织结构、扩张机制与评估方法</a:t></a:r></a:p></p:txBody></p:sp>"
      let cover_line = "<p:sp><p:nvSpPr><p:cNvPr id=\"202\" name=\"CoverLine\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"812800\" y=\"2680000\"/><a:ext cx=\"3200000\" cy=\"0\"/></a:xfrm><a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom><a:ln w=\"25400\"><a:solidFill><a:srgbClr val=\"2F5597\"/></a:solidFill></a:ln></p:spPr></p:sp>"
      let cover_sub = "<p:sp><p:nvSpPr><p:cNvPr id=\"203\" name=\"CoverSub\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"812800\" y=\"2840000\"/><a:ext cx=\"10500000\" cy=\"450000\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/><a:lstStyle/><a:p><a:r><a:rPr lang=\"zh-CN\" altLang=\"en-US\" sz=\"1800\" b=\"1\" dirty=\"0\"><a:solidFill><a:srgbClr val=\"252925\"/></a:solidFill><a:latin typeface=\"Microsoft YaHei\"/><a:ea typeface=\"Microsoft YaHei\"/></a:rPr><a:t>汪凯棋｜上海交大—新加坡管理大学 DBA｜开题答辩</a:t></a:r></a:p></p:txBody></p:sp>"
      slide_xml = page_replace_tag_block(
        slide_xml,
        "<p:grpSp>",
        "</p:grpSp>",
        cover_title + cover_line + cover_sub,
      ).replace_all(old=">学员名字<", new=">汇报人：汪凯棋<")
    } else if pnum == pages.length() && pages.length() == 25 {
      slide_xml = slide_xml.replace_all(
        old="<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr>",
        new="<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr>",
      )
    } else {
      let page_data = parse_page_yaml(page_yaml)
      let elements = match pptx_json_field(page_data, "elements") {
        Array(arr) => arr
        _ => []
      }
      let shapes_buf = StringBuilder::new()
      let mut rid_counter = 10
      let next_rid = fn() -> String {
        rid_counter += 1
        "rId" + rid_counter.to_string()
      }
      for ei, el in elements {
        let (xml_piece, rel_opt) = page_build_element(
          el,
          100 + ei,
          media,
          next_rid,
        )
        if !xml_piece.is_empty() {
          shapes_buf.write_string(xml_piece)
        }
        match rel_opt {
          Some((rid, target, src_key, pkg_path)) =>
            match media.get(src_key) {
              Some(img_bytes) => {
                pkg = pkg.replace_part(pkg_path, img_bytes)
                rels_xml = rels_xml.replace_all(
                  old="</Relationships>",
                  new="<Relationship Id=\"\{rid}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\{target}\"/></Relationships>",
                )
              }
              None => ()
            }
          None => ()
        }
      }
      slide_xml = slide_xml.replace_all(
        old="</p:spTree>",
        new=shapes_buf.to_string() + "</p:spTree>",
      )
    }
    let note_text = if idx < notes.length() { notes[idx] } else { "" }
    if !note_text.trim().to_string().is_empty() {
      let notes_part = "ppt/notesSlides/notesSlide\{pnum}.xml"
      let notes_rels_part = pptx_rels_path(notes_part)
      pkg = pkg.replace_text(notes_part, pptx_notes_xml(note_text))
      let notes_master_rel = if pkg.has_part(
          "ppt/notesMasters/notesMaster1.xml",
        ) {
        "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" Target=\"../notesMasters/notesMaster1.xml\"/>"
      } else {
        ""
      }
      let notes_rels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"../slides/slide\{pnum}.xml\"/>\{notes_master_rel}</Relationships>"
      pkg = pkg.replace_text(notes_rels_part, notes_rels)
      rels_xml = rels_xml.replace_all(
        old="</Relationships>",
        new="<Relationship Id=\"rId99\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide\" Target=\"../notesSlides/notesSlide\{pnum}.xml\"/></Relationships>",
      )
      ct_overrides.write_string(
        "<Override PartName=\"/\{notes_part}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml\"/>",
      )
    }
    pkg = pkg.replace_text(slide_part, slide_xml)
    pkg = pkg.replace_text(slide_rels_part, rels_xml)
    ct_overrides.write_string(
      "<Override PartName=\"/\{slide_part}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>",
    )
    let pres_rid = "rId" + (100 + pnum).to_string()
    pres_rels_extra.write_string(
      "<Relationship Id=\"\{pres_rid}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\{pnum}.xml\"/>",
    )
    sld_id_list.write_string(
      "<p:sldId id=\"\{255 + pnum}\" r:id=\"\{pres_rid}\"/>",
    )
  }
  let ct = tpl.text("[Content_Types].xml") catch {
    _ => raise InvalidPackagePart(part="[Content_Types].xml")
  }
  let updated_ct = page_strip_slide_overrides(ct).replace_all(
    old="</Types>",
    new=ct_overrides.to_string() + "</Types>",
  )
  pkg = pkg.replace_text("[Content_Types].xml", updated_ct)
  let prels = tpl.text("ppt/_rels/presentation.xml.rels") catch {
    _ => raise InvalidPackagePart(part="ppt/_rels/presentation.xml.rels")
  }
  let updated_prels = page_strip_slide_rels(prels).replace_all(
    old="</Relationships>",
    new=pres_rels_extra.to_string() + "</Relationships>",
  )
  pkg = pkg.replace_text("ppt/_rels/presentation.xml.rels", updated_prels)
  let pres = tpl.text("ppt/presentation.xml") catch {
    _ => raise InvalidPackagePart(part="ppt/presentation.xml")
  }
  let updated_pres = page_replace_tag_block(
    pres,
    "<p:sldIdLst>",
    "</p:sldIdLst>",
    "<p:sldIdLst>" + sld_id_list.to_string() + "</p:sldIdLst>",
  )
  pkg = pkg.replace_text("ppt/presentation.xml", updated_pres)
  @opc.save(pkg) catch {
    _ => raise InvalidPresentation(message="failed to save built presentation")
  }
}
