# SPDX-License-Identifier: Apache-2.0
## Bounded RFC 7095 jCard and RFC 7265 jCal structural mappings.
##
## The content-line component tree remains UniDAV's source of truth. These
## adapters preserve extension names, parameters, values and component
## nesting while applying the JSON formats' lowercase-name convention.
import std/[json, parseutils, strutils]

import component, contentline, document, editing

type JsonFormatError* = object of CatchableError

const
  MaxJsonBytes* = 16 * 1024 * 1024
  MaxJsonDepth* = 32
  MaxJsonItems* = 100_000

proc splitEscaped(value: string; separator: char): seq[string] =
  var part = ""
  var escaped = false
  for character in value:
    if escaped:
      part.add('\\')
      part.add(character)
      escaped = false
    elif character == '\\':
      escaped = true
    elif character == separator:
      result.add(part)
      part = ""
    else:
      part.add(character)
  if escaped: part.add('\\')
  result.add(part)

proc explicitValueType(line: ContentLine): string =
  for parameter in line.params:
    if parameter.name.cmpIgnoreCase("VALUE") == 0 and parameter.values.len > 0:
      return parameter.values[0].toLowerAscii

proc cardDefaultType(name: string): string =
  case name.toUpperAscii
  of "BDAY", "ANNIVERSARY": "date-and-or-time"
  of "REV": "timestamp"
  of "TEL", "IMPP", "GEO", "LOGO", "MEMBER", "RELATED", "PHOTO", "SOURCE",
      "SOUND", "UID", "URL", "KEY", "FBURL", "CALADRURI", "CALURI": "uri"
  of "LANG": "language-tag"
  of "ADR", "CATEGORIES", "CLIENTPIDMAP", "EMAIL", "FN", "GENDER", "KIND",
      "N", "NICKNAME", "NOTE", "ORG", "PRODID", "ROLE", "TITLE", "TZ",
      "VERSION", "XML": "text"
  else: "unknown"

proc calendarDefaultType(name: string): string =
  case name.toUpperAscii
  of "DTSTART", "DTEND", "DUE", "DTSTAMP", "CREATED", "LAST-MODIFIED",
      "RECURRENCE-ID", "COMPLETED": "date-time"
  of "DURATION", "TRIGGER": "duration"
  of "ATTENDEE", "ORGANIZER": "cal-address"
  of "URL", "TZURL", "ATTACH", "SOURCE": "uri"
  of "PERCENT-COMPLETE", "PRIORITY", "REPEAT", "SEQUENCE": "integer"
  of "GEO": "float"
  of "FREEBUSY": "period"
  of "RRULE", "EXRULE": "recur"
  of "TZOFFSETFROM", "TZOFFSETTO": "utc-offset"
  of "ACTION", "CALSCALE", "CATEGORIES", "CLASS", "COMMENT", "CONTACT",
      "DESCRIPTION", "LOCATION", "METHOD", "PRODID", "RELATED-TO",
      "RESOURCES", "STATUS", "SUMMARY", "TRANSP", "TZID", "TZNAME", "UID",
      "VERSION": "text"
  else: "unknown"

proc valueType(line: ContentLine; card: bool): string =
  result = explicitValueType(line)
  if result.len == 0:
    result = if card: cardDefaultType(line.name) else: calendarDefaultType(line.name)

proc parametersJson(line: ContentLine; card: bool): JsonNode =
  result = newJObject()
  if card and line.group.len > 0:
    result["group"] = %line.group.toLowerAscii
  for parameter in line.params:
    if parameter.name.cmpIgnoreCase("VALUE") == 0: continue
    let key = parameter.name.toLowerAscii
    if parameter.values.len == 1:
      result[key] = %parameter.values[0]
    else:
      result[key] = %parameter.values

proc extendedOffset(value: string): string =
  let sign = if value.len > 0 and value[0] in {'+', '-'}: 1 else: 0
  let digits = value.len - sign
  if digits notin [4, 6]: return value
  for index in sign ..< value.len:
    if value[index] notin Digits: return value
  result = value[0 ..< sign + 2] & ":" & value[sign + 2 ..< sign + 4]
  if digits == 6: result.add(":" & value[sign + 4 ..< sign + 6])

