"""Focused offline edit-sheet workflow checks, runnable in an independent checkout."""
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import review_sheet as m

SOURCE = b'id,name,status,private_note\n001,Ada,pending,"keep, exactly"\n002,Bo,open,=1+1\n003,Chen,,untouched\n'
SELECTION = {'key_columns': ['id'], 'edit_columns': ['status', 'name']}
EDITED = b'name,id,status\nChen,003,ready\n"Ada, A.",001,approved\nBo,002,\n'


class ReviewSheet(unittest.TestCase):
    def files(self, directory):
        source, selection, workspace = directory / 'source.csv', directory / 'selection.json', directory / 'review'
        source.write_bytes(SOURCE)
        selection.write_bytes(m.encode(SELECTION))
        m.create_sheet(source, 'csv', selection, workspace)
        (workspace / 'editable.csv').write_bytes(EDITED)
        return source, workspace

    def test_export_exposes_only_selected_columns_in_requested_order(self):
        manifest, sheet = m.prepare_sheet(SOURCE, 'csv', SELECTION)
        self.assertEqual(m.parse(sheet, 'csv'), [['id', 'status', 'name'], ['001', 'pending', 'Ada'], ['002', 'open', 'Bo'], ['003', '', 'Chen']])
        self.assertNotIn(b'private_note', sheet)
        self.assertEqual(manifest['source_sha256'], m.digest(SOURCE))
        self.assertEqual(manifest['baseline_sheet_sha256'], m.digest(sheet))

    def test_sorted_reordered_review_generates_exact_existing_recipe_and_full_copy(self):
        manifest, _ = m.prepare_sheet(SOURCE, 'csv', SELECTION)
        plan, recipe_raw, copy = m.prepare_proposal(SOURCE, manifest, EDITED)
        recipe = json.loads(recipe_raw)
        self.assertEqual(set(recipe), {'key_columns', 'edits'})
        self.assertEqual(recipe['key_columns'], ['id'])
        self.assertEqual(recipe['edits'], [
            {'key': ['001'], 'column': 'status', 'before': {'type': 'text', 'value': 'pending'}, 'after': {'type': 'text', 'value': 'approved'}},
            {'key': ['001'], 'column': 'name', 'before': {'type': 'text', 'value': 'Ada'}, 'after': {'type': 'text', 'value': 'Ada, A.'}},
            {'key': ['002'], 'column': 'status', 'before': {'type': 'text', 'value': 'open'}, 'after': {'type': 'text', 'value': ''}},
            {'key': ['003'], 'column': 'status', 'before': {'type': 'text', 'value': ''}, 'after': {'type': 'text', 'value': 'ready'}},
        ])
        self.assertEqual(m.parse(copy, 'csv'), [['id', 'name', 'status', 'private_note'], ['001', 'Ada, A.', 'approved', 'keep, exactly'], ['002', 'Bo', '', '=1+1'], ['003', 'Chen', 'ready', 'untouched']])
        self.assertEqual((plan['changed_rows'], plan['changed_cells']), (3, 4))
        # An independent in-memory recipe consumer verifies the published exchange.
        rows = list(csv.reader(io.StringIO(SOURCE.decode(), newline='')))
        for edit in recipe['edits']:
            row = next(row for row in rows[1:] if [row[rows[0].index(k)] for k in recipe['key_columns']] == edit['key'])
            column = rows[0].index(edit['column'])
            self.assertEqual(edit['before'], {'type': 'text', 'value': row[column]})
            row[column] = edit['after']['value']
        self.assertEqual(rows, list(csv.reader(io.StringIO(copy.decode(), newline=''))))

    def test_actual_cli_export_edit_propose_apply_reopens_full_table(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            source, selection, workspace = directory / 'source.csv', directory / 'selection.json', directory / 'review'
            source.write_bytes(SOURCE); selection.write_bytes(m.encode(SELECTION))
            def cli(*args):
                return subprocess.run([sys.executable, str(ROOT / 'tools/review_sheet.py'), *map(str, args)], capture_output=True, check=True)
            exported = json.loads(cli('export', 'csv', source, selection, workspace).stdout)
            self.assertEqual(exported['editable_file'], 'editable.csv')
            (workspace / 'editable.csv').write_bytes(EDITED)
            plan = directory / 'proposal'
            proposed = json.loads(cli('propose', source, workspace, plan).stdout)
            receipt = json.loads(cli('apply', source, plan, directory / 'copy.csv').stdout)
            self.assertEqual(source.read_bytes(), SOURCE)
            self.assertEqual(receipt['copy_sha256'], m.digest((directory / 'copy.csv').read_bytes()))
            self.assertEqual(receipt['recipe_sha256'], m.digest((plan / 'corrections.json').read_bytes()))
            self.assertEqual(proposed['changed_cells'], 4)
            self.assertTrue(receipt['text_values_reopened']); self.assertFalse(receipt['render_verified'])
            self.assertEqual(workspace.stat().st_mode & 0o777, 0o700)
            self.assertEqual((plan / 'corrections.json').stat().st_mode & 0o777, 0o600)
            self.assertEqual((directory / 'copy.csv').stat().st_mode & 0o777, 0o600)
            self.assertNotIn('keep, exactly', json.dumps(receipt))
            # A large unselected note remains valid under the declared text bound.
            source.write_bytes(SOURCE.replace(b'untouched', b'z' * 150000))
            cli('export', 'csv', source, selection, directory / 'long-review')
            (directory / 'long-review/editable.csv').write_bytes(EDITED)
            cli('propose', source, directory / 'long-review', directory / 'long-proposal')
            self.assertTrue(json.loads(cli('apply', source, directory / 'long-proposal', directory / 'long-copy.csv').stdout)['text_values_reopened'])
            self.assertEqual(m.parse((directory / 'long-copy.csv').read_bytes(), 'csv')[3][-1], 'z' * 150000)

    def test_unicode_tsv_composite_keys_multiline_quotes_and_empty_values(self):
        rows = [['project', 'line', 'note', 'hidden'], ['001', 'a', '東京 😀', 'h1'], ['001', 'b', '', 'h2']]
        raw = b'\xef\xbb\xbf' + m.serialize(rows, 'tsv')
        selection = {'key_columns': ['project', 'line'], 'edit_columns': ['note']}
        manifest, _ = m.prepare_sheet(raw, 'tsv', selection)
        edited = m.serialize([['line', 'note', 'project'], ['b', 'tab\there\n"quoted"', '001'], ['a', '', '001']], 'tsv')
        _, recipe, copy = m.prepare_proposal(raw, manifest, edited)
        result = list(csv.reader(io.StringIO(copy.decode(), newline=''), delimiter='\t'))
        self.assertEqual(result, [rows[0], ['001', 'a', '', 'h1'], ['001', 'b', 'tab\there\n"quoted"', 'h2']])
        self.assertEqual(json.loads(recipe)['edits'][0]['key'], ['001', 'a'])
        self.assertEqual(raw, b'\xef\xbb\xbf' + m.serialize(rows, 'tsv'))

    def test_key_membership_and_column_scope_mistakes_have_actionable_refusals(self):
        manifest, _ = m.prepare_sheet(SOURCE, 'csv', SELECTION)
        with self.assertRaisesRegex(m.Refused, '1 missing and 1 unknown'):
            m.prepare_proposal(SOURCE, manifest, EDITED.replace(b'003', b'3'))
        with self.assertRaisesRegex(m.Refused, 'duplicate stable key'):
            m.prepare_proposal(SOURCE, manifest, EDITED.replace(b'003', b'001'))
        with self.assertRaisesRegex(m.Refused, 'exactly the selected'):
            m.prepare_proposal(SOURCE, manifest, b'id,name,private_note\n001,Ada,replaced\n')
        with self.assertRaisesRegex(m.Refused, '1 missing and 0 unknown'):
            m.prepare_proposal(SOURCE, manifest, EDITED.replace(b'Chen,003,ready\n', b''))

    def test_stale_original_conflict_keeps_source_and_proposal_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp); source, workspace = self.files(directory)
            plan = directory / 'proposal'; m.create_proposal(source, workspace, plan)
            recipe = (plan / 'corrections.json').read_bytes()
            newer = SOURCE.replace(b'pending', b'external change'); source.write_bytes(newer)
            with self.assertRaisesRegex(m.Refused, 'Source changed'):
                m.apply_proposal(source, plan, directory / 'copy.csv')
            self.assertFalse((directory / 'copy.csv').exists())
            self.assertEqual(source.read_bytes(), newer)
            self.assertEqual((plan / 'corrections.json').read_bytes(), recipe)
            source.write_bytes(SOURCE)
            self.assertTrue(m.apply_proposal(source, plan, directory / 'copy.csv')['text_values_reopened'])

    def test_proposal_freezes_review_and_detects_later_recipe_edit(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp); source, workspace = self.files(directory)
            plan = directory / 'proposal'; m.create_proposal(source, workspace, plan)
            (workspace / 'editable.csv').write_bytes(EDITED.replace(b'approved', b'not in proposal'))
            m.apply_proposal(source, plan, directory / 'first.csv')
            self.assertIn(b'approved', (directory / 'first.csv').read_bytes())
            self.assertNotIn(b'not in proposal', (directory / 'first.csv').read_bytes())
            (plan / 'corrections.json').write_bytes(b'{}')
            with self.assertRaisesRegex(m.Refused, 'Proposal or recipe changed'):
                m.apply_proposal(source, plan, directory / 'second.csv')
            self.assertFalse((directory / 'second.csv').exists())

    def test_destination_conflict_and_failed_readback_allow_fresh_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp); source, workspace = self.files(directory)
            plan = directory / 'proposal'; m.create_proposal(source, workspace, plan)
            target = directory / 'existing.csv'; target.write_bytes(b'keep')
            with self.assertRaises(FileExistsError): m.apply_proposal(source, plan, target)
            self.assertEqual(target.read_bytes(), b'keep')
            with self.assertRaisesRegex(m.Refused, 'distinct'): m.apply_proposal(source, plan, source)
            failed = directory / 'failed.csv'; real_read = m.read_regular
            def wrong_read(path):
                return b'id,name\n1,wrong\n' if Path(path) == failed else real_read(path)
            with patch.object(m, 'read_regular', side_effect=wrong_read):
                with self.assertRaisesRegex(m.Refused, 'retained unverified'): m.apply_proposal(source, plan, failed)
            self.assertTrue(failed.exists()); self.assertEqual(source.read_bytes(), SOURCE)
            self.assertTrue(m.apply_proposal(source, plan, directory / 'retry.csv')['text_values_reopened'])

    def test_unchanged_sheet_does_not_create_a_meaningless_proposal(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp); source, workspace = self.files(directory)
            _, original_sheet = m.prepare_sheet(SOURCE, 'csv', SELECTION)
            (workspace / 'editable.csv').write_bytes(original_sheet)
            with self.assertRaisesRegex(m.Refused, 'No changed cells'):
                m.create_proposal(source, workspace, directory / 'proposal')
            self.assertFalse((directory / 'proposal').exists())

    def test_selection_and_actual_changed_cell_budget_match_review_scope(self):
        with self.assertRaisesRegex(m.Refused, 'Key columns cannot be editable'):
            m.prepare_sheet(SOURCE, 'csv', {'key_columns': ['id'], 'edit_columns': ['id']})
        rows = [['id', 'value']] + [[str(i), 'before'] for i in range(1001)]
        raw = m.serialize(rows, 'csv'); selection = {'key_columns': ['id'], 'edit_columns': ['value']}
        manifest, _ = m.prepare_sheet(raw, 'csv', selection)
        changed = [rows[0]] + [[str(i), 'after'] for i in range(1000)] + [rows[-1]]
        self.assertEqual(m.prepare_proposal(raw, manifest, m.serialize(changed, 'csv'))[0]['changed_cells'], 1000)
        changed[-1][1] = 'after'
        with self.assertRaisesRegex(m.Refused, '1000 changed cells'):
            m.prepare_proposal(raw, manifest, m.serialize(changed, 'csv'))

    def test_committed_review_example_reproduces_recipe_and_copy(self):
        kit = ROOT / 'kit/review-sheet'
        raw = (kit / 'source.csv').read_bytes()
        selection = json.loads((kit / 'selection.json').read_bytes())
        manifest, sheet = m.prepare_sheet(raw, 'csv', selection)
        self.assertEqual(sheet, (kit / 'exported.csv').read_bytes())
        plan, recipe, copy = m.prepare_proposal(raw, manifest, (kit / 'edited.csv').read_bytes())
        self.assertEqual(recipe, (kit / 'corrections.json').read_bytes())
        self.assertEqual(copy, (kit / 'copy.csv').read_bytes())
        self.assertEqual(plan['changed_cells'], 4)


if __name__ == '__main__':
    unittest.main()
