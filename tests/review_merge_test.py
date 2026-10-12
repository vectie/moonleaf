"""Independent review proposals converge into the existing verified-copy lane."""
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
import review_merge as merge
import review_selection as selection

SOURCE = b'id,name,status,region,private\n001,Ada,pending,east,retain A\n002,Bo,open,east,retain B\n003,Chen,open,north,retain C\n'
LEFT = b'id,name,status\n001,"Ada, A.",approved\n002,Bo,ready\n003,Chen,open\n'
RIGHT = b'region,status,id\nnorth,open,003\neast,held,002\neast,approved,001\n'.replace(b'north,open,003', b'west,open,003')
LEFT_SCOPE = {'key_columns': ['id'], 'edit_columns': ['name', 'status']}
RIGHT_SCOPE = {'key_columns': ['id'], 'edit_columns': ['status', 'region']}


class ReviewMerge(unittest.TestCase):
    def cli(self, script, *args, success=True):
        proc = subprocess.run([sys.executable, '-B', str(ROOT / 'tools' / script), *map(str, args)], capture_output=True)
        if success:
            self.assertEqual(proc.returncode, 0, proc.stderr.decode())
            return json.loads(proc.stdout)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, b'')
        return proc.stderr.decode()

    def proposal(self, root, source, side, scope, edited, fmt='csv', cli=False):
        spec = root / (side + '-scope.json'); spec.write_bytes(sheet.encode(scope))
        work, proposal = root / (side + '-sheet'), root / side
        if cli:
            self.cli('review_sheet.py', 'export', fmt, source, spec, work)
        else:
            sheet.create_sheet(source, fmt, spec, work)
        (work / ('editable.' + fmt)).write_bytes(edited)
        if cli:
            self.cli('review_sheet.py', 'propose', source, work, proposal)
        else:
            sheet.create_proposal(source, work, proposal)
        return proposal

    def setup(self, root, cli=False):
        source = root / 'source.csv'; source.write_bytes(SOURCE)
        left = self.proposal(root, source, 'left', LEFT_SCOPE, LEFT, cli=cli)
        right = self.proposal(root, source, 'right', RIGHT_SCOPE, RIGHT, cli=cli)
        review = root / 'review'
        report = (self.cli('review_merge.py', 'export', source, left, right, review) if cli
                  else merge.export_review(source, left, right, review))
        self.assertEqual(report['counts'], {'left_only': 1, 'right_only': 1, 'agreed': 1, 'conflict': 1})
        return source, left, right, review

    def choose(self, review, conflict='right', all_original=False):
        rows = sheet.parse((review / 'decisions.csv').read_bytes(), 'csv')
        for row in rows[1:]:
            if all_original or row[-2] == 'conflict':
                row[-1] = 'original' if all_original else conflict
        (review / 'decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
        return rows

    def read_csv(self, path, fmt='csv'):
        with path.open(encoding='utf-8', newline='') as handle:
            return list(csv.reader(handle, delimiter=',' if fmt == 'csv' else '\t'))

    def test_complete_cli_merges_scopes_and_applies_one_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, right, review = self.setup(root, cli=True)
            self.choose(review)
            result = self.cli('review_merge.py', 'prepare', source, left, right, review, root / 'merged')
            receipt = self.cli('review_sheet.py', 'apply', source, root / 'merged', root / 'copy.csv')
            expected = [['id','name','status','region','private'], ['001','Ada, A.','approved','east','retain A'],
                        ['002','Bo','held','east','retain B'], ['003','Chen','open','west','retain C']]
            self.assertEqual(self.read_csv(root / 'copy.csv'), expected)
            self.assertEqual(result['changed_cells'], 4)
            self.assertEqual(result['merged_recipe_sha256'], receipt['recipe_sha256'])
            self.assertTrue(receipt['text_values_reopened']); self.assertFalse(receipt['render_verified'])
            # Separate simple consumer verifies compatibility with the existing
            # correction format rather than relying only on the shared writer.
            original = self.read_csv(source)
            recipe = json.loads((root / 'merged/corrections.json').read_bytes())
            for edit in recipe['edits']:
                indexes = [original[0].index(k) for k in recipe['key_columns']]
                row, = [row for row in original[1:] if [row[i] for i in indexes] == edit['key']]
                column = original[0].index(edit['column'])
                self.assertEqual(row[column], edit['before']['value'])
                row[column] = edit['after']['value']
            self.assertEqual(original, expected)
            self.assertEqual(source.read_bytes(), SOURCE)
            self.assertEqual((root / 'merged').stat().st_mode & 0o777, 0o700)
            self.assertEqual((root / 'merged/merge.json').stat().st_mode & 0o777, 0o600)

    def test_only_true_disagreement_needs_choice_then_original_can_preserve_cell(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, right, review = self.setup(root)
            error = self.cli('review_merge.py', 'prepare', source, left, right, review, root / 'merged', success=False)
            self.assertIn('no pending choices', error); self.assertFalse((root / 'merged').exists())
            rows = self.choose(review, 'original')
            self.assertEqual([row[-1] for row in rows[1:]], ['left','left','original','right'])
            result = merge.prepare_merge(source, left, right, review, root / 'merged')
            self.assertEqual(result['changed_cells'], 3)
            sheet.apply_proposal(source, root / 'merged', root / 'copy.csv')
            self.assertEqual(self.read_csv(root / 'copy.csv')[2][2], 'open')

    def test_disjoint_changes_need_no_manual_choices(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'source.csv'; source.write_bytes(SOURCE)
            left = self.proposal(root, source, 'left', {'key_columns':['id'],'edit_columns':['name']}, b'id,name\n001,Ada A\n002,Bo\n003,Chen\n')
            right = self.proposal(root, source, 'right', {'key_columns':['id'],'edit_columns':['region']}, b'id,region\n001,east\n002,east\n003,west\n')
            report = merge.export_review(source, left, right, root / 'review')
            self.assertEqual(report['counts']['conflict'], 0)
            result = merge.prepare_merge(source, left, right, root / 'review', root / 'merged')
            self.assertEqual(result['changed_cells'], 2)
            sheet.apply_proposal(source, root / 'merged', root / 'copy.csv')
            self.assertEqual(self.read_csv(root / 'copy.csv')[3][3], 'west')

    def test_same_proposal_deduplicates_agreed_cells(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, _, _ = self.setup(root)
            report = merge.export_review(source, left, left, root / 'same-review')
            self.assertEqual(report['counts'], {'left_only':0,'right_only':0,'agreed':3,'conflict':0})
            merge.prepare_merge(source, left, left, root / 'same-review', root / 'merged')
            self.assertEqual((root / 'merged/corrections.json').read_bytes(), (left / 'corrections.json').read_bytes())

    def test_reordered_decision_rows_and_columns_keep_identity_and_left_choice(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, right, review = self.setup(root)
            rows = self.choose(review, 'left')
            rows = [rows[0]] + rows[:0:-1]
            order = list(reversed(range(len(rows[0]))))
            (review / 'decisions.csv').write_bytes(sheet.serialize([[row[i] for i in order] for row in rows], 'csv'))
            merge.prepare_merge(source, left, right, review, root / 'merged')
            sheet.apply_proposal(source, root / 'merged', root / 'copy.csv')
            self.assertEqual(self.read_csv(root / 'copy.csv')[2][2], 'ready')

    def test_tsv_composite_keys_empty_proposal_and_unicode_are_literal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            values = [['project','line','note','hidden'], ['001','a','東京 😀','x'], ['001','b','old\tnote','y']]
            source = root / 'source.tsv'; source.write_bytes(sheet.serialize(values, 'tsv'))
            scope = {'key_columns':['project','line'], 'edit_columns':['note']}
            left = self.proposal(root, source, 'left', scope, sheet.serialize([['project','line','note'], ['001','a',''],['001','b','old\tnote']], 'tsv'), 'tsv')
            right = self.proposal(root, source, 'right', scope, sheet.serialize([['note','line','project'], ['別\n行','b','001'],['東京 😀','a','001']], 'tsv'), 'tsv')
            merge.export_review(source, left, right, root / 'review')
            rows = sheet.parse((root / 'review/decisions.csv').read_bytes(), 'csv')
            self.assertEqual(rows[1][4:8], ['yes','','no',''])
            merge.prepare_merge(source, left, right, root / 'review', root / 'merged')
            sheet.apply_proposal(source, root / 'merged', root / 'copy.tsv')
            values[1][2] = ''; values[2][2] = '別\n行'
            self.assertEqual(self.read_csv(root / 'copy.tsv', 'tsv'), values)

    def test_keep_all_original_records_no_copy_needed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, right, review = self.setup(root)
            self.choose(review, all_original=True)
            result = merge.prepare_merge(source, left, right, review, root / 'merged')
            self.assertEqual(result['result'], 'no_changes_no_copy_needed')
            self.assertEqual(result['changed_cells'], 0); self.assertIsNone(result['merged_recipe_sha256'])
            self.assertEqual({p.name for p in (root / 'merged').iterdir()}, {'merge.json','decisions.csv'})

    def test_proposals_from_different_source_snapshots_refuse(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, _, _ = self.setup(root)
            newer = root / 'newer.csv'; newer.write_bytes(SOURCE.replace(b'retain C', b'new private'))
            right = self.proposal(root, newer, 'newer-right', RIGHT_SCOPE, RIGHT)
            with self.assertRaisesRegex(sheet.Refused, 'Source changed'):
                merge.export_review(source, left, right, root / 'wrong')
            self.assertFalse((root / 'wrong').exists())

    def test_different_row_identity_contract_cannot_be_silently_merged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, _, _ = self.setup(root)
            other = self.proposal(root, source, 'other', {'key_columns':['id','region'],'edit_columns':['status']}, b'id,region,status\n001,east,approved\n002,east,open\n003,north,open\n')
            with self.assertRaisesRegex(sheet.Refused, 'ordered key columns'):
                merge.export_review(source, left, other, root / 'wrong')

    def test_frozen_parents_and_decisions_remain_bound(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, right, review = self.setup(root)
            rows = self.choose(review)
            rows[1][5] = 'not a proposed value'
            (review / 'decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
            with self.assertRaisesRegex(sheet.Refused, 'edit only decision'):
                merge.prepare_merge(source, left, right, review, root / 'wrong')
            merge.export_review(source, left, right, root / 'fresh')
            self.choose(root / 'fresh')
            # Unfrozen working-sheet edits have no effect on these parents.
            (root / 'left-sheet/editable.csv').write_bytes(b'not used')
            merge.prepare_merge(source, left, right, root / 'fresh', root / 'merged')
            with self.assertRaisesRegex(sheet.Refused, 'ordered parent proposals'):
                merge.prepare_merge(source, right, left, root / 'fresh', root / 'swapped')

    def test_existing_apply_keeps_drift_destination_and_selective_review_checks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source, left, right, review = self.setup(root)
            self.choose(review); merge.prepare_merge(source, left, right, review, root / 'merged')
            selection.export_decisions(source, root / 'merged', root / 'selection')
            rows = sheet.parse((root / 'selection/decisions.csv').read_bytes(), 'csv')
            for row in rows[1:]: row[-1] = 'accept' if row[2] == 'region' else 'reject'
            (root / 'selection/decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
            selection.select_proposal(source, root / 'merged', root / 'selection', root / 'selected')
            source.write_bytes(SOURCE.replace(b'retain B', b'later'))
            with self.assertRaisesRegex(sheet.Refused, 'Source changed'):
                sheet.apply_proposal(source, root / 'selected', root / 'copy.csv')
            source.write_bytes(SOURCE)
            sheet.apply_proposal(source, root / 'selected', root / 'copy.csv')
            with self.assertRaises(FileExistsError):
                sheet.apply_proposal(source, root / 'selected', root / 'copy.csv')
            expected = self.read_csv(source); expected[3][3] = 'west'
            self.assertEqual(self.read_csv(root / 'copy.csv'), expected)

    def test_union_edit_budget_can_be_reduced_before_ordinary_prepare(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'source.csv'
            source.write_bytes(sheet.serialize([['id','value']] + [[str(i),'old'] for i in range(1001)], 'csv'))
            scope = {'key_columns':['id'],'edit_columns':['value']}
            left = self.proposal(root, source, 'left', scope, sheet.serialize([['id','value']] + [[str(i),'L' if i < 500 else 'old'] for i in range(1001)], 'csv'))
            right = self.proposal(root, source, 'right', scope, sheet.serialize([['id','value']] + [[str(i),'R' if i >= 500 else 'old'] for i in range(1001)], 'csv'))
            merge.export_review(source, left, right, root / 'review')
            with self.assertRaisesRegex(sheet.Refused, '1000 changed cells'):
                merge.prepare_merge(source, left, right, root / 'review', root / 'too-many')
            self.assertFalse((root / 'too-many').exists())
            rows = sheet.parse((root / 'review/decisions.csv').read_bytes(), 'csv'); rows[-1][-1] = 'original'
            (root / 'review/decisions.csv').write_bytes(sheet.serialize(rows, 'csv'))
            result = merge.prepare_merge(source, left, right, root / 'review', root / 'merged')
            self.assertEqual(result['changed_cells'], 1000)
            sheet.apply_proposal(source, root / 'merged', root / 'copy.csv')
            self.assertEqual(self.read_csv(root / 'copy.csv')[-1], ['1000','old'])


if __name__ == '__main__':
    unittest.main()
