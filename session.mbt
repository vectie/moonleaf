///|
pub(all) enum DocumentFormat {
  Docx
  Xlsx
  Pptx
} derive(Debug, Eq)

///|
pub(all) struct DocumentCapabilities {
  render_scene : Bool
  save_as_copy : Bool
  replace_text : Bool
  set_cell_text : Bool
} derive(Debug, Eq)

///|
pub(all) struct DocumentDiagnostic {
  code : String
  message : String
  part : String?
} derive(Debug, Eq)

///|
pub(all) suberror DocumentSessionError {
  UnsupportedFormat(String)
  Package(String)
  Render(String)
  OperationNotSupported(operation~ : String, format~ : DocumentFormat)
  InvalidFind(String)
  InvalidCoordinates(row~ : Int, column~ : Int)
  SheetNotFound(String)
  FormulaCell(sheet~ : String, row~ : Int, column~ : Int)
  MergedCellNotAnchor(sheet~ : String, row~ : Int, column~ : Int)
  SaveVerification(String)
} derive(Debug, Eq)

///|
pub struct DocumentSession {
  priv filename : String
  priv format : DocumentFormat
  priv archive_policy : ArchivePolicy
  priv source_archive : @opc.Package
  priv scene : @scene.Document
  priv diagnostics : Array[DocumentDiagnostic]
  priv revision : Int
  priv dirty : Bool
}

///|
pub struct VerifiedDocumentCopy {
  priv bytes : FixedArray[Byte]
  priv session : DocumentSession
}

///|
pub fn DocumentFormat::capabilities(
  self : DocumentFormat,
) -> DocumentCapabilities {
  match self {
    Docx | Pptx =>
      {
        render_scene: true,
        save_as_copy: true,
        replace_text: true,
        set_cell_text: false,
      }
    Xlsx =>
      {
        render_scene: true,
        save_as_copy: true,
        replace_text: false,
        set_cell_text: true,
      }
  }
}

///|
fn format_from_filename(
  filename : String,
) -> DocumentFormat raise DocumentSessionError {
  let lower = filename.to_lower()
  if lower.has_suffix(".docx") {
    Docx
  } else if lower.has_suffix(".xlsx") {
    Xlsx
  } else if lower.has_suffix(".pptx") {
    Pptx
  } else {
    raise DocumentSessionError::UnsupportedFormat(filename)
  }
}

///|
fn render_archive(
  archive : @opc.Package,
  format : DocumentFormat,
) -> @scene.Document raise DocumentSessionError {
  match format {
    Docx =>
      @scene.Document::TextDocument(@docx.read(archive)) catch {
        error => raise DocumentSessionError::Render("\{Repr(error)}")
      }
    Xlsx =>
      @scene.Document::WorkbookDocument(@xlsx.read(archive)) catch {
        error => raise DocumentSessionError::Render("\{Repr(error)}")
      }
    Pptx =>
      @scene.Document::PresentationDocument(@pptx.read(archive)) catch {
        error => raise DocumentSessionError::Render("\{Repr(error)}")
      }
  }
}

///|
fn normalized_diagnostics(scene : @scene.Document) -> Array[DocumentDiagnostic] {
  let warnings = match scene {
    TextDocument(document) => document.warnings
    WorkbookDocument(workbook) => workbook.warnings
    PresentationDocument(presentation) => presentation.warnings
  }
  warnings.map(fn(warning) {
    { code: warning.code, message: warning.message, part: warning.part, }
  })
}

///| Opens and renders an OOXML editing session with conservative ZIP/OPC

///|
/// limits, mandatory CRC verification, revision zero, and a clean baseline.
pub fn open_session(
  filename : String,
  content : FixedArray[Byte],
) -> DocumentSession raise DocumentSessionError {
  open_session_with_policy(filename, content, @opc.ArchivePolicy::default())
}

///|
/// Open a document session with explicit, validated ZIP/OPC limits.
pub fn open_session_with_policy(
  filename : String,
  content : FixedArray[Byte],
  policy : ArchivePolicy,
) -> DocumentSession raise DocumentSessionError {
  let format = format_from_filename(filename)
  let archive = @opc.open_with_policy(content, policy) catch {
    error => raise DocumentSessionError::Package(error.to_string())
  }
  let scene = render_archive(archive, format)
  {
    format,
    filename,
    archive_policy: policy,
    source_archive: archive,
    scene,
    diagnostics: normalized_diagnostics(scene),
    revision: 0,
    dirty: false,
  }
}

///|
pub fn DocumentSession::filename(self : DocumentSession) -> String {
  self.filename
}

///|
pub fn DocumentSession::format(self : DocumentSession) -> DocumentFormat {
  self.format
}

///|
pub fn DocumentSession::capabilities(
  self : DocumentSession,
) -> DocumentCapabilities {
  self.format.capabilities()
}

