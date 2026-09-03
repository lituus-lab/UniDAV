# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## The shapes UniDAV works on, end to end: validate a vCard, normalise it,
## project it to the neutral record a caller stores, and expand a recurrence
## rule. Nothing here touches a network or a file.
import std/[strutils, times]
import UniDAV

proc main() =
  echo "UniDAV " & UniDAVVersion

  const card = "begin:vcard\nversion:4.0\nuid:urn:uuid:ada\nfn:Ada Lovelace\n" &
    "email:ada@example.org\nend:vcard\n"

  echo "--- valid ---"
  echo validationJson(card)

  # Line endings, folding and case are the format's business, not the caller's:
  # what goes in loosely comes back as the wire form the standard requires.
  let normalised = normalizeDocument(card)
  echo "--- normalised ---"
  echo normalised.strip.replace("\r\n", " | ")

  echo "--- projected ---"
  echo projectionJson(normalised)

  # Every expansion is given a window and a ceiling. A rule with neither UNTIL
  # nor COUNT is unbounded by definition, and the caller says where to stop
  # rather than the library guessing.
  echo "--- occurrences ---"
  let window = RecurrenceWindow(
    first: dateTime(2026, mJan, 1, 0, 0, 0, zone = utc()),
    last: dateTime(2026, mFeb, 1, 0, 0, 0, zone = utc()),
    maxOccurrences: 10)
  for at in expandRecurrence("20260105T090000Z", "FREQ=WEEKLY;BYDAY=MO", window):
    echo "  ", at

when isMainModule:
  main()
