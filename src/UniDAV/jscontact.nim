# SPDX-License-Identifier: Apache-2.0
## Bounded JSContact bridge.
##
## This module implements the common Card fields and RFC 9555 extension
## carriers (`vCardProps`, `vCardName`, and `JSPROP`). Unknown data is never
## silently discarded. Unsupported Card members are rejected rather than
## guessed, so callers can retain the original vCard as their source of truth.
import std/[json, sequtils, sets, strutils]

import component, contentline, document, editing, projection

type JsContactError* = object of CatchableError

const MaxJsContactBytes* = 16 * 1024 * 1024
const MaxJsContactDepth = 32
const MaxJsContactItems = 100_000

proc decodedJsPropName(property: ContentLine): string

proc checkJsonBounds(node: JsonNode; depth: int; items: var int) =
  if depth > MaxJsContactDepth:
    raise newException(JsContactError, "JSContact nesting exceeds depth limit")
  inc items
  if items > MaxJsContactItems:
    raise newException(JsContactError, "JSContact exceeds item limit")
  case node.kind
  of JArray:
    for child in node: checkJsonBounds(child, depth + 1, items)
  of JObject:
    for _, child in node: checkJsonBounds(child, depth + 1, items)
  else: discard

proc parseCard(source: string): JsonNode =
  if source.len > MaxJsContactBytes:
    raise newException(JsContactError, "JSContact exceeds byte limit")
  try: result = parseJson(source)
  except JsonParsingError as error:
    raise newException(JsContactError, "invalid JSContact JSON: " & error.msg)
  var items = 0
  checkJsonBounds(result, 1, items)
  if result.kind != JObject or not result.hasKey("@type") or
      result["@type"].kind != JString or result["@type"].getStr != "Card":
    raise newException(JsContactError, "JSContact root must be a Card")
  if not result.hasKey("version") or result["version"].kind != JString:
    raise newException(JsContactError, "JSContact version is required")
  let version = result["version"].getStr
  if version notin ["1.0", "2.0"]:
    raise newException(JsContactError, "unsupported JSContact version")
  if version == "1.0" and (not result.hasKey("uid") or
      result["uid"].kind != JString or result["uid"].getStr.len == 0):
    raise newException(JsContactError, "JSContact 1.0 requires uid")

proc safeText(node: JsonNode; field: string): string =
  if node.kind != JString:
    raise newException(JsContactError, field & " must be a string")
  result = node.getStr
  if result.contains({'\r', '\n'}):
    raise newException(JsContactError, field & " contains a line break")

proc compactTimestamp(value: string): string =
  if value.len >= 19 and value[4] == '-' and value[7] == '-' and
      value[10] == 'T' and value[13] == ':' and value[16] == ':':
    result = value[0 .. 3] & value[5 .. 6] & value[8 .. 9] & "T" &
      value[11 .. 12] & value[14 .. 15] & value[17 .. 18]
    if value.len > 19 and value[19] == 'Z': result.add('Z')
  else:
    result = value

proc unknownCardProperties(card: Component): JsonNode =
  let known = toHashSet(["VERSION", "UID", "FN", "N", "KIND", "ORG", "TITLE", "ROLE",
    "EMAIL", "TEL", "NOTE", "CREATED", "LANGUAGE", "LANG", "PRONOUNS",
    "IMPP", "SOCIALPROFILE", "GRAMGENDER", "ADR", "CATEGORIES", "URL", "BDAY",
    "ANNIVERSARY", "DEATHDATE", "BIRTHPLACE", "DEATHPLACE", "PRODID", "REV",
    "NICKNAME", "MEMBER", "RELATED",
    "PHOTO", "LOGO", "SOUND", "KEY", "GEO", "TZ", "CALADRURI", "CALURI",
    "FBURL",
    "EXPERTISE", "HOBBY", "INTEREST", "ORG-DIRECTORY", "SOURCE"])
  result = newJArray()
  let reserved = toHashSet(["@type", "version", "uid", "kind", "name",
    "language", "created", "emails", "phones", "organizations", "titles",
    "notes", "speakToAs", "onlineServices", "preferredLanguages",
    "vCardProps", "addresses", "keywords", "links", "prodId", "updated",
    "anniversaries", "nicknames", "members", "relatedTo", "media",
    "cryptoKeys", "schedulingAddresses", "calendars", "personalInfo",
    "directories"])
  for entry in card.entries:
    if entry.kind != ekProperty or entry.property.name in known: continue
    if entry.property.name == "X-ABLABEL" and entry.property.group.len > 0:
      var hasTarget = false
      for candidate in card.entries:
        if candidate.kind == ekProperty and candidate.property.group ==
            entry.property.group and candidate.property.name != "X-ABLABEL":
          hasTarget = true
      if hasTarget: continue
    let decodedName = entry.property.decodedJsPropName
    if decodedName.len > 0 and decodedName notin reserved: continue
    var parameters = newJObject()
    if entry.property.group.len > 0: parameters["group"] = %entry.property.group
    for parameter in entry.property.params:
      if parameter.values.len == 1: parameters[
          parameter.name.toLowerAscii] = %parameter.values[0]
      else:
        var values = newJArray()
        for value in parameter.values: values.add(%value)
        parameters[parameter.name.toLowerAscii] = values
    result.add(%*[entry.property.name.toLowerAscii, parameters, "unknown",
      textUnescape(entry.property.value)])

proc splitVCardComponents(value: string): seq[string] =
  var part = ""
  var escaped = false
  for ch in value:
    if escaped:
      part.add('\\'); part.add(ch); escaped = false
    elif ch == '\\': escaped = true
    elif ch == ';': result.add(textUnescape(part)); part = ""
    else: part.add(ch)
  if escaped: part.add('\\')
  result.add(textUnescape(part))

proc splitVCardValues(value: string): seq[string] =
  var part = ""
  var escaped = false
  for ch in value:
    if escaped:
      part.add('\\'); part.add(ch); escaped = false
    elif ch == '\\': escaped = true
    elif ch == ',': result.add(textUnescape(part)); part = ""
    else: part.add(ch)
  if escaped: part.add('\\')
  result.add(textUnescape(part))

proc parameterValue(property: ContentLine; name: string): string =
  for parameter in property.params:
    if parameter.name.toUpperAscii == name.toUpperAscii and
        parameter.values.len > 0:
      return parameter.values[0]

