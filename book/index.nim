# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "UniDAV"

nbText: """
# UniDAV

Calendars and contacts, as a library. UniDAV reads and writes the formats
people's data actually lives in — vCard and iCalendar — and speaks the two
protocols servers offer it over, CardDAV and CalDAV.

Its rule is **lossless**: the ordered document tree is the source of truth, and
a property this library does not understand survives a round trip untouched.
Typed projections sit on top so a host can show a name and an email without
first understanding every extension a phone put there.

Four surfaces, one engine: **Nim**, a **C ABI**, a **Python** binding, and a
**WASM** facade for the browser.

**Read this front to back.** Each chapter uses what the one before it
introduced.

## Installing

```bash
nimble install https://github.com/lituus-lab/UniDAV    # Nim
pip install lituus-unidav                              # Python
```

For C, the build produces `libUniDAV.a` and `include/UniDAV.h`:

```bash
build/unigate clibStatic
cc -Iinclude your.c libUniDAV.a -lcurl        # -lwinhttp on Windows
```

The PyPI distribution is `lituus-unidav`; the import name stays `unidav`.

## What runs here

Every Nim block on these pages is compiled and run when the book is built, and
the output shown is what the code produced. A change that breaks the API breaks
the docs build — so prose that outlived its API cannot ship.

That guarantee covers `nbCode` blocks and nothing else. A fenced block written
inside prose is a picture of code, not code.

## A document, end to end
"""

nbCode:
  import std/strutils
  import UniDAV

  const card = "begin:vcard\nversion:4.0\nuid:urn:uuid:ada\n" &
    "fn:Ada Lovelace\nemail:ada@example.org\nx-phone-model:something\n" &
    "end:vcard\n"

  echo "valid:      ", validationJson(card)
  echo "normalised: ", normalizeDocument(card).strip.replace("\r\n", " | ")

nbText: """
Two things happened there. Line endings, folding and case were put right —
that is `normalizeDocument`, and the wire form it emits is the one the standard
requires rather than the one that was typed. And `X-PHONE-MODEL`, which this
library has no opinion about, is still there.

That is the losslessness rule in one line: **normalising is not filtering.**

## The typed view

A host that wants a name and an address should not have to walk a component
tree. `projectionJson` gives the neutral record instead — and it is a *view*,
not the document: nothing is lost by taking it, because the document is still
the thing you store.
"""

nbCode:
  echo projectionJson(normalizeDocument(card))

nbText: """
`x-phone-model` is absent from the projection, and present in the document. A
host that round-trips through the projection alone would drop it; one that
edits the document and projects for display does not.

## Supported versions

Nim 2.2 or later, on Linux, macOS and Windows. CPython 3.10 to 3.14, on the
same three. The `0.x` C ABI is not frozen.

## Licence, and where to ask

Apache-2.0. Contributions take a DCO sign-off; see `CONTRIBUTING.md`, and
`CODE_OF_CONDUCT.md` for conduct. Questions and defects go to the repository's
issue tracker.
"""

nbSave
