///|
#derive(Debug, Eq)
pub(all) suberror PdfTextError {
  TooLarge
  InvalidPdf(String)
  Encrypted
  Empty
}

///|
pub extend PdfTextError with @debug.Debug::{to_repr}

///|
pub extend PdfTextError with Eq::{equal, not_equal}

///|
/// Extract page-oriented Markdown from a bounded PDF without OCR.
pub fn extract(
  content : FixedArray[Byte],
  max_bytes~ : Int32 = 8_000_000,
) -> String raise PdfTextError {
  extract_with_details(content, max_bytes~).text
}

///|
/// Extract text with explicit source-checksum and page-limit metadata.
pub fn extract_with_details(
  content : FixedArray[Byte],
  max_bytes~ : Int32 = 8_000_000,
  page_start~ : Int32 = 1,
  page_limit~ : Int32 = 100,
) -> PdfTextResult raise PdfTextError {
  if max_bytes < 1 ||
    max_bytes > 32 * 1024 * 1024 ||
    content.length() > max_bytes {
    raise TooLarge
  }
  if page_start < 1 || page_limit < 1 || page_limit > 100 {
    raise InvalidPdf(
      "Page range requires page_start >= 1 and page_limit 1..100",
    )
  }
  let data = Bytes::from_array(content)
  let (document, metadata_warnings) = try
    @pdflite.pdf_read_document_from_bytes(data)
  catch {
    InvalidFlateData => recover_metadata_document(data)
    error => raise InvalidPdf("Document loading: \{Repr(error)}")
  } noraise {
    document => (document, [])
  }
  if document.is_encrypted() {
    raise Encrypted
  }
  let warnings = if metadata_warnings.is_empty() {
    recover_document_text_streams(document)
  } else {
    metadata_warnings
  }
  let page_count = document.pages_of_pagetree_quick() catch {
    error => raise InvalidPdf("Page-tree loading: \{Repr(error)}")
  }
  if page_start > page_count {
    raise InvalidPdf("Requested page starts after the end of the PDF")
  }
  let page_end = (page_start + page_limit - 1).min(page_count)
  let selected = if page_start != 1 || page_end != page_count {
    let pages : Array[Int32] = []
    for number in page_start..<=page_end {
      pages.push(number)
    }
    document.pdf_of_pages(pages) catch {
      error => raise InvalidPdf("Page selection: \{Repr(error)}")
    }
  } else {
    document
  }
  let extracted = @markdown.pdf_document_to_markdown(selected) catch {
    error => raise InvalidPdf("Text decoding: \{Repr(error)}")
  }
  // The PDF subset renumbers pages. Restore original source page numbers so
  // citations remain stable across bounded extraction windows.
  let output = StringBuilder()
  let mut number = page_start
  for line in extracted.split("\n") {
    if line.has_prefix("# Page ") {
      output.write_string("# Page " + number.to_string() + "\n")
      number += 1
    } else {
      output.write_string(line.to_owned() + "\n")
    }
  }
  let markdown = output.to_string()
  let mut has_text = false
  for line in markdown.split("\n") {
    let line = line.trim()
    if line != "" && !line.has_prefix("# Page ") {
      has_text = true
      break
    }
  }
  if !has_text && page_start == 1 && page_end == page_count {
    raise Empty
  }
  if markdown.length() > 1_000_000 {
    raise TooLarge
  }
  {
    text: if warnings.is_empty() {
      markdown
    } else {
      "> MoonLeaf source warning: one or more original compressed PDF streams could not be verified. Extraction used complete source objects and bounded DEFLATE recovery; see extraction warnings. Original source bytes remain unchanged and checksum verification is incomplete.\n\n" +
      markdown
    },
    extraction_warnings: warnings,
    checksum_verification: if warnings.is_empty() {
      "verified_streams_only"
    } else {
      "unverified_recovered_streams"
    },
    truncated_pages: page_start > 1 || page_end < page_count,
    page_count,
    page_start,
    page_end,
    next_page: if page_end < page_count {
      Some(page_end + 1)
    } else {
      None
    },
  }
}
