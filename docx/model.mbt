///| DOCX-local semantic model.  The scene projection remains deliberately lossy;

///|
/// Callers needing layout or relationship metadata should use `inspect_document`.
pub(all) struct ParagraphMetadata {
  alignment : String?
  spacing_before_twips : Int?
  spacing_after_twips : Int?
  line_twips : Int?
  left_indent_twips : Int?
  right_indent_twips : Int?
  first_line_twips : Int?
  hanging_twips : Int?
} derive(Eq, Debug)

///|
pub(all) struct RunMetadata {
  text : String
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
}

///|
pub(all) struct ParagraphInfo {
  metadata : ParagraphMetadata
  outline_level : Int?
  runs : Array[RunMetadata]
} derive(Eq, Debug)

///|
pub(all) struct TableCellInfo {
  text : String
  grid_span : Int
  vertical_merge : String?
} derive(Eq, Debug)

///|
pub(all) struct TableInfo {
  rows : Array[Array[TableCellInfo]]
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
