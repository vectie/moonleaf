///|
fn replace_in_element(
  element : @xml.Element,
  find : String,
  replacement : String,
  changed : Ref[Bool],
) -> @xml.Element {
  // Be deliberately prefix-specific here. A Word document part can contain
  // DrawingML `a:t` nodes, which this basic WordprocessingML editor must not
  // silently rewrite.
  let is_text_element = element.name == "w:t"
  let children = []
  for child in element.children {
    match child {
      Text(text) =>
        if is_text_element {
          let replaced = text.replace_all(old=find, new=replacement)
          if replaced != text {
            changed.val = true
          }
          children.push(@xml.Text(replaced))
        } else {
          children.push(child)
        }
      Element(child_element) => {
        let updated_child : @xml.Node = Element(
          replace_in_element(child_element, find, replacement, changed),
        )
        children.push(updated_child)
      }
    }
  }
  { name: element.name, attributes: element.attributes, children, }
}

///|
/// Replace text contained within individual `w:t` elements.
///
/// Matches never cross Word run boundaries. All package parts other than
/// `word/document.xml` are preserved byte-for-byte. The input package is not
/// mutated; an updated package value is returned.
pub fn replace_text(
  document_package : @opc.Package,
  find : String,
  replacement : String,
) -> @opc.Package raise DocxError {
  if find.is_empty() {
    raise InvalidReplacement("find text must not be empty")
  }
  let source = document_package.text("word/document.xml") catch {
    MissingPart(_) => raise MissingDocument
    error => raise InvalidDocument(repr(error))
  }
  let root = @xml.parse(source) catch {
    error => raise InvalidDocument(repr(error))
  }
  let changed = Ref(false)
  let updated = replace_in_element(root, find, replacement, changed)
  if changed.val {
    document_package.replace_text("word/document.xml", @xml.serialize(updated))
  } else {
    document_package
  }
}
