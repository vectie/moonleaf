///|
pub(all) suberror PdfError {
  Unsupported(String)
  InvalidFont(String)
  LayoutOverflow(String)
} derive(Debug, Eq)

///|
/// A deployment must separately establish its license to embed these bytes.
pub(all) struct PdfFontInput {
  family : String
  bytes : Bytes
} derive(Debug)

///|
priv struct Face {
  input : PdfFontInput
  units : Int
  metrics : Int
  metric_count : Int
  glyph_count : Int
  cmap : Int
  cmap_format : Int
  used : Map[Int, Int]
}

///|
fn u16(b : Bytes, p : Int) -> Int raise PdfError {
  guard p >= 0 && p <= b.length() - 2 else {
    raise InvalidFont("truncated font table")
  }
  b[p].to_int() * 256 + b[p + 1].to_int()
}

///|
fn u32(b : Bytes, p : Int) -> Int raise PdfError {
  let hi = u16(b, p)
  guard hi < 32768 else { raise InvalidFont("font offset exceeds bound") }
  hi * 65536 + u16(b, p + 2)
}

///|
fn font_face(input : PdfFontInput) -> Face raise PdfError {
  let b = input.bytes
  guard b.length() <= 64 * 1024 * 1024 && u32(b, 0) == 65536 else {
    raise InvalidFont(
      "only bounded static TrueType glyf fonts supported; not CFF/TTC",
    )
  }
  let tables : Map[String, Int] = Map([])
  let count = u16(b, 4)
  guard count <= 256 && b.length() >= 12 + count * 16 else {
    raise InvalidFont("invalid font table directory")
  }
  for i in 0..<count {
    let p = 12 + i * 16
    let tag = @utf8.decode(b[p:p + 4]) catch {
      _ => raise InvalidFont("invalid table tag")
    }
    let offset = u32(b, p + 8)
    let length = u32(b, p + 12)
    guard offset <= b.length() && length <= b.length() - offset else {
      raise InvalidFont("font table outside file")
    }
    tables[tag] = offset
  }
  guard !tables.contains("fvar") && tables.contains("glyf") else {
    raise InvalidFont("variable or non-glyf font unsupported")
  }
  fn table(tables : Map[String, Int], name : String) -> Int raise PdfError {
    tables.get(name).unwrap_or_else(() => raise InvalidFont("missing " + name))
  }
  let names = table(tables, "name")
  let name_count = u16(b, names + 2)
  let name_data = names + u16(b, names + 4)
  let expected = @buffer.Buffer()
  expected.write_string_utf16be(input.family)
  let mut family_matches = false
  guard name_count <= 4096 else {
    raise InvalidFont("font name table too large")
  }
  for i in 0..<name_count {
    let p = names + 6 + i * 12
    let platform = u16(b, p)
    let name_id = u16(b, p + 6)
    let length = u16(b, p + 8)
    let offset = name_data + u16(b, p + 10)
    guard offset <= b.length() && length <= b.length() - offset else {
      raise InvalidFont("font name outside table")
    }
    if (name_id == 1 || name_id == 16) &&
      (platform == 0 || platform == 3) &&
      b[offset:offset + length].to_owned() == expected.to_bytes() {
      family_matches = true
    }
  }
  guard family_matches else {
    raise InvalidFont(
      "font bytes do not declare requested family: " + input.family,
    )
  }
  let os2 = table(tables, "OS/2")
  let rights = u16(b, os2 + 8)
  guard (rights & 0x0202) == 0 else {
    raise InvalidFont("font forbids outline embedding")
  }
  let units = u16(b, table(tables, "head") + 18)
  let glyph_count = u16(b, table(tables, "maxp") + 4)
  let metric_count = u16(b, table(tables, "hhea") + 34)
  guard units >= 16 && metric_count > 0 && metric_count <= glyph_count else {
    raise InvalidFont("invalid font metrics")
  }
  let cmap = table(tables, "cmap")
  let mut chosen = -1
  let mut format = 0
  let encodings = u16(b, cmap + 2)
  guard encodings < 128 else { raise InvalidFont("too many cmaps") }
  for i in 0..<encodings {
    let p = cmap + 4 + 8 * i
    let platform = u16(b, p)
    let encoding = u16(b, p + 2)
    let offset = cmap + u32(b, p + 4)
    let kind = u16(b, offset)
    if (platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10))) &&
      (kind == 12 || (kind == 4 && format != 12)) {
      chosen = offset
      format = kind
    }
  }
  guard chosen >= 0 else { raise InvalidFont("Unicode cmap unavailable") }
  {
    input,
    units,
    glyph_count,
    metric_count,
    metrics: table(tables, "hmtx"),
    cmap: chosen,
    cmap_format: format,
    used: {},
  }
}

///|
fn Face::glyph(self : Face, code : Int) -> Int raise PdfError {
  if self.used.get(code) is Some(g) {
    return g
  }
  let b = self.input.bytes
  let p = self.cmap
  let mut glyph = 0
  if self.cmap_format == 12 {
    let n = u32(b, p + 12)
    guard n <= 65536 else { raise InvalidFont("cmap group bound") }
    for i in 0..<n {
      let q = p + 16 + i * 12
      let start = u32(b, q)
      let end = u32(b, q + 4)
      if code >= start && code <= end {
        glyph = u32(b, q + 8) + code - start
        break
      }
    }
  } else if code <= 65535 {
    let n = u16(b, p + 6) / 2
    guard n > 0 && n <= 8192 else { raise InvalidFont("cmap segment bound") }
    for i in 0..<n {
      let end = u16(b, p + 14 + i * 2)
      let start = u16(b, p + 16 + n * 2 + i * 2)
      if code >= start && code <= end {
        let delta = u16(b, p + 16 + n * 4 + i * 2)
        let address = p + 16 + n * 6 + i * 2
        let offset = u16(b, address)
        glyph = if offset == 0 {
          (code + delta) & 65535
        } else {
          let g = u16(b, address + offset + (code - start) * 2)
          if g == 0 {
            0
          } else {
            (g + delta) & 65535
          }
        }
        break
      }
    }
  }
  guard glyph > 0 && glyph < self.glyph_count else {
    raise InvalidFont(
      "missing glyph U+" + code.to_string(radix=16) + " in " + self.input.family,
    )
  }
  self.used[code] = glyph
  glyph
}

///|
fn Face::advance(self : Face, glyph : Int, size : Int) -> Int raise PdfError {
  u16(self.input.bytes, self.metrics + glyph.min(self.metric_count - 1) * 4) *
  size /
  self.units
}
