# SPDX-License-Identifier: Apache-2.0
## Bounded, deterministic RRULE expansion for application projections.
import std/[algorithm, sequtils, times, strutils, sets]

type
  ByDayRule = tuple[weekday: string, ordinal: int]
  RecurrenceLimitError* = object of CatchableError
  RecurrenceWindow* = object
    first*: DateTime
    last*: DateTime
    maxOccurrences*: int

proc compact(dt: DateTime): string = dt.format("yyyyMMdd'T'HHmmss'Z'")

proc parseUtc(value: string): DateTime =
  try: parse(value, "yyyyMMdd'T'HHmmss'Z'", utc())
  except ValueError:
    try: parse(value, "yyyyMMdd", utc())
    except ValueError: raise newException(RecurrenceLimitError, "unsupported DTSTART/UNTIL")

proc weekdayToken(day: WeekDay): string =
  case day
  of dMon: "MO"
  of dTue: "TU"
  of dWed: "WE"
  of dThu: "TH"
  of dFri: "FR"
  of dSat: "SA"
  of dSun: "SU"

proc weekdayIndex(token: string): int =
  case token
  of "MO": 0
  of "TU": 1
  of "WE": 2
  of "TH": 3
  of "FR": 4
  of "SA": 5
  else: 6

proc ordinalWeekdayMatches(dt: DateTime; rule: ByDayRule): bool =
  let lastDay = getDaysInMonth(dt.month, dt.year)
  let targetDay = if rule.ordinal > 0:
    var candidate = 1
    while candidate <= 7 and weekdayToken(
        dateTime(dt.year, dt.month, candidate, zone = utc()).weekday) != rule.weekday:
      inc candidate
    candidate + 7 * (rule.ordinal - 1)
  else:
    var candidate = lastDay
    while candidate >= lastDay - 6 and weekdayToken(
        dateTime(dt.year, dt.month, candidate, zone = utc()).weekday) != rule.weekday:
      dec candidate
    candidate + 7 * (rule.ordinal + 1)
  dt.monthday == targetDay

proc ordinalYearWeekdayMatches(dt: DateTime; rule: ByDayRule): bool =
  let firstDay = dateTime(dt.year, mJan, 1, zone = utc())
  let lastDay = dateTime(dt.year, mDec, 31, zone = utc())
  let targetDay = if rule.ordinal > 0:
    var candidate = 1
    while candidate <= 7 and weekdayToken(
        (firstDay + initDuration(days = candidate - 1)).weekday) != rule.weekday:
      inc candidate
    candidate + 7 * (rule.ordinal - 1)
  else:
    var candidate = 365 + (if isLeapYear(dt.year): 1 else: 0)
    while candidate >= 359 and weekdayToken(
        (lastDay - initDuration(days = (365 + (if isLeapYear(
            dt.year): 1 else: 0)) - candidate)).weekday) != rule.weekday:
      dec candidate
    candidate + 7 * (rule.ordinal + 1)
  let dayOfYear = dt.yearday.int + 1
  dayOfYear == targetDay

