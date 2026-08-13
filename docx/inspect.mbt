///|
fn nonnegative_int_attr(element : @xml.Element?, name : String) -> Int? {
  match element {
    None => None
    Some(element) => {
      let n = parse_int_or(element.attribute(name), -1)
      if n < 0 {
        None
      } else {
        Some(n)
      }
    }
  }
}

///|
fn signed_indent_attr(element : @xml.Element?, name : String) -> Int? {
  match element {
    None => None
    Some(element) => {
      let value = element.attribute(name)
      let invalid = 2147483647
      let n = parse_int_or(value, invalid)
      if n == invalid {
        None
      } else {
        Some(n)
      }
    }
  }
}

///|
fn int_attr(element : @xml.Element?, name : String) -> Int? {
  nonnegative_int_attr(element, name)
}

///|
fn signed_int_attr(element : @xml.Element?, name : String) -> Int? {
  signed_indent_attr(element, name)
}

///|
fn string_attr(element : @xml.Element?, name : String) -> String? {
  match element {
    None => None
    Some(e) => e.attribute(name)
  }
}

///|
fn child(element : @xml.Element?, name : String) -> @xml.Element? {
  match element {
    Some(value) => value.first_child(name)
    None => None
  }
}

///|
fn paragraph_metadata_from_pr(pr : @xml.Element) -> ParagraphMetadata {
  let pr = Some(pr)
  let spacing = match pr {
    Some(x) => x.first_child("spacing")
    None => None
  }
  let ind = match pr {
    Some(x) => x.first_child("ind")
    None => None
  }
  {
    alignment: match pr {
      Some(x) => string_attr(x.first_child("jc"), "val")
      None => None
    },
    spacing_before_twips: nonnegative_int_attr(spacing, "before"),
    spacing_after_twips: nonnegative_int_attr(spacing, "after"),
    line_twips: nonnegative_int_attr(spacing, "line"),
    line_rule: string_attr(spacing, "lineRule"),
    left_indent_twips: signed_indent_attr(ind, "left"),
    right_indent_twips: signed_indent_attr(ind, "right"),
    first_line_twips: signed_indent_attr(ind, "firstLine"),
    hanging_twips: signed_indent_attr(ind, "hanging"),
  }
}

///|
fn collect_run_info(
  element : @xml.Element,
  link : String?,
  out : Array[RunMetadata],
  table : StyleTable,
  paragraph_style : ResolvedStyle,
  warnings : Array[@scene.Warning],
) -> Unit {
  for child in element.child_elements() {
    if child.local_name() == "r" {
      let pr = child.first_child("rPr")
      let run_direct = run_style_from_pr(pr)
      let character_style = match pr {
        Some(x) =>
          match string_attr(x.first_child("rStyle"), "val") {
            Some(id) =>
              resolve_style(
                table.character_styles,
                id,
                empty_resolved_style(),
                warnings,
              )
            None => empty_resolved_style()
          }
        None => empty_resolved_style()
      }
      let resolved = merge_resolved_style(
        merge_resolved_style(
          merge_resolved_style(table.run_default, paragraph_style),
          character_style,
        ),
        run_direct,
      )
      out.push({
        text: child.text_content(),
        bold: resolved.bold.unwrap_or(false),
        italic: resolved.italic.unwrap_or(false),
        underline: resolved.underline.unwrap_or(false),
        font_size_half_points: resolved.font_size_half_points,
        font_ascii: resolved.font_ascii,
        font_east_asia: resolved.font_east_asia,
        font_complex_script: resolved.font_complex_script,
        color: resolved.color,
        highlight: resolved.highlight,
        strike: resolved.strike.unwrap_or(false),
        hyperlink: link,
      })
    } else if child.local_name() == "hyperlink" {
      let target = match child.attribute("id") {
        Some(x) => Some(x)
        None => child.attribute("anchor")
      }
      collect_run_info(child, target, out, table, paragraph_style, warnings)
    } else if child.local_name() != "pPr" {
      collect_run_info(child, link, out, table, paragraph_style, warnings)
    }
  }
}

