#!/usr/bin/env python3
"""Focused retained actual CLI evidence; never deletes fixtures or outputs."""
import csv, hashlib, io, json, subprocess, sys, zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

build, out = map(Path, sys.argv[1:])
assert build.is_absolute() and out.is_absolute()
out.mkdir(parents=True, exist_ok=False)
root = Path(__file__).resolve().parents[1]
kit = root / 'kit/markdown-tables'
source, query = kit / 'vendors.md', kit / 'query.json'
cli = build / 'js/debug/build/cmd/markdown-tables/markdown-tables.js'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
before = {str(p): digest(p) for p in (source, query)}
calls = []

def invoke(label, args, ok=True):
    p = subprocess.run(['node', str(cli), *map(str, args)], capture_output=True)
    (out / (label + '.stdout')).write_bytes(p.stdout)
    (out / (label + '.stderr')).write_bytes(p.stderr)
    calls.append({'label': label, 'argv': list(map(str, args)), 'exit': p.returncode, 'expected_success': ok})
    (out / 'invocations.json').write_text(json.dumps(calls, indent=2) + '\n')
    assert (p.returncode == 0) == ok, (label, p.stdout, p.stderr)
    if not ok:
        assert not p.stdout, label
        return
    return json.loads(p.stdout)

def export(label, src=source, table='table-1', sha=None, q=query, fmt='json', target=None, ok=True):
    target = target or out / (label + '.' + fmt)
    r = invoke(label, ['export', src, table, sha or digest(src), q, fmt, target], ok)
    if not ok:
        return
    assert r['source_sha256'] == digest(src) and r['output_sha256'] == digest(target)
    assert r['query_sha256'] == (None if str(q) == '-' else digest(Path(q)))
    assert r['query'] == (None if str(q) == '-' else json.loads(Path(q).read_text()))
    assert r['readback_equal'] is True and target.stat().st_mode & 0o777 == 0o600
    return r

listing = invoke('list', ['list', source])
assert listing['source_sha256'] == before[str(source)]
assert [t['id'] for t in listing['tables']] == ['table-1', 'table-2']
assert listing['tables'][0]['header_line'] == 13
assert listing['tables'][0]['source_lines'] == [15, 16, 17]
assert listing['tables'][1]['source_lines'] == [23, 24]
assert listing['warnings']
expected = [
    {'Vendor ID': '003', 'Vendor': '桜 🌙', 'Monthly cost': '12', 'Notes': '=literal, **quoted**'},
    {'Vendor ID': '001', 'Vendor': 'Cedar', 'Monthly cost': '20', 'Notes': 'SSO | SCIM'},
]
columns = list(expected[0])
expected_rows = [columns] + [[row[c] for c in columns] for row in expected]
for fmt in ('csv', 'json', 'xlsx'):
    target = out / ('selected.' + fmt)
    r = export('selected-' + fmt, fmt=fmt, target=target)
    assert r['source_lines'] == [17, 15]
    assert (r['input_rows'], r['matched_rows'], r['output_rows']) == (3, 2, 2)
    assert r['output_columns'] == columns
    if fmt == 'csv':
        assert list(csv.reader(io.StringIO(target.read_text()))) == expected_rows
    elif fmt == 'json':
        assert json.loads(target.read_text()) == expected
    else:
        ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        with zipfile.ZipFile(target) as z:
            assert z.testzip() is None
            sheet = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
            assert not sheet.findall('.//s:f', ns)
            rows = []
            for row in sheet.findall('s:sheetData/s:row', ns):
                cells = row.findall('s:c', ns)
                assert all(c.attrib.get('t') == 'inlineStr' for c in cells)
                rows.append([''.join(t.text or '' for t in c.findall('.//s:t', ns)) for c in cells])
            assert rows == expected_rows

r = export('owners', table='table-2', q='-')
assert r['source_lines'] == [23, 24]
assert json.loads((out / 'owners.json').read_text()) == [{'Team':'Ops','Owner':'Ada'},{'Team':'Research','Owner':'Ben'}]
export('all-shortlist', q='-')
assert json.loads((out / 'all-shortlist.json').read_text())[1]['Notes'] == '`trial`'
empty = out / 'empty.md'; empty.write_text('| a | b |\n| --- | --- |\n')
r = export('empty', src=empty, q='-')
assert r['output_rows'] == 0 and r['source_lines'] == [] and r['output_columns'] == ['a','b']
assert json.loads((out / 'empty.json').read_text()) == []
no_matches = out / 'no-matches-query.json'
q = json.loads(query.read_text()); q['filters'][0]['value'] = 'absent'
no_matches.write_text(json.dumps(q))
r = export('no-matches', q=no_matches)
assert r['matched_rows'] == r['output_rows'] == 0 and r['source_lines'] == []

changed = out / 'changed-source.md'; changed.write_text('# A different source\n' + source.read_text())
export('stale-source', src=changed, sha=before[str(source)], ok=False)
assert not (out / 'stale-source.json').exists()
export('unknown-table', table='table-3', ok=False)
assert not (out / 'unknown-table.json').exists()
for label, value in [
    ('ragged', '| a | b |\n| --- | --- |\n| ok | value |\n| bad | extra | cell |'),
    ('duplicate-header', '| a | a |\n| --- | --- |'),
    ('raw-code-pipe', '| a | b |\n| --- | --- |\n| `a|b` | c |'),
]:
    path = out / (label + '-input.md'); path.write_text(value)
    export(label, src=path, q='-', ok=False)
    assert not (out / (label + '.json')).exists()
utf8 = out / 'invalid-utf8.md'; utf8.write_bytes(b'\xff')
export('invalid-utf8', src=utf8, q='-', ok=False)
assert not (out / 'invalid-utf8.json').exists()
no_table = out / 'no-table.md'; no_table.write_text('# Notes\nNo tables\n')
r = invoke('no-table-list', ['list', no_table]); assert r['tables'] == []
export('source-destination', target=source, ok=False)
export('existing-destination', target=out / 'selected.json', ok=False)
assert json.loads((out / 'selected.json').read_text()) == expected
export('missing-directory', target=out / 'absent/result.json', ok=False)
assert not (out / 'absent').exists()
export('fresh-retry')
assert json.loads((out / 'fresh-retry.json').read_text()) == expected
assert {str(p): digest(p) for p in (source, query)} == before
(out / 'SUMMARY.json').write_text(json.dumps({'passed': True,'cli_calls':len(calls),'source_inputs_unchanged':before,'formats':['csv','json','xlsx'],'selected_lines':[17,15]}, indent=2) + '\n')
print(json.dumps({'passed':True,'cli_calls':len(calls)}))
