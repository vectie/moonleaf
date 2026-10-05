///|
pub using @opc {type ArchivePolicy}

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
  open_with_policy(filename, content, @opc.ArchivePolicy::default())
}

///|
/// Open and render an OOXML file with explicit ZIP/OPC resource limits.
pub fn open_with_policy(
  filename : String,
  content : FixedArray[Byte],
  policy : ArchivePolicy,
) -> @scene.Document raise MoonLeafError {
  let lower = filename.to_lower()
  if lower.has_suffix(".csv") || lower.has_suffix(".tsv") {
    let text = @utf8.decode(Bytes::from_array(content)) catch {
      _ => raise MoonLeafError::Document("invalid UTF-8")
    }
    let delimiter = if lower.has_suffix(".tsv") { '\t' } else { ',' }
    let table = @csv.parse(text, delimiter~) catch {
      _ => raise MoonLeafError::Document("invalid delimited table")
    }
    return @scene.Document::WorkbookDocument(table.workbook())
  }
  if !lower.has_suffix(".docx") &&
    !lower.has_suffix(".xlsx") &&
    !lower.has_suffix(".pptx") {
    raise MoonLeafError::UnsupportedExtension(filename)
  }
  let archive = @opc.open_with_policy(content, policy) catch {
    error => raise MoonLeafError::Package(error.to_string())
  }
  if lower.has_suffix(".docx") {
    @scene.Document::TextDocument(@docx.read(archive)) catch {
      error => raise MoonLeafError::Document("\{Repr(error)}")
    }
  } else if lower.has_suffix(".xlsx") {
    @scene.Document::WorkbookDocument(@xlsx.read(archive)) catch {
      error => raise MoonLeafError::Document("\{Repr(error)}")
    }
  } else {
    @scene.Document::PresentationDocument(@pptx.read(archive)) catch {
      error => raise MoonLeafError::Document("\{Repr(error)}")
    }
  }
}
