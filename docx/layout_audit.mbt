///|
/// MoonLeaf-owned, renderer-independent DOCX layout audit contract.
pub fn layout_audit_contract_version() -> String {
  "moonleaf.docx-layout-audit.v1"
}

///| Evidence that two DOCX packages retain the same format-bearing structure.

///|

///| `cached_page_count_*` is metadata last written by an office application;

///| it is not a fresh pagination result. Physical page equality requires a

///|
/// valid `@render.Evidence` receipt from MoonLeaf's pagination renderer.
pub(all) struct LayoutAudit {
  contract_version : String
  equivalent : Bool
  non_document_parts_equal : Bool
  main_structure_equal : Bool
  paragraph_layout_equal : Bool
  run_style_layout_equal : Bool
  table_layout_equal : Bool
  section_layout_equal : Bool
  explicit_page_breaks_equal : Bool
  reference_cached_page_count : Int?
  candidate_cached_page_count : Int?
  reference_paragraph_count : Int
  candidate_paragraph_count : Int
  reference_table_count : Int
  candidate_table_count : Int
  reference_explicit_page_break_count : Int
  candidate_explicit_page_break_count : Int
  inserted_text_slot_paragraphs : Int
  diagnostics : Array[String]
} derive(Eq)

///|
priv struct RunStyle {
  bold : Bool
  italic : Bool
  underline : Bool
  font_size_half_points : Int?
  font_ascii : String?
  font_east_asia : String?
  font_complex_script : String?
  color : String?
  highlight : String?
  strike : Bool
  hyperlink : String?
} derive(Eq)

///|
fn run_style(run : RunMetadata) -> RunStyle {
  {
    bold: run.bold,
    italic: run.italic,
    underline: run.underline,
    font_size_half_points: run.font_size_half_points,
    font_ascii: run.font_ascii,
    font_east_asia: run.font_east_asia,
    font_complex_script: run.font_complex_script,
    color: run.color,
    highlight: run.highlight,
    strike: run.strike,
    hyperlink: run.hyperlink,
  }
}

///|
fn collapsed_run_styles(paragraph : ParagraphInfo) -> Array[RunStyle] {
  let styles : Array[RunStyle] = []
  for run in paragraph.runs {
    let style = run_style(run)
    if styles.last() != Some(style) {
      styles.push(style)
    }
  }
  styles
}

///|
fn paragraph_layouts_equal(
  reference : Array[ParagraphInfo],
  candidate : Array[ParagraphInfo],
) -> Bool {
  if reference.length() != candidate.length() {
    return false
  }
  for index = 0; index < reference.length(); index = index + 1 {
    if reference[index].metadata != candidate[index].metadata ||
      reference[index].outline_level != candidate[index].outline_level {
      return false
    }
  }
  true
}

///|
fn run_style_layouts(
  reference : Array[ParagraphInfo],
  candidate : Array[ParagraphInfo],
) -> (Bool, Int) {
  if reference.length() != candidate.length() {
    return (false, 0)
  }
  let inserted_slots = Ref(0)
  for index = 0; index < reference.length(); index = index + 1 {
    let expected = collapsed_run_styles(reference[index])
    let actual = collapsed_run_styles(candidate[index])
    if expected.is_empty() && !actual.is_empty() {
      // A fillable copy may materialize one text run in an otherwise empty
      // source paragraph. Paragraph properties remain the format authority.
      inserted_slots.val = inserted_slots.val + 1
    } else if expected != actual {
      return (false, inserted_slots.val)
    }
  }
  (true, inserted_slots.val)
}

///|
fn tables_equal(
  reference : Array[TableInfo],
  candidate : Array[TableInfo],
) -> Bool {
  if reference.length() != candidate.length() {
    return false
  }
  for table_index = 0
      table_index < reference.length()
      table_index = table_index + 1 {
    let left = reference[table_index]
    let right = candidate[table_index]
    if left.grid_widths_twips != right.grid_widths_twips ||
      left.rows.length() != right.rows.length() {
      return false
    }
    for row_index = 0; row_index < left.rows.length(); row_index = row_index + 1 {
      let left_row = left.rows[row_index]
      let right_row = right.rows[row_index]
      if left_row.length() != right_row.length() {
        return false
      }
      for cell_index = 0
          cell_index < left_row.length()
          cell_index = cell_index + 1 {
        let left_cell = left_row[cell_index]
        let right_cell = right_row[cell_index]
        if left_cell.grid_span != right_cell.grid_span ||
          left_cell.vertical_merge != right_cell.vertical_merge ||
          left_cell.width_twips != right_cell.width_twips {
          return false
        }
      }
    }
  }
  true
}

///|
fn text_only_run(element : @xml.Element) -> Bool {
  if element.name != "w:r" {
    return false
  }
  for child in element.children {
    match child {
      Text(text) => if text.trim() != "" { return false }
      Element(nested) =>
        if nested.name != "w:rPr" && nested.name != "w:t" {
          return false
        }
    }
  }
  true
}

///|
fn layout_structure(element : @xml.Element) -> @xml.Element {
  let children : Array[@xml.Node] = []
  for child in element.children {
    match child {
      Text(text) =>
        if element.name == "w:t" {
          children.push(Text(""))
        } else {
          children.push(Text(text))
        }
      Element(nested) =>
        if !text_only_run(nested) {
          children.push(Element(layout_structure(nested)))
        }
    }
  }
  let attributes = if element.name == "w:t" { [] } else { element.attributes }
  { name: element.name, attributes, children }
}

