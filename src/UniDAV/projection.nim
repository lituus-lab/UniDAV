# SPDX-License-Identifier: Apache-2.0
## Stable JSON projection for thin C/Python/WASM hosts. The raw standards
## document remains authoritative; this view is intentionally non-destructive.
import std/[json, sets, strutils]
import component, contentline, document, editing

proc isoDateTime(value: string): string =
  if value.len == 16 and value[8] == 'T' and value[^1] == 'Z':
    value[0..3] & "-" & value[4..5] & "-" & value[6..7] & "T" &
      value[9..10] & ":" & value[11..12] & ":" & value[13..14] & "Z"
  elif value.len == 15 and value[8] == 'T':
    value[0..3] & "-" & value[4..5] & "-" & value[6..7] & "T" &
      value[9..10] & ":" & value[11..12] & ":" & value[13..14]
  elif value.len == 8:
    value[0..3] & "-" & value[4..5] & "-" & value[6..7] & "T00:00:00"
  else:
    value

proc firstParameter(component: Component; propertyName,
    parameterName: string): string =
  let properties = component.properties(propertyName)
  if properties.len == 0: return ""
  for parameter in properties[0].params:
    if parameter.name.cmpIgnoreCase(parameterName) == 0 and
        parameter.values.len > 0:
      return parameter.values[0]

proc parameterValue(property: ContentLine; name: string): string =
  for parameter in property.params:
    if parameter.name.cmpIgnoreCase(name) == 0 and parameter.values.len > 0:
      return parameter.values[0]

proc parameterValues(property: ContentLine; name: string): seq[string] =
  for parameter in property.params:
    if parameter.name.cmpIgnoreCase(name) == 0:
      result = parameter.values
      return

proc projectedId(property: ContentLine; prefix: string; index: int): string =
  let propId = property.parameterValue("PROP-ID")
  if propId.len > 0: propId else: prefix & $index

proc contextObject(property: ContentLine): JsonNode =
  result = newJObject()
  for value in property.parameterValues("TYPE"):
    result[value.toLowerAscii] = %true

proc addContextualFields(target: JsonNode; property: ContentLine) =
  let contexts = property.contextObject
  if contexts.len > 0: target["contexts"] = contexts
  let preference = property.parameterValue("PREF")
  if preference.len > 0:
    try: target["pref"] = %parseInt(preference)
    except ValueError: discard

proc projectVCard(card: Component): JsonNode =
  result = %*{
    "@type": "Card", "version": "1.0", "kind": "contact",
    "uid": card.propertyValue("UID"),
    "name": {"full": card.propertyValue("FN"),
      "fullName": card.propertyValue("FN")},
    "organizations": {}, "titles": {}, "emails": {}, "phones": {}, "notes": {},
    "preferredLanguages": {}, "pronouns": {}, "onlineServices": {}
  }
  for index, property in card.properties("ORG"):
    var organization = %*{"name": textUnescape(property.value)}
    organization.addContextualFields(property)
    result["organizations"][property.projectedId("org", index)] = organization
  for index, property in card.properties("TITLE"):
    var title = %*{"name": textUnescape(property.value)}
    title.addContextualFields(property)
    result["titles"][property.projectedId("title", index)] = title
  for index, property in card.properties("EMAIL"):
    var email = %*{"address": textUnescape(property.value)}
    email.addContextualFields(property)
    result["emails"][property.projectedId("email", index)] = email
  for index, property in card.properties("TEL"):
    var phone = %*{"number": textUnescape(property.value)}
    phone.addContextualFields(property)
    var features = newJObject()
    for value in property.parameterValues("TYPE"):
      let feature = value.toLowerAscii
      if feature in ["cell", "fax", "main-number", "pager", "text",
          "textphone", "video", "voice"]:
        features[feature] = %true
    if features.len > 0: phone["features"] = features
    result["phones"][property.projectedId("phone", index)] = phone
  for index, property in card.properties("NOTE"):
    var note = %*{"note": textUnescape(property.value)}
    let created = property.parameterValue("CREATED")
    if created.len > 0: note["created"] = %isoDateTime(created)
    let author = property.parameterValue("AUTHOR-NAME")
    if author.len > 0: note["author"] = %*{"name": textUnescape(author)}
    note.addContextualFields(property)
    result["notes"][property.projectedId("note", index)] = note

  let created = card.propertyValue("CREATED")
  if created.len > 0: result["created"] = %isoDateTime(created)
  let language = card.propertyValue("LANGUAGE")
  if language.len > 0: result["language"] = %language
  for index, property in card.properties("LANG"):
    var languagePref = %*{"language": textUnescape(property.value)}
    languagePref.addContextualFields(property)
    result["preferredLanguages"][property.projectedId("lang",
        index)] = languagePref
  for index, property in card.properties("PRONOUNS"):
    var pronouns = %*{"value": textUnescape(property.value)}
    pronouns.addContextualFields(property)
    result["pronouns"][property.projectedId("pronouns", index)] = pronouns
  for index, property in card.properties("IMPP"):
    var service = %*{"uri": textUnescape(property.value), "vCardName": "impp"}
    let serviceType = property.parameterValue("SERVICE-TYPE")
    if serviceType.len > 0: service["service"] = %serviceType
    let username = property.parameterValue("USERNAME")
    if username.len > 0: service["user"] = %username
    service.addContextualFields(property)
    result["onlineServices"][property.projectedId("os", index)] = service
  for index, property in card.properties("SOCIALPROFILE"):
    var service = %*{"vCardName": "socialprofile"}
    let valueType = property.parameterValue("VALUE").toLowerAscii
    if valueType == "text": service["user"] = %textUnescape(property.value)
    else: service["uri"] = %textUnescape(property.value)
    let serviceType = property.parameterValue("SERVICE-TYPE")
    if serviceType.len > 0: service["service"] = %serviceType
    let username = property.parameterValue("USERNAME")
    if username.len > 0: service["user"] = %username
    service.addContextualFields(property)
    result["onlineServices"][property.projectedId("social", index)] = service