proc jsonPointerEscape(value: string): string =
  value.replace("~", "~0").replace("/", "~1")

proc jsonPointerUnescape(value: string): string =
  var index = 0
  while index < value.len:
    if value[index] == '~' and index + 1 < value.len:
      case value[index + 1]
      of '0': result.add('~'); inc index
      of '1': result.add('/'); inc index
      else: result.add('~')
    else: result.add(value[index])
    inc index

proc decodedJsPropName(property: ContentLine): string =
  if property.name != "JSPROP": return ""
  let pointer = property.parameterValue("JSPTR")
  if pointer.len == 0: return ""
  var segments: seq[string]
  for segment in pointer.split('/'):
    if segment.contains("~") and not segment.contains("~0") and
        not segment.contains("~1"): return ""
    segments.add(jsonPointerUnescape(segment))
  result = segments.join("/")
  if result.len == 0 or result.contains({'\r', '\n'}): result = ""

proc parsedJsProp(property: ContentLine; name: var string;
    value: var JsonNode): bool =
  name = property.decodedJsPropName
  if name.len == 0: return false
  try: value = parseJson(textUnescape(property.value))
  except JsonParsingError: return false
  true

proc setJsonPointer(root: JsonNode; path: string; value: JsonNode): bool =
  var segments: seq[string]
  for segment in path.split('/'):
    segments.add(jsonPointerUnescape(segment))
  if segments.len == 0 or segments.anyIt(it.len == 0): return false
  var target = root
  for index, segment in segments:
    let finalSegment = index == segments.high
    if target.kind == JObject:
      if finalSegment:
        target[segment] = value
        return true
      if not target.hasKey(segment): target[segment] = newJObject()
      target = target[segment]
    elif target.kind == JArray:
      try:
        let position = parseInt(segment)
        if position < 0 or position >= target.len: return false
        target = target[position]
      except ValueError: return false
    else: return false
  false

proc addContextAndPref(target: JsonNode; property: ContentLine) =
  var contexts = newJObject()
  for parameter in property.params:
    if parameter.name.toUpperAscii == "TYPE":
      for value in parameter.values: contexts[value.toLowerAscii] = %true
    elif parameter.name.toUpperAscii == "PREF" and parameter.values.len > 0:
      try: target["pref"] = %parseInt(parameter.values[0])
      except ValueError: discard
  if contexts.len > 0: target["contexts"] = contexts

proc addUnknownVCardParams(target: JsonNode; property: ContentLine;
    excluded: openArray[string]) =
  var parameters = newJObject()
  for parameter in property.params:
    let name = parameter.name.toUpperAscii
    if name in excluded or name == "GROUP" or parameter.values.len == 0: continue
    if parameter.values.len == 1: parameters[
        parameter.name.toLowerAscii] = %parameter.values[0]
    else:
      var values = newJArray()
      for value in parameter.values: values.add(%value)
      parameters[parameter.name.toLowerAscii] = values
  if parameters.len > 0: target["vCardParams"] = parameters

proc isoTimestamp(value: string): string =
  if value.len == 16 and value[8] == 'T' and value[^1] == 'Z':
    return value[0..3] & "-" & value[4..5] & "-" & value[6..7] & "T" &
      value[9..10] & ":" & value[11..12] & ":" & value[13..14] & "Z"
  if value.len == 15 and value[8] == 'T':
    return value[0..3] & "-" & value[4..5] & "-" & value[6..7] & "T" &
      value[9..10] & ":" & value[11..12] & ":" & value[13..14]
  value

proc matchingPropertyIndex(properties: seq[ContentLine];
    property: ContentLine): int =
  for index, candidate in properties:
    if property.group.len > 0 and candidate.group == property.group:
      return index
  if property.group.len == 0 and properties.len == 1: return 0
  -1

proc jsPropertyId(property: ContentLine; prefix: string; index: int): string =
  let propId = property.parameterValue("PROP-ID")
  if propId.len > 0: propId else: prefix & $index

proc xAbLabel(card: Component; property: ContentLine): string =
  if property.group.len == 0: return ""
  for label in card.properties("X-ABLABEL"):
    if label.group == property.group: return textUnescape(label.value)

proc projectXAbLabels(card: Component; target: JsonNode) =
  let mappings = [("EMAIL", "emails", "email"), ("TEL", "phones", "phone"),
    ("URL", "links", "link"), ("ADR", "addresses", "address"),
    ("NOTE", "notes", "note"), ("IMPP", "onlineServices", "os"),
    ("SOCIALPROFILE", "onlineServices", "social")]
  for mapping in mappings:
    for index, property in card.properties(mapping[0]):
      let label = card.xAbLabel(property)
      let key = property.jsPropertyId(mapping[2], index)
      if label.len > 0 and target.hasKey(mapping[1]) and
          target[mapping[1]].hasKey(key): target[mapping[1]][key][
              "label"] = %label

