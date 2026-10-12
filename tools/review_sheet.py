#!/usr/bin/env python3
"""Round-trip a scoped CSV/TSV review sheet into exact MoonLeaf corrections."""
import argparse
import csv
import io
import json
from pathlib import Path
import sys

from pseudonymize import (
    MAX_BYTES, Refused, digest, encode, json_value, parse, read_regular,
    require_fields, serialize, units, write_new,
)

LIMITS = [
    'All cells are literal text; no type inference, formula calculation or spreadsheet formatting.',
    'Review keys identify source rows; do not edit keys, add rows, remove rows or change the selected column set.',
    'Sheets, recipes and plans contain private source values; sharing remains the host responsibility.',
    'Hashes bind local snapshots; they do not authenticate a reviewer or record approval.',
    'Formula-looking strings may execute when opened in external spreadsheet applications.',
    'Text-value readback only; no MoonBit document-session, render, Office fidelity or delivery qualification.',
]


def column_names(value, label, maximum):
    if (not isinstance(value, list) or not 1 <= len(value) <= maximum
            or any(not isinstance(name, str) or not name or units(name) > 4096 for name in value)
            or len(set(value)) != len(value)):
        raise Refused(f'{label} must contain 1–{maximum} distinct nonempty column names up to 4096 units')
    return value


def keyed_rows(rows, keys, label):
    indexes = [rows[0].index(key) for key in keys]
    result = {}
    for row_number, row in enumerate(rows[1:], 1):
        key = tuple(row[index] for index in indexes)
        if any(not value or units(value) > 4096 for value in key):
            raise Refused(f'{label} row {row_number}: keys must be nonempty text up to 4096 units')
        if key in result:
            raise Refused(f'{label} row {row_number}: duplicate stable key')
        result[key] = row
    return result


def prepare_sheet(raw, fmt, selection):
    """Pure export: preserve all rows but expose only keys and chosen edit columns."""
    rows = parse(raw, fmt)
    require_fields(selection, ['key_columns', 'edit_columns'])
    keys = column_names(selection['key_columns'], 'key_columns', 32)
    editable = column_names(selection['edit_columns'], 'edit_columns', 128)
    if set(keys) & set(editable):
        raise Refused('Key columns cannot be editable')
    selected = keys + editable
    if any(name not in rows[0] for name in selected):
        raise Refused('Unknown selected column')
    keyed_rows(rows, keys, 'Source')
    indexes = [rows[0].index(name) for name in selected]
    sheet = serialize([[row[index] for index in indexes] for row in rows], fmt)
    # Projection can expand quoting, so the exported sheet must itself reopen.
    parse(sheet, fmt)
    manifest = {
        'format': 'moonleaf.review-sheet.v1', 'input_format': fmt,
        'source_sha256': digest(raw), 'baseline_sheet_sha256': digest(sheet),
        'selection': selection, 'source_columns': rows[0], 'rows': len(rows) - 1,
        'diagnostics': LIMITS,
    }
    return manifest, sheet


def prepare_proposal(raw, manifest, edited):
    """Diff by exact stable key; return the existing correction recipe and copy."""
    if not isinstance(manifest, dict) or manifest.get('format') != 'moonleaf.review-sheet.v1':
        raise Refused('Unsupported review-sheet manifest')
    if digest(raw) != manifest.get('source_sha256'):
        raise Refused('Source changed since sheet export; export and review a new sheet')
    fmt = manifest.get('input_format')
    expected, _ = prepare_sheet(raw, fmt, manifest.get('selection'))
    if manifest != expected:
        raise Refused('Review-sheet manifest does not match source and selection')
    rows, reviewed = parse(raw, fmt), parse(edited, fmt)
    keys = manifest['selection']['key_columns']
    editable = manifest['selection']['edit_columns']
    if set(reviewed[0]) != set(keys + editable):
        raise Refused('Edited sheet must retain exactly the selected key and editable columns')
    source_index = keyed_rows(rows, keys, 'Source')
    edited_index = keyed_rows(reviewed, keys, 'Edited sheet')
    missing, added = source_index.keys() - edited_index.keys(), edited_index.keys() - source_index.keys()
    if missing or added:
        raise Refused(f'Stable-key mismatch: {len(missing)} missing and {len(added)} unknown rows; restore keys and row membership')
    source_columns = {name: rows[0].index(name) for name in editable}
    edited_columns = {name: reviewed[0].index(name) for name in editable}
    output = [row.copy() for row in rows]
    edits, changed_rows = [], 0
    for source_row, (key, row) in enumerate(source_index.items(), 1):
        row_changed = False
        for column in editable:
            before = row[source_columns[column]]
            after = edited_index[key][edited_columns[column]]
            if before == after:
                continue
            edits.append({'key': list(key), 'column': column,
                          'before': {'type': 'text', 'value': before},
                          'after': {'type': 'text', 'value': after}})
            if len(edits) > 1000:
                raise Refused('Existing MoonLeaf correction recipes support at most 1000 changed cells')
            output[source_row][source_columns[column]] = after
            row_changed = True
        changed_rows += row_changed
    if not edits:
        raise Refused('No changed cells; no correction proposal or copy is needed')
    recipe = encode({'key_columns': keys, 'edits': edits})
    if units(recipe.decode('utf-8')) > 1048576:
        raise Refused('Correction recipe exceeds 1048576 UTF-16 units')
    copy = serialize(output, fmt)
    if len(copy) > MAX_BYTES or parse(copy, fmt) != output:
        raise Refused('Copy exceeds supported bounds or cannot reopen')
    plan = {
        'format': 'moonleaf.review-sheet-plan.v1', 'input_format': fmt,
        'source_sha256': digest(raw), 'manifest_sha256': digest(encode(manifest)),
        'edited_sheet_sha256': digest(edited), 'recipe_sha256': digest(recipe),
        'copy_sha256': digest(copy), 'rows': len(rows) - 1,
        'changed_rows': changed_rows, 'changed_cells': len(edits),
        'edit_columns': editable, 'diagnostics': LIMITS,
    }
    return plan, recipe, copy


