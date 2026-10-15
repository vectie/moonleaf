///|
fn created_pptx_slides(
  input : Json,
) -> (String, Array[CreatedSlide]) raise PptxError {
  guard input is { "title": String(title), "slides": Array(values), .. } else {
    raise InvalidPresentation(message="PPTX creation requires title and slides")
  }
  guard values.length() >= 1 && values.length() <= 100 else {
    raise InvalidPresentation(message="PPTX creation needs 1..100 slides")
  }
  let slides : Array[CreatedSlide] = []
  let mut text_size = title.length()
  ignore(created_pptx_text(title))
  for value in values {
    guard value
      is { "title": String(slide_title), "bullets": Array(bullet_values), .. } else {
      raise InvalidPresentation(
        message="Each PPTX slide requires title and bullets",
      )
    }
    guard bullet_values.length() <= 100 else {
      raise InvalidPresentation(
        message="PPTX slide exceeds 100 bullet paragraphs",
      )
    }
    ignore(created_pptx_text(slide_title))
    let bullets : Array[String] = []
    text_size += slide_title.length()
    for bullet in bullet_values {
      guard bullet is String(text) else {
        raise InvalidPresentation(message="PPTX bullets must be strings")
      }
      ignore(created_pptx_text(text))
      text_size += text.length()
      bullets.push(text)
    }
    let notes = match value {
      { "notes": String(notes), .. } => {
        ignore(created_pptx_text(notes))
        text_size += notes.length()
        Some(notes)
      }
      { "notes": Null, .. } => None
      Object(fields) if !fields.contains("notes") => None
      _ =>
        raise InvalidPresentation(
          message="PPTX notes must be a string when supplied",
        )
    }
    guard text_size <= 2_000_000 else {
      raise InvalidPresentation(
        message="PPTX exceeds 2 million UTF-16 text units",
      )
    }
    slides.push({ title: slide_title, bullets, notes, })
  }
  (title, slides)
}

///|
fn created_pptx_content_type(name : String, subtype : String) -> String {
  "<Override PartName=\"/\{name}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.\{subtype}+xml\"/>"
}

