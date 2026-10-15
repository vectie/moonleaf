///|
/// List supported DOCX text targets for this exact session revision.
pub fn DocumentSession::docx_text_targets(
  self : DocumentSession,
) -> Array[@docx.TextTarget] raise DocumentSessionError {
  if self.format != Docx {
    raise OperationNotSupported(
      operation="docx_text_targets",
      format=self.format,
    )
  }
  @docx.text_targets(self.source_archive) catch {
    error => raise Render("\{Repr(error)}")
  }
}

///|
/// Change one listed DOCX text element while retaining normal session copy
/// verification. A stale expected value is refused, including for no-op edits.
pub fn DocumentSession::set_docx_target_text(
  self : DocumentSession,
  id : String,
  expected : String,
  replacement : String,
) -> DocumentSession raise DocumentSessionError {
  if self.format != Docx {
    raise OperationNotSupported(
      operation="set_docx_target_text",
      format=self.format,
    )
  }
  let candidate = @docx.set_target_text(
    self.source_archive,
    id,
    expected,
    replacement,
  ) catch {
    error => raise Render("\{Repr(error)}")
  }
  self.commit_candidate(candidate)
}
