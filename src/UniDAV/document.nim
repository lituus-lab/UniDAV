# SPDX-License-Identifier: Apache-2.0
import std/[json, sequtils, strutils, times, uri]
import contentline, component

type
  DiagnosticSeverity* = enum dsError, dsWarning
  Diagnostic* = object
    severity*: DiagnosticSeverity
    line*: int
    message*: string
  DocumentKind* = enum dkUnknown, dkVCard, dkICalendar

proc addDiagnostic(diagnostics: var seq[Diagnostic]; message: string) =
  diagnostics.add(Diagnostic(severity: dsError, message: message))

proc firstValue(component: Component; name: string): string =
  let values = component.properties(name)
  if values.len > 0: result = values[0].value

proc validateIntegerProperty(component: Component; name: string; minimum,
    maximum: int; diagnostics: var seq[Diagnostic]) =
  for property in component.properties(name):
    try:
      let value = parseInt(property.value)
      if value < minimum or value > maximum:
        diagnostics.addDiagnostic(name & " is outside its RFC 5545 range")
    except ValueError:
      diagnostics.addDiagnostic(name & " must be an integer")

proc validateGeoProperty(component: Component;
    diagnostics: var seq[Diagnostic]) =
  proc validFloatToken(value: string): bool =
    if value.len == 0: return false
    var index = 0
    if value[index] in ['+', '-']:
      inc index
    var integerDigits = 0
    var fractionalDigits = 0
    var seenDot = false
    while index < value.len:
      if value[index] == '.':
        if seenDot or integerDigits == 0:
          return false
        seenDot = true
      elif value[index] in {'0'..'9'}:
        if seenDot: inc fractionalDigits
        else: inc integerDigits
      else:
        return false
      inc index
    integerDigits > 0 and (not seenDot or fractionalDigits > 0)
  for property in component.properties("GEO"):
    let parts = property.value.split(';')
    if parts.len != 2:
      diagnostics.addDiagnostic("GEO must contain latitude and longitude")
      continue
    if not validFloatToken(parts[0]) or not validFloatToken(parts[1]):
      diagnostics.addDiagnostic("GEO must contain numeric coordinates")
      continue
    try:
      let latitude = parseFloat(parts[0])
      let longitude = parseFloat(parts[1])
      if not (latitude >= -90.0 and latitude <= 90.0):
        diagnostics.addDiagnostic("GEO latitude is outside its RFC 5545 range")
      if not (longitude >= -180.0 and longitude <= 180.0):
        diagnostics.addDiagnostic("GEO longitude is outside its RFC 5545 range")
    except ValueError:
      diagnostics.addDiagnostic("GEO must contain numeric coordinates")

proc parameterValue(property: ContentLine; name: string): string
proc validCalendarUri(value: string): bool
proc splitUnescapedSemicolons(value: string): seq[string]

proc validBase64(value: string): bool =
  if value.len == 0 or value.len mod 4 != 0: return false
  var padding = 0
  for index, character in value:
    if character == '=':
      inc padding
      if index < value.len - 2 or padding > 2: return false
    elif padding > 0 or character notin
        {'A'..'Z', 'a'..'z', '0'..'9', '+', '/'}:
      return false
  true

proc validateAttachProperty(component: Component;
    diagnostics: var seq[Diagnostic]) =
  for property in component.properties("ATTACH"):
    let valueType = property.parameterValue("VALUE").toUpperAscii
    let encoding = property.parameterValue("ENCODING").toUpperAscii
    if valueType notin ["", "URI", "BINARY"]:
      diagnostics.addDiagnostic("ATTACH has an invalid VALUE parameter")
    if valueType == "BINARY":
      if encoding != "BASE64" or not validBase64(property.value):
        diagnostics.addDiagnostic("ATTACH BINARY must contain Base64 data")
    elif encoding.len > 0:
      diagnostics.addDiagnostic("ATTACH URI cannot specify ENCODING")
    elif not validCalendarUri(property.value):
      diagnostics.addDiagnostic("ATTACH must contain a URI value")

proc validateAlarmContext(component: Component;
    diagnostics: var seq[Diagnostic]) =
  if component.name notin ["VEVENT", "VTODO"]: return
  for alarm in component.children("VALARM"):
    for trigger in alarm.properties("TRIGGER"):
      let valueType = trigger.parameterValue("VALUE").toUpperAscii
      let isDuration = valueType in ["", "DURATION"] and
        (trigger.value.startsWith("P") or trigger.value.startsWith("-P"))
      if not isDuration: continue
      let related = trigger.parameterValue("RELATED").toUpperAscii
      if related in ["", "START"]:
        if component.properties("DTSTART").len == 0:
          diagnostics.addDiagnostic(component.name &
            " duration TRIGGER requires DTSTART")
      elif related == "END":
        let hasEnd = if component.name == "VEVENT":
          component.properties("DTEND").len > 0 or
            (component.properties("DTSTART").len > 0 and
              component.properties("DURATION").len > 0)
        else:
          component.properties("DUE").len > 0 or
            (component.properties("DTSTART").len > 0 and
              component.properties("DURATION").len > 0)
        if not hasEnd:
          diagnostics.addDiagnostic(component.name &
            " duration TRIGGER related to END lacks an end definition")

proc rejectPropertyOutside(component: Component; name: string;
    allowed: openArray[string]; diagnostics: var seq[Diagnostic]) =
  if component.properties(name).len > 0 and component.name notin allowed:
    diagnostics.addDiagnostic(name & " is not allowed in " & component.name)

