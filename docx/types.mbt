///|
/// Errors reported while reading or conservatively editing a DOCX package.
pub(all) suberror DocxError {
  MissingDocument
  InvalidDocument(String)
  InvalidReplacement(String)
} derive(Debug, Eq)
