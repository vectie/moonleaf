"""Dependency-free end-user workflow tests; run from any replay checkout."""
import csv
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pseudonymize', ROOT / 'tools/pseudonymize.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
POLICY = {'key_columns': ['id'], 'columns': [
    {'column': 'name', 'mode': 'pseudonym', 'prefix': 'PERSON-'},
    {'column': 'email', 'mode': 'mask', 'value': '[removed]'},
]}
SOURCE = b'id,name,email,note\n001,Ada,ada@example.test,"hello, world"\n002,Bo,bo@example.test,=1+1\n003,Ada,ada@example.test,\n004,,,unchanged\n'


class Pseudonymization(unittest.TestCase):
    def test_consistent_tokens_and_mask_preserve_schema_blanks_unselected_values(self):
        plan, recipe, copy = m.prepare(SOURCE, 'csv', POLICY)
        rows = m.parse(copy, 'csv')
        self.assertEqual([row[1] for row in rows[1:]], ['PERSON-0001', 'PERSON-0002', 'PERSON-0001', ''])
        self.assertEqual([row[2] for row in rows[1:]], ['[removed]'] * 3 + [''])
        self.assertEqual([row[0] for row in rows], [row[0] for row in m.parse(SOURCE, 'csv')])
        self.assertEqual([row[3] for row in rows], [row[3] for row in m.parse(SOURCE, 'csv')])
        self.assertNotIn(b'ada@example.test', copy)
        self.assertEqual(plan['changes'][0]['distinct_tokens'], 2)
        parsed = json.loads(recipe)
        self.assertEqual(set(parsed), {'key_columns', 'edits'})
        self.assertEqual(len(parsed['edits']), 6)
        self.assertEqual(parsed['edits'][0], {'key': ['001'], 'column': 'name', 'before': {'type': 'text', 'value': 'Ada'}, 'after': {'type': 'text', 'value': 'PERSON-0001'}})

    def test_unicode_multiline_tsv_composite_keys_and_exact_case(self):
        rows = [['id', 'part', 'name', 'email', 'note'], ['01', 'a', '東京 😀', 'a@x', 'line1\r\nline2'], ['01', 'b', '東京 😀', 'b@x', 'tab\there'], ['02', 'a', '東京', '', '"quote"']]
        raw = '\ufeff'.encode('utf-8') + m.serialize(rows, 'tsv')
        policy = {**POLICY, 'key_columns': ['id', 'part']}
        _, recipe, copy = m.prepare(raw, 'tsv', policy)
        result = m.parse(copy, 'tsv')
        self.assertEqual(result[1][2], result[2][2]); self.assertNotEqual(result[1][2], result[3][2])
        self.assertEqual([r[-1] for r in result], [r[-1] for r in rows])
        self.assertEqual(json.loads(recipe)['edits'][1]['key'], ['01', 'b'])
        self.assertEqual(list(csv.reader(io.StringIO(copy.decode(), newline=''), delimiter='\t')), result)

    def test_tokens_are_per_column_per_file_and_not_global_identities(self):
        policy = {'key_columns': ['id'], 'columns': [{'column': 'name', 'mode': 'pseudonym', 'prefix': 'N-'}, {'column': 'email', 'mode': 'pseudonym', 'prefix': 'E-'}]}
        _, _, copy = m.prepare(SOURCE, 'csv', policy)
        self.assertEqual(m.parse(copy, 'csv')[1][1:3], ['N-0001', 'E-0001'])
        _, _, other = m.prepare(b'id,name,email,note\n9,Different,other@x,new\n', 'csv', policy)
        self.assertEqual(m.parse(other, 'csv')[1][1:3], ['N-0001', 'E-0001'])

    def test_blank_only_targets_refuse_without_meaningless_recipe(self):
        with self.assertRaisesRegex(m.Refused, 'No nonempty'):
            m.prepare(b'id,name,email,note\n1,,,ok\n', 'csv', POLICY)

    def test_existing_correction_limits_and_key_invariants(self):
        for raw in [b'id,name,email,note\n1,A,a,n\n1,B,b,n\n', b'id,name,email,note\n,A,a,n\n']:
            with self.assertRaisesRegex(m.Refused, 'globally unique'):
                m.prepare(raw, 'csv', POLICY)
        for policy in [dict(POLICY, key_columns=['missing']), dict(POLICY, columns=[{'column': 'id', 'mode': 'mask', 'value': 'x'}])]:
            with self.assertRaises(m.Refused): m.prepare(SOURCE, 'csv', policy)
        raw = m.serialize([['id', 'name', 'email', 'note']] + [[str(i), 'A', 'e', ''] for i in range(500)], 'csv')
        self.assertEqual(len(json.loads(m.prepare(raw, 'csv', POLICY)[1])['edits']), 1000)
        raw += b'501,A,e,\r\n'
        with self.assertRaisesRegex(m.Refused, '1000'): m.prepare(raw, 'csv', POLICY)

    def test_parser_refuses_invalid_quote_ragged_rows_and_duplicate_headers(self):
        for raw in [b'id,name,email,note\n1,a"b,x,y', b'id,name,email,note\n1,"a"junk,x,y', b'id,name,email,note\n1,"abc', b'id,name,email,note\n1,a', b'id,name,name\n1,a,b']:
            with self.assertRaises(m.Refused): m.prepare(raw, 'csv', POLICY)

    def test_policies_are_explicit_and_summary_contains_no_before_values(self):
        for columns in [[{'column': 'name', 'mode': 'pseudonym', 'prefix': '=BAD'}], [POLICY['columns'][0]] * 2, [{'column': 'name', 'mode': 'guess'}]]:
            with self.assertRaises(m.Refused): m.prepare(SOURCE, 'csv', dict(POLICY, columns=columns))
        plan, _, _ = m.prepare(SOURCE, 'csv', POLICY)
        self.assertNotIn('ada@example.test', json.dumps(plan))
        with self.assertRaisesRegex(m.Refused, 'Duplicate'): m.json_value(b'{"a":1,"a":2}')

    def test_actual_cli_plan_apply_reopen_and_original_preservation(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp); source = d / 'original.csv'; source.write_bytes(SOURCE)
            policy = d / 'policy.json'; policy.write_bytes(m.encode(POLICY))
            def cli(*args):
                return subprocess.run([sys.executable, str(ROOT / 'tools/pseudonymize.py'), *map(str, args)], capture_output=True, check=True)
            summary = json.loads(cli('plan', 'csv', source, policy, d / 'private').stdout)
            receipt = json.loads(cli('apply', source, d / 'private', d / 'client.csv').stdout)
            self.assertEqual(source.read_bytes(), SOURCE)
            self.assertEqual(receipt['copy_sha256'], m.digest((d / 'client.csv').read_bytes()))
            self.assertTrue(receipt['text_values_reopened']); self.assertFalse(receipt['render_verified'])
            self.assertEqual(summary['rows'], 4)
            self.assertEqual((d / 'private/corrections.json').stat().st_mode & 0o777, 0o600)
            self.assertEqual((d / 'client.csv').stat().st_mode & 0o777, 0o600)
            self.assertNotIn(b'ada@example.test', json.dumps(receipt).encode())

    def _files(self, d):
        source, policy, plan = d / 'original.csv', d / 'policy.json', d / 'private'
        source.write_bytes(SOURCE); policy.write_bytes(m.encode(POLICY))
        m.create_plan(source, 'csv', policy, plan)
        return source, policy, plan

    def test_source_change_and_plan_edit_require_review_again(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp); source, _, plan = self._files(d)
            source.write_bytes(SOURCE + b'5,New,new@x,z\n')
            with self.assertRaisesRegex(m.Refused, 'Source changed'): m.apply_plan(source, plan, d / 'out.csv')
            self.assertFalse((d / 'out.csv').exists())
            source.write_bytes(SOURCE)
            (plan / 'corrections.json').write_bytes(b'{}')
            with self.assertRaisesRegex(m.Refused, 'recipe changed'): m.apply_plan(source, plan, d / 'out.csv')
            self.assertFalse((d / 'out.csv').exists())

    def test_existing_destination_and_source_paths_are_never_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp); source, policy, plan = self._files(d)
            target = d / 'out.csv'; target.write_bytes(b'keep')
            with self.assertRaises(FileExistsError): m.apply_plan(source, plan, target)
            self.assertEqual(target.read_bytes(), b'keep')
            with self.assertRaises(m.Refused): m.apply_plan(source, plan, source)
            with self.assertRaises(FileExistsError): m.create_plan(source, 'csv', policy, plan)
            self.assertEqual(source.read_bytes(), SOURCE)
            receipt = m.apply_plan(source, plan, d / 'retry.csv')
            self.assertTrue(receipt['text_values_reopened'])

    def test_failed_readback_retains_unverified_copy_and_can_retry_new_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp); source, _, plan = self._files(d); target = d / 'out.csv'
            real_read = m.read_regular
            def corrupt(path):
                return b'id,name\n1,wrong\n' if Path(path) == target else real_read(path)
            with patch.object(m, 'read_regular', side_effect=corrupt):
                with self.assertRaisesRegex(m.Refused, 'retained unverified'): m.apply_plan(source, plan, target)
            self.assertTrue(target.exists()); self.assertEqual(source.read_bytes(), SOURCE)
            self.assertTrue(m.apply_plan(source, plan, d / 'retry.csv')['text_values_reopened'])

    def test_checked_in_synthetic_example_is_reproducible(self):
        kit = ROOT / 'kit/pseudonymize'
        plan, recipe, copy = m.prepare((kit / 'source.csv').read_bytes(), 'csv', json.loads((kit / 'policy.json').read_bytes()))
        self.assertEqual(recipe, (kit / 'private-plan/corrections.json').read_bytes())
        self.assertEqual(copy, (kit / 'client-copy.csv').read_bytes())
        self.assertEqual(plan, json.loads((kit / 'private-plan/plan.json').read_bytes()))


if __name__ == '__main__':
    unittest.main()