///|
fn main_structure(document_package : @opc.Package) -> String raise DocxError {
  let source = document_package.text("word/document.xml") catch {
    MissingPart(_) => raise MissingDocument
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  @xml.serialize(layout_structure(root))
}

///|
fn non_document_parts_equal(
  reference : @opc.Package,
  candidate : @opc.Package,
) -> Bool {
  let reference_names = reference.parts
    .filter(part => part.name != "word/document.xml")
    .map(part => part.name)
  let candidate_names = candidate.parts
    .filter(part => part.name != "word/document.xml")
    .map(part => part.name)
  reference_names.sort_by(String::compare)
  candidate_names.sort_by(String::compare)
  if reference_names != candidate_names {
    return false
  }
  for name in reference_names {
    let left = reference.part(name)
    let right = candidate.part(name)
    if left is None ||
      right is None ||
      left.unwrap().content != right.unwrap().content {
      return false
    }
  }
  true
}

///|
fn cached_page_count(document_package : @opc.Package) -> Int? {
  guard document_package.has_part("docProps/app.xml") else { return None }
  let source = document_package.text("docProps/app.xml") catch {
    _ => return None
  }
  let root = @xml.parse(source) catch { _ => return None }
  fn find_pages(element : @xml.Element) -> String? {
    if element.local_name() == "Pages" {
      return Some(element.text_content())
    }
    for child in element.child_elements() {
      match find_pages(child) {
        Some(value) => return Some(value)
        None => ()
      }
    }
    None
  }
  match find_pages(root) {
    Some(value) => {
      let parsed : Int = @strconv.from_str(value) catch { _ => return None }
      if parsed > 0 {
        Some(parsed)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// Compare format-bearing structure without claiming to paginate the files.
pub fn audit_layout_equivalence(
  reference : @opc.Package,
  candidate : @opc.Package,
) -> LayoutAudit raise DocxError {
  let reference_document = inspect_document(reference)
  let candidate_document = inspect_document(candidate)
  let reference_preview = preview_document(reference)
  let candidate_preview = preview_document(candidate)
  let non_document_parts_equal = non_document_parts_equal(reference, candidate)
  let main_structure_equal = main_structure(reference) ==
    main_structure(candidate)
  let paragraph_layout_equal = paragraph_layouts_equal(
    reference_document.paragraphs,
    candidate_document.paragraphs,
  )
  let (run_style_layout_equal, inserted_text_slot_paragraphs) = run_style_layouts(
    reference_document.paragraphs,
    candidate_document.paragraphs,
  )
  let table_layout_equal = tables_equal(
    reference_document.tables,
    candidate_document.tables,
  )
  let section_layout_equal = reference_document.sections ==
    candidate_document.sections
  let reference_explicit_page_break_count = reference_preview.blocks
    .filter(block => block is FlowPageBreak)
    .length()
  let candidate_explicit_page_break_count = candidate_preview.blocks
    .filter(block => block is FlowPageBreak)
    .length()
  let explicit_page_breaks_equal = reference_explicit_page_break_count ==
    candidate_explicit_page_break_count
  let reference_cached_page_count = cached_page_count(reference)
  let candidate_cached_page_count = cached_page_count(candidate)
  let cached_page_counts_equal = reference_cached_page_count is Some(_) &&
    reference_cached_page_count == candidate_cached_page_count
  let diagnostics : Array[String] = []
  if !non_document_parts_equal {
    diagnostics.push("NON_DOCUMENT_PARTS_DIFFER")
  }
  if !main_structure_equal {
    diagnostics.push("MAIN_STRUCTURE_DIFFERS")
  }
  if !paragraph_layout_equal {
    diagnostics.push("PARAGRAPH_LAYOUT_DIFFERS")
  }
  if !run_style_layout_equal {
    diagnostics.push("RUN_STYLE_LAYOUT_DIFFERS")
  }
  if !table_layout_equal {
    diagnostics.push("TABLE_LAYOUT_DIFFERS")
  }
  if !section_layout_equal {
    diagnostics.push("SECTION_LAYOUT_DIFFERS")
  }
  if !explicit_page_breaks_equal {
    diagnostics.push("EXPLICIT_PAGE_BREAKS_DIFFER")
  }
  if !cached_page_counts_equal {
    diagnostics.push("CACHED_PAGE_COUNT_DIFFERS_OR_MISSING")
  }
  let equivalent = diagnostics.is_empty()
  {
    contract_version: layout_audit_contract_version(),
    equivalent,
    non_document_parts_equal,
    main_structure_equal,
    paragraph_layout_equal,
    run_style_layout_equal,
    table_layout_equal,
    section_layout_equal,
    explicit_page_breaks_equal,
    reference_cached_page_count,
    candidate_cached_page_count,
    reference_paragraph_count: reference_document.paragraphs.length(),
    candidate_paragraph_count: candidate_document.paragraphs.length(),
    reference_table_count: reference_document.tables.length(),
    candidate_table_count: candidate_document.tables.length(),
    reference_explicit_page_break_count,
    candidate_explicit_page_break_count,
    inserted_text_slot_paragraphs,
    diagnostics,
  }
}
