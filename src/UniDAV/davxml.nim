# SPDX-License-Identifier: Apache-2.0
import std/[parseutils, streams, strutils, times, xmlparser, xmltree]

const
  DavNamespace* = "DAV:"
  CalDavNamespace* = "urn:ietf:params:xml:ns:caldav"
  CardDavNamespace* = "urn:ietf:params:xml:ns:carddav"
  MaxMultigetHrefs* = 1000

type
  DavXmlError* = object of CatchableError
  DavProperty* = object
    namespace*: string
    name*: string
    value*: string
    childNames*: seq[string]
    childValues*: seq[string]
  DavResponse* = object
    href*: string
    status*: int
    properties*: seq[DavProperty]
  MultiStatus* = object
    responses*: seq[DavResponse]
    syncToken*: string

proc xmlEscape*(value: string): string =
  value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    .replace("\"", "&quot;").replace("'", "&apos;")

proc validateReportKind(kind: string) =
  if kind.cmpIgnoreCase("calendar") != 0 and
      kind.cmpIgnoreCase("addressbook") != 0:
    raise newException(DavXmlError, "DAV report kind must be calendar or addressbook")

proc validateCalendarComponent(component: string) =
  if component.len == 0: return
  if component.toUpperAscii notin ["VEVENT", "VTODO", "VJOURNAL"]:
    raise newException(DavXmlError,
      "CalDAV component filter must be VEVENT, VTODO, or VJOURNAL")

proc validateVCardProperty(property: string) =
  if property.len == 0: return
  for character in property:
    if not (character.isAlphaNumeric or character == '-'):
      raise newException(DavXmlError,
        "CardDAV property filter contains an invalid name")

proc statusCode(value: string): int =
  for token in value.splitWhitespace:
    if token.len == 3 and token[0] in {'1'..'5'}:
      var parsed = 0
      if parseInt(token, parsed) == 3: return parsed

proc localName(node: XmlNode): string =
  let tag = node.tag
  let colon = tag.find(':')
  if colon >= 0: tag[colon + 1 .. ^1] else: tag

proc nodeText(node: XmlNode): string =
  for child in node:
    case child.kind
    of xnText, xnVerbatimText, xnCData: result.add(child.text)
    else: result.add(nodeText(child))

proc descendants(node: XmlNode; name: string): seq[XmlNode] =
  if node.kind == xnElement and localName(node).cmpIgnoreCase(name) == 0:
    result.add(node)
  for child in node:
    if child.kind == xnElement:
      result.add(descendants(child, name))

proc directChild(node: XmlNode; name: string): XmlNode =
  for child in node:
    if child.kind == xnElement and localName(child).cmpIgnoreCase(name) == 0:
      return child

proc parseMultiStatus*(xml: string; maxBytes = 8 * 1024 * 1024): MultiStatus =
  if xml.len > maxBytes:
    raise newException(DavXmlError, "DAV XML exceeds byte limit")
  var root: XmlNode
  try:
    root = parseXml(newStringStream(xml))
  except CatchableError as error:
    raise newException(DavXmlError, "invalid DAV XML: " & error.msg)
  if root.isNil or localName(root).cmpIgnoreCase("multistatus") != 0:
    raise newException(DavXmlError, "expected DAV:multistatus root")
  let tokens = descendants(root, "sync-token")
  if tokens.len > 0: result.syncToken = nodeText(tokens[0]).strip
  for responseNode in descendants(root, "response"):
    var response: DavResponse
    let hrefNode = directChild(responseNode, "href")
    if hrefNode.isNil: continue
    response.href = nodeText(hrefNode).strip
    let responseStatus = directChild(responseNode, "status")
    if not responseStatus.isNil: response.status = statusCode(nodeText(responseStatus))
    for propstat in responseNode:
      if propstat.kind != xnElement or localName(propstat).cmpIgnoreCase(
          "propstat") != 0: continue
      let statusNode = directChild(propstat, "status")
      let code = if statusNode.isNil: 0 else: statusCode(nodeText(statusNode))
      if response.status == 0: response.status = code
      let propNode = directChild(propstat, "prop")
      if propNode.isNil: continue
      for propertyNode in propNode:
        if propertyNode.kind == xnElement:
          var item = DavProperty(name: localName(propertyNode),
            value: nodeText(propertyNode), namespace: propertyNode.tag)
          for child in propertyNode:
            if child.kind == xnElement:
              item.childNames.add(localName(child))
              item.childValues.add(nodeText(child).strip)
          response.properties.add(item)
    result.responses.add(response)

