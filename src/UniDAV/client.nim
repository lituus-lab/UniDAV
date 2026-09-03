# SPDX-License-Identifier: Apache-2.0
import std/[strutils, tables, uri]
import component, davxml, document, etag

type
  DavMethod* = enum dmGet, dmPut, dmPost, dmDelete, dmOptions, dmPropfind, dmReport
  DavRequest* = object
    httpMethod*: DavMethod
    url*: string
    headers*: Table[string, string]
    body*: string
  DavHttpResponse* = object
    status*: int
    headers*: Table[string, string]
    body*: string
    finalUrl*: string
  DavTransport* = proc(request: DavRequest): DavHttpResponse {.closure.}
  DavClientError* = object of CatchableError
  DavTransportError* = object of DavClientError
  DavHttpError* = object of DavClientError
    status*: int
    responseBody*: string
  DavServiceKind* = enum dskCalendar, dskAddressBook
  DiscoveryResult* = object
    contextUrl*: string
    principalUrl*: string
    homeUrl*: string
    scheduleInboxUrl*: string
    scheduleOutboxUrl*: string
    calendarUserAddresses*: seq[string]
    calendarAvailability*: string
  CollectionInfo* = object
    href*: string
    displayName*: string
    syncToken*: string
    kind*: DavServiceKind
    timezoneId*: string
    timezoneServiceUrls*: seq[string]
  DavClient* = ref object
    transport*: DavTransport
  ResourcePayload* = object
    body*: string
    etag*: string
    contentType*: string
    finalUrl*: string
  WritePreconditionKind* = enum wpkCreate, wpkReplace
  WritePrecondition* = object
    kind*: WritePreconditionKind
    etag*: string

  ScheduleResponse* = object
    status*: int
    body*: string
    contentType*: string
  DavCapabilities* = object
    tokens*: seq[string]
    calendarAccess*: bool
    calendarSchedule*: bool
    calendarAutoSchedule*: bool
    calendarAvailability*: bool

proc newDavClient*(transport: DavTransport): DavClient =
  if transport.isNil: raise newException(DavClientError, "DAV transport is required")
  DavClient(transport: transport)

proc resolveUrl*(baseUrl, reference: string): string =
  if reference.startsWith("http://") or reference.startsWith(
      "https://"): return reference
  $combine(parseUri(baseUrl), parseUri(reference))

proc wellKnownUrl*(baseUrl: string; kind: DavServiceKind): string =
  let parsed = parseUri(baseUrl)
  if parsed.scheme notin ["http", "https"]:
    raise newException(DavClientError, "DAV base URL must use HTTP or HTTPS")
  var origin = parsed
  origin.path = if kind == dskCalendar: "/.well-known/caldav" else: "/.well-known/carddav"
  origin.query = ""
  origin.anchor = ""
  $origin

proc request(client: DavClient; httpMethod: DavMethod; url, body: string;
             depth = ""; extraHeaders: openArray[(string, string)] = []): DavHttpResponse =
  var headers = initTable[string, string]()
  headers["Accept"] = "application/xml, text/xml;q=0.9"
  if httpMethod in {dmPropfind, dmReport} and depth.len > 0:
    headers["Content-Type"] = "application/xml; charset=utf-8"
    headers["Depth"] = depth
  elif httpMethod in {dmPropfind, dmReport}:
    headers["Content-Type"] = "application/xml; charset=utf-8"
  for (name, value) in extraHeaders: headers[name] = value
  result = client.transport(DavRequest(httpMethod: httpMethod, url: url,
      headers: headers, body: body))
  if result.status < 200 or result.status >= 400:
    let message = if result.status in [401,
        403]: "DAV authentication or authorization failed"
      else: "DAV request failed with HTTP " & $result.status
    var error = newException(DavHttpError, message)
    error.status = result.status
    error.responseBody = result.body
    raise error

proc responseHeader(headers: Table[string, string]; wanted: string): string =
  for name, value in headers:
    if name.cmpIgnoreCase(wanted) == 0: return value

proc normalizedMediaType(value: string): string =
  value.split(';', 1)[0].strip.toLowerAscii

