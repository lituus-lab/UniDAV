# SPDX-License-Identifier: Apache-2.0
import std/[options, strutils, tables, times, unittest]
import UniDAV

proc response(status: int; body: string; finalUrl = ""): DavHttpResponse =
  DavHttpResponse(status: status, body: body, finalUrl: finalUrl,
    headers: initTable[string, string]())

suite "DAV client discovery":
  test "discovers calendar principal, home and collections":
    var requests: seq[DavRequest]
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      requests.add(request)
      if request.url.endsWith("/.well-known/caldav"):
        return response(207, """<D:multistatus xmlns:D="DAV:"><D:response><D:href>/dav/</D:href>
          <D:propstat><D:prop><D:current-user-principal><D:href>/principals/ada/</D:href>
          </D:current-user-principal></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
          </D:response></D:multistatus>""", "https://dav.example.test/dav/")
      if request.url.endsWith("/principals/ada/"):
        return response(207, """<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:response><D:href>/principals/ada/</D:href><D:propstat><D:prop>
          <C:calendar-home-set><D:href>/calendars/ada/</D:href></C:calendar-home-set>
          <C:schedule-inbox-URL><D:href>/calendars/ada/inbox/</D:href></C:schedule-inbox-URL>
          <C:schedule-outbox-URL><D:href>/calendars/ada/outbox/</D:href></C:schedule-outbox-URL>
          <C:calendar-user-address-set><D:href>mailto:ada@example.test</D:href></C:calendar-user-address-set>
          </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>""")
      if request.url.endsWith("/calendars/ada/inbox/"):
        return response(207, """<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:response><D:href>/calendars/ada/inbox/</D:href><D:propstat><D:prop>
          <C:calendar-availability>BEGIN:VCALENDAR&#13;&#10;VERSION:2.0&#13;&#10;PRODID:-//Test//EN&#13;&#10;BEGIN:VAVAILABILITY&#13;&#10;UID:availability-1&#13;&#10;DTSTAMP:20260801T120000Z&#13;&#10;END:VAVAILABILITY&#13;&#10;END:VCALENDAR&#13;&#10;</C:calendar-availability>
          </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>""")
      return response(207, """<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
        <D:response><D:href>/calendars/ada/work/</D:href><D:propstat><D:prop>
        <D:displayname>Work</D:displayname><D:resourcetype><D:collection/><C:calendar/></D:resourcetype>
        <C:calendar-timezone-id>Europe/Paris</C:calendar-timezone-id>
        <C:timezone-service-set><D:href>https://tz.example.test/</D:href></C:timezone-service-set>
        <D:sync-token>token-1</D:sync-token></D:prop><D:status>HTTP/1.1 200 OK</D:status>
        </D:propstat></D:response></D:multistatus>""")
    let client = newDavClient(transport)
    let discovery = client.discover("https://dav.example.test/account", dskCalendar)
    check discovery.contextUrl == "https://dav.example.test/dav/"
    check discovery.principalUrl == "https://dav.example.test/principals/ada/"
    check discovery.homeUrl == "https://dav.example.test/calendars/ada/"
    check discovery.scheduleInboxUrl == "https://dav.example.test/calendars/ada/inbox/"
    check discovery.scheduleOutboxUrl == "https://dav.example.test/calendars/ada/outbox/"
    check discovery.calendarUserAddresses == @["mailto:ada@example.test"]
    check discovery.calendarAvailability.contains("BEGIN:VAVAILABILITY")
    check validCalendarAvailability(discovery.calendarAvailability)
    let collections = client.listCollections(discovery, dskCalendar)
    check collections.len == 1
    check collections[0].displayName == "Work"
    check collections[0].syncToken == "token-1"
    check collections[0].timezoneId == "Europe/Paris"
    check collections[0].timezoneServiceUrls == @["https://tz.example.test/"]
    check requests[^1].headers["Depth"] == "1"

  test "builds a bounded CalDAV free-busy report":
    var seen: DavRequest
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      seen = request
      response(207, """<D:multistatus xmlns:D="DAV:"/>""")
    let result = newDavClient(transport).queryFreeBusy(
      "https://dav.example.test/calendars/ada/",
      "20260801T000000Z", "20260802T000000Z")
    check result.responses.len == 0
    check seen.httpMethod == dmReport
    check seen.headers["Depth"] == "0"
    check seen.body.contains("free-busy-query")
    check seen.body.contains("start=\"20260801T000000Z\"")
    expect DavXmlError:
      discard newDavClient(transport).queryFreeBusy(
        "https://dav.example.test/calendars/ada/", "20260802T000000Z",
        "20260801T000000Z")

  test "reads CalDAV capabilities from OPTIONS":
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      var headers = initTable[string, string]()
      headers["DAV"] = "1, 2, calendar-access, calendar-schedule, calendar-availability"
      DavHttpResponse(status: 200, headers: headers, body: "")
    let found = newDavClient(transport).capabilities("https://dav.example.test/")
    check found.calendarAccess
    check found.calendarSchedule
    check not found.calendarAutoSchedule
    check found.calendarAvailability
    check found.tokens == @["1", "2", "calendar-access", "calendar-schedule",
      "calendar-availability"]

  test "adds a bounded time-range to CalDAV collection queries":
    var seen: DavRequest
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      seen = request
      response(207, "<D:multistatus xmlns:D=\"DAV:\"/>")
    discard newDavClient(transport).queryCollection(
      "https://dav.example.test/calendars/ada/", dskCalendar,
      "20260801T000000Z", "20260803T000000Z")
    check seen.body.contains("name=\"VEVENT\"")
    check seen.body.contains("end=\"20260803T000000Z\"")
    discard newDavClient(transport).queryCollection(
      "https://dav.example.test/calendars/ada/", dskCalendar,
      "", "", "", "VTODO")
    check seen.body.contains("name=\"VTODO\"")
    discard newDavClient(transport).queryCollection(
      "https://dav.example.test/calendars/ada/", dskCalendar,
      "", "", "Europe/Paris")
    check seen.body.contains("timezone-id>Europe/Paris")
    expect DavXmlError:
      discard newDavClient(transport).queryCollection(
        "https://dav.example.test/calendars/ada/", dskCalendar,
        "20260803T000000Z", "20260801T000000Z")

  test "builds CardDAV well-known URL and validates inputs":
    check wellKnownUrl("https://example.test/path", dskAddressBook) ==
      "https://example.test/.well-known/carddav"
    expect DavClientError: discard wellKnownUrl("ftp://example.test", dskCalendar)
    expect DavClientError: discard newDavClient(nil)

  test "builds a non-empty RFC 6352 addressbook filter":
    var seen: DavRequest
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      seen = request
      response(207, "<D:multistatus xmlns:D=\"DAV:\"/>")
    discard newDavClient(transport).queryCollection(
      "https://example.test/addressbooks/ada/", dskAddressBook)
    check seen.body.contains("addressbook-query")
    check seen.body.contains("<A:filter test=\"anyof\">")
    check seen.body.contains("<A:prop-filter name=\"FN\"/>")
    discard newDavClient(transport).queryCollection(
      "https://example.test/addressbooks/ada/", dskAddressBook,
      property = "EMAIL")
    check seen.body.contains("<A:prop-filter name=\"EMAIL\"/>")
    discard newDavClient(transport).queryCollection(
      "https://example.test/addressbooks/ada/", dskAddressBook,
      property = "FN", propertyText = "Ada")
    check seen.body.contains("<A:text-match")

  test "does not send Depth for CalDAV or CardDAV multiget":
    var seen: DavRequest
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      seen = request
      response(207, "<D:multistatus xmlns:D=\"DAV:\"/>")
    discard newDavClient(transport).multiget(
      "https://example.test/addressbooks/ada/", dskAddressBook,
      @["https://example.test/addressbooks/ada/a.vcf"])
    check not seen.headers.hasKey("Depth")
    check seen.headers["Content-Type"] == "application/xml; charset=utf-8"
    discard newDavClient(transport).multiget(
      "https://example.test/calendars/ada/", dskCalendar,
      @["https://example.test/calendars/ada/a.ics"])
    check not seen.headers.hasKey("Depth")

  test "reports authentication and malformed discovery":
    let unauthorized: DavTransport = proc(
        request: DavRequest): DavHttpResponse = response(401, "")
    expect DavClientError:
      discard newDavClient(unauthorized).discover("https://example.test", dskCalendar)
    let empty: DavTransport = proc(request: DavRequest): DavHttpResponse =
      response(207, "<D:multistatus xmlns:D=\"DAV:\"/>")
    expect DavClientError:
      discard newDavClient(empty).discover("https://example.test", dskCalendar)
    let missingPrincipal: DavTransport = proc(
        request: DavRequest): DavHttpResponse =
      response(207, """<D:multistatus xmlns:D="DAV:"><D:response><D:href>/</D:href>
        <D:propstat><D:prop/><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
        </D:response></D:multistatus>""")
    expect DavClientError:
      discard newDavClient(missingPrincipal).discover("https://example.test", dskCalendar)

