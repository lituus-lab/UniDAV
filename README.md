<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniDAV

GitHub template repository for the `lituus-lab` `Uni*` libraries. Press **Use
this template** and a new engine starts with the layout, the gates and the CI
already in place. Hello-world: `fibonacci`, in Nim, C ABI, and Python.

**Status: incubating.** The layout, the gates and the CI are in use across the
family and are not expected to move much. The `0.x` C ABI is not frozen, and
this repo is a starting point rather than a dependency: nothing should require
it.

## Layout

```text
src/UniDAV.nim          umbrella module
src/UniDAV/fibonacci.nim  Nim core (NimContracts)
src/UniDAV/c_api.nim    C ABI
include/UniDAV.h        hand-written C header
tests/test_fibonacci.nim     Nim tests
tests/c/                     C ABI test (links the header against the lib)
examples/                    Nim + C demos
py/                          Cython binding + pytest
ADRs/                        0001 DAG, 0002 license, 0003 engine&shell, 0004 conventions
tools/gate.nim               the failure gate (see "Running a task")
tools/lint.nim tools/vgraph.nim  nimpretty check, layer check
tests/canary_broken.nim      does not compile, on purpose
tests/test_version.nim       the version's six copies must agree
.github/workflows/ci.yml     3-OS Nim matrix + C ABI + Python + all-green
CHANGELOG.md CITATION.cff CODE_OF_CONDUCT.md .editorconfig
```

## Build

```bash
nimble install -y
nim c --hints:off -o:build/unigate tools/gate.nim   # the failure gate, once

build/unigate test    # Nim, debug (contracts active), see below
build/unigate testRelease    # Nim, release (contracts compiled away)
build/unigate testAll        # debug + release + C ABI
build/unigate ctest          # C ABI: static lib + tests/c
build/unigate cexample       # C demo
build/unigate example        # Nim demo
build/unigate pyTest         # Cython + pytest
build/unigate coverage       # gcov + lcov -> coverage/
build/unigate book           # nimib book -> book/index.html
build/unigate docs           # book + API reference -> pages/
build/unigate canary         # must fail: proves the gate still works
```

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

## After "Use this template"

Rename the tokens, then replace `fibonacci.nim` with the domain module(s).

| Template | New engine | Example |
|---|---|---|
| `UniDAV` | `UniFoo` | `UniAccurate`, `UniMath` |
| `unidav` | `unifoo` | `uniaccurate`, `unimath` |
| `libUniDAV` | `libUniFoo` | `libUniAccurate` |
| `UniDAV.h` | `UniFoo.h` | `UniAccurate.h` |
| `lituus-unidav` | `lituus-unifoo` | `lituus-uniaccurate` |

The C symbol prefix is the library's own name in lower case —
`unidav_fibonacci`, so `unifoo_*`. Short prefixes read better and collide:
a binary that links several engines at once holds them all in one namespace.

Files to rename: `UniDAV.nimble`, `src/UniDAV.nim`, `src/UniDAV/`,
`include/UniDAV.h`, `tests/c/test_unidav.c` (+ its Makefile target),
`py/unidav/`. Then update `LICENSE`/`NOTICE` copyright and the ADR titles.

The PyPI distribution is `lituus-<module>`; the import name stays `<module>`.
Distribution and import are separate decisions, and the bare names are not all
available.

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