proc extendedDate(value: string): string =
  if value.len == 8 and value.allCharsInSet(Digits):
    value[0 .. 3] & "-" & value[4 .. 5] & "-" & value[6 .. 7]
  elif value.len == 6 and value.startsWith("--") and
      value[2 .. ^1].allCharsInSet(Digits):
    "--" & value[2 .. 3] & "-" & value[4 .. 5]
  else:
    value

proc extendedTime(value: string): string =
  var core = value
  var zone = ""
  if core.endsWith("Z"):
    zone = "Z"
    core.setLen(core.len - 1)
  else:
    if core.len > 1:
      for index in 1 ..< core.len:
        if core[index] in {'+', '-'}:
          zone = extendedOffset(core[index .. ^1])
          core.setLen(index)
          break
  if core.len == 6 and core.allCharsInSet(Digits):
    core = core[0 .. 1] & ":" & core[2 .. 3] & ":" & core[4 .. 5]
  elif core.len == 4 and core.allCharsInSet(Digits):
    core = core[0 .. 1] & ":" & core[2 .. 3]
  elif core.len == 5 and core[0] == '-' and
      core[1 .. ^1].allCharsInSet(Digits):
    core = "-" & core[1 .. 2] & ":" & core[3 .. 4]
  core & zone

proc extendedDateTime(value: string): string =
  let separator = value.find('T')
  if separator <= 0 or separator == value.high: return value
  extendedDate(value[0 ..< separator]) & "T" & extendedTime(
    value[separator + 1 .. ^1])

proc extendedTemporal(value, kind: string): string =
  case kind
  of "date": extendedDate(value)
  of "date-time", "timestamp": extendedDateTime(value)
  of "date-and-or-time":
    if value.len > 1 and value.startsWith("T"):
      "T" & extendedTime(value[1 .. ^1])
    elif 'T' in value: extendedDateTime(value)
    else: extendedDate(value)
  of "time": extendedTime(value)
  of "utc-offset": extendedOffset(value)
  else: value

proc compactDate(value: string): string =
  if value.len == 10 and value[4] == '-' and value[7] == '-':
    value[0 .. 3] & value[5 .. 6] & value[8 .. 9]
  elif value.len == 7 and value.startsWith("--") and value[4] == '-':
    "--" & value[2 .. 3] & value[5 .. 6]
  else:
    value

proc compactDateTime(value: string): string =
  let separator = value.find('T')
  if separator <= 0 or separator == value.high: return value
  compactDate(value[0 ..< separator]) & "T" &
    value[separator + 1 .. ^1].replace(":", "")

proc compactTemporal(value, kind: string): string =
  case kind
  of "date": compactDate(value)
  of "date-time", "timestamp": compactDateTime(value)
  of "date-and-or-time":
    if value.len > 1 and value.startsWith("T"):
      "T" & value[1 .. ^1].replace(":", "")
    elif 'T' in value: compactDateTime(value)
    else: compactDate(value)
  of "time", "utc-offset": value.replace(":", "")
  else: value

proc integerJson(value: string): JsonNode =
  var parsed: BiggestInt
  if parseBiggestInt(value, parsed) != value.len:
    raise newException(JsonFormatError, "invalid recurrence integer")
  %parsed

proc recurrenceJson(raw: string): JsonNode =
  result = newJObject()
  for field in splitEscaped(raw, ';'):
    let separator = field.find('=')
    if separator <= 0 or separator == field.high:
      raise newException(JsonFormatError, "invalid recurrence field")
    let key = field[0 ..< separator].toLowerAscii
    if result.hasKey(key):
      raise newException(JsonFormatError, "duplicate recurrence field")
    let rawValue = field[separator + 1 .. ^1]
    if key in ["count", "interval"]:
      result[key] = integerJson(rawValue)
    elif key in ["bysecond", "byminute", "byhour", "bymonthday", "byyearday",
        "byweekno", "bymonth", "bysetpos"]:
      var values = newJArray()
      for value in splitEscaped(rawValue, ','): values.add(integerJson(value))
      result[key] = values
    elif key == "until":
      result[key] = %(if 'T' in rawValue: extendedDateTime(rawValue) else:
        extendedDate(rawValue))
    elif key == "byday":
      result[key] = %splitEscaped(rawValue, ',')
    else:
      result[key] = %rawValue

