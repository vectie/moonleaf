# ZIP/OPC archive security

MoonLeaf treats each document open as an in-memory, fail-closed ZIP/OPC
operation. `@opc.open`, `@moonleaf.open`, and `@moonleaf.open_session` use
`ArchivePolicy::default()`. Their `*_with_policy` variants accept a stricter
validated policy, and a document session retains its selected policy for
save/reopen verification.

## Default limits

| Limit | Default |
| --- | ---: |
| Compressed archive input | 64 MiB |
| ZIP entries, including directory entries | 8,192 |
| Compressed bytes per entry | 32 MiB |
| Uncompressed bytes per entry | 64 MiB |
| Total uncompressed bytes | 96 MiB |
| Uncompressed/compressed ratio per entry | 200:1 |
| Normalized path depth | 32 components |
| ZIP path length | 1,024 MoonBit string code units |

The configured per-entry compressed limit cannot exceed the input limit, and
the per-entry uncompressed limit cannot exceed the total limit. Every limit
must be positive. `hustcer/fzip` also retains its own coarser hard ceilings, so
loosening a MoonLeaf policy does not override dependency limits.

## Open sequence

1. Validate the policy and bound compressed input bytes.
2. Read central-directory metadata with `unzip_list`.
3. Bound entry count, per-entry and total sizes, compression method and ratio.
4. Reject absolute paths, backslashes, control characters, empty/dot/parent
   components, whitespace aliases, encoded dot/separator aliases, URI
   query/fragment delimiters, excessive depth/length, and case-insensitive
   duplicate or directory/file aliases.
5. Extract with `unzip_sync(opts={ verify_checksum: true })`.
6. Require extracted entry count, order, names and uncompressed sizes to match
   the preflight metadata, and recheck actual output budgets.
7. Normalize usable part names and require `[Content_Types].xml`.

Any failure returns no `Package` or `DocumentSession`. Host code must not retry
with a looser policy without a separate user or authority decision.

## Deliberate non-claims

This boundary does not validate VBA/macros, digital signatures, encryption,
embedded executables, remote/external relationship targets, fonts, media
decoders, or the semantic safety of unsupported OOXML. It also does not promise
Unicode normalization equivalence for path names. Hosts remain responsible for
file permission, process/network isolation, destination authorization, and
whether active or external content may be used.
