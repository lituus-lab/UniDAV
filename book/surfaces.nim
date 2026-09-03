# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, osproc, strutils]
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "Surfaces"

const Root = currentSourcePath().parentDir.parentDir

proc run(command: string): string =
  ## Run a command from the repository root and return its output. Used so the
  ## C and Python results on this page are produced rather than transcribed.
  ##
  ## A non-zero exit stops the book. Returning the failure as text instead
  ## would publish a page whose "output" is a traceback, from a build that
  ## reported success -- which is exactly what happened before this raised.
  let (output, code) = execCmdEx("cd " & Root.quoteShell & " && " & command)
  result = output.strip
  if code != 0:
    raise newException(OSError,
      "book: `" & command & "` exited " & $code & "\n" & result)

nbText: """
# Surfaces

The same function reaches three audiences, and out of its domain it does three
different things. That is not an inconsistency to be tidied away — each surface
does what its callers can act on — but it is the thing a reader most needs
stated, so it is stated here rather than implied three times.

| Surface | Out of domain | Why |
|---|---|---|
| Nim, debug | raises `PreConditionDefect` | the caller made a mistake and can be told |
| Nim, release | no check | the contract compiled away |
| C | **clamps** | a Nim exception unwinding into C is undefined behaviour |
| Python | raises `ValueError` / `TypeError` | Python callers expect an exception |

## The C ABI clamps

`unidav_fibonacci(n)` answers for every `int` a caller can pass. Below the
domain it gives 0, above it gives `fibonacci(FibMaxN)`. It never raises, and
`{.raises: [].}` on the boundary is what proves that rather than a convention
someone has to remember.
"""

nbCode:
  echo run("cc -Iinclude -o build/book_c_demo book/surfaces_demo.c " &
          "libUniDAV.a 2>&1 && ./build/book_c_demo")

nbText: """
Clamping is a choice, not the only one. It suits a function that has an answer
at every `n`; a library whose failure carries information — a parse that failed
*where* — reports in-band instead, with a sentinel the caller must test. Say
which one you chose, in the words the header uses.

## The Python binding raises

The binding checks the domain in Python before it reaches C, so the clamp is
never observed from there. `FIB_MAX_N` is read from the C header through
Cython rather than restated, so what a caller is checked against is exactly
what the C ABI would clamp to.
"""

nbCode:
  echo run("""PYTHONPATH=py python3 -c '
import unidav as u
print("FIB_MAX_N from the header:", u.FIB_MAX_N)
for bad in (-1, u.FIB_MAX_N + 1, 1.0):
    try:
        u.fibonacci(bad)
    except (ValueError, TypeError) as exc:
        print(f"  fibonacci({bad!r}) -> {type(exc).__name__}: {exc}")
'""")

nbText: """
## Where they differ in meaning, not syntax

Three differences a caller has to know, none of which is visible from a
signature:

- **The C surface answers where Nim refuses.** A C caller passing -1 gets 0,
  not an error, so a C program cannot discover a bad index by calling this.
  Validate before the boundary, not after it.
- **The release build agrees with neither.** It has no check and no clamp; it
  returns whatever the arithmetic gives, and aborts on overflow.
- **`_core` is importable and unchecked.** `unidav._core.fibonacci` is the
  raw C call, and its own docstring says so. The domain check lives in the
  package, not in the extension.

## What this chapter is for

Every engine cloned from this template has this chapter, with its own three
behaviours. If all three agree, say so — that is worth a sentence. If they do
not, this is where a reader finds out, and finding out here is much cheaper
than finding out from a caller's bug report.
"""

nbSave
