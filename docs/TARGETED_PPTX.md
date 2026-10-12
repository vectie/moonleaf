# Correct one presentation text run

R296 lets a reviewer inspect exact slide text targets and correct one selected
run in a fresh verified PPTX copy. Duplicate words in other runs, shapes or slides
stay unchanged. This fulfills a missing deliberate-selection step in PRD W03/B07
and the W06/R02 reviewed-copy workflow. The existing global `replace_text` API and
R265 read-only outline remain unchanged. No MoonDesk UI or MoonProj delivery
integration is added.

## Inspect, choose, copy

Build the Node adapter with the pinned toolchain and real `hustcer/fzip@0.8.5`.
Use an absolute target outside the source tree for every Moon command.

```sh
moon --target-dir /absolute/external-build build cmd/pptx-edit --target js --frozen --strip -j 1
node /absolute/external-build/js/debug/build/cmd/pptx-edit/pptx-edit.js inspect kit/pptx-edit/source.pptx
node /absolute/external-build/js/debug/build/cmd/pptx-edit/pptx-edit.js apply kit/pptx-edit/source.pptx kit/pptx-edit/request.json /fresh/client-copy.pptx
node /absolute/external-build/js/debug/build/cmd/pptx-edit/pptx-edit.js inspect /fresh/client-copy.pptx
```

The retained two-slide python-pptx 1.0.2 fixture contains repeated `Acme` runs,
bold styling, grouped text, a table, speaker notes and a picture. Human slide
order differs from part filename order; the first displayed slide is hidden.
The example corrects only its grouped `Acme` text. Its request digest matches the
committed fixture bytes. Regeneration changes the digest: inspect again and
update the request before applying it.

`inspect` emits `moonleaf.pptx-text-targets.v1`, with `source_sha256`, `targets`,
scope warnings and the session's scene diagnostics. Each target has:

- `id`: structural path such as `slide:1/cSld:1/spTree:1/grpSp:5/sp:3/txBody:3/p:3/r:1/t:1`
- `slide_number`: one-based presentation order, independent of filename order
- `part`: actual slide OPC path
- `shape_id`: source `cNvPr/@id`, or empty when absent; a display aid, not the key
- `hidden_slide`: whether the source slide explicitly has `show="0"` or `"false"`
- `text`: the complete decoded text of this one `a:t`

After the `slide:N` prefix, each ordinal is the one-based position among all
element children of its parent. Properties count; whitespace and comments do
not. Duplicate shape IDs and duplicate text do not make the structural path
ambiguous. IDs are valid only for that exact source snapshot. They are neither
persistent across revisions nor interchangeable with outline block references.
Inspect again after source edits, reorderings or successful corrections.

The UTF-8 request requires exactly these five fields:

```json
{
  "version": 1,
  "source_sha256": "64-character digest returned by inspect",
  "target": "exact inspected id",
  "expected": "complete original text",
  "replacement": "complete new text"
}
```

The adapter requires the source digest and full expected text to agree. It never
interprets a substring, cross-run match or replace-all operation. An empty string
erases text but retains the target; an empty existing element can be filled.
An identical replacement is a validated no-op and preserves package-part bytes.
Missing targets and stale expected text still fail for no-ops. The existing JSON
parser retains the final value of a duplicate property; supply unique keys.

`apply` returns `moonleaf.pptx-text-copy.v1` only after session save/reopen and
scene/package verification, inspection of the selected target in the exact output
bytes, exclusive fresh-file creation and exact disk readback. The report includes
source/copy digests, target, before/after text, changed flag, verification flags,
scope warnings and reopened scene diagnostics. Copy diagnostics are retained even
when the edited content is outside the neutral scene's current representation,
for example group contents. The explicit target check verifies that content.

