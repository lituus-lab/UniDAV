# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, osproc, strutils]
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "Contracts"

const Root = currentSourcePath().parentDir.parentDir

proc runNim(name, source, flags: string): string =
  ## Compile and run a fragment, and return what it printed or how it died.
  ## The failures on this page are produced, not transcribed: a pasted error
  ## message is a message nobody re-checked.
  ##
  ## `name` keeps each fragment's source, binary and nimcache apart. Sharing
  ## one output path between a debug and a release build silently ran the
  ## second binary for both, and the page then showed the release answer twice
  ## while claiming one of them was the debug one.
  let dir = getTempDir() / "unidav-book-contracts" / name
  removeDir dir
  createDir dir
  let path = dir / "fragment.nim"
  writeFile(path, source)
  let (output, _) = execCmdEx(
    "nim c -r --hints:off " & flags &
    " --nimcache:" & (dir / "cache").quoteShell &
    " --path:" & (Root / "src").quoteShell &
    " -o:" & (dir / "fragment").quoteShell & " " & path.quoteShell)
  # Absolute paths differ per machine; the page must not carry this one's.
  for line in output.replace(Root & "/", "").splitLines:
    let trimmed = line.strip
    if trimmed.startsWith("Error: unhandled") or trimmed.startsWith("fib(") or
       "Defect" in trimmed:
      result.add trimmed & "\n"
  if result.len == 0: result = output.replace(Root & "/", "").strip & "\n"

nbText: """
# Contracts

`fibonacci` carries a precondition — `n` in `[0, FibMaxN]` — written with
NimContracts and compiled away under `-d:release`. This chapter shows what a
violation does, because a contract described in prose is a contract nobody has
seen fire.

Everything below is produced by compiling and running a fragment during the
book build. None of it is transcribed.

## In a debug build, the precondition raises
"""

const Violation = """
import UniDAV
echo "fib(-1) = ", fibonacci(-1)
"""

nbCode:
  echo runNim("debug", Violation, "")

nbText: """
`PreConditionDefect` names the predicate that broke and where it was promised.
It is a `Defect`, not a `CatchableError`: it reports a caller's mistake, not a
condition the caller could recover from.

## Under `-d:release`, the same call is not checked

The contract compiles away entirely — that is what makes it free in production.
What the function does out of domain is then whatever the arithmetic does.
"""

nbCode:
  echo runNim("release", Violation, "-d:release")

nbText: """
Below the domain the release build returns a number; the guard that would have
refused it is gone. Above the domain it aborts on overflow. Neither is a
contract violation any more — there is no contract in a release build.

**This is the reason the C ABI exists in the shape it does.** A foreign caller
gets neither the debug check nor a Nim exception, so the boundary cannot rely
on either. The next chapter is what it does instead.

## What a postcondition is for

`ensure: result >= 0` is checked on the way out, in debug. It is deliberately
weaker than "the result is the nth Fibonacci number": a postcondition that
recomputed the answer would double the cost and prove only that the function
agrees with itself.
"""

nbSave
