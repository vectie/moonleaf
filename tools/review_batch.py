"""Explicit record batches with immutable context for the review-sheet workflow."""
from pathlib import Path

from review_sheet import (
    Refused, column_names, digest, encode, json_value, keyed_rows, parse,
    prepare_proposal, prepare_sheet, read_regular, serialize, units, write_new,
)
from pseudonymize import MAX_BYTES, require_fields

LIMITS = [
    'Only explicitly selected records and key, context and editable columns appear in the exported batch.',
    'Keys and context values are read-only on import; only declared editable columns can produce corrections.',
    'The resulting ordinary proposal and full-table copy include unselected source records; do not share them as a scoped batch.',
    'Selected keys, context and values may be private; the host owns permission, review and sharing.',
    'Hashes and local review files do not authenticate reviewers or establish approval, delivery or acceptance.',
    'Literal text only; formula-looking strings may execute in external spreadsheet applications.',
    'Python text-value readback only; no MoonBit session, rendering, Office fidelity or host-linkage qualification.',
]


def prepare_batch(raw, fmt, selection):
    """Project explicit stable-key records without exporting other source values."""
    require_fields(selection, ['key_columns', 'edit_columns', 'context_columns', 'row_keys'])
    keys = column_names(selection['key_columns'], 'key_columns', 32)
    editable = column_names(selection['edit_columns'], 'edit_columns', 128)
    context = selection['context_columns']
    if context != []:
        column_names(context, 'context_columns', 128)
    # prepare_sheet validates key/edit scope, global row identity and source bounds.
    ordinary, _ = prepare_sheet(raw, fmt, {'key_columns': keys, 'edit_columns': editable})
    source = parse(raw, fmt)
    columns = keys + context + editable
    if len(set(columns)) != len(columns) or any(name not in source[0] for name in columns):
        raise Refused('Key, context and edit columns must be disjoint existing columns')
    wanted = selection['row_keys']
    if not isinstance(wanted, list) or not 1 <= len(wanted) <= 9999:
        raise Refused('row_keys must contain 1–9999 explicit key arrays')
    selected = set()
    for key in wanted:
        if (not isinstance(key, list) or len(key) != len(keys)
                or any(not isinstance(value, str) or not value or units(value) > 4096 for value in key)):
            raise Refused('Each row key must contain one bounded nonempty text value per key column')
        if tuple(key) in selected:
            raise Refused('Repeated selected row key')
        selected.add(tuple(key))
    indexed = keyed_rows(source, keys, 'Source')
    if not selected <= indexed.keys():
        raise Refused('Unknown selected row key; select exact keys from this source')
    positions = [source[0].index(name) for name in columns]
    rows = [columns] + [[row[i] for i in positions] for key, row in indexed.items() if key in selected]
    batch = serialize(rows, fmt)
    parse(batch, fmt)
    manifest = {
        'format': 'moonleaf.review-batch.v1', 'input_format': fmt,
        'source_sha256': ordinary['source_sha256'], 'baseline_batch_sha256': digest(batch),
        'selection': selection, 'selected_rows': len(selected),
        'source_rows': len(source) - 1, 'diagnostics': LIMITS,
    }
    if len(encode(manifest)) > MAX_BYTES:
        raise Refused('Batch manifest exceeds 8 MiB')
    return manifest, batch


def prepare_batch_proposal(raw, manifest, edited):
    """Validate a batch and return an unchanged ordinary proposal contract."""
    if not isinstance(manifest, dict) or manifest.get('format') != 'moonleaf.review-batch.v1':
        raise Refused('Unsupported review-batch manifest')
    if digest(raw) != manifest.get('source_sha256'):
        raise Refused('Source changed since batch export; retain the original to prepare, then rebase if needed')
    fmt = manifest.get('input_format')
    expected, baseline = prepare_batch(raw, fmt, manifest.get('selection'))
    if manifest != expected:
        raise Refused('Batch manifest does not match source and selection')
    original, reviewed = parse(baseline, fmt), parse(edited, fmt)
    selection = manifest['selection']
    keys, editable, context = (selection[name] for name in ('key_columns', 'edit_columns', 'context_columns'))
    if set(reviewed[0]) != set(original[0]):
        raise Refused('Edited batch must retain exactly its key, context and editable columns')
    original_index = keyed_rows(original, keys, 'Batch baseline')
    edited_index = keyed_rows(reviewed, keys, 'Edited batch')
    if original_index.keys() != edited_index.keys():
        raise Refused('Batch must retain every selected key exactly once; do not add, remove or change records')
    positions = {name: reviewed[0].index(name) for name in context + editable}
    for key, row in original_index.items():
        if any(row[original[0].index(name)] != edited_index[key][positions[name]] for name in context):
            raise Refused('Context columns are read-only; restore original context before proposing changes')
    # Reconstruct the full ordinary review sheet only in the private proposal
    # step. The exported reviewer batch never contains these unselected values.
    ordinary, full = prepare_sheet(raw, fmt, {'key_columns': keys, 'edit_columns': editable})
    full_rows = parse(full, fmt)
    full_index = keyed_rows(full_rows, keys, 'Source')
    for key, row in edited_index.items():
        for name in editable:
            full_index[key][full_rows[0].index(name)] = row[positions[name]]
    full_edited = serialize(full_rows, fmt)
    plan, recipe, copy = prepare_proposal(raw, ordinary, full_edited)
    receipt = {
        'format': 'moonleaf.review-batch-result.v1', 'source_sha256': digest(raw),
        'batch_manifest_sha256': digest(encode(manifest)), 'edited_batch_sha256': digest(edited),
        'selected_rows': manifest['selected_rows'], 'source_rows': manifest['source_rows'],
        'changed_rows': plan['changed_rows'], 'changed_cells': plan['changed_cells'],
        'recipe_sha256': digest(recipe), 'diagnostics': LIMITS,
    }
    return receipt, ordinary, full_edited, plan, recipe, copy


def create_batch(source, fmt, selection_path, directory):
    raw = read_regular(source)
    manifest, batch = prepare_batch(raw, fmt, json_value(read_regular(selection_path)))
    if read_regular(source) != raw:
        raise Refused('Source changed during batch export')
    directory = Path(directory)
    directory.mkdir(mode=0o700)
    write_new(directory / 'manifest.json', encode(manifest))
    write_new(directory / ('editable.' + fmt), batch)
    return {**manifest, 'editable_file': 'editable.' + fmt,
            'next': 'Edit only declared edit_columns, then batch-propose against the retained source.'}


def create_batch_proposal(source, workspace, directory):
    workspace, directory = Path(workspace), Path(directory)
    raw = read_regular(source)
    manifest = json_value(read_regular(workspace / 'manifest.json'))
    if not isinstance(manifest, dict) or manifest.get('input_format') not in ('csv', 'tsv'):
        raise Refused('Expected csv or tsv review-batch format')
    edited = read_regular(workspace / ('editable.' + manifest['input_format']))
    receipt, ordinary, full, plan, recipe, _ = prepare_batch_proposal(raw, manifest, edited)
    if read_regular(source) != raw:
        raise Refused('Source changed during batch proposal')
    directory.mkdir(mode=0o700)
    write_new(directory / 'batch.json', encode(receipt))
    write_new(directory / 'batch-manifest.json', encode(manifest))
    write_new(directory / 'edited-batch.txt', edited)
    write_new(directory / 'manifest.json', encode(ordinary))
    write_new(directory / 'edited-sheet.txt', full)
    write_new(directory / 'plan.json', encode(plan))
    write_new(directory / 'corrections.json', recipe)
    return receipt
