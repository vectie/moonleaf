#!/usr/bin/env python3
"""Real CLI integration verifier. Usage: script BUILD_DIR FRESH_EVIDENCE_DIR.
Build cmd/typed-import cmd/query cmd/xlsx-table with the pinned MoonBit compiler.
Uses Python stdlib and Node only. Never rewrites source fixtures.
"""
import csv, hashlib, io, json, pathlib, subprocess, sys, zipfile
import xml.etree.ElementTree as ET

build, out = map(lambda s: pathlib.Path(s).resolve(), sys.argv[1:])
root = pathlib.Path(__file__).resolve().parents[1]
fixture = root / 'kit/typed-import'
out.mkdir(parents=True, exist_ok=False)
commands = []

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

before = {p.name: digest(p) for p in fixture.iterdir() if p.is_file()}

def call(package, arguments, label, good=True):
    cmd = ['node', str(build / f'js/debug/build/cmd/{package}/{package}.js'), *map(str, arguments)]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    commands.append(dict(label=label,command=cmd,exit_code=result.returncode,stdout_bytes=len(result.stdout)))
    (out / f'{label}.stderr').write_bytes(result.stderr)
    if good:
        assert result.returncode == 0, (label, result.stderr.decode(errors='replace'))
    else:
        assert result.returncode != 0 and not result.stdout and result.stderr, (label,result)
    return result.stdout

source, schema = fixture/'source.csv', fixture/'schema.json'
expected = [
    {'id':'001','amount':12.5,'active':True,'note':'北, customer'},
    {'id':'002','active':False,'note':''},
    {'id':'1','amount':-20,'active':True,'note':'=1+1'},
    {'id':'004','amount':0},
    {'id':'005','amount':3.25,'active':True,'note':'line one\nline "two"'},
]
for fmt in ['json','csv','xlsx']:
    data = call('typed-import', ['csv',source,schema,fmt], 'export-'+fmt)
    (out/f'typed.{fmt}').write_bytes(data)
