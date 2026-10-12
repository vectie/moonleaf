///|
pub(all) suberror MarkdownTableError {
  InvalidMarkdownTable(line~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
/// Literal pipe-table data and one-based physical source lines. The identifier
/// is local to this exact document and is not a stable business key.
pub(all) struct MarkdownTable {
  id : String
  header_line : Int
  separator_line : Int
  source_lines : Array[Int]
  table : Table
} derive(Debug, Eq)

///|
fn markdown_indented(line : String) -> Bool {
  let mut spaces = 0
  for c in line {
    if c == '\t' {
      return true
    }
    if c != ' ' {
      break
    }
    spaces += 1
    if spaces >= 4 {
      return true
    }
  }
  false
}

///|
// Unescaped pipes are delimiters even inside backticks. Only escaped pipes and
// backslashes are decoded; other Markdown syntax stays literal text.
fn markdown_cells(line : String) -> Array[String]? {
  if markdown_indented(line) {
    return None
  }
  let text = line.trim(chars=" \t").to_owned()
  let cells : Array[String] = []
  let mut cell = StringBuilder::new()
  let mut escaped = false
  let mut delimiter = false
  let mut last_pipe = false
  for c in text {
    if escaped {
      if c != '|' && c != '\\' {
        cell.write_char('\\')
      }
      cell.write_char(c)
      escaped = false
      last_pipe = false
    } else if c == '\\' {
      escaped = true
      last_pipe = false
    } else if c == '|' {
      cells.push(cell.to_string().trim(chars=" \t").to_owned())
      cell = StringBuilder::new()
      delimiter = true
      last_pipe = true
    } else {
      cell.write_char(c)
      last_pipe = false
    }
  }
  if escaped {
    cell.write_char('\\')
  }
  if !delimiter {
    return None
  }
  if !last_pipe {
    cells.push(cell.to_string().trim(chars=" \t").to_owned())
  }
  if text.has_prefix("|") && !cells.is_empty() {
    ignore(cells.remove(0))
  }
  Some(cells)
}

///|
fn markdown_separator(cells : Array[String]) -> Bool {
  !cells.is_empty() &&
  cells.all(cell => {
    let chars = cell.iter().collect()
    let start = if chars.get(0) == Some(':') { 1 } else { 0 }
    let end = chars.length() - (if chars.last() == Some(':') { 1 } else { 0 })
    end - start >= 3 && chars[start:end].iter().all(c => c == '-')
  })
}

///|
fn markdown_fence(line : String) -> (Char, Int, Bool)? {
  if markdown_indented(line) {
    return None
  }
  let text = line.trim(chars=" \t").to_owned()
  let chars = text.iter().collect()
  guard chars.get(0) is Some(marker) && (marker == '`' || marker == '~') else {
    return None
  }
  let mut count = 0
  for c in chars {
    if c != marker {
      break
    }
    count += 1
  }
  if count < 3 {
    return None
  }
  Some((marker, count, chars[count:].iter().all(c => c == ' ' || c == '\t')))
}

///|
/// Discover and parse bounded standalone Markdown pipe tables. Cells remain
/// text, including numeric-looking identifiers and inline Markdown. Fenced and
/// four-space/tab-indented code is excluded; no full Markdown rendering occurs.
/// All detected tables must be rectangular with unique nonempty headers.
pub fn parse_markdown_tables(
  text : String,
) -> Array[MarkdownTable] raise MarkdownTableError {
  if text.length() > 4_000_000 || text.contains("\u0000") {
    raise InvalidMarkdownTable(
      line=0,
      reason="Expected at most 4000000 UTF-16 units without NUL",
    )
  }
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  if lines.length() > 100_000 {
    raise InvalidMarkdownTable(
      line=0,
      reason="Input exceeds 100000 physical lines",
    )
  }
  for i, line in lines {
    let clean = line.trim_end(chars="\r").to_owned()
    if line.length() - clean.length() > 1 || clean.contains("\r") {
      raise InvalidMarkdownTable(
        line=i + 1,
        reason="Use LF or CRLF line endings",
      )
    }
    lines[i] = clean
  }
  if !lines.is_empty() && lines[0].has_prefix("\uFEFF") {
    lines[0] = lines[0].trim_start(chars="\uFEFF").to_owned()
  }
  let tables : Array[MarkdownTable] = []
  let mut fence : (Char, Int)? = None
  let mut line = 0
  let mut total_cells = 0
  while line < lines.length() {
    if fence is Some((marker, length)) {
      if markdown_fence(lines[line]) is Some((close, size, true)) &&
        close == marker &&
        size >= length {
        fence = None
      }
      line += 1
      continue
    }
    if markdown_fence(lines[line]) is Some((marker, length, _)) {
      fence = Some((marker, length))
      line += 1
      continue
    }
    if line + 1 >= lines.length() {
      break
    }
    guard markdown_cells(lines[line]) is Some(headers) &&
      markdown_cells(lines[line + 1]) is Some(separator) &&
      markdown_separator(separator) else {
      line += 1
      continue
    }
    if tables.length() >= 64 ||
      headers.is_empty() ||
      headers.length() > 128 ||
      headers.length() != separator.length() {
      raise InvalidMarkdownTable(
        line=line + 1,
        reason="Expected at most 64 tables and 1–128 headers matching separator width",
      )
    }
    let seen : Array[String] = []
    for header in headers {
      if header == "" || seen.contains(header) || header.length() > 16384 {
        raise InvalidMarkdownTable(
          line=line + 1,
          reason="Headers must be unique nonempty text of at most 16384 units",
        )
      }
      seen.push(header)
    }
    let header_line = line + 1
    let separator_line = line + 2
    let rows : Array[Array[@scene.CellValue]] = []
    let source_lines : Array[Int] = []
    total_cells += headers.length()
    line += 2
    while line < lines.length() {
      // A fence starts a different block even when its info string has a pipe.
      if markdown_fence(lines[line]) is Some(_) {
        break
      }
      guard markdown_cells(lines[line]) is Some(cells) else { break }
      if cells.length() != headers.length() {
        raise InvalidMarkdownTable(
          line=line + 1,
          reason="Ragged row: expected \{headers.length()} cells, found \{cells.length()}",
        )
      }
      if rows.length() >= 10_000 || cells.any(cell => cell.length() > 16384) {
        raise InvalidMarkdownTable(
          line=line + 1,
          reason="Table exceeds 10000 rows or cell exceeds 16384 units",
        )
      }
      total_cells += cells.length()
      if total_cells > 100_000 {
        raise InvalidMarkdownTable(
          line=line + 1,
          reason="Document tables exceed 100000 cells including headers",
        )
      }
      rows.push(cells.map(cell => @scene.Text(cell)))
      source_lines.push(line + 1)
      line += 1
    }
    if total_cells > 100_000 {
      raise InvalidMarkdownTable(
        line=header_line,
        reason="Document tables exceed 100000 cells including headers",
      )
    }
    tables.push({
      id: "table-\{tables.length() + 1}",
      header_line,
      separator_line,
      source_lines,
      table: { columns: headers, rows, },
    })
  }
  tables
}