///|
fn parse_cell_info(
  cell : @xml.Element,
  styles : StyleTable,
  warnings : Array[@scene.Warning],
) -> TableCellInfo {
  let pr = cell.first_child("tcPr")
  let margins = match pr {
    Some(x) => x.first_child("tcMar")
    None => None
  }
  let paragraphs : Array[ParagraphInfo] = []
  for paragraph in cell.children_named("p") {
    let nested_tables : Array[TableInfo] = []
    let nested_sections : Array[SectionInfo] = []
    inspect_element(
      paragraph, paragraphs, nested_tables, nested_sections, styles, warnings,
    )
  }
  let grid_span = match pr {
    Some(x) =>
      match x.first_child("gridSpan") {
        None => 1
        Some(span) => {
          let value = parse_int_or(span.attribute("val"), 0)
          if value > 0 {
            value
          } else {
            warnings.push({
              code: "DOCX_GRID_SPAN_INVALID",
              message: "gridSpan must be a positive integer; using 1",
              part: Some("word/document.xml"),
            })
            1
          }
        }
      }
    None => 1
  }
  {
    text: paragraphs
    .map(paragraph => paragraph.runs.map(run => run.text).join(""))
    .join("\n"),
    paragraphs,
    grid_span,
    vertical_merge: match pr {
      Some(x) =>
        match x.first_child("vMerge") {
          None => None
          Some(v) =>
            match v.attribute("val") {
              Some(s) => Some(s)
              None => Some("continue")
            }
        }
      None => None
    },
    width_twips: match pr {
      Some(x) => nonnegative_int_attr(x.first_child("tcW"), "w")
      None => None
    },
    margin_top_twips: nonnegative_int_attr(child(margins, "top"), "w"),
    margin_right_twips: nonnegative_int_attr(child(margins, "right"), "w"),
    margin_bottom_twips: nonnegative_int_attr(child(margins, "bottom"), "w"),
    margin_left_twips: nonnegative_int_attr(child(margins, "left"), "w"),
    vertical_alignment: match pr {
      Some(x) => string_attr(x.first_child("vAlign"), "val")
      None => None
    },
  }
}

///|
fn add_related_text(
  document_package : @opc.Package,
  target : String,
  out : Array[String],
) -> Unit {
  if document_package.has_part(target) {
    let source = document_package.text(target) catch { _ => return }
    let root = @xml.parse(source) catch { _ => return }
    out.push(root.text_content())
  }
}

///|
fn resolve_related_part(
  container : @opc.Package,
  rel : @opc.Relationship,
  warnings : Array[@scene.Warning],
) -> String? {
  if rel.external {
    warnings.push({
      code: "DOCX_EXTERNAL_RELATED_PART",
      message: "External related parts are not read from the package",
      part: None,
    })
    return None
  }
  let part = @opc.resolve_target("word/document.xml", rel.target) catch {
    _ => {
      warnings.push({
        code: "DOCX_RELATIONSHIP_TARGET_INVALID",
        message: "Relationship target cannot be resolved",
        part: Some("word/_rels/document.xml.rels"),
      })
      return None
    }
  }
  if container.has_part(part) {
    Some(part)
  } else {
    warnings.push({
      code: "DOCX_RELATED_PART_MISSING",
      message: "Resolved relationship target is missing",
      part: Some(part),
    })
    None
  }
}

