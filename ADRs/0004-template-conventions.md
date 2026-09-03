<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0004: UniDAV conventions

- Status: Accepted
- Date: 2026-07-15
- Scope: UniDAV and the conventions every engine started from it inherits

## Layout

```text
UniDAV.nimble          package + tasks
config.nims                 arch-conditional build flags
src/UniDAV.nim         umbrella
src/UniDAV/fibonacci.nim  hello-world (NimContracts)
src/UniDAV/c_api.nim   C ABI
include/UniDAV.h       hand-written C header
tests/ tests/c/             Nim + C ABI tests
examples/                   Nim + C demos
py/                         Cython binding + pytest
book/                       nimib book, code blocks run at build
ADRs/                       0001–0004
.github/workflows/ci.yml    3-OS Nim + C ABI + Python
LICENSE NOTICE CONTRIBUTING.md SECURITY.md .gitignore README.md AGENTS.md CLAUDE.md
```

## Naming

- Nim package/module: `UniFoo` (PascalCase).
- C library: `libUniFoo`. C header: `UniFoo.h`.
- C symbol prefix: the library's own name in lower case (`unidav_`, so
  `unimath_`, `uniaccurate_`). Not a short token: a binary that links several
  engines at once holds them all in one namespace, and `um_` has more than one
  plausible owner.

## Conventions

- Hello-world `fibonacci`, exercised in Nim + C ABI + Python.
- NimContracts `{.contractual.}` + `require:`/`ensure:`/`body:`, compiled away
  under `-d:release`. The C ABI never raises — it clamps out-of-range input.
- A postcondition is cheaper than the body; it never re-derives the result.
- English comments, terse, describe what is done. No "deprecated".
- Internal `types/` never imports `algorithms/`; `io/` → `types/` only.

## CI gates

Every task runs through `tools/gate.nim`: nimble exits 0 on a task whose `exec`
failed, so its exit code proves nothing and the task's own success marker is
what the gate reads.

- `testCi` + `testCiRelease` on ubuntu/macOS/Windows.
- `ctest`, `cexample` and `clib` on ubuntu/macOS/Windows.
- the Python matrix on ubuntu/macOS/Windows, 3.10 to 3.14.
- `lint`, `checkVGraph`, `docs` and `coverage` on ubuntu.
- `canary`, which must fail.
- `all-green` over all of them: the one check branch protection requires.

## Rename map

| Template | New engine |
|---|---|
| `UniDAV` | `UniFoo` |
| `unidav` | `unifoo` |
| `libUniDAV` | `libUniFoo` |
| `UniDAV.h` | `UniFoo.h` |
| `lituus-unidav` | `lituus-unifoo` |

After the rename, replace `fibonacci.nim` with the domain module(s), update the
umbrella exports, the C ABI + header + C test + Python `_core.pyx`, and run the
gates.
