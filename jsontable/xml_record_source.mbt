///|
fn record_xml_at(source : String, offset : Int, token : String) -> Bool {
  offset + token.length() <= source.length() &&
  source.unsafe_substring(start=offset, end=offset + token.length()) == token
}

///|
fn record_xml_space(c : UInt16) -> Bool {
  c == ' ' || c == '\n' || c == '\t'
}

///|
fn record_xml_end(
  source : String,
  start : Int,
  token : String,
) -> Int raise XmlRecordError {
  match source.unsafe_substring(start~, end=source.length()).find(token) {
    Some(index) => start + index
    None => raise InvalidRecordXml("Unterminated XML construct")
  }
}

///|
/// Tighten the intentionally tolerant shared DOM parser for this intake subset.
/// Normalize XML line endings and literal attribute whitespace. Character
/// references are left for the shared parser and retain their referenced value.
fn validate_record_xml_source(source : String) -> String raise XmlRecordError {
  let mut i = 0
  while i < source.length() {
    let c = source[i].to_int()
    if (c < 0x20 && c != 9 && c != 10 && c != 13) || c == 0xfffe || c == 0xffff {
      raise InvalidRecordXml("Invalid XML character")
    }
    if c >= 0xd800 && c <= 0xdbff {
      if i + 1 >= source.length() ||
        source[i + 1] < 0xdc00 ||
        source[i + 1] > 0xdfff {
        raise InvalidRecordXml("Unpaired Unicode surrogate")
      }
      i += 1
    } else if c >= 0xdc00 && c <= 0xdfff {
      raise InvalidRecordXml("Unpaired Unicode surrogate")
    }
    i += 1
  }
  let source = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let out = StringBuilder()
  i = 0
  if source.has_prefix("\u{FEFF}") {
    i = 1
  }
  while i < source.length() {
    if record_xml_at(source, i, "<!--") {
      let end = record_xml_end(source, i + 4, "-->")
      let comment = source.unsafe_substring(start=i + 4, end~)
      if comment.find("--") is Some(_) || comment.has_suffix("-") {
        raise InvalidRecordXml("Invalid XML comment")
      }
      out.write_string(source.unsafe_substring(start=i, end=end + 3))
      i = end + 3
    } else if record_xml_at(source, i, "<![CDATA[") {
      let end = record_xml_end(source, i + 9, "]]>")
      out.write_string(source.unsafe_substring(start=i, end=end + 3))
      i = end + 3
    } else if record_xml_at(source, i, "<?") {
      let end = record_xml_end(source, i + 2, "?>")
      if (i != 0 && !(i == 1 && source.has_prefix("\u{FEFF}"))) ||
        !record_xml_at(source, i, "<?xml") ||
        i + 5 >= source.length() ||
        !record_xml_space(source[i + 5]) {
        raise InvalidRecordXml(
          "Only an initial XML 1.0 declaration is supported; processing instructions are not",
        )
      }
      let body = source.unsafe_substring(start=i + 6, end~)
      if body.contains_char('&') {
        raise InvalidRecordXml(
          "Character references are not permitted in an XML declaration",
        )
      }
      // Validate declaration attributes using this same bounded tag scanner.
      let declaration = validate_record_xml_source(
        "<declaration " + body + "/>",
      )
      let parsed = @xml.parse(declaration) catch {
        _ => raise InvalidRecordXml("Invalid XML declaration")
      }
      if parsed.attributes.is_empty() ||
        parsed.attributes[0].name != "version" ||
        parsed.attributes[0].value != "1.0" {
        raise InvalidRecordXml("Only XML version 1.0 is supported")
      }
      let mut standalone = false
      for index, attribute in parsed.attributes {
        if index > 0 {
          match attribute.name {
            "encoding" =>
              if standalone || attribute.value.to_upper() != "UTF-8" {
                raise InvalidRecordXml("Only UTF-8 XML input is supported")
              }
            "standalone" => {
              if attribute.value != "yes" && attribute.value != "no" {
                raise InvalidRecordXml("Invalid standalone declaration")
              }
              standalone = true
            }
            _ => raise InvalidRecordXml("Invalid XML declaration attribute")
          }
        }
      }
      i = end + 2
    } else if record_xml_at(source, i, "<!") {
      raise InvalidRecordXml("DTD and entity declarations are forbidden")
    } else if source[i] == '<' {
      out.write_string("<")
      i += 1
      let closing = i < source.length() && source[i] == '/'
      if closing {
        out.write_string("/")
        i += 1
      }
      // Read a lexical QName. The DOM and namespace pass check its grammar.
      let name_start = i
      while i < source.length() &&
            !record_xml_space(source[i]) &&
            source[i] != '>' &&
            source[i] != '/' {
        i += 1
      }
      out.write_string(source.unsafe_substring(start=name_start, end=i))
      while i < source.length() &&
            source[i] != '>' &&
            !record_xml_at(source, i, "/>") {
        if !record_xml_space(source[i]) {
          raise InvalidRecordXml("Attributes require separating whitespace")
        }
        while i < source.length() && record_xml_space(source[i]) {
          out.write_string(" ")
          i += 1
        }
        if i >= source.length() ||
          source[i] == '>' ||
          record_xml_at(source, i, "/>") {
          break
        }
        if closing {
          raise InvalidRecordXml("Unexpected content in closing tag")
        }
        let attribute_start = i
        while i < source.length() &&
              !record_xml_space(source[i]) &&
              source[i] != '=' {
          if source[i] == '>' || source[i] == '<' {
            raise InvalidRecordXml("Invalid attribute")
          }
          i += 1
        }
        out.write_string(source.unsafe_substring(start=attribute_start, end=i))
        while i < source.length() && record_xml_space(source[i]) {
          out.write_string(" ")
          i += 1
        }
        if i >= source.length() || source[i] != '=' {
          raise InvalidRecordXml("Expected attribute equals")
        }
        out.write_string("=")
        i += 1
        while i < source.length() && record_xml_space(source[i]) {
          i += 1
        }
        if i >= source.length() || (source[i] != '\'' && source[i] != '"') {
          raise InvalidRecordXml("Expected quoted attribute")
        }
        let quote = source[i]
        out.write_char(quote.to_int().to_char().unwrap())
        i += 1
        let start = i
        while i < source.length() && source[i] != quote {
          i += 1
        }
        if i >= source.length() {
          raise InvalidRecordXml("Unterminated attribute")
        }
        let attribute = source.unsafe_substring(start~, end=i)
        if attribute.find("&#X") is Some(_) {
          raise InvalidRecordXml(
            "Hexadecimal character references require lowercase x",
          )
        }
        out.write_string(
          attribute
          .replace_all(old="\n", new=" ")
          .replace_all(old="\t", new=" "),
        )
        out.write_char(quote.to_int().to_char().unwrap())
        i += 1
      }
      if record_xml_at(source, i, "/>") {
        out.write_string("/>")
        i += 2
      } else if i < source.length() && source[i] == '>' {
        out.write_string(">")
        i += 1
      } else {
        raise InvalidRecordXml("Unterminated tag")
      }
    } else {
      let start = i
      while i < source.length() && source[i] != '<' {
        i += 1
      }
      let text = source.unsafe_substring(start~, end=i)
      if text.find("]]>") is Some(_) {
        raise InvalidRecordXml("CDATA terminator outside CDATA")
      }
      if text.find("&#X") is Some(_) {
        raise InvalidRecordXml(
          "Hexadecimal character references require lowercase x",
        )
      }
      out.write_string(text)
    }
  }
  out.to_string()
}