suite "RFC 6764 service discovery":
  test "prefers TLS SRV and applies its TXT context path":
    var queries: seq[string]
    let resolver = DavDnsResolver(
      lookupSrv: proc(name: string): seq[DavSrvRecord] =
      queries.add name
      if name.startsWith("_caldavs"):
        @[DavSrvRecord(priority: 10, weight: 1, port: 8443,
            target: "dav.example.test.")]
      else:
        @[],
      lookupTxt: proc(name: string): seq[string] = @["path=/calendar"])
    let endpoints = locateDavService("Example.Test", dskCalendar, resolver,
      proc(limit: int): int = 0, allowPlainHttp = true)
    check endpoints.len == 1
    check endpoints[0].url == "https://dav.example.test:8443/calendar"
    check endpoints[0].secure
    check endpoints[0].fromSrv
    check queries == @["_caldavs._tcp.example.test"]

  test "orders equal-priority SRV records by injected weighted draws":
    let records = @[
      DavSrvRecord(priority: 20, weight: 0, port: 443, target: "later.example"),
      DavSrvRecord(priority: 10, weight: 1, port: 443, target: "one.example"),
      DavSrvRecord(priority: 10, weight: 3, port: 443, target: "three.example")]
    let ordered = orderSrvRecords(records, proc(limit: int): int = limit - 1)
    check ordered[0].target == "three.example"
    check ordered[1].target == "one.example"
    check ordered[2].target == "later.example"

  test "falls back safely and rejects malformed resolver data":
    let emptyResolver = DavDnsResolver(
      lookupSrv: proc(name: string): seq[DavSrvRecord] = @[],
      lookupTxt: proc(name: string): seq[string] = @[])
    let fallback = locateDavService("example.test", dskAddressBook,
      emptyResolver, proc(limit: int): int = 0)
    check fallback.len == 1
    check fallback[0].url == "https://example.test/.well-known/carddav"
    check not fallback[0].fromSrv

    let unsafeTxt = DavDnsResolver(
      lookupSrv: proc(name: string): seq[DavSrvRecord] =
      @[DavSrvRecord(priority: 0, weight: 0, port: 443,
          target: "dav.example.test")],
      lookupTxt: proc(name: string): seq[string] = @["path=//other.test/dav"])
    expect DavClientError:
      discard locateDavService("example.test", dskCalendar, unsafeTxt,
        proc(limit: int): int = 0)

    expect DavClientError:
      discard locateDavService("bad/domain", dskCalendar, emptyResolver,
        proc(limit: int): int = 0)

