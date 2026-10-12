"""Optional fixture regeneration with XlsxWriter 3.2.9; tests use committed bytes."""
from pathlib import Path
from datetime import datetime
import xlsxwriter

p = Path(__file__).resolve().parent
book = xlsxwriter.Workbook(p / 'orders.xlsx', {'strings_to_formulas': False, 'strings_to_urls': False})
book.set_properties({'title': 'Synthetic quarterly orders', 'created': datetime(2026, 10, 1)})
sales = book.add_worksheet('Sales Q4')
sales.write('A1', 'Synthetic retained business example. Totals are not order records.')
sales.add_table('B3:F7', {
    'name': 'Orders', 'total_row': True,
    'columns': [{'header': 'id', 'total_string': 'Total'}, {'header': 'customer'},
                {'header': 'amount', 'total_function': 'sum'}, {'header': 'active'}, {'header': 'note'}],
    'data': [['001', 'Ada', 12.5, True, '=SUM(1,2)'],
             ['002', 'Bo', 8, False, ''], ['003', 'Chloé', 20, True, 'priority\nship']],
})
sales.set_row(5, None, None, {'hidden': True})
ops = book.add_worksheet('Ops')
ops.add_table('A1:B2', {'name': 'Regions', 'columns': [{'header': 'region'}, {'header': 'owner'}], 'data': [['East', 'Ada']]})
feed = book.add_worksheet('Hidden Feed')
feed.hide()
feed.add_table('B2:C3', {'name': 'Feed', 'header_row': False,
                       'columns': [{'header': 'id'}, {'header': 'amount'}], 'data': [['101', 3], ['102', 4]]})
book.close()
