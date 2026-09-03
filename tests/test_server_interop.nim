# SPDX-License-Identifier: Apache-2.0
import std/[os, strutils, unittest, sequtils]
import UniDAV/[client, document, http_transport]

proc interopEnv(genericName, legacyName: string): string =
  result = getEnv(genericName)
  if result.len == 0:
    result = getEnv(legacyName)

let baseUrl = interopEnv("UNIDAV_INTEROP_URL", "UNIDAV_RADICALE_URL")
let username = interopEnv("UNIDAV_INTEROP_USER", "UNIDAV_RADICALE_USER")
let password = interopEnv("UNIDAV_INTEROP_PASSWORD", "UNIDAV_RADICALE_PASSWORD")
let calendarName = getEnv("UNIDAV_INTEROP_CALENDAR", "Interop Calendar")
let addressBookName = getEnv("UNIDAV_INTEROP_ADDRESSBOOK", "Interop Address Book")

proc collectionNamed(client: DavClient; kind: DavServiceKind;
    name: string): CollectionInfo =
  let discovery = client.discover(baseUrl, kind)
  for collection in client.listCollections(discovery, kind):
    if collection.displayName == name:
      return collection
  raise newException(ValueError, "DAV collection was not discovered: " & name)

proc deleteIfPresent(client: DavClient; url: string) =
  try:
    let resource = client.fetchResource(url)
    client.deleteResource(url, resource.etag)
  except DavHttpError as error:
    if error.status != 404:
      raise

suite "DAV server interoperability":
  test "discovers, creates, queries, replaces and deletes CalDAV/CardDAV resources":
    require baseUrl.startsWith("https://")
    require username.len > 0
    var config = defaultHttpTransportConfig()
    config.credentials = DavCredentials(kind: dakBasic, username: username,
        password: password)
    config.caBundlePath = interopEnv("UNIDAV_INTEROP_CA_BUNDLE", "UNIDAV_RADICALE_CA_BUNDLE")
    config.connectTimeoutMs = 5_000
    config.timeoutMs = 20_000
    let client = newDavClient(newHttpTransport(config))

    let calendar = client.collectionNamed(dskCalendar, calendarName)
    let addressBook = client.collectionNamed(dskAddressBook, addressBookName)
    check calendar.href.startsWith(baseUrl)
    check addressBook.href.startsWith(baseUrl)

    let eventUrl = resolveUrl(calendar.href, "unidav-interop-event.ics")
    let contactUrl = resolveUrl(addressBook.href, "unidav-interop-contact.vcf")
    client.deleteIfPresent(eventUrl)
    client.deleteIfPresent(contactUrl)
    defer:
      client.deleteIfPresent(eventUrl)
      client.deleteIfPresent(contactUrl)
    let eventV1 = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//UniDAV Interop//EN\r\n" &
      "BEGIN:VEVENT\r\nUID:unidav-interop-event\r\nDTSTAMP:20260801T230000Z\r\n" &
      "DTSTART:20260802T100000Z\r\nSUMMARY:Interop first\r\nX-INTEROP:kept\r\n" &
      "END:VEVENT\r\nEND:VCALENDAR\r\n"
    let eventCreated = client.putResource(eventUrl, eventV1, "text/calendar",
      WritePrecondition(kind: wpkCreate))
    check eventCreated.etag.len > 0
    let fetchedEvent = client.fetchResource(eventUrl)
    check fetchedEvent.contentType == "text/calendar"
    check detectKind(fetchedEvent.body) == dkICalendar
    check fetchedEvent.body.contains("X-INTEROP:kept")

    let eventV2 = eventV1.replace("SUMMARY:Interop first", "SUMMARY:Interop replaced")
    discard client.putResource(eventUrl, eventV2, "text/calendar",
      WritePrecondition(kind: wpkReplace, etag: fetchedEvent.etag))
    check client.fetchResource(eventUrl).body.contains("SUMMARY:Interop replaced")

    # Exercise the server-side RFC 4791 component filter and the conditional
    # recovery path with a deliberately stale validator.
    let componentQuery = client.queryCollection(calendar.href, dskCalendar,
      component = "VEVENT")
    check componentQuery.responses.anyIt(it.href.endsWith("unidav-interop-event.ics"))
    let stale = client.fetchResource(eventUrl)
    var rejectedStale = false
    try:
      discard client.putResource(eventUrl,
        eventV2.replace("SUMMARY:Interop replaced", "SUMMARY:stale"),
        "text/calendar", WritePrecondition(kind: wpkReplace,
          etag: fetchedEvent.etag))
    except DavHttpError as error:
      check error.status == 412
      rejectedStale = true
    check rejectedStale
    let recovered = client.fetchResource(eventUrl)
    check recovered.etag == stale.etag
    discard client.putResource(eventUrl,
      eventV2.replace("SUMMARY:Interop replaced", "SUMMARY:recovered"),
      "text/calendar", WritePrecondition(kind: wpkReplace,
        etag: recovered.etag))
    check client.fetchResource(eventUrl).body.contains("SUMMARY:recovered")

    let calendarQuery = client.queryCollection(calendar.href, dskCalendar)
    check calendarQuery.responses.anyIt(it.href.endsWith("unidav-interop-event.ics"))
    let eventMulti = client.multiget(calendar.href, dskCalendar, @[eventUrl])
    check eventMulti.responses.len == 1

    let contact = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:unidav-interop-contact\r\n" &
      "FN:UniDAV Interop\r\nEMAIL:interop@example.test\r\nX-INTEROP:kept\r\nEND:VCARD\r\n"
    let contactCreated = client.putResource(contactUrl, contact, "text/vcard",
      WritePrecondition(kind: wpkCreate))
    check contactCreated.etag.len > 0
    let fetchedContact = client.fetchResource(contactUrl)
    check fetchedContact.contentType == "text/vcard"
    check fetchedContact.body.contains("FN:UniDAV Interop")
    let addressQuery = client.queryCollection(addressBook.href, dskAddressBook)
    check addressQuery.responses.anyIt(it.href.endsWith("unidav-interop-contact.vcf"))
    let propertyQuery = client.queryCollection(addressBook.href, dskAddressBook,
      property = "EMAIL", propertyText = "interop@example.test")
    check propertyQuery.responses.anyIt(it.href.endsWith("unidav-interop-contact.vcf"))

    client.deleteResource(eventUrl, client.fetchResource(eventUrl).etag)
    client.deleteResource(contactUrl, fetchedContact.etag)
    expect DavHttpError:
      discard client.fetchResource(eventUrl)
    expect DavHttpError:
      discard client.fetchResource(contactUrl)
