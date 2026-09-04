<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0008: C, Python, JavaScript, and WebAssembly surfaces

- Status: Accepted
- Date: 2026-08-15
- Scope: foreign-language APIs

## Decision

The public Nim API is the source of truth. A completeness manifest maps every
public domain operation to a foreign entry point or to a documented exclusion
with a concrete language-boundary reason.

The C ABI uses the `unidav_` prefix, opaque handles, integer status values, and
explicit ownership. No exception crosses the ABI. Python uses a compiled
Cython binding over the C ABI. JavaScript uses Nim's JavaScript backend for
browser-native hosts. WebAssembly exposes a bounded, allocation-explicit API
and does not require Node.js at runtime or for its canonical tests.

## Consequences

- Static and shared C libraries are both tested against the public header.
- Python wheels bundle the native library and are tested after installation.
- Browser tests run in a real browser without npm or Node.js.
- ABI drift and surface completeness fail CI.