proc recurrenceText(node: JsonNode): string =
  if node.kind != JObject:
    raise newException(JsonFormatError, "recurrence value must be an object")
  var fields: seq[string]
  for key, value in node:
    if key.len == 0 or key.contains({'\r', '\n', ';', '='}):
      raise newException(JsonFormatError, "invalid recurrence key")
    var rendered: seq[string]
    if value.kind == JArray:
      for item in value:
        if item.kind == JInt: rendered.add($item.getBiggestInt)
        elif item.kind == JString: rendered.add(item.getStr)
        else: raise newException(JsonFormatError, "invalid recurrence array value")
    elif value.kind == JInt:
      rendered.add($value.getBiggestInt)
    elif value.kind == JString:
      let raw = if key.cmpIgnoreCase("until") == 0:
        (if 'T' in value.getStr: compactDateTime(value.getStr) else:
          compactDate(value.getStr)) else: value.getStr
      rendered.add(raw)
    else:
      raise newException(JsonFormatError, "invalid recurrence value")
    for item in rendered:
      if item.contains({'\r', '\n', ';', ','}):
        raise newException(JsonFormatError, "unsafe recurrence value")
    fields.add(key.toUpperAscii & "=" & rendered.join(","))
  if fields.len == 0:
    raise newException(JsonFormatError, "empty recurrence object")
  fields.join(";")

proc periodJson(raw: string): JsonNode =
  let parts = splitEscaped(raw, '/')
  if parts.len != 2 or parts[0].len == 0 or parts[1].len == 0:
    raise newException(JsonFormatError, "invalid period value")
  result = newJArray()
  result.add(%extendedDateTime(parts[0]))
  result.add(%(if parts[1].len > 0 and parts[1][0] in {'P', 'p', '+', '-'}:
    parts[1] else: extendedDateTime(parts[1])))

proc primitiveJson(raw, kind: string): JsonNode =
  let value = textUnescape(raw)
  case kind
  of "boolean":
    if value.cmpIgnoreCase("true") == 0: %true
    elif value.cmpIgnoreCase("false") == 0: %false
    else: raise newException(JsonFormatError, "invalid boolean value")
  of "integer":
    var parsed: BiggestInt
    if parseBiggestInt(value, parsed) != value.len:
      raise newException(JsonFormatError, "invalid integer value")
    %parsed
  of "float":
    var parsed: float
    if parseFloat(value, parsed) != value.len:
      raise newException(JsonFormatError, "invalid float value")
    %parsed
  of "date", "date-time", "date-and-or-time", "time", "timestamp", "utc-offset":
    %extendedTemporal(value, kind)
  else: %value

proc propertyJson(line: ContentLine; card: bool): JsonNode =
  result = newJArray()
  result.add(%line.name.toLowerAscii)
  result.add(parametersJson(line, card))
  let kind = valueType(line, card)
  result.add(%kind)
  let name = line.name.toUpperAscii
  let structured = card and name in ["ADR", "N", "GENDER", "ORG"]
  let multiple = name in ["CATEGORIES", "NICKNAME", "RESOURCES", "RDATE", "EXDATE"]
  if structured:
    var values = newJArray()
    for part in splitEscaped(line.value, ';'):
      let subparts = splitEscaped(part, ',')
      if subparts.len == 1:
        values.add(primitiveJson(subparts[0], kind))
      else:
        var nested = newJArray()
        for item in subparts: nested.add(primitiveJson(item, kind))
        values.add(nested)
    result.add(values)
  elif kind == "recur":
    result.add(recurrenceJson(line.value))
  elif kind == "period":
    for part in splitEscaped(line.value, ','): result.add(periodJson(part))
  elif not card and name == "REQUEST-STATUS":
    var values = newJArray()
    for part in splitEscaped(line.value, ';'): values.add(primitiveJson(part, "text"))
    if values.len notin [2, 3]:
      raise newException(JsonFormatError, "invalid request-status value")
    result.add(values)
  elif multiple:
    for part in splitEscaped(line.value, ','):
      result.add(primitiveJson(part, kind))
  elif not card and name == "GEO":
    var values = newJArray()
    for part in splitEscaped(line.value, ';'): values.add(primitiveJson(part, kind))
    result.add(values)
  else:
    result.add(primitiveJson(line.value, kind))

