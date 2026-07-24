///|
pub fn normalize_part_name(name : String) -> String {
  let normalized = name.replace_all(old="\\", new="/")
  let parts : Array[String] = []
  for view in normalized.split("/") {
    let part = view.to_owned()
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      // Never allow a relative target to climb above the package root. Keeping
      // the unresolved parent makes the result unusable as a package part,
      // rather than silently retargeting it to an unrelated root part.
      match parts.last() {
        Some(previous) if previous != ".." => ignore(parts.pop())
        _ => parts.push(part)
      }
    } else {
      parts.push(part)
    }
  }
  parts.join("/")
}

///|
pub fn relationships_part_name(source_part : String) -> String {
  let source = normalize_part_name(source_part)
  if source == "" {
    "_rels/.rels"
  } else {
    match source.rev_find("/") {
      Some(index) => {
        let directory = source.unsafe_substring(start=0, end=index)
        let filename = source.unsafe_substring(
          start=index + 1,
          end=source.length(),
        )
        directory + "/_rels/" + filename + ".rels"
      }
      None => "_rels/" + source + ".rels"
    }
  }
}

///|
pub fn resolve_target(
  source_part : String,
  target : String,
) -> String raise PackageError {
  if target.has_prefix("/") {
    let resolved = normalize_part_name(target)
    if resolved == ".." || resolved.has_prefix("../") {
      raise PackageError::InvalidPackage(
        "relationship target traverses above package root: " + target,
      )
    }
    return resolved
  }
  let source = normalize_part_name(source_part)
  let directory = match source.rev_find("/") {
    Some(index) => source.unsafe_substring(start=0, end=index + 1)
    None => ""
  }
  let resolved = normalize_part_name(directory + target)
  if resolved == ".." || resolved.has_prefix("../") {
    raise PackageError::InvalidPackage(
      "relationship target traverses above package root: " + target,
    )
  }
  resolved
}

///|
fn parse_relationships(text : String) -> Array[Relationship] raise PackageError {
  let root = @xml.parse(text) catch {
    _ => raise PackageError::InvalidPackage("invalid relationships XML")
  }
  let relationships : Array[Relationship] = []
  for element in root.children_named("Relationship") {
    let id = element.attribute("Id").unwrap_or("")
    let relationship_type = element.attribute("Type").unwrap_or("")
    let target = element.attribute("Target").unwrap_or("")
    if id == "" || relationship_type == "" || target == "" {
      raise PackageError::InvalidPackage(
        "relationship is missing Id, Type, or Target",
      )
    }
    for existing in relationships {
      if existing.id == id {
        raise PackageError::InvalidPackage("duplicate relationship Id: " + id)
      }
    }
    relationships.push({
      id,
      relationship_type,
      target,
      external: element.attribute("TargetMode") == Some("External"),
    })
  }
  relationships
}

///|
fn unsafe_archive_name(name : String) -> Bool {
  if name.has_prefix("/") || name.has_prefix("\\") {
    return true
  }
  for part in name.replace_all(old="\\", new="/").split("/") {
    if part == ".." {
      return true
    }
  }
  false
}

///|
fn open_package(content : FixedArray[Byte]) -> Package raise PackageError {
  let entries = @fzip.unzip_sync(content) catch {
    _ => raise PackageError::InvalidPackage("unable to read ZIP container")
  }
  let parts : Array[Part] = []
  for entry in entries {
    let (name, part_content) = entry
    if unsafe_archive_name(name) {
      raise PackageError::InvalidPackage("unsafe ZIP entry path: " + name)
    }
    let normalized = normalize_part_name(name)
    if normalized == "" || name.has_suffix("/") {
      continue
    }
    for existing in parts {
      if existing.name == normalized {
        raise PackageError::InvalidPackage("duplicate part: " + normalized)
      }
    }
    parts.push({ name: normalized, content: part_content })
  }
  let archive : Package = { parts, }
  if !archive.has_part("[Content_Types].xml") {
    raise PackageError::InvalidPackage("missing [Content_Types].xml")
  }
  archive
}

///|
fn save_package(archive : Package) -> FixedArray[Byte] raise PackageError {
  if !archive.has_part("[Content_Types].xml") {
    raise PackageError::InvalidPackage("missing [Content_Types].xml")
  }
  let entries = []
  for part in archive.parts {
    if unsafe_archive_name(part.name) || normalize_part_name(part.name) == "" {
      raise PackageError::InvalidPackage("invalid part path: " + part.name)
    }
    entries.push((normalize_part_name(part.name), part.content))
  }
  @fzip.zip_sync(entries)
}
