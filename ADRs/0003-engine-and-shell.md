<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0003: Engine & Shell

- Status: Accepted
- Date: 2026-07-15
- Scope: every `Uni*` library consumed by a native app

## Decision

- **Engine** (pure Nim): the library + a thin C ABI (`src/<Lib>/c_api.nim`),
  built `--app:staticlib`/`--app:lib --noMain --mm:arc -d:release` →
  `lib<Lib>.a` / `lib<Lib>.so`. No UI in the engine.
- **Shell** (native UI, separate private repo): links the C ABI, owns the UI.
- **C header** (`include/<Lib>.h`): hand-written, kept in sync with `c_api.nim`.
  `tests/c` links the header against the lib — a renamed/retyped symbol fails
  to link, so the C test is the ABI drift detector. (`--header:X.h` auto-gen is
  not used.)
- `--mm:arc`: deterministic memory model for foreign callers (no cycle
  collector). `--noMain`: Nim emits no `main()`, so nothing calls `NimMain()`
  on its own — and no build gets one for free. The shared library was long
  assumed to be covered by a DllMain or an ELF constructor; it is not, and the
  registries of every library that believed it stayed empty until a caller ran
  the initializer by hand. Every entry point in `c_api.nim` opens with
  `ensureRuntime()`, and every `--noMain` build — static, shared and wasm
  alike — passes `-d:noAutoInit` so that call is the once primitive rather
  than a no-op. Only an ordinary executable linking the module leaves it out,
  its own `main` having already run `NimMain`.
- **Python binding**: Cython over the shared lib, RPATH `$ORIGIN`.
