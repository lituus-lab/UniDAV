<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0004: UniDAV conventions

- Status: Accepted
- Date: 2026-07-15
- Scope: UniDAV

## Layout

```text
UniDAV.nimble               package + tasks
config.nims                 arch-conditional build flags
src/UniDAV.nim              umbrella
src/UniDAV/                 21 modules, layered; see vgraph.cfg
src/UniDAV/c_api.nim        C ABI
src/UniDAV/wasm_api.nim     WASM facade
csrc/                       the hardened HTTP transports: libcurl, WinHTTP
include/UniDAV.h            hand-written C header
bin/unidav.nim              the CLI
tests/ tests/c/             Nim + C ABI tests
tests/oracles/              independent Python parsers the fixtures are checked against
tests/interop/              opt-in suites against a real DAV server
examples/                   Nim + C demos
py/                         Cython binding + pytest
book/                       nimib book, code blocks run at build
ADRs/                       0001-0004
.github/workflows/ci.yml    3-OS Nim + C ABI + Python
LICENSE NOTICE CONTRIBUTING.md SECURITY.md .gitignore README.md AGENTS.md CLAUDE.md
```

## Naming

- Nim package/module: `UniDAV` (PascalCase).
- C library: `libUniDAV`. C header: `UniDAV.h`.
- C symbol prefix: the library's own name in lower case, `unidav_`. It was
  `udav_` and was renamed: a short token has more than one plausible owner, and
  a binary that links several engines at once holds them all in one namespace.

## Conventions

- English comments, terse, describe what is done. No "deprecated".
- NimContracts `{.contractual.}` where a precondition is about structure rather
  than a live handle -- see `sync.nim`. Anything guarding the C ABI or a
  foreign resource is checked in plain code, because contracts compile away
  under `-d:release` and those checks must not.
- The C ABI never raises: a failure is a NULL return with a code in
  `unidav_status`. Every returned string is the caller's, freed with
  `unidav_free` exactly once -- the opposite of the borrowed-pointer convention
  UniMCP and UniDatabase use, and stated at each entry point in the header.
- Losslessness is the rule the format code answers to: a property this library
  does not understand survives a round trip. Serialising canonicalises the fold
  position, which carries no meaning; it preserves every value.
- Layers, checked by `nimble checkVGraph`: `contentline` up to `wasm_api`,
  never upward. Every name in `vgraph.cfg` answers to a real module -- one that
  does not constrains nothing, and the check then passes on a graph it never
  read.

## CI gates

Every task runs through `tools/gate.nim`: nimble exits 0 on a task whose `exec`
failed, so its exit code proves nothing and the task's own success marker is
what the gate reads.

- `testCi` + `testCiRelease` on ubuntu/macOS/Windows.
- `wasmTest`, `testOracles`, `testInterop` and `testRadicale` are opt-in: they
  need Emscripten, Python parsers, or a DAV server this repo does not run.
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
