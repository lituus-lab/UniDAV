<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# AGENTS.md — UniDAV

## Build & gates

```bash
nimble install -y
nim c --hints:off -o:build/unigate tools/gate.nim   # the failure gate, once

build/unigate testAll    # Nim debug + release + C ABI
build/unigate pyTest     # Cython + pytest (needs libUniDAV.so)
build/unigate example
build/unigate coverage   # gcov + lcov -> coverage/ (needs lcov; linux/macOS)
build/unigate docs       # nimib book + API reference -> pages/ (needs nimib)
build/unigate canary     # must fail
```

Never `nimble <task>` bare where the answer matters: nimble 0.22 exits 0 even
when an `exec` inside the task failed. The gate reads the task's own success
marker instead, which is the only evidence it ran to its last line.

`nimble docs` needs a complete Nim distribution: `--project` builds `dochack`,
which Homebrew's `nim` omits (no `tools/`). choosenim and the CI action ship it.

CI: Nim, C ABI and Python each on ubuntu/macOS/Windows; lint, docs and
coverage on ubuntu; a canary job that must fail; `all-green` over all of them.

## Conventions

- English comments, terse, describe what is done. No "deprecated".
- NimContracts `{.contractual.}` + `require:`/`ensure:`/`body:`, compiled away
  under `-d:release`. C ABI never raises — it clamps out-of-range input.
- A postcondition is cheaper than the body: never re-derives the result by
  calling the function itself.
- C ABI: hand-written `include/UniDAV.h` kept in sync with
  `src/UniDAV/c_api.nim`; `tests/c` links the header against the lib.
  Built `--app:staticlib`/`--app:lib --noMain --mm:arc -d:release`.
- A change to `c_api.nim` is verified by `ctest`, `pyTest` and, where there
  is one, `wasmTest`: three linkages, three runtime bootstraps. A green
  `ctest` alone proved nothing the day the shared build lost its
  initializer and every registry answered with the sentinel.
- C symbols `unidav_*` — the library's own name in lower case, not a
  short token: a binary linking several engines holds them in one namespace.
  Lib `libUniDAV`; header `UniDAV.h`.
- `book/index.nim` is nimib: its code blocks are compiled and run at docs build,
  so prose that outlives its API breaks the build. `py/notebooks/quickstart.ipynb`
  plays the same role for Python and renders natively on GitHub.
- End covered sources with a blank line. Nim maps a trailing statement one line
  past EOF; without that line lcov aborts on `range`/`unmapped`, and `coverage`
  keeps those fatal so the failure stays visible. It ignores exactly one error,
  `mismatch`, which lcov 2.0 raises on a NimContracts-generated destructor and
  lcov 2.5 does not — a compiler-generated symbol, not a line of the library.

- The SQLite cache goes through UniDatabase, which compiles SQLite in. Nothing
  loads `sqlite3.dll` at run time -- verified on Windows with a PATH holding
  only system32: the built binary imports KERNEL32, the UCRT and WINHTTP, and
  nothing else. `db_connector` needed a system SQLite, which a CI runner has
  not got.
- `row` gives an empty seq when there is no row. db_connector gave a row of
  empty strings, so callers tested the first column -- which could not tell "no
  such account" from "an account whose name is empty".

## Scope

GitHub template repository for the `Uni*` family: "Use this template" starts an
engine with the layout, the gates and the CI in place. Apache-2.0, DCO.