proc property*(response: DavResponse; name: string): string =
  for item in response.properties:
    if item.name.cmpIgnoreCase(name) == 0: return item.value

proc hasPropertyChild*(response: DavResponse; propertyName,
    childName: string): bool =
  for item in response.properties:
    if item.name.cmpIgnoreCase(propertyName) != 0: continue
    for name in item.childNames:
      if name.cmpIgnoreCase(childName) == 0: return true

const
  NameStartChars = {'A'..'Z', 'a'..'z', '_'}
    ## What an XML name may begin with. A digit, a hyphen or a period there is
    ## not a name, and a server answering the malformed element it produces is
    ## answering about nothing.
  NameChars = NameStartChars + {'0'..'9', '-', '.'}
    ## What may follow. Deliberately narrower than the standard allows: every
    ## property this library asks for is spelled from these, and a wider set
    ## only widens what a caller can inject.

proc propfindBody*(properties: openArray[(string, string)]): string =
  result = "<?xml version=\"1.0\" encoding=\"utf-8\"?>" &
    "<D:propfind xmlns:D=\"DAV:\" xmlns:C=\"" & CalDavNamespace &
    "\" xmlns:A=\"" & CardDavNamespace & "\"><D:prop>"
  for (namespace, name) in properties:
    # Three namespaces are declared above, and an unknown one used to fall
    # through to `A` -- so a caller asking for a property in a namespace this
    # body cannot declare got a CardDAV element instead, and a server answered
    # about something else entirely.
    let prefix =
      if namespace == DavNamespace: "D"
      elif namespace == CalDavNamespace: "C"
      elif namespace == CardDavNamespace: "A"
      else:
        raise newException(DavXmlError,
          "propfind namespace is not declared by this body: " & namespace)
    # The name goes into a tag, where escaping cannot save it: a name carrying
    # `<`, a quote or a space is not a name, it is markup.
    if name.len == 0 or name[0] notin NameStartChars or
        not name.allCharsInSet(NameChars):
      raise newException(DavXmlError, "propfind property name is not a name: " & name)
    result.add("<" & prefix & ":" & name & "/>")
  result.add("</D:prop></D:propfind>")

proc syncCollectionBody*(token = ""): string =
  "<?xml version=\"1.0\" encoding=\"utf-8\"?>" &
    "<D:sync-collection xmlns:D=\"DAV:\"><D:sync-token>" & xmlEscape(token) &
    "</D:sync-token><D:sync-level>1</D:sync-level><D:prop><D:getetag/>" &
    "</D:prop></D:sync-collection>"

proc multigetBody*(kind: string; hrefs: openArray[string]): string =
  if hrefs.len < 1 or hrefs.len > MaxMultigetHrefs:
    raise newException(DavXmlError, "DAV multiget href count must be between 1 and " &
      $MaxMultigetHrefs)
  validateReportKind(kind)
  let isCalendar = kind.cmpIgnoreCase("calendar") == 0
  let prefix = if isCalendar: "C" else: "A"
  let namespace = if isCalendar: CalDavNamespace else: CardDavNamespace
  let report = if isCalendar: "calendar-multiget" else: "addressbook-multiget"
  let data = if isCalendar: "calendar-data" else: "address-data"
  result = "<?xml version=\"1.0\" encoding=\"utf-8\"?><" & prefix & ":" & report &
    " xmlns:D=\"DAV:\" xmlns:" & prefix & "=\"" & namespace &
    "\"><D:prop><D:getetag/><" & prefix & ":" & data & "/></D:prop>"
  for href in hrefs: result.add("<D:href>" & xmlEscape(href) & "</D:href>")
  result.add("</" & prefix & ":" & report & ">")

proc validateUtcRange(startUtc, endUtc: string) =
  try:
    discard parse(startUtc, "yyyyMMdd'T'HHmmss'Z'", utc())
    discard parse(endUtc, "yyyyMMdd'T'HHmmss'Z'", utc())
  except ValueError:
    raise newException(DavXmlError, "time range must use UTC iCalendar timestamps")
  if endUtc <= startUtc:
    raise newException(DavXmlError, "time range must be increasing")

