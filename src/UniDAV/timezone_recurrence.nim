# SPDX-License-Identifier: Apache-2.0
## Bounded wall-clock recurrence conversion through explicit VTIMEZONE data.
import std/[algorithm, sequtils, sets, times, strutils]
import recurrence, timezone_registry

proc compactUtc(dt: DateTime): string = dt.format("yyyyMMdd'T'HHmmss'Z'")

proc parseUtcValue(value: string): DateTime =
  try: parse(value, "yyyyMMdd'T'HHmmss'Z'", utc())
  except ValueError: raise newException(RecurrenceLimitError, "unsupported recurrence value")

proc expandRecurrenceLocal*(startValue, rule, tzid: string;
                            registry: TimezoneRegistry;
                            window: RecurrenceWindow): seq[string] =
  ## Expands wall-clock recurrences and converts each occurrence through a bounded VTIMEZONE.
  ## A small padding avoids dropping occurrences near UTC window edges.
  if registry.isNil:
    raise newException(RecurrenceLimitError, "timezone registry is required")
  ## DATE values are all-day floating values and must not be shifted by a
  ## timezone offset; DATE-TIME values use the supplied VTIMEZONE.
  let dateOnly = startValue.len == 8
  let wallStart = if startValue.endsWith("Z"): startValue
    elif startValue.len == 8: startValue & "T000000Z"
    else: startValue & "Z"
  let padded = RecurrenceWindow(first: window.first - initDuration(days = 2),
    last: window.last + initDuration(days = 2),
        maxOccurrences: window.maxOccurrences)
  let walls = expandRecurrence(wallStart, rule, padded)
  var unique = initHashSet[string]()
  for wall in walls:
    let offset = registry.offsetAt(tzid, wall)
    let utcValue = if dateOnly: parseUtcValue(wall)
      else: parseUtcValue(wall) - initDuration(seconds = offset)
    if utcValue >= window.first and utcValue <= window.last:
      unique.incl(compactUtc(utcValue))
  result = toSeq(unique)
  result.sort(system.cmp[string])
  if result.len > window.maxOccurrences:
    result.setLen(window.maxOccurrences)
