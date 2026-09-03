<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Changelog

Notable changes, newest first. Format after
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The C ABI has its own compatibility: a symbol removed or retyped is a major
change, whatever the Nim API did.

## [Unreleased]

### Added

- `tools/gate.nim`, and a success marker on every task. Nimble 0.22 exits 0
  when an `exec` inside a task failed, so its exit code proves nothing; the
  gate reads the marker instead.
- A `canary` task that must fail, and a CI job that checks it does.
- An `all-green` job over every other job: one check for branch protection,
  and a skipped job can no longer pass for a green one.
- `tests/test_version.nim`, which reads the version out of the manifest, the
  Nim constant, the C header, the C ABI and the Python packaging, and fails
  when one drifts.
- `CODE_OF_CONDUCT.md`, `CITATION.cff`, `.editorconfig`, this file.

### Changed

- The C ABI takes the once-primitive runtime guard and `raises: []` that every
  library cloned from here already had.
- The PyPI distribution becomes `lituus-unidav`; the import name stays
  `unidav`.
- Nim minimum 2.0 to 2.2.
- Every GitHub action is pinned by commit SHA.
- Coverage below 90% fails, instead of being reported and ignored.
- Pages deploys only where `PUBLISH_PAGES` is set.
- The Python binding reads the domain bound from the C header rather than
  restating it.

### Fixed

- Documentation that the code contradicted: the C prefix, what `--noMain`
  implies, NimContracts described as optional, a library that does not exist,
  eight numbered layers nothing defines, the platforms the C ABI is tested on,
  and a NimContracts branch deleted upstream.
