# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "Formats"

nbText: """
# Formats

vCard and iCalendar are the same shape underneath: content lines, folded to 75
octets, grouped into nested components. UniDAV parses that shape once and both
formats fall out of it.

## Content lines, and why folding is not cosmetic

A long value is split across lines with a leading space on each continuation.
Un-folding is not optional — a parser that reads lines naively gets a truncated
value and no error.
"""

nbCode:
  import std/strutils
  import UniDAV

  const folded = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada Lovelace\r\n" &
    "NOTE:the first published algorithm intended to be carried out by a mach\r\n" &
    " ine, written in 1843\r\nEND:VCARD\r\n"

  let components = parseComponents(folded)
  for note in components[0].properties("NOTE"):
    echo "NOTE = ", note.value

nbText: """
Note where the break falls: in the middle of `machine`. That is legal, and it
is why unfolding cannot be "join the lines with a space" — the continuation's
leading space is the fold marker and is removed, so a fold placed after a space
would swallow it.

## What a round trip preserves, and what it does not

Serialising what was parsed does **not** give the input bytes back: the fold
position is canonicalised, because where a line was broken carries no meaning.
What survives is every value, and the output is stable — serialise twice and
the second is the first.
"""

nbCode:
  let once = serializeComponents(components)
  echo once.replace("\r\n", "\\r\\n")
  echo "stable:        ",
    serializeComponents(parseComponents(once)) == once
  echo "value kept:    ",
    parseComponents(once)[0].properties("NOTE")[0].value ==
      components[0].properties("NOTE")[0].value

nbText: """
## Validation reports, it does not throw

`validationJson` answers with a verdict and a list of diagnostics. A document
that is wrong is still a document you can look at — which is what a caller
importing a file from an unknown source needs.
"""

nbCode:
  echo validationJson("BEGIN:VCARD\r\nFN:no version\r\nEND:VCARD\r\n")
  echo validationJson("this is not a document")

nbText: """
## The JSON forms

Each format has a JSON encoding the web uses — jCard for vCard, jCal for
iCalendar — and JSContact is the newer contact model. UniDAV converts both
ways, and the conversion is where losslessness is easiest to lose: an encoding
that cannot express a property will drop it.
"""

nbCode:
  const card = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\n" &
    "FN:Ada Lovelace\r\nEMAIL:ada@example.org\r\nEND:VCARD\r\n"
  echo "jCard:     ", jCardJson(card)
  echo "round trip equal: ", documentFromJCard(jCardJson(card)) == card

nbSave
