<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0005: UniDAV engine boundary and dependency DAG

- Status: Accepted
- Date: 2026-08-15
- Scope: UniDAV and its consumers

## Decision

UniDAV is the layer-0 PIM data and DAV engine. It owns lossless vCard and
iCalendar documents, PIM semantics, CardDAV and CalDAV protocol sequencing,
synchronization state machines, and portable Nim, C, Python, JavaScript, and
WebAssembly surfaces.

Applications own user interfaces, account lifecycle, credential storage,
conflict policy, application databases, scheduling policy, and extension
permissions. Concordia is the canonical consumer. UniDAV never imports
Concordia or another application.

The internal dependency direction is:

```text
formats <- pim <- dav <- sync
   ^         ^      ^      ^
   +--------- injectable ports ----+
```

Native transports and foreign-language bindings are adapters around those
layers. `tools/vgraph.nim` enforces the direction in CI.

## Consequences

- A format or PIM module cannot import transport, storage, or application code.
- A network write is conditional and idempotent.
- A checkpoint becomes visible only after the consumer's durable transaction
  commits.
- SQLite may be supplied as an adapter, but no application schema or secret
  policy belongs to UniDAV.