suite "atomic remote apply":
  test "applies upserts, tombstones and checkpoint in one transaction":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test")
    let collection = store.addCollection(account, "/cal/", "calendar", "Work")
    store.applyRemoteBatch(collection, @[
      RemoteChange(kind: rckUpsert, href: "/cal/a.ics", etag: "1",
          rawData: "A"),
      RemoteChange(kind: rckDelete, href: "/cal/b.ics", etag: "2")], "token-2")
    check store.getResource(collection, "/cal/a.ics").get.rawData == "A"
    check store.getResource(collection, "/cal/b.ics").get.deleted
    check store.syncToken(collection) == "token-2"

  test "rolls back resources and token when a batch fails":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    expect CatchableError:
      store.applyRemoteBatch(9999, @[RemoteChange(kind: rckUpsert, href: "/bad",
          rawData: "x")], "bad")
    check store.getResource(9999, "/bad").isNone

  test "never overwrites a resource with an active local-first operation":
    let baseCard = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Base\r\nEND:VCARD\r\n"
    let localCard = baseCard.replace("Base", "Local")
    let remoteCard = baseCard.replace("Base", "Remote")
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/book/",
      "addressbook", "People")
    let href = "https://example.test/book/a.vcf"
    store.putResource(ResourceRecord(collectionId: collection, href: href,
      etag: "\"base\"",
      contentType: "text/vcard", rawData: baseCard))
    store.stageLocalUpsert("local-edit", collection, href, "text/vcard",
      localCard,
      "\"base\"", create = false)
    try:
      store.applyRemoteBatch(collection, @[RemoteChange(kind: rckUpsert,
        href: href,
        etag: "\"remote\"", contentType: "text/vcard", rawData: remoteCard)], "unsafe")
      check false
    except LocalChangesPendingError as error:
      check error.href == href
    check store.getResource(collection, href).get.rawData == localCard
    check store.syncToken(collection) == ""

