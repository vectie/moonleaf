///|
/// Errors reported while reading or conservatively editing an XLSX package.
pub(all) suberror XlsxError {
  MissingWorkbook
  PackageFailure(part~ : String, message~ : String)
  InvalidXml(part~ : String, message~ : String)
  InvalidWorkbook(String)
  MissingWorksheet(sheet~ : String, relationship_id~ : String)
  InvalidCellReference(String)
  InvalidSharedStringIndex(Int32)
  SheetNotFound(String)
  InvalidCoordinates(row~ : Int32, column~ : Int32)
} derive(Debug, Eq)
