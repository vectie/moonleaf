"""Product tests for the compiled pivot CLI and its exported/reopened copies.

MOONLEAF_BUILD_ROOT=/absolute/target python3 tests/pivot_cli_test.py
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
CLI = BUILD / "js/debug/build/cmd/pivot/pivot.js"
PREVIEW = BUILD / "js/debug/build/cmd/preview/preview.js"
FIXTURES = ROOT / "docs/samples/pivot"
NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def pivot(data, input_format="csv", output="json", spec=None):
    return subprocess.run(
        ["node", str(CLI), input_format, str(spec or FIXTURES / "wide-sales.json"), output],
        input=data, capture_output=True, check=False,
    )


class PivotCLI(unittest.TestCase):
    def test_comparison_csv_json_and_xlsx_reopen(self):
        data = (FIXTURES / "monthly-sales.csv").read_bytes()
        expected = [
            {"store": "002", "region": "West", "Feb": "75", "Jan": "0", "Mar": "80"},
            {"store": "001", "region": "North", "Jan": "100", "Mar": "120"},
            {"store": "003", "region": "North", "Feb": "", "Jan": "50"},
        ]
        result = pivot(data)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(json.loads(result.stdout), expected)
        csv_result = pivot(data, output="csv")
        self.assertEqual(csv_result.returncode, 0, csv_result.stderr.decode())
        rows = list(csv.reader(io.StringIO(csv_result.stdout.decode())))
        self.assertEqual(rows, [["store", "region", "Feb", "Jan", "Mar"],
                               ["002", "West", "75", "0", "80"],
                               ["001", "North", "", "100", "120"],
                               ["003", "North", "", "50", ""]])
        xlsx = pivot(data, output="xlsx")
        self.assertEqual(xlsx.returncode, 0, xlsx.stderr.decode())
        with zipfile.ZipFile(io.BytesIO(xlsx.stdout)) as archive:
            self.assertIsNone(archive.testzip())
            sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
            cells = {cell.attrib["r"]: cell for cell in sheet.findall(".//s:c", NS)}
            self.assertEqual(cells["A2"].attrib["t"], "inlineStr")
            self.assertEqual(cells["A2"].find("s:is/s:t", NS).text, "002")
            self.assertEqual(cells["D2"].find("s:is/s:t", NS).text, "0")
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "wide.xlsx"
            path.write_bytes(xlsx.stdout)
            reopened = subprocess.run(["node", str(PREVIEW), str(path), "wide.xlsx"], capture_output=True, check=False)
            self.assertEqual(reopened.returncode, 0, reopened.stderr.decode())
            self.assertEqual(json.loads(reopened.stdout)["sheets"][0]["rows"], rows)
        self.assertEqual((FIXTURES / "monthly-sales.csv").read_bytes(), data)

    def with_spec(self, spec, callback):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "spec.json"
            path.write_text(json.dumps(spec), encoding="utf-8")
            callback(path)

    def test_all_input_formats_and_scalar_values(self):
        spec = {"id_columns": ["id"], "key_column": "k", "value_column": "v"}
        def check(path):
            objects = [{"id": "001", "k": "東京 🍵", "v": 0},
                       {"id": "001", "k": "active", "v": False},
                       {"id": "002", "k": "active", "v": ""}]
            for kind, data in [("json", json.dumps(objects).encode()),
                               ("jsonl", "\n".join(json.dumps(x) for x in objects).encode())]:
                result = pivot(data, kind, spec=path)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertEqual(json.loads(result.stdout), [
                    {"id": "001", "東京 🍵": 0, "active": False}, {"id": "002", "active": ""}])
            tsv = pivot("id\tk\tv\n001\t東京 🍵\t0\n".encode(), "tsv", spec=path)
            self.assertEqual(tsv.returncode, 0, tsv.stderr.decode())
            self.assertEqual(json.loads(tsv.stdout), [{"id": "001", "東京 🍵": "0"}])
            xlsx = pivot(json.dumps(objects).encode(), "json", "xlsx", spec=path)
            self.assertEqual(xlsx.returncode, 0, xlsx.stderr.decode())
            with zipfile.ZipFile(io.BytesIO(xlsx.stdout)) as archive:
                sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
                cells = {cell.attrib["r"]: cell for cell in sheet.findall(".//s:c", NS)}
                self.assertEqual(cells["B2"].find("s:v", NS).text, "0")
                self.assertEqual(cells["C2"].attrib["t"], "b")
                self.assertEqual(cells["C2"].find("s:v", NS).text, "0")
        self.with_spec(spec, check)

    def test_duplicates_fail_without_stdout_and_last_corrections_work(self):
        data = (FIXTURES / "corrections.csv").read_bytes()
        spec = {"id_columns": ["store"], "key_column": "month", "value_column": "sales"}
        def reject(path):
            result = pivot(data, spec=path)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"DuplicatePivotCell", result.stderr)
            self.assertIn(b"first_row=1", result.stderr)
            self.assertIn(b"row=3", result.stderr)
        self.with_spec(spec, reject)
        last = pivot(data, spec=FIXTURES / "latest-sales.json")
        self.assertEqual(last.returncode, 0, last.stderr.decode())
        self.assertEqual(json.loads(last.stdout), [{"store": "001", "Jan": "110", "Feb": "120"}, {"store": "002", "Jan": "0"}])
        spec["duplicates"] = "first"
        def first(path):
            result = pivot(data, spec=path)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(json.loads(result.stdout)[0]["Jan"], "100")
        self.with_spec(spec, first)

    def test_missing_keys_rejected_and_prefix_resolves_collision(self):
        spec = {"id_columns": ["id"], "key_column": "k", "value_column": "v"}
        def reject(path):
            for data in [b"id,k,v\na,,1\n", b"id,k,v\na,id,1\n"]:
                result = pivot(data, spec=path)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
        self.with_spec(spec, reject)
        spec["prefix"] = "answer."
        def prefixed(path):
            result = pivot(b"id,k,v\na,id,1\n", spec=path)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(json.loads(result.stdout), [{"id": "a", "answer.id": "1"}])
        self.with_spec(spec, prefixed)

    def test_unknown_spec_field_and_invalid_utf8_do_not_emit(self):
        spec = {"id_columns": ["id"], "key_column": "k", "value_column": "v", "drop_empty": True}
        def invalid(path):
            result = pivot(b"id,k,v\na,x,1\n", spec=path)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"Unknown pivot spec field", result.stderr)
        self.with_spec(spec, invalid)
        result = pivot(b"\xff")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_empty_input_preserves_csv_identifier_header(self):
        result = pivot(b"store,region,month,sales\n", output="csv")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(list(csv.reader(io.StringIO(result.stdout.decode()))), [["store", "region"]])

    def test_csv_quoted_keys_and_values_are_preserved(self):
        spec = {"id_columns": ["id"], "key_column": "k", "value_column": "v"}
        def check(path):
            data = b'id,k,v\r\n001,"Jan, actual","line one\nline two"\r\n001,"Feb ""plan""",=A1+1\r\n'
            result = pivot(data, output="csv", spec=path)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(list(csv.reader(io.StringIO(result.stdout.decode()))), [["id", "Jan, actual", 'Feb "plan"'], ["001", "line one\nline two", "=A1+1"]])
        self.with_spec(spec, check)


if __name__ == "__main__":
    unittest.main()
