///|
fn decode_text_payload(payload : String) -> String raise PptxError {
  let wrapped = "<root>\{payload}</root>"
  let root = @xml.parse(wrapped) catch {
    _ => raise InvalidPresentation(message="invalid XML text payload")
  }
  root.text_content()
}

///|
fn replace_a_text_nodes(
  source : String,
  find : String,
  replacement : String,
) -> (String, Bool) raise PptxError {
  let output = StringBuilder(size_hint=source.length())
  let escaped = @xml.escape_text(replacement)
  let mut offset = 0
  let mut changed = false
  for ; offset < source.length(); {
    let remainder = source[offset:]
    match remainder.find("<a:t") {
      None => {
        output.write_string(remainder.to_owned())
        offset = source.length()
      }
      Some(relative_open) => {
        let open = offset + relative_open
        let after_name = open + 4
        if after_name >= source.length() ||
          (
            source[after_name] != '>' &&
            source[after_name] != ' ' &&
            source[after_name] != '\t' &&
            source[after_name] != '\r' &&
            source[after_name] != '\n'
          ) {
          output.write_string(source[offset:after_name].to_owned())
          offset = after_name
          continue
        }
        output.write_string(source[offset:open].to_owned())
        match source[open:].find(">") {
          None => {
            output.write_string(source[open:].to_owned())
            offset = source.length()
          }
          Some(relative_content) => {
            let content_start = open + relative_content + 1
            match source[content_start:].find("</a:t>") {
              None => {
                output.write_string(source[open:].to_owned())
                offset = source.length()
              }
              Some(relative_close) => {
                let close = content_start + relative_close
                output.write_string(source[open:content_start].to_owned())
                let payload = source[content_start:close].to_owned()
                let matches = decode_text_payload(payload) == find
                if matches {
                  output.write_string(escaped)
                  changed = true
                } else {
                  output.write_string(payload)
                }
                output.write_string("</a:t>")
                offset = close + 6
              }
            }
          }
        }
      }
    }
  }
  (output.to_string(), changed)
}

///|
/// Replace exact text payloads in slide `a:t` elements.
///
/// Only slide parts referenced by `ppt/presentation.xml` are considered.
/// Unrelated ZIP entries remain untouched. The slide XML outside matching text
/// payloads is copied verbatim, making this suitable for conservative
/// lightweight edits and "Save a Copy" workflows.
///
/// This intentionally does not replace substrings spanning multiple runs.
pub fn replace_text(
  container : @opc.Package,
  find : String,
  replacement : String,
) -> @opc.Package raise PptxError {
  let root = parse_xml_part(container, presentation_part, presentation=true)
  let relationships = presentation_relationships(container)
  let parts = ordered_slide_parts(root, relationships)
  let result = Ref(container)
  for part in parts {
    let source = container.text(part) catch {
      _ => raise InvalidPackagePart(part~)
    }
    let (updated, changed) = replace_a_text_nodes(source, find, replacement)
    if changed {
      result.val = result.val.replace_text(part, updated)
    }
  }
  result.val
}
