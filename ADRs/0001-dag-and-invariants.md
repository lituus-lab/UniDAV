<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0001: Acyclic DAG + anti-cycle invariants

- Status: Accepted
- Date: 2026-07-15
- Scope: every `Uni*` repo

## Decision

Family dependencies form a strictly acyclic graph: a library depends only on
libraries below it, never sideways and never up. Topological order is build
order, and it is also release order — a stable release pins its dependencies to
their tags, which only works if they are published first.

The layers are not numbered family-wide. What is checked is concrete: each
repo's `vgraph.cfg` names the `Uni*` engines it may require, and `nimble
checkVGraph` fails on any `requires` that is not among them.

## Invariants

1. Layer-0 primitives have no domain dependency (`UniColor`, `UniChecksum`,
   `UniContainer` → none).
2. Type modules never import algorithm modules within a library
   (`types/` ↛ `algorithms/`; `io/` → `types/` only).
3. `UniLinalg` is a repo above `UniMath`; `UniGeom` consumes it, no redefined Vec.
4. No library depends on an app. Apps may depend on anything below.
5. Infrastructure deps (`NimContracts`, `nimsimd`) are not domain edges: they
   carry no `Uni*` subject, so `vgraph.cfg`'s `[engines]` leaves them unchecked.
   `NimContracts` is a hard `requires` — the contracts compile away under
   `-d:release`, the dependency does not.

Extraction into its own repo requires a consumer wanting the piece *without*
the parent's main subject; else one repo with a documented internal DAG.