proc projectStructured(card: Component; target: JsonNode) =
  target["addresses"] = newJObject()
  target["keywords"] = newJObject()
  target["links"] = newJObject()
  target["anniversaries"] = newJObject()
  for index, property in card.properties("EMAIL"):
    addUnknownVCardParams(target["emails"][property.jsPropertyId("email",
        index)], property,
      ["TYPE", "PREF"])
  for index, property in card.properties("TEL"):
    addUnknownVCardParams(target["phones"][property.jsPropertyId("phone",
        index)], property,
      ["TYPE", "PREF"])
  for index, property in card.properties("NOTE"):
    addUnknownVCardParams(target["notes"][property.jsPropertyId("note", index)],
        property,
      ["TYPE", "PREF", "CREATED", "AUTHOR-NAME"])
  let n = card.properties("N")
  if n.len > 0:
    let fields = splitVCardComponents(n[0].value)
    var components = newJArray()
    let kinds: seq[seq[string]] = @[@["surname", "surname2"], @["given"],
      @["given2"], @["title"], @["credential", "generation"]]
    for i, fieldKinds in kinds:
      if i >= fields.len: continue
      for j, value in splitVCardValues(fields[i]):
        if value.len == 0: continue
        let kind = if j < fieldKinds.len: fieldKinds[j] else: fieldKinds[^1]
        components.add(%*{"kind": kind, "value": value})
    target["name"]["components"] = components
    let script = n[0].parameterValue("SCRIPT")
    if script.len > 0: target["name"]["phoneticScript"] = %script
  for index, property in card.properties("ORG"):
    let fields = splitVCardComponents(property.value)
    let organization = target["organizations"][property.jsPropertyId("org", index)]
    if fields.len > 0: organization["name"] = %fields[0]
    var units = newJArray()
    for i in 1 ..< fields.len:
      if fields[i].len > 0: units.add(%*{"name": fields[i]})
    if units.len > 0: organization["units"] = units
    addUnknownVCardParams(organization, property, ["TYPE", "PREF", "SORT-AS"])
    for parameter in property.params:
      if parameter.name.toUpperAscii == "SORT-AS" and parameter.values.len > 0:
        var sortValues: seq[string]
        for rawValue in parameter.values:
          for sortValue in splitVCardValues(rawValue): sortValues.add(sortValue)
        if sortValues.len > 0 and sortValues[0].len > 0:
          organization["sortAs"] = %sortValues[0]
        if organization.hasKey("units") and sortValues.len > 1:
          for unitIndex, sortValue in sortValues[1 ..^ 1]:
            if unitIndex < organization["units"].len and sortValue.len > 0:
              organization["units"][unitIndex]["sortAs"] = %sortValue
  var titleIndex = 0
  for name in ["TITLE", "ROLE"]:
    for property in card.properties(name):
      var title = %*{"name": textUnescape(property.value),
        "kind": (if name == "TITLE": "title" else: "role")}
      if property.group.len > 0:
        var matchingOrg = -1
        for orgIndex, organization in card.properties("ORG"):
          if organization.group == property.group: matchingOrg = orgIndex
        if matchingOrg >= 0: title["organizationId"] = %("org" & $matchingOrg)
      addContextAndPref(title, property)
      addUnknownVCardParams(title, property, ["TYPE", "PREF"])
      let titleKey = if property.parameterValue("PROP-ID").len > 0:
          property.parameterValue("PROP-ID") else: "title" & $titleIndex
      target["titles"][titleKey] = title
      inc titleIndex
  for index, property in card.properties("ADR"):
    let fields = splitVCardComponents(property.value)
    let names = ["poBox", "extended", "street", "locality", "region",
        "postcode", "country"]
    var address = %*{}
    var components = newJArray()
    for i, name in names:
      if i < fields.len and fields[i].len > 0: components.add(%*{"kind": name,
          "value": fields[i]})
    address["components"] = components
    address.addContextAndPref(property)
    let script = property.parameterValue("SCRIPT")
    if script.len > 0: address["phoneticScript"] = %script
    let timeZone = property.parameterValue("TZ")
    if timeZone.len > 0: address["timeZone"] = %timeZone
    addUnknownVCardParams(address, property, ["TYPE", "PREF", "SCRIPT", "TZ"])
    target["addresses"]["address" & $index] = address
  let addresses = card.properties("ADR")
  for name in ["GEO", "TZ"]:
    for index, property in card.properties(name):
      let addressIndex = addresses.matchingPropertyIndex(property)
      let key = if addressIndex >= 0: "address" & $addressIndex
        elif name == "TZ" and target["addresses"].hasKey("geo" & $index):
          "geo" & $index
        elif name == "GEO" and target["addresses"].hasKey("tz" & $index):
          "tz" & $index
        else: name.toLowerAscii & $index
      if not target["addresses"].hasKey(key): target["addresses"][
          key] = newJObject()
      if name == "GEO": target["addresses"][key]["coordinates"] = %textUnescape(property.value)
      else: target["addresses"][key]["timeZone"] = %textUnescape(property.value)
      addContextAndPref(target["addresses"][key], property)
      addUnknownVCardParams(target["addresses"][key], property, ["TYPE", "PREF"])
  for index, property in card.properties("CATEGORIES"):
    for value in property.value.split(','):
      let keyword = textUnescape(value)
      if keyword.len > 0: target["keywords"][keyword] = %true
  for index, property in card.properties("URL"):
    var link = %*{"uri": textUnescape(property.value)}
    link.addContextAndPref(property)
    let mediaType = property.parameterValue("MEDIATYPE")
    if mediaType.len > 0: link["mediaType"] = %mediaType
    addUnknownVCardParams(link, property, ["TYPE", "PREF", "MEDIATYPE"])
    target["links"]["link" & $index] = link
  let kind = card.propertyValue("KIND")
  if kind.len > 0: target["kind"] = %kind
  let prodId = card.propertyValue("PRODID")
  if prodId.len > 0: target["prodId"] = %textUnescape(prodId)
  let rev = card.propertyValue("REV")
  if rev.len > 0: target["updated"] = %isoTimestamp(rev)
  var anniversaryIndex = 0
  for name in ["BDAY", "ANNIVERSARY", "DEATHDATE"]:
    for index, property in card.properties(name):
      var anniversary = %*{"date": textUnescape(property.value)}
      anniversary["kind"] = %(if name == "BDAY": "birth" elif name ==
          "DEATHDATE": "death" else: "wedding")
      addUnknownVCardParams(anniversary, property, [])
      target["anniversaries"]["anniversary" & $anniversaryIndex] = anniversary
      inc anniversaryIndex
  let bdayCount = card.properties("BDAY").len
  let weddingCount = card.properties("ANNIVERSARY").len
  for name in ["BIRTHPLACE", "DEATHPLACE"]:
    for index, property in card.properties(name):
      let offset = if name == "BIRTHPLACE": index else: bdayCount +
          weddingCount + index
      let key = "anniversary" & $offset
      if target["anniversaries"].hasKey(key):
        var place = newJObject()
        if property.parameterValue("VALUE").toLowerAscii == "uri" or
            property.value.startsWith("geo:"): place[
                "coordinates"] = %textUnescape(property.value)
        else: place["full"] = %textUnescape(property.value)
        addUnknownVCardParams(place, property, ["VALUE", "TYPE", "PREF"])
        target["anniversaries"][key]["place"] = place
  let grammaticalGender = card.propertyValue("GRAMGENDER")
  if grammaticalGender.len > 0:
    if not target.hasKey("speakToAs"): target["speakToAs"] = newJObject()
    target["speakToAs"]["grammaticalGender"] = %textUnescape(grammaticalGender)
  for index, property in card.properties("NICKNAME"):
    var nickname = %*{"name": textUnescape(property.value)}
    addContextAndPref(nickname, property)
    if not target.hasKey("nicknames"): target["nicknames"] = newJObject()
    target["nicknames"]["nickname" & $index] = nickname
  for property in card.properties("MEMBER"):
    if not target.hasKey("members"): target["members"] = newJObject()
    target["members"][textUnescape(property.value)] = %true
  for index, property in card.properties("RELATED"):
    var relation = newJObject()
    var relationTypes = newJObject()
    for parameter in property.params:
      if parameter.name.toUpperAscii == "TYPE":
        for value in parameter.values: relationTypes[value.toLowerAscii] = %true
    relation["relation"] = relationTypes
    if not target.hasKey("relatedTo"): target["relatedTo"] = newJObject()
    target["relatedTo"][textUnescape(property.value)] = relation
  for name in ["EXPERTISE", "HOBBY", "INTEREST"]:
    for index, property in card.properties(name):
      var info = %*{"kind": name.toLowerAscii, "value": textUnescape(
          property.value)}
      let level = property.parameterValue("LEVEL")
      if level.len > 0: info["level"] = %level.toLowerAscii
      let listAs = property.parameterValue("INDEX")
      if listAs.len > 0:
        try: info["listAs"] = %parseInt(listAs)
        except ValueError: discard
      addUnknownVCardParams(info, property, ["LEVEL", "INDEX"])
      if not target.hasKey("personalInfo"): target["personalInfo"] = newJObject()
      target["personalInfo"][name.toLowerAscii & $index] = info
  for name in ["ORG-DIRECTORY", "SOURCE"]:
    for index, property in card.properties(name):
      var directory = %*{"kind": (if name ==
          "SOURCE": "entry" else: "directory"),
        "uri": textUnescape(property.value)}
      addContextAndPref(directory, property)
      let listAs = property.parameterValue("INDEX")
      if listAs.len > 0:
        try: directory["listAs"] = %parseInt(listAs)
        except ValueError: discard
      let mediaType = property.parameterValue("MEDIATYPE")
      if mediaType.len > 0: directory["mediaType"] = %mediaType
      addUnknownVCardParams(directory, property,
        ["TYPE", "PREF", "INDEX", "MEDIATYPE"])
      if not target.hasKey("directories"): target["directories"] = newJObject()
      target["directories"][name.toLowerAscii & $index] = directory
  for name in ["PHOTO", "LOGO", "SOUND"]:
    for index, property in card.properties(name):
      if not target.hasKey("media"): target["media"] = newJObject()
      var media = %*{"kind": name.toLowerAscii, "uri": textUnescape(
          property.value)}
      let mediaType = property.parameterValue("MEDIATYPE")
      if mediaType.len > 0: media["mediaType"] = %mediaType
      addUnknownVCardParams(media, property, ["TYPE", "PREF", "MEDIATYPE"])
      target["media"][name.toLowerAscii & $index] = media
  for index, property in card.properties("KEY"):
    if not target.hasKey("cryptoKeys"): target["cryptoKeys"] = newJObject()
    var key = %*{"uri": textUnescape(property.value)}
    let mediaType = property.parameterValue("MEDIATYPE")
    if mediaType.len > 0: key["mediaType"] = %mediaType
    addUnknownVCardParams(key, property, ["TYPE", "PREF", "MEDIATYPE"])
    target["cryptoKeys"]["key" & $index] = key
  for name in ["CALADRURI", "CALURI", "FBURL"]:
    for index, property in card.properties(name):
      let key = if name == "CALADRURI": "schedulingAddresses" else: "calendars"
      if not target.hasKey(key): target[key] = newJObject()
      var value = %*{"uri": textUnescape(property.value)}
      if name == "CALURI": value["kind"] = %"calendar"
      elif name == "FBURL": value["kind"] = %"freeBusy"
      let mediaType = property.parameterValue("MEDIATYPE")
      if mediaType.len > 0: value["mediaType"] = %mediaType
      addContextAndPref(value, property)
      addUnknownVCardParams(value, property, ["TYPE", "PREF", "MEDIATYPE"])
      target[key][name.toLowerAscii & $index] = value
  for key in ["addresses", "keywords", "links", "anniversaries"]:
    if target[key].len == 0: target.delete(key)
  projectXAbLabels(card, target)

