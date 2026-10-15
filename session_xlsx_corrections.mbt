///|
/// Apply one atomic batch of exact XLSX text corrections. The caller binds the
/// request to its original bytes; all expected values refer to this session.
pub fn DocumentSession::correct_xlsx_text_cells(
  self : DocumentSession,
  edits : Array[@xlsx.TextCellCorrection],
) -> DocumentSession raise DocumentSessionError {
  if self.format != Xlsx {
    raise OperationNotSupported(
      operation="correct_xlsx_text_cells",
      format=self.format,
    )
  }
  let candidate = @xlsx.correct_text_cells(self.source_archive, edits) catch {
    error => raise Render("\{Repr(error)}")
  }
  self.commit_candidate(candidate)
}
