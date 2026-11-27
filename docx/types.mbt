///|
/// Errors reported while reading or conservatively editing a DOCX package.
#derive(Debug, Eq)
pub(all) suberror DocxError {
  MissingDocument
  InvalidDocument(String)
  InvalidReplacement(String)
}
