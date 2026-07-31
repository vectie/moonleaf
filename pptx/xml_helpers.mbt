///|
fn parse_xml_part(
  container : @opc.Package,
  part : String,
  presentation~ : Bool,
) -> @xml.Element raise PptxError {
  let source = container.text(part) catch {
    _ =>
      if presentation {
        raise MissingPresentation
      } else {
        raise InvalidPackagePart(part~)
      }
  }
  @xml.parse(source) catch {
    _ =>
      if presentation {
        raise InvalidPresentation(message="invalid XML in \{part}")
      } else {
        raise InvalidSlide(part~, message="invalid XML")
      }
  }
}

///|
fn first_descendant(element : @xml.Element, name : String) -> @xml.Element? {
  for child in element.child_elements() {
    if child.local_name() == name {
      return Some(child)
    }
    match first_descendant(child, name) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
fn relationship_id_attribute(element : @xml.Element) -> String? {
  for attribute in element.attributes {
    if attribute.name != "id" && attribute.name.has_suffix(":id") {
      return Some(attribute.value)
    }
  }
  None
}

///|
fn parse_decimal(part : String, value : String) -> Int raise PptxError {
  if value is "" {
    raise InvalidNumber(part~, value~)
  }
  let negative = value[0] == '-'
  let start = if negative { 1 } else { 0 }
  if start == value.length() {
    raise InvalidNumber(part~, value~)
  }
  // Accumulate negatively: the negative range has one extra representable value,
  // and checking before multiplication avoids relying on wrapped arithmetic.
  // MoonBit Int is a signed 32-bit value on every supported backend.
  let limit = if negative { -2147483648 } else { -2147483647 }
  let multiply_limit = -214748364
  for index = start, total = 0; index < value.length(); {
    let digit_char = value[index]
    if digit_char < '0' || digit_char > '9' {
      raise InvalidNumber(part~, value~)
    }
    let digit = digit_char.to_int() - '0'.to_int()
    if total < multiply_limit {
      raise InvalidNumber(part~, value~)
    }
    let multiplied = total * 10
    if multiplied < limit + digit {
      raise InvalidNumber(part~, value~)
    }
    continue index + 1, multiplied - digit
  } nobreak {
    if negative {
      total
    } else {
      -total
    }
  }
}

///|
fn numeric_attribute(
  element : @xml.Element,
  name : String,
  part : String,
  default~ : Int,
) -> Int raise PptxError {
  match element.attribute(name) {
    Some(value) => parse_decimal(part, value)
    None => default
  }
}

///|
fn part_stem(name : String) -> String {
  let basename = match name.rev_split_once("/") {
    Some((_, tail)) => tail.to_owned()
    None => name
  }
  match basename.rev_split_once(".") {
    Some((stem, _)) => stem.to_owned()
    None => basename
  }
}
