///|
priv struct Parser {
  source : String
  mut offset : Int
}

///|
fn Parser::new(source : String) -> Parser {
  { source, offset: 0 }
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.offset >= self.source.length()
}

///|
fn Parser::starts_with(self : Parser, token : String) -> Bool {
  let end = self.offset + token.length()
  end <= self.source.length() &&
  self.source.unsafe_substring(start=self.offset, end~) == token
}

///|
fn Parser::fail(self : Parser, message : String) -> Unit raise XmlError {
  raise XmlError::InvalidXml(offset=self.offset, message~)
}

///|
fn Parser::skip_ascii_whitespace(self : Parser) -> Unit {
  while !self.at_end() &&
        (
          self.source[self.offset] == ' ' ||
          self.source[self.offset] == '\t' ||
          self.source[self.offset] == '\r' ||
          self.source[self.offset] == '\n'
        ) {
    self.offset += 1
  }
}

///|
fn Parser::consume(self : Parser, token : String) -> Bool {
  if self.starts_with(token) {
    self.offset += token.length()
    true
  } else {
    false
  }
}

///|
fn Parser::expect(self : Parser, token : String) -> Unit raise XmlError {
  if !self.consume(token) {
    self.fail("expected " + token)
  }
}

///|
fn is_name_code_unit(unit : UInt16) -> Bool {
  unit == ':' ||
  unit == '_' ||
  unit == '-' ||
  unit == '.' ||
  (unit >= '0' && unit <= '9') ||
  (unit >= 'A' && unit <= 'Z') ||
  (unit >= 'a' && unit <= 'z') ||
  unit > 0x7f
}

///|
fn Parser::parse_name(self : Parser) -> String raise XmlError {
  let start = self.offset
  while !self.at_end() && is_name_code_unit(self.source[self.offset]) {
    self.offset += 1
  }
  if self.offset == start {
    self.fail("expected XML name")
  }
  self.source.unsafe_substring(start~, end=self.offset)
}

///|
fn decode_numeric_entity(
  entity : String,
  offset : Int,
) -> String raise XmlError {
  let (digits, base) = if entity.has_prefix("#x") || entity.has_prefix("#X") {
    (entity.unsafe_substring(start=2, end=entity.length()), 16)
  } else {
    (entity.unsafe_substring(start=1, end=entity.length()), 10)
  }
  if digits.length() == 0 {
    raise XmlError::InvalidXml(offset~, message="empty numeric entity")
  }
  let mut value = 0
  for unit in digits {
    let digit = if unit >= '0' && unit <= '9' {
      unit.to_int() - ('0' : UInt16).to_int()
    } else if base == 16 && unit >= 'a' && unit <= 'f' {
      unit.to_int() - ('a' : UInt16).to_int() + 10
    } else if base == 16 && unit >= 'A' && unit <= 'F' {
      unit.to_int() - ('A' : UInt16).to_int() + 10
    } else {
      raise XmlError::InvalidXml(offset~, message="invalid numeric entity")
    }
    value = value * base + digit
  }
  match value.to_char() {
    Some(character) => character.to_string()
    None =>
      raise XmlError::InvalidXml(offset~, message="invalid Unicode entity")
  }
}

///|
fn decode_entity(entity : String, offset : Int) -> String raise XmlError {
  match entity {
    "amp" => "&"
    "lt" => "<"
    "gt" => ">"
    "quot" => "\""
    "apos" => "'"
    _ =>
      if entity.has_prefix("#") {
        decode_numeric_entity(entity, offset)
      } else {
        raise XmlError::InvalidXml(
          offset~,
          message="unknown XML entity &" + entity + ";",
        )
      }
  }
}

///|
fn decode_text(text : String, source_offset : Int) -> String raise XmlError {
  if text.find("&") is None {
    return text
  }
  let output = StringBuilder()
  let mut cursor = 0
  while cursor < text.length() {
    match text.unsafe_substring(start=cursor, end=text.length()).find("&") {
      None => {
        output.write_string(
          text.unsafe_substring(start=cursor, end=text.length()),
        )
        cursor = text.length()
      }
      Some(relative) => {
        let amp = cursor + relative
        output.write_string(text.unsafe_substring(start=cursor, end=amp))
        match
          text.unsafe_substring(start=amp + 1, end=text.length()).find(";") {
          None =>
            raise XmlError::InvalidXml(
              offset=source_offset + amp,
              message="unterminated XML entity",
            )
          Some(entity_length) => {
            let semicolon = amp + 1 + entity_length
            let entity = text.unsafe_substring(start=amp + 1, end=semicolon)
            output.write_string(decode_entity(entity, source_offset + amp))
            cursor = semicolon + 1
          }
        }
      }
    }
  }
  output.to_string()
}

