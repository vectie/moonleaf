///|
/// Stable engine identifier carried by every MoonLeaf render receipt.
pub fn engine_id() -> String {
  "moonleaf"
}

///|
/// Version of MoonLeaf's deterministic render-evidence contract.
pub fn contract_version() -> String {
  "moonleaf.render-evidence.v1"
}

///|
/// Evidence returned by a MoonLeaf DOCX-to-PDF/page render. The renderer owns
/// pagination and glyph placement; a host may verify this bounded receipt
/// without learning document text.
pub(all) struct Evidence {
  contract_version : String
  engine : String
  engine_version : String
  source_sha256 : String
  artifact_sha256 : String
  font_bundle_sha256 : String
  layout_profile_sha256 : String
  page_count : Int32
  rendered_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Evidence::valid(self : Evidence) -> Bool {
  fn valid_digest(value : String) -> Bool {
    value.length() == 71 &&
    value.has_prefix("sha256:") &&
    value[7:].all(character => character.is_ascii_hexdigit())
  }
  self.contract_version == contract_version() &&
  self.engine == engine_id() &&
  self.engine_version.length() >= 1 &&
  self.engine_version.length() <= 64 &&
  self.engine_version.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '.' ||
    character == '-' ||
    character == '_'
  }) &&
  valid_digest(self.source_sha256) &&
  valid_digest(self.artifact_sha256) &&
  valid_digest(self.font_bundle_sha256) &&
  valid_digest(self.layout_profile_sha256) &&
  self.page_count >= 1 &&
  self.page_count <= 1000 &&
  self.rendered_unix_ms > 0L
}
