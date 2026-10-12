#!/usr/bin/env python3
"""Actual CLI + independent ZIP/XML verification. Never overwrite evidence."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET

build, out = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=False)
source = Path(__file__).resolve().parents[1] / 'kit/pptx-edit/source.pptx'
cli = build / 'js/debug/build/cmd/pptx-edit/pptx-edit.js'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
XML = 'http://www.w3.org/XML/1998/namespace'
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def parts(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        return {name:z.read(name) for name in z.namelist()}
def package(path, entries):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_STORED) as z:
        for name, data in entries.items(): z.writestr(name, data)
calls=[]
def run(label, *args, ok=True):
    args=list(map(str,args))
    p=subprocess.run(['node',str(cli),*args],capture_output=True)
    (out/(label+'.stdout')).write_bytes(p.stdout)
    (out/(label+'.stderr')).write_bytes(p.stderr)
    calls.append({'label':label,'argv':args,'exit':p.returncode,'expected_success':ok})
    assert (p.returncode==0)==ok,(label,p.stdout,p.stderr)
    if not ok:
        assert not p.stdout,(label,'unexpected success report')
        return None
    return json.loads(p.stdout)
def resolve(root, id):
    for segment in id.split('/')[1:]:
        name, ordinal=segment.split(':')
        root=list(root)[int(ordinal)-1]
        assert root.tag.rsplit('}',1)[-1]==name
    return root
original=digest(source); entries=parts(source)
listing=run('inspect','inspect',source)
assert listing['schema']=='moonleaf.pptx-text-targets.v1'
assert listing['source_sha256']==original
assert listing['warnings'] and 'diagnostics' in listing
found=listing['targets']
assert len(found)==8 and len({t['id'] for t in found})==8
assert [t['text'] for t in found]==['Client review 2','Acme','Acme','Acme','Client review 1','Acme','Acme','Acme']
assert found[0]['part']=='ppt/slides/slide2.xml' and found[0]['hidden_slide']
assert found[4]['part']=='ppt/slides/slide1.xml' and not found[4]['hidden_slide']
selected=found[3]; assert '/grpSp:' in selected['id']
for target in found:
    assert resolve(ET.fromstring(entries[target['part']]),target['id']).text==target['text']
request={'version':1,'source_sha256':original,'target':selected['id'],'expected':'Acme','replacement':'  Client B & <雪😀>\r\n\t '}
def apply(label, req, input=source, ok=True, dest=None):
    path=out/(label+'.json'); path.write_text(json.dumps(req,ensure_ascii=True))
    dest=dest or out/(label+'.pptx')
    result=run(label,'apply',input,path,dest,ok=ok)
    if not ok and not dest.exists(): pass
    return result,dest
report,output=apply('apply',request)
assert report['reopened'] and report['readback_equal'] and report['changed']
assert report['source_sha256']==original and report['copy_sha256']==digest(output)
assert report['before']=='Acme' and report['after']==request['replacement']
assert report['warnings'] and 'diagnostics' in report
reopened=run('reinspect','inspect',output)
expected=copy.deepcopy(found); expected[3]['text']=request['replacement']
assert reopened['targets']==expected
edited=parts(output)
assert entries.keys()==edited.keys()
for name,data in entries.items():
    if name!=selected['part']: assert edited[name]==data,name
expected_xml=ET.fromstring(entries[selected['part']]); node=resolve(expected_xml,selected['id'])
node.text=request['replacement']; node.set('{'+XML+'}space','preserve')
assert ET.tostring(expected_xml)==ET.tostring(ET.fromstring(edited[selected['part']]))
assert digest(source)==original
# Independent producer reopen verifies normal-shape formatting, repeated text,
# groups, table, notes and slide ordering in actual emitted PPTX.
producer={'fixture':'python-pptx 1.0.2','independent_reopen':'unavailable'}
try:
    import pptx
except ImportError:
    pass
else:
    p=pptx.Presentation(output)
    assert p.slides[0].shapes[0].text=='Client review 2'
    assert p.slides[0].shapes[1].text=='AcmeAcme'
    assert p.slides[0].shapes[1].text_frame.paragraphs[0].runs[0].font.bold
    assert p.slides[0].shapes[2].shapes[0].text==request['replacement']
    assert p.slides[0].shapes[3].table.cell(0,0).text=='Acme table'
    assert p.slides[0].notes_slide.notes_text_frame.text=='Acme speaker note'
    assert p.slides[1].shapes[2].shapes[0].text=='Acme'
    producer['independent_reopen']=pptx.__version__
# Targeted ordinary runs, empty-slot continuity, no-op package preservation.
for label,index,replacement in [('second-run',2,'Selected'),('noop',1,'Acme'),('erase',1,''),('limit',1,'x'*32768)]:
    req=dict(request,target=found[index]['id'],expected=found[index]['text'],replacement=replacement)
    result,dest=apply(label,req)
    targets=run(label+'-inspect','inspect',dest)['targets']
    expect=copy.deepcopy(found); expect[index]['text']=replacement
    assert targets==expect
    if label=='noop': assert not result['changed'] and parts(dest)==entries
    if label=='erase':
        fill=dict(req,source_sha256=digest(dest),expected='',replacement='Filled')
        _,filled=apply('fill-empty',fill,input=dest)
        assert run('filled-inspect','inspect',filled)['targets'][index]['text']=='Filled'
# Lexical preservation across comments, PI, quoted >, CDATA and sibling entity spellings.
lex=dict(entries)
part=selected['part']
text=lex[part].decode().replace('<p:cSld>', '<p:cSld><!-- <a:t>fake</a:t> --><?keep this?>',1)
# First run is selected deliberately; other duplicated runs remain untouched.
text=text.replace('<a:t>Acme</a:t>', '<a:t note="a > b"><![CDATA[Acme]]></a:t>',1)
lex[part]=text.encode(); lexical=out/'lexical-source.pptx'; package(lexical,lex)
listed=run('lexical-inspect','inspect',lexical)
target=listed['targets'][1]
req=dict(request,source_sha256=digest(lexical),target=target['id'])
_,dest=apply('lexical-apply',req,input=lexical)
new=parts(dest)[part]
before,after=lex[part].split(b'<a:t note="a > b"><![CDATA[Acme]]></a:t>')
assert new.startswith(before) and new.endswith(after)
# Refuse stale source, stale full text, bad target, invalid replacement, bad request.
for label,req in {
    'stale-hash':dict(request,source_sha256='0'*64),
    'stale-text':dict(request,expected='different'),
    'stale-noop':dict(request,expected='different',replacement='different'),
    'unknown-target':dict(request,target='slide:999/cSld:1/spTree:1'),
    'invalid-control':dict(request,replacement='\x00'),
    'invalid-surrogate':dict(request,replacement='\ud800'),
    'over-limit':dict(request,replacement='x'*32769),
    'wrong-version':dict(request,version=2),
    'extra-field':dict(request,extra=True),
    'missing-field':{k:v for k,v in request.items() if k!='expected'},
}.items():
    _,dest=apply(label,req,ok=False); assert not dest.exists()
output_digest=digest(output)
apply('existing-output',request,ok=False,dest=output)
assert digest(output)==output_digest
apply('source-output',request,ok=False,dest=source)
assert digest(source)==original
apply('changed-source',request,input=output,ok=False)
apply('missing-parent',request,ok=False,dest=out/'absent'/'copy.pptx')
apply('fresh-retry',request)
# Namespace refusal and unsupported field remains unlisted.
wrong=dict(entries); wrong[part]=wrong[part].replace(A.encode(),b'urn:other')
path=out/'wrong-namespace.pptx'; package(path,wrong)
run('wrong-namespace','inspect',path,ok=False)
run('usage',ok=False)
assert digest(source)==original
summary={'schema':'moonleaf.r296-cli-verification.v1','passed':True,'invocations':len(calls),'expected_refusals':sum(not c['expected_success'] for c in calls),'source_sha256':original,'producer':producer,'checks':['exact structural targets','duplicate text unchanged','grouped and ordinary runs','empty and no-op copies','slide order and hidden flag','ZIP CRC and all nonselected part payloads','independent XML and producer reopen','bold run/table/notes/image relationships retained','lexical preservation','source unchanged','fresh-output retry']}
(out/'calls.json').write_text(json.dumps(calls,indent=2)+'\n')
(out/'RESULT.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
