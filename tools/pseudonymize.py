#!/usr/bin/env python3
"""Prepare private MoonLeaf correction recipes and fresh pseudonymized CSV/TSV copies."""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import sys

MAX_BYTES = 8 * 1024 * 1024
LIMITS = [
    'Pseudonymized data may remain identifiable; inspect every column before sharing.',
    'Sequential tokens preserve equality within one column and file, not across files.',
    'Keys and unselected fields remain unchanged and may identify people.',
    'CSV/TSV formula-looking strings remain text here but may execute in spreadsheet apps.',
    'Text-value reopen only; no MoonBit session, visual rendering, delivery or acceptance claim.',
]


class Refused(ValueError):
    pass


def units(value):
    return len(value.encode('utf-16-le')) // 2


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def json_value(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise Refused('Duplicate JSON field')
            result[key] = value
        return result
    return json.loads(raw.decode('utf-8'), object_pairs_hook=unique)


def read_regular(path):
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
            raise Refused('Expected a regular file no larger than 8 MiB')
        raw = handle.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise Refused('File exceeds 8 MiB')
    return raw


def parse(raw, fmt):
    """Conservative quoting/state rules matching MoonLeaf csv.parse's text subset."""
    if fmt not in ('csv', 'tsv'):
        raise Refused('Expected csv or tsv')
    text = raw.decode('utf-8')
    if units(text) > 2097152:
        raise Refused('Input exceeds 2097152 UTF-16 units')
    text = text.removeprefix('\ufeff')
    delimiter = ',' if fmt == 'csv' else '\t'
    rows, row, field = [], [], []
    quoted = closed = False
    start = True
    i = 0
    while i < len(text):
        char = text[i]
        if quoted:
            if char == '"':
                if i + 1 < len(text) and text[i + 1] == '"':
                    field.append('"'); i += 2; continue
                quoted, closed = False, True
            else:
                field.append(char)
        elif char == '"':
            if not start:
                raise Refused('Invalid quote')
            quoted, start = True, False
        elif char in (delimiter, '\r', '\n'):
            row.append(''.join(field)); field = []; start = True; closed = False
            if char != delimiter:
                rows.append(row); row = []
                if char == '\r' and i + 1 < len(text) and text[i + 1] == '\n':
                    i += 1
        else:
            if closed:
                raise Refused('Unexpected text after closing quote')
            field.append(char); start = False
        i += 1
    if quoted:
        raise Refused('Unterminated quote')
    if row or not start or text.endswith(delimiter):
        row.append(''.join(field)); rows.append(row)
    if not rows:
        raise Refused('Missing header')
    header = rows[0]
    if not 1 <= len(header) <= 128 or any(not name for name in header) or len(set(header)) != len(header):
        raise Refused('Expected 1–128 distinct nonempty headers')
    if len(rows) > 10000 or len(rows) * len(header) > 100000:
        raise Refused('Table exceeds row or cell limits')
    if any(len(row) != len(header) for row in rows):
        raise Refused('Ragged row')
    return rows


def serialize(rows, fmt):
    stream = io.StringIO(newline='')
    writer = csv.writer(stream, delimiter=',' if fmt == 'csv' else '\t', quoting=csv.QUOTE_ALL, lineterminator='\r\n')
    writer.writerows(rows)
    return stream.getvalue().encode('utf-8')


def require_fields(value, names):
    if not isinstance(value, dict) or set(value) != set(names):
        raise Refused('Missing or unknown object fields')


def prepare(raw, fmt, policy):
    rows = parse(raw, fmt)
    header = rows[0]
    require_fields(policy, ['key_columns', 'columns'])
    keys = policy['key_columns']
    if not isinstance(keys, list) or not 1 <= len(keys) <= 32 or any(not isinstance(k, str) or not k or units(k) > 4096 for k in keys) or len(set(keys)) != len(keys):
        raise Refused('Expected 1–32 distinct exact key columns')
    if any(key not in header for key in keys):
        raise Refused('Unknown key column')
    key_indexes = [header.index(key) for key in keys]
    seen_keys = set()
    for row in rows[1:]:
        key = tuple(row[i] for i in key_indexes)
        if any(not value or units(value) > 4096 for value in key) or key in seen_keys:
            raise Refused('Keys must be nonempty, bounded and globally unique')
        seen_keys.add(key)
    rules = policy['columns']
    if not isinstance(rules, list) or not rules or len(rules) > 128:
        raise Refused('Expected 1–128 column rules')
    seen_columns = set()
    for rule in rules:
        if not isinstance(rule, dict) or rule.get('mode') not in ('mask', 'pseudonym'):
            raise Refused('Expected mask or pseudonym mode')
        require_fields(rule, ['column', 'mode', 'value' if rule['mode'] == 'mask' else 'prefix'])
        name = rule['column']
        if not isinstance(name, str) or name not in header or name in seen_columns or name in keys:
            raise Refused('Unknown, repeated or key-column redaction target')
        seen_columns.add(name)
        if rule['mode'] == 'mask':
            if not isinstance(rule['value'], str) or units(rule['value']) > 32768:
                raise Refused('Mask must be text up to 32768 UTF-16 units')
        elif not isinstance(rule['prefix'], str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,31}', rule['prefix']):
            raise Refused('Pseudonym prefix must be 1–32 ASCII letters, digits, hyphens or underscores, starting with a letter')
    output = [row.copy() for row in rows]
    edits, counts = [], []
    for rule in rules:
        c = header.index(rule['column'])
        tokens = {}
        count = changed = 0
        for r, row in enumerate(rows[1:], 1):
            before = row[c]
            if before == '':
                continue
            if rule['mode'] == 'mask':
                after = rule['value']
            else:
                if before not in tokens:
                    tokens[before] = rule['prefix'] + str(len(tokens) + 1).zfill(4)
                after = tokens[before]
            output[r][c] = after
            edits.append({'key': [row[i] for i in key_indexes], 'column': rule['column'],
                          'before': {'type': 'text', 'value': before}, 'after': {'type': 'text', 'value': after}})
            count += 1; changed += before != after
            if len(edits) > 1000:
                raise Refused('Existing MoonLeaf correction recipes support at most 1000 cell edits')
        counts.append({'column': rule['column'], 'mode': rule['mode'], 'target_cells': count, 'changed_cells': changed,
                       'distinct_tokens': len(tokens) if rule['mode'] == 'pseudonym' else None})
    if not edits:
        raise Refused('No nonempty target cells; no correction recipe is needed')
    recipe = {'key_columns': keys.copy(), 'edits': edits}
    recipe_bytes = encode(recipe)
    if units(recipe_bytes.decode('utf-8')) > 1048576:
        raise Refused('Correction recipe exceeds 1048576 UTF-16 units')
    copy = serialize(output, fmt)
    if len(copy) > MAX_BYTES:
        raise Refused('Copy exceeds 8 MiB')
    if parse(copy, fmt) != output:
        raise Refused('Copy does not round-trip within supported parser bounds')
    plan = {'format': 'moonleaf.pseudonym-plan.v1', 'input_format': fmt, 'source_sha256': digest(raw),
            'recipe_sha256': digest(recipe_bytes), 'copy_sha256': digest(copy), 'policy': policy,
            'rows': len(rows) - 1, 'columns': header, 'changes': counts, 'diagnostics': LIMITS}
    return plan, recipe_bytes, copy


def write_new(path, raw):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as handle:
        handle.write(raw); handle.flush(); os.fsync(handle.fileno())


def create_plan(source, fmt, policy_path, directory):
    raw = read_regular(source)
    plan, recipe, _ = prepare(raw, fmt, json_value(read_regular(policy_path)))
    directory = Path(directory)
    directory.mkdir(mode=0o700)
    # A failed write leaves the private incomplete directory for diagnosis, never overwrites it.
    write_new(directory / 'corrections.json', recipe)
    write_new(directory / 'plan.json', encode(plan))
    return {k: plan[k] for k in ('source_sha256', 'rows', 'columns', 'changes', 'diagnostics')}


def apply_plan(source, directory, destination):
    directory, destination = Path(directory), Path(destination)
    stored = json_value(read_regular(directory / 'plan.json'))
    if not isinstance(stored, dict) or stored.get('format') != 'moonleaf.pseudonym-plan.v1':
        raise Refused('Unsupported plan')
    raw = read_regular(source)
    if digest(raw) != stored.get('source_sha256'):
        raise Refused('Source changed since review; create a new plan')
    planned, recipe, copy = prepare(raw, stored.get('input_format'), stored.get('policy'))
    if stored != planned or read_regular(directory / 'corrections.json') != recipe:
        raise Refused('Plan or correction recipe changed; create and review a new plan')
    if destination.resolve() == Path(source).resolve():
        raise Refused('Destination must be distinct from source')
    write_new(destination, copy)
    # Independent standard-library reader, in addition to the conservative production parse.
    readback = read_regular(destination)
    delimiter = ',' if planned['input_format'] == 'csv' else '\t'
    reopened = list(csv.reader(io.StringIO(readback.decode('utf-8'), newline=''), delimiter=delimiter, strict=True))
    if readback != copy or reopened != parse(copy, planned['input_format']) or read_regular(source) != raw:
        raise Refused('Copy/source readback failed; destination is retained unverified')
    return {'format': 'moonleaf.pseudonym-copy-receipt.v1', 'source_sha256': digest(raw),
            'copy_sha256': digest(readback), 'recipe_sha256': planned['recipe_sha256'],
            'rows': planned['rows'], 'columns': planned['columns'], 'text_values_reopened': True,
            'render_verified': False, 'diagnostics': LIMITS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    plan = commands.add_parser('plan', help='Create a PRIVATE plan and existing MoonLeaf correction recipe')
    plan.add_argument('format', choices=['csv', 'tsv']); plan.add_argument('source'); plan.add_argument('policy'); plan.add_argument('directory')
    apply = commands.add_parser('apply', help='Apply the reviewed plan to a new local copy')
    apply.add_argument('source'); apply.add_argument('directory'); apply.add_argument('destination')
    args = parser.parse_args()
    try:
        result = create_plan(args.source, args.format, args.policy, args.directory) if args.command == 'plan' else apply_plan(args.source, args.directory, args.destination)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (ValueError, OSError, UnicodeError, csv.Error) as error:
        print('MoonLeaf pseudonymization refused: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
