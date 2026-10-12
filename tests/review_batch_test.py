"""Scoped reviewer work returns to the ordinary proposal and verified-copy lane."""
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import review_batch as batch
import review_sheet as sheet
import review_merge as merge
import review_rebase as rebase
import review_selection as selection

SOURCE = b'id,name,status,private\n001,Ada,pending,secret A\n002,Unassigned Person,unassigned status,secret B\n003,Chen,open,secret C\n'
SCOPE = {'key_columns': ['id'], 'edit_columns': ['status'],
         'context_columns': ['name'], 'row_keys': [['003'], ['001']]}
EDITED = b'id,name,status\n003,Chen,ready\n001,Ada,approved\n'


class ReviewBatch(unittest.TestCase):
    def cli(self, *args, script='review_sheet.py', success=True):
        proc = subprocess.run([sys.executable, '-B', str(ROOT / 'tools' / script), *map(str, args)], capture_output=True)
        if success:
            self.assertEqual(proc.returncode, 0, proc.stderr.decode())
            return json.loads(proc.stdout)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, b'')
        return proc.stderr.decode()

    def workspace(self, root, scope=SCOPE, raw=SOURCE, fmt='csv', name='batch'):
        source = root / ('source.' + fmt); source.write_bytes(raw)
        spec = root / (name + '.json'); spec.write_bytes(sheet.encode(scope))
        batch.create_batch(source, fmt, spec, root / name)
        return source, root / name

    def proposal(self, root, scope=SCOPE, edited=EDITED, name='batch'):
        source, work = self.workspace(root, scope=scope, name=name)
        (work / 'editable.csv').write_bytes(edited)
        proposal = root / (name + '-proposal')
        batch.create_batch_proposal(source, work, proposal)
        return source, work, proposal

    def read_csv(self, path, fmt='csv'):
        with path.open(encoding='utf-8', newline='') as handle:
            return list(csv.reader(handle, delimiter=',' if fmt == 'csv' else '\t'))

    def test_actual_cli_exports_only_assigned_values_then_applies_full_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'source.csv'; source.write_bytes(SOURCE)
            spec = root / 'scope.json'; spec.write_bytes(sheet.encode(SCOPE))
            report = self.cli('batch-export', 'csv', source, spec, root / 'batch')
            self.assertEqual((report['selected_rows'], report['source_rows']), (2, 3))
            self.assertEqual(self.read_csv(root / 'batch/editable.csv'),
                             [['id','name','status'], ['001','Ada','pending'], ['003','Chen','open']])
            for path in (root / 'batch').iterdir():
                for hidden in (b'Unassigned Person', b'unassigned status', b'secret A', b'secret B', b'secret C'):
                    self.assertNotIn(hidden, path.read_bytes())
            (root / 'batch/editable.csv').write_bytes(EDITED)
            proposed = self.cli('batch-propose', source, root / 'batch', root / 'proposal')
            copied = self.cli('apply', source, root / 'proposal', root / 'copy.csv')
            expected = [['id','name','status','private'], ['001','Ada','approved','secret A'],
                        ['002','Unassigned Person','unassigned status','secret B'], ['003','Chen','ready','secret C']]
            self.assertEqual(self.read_csv(root / 'copy.csv'), expected)
            self.assertEqual(proposed['changed_cells'], 2)
            self.assertEqual(proposed['recipe_sha256'], copied['recipe_sha256'])
            self.assertTrue(copied['text_values_reopened']); self.assertFalse(copied['render_verified'])
            # A small independent consumer checks the existing recipe format.
            values = self.read_csv(source)
            recipe = json.loads((root / 'proposal/corrections.json').read_bytes())
            for edit in recipe['edits']:
                row, = [r for r in values[1:] if [r[0]] == edit['key']]
                column = values[0].index(edit['column'])
                self.assertEqual(edit['before'], {'type':'text', 'value':row[column]})
                row[column] = edit['after']['value']
            self.assertEqual(values, expected)
            self.assertEqual(source.read_bytes(), SOURCE)
            self.assertEqual((root / 'batch').stat().st_mode & 0o777, 0o700)
            self.assertEqual((root / 'proposal/batch.json').stat().st_mode & 0o777, 0o600)

    def test_context_must_be_restored_before_changed_cells_can_be_proposed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, work = self.workspace(root)
            (work / 'editable.csv').write_bytes(EDITED.replace(b'Ada', b'Adaline'))
            error = self.cli('batch-propose', source, work, root / 'proposal', success=False)
            self.assertIn('Context columns are read-only', error)
            self.assertFalse((root / 'proposal').exists())
            (work / 'editable.csv').write_bytes(EDITED)
            result = self.cli('batch-propose', source, work, root / 'proposal')
            self.assertEqual(result['changed_cells'], 2)

    def test_tsv_reordered_columns_composite_keys_blank_and_unicode_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            values = [['account','line','context','note','private'], ['001','01','東京\t支店','old','A'],
                      ['1','01','Other account','leave','B'], ['001','02','','old\ntext','C']]
            scope = {'key_columns':['account','line'], 'context_columns':['context'],
                     'edit_columns':['note'], 'row_keys':[['001','02'],['001','01']]}
            source, work = self.workspace(root, scope, sheet.serialize(values, 'tsv'), 'tsv')
            edited = [['note','line','context','account'], ['', '02','','001'], ['😀\n修正','01','東京\t支店','001']]
            (work / 'editable.tsv').write_bytes(sheet.serialize(edited, 'tsv'))
            batch.create_batch_proposal(source, work, root / 'proposal')
            sheet.apply_proposal(source, root / 'proposal', root / 'copy.tsv')
            values[1][3] = '😀\n修正'; values[3][3] = ''
            self.assertEqual(self.read_csv(root / 'copy.tsv', 'tsv'), values)

    def test_no_context_is_an_explicit_supported_choice(self):
        scope = {**SCOPE, 'context_columns':[], 'row_keys':[['003']]}
        manifest, exported = batch.prepare_batch(SOURCE, 'csv', scope)
        self.assertEqual(sheet.parse(exported, 'csv'), [['id','status'],['003','open']])
        result = batch.prepare_batch_proposal(SOURCE, manifest, b'status,id\n,003\n')
        self.assertEqual(result[0]['changed_cells'], 1)
        self.assertEqual(json.loads(result[4])['edits'][0]['after'], {'type':'text','value':''})

    def test_missing_assignment_and_added_record_are_not_silently_ignored(self):
        manifest, _ = batch.prepare_batch(SOURCE, 'csv', SCOPE)
        with self.assertRaisesRegex(sheet.Refused, 'every selected key'):
            batch.prepare_batch_proposal(SOURCE, manifest, b'id,name,status\n001,Ada,approved\n')
        with self.assertRaisesRegex(sheet.Refused, 'every selected key'):
            batch.prepare_batch_proposal(SOURCE, manifest, EDITED + b'002,Unassigned Person,changed\n')

    def test_selector_requires_exact_existing_distinct_keys(self):
        with self.assertRaisesRegex(sheet.Refused, 'Unknown selected row key'):
            batch.prepare_batch(SOURCE, 'csv', {**SCOPE, 'row_keys':[['1']]})
        with self.assertRaisesRegex(sheet.Refused, 'Repeated selected row key'):
            batch.prepare_batch(SOURCE, 'csv', {**SCOPE, 'row_keys':[['001'],['001']]})
        with self.assertRaisesRegex(sheet.Refused, 'disjoint existing columns'):
            batch.prepare_batch(SOURCE, 'csv', {**SCOPE, 'context_columns':['status']})

    def test_no_changes_leave_no_empty_proposal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, work = self.workspace(root)
            with self.assertRaisesRegex(sheet.Refused, 'No changed cells'):
                batch.create_batch_proposal(source, work, root / 'proposal')
            self.assertFalse((root / 'proposal').exists())

    def test_source_drift_requires_retained_source_and_apply_still_checks_exact_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, work = self.workspace(root)
            (work / 'editable.csv').write_bytes(EDITED)
            source.write_bytes(SOURCE.replace(b'secret B', b'later B'))
            with self.assertRaisesRegex(sheet.Refused, 'Source changed since batch export'):
                batch.create_batch_proposal(source, work, root / 'proposal')
            self.assertFalse((root / 'proposal').exists())
            source.write_bytes(SOURCE)
            batch.create_batch_proposal(source, work, root / 'proposal')
            source.write_bytes(SOURCE + b'004,Dee,new,later\n')
            with self.assertRaisesRegex(sheet.Refused, 'Source changed'):
                sheet.apply_proposal(source, root / 'proposal', root / 'copy.csv')
            self.assertFalse((root / 'copy.csv').exists())

    def test_frozen_proposal_outlives_working_batch_and_existing_destination_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, work, proposal = self.proposal(root)
            (work / 'editable.csv').write_bytes(b'irrelevant later working edit')
            sheet.apply_proposal(source, proposal, root / 'copy.csv')
            before = (root / 'copy.csv').read_bytes()
            with self.assertRaises(FileExistsError):
                sheet.apply_proposal(source, proposal, root / 'copy.csv')
            self.assertEqual((root / 'copy.csv').read_bytes(), before)
            self.assertEqual(source.read_bytes(), SOURCE)

    def test_two_assigned_batches_combine_through_existing_merge_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, _, left = self.proposal(root, {**SCOPE,'row_keys':[['001']]}, b'id,name,status\n001,Ada,approved\n', 'left')
            _, _, right = self.proposal(root, {**SCOPE,'row_keys':[['003']]}, b'id,name,status\n003,Chen,ready\n', 'right')
            report = self.cli('export', source, left, right, root / 'merge', script='review_merge.py')
            self.assertEqual(report['counts'], {'left_only':1,'right_only':1,'agreed':0,'conflict':0})
            self.cli('prepare', source, left, right, root / 'merge', root / 'merged', script='review_merge.py')
            self.cli('apply', source, root / 'merged', root / 'copy.csv')
            self.assertEqual([row[2] for row in self.read_csv(root / 'copy.csv')[1:]], ['approved','unassigned status','ready'])

    def test_batch_proposal_supports_accept_reject_without_exporting_context_as_edit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, _, proposal = self.proposal(root)
            selection.export_decisions(source, proposal, root / 'choose')
            rows = sheet.parse((root / 'choose/decisions.csv').read_bytes(), 'csv')
            self.assertEqual([r[2] for r in rows[1:]], ['status','status'])
            rows[1][-1] = 'accept'; rows[2][-1] = 'reject'
            (root / 'choose/decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
            selection.select_proposal(source, proposal, root / 'choose', root / 'selected')
            sheet.apply_proposal(source, root / 'selected', root / 'copy.csv')
            self.assertEqual([r[2] for r in self.read_csv(root / 'copy.csv')[1:]], ['approved','unassigned status','open'])

    def test_newer_source_rebase_preserves_other_records_and_new_context(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, _, proposal = self.proposal(root)
            current = root / 'current.csv'
            current.write_bytes(SOURCE.replace(b'Ada', b'Adaline').replace(b'secret B', b'latest B') + b'004,Dee,new,private D\n')
            report = rebase.export_review(source, proposal, current, root / 'rebase')
            self.assertEqual(report['counts']['ready'], 2)
            rebase.prepare_rebase(source, proposal, current, root / 'rebase', root / 'rebased')
            sheet.apply_proposal(current, root / 'rebased', root / 'copy.csv')
            rows = self.read_csv(root / 'copy.csv')
            self.assertEqual(rows[1], ['001','Adaline','approved','secret A'])
            self.assertEqual(rows[2][-1], 'latest B')
            self.assertEqual(rows[-1], ['004','Dee','new','private D'])

    def test_checked_in_example_reproduces_expected_full_copy(self):
        sample = ROOT / 'docs/samples/review-batches'
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.cli('batch-export', 'csv', sample / 'source.csv', sample / 'selection.json', root / 'batch')
            (root / 'batch/editable.csv').write_bytes((sample / 'reviewed.csv').read_bytes())
            self.cli('batch-propose', sample / 'source.csv', root / 'batch', root / 'proposal')
            self.cli('apply', sample / 'source.csv', root / 'proposal', root / 'copy.csv')
            self.assertEqual(self.read_csv(root / 'copy.csv'), self.read_csv(sample / 'expected-copy.csv'))

    def test_proposal_change_budget_still_applies_to_batches(self):
        values = [['id','status']] + [[str(i),'old'] for i in range(1001)]
        raw = sheet.serialize(values, 'csv')
        scope = {'key_columns':['id'],'context_columns':[], 'edit_columns':['status'],
                 'row_keys':[[str(i)] for i in range(1001)]}
        manifest, _ = batch.prepare_batch(raw, 'csv', scope)
        edited = [values[0]] + [[row[0],'new'] for row in values[1:]]
        with self.assertRaisesRegex(sheet.Refused, '1000 changed cells'):
            batch.prepare_batch_proposal(raw, manifest, sheet.serialize(edited, 'csv'))
        edited[-1][-1] = 'old'
        result = batch.prepare_batch_proposal(raw, manifest, sheet.serialize(edited, 'csv'))
        self.assertEqual(result[0]['changed_cells'], 1000)


if __name__ == '__main__':
    unittest.main()
