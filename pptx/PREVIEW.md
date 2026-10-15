# Presentation preview and edited copies

Public pure MoonBit helpers:

- preview_json(package, source_sha256) → moonleaf.pptx-preview.v1 JSON.
- source_sha256(source_bytes) → lowercase SHA-256 hex.
- edit_copy(source_bytes, request) → (copy_bytes, receipt_json).
- plain_text(package) → decoded slide/table/note text for attachment indexing.

The shared preview CLI dispatches preview-pptx SOURCE and edit-pptx-copy
SOURCE OUTPUT. File I/O stays in the existing CLI adapter; scene construction,
SVG, JSON, digest checking and Office mutation remain MoonBit.

## Preview

Reuses the existing read, read_outline, read_tables and text_targets APIs.
Slides retain presentation order, source part/name/hidden state, source EMU
dimensions, full outline blocks and speaker-note blocks. The first source text
is used as a display title when the slide has no explicit title placeholder.

SVG uses the existing neutral scene's source transforms and coordinates.
Ordinary text shapes show direct/inherited paragraph font size, color,
bold/italic/underline, font family, bullet character, paragraph alignment,
spacing, textbox insets and vertical anchor. Text is decoded by the existing
XML reader and escaped when serialized. Basic theme palette colors resolve
from the local package. Rectangle/rounded rectangle/ellipse/line/triangle/
diamond shapes use source solid fill and line styles.

Text width and line wrapping use a disclosed neutral glyph-width
approximation rather than Office's shaping/auto-fit engine. Source bounds clip
the visual text; full text remains readable in the outline and edit-target
list. Unsupported geometry, non-solid fills, rotation/flip orientation and
overflow get source warnings.

PNG/JPEG/GIF images use the original relationship/content-type/signature
checks, are read only from local package parts, and are embedded as base64 data
URIs. Linked/external resources are never fetched. Image cropping is not
reproduced and is labelled. Tables and notes remain readable in accompanying
JSON when absent from the neutral scene. Charts/SmartArt, layouts/masters,
animations, media and complete Office rendering are outside this viewer.

Text-outline warnings are prefixed as such; they describe extraction limits
and do not imply that supported SVG images are absent.

## Editing

Request: target, expected, replacement and optional source_sha256.
The original set_target_text replaces one exact supported a:r/a:t run,
preserving surrounding source markup and unrelated package parts. Structural
target IDs remain source-bound, with original shape/slide references. A stale
digest or expected text produces the existing scoped PPTX error.

Equal expected/replacement is a valid no-op: original bytes are written as the
copy, changed is false. Changed edits save the original OPC package with only
the targeted text splice.

Receipt contract moonleaf.pptx-edit-copy.v1 contains changed, byte length and
the original source_sha256. Hashing reuses the project's existing pure MoonBit
pdflite SHA-256 implementation; no added JavaScript cryptography/domain engine.

Notes editing, slide ordering and shape creation are not part of this first
viewer/edit interface. Delivery uses compilation/info/fmt only, without deck
creation demonstrations, rendering checks or test suites.

The extract-pptx SOURCE OUTPUT command writes plain_text as UTF-8 through the
existing file adapter. Extraction follows presentation order, labels hidden
slides, keeps stored table rows as tab-separated cells, and includes speaker
notes. It reuses read_outline rather than adding a second parser or JavaScript
document-text engine.
