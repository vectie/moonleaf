#!/usr/bin/env python3
"""Run the real Node adapter, retain every invocation and check PPTX XML independently."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from urllib.parse import urlparse, unquote
import xml.etree.ElementTree as ET
import zipfile

build, out = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=False)
root = Path(__file__).resolve().parents[1]
cli = build / 'js/debug/build/cmd/pptx-outline/pptx-outline.js'
fixture = root / 'kit/presentation-outline/quarterly-review.pptx'
source = out / 'source # (review) 雪.pptx'
shutil.copyfile(fixture, source)
calls = []

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(label, *args, ok=True):
    p = subprocess.run(['node', str(cli), *map(str, args)], capture_output=True)
    (out / f'{label}.stdout').write_bytes(p.stdout)
    (out / f'{label}.stderr').write_bytes(p.stderr)
    calls.append({'label': label, 'argv': list(map(str, args)), 'exit': p.returncode, 'expected_success': ok})
    assert (p.returncode == 0) == ok, (label, p.stdout, p.stderr)
    if not ok:
        assert p.stdout == b'', (label, 'unexpected success output')
        return
    return json.loads(p.stdout)

with zipfile.ZipFile(source) as z:
    parts = {n: z.read(n) for n in z.namelist()}
    assert z.testzip() is None
original_hash = digest(source)
report = run('inspect-producer', 'inspect', source)
assert report['schema'] == 'moonleaf.presentation-outline.v1'
assert report['source_sha256'] == original_hash
uri = report['source_uri']
assert urlparse(uri).scheme == 'file' and Path(unquote(urlparse(uri).path)) == source.resolve()
slides = report['outline']['slides']
assert [s['part'] for s in slides] == ['ppt/slides/slide2.xml', 'ppt/slides/slide1.xml']
assert [s['title'] for s in slides] == ['Budget <draft>', 'Operations | October']
assert [s['hidden'] for s in slides] == [True, False]
assert slides[0]['blocks'][1]['rows'] == [['Item','USD'],['Hosting','1200'],['Research','Line 1\nLine 2']]
assert slides[1]['blocks'][1]['paragraphs'] == ['Ship the pilot','Review supplier costs','雪😀 & partners']
assert slides[0]['notes'][0]['paragraphs'] == ['Check the research estimate.','Budget is not approved.']
assert slides[1]['notes'][0]['paragraphs'] == ['Ask for a decision.','Owner: operations','Do not distribute the draft.']
assert len(slides[0]['notes']) == len(slides[1]['notes']) == 1

# Independent XML checks prove every source part and shape reference resolves.
ns = {'p': 'http://schemas.openxmlformats.org/presentationml/2006/main',
      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}
rns = '{http://schemas.openxmlformats.org/package/2006/relationships}'
for s in slides:
    for part, blocks in [(s['part'], s['blocks']), (s['notes_part'], s['notes'])]:
        tree = ET.fromstring(parts[part])
        ids = {v.attrib['id'] for v in tree.findall('.//p:cNvPr', ns)}
        assert all(b['shape_id'] in ids for b in blocks)
        for b in blocks:
            assert b['kind'] in ('text', 'table')
            for text in b['paragraphs']:
                assert text in ''.join(tree.itertext())
    relpart = str(Path(s['part']).parent / '_rels' / (Path(s['part']).name + '.rels'))
    rels = ET.fromstring(parts[relpart])
    note_rels = [r for r in rels if r.attrib['Type'].endswith('/notesSlide')]
    assert len(note_rels) == 1
    import posixpath
    assert posixpath.normpath(posixpath.join(posixpath.dirname(s['part']), note_rels[0].attrib['Target'])) == s['notes_part']

json_path, markdown_path = out/'outline.json', out/'outline.md'
for fmt, path in [('json', json_path), ('markdown', markdown_path)]:
    exported = run('export-'+fmt, 'export', source, fmt, path)
    assert exported['source_sha256'] == original_hash
    assert exported['output_sha256'] == digest(path)
    assert exported['readback_equal'] is True and exported['slides'] == 2
assert json.loads(json_path.read_text()) == report
md = markdown_path.read_text()
assert f'[PPTX source](<{uri}>)' in md and original_hash in md
assert md.index('## Slide 1 (hidden)') < md.index('## Slide 2')
assert 'Budget &lt;draft&gt;' in md and 'Operations \\| October' in md
assert '| Hosting | 1200 |' in md and '| Research | Line 1<br>Line 2 |' in md
assert 'Budget is not approved.' in md and slides[0]['notes_part'] in md
assert digest(source) == original_hash

# Fresh output only: same file, existing file, directory, hardlink and symlink.
for label, target in [('source-output', source), ('existing-output', json_path), ('directory-output', out)]:
    run(label, 'export', source, 'json', target, ok=False)
assert json.loads(json_path.read_text()) == report and digest(source) == original_hash
hard = out/'hardlink.pptx'; hard.hardlink_to(source)
link = out/'symlink.pptx'; link.symlink_to(source)
for label, target in [('hardlink-output', hard), ('symlink-output', link)]:
    run(label, 'export', source, 'markdown', target, ok=False)
assert digest(source) == original_hash
run('failed-first-write', 'export', source, 'json', out/'missing-dir'/'copy.json', ok=False)
run('retry-fresh-copy', 'export', source, 'json', out/'retried.json')
run('unsupported-format', 'export', source, 'html', out/'bad.html', ok=False)
assert not (out/'bad.html').exists()
run('missing-input', 'inspect', out/'missing.pptx', ok=False)
run('directory-input', 'inspect', out, ok=False)

notes_rel = 'ppt/slides/_rels/slide2.xml.rels'
notes_xml = parts[notes_rel].decode()
notes_part = 'ppt/notesSlides/notesSlide2.xml'

def variant(label, replacements=None, removals=()):
    path = out/(label+'.pptx')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in parts.items():
            if name not in removals:
                z.writestr(name, (replacements or {}).get(name, data))
    return path

strict = variant('strict-notes', {notes_rel: notes_xml.replace(
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide',
    'http://purl.oclc.org/ooxml/officeDocument/relationships/notesSlide')})
assert run('strict-notes', 'inspect', strict)['outline']['slides'][0]['notes'] == slides[0]['notes']
no_notes = variant('no-linked-notes', removals=(notes_rel,))
assert run('no-linked-notes', 'inspect', no_notes)['outline']['slides'][0].get('notes_part') is None
renamed = 'ppt/notesSlides/speaker-material.xml'
renamed_path = out/'renamed-notes.pptx'
with zipfile.ZipFile(renamed_path, 'w', zipfile.ZIP_DEFLATED) as z:
    for name,data in parts.items():
        if name == notes_rel: data = notes_xml.replace('notesSlide2.xml','speaker-material.xml')
        if name == notes_part: name = renamed
        z.writestr(name,data)
assert run('renamed-notes', 'inspect', renamed_path)['outline']['slides'][0]['notes_part'] == renamed

external = ET.fromstring(parts[notes_rel])
for rel in external:
    if rel.attrib['Type'].endswith('/notesSlide'): rel.set('TargetMode','External')
ambiguous = ET.fromstring(parts[notes_rel])
for rel in list(ambiguous):
    if rel.attrib['Type'].endswith('/notesSlide'):
        duplicate = ET.SubElement(ambiguous, rns+'Relationship', dict(rel.attrib))
        duplicate.set('Id','duplicate-note')
for label, replacements, removals in [
    ('external-notes', {notes_rel: ET.tostring(external)}, ()),
    ('ambiguous-notes', {notes_rel: ET.tostring(ambiguous)}, ()),
    ('missing-linked-notes', {}, (notes_part,)),
    ('malformed-notes', {notes_part: '<p:notes>'}, ()),
    ('wrong-notes-root', {notes_part: '<p:sld/>'}, ()),
    ('traversal-notes', {notes_rel: notes_xml.replace('../notesSlides/notesSlide2.xml','../../../outside.xml')}, ()),
    ('malformed-slide', {'ppt/slides/slide2.xml': '<p:sld>'}, ()),
]:
    path = variant(label, replacements, removals)
    destination = out/(label+'.json')
    run(label, 'export', path, 'json', destination, ok=False)
    assert not destination.exists()
invalid = out/'not-zip.pptx'; invalid.write_text('not an office package')
run('not-zip', 'inspect', invalid, ok=False)
large = out/'oversized.pptx'
with large.open('wb') as f: f.truncate(8_388_609)
run('oversized-input', 'inspect', large, ok=False)
assert digest(source) == original_hash and source.read_bytes() == fixture.read_bytes()
result = {'status':'passed', 'invocations':len(calls), 'expected_refusals':sum(not x['expected_success'] for x in calls),
          'producer':'python-pptx 1.0.2', 'source_sha256':original_hash,
          'independent_xml_source_references':True, 'source_unchanged':True, 'calls':calls}
(out/'RESULT.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k != 'calls'}))
