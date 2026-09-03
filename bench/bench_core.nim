# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Deterministic local-format benchmark. Built in release mode.
import std/[strformat, strutils, times]
import UniDAV

const Iterations = 2_000

var sink: int
var rows: seq[tuple[name: string, nanoseconds, operations: float64]]

proc keep(value: int) {.inline: false.} =
  sink += value

template measure(label: string; body: untyped) =
  block:
    let benchLabel = label
    let started = cpuTime()
    for _ in 0 ..< Iterations:
      body
    let elapsed = cpuTime() - started
    let nanoseconds = elapsed * 1_000_000_000 / float64(Iterations)
    let operations = if elapsed > 0: float64(Iterations) / elapsed else: 0.0
    rows.add((benchLabel, nanoseconds, operations))
    echo benchLabel, ": ", formatFloat(nanoseconds, ffDecimal, 1), " ns/op"

proc main() =
  let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:ada\r\nFN:Ada Lovelace\r\n" &
    "EMAIL;TYPE=work:ada@example.test\r\nX-ARCHIVE-ID:1843\r\nEND:VCARD\r\n"
  let calendar = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//UniDAV Bench//EN\r\n" &
    "BEGIN:VEVENT\r\nUID:event-1\r\nDTSTART:20260815T120000Z\r\n" &
    "SUMMARY:Review\r\nX-COLOR:blue\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

  measure("parse vCard"):
    keep(parseComponents(card)[0].entries.len)
  measure("parse iCalendar"):
    keep(parseComponents(calendar)[0].entries.len)
  let parsedCard = parseComponents(card)[0]
  let recurrenceWindow = RecurrenceWindow(
    first: parse("20260801T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
    last: parse("20260901T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
    maxOccurrences: 64)
  let timezone = parseComponents(
    "BEGIN:VTIMEZONE\r\nTZID:Bench/Zone\r\nBEGIN:STANDARD\r\n" &
    "DTSTART:20261025T030000\r\nTZOFFSETFROM:+0200\r\n" &
    "TZOFFSETTO:+0100\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n")[0]
  let timezoneRegistry = newTimezoneRegistry()
  timezoneRegistry.registerTimezone(timezone)
  measure("serialize vCard"):
    keep(serializeComponent(parsedCard).len)
  measure("project vCard"):
    keep(projectionJson(card).len)
  measure("expand weekly recurrence"):
    keep(expandRecurrence("20260803T120000Z",
      "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=16",
      recurrenceWindow).len)
  measure("resolve VTIMEZONE offset"):
    keep(timezoneRegistry.offsetAt("Bench/Zone", "20261101T120000"))

  var markdown = "| operation | ns/op | ops/sec |\n|---|---:|---:|\n"
  for row in rows:
    let operations = formatFloat(row.operations, ffDecimal, 0).strip(
      leading = false, chars = {'.'})
    markdown.add &"| {row.name} | {row.nanoseconds:.1f} | {operations} |\n"
  writeFile("bench/.results.md", markdown)
  echo "sink = ", sink

when isMainModule:
  main()
