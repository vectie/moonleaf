///|
/// Pure MoonBit digest using the existing pdflite cryptography dependency.
pub fn source_sha256(source : FixedArray[Byte]) -> String {
  let digest = @digest.pdf_sha256_digest(Bytes::from_array(source)[:])
  let alphabet = "0123456789abcdef"
  let out = StringBuilder()
  for byte in digest {
    let n = byte.to_int()
    out.write_string(alphabet[n / 16:n / 16 + 1].to_owned())
    out.write_string(alphabet[n % 16:n % 16 + 1].to_owned())
  }
  out.to_string()
}

///|
/// Replace an exact structural text run and save a new package. No-op copies
/// are accepted; original targeted editor preserves unrelated source parts.
pub fn edit_copy(
  source : FixedArray[Byte],
  request : Json,
) -> (FixedArray[Byte], Json) raise PptxError {
  guard request
    is {
      "target": String(target),
      "expected": String(expected),
      "replacement": String(replacement),
      ..
    } else {
    raise InvalidPresentation(
      message="edit-copy requires target,expected,replacement",
    )
  }
  let digest = source_sha256(source)
  match request {
    { "source_sha256": String(expected_digest), .. } if expected_digest !=
      digest =>
      raise InvalidPresentation(
        message="source_sha256 no longer matches the source presentation",
      )
    { "source_sha256": Null, .. } | { "source_sha256"? : None, .. } => ()
    { "source_sha256": String(_), .. } => ()
    _ =>
      raise InvalidPresentation(
        message="source_sha256 must be text when supplied",
      )
  }
  let archive = @opc.open(source) catch {
    _ => raise InvalidPresentation(message="invalid PPTX package")
  }
  let edited = set_target_text(archive, target, expected, replacement)
  let copy = if expected == replacement {
    source
  } else {
    @opc.save(edited) catch {
      _ =>
        raise InvalidPresentation(message="could not save edited PPTX package")
    }
  }
  (
    copy,
    {
      "contract": "moonleaf.pptx-edit-copy.v1",
      "changed": (expected != replacement).to_json(),
      "bytes": copy.length().to_json(),
      "source_sha256": digest.to_json(),
    },
  )
}

///|
fn visual_sources(
  container : @opc.Package,
  tree : @xml.Element,
  part : String,
  relationships : Array[@opc.Relationship],
  output : Array[@xml.Element],
) -> Unit {
  for element in tree.child_elements() {
    match element.local_name() {
      "sp" => output.push(element)
      "pic" => {
        let id = match first_descendant(element, "blip") {
          Some(blip) =>
            blip
            .attribute("embed")
            .unwrap_or(blip.attribute("link").unwrap_or(""))
          None => ""
        }
        if image_relationship_part(container, part, relationships, id)
          is Some(_) {
          output.push(element)
        }
      }
      "grpSp" => visual_sources(container, element, part, relationships, output)
      _ => ()
    }
  }
}

///|
/// Build an embeddable SVG scene with readable outline/tables/notes and exact
/// original text targets. The digest is supplied from the original file bytes.
pub fn preview_json(
  container : @opc.Package,
  source_sha256 : String,
) -> Json raise PptxError {
  let outline = read_outline(container)
  let warnings : Array[String] = []
  for warning in outline.warnings {
    warnings.push("Text outline: " + warning)
  }
  let scene = read(container) catch {
    error => {
      warnings.push(
        "Slide scene unavailable; readable outline remains: " +
        error.to_string(),
      )
      { slides: [], warnings: [], }
    }
  }
  for warning in scene.warnings {
    warnings.push(warning.code + ": " + warning.message)
  }
  let targets = text_targets(container) catch {
    error => {
      warnings.push(
        "Exact text targets unavailable for this presentation: " +
        error.to_string(),
      )
      []
    }
  }
  let tables = read_tables(container) catch {
    error => {
      warnings.push(
        "Structured tables unavailable; outline tables remain: " +
        error.to_string(),
      )
      []
    }
  }
  let root = parse_xml_part(container, presentation_part, presentation=true)
  let (width, height) = slide_dimensions(root)
  let palette = preview_palette(container)
  let slides : Array[Json] = []
  for index, slide in outline.slides {
    let xml = parse_xml_part(container, slide.part, presentation=false)
    let relationships = container.relationships(slide.part) catch { _ => [] }
    let originals : Array[@xml.Element] = []
    visual_sources(
      container,
      outline_tree(xml, slide.part),
      slide.part,
      relationships,
      originals,
    )
    let svg = if index < scene.slides.length() {
      preview_svg(
        container,
        scene.slides[index],
        xml,
        originals,
        slide.part,
        relationships,
        palette,
        warnings,
      )
    } else {
      preview_outline_svg(slide, width, height)
    }
    let title = if slide.title != "" {
      slide.title
    } else {
      let mut fallback = ""
      for block in slide.blocks {
        if !block.paragraphs.is_empty() {
          fallback = block.paragraphs[0]
          break
        }
      }
      fallback
    }
    slides.push({
      "number": slide.number.to_json(),
      "name": slide.name.to_json(),
      "part": slide.part.to_json(),
      "hidden": slide.hidden.to_json(),
      "title": title.to_json(),
      "svg": svg.to_json(),
      "blocks": slide.blocks.to_json(),
      "notes": slide.notes.to_json(),
      "tables": tables
      .filter(table => table.slide_number == slide.number)
      .to_json(),
      "targets": targets
      .filter(target => target.slide_number == slide.number)
      .to_json(),
    })
  }
  {
    "contract": "moonleaf.pptx-preview.v1",
    "source_sha256": source_sha256.to_json(),
    "width": width.to_json(),
    "height": height.to_json(),
    "slides": slides.to_json(),
    "warnings": warnings.to_json(),
  }
}
