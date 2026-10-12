#!/usr/bin/env python3
"""Choose which proposed CSV/TSV cell edits belong in a fresh MoonLeaf copy."""
import argparse
import csv
import json
from pathlib import Path
import sys

from review_sheet import (
    Refused, digest, encode, json_value, keyed_rows, parse, prepare_proposal,
    prepare_sheet, read_regular, serialize, write_new,
)

HEADERS = ['change_id', 'key_json', 'column', 'before', 'after', 'decision']
LIMITS = [
    'Accept/reject choices are local user annotations, not authenticated approval.',
    'Source keys and before/after values are private; review before sharing.',
    'Only changes already in the frozen proposal can be accepted; edit the original review sheet to propose other values.',
    'All cells remain literal text; no formula calculation, rendering or Office qualification.',
]


def read_proposal(source, directory):
    """Use the same exact recomputation boundary as review_sheet.apply."""
    directory = Path(directory)
    raw = read_regular(source)
    manifest = json_value(read_regular(directory / 'manifest.json'))
    edited = read_regular(directory / 'edited-sheet.txt')
    plan, recipe, _ = prepare_proposal(raw, manifest, edited)
    if json_value(read_regular(directory / 'plan.json')) != plan or read_regular(directory / 'corrections.json') != recipe:
        raise Refused('Proposal or recipe changed; prepare a fresh proposal')
    return raw, manifest, plan, recipe


def decision_rows(recipe):
    rows = [HEADERS]
    for number, edit in enumerate(json_value(recipe)['edits'], 1):
        rows.append([f'change-{number:04}', json.dumps(edit['key'], ensure_ascii=False, separators=(',', ':')),
                     edit['column'], edit['before']['value'], edit['after']['value'], ''])
    return rows


def selection_manifest(raw, plan, recipe):
    return {
        'format': 'moonleaf.review-selection.v1', 'source_sha256': digest(raw),
        'parent_plan_sha256': digest(encode(plan)), 'parent_recipe_sha256': digest(recipe),
        'changes': len(json_value(recipe)['edits']), 'diagnostics': LIMITS,
    }


def export_decisions(source, proposal, directory):
    raw, _, plan, recipe = read_proposal(source, proposal)
    manifest = selection_manifest(raw, plan, recipe)
    decisions = serialize(decision_rows(recipe), 'csv')
    # Same bounded parser as the actual import; a large recipe can exceed the
    # delimited review-sheet limit even when the proposal itself remains valid.
    parse(decisions, 'csv')
    if read_regular(source) != raw:
        raise Refused('Source changed during selection export')
    directory = Path(directory)
    directory.mkdir(mode=0o700)
    write_new(directory / 'manifest.json', encode(manifest))
    write_new(directory / 'decisions.csv', decisions)
    return {**manifest, 'next': 'Set every decision to accept or reject, then select into a new proposal directory.'}


def select_proposal(source, proposal, selection, destination):
    raw, manifest, parent_plan, recipe = read_proposal(source, proposal)
    selection, destination = Path(selection), Path(destination)
    expected = selection_manifest(raw, parent_plan, recipe)
    if json_value(read_regular(selection / 'manifest.json')) != expected:
        raise Refused('Selection belongs to a different source or proposal; export a fresh decision sheet')
    decisions_raw = read_regular(selection / 'decisions.csv')
    decisions = parse(decisions_raw, 'csv')
    if set(decisions[0]) != set(HEADERS):
        raise Refused('Decision sheet must keep every original column')
    by_id = keyed_rows(decisions, ['change_id'], 'Decision sheet')
    original = decision_rows(recipe)
    if set(by_id) != {(row[0],) for row in original[1:]}:
        raise Refused('Decision sheet must keep every original change exactly once')
    indexes = [decisions[0].index(column) for column in HEADERS]
    accepted = []
    choices = []
    for number, expected_row in enumerate(original[1:]):
        row = [by_id[(expected_row[0],)][index] for index in indexes]
        if row[:-1] != expected_row[:-1]:
            raise Refused(f'{expected_row[0]}: keep the original key, column and before/after values; edit only decision')
        if row[-1] not in ('accept', 'reject'):
            raise Refused(f'{expected_row[0]}: decision must be exactly accept or reject; no pending choices can be applied')
        if row[-1] == 'accept':
            accepted.append(number)
        choices.append({'change_id': row[0], 'decision': row[-1]})
    _, baseline = prepare_sheet(raw, parent_plan['input_format'], manifest['selection'])
    rows = parse(baseline, parent_plan['input_format'])
    keyed = keyed_rows(rows, manifest['selection']['key_columns'], 'Source')
    edits = json_value(recipe)['edits']
    for index in accepted:
        edit = edits[index]
        keyed[tuple(edit['key'])][rows[0].index(edit['column'])] = edit['after']['value']
    # Re-enter the existing proposal boundary. No separate application semantics.
    edited = serialize(rows, parent_plan['input_format'])
    selected = prepare_proposal(raw, manifest, edited) if accepted else None
    if read_regular(source) != raw:
        raise Refused('Source changed during selection; export and review again')
    receipt = {
        'format': 'moonleaf.review-selection-result.v1',
        'source_sha256': digest(raw), 'parent_plan_sha256': expected['parent_plan_sha256'],
        'parent_recipe_sha256': digest(recipe), 'decision_sheet_sha256': digest(decisions_raw),
        'accepted_cells': len(accepted), 'rejected_cells': len(choices) - len(accepted),
        'result': 'proposal_created' if selected else 'all_rejected_no_copy_needed',
        'selected_recipe_sha256': digest(selected[1]) if selected else None,
        'choices': choices, 'diagnostics': LIMITS,
    }
    destination.mkdir(mode=0o700)
    write_new(destination / 'selection.json', encode(receipt))
    write_new(destination / 'decisions.csv', decisions_raw)
    if selected:
        plan, selected_recipe, _ = selected
        write_new(destination / 'manifest.json', encode(manifest))
        write_new(destination / 'edited-sheet.txt', edited)
        write_new(destination / 'corrections.json', selected_recipe)
        write_new(destination / 'plan.json', encode(plan))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    export = commands.add_parser('export', help='Export exact proposed changes with blank accept/reject choices')
    export.add_argument('source'); export.add_argument('proposal'); export.add_argument('directory')
    select = commands.add_parser('select', help='Freeze chosen edits as a new proposal for review_sheet.py apply')
    select.add_argument('source'); select.add_argument('proposal'); select.add_argument('selection'); select.add_argument('destination')
    args = parser.parse_args()
    try:
        result = (export_decisions(args.source, args.proposal, args.directory) if args.command == 'export'
                  else select_proposal(args.source, args.proposal, args.selection, args.destination))
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (ValueError, OSError, UnicodeError, csv.Error) as error:
        print('MoonLeaf review selection refused: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