suite "descending collection sync":
  test "cooperatively cancels before durable apply":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/book/",
      "addressbook", "People")
    let token = newCancellationToken()
    token.cancel()
    var called = false
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      called = true
      response(207, "<D:multistatus xmlns:D=\"DAV:\"/>")
    expect SyncCancelledError:
      discard store.pullCollection(newDavClient(transport), collection,
        "https://example.test/book/", dskAddressBook, cancellation = token)
    check not called
    check store.syncToken(collection) == ""

  test "cancellation after listing leaves cache and checkpoint unchanged":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/book/",
      "addressbook", "People")
    let token = newCancellationToken()
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      token.cancel()
      response(207, """<D:multistatus xmlns:D="DAV:"><D:sync-token>never-committed</D:sync-token>
        </D:multistatus>""")
    expect SyncCancelledError:
      discard store.pullCollection(newDavClient(transport), collection,
        "https://example.test/book/", dskAddressBook, cancellation = token)
    check store.syncToken(collection) == ""
    check store.listResources(collection).len == 0

  test "inventories, multigets changes and checkpoints atomically":
    let oldCard = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Old\r\nEND:VCARD\r\n"
    let newCard = oldCard.replace("Old", "New")
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/book/",
      "addressbook", "People")
    store.putResource(ResourceRecord(collectionId: collection,
      href: "https://example.test/book/gone.vcf", etag: "\"old\"",
      contentType: "text/vcard", rawData: oldCard))
    var requests: seq[DavRequest]
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      requests.add(request)
      if request.httpMethod == dmPropfind:
        return response(207, """<D:multistatus xmlns:D="DAV:"><D:sync-token>token-1</D:sync-token>
          <D:response><D:href>/book/</D:href><D:propstat><D:prop><D:resourcetype>
          <D:collection/></D:resourcetype></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
          <D:response><D:href>/book/new.vcf</D:href><D:propstat><D:prop><D:getetag>"one"</D:getetag>
          </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>""")
      response(207, """<D:multistatus xmlns:D="DAV:" xmlns:A="urn:ietf:params:xml:ns:carddav">
        <D:response><D:href>/book/new.vcf</D:href><D:propstat><D:prop><D:getetag>"one"</D:getetag>
        <A:address-data>BEGIN:VCARD&#13;&#10;VERSION:4.0&#13;&#10;FN:New&#13;&#10;END:VCARD&#13;&#10;</A:address-data>
        </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>""")
    let outcome = store.pullCollection(newDavClient(transport), collection,
      "https://example.test/book/", dskAddressBook)
    check outcome.fullInventory
    check outcome.fetched == 1
    check outcome.deleted == 1
    check store.syncToken(collection) == "token-1"
    check store.getResource(collection, "https://example.test/book/new.vcf").get.rawData == newCard
    check store.getResource(collection, "https://example.test/book/gone.vcf").get.deleted
    check requests[0].headers["Depth"] == "1"

  test "uses incremental sync and falls back only for an invalid token":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/book/",
      "addressbook", "People")
    store.checkpoint(collection, "expired")
    var reports = 0
    let fallback: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmReport:
        inc reports
        return response(403, "<D:error xmlns:D=\"DAV:\"><D:valid-sync-token/></D:error>")
      response(207, """<D:multistatus xmlns:D="DAV:"><D:sync-token>fresh</D:sync-token>
        </D:multistatus>""")
    let outcome = store.pullCollection(newDavClient(fallback), collection,
      "https://example.test/book/", dskAddressBook)
    check reports == 1
    check outcome.fullInventory
    check outcome.syncToken == "fresh"

    store.checkpoint(collection, "current")
    let forbidden: DavTransport = proc(request: DavRequest): DavHttpResponse = response(
        403, "")
    expect DavHttpError:
      discard store.pullCollection(newDavClient(forbidden), collection,
        "https://example.test/book/", dskAddressBook)

    let incremental: DavTransport = proc(request: DavRequest): DavHttpResponse =
      response(207, """<D:multistatus xmlns:D="DAV:"><D:sync-token>next</D:sync-token>
        <D:response><D:href>/book/missing.vcf</D:href><D:status>HTTP/1.1 404 Not Found</D:status>
        </D:response><D:response><D:href>/book/</D:href>
        <D:status>HTTP/1.1 507 Insufficient Storage</D:status></D:response></D:multistatus>""")
    let increment = store.pullCollection(newDavClient(incremental), collection,
      "https://example.test/book/", dskAddressBook)
    check not increment.fullInventory
    check increment.moreAvailable
    check increment.deleted == 1
    check store.syncToken(collection) == "next"

  test "rejects incomplete multiget without advancing the checkpoint":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/book/",
      "addressbook", "People")
    let incomplete: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmPropfind:
        return response(207, """<D:multistatus xmlns:D="DAV:"><D:sync-token>unsafe</D:sync-token>
          <D:response><D:href>/book/a.vcf</D:href><D:propstat><D:prop><D:getetag>"a"</D:getetag>
          </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>""")
      response(207, "<D:multistatus xmlns:D=\"DAV:\"/>")
    expect PullSyncError:
      discard store.pullCollection(newDavClient(incomplete), collection,
        "https://example.test/book/", dskAddressBook)
    check store.syncToken(collection) == ""
    check store.listResources(collection).len == 0
    expect ValueError:
      discard store.pullCollection(newDavClient(incomplete), collection,
        "https://example.test/book/", dskAddressBook, batchSize = 0)

  test "falls back to a complete CardDAV query when sync tokens are unavailable":
    let oldCard = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Old\r\nEND:VCARD\r\n"
    let card = oldCard.replace("Old", "Ada")
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/book/",
      "addressbook", "People")
    store.putResource(ResourceRecord(collectionId: collection,
      href: "https://example.test/book/old.vcf", etag: "\"old\"",
      contentType: "text/vcard", rawData: oldCard))
    var queryRequest: DavRequest
    let noSyncToken: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmPropfind:
        return response(207, "<D:multistatus xmlns:D=\"DAV:\"/>")
      queryRequest = request
      response(207, """<D:multistatus xmlns:D="DAV:" xmlns:A="urn:ietf:params:xml:ns:carddav">
        <D:response><D:href>/book/ada.vcf</D:href><D:propstat><D:prop><D:getetag>"ada"</D:getetag>
        <A:address-data>BEGIN:VCARD&#13;&#10;VERSION:4.0&#13;&#10;FN:Ada&#13;&#10;END:VCARD&#13;&#10;</A:address-data>
        </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>""")
    let outcome = store.pullCollection(newDavClient(noSyncToken), collection,
      "https://example.test/book/", dskAddressBook)
    check outcome.fullInventory
    check outcome.queryFallback
    check outcome.fetched == 1
    check outcome.deleted == 1
    check outcome.syncToken == ""
    check queryRequest.headers["Depth"] == "1"
    check queryRequest.body.contains("addressbook-query")
    check store.getResource(collection, "https://example.test/book/ada.vcf").get.rawData == card
    check store.getResource(collection, "https://example.test/book/old.vcf").get.deleted

  test "falls back from unsupported WebDAV sync to a complete CalDAV query":
    let calendar = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/cal/",
      "calendar", "Work")
    store.checkpoint(collection, "legacy-token")
    var reportCount = 0
    let unsupported: DavTransport = proc(request: DavRequest): DavHttpResponse =
      inc reportCount
      if reportCount == 1: return response(501, "")
      check request.body.contains("calendar-query")
      response(207, """<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
        <D:response><D:href>/cal/one.ics</D:href><D:propstat><D:prop><D:getetag>"one"</D:getetag>
        <C:calendar-data>BEGIN:VCALENDAR&#13;&#10;VERSION:2.0&#13;&#10;PRODID:-//Test//EN&#13;&#10;BEGIN:VEVENT&#13;&#10;UID:1&#13;&#10;DTSTAMP:20260801T120000Z&#13;&#10;END:VEVENT&#13;&#10;END:VCALENDAR&#13;&#10;</C:calendar-data>
        </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>""")
    let outcome = store.pullCollection(newDavClient(unsupported), collection,
      "https://example.test/cal/", dskCalendar)
    check outcome.queryFallback
    check outcome.fetched == 1
    check reportCount == 2
    check store.syncToken(collection) == ""
    check store.getResource(collection, "https://example.test/cal/one.ics").get.rawData == calendar

  test "rejects listing hrefs outside the direct collection boundary":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "https://example.test/book/",
      "addressbook", "People")
    proc unsafeListing(href: string): DavTransport =
      result = proc(request: DavRequest): DavHttpResponse =
        response(207, "<D:multistatus xmlns:D=\"DAV:\"><D:sync-token>unsafe</D:sync-token>" &
          "<D:response><D:href>" & href & "</D:href><D:propstat><D:prop>" &
          "<D:getetag>&quot;x&quot;</D:getetag></D:prop>" &
          "<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>")
    for href in ["https://evil.test/stolen.vcf", "/other/a.vcf", "/book/nested/a.vcf",
                 "/book/a%2Fhidden.vcf", "/book/a.vcf?secret=1"]:
      expect PullSyncError:
        discard store.pullCollection(newDavClient(unsafeListing(href)),
            collection,
          "https://example.test/book/", dskAddressBook)
      check store.syncToken(collection) == ""

