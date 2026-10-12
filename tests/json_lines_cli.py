#!/usr/bin/env python3
"""Focused actual Node CLI checks with independent CSV, JSON and XLSX readers.
Usage: python3 tests/json_lines_cli.py /absolute/build /fresh/evidence
"""
import copy, csv, hashlib, io, json, subprocess, sys, zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

build, out = map(Path, sys.argv[1:])
assert build.is_absolute() and out.is_absolute()
out.mkdir(parents=True, exist_ok=False)
root = Path(__file__).resolve().parents[1]
kit = root / 'kit/json-lines'
cli = build / 'js/debug/build/cmd/json-lines/json-lines.js'
source, mapping, query = [kit / (name + '.json') for name in ('orders', 'mapping', 'query')]
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
before = {str(p): digest(p) for p in (source, mapping, query)}
calls = []

def run(label, src=source, spec=mapping, q=query, fmt='json', target=None, ok=True):
    target = target or out / (label + '.' + fmt)
    args = [str(src), str(spec), str(q), fmt, str(target)]
    p = subprocess.run(['node', str(cli), *args], capture_output=True)
    (out / (label + '.stdout')).write_bytes(p.stdout)
    (out / (label + '.stderr')).write_bytes(p.stderr)
    calls.append({'label': label, 'argv': args, 'exit': p.returncode, 'expected_success': ok})
    (out / 'invocations.json').write_text(json.dumps(calls, indent=2) + '\n')
    assert (p.returncode == 0) == ok, (label, p.stdout, p.stderr)
    if not ok:
        assert not p.stdout, label
        return None
    r = json.loads(p.stdout)
    assert r['readback_equal'] is True and r['source_sha256'] == digest(src)
    assert r['mapping_sha256'] == digest(spec) and r['output_sha256'] == digest(target)
    assert r['mapping'] == json.loads(spec.read_text())
    assert r['query'] == (None if str(q) == '-' else json.loads(Path(q).read_text()))
    assert target.stat().st_mode & 0o777 == 0o600
    return r

expected = [
    {'order': '003', 'customer': 'Gamma', 'sku': '0003', 'qty': 5, 'active': True, 'note': '=1+1'},
    {'order': '003', 'customer': 'Gamma', 'sku': '0003', 'qty': 5, 'active': True},
    {'order': '001', 'customer': '雪😀 & Co', 'sku': '0002', 'qty': 3, 'active': False, 'note': 'a,"b"\nnext'},
]
columns = ['order', 'customer', 'sku', 'qty', 'active', 'note']
text = lambda v: 'true' if v is True else 'false' if v is False else str(v)
expected_text = [[text(row.get(k, '')) for k in columns] for row in expected]
for fmt in ('csv', 'json', 'xlsx'):
    path = out / ('selected.' + fmt)
    report = run('selected-' + fmt, fmt=fmt, target=path)
    assert (report['parent_count'], report['expanded_rows'], report['matched_rows'], report['output_rows']) == (3, 4, 3, 3)
    assert report['empty_parent_rows'] == [2] and report['output_columns'] == columns
    assert report['source_rows'] == [{'parent_row': 3, 'item_row': 1}, {'parent_row': 3, 'item_row': 2}, {'parent_row': 1, 'item_row': 2}]
    if fmt == 'csv':
        assert list(csv.reader(io.StringIO(path.read_text()))) == [columns] + expected_text
    elif fmt == 'json':
        assert json.loads(path.read_text()) == expected
    else:
        ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        with zipfile.ZipFile(path) as z:
            assert z.testzip() is None
            sheet = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
            assert not sheet.findall('.//s:f', ns)
            actual = []
            for row in sheet.findall('s:sheetData/s:row', ns):
                cells = row.findall('s:c', ns)
                values = [''] * len(columns)
                for cell in cells:
                    col = ord(cell.attrib['r'][0]) - ord('A')
                    if cell.attrib.get('t') == 'inlineStr':
                        value = ''.join(t.text or '' for t in cell.findall('.//s:t', ns))
                    elif cell.attrib.get('t') == 'b':
                        value = cell.find('s:v', ns).text == '1'
                    else:
                        node = cell.find('s:v', ns)
                        value = int(node.text) if node is not None else ''
                    values[col] = value
                actual.append(values)
            assert actual == [columns] + [[row.get(k, '') for k in columns] for row in expected]
            assert sheet.find("s:sheetData/s:row[@r='2']/s:c[@r='F2']", ns).attrib['t'] == 'inlineStr'

report = run('all-lines', q='-')
assert report['output_rows'] == 4 and report['source_rows'][0] == {'parent_row': 1, 'item_row': 1}
all_rows = json.loads((out / 'all-lines.json').read_text())
assert [(r['_parent_row'], r['_item_row']) for r in all_rows] == [(1, 1), (1, 2), (3, 1), (3, 2)]

base = json.loads(source.read_text())
for label, value in [('null-child', None), ('object-child', {}), ('scalar-child', [7])]:
    data = copy.deepcopy(base); data['orders'][2]['lines'] = value
    p = out / (label + '-input.json'); p.write_text(json.dumps(data))
    target = out / (label + '.json')
    run(label, src=p, target=target, ok=False)
    assert not target.exists()
# The second selected line fails even if its quantity would filter it out.
data = copy.deepcopy(base); data['orders'][0]['lines'][0]['sku'] = {}
p = out / 'filtered-invalid-input.json'; p.write_text(json.dumps(data))
run('filtered-invalid', src=p, ok=False); assert not (out / 'filtered-invalid.json').exists()

empty = out / 'empty-input.json'
empty.write_text(json.dumps({'orders': [{'id': 'e', 'customer': {'name': 'Empty'}, 'lines': []}]}))
report = run('empty', src=empty, q='-')
assert report['empty_parent_rows'] == [1] and report['output_rows'] == 0 and len(report['output_columns']) == 8
assert json.loads((out / 'empty.json').read_text()) == []

bad = out / 'bad-mapping.json'
value = json.loads(mapping.read_text()); value['item_fields'][0]['name'] = 'order'
bad.write_text(json.dumps(value)); run('duplicate-name', spec=bad, ok=False)
assert not (out / 'duplicate-name.json').exists()
invalid_utf8 = out / 'invalid-utf8-input.json'; invalid_utf8.write_bytes(b'\xff')
run('invalid-utf8', src=invalid_utf8, ok=False); assert not (out / 'invalid-utf8.json').exists()
run('source-destination', target=source, ok=False)
run('existing-destination', target=out / 'selected.json', ok=False)
assert json.loads((out / 'selected.json').read_text()) == expected
run('missing-directory', target=out / 'absent/result.json', ok=False)
assert not (out / 'absent').exists()
run('fresh-retry')
assert json.loads((out / 'fresh-retry.json').read_text()) == expected
assert {str(p): digest(p) for p in (source, mapping, query)} == before
(out / 'SUMMARY.json').write_text(json.dumps({'passed': True, 'cli_calls': len(calls), 'source_inputs_unchanged': before, 'formats': ['csv', 'json', 'xlsx'], 'selected_locators': [[3, 1], [3, 2], [1, 2]], 'empty_parent_rows': [2]}, indent=2) + '\n')
print(json.dumps({'passed': True, 'cli_calls': len(calls)}))
