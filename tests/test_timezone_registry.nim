# SPDX-License-Identifier: Apache-2.0
import std/unittest
import UniDAV

const timezoneText =
  "BEGIN:VTIMEZONE\r\nTZID:Europe/Test\r\n" &
  "BEGIN:STANDARD\r\nDTSTART:20261025T030000\r\n" &
  "TZOFFSETFROM:+0200\r\nTZOFFSETTO:+0100\r\nTZNAME:CET\r\n" &
  "END:STANDARD\r\nBEGIN:DAYLIGHT\r\nDTSTART:20260329T020000\r\n" &
  "TZOFFSETFROM:+0100\r\nTZOFFSETTO:+0200\r\nTZNAME:CEST\r\n" &
  "END:DAYLIGHT\r\nEND:VTIMEZONE\r\n"

suite "bounded VTIMEZONE registry":
  test "registers explicit standard and daylight observances":
    let registry = newTimezoneRegistry()
    registry.registerTimezone(parseComponents(timezoneText)[0])
    check registry.hasTimezone("Europe/Test")
    check registry.offsetAt("Europe/Test", "20260401T120000") == 7200
    check registry.offsetAt("Europe/Test", "20261101T120000") == 3600

  test "rejects malformed offsets and missing observances":
    let registry = newTimezoneRegistry()
    let malformed = parseComponents(
      "BEGIN:VTIMEZONE\r\nTZID:Broken\r\nBEGIN:STANDARD\r\n" &
      "DTSTART:20260101T000000\r\nTZOFFSETFROM:+2500\r\n" &
      "TZOFFSETTO:+0100\r\nEND:STANDARD\r\n" &
      "BEGIN:DAYLIGHT\r\nDTSTART:20270101T000000\r\n" &
      "RDATE:20260315T000000\r\nTZOFFSETFROM:+0100\r\n" &
      "TZOFFSETTO:+0200\r\nEND:DAYLIGHT\r\nEND:VTIMEZONE\r\n")[0]
    expect TimezoneRegistryError:
      registry.registerTimezone(malformed)
    let empty = parseComponents(
      "BEGIN:VTIMEZONE\r\nTZID:Empty\r\nEND:VTIMEZONE\r\n")[0]
    expect TimezoneRegistryError:
      registry.registerTimezone(empty)
    expect TimezoneRegistryError:
      discard registry.offsetAt("Unknown/Zone", "20260201T120000")

  test "expands recurring and explicit observance transitions":
    let recurring = parseComponents(
      "BEGIN:VTIMEZONE\r\nTZID:Europe/Recurring\r\n" &
      "BEGIN:STANDARD\r\nDTSTART:20250101T000000\r\n" &
      "RRULE:FREQ=YEARLY;BYMONTH=10;BYMONTHDAY=27\r\n" &
      "TZOFFSETFROM:+0200\r\n" &
      "TZOFFSETTO:+0100\r\nEND:STANDARD\r\n" &
      "BEGIN:DAYLIGHT\r\nDTSTART:20270101T000000\r\n" &
      "RDATE:20260315T000000\r\nTZOFFSETFROM:+0100\r\n" &
      "TZOFFSETTO:+0200\r\nEND:DAYLIGHT\r\nEND:VTIMEZONE\r\n")[0]
    let registry = newTimezoneRegistry()
    registry.registerTimezone(recurring)
    check registry.timezone("Europe/Recurring").observances[
        1].recurrenceDates.len == 1
    check registry.timezone("Europe/Recurring").observances[
        1].offsetToSeconds == 7200
    check registry.offsetAt("Europe/Recurring", "20260301T120000") == 3600
    check registry.offsetAt("Europe/Recurring", "20260320T120000") == 7200
    check registry.offsetAt("Europe/Recurring", "20261028T120000") == 3600
