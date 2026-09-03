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
nim c --hints:off -o:build/unigate tools/gate.nim   # once

build/unigate lint
build/unigate checkVGraph
build/unigate test
build/unigate testRelease
build/unigate ctest
build/unigate pyTest
```

Through the gate, never `nimble <task>` bare: nimble exits 0 even when an
`exec` inside a task failed, so a green run tells you only that nimble ran.
The gate reads the marker each task writes on its last line.

A DAV regression needs an anonymized fixture and a recovery-path test. Changes
to a public Nim operation also update the surface-completeness manifest or
record a deliberate foreign-interface exclusion in an ADR.

## Documentation

Reader-facing claims must be verified against source or execution. Every book
example is compiled and run by the book task. Never paste invented output or
claim blanket standards compliance without matching corpus and interoperability
evidence.

