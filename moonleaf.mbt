///|
pub(all) suberror MoonLeafError {
  UnsupportedExtension(String)
  Package(String)
  Document(String)
} derive(Debug, Eq)

///|
pub fn open(
  filename : String,
  content : FixedArray[Byte],
) -> @scene.Document raise MoonLeafError {
  let lower = filename.to_lower()
  if !lower.has_suffix(".docx") &&
    !lower.has_suffix(".xlsx") &&
    !lower.has_suffix(".pptx") {
    raise MoonLeafError::UnsupportedExtension(filename)
  }
  let archive = @opc.open(content) catch {
    error => raise MoonLeafError::Package(error.to_string())
  }
  if lower.has_suffix(".docx") {
    @scene.Document::TextDocument(@docx.read(archive)) catch {
      error => raise MoonLeafError::Document("\{to_repr(error)}")
    }
  } else if lower.has_suffix(".xlsx") {
    @scene.Document::WorkbookDocument(@xlsx.read(archive)) catch {
      error => raise MoonLeafError::Document("\{to_repr(error)}")
    }
  } else {
    @scene.Document::PresentationDocument(@pptx.read(archive)) catch {
      error => raise MoonLeafError::Document("\{to_repr(error)}")
    }
  }
}
