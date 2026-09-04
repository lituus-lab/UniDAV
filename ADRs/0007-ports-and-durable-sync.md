<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0007: Injectable ports and durable synchronization

- Status: Accepted
- Date: 2026-08-15
- Scope: discovery, transport, time, storage, and synchronization

## Decision

UniDAV expresses network and persistence effects through bounded interfaces
for HTTP transport, DNS resolution, clocks, time-zone registries, identifiers,
and transactional storage. Protocol planning and state transitions remain
deterministic under injected implementations.

Outgoing operations use stable identifiers and conditional requests. Ambiguous
responses are verified before an operation is completed. Incoming resources,
tombstones, and the next checkpoint commit atomically. Recovery of interrupted
work is explicit and cannot claim work owned by another live process.

## Consequences

- Tests can inject transport failures and crashes at every durable boundary.
- DAV regressions include an anonymized fixture and a recovery-path test.
- Credentials remain in the host's memory or credential vault and are never
  persisted by a protocol object or written to logs.

