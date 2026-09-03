<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Contributing

## License

Apache-2.0 (`LICENSE`).

## DCO

Every commit signs off the [Developer Certificate of Origin](https://developercertificate.org/):

```bash
git commit -s
```

Commits without a `Signed-off-by` trailer are not accepted.

## Conventional commits

Commit subjects and the PR title follow [Conventional Commits 1.0](https://www.conventionalcommits.org/):

```text
<type>(scope)!: <description>
```

`type` is one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`, `revert`, `bump`. `scope` and `!` (breaking change) are
optional. A space separates the colon from the description.

```text
feat(c_api): expose the domain bound to C callers
fix(c_api): clamp a negative index instead of raising
docs: say which platforms the C ABI is tested on
feat(core)!: drop the old accumulator API
```

The `commitizen` CI job blocks the PR if any non-merge commit — or the PR
title — does not match. The title matters because a squash-merge folds the
whole PR into one commit whose subject is the title.

## Workflow

1. Branch from `main`, one logical change per commit.
2. Pass the gates: `build/unigate testAll`, `build/unigate pyTest`. Through
   `build/unigate`, not `nimble` — nimble exits 0 even when a task failed, so
   a bare run tells you nothing. Build it once with
   `nim c --hints:off -o:build/unigate tools/gate.nim`.
3. Open a PR. CI runs Nim, the C ABI and Python on ubuntu/macOS/Windows, plus
   lint, docs, coverage, and a canary that must fail. `all-green` is the check
   that has to be green.

## Pre-commit

The CI gates also run locally via [pre-commit](https://pre-commit.com):

```bash
pip install pre-commit
pre-commit install
```

`pre-commit install` sets up the pre-commit, pre-push and commit-msg hooks at
once. Hooks: hygiene (trailing whitespace, EOF, yaml/toml, large files),
`lint` on `*.nim`, `checkVGraph` before push, Conventional Commits via
`cz check` on the commit message, and a DCO sign-off check. The two nimble
tasks go through `tools/hooks/gated.sh`, for the reason above. Run everything
manually:

```bash
pre-commit run --all-files
```

## Conduct

See `CODE_OF_CONDUCT.md`. Report a problem privately to the maintainer.

## Conventions

See `ADRs/0004` and `AGENTS.md`. English comments, terse, describe what is done.
NimContracts compiled away under `-d:release`; the C ABI clamps, never raises.
