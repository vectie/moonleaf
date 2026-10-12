///| DOCX-local semantic model.  The scene projection remains deliberately lossy;

///|
/// Callers needing layout or relationship metadata should use `inspect_document`.
pub(all) struct ParagraphMetadata {
  alignment : String?
  spacing_before_twips : Int?
  spacing_after_twips : Int?
  line_twips : Int?
  line_rule : String?
  left_indent_twips : Int?
  right_indent_twips : Int?
  first_line_twips : Int?
  hanging_twips : Int?
} derive(Eq, Debug)

///|
pub(all) struct RunMetadata {
  text : String
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
} derive(Eq, Debug)

///|
/// Internal resolved style properties used by `inspect_document`.
/// Direct paragraph/run formatting is applied after this inherited cascade.
priv struct ResolvedStyle {
  outline_level : Int?
  paragraph : ParagraphMetadata
  font_ascii : String?
  font_east_asia : String?
  font_complex_script : String?
  color : String?
  highlight : String?
  strike : Bool?
  bold : Bool?
  italic : Bool?
  underline : Bool?
  font_size_half_points : Int?
}

///|
pub(all) struct ParagraphInfo {
  metadata : ParagraphMetadata
  outline_level : Int?
  list : ListInfo?
  runs : Array[RunMetadata]
} derive(Eq, Debug)

///|
/// Word numbering resolved for a paragraph. `label_template` is the source
/// `w:lvlText`, such as `%1.` or `•`; callers can render common formats while
/// retaining the list identity and explicit restart value.
pub(all) struct ListInfo {
  num_id : String
  level : Int
  format : String
  label_template : String
  start : Int
} derive(Eq, Debug)

///|
pub(all) struct TableCellInfo {
  text : String
  paragraphs : Array[ParagraphInfo]
  grid_span : Int
  vertical_merge : String?
  width_twips : Int?
  margin_top_twips : Int?
  margin_right_twips : Int?
  margin_bottom_twips : Int?
  margin_left_twips : Int?
  vertical_alignment : String?
} derive(Eq, Debug)

///|
pub(all) struct TableRowInfo {
  cells : Array[TableCellInfo]
  height_twips : Int?
  height_rule : String?
} derive(Eq, Debug)

///|
pub(all) struct TableInfo {
  rows : Array[TableRowInfo]
  grid_widths_twips : Array[Int]
} derive(Eq, Debug)

///| Ordered rich DOCX content for host renderers. This keeps the existing

///| portable text scene stable while exposing source formatting and table

///|
/// geometry that a faithful document preview needs.
pub(all) enum DocxFlowBlock {
  FlowParagraph(ParagraphInfo)
  FlowTable(TableInfo)
  FlowPageBreak
  FlowSection(SectionInfo)
} derive(Eq, Debug)

///|
pub(all) struct SectionInfo {
  page_width_twips : Int?
  page_height_twips : Int?
  margin_top_twips : Int?
  margin_right_twips : Int?
  margin_bottom_twips : Int?
  margin_left_twips : Int?
} derive(Eq, Debug)

///|
pub(all) struct ResourceInfo {
  relationship_id : String
  target : String
  external : Bool
  media_part : String?
} derive(Eq, Debug)

///|
pub(all) struct DocxDocument {
  scene : @scene.TextDocument
  paragraphs : Array[ParagraphInfo]
  tables : Array[TableInfo]
  sections : Array[SectionInfo]
  headers : Array[String]
  footers : Array[String]
  resources : Array[ResourceInfo]
  warnings : Array[@scene.Warning]
} derive(Eq, Debug)

///|
pub(all) struct DocxPreviewDocument {
  blocks : Array[DocxFlowBlock]
  headers : Array[String]
  footers : Array[String]
  resources : Array[ResourceInfo]
  warnings : Array[@scene.Warning]
} derive(Eq, Debug)

///|
/// Deterministic layout constants used by MoonLeaf's portable paginator.
pub(all) struct PaginationProfile {
  default_margin_top_twips : Int
  default_margin_right_twips : Int
  default_margin_bottom_twips : Int
  default_margin_left_twips : Int
  default_font_size_half_points : Int
  default_line_twips : Int
  table_cell_vertical_padding_twips : Int
  page_safety_twips : Int
} derive(Eq, Debug)

///|
/// One physical page projected from DOCX flow blocks.
pub(all) struct DocxPage {
  blocks : Array[DocxFlowBlock]
  used_height_twips : Int
} derive(Eq, Debug)

///| Portable MoonLeaf pagination output. This contains layout decisions, not

///|
/// raster or PDF bytes; glyph rasterization remains a renderer responsibility.
pub(all) struct PagedDocxDocument {
  pages : Array[DocxPage]
  page_width_twips : Int
  page_height_twips : Int
  margin_top_twips : Int
  margin_right_twips : Int
  margin_bottom_twips : Int
  margin_left_twips : Int
  content_width_twips : Int
  content_height_twips : Int
  diagnostics : Array[@scene.Warning]
} derive(Eq, Debug)
