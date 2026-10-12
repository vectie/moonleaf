///|
/// One ordinary slide text run, identified only within the exact source snapshot.
/// The ID is a structural path; slide position and shape ID aid human selection.
pub(all) struct TextTarget {
  id : String
  slide_number : Int
  part : String
  shape_id : String
  hidden_slide : Bool
  text : String
} derive(Eq, Debug, ToJson)

///|
pub extend TextTarget with Eq::{equal, not_equal}

///|
pub extend TextTarget with @debug.Debug::{to_repr}

///|
pub extend TextTarget with ToJson::{to_json}

///|
priv struct TextSlot {
  target : TextTarget
  root : @xml.Element
  path : Array[Int]
}

///|
fn validate_target_namespaces(element : @xml.Element) -> Unit raise PptxError {
  for attr in element.attributes {
    if (
        attr.name == "xmlns:p" &&
        attr.value !=
        "http://schemas.openxmlformats.org/presentationml/2006/main"
      ) ||
      (
        attr.name == "xmlns:a" &&
        attr.value != "http://schemas.openxmlformats.org/drawingml/2006/main"
      ) {
      raise InvalidPresentation(
        message="targeted editing does not support rebinding p or a namespaces",
      )
    }
  }
  for child in element.child_elements() {
    validate_target_namespaces(child)
  }
}

///|
fn collect_text_slots(
  element : @xml.Element,
  root : @xml.Element,
  path : Array[Int],
  context : TextTarget,
  output : Array[TextSlot],
) -> Unit raise PptxError {
  let mut ordinal = 0
  for index, node in element.children {
    guard node is Element(child) else { continue }
    ordinal += 1
    let eligible = match element.name {
      "p:sld" => child.name == "p:cSld"
      "p:cSld" => child.name == "p:spTree"
      "p:spTree" | "p:grpSp" => child.name == "p:sp" || child.name == "p:grpSp"
      "p:sp" => child.name == "p:txBody"
      "p:txBody" => child.name == "a:p"
      "a:p" => child.name == "a:r"
      "a:r" => child.name == "a:t"
      _ => false
    }
    if !eligible {
      continue
    }
    let next_path = path.copy()
    next_path.push(index)
    let shape_id = if child.name == "p:sp" {
      outline_shape_info(child).0
    } else {
      context.shape_id
    }
    let next = {
      ..context,
      id: context.id + "/" + child.local_name() + ":" + ordinal.to_string(),
      shape_id,
    }
    if child.name == "a:t" {
      if child.children.any(node => node is Element(_)) {
        raise InvalidPresentation(
          message="target text must not contain child elements",
        )
      }
      if output.length() >= 10_000 {
        raise InvalidPresentation(
          message="targeted editing exceeds 10000 text elements",
        )
      }
      output.push({
        target: { ..next, text: child.text_content(), },
        root,
        path: next_path,
      })
    } else {
      collect_text_slots(child, root, next_path, next, output)
    }
  }
}

///|
fn text_slots(container : @opc.Package) -> Array[TextSlot] raise PptxError {
  let presentation = parse_xml_part(
    container,
    presentation_part,
    presentation=true,
  )
  if presentation.local_name() != "presentation" {
    raise InvalidPresentation(message="expected presentation root")
  }
  let parts = ordered_slide_parts(
    presentation,
    presentation_relationships(container),
  )
  if parts.length() > 200 {
    raise InvalidPresentation(message="targeted editing exceeds 200 slides")
  }
  let seen : Map[String, Bool] = Map([])
  let output = []
  for index, part in parts {
    if seen.contains(part) {
      raise InvalidPresentation(
        message="targeted editing requires distinct slide parts",
      )
    }
    seen[part] = true
    let root = parse_xml_part(container, part, presentation=false)
    if root.name != "p:sld" ||
      !root.attributes.any(a => {
        a.name == "xmlns:p" &&
        a.value == "http://schemas.openxmlformats.org/presentationml/2006/main"
      }) ||
      !root.attributes.any(a => {
        a.name == "xmlns:a" &&
        a.value == "http://schemas.openxmlformats.org/drawingml/2006/main"
      }) {
      raise InvalidSlide(
        part~,
        message="targeted editing requires standard p:sld, p and a namespaces",
      )
    }
    validate_target_namespaces(root)
    let common = root.child_elements().filter(child => child.name == "p:cSld")
    guard common is [common] &&
      common.child_elements().filter(child => child.name == "p:spTree").length() ==
      1 else {
      raise InvalidSlide(
        part~,
        message="targeted editing requires one direct cSld and spTree",
      )
    }
    collect_text_slots(
      root,
      root,
      [],
      {
        id: "slide:" + (index + 1).to_string(),
        slide_number: index + 1,
        part,
        shape_id: "",
        hidden_slide: root.attribute("show") == Some("0") ||
        root.attribute("show") == Some("false"),
        text: "",
      },
      output,
    )
  }
  output
}

///|
/// List direct a:r/a:t runs in ordinary slide text shapes and groups.
/// Tables, notes, fields, masters, layouts and wrapped content are not editable.
/// IDs must be bound by the caller to this exact source or session revision.
pub fn text_targets(
  container : @opc.Package,
) -> Array[TextTarget] raise PptxError {
  text_slots(container).map(slot => slot.target)
}

///|
/// Replace one complete run's expected text. Other runs and package parts remain
/// unchanged; no substring matching, shape reconstruction or formatting changes.
pub fn set_target_text(
  container : @opc.Package,
  id : String,
  expected : String,
  replacement : String,
) -> @opc.Package raise PptxError {
  validate_target_text(replacement)
  let matches = text_slots(container).filter(slot => slot.target.id == id)
  guard matches is [slot] else {
    raise InvalidPresentation(
      message="unknown or unsupported text target: " + id,
    )
  }
  if slot.target.text != expected {
    raise InvalidPresentation(
      message="text target no longer has the expected text",
    )
  }
  if expected == replacement {
    return container
  }
  let source = container.text(slot.target.part) catch {
    _ => raise InvalidPackagePart(part=slot.target.part)
  }
  let (start, end) = target_source_span(
    source,
    target_ordinal(slot.root, slot.path, 0, 1),
  )
  let updated = source.unsafe_substring(start=0, end=start) +
    replacement_element(element_at_path(slot.root, slot.path, 0), replacement) +
    source.unsafe_substring(start=end, end=source.length())
  container.replace_text(slot.target.part, updated)
}
