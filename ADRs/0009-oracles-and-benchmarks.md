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

Benchmarks use the same canonical corpora across implementations. They measure
format processing, recurrence, XML, synchronization planning, transactional
apply, search, and foreign-interface overhead. Machine-tagged results are
exported by script; undocumented performance regressions fail the benchmark
gate.

## Consequences

- Oracle dependencies remain outside the runtime dependency graph.
- Correctness and performance datasets are versioned; generated executables
  and measurements are not.
- Every published number records its machine, compiler, mode, corpus, and
  command.

