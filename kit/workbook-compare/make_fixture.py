"""Recreate the retained, real-producer XLSX fixtures with XlsxWriter 3.2.9."""
from pathlib import Path
import hashlib, importlib.metadata, json
import xlsxwriter
from datetime import datetime

root = Path(__file__).resolve().parent
assert importlib.metadata.version('XlsxWriter') == '3.2.9'

def make(name, changed=False, style_only=False):
    wb = xlsxwriter.Workbook(root / name)
    wb.set_properties({'title': 'Synthetic client budget comparison', 'author': 'MoonLeaf fixture', 'created': datetime(2026, 10, 10)})
    # The copy intentionally reorders the two retained sheets.
    if changed:
        hidden = wb.add_worksheet('Hidden notes')
        budget = wb.add_worksheet('Budget & 雪')
    else:
        budget = wb.add_worksheet('Budget & 雪')
        hidden = wb.add_worksheet('Hidden notes')
    hidden.write_string('A1', 'Retained source note')
    if not changed:
        hidden.hide()
    wb.add_worksheet('New appendix' if changed else 'Old appendix')
    header = wb.add_format({'bold': True, 'bg_color': '#88CCFF' if style_only else '#CCCCCC'})
    for c, value in enumerate(['id','customer','amount','formula change','cache change','obsolete','active','added']):
        budget.write_string(0, c, value, header)
    budget.write_string('A2', '001')
    budget.write_string('B2', 'Client 雪😀 & <new>\nsecond line' if changed else 'Client Alpha')
    budget.write_number('C2', 12.5)
    budget.write_number('C3', 7.5)
    budget.write_formula('D2', '=C2*3' if changed else '=C2*2', None, 25)
    budget.write_formula('E2', '=SUM(C2:C3)', None, 21 if changed else 20)
    if not changed:
        budget.write_string('F2', 'Remove this note')
    budget.write_boolean('G2', changed)
    if changed:
        budget.write_string('H2', '=literal text, not a formula')
    budget.merge_range('A5:C5' if changed else 'A5:B5', 'Overview')
    # A shared-string index changes when new text is inserted, not the cell value.
    budget.write_string('A7', 'Unchanged tail')
    wb.close()

make('original.xlsx')
make('client-copy.xlsx', changed=True)
make('style-only.xlsx', style_only=True)
files = {name: hashlib.sha256((root/name).read_bytes()).hexdigest()
         for name in ['original.xlsx','client-copy.xlsx','style-only.xlsx']}
(root/'PROVENANCE.json').write_text(json.dumps({
    'producer':'XlsxWriter','version':'3.2.9','source':'make_fixture.py',
    'synthetic_business_content':True,
    'formula_caches':'Explicit fixture values supplied to write_formula; not recalculated or claimed fresh.',
    'sha256': files,
}, ensure_ascii=False, indent=2)+'\n')