proc jsContactFromVCard*(source: string; version = "2.0"): string =
  if version notin ["1.0", "2.0"]:
    raise newException(JsContactError, "unsupported JSContact version")
  if not isValid(source): raise newException(JsContactError, "invalid vCard")
  let roots = parseComponents(source)
  if roots.len != 1 or roots[0].name != "VCARD":
    raise newException(JsContactError, "one vCard is required")
  var card = parseJson(projectionJson(source))
  card["version"] = %version
  card["kind"] = %"individual"
  card["name"].delete("fullName")
  if version == "1.0" and card["uid"].getStr.len == 0:
    raise newException(JsContactError, "vCard without UID cannot become JSContact 1.0")
  if card["pronouns"].len > 0:
    var speakToAs = newJObject()
    for key, value in card["pronouns"]: speakToAs["pronouns" & "/" & key] = value
    card.delete("pronouns")
    card["speakToAs"] = speakToAs
  let reserved = toHashSet(["@type", "version", "uid", "kind", "name",
    "language", "created", "emails", "phones", "organizations", "titles",
    "notes", "speakToAs", "onlineServices", "preferredLanguages",
    "vCardProps", "addresses", "keywords", "links", "prodId", "updated",
    "anniversaries", "nicknames", "members", "relatedTo", "media",
    "cryptoKeys", "schedulingAddresses", "calendars"])
  for entry in roots[0].entries:
    if entry.kind != ekProperty: continue
    var name = ""
    var value: JsonNode
    let pointer = entry.property.parameterValue("JSPTR")
    if entry.property.parsedJsProp(name, value):
      if pointer.contains('/') or name notin reserved:
        if pointer.contains('/'):
          discard setJsonPointer(card, pointer, value)
        else:
          card[name] = value
  projectStructured(roots[0], card)
  let extensions = unknownCardProperties(roots[0])
  if extensions.len > 0: card["vCardProps"] = extensions
  result = $card

proc addText(card: Component; name, value: string) =
  if value.len > 0:
    card.entries.add(ComponentEntry(kind: ekProperty,
      property: ContentLine(name: name, value: textEscape(value))))

