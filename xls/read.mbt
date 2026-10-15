///|
pub(all) suberror XlsError {
  Invalid(String)
} derive(Debug, Eq)

///|
pub extend XlsError with Debug::{to_repr}

///|
pub extend XlsError with Eq::{equal, not_equal}

///|
fn u16(b : FixedArray[Byte], p : Int) -> Int raise XlsError {
  guard p >= 0 && p + 2 <= b.length() else {
    raise Invalid("truncated XLS integer")
  }
  b[p].to_int() + (b[p + 1].to_int() << 8)
}

///|
fn u32(b : FixedArray[Byte], p : Int) -> Int raise XlsError {
  u16(b, p) | (u16(b, p + 2) << 16)
}

///|
fn text(
  b : FixedArray[Byte],
  p : Int,
  count : Int,
  wide : Bool,
) -> String raise XlsError {
  let chars : Array[Char] = []
  for i in 0..<count {
    let code = if wide {
      u16(b, p + i * 2)
    } else {
      guard p + i < b.length() else { raise Invalid("truncated XLS text") }
      b[p + i].to_int()
    }
    chars.push(code.unsafe_to_char())
  }
  String::from_array(chars)
}

///|
fn slice(
  b : FixedArray[Byte],
  p : Int,
  n : Int,
) -> FixedArray[Byte] raise XlsError {
  guard p >= 0 && n >= 0 && p <= b.length() - n else {
    raise Invalid("truncated XLS segment")
  }
  FixedArray::makei(n, i => b[p + i])
}

///|
fn chain(
  b : FixedArray[Byte],
  fat : Array[Int],
  start : Int,
  sector_size : Int,
  maximum : Int,
) -> FixedArray[Byte] raise XlsError {
  let output : Array[Byte] = []
  let seen : Map[Int, Bool] = Map([])
  let mut sector = start
  while sector >= 0 {
    guard sector < fat.length() && !seen.contains(sector) else {
      raise Invalid("invalid/cyclic OLE sector chain")
    }
    seen[sector] = true
    let position = (sector + 1) * sector_size
    guard position >= 0 &&
      position <= b.length() - sector_size &&
      output.length() <= maximum - sector_size else {
      raise Invalid("OLE stream exceeds bounds")
    }
    for i in 0..<sector_size {
      output.push(b[position + i])
    }
    sector = fat[sector]
  }
  guard sector == -2 else { raise Invalid("invalid OLE end marker") }
  FixedArray::from_array(output)
}

