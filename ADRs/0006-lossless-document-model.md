<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0006: Lossless documents are the source of truth

- Status: Accepted
- Date: 2026-08-15
- Scope: vCard and iCalendar processing

## Decision

The ordered component tree is UniDAV's canonical representation. It retains
unknown properties, parameters, repeated values, component order, and nested
components across parse and serialization.

Typed PIM objects and JSON projections are views. An edit is applied to the
original tree and changes only the selected modeled fields. A projection must
not replace a source document or silently discard data that the host does not
understand.

Parsing, normalization, projection, patching, and recurrence expansion are
bounded by caller-visible limits. Recovery mode reports every repair it makes.

## Consequences

- Round-trip preservation is tested separately from semantic equivalence.
- Canonical output may normalize folding and line endings without deleting
  extensions.
- A new modeled property requires a preservation test for adjacent unknown
  data.

