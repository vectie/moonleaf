#!/usr/bin/env python3
"""Review older CSV/TSV corrections against a newer source, then prepare a fresh proposal."""
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

HEADERS = ['change_id', 'key_json', 'column', 'original', 'reviewed', 'current', 'status', 'decision']
LIMITS = [
    'Exact caller-chosen keys identify rows; renamed keys appear missing and are never guessed or resurrected.',
    'Conflicts require an explicit local keep-current or use-reviewed decision; missing rows can only be kept absent.',
    'Original and current snapshots, proposals and decision sheets contain private values; sharing belongs to the host.',
    'Hashes and local decisions do not authenticate a reviewer, authorize an overwrite or record customer acceptance.',
    'All values are text; formula-looking strings may execute in external spreadsheet applications.',
    'Only the existing Python text-value copy readback is qualified; no MoonBit session, rendering or host linkage.',
]


def inspect_changes(original, manifest, parent_plan, recipe, current):
    """Classify each already-frozen correction against exact current cell values."""
    fmt = parent_plan['input_format']
    current_manifest, baseline = prepare_sheet(current, fmt, manifest['selection'])
    rows = parse(baseline, fmt)
    keys = manifest['selection']['key_columns']
    indexed = keyed_rows(rows, keys, 'Current source')
    decisions = [HEADERS]
    counts = dict.fromkeys(['ready', 'already_applied', 'conflict', 'missing_row'], 0)
    for number, edit in enumerate(json_value(recipe)['edits'], 1):
        row = indexed.get(tuple(edit['key']))
        before, after = edit['before']['value'], edit['after']['value']
        value = row[rows[0].index(edit['column'])] if row is not None else ''
        if row is None:
            status, choice = 'missing_row', ''
        elif value == before:
            status, choice = 'ready', 'use-reviewed'
        elif value == after:
            status, choice = 'already_applied', 'keep-current'
        else:
            status, choice = 'conflict', ''
        counts[status] += 1
        decisions.append([f'change-{number:04}', json.dumps(edit['key'], ensure_ascii=False, separators=(',', ':')),
                          edit['column'], before, after, value, status, choice])
    review = {
        'format': 'moonleaf.review-rebase.v1', 'input_format': fmt,
        'original_sha256': digest(original), 'current_sha256': digest(current),
        'parent_plan_sha256': digest(encode(parent_plan)), 'parent_recipe_sha256': digest(recipe),
        'current_manifest_sha256': digest(encode(current_manifest)),
        'changes': len(decisions) - 1, 'counts': counts, 'diagnostics': LIMITS,
    }
    # Repeated before/current/after values can exceed the original sheet limit.
    # Ensure the review can be reopened before publishing any workspace.
    parse(serialize(decisions, 'csv'), 'csv')
    return review, decisions, current_manifest, rows


def read_inputs(original_path, proposal, current_path):
    original, manifest, parent_plan, recipe = read_proposal(original_path, proposal)
    current = read_regular(current_path)
    inspected = inspect_changes(original, manifest, parent_plan, recipe, current)
    return original, current, inspected


def stable_inputs(original_path, original, current_path, current):
    if read_regular(original_path) != original or read_regular(current_path) != current:
        raise Refused('Original or current source changed during review; export a fresh rebase review')


def export_review(original_path, proposal, current_path, directory):
    original, current, (review, decisions, _, _) = read_inputs(original_path, proposal, current_path)
    stable_inputs(original_path, original, current_path, current)
    directory = Path(directory)
    directory.mkdir(mode=0o700)
    write_new(directory / 'manifest.json', encode(review))
    write_new(directory / 'decisions.csv', serialize(decisions, 'csv'))
    return {**review, 'next': 'Inspect decisions.csv; resolve every blank choice, then prepare a new proposal.'}


