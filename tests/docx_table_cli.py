#!/usr/bin/env python3
"""Exercise the production Node CLI and independently inspect source/output XML.
Usage: docx_table_cli.py /absolute/build /fresh/evidence
Uses only Python standard library and Node; retained fixture is python-docx 1.2.0.
"""
import csv
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

build, out = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=False)
root = Path(__file__).resolve().parents[1]
cli = build/'js/debug/build/cmd/docx-table/docx-table.js'
kit = root/'kit/docx-table'
source = out/'suppliers 雪 # review.docx'
shutil.copyfile(kit/'suppliers.docx', source)
query = kit/'query.json'
calls = []

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def run(label, *args, ok=True):
    p = subprocess.run(['node', str(cli), *map(str,args)], capture_output=True)
    (out/f'{label}.stdout').write_bytes(p.stdout)
    (out/f'{label}.stderr').write_bytes(p.stderr)
    calls.append({'label':label,'argv':list(map(str,args)),'exit':p.returncode,'expected_success':ok})
    (out/'invocations.json').write_text(json.dumps(calls,indent=2)+'\n')
    assert (p.returncode == 0) == ok, (label,p.stdout,p.stderr)
    if not ok:
        assert not p.stdout, (label,'unexpected success report')
        return None
    return json.loads(p.stdout)

def selection(label, src=source, **changes):
    value={'version':1,'source_sha256':digest(src),'table':'body/table:2','header':'first_row'}
    value.update(changes)
    path=out/f'{label}.selection.json'; path.write_text(json.dumps(value,ensure_ascii=False)+'\n')
    return path

def failure(label, src=source, sel=None, q='-', fmt='json', target=None):
    target = target or out/f'{label}.json'
    run(label,'export',src,sel or selection(label,src),q,fmt,target,ok=False)
    return target

ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
with zipfile.ZipFile(source) as z:
    parts={n:z.read(n) for n in z.namelist()}
    assert z.testzip() is None
body=ET.fromstring(parts['word/document.xml']).find('w:body',ns)
tables=body.findall('w:tbl',ns)
assert len(tables)==2

def text(p):
    values=[]
    for child in p.iter():
        name=child.tag.rsplit('}',1)[-1]
        if name=='t': values.append(child.text or '')
        elif name=='tab': values.append('\t')
        elif name in ('br','cr'): values.append('\n')
    return ''.join(values)

rows=[['\n'.join(text(p) for p in c.findall('w:p',ns)) for c in r.findall('w:tc',ns)] for r in tables[1].findall('w:tr',ns)]
assert rows==[['id','supplier','amount','notes'],['001','雪😀 & Co','1200.50','Line 1\n\nLine 2\tend'],['002','Beta, "Labs"','900',''],['003','Gamma','1500','=1+1']]
before=digest(source)
inspected=run('inspect-producer','inspect',source)
assert inspected['source_sha256']==before
assert inspected['tables'][0]['refusal'] is not None
assert inspected['tables'][1]=={'id':'body/table:2','rows':4,'columns':4,'first_row':rows[0],'refusal':None}
sel=selection('valid')
assert json.loads(sel.read_text())==json.loads((kit/'selection.json').read_text())
expected=[rows[3],rows[1]]
for fmt in ('csv','json','xlsx'):
    target=out/f'selected.{fmt}'
    report=run('export-'+fmt,'export',source,sel,query,fmt,target)
    assert report['source_sha256']==before and report['output_sha256']==digest(target)
    assert report['readback_equal'] is True
    assert report['input_rows']==3 and report['matched_rows']==2 and report['output_rows']==2
    assert report['table_rows']==[4,2] and report['output_columns']==rows[0]
    assert report['selection']==json.loads(sel.read_text()) and report['query']==json.loads(query.read_text())
    assert len(report['warnings'])==4
    if fmt=='csv':
        assert list(csv.reader(io.StringIO(target.read_text())))==[rows[0]]+expected
    elif fmt=='json':
        assert json.loads(target.read_text())==[dict(zip(rows[0],r)) for r in expected]
    else:
        xns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        with zipfile.ZipFile(target) as z:
            assert z.testzip() is None
            sheet=ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
            actual=[]
            for row in sheet.findall('s:sheetData/s:row',xns):
                cells=row.findall('s:c',xns)
                assert all(c.attrib.get('t')=='inlineStr' and c.find('s:f',xns) is None for c in cells)
                actual.append([''.join(c.itertext()) for c in cells])
            assert actual==[rows[0]]+expected