///|
fn workbook_stream(b : FixedArray[Byte]) -> FixedArray[Byte] raise XlsError {
  guard b.length() >= 512 &&
    b.length() <= 16 * 1024 * 1024 &&
    u32(b, 0).reinterpret_as_uint() == 0xe011cfd0U &&
    u32(b, 4).reinterpret_as_uint() == 0xe11ab1a1U else {
    raise Invalid("not a bounded OLE compound XLS file")
  }
  let shift = u16(b, 30)
  guard shift == 9 || shift == 12 else {
    raise Invalid("unsupported OLE sector size")
  }
  let sector_size = 1 << shift
  guard u32(b, 68) == -2 && u32(b, 72) == 0 else {
    raise Invalid("extended DIFAT XLS not supported")
  }
  let fat : Array[Int] = []
  let fat_count = u32(b, 44)
  guard fat_count >= 0 && fat_count <= 109 else {
    raise Invalid("unsupported OLE FAT length")
  }
  for i in 0..<fat_count {
    let sid = u32(b, 76 + i * 4)
    guard sid >= 0 && sid < b.length() / sector_size - 1 else {
      raise Invalid("invalid OLE FAT sector")
    }
    for j in 0..<(sector_size / 4) {
      fat.push(u32(b, (sid + 1) * sector_size + j * 4))
    }
  }
  let directory = chain(b, fat, u32(b, 48), sector_size, 1024 * 1024)
  let mut root_start = -1
  let mut root_size = 0
  let mut stream_start = -1
  let mut stream_size = 0
  for p = 0; p + 128 <= directory.length(); p = p + 128 {
    let len = u16(directory, p + 64)
    if len >= 2 && len <= 64 {
      let name = text(directory, p, len / 2 - 1, true)
      if directory[p + 66].to_int() == 5 {
        root_start = u32(directory, p + 116)
        root_size = u32(directory, p + 120)
      } else if name == "Workbook" || name == "Book" {
        stream_start = u32(directory, p + 116)
        stream_size = u32(directory, p + 120)
      }
    }
  }
  guard stream_start >= 0 && stream_size > 0 && stream_size <= 16 * 1024 * 1024 else {
    raise Invalid("missing bounded Workbook stream")
  }
  if stream_size >= u32(b, 56) {
    return slice(
      chain(b, fat, stream_start, sector_size, 17 * 1024 * 1024),
      0,
      stream_size,
    )
  }
  guard root_start >= 0 && root_size > 0 && u16(b, 32) == 6 else {
    raise Invalid("invalid OLE mini-stream")
  }
  let root = slice(
    chain(b, fat, root_start, sector_size, 17 * 1024 * 1024),
    0,
    root_size,
  )
  let mini_bytes = chain(b, fat, u32(b, 60), sector_size, 1024 * 1024)
  let mini_fat : Array[Int] = []
  for i in 0..<(mini_bytes.length() / 4) {
    mini_fat.push(u32(mini_bytes, i * 4))
  }
  let output : Array[Byte] = []
  let seen : Map[Int, Bool] = Map([])
  let mut sid = stream_start
  while sid >= 0 && output.length() < stream_size {
    guard sid < mini_fat.length() &&
      sid * 64 + 64 <= root.length() &&
      !seen.contains(sid) else {
      raise Invalid("invalid OLE mini-sector chain")
    }
    seen[sid] = true
    for i in 0..<64 {
      output.push(root[sid * 64 + i])
    }
    sid = mini_fat[sid]
  }
  slice(FixedArray::from_array(output), 0, stream_size)
}

///|
priv struct SstReader {
  chunks : Array[FixedArray[Byte]]
  mut chunk : Int
  mut offset : Int
}

///|
fn SstReader::byte(self : SstReader) -> Int raise XlsError {
  while self.chunk < self.chunks.length() &&
        self.offset >= self.chunks[self.chunk].length() {
    self.chunk += 1
    self.offset = 0
  }
  guard self.chunk < self.chunks.length() else {
    raise Invalid("truncated BIFF shared strings")
  }
  let value = self.chunks[self.chunk][self.offset].to_int()
  self.offset += 1
  value
}

///|
fn SstReader::short(self : SstReader) -> Int raise XlsError {
  self.byte() | (self.byte() << 8)
}

///|
fn strings(chunks : Array[FixedArray[Byte]]) -> Array[String] raise XlsError {
  let r = { chunks, chunk: 0, offset: 0, }
  for _ in 0..<4 {
    ignore(r.byte())
  }
  let count = r.short() | (r.short() << 16)
  guard count >= 0 && count <= 200000 else {
    raise Invalid("BIFF string count exceeds limit")
  }
  let result = []
  for _ in 0..<count {
    let length = r.short()
    let flags = r.byte()
    let mut wide = (flags & 1) != 0
    let rich = if (flags & 8) != 0 { r.short() } else { 0 }
    let ext = if (flags & 4) != 0 { r.short() | (r.short() << 16) } else { 0 }
    guard length <= 32767 && ext >= 0 && ext <= 1024 * 1024 else {
      raise Invalid("BIFF string exceeds limit")
    }
    let chars : Array[Char] = []
    for _ in 0..<length {
      if r.offset == r.chunks[r.chunk].length() {
        r.chunk += 1
        r.offset = 0
        wide = (r.byte() & 1) != 0
      }
      let code = if wide { r.short() } else { r.byte() }
      chars.push(code.unsafe_to_char())
    }
    for _ in 0..<(rich * 4 + ext) {
      ignore(r.byte())
    }
    result.push(String::from_array(chars))
  }
  result
}

///|
fn number(b : FixedArray[Byte], p : Int) -> String raise XlsError {
  let bits = u32(b, p).reinterpret_as_uint().to_uint64() |
    (u32(b, p + 4).reinterpret_as_uint().to_uint64() << 32)
  bits.reinterpret_as_double().to_string()
}

