<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0009: Differential oracles and performance evidence

- Status: Accepted
- Date: 2026-08-15
- Scope: semantic verification and performance

## Decision

UniDAV is compared against independent implementations for parsing,
validation, recurrence, time zones, conversion, and DAV behavior. The initial
oracle set is libical, iCal4j, sabre/vobject, IETF examples, CalDAVTester, and
the configured interoperability servers.

No implementation is treated as authoritative by itself. Results are reduced
to a common schema and classified as a UniDAV defect, a standards-permitted
difference, an oracle defect, or an explicitly unverified case. Regressions
become minimal local fixtures.

Benchmarks use generated, deterministic corpora and keep every result live
through a non-inline sink, so the release optimizer cannot delete the work
being timed. What `bench` measures today is the format path and the two
calculations behind it: parsing and serializing vCard, parsing iCalendar,
projecting a vCard, expanding a weekly rule, and resolving a VTIMEZONE offset.

XML, synchronization planning, transactional apply, search and
foreign-interface overhead are **not** measured. They are the obvious next
families, and this ADR names them as absent rather than describing a suite
that does not exist.

`benchReadme` exports the current machine's block into `bench/README.md`,
tagged with the machine, the compiler and the build mode. There is **no**
regression gate: a threshold that means anything needs a baseline measured on
the same machine, and this project has no such baseline to compare against.
Adding one is a decision of its own; until then the benchmarks record, and a
reader compares blocks themselves.

## Consequences

- Oracle dependencies remain outside the runtime dependency graph.
- Correctness and performance datasets are versioned; generated executables
  and measurements are not.
- Every published number records its machine, compiler, mode, corpus, and
  command.