proc validateKnownPropertyPlacement(component: Component;
    diagnostics: var seq[Diagnostic]) =
  rejectPropertyOutside(component, "GEO", ["VEVENT", "VTODO"], diagnostics)
  rejectPropertyOutside(component, "PRIORITY",
    ["VEVENT", "VTODO", "VAVAILABILITY"], diagnostics)
  rejectPropertyOutside(component, "TRANSP", ["VEVENT"], diagnostics)
  rejectPropertyOutside(component, "PERCENT-COMPLETE", ["VTODO"], diagnostics)
  rejectPropertyOutside(component, "DUE", ["VTODO"], diagnostics)
  rejectPropertyOutside(component, "COMPLETED", ["VTODO"], diagnostics)
  rejectPropertyOutside(component, "DTEND",
    ["VEVENT", "VFREEBUSY", "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "DURATION",
    ["VEVENT", "VTODO", "VALARM", "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "DTSTART",
    ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY", "STANDARD", "DAYLIGHT",
      "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "RECURRENCE-ID",
    ["VEVENT", "VTODO", "VJOURNAL", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "RRULE",
    ["VEVENT", "VTODO", "VJOURNAL", "STANDARD", "DAYLIGHT", "AVAILABLE"],
    diagnostics)
  rejectPropertyOutside(component, "RDATE",
    ["VEVENT", "VTODO", "VJOURNAL", "STANDARD", "DAYLIGHT", "AVAILABLE"],
    diagnostics)
  rejectPropertyOutside(component, "EXDATE",
    ["VEVENT", "VTODO", "VJOURNAL", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "STATUS",
    ["VEVENT", "VTODO", "VJOURNAL"], diagnostics)
  rejectPropertyOutside(component, "REQUEST-STATUS",
    ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY"], diagnostics)
  rejectPropertyOutside(component, "CATEGORIES",
    ["VEVENT", "VTODO", "VJOURNAL", "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "COMMENT",
    ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY", "VAVAILABILITY", "AVAILABLE",
      "STANDARD", "DAYLIGHT"],
    diagnostics)
  rejectPropertyOutside(component, "CONTACT",
    ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY", "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "DESCRIPTION",
    ["VEVENT", "VTODO", "VJOURNAL", "VALARM", "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "LOCATION",
    ["VEVENT", "VTODO", "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "RESOURCES", ["VEVENT", "VTODO"], diagnostics)
  rejectPropertyOutside(component, "SUMMARY",
    ["VEVENT", "VTODO", "VJOURNAL", "VALARM", "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "URL",
    ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY", "VAVAILABILITY", "AVAILABLE"], diagnostics)
  rejectPropertyOutside(component, "FREEBUSY", ["VFREEBUSY"], diagnostics)
  rejectPropertyOutside(component, "ATTACH",
    ["VEVENT", "VTODO", "VJOURNAL", "VALARM"], diagnostics)
  rejectPropertyOutside(component, "ATTENDEE",
    ["VEVENT", "VTODO", "VFREEBUSY", "VALARM"], diagnostics)
  rejectPropertyOutside(component, "BUSYTYPE", ["VAVAILABILITY"], diagnostics)
  rejectPropertyOutside(component, "TZURL", ["VTIMEZONE"], diagnostics)
  rejectPropertyOutside(component, "TZNAME", ["STANDARD", "DAYLIGHT"], diagnostics)
  rejectPropertyOutside(component, "TZOFFSETFROM",
    ["STANDARD", "DAYLIGHT"], diagnostics)
  rejectPropertyOutside(component, "TZOFFSETTO",
    ["STANDARD", "DAYLIGHT"], diagnostics)

proc requireOne(component: Component; name: string;
    diagnostics: var seq[Diagnostic]) =
  let properties = component.properties(name)
  if properties.len != 1 or properties[0].value.len == 0:
    diagnostics.addDiagnostic(component.name & " requires exactly one " & name)

proc atMostOne(component: Component; name: string;
    diagnostics: var seq[Diagnostic]) =
  if component.properties(name).len > 1:
    diagnostics.addDiagnostic(component.name & " allows at most one " & name)

proc hasParameter(property: ContentLine; name, value: string): bool =
  for parameter in property.params:
    if parameter.name == name:
      for candidate in parameter.values:
        if candidate.toUpperAscii == value.toUpperAscii:
          return true

proc parameterValue(property: ContentLine; name: string): string =
  for parameter in property.params:
    if parameter.name == name and parameter.values.len > 0:
      return parameter.values[0]

proc validDate(value: string): bool =
  try:
    discard parse(value, "yyyyMMdd", utc())
    value.len == 8
  except ValueError:
    false

proc validDateTime(value: string; utcOnly = false): bool =
  let isUtc = value.len == 16 and value[^1] == 'Z'
  if utcOnly and not isUtc: return false
  if value.len notin [15, 16] or value[8] != 'T' or
      (not isUtc and value.len != 15):
    return false
  let datePart = value[0 .. 7]
  let timePart = value[9 .. (if isUtc: ^2 else: ^1)]
  if not validDate(datePart) or timePart.len != 6 or
      not timePart.allCharsInSet({'0'..'9'}):
    return false
  try:
    let hour = parseInt(timePart[0 .. 1])
    let minute = parseInt(timePart[2 .. 3])
    let second = parseInt(timePart[4 .. 5])
    return hour <= 23 and minute <= 59 and second <= 60
  except ValueError:
    return false

proc validOffset(value: string): bool

proc validVCardDatePart(value: string; reduced = true): bool =
  if value.len == 8 and validDate(value): return true
  if reduced and value.len == 4 and value.startsWith("--") and
      value[2 .. 3].allCharsInSet({'0'..'9'}):
    try: return parseInt(value[2 .. 3]) in 1 .. 12
    except ValueError: return false
  if reduced and value.len == 4 and value.allCharsInSet({'0'..'9'}):
    return true # YYYY
  if reduced and value.len == 7 and value[4] == '-' and
      value[0 .. 3].allCharsInSet({'0'..'9'}) and
      value[5 .. 6].allCharsInSet({'0'..'9'}):
    try: return parseInt(value[5 .. 6]) in 1 .. 12 # YYYY-MM
    except ValueError: return false
  if value.len == 6 and value.startsWith("--") and
      value[2 .. 5].allCharsInSet({'0'..'9'}):
    try:
      let month = parseInt(value[2 .. 3])
      let day = parseInt(value[4 .. 5])
      let maximum = case month
        of 2: 29
        of 4, 6, 9, 11: 30
        else: 31
      return month in 1 .. 12 and day in 1 .. maximum
    except ValueError: return false
  if value.len == 5 and value.startsWith("---") and
      value[3 .. 4].allCharsInSet({'0'..'9'}):
    try: return parseInt(value[3 .. 4]) in 1 .. 31
    except ValueError: return false
  false

proc validVCardTimePart(value: string; truncated = true): bool =
  var timePart = value
  if timePart.endsWith("Z"):
    timePart.setLen(timePart.len - 1)
  else:
    let plus = timePart.rfind('+')
    let minus = timePart.rfind('-')
    let sign = max(if plus > 0: plus else: -1,
      if minus > 0: minus else: -1)
    if sign >= 0:
      let zone = timePart[sign .. ^1]
      if zone.len notin [3, 5] or not zone[1 .. ^1].allCharsInSet({'0'..'9'}):
        return false
      try:
        let hours = parseInt(zone[1 .. 2])
        let minutes = if zone.len == 5: parseInt(zone[3 .. 4]) else: 0
        if hours > 23 or minutes > 59: return false
      except ValueError: return false
      timePart.setLen(sign)
  if truncated and timePart.startsWith("--"):
    if timePart.len != 4 or not timePart[2 .. 3].allCharsInSet({'0'..'9'}):
      return false
    try: return parseInt(timePart[2 .. 3]) <= 60
    except ValueError: return false
  if truncated and timePart.startsWith("-"):
    if timePart.len != 3 or not timePart[1 .. 2].allCharsInSet({'0'..'9'}):
      return false
    try: return parseInt(timePart[1 .. 2]) <= 59
    except ValueError: return false
  if timePart.len notin [2, 4, 6] or not timePart.allCharsInSet({'0'..'9'}):
    return false
  try:
    let hour = parseInt(timePart[0 .. 1])
    let minute = if timePart.len >= 4: parseInt(timePart[2 .. 3]) else: 0
    let second = if timePart.len == 6: parseInt(timePart[4 .. 5]) else: 0
    hour <= 23 and minute <= 59 and second <= 60
  except ValueError: false

proc validVCardDateAndOrTime(value: string): bool =
  ## Bounded RFC 6350 date-and-or-time acceptance, including partial dates
  ## and numeric UTC offsets used by vCard anniversary properties.
  let t = value.find('T')
  if t >= 0:
    if t == 0: return validVCardTimePart(value[1 .. ^1])
    return validVCardDatePart(value[0 ..< t], reduced = false) and
      validVCardTimePart(value[t + 1 .. ^1], truncated = false)
  validVCardDatePart(value) or validVCardTimePart(value)

proc validVCardUri(value: string): bool =
  value.len > 0 and not value.anyIt(it in {'\0'..' ', '\t', '\r', '\n'})

proc validCalendarUri(value: string): bool =
  if not validVCardUri(value): return false
  try:
    parseUri(value).scheme.len > 0
  except ValueError:
    false

proc validIanaToken(value: string): bool =
  value.len > 0 and value.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '-'})

proc validateVCardParameters(property: ContentLine; diagnostics: var seq[Diagnostic]) =
  var seen: seq[string]
  for parameter in property.params:
    if parameter.name in seen:
      diagnostics.addDiagnostic(property.name & " repeats the " &
        parameter.name &
        " parameter")
    else:
      seen.add(parameter.name)
    if parameter.name == "PREF":
      if parameter.values.len != 1:
        diagnostics.addDiagnostic(property.name & " PREF must have one value")
      else:
        try:
          let preference = parseInt(parameter.values[0])
          if preference < 1 or preference > 100:
            diagnostics.addDiagnostic(property.name & " PREF must be between 1 and 100")
        except ValueError:
          diagnostics.addDiagnostic(property.name & " PREF must be an integer")
    elif parameter.name == "PID":
      for pid in parameter.values:
        let pieces = pid.split('.', maxsplit = 1)
        if pieces.len > 2 or pieces.anyIt(it.len == 0 or
            not it.allCharsInSet({'0'..'9'})):
          diagnostics.addDiagnostic(property.name & " PID is not an RFC 6350 value")

proc validDuration(value: string): bool =
  var index = 0
  if value.len == 0: return false
  if value[index] == '-': inc index
  if index >= value.len or value[index] != 'P': return false
  inc index
  var digits = false
  var units = 0
  var inTime = false
  var weekForm = false
  var seenUnits: seq[char]
  while index < value.len:
    if value[index] == 'T':
      if inTime or index + 1 >= value.len: return false
      inTime = true
      inc index
      continue
    let start = index
    while index < value.len and value[index] in {'0'..'9'}:
      inc index
    if start == index or index >= value.len: return false
    digits = true
    let unit = value[index]
    let validUnit = if unit == 'W': not inTime and units == 0
      elif unit in ['D', 'H', 'M', 'S']:
        if weekForm or unit in seenUnits: false
        elif unit == 'D': not inTime else: inTime
      else: false
    if not validUnit: return false
    if unit == 'W': weekForm = true
    seenUnits.add(unit)
    inc units
    inc index
  digits and units > 0

proc validOffset(value: string): bool =
  if value.len notin [5, 7] or value[0] notin ['+', '-']: return false
  if not value[1 .. ^1].allCharsInSet({'0'..'9'}): return false
  let hours = parseInt(value[1 .. 2])
  let minutes = parseInt(value[3 .. 4])
  let seconds = if value.len == 7: parseInt(value[5 .. 6]) else: 0
  hours <= 23 and minutes <= 59 and seconds <= 59

proc validateTemporalProperty(component: Component; name: string;
    diagnostics: var seq[Diagnostic]; utcOnly = false; allowDate = true;
    localOnly = false) =
  for property in component.properties(name):
    let valueType = property.parameterValue("VALUE").toUpperAscii
    if valueType notin ["", "DATE", "DATE-TIME"]:
      diagnostics.addDiagnostic(name & " has an invalid VALUE parameter")
    if valueType == "DATE" and not allowDate:
      diagnostics.addDiagnostic(name & " does not allow VALUE=DATE")
    let isDate = allowDate and valueType == "DATE"
    let tzid = property.parameterValue("TZID")
    if tzid.len == 0:
      for parameter in property.params:
        if parameter.name == "TZID":
          diagnostics.addDiagnostic(name & " has an empty TZID parameter")
    if tzid.len > 0 and (isDate or utcOnly or property.value.endsWith("Z")):
      diagnostics.addDiagnostic(name & " cannot combine TZID with a date or UTC value")
    if localOnly and (isDate or property.value.endsWith("Z") or tzid.len > 0):
      diagnostics.addDiagnostic(name & " must be a local date-time without TZID")
    let valid = if isDate: validDate(property.value)
      else: validDateTime(property.value, utcOnly)
    if not valid:
      diagnostics.addDiagnostic(name & " has an invalid RFC 5545 date value")

proc validateDurationProperty(component: Component; name: string;
    diagnostics: var seq[Diagnostic]) =
  for property in component.properties(name):
    if not validDuration(property.value) or property.value.startsWith("-") or
        not property.value.anyIt(it in {'1'..'9'}):
      diagnostics.addDiagnostic(name & " has an invalid RFC 5545 duration")

proc validateRRuleProperty(component: Component;
    diagnostics: var seq[Diagnostic]) =
  for property in component.properties("RRULE"):
    var seen = newSeq[string]()
    var hasFreq = false
    var frequency = ""
    var hasCount = false
    var hasUntil = false
    var untilValue = ""
    var hasOrdinalByDay = false
    for part in property.value.split(';'):
      let pair = part.split('=', maxsplit = 1)
      if pair.len != 2 or pair[0].len == 0 or pair[1].len == 0:
        diagnostics.addDiagnostic("RRULE has an invalid clause")
        continue
      let key = pair[0].toUpperAscii
      let value = pair[1].toUpperAscii
      if key in seen:
        diagnostics.addDiagnostic("RRULE contains a duplicate " & key)
      else:
        seen.add(key)
      case key
      of "FREQ":
        hasFreq = true
        frequency = value
        if value notin ["SECONDLY", "MINUTELY", "HOURLY", "DAILY", "WEEKLY",
            "MONTHLY", "YEARLY"]:
          diagnostics.addDiagnostic("RRULE FREQ is not an RFC 5545 value")
      of "COUNT":
        hasCount = true
        try:
          if parseInt(value) <= 0:
            diagnostics.addDiagnostic("RRULE COUNT must be positive")
        except ValueError:
          diagnostics.addDiagnostic("RRULE COUNT must be an integer")
      of "INTERVAL":
        try:
          if parseInt(value) <= 0:
            diagnostics.addDiagnostic("RRULE INTERVAL must be positive")
        except ValueError:
          diagnostics.addDiagnostic("RRULE INTERVAL must be an integer")
      of "UNTIL":
        hasUntil = true
        untilValue = value
        if value.len == 8:
          if not validDate(value):
            diagnostics.addDiagnostic("RRULE UNTIL has an invalid date value")
        elif not validDateTime(value, utcOnly = true):
          diagnostics.addDiagnostic("RRULE UNTIL must be a UTC date-time")
      of "BYSECOND", "BYMINUTE", "BYHOUR", "BYMONTH", "BYMONTHDAY",
          "BYYEARDAY", "BYWEEKNO", "BYSETPOS":
        for token in value.split(','):
          try:
            let number = parseInt(token)
            let valid = case key
              of "BYSECOND": number in 0..60
              of "BYMINUTE": number in 0..59
              of "BYHOUR": number in 0..23
              of "BYMONTH": number in 1..12
              of "BYMONTHDAY": number != 0 and number in -31..31
              of "BYYEARDAY": number != 0 and number in -366..366
              of "BYWEEKNO": number != 0 and number in -53..53
              else: number != 0 and number in -366..366
            if not valid:
              diagnostics.addDiagnostic("RRULE " & key & " is outside its RFC 5545 range")
          except ValueError:
            diagnostics.addDiagnostic("RRULE " & key & " must contain integers")
      of "BYDAY":
        for token in value.split(','):
          if token.len < 2:
            diagnostics.addDiagnostic("RRULE BYDAY is invalid")
          else:
            let weekday = token[^2 .. ^1]
            let prefix = token[0 ..< token.len - 2]
            if weekday notin ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]:
              diagnostics.addDiagnostic("RRULE BYDAY has an invalid weekday")
            if prefix.len > 0:
              hasOrdinalByDay = true
              var digits = prefix
              if prefix[0] in ['+', '-']:
                digits = if prefix.len == 1: "" else: prefix[1 .. ^1]
              if digits.len == 0 or digits.len > 2 or
                  not digits.allCharsInSet({'0'..'9'}):
                diagnostics.addDiagnostic("RRULE BYDAY ordinal must be an integer")
              else:
                try:
                  let ordinal = parseInt(prefix)
                  if ordinal == 0 or ordinal < -53 or ordinal > 53:
                    diagnostics.addDiagnostic("RRULE BYDAY ordinal is outside its RFC 5545 range")
                except ValueError:
                  diagnostics.addDiagnostic("RRULE BYDAY ordinal must be an integer")
      of "WKST":
        if value notin ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]:
          diagnostics.addDiagnostic("RRULE WKST is not an RFC 5545 weekday")
      else:
        diagnostics.addDiagnostic("RRULE contains an unsupported clause " & key)
    if not hasFreq:
      diagnostics.addDiagnostic("RRULE requires exactly one FREQ")
    if hasCount and hasUntil:
      diagnostics.addDiagnostic("RRULE COUNT and UNTIL are mutually exclusive")
    if hasOrdinalByDay and frequency notin ["MONTHLY", "YEARLY"]:
      diagnostics.addDiagnostic("RRULE BYDAY ordinals require MONTHLY or YEARLY")
    if hasOrdinalByDay and frequency == "YEARLY" and "BYWEEKNO" in seen:
      diagnostics.addDiagnostic("RRULE BYDAY ordinals cannot combine with BYWEEKNO")
    if frequency != "YEARLY":
      for key in ["BYYEARDAY", "BYWEEKNO"]:
        if key in seen:
          diagnostics.addDiagnostic("RRULE " & key & " requires YEARLY")
    if frequency == "WEEKLY" and "BYMONTHDAY" in seen:
      diagnostics.addDiagnostic("RRULE BYMONTHDAY is invalid for WEEKLY")
    if "BYSETPOS" in seen:
      let byParts = ["BYSECOND", "BYMINUTE", "BYHOUR", "BYDAY", "BYMONTHDAY",
        "BYYEARDAY", "BYWEEKNO", "BYMONTH"]
      if not byParts.anyIt(it in seen):
        diagnostics.addDiagnostic("RRULE BYSETPOS requires another BYxxx part")
    let starts = component.properties("DTSTART")
    if hasUntil and starts.len == 1:
      let dateStart = hasParameter(starts[0], "VALUE", "DATE")
      if dateStart != (untilValue.len == 8):
        diagnostics.addDiagnostic("RRULE UNTIL must match DTSTART value type")
      elif (dateStart and validDate(starts[0].value) and validDate(
          untilValue)) or (not dateStart and validDateTime(starts[0].value) and
            validDateTime(untilValue, utcOnly = true)):
        try:
          let start = if dateStart: parse(starts[0].value, "yyyyMMdd", utc())
            else: parse(starts[0].value, "yyyyMMdd'T'HHmmss" &
              (if starts[0].value[^1] == 'Z': "'Z'" else: ""), utc())
          let finish = if dateStart: parse(untilValue, "yyyyMMdd", utc())
            else: parse(untilValue, "yyyyMMdd'T'HHmmss'Z'", utc())
          if finish < start:
            diagnostics.addDiagnostic("RRULE UNTIL must not precede DTSTART")
        except ValueError:
          discard

proc validateRecurrenceDateProperties(component: Component;
    diagnostics: var seq[Diagnostic]) =
  let starts = component.properties("DTSTART")
  let startIsDate = starts.len == 1 and hasParameter(starts[0], "VALUE", "DATE")
  for name in ["RDATE", "EXDATE", "RECURRENCE-ID"]:
    for property in component.properties(name):
      let isDate = hasParameter(property, "VALUE", "DATE")
      let isPeriod = hasParameter(property, "VALUE", "PERIOD")
      let valueType = property.parameterValue("VALUE").toUpperAscii
      let allowedTypes = if name == "RDATE": @[
        "", "DATE", "DATE-TIME", "PERIOD"] else: @[
        "", "DATE", "DATE-TIME"]
      if valueType notin allowedTypes:
        diagnostics.addDiagnostic(name & " has an invalid VALUE parameter")
      let tzid = property.parameterValue("TZID")
      if tzid.len == 0:
        for parameter in property.params:
          if parameter.name == "TZID":
            diagnostics.addDiagnostic(name & " has an empty TZID parameter")
      if tzid.len > 0 and valueType == "DATE":
        diagnostics.addDiagnostic(name & " cannot combine TZID with VALUE=DATE")
      if tzid.len > 0:
        for token in property.value.split(','):
          let dateTime = if isPeriod: token.split('/', maxsplit = 1)[0] else: token
          if dateTime.endsWith("Z"):
            diagnostics.addDiagnostic(name & " cannot combine TZID with a UTC value")
      if name == "RECURRENCE-ID" and isDate and
          property.parameterValue("RANGE").len > 0:
        diagnostics.addDiagnostic("RECURRENCE-ID RANGE requires DATE-TIME")
      if name == "RECURRENCE-ID":
        let range = property.parameterValue("RANGE")
        if range.len > 0 and range.toUpperAscii notin ["THISANDPRIOR",
            "THISANDFUTURE"]:
          diagnostics.addDiagnostic("RECURRENCE-ID RANGE is not an RFC 5545 value")
      if isPeriod and name != "RDATE":
        diagnostics.addDiagnostic(name & " cannot use VALUE=PERIOD")
      for token in property.value.split(','):
        if isPeriod:
          let parts = token.split('/', maxsplit = 1)
          if parts.len != 2 or not validDateTime(parts[0]):
            diagnostics.addDiagnostic("RDATE has an invalid PERIOD start")
          elif validDateTime(parts[1]):
            try:
              let first = parse(parts[0], "yyyyMMdd'T'HHmmss" &
                (if parts[0][^1] == 'Z': "'Z'" else: ""), utc())
              let last = parse(parts[1], "yyyyMMdd'T'HHmmss" &
                (if parts[1][^1] == 'Z': "'Z'" else: ""), utc())
              if last <= first:
                diagnostics.addDiagnostic("RDATE PERIOD must be increasing")
            except ValueError:
              discard
          elif not validDuration(parts[1]) or parts[1].startsWith("-"):
            diagnostics.addDiagnostic("RDATE has an invalid PERIOD end")
          elif not parts[1].anyIt(it in {'1'..'9'}):
            diagnostics.addDiagnostic("RDATE PERIOD duration must be positive")
        elif isDate:
          if not validDate(token):
            diagnostics.addDiagnostic(name & " has an invalid date value")
        elif not validDateTime(token):
          diagnostics.addDiagnostic(name & " has an invalid date-time value")
        if starts.len == 1 and not isPeriod and
            (isDate != startIsDate):
          diagnostics.addDiagnostic(name & " must match DTSTART value type")
        elif starts.len == 1 and isPeriod and startIsDate:
          diagnostics.addDiagnostic("RDATE PERIOD must match a date-time DTSTART")

proc validateTemporalPair(component: Component; startName, endName: string;
    diagnostics: var seq[Diagnostic]) =
  let starts = component.properties(startName)
  let ends = component.properties(endName)
  if starts.len == 0 or ends.len == 0:
    return
  let startIsDate = hasParameter(starts[0], "VALUE", "DATE")
  let endIsDate = hasParameter(ends[0], "VALUE", "DATE")
  if startIsDate != endIsDate:
    diagnostics.addDiagnostic(endName & " must match " & startName &
      " value type")
    return
  let startValid = if startIsDate: validDate(starts[0].value)
    else: validDateTime(starts[0].value)
  let endValid = if endIsDate: validDate(ends[0].value)
    else: validDateTime(ends[0].value)
  if not startValid or not endValid:
    return
  try:
    let first = if startIsDate: parse(starts[0].value, "yyyyMMdd", utc())
      else: parse(starts[0].value, "yyyyMMdd'T'HHmmss" &
        (if starts[0].value[^1] == 'Z': "'Z'" else: ""), utc())
    let last = if endIsDate: parse(ends[0].value, "yyyyMMdd", utc())
      else: parse(ends[0].value, "yyyyMMdd'T'HHmmss" &
        (if ends[0].value[^1] == 'Z': "'Z'" else: ""), utc())
    if last <= first:
      diagnostics.addDiagnostic(endName & " must be later than " & startName)
  except ValueError:
    discard

proc validateVCard(component: Component; diagnostics: var seq[Diagnostic]) =
  for name in ["N", "KIND", "GENDER", "BDAY", "ANNIVERSARY", "DEATHDATE",
      "GEO", "PRODID", "REV", "SORT-STRING", "UID"]:
    atMostOne(component, name, diagnostics)
  if component.properties("KIND").len == 1 and
      firstValue(component, "KIND").toLowerAscii notin
        ["individual", "group", "org", "location", "application"] and
      not firstValue(component, "KIND").toLowerAscii.startsWith("x-"):
    diagnostics.addDiagnostic("vCard KIND is not an RFC 6350 value")
  if component.properties("UID").len == 1:
    if firstValue(component, "UID").len == 0:
      diagnostics.addDiagnostic("vCard UID must not be empty")
    elif not validCalendarUri(firstValue(component, "UID")):
      diagnostics.addDiagnostic("vCard UID must contain a URI value")
  if component.properties("GENDER").len == 1:
    let parts = splitUnescapedSemicolons(firstValue(component, "GENDER"))
    if parts.len > 2 or (parts[0].toUpperAscii notin ["", "M", "F", "O", "N", "U"]):
      diagnostics.addDiagnostic("vCard GENDER is not an RFC 6350 value")
  for property in component.properties("N"):
    if splitUnescapedSemicolons(property.value).len != 5:
      diagnostics.addDiagnostic("vCard N must contain five components")
  for property in component.properties("ADR"):
    if splitUnescapedSemicolons(property.value).len != 7:
      diagnostics.addDiagnostic("vCard ADR must contain seven components")
  for property in component.properties("CLIENTPIDMAP"):
    let parts = splitUnescapedSemicolons(property.value)
    var valid = parts.len == 2 and validCalendarUri(parts[1])
    if valid:
      try:
        valid = parseInt(parts[0]) > 0
      except ValueError:
        valid = false
    if not valid:
      diagnostics.addDiagnostic("vCard CLIENTPIDMAP is not an RFC 6350 value")
  if component.properties("REV").len == 1 and
      not validDateTime(firstValue(component, "REV"), utcOnly = true):
    diagnostics.addDiagnostic("vCard REV must be a UTC timestamp")
  for property in component.entries:
    if property.kind == ekProperty:
      validateVCardParameters(property.property, diagnostics)
  for name in ["BDAY", "ANNIVERSARY", "DEATHDATE"]:
    for property in component.properties(name):
      let valueType = property.parameterValue("VALUE").toUpperAscii
      if valueType notin ["", "DATE-AND-OR-TIME", "TEXT"]:
        diagnostics.addDiagnostic(name & " has an invalid VALUE parameter")
      elif valueType != "TEXT" and not validVCardDateAndOrTime(property.value):
        diagnostics.addDiagnostic(name & " has an invalid date-and-or-time value")
  for name in ["UID", "GEO"]:
    for property in component.properties(name):
      if not validCalendarUri(property.value):
        diagnostics.addDiagnostic(name & " must contain a URI value")
  for name in ["URL", "SOURCE", "FBURL", "CALADRURI", "CALURI", "IMPP"]:
    for property in component.properties(name):
      if not validCalendarUri(property.value):
        diagnostics.addDiagnostic(name & " must contain a URI value")
  for name in ["MEMBER", "RELATED"]:
    for property in component.properties(name):
      for value in property.value.split(','):
        if not validCalendarUri(value):
          diagnostics.addDiagnostic(name & " must contain URI values")

proc validateFreeBusy(component: Component; diagnostics: var seq[Diagnostic]) =
  for property in component.properties("FREEBUSY"):
    let valueType = property.parameterValue("VALUE").toUpperAscii
    if valueType notin ["", "PERIOD"]:
      diagnostics.addDiagnostic("FREEBUSY has an invalid VALUE parameter")
    let fbType = property.parameterValue("FBTYPE").toUpperAscii
    for parameter in property.params:
      if parameter.name == "FBTYPE" and parameter.values.len != 1:
        diagnostics.addDiagnostic("FREEBUSY FBTYPE must have one value")
      elif parameter.name == "TZID":
        diagnostics.addDiagnostic("FREEBUSY cannot contain a TZID parameter")
    if fbType.len > 0 and fbType notin ["FREE", "BUSY", "BUSY-UNAVAILABLE",
        "BUSY-TENTATIVE"] and not validIanaToken(fbType):
      diagnostics.addDiagnostic("FREEBUSY FBTYPE is not an RFC 5545 value")
    for period in property.value.split(','):
      let parts = period.split('/', maxsplit = 1)
      if parts.len != 2 or not validDateTime(parts[0], utcOnly = true):
        diagnostics.addDiagnostic("FREEBUSY has an invalid UTC period start")
      elif validDateTime(parts[1], utcOnly = true):
        try:
          let first = parse(parts[0], "yyyyMMdd'T'HHmmss'Z'", utc())
          let last = parse(parts[1], "yyyyMMdd'T'HHmmss'Z'", utc())
          if last <= first:
            diagnostics.addDiagnostic("FREEBUSY period must be increasing")
        except ValueError:
          discard
      elif not validDuration(parts[1]) or parts[1].startsWith("-"):
        diagnostics.addDiagnostic("FREEBUSY has an invalid period end")
      elif not parts[1].anyIt(it in {'1'..'9'}):
        diagnostics.addDiagnostic("FREEBUSY period duration must be positive")

proc splitUnescapedSemicolons(value: string): seq[string] =
  var current = ""
  var index = 0
  while index < value.len:
    if value[index] == '\\' and index + 1 < value.len:
      current.add(value[index])
      inc index
      current.add(value[index])
    elif value[index] == ';':
      result.add(current)
      current.setLen(0)
    else:
      current.add(value[index])
    inc index
  result.add(current)

proc validStatusCode(value: string): bool =
  let parts = value.split('.')
  if parts.len notin [2, 3]: return false
  for part in parts:
    if part.len == 0 or not part.allCharsInSet({'0'..'9'}): return false
  parts[0].len > 0

proc validateRequestStatus(component: Component;
    diagnostics: var seq[Diagnostic]) =
  for property in component.properties("REQUEST-STATUS"):
    let parts = splitUnescapedSemicolons(property.value)
    if parts.len notin [2, 3] or not validStatusCode(parts[0]):
      diagnostics.addDiagnostic("REQUEST-STATUS has an invalid value")

proc validateOffsetProperty(component: Component; name: string;
    diagnostics: var seq[Diagnostic]) =
  for property in component.properties(name):
    if not validOffset(property.value):
      diagnostics.addDiagnostic(name & " has an invalid RFC 5545 UTC offset")

proc validateObservanceRecurrence(component: Component;
    diagnostics: var seq[Diagnostic]) =
  atMostOne(component, "RRULE", diagnostics)
  for rule in component.properties("RRULE"):
    var frequencies: seq[string]
    for clause in rule.value.split(';'):
      let pair = clause.split('=', maxsplit = 1)
      if pair.len == 2 and pair[0].toUpperAscii == "FREQ":
        frequencies.add(pair[1].toUpperAscii)
    if frequencies.len != 1 or frequencies[0] != "YEARLY":
      diagnostics.addDiagnostic(component.name & " RRULE must use FREQ=YEARLY")
  for property in component.properties("RDATE"):
    let valueType = property.parameterValue("VALUE").toUpperAscii
    if valueType notin ["", "DATE-TIME"]:
      diagnostics.addDiagnostic(component.name & " RDATE must contain date-times")
    if property.parameterValue("TZID").len > 0:
      diagnostics.addDiagnostic(component.name & " RDATE cannot contain TZID")
    for value in property.value.split(','):
      if not validDateTime(value) or value.endsWith("Z"):
        diagnostics.addDiagnostic(component.name & " RDATE must be a local date-time")

proc validateCalendarComponent(component: Component;
    diagnostics: var seq[Diagnostic]; parentName = "") =
  ## Validate unambiguous RFC 5545 value/cardinality rules while preserving
  ## unknown properties and components for forward compatibility.
  case component.name
  of "VEVENT":
    if parentName != "VCALENDAR":
      diagnostics.addDiagnostic("VEVENT must be a direct child of VCALENDAR")
    requireOne(component, "UID", diagnostics)
    requireOne(component, "DTSTAMP", diagnostics)
    for name in ["DTSTART", "DTEND", "DURATION", "RECURRENCE-ID", "RRULE",
        "CLASS", "CREATED", "DESCRIPTION", "GEO", "LAST-MODIFIED",
        "LOCATION", "ORGANIZER", "PRIORITY", "SEQUENCE", "STATUS",
        "SUMMARY", "TRANSP", "URL"]:
      atMostOne(component, name, diagnostics)
    if component.properties("DTEND").len > 0 and
        component.properties("DURATION").len > 0:
      diagnostics.addDiagnostic("VEVENT cannot contain both DTEND and DURATION")
    if component.properties("STATUS").len > 0 and
        firstValue(component, "STATUS").toUpperAscii notin
        ["TENTATIVE", "CONFIRMED", "CANCELLED"]:
      diagnostics.addDiagnostic("VEVENT STATUS is not an RFC 5545 value")
  of "VTODO":
    if parentName != "VCALENDAR":
      diagnostics.addDiagnostic("VTODO must be a direct child of VCALENDAR")
    requireOne(component, "UID", diagnostics)
    requireOne(component, "DTSTAMP", diagnostics)
    for name in ["DUE", "DURATION", "DTSTART", "COMPLETED", "RECURRENCE-ID",
        "RRULE", "CLASS", "CREATED", "DESCRIPTION", "GEO", "LAST-MODIFIED",
        "LOCATION", "ORGANIZER", "PERCENT-COMPLETE", "PRIORITY", "SEQUENCE",
        "STATUS", "SUMMARY", "URL"]:
      atMostOne(component, name, diagnostics)
    if component.properties("DUE").len > 0 and
        component.properties("DURATION").len > 0:
      diagnostics.addDiagnostic("VTODO cannot contain both DUE and DURATION")
    if component.properties("DURATION").len > 0 and
        component.properties("DTSTART").len == 0:
      diagnostics.addDiagnostic("VTODO DURATION requires DTSTART")
    if component.properties("STATUS").len > 0 and
        firstValue(component, "STATUS").toUpperAscii notin
        ["NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"]:
      diagnostics.addDiagnostic("VTODO STATUS is not an RFC 5545 value")
    if component.properties("STATUS").len == 1 and
        firstValue(component, "STATUS").toUpperAscii == "COMPLETED":
      requireOne(component, "COMPLETED", diagnostics)
    validateIntegerProperty(component, "PERCENT-COMPLETE", 0, 100, diagnostics)
  of "VJOURNAL":
    if parentName != "VCALENDAR":
      diagnostics.addDiagnostic("VJOURNAL must be a direct child of VCALENDAR")
    requireOne(component, "UID", diagnostics)
    requireOne(component, "DTSTAMP", diagnostics)
    for name in ["DTSTART", "RECURRENCE-ID", "RRULE", "CLASS", "CREATED",
        "LAST-MODIFIED", "ORGANIZER", "SEQUENCE", "STATUS",
        "SUMMARY", "UID", "URL"]:
      atMostOne(component, name, diagnostics)
    if component.properties("STATUS").len > 0 and
        firstValue(component, "STATUS").toUpperAscii notin
        ["DRAFT", "FINAL", "CANCELLED"]:
      diagnostics.addDiagnostic("VJOURNAL STATUS is not an RFC 5545 value")
  of "VALARM":
    if parentName notin ["VEVENT", "VTODO"]:
      diagnostics.addDiagnostic("VALARM must be nested in VEVENT or VTODO")
    if component.properties("ACTION").len != 1:
      diagnostics.addDiagnostic("VALARM requires exactly one ACTION")
    if component.properties("TRIGGER").len != 1:
      diagnostics.addDiagnostic("VALARM requires exactly one TRIGGER")
    # Its own `if`, not an `elif` on the TRIGGER count: the two say nothing
    # about each other, and an alarm with both faults reported only the first.
    if firstValue(component, "ACTION").toUpperAscii notin
        ["AUDIO", "DISPLAY", "EMAIL"]:
      diagnostics.addDiagnostic("VALARM ACTION is not an RFC 5545 value")
    let action = firstValue(component, "ACTION").toUpperAscii
    if action in ["DISPLAY", "EMAIL"]:
      requireOne(component, "DESCRIPTION", diagnostics)
    if action == "EMAIL":
      requireOne(component, "SUMMARY", diagnostics)
      if component.properties("ATTENDEE").len == 0:
        diagnostics.addDiagnostic("EMAIL VALARM requires an ATTENDEE")
    if action == "AUDIO" and (component.properties("DESCRIPTION").len > 0 or
        component.properties("SUMMARY").len > 0 or
        component.properties("ATTENDEE").len > 0):
      diagnostics.addDiagnostic("AUDIO VALARM cannot contain DISPLAY or EMAIL fields")
    if action == "DISPLAY" and (component.properties("SUMMARY").len > 0 or
        component.properties("ATTENDEE").len > 0 or
        component.properties("ATTACH").len > 0):
      diagnostics.addDiagnostic("DISPLAY VALARM contains fields reserved for other actions")
    if action == "AUDIO" and component.properties("ATTACH").len > 1:
      diagnostics.addDiagnostic("AUDIO VALARM allows at most one ATTACH")
    for trigger in component.properties("TRIGGER"):
      let valueType = trigger.parameterValue("VALUE").toUpperAscii
      let related = trigger.parameterValue("RELATED").toUpperAscii
      let durationValue = trigger.value.startsWith("P") or
          trigger.value.startsWith("-P")
      if related.len > 0 and related notin ["START", "END"]:
        diagnostics.addDiagnostic("TRIGGER RELATED is not an RFC 5545 value")
      if durationValue:
        if valueType notin ["", "DURATION"]:
          diagnostics.addDiagnostic("duration TRIGGER has an invalid VALUE parameter")
        if not validDuration(trigger.value):
          diagnostics.addDiagnostic("TRIGGER has an invalid RFC 5545 duration")
      else:
        if valueType notin ["", "DATE-TIME"] or related.len > 0:
          diagnostics.addDiagnostic("date-time TRIGGER has invalid VALUE or RELATED")
        if not validDateTime(trigger.value, utcOnly = true):
          diagnostics.addDiagnostic("TRIGGER has an invalid UTC date value")
    if (component.properties("REPEAT").len > 0) !=
        (component.properties("DURATION").len > 0):
      diagnostics.addDiagnostic("VALARM REPEAT and DURATION must appear together")
    validateIntegerProperty(component, "REPEAT", 0, 999999999, diagnostics)
    atMostOne(component, "ACTION", diagnostics)
    atMostOne(component, "TRIGGER", diagnostics)
  of "VFREEBUSY":
    if parentName != "VCALENDAR":
      diagnostics.addDiagnostic("VFREEBUSY must be a direct child of VCALENDAR")
    requireOne(component, "UID", diagnostics)
    requireOne(component, "DTSTAMP", diagnostics)
    for name in ["CONTACT", "DTSTART", "DTEND", "ORGANIZER", "URL"]:
      atMostOne(component, name, diagnostics)
    for name in ["RRULE", "RDATE", "EXDATE"]:
      if component.properties(name).len > 0:
        diagnostics.addDiagnostic("VFREEBUSY cannot contain " & name)
    validateFreeBusy(component, diagnostics)
  of "VTIMEZONE":
    if parentName != "VCALENDAR":
      diagnostics.addDiagnostic("VTIMEZONE must be a direct child of VCALENDAR")
    requireOne(component, "TZID", diagnostics)
    atMostOne(component, "LAST-MODIFIED", diagnostics)
    atMostOne(component, "TZURL", diagnostics)
    if component.children("STANDARD").len + component.children(
        "DAYLIGHT").len == 0:
      diagnostics.addDiagnostic("VTIMEZONE requires STANDARD or DAYLIGHT")
  of "STANDARD", "DAYLIGHT":
    if parentName != "VTIMEZONE":
      diagnostics.addDiagnostic(component.name & " must be nested in VTIMEZONE")
    requireOne(component, "DTSTART", diagnostics)
    requireOne(component, "TZOFFSETFROM", diagnostics)
    requireOne(component, "TZOFFSETTO", diagnostics)
  of "VAVAILABILITY":
    if parentName != "VCALENDAR":
      diagnostics.addDiagnostic("VAVAILABILITY must be a direct child of VCALENDAR")
    requireOne(component, "UID", diagnostics)
    requireOne(component, "DTSTAMP", diagnostics)
    for name in ["BUSYTYPE", "CLASS", "CREATED", "DESCRIPTION", "DTSTART",
        "LAST-MODIFIED", "LOCATION", "ORGANIZER", "PRIORITY", "SEQUENCE",
        "SUMMARY", "URL"]:
      atMostOne(component, name, diagnostics)
    if component.properties("BUSYTYPE").len == 1:
      let busyType = firstValue(component, "BUSYTYPE").toUpperAscii
      if busyType == "FREE" or (busyType notin
          ["BUSY", "BUSY-UNAVAILABLE", "BUSY-TENTATIVE"] and
          not validIanaToken(busyType)):
        diagnostics.addDiagnostic("VAVAILABILITY BUSYTYPE is not an RFC 7953 value")
    validateIntegerProperty(component, "PRIORITY", 0, 9, diagnostics)
    atMostOne(component, "DTEND", diagnostics)
    atMostOne(component, "DURATION", diagnostics)
    if component.properties("DTEND").len > 0 and
        component.properties("DURATION").len > 0:
      diagnostics.addDiagnostic("VAVAILABILITY cannot contain both DTEND and DURATION")
    if component.properties("DURATION").len > 0 and
        component.properties("DTSTART").len == 0:
      diagnostics.addDiagnostic("VAVAILABILITY DURATION requires DTSTART")
  of "AVAILABLE":
    if parentName != "VAVAILABILITY":
      diagnostics.addDiagnostic("AVAILABLE must be nested in VAVAILABILITY")
    requireOne(component, "UID", diagnostics)
    requireOne(component, "DTSTAMP", diagnostics)
    requireOne(component, "DTSTART", diagnostics)
    for name in ["CREATED", "DESCRIPTION", "DTEND", "DURATION", "LAST-MODIFIED",
        "LOCATION", "RECURRENCE-ID", "RRULE", "SUMMARY"]:
      atMostOne(component, name, diagnostics)
    if component.properties("DTEND").len == 0 and
        component.properties("DURATION").len == 0:
      diagnostics.addDiagnostic("AVAILABLE requires DTEND or DURATION")
    if component.properties("DTEND").len > 0 and
        component.properties("DURATION").len > 0:
      diagnostics.addDiagnostic("AVAILABLE cannot contain both DTEND and DURATION")
    validateRRuleProperty(component, diagnostics)
    validateRecurrenceDateProperties(component, diagnostics)
  else: discard
  if component.name in ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY",
      "VAVAILABILITY", "AVAILABLE"]:
    validateTemporalProperty(component, "DTSTAMP", diagnostics,
      utcOnly = true, allowDate = false)
    let availabilityTemporal = component.name in ["VAVAILABILITY", "AVAILABLE"]
    validateTemporalProperty(component, "DTSTART", diagnostics,
      allowDate = not availabilityTemporal)
    validateTemporalProperty(component, "DTEND", diagnostics,
      allowDate = not availabilityTemporal)
    validateTemporalProperty(component, "DUE", diagnostics)
    validateTemporalProperty(component, "RECURRENCE-ID", diagnostics)
    validateTemporalProperty(component, "COMPLETED", diagnostics,
      utcOnly = true, allowDate = false)
    validateTemporalProperty(component, "CREATED", diagnostics,
      utcOnly = true, allowDate = false)
    validateTemporalProperty(component, "LAST-MODIFIED", diagnostics,
      utcOnly = true, allowDate = false)
    validateDurationProperty(component, "DURATION", diagnostics)
    if component.name == "VFREEBUSY":
      validateTemporalProperty(component, "DTSTART", diagnostics,
        utcOnly = true, allowDate = false)
      validateTemporalProperty(component, "DTEND", diagnostics,
        utcOnly = true, allowDate = false)
    if availabilityTemporal:
      for name in ["DTSTART", "DTEND"]:
        for property in component.properties(name):
          if not property.value.endsWith("Z") and
              property.parameterValue("TZID").len == 0:
            diagnostics.addDiagnostic(name &
              " in availability components requires UTC or TZID")
    if component.name in ["VEVENT", "VFREEBUSY", "VAVAILABILITY", "AVAILABLE"]:
      validateTemporalPair(component, "DTSTART", "DTEND", diagnostics)
    elif component.name == "VTODO":
      validateTemporalPair(component, "DTSTART", "DUE", diagnostics)
  elif component.name in ["STANDARD", "DAYLIGHT"]:
    validateTemporalProperty(component, "DTSTART", diagnostics,
      allowDate = false, localOnly = true)
    validateOffsetProperty(component, "TZOFFSETFROM", diagnostics)
    validateOffsetProperty(component, "TZOFFSETTO", diagnostics)
    validateRRuleProperty(component, diagnostics)
    validateObservanceRecurrence(component, diagnostics)
  elif component.name == "VTIMEZONE":
    validateTemporalProperty(component, "LAST-MODIFIED", diagnostics,
      utcOnly = true, allowDate = false)
    for property in component.properties("TZURL"):
      if not validVCardUri(property.value):
        diagnostics.addDiagnostic("TZURL must contain a URI value")
  elif component.name == "VALARM":
    validateDurationProperty(component, "DURATION", diagnostics)
    validateAttachProperty(component, diagnostics)
  if component.name in ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY", "VALARM",
      "VAVAILABILITY"]:
    for name in ["ATTENDEE", "ORGANIZER"]:
      for property in component.properties(name):
        if not validCalendarUri(property.value):
          diagnostics.addDiagnostic(name & " must contain a CAL-ADDRESS URI")
  if component.name in ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY",
      "VAVAILABILITY", "AVAILABLE"]:
    for name in ["URL", "RELATED-TO"]:
      for property in component.properties(name):
        if not validCalendarUri(property.value):
          diagnostics.addDiagnostic(name & " must contain a URI value")
  if component.name in ["VEVENT", "VTODO", "VJOURNAL"]:
    validateRRuleProperty(component, diagnostics)
    validateRecurrenceDateProperties(component, diagnostics)
    validateIntegerProperty(component, "PRIORITY", 0, 9, diagnostics)
    validateIntegerProperty(component, "SEQUENCE", 0, 999999999, diagnostics)
    validateGeoProperty(component, diagnostics)
    validateAttachProperty(component, diagnostics)
    if component.properties("CLASS").len > 0 and
        firstValue(component, "CLASS").toUpperAscii notin
        ["PUBLIC", "PRIVATE", "CONFIDENTIAL"] and
        not validIanaToken(firstValue(component, "CLASS")):
      diagnostics.addDiagnostic("CLASS is not an RFC 5545 value")
    if component.properties("TRANSP").len > 0 and
        firstValue(component, "TRANSP").toUpperAscii notin
        ["OPAQUE", "TRANSPARENT"]:
      diagnostics.addDiagnostic("TRANSP is not an RFC 5545 value")
  for child in component.children():
    validateCalendarComponent(child, diagnostics, component.name)
  validateAlarmContext(component, diagnostics)
  validateKnownPropertyPlacement(component, diagnostics)
  validateRequestStatus(component, diagnostics)

proc validateKnownChildPlacement(component: Component;
    diagnostics: var seq[Diagnostic]) =
  ## RFC 5545 defines a closed set of standard child components for each
  ## container. Unknown extensions remain accepted and lossless.
  for child in component.children():
    case component.name
    of "VCALENDAR":
      if child.name notin ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY",
          "VTIMEZONE", "VAVAILABILITY"]:
        if child.name in ["VALARM", "STANDARD", "DAYLIGHT", "AVAILABLE"]:
          diagnostics.addDiagnostic(child.name & " is not allowed directly in VCALENDAR")
    of "VTIMEZONE":
      if child.name notin ["STANDARD", "DAYLIGHT"] and child.name in
          ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY", "VALARM", "AVAILABLE"]:
        diagnostics.addDiagnostic(child.name & " is not allowed in VTIMEZONE")
    of "VEVENT", "VTODO":
      if child.name notin ["VALARM"] and child.name in
          ["STANDARD", "DAYLIGHT", "VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY",
           "VTIMEZONE", "VAVAILABILITY", "AVAILABLE"]:
        diagnostics.addDiagnostic(child.name & " is not allowed in " &
            component.name)
    of "VAVAILABILITY":
      if child.name notin ["AVAILABLE"] and child.name in
          ["STANDARD", "DAYLIGHT", "VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY",
           "VTIMEZONE", "VAVAILABILITY", "VALARM"]:
        diagnostics.addDiagnostic(child.name & " is not allowed in VAVAILABILITY")
    else: discard

proc collectTimezoneIds(component: Component; ids: var seq[string]) =
  if component.name == "VTIMEZONE":
    let timezoneId = firstValue(component, "TZID")
    if timezoneId.len > 0 and timezoneId notin ids:
      ids.add(timezoneId)
  for child in component.children():
    collectTimezoneIds(child, ids)

proc validateAvailabilityTimezoneRefs(component: Component; ids: seq[string];
    diagnostics: var seq[Diagnostic]) =
  if component.name in ["VAVAILABILITY", "AVAILABLE"]:
    for name in ["DTSTART", "DTEND"]:
      for property in component.properties(name):
        let timezoneId = property.parameterValue("TZID")
        if timezoneId.len > 0 and timezoneId notin ids:
          diagnostics.addDiagnostic(name & " references missing VTIMEZONE " &
            timezoneId)
  for child in component.children():
    validateAvailabilityTimezoneRefs(child, ids, diagnostics)

proc validate*(input: string): seq[Diagnostic] =
  try:
    let components = parseComponents(input)
    if components.len == 0:
      return @[Diagnostic(severity: dsError, message: "empty document")]
    for item in components:
      case item.name
      of "VCARD":
        let versions = item.properties("VERSION")
        if versions.len != 1:
          result.add(Diagnostic(severity: dsError,
              message: "vCard requires exactly one VERSION"))
        elif versions[0].value != "4.0":
          result.add(Diagnostic(severity: dsError,
              message: "vCard VERSION must be 4.0"))
        if item.entries.len == 0 or item.entries[0].kind != ekProperty or
            item.entries[0].property.name != "VERSION":
          result.add(Diagnostic(severity: dsError,
            message: "vCard VERSION must immediately follow BEGIN:VCARD"))
        if item.properties("FN").len == 0:
          result.add(Diagnostic(severity: dsError,
            message: "vCard requires at least one FN"))
        validateVCard(item, result)
      of "VCALENDAR":
        let versions = item.properties("VERSION")
        let productIds = item.properties("PRODID")
        if versions.len != 1:
          result.add(Diagnostic(severity: dsError,
            message: "iCalendar requires exactly one VERSION"))
        elif versions[0].value != "2.0":
          result.add(Diagnostic(severity: dsError,
              message: "iCalendar VERSION must be 2.0"))
        if productIds.len != 1:
          result.add(Diagnostic(severity: dsError,
            message: "iCalendar requires exactly one PRODID"))
        elif productIds[0].value.len == 0:
          result.addDiagnostic("iCalendar PRODID must not be empty")
        if item.children().len == 0:
          result.add(Diagnostic(severity: dsError,
            message: "iCalendar requires at least one calendar component"))
        let methods = item.properties("METHOD")
        if methods.len > 1:
          result.addDiagnostic("iCalendar allows at most one METHOD")
        if methods.len == 1 and not validIanaToken(methods[0].value):
          result.addDiagnostic("METHOD is not an RFC 5545 value")
        let scales = item.properties("CALSCALE")
        if scales.len > 1:
          result.addDiagnostic("iCalendar allows at most one CALSCALE")
        if scales.len == 1 and scales[0].value.toUpperAscii != "GREGORIAN":
          result.addDiagnostic("CALSCALE is not an RFC 5545 value")
        validateKnownChildPlacement(item, result)
        var timezoneIds: seq[string]
        for child in item.children():
          if child.name == "VTIMEZONE":
            let timezoneId = firstValue(child, "TZID")
            if timezoneId.len > 0 and timezoneId in timezoneIds:
              result.addDiagnostic("iCalendar cannot repeat VTIMEZONE TZID " &
                timezoneId)
            elif timezoneId.len > 0:
              timezoneIds.add(timezoneId)
          validateCalendarComponent(child, result, item.name)
        collectTimezoneIds(item, timezoneIds)
        validateAvailabilityTimezoneRefs(item, timezoneIds, result)
      else:
        result.add(Diagnostic(severity: dsError,
          message: "unsupported top-level component: " & item.name))
    if components.len > 1:
      result.add(Diagnostic(severity: dsError,
        message: "document must contain exactly one top-level component"))
  except ParseError as error:
    result.add(Diagnostic(severity: dsError, message: error.msg))
  except ComponentParseError as error:
    result.add(Diagnostic(severity: dsError, message: error.msg))

proc isValid*(input: string): bool =
  for diagnostic in validate(input):
    if diagnostic.severity == dsError: return false
  true

proc detectKind*(input: string): DocumentKind =
  try:
    if input.len == 0: return dkUnknown
    var ending = input.find("\r\n")
    if ending < 0: ending = input.find('\n')
    if ending < 0: ending = input.len
    if ending == 0 or ending > 1024: return dkUnknown
    let first = parseContentLine(input[0..<ending])
    if first.name != "BEGIN": return dkUnknown
    case first.value.toUpperAscii
    of "VCARD": dkVCard
    of "VCALENDAR": dkICalendar
    else: dkUnknown
  except ParseError:
    dkUnknown

proc validationJson*(input: string): string =
  var root = newJObject()
  let diagnostics = validate(input)
  var hasError = false
  for diagnostic in diagnostics:
    if diagnostic.severity == dsError: hasError = true
  root["valid"] = %(not hasError)
  root["kind"] = %($detectKind(input))
  root["diagnostics"] = newJArray()
  for diagnostic in diagnostics:
    root["diagnostics"].add(%*{
      "severity": $diagnostic.severity,
      "line": diagnostic.line,
      "message": diagnostic.message
    })
  $root

proc normalizeDocument*(input: string): string =
  serializeComponents(parseComponents(input))

# Keep source mapping stable for gcov-generated exception branches.
# Coverage is intentionally strict.
# End of module.
