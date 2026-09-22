///|
pub(all) suberror PackageError {
  InvalidPackage(String)
  MissingPart(String)
  InvalidTextPart(String)
} derive(Debug, Eq)

///|
pub fn PackageError::to_string(self : PackageError) -> String {
  match self {
    InvalidPackage(message) => "invalid package: " + message
    MissingPart(name) => "missing package part: " + name
    InvalidTextPart(name) => "package part is not valid UTF-8: " + name
  }
}

///|
pub(all) struct Part {
  name : String
  content : FixedArray[Byte]
} derive(Debug, Eq)

///|
pub(all) struct Relationship {
  id : String
  relationship_type : String
  target : String
  external : Bool
} derive(Debug, Eq)

///|
pub(all) struct Package {
  parts : Array[Part]
} derive(Debug, Eq)

///|
pub fn Package::part(self : Package, name : String) -> Part? {
  let normalized = normalize_part_name(name)
  for part in self.parts {
    if part.name == normalized {
      return Some(part)
    }
  }
  None
}

///|
pub fn Package::has_part(self : Package, name : String) -> Bool {
  self.part(name) is Some(_)
}

///|
pub fn Package::text(
  self : Package,
  name : String,
) -> String raise PackageError {
  match self.part(name) {
    Some(part) =>
      @fzip.str_from_u8(part.content) catch {
        _ => raise PackageError::InvalidTextPart(name)
      }
    None => raise PackageError::MissingPart(name)
  }
}

///|
pub fn Package::replace_text(
  self : Package,
  name : String,
  content : String,
) -> Package {
  self.replace_part(name, @utf8.encode(content).to_fixedarray())
}

///|
pub fn Package::replace_part(
  self : Package,
  name : String,
  content : FixedArray[Byte],
) -> Package {
  let normalized = normalize_part_name(name)
  let parts = []
  let replaced = Ref(false)
  for part in self.parts {
    if part.name == normalized {
      parts.push({ name: normalized, content, })
      replaced.val = true
    } else {
      parts.push(part)
    }
  }
  if !replaced.val {
    parts.push({ name: normalized, content, })
  }
  { parts, }
}

///|
pub fn Package::relationships(
  self : Package,
  source_part : String,
) -> Array[Relationship] raise PackageError {
  parse_relationships(self.text(relationships_part_name(source_part)))
}

///|
pub fn open(content : FixedArray[Byte]) -> Package raise PackageError {
  open_package_with_policy(content, ArchivePolicy::default())
}

///|
/// Open an OPC package using explicit, validated per-open archive limits.
///
/// ZIP central-directory metadata is checked before extraction, CRC
/// verification is mandatory, and declared sizes are compared with extracted
/// outputs before the package is returned.
pub fn open_with_policy(
  content : FixedArray[Byte],
  policy : ArchivePolicy,
) -> Package raise PackageError {
  open_package_with_policy(content, policy)
}

///|
pub fn save(archive : Package) -> FixedArray[Byte] raise PackageError {
  save_package(archive)
}
