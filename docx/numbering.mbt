///|
priv struct NumberingInstance {
  num_id : String
  abstract_id : String
  start_overrides : Array[(Int, Int)]
}

///|
priv struct NumberingFormat {
  abstract_id : String
  level : Int
  format : String
  label_template : String
  start : Int
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
              Some(abstract_id) => {
                let start_overrides = []
                for level_override in child.children_named("lvlOverride") {
                  let level = parse_int_or(level_override.attribute("ilvl"), -1)
                  let value = match
                    level_override.first_child("startOverride") {
                    Some(start) => parse_int_or(start.attribute("val"), -1)
                    None => -1
                  }
                  if level >= 0 &&
                    level <= 8 &&
                    value >= 1 &&
                    value <= 1_000_000 {
                    start_overrides.push((level, value))
                  }
                }
                instances.push({ num_id, abstract_id, start_overrides, })
              }
              None => ()
            }
          _ => ()
        }
      "abstractNum" =>
        match child.attribute("abstractNumId") {
          Some(abstract_id) =>
            for level_element in child.children_named("lvl") {
              let level = parse_int_or(level_element.attribute("ilvl"), 0)
              let format = match level_element.first_child("numFmt") {
                Some(value) => value.attribute("val").unwrap_or("decimal")
                None => "decimal"
              }
              let label_template = match level_element.first_child("lvlText") {
                Some(value) => value.attribute("val").unwrap_or("%1.")
                None => "%1."
              }
              let raw_start = match level_element.first_child("start") {
                Some(value) => parse_int_or(value.attribute("val"), 1)
                None => 1
              }
              let start = if raw_start >= 1 && raw_start <= 1_000_000 {
                raw_start
              } else {
                1
              }
              formats.push({
                abstract_id,
                level,
                format,
                label_template,
                start,
              })
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
  self.info(num_id, level).format.to_lower() != "bullet"
}

///|
fn Numbering::info(self : Numbering, num_id : String, level : Int) -> ListInfo {
  let mut abstract_id : String? = None
  let mut start_override : Int? = None
  for instance in self.instances {
    if instance.num_id == num_id {
      abstract_id = Some(instance.abstract_id)
      for (override_level, start) in instance.start_overrides {
        if override_level == level {
          start_override = Some(start)
        }
      }
      break
    }
  }
  match abstract_id {
    None =>
      {
        num_id,
        level,
        format: "decimal",
        label_template: "%1.",
        start: start_override.unwrap_or(1),
      }
    Some(abstract_id) => {
      for format in self.formats {
        if format.abstract_id == abstract_id && format.level == level {
          return {
            num_id,
            level,
            format: format.format,
            label_template: format.label_template,
            start: start_override.unwrap_or(format.start),
          }
        }
      }
      {
        num_id,
        level,
        format: "decimal",
        label_template: "%1.",
        start: start_override.unwrap_or(1),
      }
    }
  }
}
