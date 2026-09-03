# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, osproc, strutils]
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "The Python surface"

const Root = currentSourcePath().parentDir.parentDir

proc run(command: string): string =
  let (output, code) = execCmdEx("cd " & Root.quoteShell & " && " & command)
  result = output.strip
  if code != 0:
    raise newException(OSError,
      "book: `" & command & "` exited " & $code & "\n" & result)

nbText: """
# The Python surface

A Cython extension over the C ABI. The JSON the C entry points return is
decoded here, so a Python caller gets dicts and lists rather than strings to
parse — and the `unidav_free` discipline of the layer underneath is not
something they ever have to think about.
"""

nbCode:
  echo run("""PYTHONPATH=py python3 -c '
import unidav

card = ("begin:vcard\nversion:4.0\nuid:urn:uuid:ada\n"
        "fn:Ada Lovelace\nemail:ada@example.org\nend:vcard\n")

print("version:  ", unidav.version())
print("valid:    ", unidav.validate(card)["valid"])
print("projected:", unidav.project(card)["name"]["full"])
print("normalised lines:", len(unidav.normalize(card).strip().split("\r\n")))
'""")

nbText: """
## Merging is where a sync client lives

Two sides changed the same contact. `merge` takes the common ancestor and both
versions, and answers with a document plus the conflicts it could not decide —
rather than picking a winner quietly.
"""

nbCode:
  echo run("""PYTHONPATH=py python3 -c '
import unidav

base  = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:a\r\nFN:Ada\r\nEND:VCARD\r\n"
local = base.replace("FN:Ada", "FN:Grace")
outcome = unidav.merge(base, local, base)
print("merged FN:", "FN:Grace" in outcome["document"])
print("conflicts:", outcome["conflicts"])

both = base.replace("FN:Ada", "FN:Katherine")
clash = unidav.merge(base, local, both)
print("clashing conflicts:", len(clash["conflicts"]) > 0)
'""")

nbText: """
## The distribution

`pip install lituus-unidav`; the import name stays `unidav`. The wheel bundles
the shared library beside the extension and finds it through an rpath relative
to it, so an installed package needs nothing else on the system.
"""

nbSave
