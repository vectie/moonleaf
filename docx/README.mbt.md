# MoonLeaf DOCX

This package reads a deliberately small, portable subset of
WordprocessingML into `moonleaf/scene` and supports conservative replacement
inside individual `w:t` elements. It is a viewer and lightweight editing core,
not a full Microsoft Word compatibility layer.

The initial document traversal and run-style mapping were informed by
[docxjs](https://github.com/VolodymyrBaydalka/docxjs), an Apache-2.0 licensed
DOCX-to-HTML renderer. MoonLeaf is an independent pure-MoonBit implementation;
no docxjs source code is copied into this package.

`preview_document` retains paragraphs, tables, explicit page breaks, sections,
and resolved text formatting in main-document order for host preview renderers.
