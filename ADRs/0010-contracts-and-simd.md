<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0010: Structural contracts without SIMD

- Status: Accepted
- Date: 2026-08-15
- Scope: UniDAV implementation

## Decision

UniDAV uses NimContracts on public operations with cheap structural
postconditions, including synchronization state initialization and bounded
retry results. Input validation remains explicit and raises typed errors;
contracts do not replace checks on untrusted vCard, iCalendar, XML, DNS, HTTP,
or database data.

UniDAV does not depend on nimsimd. Its dominant work is variable-length text
parsing, recursive component traversal, XML processing, hashing, database I/O,
and network orchestration. These branch-heavy operations do not expose a
stable contiguous numeric kernel that would justify an ISA-specific backend.

## Consequences

- Debug tests execute contracts and release tests exercise the compiled-away
  path.
- New contracts state shape, count, ownership, or state-transition invariants;
  they do not repeat expensive semantic validation.
- Performance work starts from profiling and allocation reduction. SIMD is
  reconsidered only if a benchmark identifies a reusable numeric buffer
  kernel.

