# Export a presentation review outline

R265 adds read-only PPTX intake for a reviewer who needs the slide text, ordinary
slide tables and speaker notes together in a searchable, source-linked artifact.
This is a bounded content extraction, not a slideshow renderer or PPTX editor.
It directly serves the PRD's W03/W05 presentation/business-document inspection
workflow and B07's honest supported slide representation. It does not qualify
MoonDesk integration or a complete-source, print-ready or customer-accepted claim.

## Use the Node adapter

Build the `cmd/pptx-outline` package on the JavaScript backend using the pinned
MoonBit toolchain and retained `hustcer/fzip@0.8.5`. Every Moon command must use an
absolute external target; no dependency upgrade is needed.

```sh
moon --target-dir /absolute/external/target build cmd/pptx-outline --target js --frozen --strip -j 1
node /absolute/external/target/js/debug/build/cmd/pptx-outline/pptx-outline.js inspect kit/presentation-outline/quarterly-review.pptx
node /absolute/external/target/js/debug/build/cmd/pptx-outline/pptx-outline.js export kit/presentation-outline/quarterly-review.pptx json /absolute/fresh-outline.json
node /absolute/external/target/js/debug/build/cmd/pptx-outline/pptx-outline.js export kit/presentation-outline/quarterly-review.pptx markdown /absolute/fresh-outline.md
```

`inspect` prints JSON. `export` writes a fresh file exclusively, reads it back,
compares its exact bytes, then prints the source/output SHA-256 and format.
Existing destinations, including the input, symlinks and hardlinks, are refused.
A failed readback or write never prints a success receipt; a partially written
file may remain and must be inspected or retried to a fresh destination. There
is no automatic deletion or overwrite. The source is never opened for writing.

Both formats include the SHA-256 of the bytes actually read and the real local
source's file URI. The Markdown source link opens the original when the reader
allows file links and that path still exists. It is not a remote share link.
Moving the source or sharing the outline on another machine requires retaining
and relinking the exact source; verify its SHA-256. No source is uploaded or
copied by this command. Exported speaker notes can contain private information;
review the outline before sharing it.

## Output and provenance

The JSON envelope is `moonleaf.presentation-outline.v1`:

- `source_sha256`, `source_uri`
- `outline.slides` in presentation relationship order, not filename order
- `outline.warnings` with extraction-wide and observed omissions

Each slide contains `number` (one-based presentation position), `part` (exact OPC
part), `name`, `hidden`, `title`, `blocks`, `notes`, and optional `notes_part`.
`notes_part` is omitted when there is no linked notes part. Hidden slides are
included and explicitly marked. A missing title becomes an empty string, not an
inferred title from unrelated text.

A block has `kind` (`text` or `table`), `shape_id` (the source `cNvPr/@id`, empty
if absent), `paragraphs`, and `rows`. Text blocks preserve ordered paragraphs,
empty paragraphs, cached field text and explicit text line breaks. Table cells
join their paragraphs with newline; rows/cells remain in stored grid order.
Blocks are in XML shape-tree order, including nested groups, which may differ
from visual reading order. Source part plus shape ID (or block ordinal when no
ID exists) helps inspect the source, but is not a persistent edit target. Bind
all these references to the source digest; do not reuse them after source edits.

Notes are followed through each slide's internal `notesSlide` relationship,
including strict and transitional OOXML relationship type URIs. Filename
numbering is not assumed. Body placeholders and non-placeholder text shapes are
included; notes slide thumbnails, dates, headers, footers, slide numbers, other
placeholders and notes-master content are omitted. Missing relationships mean
no notes, while malformed relationships, multiple notes targets, external
notes, above-root targets, missing linked parts and invalid notes roots fail the
whole extraction. External resources are never fetched.

Markdown contains escaped text, generic column labels (it does not promote the
first data row to a header), slide/notes source part references, shape IDs and
all diagnostics. It shows line breaks inside cells as `<br>`. It is intended
for review; JSON is the lossless representation of the extracted strings.
Markdown does not reproduce every blank paragraph or carriage-return encoding.

## Reusable library

```mbt nocheck
let container = @opc.open_with_policy(bytes, archive_policy)
let outline = @pptx.read_outline(container)
let markdown = outline.to_markdown()
```

The public `OutlineBlock`, `SlideOutline` and `PresentationOutline` values can
also be serialized with `ToJson`. The library has no file, network, or host
permission effects. A host supplies the archive policy and source identity.

## Scope and ceilings

- Up to 200 slides, 100000 total encountered shape-tree items and table cells,
  2000000 extracted UTF-16 text units including slide names, 1000 rows and 256
  columns per table. A failure returns no partial outline.
- The CLI accepts a regular PPTX ZIP input up to 8 MiB, at most 8 MiB per archive
  entry and 16 MiB total expanded bytes; the existing OPC entry/path/CRC policy
  and XML parser limits also apply. Library callers must use an appropriate OPC
  open policy; an already constructed in-memory Package is their responsibility.
- Ordinary `p:sp/p:txBody` and `graphicFrame/graphic/graphicData/tbl` structures
  only. Grouped text is included. Merged table cells remain raw grid cells, with
  a warning; spans are not reconstructed. Empty tables produce no Markdown grid.
- Charts, SmartArt, picture text/OCR, comments, layout/master text, media,
  animations, typography, bullets/levels and hyperlinks are not reproduced.
  A table or text not stored in the supported structures may be omitted.
- Uses MoonLeaf's existing lexical/local-name XML model, not XSD validation or
  namespace-URI semantic validation. Cached fields are not recalculated.
- No PPTX bytes are emitted or mutated, and no renderer runs. This adds no
  editing, full-Office, visual fidelity, signature validation, macro execution,
  hostile-document sandbox, print readiness or factual verification guarantee.

## Reproducible evidence

The committed kit is a real python-pptx 1.0.2-produced deck with two reordered
slides, a hidden budget slide, a table, Unicode text and linked notes. Its small
`make_fixture.py` generator is provided; regeneration needs that exact installed
producer version, but the verifier uses the committed bytes without installing
anything. ZIP timestamps can change its digest when regenerated.

`tests/pptx_outline_cli.py EXTERNAL_BUILD FRESH_EVIDENCE_DIRECTORY` invokes the
actual Node adapter and independently checks source XML references, relationships,
JSON/Markdown content, digest/readback, unchanged source, refusal and fresh-file
retry behavior. It preserves all invocation stdout/stderr and RESULT.json.
`pptx/outline_test.mbt` adds library coverage for ordering, groups, notes, tables,
Markdown escaping, malformed targets and resource boundaries. These tests do not
establish intended-size visual acceptance in PowerPoint or a MoonDesk UI flow.
