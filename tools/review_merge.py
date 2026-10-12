#!/usr/bin/env python3
"""Combine two frozen CSV/TSV review proposals with explicit conflicting-cell choices."""
import argparse
import csv
import json
from pathlib import Path
import sys

from review_selection import read_proposal
from review_sheet import (
    Refused, digest, encode, json_value, keyed_rows, parse, prepare_proposal,
    prepare_sheet, read_regular, serialize, write_new,
)

HEADERS = ['change_id', 'key_json', 'column', 'original', 'left_present', 'left',
           'right_present', 'right', 'status', 'decision']
LIMITS = [
    'Two local proposals must bind the same exact source bytes, delimiter and ordered key columns.',
    'Only conflicting proposed values require a new decision; other changes default to their proposed value.',
    'Local decisions and hashes do not authenticate reviewers or authorize sharing, delivery or acceptance.',
    'Source, review sheets and merged proposals contain private values; access and sharing belong to the host.',
    'All cells remain literal text; formula-looking strings may execute in external spreadsheet applications.',
    'Existing Python copy readback only; no document-session, render, Office or host-linkage qualification.',
]


def read_inputs(source, left, right):
    raw, lm, lp, lr = read_proposal(source, left)
    right_raw, rm, rp, rr = read_proposal(source, right)
    if right_raw != raw:
        raise Refused('Source changed while reading proposals; retry with one retained snapshot')
    if lm['input_format'] != rm['input_format'] or lm['selection']['key_columns'] != rm['selection']['key_columns']:
        raise Refused('Proposals must use the same delimiter and ordered key columns')
    keys = lm['selection']['key_columns']
    source_rows = parse(raw, lm['input_format'])
    editable = set(lm['selection']['edit_columns']) | set(rm['selection']['edit_columns'])
    # Source order makes the merged recipe deterministic even when the inputs
    # were reviewed with different column orders or different editable scopes.
    scope = {'key_columns': keys, 'edit_columns': [c for c in source_rows[0] if c in editable]}
    manifest, baseline = prepare_sheet(raw, lm['input_format'], scope)
    changes = []
    for recipe in (lr, rr):
        changes.append({(tuple(edit['key']), edit['column']): edit for edit in json_value(recipe)['edits']})
    expected = [HEADERS]
    counts = dict.fromkeys(['left_only', 'right_only', 'agreed', 'conflict'], 0)
    for key, row in keyed_rows(source_rows, keys, 'Source').items():
        for column in scope['edit_columns']:
            a, b = (side.get((key, column)) for side in changes)
            if a is None and b is None:
                continue
            av = a['after']['value'] if a is not None else ''
            bv = b['after']['value'] if b is not None else ''
            if a is None:
                status, choice = 'right_only', 'right'
            elif b is None:
                status, choice = 'left_only', 'left'
            elif av == bv:
                status, choice = 'agreed', 'left'
            else:
                status, choice = 'conflict', ''
            counts[status] += 1
            expected.append([f'change-{len(expected):04}', json.dumps(list(key), ensure_ascii=False, separators=(',', ':')),
                             column, row[source_rows[0].index(column)], 'yes' if a is not None else 'no', av,
                             'yes' if b is not None else 'no', bv, status, choice])
    review = {
        'format': 'moonleaf.review-merge.v1', 'input_format': lm['input_format'],
        'source_sha256': digest(raw), 'key_columns': keys,
        'left_plan_sha256': digest(encode(lp)), 'left_recipe_sha256': digest(lr),
        'right_plan_sha256': digest(encode(rp)), 'right_recipe_sha256': digest(rr),
        'merged_manifest_sha256': digest(encode(manifest)),
        'changes': len(expected) - 1, 'counts': counts, 'diagnostics': LIMITS,
    }
    # Check that repeated values fit the same delimited boundary before writes.
    parse(serialize(expected, 'csv'), 'csv')
    return raw, review, expected, manifest, parse(baseline, lm['input_format'])


def export_review(source, left, right, directory):
    raw, review, expected, _, _ = read_inputs(source, left, right)
    if read_regular(source) != raw:
        raise Refused('Source changed during merge export')
    directory = Path(directory)
    directory.mkdir(mode=0o700)
    write_new(directory / 'manifest.json', encode(review))
    write_new(directory / 'decisions.csv', serialize(expected, 'csv'))
    return {**review, 'next': 'Inspect decisions.csv; choose left, right or original for every conflict, then prepare.'}