proc projectCalendar(calendar: Component): JsonNode =
  var item: Component
  var kind = ""
  for candidate in calendar.children():
    if candidate.name in ["VEVENT", "VTODO"]:
      item = candidate
      kind = if candidate.name == "VEVENT": "event" else: "task"
      break
  if item.isNil: raise newException(DocumentEditError, "calendar has no event or task")
  let standardType = if kind == "event": "Event" else: "Task"
  let summary = item.propertyValue("SUMMARY")
  result = %*{
    "@type": standardType, "version": "1.0", "kind": kind,
    "uid": item.propertyValue("UID"),
    "title": summary,
    "summary": summary,
    "description": item.propertyValue("DESCRIPTION"),
    "location": item.propertyValue("LOCATION"),
    "start": isoDateTime(item.propertyValue("DTSTART")),
    "end": isoDateTime(item.propertyValue("DTEND")),
    "due": isoDateTime(item.propertyValue("DUE")),
    "completed": isoDateTime(item.propertyValue("COMPLETED")),
    "percentComplete": item.propertyValue("PERCENT-COMPLETE"),
    "priority": item.propertyValue("PRIORITY"),
    "timeZone": (block:
    let parameter = item.firstParameter("DTSTART", "TZID")
    if parameter.len > 0: parameter else: item.propertyValue(
        "X-CONCORDIA-TIMEZONE")),
    "status": item.propertyValue("STATUS").toLowerAscii,
    "recurrenceRules": []
  }
  let recurrence = item.propertyValue("RRULE")
  if recurrence.len > 0:
    var rule = %*{"frequency": "", "interval": 1, "count": 0,
      "until": "", "byDay": [], "byMonth": [], "byMonthDay": [],
          "raw": recurrence}
    for part in recurrence.split(';'):
      let pair = part.split('=', maxsplit = 1)
      if pair.len != 2: continue
      case pair[0].toUpperAscii
      of "FREQ": rule["frequency"] = %pair[1].toLowerAscii
      of "INTERVAL":
        try: rule["interval"] = %parseInt(pair[1])
        except ValueError: discard
      of "COUNT":
        try: rule["count"] = %parseInt(pair[1])
        except ValueError: discard
      of "UNTIL": rule["until"] = %isoDateTime(pair[1])
      of "BYDAY":
        for value in pair[1].split(','):
          rule["byDay"].add(%value)
      of "BYMONTH":
        for value in pair[1].split(','):
          try: rule["byMonth"].add(%parseInt(value))
          except ValueError: discard
      of "BYMONTHDAY":
        for value in pair[1].split(','):
          try: rule["byMonthDay"].add(%parseInt(value))
          except ValueError: discard
      else: discard
    result["recurrenceRules"].add(rule)

proc projectionJson*(input: string): string =
  let roots = parseComponents(input)
  if roots.len != 1: raise newException(DocumentEditError, "one document is required")
  let projection = case roots[0].name
    of "VCARD": projectVCard(roots[0])
    of "VCALENDAR": projectCalendar(roots[0])
    else: raise newException(DocumentEditError, "unsupported document kind")
  $projection

proc compactDateTime(value: string): string =
  if value.len >= 19 and value[4] == '-' and value[7] == '-' and value[10] == 'T':
    result = value[0..3] & value[5..6] & value[8..9] & "T" & value[11..12] &
      value[14..15] & value[17..18]
    if value.len > 19 and value[19] == 'Z': result.add('Z')
  else:
    result = value

proc recurrenceFrequency(value: string): string =
  for part in value.split(';'):
    if part.toUpperAscii.startsWith("FREQ="): return part[5..^1].toUpperAscii

