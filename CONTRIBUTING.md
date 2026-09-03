<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Contributing

## License and DCO

UniDAV is Apache-2.0. Every commit signs off the
[Developer Certificate of Origin](https://developercertificate.org/):

```sh
git commit -s
```

## Commit style

Use a Conventional Commits subject with one logical change per commit:

```text
feat(recurrence): expand bounded weekly rules
fix(dav): preserve checkpoint after a failed multiget
docs: explain lossless projection edits
```

Keep the body to the reason and the relevant behavior. Do not add generated
files, personal data, credentials, compatibility-review logs, or co-author
trailers.

## Required checks

Run the tasks relevant to the change and the complete local gate before a
pull request:

```sh
nimble lint
nimble checkVGraph
nimble test
nimble testRelease
nimble ctest
nimble pyTest
```

A DAV regression needs an anonymized fixture and a recovery-path test. Changes
to a public Nim operation also update the surface-completeness manifest or
record a deliberate foreign-interface exclusion in ADR-0005.

## Documentation

Reader-facing claims must be verified against source or execution. Every book
example is compiled and run by the book task. Never paste invented output or
claim blanket standards compliance without matching corpus and interoperability
evidence.