proc validCalendarUserAddress(value: string): bool =
  ## RFC 6638 calendar-user-address values are absolute URIs. Keep the
  ## scheme policy open (mailto, urn, and server-specific schemes are valid)
  ## while rejecting header-unsafe or fragment-bearing values.
  if value.len == 0: return false
  for character in value:
    if character in {'\r', '\n'} or character.isSpaceAscii: return false
  let schemeSeparator = value.find(':')
  if schemeSeparator <= 0 or schemeSeparator == value.high: return false
  try:
    let parsed = parseUri(value)
    parsed.scheme.len > 0 and parsed.anchor.len == 0
  except ValueError:
    false

proc validScheduleBody(body: string): bool =
  ## A schedule outbox POST carries one RFC 5546 iTIP method.
  try:
    let roots = parseComponents(body)
    if roots.len != 1 or roots[0].name != "VCALENDAR": return false
    let methods = roots[0].properties("METHOD")
    methods.len == 1 and methods[0].value.toUpperAscii in
      ["PUBLISH", "REQUEST", "REPLY", "ADD", "CANCEL", "REFRESH",
       "COUNTER", "DECLINECOUNTER"]
  except CatchableError:
    false

proc validCalendarAvailability*(body: string): bool =
  ## Validate the RFC 7953 calendar-availability property shape.
  if detectKind(body) != dkICalendar or not isValid(body): return false
  try:
    let roots = parseComponents(body)
    if roots.len != 1 or roots[0].name != "VCALENDAR": return false
    let availability = roots[0].children("VAVAILABILITY")
    if availability.len != 1: return false
    for child in roots[0].children():
      if child.name notin ["VAVAILABILITY", "VTIMEZONE"]: return false
    let item = availability[0]
    if item.properties("UID").len != 1 or item.properties("DTSTAMP").len != 1:
      return false
    for available in item.children("AVAILABLE"):
      if available.properties("UID").len != 1 or
          available.properties("DTSTART").len != 1 or
          (available.properties("DTEND").len > 0 and
           available.properties("DURATION").len > 0):
        return false
    true
  except CatchableError:
    false

proc fetchResource*(client: DavClient; url: string): ResourcePayload =
  let response = client.request(dmGet, url, "", extraHeaders = [("Accept",
      "text/calendar, text/vcard;q=0.9")])
  ResourcePayload(body: response.body, etag: responseHeader(response.headers, "ETag"),
    contentType: normalizedMediaType(responseHeader(response.headers,
        "Content-Type")),
    finalUrl: if response.finalUrl.len > 0: response.finalUrl else: url)

proc capabilities*(client: DavClient; url: string): DavCapabilities =
  ## Read the DAV response header advertised by a server's OPTIONS endpoint.
  let response = client.request(dmOptions, url, "")
  for token in responseHeader(response.headers, "DAV").split(','):
    let normalized = token.strip.toLowerAscii
    if normalized.len == 0: continue
    result.tokens.add(normalized)
    case normalized
    of "calendar-access": result.calendarAccess = true
    of "calendar-schedule": result.calendarSchedule = true
    of "calendar-auto-schedule": result.calendarAutoSchedule = true
    of "calendar-availability": result.calendarAvailability = true
    else: discard

proc putResource*(client: DavClient; url, body, contentType: string;
                  precondition: WritePrecondition): ResourcePayload =
  if body.len == 0: raise newException(DavClientError, "DAV resource body is required")
  if contentType notin ["text/calendar", "text/vcard"]:
    raise newException(DavClientError, "DAV resource content type must be text/calendar or text/vcard")
  let expectedKind = if contentType == "text/calendar": dkICalendar else: dkVCard
  if detectKind(body) != expectedKind or not isValid(body):
    raise newException(DavClientError, "DAV resource body does not match its declared content type")
  var conditions: seq[(string, string)] = @[("Content-Type", contentType &
      "; charset=utf-8")]
  case precondition.kind
  of wpkCreate: conditions.add(("If-None-Match", "*"))
  of wpkReplace:
    if not isStrongEtag(precondition.etag):
      raise newException(DavClientError, "replacement requires a safe ETag")
    conditions.add(("If-Match", precondition.etag))
  let response = client.request(dmPut, url, body, extraHeaders = conditions)
  ResourcePayload(body: response.body, etag: responseHeader(response.headers, "ETag"),
    contentType: responseHeader(response.headers, "Content-Type"),
    finalUrl: if response.finalUrl.len > 0: response.finalUrl else: url)

