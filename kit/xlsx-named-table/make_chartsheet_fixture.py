"""Optional retained chartsheet variant generation with openpyxl 3.1.5."""
from pathlib import Path
import openpyxl
from openpyxl.chart import BarChart, Reference

folder = Path(__file__).resolve().parent
book = openpyxl.load_workbook(folder / 'orders.xlsx')
chart = BarChart()
chart.title = 'Order amounts'
chart.add_data(Reference(book['Sales Q4'], min_col=4, min_row=3, max_row=6), titles_from_data=True)
sheet = book.create_chartsheet('Cost chart')
sheet.add_chart(chart)
book.save(folder / 'orders-with-chartsheet.xlsx')