///|
fn rk(value : Int) -> String {
  let result = if (value & 2) != 0 {
    (value >> 2).to_double()
  } else {
    ((value & -4).reinterpret_as_uint().to_uint64() << 32).reinterpret_as_double()
  }
  (if (value & 1) != 0 { result / 100.0 } else { result }).to_string()
}

///|
/// Read scalar values from bounded unencrypted BIFF8 XLS workbooks. Formula
/// cells expose cached results only; no formulas/macros are executed. Unsupported
/// charts/styles are omitted and called out in workbook warnings.
pub fn read(bytes : FixedArray[Byte]) -> @scene.Workbook raise XlsError {
  let b = workbook_stream(bytes)
  let descriptors : Array[(Int, String)] = []
  let chunks : Array[FixedArray[Byte]] = []
  let mut p = 0
  let mut sst_open = false
  while p + 4 <= b.length() {
    let kind = u16(b, p)
    let n = u16(b, p + 2)
    guard p + 4 + n <= b.length() else {
      raise Invalid("truncated BIFF record")
    }
    if kind == 47 {
      raise Invalid("encrypted XLS unsupported")
    }
    if kind == 133 && n >= 8 && b[p + 9].to_int() == 0 {
      descriptors.push(
        (
          u32(b, p + 4),
          text(b, p + 12, b[p + 10].to_int(), (b[p + 11].to_int() & 1) != 0),
        ),
      )
    }
    if kind == 252 {
      chunks.push(slice(b, p + 4, n))
      sst_open = true
    } else if kind == 60 && sst_open {
      chunks.push(slice(b, p + 4, n))
    } else {
      sst_open = false
    }
    p += n + 4
  }
  let shared = if chunks.is_empty() { [] } else { strings(chunks) }
  let sheets : Array[@scene.Sheet] = []
  let mut cells_total = 0
  for (offset, name) in descriptors {
    let cells : Array[@scene.Cell] = []
    p = offset
    while p + 4 <= b.length() {
      let kind = u16(b, p)
      let n = u16(b, p + 2)
      let q = p + 4
      guard q + n <= b.length() else {
        raise Invalid("truncated worksheet record")
      }
      if kind == 10 {
        break
      }
      if [253, 515, 638, 513, 517, 6, 189].contains(kind) && n >= 6 {
        let row = u16(b, q) + 1
        let col = u16(b, q + 2) + 1
        let mut value : @scene.CellValue = Empty
        if kind == 253 && n >= 10 {
          let index = u32(b, q + 6)
          guard index >= 0 && index < shared.length() else {
            raise Invalid("invalid shared-string reference")
          }
          value = Text(shared[index])
        } else if kind == 515 && n >= 14 {
          value = Number(number(b, q + 6))
        } else if kind == 638 && n >= 10 {
          value = Number(rk(u32(b, q + 6)))
        } else if kind == 517 && n >= 8 {
          value = if b[q + 7].to_int() == 0 {
            Boolean(b[q + 6].to_int() != 0)
          } else {
            Error("BIFF cell error")
          }
        } else if kind == 6 && n >= 14 {
          value = if u16(b, q + 12) == 65535 {
            Empty
          } else {
            Number(number(b, q + 6))
          }
        }
        if kind == 189 && n >= 12 {
          let count = (n - 6) / 6
          for i in 0..<count {
            cells.push({
              row,
              column: col + i,
              value: Number(rk(u32(b, q + 6 + i * 6))),
              style_id: Some(u16(b, q + 4 + i * 6)),
            })
          }
        } else {
          cells.push({ row, column: col, value, style_id: Some(u16(b, q + 4)), })
        }
        cells_total += 1
        guard cells_total <= 200000 else {
          raise Invalid("XLS cell count exceeds limit")
        }
      }
      p = q + n
    }
    sheets.push({ name, cells, merged_ranges: [], })
  }
  guard !sheets.is_empty() else {
    raise Invalid("BIFF8 workbook contains no worksheets")
  }
  {
    sheets,
    warnings: [
      {
        code: "xls_scalar_import",
        message: "Legacy BIFF8 scalar values only; cached formula results; styles, date formatting, charts and macros are not imported.",
        part: None,
      },
    ],
  }
}