proc allDigits(value: string): bool =
  result = value.len > 0
  for character in value:
    if character notin {'0'..'9'}: return false

proc boundedInteger(value: string; minimum, maximum: int;
    nonZero = false): bool =
  try:
    let parsed = parseInt(value)
    parsed >= minimum and parsed <= maximum and (not nonZero or parsed != 0)
  except ValueError:
    false

proc validUntil(value: string): bool =
  (value.len == 8 and value.allDigits) or
    (value.len == 16 and value[8] == 'T' and value[^1] == 'Z' and
      (value[0..<8] & value[9..<15]).allDigits)

proc validByDay(value: string): bool =
  let weekdays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
  if value.len < 2 or value[^2..^1] notin weekdays: return false
  let ordinal = value[0..^3]
  ordinal.len == 0 or boundedInteger(ordinal, -53, 53, nonZero = true)

proc validRecurrenceRule(value: string; startValue = ""): bool =
  if value.len == 0: return true
  var keys = initHashSet[string]()
  var hasFrequency, hasCount, hasUntil: bool
  var untilValue = ""
  var frequency = ""
  for part in value.split(';'):
    let pair = part.split('=', maxsplit = 1)
    if pair.len != 2 or pair[0].len == 0 or pair[1].len == 0: return false
    let key = pair[0].toUpperAscii
    if key in keys: return false
    keys.incl(key)
    case key
    of "FREQ":
      if pair[1] notin ["SECONDLY", "MINUTELY", "HOURLY", "DAILY", "WEEKLY",
          "MONTHLY", "YEARLY"]: return false
      frequency = pair[1]
      hasFrequency = true
    of "INTERVAL", "COUNT":
      if not boundedInteger(pair[1], 1, high(int)): return false
      if key == "COUNT": hasCount = true
    of "UNTIL":
      if not validUntil(pair[1]): return false
      untilValue = pair[1]
      hasUntil = true
    of "BYDAY":
      for item in pair[1].split(','):
        if not validByDay(item): return false
    of "BYMONTH":
      for item in pair[1].split(','):
        if not boundedInteger(item, 1, 12): return false
    of "BYMONTHDAY":
      for item in pair[1].split(','):
        if not boundedInteger(item, -31, 31, nonZero = true): return false
    of "BYHOUR":
      for item in pair[1].split(','):
        if not boundedInteger(item, 0, 23): return false
    of "BYMINUTE", "BYSECOND":
      for item in pair[1].split(','):
        if not boundedInteger(item, 0, 59): return false
    of "BYYEARDAY":
      for item in pair[1].split(','):
        if not boundedInteger(item, -366, 366, nonZero = true): return false
    of "BYWEEKNO":
      for item in pair[1].split(','):
        if not boundedInteger(item, -53, 53, nonZero = true): return false
    of "BYSETPOS":
      for item in pair[1].split(','):
        if not boundedInteger(item, -366, 366, nonZero = true): return false
    of "WKST":
      if pair[1] notin ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]: return false
    else: return false
  if not hasFrequency or (hasCount and hasUntil): return false
  if startValue.len > 0 and hasUntil and
      ((startValue.len == 8) != (untilValue.len == 8)): return false
  if frequency != "YEARLY" and ("BYYEARDAY" in keys or
      "BYWEEKNO" in keys): return false
  if frequency == "WEEKLY" and "BYMONTHDAY" in keys: return false
  true

proc addText(component: Component; name, value: string; required = false) =
  if required and value.len == 0:
    raise newException(DocumentEditError, "required projected field is empty")
  if value.len > 0:
    component.entries.add(ComponentEntry(kind: ekProperty,
      property: ContentLine(name: name, value: textEscape(value))))

proc patchFirstText(target: Component; name, value: string) =
  var found = false
  var entries: seq[ComponentEntry]
  for entry in target.entries:
    if not found and entry.kind == ekProperty and
        entry.property.name.cmpIgnoreCase(name) == 0:
      found = true
      if value.len > 0:
        var updated = entry
        updated.property.value = textEscape(value)
        entries.add(updated)
    else:
      entries.add(entry)
  if not found and value.len > 0:
    entries.add(ComponentEntry(kind: ekProperty,
      property: ContentLine(name: name, value: textEscape(value))))
  target.entries = entries

proc patchFirstValue(target: Component; name, value: string) =
  ## Patch a structured property without text escaping its delimiters.
  var found = false
  var entries: seq[ComponentEntry]
  for entry in target.entries:
    if not found and entry.kind == ekProperty and
        entry.property.name.cmpIgnoreCase(name) == 0:
      found = true
      if value.len > 0:
        var updated = entry
        updated.property.value = value
        entries.add(updated)
    else:
      entries.add(entry)
  if not found and value.len > 0:
    entries.add(ComponentEntry(kind: ekProperty,
      property: ContentLine(name: name, value: value)))
  target.entries = entries

