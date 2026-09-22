# MoonLeaf native PDF legal profile

`render_docx_pdf` owns OOXML interpretation, glyph selection, wrapping, page
placement and PDF bytes. It does not delegate rendering to LibreOffice, Chrome
or a renamed external engine. The host can use Poppler to rasterize the emitted
PDF for visual inspection. Rasterization success is not human layout approval.

## Implemented

- Static TrueType `glyf` fonts, Unicode cmap 4/12, hmtx advances, exact internal
  family-name checks, OS/2 embedding restrictions, complete embedded fonts,
  PDF Type0/CIDFontType2 + ToUnicode. Named CJK and Latin families must be supplied;
  missing families or glyphs fail rather than substituting a system font.
- A4/custom bounded page geometry and margins; resolved DOCX run/paragraph styles;
  font sizes, first/hanging/left/right indents, before/after spacing, exact/minimum
  line height, left/center/right/both alignment, explicit page breaks and underlining.
- Single-level decimal and ChineseCounting numbering (1..99), start values,
  CJK closing punctuation avoidance and Latin alphanumeric word wrapping.
- Fixed table widths, horizontal spans, per-cell/default margins, uniform single
  borders, exact/minimum row heights, top/center/bottom alignment, row page breaks,
  and bounded page-horizontal/text-vertical floating-table offsets.
- Normalized XLSX cell-value PDF proofs, separate from the delivered unchanged
  workbook. This is not Excel print-layout fidelity. Missing cached formulas,
  merged cells, unsupported formats and parser warnings fail closed.

## Explicit limits

Not an Office clone or a claim of pixel-identical Word pagination. Full OpenType
GSUB/GPOS shaping, bidi/complex scripts, bold/italic face selection, variable/CFF/TTC
fonts, images, headers/footers, vertical table merges, multi-column sections,
multi-level lists, keep-with-next, mixed borders and charts remain unsupported.
Paragraphs stay together; oversized paragraphs/rows fail rather than clipping.
Word grid/kinsoku/mixed-script spacing controls are conservatively approximated
by this profile, not a certified Word typography engine. Floating text wrapping
around tables is not implemented: tables participate in document flow at their
specified offset. A legal template needs real licensed fonts and independent
visual acceptance before its deployment capability may be attested.

The original undertaking has been used as a **structural test only**, with
explicitly replaced OFL Noto Sans SC test fonts. Such results must never be
presented as a certified rendering of the original font-preserving template.
Tests do not generate readiness proofs or operator approvals.

Font `fsType` permission is a technical embedding flag, not proof of ownership.
Deployers must provide the font license evidence separately. Font binaries and
proprietary license material must not be committed to this repository.
