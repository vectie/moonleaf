"""Product CLI tests; Python stdlib independently reads JSON, CSV and XLSX XML.

Build cmd/xml_records, cmd/summarize and cmd/preview for JS first, then:
MOONLEAF_BUILD_ROOT=/absolute/external-build python3 tests/xml_records_cli_test.py
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
FIXTURES = ROOT / "docs/samples/xml-records"
CLI = BUILD / "js/debug/build/cmd/xml_records/xml_records.js"
SUMMARY = BUILD / "js/debug/build/cmd/summarize/summarize.js"
PREVIEW = BUILD / "js/debug/build/cmd/preview/preview.js"
NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def intake(data, output="json", mapping=None):
    return subprocess.run(
        ["node", str(CLI), str(mapping or FIXTURES / "catalog.mapping.json"), output],
        input=data, capture_output=True, check=False,
    )


class XmlRecordsCLI(unittest.TestCase):
    def test_actual_catalog_exports_and_existing_summary_operator(self):
        data = (FIXTURES / "supplier-catalog.xml").read_bytes()
        result = intake(data)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        records = json.loads(result.stdout)
        self.assertEqual(records[0]["sku"], "001")
        self.assertEqual(records[0]["price"], "12.50")
        self.assertEqual(records[0]["name"], "東京 Green Tea 🍵")
        self.assertEqual(records[0]["barcode"], "")
        self.assertNotIn("barcode", records[1])
        self.assertNotIn("tags", records[2])
        self.assertEqual(records[2]["name"], "Glass <small>")
        csv_result = intake(data, "csv")
        self.assertEqual(csv_result.returncode, 0, csv_result.stderr.decode())
        rows = list(csv.DictReader(io.StringIO(csv_result.stdout.decode())))
        self.assertEqual(rows[0]["sku"], "001")
        self.assertEqual(rows[0]["tags"], "tea | gift & pantry")
        self.assertEqual(rows[0]["barcode"], "")
        self.assertEqual(rows[1]["barcode"], "")
        summary = subprocess.run(
            ["node", str(SUMMARY), "json", str(FIXTURES / "supplier-summary.json"), "json"],
            input=result.stdout, capture_output=True, check=False,
        )
        self.assertEqual(summary.returncode, 0, summary.stderr.decode())
        self.assertEqual(json.loads(summary.stdout), [
            {"supplier": "N01", "products": 2, "units_available": 34},
            {"supplier": "N02", "products": 1, "units_available": 6},
        ])
        xlsx = intake(data, "xlsx")
        self.assertEqual(xlsx.returncode, 0, xlsx.stderr.decode())
        with zipfile.ZipFile(io.BytesIO(xlsx.stdout)) as archive:
            self.assertIsNone(archive.testzip())
            sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
            cells = {cell.attrib["r"]: cell for cell in sheet.findall(".//s:c", NS)}
            self.assertEqual(cells["A2"].attrib["t"], "inlineStr")
            self.assertEqual(cells["A2"].find("s:is/s:t", NS).text, "001")
            self.assertEqual(cells["D2"].find("s:is/s:t", NS).text, "12.50")
            self.assertEqual(cells["C2"].find("s:is/s:t", NS).text, "東京 Green Tea 🍵")
            self.assertEqual(cells["G3"].attrib.get("t") if "G3" in cells else None, None)
            self.assertEqual(cells["G2"].attrib["t"], "inlineStr")
            self.assertIsNone(cells["G2"].find("s:is/s:t", NS).text)
            self.assertEqual(sheet.findall(".//s:f", NS), [])
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "catalog.xlsx"
            output.write_bytes(xlsx.stdout)
            reopened = subprocess.run(
                ["node", str(PREVIEW), str(output), "catalog.xlsx"],
                capture_output=True, check=False,
            )
            self.assertEqual(reopened.returncode, 0, reopened.stderr.decode())
            self.assertEqual(json.loads(reopened.stdout)["sheets"][0]["rows"][1][0], "001")
        self.assertEqual((FIXTURES / "supplier-catalog.xml").read_bytes(), data)

    def test_orders_fixture(self):
        result = intake((FIXTURES / "orders.xml").read_bytes(), mapping=FIXTURES / "orders.mapping.json")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(json.loads(result.stdout), [
            {"order": "PO-104", "sku": "001", "quantity": "4"},
            {"order": "PO-105", "sku": "003", "quantity": "2"},
            {"order": "PO-106", "sku": "009", "quantity": "1"},
        ])

    def test_rejects_late_ambiguity_with_no_partial_stdout(self):
        data = b'<c:catalog xmlns:c="urn:moonleaf:catalog"><c:item sku="001"/><c:item><c:name>a</c:name><c:name>b</c:name></c:item></c:catalog>'
        for output in ("json", "csv", "xlsx"):
            result = intake(data, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"RepeatedXmlField", result.stderr)

    def test_rejects_bad_xml_utf8_limits_and_invalid_arguments(self):
        for data in (
            b"<catalog>", b"\xff<catalog/>", b" " * 4_000_001,
            b"<!DOCTYPE catalog SYSTEM 'https://example.invalid/data'><catalog/>",
            b"<!DOCTYPE catalog [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><catalog>&secret;</catalog>",
        ):
            result = intake(data)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
        for args in ([], [str(FIXTURES / "catalog.mapping.json"), "pdf"], [str(FIXTURES / "missing.json"), "json"]):
            result = subprocess.run(["node", str(CLI), *args], input=b"", capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")

    def test_bad_spec_has_no_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            mapping = Path(temporary) / "bad.json"
            mapping.write_text('{"record_path":["r"],"fields":[{"name":"x","path":[],"repeated":"first"}]}')
            result = intake(b"<r/>", mapping=mapping)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
