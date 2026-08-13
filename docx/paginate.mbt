///|
/// Conservative defaults matching WordprocessingML's conventional A4 page.
pub fn PaginationProfile::default() -> PaginationProfile {
  {
    default_margin_top_twips: 1440,
    default_margin_right_twips: 1440,
    default_margin_bottom_twips: 1440,
    default_margin_left_twips: 1440,
    default_font_size_half_points: 32,
    default_line_twips: 560,
    table_cell_vertical_padding_twips: 90,
    page_safety_twips: 0,
  }
}

///|
fn positive_or(value : Int?, fallback : Int) -> Int {
  match value {
    Some(number) if number > 0 => number
    _ => fallback
  }
}

///|
fn signed_or(value : Int?, fallback : Int) -> Int {
  match value {
    Some(number) if number >= 0 => number
    _ => fallback
  }
}

///|
fn run_font_size(run : RunMetadata, profile : PaginationProfile) -> Int {
  positive_or(run.font_size_half_points, profile.default_font_size_half_points)
}

///|
fn paragraph_line_count(
  paragraph : ParagraphInfo,
  width_twips : Int,
  profile : PaginationProfile,
) -> Int {
  let available = width_twips -
    paragraph.metadata.left_indent_twips.unwrap_or(0) -
    paragraph.metadata.right_indent_twips.unwrap_or(0)
  if available <= 0 {
    return 1
  }
  let first_width = (available -
  paragraph.metadata.first_line_twips.unwrap_or(0) +
  paragraph.metadata.hanging_twips.unwrap_or(0)).max(1)
  let lines = Ref(1)
  let used = Ref(0)
  let current_width = Ref(first_width)
  for run in paragraph.runs {
    let em_twips = run_font_size(run, profile) * 10
    for character in run.text {
      if character == '\n' || character == '\r' {
        lines.val = lines.val + 1
        used.val = 0
        current_width.val = available
      } else {
        let advance = if character.is_ascii() {
          (em_twips + 1) / 2
        } else {
          em_twips
        }
        if used.val > 0 && used.val + advance > current_width.val {
          lines.val = lines.val + 1
          used.val = advance
          current_width.val = available
        } else {
          used.val = used.val + advance
        }
      }
    }
  }
  lines.val
}

///|
fn paragraph_height(
  paragraph : ParagraphInfo,
  width_twips : Int,
  profile : PaginationProfile,
) -> Int {
  let font_line = paragraph.runs.fold(
    init=profile.default_font_size_half_points * 12,
    fn(current, run) { current.max(run_font_size(run, profile) * 12) },
  )
  let line_height = match paragraph.metadata.line_twips {
    Some(value) if value > 0 && paragraph.metadata.line_rule == Some("exact") =>
      value
    Some(value) if value > 0 => (font_line * value / 240).max(font_line)
    _ => font_line.max(profile.default_line_twips)
  }
  paragraph_line_count(paragraph, width_twips, profile) * line_height
}

///|
fn cell_height(cell : TableCellInfo, profile : PaginationProfile) -> Int {
  let width = positive_or(cell.width_twips, 2400)
  let paragraph_total = if cell.paragraphs.is_empty() {
    profile.default_line_twips
  } else {
    cell.paragraphs.fold(init=0, fn(total, paragraph) {
      total +
      paragraph.metadata.spacing_before_twips.unwrap_or(0) +
      paragraph_height(paragraph, width, profile) +
      paragraph.metadata.spacing_after_twips.unwrap_or(0)
    })
  }
  paragraph_total +
  cell.margin_top_twips.unwrap_or(profile.table_cell_vertical_padding_twips / 2) +
  cell.margin_bottom_twips.unwrap_or(
    profile.table_cell_vertical_padding_twips / 2,
  )
}

///|
fn table_row_height(row : TableRowInfo, profile : PaginationProfile) -> Int {
  let content_height = row.cells.fold(init=profile.default_line_twips, fn(
    height,
    cell,
  ) {
    height.max(cell_height(cell, profile))
  })
  let content_height = content_height.max(
    profile.default_line_twips + profile.table_cell_vertical_padding_twips * 2,
  )
  match row.height_twips {
    Some(value) if row.height_rule == Some("exact") => value
    Some(value) => content_height.max(value)
    None => content_height
  }
}

///|
fn table_with_rows(table : TableInfo, rows : Array[TableRowInfo]) -> TableInfo {
  { rows, grid_widths_twips: table.grid_widths_twips }
}

///|
fn add_page(
  pages : Array[DocxPage],
  blocks : Array[DocxFlowBlock],
  used : Int,
) -> Unit {
  if !blocks.is_empty() || pages.is_empty() {
    pages.push({ blocks: blocks.copy(), used_height_twips: used })
  }
  blocks.clear()
}

///|
fn paragraph_has_visible_content(paragraph : ParagraphInfo) -> Bool {
  paragraph.runs.any(run => !run.text.trim().is_empty())
}

///| Ignore Word's terminal body paragraph when it carries no visible content.

///| WordprocessingML producers commonly emit this paragraph after the final

///|
/// table; it is a document sentinel, not an additional rendered page.
fn pagination_block_count(blocks : Array[DocxFlowBlock]) -> Int {
  let count = Ref(blocks.length())
  while count.val > 0 {
    match blocks[count.val - 1] {
      FlowSection(_) => count.val = count.val - 1
      FlowParagraph(paragraph) if !paragraph_has_visible_content(paragraph) =>
        count.val = count.val - 1
      _ => break
    }
  }
  count.val
}

