"""File-level three-way review, explicit decisions and unchanged copy application."""
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import review_sheet as sheet
import review_rebase as rebase
import review_selection as selection

SOURCE = b'id,name,status,private_note\n001,Ada,pending,"keep, exactly"\n002,Bo,open,=1+1\n003,Chen,,untouched\n'
EDITED = b'name,id,status\nChen,003,ready\n"Ada, A.",001,approved\nBo,002,\n'
CURRENT = b'name,id,status,private_note,added_column\nBo,002,,updated private,b\nDee,004,new,new row,d\nAda,001,awaiting,current private,a\n'
SCOPE = {'key_columns': ['id'], 'edit_columns': ['status', 'name']}


class RebaseReview(unittest.TestCase):
    def setup_files(self, root, source=SOURCE, edited=EDITED, current=CURRENT, fmt='csv', scope=SCOPE):
        original = root / ('original.' + fmt); original.write_bytes(source)
        latest = root / ('current.' + fmt); latest.write_bytes(current)
        spec = root / 'scope.json'; spec.write_bytes(sheet.encode(scope))
        workspace = root / 'sheet'; sheet.create_sheet(original, fmt, spec, workspace)
        (workspace / ('editable.' + fmt)).write_bytes(edited)
        proposal = root / 'proposal'; sheet.create_proposal(original, workspace, proposal)
        review = root / 'review'; rebase.export_review(original, proposal, latest, review)
        return original, proposal, latest, review

    def choices(self, directory, values):
        rows = sheet.parse((directory / 'decisions.csv').read_bytes(), 'csv')
        for row, value in zip(rows[1:], values):
            row[-1] = value
        (directory / 'decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
        return rows

    def cli(self, script, *args, success=True):
        run = subprocess.run([sys.executable, '-B', str(ROOT / 'tools' / script), *map(str, args)], capture_output=True)
        if success:
            self.assertEqual(run.returncode, 0, run.stderr.decode())
            return json.loads(run.stdout)
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(run.stdout, b'')
        return run.stderr.decode()

    def read_csv(self, path, fmt='csv'):
        with path.open(encoding='utf-8', newline='') as handle:
            return list(csv.reader(handle, delimiter=',' if fmt == 'csv' else '\t'))

    def test_full_cli_current_values_added_rows_and_columns_survive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = root / 'original.csv'; original.write_bytes(SOURCE)
            current = root / 'current.csv'; current.write_bytes(CURRENT)
            spec = root / 'scope.json'; spec.write_bytes(sheet.encode(SCOPE))
            self.cli('review_sheet.py', 'export', 'csv', original, spec, root / 'sheet')
            (root / 'sheet/editable.csv').write_bytes(EDITED)
            self.cli('review_sheet.py', 'propose', original, root / 'sheet', root / 'parent')
            report = self.cli('review_rebase.py', 'export', original, root / 'parent', current, root / 'review')
            self.assertEqual(report['counts'], {'ready': 1, 'already_applied': 1, 'conflict': 1, 'missing_row': 1})
            self.choices(root / 'review', ['use-reviewed', 'use-reviewed', 'keep-current', 'keep-current'])
            result = self.cli('review_rebase.py', 'prepare', original, root / 'parent', current, root / 'review', root / 'rebased')
            receipt = self.cli('review_sheet.py', 'apply', current, root / 'rebased', root / 'copy.csv')
            expected = [['name','id','status','private_note','added_column'],
                        ['Bo','002','','updated private','b'], ['Dee','004','new','new row','d'],
                        ['Ada, A.','001','approved','current private','a']]
            self.assertEqual(self.read_csv(root / 'copy.csv'), expected)
            self.assertEqual(result['changed_cells'], 2)
            self.assertTrue(receipt['text_values_reopened']); self.assertFalse(receipt['render_verified'])
            self.assertEqual(receipt['source_sha256'], sheet.digest(CURRENT))
            self.assertEqual(result['rebased_recipe_sha256'], receipt['recipe_sha256'])
            recipe = json.loads((root / 'rebased/corrections.json').read_bytes())
            self.assertEqual(recipe['edits'][0]['before'], {'type':'text', 'value':'awaiting'})
            # Independent existing recipe consumer: all before-values target CURRENT.
            values = self.read_csv(current)
            keys = [values[0].index(name) for name in recipe['key_columns']]
            for edit in recipe['edits']:
                row, = [r for r in values[1:] if [r[k] for k in keys] == edit['key']]
                index = values[0].index(edit['column'])
                self.assertEqual(row[index], edit['before']['value'])
                row[index] = edit['after']['value']
            self.assertEqual(values, expected)
            self.assertEqual(original.read_bytes(), SOURCE); self.assertEqual(current.read_bytes(), CURRENT)
            self.assertEqual((root / 'rebased').stat().st_mode & 0o777, 0o700)
            self.assertEqual((root / 'rebased/rebase.json').stat().st_mode & 0o777, 0o600)

    def test_pending_conflict_cli_refuses_then_keep_current_resolves_without_retyping_other_edits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, review = self.setup_files(root)
            error = self.cli('review_rebase.py', 'prepare', old, parent, current, review, root / 'rebased', success=False)
            self.assertIn('no pending choices', error); self.assertFalse((root / 'rebased').exists())
            self.choices(review, ['keep-current', 'use-reviewed', 'keep-current', 'keep-current'])
            result = self.cli('review_rebase.py', 'prepare', old, parent, current, review, root / 'rebased')
            self.assertEqual(result['changed_cells'], 1)
            sheet.apply_proposal(current, root / 'rebased', root / 'copy.csv')
            self.assertEqual(self.read_csv(root / 'copy.csv')[-1], ['Ada, A.','001','awaiting','current private','a'])

    def test_reordered_decision_sheet_and_current_rows_keep_exact_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, review = self.setup_files(root)
            rows = self.choices(review, ['keep-current', 'use-reviewed', 'keep-current', 'keep-current'])
            indices = [7, 4, 1, 5, 3, 2, 6, 0]
            rows = [rows[0]] + list(reversed(rows[1:]))
            (review / 'decisions.csv').write_bytes(sheet.serialize([[r[i] for i in indices] for r in rows], 'csv'))
            rebase.prepare_rebase(old, parent, current, review, root / 'rebased')
            self.assertEqual(json.loads((root / 'rebased/corrections.json').read_bytes())['edits'],
                             [{'key':['001'], 'column':'name', 'before':{'type':'text','value':'Ada'}, 'after':{'type':'text','value':'Ada, A.'}}])

    def test_missing_row_is_explicit_and_cannot_be_resurrected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, review = self.setup_files(root)
            self.choices(review, ['keep-current','keep-current','keep-current','use-reviewed'])
            with self.assertRaisesRegex(sheet.Refused, 'rows are not resurrected'):
                rebase.prepare_rebase(old, parent, current, review, root / 'rebased')
            self.assertFalse((root / 'rebased').exists())
            self.choices(review, ['keep-current'] * 4)
            result = rebase.prepare_rebase(old, parent, current, review, root / 'rebased')
            self.assertEqual(result['result'], 'no_changes_no_copy_needed')
            self.assertEqual(set(p.name for p in (root / 'rebased').iterdir()), {'rebase.json','decisions.csv'})

    def test_already_applied_all_edits_need_no_second_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest, _ = sheet.prepare_sheet(SOURCE, 'csv', SCOPE)
            _, _, corrected = sheet.prepare_proposal(SOURCE, manifest, EDITED)
            old, parent, current, review = self.setup_files(root, current=corrected)
            result = rebase.prepare_rebase(old, parent, current, review, root / 'rebased')
            self.assertEqual(result['classification_counts']['already_applied'], 4)
            self.assertEqual(result['changed_cells'], 0)
            self.assertIsNone(result['rebased_recipe_sha256'])
            self.assertFalse((root / 'rebased/plan.json').exists())

    def test_no_drift_retains_the_original_correction_recipe(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, review = self.setup_files(root, current=SOURCE)
            result = rebase.prepare_rebase(old, parent, current, review, root / 'rebased')
            self.assertEqual(result['classification_counts']['ready'], 4)
            self.assertEqual((root / 'rebased/corrections.json').read_bytes(), (parent / 'corrections.json').read_bytes())

    def test_current_change_requires_fresh_review_and_existing_apply_remains_source_bound(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, review = self.setup_files(root)
            self.choices(review, ['keep-current','use-reviewed','keep-current','keep-current'])
            changed = CURRENT.replace(b'current private', b'later private')
            current.write_bytes(changed)
            with self.assertRaisesRegex(sheet.Refused, 'no longer matches current source'):
                rebase.prepare_rebase(old, parent, current, review, root / 'rebased')
            self.assertFalse((root / 'rebased').exists())
            rebase.export_review(old, parent, current, root / 'fresh-review')
            self.choices(root / 'fresh-review', ['keep-current','use-reviewed','keep-current','keep-current'])
            rebase.prepare_rebase(old, parent, current, root / 'fresh-review', root / 'rebased')
            current.write_bytes(CURRENT)
            with self.assertRaisesRegex(sheet.Refused, 'Source changed'):
                sheet.apply_proposal(current, root / 'rebased', root / 'copy.csv')
            self.assertFalse((root / 'copy.csv').exists())
            current.write_bytes(changed)
            sheet.apply_proposal(current, root / 'rebased', root / 'copy.csv')
            self.assertEqual(self.read_csv(root / 'copy.csv')[-1][3], 'later private')

    def test_parent_selected_proposal_only_carries_accepted_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, _ = self.setup_files(root)
            selection.export_decisions(old, parent, root / 'selection')
            self.choices(root / 'selection', ['reject','accept','reject','reject'])
            selection.select_proposal(old, parent, root / 'selection', root / 'selected')
            result = rebase.export_review(old, root / 'selected', current, root / 'selected-review')
            self.assertEqual(result['changes'], 1)
            rebase.prepare_rebase(old, root / 'selected', current, root / 'selected-review', root / 'rebased')
            self.assertEqual(len(json.loads((root / 'rebased/corrections.json').read_bytes())['edits']), 1)

    def test_decision_values_cannot_retarget_the_reviewed_current_snapshot(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, review = self.setup_files(root)
            rows = self.choices(review, ['use-reviewed','use-reviewed','keep-current','keep-current'])
            rows[1][4] = 'invented new value'
            (review / 'decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
            with self.assertRaisesRegex(sheet.Refused, 'edit only decision'):
                rebase.prepare_rebase(old, parent, current, review, root / 'rebased')
            self.assertFalse((root / 'rebased').exists())
            old.write_bytes(SOURCE.replace(b'pending', b'changed'))
            with self.assertRaisesRegex(sheet.Refused, 'Source changed'):
                rebase.export_review(old, parent, current, root / 'fresh')

    def test_tsv_composite_ids_multiline_unicode_and_empty_text_remain_literal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            old_rows = [['project','line','note','hidden'], ['001','a','old\tnote','h1'], ['001','b','東京 😀','h2']]
            edited_rows = [['line','note','project'], ['b','new\n"note"','001'], ['a','','001']]
            current_rows = [['line','hidden','project','note'], ['b','new private','001','other value'], ['a','h1','001','old\tnote']]
            old, parent, current, review = self.setup_files(root, sheet.serialize(old_rows,'tsv'), sheet.serialize(edited_rows,'tsv'),
                                                           sheet.serialize(current_rows,'tsv'), 'tsv', {'key_columns':['project','line'],'edit_columns':['note']})
            self.choices(review, ['use-reviewed','use-reviewed'])
            self.cli('review_rebase.py', 'prepare', old, parent, current, review, root / 'rebased')
            self.cli('review_sheet.py', 'apply', current, root / 'rebased', root / 'copy.tsv')
            self.assertEqual(self.read_csv(root / 'copy.tsv','tsv'), [['line','hidden','project','note'], ['b','new private','001','new\n"note"'], ['a','h1','001','']])

    def test_fresh_destination_retry_and_frozen_proposal_survive_later_working_choices(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, review = self.setup_files(root)
            self.choices(review, ['keep-current','use-reviewed','keep-current','keep-current'])
            (root / 'taken').mkdir(); (root / 'taken/keep').write_text('existing')
            with self.assertRaises(FileExistsError):
                rebase.prepare_rebase(old, parent, current, review, root / 'taken')
            rebase.prepare_rebase(old, parent, current, review, root / 'rebased')
            self.choices(review, ['use-reviewed','keep-current','keep-current','keep-current'])
            sheet.apply_proposal(current, root / 'rebased', root / 'copy.csv')
            self.assertEqual(self.read_csv(root / 'copy.csv')[-1][:3], ['Ada, A.','001','awaiting'])
            self.assertEqual((root / 'taken/keep').read_text(), 'existing')

    def test_current_selected_schema_must_still_exist(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old, parent, current, _ = self.setup_files(root)
            current.write_bytes(b'id,status\n001,pending\n')
            with self.assertRaisesRegex(sheet.Refused, 'Unknown selected column'):
                rebase.export_review(old, parent, current, root / 'missing-column')
            self.assertFalse((root / 'missing-column').exists())


if __name__ == '__main__': unittest.main()
