///|
fn runs_text(runs : Array[TextRun]) -> String {
  let output = StringBuilder()
  for run in runs {
    output.write_string(run.text)
  }
  output.to_string()
}

///|
/// Extract visible text from a parsed document for search and indexing.
pub fn TextDocument::plain_text(self : TextDocument) -> String {
  let output = StringBuilder()
  let mut length = 0
  for block in self.blocks {
    let lines : Array[String] = []
    match block {
      Paragraph(runs) | Heading(_, runs) | ListItem(level=_, ordered=_, runs) =>
        lines.push(runs_text(runs))
      Table(rows) =>
        for row in rows {
          for cell in row {
            lines.push(cell)
          }
        }
    }
    for line in lines {
      if line.trim() != "" && length + line.length() + 1 <= 1_000_000 {
        if length > 0 {
          output.write_char('\n')
          length += 1
        }
        output.write_string(line)
        length += line.length()
      }
    }
  }
  output.to_string()
}
