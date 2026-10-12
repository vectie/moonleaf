#!/usr/bin/env python3
"""Real-producer PPTX intake through the actual Node CLI, independently verified.
Usage: python3 tests/pptx_table_cli.py /absolute/build /fresh/evidence
Only Python stdlib and Node are needed; uses the committed python-pptx fixture.
"""
import csv, hashlib, io, json, shutil, subprocess, sys, zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

build,out=map(Path,sys.argv[1:]); out.mkdir(parents=True,exist_ok=False)
root=Path(__file__).resolve().parents[1]; kit=root/'kit/pptx-table'
cli=build/'js/debug/build/cmd/pptx-table/pptx-table.js'
source=out/'suppliers 雪 # review.pptx';shutil.copyfile(kit/'suppliers.pptx',source)
query=kit/'query.json';calls=[]

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(label,*args,ok=True):
    p=subprocess.run(['node',str(cli),*map(str,args)],capture_output=True)
    (out/f'{label}.stdout').write_bytes(p.stdout);(out/f'{label}.stderr').write_bytes(p.stderr)
    calls.append({'label':label,'argv':list(map(str,args)),'exit':p.returncode,'expected_success':ok})
    (out/'invocations.json').write_text(json.dumps(calls,indent=2)+'\n')
    assert (p.returncode==0)==ok,(label,p.stdout,p.stderr)
    if not ok:
        assert not p.stdout,(label,'unexpected success report')
        return
    return json.loads(p.stdout)
def selection(label,src=source,**changes):
    value={'version':1,'source_sha256':digest(src),'table':'slide:1/table:2','header':'first_row'}
    value.update(changes);p=out/f'{label}.selection.json';p.write_text(json.dumps(value,ensure_ascii=False)+'\n');return p
def failure(label,src=source,sel=None,q='-',fmt='json',target=None):
    target=target or out/f'{label}.json'
    run(label,'export',src,sel or selection(label,src),q,fmt,target,ok=False)
    return target

