<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniDAV

Calendars and contacts, as a library, for the `lituus-lab` `Uni*` family.
UniDAV reads and writes the formats the data actually lives in — vCard and
iCalendar — and speaks the two protocols servers offer it over, CardDAV and
CalDAV.

Its rule is **lossless**: the ordered document tree is the source of truth, and
a property this library does not understand survives a round trip untouched.
Typed projections sit on top, so a host can show a name and an email without
first understanding every extension a phone put there.

Four surfaces, one engine: **Nim**, a **C ABI**, a **Python** binding, and a
**WASM** facade. The HTTP transport is separable — the bundled one is libcurl
on Unix and WinHTTP on Windows, compiled from `csrc/` — so a caller can bring
their own stack, and the tests can bring a fixture.

**Status: incubating.** The `0.x` C ABI is not frozen.

## Layout

```text
src/UniDAV.nim               umbrella module
src/UniDAV/                  21 modules, layered bottom-up; see vgraph.cfg
src/UniDAV/c_api.nim         C ABI
src/UniDAV/wasm_api.nim      WASM facade
csrc/                        the hardened HTTP transports
include/UniDAV.h             hand-written C header
bin/unidav.nim               the CLI
tests/                       the Nim suites
tests/c/                     C ABI test (links the header against the lib)
tests/oracles/               fixtures checked against independent Python parsers
tests/interop/               opt-in suites against a real DAV server
bench/                       deterministic local benchmarks
examples/                    Nim + C demos
py/                          Cython binding + pytest
book/                        the five-chapter book
ADRs/                        0001-0010
tools/gate.nim               the failure gate (see "Running a task")
tests/canary_broken.nim      does not compile, on purpose
tests/test_version.nim       the version's copies must agree
.github/workflows/ci.yml     3-OS Nim matrix + C ABI + Python + all-green
```

## Build

```bash
nimble install -y
nim c --hints:off -o:build/unigate tools/gate.nim   # the failure gate, once

build/unigate testAll        # debug + release + C ABI
build/unigate ctest          # C ABI: static lib + tests/c
build/unigate example        # Nim demo
build/unigate cexample       # C demo
build/unigate pyTest         # Cython + pytest
build/unigate coverage       # gcov + lcov -> coverage/
build/unigate docs           # book + API reference -> pages/
build/unigate canary         # must fail: proves the gate still works
```

Opt-in, because each needs something this repo does not ship: `wasmTest`
(Emscripten and node), `testOracles` (Python PIM parsers), `testInterop` and
`testRadicale` (a prepared DAV server).

`bench` and `benchReadme` are opt-in for a different reason: they need nothing
this repo lacks, they need *this* machine. A number measured elsewhere says
nothing here.

## Using it

```nim
import UniDAV

proc main() =
  const card = "begin:vcard\nversion:4.0\nuid:urn:uuid:ada\n" &
    "fn:Ada Lovelace\nend:vcard\n"

  echo validationJson(card)          # a verdict and its diagnostics
  echo normalizeDocument(card)       # the wire form the standard requires
  echo projectionJson(card)          # the neutral record a host displays

main()
```

Normalising is not filtering: a property UniDAV has no opinion about comes back
untouched. The projection is a *view* — take it to display, keep the document
to store.

The PyPI distribution is `lituus-unidav`; the import name stays `unidav`.
Distribution and import are separate decisions, and the bare names are not all
available.

## Running a task

Nimble 0.22 exits 0 even when an `exec` inside a task failed: the exception is
printed, the task stops, and the process still reports success. `nimble test`
coming back 0 therefore proves only that nimble ran. Every task here ends by
writing its own success marker, and `tools/gate.nim` is what turns a missing
marker into a non-zero exit.

Run tasks through `build/unigate`, never bare, wherever the answer matters.
`build/unigate canary` compiles a source that cannot compile and must come back
non-zero; a CI job checks exactly that, because a gate nobody tests is a gate
nobody can trust.

## CI

`test`, `cabi` and `python` on ubuntu/macOS/Windows. `consume-cabi` and
`consume-wheel` rebuild against the published artifacts on a machine without Nim,
so what ships is what was tested. `coverage` and `docs` run on ubuntu. `canary`
checks that the gate still rejects a broken build.

`all-green` gathers every job's result and is the single check branch protection
requires: a job that was skipped or cancelled cannot pass for one that ran.

`dco` blocks PRs missing a `Signed-off-by` trailer; `commitizen` blocks PRs whose
commits or title are not [Conventional Commits](https://www.conventionalcommits.org/)
(`CONTRIBUTING.md`).

The same gates run locally with pre-commit: `pip install pre-commit && pre-commit install`
(`CONTRIBUTING.md`).

`pages` deploys the built docs, and is opt-in through the `PUBLISH_PAGES`
repository variable. It is off by default: across the family today every one of
these deployments reports success while every site answers 404, and a job that
is red forever teaches everyone to ignore red.

## AI-assisted contributions

Assistance from AI/LLM tools is welcome on the same terms as any other
contribution.

- **Accountability.** The human contributor is the author and remains fully
  responsible for the change. The DCO sign-off (`Signed-off-by`) is the mechanism:
  by signing you certify the content is yours or properly licensed — this covers
  AI-assisted work, provided you can stand behind it.
- **No third-party contamination.** Ensure AI output introduces no code from a
  third party without a compatible license and attribution. If an LLM reproduced
  protected material, do not submit it.
- **Correctness is yours.** The gates (tests, `nimble lint`, conventional commits,
  pre-commit) catch a lot, but you own the result — review and verify what you
  commit.
- **Atomic commits.** Each commit is one logical change. A PR may stack
  several atomic commits (one per element, say) — one monolithic big-bang
  commit is not.
- **Disclosure.** State in the PR whether AI assistance was used (see the PR
  template). It is not a hard requirement — the DCO remains the gate.

## License

Apache-2.0 (`LICENSE`). DCO sign-off on every commit (`CONTRIBUTING.md`).