proc patchedDocument*(input, patchJson: string): string =
  let roots = parseComponents(input)
  if roots.len != 1: raise newException(DocumentEditError, "one document is required")
  let patch = parseJson(patchJson)
  if patch.kind != JObject: raise newException(DocumentEditError, "projection patch must be an object")
  case roots[0].name
  of "VCARD":
    var source = Component(name: "VCARD")
    let fullName = if patch{"name", "fullName"}.getStr.len > 0:
        patch{"name", "fullName"}.getStr else: patch{"name", "full"}.getStr
    source.addText("FN", fullName, required = true)
    for key in ["organizations", "titles", "emails", "phones", "notes"]:
      if patch.hasKey(key) and patch[key].kind != JObject:
        raise newException(DocumentEditError, "projected collection must be an object")
    roots[0].replaceProperties(source, ["FN"])
    template patchFirstCollection(key, propertyName, fieldName: string) =
      if patch.hasKey(key):
        var value = ""
        for _, item in patch[key]: value = item{fieldName}.getStr; break
        roots[0].patchFirstText(propertyName, value)
    patchFirstCollection("organizations", "ORG", "name")
    patchFirstCollection("titles", "TITLE", "name")
    patchFirstCollection("emails", "EMAIL", "address")
    patchFirstCollection("phones", "TEL", "number")
    patchFirstCollection("notes", "NOTE", "note")
  of "VCALENDAR":
    var target: Component
    for child in roots[0].children():
      if child.name in ["VEVENT", "VTODO"]: target = child; break
    if target.isNil: raise newException(DocumentEditError, "calendar item component is absent")
    var source = Component(name: target.name)
    let summary = if patch{"summary"}.getStr.len > 0:
        patch{"summary"}.getStr else: patch{"title"}.getStr
    source.addText("SUMMARY", summary, required = true)
    source.addText("DESCRIPTION", patch{"description"}.getStr)
    source.addText("LOCATION", patch{"location"}.getStr)
    let start = compactDateTime(patch{"start"}.getStr)
    let starts = target.properties("DTSTART")
    if start.len > 0 and (starts.len == 0 or start != starts[0].value):
      source.entries.add(ComponentEntry(kind: ekProperty, property: ContentLine(
          name: "DTSTART", value: start)))
      target.replaceProperties(source, ["SUMMARY", "DESCRIPTION", "LOCATION", "DTSTART"])
    else: target.replaceProperties(source, ["SUMMARY", "DESCRIPTION", "LOCATION"])
    if target.name == "VEVENT" and start.len == 0:
      raise newException(DocumentEditError, "event start is required")
    if patch.hasKey("end"):
      let finish = compactDateTime(patch{"end"}.getStr)
      if finish != target.propertyValue("DTEND"):
        target.patchFirstText("DTEND", finish)
    if patch.hasKey("timeZone"):
      let zone = patch{"timeZone"}.getStr
      if zone.len > 128 or zone.contains({'\r', '\n', ':', ';', ','}):
        raise newException(DocumentEditError, "event timezone is unsafe")
      target.patchFirstText("X-CONCORDIA-TIMEZONE", zone)
    if patch.hasKey("recurrence"):
      let frequency = patch{"recurrence"}.getStr.toUpperAscii
      let currentRule = target.propertyValue("RRULE")
      if frequency == recurrenceFrequency(currentRule): discard
      elif frequency.len == 0: target.patchFirstValue("RRULE", "")
      elif frequency in ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]:
        target.patchFirstValue("RRULE", "FREQ=" & frequency)
      else: raise newException(DocumentEditError, "event recurrence is unsupported")
    if patch.hasKey("recurrenceRule"):
      let rule = patch{"recurrenceRule"}.getStr.toUpperAscii
      if rule.len > 512 or rule.contains({'\r', '\n', ':'}) or
          not validRecurrenceRule(rule, target.propertyValue("DTSTART")):
        raise newException(DocumentEditError, "event recurrence rule is unsafe or unsupported")
      target.patchFirstValue("RRULE", rule)
    if target.name == "VTODO":
      for (field, propertyName) in [("due", "DUE"), ("completed", "COMPLETED"),
          ("percentComplete", "PERCENT-COMPLETE"), ("priority", "PRIORITY"), (
              "status", "STATUS")]:
        if patch.hasKey(field):
          let value = if field in ["due", "completed"]: compactDateTime(patch{field}.getStr)
            else: patch{field}.getStr.toUpperAscii
          target.patchFirstText(propertyName, value)
  else:
    raise newException(DocumentEditError, "unsupported document kind")
  result = serializeComponents(roots)
  if not isValid(result): raise newException(DocumentEditError, "patched document is invalid")