///|
/// Create a standalone 16:9 PresentationML package from
/// `{title,slides:[{title,bullets:[String],notes?:String}]}`.
/// Title, bullet and footer shapes stay editable. Notes retain caller text.
/// The package includes its own theme, slide master, layout and optional notes
/// master, using MoonLeaf's existing OPC ZIP writer on every target.
/// Supports 1..100 slides, at most 100 bullet paragraphs per slide and two
/// million total UTF-16 text units. Invalid XML characters are rejected.
/// Dense text can wrap/shrink in an office application; no text is truncated
/// and this API does not infer slide splitting, images, charts or animations.
pub fn create(input : Json) -> FixedArray[Byte] raise PptxError {
  let (title, slides) = created_pptx_slides(input)
  let has_notes = slides.any(slide => slide.notes is Some(_))
  let content_types = StringBuilder()
  content_types <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"
  for
    (name, subtype) in [
      ("ppt/presentation.xml", "presentation.main"),
      ("ppt/slideMasters/slideMaster1.xml", "slideMaster"),
      ("ppt/slideLayouts/slideLayout1.xml", "slideLayout"),
    ] {
    content_types.write_string(created_pptx_content_type(name, subtype))
  }
  content_types <+
    "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
  let presentation = StringBuilder()
  presentation <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:presentation xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rIdMaster\"/></p:sldMasterIdLst>"
  let relationships = StringBuilder()
  relationships.write_string(
    created_pptx_relationship(
      "rIdMaster", "slideMaster", "slideMasters/slideMaster1.xml",
    ),
  )
  if has_notes {
    presentation <+
      "<p:notesMasterIdLst><p:notesMasterId r:id=\"rIdNotesMaster\"/></p:notesMasterIdLst>"
    relationships.write_string(
      created_pptx_relationship(
        "rIdNotesMaster", "notesMaster", "notesMasters/notesMaster1.xml",
      ),
    )
    content_types.write_string(
      created_pptx_content_type(
        "ppt/notesMasters/notesMaster1.xml", "notesMaster",
      ),
    )
  }
  presentation <+ "<p:sldIdLst>"
  let parts : Array[@opc.Part] = []
  for index, slide in slides {
    let ordinal = index + 1
    let path = "ppt/slides/slide\{ordinal}.xml"
    presentation <+
      "<p:sldId id=\"\{256 + index}\" r:id=\"rIdSlide\{ordinal}\"/>"
    relationships.write_string(
      created_pptx_relationship(
        "rIdSlide\{ordinal}",
        "slide",
        "slides/slide\{ordinal}.xml",
      ),
    )
    content_types.write_string(created_pptx_content_type(path, "slide"))
    parts.push(
      created_pptx_part(path, created_pptx_slide(slide, title, ordinal)),
    )
    let slide_rel = StringBuilder()
    slide_rel.write_string(
      created_pptx_relationship(
        "rIdLayout", "slideLayout", "../slideLayouts/slideLayout1.xml",
      ),
    )
    if slide.notes is Some(notes) {
      let notes_path = "ppt/notesSlides/notesSlide\{ordinal}.xml"
      content_types.write_string(
        created_pptx_content_type(notes_path, "notesSlide"),
      )
      slide_rel.write_string(
        created_pptx_relationship(
          "rIdNotes",
          "notesSlide",
          "../notesSlides/notesSlide\{ordinal}.xml",
        ),
      )
      parts.push(created_pptx_part(notes_path, created_pptx_notes(notes)))
      parts.push(
        created_pptx_part(
          "ppt/notesSlides/_rels/notesSlide\{ordinal}.xml.rels",
          created_pptx_relationships(
            created_pptx_relationship(
              "rIdNotesMaster", "notesMaster", "../notesMasters/notesMaster1.xml",
            ) +
            created_pptx_relationship(
              "rIdSlide",
              "slide",
              "../slides/slide\{ordinal}.xml",
            ),
          ),
        ),
      )
    }
    parts.push(
      created_pptx_part(
        "ppt/slides/_rels/slide\{ordinal}.xml.rels",
        created_pptx_relationships(slide_rel.to_string()),
      ),
    )
  }
  presentation <+
    "</p:sldIdLst><p:sldSz cx=\"12192000\" cy=\"6858000\" type=\"screen16x9\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/><p:defaultTextStyle><a:defPPr><a:defRPr lang=\"zh-CN\"/></a:defPPr></p:defaultTextStyle></p:presentation>"
  content_types <+ "</Types>"
  parts.push(
    created_pptx_part("[Content_Types].xml", content_types.to_string()),
  )
  parts.push(
    created_pptx_part("ppt/presentation.xml", presentation.to_string()),
  )
  parts.push(
    created_pptx_part(
      "ppt/_rels/presentation.xml.rels",
      created_pptx_relationships(relationships.to_string()),
    ),
  )
  parts.push(created_pptx_part("ppt/theme/theme1.xml", created_pptx_theme()))
  parts.push(
    created_pptx_part(
      "ppt/slideMasters/slideMaster1.xml",
      created_pptx_master(),
    ),
  )
  parts.push(
    created_pptx_part(
      "ppt/slideMasters/_rels/slideMaster1.xml.rels",
      created_pptx_relationships(
        created_pptx_relationship(
          "rIdLayout", "slideLayout", "../slideLayouts/slideLayout1.xml",
        ) +
        created_pptx_relationship("rIdTheme", "theme", "../theme/theme1.xml"),
      ),
    ),
  )
  parts.push(
    created_pptx_part(
      "ppt/slideLayouts/slideLayout1.xml",
      created_pptx_layout(),
    ),
  )
  parts.push(
    created_pptx_part(
      "ppt/slideLayouts/_rels/slideLayout1.xml.rels",
      created_pptx_relationships(
        created_pptx_relationship(
          "rIdMaster", "slideMaster", "../slideMasters/slideMaster1.xml",
        ),
      ),
    ),
  )
  if has_notes {
    parts.push(
      created_pptx_part(
        "ppt/notesMasters/notesMaster1.xml",
        created_pptx_notes_master(),
      ),
    )
    parts.push(
      created_pptx_part(
        "ppt/notesMasters/_rels/notesMaster1.xml.rels",
        created_pptx_relationships(
          created_pptx_relationship("rIdTheme", "theme", "../theme/theme1.xml"),
        ),
      ),
    )
  }
  parts.push(
    created_pptx_part(
      "docProps/core.xml",
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\{created_pptx_text(title)}</dc:title><dc:creator>MoonLeaf</dc:creator><cp:lastModifiedBy>MoonLeaf</cp:lastModifiedBy><cp:revision>1</cp:revision></cp:coreProperties>",
    ),
  )
  parts.push(
    created_pptx_part(
      "docProps/app.xml",
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>MoonLeaf</Application><PresentationFormat>On-screen Show (16:9)</PresentationFormat><Slides>\{slides.length()}</Slides><Notes>\{slides.filter(slide => slide.notes is Some(_)).length()}</Notes><HiddenSlides>0</HiddenSlides></Properties>",
    ),
  )
  parts.push(
    created_pptx_part(
      "_rels/.rels",
      created_pptx_relationships(
        created_pptx_relationship(
          "rIdPresentation", "officeDocument", "ppt/presentation.xml",
        ) +
        "<Relationship Id=\"rIdCore\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>" +
        created_pptx_relationship(
          "rIdApp", "extended-properties", "docProps/app.xml",
        ),
      ),
    ),
  )
  @opc.save({ parts, }) catch {
    error =>
      raise InvalidPresentation(
        message="PPTX package creation failed: \{Repr(error)}",
      )
  }
}
