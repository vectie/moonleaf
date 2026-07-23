///|
/// Errors reported while reading or conservatively editing an XLSX package.
pub(all) suberror XlsxError {
  MissingWorkbook
  PackageFailure(part~ : String, message~ : String)
  InvalidXml(part~ : String, message~ : String)
  InvalidWorkbook(String)
  MissingWorksheet(sheet~ : String, relationship_id~ : String)
  InvalidCellReference(String)
  InvalidSharedStringIndex(Int)
  SheetNotFound(String)
  InvalidCoordinates(row~ : Int, column~ : Int)
} derive(Debug, Eq)
