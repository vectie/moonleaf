///|
fn outline_markdown_text(text : String) -> String {
  let output = StringBuilder()
  for char in text {
    match char {
      '&' => output.write_string("&amp;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '\n' => output.write_string("<br>")
      '\r' => ()
      '\\' | '`' | '*' | '_' | '[' | ']' | '#' | '|' | '~' | '!' => {
        output.write_char('\\')
        output.write_char(char)
      }
      _ => output.write_char(char)
    }
  }
  output.to_string()
}

///|
fn outline_markdown_blocks(
  blocks : Array[OutlineBlock],
  out : StringBuilder,
) -> Unit {
  for index, block in blocks {
    out.write_string(
      "Block \{index + 1}, shape \{outline_markdown_text(block.shape_id)} (\{block.kind})\n\n",
    )
    if block.kind == "table" {
      let mut columns = 0
      for row in block.rows {
        if row.length() > columns {
          columns = row.length()
        }
      }
      if columns > 0 {
        // Generic column labels avoid presenting a data row as a header.
        out.write_string("|")
        for column in 0..<columns {
          out.write_string(" Column \{column + 1} |")
        }
        out.write_string("\n|")
        for _ in 0..<columns {
          out.write_string(" --- |")
        }
        out.write_char('\n')
        for row in block.rows {
          out.write_string("|")
          for column in 0..<columns {
            let value = row.get(column).unwrap_or("")
            out.write_string(" \{outline_markdown_text(value)} |")
          }
          out.write_char('\n')
        }
        out.write_char('\n')
      }
    } else {
      for paragraph in block.paragraphs {
        // Prefixing every paragraph with a bullet prevents input from creating
        // headings, ordered lists, indented code or blockquotes.
        out.write_string("- \{outline_markdown_text(paragraph)}\n")
      }
      out.write_char('\n')
    }
  }
}

///|
/// Produce an escaped Markdown review outline, including all extraction limits.
/// The host should prepend the source artifact reference and digest.
pub fn PresentationOutline::to_markdown(self : PresentationOutline) -> String {
  let out = StringBuilder()
  out.write_string("# Presentation review outline\n\n")
  for warning in self.warnings {
    out.write_string("- \{outline_markdown_text(warning)}\n")
  }
  out.write_char('\n')
  for slide in self.slides {
    let hidden = if slide.hidden { " (hidden)" } else { "" }
    out.write_string(
      "## Slide \{slide.number}\{hidden}: \{outline_markdown_text(slide.title)}\n\n",
    )
    out.write_string("Source part: \{outline_markdown_text(slide.part)}\n\n")
    outline_markdown_blocks(slide.blocks, out)
    out.write_string("### Speaker notes\n\n")
    match slide.notes_part {
      Some(part) => {
        out.write_string("Source part: \{outline_markdown_text(part)}\n\n")
        outline_markdown_blocks(slide.notes, out)
      }
      None => out.write_string("No notes part.\n\n")
    }
  }
  out.to_string()
}