proc expandRecurrence*(startValue, rule: string; window: RecurrenceWindow): seq[string] =
  ## Expand a bounded UTC date/date-time rule. Unsupported clauses fail closed.
  if window.maxOccurrences <= 0 or window.maxOccurrences > 100_000:
    raise newException(RecurrenceLimitError, "invalid recurrence limit")
  if window.last < window.first:
    raise newException(RecurrenceLimitError, "invalid recurrence window")
  let start = parseUtc(startValue)
  var frequency = ""
  var interval = 1
  var count = 0
  var until = start
  var hasUntil = false
  var untilValue = ""
  var byDays = initHashSet[string]()
  var byDayRules: seq[ByDayRule]
  var byMonths = initHashSet[int]()
  var byMonthDays = initHashSet[int]()
  var byHours = initHashSet[int]()
  var byMinutes = initHashSet[int]()
  var bySeconds = initHashSet[int]()
  var byYearDays = initHashSet[int]()
  var byWeekNumbers = initHashSet[int]()
  var bySetPositions: seq[int]
  var weekStart = "MO"
  var weekStartDay = 0
  var seenKeys = initHashSet[string]()
  for part in rule.split(';'):
    let pair = part.split('=', maxsplit = 1)
    if pair.len != 2: raise newException(RecurrenceLimitError, "invalid RRULE")
    let key = pair[0].toUpperAscii
    let value = pair[1].toUpperAscii
    if key in seenKeys:
      raise newException(RecurrenceLimitError, "duplicate RRULE clause")
    seenKeys.incl(key)
    case key
    of "FREQ": frequency = value
    of "INTERVAL":
      try: interval = parseInt(value)
      except ValueError: raise newException(RecurrenceLimitError, "invalid INTERVAL")
      if interval <= 0: raise newException(RecurrenceLimitError, "invalid INTERVAL")
    of "COUNT":
      try: count = parseInt(value)
      except ValueError: raise newException(RecurrenceLimitError, "invalid COUNT")
      if count <= 0: raise newException(RecurrenceLimitError, "invalid COUNT")
    of "UNTIL":
      untilValue = value
      until = parseUtc(value)
      hasUntil = true
    of "BYDAY":
      for token in value.split(','):
        if token.len < 2: raise newException(RecurrenceLimitError, "invalid BYDAY")
        let weekday = token[^2 .. ^1]
        if weekday notin ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]:
          raise newException(RecurrenceLimitError, "unsupported BYDAY")
        let prefix = token[0 ..< token.len - 2]
        var ordinal = 0
        if prefix.len > 0:
          try: ordinal = parseInt(prefix)
          except ValueError: raise newException(RecurrenceLimitError, "invalid BYDAY")
          if ordinal == 0 or ordinal < -53 or ordinal > 53:
            raise newException(RecurrenceLimitError, "invalid BYDAY ordinal")
          byDayRules.add((weekday: weekday, ordinal: ordinal))
        else:
          byDays.incl(weekday)
    of "BYMONTH":
      for token in value.split(','):
        try:
          let month = parseInt(token)
          if month < 1 or month > 12: raise newException(RecurrenceLimitError,
            "invalid BYMONTH")
          byMonths.incl(month)
        except ValueError:
          raise newException(RecurrenceLimitError, "invalid BYMONTH")
    of "BYMONTHDAY":
      for token in value.split(','):
        try:
          let day = parseInt(token)
          if day == 0 or day < -31 or day > 31:
            raise newException(RecurrenceLimitError, "invalid BYMONTHDAY")
          byMonthDays.incl(day)
        except ValueError:
          raise newException(RecurrenceLimitError, "invalid BYMONTHDAY")
    of "BYHOUR", "BYMINUTE", "BYSECOND", "BYYEARDAY", "BYWEEKNO":
      for token in value.split(','):
        try:
          let number = parseInt(token)
          let valid =
            if key == "BYHOUR": number in 0..23
            elif key == "BYMINUTE" or key == "BYSECOND": number in 0..59
            elif key == "BYYEARDAY": number != 0 and number in -366..366
            else: number != 0 and number in -53..53
          if not valid: raise newException(RecurrenceLimitError, "invalid " & key)
          case key
          of "BYHOUR": byHours.incl(number)
          of "BYMINUTE": byMinutes.incl(number)
          of "BYSECOND": bySeconds.incl(number)
          of "BYYEARDAY": byYearDays.incl(number)
          else: byWeekNumbers.incl(number)
        except ValueError:
          raise newException(RecurrenceLimitError, "invalid " & key)
    of "WKST":
      if value notin ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]:
        raise newException(RecurrenceLimitError, "invalid WKST")
      weekStart = value
      weekStartDay = weekdayIndex(value)
    of "BYSETPOS":
      for token in value.split(','):
        try:
          let position = parseInt(token)
          if position == 0 or position < -366 or position > 366:
            raise newException(RecurrenceLimitError, "invalid BYSETPOS")
          bySetPositions.add(position)
        except ValueError:
          raise newException(RecurrenceLimitError, "invalid BYSETPOS")
    else: raise newException(RecurrenceLimitError, "unsupported RRULE clause")
  if count > 0 and hasUntil:
    raise newException(RecurrenceLimitError, "COUNT and UNTIL are mutually exclusive")
  if hasUntil and ((startValue.len == 8) != (untilValue.len == 8)):
    raise newException(RecurrenceLimitError, "DTSTART and UNTIL value types differ")
  if frequency notin ["SECONDLY", "MINUTELY", "HOURLY", "DAILY", "WEEKLY",
      "MONTHLY", "YEARLY"]:
    raise newException(RecurrenceLimitError, "unsupported RRULE frequency")
  if byYearDays.len > 0 and frequency != "YEARLY":
    raise newException(RecurrenceLimitError, "BYYEARDAY requires YEARLY")
  if byWeekNumbers.len > 0 and frequency != "YEARLY":
    raise newException(RecurrenceLimitError, "BYWEEKNO requires YEARLY")
  if byMonthDays.len > 0 and frequency == "WEEKLY":
    raise newException(RecurrenceLimitError, "BYMONTHDAY is invalid for WEEKLY")
  if bySetPositions.len > 0 and frequency in ["SECONDLY", "MINUTELY", "HOURLY"]:
    raise newException(RecurrenceLimitError, "BYSETPOS requires a calendar period")
  if frequency in ["SECONDLY", "MINUTELY"] and (byDays.len > 0 or
      byDayRules.len > 0 or byMonths.len > 0 or byMonthDays.len > 0 or
          byYearDays.len > 0 or byWeekNumbers.len > 0):
    raise newException(RecurrenceLimitError, "unsupported subrule for fine frequency")
  if frequency == "WEEKLY" and byDayRules.len > 0:
    raise newException(RecurrenceLimitError, "weekly BYDAY ordinals are unsupported")

  if frequency in ["HOURLY", "MINUTELY"] and
      (byMinutes.len > 0 or bySeconds.len > 0):
    ## For sub-day frequencies, expand the selected minute/second candidates
    ## inside each interval instead of filtering a single DTSTART clock value.
    var minutes = if byMinutes.len > 0: toSeq(byMinutes) else: @[
        start.minute.int]
    var seconds = if bySeconds.len > 0: toSeq(bySeconds) else: @[
        start.second.int]
    minutes.sort(system.cmp[int])
    seconds.sort(system.cmp[int])
    var cursor = start
    var generated = 0
    var emitted = 0
    while cursor <= window.last and generated < 100_000:
      let hourMatches = byHours.len == 0 or cursor.hour.int in byHours
      let monthMatches = byMonths.len == 0 or cursor.month.int in byMonths
      let lastDay = getDaysInMonth(cursor.month, cursor.year)
      var monthDayMatches = byMonthDays.len == 0
      if byMonthDays.len > 0:
        monthDayMatches = false
        for value in byMonthDays:
          let candidate = if value < 0: lastDay + value + 1 else: value
          if candidate == cursor.monthday: monthDayMatches = true
      var dayMatches = byDays.len == 0 and byDayRules.len == 0
      if byDayRules.len > 0:
        dayMatches = false
        for byDay in byDayRules:
          if frequency == "YEARLY" and byMonths.len == 0:
            if ordinalYearWeekdayMatches(cursor, byDay): dayMatches = true
          elif ordinalWeekdayMatches(cursor, byDay): dayMatches = true
      elif byDays.len > 0:
        dayMatches = weekdayToken(cursor.weekday) in byDays
      let yearDay = cursor.yearday.int + 1
      let daysInYear = if isLeapYear(cursor.year): 366 else: 365
      let yearDayMatches = byYearDays.len == 0 or byYearDays.anyIt(
        (it > 0 and it == yearDay) or (it < 0 and daysInYear + it + 1 == yearDay))
      let isoWeek = getIsoWeekAndYear(cursor).isoweek.int
      let weeksInYear = getWeeksInIsoYear(IsoYear(cursor.year)).int
      let weekMatches = byWeekNumbers.len == 0 or byWeekNumbers.anyIt(
        (it > 0 and it == isoWeek) or (it < 0 and weeksInYear + it + 1 == isoWeek))
      if hourMatches and monthMatches and monthDayMatches and dayMatches and
          yearDayMatches and weekMatches:
        for minute in minutes:
          if count > 0 and emitted >= count: break
          for second in seconds:
            if count > 0 and emitted >= count: break
            let value = if frequency == "HOURLY":
              dateTime(cursor.year, cursor.month, cursor.monthday,
                cursor.hour.int, minute, second, zone = utc())
            else:
              dateTime(cursor.year, cursor.month, cursor.monthday,
                cursor.hour.int, cursor.minute.int, second, zone = utc())
            if value < start or (hasUntil and value > until): continue
            inc emitted
            if value >= window.first and value <= window.last:
              result.add(compact(value))
      inc generated
      cursor = if frequency == "HOURLY": cursor + initDuration(hours = interval)
        else: cursor + initDuration(minutes = interval)
    if generated >= 100_000 and result.len == 0 and count > 0:
      raise newException(RecurrenceLimitError, "recurrence expansion limit exceeded")
    return

  if frequency in ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"] and
      (byHours.len > 0 or byMinutes.len > 0 or bySeconds.len > 0):
    ## Date-based frequencies expand the time part inside each matching
    ## date. The simple cursor below is intentionally retained for rules
    ## without time selectors; this branch prevents BYHOUR/BYMINUTE/
    ## BYSECOND from collapsing multiple valid instances into one.
    var hours = if byHours.len > 0: toSeq(byHours) else: @[start.hour.int]
    var minutes = if byMinutes.len > 0: toSeq(byMinutes) else: @[
        start.minute.int]
    var seconds = if bySeconds.len > 0: toSeq(bySeconds) else: @[
        start.second.int]
    hours.sort(system.cmp[int])
    minutes.sort(system.cmp[int])
    seconds.sort(system.cmp[int])
    let dayStart = dateTime(start.year, start.month, start.monthday, zone = utc())
    var dayEnd = window.last
    if hasUntil and until < dayEnd:
      dayEnd = until
    var day = dayStart
    var generatedDays = 0
    var emitted = 0
    var periodCandidates: seq[DateTime]
    var currentPeriod = ""

    template flushTimePeriod() =
      if periodCandidates.len > 0:
        var positions = bySetPositions
        positions.sort(system.cmp[int])
        var selected: seq[DateTime]
        for position in positions:
          let index = if position > 0: position - 1 else: periodCandidates.len + position
          if index >= 0 and index < periodCandidates.len and
              periodCandidates[index] notin selected:
            selected.add(periodCandidates[index])
        selected.sort(proc(a, b: DateTime): int = cmp(a, b))
        for value in selected:
          if count > 0 and emitted >= count: break
          inc emitted
          if value >= window.first and value <= window.last:
            result.add(compact(value))
        periodCandidates.setLen(0)

    while day <= dayEnd and generatedDays < 100_000:
      let elapsedDays = (day - dayStart).inDays
      let startOffset = (start.weekday.int - 1 - weekStartDay + 7) mod 7
      let dayOffset = (day.weekday.int - 1 - weekStartDay + 7) mod 7
      let elapsedWeeks = (elapsedDays + startOffset - dayOffset) div 7
      let monthDistance = (day.year - start.year) * 12 +
        (day.month.int - start.month.int)
      let periodMatches =
        if frequency == "DAILY": elapsedDays mod interval == 0
        elif frequency == "WEEKLY": elapsedWeeks mod interval == 0
        elif frequency == "MONTHLY": monthDistance >= 0 and
            monthDistance mod interval == 0
        else: day.year >= start.year and (day.year - start.year) mod interval == 0
      let monthMatches = byMonths.len == 0 or day.month.int in byMonths
      let yearDay = day.yearday.int + 1
      let daysInYear = if isLeapYear(day.year): 366 else: 365
      let yearDayMatches = byYearDays.len == 0 or byYearDays.anyIt(
        (it > 0 and it == yearDay) or (it < 0 and daysInYear + it + 1 == yearDay))
      let isoWeek = getIsoWeekAndYear(day).isoweek.int
      let weeksInYear = getWeeksInIsoYear(IsoYear(day.year)).int
      let weekMatches = byWeekNumbers.len == 0 or byWeekNumbers.anyIt(
        (it > 0 and it == isoWeek) or (it < 0 and weeksInYear + it + 1 == isoWeek))
      let defaultMonth = if frequency == "YEARLY" and byMonths.len == 0 and
          byYearDays.len == 0 and byWeekNumbers.len == 0:
        day.month == start.month else: true
      let defaultDay = if frequency in ["MONTHLY", "YEARLY"] and
          byMonthDays.len == 0 and byDays.len == 0 and byDayRules.len == 0 and
          byYearDays.len == 0 and byWeekNumbers.len == 0:
        day.monthday == start.monthday else: true
      let weeklyDefault = frequency == "WEEKLY" and byDays.len == 0 and
        byDayRules.len == 0 and day.weekday == start.weekday
      var selectedMonthDay = defaultDay
      if byMonthDays.len > 0:
        selectedMonthDay = false
        let lastDay = getDaysInMonth(day.month, day.year)
        for value in byMonthDays:
          let candidate = if value < 0: lastDay + value + 1 else: value
          if candidate == day.monthday: selectedMonthDay = true
      var daySelector = weeklyDefault
      if frequency != "WEEKLY": daySelector = true
      if byDayRules.len > 0:
        daySelector = false
        for byDay in byDayRules:
          if ordinalWeekdayMatches(day, byDay): daySelector = true
      elif byDays.len > 0:
        daySelector = weekdayToken(day.weekday) in byDays
      let dateMatches = periodMatches and monthMatches and defaultMonth and
        selectedMonthDay and daySelector and yearDayMatches and weekMatches
      if dateMatches:
        let period = if frequency == "WEEKLY":
          "W" & $elapsedWeeks
          elif frequency == "MONTHLY": "M" & $day.year & "." & $day.month.int
          elif frequency == "YEARLY": "Y" & $day.year
          else: "D" & $day.year & "." & $day.month.int & "." & $day.monthday
        if bySetPositions.len > 0 and period != currentPeriod:
          flushTimePeriod()
          currentPeriod = period
        for hour in hours:
          if count > 0 and emitted >= count: break
          for minute in minutes:
            if count > 0 and emitted >= count: break
            for second in seconds:
              if count > 0 and emitted >= count: break
              let value = dateTime(day.year, day.month, day.monthday, hour,
                minute, second, zone = utc())
              if value < start or (hasUntil and value > until): continue
              if bySetPositions.len > 0:
                periodCandidates.add(value)
              else:
                inc emitted
                if value >= window.first and value <= window.last:
                  result.add(compact(value))
      inc generatedDays
      day = day + initDuration(days = 1)
    if bySetPositions.len > 0:
      flushTimePeriod()
    if generatedDays >= 100_000 and result.len == 0 and count > 0:
      raise newException(RecurrenceLimitError, "recurrence expansion limit exceeded")
    return

  var cursor = start
  var emitted = 0
  var generated = 0
  var periodCandidates: seq[DateTime]
  var currentPeriod = ""

  template flushPeriod() =
    if periodCandidates.len > 0:
      var positions = bySetPositions
      positions.sort(system.cmp[int])
      var selected: seq[DateTime]
      for position in positions:
        let index = if position > 0: position - 1 else: periodCandidates.len + position
        if index >= 0 and index < periodCandidates.len and
            periodCandidates[index] notin selected:
          selected.add(periodCandidates[index])
      selected.sort(proc(a, b: DateTime): int = cmp(a, b))
      for value in selected:
        if count > 0 and emitted >= count: break
        inc emitted
        if value >= window.first and value <= window.last:
          result.add(compact(value))
      periodCandidates.setLen(0)

  while generated < 100_000 and result.len < window.maxOccurrences:
    if count > 0 and emitted >= count: break
    if hasUntil and cursor > until: break
    let elapsedSeconds = (cursor - start).inSeconds
    let elapsedDays = elapsedSeconds div 86400
    let startOffset = (start.weekday.int - 1 - weekStartDay + 7) mod 7
    let cursorOffset = (cursor.weekday.int - 1 - weekStartDay + 7) mod 7
    let elapsedWeeks = ((elapsedDays + startOffset - cursorOffset) div 7)
    let period = if frequency == "WEEKLY":
      "W" & $elapsedWeeks
      elif frequency == "MONTHLY": "M" & $cursor.year & "." & $cursor.month.int
      elif frequency == "YEARLY": "Y" & $cursor.year
      else: "D" & $cursor.year & "." & $cursor.month.int & "." &
          $cursor.monthday
    if bySetPositions.len > 0 and period != currentPeriod:
      flushPeriod()
      currentPeriod = period
    let monthDistance = (cursor.year - start.year) * 12 +
      (cursor.month.int - start.month.int)
    let periodMatches =
      if frequency == "SECONDLY": elapsedSeconds mod interval == 0
      elif frequency == "MINUTELY": (elapsedSeconds div 60) mod interval == 0
      elif frequency == "HOURLY": (elapsedSeconds div 3600) mod interval == 0
      elif frequency == "DAILY": true
      elif frequency == "WEEKLY": elapsedWeeks mod interval == 0
      elif frequency == "MONTHLY": monthDistance >= 0 and
          monthDistance mod interval == 0
      else: cursor.year >= start.year and (cursor.year -
          start.year) mod interval == 0
    let monthMatches = byMonths.len == 0 or cursor.month.int in byMonths
    let hourMatches = byHours.len == 0 or cursor.hour in byHours
    let minuteMatches = byMinutes.len == 0 or cursor.minute in byMinutes
    let secondMatches = bySeconds.len == 0 or cursor.second in bySeconds
    let yearDay = cursor.yearday.int + 1
    let daysInYear = if isLeapYear(cursor.year): 366 else: 365
    let yearDayMatches = byYearDays.len == 0 or byYearDays.anyIt(
      (it > 0 and it == yearDay) or (it < 0 and daysInYear + it + 1 == yearDay))
    let isoWeek = getIsoWeekAndYear(cursor).isoweek.int
    let weeksInYear = getWeeksInIsoYear(IsoYear(cursor.year)).int
    let weekMatches = byWeekNumbers.len == 0 or byWeekNumbers.anyIt(
      (it > 0 and it == isoWeek) or (it < 0 and weeksInYear + it + 1 == isoWeek))
    let defaultMonth = if frequency == "YEARLY" and byMonths.len == 0 and
        byYearDays.len == 0 and byWeekNumbers.len == 0:
      cursor.month == start.month else: true
    let defaultDay = if frequency in ["MONTHLY", "YEARLY"] and
        byMonthDays.len == 0 and byDays.len == 0 and byDayRules.len == 0 and
        byYearDays.len == 0 and byWeekNumbers.len == 0:
      cursor.monthday == start.monthday else: true
    var selectedMonthDay = defaultDay
    if byMonthDays.len > 0:
      selectedMonthDay = false
      let lastDay = getDaysInMonth(cursor.month, cursor.year)
      for value in byMonthDays:
        let day = if value < 0: lastDay + value + 1 else: value
        if day == cursor.monthday: selectedMonthDay = true
    var daySelector = true
    if byDayRules.len > 0:
      daySelector = false
      for byDay in byDayRules:
        if frequency == "YEARLY" and byMonths.len == 0:
          if ordinalYearWeekdayMatches(cursor, byDay): daySelector = true
        elif ordinalWeekdayMatches(cursor, byDay): daySelector = true
    elif byDays.len > 0:
      daySelector = weekdayToken(cursor.weekday) in byDays
    let dayMatches = periodMatches and monthMatches and defaultMonth and
      selectedMonthDay and daySelector and hourMatches and minuteMatches and
      secondMatches and yearDayMatches and weekMatches
    if dayMatches:
      if bySetPositions.len > 0:
        periodCandidates.add(cursor)
      else:
        inc emitted
        if cursor >= window.first and cursor <= window.last: result.add(compact(cursor))
    inc generated
    if frequency == "SECONDLY":
      cursor = cursor + initDuration(seconds = interval)
    elif frequency == "MINUTELY":
      cursor = cursor + initDuration(minutes = interval)
    elif frequency == "HOURLY":
      cursor = cursor + initDuration(hours = interval)
    elif frequency == "DAILY":
      cursor = cursor + initDuration(days = interval)
    elif frequency == "WEEKLY" and byDays.len > 0:
      cursor = cursor + initDuration(days = 1)
    elif frequency == "WEEKLY":
      cursor = cursor + initDuration(days = 7 * interval)
    else:
      cursor = cursor + initDuration(days = 1)
  if bySetPositions.len > 0:
    flushPeriod()
  if generated >= 100_000 and result.len == 0 and count > 0:
    raise newException(RecurrenceLimitError, "recurrence expansion limit exceeded")

proc expandRecurrenceSet*(startValue, rule: string;
                          additions, exclusions: openArray[string];
                          window: RecurrenceWindow): seq[string] =
  ## Expands RRULE plus explicit RDATE/EXDATE values without duplicate output.
  var values = if rule.len > 0:
    expandRecurrence(startValue, rule, window)
  else:
    let start = parseUtc(startValue)
    if start >= window.first and start <= window.last: @[compact(
        start)] else: @[]
  var included = initHashSet[string]()
  for value in values: included.incl(value)
  for value in additions:
    let parsed = parseUtc(value)
    if parsed >= window.first and parsed <= window.last: included.incl(compact(parsed))
  for value in exclusions:
    included.excl(compact(parseUtc(value)))
  result = toSeq(included)
  result.sort(system.cmp[string])
  if result.len > window.maxOccurrences:
    result.setLen(window.maxOccurrences)
