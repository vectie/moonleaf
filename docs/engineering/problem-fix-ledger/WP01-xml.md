# WP01 XML compatibility and resource-limit checkpoint

## Problem

An attempted prefix-tolerant lexical QName model added expanded-name fields to the public legacy
`Element` and `Attribute` records. That was incompatible with existing record literals
throughout the repository. The compiler reported incompatible-record and missing-field
errors; an intermediate duplicate-attribute check also referenced an unbound `aname`.

## Fix

WP01 retains the legacy lexical tree (`name`, `attributes`, and `children`) and ordinary-input behavior of the existing `parse` API. This is the legacy representation and compatibility boundary; default `parse` intentionally adds finite resource limits and rejects DTDs and general entities. Namespace declarations (`xmlns` and `xmlns:*`) remain ordinary
attributes so parse/serialize retains bindings and prefixes. Public expanded-name,
QName, namespaced-node APIs and misleading URI lookup methods are deliberately not
shipped. Lexical QNames tolerate prefixes, but namespace bindings are explicitly not validated. The established exact mismatch diagnostic is `mismatched closing element name`, without angle brackets.

`ParseOptions` and `parse_with_options` provide bounded input measured as UTF-16 code units, nesting depth, node count, attributes per element, and total decoded text. DTD and declared/general entities remain
rejected.

## Checkpoint hygiene correction

### Problem

Every tracked `*.generated.mbti` was accidentally corrupted by a final literal `\\n`
line and lacked a normal terminating newline. In addition, the `Element::attribute`
documentation misleadingly directed callers to a nonexistent `attribute_ns` API.

### Root cause

A noncanonical interface-file rewrite appended escaped newline text instead of a real
line ending, bypassing `moon info` ownership of generated declarations. The comment
described a planned URI-aware API as though it had been implemented, while the method
only performs compatibility matching against an attribute's lexical or local name.

### Fix

The corrupt literal lines were removed without hand-authoring declarations, and
`moon info` regenerated all interfaces canonically with normal file endings. The
comment now explicitly documents lexical/local-name compatibility lookup and states
that URI-aware lookup is not implemented.

### Verification

Focused tests cover each resource ceiling, DTD/entity rejection, mismatch diagnostics,
and prefixed parse/serialize namespace retention. `moon info` leaves unrelated package
interfaces unchanged and the generated diff is limited to the intended XML public API.
The release gate is:

- `moon fmt`
- `moon info`
- `moon check --target all`
- `moon test --target all`
- `git diff --check`

## Remaining work

Raw invalid XML control characters and URI namespace binding validation remain residual risks. A separate `parse_namespaced` API must define URI-resolved element and attribute names,
namespace scope representation, serialization behavior, and migration guidance before
any namespace-validating public types or URI-qualified lookup methods are introduced.
