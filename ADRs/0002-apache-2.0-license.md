<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0002: Apache License 2.0 for the engines

- Status: Accepted
- Date: 2026-07-15
- Scope: every `Uni*` engine (open-source)

## Decision

`Uni*` engine repos are Apache-2.0. Apps (closed-source) are private and not
covered. The MIT→Apache relicense is unambiguous (each repo is author-single).
Forks `NimContracts`/`nimsimd` keep MIT (upstream preserved).

Every repo ships `LICENSE`, `NOTICE`, `CONTRIBUTING.md` (DCO) and
`CODE_OF_CONDUCT.md`. Apache-2.0 grants an explicit patent license. `NOTICE`
records the MIT dependency — recorded, not bundled: the contracts compile away
under `-d:release`, so nothing of NimContracts reaches a shipped artifact.