proc addWithParameters(card: Component; name, value: string; source: JsonNode;
    escapeValue = true) =
  if value.len == 0: return
  var line = ContentLine(name: name, value: if escapeValue: textEscape(
      value) else: value)
  if source.kind == JObject:
    if source.hasKey("group"):
      line.group = safeText(source["group"], "vCard group")
    var typeValues: seq[string]
    if source.hasKey("contexts"):
      for context, enabled in source["contexts"]:
        if enabled.kind == JBool and enabled.getBool:
          if context notin typeValues: typeValues.add(context)
    if name == "TEL" and source.hasKey("features"):
      if source["features"].kind != JObject:
        raise newException(JsContactError, "phone.features must be an object")
      var features: seq[string]
      for feature, enabled in source["features"]:
        if enabled.kind == JBool and enabled.getBool and feature notin typeValues:
          features.add(feature); typeValues.add(feature)
    if typeValues.len > 0: line.params.add(Parameter(name: "TYPE",
        values: typeValues))
    if source.hasKey("pref"):
      if source["pref"].kind != JInt: raise newException(JsContactError,
          "pref must be an integer")
      line.params.add(Parameter(name: "PREF", values: @[$source[
          "pref"].getInt]))
    if source.hasKey("vCardParams"):
      if source["vCardParams"].kind != JObject:
        raise newException(JsContactError, "vCardParams must be an object")
      for key, value in source["vCardParams"]:
        if key.toLowerAscii in ["group", "type", "pref"]: continue
        if value.kind == JString:
          line.params.add(Parameter(name: key.toUpperAscii, values: @[value.getStr]))
        elif value.kind == JArray:
          var values: seq[string]
          for item in value: values.add(safeText(item, "vCard parameter"))
          line.params.add(Parameter(name: key.toUpperAscii, values: values))
        else: raise newException(JsContactError, "vCard parameter is not textual")
  if source.kind == JObject and source.hasKey("label"):
    let label = safeText(source["label"], "label")
    if label.len > 0:
      if line.group.len == 0: line.group = "item" & $card.entries.len
      card.entries.add(ComponentEntry(kind: ekProperty, property: line))
      card.entries.add(ComponentEntry(kind: ekProperty,
        property: ContentLine(name: "X-ABLABEL", group: line.group,
          value: textEscape(label))))
      return
  card.entries.add(ComponentEntry(kind: ekProperty, property: line))

proc addCollection(card: Component; node: JsonNode; propertyName,
    fieldName: string) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError,
      propertyName & " must be an object")
  for key, item in node:
    if item.kind != JObject or not item.hasKey(fieldName):
      raise newException(JsContactError, propertyName & "/" & key & " is malformed")
    var source = newJObject()
    for itemKey, itemValue in item: source[itemKey] = itemValue
    let prefix = case propertyName
      of "EMAIL": "email"
      of "TEL": "phone"
      of "NOTE": "note"
      else: ""
    if prefix.len > 0 and not key.startsWith(prefix):
      if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
      if not source["vCardParams"].hasKey("prop-id"):
        source["vCardParams"]["prop-id"] = %key
    addWithParameters(card, propertyName, safeText(item[fieldName], fieldName), source)

proc addTitles(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError,
      "titles must be an object")
  for itemId, item in node:
    if item.kind != JObject or not item.hasKey("name"):
      raise newException(JsContactError, "title is malformed")
    let kind = if item.hasKey("kind"): safeText(item["kind"],
        "title.kind") else: "title"
    let propertyName = if kind == "role": "ROLE" else: "TITLE"
    var source = newJObject()
    for key, value in item: source[key] = value
    if item.hasKey("organizationId"):
      let organizationId = safeText(item["organizationId"], "title.organizationId")
      if organizationId.startsWith("org") and organizationId.len > 3:
        source["group"] = %organizationId
    if not itemId.startsWith("title"):
      if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
      if not source["vCardParams"].hasKey("prop-id"):
        source["vCardParams"]["prop-id"] = %itemId
    addWithParameters(card, propertyName, safeText(item["name"],
        "title.name"), source)

proc addStructuredName(card: Component; node: JsonNode) =
  if node.kind != JObject or not node.hasKey("components"): return
  if node["components"].kind != JArray: raise newException(JsContactError, "name.components must be an array")
  var fields = newSeq[seq[string]](5)
  for index in 0 ..< fields.len: fields[index] = @[]
  for item in node["components"]:
    if item.kind != JObject or not item.hasKey("kind") or not item.hasKey(
        "value"): continue
    let kind = safeText(item["kind"], "name component kind")
    let value = safeText(item["value"], "name component")
    let index = if kind in ["surname", "surname2"]: 0
      elif kind == "given": 1
      elif kind == "given2": 2
      elif kind == "title": 3
      elif kind in ["credential", "generation"]: 4 else: -1
    if index >= 0: fields[index].add(value)
  var encoded: seq[string]
  for values in fields:
    var encodedValues: seq[string]
    for value in values: encodedValues.add(textEscape(value))
    encoded.add(encodedValues.join(","))
  var source = newJObject()
  if node.hasKey("phoneticScript"):
    source["vCardParams"] = %*{"script": safeText(node["phoneticScript"],
      "name.phoneticScript")}
  addWithParameters(card, "N", encoded.join(";"), source,
      escapeValue = false)

proc addOrganizations(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject or not node.hasKey("organizations") or
      node["organizations"].kind != JObject: raise newException(JsContactError,
      "organizations must be an object")
  var linkedIds = initHashSet[string]()
  if node.hasKey("titles") and node["titles"].kind == JObject:
    for _, title in node["titles"]:
      if title.kind == JObject and title.hasKey("organizationId") and
          title["organizationId"].kind == JString:
        linkedIds.incl(title["organizationId"].getStr)
  for organizationId, organization in node["organizations"]:
    if organization.kind != JObject or not organization.hasKey("name"):
      raise newException(JsContactError, "organization is malformed")
    var fields = @[textEscape(safeText(organization["name"],
        "organization.name"))]
    if organization.hasKey("units"):
      if organization["units"].kind != JArray: raise newException(
          JsContactError,
          "organization.units must be an array")
      for unit in organization["units"]:
        if unit.kind == JObject and unit.hasKey("name"):
          fields.add(textEscape(safeText(unit["name"],
              "organization unit.name")))
    var source = newJObject()
    for key, value in organization: source[key] = value
    if organizationId in linkedIds and organizationId.len > 0 and
        organizationId.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}):
      source["group"] = %organizationId
    if not organizationId.startsWith("org"):
      if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
      if not source["vCardParams"].hasKey("prop-id"):
        source["vCardParams"]["prop-id"] = %organizationId
    var sortValues: seq[string]
    if organization.hasKey("sortAs"):
      sortValues.add(safeText(organization["sortAs"], "organization.sortAs"))
    if organization.hasKey("units"):
      for unit in organization["units"]:
        if unit.kind == JObject and unit.hasKey("sortAs"):
          sortValues.add(safeText(unit["sortAs"], "organization unit.sortAs"))
        else: sortValues.add("")
    if sortValues.len > 0:
      source["vCardParams"] = newJObject()
      source["vCardParams"]["sort-as"] = %sortValues
    addWithParameters(card, "ORG", fields.join(";"), source,
        escapeValue = false)

