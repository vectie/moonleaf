///|
/// XML 1.0 excludes most controls, surrogate code units outside pairs, and
/// U+FFFE/U+FFFF. Character references cannot make these values legal XML.
fn validate_created_xml(text : String) -> Unit raise XlsxError {
  for i = 0; i < text.length(); {
    let unit = text.code_unit_at(i).to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if i + 1 >= text.length() {
        raise InvalidWorkbook("XLSX text contains an unpaired UTF-16 surrogate")
      }
      let next = text.code_unit_at(i + 1).to_int()
      if next < 0xDC00 || next > 0xDFFF {
        raise InvalidWorkbook("XLSX text contains an unpaired UTF-16 surrogate")
      }
      continue i + 2
    } else {
      if (unit < 0x20 && unit != 9 && unit != 10 && unit != 13) ||
        (unit >= 0xDC00 && unit <= 0xDFFF) ||
        unit > 0xFFFD {
        raise InvalidWorkbook(
          "XLSX text contains a character forbidden by XML 1.0",
        )
      }
      continue i + 1
    }
  }
}

///|
/// Append escaped cell text directly to the sheet builder. Large source tables
/// do not allocate a complete escaped string and cell XML string for each cell.
/// References preserve CR through XML end-of-line normalization; literal '&'
/// is escaped so a user's "&#13;" remains distinct from a carriage return.
fn write_created_xml_text(
  output : StringBuilder,
  text : String,
) -> Unit raise XlsxError {
  validate_created_xml(text)
  for character in text.iter() {
    match character {
      '&' => output.write_string("&amp;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '\r' => output.write_string("&#13;")
      _ => output.write_char(character)
    }
  }
}

///|
/// Attribute normalization also affects literal tabs and line feeds.
fn created_xml_attribute(text : String) -> String raise XlsxError {
  validate_created_xml(text)
  @xml.escape_attribute(text)
  .replace_all(old="\r", new="&#13;")
  .replace_all(old="\n", new="&#10;")
  .replace_all(old="\t", new="&#9;")
}
