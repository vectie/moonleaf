///|
fn append_plain_blocks(
  out : StringBuilder,
  blocks : Array[OutlineBlock],
) -> Unit {
  for block in blocks {
    for paragraph in block.paragraphs {
      out.write_string(paragraph)
      out.write_char('\n')
    }
    for row in block.rows {
      out.write_string(row.join("\t"))
      out.write_char('\n')
    }
  }
}

///|
/// Extract decoded slide text, stored table cells and speaker notes in source
/// slide order for attachment indexing. No image OCR or external fetch occurs.
pub fn plain_text(container : @opc.Package) -> String raise PptxError {
  let outline = read_outline(container)
  let out = StringBuilder()
  for slide in outline.slides {
    out.write_string("Slide " + slide.number.to_string() + " — " + slide.name)
    if slide.hidden {
      out.write_string(" [hidden]")
    }
    out.write_char('\n')
    append_plain_blocks(out, slide.blocks)
    if !slide.notes.is_empty() {
      out.write_string("Speaker notes\n")
      append_plain_blocks(out, slide.notes)
    }
    out.write_char('\n')
  }
  out.to_string()
}
