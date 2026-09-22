///|
test "render evidence is explicitly MoonLeaf and binds fonts plus layout" {
  let digest = "sha256:" + "a".repeat(64)
  let evidence : @render.Evidence = {
    contract_version: @render.contract_version(),
    engine: @render.engine_id(),
    engine_version: "0.1.3",
    source_sha256: digest,
    artifact_sha256: digest,
    font_bundle_sha256: digest,
    layout_profile_sha256: digest,
    page_count: 18,
    rendered_unix_ms: 1L,
  }
  assert_true(evidence.valid())
  assert_false({ ..evidence, engine: "libreoffice", }.valid())
  assert_false({ ..evidence, font_bundle_sha256: "unverified", }.valid())
  assert_false({ ..evidence, page_count: 0, }.valid())
}
