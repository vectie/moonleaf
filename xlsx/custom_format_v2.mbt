///|
/// Production custom-number-format classifier with distinct malformed and
/// ambiguous outcomes. `custom_format_kind` narrowly adapts these outcomes to
/// the established inspection-warning mapping.
fn custom_format_kind_v2(code : String) -> (DisplayKind, Bool, Bool) {
  let bytes = @utf8.encode(code)
  let sections : Array[(Bool, Bool, Bool, Bool)] = []
  let mut has_y_or_d = false
  let mut has_h_or_s = false
  let mut has_m = false
  let mut has_ampm = false
  let mut content = false
  let mut separators = 0
  let mut i = 0

  while i < bytes.length() {
    let c = bytes[i]
    if c == b';' {
      if separators < 3 {
        sections.push((has_y_or_d, has_h_or_s || has_ampm, has_m, content))
      }
      separators += 1
      if separators > 3 {
        return (Unsupported, true, false)
      }
      has_y_or_d = false
      has_h_or_s = false
      has_m = false
      has_ampm = false
      content = false
      i += 1
    } else if c == b'"' {
      i += 1
      while i < bytes.length() && bytes[i] != b'"' {
        i += 1
      }
      if i >= bytes.length() {
        return (Unsupported, true, false)
      }
      content = true
      i += 1
    } else if c == b'\\' || c == b'_' || c == b'*' {
      if i + 1 >= bytes.length() {
        return (Unsupported, true, false)
      }
      content = true
      i += 2
    } else if c == b'[' {
      let begin = i + 1
      i = begin
      while i < bytes.length() && bytes[i] != b']' {
        i += 1
      }
      if i >= bytes.length() {
        return (Unsupported, true, false)
      }
      let mut j = begin
      let mut elapsed = j < i
      while j < i {
        let b = bytes[j]
        if b != b'h' &&
          b != b'H' &&
          b != b'm' &&
          b != b'M' &&
          b != b's' &&
          b != b'S' {
          elapsed = false
        }
        j += 1
      }
      if elapsed {
        has_h_or_s = true
        content = true
      }
      i += 1
    } else {
      let lower = if c >= b'A' && c <= b'Z' { c + 32 } else { c }
      if lower == b'y' || lower == b'd' {
        has_y_or_d = true
      } else if lower == b'h' || lower == b's' {
        has_h_or_s = true
      } else if lower == b'm' {
        has_m = true
      }
      if lower == b'a' &&
        i + 2 < bytes.length() &&
        bytes[i + 1] == b'/' &&
        (bytes[i + 2] == b'p' || bytes[i + 2] == b'P') {
        has_ampm = true
      } else if lower == b'a' &&
        i + 4 < bytes.length() &&
        (bytes[i + 1] == b'm' || bytes[i + 1] == b'M') &&
        bytes[i + 2] == b'/' &&
        (bytes[i + 3] == b'p' || bytes[i + 3] == b'P') &&
        (bytes[i + 4] == b'm' || bytes[i + 4] == b'M') {
        has_ampm = true
      }
      if c != b' ' {
        content = true
      }
      i += 1
    }
  }

  if separators < 3 {
    sections.push((has_y_or_d, has_h_or_s || has_ampm, has_m, content))
  }
  let mut found : DisplayKind? = None
  for section in sections {
    let (date_token, time_token, minute_token, nonempty) = section
    if nonempty {
      let date = date_token || (minute_token && !time_token)
      let time = time_token
      let kind = if date && time {
        DateTime
      } else if date {
        Date
      } else if time {
        Time
      } else {
        Number
      }
      match found {
        None => found = Some(kind)
        Some(old) => if old != kind { return (Unsupported, false, true) }
      }
    }
  }
  (found.unwrap_or(Number), false, false)
}