def resolve_choices(raw, expected):
    rows = parse(raw, 'csv')
    if set(rows[0]) != set(HEADERS):
        raise Refused('Decision sheet must retain exactly the original columns')
    indexed = keyed_rows(rows, ['change_id'], 'Merge decision sheet')
    if set(indexed) != {(row[0],) for row in expected[1:]}:
        raise Refused('Decision sheet must keep every original change exactly once')
    positions = [rows[0].index(name) for name in HEADERS]
    choices = []
    for original in expected[1:]:
        row = [indexed[(original[0],)][i] for i in positions]
        if row[:-1] != original[:-1]:
            raise Refused(f'{original[0]}: keep keys, values, presence and status exact; edit only decision')
        choice = row[-1]
        if choice not in ('left', 'right', 'original'):
            raise Refused(f'{row[0]}: choose left, right or original; no pending choices can proceed')
        if (choice == 'left' and row[4] != 'yes') or (choice == 'right' and row[6] != 'yes'):
            raise Refused(f'{row[0]}: chosen side has no proposed change; choose original to keep source text')
        choices.append(choice)
    return choices


def prepare_merge(source, left, right, workspace, destination):
    raw, review, expected, manifest, rows = read_inputs(source, left, right)
    workspace, destination = Path(workspace), Path(destination)
    if json_value(read_regular(workspace / 'manifest.json')) != review:
        raise Refused('Merge review no longer matches these ordered parent proposals; export a fresh review')
    decisions_raw = read_regular(workspace / 'decisions.csv')
    choices = resolve_choices(decisions_raw, expected)
    indexed = keyed_rows(rows, manifest['selection']['key_columns'], 'Source')
    records, changed = [], 0
    for row, choice in zip(expected[1:], choices):
        if choice != 'original':
            indexed[tuple(json.loads(row[1]))][rows[0].index(row[2])] = row[5 if choice == 'left' else 7]
            changed += 1
        records.append({'change_id': row[0], 'status': row[-2], 'decision': choice})
    edited = serialize(rows, review['input_format'])
    # Re-enter the unchanged source-bound proposal and application workflow.
    selected = prepare_proposal(raw, manifest, edited) if changed else None
    if read_regular(source) != raw:
        raise Refused('Source changed during merge; export a fresh review')
    receipt = {
        'format': 'moonleaf.review-merge-result.v1', 'source_sha256': digest(raw),
        **{key: review[key] for key in ('left_plan_sha256', 'left_recipe_sha256', 'right_plan_sha256', 'right_recipe_sha256')},
        'review_manifest_sha256': digest(encode(review)), 'decision_sheet_sha256': digest(decisions_raw),
        'classification_counts': review['counts'], 'changed_cells': changed,
        'kept_original_cells': choices.count('original'),
        'result': 'proposal_created' if selected else 'no_changes_no_copy_needed',
        'merged_recipe_sha256': digest(selected[1]) if selected else None,
        'choices': records, 'diagnostics': LIMITS,
    }
    destination.mkdir(mode=0o700)
    write_new(destination / 'merge.json', encode(receipt))
    write_new(destination / 'decisions.csv', decisions_raw)
    if selected:
        plan, recipe, _ = selected
        write_new(destination / 'manifest.json', encode(manifest))
        write_new(destination / 'edited-sheet.txt', edited)
        write_new(destination / 'corrections.json', recipe)
        write_new(destination / 'plan.json', encode(plan))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    export = commands.add_parser('export', help='Inspect the union of two frozen proposals against one source')
    prepare = commands.add_parser('prepare', help='Freeze resolved changes as an ordinary review-sheet proposal')
    for command in (export, prepare):
        command.add_argument('source'); command.add_argument('left'); command.add_argument('right')
    export.add_argument('directory')
    prepare.add_argument('workspace'); prepare.add_argument('destination')
    args = parser.parse_args()
    try:
        result = (export_review(args.source, args.left, args.right, args.directory) if args.command == 'export'
                  else prepare_merge(args.source, args.left, args.right, args.workspace, args.destination))
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (ValueError, OSError, UnicodeError, csv.Error) as error:
        print('MoonLeaf review merge refused: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