///|
fn clone_text_run(run : @scene.TextRun) -> @scene.TextRun {
  { text: run.text, style: run.style, }
}

///|
fn clone_text_runs(runs : Array[@scene.TextRun]) -> Array[@scene.TextRun] {
  runs.map(clone_text_run)
}

///|
fn clone_text_block(block : @scene.TextBlock) -> @scene.TextBlock {
  match block {
    Paragraph(runs) => Paragraph(clone_text_runs(runs))
    Heading(level, runs) => Heading(level, clone_text_runs(runs))
    ListItem(level~, ordered~, runs) =>
      ListItem(level~, ordered~, clone_text_runs(runs))
    Table(rows) => Table(rows.map(fn(row) { row.copy() }))
  }
}

///|
fn clone_slide_element(element : @scene.SlideElement) -> @scene.SlideElement {
  match element {
    TextBox(bounds~, runs~) => TextBox(bounds~, runs=clone_text_runs(runs))
    Shape(kind~, bounds~, text~) =>
      Shape(kind~, bounds~, text=clone_text_runs(text))
    Image(bounds~, relationship_id~) => Image(bounds~, relationship_id~)
  }
}

///|
fn clone_scene(scene : @scene.Document) -> @scene.Document {
  match scene {
    TextDocument(document) =>
      TextDocument({
        blocks: document.blocks.map(clone_text_block),
        warnings: document.warnings.copy(),
      })
    WorkbookDocument(workbook) =>
      WorkbookDocument({
        sheets: workbook.sheets.map(fn(sheet) {
          {
            name: sheet.name,
            cells: sheet.cells.copy(),
            merged_ranges: sheet.merged_ranges.copy(),
          }
        }),
        warnings: workbook.warnings.copy(),
      })
    PresentationDocument(presentation) =>
      PresentationDocument({
        slides: presentation.slides.map(fn(slide) {
          {
            name: slide.name,
            width: slide.width,
            height: slide.height,
            elements: slide.elements.map(clone_slide_element),
          }
        }),
        warnings: presentation.warnings.copy(),
      })
  }
}

///|
pub fn DocumentSession::scene(self : DocumentSession) -> @scene.Document {
  clone_scene(self.scene)
}

///|
pub fn DocumentSession::diagnostics(
  self : DocumentSession,
) -> Array[DocumentDiagnostic] {
  self.diagnostics.copy()
}

///|
pub fn DocumentSession::revision(self : DocumentSession) -> Int {
  self.revision
}

///|
pub fn DocumentSession::is_dirty(self : DocumentSession) -> Bool {
  self.dirty
}

///|
fn DocumentSession::commit_candidate(
  self : DocumentSession,
  candidate : @opc.Package,
) -> DocumentSession raise DocumentSessionError {
  let scene = render_archive(candidate, self.format)
  if candidate == self.source_archive {
    return self
  }
  {
    format: self.format,
    filename: self.filename,
    archive_policy: self.archive_policy,
    source_archive: candidate,
    scene,
    diagnostics: normalized_diagnostics(scene),
    revision: self.revision + 1,
    dirty: true,
  }
}

///|
pub fn DocumentSession::replace_text(
  self : DocumentSession,
  find : String,
  replacement : String,
) -> DocumentSession raise DocumentSessionError {
  if find == "" {
    raise DocumentSessionError::InvalidFind("find text must not be empty")
  }
  match self.format {
    Xlsx =>
      raise OperationNotSupported(operation="replace_text", format=self.format)
    Docx | Pptx => ()
  }
  if find == replacement {
    return self
  }
  let candidate = match self.format {
    Docx =>
      @docx.replace_text(self.source_archive, find, replacement) catch {
        error => raise DocumentSessionError::Render("\{Repr(error)}")
      }
    Pptx =>
      @pptx.replace_text(self.source_archive, find, replacement) catch {
        error => raise DocumentSessionError::Render("\{Repr(error)}")
      }
    Xlsx =>
      raise DocumentSessionError::OperationNotSupported(
        operation="replace_text",
        format=self.format,
      )
  }
  self.commit_candidate(candidate)
}

