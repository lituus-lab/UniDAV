<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# The Book

A nimibook table of contents, one chapter per file. Every code block is
compiled and run when the book is built, so prose that outlives its API breaks
the build rather than quietly misleading a reader.

| File | What it is |
|---|---|
| `nbook.nim` | the table of contents and the theme selection — the driver |
| `nimib.toml` | nimib's own configuration, read from this directory |
| `config.nims` | the paths each chapter's own compilation needs |
| `index.nim` | the opening chapter |
| `fibonacci.nim`, `contracts.nim`, `surfaces.nim` | the chapters |

## Building it

```bash
build/unigate book     # the book alone
build/unigate docs     # book + generated API reference, into pages/
```

`book` builds what the chapters are going to run — the C static library and
the Python extension — and runs nimibook's `init` before `build`. `init` is
what creates `__site/assets`, which is not tracked: without it every page
ships referencing a stylesheet and a script that are not there, and nothing
says so until someone opens the site.

Through the gate, never `nimble book` directly: nimble exits 0 even when an
`exec` inside a task fails, so a green run that went through it proves nothing.

## Adding a chapter

Add the entry to `nbook.nim`'s table of contents, then:

```bash
nimble bookInit        # scaffolds the missing source
```

Each chapter calls `nbInit(theme = useNimibook)` itself and then `useLituus()`.
`nbInit` cannot be wrapped: it reads `instantiationInfo(-1)` to learn which
file it is documenting, so a template calling it from another module makes
every chapter claim to be that module, and nimibook then writes no HTML at all.
