# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "UniDAV"

nbText: """
# UniDAV

The scaffold every `lituus-lab` `Uni*` engine starts from. Press **Use this
template** on GitHub and a new engine begins with this layout, these gates and
this CI already in place.

It carries one hello-world function, `fibonacci`, exposed across the three
surfaces every engine ships: **Nim**, a **C ABI**, and a **Python** binding.
The function is not the point. The shape is: what a chapter contains, what is
shown rather than asserted, and where each surface differs from the others.

**Read this front to back.** Each chapter uses what the one before it
introduced, and the last two are about failure, which is where the three
surfaces stop agreeing.

## Installing

```bash
nimble install https://github.com/lituus-lab/UniDAV    # Nim
pip install lituus-unidav                              # Python
```

For C, the build produces `libUniDAV.a` and `include/UniDAV.h`:

```bash
build/unigate clibStatic
cc -Iinclude your.c libUniDAV.a
```

The PyPI distribution is `lituus-unidav`; the import name stays
`unidav`. Those are two decisions, and the bare names are not all
available.

## What runs here

Every Nim block on these pages is compiled and run when the book is built, and
the output shown is what the code produced. A change that breaks the API breaks
the docs build — so prose that outlived its API cannot ship.

That guarantee covers `nbCode` blocks and nothing else. A fenced block written
inside prose is a picture of code, not code.
"""

nbCode:
  import UniDAV

  echo "version ", UniDAVVersion
  echo "fib(10) = ", fibonacci(10)
  echo "fib(", FibMaxN, ") = ", fibonacci(FibMaxN)

nbText: """
## Supported versions

Nim 2.2 or later, on Linux, macOS and Windows. CPython 3.10 to 3.14, on the
same three. The `0.x` C ABI is not frozen.

## Licence, and where to ask

Apache-2.0. Contributions take a DCO sign-off; see `CONTRIBUTING.md`, and
`CODE_OF_CONDUCT.md` for conduct. Questions and defects go to the repository's
issue tracker.

## What this book does not cover

The build gates (`build/unigate`, the canary, `all-green`), which are in
`README.md`; the layer check in `vgraph.cfg`; and the release workflow. Those
are about the repository rather than the library, and a reader cloning the
template meets them in the README first.
"""

nbSave