///|
fn DocumentSession::validate_xlsx_cell(
  self : DocumentSession,
  sheet_name : String,
  row : Int,
  column : Int,
) -> Unit raise DocumentSessionError {
  if row < 1 || row > 1048576 || column < 1 || column > 16384 {
    raise DocumentSessionError::InvalidCoordinates(row~, column~)
  }
  let workbook = match self.scene {
    WorkbookDocument(workbook) => workbook
    _ =>
      raise DocumentSessionError::OperationNotSupported(
        operation="set_cell_text",
        format=self.format,
      )
  }
  let mut matched : @scene.Sheet? = None
  for candidate in workbook.sheets {
    if candidate.name == sheet_name {
      matched = Some(candidate)
      break
    }
  }
  let sheet = matched
  guard sheet is Some(sheet) else {
    raise DocumentSessionError::SheetNotFound(sheet_name)
  }
  for cell in sheet.cells {
    if cell.row == row && cell.column == column {
      match cell.value {
        Formula(..) =>
          raise DocumentSessionError::FormulaCell(
            sheet=sheet_name,
            row~,
            column~,
          )
        _ => ()
      }
    }
  }
  for range in sheet.merged_ranges {
    if row >= range.start_row &&
      row <= range.end_row &&
      column >= range.start_column &&
      column <= range.end_column &&
      (row != range.start_row || column != range.start_column) {
      raise DocumentSessionError::MergedCellNotAnchor(
        sheet=sheet_name,
        row~,
        column~,
      )
    }
  }
}

///|
fn DocumentSession::cell_text_equals(
  self : DocumentSession,
  sheet_name : String,
  row : Int,
  column : Int,
  text : String,
) -> Bool {
  match self.scene {
    WorkbookDocument(workbook) =>
      workbook.sheets.any(sheet => {
        sheet.name == sheet_name &&
        // A same-value request is a no-op only for one logical target. Let the
        // editor report ambiguous coordinates instead of bypassing its check.
        (match
          sheet.cells.filter(cell => cell.row == row && cell.column == column) {
          [{ value: Text(existing), .. }] => existing == text
          _ => false
        })
      })
    _ => false
  }
}

///|
pub fn DocumentSession::set_cell_text(
  self : DocumentSession,
  sheet : String,
  row : Int,
  column : Int,
  text : String,
) -> DocumentSession raise DocumentSessionError {
  if self.format != Xlsx {
    raise DocumentSessionError::OperationNotSupported(
      operation="set_cell_text",
      format=self.format,
    )
  }
  self.validate_xlsx_cell(sheet, row, column)
  if self.cell_text_equals(sheet, row, column, text) {
    return self
  }
  let candidate = @xlsx.set_cell_text(
    self.source_archive,
    sheet,
    row,
    column,
    text,
  ) catch {
    error => raise DocumentSessionError::Render("\{Repr(error)}")
  }
  self.commit_candidate(candidate)
}

///|
/// Apply existing-cell edits to an XLSX sheet as one verified session change.
pub fn DocumentSession::set_cells_text(
  self : DocumentSession,
  sheet : String,
  edits : Array[(Int, Int, String)],
) -> DocumentSession raise DocumentSessionError {
  if self.format != Xlsx {
    raise DocumentSessionError::OperationNotSupported(
      operation="set_cells_text",
      format=self.format,
    )
  }
  if edits.is_empty() {
    return self
  }
  for (row, column, text) in edits {
    self.validate_xlsx_cell(sheet, row, column)
    if text.length() > 32_768 {
      raise DocumentSessionError::Render("cell text exceeds limit")
    }
  }
  let candidate = @xlsx.set_cells_text(self.source_archive, sheet, edits) catch {
    error => raise DocumentSessionError::Render("\{Repr(error)}")
  }
  self.commit_candidate(candidate)
}

///|
fn same_parts(left : @opc.Package, right : @opc.Package) -> Bool {
  if left.parts.length() != right.parts.length() {
    return false
  }
  left.parts.all(fn(part) {
    match right.part(part.name) {
      Some(saved) => saved.content == part.content
      None => false
    }
  })
}

///|
pub fn DocumentSession::save_as_copy(
  self : DocumentSession,
) -> VerifiedDocumentCopy raise DocumentSessionError {
  let bytes = @opc.save(self.source_archive) catch {
    error => raise DocumentSessionError::Package(error.to_string())
  }
  let reopened_package = @opc.open_with_policy(bytes, self.archive_policy) catch {
    error => raise DocumentSessionError::SaveVerification(error.to_string())
  }
  let reopened_scene = render_archive(reopened_package, self.format)
  if reopened_scene != self.scene {
    raise DocumentSessionError::SaveVerification(
      "semantic scene changed after reopen",
    )
  }
  if !same_parts(self.source_archive, reopened_package) {
    raise DocumentSessionError::SaveVerification(
      "OPC part names or payloads changed after reopen",
    )
  }
  {
    bytes,
    session: {
      format: self.format,
      filename: self.filename,
      archive_policy: self.archive_policy,
      source_archive: reopened_package,
      scene: reopened_scene,
      diagnostics: normalized_diagnostics(reopened_scene),
      revision: self.revision,
      dirty: false,
    },
  }
}

///|
pub fn VerifiedDocumentCopy::bytes(
  self : VerifiedDocumentCopy,
) -> FixedArray[Byte] {
  self.bytes.copy()
}

///|
pub fn VerifiedDocumentCopy::session(
  self : VerifiedDocumentCopy,
) -> DocumentSession {
  self.session
}