The source is never opened for writing. Existing paths, including source paths,
symlinks and hardlinks, are refused by exclusive `wx` creation. A failed write or
readback may leave a partial/unverified fresh destination. It emits no successful
report, does not delete anything and does not retry automatically. Inspect the
failure and retry with a new path. The source digest identifies the bytes read;
there is no filesystem lock against a different process subsequently changing it.

## Precisely supported edits

- Referenced slide parts in presentation relationship order, including hidden
  slides. A repeated reference to the same part is refused.
- Standard transitional `p:sld` with explicit standard `xmlns:p` and `xmlns:a`
  bindings, one direct `p:cSld` and one direct `p:spTree`. Rebinding either prefix
  anywhere in a slide is refused. This deliberately excludes alternate-prefix
  and strict-namespace slides; it is not general namespace/XSD validation.
- Direct `p:sp/p:txBody/a:p/a:r/a:t` text and ordinary shapes inside `p:grpSp`
  groups. Only that direct structural chain is selectable. Properties and other
  elements are kept, but are not interpreted as permission to edit them.
- Tables, `a:fld` fields, speaker notes, masters, layouts, charts, SmartArt,
  comments, drawings and wrapped content are not selectable. An inspect result
  is not a complete text inventory. Existing fields are not recalculated.
- Only the chosen `a:t` element is rewritten, with XML escaping and
  `xml:space="preserve"`. Its other attributes are preserved as decoded values.
  Selected CDATA/comments/entity spellings may be normalized inside that one
  element. Every character outside it in the selected slide XML is retained;
  all other package-part payloads remain byte-for-byte unchanged.
- Leading/trailing spaces, literal `&`, `<`, Unicode, CR/CRLF and tabs survive XML
  round trip. Literal newlines do not create `a:br` or paragraph elements. Text
  layout, wrapping or font fit is not assessed. XML-forbidden controls,
  noncharacters U+FFFE/U+FFFF and unpaired surrogates are refused.

Limits: at most 200 slides, 10000 selectable text elements and 32768 UTF-16 units
per replacement. Existing bounded XML parsing applies. The CLI accepts regular
files: source <=8 MiB, request <=64 KiB; archive entries <=8 MiB compressed and
uncompressed, total expanded content <=16 MiB. Existing OPC CRC, entry-count,
path and ratio limits remain. In-memory operation has no production performance
SLA. ZIP byte layout and compression are not preserved guarantees.

No Office visual fidelity, print readiness, animation edit, signature validation,
macro safety, hostile-document sandbox, factual verification, delivery or customer
acceptance claim follows. External resources are not fetched. Hosts own file
permissions, destination choice, conflicts, retention and delivery authority.

## Library and sessions

```mbt nocheck
let targets = @pptx.text_targets(package)
let candidate = @pptx.set_target_text(package, targets[0].id, targets[0].text, "New")
let targets = session.pptx_text_targets()
let edited = session.set_pptx_target_text(targets[0].id, targets[0].text, "New")
let copy = edited.save_as_copy()
```

Callers bind IDs to an already policy-opened package or exact session revision.
A real session change increments its revision/dirty state; a validated no-op
retains it. Source packages/sessions are not mutated. Non-PPTX sessions return
`OperationNotSupported`. Pure library calls perform no filesystem/network effect.

## Focused verification

`pptx/text_targets_test.mbt` and `session_pptx_targets_test.mbt` exercise selection,
repeated values, groups, empty/no-op changes, lexical/package preservation, text
boundaries, malformed scopes, source immutability and verified session copies.
`tests/pptx_edit_cli.py EXTERNAL_BUILD FRESH_EVIDENCE_DIRECTORY` invokes the actual
Node adapter, independently resolves structural paths with Python XML, compares
ZIP CRC/part payloads, checks deliberate failures and fresh-path retry, and
reopens the result with python-pptx when available. It consumes the committed
fixture; no package install or fixture regeneration is required. The retained
R296 run used installed python-pptx 1.0.2. This is producer-library coverage,
not PowerPoint/LibreOffice visual acceptance or a host UI test.
