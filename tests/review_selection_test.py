"""Selective acceptance through the actual review/export/apply file workflow."""
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import review_sheet as sheet
import review_selection as selection

SOURCE = b'id,name,status,private_note\n001,Ada,pending,"keep, exactly"\n002,Bo,open,=1+1\n003,Chen,,untouched\n'
EDITED = b'name,id,status\nChen,003,ready\n"Ada, A.",001,approved\nBo,002,\n'
SCOPE = {'key_columns': ['id'], 'edit_columns': ['status', 'name']}


class SelectReviewEdits(unittest.TestCase):
    def prepare(self, root, source=SOURCE, edited=EDITED, fmt='csv', scope=SCOPE):
        original = root / ('source.' + fmt); original.write_bytes(source)
        spec = root / 'scope.json'; spec.write_bytes(sheet.encode(scope))
        workspace = root / 'sheet'; sheet.create_sheet(original, fmt, spec, workspace)
        (workspace / ('editable.' + fmt)).write_bytes(edited)
        proposal = root / 'proposal'; sheet.create_proposal(original, workspace, proposal)
        decisions = root / 'choices'; selection.export_decisions(original, proposal, decisions)
        return original, proposal, decisions

    def choose(self, directory, values):
        rows = sheet.parse((directory / 'decisions.csv').read_bytes(), 'csv')
        for row, value in zip(rows[1:], values): row[-1] = value
        (directory / 'decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
        return rows

    def test_cli_select_then_existing_apply_preserves_rejected_and_private_cells(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = root / 'source.csv'; original.write_bytes(SOURCE)
            spec = root / 'scope.json'; spec.write_bytes(sheet.encode(SCOPE))
            def cli(script, *args):
                return json.loads(subprocess.run([sys.executable, str(ROOT / 'tools' / script), *map(str, args)], check=True, capture_output=True).stdout)
            cli('review_sheet.py', 'export', 'csv', original, spec, root / 'sheet')
            (root / 'sheet/editable.csv').write_bytes(EDITED)
            cli('review_sheet.py', 'propose', original, root / 'sheet', root / 'proposal')
            cli('review_selection.py', 'export', original, root / 'proposal', root / 'choices')
            self.choose(root / 'choices', ['reject', 'accept', 'reject', 'accept'])
            receipt = cli('review_selection.py', 'select', original, root / 'proposal', root / 'choices', root / 'chosen')
            result = cli('review_sheet.py', 'apply', original, root / 'chosen', root / 'copy.csv')
            actual = list(csv.reader(io.StringIO((root / 'copy.csv').read_text(), newline='')))
            self.assertEqual(actual, [['id','name','status','private_note'], ['001','Ada, A.','pending','keep, exactly'], ['002','Bo','open','=1+1'], ['003','Chen','ready','untouched']])
            self.assertEqual((receipt['accepted_cells'], receipt['rejected_cells']), (2, 2))
            self.assertTrue(result['text_values_reopened']); self.assertFalse(result['render_verified'])
            self.assertEqual(result['recipe_sha256'], receipt['selected_recipe_sha256'])
            self.assertEqual(original.read_bytes(), SOURCE)
            self.assertEqual((root / 'chosen').stat().st_mode & 0o777, 0o700)
            self.assertEqual((root / 'chosen/selection.json').stat().st_mode & 0o777, 0o600)
            # Frozen selected proposal is independent of later working choices.
            self.choose(root / 'choices', ['accept'] * 4)
            sheet.apply_proposal(original, root / 'chosen', root / 'same.csv')
            self.assertEqual((root / 'copy.csv').read_bytes(), (root / 'same.csv').read_bytes())

    def test_all_accept_preserves_parent_recipe_and_copy_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original, parent, choices = self.prepare(root)
            self.choose(choices, ['accept'] * 4)
            selection.select_proposal(original, parent, choices, root / 'chosen')
            self.assertEqual((parent / 'corrections.json').read_bytes(), (root / 'chosen/corrections.json').read_bytes())
            sheet.apply_proposal(original, parent, root / 'all.csv')
            sheet.apply_proposal(original, root / 'chosen', root / 'selected.csv')
            self.assertEqual((root / 'all.csv').read_bytes(), (root / 'selected.csv').read_bytes())

    def test_all_reject_records_deliberate_no_change_without_copy_proposal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original, parent, choices = self.prepare(root)
            self.choose(choices, ['reject'] * 4)
            result = selection.select_proposal(original, parent, choices, root / 'none')
            self.assertEqual(result['result'], 'all_rejected_no_copy_needed')
            self.assertEqual(result['accepted_cells'], 0)
            self.assertEqual(set(p.name for p in (root / 'none').iterdir()), {'selection.json', 'decisions.csv'})
            self.assertEqual(original.read_bytes(), SOURCE)

    def test_reordered_decision_rows_and_columns_keep_exact_cell_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original, parent, choices = self.prepare(root)
            rows = self.choose(choices, ['reject', 'accept', 'reject', 'accept'])
            indexes = [5, 2, 4, 0, 1, 3]
            reordered = [rows[0]] + list(reversed(rows[1:]))
            (choices / 'decisions.csv').write_bytes(sheet.serialize([[r[i] for i in indexes] for r in reordered], 'csv'))
            selection.select_proposal(original, parent, choices, root / 'chosen')
            edits = json.loads((root / 'chosen/corrections.json').read_bytes())['edits']
            self.assertEqual([(e['key'],e['column']) for e in edits], [(['001'],'name'), (['003'],'status')])

    def test_pending_choice_blocks_then_can_be_completed_without_lost_work(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original, parent, choices = self.prepare(root)
            self.choose(choices, ['accept', '', 'reject', 'reject'])
            with self.assertRaisesRegex(sheet.Refused, 'no pending choices'): selection.select_proposal(original, parent, choices, root / 'chosen')
            self.assertFalse((root / 'chosen').exists())
            self.choose(choices, ['accept', 'reject', 'reject', 'reject'])
            self.assertEqual(selection.select_proposal(original, parent, choices, root / 'chosen')['accepted_cells'], 1)

    def test_changed_source_or_parent_does_not_retarget_saved_decisions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original, parent, choices = self.prepare(root)
            self.choose(choices, ['accept'] * 4)
            original.write_bytes(SOURCE.replace(b'pending', b'external'))
            with self.assertRaisesRegex(sheet.Refused, 'Source changed'): selection.select_proposal(original, parent, choices, root / 'chosen')
            original.write_bytes(SOURCE)
            (parent / 'corrections.json').write_bytes(b'{}')
            with self.assertRaisesRegex(sheet.Refused, 'Proposal or recipe changed'): selection.select_proposal(original, parent, choices, root / 'chosen')
            self.assertFalse((root / 'chosen').exists())

    def test_editing_proposed_values_requires_a_new_proposal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original, parent, choices = self.prepare(root)
            rows = self.choose(choices, ['accept'] * 4)
            rows[1][4] = 'not originally proposed'
            (choices / 'decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
            with self.assertRaisesRegex(sheet.Refused, 'edit only decision'): selection.select_proposal(original, parent, choices, root / 'chosen')
            self.assertFalse((root / 'chosen').exists())

    def test_destination_conflict_preserves_selection_and_can_retry_fresh(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original, parent, choices = self.prepare(root)
            self.choose(choices, ['accept'] * 4)
            (root / 'exists').mkdir(); (root / 'exists/keep').write_text('kept')
            with self.assertRaises(FileExistsError): selection.select_proposal(original, parent, choices, root / 'exists')
            self.assertEqual((root / 'exists/keep').read_text(), 'kept')
            self.assertEqual(selection.select_proposal(original, parent, choices, root / 'retry')['accepted_cells'], 4)

    def test_tsv_unicode_composite_ids_and_multiline_before_after_are_literal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = sheet.serialize([['project','line','note','hidden'],['001','a','old\tnote','h1'],['001','b','東京 😀','h2']], 'tsv')
            edited = sheet.serialize([['line','note','project'],['b','new\n"note"','001'],['a','','001']], 'tsv')
            original, parent, choices = self.prepare(root, source, edited, 'tsv', {'key_columns':['project','line'],'edit_columns':['note']})
            self.choose(choices, ['reject','accept'])
            selection.select_proposal(original, parent, choices, root / 'chosen')
            sheet.apply_proposal(original, root / 'chosen', root / 'copy.tsv')
            with (root / 'copy.tsv').open(newline='') as f: rows = list(csv.reader(f, delimiter='\t'))
            self.assertEqual(rows[1], ['001','a','old\tnote','h1'])
            self.assertEqual(rows[2], ['001','b','new\n"note"','h2'])


if __name__ == '__main__': unittest.main()