def create_sheet(source, fmt, selection_path, directory):
    raw = read_regular(source)
    manifest, sheet = prepare_sheet(raw, fmt, json_value(read_regular(selection_path)))
    if read_regular(source) != raw:
        raise Refused('Source changed during export; retry with a stable source')
    directory = Path(directory)
    directory.mkdir(mode=0o700)
    write_new(directory / 'manifest.json', encode(manifest))
    write_new(directory / ('editable.' + fmt), sheet)
    return {'source_sha256': manifest['source_sha256'], 'rows': manifest['rows'],
            'key_columns': manifest['selection']['key_columns'],
            'edit_columns': manifest['selection']['edit_columns'],
            'editable_file': 'editable.' + fmt, 'diagnostics': LIMITS}


def create_proposal(source, workspace, directory):
    workspace, directory = Path(workspace), Path(directory)
    raw = read_regular(source)
    manifest = json_value(read_regular(workspace / 'manifest.json'))
    # Never use arbitrary manifest content as a filename.
    if not isinstance(manifest, dict) or manifest.get('input_format') not in ('csv', 'tsv'):
        raise Refused('Expected csv or tsv review-sheet format')
    edited = read_regular(workspace / ('editable.' + manifest['input_format']))
    plan, recipe, _ = prepare_proposal(raw, manifest, edited)
    if read_regular(source) != raw:
        raise Refused('Source changed during proposal; export and review a new sheet')
    directory.mkdir(mode=0o700)
    # Freeze all proposal inputs; later working-sheet edits cannot silently change it.
    write_new(directory / 'manifest.json', encode(manifest))
    write_new(directory / 'edited-sheet.txt', edited)
    write_new(directory / 'corrections.json', recipe)
    write_new(directory / 'plan.json', encode(plan))
    return plan


def apply_proposal(source, directory, destination):
    directory, destination = Path(directory), Path(destination)
    stored = json_value(read_regular(directory / 'plan.json'))
    manifest = json_value(read_regular(directory / 'manifest.json'))
    edited = read_regular(directory / 'edited-sheet.txt')
    raw = read_regular(source)
    plan, recipe, copy = prepare_proposal(raw, manifest, edited)
    if stored != plan or read_regular(directory / 'corrections.json') != recipe:
        raise Refused('Proposal or recipe changed; prepare and review a new proposal')
    if destination.resolve() == Path(source).resolve():
        raise Refused('Destination must be distinct from source')
    write_new(destination, copy)
    readback = read_regular(destination)
    # csv's default field ceiling is below the declared delimited text bound.
    prior_limit = csv.field_size_limit(2097152)
    try:
        reopened = list(csv.reader(io.StringIO(readback.decode('utf-8'), newline=''),
                                   delimiter=',' if plan['input_format'] == 'csv' else '\t', strict=True))
    finally:
        csv.field_size_limit(prior_limit)
    if readback != copy or reopened != parse(copy, plan['input_format']) or read_regular(source) != raw:
        raise Refused('Copy/source readback failed; destination is retained unverified')
    return {'format': 'moonleaf.review-sheet-copy-receipt.v1',
            'source_sha256': digest(raw), 'copy_sha256': digest(readback),
            'edited_sheet_sha256': plan['edited_sheet_sha256'], 'recipe_sha256': plan['recipe_sha256'],
            'changed_rows': plan['changed_rows'], 'changed_cells': plan['changed_cells'],
            'text_values_reopened': True, 'render_verified': False, 'diagnostics': LIMITS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    export = commands.add_parser('export', help='Create a private editable sheet and source manifest')
    export.add_argument('format', choices=['csv', 'tsv'])
    export.add_argument('source'); export.add_argument('selection'); export.add_argument('directory')
    propose = commands.add_parser('propose', help='Freeze a changed sheet as an existing typed correction recipe')
    propose.add_argument('source'); propose.add_argument('workspace'); propose.add_argument('directory')
    batch_export = commands.add_parser('batch-export', help='Export explicit records with read-only context columns')
    batch_export.add_argument('format', choices=['csv', 'tsv'])
    batch_export.add_argument('source'); batch_export.add_argument('selection'); batch_export.add_argument('directory')
    batch_propose = commands.add_parser('batch-propose', help='Freeze a reviewed record batch as an ordinary full-source proposal')
    batch_propose.add_argument('source'); batch_propose.add_argument('workspace'); batch_propose.add_argument('directory')
    apply = commands.add_parser('apply', help='Apply the reviewed proposal to a fresh full-table copy')
    apply.add_argument('source'); apply.add_argument('directory'); apply.add_argument('destination')
    args = parser.parse_args()
    try:
        if args.command in ('batch-export', 'batch-propose'):
            from review_batch import create_batch, create_batch_proposal
            result = (create_batch(args.source, args.format, args.selection, args.directory)
                      if args.command == 'batch-export' else create_batch_proposal(args.source, args.workspace, args.directory))
        elif args.command == 'export':
            result = create_sheet(args.source, args.format, args.selection, args.directory)
        elif args.command == 'propose':
            result = create_proposal(args.source, args.workspace, args.directory)
        else:
            result = apply_proposal(args.source, args.directory, args.destination)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (ValueError, OSError, UnicodeError, csv.Error) as error:
        print('MoonLeaf review-sheet refused: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
