# Correct one DOCX text element

Inspect a DOCX, choose one ordinary paragraph or table-cell text element, and
create a fresh verified copy without changing identical words elsewhere. This
complements the existing global `replace_text` operation; that API is unchanged.

## Run the example

Build the JavaScript adapter using the repository's pinned dependencies:

```sh
moon --target-dir /absolute/external-build build cmd/docx-edit --target js --frozen --strip -j 1
node /absolute/external-build/js/debug/build/cmd/docx-edit/docx-edit.js inspect kit/docx-edit/source.docx
node /absolute/external-build/js/debug/build/cmd/docx-edit/docx-edit.js apply kit/docx-edit/source.docx kit/docx-edit/request.json /fresh/client-copy.docx
node /absolute/external-build/js/debug/build/cmd/docx-edit/docx-edit.js inspect /fresh/client-copy.docx
```

The sample contains repeated `Acme` text in paragraphs and a table. Its request
changes just the first table cell to `  Client B & <雪😀>\r\n\t `, preserving the
other occurrences, header, opaque package part and source bytes. The output
path must not already exist. The command reads explicit files and writes the
copy itself with exclusive creation; do not redirect dataset bytes onto a source.
Reports are JSON on stdout; errors exit nonzero and emit no success report.

## Inspect and choose

`inspect SOURCE.docx` returns `moonleaf.docx-text-targets.v1` with the exact source
SHA-256, ordered `targets` (`id`, `text`) and scope warnings. A target ID such as
`body/tbl:3/tr:2/tc:1/p:1/r:1/t:1` is a path through the main document. Each number
is the one-based position among all element children of that parent, including
property elements; whitespace and comments do not count. IDs do not depend on
the text's value, so duplicate text can be selected deliberately and empty text
elements remain addressable. They are not permanent IDs across source revisions.

Create a UTF-8 request with exactly these five fields:

```json
{
  "version": 1,
  "source_sha256": "the exact 64-character SHA-256 from inspect",
  "target": "the exact target ID from inspect",
  "expected": "the complete current text of this one element",
  "replacement": "the complete replacement text"
}
```

`apply SOURCE.docx REQUEST.json FRESH_COPY.docx` requires the source digest and
full expected text to agree. There is no substring, cross-run or replace-all
interpretation. Empty replacements erase the selected text but retain its slot;
empty slots can be filled. An identical replacement is a no-op to package parts
but can still be saved to a distinct copy. Missing or stale targets fail even
for identical expected/replacement strings. Inspect again after any source
change, including a successful edit. The existing JSON parser keeps the final
value of duplicate property names; provide unique keys.

The successful `moonleaf.docx-text-copy.v1` report includes original and copy
SHA-256, chosen ID, before/after text, whether it changed, reopen and exact byte
readback results, and the same warnings. The adapter uses the existing session
save-as-copy check, reopens the exact bytes again to compare the selected target,
then writes with `wx` and reads back the file bytes. The source is never written.
A failed disk write/readback may leave a partial or unverified fresh destination;
there is no success report, automatic deletion, overwrite or retry. Retry with a
new destination after checking the failure. There is no filesystem lock against
another process changing the source after it has been read; the report describes
the exact input snapshot. Hosts still own permissions, destinations, conflict
handling, source retention and any delivery decision.

## Supported subset and preservation

- Standard transitional `w:document` with the standard `xmlns:w` binding and one
  direct `w:body`. Rebinding that prefix and complex fields (`w:fldChar` or
  `w:instrText`, which may span paragraphs) refuse this targeted workflow.
- Direct body paragraphs, and direct paragraphs inside cells of one-level body
  tables. Within those paragraphs, only direct `w:r` → `w:t` elements are listed.
- Headings and lists using ordinary runs are included. Rich run properties,
  surrounding tabs/breaks, table properties and other text elements are retained.
- Hyperlinks, content controls, tracked-change wrappers, drawings, nested tables,
  headers and footers are not selectable. Their content can remain in the source;
  an inspect result is not a complete document text inventory or a fidelity claim.
- The selected element's entire text is replaced and `xml:space="preserve"` is
  set. Its other attributes are retained as decoded XML values. Selected CDATA,
  comments and entity spellings may be rewritten within that selected element.
  Every character outside that element in `word/document.xml` is kept verbatim,
  including comments, processing instructions, other entity spellings and source
  formatting. All other package-part payloads are kept byte-for-byte.
- XML escaping preserves literal `&`, `<`, Unicode, CR/CRLF, tabs and leading or
  trailing whitespace. XML 1.0-forbidden replacement controls, U+FFFE/U+FFFF and
  unpaired surrogates are refused. Text newlines do not create Word paragraph or
  break elements; no line-layout equivalence is promised.
- This uses MoonLeaf's existing lexical XML parser and archive policy. It is not
  general OOXML validation, namespace validation or hostile-document containment.
  ZIP layout, compression and signatures are not preserved/validated claims.

Limits: at most 10,000 selectable text elements and 32,768 UTF-16 units in one
replacement. Existing bounded XML parser limits also apply. The CLI requires
regular files: source at most 8 MiB; request at most 64 KiB. Archive open limits
are 8 MiB per compressed/uncompressed entry and 16 MiB total uncompressed content,
with existing entry-count, CRC, path and compression-ratio checks. Everything is
in memory, with no streaming or production performance SLA.

## Library and sessions

```mbt nocheck
let targets = @docx.text_targets(package)
let changed = @docx.set_target_text(package, targets[0].id, targets[0].text, "New")
let targets = session.docx_text_targets()
let changed = session.set_docx_target_text(targets[0].id, targets[0].text, "New")
let copy = changed.save_as_copy()
```

Library callers supply an already policy-opened package or session and must bind
IDs to that exact source/revision themselves. Session operations are DOCX-only;
XLSX/PPTX return `OperationNotSupported`. A real edit increments session revision
and dirty state; a validated no-op retains both. Original values are not mutated.

## Verification

Run `moon test docx . --target js --frozen --strip -j 1` with an absolute external
target, and `python3 tests/docx_edit_cli.py /absolute/external-build /fresh/evidence`.
The verifier retains actual CLI outputs and refusals, independently compares ZIP
part payloads and XML structure with Python, and checks original digests. When
`python-docx` is installed it also creates and independently reopens a proposal
with bold text, a table and a header. That is a library-produced fixture, not
Microsoft Word/LibreOffice visual qualification. Neither this workflow nor these
tests establish Office layout fidelity, print readiness, customer acceptance or
MoonDesk UI integration.