suite "conditional DAV resources":
  test "submits validated RFC 6638 scheduling messages":
    let calendar = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "METHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:meeting-1\r\n" &
      "DTSTAMP:20260801T120000Z\r\nDTSTART:20260802T120000Z\r\n" &
      "END:VEVENT\r\nEND:VCALENDAR\r\n"
    var seen: DavRequest
    var scheduleCalls = 0
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      var headers = initTable[string, string]()
      inc scheduleCalls
      seen = request
      headers["Content-Type"] = "application/calendar+json"
      result = DavHttpResponse(status: 200, headers: headers, body: "reply")
    let client = newDavClient(transport)
    let response = client.postSchedule("https://example.test/outbox", calendar,
      "mailto:organizer@example.test", @["mailto:attendee@example.test"])
    check response.status == 200
    check response.body == "reply"
    check seen.httpMethod == dmPost
    check seen.headers["Originator"] == "mailto:organizer@example.test"
    check seen.headers["Recipient"] == "mailto:attendee@example.test"
    check seen.headers["Content-Type"] == "text/calendar; charset=utf-8"
    expect DavClientError:
      discard client.postSchedule("https://example.test/outbox", "invalid",
        "mailto:organizer@example.test", @["mailto:attendee@example.test"])
    expect DavClientError:
      discard client.postSchedule("https://example.test/outbox",
        calendar.replace("METHOD:REQUEST\r\n", ""),
        "mailto:organizer@example.test", @["mailto:attendee@example.test"])
    expect DavClientError:
      discard client.postSchedule("https://example.test/outbox", calendar,
        "organizer@example.test", @["mailto:attendee@example.test"])
    expect DavClientError:
      discard client.postSchedule("https://example.test/outbox", calendar,
        "mailto:organizer@example.test",
        @["https://attendee.example.test/#fragment"])
    check scheduleCalls == 1

  test "fetches, creates, replaces and deletes with preconditions":
    let calendar = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    var requests: seq[DavRequest]
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      requests.add(request)
      case request.httpMethod
      of dmGet:
        var headers = initTable[string, string]()
        headers["etag"] = "\"remote-1\""
        headers["content-type"] = "text/calendar"
        DavHttpResponse(status: 200, headers: headers, body: "calendar",
            finalUrl: request.url)
      of dmPut:
        var headers = initTable[string, string]()
        headers["ETag"] = "\"remote-2\""
        DavHttpResponse(status: 204, headers: headers, finalUrl: request.url)
      else: response(204, "")
    let client = newDavClient(transport)
    let fetched = client.fetchResource("https://example.test/a.ics")
    check fetched.body == "calendar"
    check fetched.etag == "\"remote-1\""
    discard client.putResource("https://example.test/new.ics", calendar,
      "text/calendar",
      WritePrecondition(kind: wpkCreate))
    check requests[^1].headers["If-None-Match"] == "*"
    let replaced = client.putResource("https://example.test/a.ics", calendar,
      "text/calendar",
      WritePrecondition(kind: wpkReplace, etag: "\"remote-1\""))
    check replaced.etag == "\"remote-2\""
    check requests[^1].headers["If-Match"] == "\"remote-1\""
    client.deleteResource("https://example.test/a.ics", "\"remote-2\"")
    check requests[^1].httpMethod == dmDelete
    check requests[^1].headers["If-Match"] == "\"remote-2\""

  test "rejects unsafe writes and exposes HTTP status":
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    let failed: DavTransport = proc(request: DavRequest): DavHttpResponse = response(
        412, "")
    let client = newDavClient(failed)
    expect DavClientError:
      discard client.putResource("https://example.test/a", "", "text/calendar",
        WritePrecondition(kind: wpkCreate))
    expect DavClientError:
      discard client.putResource("https://example.test/a", "x",
        "application/json",
        WritePrecondition(kind: wpkCreate))
    expect DavClientError:
      discard client.putResource("https://example.test/a", "x", "text/vcard",
        WritePrecondition(kind: wpkCreate))
    expect DavClientError:
      discard client.putResource("https://example.test/a", card,
        "text/calendar",
        WritePrecondition(kind: wpkReplace))
    expect DavClientError:
      discard client.putResource("https://example.test/a", card, "text/vcard",
        WritePrecondition(kind: wpkReplace))
    expect DavClientError: client.deleteResource("https://example.test/a", "bad\n")
    expect DavClientError: client.deleteResource("https://example.test/a", "W/\"weak\"")
    expect DavClientError: client.deleteResource("https://example.test/a", "unquoted")
    try:
      discard client.putResource("https://example.test/a", card, "text/vcard",
        WritePrecondition(kind: wpkCreate))
      check false
    except DavHttpError as error:
      check error.status == 412

