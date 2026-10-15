///|
pub(all) suberror PdfTextError {
  TooLarge
  InvalidPdf(String)
  Encrypted
  Empty
} derive(Debug, Eq)

///|
pub extend PdfTextError with @debug.Debug::{to_repr}

///|
pub extend PdfTextError with Eq::{equal, not_equal}

///|
/// Extract page-oriented Markdown from a bounded PDF without OCR.
pub fn extract(
  content : FixedArray[Byte],
  max_bytes? : Int = 8_000_000,
) -> String raise PdfTextError {
  extract_with_details(content, max_bytes~).text
}

///|
/// Extract text with explicit source-checksum and page-limit metadata.
pub fn extract_with_details(
  content : FixedArray[Byte],
  max_bytes? : Int = 8_000_000,
) -> PdfTextResult raise PdfTextError {
  if max_bytes < 1 ||
    max_bytes > 32 * 1024 * 1024 ||
    content.length() > max_bytes {
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
  let warnings = recover_document_text_streams(document)
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
  {
    text: if warnings.is_empty() {
      markdown
    } else {
      "> MoonLeaf source warning: one or more original PDF streams have an invalid or incomplete zlib checksum. Text was recovered only from fully completed DEFLATE bodies; source checksum remains unverified.\n\n" +
      markdown
    },
    extraction_warnings: warnings,
    checksum_verification: if warnings.is_empty() {
      "verified_streams_only"
    } else {
      "unverified_recovered_streams"
    },
    truncated_pages: page_count > 100,
  }
}
