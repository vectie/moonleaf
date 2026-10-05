///|
pub(all) suberror PdfTextError {
  TooLarge
  InvalidPdf(String)
  Encrypted
  Empty
} derive(Debug, Eq)

///|
/// Extract page-oriented Markdown from a bounded PDF without OCR.
pub fn extract(content : FixedArray[Byte]) -> String raise PdfTextError {
  if content.length() > 8_000_000 {
    raise TooLarge
  }
  let document = @pdflite.pdf_read_document_from_bytes(
    Bytes::from_array(content),
  ) catch {
    error => raise InvalidPdf("\{Repr(error)}")
  }
  if document.is_encrypted() {
    raise Encrypted
  }
  let page_count = document.pages_of_pagetree_quick() catch {
    error => raise InvalidPdf("\{Repr(error)}")
  }
  let selected = if page_count > 100 {
    let pages : Array[Int] = []
    for number in 1..<=100 {
      pages.push(number)
    }
    document.pdf_of_pages(pages) catch {
      error => raise InvalidPdf("\{Repr(error)}")
    }
  } else {
    document
  }
  let markdown = @markdown.pdf_document_to_markdown(selected) catch {
    error => raise InvalidPdf("\{Repr(error)}")
  }
  let mut has_text = false
  for line in markdown.split("\n") {
    let line = line.trim()
    if line != "" && !line.has_prefix("# Page ") {
      has_text = true
      break
    }
  }
  if !has_text {
    raise Empty
  }
  if markdown.length() > 1_000_000 {
    raise TooLarge
  }
  markdown
}
