///|
/// Errors produced while reading or conservatively editing PresentationML.
pub(all) suberror PptxError {
  MissingPresentation
  InvalidPackagePart(part~ : String)
  InvalidPresentation(message~ : String)
  MissingSlide(relationship_id~ : String)
  InvalidSlide(part~ : String, message~ : String)
  InvalidNumber(part~ : String, value~ : String)
} derive(Debug, Eq)

///|
pub fn PptxError::to_string(self : PptxError) -> String {
  match self {
    MissingPresentation => "missing ppt/presentation.xml"
    InvalidPackagePart(part~) => "invalid or missing package part: \{part}"
    InvalidPresentation(message~) => "invalid presentation: \{message}"
    MissingSlide(relationship_id~) =>
      "missing slide relationship: \{relationship_id}"
    InvalidSlide(part~, message~) => "invalid slide \{part}: \{message}"
    InvalidNumber(part~, value~) => "invalid numeric value in \{part}: \{value}"
  }
}
