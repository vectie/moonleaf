///|
priv struct NumberingInstance {
  num_id : String
  abstract_id : String
}

///|
priv struct NumberingFormat {
  abstract_id : String
  level : Int
  ordered : Bool
}

///|
priv struct Numbering {
  instances : Array[NumberingInstance]
  formats : Array[NumberingFormat]
}

///|
fn parse_int_or(value : String?, fallback : Int) -> Int {
  match value {
    None => fallback
    Some(value) =>
      try @string.parse_int(value) catch {
        _ => fallback
      } noraise {
        value => value
      }
  }
}

///|
fn load_numbering(document_package : @opc.Package) -> Numbering raise DocxError {
  if !document_package.has_part("word/numbering.xml") {
    return { instances: [], formats: [], }
  }
  let source = document_package.text("word/numbering.xml") catch {
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  let instances = []
  let formats = []
  for child in root.child_elements() {
    match child.local_name() {
      "num" =>
        match (child.attribute("numId"), child.first_child("abstractNumId")) {
          (Some(num_id), Some(abstract_id_element)) =>
            match abstract_id_element.attribute("val") {
              Some(abstract_id) => instances.push({ num_id, abstract_id, })
              None => ()
            }
          _ => ()
        }
      "abstractNum" =>
        match child.attribute("abstractNumId") {
          Some(abstract_id) =>
            for level_element in child.children_named("lvl") {
              let level = parse_int_or(level_element.attribute("ilvl"), 0)
              let ordered = match level_element.first_child("numFmt") {
                Some(format) =>
                  match format.attribute("val") {
                    Some(value) => value.to_lower() != "bullet"
                    None => true
                  }
                None => true
              }
              formats.push({ abstract_id, level, ordered, })
            }
          None => ()
        }
      _ => ()
    }
  }
  { instances, formats, }
}

///|
fn Numbering::is_ordered(
  self : Numbering,
  num_id : String,
  level : Int,
) -> Bool {
  let mut abstract_id : String? = None
  for instance in self.instances {
    if instance.num_id == num_id {
      abstract_id = Some(instance.abstract_id)
      break
    }
  }
  match abstract_id {
    None => true
    Some(abstract_id) => {
      for format in self.formats {
        if format.abstract_id == abstract_id && format.level == level {
          return format.ordered
        }
      }
      true
    }
  }
}