///|
/// Keep a short table caption and up to two following metadata paragraphs
/// with the table when they would otherwise be orphaned at the page bottom.
fn table_follows_soon(blocks : Array[DocxFlowBlock], index : Int) -> Bool {
  let mut seen_paragraphs = 0
  for next = index + 1
      next < blocks.length() && seen_paragraphs < 3
      next = next + 1 {
    match blocks[next] {
      FlowParagraph(_) => seen_paragraphs = seen_paragraphs + 1
      FlowTable(_) => return true
      FlowSection(_) => ()
      FlowPageBreak => return false
    }
  }
  false
}

///|
/// Paginate rich DOCX flow with deterministic OOXML-derived metrics.
pub fn paginate_document(
  document_package : @opc.Package,
  profile? : PaginationProfile = PaginationProfile::default(),
) -> PagedDocxDocument raise DocxError {
  let preview = preview_document(document_package)
  let section = preview.blocks.fold(init=None, fn(current, block) {
    match block {
      FlowSection(value) => Some(value)
      _ => current
    }
  })
  let section_page_width = match section {
    Some(value) => value.page_width_twips
    None => None
  }
  let section_page_height = match section {
    Some(value) => value.page_height_twips
    None => None
  }
  let section_margin_top = match section {
    Some(value) => value.margin_top_twips
    None => None
  }
  let section_margin_right = match section {
    Some(value) => value.margin_right_twips
    None => None
  }
  let section_margin_bottom = match section {
    Some(value) => value.margin_bottom_twips
    None => None
  }
  let section_margin_left = match section {
    Some(value) => value.margin_left_twips
    None => None
  }
  let page_width_twips = section_page_width.unwrap_or(11906)
  let page_height_twips = section_page_height.unwrap_or(16838)
  let margin_top_twips = signed_or(
    section_margin_top,
    profile.default_margin_top_twips,
  )
  let margin_right_twips = signed_or(
    section_margin_right,
    profile.default_margin_right_twips,
  )
  let margin_bottom_twips = signed_or(
    section_margin_bottom,
    profile.default_margin_bottom_twips,
  )
  let margin_left_twips = signed_or(
    section_margin_left,
    profile.default_margin_left_twips,
  )
  let content_width_twips = (page_width_twips -
  margin_left_twips -
  margin_right_twips).max(1)
  let content_height_twips = (page_height_twips -
  margin_top_twips -
  margin_bottom_twips -
  profile.page_safety_twips).max(1)
  let pages : Array[DocxPage] = []
  let current : Array[DocxFlowBlock] = []
  let used = Ref(0)
  let pending_paragraph_after = Ref(0)
  fn next_page(
    pages : Array[DocxPage],
    current : Array[DocxFlowBlock],
    used : Ref[Int],
  ) -> Unit {
    add_page(pages, current, used.val)
    used.val = 0
  }
  let block_count = pagination_block_count(preview.blocks)
  for index = 0; index < block_count; index = index + 1 {
    let block = preview.blocks[index]
    match block {
      FlowPageBreak => {
        next_page(pages, current, used)
        pending_paragraph_after.val = 0
      }
      FlowSection(_) => ()
      FlowParagraph(paragraph) => {
        let before = paragraph.metadata.spacing_before_twips.unwrap_or(0).max(0)
        let after = paragraph.metadata.spacing_after_twips.unwrap_or(0).max(0)
        let content_height = paragraph_height(
          paragraph, content_width_twips, profile,
        )
        let mut height = pending_paragraph_after.val.max(before) +
          content_height
        let keep_with_table = paragraph_line_count(
            paragraph, content_width_twips, profile,
          ) ==
          1 &&
          table_follows_soon(preview.blocks, index)
        if keep_with_table &&
          used.val > 0 &&
          content_height_twips - used.val < profile.default_line_twips * 5 {
          next_page(pages, current, used)
          pending_paragraph_after.val = 0
          height = before + content_height
        }
        if used.val > 0 && used.val + height > content_height_twips {
          next_page(pages, current, used)
          height = before + content_height
        }
        current.push(FlowParagraph(paragraph))
        used.val = used.val + height
        pending_paragraph_after.val = after
      }
      FlowTable(table) => {
        if pending_paragraph_after.val > 0 {
          if used.val > 0 &&
            used.val + pending_paragraph_after.val > content_height_twips {
            next_page(pages, current, used)
          } else {
            used.val = used.val + pending_paragraph_after.val
          }
          pending_paragraph_after.val = 0
        }
        let fragment : Array[TableRowInfo] = []
        let fragment_height = Ref(0)
        for row in table.rows {
          let height = table_row_height(row, profile)
          if !fragment.is_empty() &&
            used.val + fragment_height.val + height > content_height_twips {
            current.push(FlowTable(table_with_rows(table, fragment.copy())))
            used.val = used.val + fragment_height.val
            next_page(pages, current, used)
            fragment.clear()
            fragment_height.val = 0
          } else if fragment.is_empty() &&
            used.val > 0 &&
            used.val + height > content_height_twips {
            next_page(pages, current, used)
          }
          fragment.push(row)
          fragment_height.val = fragment_height.val + height
        }
        if !fragment.is_empty() {
          current.push(FlowTable(table_with_rows(table, fragment)))
          used.val = used.val + fragment_height.val
        }
      }
    }
  }
  next_page(pages, current, used)
  {
    pages,
    page_width_twips,
    page_height_twips,
    margin_top_twips,
    margin_right_twips,
    margin_bottom_twips,
    margin_left_twips,
    content_width_twips,
    content_height_twips,
    diagnostics: preview.warnings,
  }
}
