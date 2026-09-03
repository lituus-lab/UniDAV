# SPDX-License-Identifier: Apache-2.0
## Bounded VTIMEZONE registry for explicit observance offsets.
import std/[tables, times, strutils]
import component, recurrence

const
  MaxTimezoneIdBytes* = 255
  MaxTimezoneDefinitions* = 256
  MaxTimezoneObservances* = 64

type
  TimezoneRegistryError* = object of CatchableError
  TimezoneObservance* = object
    kind*: string
    start*: DateTime
    offsetFromSeconds*: int
    offsetToSeconds*: int
    name*: string
    recurrenceRule*: string
    recurrenceDates*: seq[DateTime]
  TimezoneDefinition* = object
    tzid*: string
    observances*: seq[TimezoneObservance]
  TimezoneRegistry* = ref object
    definitions: Table[string, TimezoneDefinition]

proc newTimezoneRegistry*(): TimezoneRegistry =
  TimezoneRegistry(definitions: initTable[string, TimezoneDefinition]())

proc validTzid(value: string): bool =
  value.len > 0 and value.len <= MaxTimezoneIdBytes and
    value.allCharsInSet({' '..'~'}) and not value.contains({'\r', '\n'})

proc parseOffset(value: string): int =
  ## `+HHMM` and `+HHMMSS`, the two forms RFC 5545 allows. The seven-character
  ## one was refused here while `document.validOffset` accepted it, so a
  ## VTIMEZONE that validated could not be registered.
  if value.len notin [5, 7] or value[0] notin ['+', '-'] or
      not value[1 .. ^1].allCharsInSet({'0'..'9'}):
    raise newException(TimezoneRegistryError, "invalid VTIMEZONE offset")
  let hours = parseInt(value[1..2])
  let minutes = parseInt(value[3..4])
  let extraSeconds = if value.len == 7: parseInt(value[5..6]) else: 0
  if hours > 23 or minutes > 59 or extraSeconds > 59:
    raise newException(TimezoneRegistryError, "invalid VTIMEZONE offset")
  let total = hours * 3600 + minutes * 60 + extraSeconds
  if value[0] == '-': -total else: total

proc parseTransition(value: string): DateTime =
  try:
    if value.len == 15 and value[8] == 'T':
      return parse(value, "yyyyMMdd'T'HHmmss", utc())
    if value.len == 16 and value[8] == 'T' and value[^1] == 'Z':
      return parse(value, "yyyyMMdd'T'HHmmss'Z'", utc())
  except ValueError:
    discard
  raise newException(TimezoneRegistryError, "invalid VTIMEZONE DTSTART")

proc normalizeUntil(rule: string): string =
  ## RFC 5545 VTIMEZONE RRULE UNTIL values are local wall times.
  ## The bounded recurrence primitive consumes UTC-shaped values, so retain
  ## the wall-clock fields while adding its required marker.
  result = rule
  var parts: seq[string]
  for part in rule.split(';'):
    if part.toUpperAscii.startsWith("UNTIL="):
      let raw = part[6 .. ^1]
      let normalized = if raw.len == 8:
        raw & "T000000Z"
      elif raw.len == 15:
        raw & "Z"
      else:
        raw
      parts.add("UNTIL=" & normalized)
    else:
      parts.add(part)
  result = parts.join(";")

proc propertyValue(component: Component; name: string): string =
  let values = component.properties(name)
  if values.len == 1: values[0].value
  elif values.len == 0: ""
  else: raise newException(TimezoneRegistryError, "duplicate VTIMEZONE property")

proc propertyValues(component: Component; name: string): seq[string] =
  for property in component.properties(name):
    result.add(property.value)

proc registerTimezone*(registry: TimezoneRegistry; timezone: Component) =
  if registry.isNil or timezone.isNil or timezone.name.toUpperAscii != "VTIMEZONE":
    raise newException(TimezoneRegistryError, "expected VTIMEZONE component")
  let tzid = timezone.propertyValue("TZID")
  if not validTzid(tzid):
    raise newException(TimezoneRegistryError, "invalid VTIMEZONE TZID")
  if registry.definitions.len >= MaxTimezoneDefinitions and
      not registry.definitions.hasKey(tzid):
    raise newException(TimezoneRegistryError, "timezone registry is full")
  var definition = TimezoneDefinition(tzid: tzid)
  for observance in timezone.children():
    if observance.name notin ["STANDARD", "DAYLIGHT"]: continue
    if definition.observances.len >= MaxTimezoneObservances:
      raise newException(TimezoneRegistryError, "too many VTIMEZONE observances")
    let start = parseTransition(observance.propertyValue("DTSTART"))
    let fromOffset = parseOffset(observance.propertyValue("TZOFFSETFROM"))
    let toOffset = parseOffset(observance.propertyValue("TZOFFSETTO"))
    let rules = observance.propertyValues("RRULE")
    if rules.len > 1:
      raise newException(TimezoneRegistryError, "duplicate VTIMEZONE RRULE")
    var recurrenceDates: seq[DateTime]
    for value in observance.propertyValues("RDATE"):
      for dateValue in value.split(','):
        recurrenceDates.add(parseTransition(dateValue.strip))
    definition.observances.add(TimezoneObservance(kind: observance.name,
      start: start, offsetFromSeconds: fromOffset, offsetToSeconds: toOffset,
      name: observance.propertyValue("TZNAME"),
      recurrenceRule: if rules.len == 1: normalizeUntil(rules[0]) else: "",
      recurrenceDates: recurrenceDates))
  if definition.observances.len == 0:
    raise newException(TimezoneRegistryError, "VTIMEZONE has no observances")
  registry.definitions[tzid] = definition

proc hasTimezone*(registry: TimezoneRegistry; tzid: string): bool =
  not registry.isNil and registry.definitions.hasKey(tzid)

proc timezone*(registry: TimezoneRegistry; tzid: string): TimezoneDefinition =
  if registry.isNil or not registry.definitions.hasKey(tzid):
    raise newException(TimezoneRegistryError, "timezone is not registered")
  registry.definitions[tzid]

proc offsetAt*(registry: TimezoneRegistry; tzid, localValue: string): int =
  ## Resolves the latest observance at a local UTC-like wall time.
  let definition = registry.timezone(tzid)
  let local = parseTransition(localValue)
  var chosen: TimezoneObservance
  var chosenStart: DateTime
  var found = false
  for observance in definition.observances:
    var transitions = @[observance.start]
    if observance.recurrenceRule.len > 0:
      let expanded = expandRecurrence(observance.start.format(
          "yyyyMMdd'T'HHmmss") & "Z",
        observance.recurrenceRule, RecurrenceWindow(first: observance.start,
          last: local, maxOccurrences: 100_000))
      for value in expanded:
        transitions.add(parseTransition(value))
    for value in observance.recurrenceDates:
      if value <= local:
        transitions.add(value)
    for transition in transitions:
      # Keep transition selection side-effect free for library callers.
      if transition <= local and (not found or transition > chosenStart):
        chosen = observance
        chosenStart = transition
        found = true
  if not found: return definition.observances[0].offsetFromSeconds
  chosen.offsetToSeconds
