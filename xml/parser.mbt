///|
/// Bounded, prefix-tolerant lexical QName XML parser; namespace bindings are not validated.
priv struct Parser {
  source : String
  options : ParseOptions
  mut offset : Int
  mut nodes : Int
  mut decoded_text : Int
}

///|
fn Parser::new(source : String, options : ParseOptions) -> Parser {
  { source, options, offset: 0, nodes: 0, decoded_text: 0 }
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
  raise InvalidXml(offset=self.offset, message~)
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
fn Parser::skip_ws(self : Parser) -> Unit {
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
fn is_name_start(c : UInt16) -> Bool {
  c == '_' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c > 0x7f
}

///|
fn is_name_char(c : UInt16) -> Bool {
  is_name_start(c) || c == ':' || c == '-' || c == '.' || (c >= '0' && c <= '9')
}

///|
fn Parser::parse_name(self : Parser) -> String raise XmlError {
  let start = self.offset
  if self.at_end() || !is_name_start(self.source[self.offset]) {
    self.fail("invalid XML name")
  }
  self.offset += 1
  while !self.at_end() && is_name_char(self.source[self.offset]) {
    self.offset += 1
  }
  let name = self.source.unsafe_substring(start~, end=self.offset)
  match name.find(":") {
    Some(i) =>
      if i == 0 ||
        i == name.length() - 1 ||
        name.unsafe_substring(start=i + 1, end=name.length()).find(":")
        is Some(_) {
        self.fail("invalid qualified name")
      }
    None => ()
  }
  name
}

///|
fn decode_entity(entity : String, offset : Int) -> String raise XmlError {
  match entity {
    "amp" => "&"
    "lt" => "<"
    "gt" => ">"
    "quot" => "\""
    "apos" => "'"
    _ => {
      if !entity.has_prefix("#") {
        raise InvalidXml(offset~, message="unknown entity")
      }
      let hex = entity.has_prefix("#x") || entity.has_prefix("#X")
      let start = if hex { 2 } else { 1 }
      if start == entity.length() {
        raise InvalidXml(offset~, message="empty numeric entity")
      }
      let mut value = 0
      for i = start; i < entity.length(); i = i + 1 {
        let c = entity[i]
        let digit = if c >= '0' && c <= '9' {
          c.to_int() - ('0' : UInt16).to_int()
        } else if hex && c >= 'a' && c <= 'f' {
          c.to_int() - ('a' : UInt16).to_int() + 10
        } else if hex && c >= 'A' && c <= 'F' {
          c.to_int() - ('A' : UInt16).to_int() + 10
        } else {
          raise InvalidXml(offset~, message="invalid numeric entity")
        }
        let base = if hex { 16 } else { 10 }
        if value > (0x10ffff - digit) / base {
          raise InvalidXml(offset~, message="invalid Unicode entity")
        }
        value = value * base + digit
      }
      if (value >= 0xd800 && value <= 0xdfff) ||
        value == 0 ||
        (value < 0x20 && value != 0x09 && value != 0x0a && value != 0x0d) ||
        value == 0xfffe ||
        value == 0xffff {
        raise InvalidXml(offset~, message="invalid Unicode entity")
      }
      match value.to_char() {
        Some(c) => c.to_string()
        None => raise InvalidXml(offset~, message="invalid Unicode entity")
      }
    }
  }
}

///|
fn Parser::decode(
  _self : Parser,
  raw : String,
  at : Int,
) -> String raise XmlError {
  let out = StringBuilder()
  let mut cursor = 0
  while cursor < raw.length() {
    match raw.unsafe_substring(start=cursor, end=raw.length()).find("&") {
      None => {
        out.write_string(raw.unsafe_substring(start=cursor, end=raw.length()))
        cursor = raw.length()
      }
      Some(relative) => {
        let amp = cursor + relative
        out.write_string(raw.unsafe_substring(start=cursor, end=amp))
        match raw.unsafe_substring(start=amp + 1, end=raw.length()).find(";") {
          None =>
            raise InvalidXml(offset=at + amp, message="unterminated entity")
          Some(semi_rel) => {
            let semi = amp + 1 + semi_rel
            out.write_string(
              decode_entity(
                raw.unsafe_substring(start=amp + 1, end=semi),
                at + amp,
              ),
            )
            cursor = semi + 1
          }
        }
      }
    }
  }
  out.to_string()
}

///|
fn Parser::quoted(self : Parser) -> String raise XmlError {
  if self.at_end() ||
    (self.source[self.offset] != '\"' && self.source[self.offset] != '\'') {
    self.fail("expected quoted value")
  }
  let quote = self.source[self.offset]
  self.offset += 1
  let start = self.offset
  while !self.at_end() && self.source[self.offset] != quote {
    if self.source[self.offset] == '<' {
      self.fail("< in attribute")
    }
    self.offset += 1
  }
  if self.at_end() {
    self.fail("unterminated attribute")
  }
  let value = self.decode(
    self.source.unsafe_substring(start~, end=self.offset),
    start,
  )
  self.offset += 1
  value
}

///|
fn Parser::until(self : Parser, end : String) -> String raise XmlError {
  let start = self.offset
  while !self.at_end() && !self.starts_with(end) {
    self.offset += 1
  }
  if self.at_end() {
    self.fail("truncated XML construct")
  }
  let value = self.source.unsafe_substring(start~, end=self.offset)
  self.offset += end.length()
  value
}

///|
fn Parser::add_text(self : Parser, text : String) -> Unit raise XmlError {
  self.decoded_text += text.length()
  if self.decoded_text > self.options.max_total_decoded_text {
    self.fail("decoded text limit exceeded")
  }
}

///|
fn Parser::parse_element(
  self : Parser,
  _parent_scope : Array[(String, String)],
  depth : Int,
) -> Element raise XmlError {
  if depth > self.options.max_depth {
    self.fail("depth limit exceeded")
  }
  self.nodes += 1
  if self.nodes > self.options.max_nodes {
    self.fail("node limit exceeded")
  }
  self.expect("<")
  let qname = self.parse_name()
  let attrs : Array[Attribute] = []
  self.skip_ws()
  while !self.at_end() && !self.starts_with(">") && !self.starts_with("/>") {
    if attrs.length() >= self.options.max_attributes_per_element {
      self.fail("attribute limit exceeded")
    }
    let n = self.parse_name()
    self.skip_ws()
    self.expect("=")
    self.skip_ws()
    let v = self.quoted()
    for a in attrs {
      if a.name == n {
        self.fail("duplicate attribute")
      }
    }
    attrs.push({ name: n, value: v })
    self.skip_ws()
  }
  let children = []
  if self.consume("/>") {
    return { name: qname, attributes: attrs, children }
  }
  self.expect(">")
  while !self.at_end() && !self.starts_with("</") {
    if self.starts_with("<!--") {
      self.offset += 4
      ignore(self.until("-->"))
    } else if self.starts_with("<![CDATA[") {
      self.offset += 9
      let text = self.until("]]>")
      self.add_text(text)
      self.nodes += 1
      if self.nodes > self.options.max_nodes {
        self.fail("node limit exceeded")
      }
      children.push(Text(text))
    } else if self.starts_with("<!DOCTYPE") || self.starts_with("<!ENTITY") {
      self.fail("DTD and entity declarations are forbidden")
    } else if self.starts_with("<?") {
      self.offset += 2
      ignore(self.until("?>"))
    } else if self.starts_with("<") {
      children.push(Element(self.parse_element(_parent_scope, depth + 1)))
    } else {
      let start = self.offset
      while !self.at_end() && !self.starts_with("<") {
        self.offset += 1
      }
      let text = self.decode(
        self.source.unsafe_substring(start~, end=self.offset),
        start,
      )
      self.add_text(text)
      if text.length() > 0 {
        self.nodes += 1
        if self.nodes > self.options.max_nodes {
          self.fail("node limit exceeded")
        }
        children.push(Text(text))
      }
    }
  }
  self.expect("</")
  let close = self.parse_name()
  if close != qname {
    self.fail("mismatched closing element " + close)
  }
  self.skip_ws()
  self.expect(">")
  { name: qname, attributes: attrs, children }
}

///|
fn parse_document_with_options(
  source : String,
  options : ParseOptions,
) -> Element raise XmlError {
  if options.max_input_utf16 < 0 ||
    options.max_depth < 0 ||
    options.max_nodes < 0 ||
    options.max_attributes_per_element < 0 ||
    options.max_total_decoded_text < 0 {
    raise InvalidXml(offset=0, message="negative parse limit")
  }
  if source.length() > options.max_input_utf16 {
    raise InvalidXml(offset=0, message="input limit exceeded")
  }
  let p = Parser::new(source, options)
  p.skip_ws()
  if p.starts_with("<?xml") {
    p.offset += 5
    ignore(p.until("?>"))
    p.skip_ws()
  }
  while p.starts_with("<!--") || p.starts_with("<?") {
    if p.starts_with("<!--") {
      p.offset += 4
      ignore(p.until("-->"))
    } else {
      p.offset += 2
      ignore(p.until("?>"))
    }
    p.skip_ws()
  }
  if p.starts_with("<!DOCTYPE") || p.starts_with("<!ENTITY") {
    p.fail("DTD and entity declarations are forbidden")
  }
  let root = p.parse_element([], 1)
  p.skip_ws()
  while p.starts_with("<!--") || p.starts_with("<?") {
    if p.starts_with("<!--") {
      p.offset += 4
      ignore(p.until("-->"))
    } else {
      p.offset += 2
      ignore(p.until("?>"))
    }
    p.skip_ws()
  }
  if !p.at_end() {
    p.fail("content after root element")
  }
  root
}
