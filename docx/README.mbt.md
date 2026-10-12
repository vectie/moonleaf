# MoonLeaf DOCX

This package reads a deliberately small, portable subset of
WordprocessingML into `moonleaf/scene` and supports conservative replacement
inside Word paragraphs. It is a viewer and lightweight editing core,
not a full Microsoft Word compatibility layer.

The initial document traversal and run-style mapping were informed by
[docxjs](https://github.com/VolodymyrBaydalka/docxjs), an Apache-2.0 licensed
DOCX-to-HTML renderer. MoonLeaf is an independent pure-MoonBit implementation;
no docxjs source code is copied into this package.

`preview_document` retains paragraphs, tables, explicit page breaks, sections,
resolved text formatting, and direct Word list numbering in main-document
order for host preview renderers. Each list paragraph carries its numbering ID,
level, format, label template, and explicit start or restart. The preview
bridge emits these as a nullable `list` object on paragraph JSON, including
paragraphs inside tables. Word numbering inherited only through a paragraph
style remains outside this bounded preview subset.

The `cmd/preview` bridge exposes `edit-docx-copy SOURCE OUTPUT`. It accepts a
UTF-8 JSON request on stdin with `find` and `replace` strings, performs literal,
case-sensitive replacement within Word paragraphs, including adjacent simple
`w:r` runs in the main body, headers, and footers, and writes a new
verified DOCX package. The source stays untouched. A missing match fails before
creating an output file. Matches do not cross paragraphs, breaks, fields,
drawings, or other structural boundaries. Tracked revisions remain outside
this bounded operation.
The bridge limits source files to 8 MB, search text to 256 UTF-16 code units,
and replacement text to 32,768 UTF-16 code units.
The same command also accepts `{ "paragraph_index": 0,
"expected_text": "old", "replace": "new" }`. The zero-based index counts
top-level body paragraphs in the preview, not table-cell paragraphs. MoonLeaf
checks the exact previous text, edits only simple Word text runs, retains the
paragraph settings and first run style, then saves and reopens a new package.
It refuses paragraphs with fields, links, page breaks, tracked revisions, or
other complex children. This is a direct paragraph edit, not page-layout
editing; source files are left untouched.