assert json.loads((out/'typed.json').read_text()) == expected
assert json.loads(call('typed-import',['tsv',fixture/'source.tsv',schema,'json'],'tsv-json')) == expected
rows = list(csv.reader(io.StringIO((out/'typed.csv').read_text())))
assert rows == [
    ['id','amount','active','note'],
    ['001','12.50','true','北, customer'], ['002','','false',''],
    ['1','-2e1','true','=1+1'], ['004','0','',''], ['005','3.25','true','line one\nline "two"'],
]
(out/'csv-reopened.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
# Independent ZIP/XML examination, plus actual production XLSX import.
with zipfile.ZipFile(out/'typed.xlsx') as z:
    assert z.testzip() is None
    xml = z.read('xl/worksheets/sheet1.xml')
    (out/'worksheet.xml').write_bytes(xml)
    ns={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    doc=ET.fromstring(xml)
    cells={c.attrib['r']:c for c in doc.findall('.//m:c',ns)}
    assert cells['A2'].attrib['t']=='inlineStr'
    assert cells['A2'].find('m:is/m:t',ns).text=='001'
    assert cells['C2'].attrib['t']=='b' and cells['C2'].find('m:v',ns).text=='1'
    assert cells['D4'].attrib['t']=='inlineStr' and cells['D4'].find('m:is/m:t',ns).text=='=1+1'
    assert not doc.findall('.//m:f',ns)
reopened=call('xlsx-table',[out/'typed.xlsx',fixture/'selection.json','-','json'],'xlsx-reopened')
(out/'xlsx-reopened.json').write_bytes(reopened)
assert json.loads(reopened)==expected
selected=call('query',['json',out/'typed.json',fixture/'query.json','json'],'boolean-query')
(out/'selected.json').write_bytes(selected)
assert json.loads(selected)==[{'id':'001','amount':12.5},{'id':'005','amount':3.25},{'id':'1','amount':-20}]
# A changed recipe produces a changed useful result without input edits.
changed=json.loads(schema.read_text()); changed['columns'][0]['trim']=True
changed['columns'][2]['kind']={'type':'boolean','true':'NO','false':'YES'}
changed_path=out/'changed-schema.json'; changed_path.write_text(json.dumps(changed))
changed_data=call('typed-import',['csv',source,changed_path,'json'],'changed-schema')
(out/'changed.json').write_bytes(changed_data)
assert json.loads(changed_data)[0]['active'] is False
assert json.loads(changed_data)[1]['active'] is True
# Real failed invocations, retaining each diagnostic. Late row failures are atomic.
invalid=out/'invalid.csv'
for label, value in [('late-number','oops'),('leading-zero','012'),('nonfinite','1e999'),('currency','$5'),('numeric-null','null')]:
    invalid.write_text('Customer ID,Enabled,Gross amount,Memo\n001,YES,2,ok\n002,NO,'+value+',bad\n')
    call('typed-import',['csv',invalid,schema,'json'],label,False)
for label, value in [('late-boolean','maybe'),('boolean-case','yes'),('boolean-blank','')]:
    invalid.write_text('Customer ID,Enabled,Gross amount,Memo\n001,YES,2,ok\n002,'+value+',3,bad\n')
    call('typed-import',['csv',invalid,schema,'xlsx'],label,False)
for label, value in [('ragged','Customer ID,Enabled,Gross amount,Memo\n001,YES,2\n'),('duplicate-header','Customer ID,Enabled,Gross amount,Memo,Customer ID\n'),('missing-header','id,amount\n1,2\n'),('bad-quote','Customer ID,Enabled,Gross amount,Memo\n001,YES,2,"unterminated')]:
    invalid.write_text(value)
    call('typed-import',['csv',invalid,schema,'json'],label,False)
bad_schema=out/'invalid-schema.json'
for label, update in [
    ('unknown-schema-field',lambda v:v.update(extra=True)),
    ('duplicate-output',lambda v:v['columns'][1].update(name='id')),
    ('missing-column',lambda v:v['columns'][0].update(source='absent')),
    ('boolean-token-collision',lambda v:v['columns'][2]['kind'].update(false='YES')),
    ('null-token-collision',lambda v:v['columns'][2].update(nulls=['YES'])),
    ('unsupported-type',lambda v:v['columns'][1].update(kind={'type':'date'})),
]:
    v=json.loads(schema.read_text());update(v);bad_schema.write_text(json.dumps(v))
    call('typed-import',['csv',source,bad_schema,'json'],label,False)
invalid.write_bytes(b'\xff')
call('typed-import',['csv',invalid,schema,'json'],'invalid-utf8',False)
for label,args in [
    ('missing-file',['csv',out/'missing.csv',schema,'json']),
    ('directory',['csv',out,schema,'json']),
    ('stdin',['csv','-',schema,'json']),
    ('format',['json',source,schema,'json']),
    ('output-format',['csv',source,schema,'tsv']),
    ('argument-count',[]),
]:call('typed-import',args,label,False)
# Sparse fixture exceeds byte limit without material resident data.
with invalid.open('wb') as f:f.truncate(8388609)
call('typed-import',['csv',invalid,schema,'json'],'file-limit',False)
invalid.write_text('v\n'+'x'*2097152)
call('typed-import',['csv',invalid,schema,'json'],'parser-limit',False)
bad_schema.write_text(' '*65537)
call('typed-import',['csv',source,bad_schema,'json'],'schema-limit',False)
# XML boundary regression: use an independent XML parser, not only MoonLeaf.
xml_dir=out/'xml-boundaries';xml_dir.mkdir()
xml_schema=xml_dir/'schema.json'
xml_schema.write_text(json.dumps({'version':1,'columns':[{'source':'v','name':'value','kind':{'type':'text'},'trim':False,'nulls':[]}]}))
xml_selection=xml_dir/'selection.json'
xml_selection.write_text(json.dumps({'sheet':'JSON data','range':'A1:A2','header':'first_row'}))
xml_results=[]
valid_xml_values=[('crlf','before\r\nafter'),('cr','before\rafter'),('lf','before\nafter'),('tab','before\tafter'),('literal-reference','literal &#13; and <&>'),('unicode-edges','\x20\ud7ff\ue000\ufffd\U00010000\U0010ffff')]
for label,value in valid_xml_values:
    path=xml_dir/(label+'.csv')
    with path.open('w',newline='') as f:csv.writer(f).writerows([['v'],[value]])
    data=call('typed-import',['csv',path,xml_schema,'xlsx'],'xml-'+label)
    xlsx=xml_dir/(label+'.xlsx');xlsx.write_bytes(data)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        assert z.testzip() is None
        for entry in z.namelist():
            if entry.endswith('.xml') or entry.endswith('.rels'):ET.fromstring(z.read(entry))
        sheet=ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
        actual=sheet.find('.//m:c[@r="A2"]/m:is/m:t',ns).text
        assert actual==value,(label,repr(actual),repr(value))
    reimport=call('xlsx-table',[xlsx,xml_selection,'-','json'],'xml-reimport-'+label)
    assert json.loads(reimport)==[{'value':value}]
    xml_results.append({'label':label,'expected':value,'independent_xml_value':actual,'production_reimport_matches':True})
for point in [p for p in range(32) if p not in (9,10,13)]+[0xfffe,0xffff]:
    label='forbidden-u%04x'%point;value='before'+chr(point)+'after'
    path=xml_dir/(label+'.csv')
    with path.open('w',newline='') as f:csv.writer(f).writerows([['v'],[value]])
    # Input is legitimate CSV/JSON data; only unsupported XML output is refused.
    data=call('typed-import',['csv',path,xml_schema,'json'],label+'-json')
    assert json.loads(data)==[{'value':value}]
    call('typed-import',['csv',path,xml_schema,'xlsx'],label+'-xlsx',False)
    xml_results.append({'label':label,'json_preserved':True,'xlsx_refused_without_stdout':True})
# Output column names are XML text too.
invalid_header=json.loads(xml_schema.read_text());invalid_header['columns'][0]['name']='bad\x01header'
header_path=xml_dir/'invalid-header-schema.json';header_path.write_text(json.dumps(invalid_header))
call('typed-import',['csv',xml_dir/'cr.csv',header_path,'xlsx'],'forbidden-header-xlsx',False)
(xml_dir/'results.json').write_text(json.dumps(xml_results,ensure_ascii=True,indent=2)+'\n')
retry=call('typed-import',['csv',source,schema,'json'],'valid-retry')
assert retry==(out/'typed.json').read_bytes()
assert before=={p.name:digest(p) for p in fixture.iterdir() if p.is_file()}
(out/'input-sha256.json').write_text(json.dumps(before,indent=2)+'\n')
(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
result=dict(status='passed',invocations=len(commands),negative_cases=sum(c['exit_code']!=0 for c in commands),input_hashes_unchanged=True,rows=len(expected),selected_rows=3)
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
