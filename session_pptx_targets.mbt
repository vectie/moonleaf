///|
/// List supported PPTX text targets for this exact session revision.
pub fn DocumentSession::pptx_text_targets(
  self : DocumentSession,
) -> Array[@pptx.TextTarget] raise DocumentSessionError {
  if self.format != Pptx {
    raise OperationNotSupported(
      operation="pptx_text_targets",
      format=self.format,
    )
  }
  @pptx.text_targets(self.source_archive) catch {
    error => raise Render("\{Repr(error)}")
  }
}

///|
/// Change one listed PPTX text element while retaining normal session copy
/// verification. A stale expected value is refused, including for no-op edits.
pub fn DocumentSession::set_pptx_target_text(
  self : DocumentSession,
  id : String,
  expected : String,
  replacement : String,
) -> DocumentSession raise DocumentSessionError {
  if self.format != Pptx {
    raise OperationNotSupported(
      operation="set_pptx_target_text",
      format=self.format,
    )
  }
  let candidate = @pptx.set_target_text(
    self.source_archive,
    id,
    expected,
    replacement,
  ) catch {
    error => raise Render("\{Repr(error)}")
  }
  self.commit_candidate(candidate)
}