///|
fn Parser::parse_quoted_value(self : Parser) -> String raise XmlError {
  if self.at_end() ||
    (self.source[self.offset] != '"' && self.source[self.offset] != '\'') {
    self.fail("expected quoted attribute value")
  }
  let quote = self.source[self.offset]
  self.offset += 1
  let start = self.offset
  while !self.at_end() && self.source[self.offset] != quote {
    self.offset += 1
  }
  if self.at_end() {
    self.fail("unterminated attribute value")
  }
  let raw = self.source.unsafe_substring(start~, end=self.offset)
  self.offset += 1
  decode_text(raw, start)
}

///|
fn Parser::skip_until(
  self : Parser,
  terminator : String,
) -> Unit raise XmlError {
  match
    self.source
    .unsafe_substring(start=self.offset, end=self.source.length())
    .find(terminator) {
    Some(relative) => self.offset += relative + terminator.length()
    None => self.fail("unterminated XML construct")
  }
}

///|
fn Parser::skip_misc(self : Parser) -> Unit raise XmlError {
  for ;; {
    self.skip_ascii_whitespace()
    if self.consume("<?") {
      self.skip_until("?>")
    } else if self.consume("<!--") {
      self.skip_until("-->")
    } else if self.consume("<!DOCTYPE") {
      let mut bracket_depth = 0
      let mut quote : UInt16? = None
      while !self.at_end() {
        let unit = self.source[self.offset]
        self.offset += 1
        match quote {
          Some(expected) => if unit == expected { quote = None }
          None =>
            if unit == '"' || unit == '\'' {
              quote = Some(unit)
            } else if unit == '[' {
              bracket_depth += 1
            } else if unit == ']' {
              bracket_depth -= 1
            } else if unit == '>' && bracket_depth == 0 {
              break
            }
        }
      }
      if self.at_end() &&
        (
          self.source.length() == 0 ||
          self.source[self.source.length() - 1] != '>'
        ) {
        self.fail("unterminated doctype")
      }
    } else {
      break
    }
  }
}

///|
fn Parser::parse_text_node(self : Parser) -> Node raise XmlError {
  let start = self.offset
  while !self.at_end() && self.source[self.offset] != '<' {
    self.offset += 1
  }
  Node::Text(
    decode_text(self.source.unsafe_substring(start~, end=self.offset), start),
  )
}

///|
fn Parser::parse_cdata(self : Parser) -> Node raise XmlError {
  self.expect("<![CDATA[")
  let start = self.offset
  match
    self.source
    .unsafe_substring(start=self.offset, end=self.source.length())
    .find("]]>") {
    Some(relative) => {
      self.offset += relative
      let text = self.source.unsafe_substring(start~, end=self.offset)
      self.offset += 3
      Node::Text(text)
    }
    None => {
      self.fail("unterminated CDATA")
      Node::Text("")
    }
  }
}

///|
fn Parser::parse_element(self : Parser) -> Element raise XmlError {
  self.expect("<")
  if self.starts_with("/") || self.starts_with("!") || self.starts_with("?") {
    self.fail("expected element")
  }
  let name = self.parse_name()
  let attributes = []
  for ;; {
    self.skip_ascii_whitespace()
    if self.consume("/>") {
      return { name, attributes, children: [] }
    }
    if self.consume(">") {
      break
    }
    let attribute_name = self.parse_name()
    self.skip_ascii_whitespace()
    self.expect("=")
    self.skip_ascii_whitespace()
    let value = self.parse_quoted_value()
    attributes.push({ name: attribute_name, value })
  }
  let children = []
  for ;; {
    if self.at_end() {
      self.fail("unterminated element " + name)
    }
    if self.consume("</") {
      let end_name = self.parse_name()
      self.skip_ascii_whitespace()
      self.expect(">")
      if end_name != name {
        self.fail("mismatched closing element " + end_name)
      }
      break
    }
    if self.starts_with("<!--") {
      self.offset += 4
      self.skip_until("-->")
    } else if self.starts_with("<?") {
      self.offset += 2
      self.skip_until("?>")
    } else if self.starts_with("<![CDATA[") {
      children.push(self.parse_cdata())
    } else if self.starts_with("<") {
      children.push(Node::Element(self.parse_element()))
    } else {
      children.push(self.parse_text_node())
    }
  }
  { name, attributes, children }
}

///|
fn parse_document(source : String) -> Element raise XmlError {
  let parser = Parser::new(source)
  parser.skip_misc()
  if parser.at_end() {
    parser.fail("empty XML document")
  }
  let root = parser.parse_element()
  parser.skip_misc()
  if !parser.at_end() {
    parser.fail("unexpected content after root element")
  }
  root
}
