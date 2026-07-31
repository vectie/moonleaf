///|
/// Resource and path limits applied to one ZIP/OPC open.
///
/// These limits are enforced before extraction from central-directory
/// metadata and checked again against the extracted entries. The dependency's
/// own hard limits remain an additional ceiling.
pub(all) struct ArchivePolicy {
  max_compressed_input_bytes : Int
  max_entries : Int
  max_entry_compressed_bytes : Int
  max_entry_uncompressed_bytes : Int
  max_total_uncompressed_bytes : Int
  max_compression_ratio : Int
  max_path_depth : Int
  max_path_length : Int
} derive(Debug, Eq)

///|
/// Conservative defaults for untrusted, in-memory OOXML opens.
///
/// The path length is measured in MoonBit string code units. Callers may use a
/// stricter validated policy for a particular trust boundary.
pub fn ArchivePolicy::default() -> ArchivePolicy {
  {
    max_compressed_input_bytes: 64 * 1024 * 1024,
    max_entries: 8192,
    max_entry_compressed_bytes: 32 * 1024 * 1024,
    max_entry_uncompressed_bytes: 64 * 1024 * 1024,
    max_total_uncompressed_bytes: 96 * 1024 * 1024,
    max_compression_ratio: 200,
    max_path_depth: 32,
    max_path_length: 1024,
  }
}

///|
/// Reject internally inconsistent or non-positive limits.
pub fn ArchivePolicy::validate(self : ArchivePolicy) -> Unit raise PackageError {
  if self.max_compressed_input_bytes <= 0 {
    raise PackageError::InvalidPackage(
      "archive policy max_compressed_input_bytes must be positive",
    )
  }
  if self.max_entries <= 0 {
    raise PackageError::InvalidPackage(
      "archive policy max_entries must be positive",
    )
  }
  if self.max_entry_compressed_bytes <= 0 {
    raise PackageError::InvalidPackage(
      "archive policy max_entry_compressed_bytes must be positive",
    )
  }
  if self.max_entry_uncompressed_bytes <= 0 {
    raise PackageError::InvalidPackage(
      "archive policy max_entry_uncompressed_bytes must be positive",
    )
  }
  if self.max_total_uncompressed_bytes <= 0 {
    raise PackageError::InvalidPackage(
      "archive policy max_total_uncompressed_bytes must be positive",
    )
  }
  if self.max_compression_ratio <= 0 {
    raise PackageError::InvalidPackage(
      "archive policy max_compression_ratio must be positive",
    )
  }
  if self.max_path_depth <= 0 {
    raise PackageError::InvalidPackage(
      "archive policy max_path_depth must be positive",
    )
  }
  if self.max_path_length <= 0 {
    raise PackageError::InvalidPackage(
      "archive policy max_path_length must be positive",
    )
  }
  if self.max_entry_compressed_bytes > self.max_compressed_input_bytes {
    raise PackageError::InvalidPackage(
      "archive policy per-entry compressed limit exceeds input limit",
    )
  }
  if self.max_entry_uncompressed_bytes > self.max_total_uncompressed_bytes {
    raise PackageError::InvalidPackage(
      "archive policy per-entry uncompressed limit exceeds total limit",
    )
  }
}

///|
fn archive_ratio_exceeds(
  uncompressed : Int,
  compressed : Int,
  maximum_ratio : Int,
) -> Bool {
  if uncompressed == 0 {
    return false
  }
  if compressed == 0 {
    return true
  }
  let quotient = uncompressed / compressed
  quotient > maximum_ratio ||
  (quotient == maximum_ratio && uncompressed % compressed != 0)
}

///|
fn canonical_archive_path(
  name : String,
  policy : ArchivePolicy,
) -> String raise PackageError {
  if name == "" {
    raise PackageError::InvalidPackage("ZIP entry path is empty")
  }
  if name.length() > policy.max_path_length {
    raise PackageError::InvalidPackage(
      "ZIP entry path exceeds max_path_length: " + name,
    )
  }
  if name.has_prefix("/") || name.has_prefix("\\") {
    raise PackageError::InvalidPackage("absolute ZIP entry path: " + name)
  }
  if name.contains("\\") {
    raise PackageError::InvalidPackage(
      "non-canonical ZIP path separator: " + name,
    )
  }
  for character in name {
    if !character.is_printable() {
      raise PackageError::InvalidPackage(
        "ZIP entry path contains a control character",
      )
    }
  }
  let directory = name.has_suffix("/")
  let body = if directory {
    name.unsafe_substring(start=0, end=name.length() - 1)
  } else {
    name
  }
  if body == "" {
    raise PackageError::InvalidPackage("ZIP entry path has no component")
  }
  let components : Array[String] = []
  for component_view in body.split("/") {
    let component = component_view.to_owned()
    if component == "" || component == "." || component == ".." {
      raise PackageError::InvalidPackage(
        "ZIP entry path contains an empty, dot, or parent component: " + name,
      )
    }
    if component.trim().to_owned() != component {
      raise PackageError::InvalidPackage(
        "ZIP entry path contains a whitespace alias: " + name,
      )
    }
    let lower = component.to_lower()
    if lower.contains("%2e") || lower.contains("%2f") || lower.contains("%5c") {
      raise PackageError::InvalidPackage(
        "ZIP entry path contains an encoded path alias: " + name,
      )
    }
    if component.contains("?") || component.contains("#") {
      raise PackageError::InvalidPackage(
        "ZIP entry path contains a URI query or fragment delimiter: " + name,
      )
    }
    components.push(component)
  }
  if components.length() > policy.max_path_depth {
    raise PackageError::InvalidPackage(
      "ZIP entry path exceeds max_path_depth: " + name,
    )
  }
  let canonical = components.join("/")
  if directory {
    canonical + "/"
  } else {
    canonical
  }
}