///|
/// Parse rich DOCX metadata while preserving `read` as the stable scene API.
pub fn inspect_document(
  document_package : @opc.Package,
) -> DocxDocument raise DocxError {
  let scene = read(document_package)
  let source = document_package.text("word/document.xml") catch {
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  let paragraphs = []
  let tables = []
  let sections = []
  let styles = parse_style_table(document_package)
  let warnings = scene.warnings.copy()
  for element in root.child_elements() {
    inspect_element(element, paragraphs, tables, sections, styles, warnings)
  }
  let headers = []
  let footers = []
  let resources = []
  let relationships = if document_package.has_part(
      "word/_rels/document.xml.rels",
    ) {
    document_package.relationships("word/document.xml") catch {
      _ => {
        warnings.push({
          code: "DOCX_RELATIONSHIPS_INVALID",
          message: "Unable to parse document relationships",
          part: Some("word/_rels/document.xml.rels"),
        })
        []
      }
    }
  } else {
    []
  }
  for rel in relationships {
    let header = rel.relationship_type ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" ||
      rel.relationship_type ==
      "http://purl.oclc.org/ooxml/officeDocument/relationships/header"
    let footer = rel.relationship_type ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" ||
      rel.relationship_type ==
      "http://purl.oclc.org/ooxml/officeDocument/relationships/footer"
    let image = rel.relationship_type ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" ||
      rel.relationship_type ==
      "http://purl.oclc.org/ooxml/officeDocument/relationships/image"
    let related = header || footer || image
    if !related {
      continue
    }
    let target = resolve_related_part(document_package, rel, warnings)
    if header {
      match target {
        Some(part) => add_related_text(document_package, part, headers)
        None => ()
      }
    } else if footer {
      match target {
        Some(part) => add_related_text(document_package, part, footers)
        None => ()
      }
    } else if image {
      resources.push({
        relationship_id: rel.id,
        target: rel.target,
        external: rel.external,
        media_part: target,
      })
      match target {
        Some(part) =>
          warnings.push({
            code: "DOCX_IMAGE_SCENE_UNSUPPORTED",
            message: "TextDocument has no image block; resource retained by inspect()",
            part: Some(part),
          })
        None => ()
      }
    }
  }
  { scene, paragraphs, tables, sections, headers, footers, resources, warnings }
}

///| Preserve the main-document flow order while exposing the resolved DOCX

///| metadata needed by host preview renderers. The stable `read()` scene stays

///|
/// intentionally portable and lossy; this API is the richer DOCX boundary.
pub fn preview_document(
  document_package : @opc.Package,
) -> DocxPreviewDocument raise DocxError {
  let inspected = inspect_document(document_package)
  let source = document_package.text("word/document.xml") catch {
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  let body = if root.local_name() == "body" {
    Some(root)
  } else {
    root.first_child("body")
  }
  guard body is Some(body) else { raise InvalidDocument("missing w:body") }
  let styles = parse_style_table(document_package)
  let warnings = inspected.warnings.copy()
  let blocks : Array[DocxFlowBlock] = []
  for child in body.child_elements() {
    let paragraphs = []
    let tables = []
    let sections = []
    inspect_element(child, paragraphs, tables, sections, styles, warnings)
    match child.local_name() {
      "p" => {
        let leading_break = leading_page_break(child)
        if leading_break {
          blocks.push(FlowPageBreak)
        }
        match paragraphs.get(0) {
          Some(paragraph) => blocks.push(FlowParagraph(paragraph))
          None => ()
        }
        if !leading_break && element_contains_page_break(child) {
          blocks.push(FlowPageBreak)
        }
        for section in sections {
          blocks.push(FlowSection(section))
        }
      }
      "tbl" =>
        match tables.get(0) {
          Some(table) => blocks.push(FlowTable(table))
          None => ()
        }
      "sectPr" =>
        for section in sections {
          blocks.push(FlowSection(section))
        }
      _ => ()
    }
  }
  {
    blocks,
    headers: inspected.headers,
    footers: inspected.footers,
    resources: inspected.resources,
    warnings,
  }
}

///|
fn first_rendered_content(element : @xml.Element) -> Int {
  if element.local_name() == "lastRenderedPageBreak" ||
    (element.local_name() == "br" && element.attribute("type") == Some("page")) {
    return 1
  }
  if element.local_name() == "t" && !element.text_content().trim().is_empty() {
    return 2
  }
  for child in element.child_elements() {
    let found = first_rendered_content(child)
    if found != 0 {
      return found
    }
  }
  0
}

///|
fn leading_page_break(element : @xml.Element) -> Bool {
  first_rendered_content(element) == 1
}

///|
fn element_contains_page_break(element : @xml.Element) -> Bool {
  if element.local_name() == "lastRenderedPageBreak" {
    return true
  }
  if element.local_name() == "br" && element.attribute("type") == Some("page") {
    return true
  }
  element.child_elements().any(element_contains_page_break)
}

///|
fn inspect_element(
  element : @xml.Element,
  paragraphs : Array[ParagraphInfo],
  tables : Array[TableInfo],
  sections : Array[SectionInfo],
  styles : StyleTable,
  warnings : Array[@scene.Warning],
) -> Unit {
  match element.local_name() {
    "p" => {
      let runs = []
      let pr = element.first_child("pPr")
      let paragraph_base = match pr {
        Some(x) =>
          match string_attr(x.first_child("pStyle"), "val") {
            Some(id) =>
              resolve_style(
                styles.paragraph_styles,
                id,
                styles.paragraph_default,
                warnings,
              )
            None =>
              match styles.default_paragraph_style_id {
                Some(id) =>
                  resolve_style(
                    styles.paragraph_styles,
                    id,
                    styles.paragraph_default,
                    warnings,
                  )
                None => styles.paragraph_default
              }
          }
        None =>
          match styles.default_paragraph_style_id {
            Some(id) =>
              resolve_style(
                styles.paragraph_styles,
                id,
                styles.paragraph_default,
                warnings,
              )
            None => styles.paragraph_default
          }
      }
      let paragraph_direct = match pr {
        Some(x) => style_properties(x)
        None => empty_resolved_style()
      }
      let resolved = merge_resolved_style(paragraph_base, paragraph_direct)
      collect_run_info(element, None, runs, styles, resolved, warnings)
      if runs.is_empty() {
        runs.push({
          text: "",
          bold: resolved.bold.unwrap_or(false),
          italic: resolved.italic.unwrap_or(false),
          underline: resolved.underline.unwrap_or(false),
          font_size_half_points: resolved.font_size_half_points,
          font_ascii: resolved.font_ascii,
          font_east_asia: resolved.font_east_asia,
          font_complex_script: resolved.font_complex_script,
          color: resolved.color,
          highlight: resolved.highlight,
          strike: resolved.strike.unwrap_or(false),
          hyperlink: None,
        })
      }
      paragraphs.push({
        metadata: resolved.paragraph,
        outline_level: resolved.outline_level,
        runs,
      })
      match pr {
        Some(x) =>
          match x.first_child("sectPr") {
            Some(s) => sections.push(parse_section(s))
            None => ()
          }
        None => ()
      }
    }
    "tbl" => {
      let rows = []
      let grid_widths_twips = []
      match element.first_child("tblGrid") {
        Some(grid) =>
          for column in grid.children_named("gridCol") {
            match nonnegative_int_attr(Some(column), "w") {
              Some(width) => grid_widths_twips.push(width)
              None => ()
            }
          }
        None => ()
      }
      for tr in element.children_named("tr") {
        let cells = []
        for tc in tr.children_named("tc") {
          cells.push(parse_cell_info(tc, styles, warnings))
        }
        let row_properties = tr.first_child("trPr")
        let row_height = child(row_properties, "trHeight")
        rows.push({
          cells,
          height_twips: nonnegative_int_attr(row_height, "val"),
          height_rule: string_attr(row_height, "hRule"),
        })
      }
      tables.push({ rows, grid_widths_twips })
    }
    "sectPr" => sections.push(parse_section(element))
    _ =>
      for child in element.child_elements() {
        inspect_element(child, paragraphs, tables, sections, styles, warnings)
      }
  }
}

///|
fn parse_section(s : @xml.Element) -> SectionInfo {
  let size = s.first_child("pgSz")
  let margin = s.first_child("pgMar")
  {
    page_width_twips: nonnegative_int_attr(size, "w"),
    page_height_twips: nonnegative_int_attr(size, "h"),
    margin_top_twips: signed_int_attr(margin, "top"),
    margin_right_twips: nonnegative_int_attr(margin, "right"),
    margin_bottom_twips: signed_int_attr(margin, "bottom"),
    margin_left_twips: nonnegative_int_attr(margin, "left"),
  }
}