suite "durable outgoing journal":
  test "applies, classifies and persists every outgoing outcome":
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "People")
    store.stageLocalUpsert("01-success", collection,
      "https://example.test/success.vcf",
      "text/vcard", card, "", create = true)
    store.stageLocalUpsert("02-conflict", collection,
      "https://example.test/conflict.vcf",
      "text/vcard", card, "\"old\"", create = false)
    store.stageLocalUpsert("03-auth", collection,
      "https://example.test/auth.vcf",
      "text/vcard", card, "", create = true)
    store.stageLocalUpsert("04-retry", collection,
      "https://example.test/retry.vcf",
      "text/vcard", card, "", create = true)
    store.stageLocalUpsert("05-fail", collection,
      "https://example.test/fail.vcf",
      "text/vcard", card, "", create = true)
    store.stageLocalUpsert("06-local-error", collection,
      "https://example.test/local-error.vcf",
      "text/vcard", card, "", create = true)
    let transport: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.url.contains("local-error"):
        raise newException(ValueError, "fixture local failure")
      if request.httpMethod == dmGet and request.url.contains("conflict"):
        var headers = initTable[string, string]()
        headers["ETag"] = "\"remote\""
        headers["Content-Type"] = "text/vcard"
        return DavHttpResponse(status: 200, headers: headers,
          body: card.replace("Ada", "Grace"), finalUrl: request.url)
      let status = if request.url.contains("conflict"): 412
        elif request.url.contains("auth"): 401
        elif request.url.contains("retry"): 500
        elif request.url.contains("fail"): 418
        else: 201
      var headers = initTable[string, string]()
      headers["ETag"] = "\"new\""
      DavHttpResponse(status: status, headers: headers, finalUrl: request.url)
    let client = newDavClient(transport)
    let clock = parse("2026-08-01T12:00:00Z", "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
    check store.processNextJournalEntry(client, clock).kind == jpkApplied
    check store.getResource(collection, "https://example.test/success.vcf").get.etag == "\"new\""
    check store.processNextJournalEntry(client, clock).kind == jpkConflict
    check store.processNextJournalEntry(client, clock).kind == jpkSuspended
    check store.processNextJournalEntry(client, clock).kind == jpkRetry
    check store.getJournalEntry("04-retry").get.nextAttemptAt > "2026-08-01T12:00:00"
    check store.processNextJournalEntry(client, clock).kind == jpkFailed
    check store.processNextJournalEntry(client, clock).kind == jpkFailed
    check store.processNextJournalEntry(client, clock).kind == jpkNoWork
    store.stageLocalUpsert("07-replace-success", collection,
      "https://example.test/replace-success.vcf", "text/vcard", card, "\"old\"",
      create = false)
    check store.processNextJournalEntry(client, clock).kind == jpkApplied

  test "retries transport failures and completes conditional deletes":
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "People")
    store.stageLocalUpsert("seed", collection, "https://example.test/a.vcf",
      "text/vcard",
      card, "\"one\"", create = false)
    store.markJournalComplete("seed")
    store.stageLocalDelete("delete", collection, "https://example.test/a.vcf", "\"one\"")
    let successful: DavTransport = proc(
        request: DavRequest): DavHttpResponse = response(204, "")
    check store.processNextJournalEntry(newDavClient(successful)).kind == jpkApplied
    check store.getJournalEntry("delete").get.state == jsComplete
    store.stageLocalUpsert("transport", collection,
      "https://example.test/b.vcf", "text/vcard",
      card, "", create = true)
    let unavailable: DavTransport = proc(request: DavRequest): DavHttpResponse =
      raise newException(DavTransportError, "offline")
    check store.processNextJournalEntry(newDavClient(unavailable),
        jitterPermille = 100).kind == jpkRetry
    check store.getJournalEntry("transport").get.state == jsRetry

  test "reconciles ambiguous remote success and supports conflict decisions":
    let baseCard = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    let localCard = baseCard.replace("Ada", "Local Ada")
    let remoteCard = baseCard.replace("Ada", "Remote Ada")
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "People")

    store.stageLocalUpsert("ambiguous-create", collection,
      "https://example.test/same.vcf",
      "text/vcard", localCard, "", create = true)
    let ambiguous: DavTransport = proc(request: DavRequest): DavHttpResponse =
      var headers = initTable[string, string]()
      headers["ETag"] = "\"remote-same\""
      headers["Content-Type"] = "text/vcard; charset=utf-8"
      if request.httpMethod == dmGet:
        return DavHttpResponse(status: 200, headers: headers,
          body: localCard.replace("\r\n", "\n"), finalUrl: request.url)
      DavHttpResponse(status: 412, headers: headers, finalUrl: request.url)
    check store.processNextJournalEntry(newDavClient(ambiguous)).kind == jpkApplied
    check store.getJournalEntry("ambiguous-create").get.state == jsComplete
    check store.getResource(collection, "https://example.test/same.vcf").get.etag == "\"remote-same\""

    store.putResource(ResourceRecord(collectionId: collection,
      href: "https://example.test/conflict-remote.vcf", etag: "\"base\"",
      contentType: "text/vcard", rawData: baseCard))
    store.stageLocalUpsert("keep-remote", collection,
      "https://example.test/conflict-remote.vcf", "text/vcard", localCard,
      "\"base\"",
      create = false)
    let divergent: DavTransport = proc(request: DavRequest): DavHttpResponse =
      var headers = initTable[string, string]()
      headers["ETag"] = "\"remote-new\""
      headers["Content-Type"] = "text/vcard"
      if request.httpMethod == dmGet:
        return DavHttpResponse(status: 200, headers: headers, body: remoteCard,
          finalUrl: request.url)
      DavHttpResponse(status: 412, headers: headers, finalUrl: request.url)
    check store.processNextJournalEntry(newDavClient(divergent)).kind == jpkConflict
    let conflict = store.getConflictForOperation("keep-remote")
    check conflict.isSome
    check conflict.get.baseData == baseCard
    check conflict.get.localData == localCard
    check conflict.get.remoteData == remoteCard
    store.resolveConflictKeepRemote("keep-remote")
    check store.getResource(collection, "https://example.test/conflict-remote.vcf").get.rawData == remoteCard
    check store.getJournalEntry("keep-remote").get.state == jsComplete
    check store.getConflictForOperation("keep-remote").get.resolved
    expect ValueError: store.resolveConflictKeepRemote("keep-remote")

    let mergeBase = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:merge\r\nFN:Ada\r\n" &
      "EMAIL:ada@example.test\r\nEND:VCARD\r\n"
    let mergeLocal = mergeBase.replace("FN:Ada", "FN:Grace")
    let mergeRemote = mergeBase.replace("EMAIL:ada@example.test",
      "EMAIL:ada@remote.test")
    store.putResource(ResourceRecord(collectionId: collection,
      href: "https://example.test/merge.vcf", etag: "\"base-merge\"",
      contentType: "text/vcard", rawData: mergeBase))
    store.stageLocalUpsert("merge-fields", collection,
      "https://example.test/merge.vcf", "text/vcard", mergeLocal,
      "\"base-merge\"", create = false)
    let mergeRemoteTransport: DavTransport = proc(
        request: DavRequest): DavHttpResponse =
      var headers = initTable[string, string]()
      headers["ETag"] = "\"remote-merge\""
      headers["Content-Type"] = "text/vcard"
      if request.httpMethod == dmGet:
        return DavHttpResponse(status: 200, headers: headers, body: mergeRemote,
          finalUrl: request.url)
      DavHttpResponse(status: 412, headers: headers, finalUrl: request.url)
    check store.processNextJournalEntry(newDavClient(
        mergeRemoteTransport)).kind ==
      jpkConflict
    let mergedOutcome = store.resolveConflictMerge("merge-fields")
    check mergedOutcome.conflicts.len == 0
    check mergedOutcome.document.contains("FN:Grace")
    check mergedOutcome.document.contains("EMAIL:ada@remote.test")
    check store.getJournalEntry("merge-fields").get.state == jsPending
    var mergedRequest: DavRequest
    let acceptMerge: DavTransport = proc(request: DavRequest): DavHttpResponse =
      mergedRequest = request
      var headers = initTable[string, string]()
      headers["ETag"] = "\"merged-fields\""
      DavHttpResponse(status: 204, headers: headers, finalUrl: request.url)
    check store.processNextJournalEntry(newDavClient(acceptMerge)).kind == jpkApplied
    check mergedRequest.body.contains("FN:Grace")
    check mergedRequest.body.contains("EMAIL:ada@remote.test")

    store.putResource(ResourceRecord(collectionId: collection,
      href: "https://example.test/conflict-local.vcf", etag: "\"base\"",
      contentType: "text/vcard", rawData: baseCard))
    store.stageLocalUpsert("retry-local", collection,
      "https://example.test/conflict-local.vcf", "text/vcard", localCard,
      "\"base\"",
      create = false)
    check store.processNextJournalEntry(newDavClient(divergent)).kind == jpkConflict
    store.resolveConflictRetryLocal("retry-local")
    let retry = store.getJournalEntry("retry-local").get
    check retry.state == jsPending
    check retry.operation == jokReplace
    check retry.baseEtag == "\"remote-new\""
    check retry.baseData == remoteCard
    var retriedRequest: DavRequest
    let acceptLocal: DavTransport = proc(request: DavRequest): DavHttpResponse =
      retriedRequest = request
      var headers = initTable[string, string]()
      headers["ETag"] = "\"merged\""
      DavHttpResponse(status: 204, headers: headers, finalUrl: request.url)
    check store.processNextJournalEntry(newDavClient(acceptLocal)).kind == jpkApplied
    check retriedRequest.headers["If-Match"] == "\"remote-new\""
    check store.getResource(collection, "https://example.test/conflict-local.vcf").get.etag == "\"merged\""
    expect ValueError: store.resolveConflictRetryLocal("missing")

  test "treats an already deleted remote resource as successful":
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "People")
    store.putResource(ResourceRecord(collectionId: collection,
      href: "https://example.test/deleted.vcf", etag: "\"base\"",
      contentType: "text/vcard", rawData: card))
    store.stageLocalDelete("ambiguous-delete", collection,
      "https://example.test/deleted.vcf",
      "\"base\"")
    let missing: DavTransport = proc(request: DavRequest): DavHttpResponse = response(
        404, "")
    check store.processNextJournalEntry(newDavClient(missing)).kind == jpkApplied
    check store.getJournalEntry("ambiguous-delete").get.state == jsComplete

  test "persists a remote deletion conflict without fabricating an empty resource":
    let baseCard = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    let localCard = baseCard.replace("Ada", "Local Ada")
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "People")
    let href = "https://example.test/remote-deleted.vcf"
    store.putResource(ResourceRecord(collectionId: collection, href: href,
      etag: "\"base\"",
      contentType: "text/vcard", rawData: baseCard))
    store.stageLocalUpsert("remote-delete-conflict", collection, href,
      "text/vcard", localCard,
      "\"base\"", create = false)
    let vanished: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmGet: response(404, "") else: response(412, "")
    check store.processNextJournalEntry(newDavClient(vanished)).kind == jpkConflict
    check store.getConflictForOperation(
        "remote-delete-conflict").get.remoteDeleted
    expect ValueError: store.resolveConflictRetryLocal("remote-delete-conflict")
    store.resolveConflictKeepRemote("remote-delete-conflict")
    let resource = store.getResource(collection, href).get
    check resource.deleted
    check resource.rawData == baseCard

  test "verifies successful writes that omit a strong ETag":
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "People")
    store.stageLocalUpsert("verify-success", collection,
      "https://example.test/a.vcf",
      "text/vcard", card, "", create = true)
    let verified: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmGet:
        var headers = initTable[string, string]()
        headers["ETag"] = "\"verified\""
        headers["Content-Type"] = "text/vcard"
        return DavHttpResponse(status: 200, headers: headers, body: card,
          finalUrl: request.url)
      response(201, "", request.url)
    check store.processNextJournalEntry(newDavClient(verified)).kind == jpkApplied
    check store.getResource(collection, "https://example.test/a.vcf").get.etag == "\"verified\""

    store.stageLocalUpsert("verify-failure", collection,
      "https://example.test/b.vcf",
      "text/vcard", card, "", create = true)
    let unverifiable: DavTransport = proc(
        request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmGet:
        var headers = initTable[string, string]()
        headers["ETag"] = "W/\"weak\""
        return DavHttpResponse(status: 200, headers: headers, body: card,
          finalUrl: request.url)
      response(201, "", request.url)
    check store.processNextJournalEntry(newDavClient(unverifiable)).kind == jpkFailed
    check store.getJournalEntry("verify-failure").get.state == jsFailed

  test "classifies failures while reconciling preconditions":
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "People")
    let clock = parse("2026-08-01T12:00:00Z", "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())

    proc stage(id: string) =
      store.stageLocalUpsert(id, collection, "https://example.test/" & id &
        ".vcf",
        "text/vcard", card, "", create = true)

    stage("vanished")
    let vanished: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmGet: response(404, "") else: response(412, "")
    check store.processNextJournalEntry(newDavClient(vanished), clock).kind == jpkRetry

    stage("auth-fetch")
    let authFetch: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmGet: response(401, "") else: response(412, "")
    check store.processNextJournalEntry(newDavClient(authFetch), clock).kind == jpkSuspended

    stage("server-fetch")
    let serverFetch: DavTransport = proc(request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmGet: response(503, "") else: response(412, "")
    check store.processNextJournalEntry(newDavClient(serverFetch),
        clock).kind == jpkRetry

    stage("offline-fetch")
    let offlineFetch: DavTransport = proc(
        request: DavRequest): DavHttpResponse =
      if request.httpMethod == dmGet:
        raise newException(DavTransportError, "offline during verification")
      response(412, "")
    check store.processNextJournalEntry(newDavClient(offlineFetch),
        clock).kind == jpkRetry