proc addAddresses(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, "addresses must be an object")
  var emittedGeo = false
  for _, address in node:
    if address.kind != JObject: continue
    var fields = newSeq[string](7)
    if address.hasKey("components") and address["components"].kind == JArray:
      for item in address["components"]:
        if item.kind != JObject or not item.hasKey("kind") or not item.hasKey(
            "value"): continue
        let index = ["poBox", "extended", "street", "locality", "region",
            "postcode", "country"].find(safeText(item["kind"],
            "address component kind"))
        if index >= 0: fields[index] = safeText(item["value"], "address component")
    var encoded: seq[string]
    for value in fields: encoded.add(textEscape(value))
    var source = newJObject()
    for key, value in address: source[key] = value
    if address.hasKey("phoneticScript"):
      if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
      source["vCardParams"]["script"] = %safeText(address["phoneticScript"],
        "address.phoneticScript")
    if address.hasKey("timeZone"):
      if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
      source["vCardParams"]["tz"] = %safeText(address["timeZone"],
        "address.timeZone")
    addWithParameters(card, "ADR", encoded.join(";"), source,
        escapeValue = false)
    if address.hasKey("coordinates") and not emittedGeo:
      addWithParameters(card, "GEO", safeText(address["coordinates"],
          "address.coordinates"), address, escapeValue = false)
      emittedGeo = true

proc addKeywords(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, "keywords must be an object")
  var values: seq[string]
  for key, enabled in node:
    if enabled.kind == JBool and enabled.getBool: values.add(textEscape(key))
  if values.len > 0:
    card.entries.add(ComponentEntry(kind: ekProperty,
      property: ContentLine(name: "CATEGORIES", value: values.join(","))))

proc addLinks(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, "links must be an object")
  for _, link in node:
    if link.kind == JObject and link.hasKey("uri"):
      var source = newJObject()
      for key, value in link: source[key] = value
      if link.hasKey("mediaType"):
        if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
        source["vCardParams"]["mediatype"] = %safeText(link["mediaType"],
          "link.mediaType")
      addWithParameters(card, "URL", safeText(link["uri"], "link.uri"), source)

proc addNicknames(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, "nicknames must be an object")
  for _, nickname in node:
    if nickname.kind == JObject and nickname.hasKey("name"):
      addWithParameters(card, "NICKNAME", safeText(nickname["name"],
          "nickname.name"), nickname)

proc addPreferredLanguages(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError,
      "preferredLanguages must be an object")
  for _, language in node:
    if language.kind == JObject and language.hasKey("language"):
      addWithParameters(card, "LANG", safeText(language["language"],
          "preferred language"), language)

proc addMembers(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, "members must be an object")
  for member, enabled in node:
    if enabled.kind == JBool and enabled.getBool: addText(card, "MEMBER", member)

proc addRelated(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, "relatedTo must be an object")
  for related, value in node:
    var source = if value.kind == JObject: value else: newJObject()
    if source.hasKey("relation") and source["relation"].kind == JObject:
      var line = ContentLine(name: "RELATED", value: textEscape(related))
      var types: seq[string]
      for kind, enabled in source["relation"]:
        if enabled.kind == JBool and enabled.getBool: types.add(kind)
      if types.len > 0: line.params.add(Parameter(name: "TYPE", values: types))
      card.entries.add(ComponentEntry(kind: ekProperty, property: line))
    else: addText(card, "RELATED", related)

proc addPersonalInfo(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError,
      "personalInfo must be an object")
  for _, info in node:
    if info.kind != JObject or not info.hasKey("kind") or not info.hasKey("value"):
      raise newException(JsContactError, "personalInfo entry is malformed")
    let kind = safeText(info["kind"], "personalInfo.kind")
    let propertyName = case kind
      of "expertise": "EXPERTISE"
      of "hobby": "HOBBY"
      of "interest": "INTEREST"
      else: raise newException(JsContactError, "unsupported personalInfo.kind")
    var line = ContentLine(name: propertyName,
      value: textEscape(safeText(info["value"], "personalInfo.value")))
    if info.hasKey("level"):
      line.params.add(Parameter(name: "LEVEL", values: @[
        safeText(info["level"], "personalInfo.level")]))
    if info.hasKey("listAs"):
      if info["listAs"].kind != JInt: raise newException(JsContactError,
          "personalInfo.listAs must be an integer")
      line.params.add(Parameter(name: "INDEX", values: @[$info[
          "listAs"].getInt]))
    card.entries.add(ComponentEntry(kind: ekProperty, property: line))

proc addMedia(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, "media must be an object")
  for _, media in node:
    if media.kind != JObject or not media.hasKey("uri"): continue
    let kind = if media.hasKey("kind"): safeText(media["kind"],
        "media.kind") else: "photo"
    let property = if kind in ["photo", "logo",
        "sound"]: kind.toUpperAscii else: "PHOTO"
    var source = newJObject()
    for key, value in media: source[key] = value
    if media.hasKey("mediaType"):
      if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
      source["vCardParams"]["mediatype"] = %safeText(media["mediaType"],
        "media.mediaType")
    addWithParameters(card, property, safeText(media["uri"], "media.uri"), source)

proc addCryptoKeys(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, "cryptoKeys must be an object")
  for _, key in node:
    if key.kind == JObject and key.hasKey("uri"):
      var source = newJObject()
      for itemKey, itemValue in key: source[itemKey] = itemValue
      if key.hasKey("mediaType"):
        if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
        source["vCardParams"]["mediatype"] = %safeText(key["mediaType"],
          "crypto key.mediaType")
      addWithParameters(card, "KEY", safeText(key["uri"], "crypto key.uri"), source)

