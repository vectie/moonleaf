"""Product integration tests for compiled unpivot, summary and preview CLIs.

MOONLEAF_BUILD_ROOT=/absolute/external-build python3 tests/unpivot_cli_test.py
"""
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = Path(os.environ.get("MOONLEAF_BUILD_ROOT", ROOT / "_build"))
FIXTURES = ROOT / "docs/samples/unpivot"
CLI = BUILD / "js/debug/build/cmd/unpivot/unpivot.js"
SUMMARY = BUILD / "js/debug/build/cmd/summarize/summarize.js"
PREVIEW = BUILD / "js/debug/build/cmd/preview/preview.js"
NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def reshape(data, input_format="csv", output="json", spec=None):
    return subprocess.run(
        ["node", str(CLI), input_format, str(spec or FIXTURES / "tidy-sales.json"), output],
        input=data, capture_output=True, check=False,
    )


class UnpivotCLI(unittest.TestCase):
    def test_sales_export_summary_and_xlsx_reopen(self):
        data = (FIXTURES / "monthly-sales.csv").read_bytes()
        result = reshape(data)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        rows = json.loads(result.stdout)
        self.assertEqual(len(rows), 7)
        self.assertEqual(rows[0], {"store": "001", "region": "North", "month": "Jan", "sales": "100"})
        self.assertEqual(rows[2]["sales"], "0")
        self.assertEqual(rows[-1]["sales"], "-10")
        csv_result = reshape(data, output="csv")
        self.assertEqual(csv_result.returncode, 0, csv_result.stderr.decode())
        self.assertEqual(list(csv.DictReader(io.StringIO(csv_result.stdout.decode()))), rows)
        summary = subprocess.run(
            ["node", str(SUMMARY), "json", str(FIXTURES / "monthly-totals.json"), "json"],
            input=result.stdout, capture_output=True, check=False,
        )
        self.assertEqual(summary.returncode, 0, summary.stderr.decode())
        self.assertEqual(json.loads(summary.stdout), [
            {"month": "Jan", "reported_stores": 3, "total": 150},
            {"month": "Feb", "reported_stores": 2, "total": 195},
            {"month": "Mar", "reported_stores": 2, "total": 70},
        ])
        xlsx = reshape(data, output="xlsx")
        self.assertEqual(xlsx.returncode, 0, xlsx.stderr.decode())
        with zipfile.ZipFile(io.BytesIO(xlsx.stdout)) as archive:
            self.assertIsNone(archive.testzip())
            sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
            cells = {cell.attrib["r"]: cell for cell in sheet.findall(".//s:c", NS)}
            self.assertEqual(cells["A2"].attrib["t"], "inlineStr")
            self.assertEqual(cells["A2"].find("s:is/s:t", NS).text, "001")
            self.assertEqual(cells["C2"].find("s:is/s:t", NS).text, "Jan")
            self.assertEqual(cells["D8"].find("s:is/s:t", NS).text, "-10")
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "tidy.xlsx"
            output.write_bytes(xlsx.stdout)
            reopened = subprocess.run(["node", str(PREVIEW), str(output), "tidy.xlsx"], capture_output=True, check=False)
            self.assertEqual(reopened.returncode, 0, reopened.stderr.decode())
            display = json.loads(reopened.stdout)["sheets"][0]["rows"]
            self.assertEqual(display[0], ["store", "region", "month", "sales"])
            self.assertEqual(display[1:], [[row[key] for key in display[0]] for row in rows])
        self.assertEqual((FIXTURES / "monthly-sales.csv").read_bytes(), data)

    def test_all_input_formats_and_typed_xlsx(self):
        spec = {"id_columns": ["id"], "value_columns": ["二月", "一月"], "drop_empty": True}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "spec.json"
            path.write_text(json.dumps(spec))
            items = [{"id": "001", "一月": 12.5, "二月": False}, {"id": "東京 🍵", "二月": 0}]
            for input_format, data in (
                ("json", json.dumps(items).encode()),
                ("jsonl", ("\n".join(json.dumps(item) for item in items) + "\n").encode()),
            ):
                result = reshape(data, input_format=input_format, spec=path)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertEqual(json.loads(result.stdout), [
                    {"id": "001", "variable": "二月", "value": False},
                    {"id": "001", "variable": "一月", "value": 12.5},
                    {"id": "東京 🍵", "variable": "二月", "value": 0},
                ])
                xlsx = reshape(data, input_format=input_format, output="xlsx", spec=path)
                self.assertEqual(xlsx.returncode, 0, xlsx.stderr.decode())
                with zipfile.ZipFile(io.BytesIO(xlsx.stdout)) as archive:
                    sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
                    cells = {cell.attrib["r"]: cell for cell in sheet.findall(".//s:c", NS)}
                    self.assertEqual(cells["C2"].attrib["t"], "b")
                    self.assertEqual(cells["C2"].find("s:v", NS).text, "0")
                    self.assertEqual(cells["C3"].find("s:v", NS).text, "12.5")
                    self.assertEqual(cells["A4"].find("s:is/s:t", NS).text, "東京 🍵")
            tsv = "id\t一月\t二月\r\n001\t12.5\t0\r\n".encode()
            result = reshape(tsv, input_format="tsv", spec=path)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(json.loads(result.stdout)[0]["value"], "0")

    def test_header_only_input_and_invalid_spec_have_no_partial_result(self):
        result = reshape(b"store,region,Jan,Feb,Mar\n", output="csv")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(list(csv.reader(io.StringIO(result.stdout.decode()))), [["store", "region", "month", "sales"]])
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "spec.json"
            path.write_text('{"id_columns":[],"value_columns":["missing"]}')
            for output in ("csv", "json", "xlsx"):
                result = reshape(b"a\n1\n", output=output, spec=path)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
                self.assertIn(b"UnknownUnpivotColumn", result.stderr)

    def test_malformed_source_utf8_and_usage(self):
        for data in (b"store,region,Jan,Feb,Mar\n001,North\n", b"\xff"):
            result = reshape(data)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
        result = subprocess.run(["node", str(CLI)], capture_output=True, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
