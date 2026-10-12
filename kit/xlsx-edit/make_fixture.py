"""Regenerate with XlsxWriter 3.2.9; final tests consume the retained bytes."""
import datetime, hashlib, json
from pathlib import Path
import xlsxwriter
assert xlsxwriter.__version__ == '3.2.9'
p = Path(__file__).parent
w = xlsxwriter.Workbook(p / 'contacts.xlsx')
w.set_properties({'created': datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)})
style = w.add_format({'bold': True, 'font_color': '#164B35', 'bg_color': '#E8F3EE', 'text_wrap': True})
rich = w.add_format({'italic': True})
s = w.add_worksheet('Customers')
s.write_row(0, 0, ['ID', 'Name', 'Amount', 'Calculation', 'Notes'])
s.write_string('A2', '001'); s.write_string('B2', 'Ada', style); s.write_number('C2', 12.50)
s.write_formula('D2', '=C2*2', None, 25); s.write_string('E2', 'Call Monday')
s.write_string('A3', '002'); s.write_string('B3', 'Bo', style); s.write_number('C3', 7.50)
s.write_formula('D3', '=SUM(C2:C3)', None, 20); s.write_string('E3', 'Call Monday')
s.write_rich_string('B5', 'Rich ', rich, 'name')
s.merge_range('A7:B7', 'Merged banner', style)
s.write_array_formula('F2:G2', '=TRANSPOSE(A2:A3)', None, 0)
s.set_column('A:A', 12); s.set_column('B:B', 24); s.set_column('E:E', 25)
s.autofilter('A1:E3')
t = w.add_worksheet('Private notes'); t.write_string('A1', 'Private draft'); t.hide()
w.close()
digest = hashlib.sha256((p/'contacts.xlsx').read_bytes()).hexdigest()
edits = [
 {'sheet':'Customers','address':'B2','expected':'Ada','replacement':'Ada Lovelace'},
 {'sheet':'Customers','address':'B3','expected':'Bo','replacement':'Bo 李'},
 {'sheet':'Customers','address':'E2','expected':'Call Monday','replacement':'=SUM(1,2)'},
 {'sheet':'Private notes','address':'A1','expected':'Private draft','replacement':'Ready for review'},
]
(p/'corrections.json').write_text(json.dumps({'version':1,'source_sha256':digest,'edits':edits},ensure_ascii=False,indent=2)+'\n')
(p/'PROVENANCE.json').write_text(json.dumps({'producer':'XlsxWriter','version':xlsxwriter.__version__,'fixture_sha256':digest,'created':'2026-01-01T00:00:00Z','formula_caches':'explicit synthetic values, not calculation evidence'},indent=2)+'\n')