///|
fn preflight_archive(
  content : FixedArray[Byte],
  policy : ArchivePolicy,
) -> Array[@fzip.UnzipFileInfo] raise PackageError {
  policy.validate()
  if content.length() > policy.max_compressed_input_bytes {
    raise PackageError::InvalidPackage(
      "ZIP input exceeds max_compressed_input_bytes",
    )
  }
  let infos = @fzip.unzip_list(content) catch {
    _ => raise PackageError::InvalidPackage("unable to inspect ZIP container")
  }
  if infos.length() > policy.max_entries {
    raise PackageError::InvalidPackage("ZIP entry count exceeds max_entries")
  }
  let seen : Map[String, Unit] = Map([])
  let mut total_uncompressed = 0
  for info in infos {
    if info.size < 0 || info.original_size < 0 {
      raise PackageError::InvalidPackage("ZIP entry declares a negative size")
    }
    if info.size > policy.max_entry_compressed_bytes {
      raise PackageError::InvalidPackage(
        "ZIP entry exceeds max_entry_compressed_bytes: " + info.name,
      )
    }
    if info.original_size > policy.max_entry_uncompressed_bytes {
      raise PackageError::InvalidPackage(
        "ZIP entry exceeds max_entry_uncompressed_bytes: " + info.name,
      )
    }
    if info.original_size >
      policy.max_total_uncompressed_bytes - total_uncompressed {
      raise PackageError::InvalidPackage(
        "ZIP archive exceeds max_total_uncompressed_bytes",
      )
    }
    total_uncompressed += info.original_size
    if info.compression != 0 && info.compression != 8 {
      raise PackageError::InvalidPackage(
        "unsupported ZIP compression method for entry: " + info.name,
      )
    }
    if info.compression == 0 && info.size != info.original_size {
      raise PackageError::InvalidPackage(
        "stored ZIP entry size mismatch: " + info.name,
      )
    }
    if archive_ratio_exceeds(
        info.original_size,
        info.size,
        policy.max_compression_ratio,
      ) {
      raise PackageError::InvalidPackage(
        "ZIP entry exceeds max_compression_ratio: " + info.name,
      )
    }
    let canonical = canonical_archive_path(info.name, policy)
    let identity = if canonical.has_suffix("/") {
      canonical.unsafe_substring(start=0, end=canonical.length() - 1).to_lower()
    } else {
      canonical.to_lower()
    }
    if seen.contains(identity) {
      raise PackageError::InvalidPackage(
        "duplicate or aliased ZIP entry path: " + info.name,
      )
    }
    seen[identity] = ()
  }
  infos
}

///|
fn extract_verified_archive(
  content : FixedArray[Byte],
  policy : ArchivePolicy,
  infos : Array[@fzip.UnzipFileInfo],
) -> Array[(String, FixedArray[Byte])] raise PackageError {
  let entries = @fzip.unzip_sync(content, opts={ verify_checksum: true }) catch {
    _ =>
      raise PackageError::InvalidPackage(
        "ZIP extraction or CRC integrity verification failed",
      )
  }
  if entries.length() != infos.length() {
    raise PackageError::InvalidPackage(
      "ZIP metadata and extracted entry counts disagree",
    )
  }
  let mut total_uncompressed = 0
  for index, entry in entries {
    let info = infos[index]
    if entry.0 != info.name || entry.1.length() != info.original_size {
      raise PackageError::InvalidPackage(
        "ZIP metadata and extracted output disagree: " + info.name,
      )
    }
    if entry.1.length() > policy.max_entry_uncompressed_bytes ||
      entry.1.length() >
      policy.max_total_uncompressed_bytes - total_uncompressed {
      raise PackageError::InvalidPackage(
        "ZIP extracted output exceeds archive policy",
      )
    }
    total_uncompressed += entry.1.length()
  }
  entries
}