ns={'a':'http://schemas.openxmlformats.org/drawingml/2006/main','p':'http://schemas.openxmlformats.org/presentationml/2006/main','r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
with zipfile.ZipFile(source) as z:
    assert z.testzip() is None
    parts={n:z.read(n) for n in z.namelist()}
rels={r.attrib['Id']:r.attrib['Target'] for r in ET.fromstring(parts['ppt/_rels/presentation.xml.rels'])}
order=[rels[s.attrib['{'+ns['r']+'}id']] for s in ET.fromstring(parts['ppt/presentation.xml']).find('p:sldIdLst',ns)]
assert order==['slides/slide2.xml','slides/slide1.xml']
slide=ET.fromstring(parts['ppt/slides/slide2.xml']);assert slide.attrib['show']=='0'
group=slide.find('p:cSld/p:spTree/p:grpSp',ns);table=group.find('.//a:tbl',ns)
def paragraph(p):
    return ''.join('\n' if x.tag=='{'+ns['a']+'}br' else (x.text or '') if x.tag=='{'+ns['a']+'}t' else '' for x in p.iter())
rows=[['\n'.join(paragraph(p) for p in c.findall('a:txBody/a:p',ns)) for c in r.findall('a:tc',ns)] for r in table.findall('a:tr',ns)]
assert rows==[['id','supplier','amount','notes'],['001','雪😀 & Co','1200.50','Line 1\n\nLine 2\nend'],['002','Beta, "Labs"','900',''],['003','Gamma','1500','=1+1']]
before=digest(source);inspection=run('inspect-producer','inspect',source)
assert inspection['source_sha256']==before
assert [t['id'] for t in inspection['tables']]==['slide:1/table:1','slide:1/table:2','slide:2/table:1']
assert inspection['tables'][0]['refusal'] and inspection['tables'][0]['first_row']==[]
assert inspection['tables'][1]=={'id':'slide:1/table:2','slide_number':1,'part':'ppt/slides/slide2.xml','shape_id':'4','hidden_slide':True,'rows':4,'columns':4,'first_row':rows[0],'refusal':None}
sel=selection('valid');assert json.loads(sel.read_text())==json.loads((kit/'selection.json').read_text())
expected=[rows[3],rows[1]]
for fmt in ('csv','json','xlsx'):
    target=out/f'selected.{fmt}';report=run('export-'+fmt,'export',source,sel,query,fmt,target)
    assert report['source_sha256']==before and report['output_sha256']==digest(target) and report['readback_equal'] is True
    assert (report['input_rows'],report['matched_rows'],report['output_rows'])==(3,2,2)
    assert report['table_rows']==[4,2] and report['output_columns']==rows[0]
    assert (report['slide_number'],report['slide_part'],report['shape_id'],report['hidden_slide'])==(1,'ppt/slides/slide2.xml','4',True)
    assert report['selection']==json.loads(sel.read_text()) and report['query']==json.loads(query.read_text())
    assert len(report['warnings'])==4 and target.stat().st_mode & 0o777 == 0o600
    if fmt=='csv':assert list(csv.reader(io.StringIO(target.read_text())))==[rows[0]]+expected
    elif fmt=='json':assert json.loads(target.read_text())==[dict(zip(rows[0],r)) for r in expected]
    else:
        xns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        with zipfile.ZipFile(target) as z:
            assert z.testzip() is None
            actual=[]
            for r in ET.fromstring(z.read('xl/worksheets/sheet1.xml')).findall('s:sheetData/s:row',xns):
                cells=r.findall('s:c',xns);assert all(c.attrib.get('t')=='inlineStr' and c.find('s:f',xns) is None for c in cells)
                actual.append([''.join(c.itertext()) for c in cells])
            assert actual==[rows[0]]+expected
all_json=out/'all.json';report=run('export-no-query','export',source,sel,'-','json',all_json)
assert json.loads(all_json.read_text())==[dict(zip(rows[0],r)) for r in rows[1:]] and report['table_rows']==[2,3,4] and report['query'] is None
report=run('explicit-columns','export',source,selection('explicit',header=['a','b','c','d']),'-','json',out/'explicit.json')
assert report['table_rows']==[1,2,3,4] and report['input_rows']==4
assert json.loads((out/'explicit.json').read_text())[0]==dict(zip(['a','b','c','d'],rows[0]))
report=run('header-only','export',source,selection('empty',table='slide:2/table:1'),'-','json',out/'empty.json')
assert report['output_rows']==0 and report['output_columns']==['Code','Description'] and report['table_rows']==[]
assert json.loads((out/'empty.json').read_text())==[]
for label,target in [('same-source',source),('existing-output',all_json),('directory-output',out)]:failure(label,sel=sel,target=target)
hard=out/'hardlink.pptx';hard.hardlink_to(source);link=out/'symlink.pptx';link.symlink_to(source)
dangling=out/'dangling.json';dangling.symlink_to(out/'nonexistent.json')
for label,target in [('hardlink-output',hard),('symlink-output',link),('dangling-output',dangling)]:failure(label,sel=sel,target=target)
assert not (out/'nonexistent.json').exists()
for label,changes in [('stale-digest',{'source_sha256':'0'*64}),('unknown-table',{'table':'slide:01/table:2'}),('merged-table',{'table':'slide:1/table:1'}),('duplicate-header',{'header':['x','x','z','q']}),('wrong-width',{'header':['x']}),('bad-version',{'version':2}),('extra-field',{'extra':True})]:
    assert not failure(label,sel=selection(label,**changes)).exists()
bad_query=out/'bad-query.recipe.json';bad_query.write_text('{"version":1}')
assert not failure('bad-query',sel=sel,q=bad_query).exists()
assert not failure('bad-format',sel=sel,fmt='pdf').exists()
missing=out/'missing-parent'/'result.json';failure('failed-write',sel=sel,target=missing);assert not missing.exists()
retry=run('fresh-retry','export',source,sel,'-','json',out/'retry.json');assert retry['readback_equal']
assert json.loads((out/'retry.json').read_text())==json.loads(all_json.read_text())
def mutate(label,edit,part='ppt/slides/slide2.xml'):
    dest=out/f'{label}.pptx'
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
        for n,b in parts.items():z.writestr(n,edit(b.decode()).encode() if n==part else b)
    return dest
for label,edit in [
    ('field-in-table',lambda s:s.replace('<a:t>001</a:t>','<a:fld><a:t>001</a:t></a:fld>')),
    ('hyperlink-in-table',lambda s:s.replace('<a:t>001</a:t>','<a:rPr><a:hlinkClick/></a:rPr><a:t>001</a:t>')),
    ('unknown-cell-content',lambda s:s.replace('<a:t>001</a:t>','<a:t>001</a:t><unknown/>')),
    ('malformed-xml',lambda s:s.replace('</p:sld>','')),
    ('rebound-namespace',lambda s:s.replace('<a:tbl>','<a:tbl xmlns:a="wrong">')),
]:
    assert not failure(label,src=mutate(label,edit)).exists()
external=mutate('external-slide',lambda s:s.replace('Target="slides/slide2.xml"','Target="https://example.invalid/slide.xml" TargetMode="External"'),'ppt/_rels/presentation.xml.rels')
run('external-slide','inspect',external,ok=False)
# An unrelated chart frame is not a table; notes need no parse/fetch for table intake.
chart=mutate('unrelated-chart',lambda s:s.replace('</p:spTree>','<p:graphicFrame><a:graphic><a:graphicData uri="chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"/></a:graphicData></a:graphic></p:graphicFrame></p:spTree>'))
assert run('unrelated-chart','inspect',chart)['tables']==inspection['tables']
notes=mutate('unread-notes',lambda s:'<invalid notes XML','ppt/notesSlides/notesSlide1.xml')
assert run('unread-notes','inspect',notes)['tables']==inspection['tables']
bad=out/'not-zip.pptx';bad.write_bytes(b'not zip');run('not-zip','inspect',bad,ok=False)
oversized=out/'oversized.selection.json';oversized.write_bytes(b' '*65537)
assert not failure('oversized-selection',sel=oversized).exists()
assert digest(source)==before and digest(hard)==before and digest(link)==before
assert json.loads(all_json.read_text())==[dict(zip(rows[0],r)) for r in rows[1:]]
result={'schema':'moonleaf.r371-cli-verification.v1','passed':True,'invocations':len(calls),'expected_refusals':sum(not c['expected_success'] for c in calls),'source_sha256':before,'independent_checks':['producer slide relationship order and grouped-table XML','CSV exact text and line breaks','JSON query and physical-row provenance','XLSX ZIP CRC, literal inlineStr types, absence of formulas, exact cells','hidden slide, header-only, unrelated chart/notes','unchanged source and exclusive-output refusal/retry']}
(out/'summary.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
