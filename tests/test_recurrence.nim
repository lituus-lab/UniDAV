# SPDX-License-Identifier: Apache-2.0
import std/[unittest, times]
import UniDAV/[recurrence, timezone_registry, timezone_recurrence, component]

suite "bounded recurrence expansion":
  test "daily count is deterministic and bounded":
    let values = expandRecurrence("20260803T120000Z", "FREQ=DAILY;COUNT=4",
      RecurrenceWindow(first: parse("20260803T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260810T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check values == @["20260803T120000Z", "20260804T120000Z",
        "20260805T120000Z", "20260806T120000Z"]

  test "accepts all-day DATE recurrence values":
    let values = expandRecurrence("20260803", "FREQ=DAILY;COUNT=3",
      RecurrenceWindow(first: parse("20260803T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260806T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check values == @["20260803T000000Z", "20260804T000000Z",
      "20260805T000000Z"]

  test "weekly byday does not leak beyond UNTIL":
    let values = expandRecurrence("20260803T120000Z",
      "FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20260812T120000Z",
      RecurrenceWindow(first: parse("20260801T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260831T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check values == @["20260803T120000Z", "20260805T120000Z",
        "20260810T120000Z", "20260812T120000Z"]

  test "fine-grained frequencies and time filters are bounded":
    let hourly = expandRecurrence("20260803T120000Z", "FREQ=HOURLY;COUNT=3",
      RecurrenceWindow(first: parse("20260803T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260803T235959Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check hourly == @["20260803T120000Z", "20260803T130000Z", "20260803T140000Z"]
    let seconds = expandRecurrence("20260803T120000Z",
      "FREQ=SECONDLY;INTERVAL=2;COUNT=3",
      RecurrenceWindow(first: parse("20260803T120000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260803T120010Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check seconds == @["20260803T120000Z", "20260803T120002Z", "20260803T120004Z"]
    let filtered = expandRecurrence("20260803T120000Z",
      "FREQ=DAILY;BYHOUR=9,12;COUNT=2",
      RecurrenceWindow(first: parse("20260803T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260805T235959Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check filtered == @["20260803T120000Z", "20260804T090000Z"]
    let yearDays = expandRecurrence("20260101T120000Z",
      "FREQ=YEARLY;BYYEARDAY=1,32;COUNT=2",
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20270101T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check yearDays == @["20260101T120000Z", "20260201T120000Z"]
    let weeks = expandRecurrence("20260101T120000Z",
      "FREQ=YEARLY;BYWEEKNO=1;BYDAY=TH;COUNT=1",
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260115T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check weeks == @["20260101T120000Z"]
    let hourSlots = expandRecurrence("20260803T121500Z",
      "FREQ=HOURLY;BYMINUTE=0,30;COUNT=3",
      RecurrenceWindow(first: parse("20260803T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260803T235959Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check hourSlots == @["20260803T123000Z", "20260803T130000Z",
      "20260803T133000Z"]
    let minuteSlots = expandRecurrence("20260803T121515Z",
      "FREQ=MINUTELY;BYSECOND=0,30;COUNT=3",
      RecurrenceWindow(first: parse("20260803T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260803T235959Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check minuteSlots == @["20260803T121530Z", "20260803T121600Z",
      "20260803T121630Z"]
    let finalDays = expandRecurrence("20260101T120000Z",
      "FREQ=YEARLY;BYYEARDAY=-1;COUNT=3",
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20300101T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check finalDays == @["20261231T120000Z", "20271231T120000Z",
      "20281231T120000Z"]
    let yearlyWeekdays = expandRecurrence("20260101T120000Z",
      "FREQ=YEARLY;BYDAY=MO;COUNT=3",
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260201T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check yearlyWeekdays == @["20260105T120000Z", "20260112T120000Z",
      "20260119T120000Z"]
    let yearlyOrdinal = expandRecurrence("20260101T120000Z",
      "FREQ=YEARLY;BYDAY=1MO;COUNT=2",
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20280101T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check yearlyOrdinal == @["20260105T120000Z", "20270104T120000Z"]

  test "BYSETPOS selects deterministic monthly positions":
    let values = expandRecurrence("20260803T120000Z",
      "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=2",
      RecurrenceWindow(first: parse("20260801T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20261001T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check values == @["20260803T120000Z", "20260901T120000Z"]
    let sundayWeeks = expandRecurrence("20260803T120000Z",
      "FREQ=WEEKLY;WKST=SU;BYDAY=SU;COUNT=2",
      RecurrenceWindow(first: parse("20260801T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260820T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check sundayWeeks == @["20260809T120000Z", "20260816T120000Z"]

  test "rejects unbounded caller limits and reversed windows":
    expect RecurrenceLimitError:
      discard expandRecurrence("20260803T120000Z", "FREQ=DAILY",
        RecurrenceWindow(first: parse("20260810T000000Z",
            "yyyyMMdd'T'HHmmss'Z'", utc()), last: parse("20260803T000000Z",
                "yyyyMMdd'T'HHmmss'Z'", utc()),
          maxOccurrences: 10))
    expect RecurrenceLimitError:
      discard expandRecurrence("20260803T120000Z", "FREQ=DAILY",
        RecurrenceWindow(first: parse("20260803T000000Z",
            "yyyyMMdd'T'HHmmss'Z'", utc()),
          last: parse("20260810T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
          maxOccurrences: 100_001))
    expect RecurrenceLimitError:
      discard expandRecurrence("20260803T120000Z",
        "FREQ=DAILY;COUNT=2;UNTIL=20260810T120000Z",
        RecurrenceWindow(first: parse("20260803T000000Z",
            "yyyyMMdd'T'HHmmss'Z'", utc()),
          last: parse("20260810T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
              maxOccurrences: 10))
    for rule in ["FREQ=WEEKLY;BYMONTHDAY=1", "FREQ=DAILY;BYYEARDAY=1",
        "FREQ=MONTHLY;BYWEEKNO=1"]:
      expect RecurrenceLimitError:
        discard expandRecurrence("20260803T120000Z", rule,
          RecurrenceWindow(first: parse("20260803T000000Z",
              "yyyyMMdd'T'HHmmss'Z'", utc()),
            last: parse("20260810T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
                maxOccurrences: 10))
    expect RecurrenceLimitError:
      discard expandRecurrence("20260803", "FREQ=DAILY;UNTIL=20260810T000000Z",
        RecurrenceWindow(first: parse("20260803T000000Z",
            "yyyyMMdd'T'HHmmss'Z'", utc()),
          last: parse("20260810T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
              maxOccurrences: 10))

  test "monthly and yearly month-day filters skip impossible dates":
    let monthly = expandRecurrence("20260131T120000Z", "FREQ=MONTHLY;COUNT=3",
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260701T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check monthly == @["20260131T120000Z", "20260331T120000Z", "20260531T120000Z"]
    let yearly = expandRecurrence("20240229T120000Z", "FREQ=YEARLY;COUNT=3",
      RecurrenceWindow(first: parse("20240101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20300101T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check yearly == @["20240229T120000Z", "20280229T120000Z"]
    let selected = expandRecurrence("20260101T120000Z",
      "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;COUNT=2",
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20320101T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check selected == @["20280229T120000Z"]
    let ordinal = expandRecurrence("20260101T120000Z",
      "FREQ=MONTHLY;BYDAY=1MO,-1FR;COUNT=4",
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260331T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check ordinal == @["20260105T120000Z", "20260130T120000Z",
      "20260202T120000Z", "20260227T120000Z"]

  test "RDATE adds and EXDATE removes deterministic occurrences":
    let values = expandRecurrenceSet("20260803T120000Z", "FREQ=DAILY;COUNT=4",
      @["20260810T120000Z"], @["20260804T120000Z"],
      RecurrenceWindow(first: parse("20260803T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260812T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check values == @["20260803T120000Z", "20260805T120000Z",
      "20260806T120000Z", "20260810T120000Z"]

  test "local wall-clock recurrence converts through VTIMEZONE":
    let roots = parseComponents("BEGIN:VTIMEZONE\r\nTZID:Europe/Test\r\n" &
      "BEGIN:STANDARD\r\nDTSTART:20250101T000000\r\nTZOFFSETFROM:+0100\r\n" &
      "TZOFFSETTO:+0100\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n")
    let registry = newTimezoneRegistry()
    registry.registerTimezone(roots[0])
    let values = expandRecurrenceLocal("20260101T120000", "FREQ=DAILY;COUNT=2",
      "Europe/Test", registry,
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260103T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check values == @["20260101T110000Z", "20260102T110000Z"]
    let allDayValues = expandRecurrenceLocal("20260101", "FREQ=DAILY;COUNT=2",
      "Europe/Test", registry,
      RecurrenceWindow(first: parse("20260101T000000Z", "yyyyMMdd'T'HHmmss'Z'",
          utc()),
        last: parse("20260103T000000Z", "yyyyMMdd'T'HHmmss'Z'", utc()),
            maxOccurrences: 10))
    check allDayValues == @["20260101T000000Z", "20260102T000000Z"]