def resolve_choices(raw, expected):
    rows = parse(raw, 'csv')
    if set(rows[0]) != set(HEADERS):
        raise Refused('Decision sheet must retain exactly the original columns')
    indexed = keyed_rows(rows, ['change_id'], 'Rebase decision sheet')
    if set(indexed) != {(row[0],) for row in expected[1:]}:
        raise Refused('Decision sheet must keep every original change exactly once')
    positions = [rows[0].index(name) for name in HEADERS]
    choices = []
    for expected_row in expected[1:]:
        row = [indexed[(expected_row[0],)][index] for index in positions]
        if row[:-1] != expected_row[:-1]:
            raise Refused(f'{expected_row[0]}: original, reviewed, current, key, column and status must stay exact; edit only decision')
        if row[-1] not in ('keep-current', 'use-reviewed'):
            raise Refused(f'{row[0]}: choose exactly keep-current or use-reviewed; no pending choices can proceed')
        if row[-2] == 'missing_row' and row[-1] != 'keep-current':
            raise Refused(f'{row[0]}: missing row can only use keep-current; rows are not resurrected')
        choices.append(row[-1])
    return choices


def prepare_rebase(original_path, proposal, current_path, workspace, destination):
    original, current, (review, expected, manifest, rows) = read_inputs(original_path, proposal, current_path)
    workspace, destination = Path(workspace), Path(destination)
    if json_value(read_regular(workspace / 'manifest.json')) != review:
        raise Refused('Rebase review no longer matches current source or parent proposal; export a fresh review')
    decisions_raw = read_regular(workspace / 'decisions.csv')
    choices = resolve_choices(decisions_raw, expected)
    indexed = keyed_rows(rows, manifest['selection']['key_columns'], 'Current source')
    changed = 0
    records = []
    for row, choice in zip(expected[1:], choices):
        if choice == 'use-reviewed':
            target = indexed[tuple(json.loads(row[1]))]
            column = rows[0].index(row[2])
            changed += target[column] != row[4]
            target[column] = row[4]
        records.append({'change_id': row[0], 'status': row[-2], 'decision': choice})
    edited = serialize(rows, review['input_format'])
    # Preserve existing apply semantics. Its recipe's before-values are CURRENT,
    # including the explicit replacement of a conflicted current value.
    selected = prepare_proposal(current, manifest, edited) if changed else None
    stable_inputs(original_path, original, current_path, current)
    receipt = {
        'format': 'moonleaf.review-rebase-result.v1',
        'original_sha256': review['original_sha256'], 'current_sha256': review['current_sha256'],
        'parent_plan_sha256': review['parent_plan_sha256'], 'parent_recipe_sha256': review['parent_recipe_sha256'],
        'review_manifest_sha256': digest(encode(review)), 'decision_sheet_sha256': digest(decisions_raw),
        'classification_counts': review['counts'], 'changed_cells': changed,
        'use_reviewed_choices': choices.count('use-reviewed'), 'keep_current_choices': choices.count('keep-current'),
        'result': 'proposal_created' if selected else 'no_changes_no_copy_needed',
        'rebased_recipe_sha256': digest(selected[1]) if selected else None,
        'choices': records, 'diagnostics': LIMITS,
    }
    destination.mkdir(mode=0o700)
    write_new(destination / 'rebase.json', encode(receipt))
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
    export = commands.add_parser('export', help='Compare a frozen original proposal with a current CSV/TSV snapshot')
    prepare = commands.add_parser('prepare', help='Resolve exact choices into the existing current-source-bound proposal')
    for command in (export, prepare):
        command.add_argument('original'); command.add_argument('proposal'); command.add_argument('current')
    export.add_argument('directory')
    prepare.add_argument('workspace'); prepare.add_argument('destination')
    args = parser.parse_args()
    try:
        result = (export_review(args.original, args.proposal, args.current, args.directory) if args.command == 'export'
                  else prepare_rebase(args.original, args.proposal, args.current, args.workspace, args.destination))
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (ValueError, OSError, UnicodeError, csv.Error) as error:
        print('MoonLeaf review rebase refused: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