all_json=out/'all.json'
report=run('export-no-query','export',source,sel,'-','json',all_json)
assert json.loads(all_json.read_text())==[dict(zip(rows[0],r)) for r in rows[1:]]
assert report['query'] is None and report['table_rows']==[2,3,4]
explicit=selection('explicit',header=['a','b','c','d'])
report=run('explicit-columns','export',source,explicit,'-','json',out/'explicit.json')
assert report['table_rows']==[1,2,3,4] and report['input_rows']==4
assert json.loads((out/'explicit.json').read_text())[0]==dict(zip(['a','b','c','d'],rows[0]))
# Source and pre-existing destinations must survive every refusal.
for label,target in [('same-source',source),('existing-output',all_json),('directory-output',out)]:
    failure(label,sel=sel,target=target)
hard=out/'hardlink.docx'; hard.hardlink_to(source)
link=out/'symlink.docx'; link.symlink_to(source)
dangling=out/'dangling.json'; dangling.symlink_to(out/'nonexistent.json')
for label,target in [('hardlink-output',hard),('symlink-output',link),('dangling-output',dangling)]: failure(label,sel=sel,target=target)
assert not (out/'nonexistent.json').exists()
for label,changes in [('stale-digest',{'source_sha256':'0'*64}),('unknown-table',{'table':'body/table:99'}),('merged-table',{'table':'body/table:1'}),('duplicate-header',{'header':['x','x','z','q']}),('wrong-width',{'header':['x']}),('bad-version',{'version':2}),('extra-field',{'extra':True})]:
    target=failure(label,sel=selection(label,**changes)); assert not target.exists()
bad_query=out/'bad-query.recipe.json'; bad_query.write_text('{"version":1}')
assert not failure('bad-query',sel=sel,q=bad_query).exists()
assert not failure('bad-format',sel=sel,fmt='pdf').exists()
missing=out/'missing-parent'/'result.json'; failure('failed-write',sel=sel,target=missing)
assert not missing.exists()
retry=run('fresh-retry','export',source,sel,'-','json',out/'retry.json')
assert retry['readback_equal'] and json.loads((out/'retry.json').read_text())==json.loads(all_json.read_text())
# Adversarial selected content and namespace/field context, with fresh digest.
def mutate(label, edit):
    dest=out/f'{label}.docx'
    xml=parts['word/document.xml'].decode()
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
        for n,b in parts.items(): z.writestr(n,edit(xml).encode() if n=='word/document.xml' else b)
    return dest
for label,edit in [
 ('nested-table',lambda s:s.replace('<w:t>001</w:t>','<w:t><w:tbl/></w:t>')),
 ('hidden-run',lambda s:s.replace('<w:t>001</w:t>','<w:rPr><w:vanish/></w:rPr><w:t>001</w:t>')),
 ('field-outside',lambda s:s.replace('<w:body>','<w:body><w:p><w:r><w:fldChar/></w:r></w:p>')),
 ('malformed-xml',lambda s:s.replace('</w:document>','')),
]:
    src=mutate(label,edit); target=failure(label,src=src); assert not target.exists()
# Corruption is refused by package opening rather than exporting a partial table.
bad=out/'not-zip.docx'; bad.write_bytes(b'not a zip')
run('not-zip','inspect',bad,ok=False)
oversized=out/'oversized.selection.json'; oversized.write_bytes(b' '*65537)
assert not failure('oversized-selection',sel=oversized).exists()
assert digest(source)==before and digest(hard)==before and digest(link)==before
assert json.loads(all_json.read_text())==[dict(zip(rows[0],r)) for r in rows[1:]]
result={'schema':'moonleaf.r279-cli-verification.v1','passed':True,'invocations':len(calls),'expected_refusals':sum(not c['expected_success'] for c in calls),'source_sha256':before,'independent_checks':['DOCX table XML and exact row content','CSV parser and quoted line breaks','JSON values and source row/query mapping','XLSX ZIP CRC, inlineStr literal types, no formulas, exact cells','source unchanged and fresh-output retry']}
(out/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
