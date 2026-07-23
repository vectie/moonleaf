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
  for index = 0, total = 0; index < value.length(); {
    let digit = value[index]
    if digit < '0' || digit > '9' {
      raise InvalidNumber(part~, value~)
    }
    continue index + 1, total * 10 + digit.to_int() - '0'.to_int()
  } nobreak {
    total
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
fn normalized_part_name(name : String) -> String {
  if name.has_prefix("/") {
    name[1:].to_owned()
  } else {
    name
  }
}

///|
fn resolve_target(source_part : String, target : String) -> String {
  if target.has_prefix("/") {
    return normalized_part_name(target)
  }
  let base = match source_part.rev_find("/") {
    Some(index) => source_part[:index].to_owned()
    None => ""
  }
  let segments : Array[String] = []
  if base != "" {
    for segment in base.split("/") {
      segments.push(segment.to_owned())
    }
  }
  for segment_view in target.split("/") {
    let segment = segment_view.to_owned()
    match segment {
      "" | "." => ()
      ".." =>
        match segments.pop() {
          Some(_) | None => ()
        }
      _ => segments.push(segment)
    }
  }
  segments.join("/")
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