proc componentJson(component: Component; card: bool): JsonNode =
  if component.isNil:
    raise newException(JsonFormatError, "component is required")
  result = newJArray()
  result.add(%component.name.toLowerAscii)
  var properties = newJArray()
  var children = newJArray()
  for entry in component.entries:
    case entry.kind
    of ekProperty: properties.add(propertyJson(entry.property, card))
    of ekComponent: children.add(componentJson(entry.component, false))
  result.add(properties)
  if not card: result.add(children)

proc jCard*(component: Component): JsonNode =
  if component.isNil or component.name.cmpIgnoreCase("VCARD") != 0:
    raise newException(JsonFormatError, "jCard requires one VCARD component")
  componentJson(component, true)

proc jCal*(component: Component): JsonNode =
  if component.isNil or component.name.cmpIgnoreCase("VCALENDAR") != 0:
    raise newException(JsonFormatError, "jCal requires one VCALENDAR component")
  componentJson(component, false)

proc jCardJson*(source: string): string =
  if not isValid(source):
    raise newException(JsonFormatError, "jCard input must be a valid vCard 4.0")
  let components = parseComponents(source)
  if components.len != 1:
    raise newException(JsonFormatError, "jCard requires exactly one component")
  $jCard(components[0])

proc jCalJson*(source: string): string =
  if not isValid(source):
    raise newException(JsonFormatError, "jCal input must be a valid iCalendar object")
  let components = parseComponents(source)
  if components.len != 1:
    raise newException(JsonFormatError, "jCal requires exactly one component")
  $jCal(components[0])

proc checkBounds(node: JsonNode; depth: int; items: var int) =
  if depth > MaxJsonDepth:
    raise newException(JsonFormatError, "JSON nesting exceeds depth limit")
  inc items
  if items > MaxJsonItems:
    raise newException(JsonFormatError, "JSON exceeds item limit")
  case node.kind
  of JArray:
    for child in node: checkBounds(child, depth + 1, items)
  of JObject:
    for _, child in node: checkBounds(child, depth + 1, items)
  else: discard

proc scalarText(node: JsonNode; kind: string): string =
  case kind
  of "boolean":
    if node.kind != JBool: raise newException(JsonFormatError, "boolean JSON value required")
    if node.getBool: "TRUE" else: "FALSE"
  of "integer":
    if node.kind != JInt: raise newException(JsonFormatError, "integer JSON value required")
    $node.getBiggestInt
  of "float":
    if node.kind notin {JInt, JFloat}:
      raise newException(JsonFormatError, "numeric JSON value required")
    if node.kind == JInt: $node.getBiggestInt else: $node.getFloat
  of "date", "date-time", "date-and-or-time", "time", "timestamp", "utc-offset":
    if node.kind != JString: raise newException(JsonFormatError, "date JSON string required")
    compactTemporal(node.getStr, kind)
  else:
    if node.kind != JString: raise newException(JsonFormatError, "JSON string value required")
    textEscape(node.getStr)