proc postSchedule*(client: DavClient; outboxUrl, icalBody, originator: string;
                   recipients: openArray[string]): ScheduleResponse =
  ## Submit an iTIP scheduling message to a CalDAV schedule outbox (RFC 6638).
  ## The caller supplies the server-advertised outbox and recipient addresses;
  ## no credentials or address policy are stored by this engine.
  if outboxUrl.len == 0 or icalBody.len == 0:
    raise newException(DavClientError, "schedule outbox and iCalendar body are required")
  if detectKind(icalBody) != dkICalendar or not isValid(icalBody) or
      not validScheduleBody(icalBody):
    raise newException(DavClientError,
      "schedule body must contain exactly one valid iTIP METHOD")
  if not validCalendarUserAddress(originator) or
      recipients.len == 0:
    raise newException(DavClientError,
      "schedule originator and recipients must be absolute URIs")
  var headers: seq[(string, string)] = @[
    ("Content-Type", "text/calendar; charset=utf-8"),
    ("Originator", originator)]
  var recipientHeader = ""
  for recipient in recipients:
    if not validCalendarUserAddress(recipient):
      raise newException(DavClientError,
        "schedule recipient must be an absolute URI")
    if recipientHeader.len > 0: recipientHeader.add(", ")
    recipientHeader.add(recipient)
  headers.add(("Recipient", recipientHeader))
  let response = client.request(dmPost, outboxUrl, icalBody,
      extraHeaders = headers)
  ScheduleResponse(status: response.status, body: response.body,
    contentType: normalizedMediaType(responseHeader(response.headers,
        "Content-Type")))

proc deleteResource*(client: DavClient; url, etag: string) =
  if not isStrongEtag(etag):
    raise newException(DavClientError, "deletion requires a safe ETag")
  discard client.request(dmDelete, url, "", extraHeaders = [("If-Match", etag)])

proc discover*(client: DavClient; baseUrl: string;
    kind: DavServiceKind): DiscoveryResult =
  let initial = wellKnownUrl(baseUrl, kind)
  let principalBody = propfindBody(@[(DavNamespace, "current-user-principal")])
  let initialResponse = client.request(dmPropfind, initial, principalBody)
  result.contextUrl = if initialResponse.finalUrl.len >
      0: initialResponse.finalUrl else: initial
  let contextMultiStatus = parseMultiStatus(initialResponse.body)
  if contextMultiStatus.responses.len == 0:
    raise newException(DavClientError, "DAV discovery returned no principal response")
  let principalHref = contextMultiStatus.responses[0].property(
      "current-user-principal").strip
  if principalHref.len == 0:
    raise newException(DavClientError, "DAV current-user-principal is missing")
  result.principalUrl = resolveUrl(result.contextUrl, principalHref)
  let homeProperty = if kind == dskCalendar: "calendar-home-set" else: "addressbook-home-set"
  let homeNamespace = if kind == dskCalendar: CalDavNamespace else: CardDavNamespace
  var principalProperties = @[(homeNamespace, homeProperty)]
  if kind == dskCalendar:
    principalProperties.add((CalDavNamespace, "schedule-inbox-URL"))
    principalProperties.add((CalDavNamespace, "schedule-outbox-URL"))
    principalProperties.add((CalDavNamespace, "calendar-user-address-set"))
  let homeResponse = client.request(dmPropfind, result.principalUrl,
    propfindBody(principalProperties))
  let homeMultiStatus = parseMultiStatus(homeResponse.body)
  if homeMultiStatus.responses.len == 0:
    raise newException(DavClientError, "DAV discovery returned no home-set response")
  let homeHref = homeMultiStatus.responses[0].property(homeProperty).strip
  if homeHref.len == 0: raise newException(DavClientError, "DAV home-set is missing")
  result.homeUrl = resolveUrl(result.principalUrl, homeHref)
  let principalResponse = homeMultiStatus.responses[0]
  let inbox = principalResponse.property("schedule-inbox-URL").strip
  let outbox = principalResponse.property("schedule-outbox-URL").strip
  if inbox.len > 0: result.scheduleInboxUrl = resolveUrl(result.principalUrl, inbox)
  if outbox.len > 0: result.scheduleOutboxUrl = resolveUrl(result.principalUrl, outbox)
  for address in principalResponse.properties:
    if address.name.cmpIgnoreCase("calendar-user-address-set") != 0: continue
    if address.childValues.len > 0:
      for value in address.childValues:
        if value.len > 0: result.calendarUserAddresses.add(value)
    elif address.value.strip.len > 0:
      result.calendarUserAddresses.add(address.value.strip)
  if result.scheduleInboxUrl.len > 0:
    try:
      let inboxResponse = client.request(dmPropfind, result.scheduleInboxUrl,
        propfindBody(@[(CalDavNamespace, "calendar-availability")]))
      if inboxResponse.status in 200..299:
        let inbox = parseMultiStatus(inboxResponse.body)
        if inbox.responses.len > 0:
          let availability = inbox.responses[0].property(
              "calendar-availability").strip
          if availability.len > 0:
            if not validCalendarAvailability(availability):
              raise newException(DavClientError,
                "server returned invalid calendar availability")
            result.calendarAvailability = availability
    except DavHttpError as error:
      if error.status notin [403, 404, 405, 501]: raise