proc addScheduling(card: Component; node: JsonNode; propertyName: string) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError, propertyName & " must be an object")
  for _, value in node:
    if value.kind == JObject and value.hasKey("uri"):
      addWithParameters(card, propertyName, safeText(value["uri"],
          propertyName & ".uri"), value)

proc addCalendars(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError,
      "calendars must be an object")
  for _, value in node:
    if value.kind != JObject or not value.hasKey("uri"): continue
    let kind = if value.hasKey("kind"): safeText(value["kind"],
        "calendar.kind") else: "calendar"
    let propertyName = if kind == "freeBusy": "FBURL" else: "CALURI"
    var source = newJObject()
    for key, item in value: source[key] = item
    if value.hasKey("mediaType"):
      if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
      source["vCardParams"]["mediatype"] = %safeText(value["mediaType"],
          "calendar.mediaType")
    addWithParameters(card, propertyName, safeText(value["uri"],
        "calendar.uri"), source)

proc addDirectories(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JObject: raise newException(JsContactError,
      "directories must be an object")
  for _, value in node:
    if value.kind != JObject or not value.hasKey("uri"): continue
    let kind = if value.hasKey("kind"): safeText(value["kind"],
        "directory.kind") else: "directory"
    if kind notin ["directory", "entry"]:
      raise newException(JsContactError, "unsupported directory.kind")
    var line = ContentLine(name: if kind ==
      "entry": "SOURCE" else: "ORG-DIRECTORY",
      value: textEscape(safeText(value["uri"], "directory.uri")))
    if value.hasKey("listAs"):
      if value["listAs"].kind != JInt: raise newException(JsContactError,
          "directory.listAs must be an integer")
      line.params.add(Parameter(name: "INDEX", values: @[$value[
          "listAs"].getInt]))
    if value.hasKey("pref"):
      if value["pref"].kind != JInt: raise newException(JsContactError,
          "directory.pref must be an integer")
      line.params.add(Parameter(name: "PREF", values: @[$value["pref"].getInt]))
    if value.hasKey("mediaType"):
      line.params.add(Parameter(name: "MEDIATYPE", values: @[
        safeText(value["mediaType"], "directory.mediaType")]))
    if value.hasKey("contexts") and value["contexts"].kind == JObject:
      var contexts: seq[string]
      for context, enabled in value["contexts"]:
        if enabled.kind == JBool and enabled.getBool: contexts.add(context)
      if contexts.len > 0: line.params.add(Parameter(name: "TYPE",
          values: contexts))
    card.entries.add(ComponentEntry(kind: ekProperty, property: line))

proc addVCardProps(card: Component; node: JsonNode) =
  if node.kind == JNull: return
  if node.kind != JArray: raise newException(JsContactError, "vCardProps must be an array")
  var index = 0
  for item in node:
    if item.kind != JArray or item.len < 4 or item[0].kind != JString or
        item[1].kind != JObject or item[3].kind != JString:
      raise newException(JsContactError, "vCardProps[" & $index & "] is malformed")
    let name = item[0].getStr
    if name.len == 0 or name.contains({'\r', '\n', ':', ';'}):
      raise newException(JsContactError, "unsafe vCard property name")
    var line = ContentLine(name: name.toUpperAscii, value: textEscape(item[3].getStr))
    let parameters = item[1]
    if parameters.kind != JObject:
      raise newException(JsContactError, "vCard property parameters must be an object")
    for key, value in parameters:
      if key == "group":
        line.group = safeText(value, "vCard group")
      elif value.kind == JString:
        line.params.add(Parameter(name: key.toUpperAscii, values: @[value.getStr]))
      elif value.kind == JArray:
        var values: seq[string]
        for member in value: values.add(safeText(member, "vCard parameter"))
        line.params.add(Parameter(name: key.toUpperAscii, values: values))
      else: raise newException(JsContactError, "vCard parameter is not textual")
    card.entries.add(ComponentEntry(kind: ekProperty, property: line))
    inc index

proc addJsProp(card: Component; name: string; value: JsonNode) =
  if name.len == 0 or name.contains({'\r', '\n', '"'}):
    raise newException(JsContactError, "unsafe JSContact extension property")
  var line = ContentLine(name: "JSPROP", value: textEscape($value))
  line.params.add(Parameter(name: "JSPTR", values: @[jsonPointerEscape(name)]))
  card.entries.add(ComponentEntry(kind: ekProperty, property: line))

proc addNestedJsProp(card: Component; segments: openArray[string];
    value: JsonNode) =
  if segments.len == 0 or value.kind == JNull:
    raise newException(JsContactError, "unsafe nested JSContact extension property")
  var line = ContentLine(name: "JSPROP", value: textEscape($value))
  var encoded: seq[string]
  for segment in segments:
    if segment.contains({'\r', '\n', '"'}):
      raise newException(JsContactError, "unsafe nested JSContact extension property")
    encoded.add(jsonPointerEscape(segment))
  line.params.add(Parameter(name: "JSPTR", values: @[encoded.join("/")]))
  card.entries.add(ComponentEntry(kind: ekProperty, property: line))

proc addNestedCollectionProps(card: Component; node: JsonNode; root: string;
    known: HashSet[string]) =
  if node.kind != JObject: return
  for itemKey, item in node:
    if item.kind != JObject: continue
    for key, value in item:
      if key notin known: addNestedJsProp(card, @[root, itemKey, key], value)

proc vCardFromJsContact*(source: string): string =
  let card = parseCard(source)
  result = ""
  var target = Component(name: "VCARD")
  addText(target, "VERSION", "4.0")
  if card.hasKey("uid") and card["uid"].kind != JNull and card[
      "uid"].getStr.len > 0:
    addText(target, "UID", safeText(card["uid"], "uid"))
  let name = if card.hasKey("name"): card["name"] else: newJObject()
  addStructuredName(target, name)
  var full = ""
  if name.kind == JObject and name.hasKey("full"): full = safeText(name["full"], "name.full")
  if full.len == 0 and name.kind == JObject and name.hasKey("components"):
    if name["components"].kind != JArray: raise newException(JsContactError,
        "name.components must be an array")
    var parts: seq[string]
    for component in name["components"]:
      if component.kind == JObject and component.hasKey("value"):
        parts.add(safeText(component["value"], "name component"))
    full = parts.join(" ")
  target.entries.add(ComponentEntry(kind: ekProperty,
    property: ContentLine(name: "FN", value: textEscape(full))))
  if card.hasKey("language"): addText(target, "LANGUAGE", safeText(card[
      "language"], "language"))
  if card.hasKey("created"): addText(target, "CREATED", safeText(card[
      "created"], "created").replace("-", "").replace(":", ""))
  if card.hasKey("emails"): addCollection(target, card["emails"], "EMAIL", "address")
  if card.hasKey("phones"): addCollection(target, card["phones"], "TEL", "number")
  if card.hasKey("organizations"): addOrganizations(target, card)
  if card.hasKey("titles"): addTitles(target, card["titles"])
  if card.hasKey("notes"): addCollection(target, card["notes"], "NOTE", "note")
  if card.hasKey("addresses"): addAddresses(target, card["addresses"])
  if card.hasKey("keywords"): addKeywords(target, card["keywords"])
  if card.hasKey("links"): addLinks(target, card["links"])
  if card.hasKey("nicknames"): addNicknames(target, card["nicknames"])
  if card.hasKey("members"): addMembers(target, card["members"])
  if card.hasKey("relatedTo"): addRelated(target, card["relatedTo"])
  if card.hasKey("personalInfo"): addPersonalInfo(target, card["personalInfo"])
  if card.hasKey("media"): addMedia(target, card["media"])
  if card.hasKey("cryptoKeys"): addCryptoKeys(target, card["cryptoKeys"])
  if card.hasKey("schedulingAddresses"):
    addScheduling(target, card["schedulingAddresses"], "CALADRURI")
  if card.hasKey("calendars"): addCalendars(target, card["calendars"])
  if card.hasKey("directories"): addDirectories(target, card["directories"])
  if card.hasKey("phones"):
    addNestedCollectionProps(target, card["phones"], "phones",
      toHashSet(["number", "contexts", "pref", "features", "vCardParams"]))
  if card.hasKey("kind"): addText(target, "KIND", safeText(card["kind"], "kind"))
  if card.hasKey("prodId"): addText(target, "PRODID", safeText(card["prodId"], "prodId"))
  if card.hasKey("updated"):
    addText(target, "REV", compactTimestamp(safeText(card["updated"], "updated")))
  if card.hasKey("preferredLanguages"):
    addPreferredLanguages(target, card["preferredLanguages"])
  if card.hasKey("anniversaries") and card["anniversaries"].kind == JObject:
    for _, anniversary in card["anniversaries"]:
      if anniversary.kind != JObject or not anniversary.hasKey("date"): continue
      let date = safeText(anniversary["date"], "anniversary.date")
      let anniversaryKind = if anniversary.hasKey("kind"): safeText(anniversary[
          "kind"], "anniversary.kind") else: "anniversary"
      let dateProperty = if anniversaryKind == "birth": "BDAY"
        elif anniversaryKind == "death": "DEATHDATE" else: "ANNIVERSARY"
      addWithParameters(target, dateProperty, date, anniversary)
      if anniversary.hasKey("place") and anniversary["place"].kind == JObject:
        let place = anniversary["place"]
        let placeValue = if place.hasKey("coordinates"): safeText(place[
            "coordinates"], "anniversary.place.coordinates")
          elif place.hasKey("full"): safeText(place["full"],
              "anniversary.place.full") else: ""
        if placeValue.len > 0:
          let placeProperty = if anniversaryKind == "birth": "BIRTHPLACE"
            elif anniversaryKind == "death": "DEATHPLACE" else: ""
          if placeProperty.len > 0:
            var placeSource = newJObject()
            for key, value in place: placeSource[key] = value
            if not placeSource.hasKey("vCardParams"):
              placeSource["vCardParams"] = newJObject()
            placeSource["vCardParams"]["value"] = %(if place.hasKey("coordinates"):
              "uri" else: "text")
            addWithParameters(target, placeProperty, placeValue, placeSource,
              escapeValue = not place.hasKey("coordinates"))
  if card.hasKey("speakToAs") and card["speakToAs"].kind == JObject:
    if card["speakToAs"].hasKey("grammaticalGender"):
      addText(target, "GRAMGENDER", safeText(card["speakToAs"][
          "grammaticalGender"], "grammaticalGender"))
    let pronouns = if card["speakToAs"].hasKey("pronouns"):
        card["speakToAs"]["pronouns"] else: newJObject()
    for _, pronoun in pronouns:
      if pronoun.kind == JObject and pronoun.hasKey("pronouns"):
        addWithParameters(target, "PRONOUNS", safeText(pronoun["pronouns"],
            "pronouns"), pronoun)
  if card.hasKey("onlineServices") and card["onlineServices"].kind == JObject:
    for _, service in card["onlineServices"]:
      if service.kind != JObject: raise newException(JsContactError,
          "online service must be an object")
      let property = if service.hasKey("vCardName"): service[
          "vCardName"].getStr.toUpperAscii else: "IMPP"
      let name = if property in ["IMPP", "SOCIALPROFILE"]: property else: "IMPP"
      let value = if service.hasKey("uri"): safeText(service["uri"], "service.uri")
        elif service.hasKey("user"): safeText(service["user"],
            "service.user") else: ""
      var source = newJObject()
      for key, item in service: source[key] = item
      if service.hasKey("service"):
        if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
        source["vCardParams"]["service-type"] = %safeText(service["service"],
          "service.service")
      if service.hasKey("user"):
        if not source.hasKey("vCardParams"): source["vCardParams"] = newJObject()
        source["vCardParams"]["username"] = %safeText(service["user"],
          "service.user")
      addWithParameters(target, name, value, source)
  if card.hasKey("vCardProps"):
    addVCardProps(target, card["vCardProps"])
  let known = toHashSet(["@type", "version", "uid", "kind", "name", "language",
    "created", "emails", "phones", "organizations", "titles", "notes",
    "speakToAs", "onlineServices", "preferredLanguages", "vCardProps",
    "addresses", "keywords",
    "links", "prodId", "updated", "anniversaries", "nicknames", "members",
    "relatedTo", "media", "cryptoKeys", "schedulingAddresses", "calendars",
    "personalInfo", "directories"])
  for key, value in card:
    if key notin known: addJsProp(target, key, value)
  let rendered = serializeComponent(target)
  if not isValid(rendered): raise newException(JsContactError, "converted vCard is invalid")
  result = rendered

proc validateJsContact*(source: string): bool =
  discard parseCard(source)
  true
