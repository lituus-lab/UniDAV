<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0002: Apache License 2.0

- Status: Accepted
- Date: 2026-08-15
- Scope: UniDAV

## Decision

UniDAV, its command-line tool, bindings, tests, documentation, fixtures, and
examples are licensed under Apache-2.0. Bundled or adapted third-party material
retains its original notice and license in `NOTICE`.

Every contribution carries a Developer Certificate of Origin sign-off. The
repository ships `LICENSE`, `NOTICE`, `CONTRIBUTING.md`, and `SECURITY.md`.

## Consequences

Generated libraries, wheels, documentation output, WebAssembly, databases,
coverage data, and oracle executables are build artifacts and are not
distributed as repository sources.

