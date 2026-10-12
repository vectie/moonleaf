#!/usr/bin/env python3
"""Focused fixed-width journeys. Every fixture/output is retained; no cleanup."""
import csv, hashlib, io, json, pathlib, subprocess, sys, zipfile
import xml.etree.ElementTree as ET
source, target, evidence = map(pathlib.Path, sys.argv[1:])
evidence.mkdir()
cli = target / 'js/debug/build/cmd/fixed-width/fixed-width.js'
kit = source / 'kit/fixed-width'
input_path, schema = kit/'suppliers.txt', kit/'schema.json'
original = input_path.read_bytes()
sha = hashlib.sha256(original).hexdigest()
count = 0
def call(*args, ok=True):
    global count
    count += 1
    proc = subprocess.run(['node', str(cli), *map(str,args)], capture_output=True)
    (evidence/f'{count:02}-stdout.txt').write_bytes(proc.stdout)
    (evidence/f'{count:02}-stderr.txt').write_bytes(proc.stderr)
    assert (proc.returncode == 0) == ok, proc.stderr
    return json.loads(proc.stdout) if ok else None
listed=call('inspect',input_path,schema)
assert listed['source_lines']==[2,4,5] and listed['skipped_lines']==[1,3]
assert listed['source_sha256']==sha
expected=[{'id':'003','name':'=1+1','cost':'3.00'},{'id':'002','name':'Beta','cost':'9.00'}]
for fmt in ['json','csv','xlsx']:
    out=evidence/f'result.{fmt}'
    report=call('export',input_path,schema,sha,kit/'query.json',fmt,out)
    assert report['source_lines']==[5,4] and report['readback_equal']
    assert report['output_sha256']==hashlib.sha256(out.read_bytes()).hexdigest()
    assert report['schema_sha256']==hashlib.sha256(schema.read_bytes()).hexdigest()
    if fmt=='json': assert json.loads(out.read_text())==expected
    elif fmt=='csv': assert list(csv.DictReader(io.StringIO(out.read_text())))==expected
    else:
        with zipfile.ZipFile(out) as z:
            xml=ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
            ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
            assert not xml.findall('.//s:f',ns)
            cells=xml.findall('.//s:c',ns)
            assert all(c.attrib['t']=='inlineStr' for c in cells)
            assert [''.join(c.itertext()) for c in cells]==['id','name','cost','003','=1+1','3.00','002','Beta','9.00']
call('export',input_path,schema,sha,'-','json',evidence/'all.json')
assert len(json.loads((evidence/'all.json').read_text()))==3
call('export',input_path,schema,sha,'-','json',evidence/'all.json',ok=False)
call('export',input_path,schema,sha,'-','json',input_path,ok=False)
call('export',input_path,schema,'0'*64,'-','json',evidence/'changed.json',ok=False)
call('export',input_path,schema,sha,'-','json',evidence/'missing-dir/out.json',ok=False)
call('export',input_path,schema,sha,'-','json',evidence/'retry.json')
for name,data in [('short',b'HEADER\n001short\n'),('long',b'HEADER\n001Acme    12.500\n'),('tab',b'HEADER\n001Acme\t   12.50\n'),('utf8',b'HEADER\n001Caf\xc3\xa9    12.50\n'),('invalid-utf8',b'\xff'),('bare-cr',b'HEADER\n001Acme    12.50\r')]:
    p=evidence/(name+'.txt');p.write_bytes(data)
    call('inspect',p,schema,ok=False)
    assert p.read_bytes()==data
empty=evidence/'header-only.txt';empty.write_text('HEADER\n')
call('export',empty,schema,hashlib.sha256(empty.read_bytes()).hexdigest(),'-','json',evidence/'empty.json')
assert json.loads((evidence/'empty.json').read_text())==[]
crlf=evidence/'crlf.txt';crlf.write_bytes(original.replace(b'\n',b'\r\n'))
assert call('inspect',crlf,schema)['preview']==listed['preview']
assert input_path.read_bytes()==original
assert not (evidence/'changed.json').exists()
(evidence/'SUMMARY.json').write_text(json.dumps({'passed':True,'cli_calls':count,'source_unchanged':True,'independent_json_csv_xlsx':True},indent=2))
print(f'{count} CLI journeys passed')
