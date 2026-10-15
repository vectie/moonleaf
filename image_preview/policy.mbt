///|
fn image_decision(allowed : Bool, mime : String, reason : String) -> String {
  let result : Json = {
    "contract": "moonleaf.image-preview-policy.v1",
    "allowed": allowed,
    "mime": mime,
    "reason": reason,
  }
  result.stringify()
}

///|
/// Admit a bounded image preview request by declared filename and actual
/// bytes. The host supplies the byte length, first 16 bytes as hexadecimal,
/// and complete decoded UTF-8 text for SVG. Rendering and filesystem access
/// remain host responsibilities.
pub fn admit_image_preview_json(raw : String) -> String {
  let request = @json.parse(raw) catch {
    _ => return image_decision(false, "", "Invalid image request")
  }
  guard request
    is {
      "name": String(name),
      "size": Number(size, ..),
      "head_hex": String(head_hex),
      ..
    } &&
    size >= 1.0 &&
    size <= 8388608.0 &&
    size.to_int().to_double() == size else {
    return image_decision(false, "", "Invalid or oversized image")
  }
  let lower_name = name.to_lower()
  let head = head_hex.to_lower()
  if lower_name.has_suffix(".png") {
    if !head.has_prefix("89504e470d0a1a0a") {
      return image_decision(false, "", "PNG signature does not match")
    }
    return image_decision(true, "image/png", "")
  }
  if lower_name.has_suffix(".jpg") || lower_name.has_suffix(".jpeg") {
    if !head.has_prefix("ffd8ff") {
      return image_decision(false, "", "JPEG signature does not match")
    }
    return image_decision(true, "image/jpeg", "")
  }
  if lower_name.has_suffix(".gif") {
    if !head.has_prefix("474946383761") && !head.has_prefix("474946383961") {
      return image_decision(false, "", "GIF signature does not match")
    }
    return image_decision(true, "image/gif", "")
  }
  if lower_name.has_suffix(".webp") {
    if head.length() < 24 ||
      !head.has_prefix("52494646") ||
      head[16:24] != "57454250" {
      return image_decision(false, "", "WebP signature does not match")
    }
    return image_decision(true, "image/webp", "")
  }
  if lower_name.has_suffix(".svg") {
    if size > 2097152.0 {
      return image_decision(false, "", "SVG exceeds 2 MiB")
    }
    guard request is { "svg_text": String(svg_text), .. } else {
      return image_decision(false, "", "SVG must be UTF-8 text")
    }
    let text = svg_text.trim().to_lower()
    if !(text.has_prefix("<svg") ||
      (text.has_prefix("<?xml") && text.contains("<svg"))) {
      return image_decision(false, "", "SVG root is missing")
    }
    for
      forbidden in [
        "<!doctype", "<script", "<foreignobject", "javascript:", "onload=", "onerror=",
        "onclick=", "onmouseover=", "<?xml-stylesheet",
      ] {
      if text.contains(forbidden) {
        return image_decision(false, "", "Active SVG content is unavailable")
      }
    }
    return image_decision(true, "image/svg+xml; charset=utf-8", "")
  }
  image_decision(false, "", "Image format is unsupported")
}