proc listCollections*(client: DavClient; discovery: DiscoveryResult;
                      kind: DavServiceKind): seq[CollectionInfo] =
  let namespace = if kind == dskCalendar: CalDavNamespace else: CardDavNamespace
  let collectionMarker = if kind == dskCalendar: "calendar" else: "addressbook"
  var properties = @[(DavNamespace, "displayname"), (DavNamespace,
      "resourcetype"), (DavNamespace, "sync-token"), (namespace,
      collectionMarker)]
  if kind == dskCalendar:
    properties.add((CalDavNamespace, "calendar-timezone-id"))
    properties.add((CalDavNamespace, "timezone-service-set"))
  let response = client.request(dmPropfind, discovery.homeUrl,
    propfindBody(properties), depth = "1")
  for resource in parseMultiStatus(response.body).responses:
    if not resource.hasPropertyChild("resourcetype", collectionMarker): continue
    var info = CollectionInfo(href: resolveUrl(discovery.homeUrl,
        resource.href),
      displayName: resource.property("displayname").strip,
      syncToken: resource.property("sync-token").strip, kind: kind,
      timezoneId: resource.property("calendar-timezone-id").strip)
    for item in resource.properties:
      if item.name.cmpIgnoreCase("timezone-service-set") != 0: continue
      for value in item.childValues:
        if value.len > 0: info.timezoneServiceUrls.add(resolveUrl(
            discovery.homeUrl, value))
    result.add(info)

proc syncCollection*(client: DavClient; collectionUrl,
    token: string): MultiStatus =
  let response = client.request(dmReport, collectionUrl, syncCollectionBody(token))
  parseMultiStatus(response.body)

proc inventoryCollection*(client: DavClient;
    collectionUrl: string): MultiStatus =
  let response = client.request(dmPropfind, collectionUrl,
    propfindBody(@[(DavNamespace, "getetag"), (DavNamespace, "resourcetype"),
      (DavNamespace, "sync-token")]), depth = "1")
  parseMultiStatus(response.body)

proc multiget*(client: DavClient; collectionUrl: string; kind: DavServiceKind;
               hrefs: openArray[string]): MultiStatus =
  ## RFC 4791 §7.9 and RFC 6352 §8.7 require clients to omit Depth here.
  let reportKind = if kind == dskCalendar: "calendar" else: "addressbook"
  let response = client.request(dmReport, collectionUrl, multigetBody(
      reportKind, hrefs), depth = "")
  parseMultiStatus(response.body)

proc queryCollection*(client: DavClient; collectionUrl: string;
                      kind: DavServiceKind; startUtc = "";
                      endUtc = ""; timezoneId = ""; component = "";
                      property = ""; propertyText = ""): MultiStatus =
  let reportKind = if kind == dskCalendar: "calendar" else: "addressbook"
  let response = client.request(dmReport, collectionUrl, collectionQueryBody(
      reportKind, startUtc, endUtc, timezoneId, component, property,
      propertyText),
    depth = "1")
  parseMultiStatus(response.body)

proc queryFreeBusy*(client: DavClient; collectionUrl, startUtc,
                    endUtc: string): MultiStatus =
  ## Query busy periods for a UTC range using the CalDAV free-busy REPORT.
  let response = client.request(dmReport, collectionUrl,
    freeBusyQueryBody(startUtc, endUtc), depth = "0")
  parseMultiStatus(response.body)

# Keep source mapping stable for gcov-generated exception branches.
# End of module.
