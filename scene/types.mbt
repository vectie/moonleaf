///|
pub(all) enum DocumentKind {
  Text
  Spreadsheet
  Presentation
} derive(Debug, Eq)

///|
pub(all) struct Warning {
  code : String
  message : String
  part : String?
} derive(Debug, Eq)

///|
pub(all) struct TextStyle {
  bold : Bool
  italic : Bool
  underline : Bool
  font_size_half_points : Int32?
  color : String?
} derive(Debug, Eq)

///|
pub fn TextStyle::plain() -> TextStyle {
  {
    bold: false,
    italic: false,
    underline: false,
    font_size_half_points: None,
    color: None,
  }
}

///|
pub(all) struct TextRun {
  text : String
  style : TextStyle
} derive(Debug, Eq)

///|
pub(all) enum TextBlock {
  Paragraph(Array[TextRun])
  Heading(Int32, Array[TextRun])
  ListItem(level~ : Int32, ordered~ : Bool, Array[TextRun])
  Table(Array[Array[String]])
} derive(Debug, Eq)

///|
pub(all) struct TextDocument {
  blocks : Array[TextBlock]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
pub(all) enum CellValue {
  Empty
  Text(String)
  Number(String)
  Boolean(Bool)
  Formula(expression~ : String, cached~ : String?)
  Error(String)
} derive(Debug, Eq)

///|
pub(all) struct Cell {
  row : Int32
  column : Int32
  value : CellValue
  style_id : Int32?
} derive(Debug, Eq)

///|
pub(all) struct CellRange {
  start_row : Int32
  start_column : Int32
  end_row : Int32
  end_column : Int32
} derive(Debug, Eq)

///|
pub(all) struct Sheet {
  name : String
  cells : Array[Cell]
  merged_ranges : Array[CellRange]
} derive(Debug, Eq)

///|
pub(all) struct Workbook {
  sheets : Array[Sheet]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
pub(all) struct Rect {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
} derive(Debug, Eq)

///|
pub(all) enum SlideElement {
  TextBox(bounds~ : Rect, runs~ : Array[TextRun])
  Shape(kind~ : String, bounds~ : Rect, text~ : Array[TextRun])
  Image(bounds~ : Rect, relationship_id~ : String)
} derive(Debug, Eq)

///|
pub(all) struct Slide {
  name : String
  width : Int32
  height : Int32
  elements : Array[SlideElement]
} derive(Debug, Eq)

///|
pub(all) struct Presentation {
  slides : Array[Slide]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
pub(all) enum Document {
  TextDocument(TextDocument)
  WorkbookDocument(Workbook)
  PresentationDocument(Presentation)
} derive(Debug, Eq)