proc propertyFromJson(node: JsonNode; card: bool): ContentLine =
  if node.kind != JArray or node.len < 4 or node[0].kind != JString or
      node[1].kind != JObject or node[2].kind != JString:
    raise newException(JsonFormatError, "invalid JSON property array")
  result.name = node[0].getStr.toUpperAscii
  if result.name.len == 0 or result.name.contains({'\r', '\n', ':', ';'}):
    raise newException(JsonFormatError, "invalid JSON property name")
  let kind = node[2].getStr.toLowerAscii
  let defaultKind = if card: cardDefaultType(
      result.name) else: calendarDefaultType(result.name)
  for key, value in node[1]:
    if card and key.cmpIgnoreCase("group") == 0:
      if value.kind != JString: raise newException(JsonFormatError, "group must be a string")
      result.group = value.getStr.toUpperAscii
      continue
    var parameter = Parameter(name: key.toUpperAscii)
    if value.kind == JString:
      parameter.values = @[value.getStr]
    elif value.kind == JArray:
      for item in value:
        if item.kind != JString:
          raise newException(JsonFormatError, "parameter values must be strings")
        parameter.values.add(item.getStr)
    else:
      raise newException(JsonFormatError, "parameter must be a string or string array")
    result.params.add(parameter)
  if kind != "unknown" and kind != defaultKind:
    result.params.add(Parameter(name: "VALUE", values: @[kind.toUpperAscii]))
  let cardStructured = card and result.name in ["ADR", "N", "GENDER", "ORG"]
  if kind == "recur":
    if node.len != 4:
      raise newException(JsonFormatError, "recurrence property must have one value")
    result.value = recurrenceText(node[3])
  elif kind == "period":
    var periods: seq[string]
    for index in 3 ..< node.len:
      let period = node[index]
      if period.kind != JArray or period.len != 2:
        raise newException(JsonFormatError, "period must contain two values")
      periods.add(scalarText(period[0], "date-time") & "/" &
        (if period[1].kind == JString and period[1].getStr.len > 0 and
          period[1].getStr[0] in {'P', 'p', '+', '-'}: period[1].getStr else:
          scalarText(period[1], "date-time")))
    result.value = periods.join(",")
  elif not card and result.name == "REQUEST-STATUS":
    if node.len != 4 or node[3].kind != JArray or node[3].len notin [2, 3]:
      raise newException(JsonFormatError, "invalid request-status array")
    var parts: seq[string]
    for item in node[3]: parts.add(scalarText(item, "text"))
    result.value = parts.join(";")
  elif cardStructured:
    if node.len != 4 or node[3].kind != JArray:
      raise newException(JsonFormatError, "structured vCard value must be one array")
    var parts: seq[string]
    for item in node[3]:
      if item.kind == JArray:
        var nested: seq[string]
        for value in item: nested.add(scalarText(value, kind))
        parts.add(nested.join(","))
      else:
        parts.add(scalarText(item, kind))
    result.value = parts.join(";")
  else:
    var values: seq[string]
    for index in 3 ..< node.len: values.add(scalarText(node[index], kind))
    result.value = values.join(",")

proc componentFromJson(node: JsonNode; card: bool; depth: int): Component =
  let expectedLength = if card: 2 else: 3
  let invalidHeader = node.kind != JArray or node.len != expectedLength
  if invalidHeader:
    raise newException(JsonFormatError, "invalid jCard/jCal component")
  let invalidBody = node[0].kind != JString or node[1].kind != JArray
  if invalidBody or (not card and node[2].kind != JArray):
    raise newException(JsonFormatError, "invalid jCard/jCal component")
  if depth > MaxJsonDepth:
    raise newException(JsonFormatError, "component nesting exceeds depth limit")
  result = Component(name: node[0].getStr.toUpperAscii)
  for property in node[1]:
    result.entries.add(ComponentEntry(kind: ekProperty,
      property: propertyFromJson(property, card)))
  if not card:
    for child in node[2]:
      result.entries.add(ComponentEntry(kind: ekComponent,
        component: componentFromJson(child, false, depth + 1)))

proc parseJsonFormat(source: string; card: bool): Component =
  if source.len > MaxJsonBytes:
    raise newException(JsonFormatError, "JSON exceeds byte limit")
  var node: JsonNode
  try:
    node = parseJson(source)
  except JsonParsingError as error:
    raise newException(JsonFormatError, "invalid JSON: " & error.msg)
  var items = 0
  checkBounds(node, 1, items)
  result = componentFromJson(node, card, 1)
  let expected = if card: "VCARD" else: "VCALENDAR"
  if result.name != expected:
    raise newException(JsonFormatError, "unexpected root component")
  if not isValid(serializeComponent(result)):
    raise newException(JsonFormatError, "mapped PIM document is invalid")

proc parseJCard*(source: string): Component = parseJsonFormat(source, true)
proc parseJCal*(source: string): Component = parseJsonFormat(source, false)

proc documentFromJCard*(source: string): string = serializeComponent(parseJCard(source))
proc documentFromJCal*(source: string): string = serializeComponent(parseJCal(source))