proc collectionQueryBody*(kind: string; startUtc = ""; endUtc = "";
                          timezoneId = ""; component = "";
                          property = ""; propertyText = ""): string =
  validateReportKind(kind)
  let isCalendar = kind.cmpIgnoreCase("calendar") == 0
  let prefix = if isCalendar: "C" else: "A"
  let namespace = if isCalendar: CalDavNamespace else: CardDavNamespace
  let report = if isCalendar: "calendar-query" else: "addressbook-query"
  let data = if isCalendar: "calendar-data" else: "address-data"
  validateCalendarComponent(component)
  validateVCardProperty(property)
  if component.len > 0 and not isCalendar:
    raise newException(DavXmlError,
      "component filter is only supported for calendar queries")
  if (startUtc.len > 0) != (endUtc.len > 0) or (not isCalendar and
      (startUtc.len > 0 or endUtc.len > 0)):
    raise newException(DavXmlError, "time range is only supported for calendar queries")
  if startUtc.len > 0: validateUtcRange(startUtc, endUtc)
  if timezoneId.len > 0 and (not isCalendar or timezoneId.contains({'\r', '\n',
      '<', '>', '"', '&'})):
    raise newException(DavXmlError, "invalid calendar time zone identifier")
  if property.len > 0 and isCalendar:
    raise newException(DavXmlError,
      "CardDAV property filter is only supported for addressbook queries")
  if propertyText.len > 0 and (isCalendar or propertyText.contains({'\r', '\n',
      '\0'})):
    raise newException(DavXmlError,
      "CardDAV text match is only supported for safe addressbook text")
  let selectedComponent = if component.len > 0: component.toUpperAscii else:
      (if startUtc.len > 0: "VEVENT" else: "")
  var filter = ""
  if isCalendar and selectedComponent.len > 0:
    filter = "<C:filter><C:comp-filter name=\"VCALENDAR\"><C:comp-filter name=\"" &
      selectedComponent & "\"" & (if startUtc.len > 0:
      "><C:time-range start=\"" & xmlEscape(startUtc) & "\" end=\"" &
      xmlEscape(endUtc) & "\"/></C:comp-filter>"
      else: "/>") & "</C:comp-filter></C:filter>"
  elif isCalendar:
    filter = "<C:filter><C:comp-filter name=\"VCALENDAR\"/></C:filter>"
  else:
    var propertyFilter = "<A:prop-filter name=\"" &
      (if property.len > 0: property.toUpperAscii else: "FN") & "\""
    if propertyText.len > 0:
      propertyFilter.add("><A:text-match collation=\"i;unicode-casemap\" " &
        "match-type=\"contains\">" & xmlEscape(propertyText) &
        "</A:text-match></A:prop-filter>")
    else:
      propertyFilter.add("/>")
    filter = "<A:filter test=\"anyof\">" & propertyFilter & "</A:filter>"
  let timezone = if timezoneId.len > 0: "<C:timezone-id>" & xmlEscape(
      timezoneId) & "</C:timezone-id>" else: ""
  result = "<?xml version=\"1.0\" encoding=\"utf-8\"?><" & prefix & ":" & report &
    " xmlns:D=\"DAV:\" xmlns:" & prefix & "=\"" & namespace &
    "\"><D:prop><D:getetag/><" & prefix & ":" & data & "/></D:prop>" &
    filter & timezone & "</" & prefix & ":" & report & ">"

# Keep source mapping stable for gcov-generated branches.

proc freeBusyQueryBody*(startUtc, endUtc: string): string =
  ## Build the RFC 4791 free-busy REPORT with a bounded UTC time range.
  validateUtcRange(startUtc, endUtc)
  "<?xml version=\"1.0\" encoding=\"utf-8\"?><C:free-busy-query " &
    "xmlns:D=\"DAV:\" xmlns:C=\"" & CalDavNamespace & "\"><D:prop>" &
    "<C:calendar-data/></D:prop><C:time-range start=\"" & xmlEscape(startUtc) &
    "\" end=\"" & xmlEscape(endUtc) & "\"/></C:free-busy-query>"

# End of module.
