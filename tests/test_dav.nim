# SPDX-License-Identifier: Apache-2.0
import std/[options, os, streams, strutils, tempfiles, unittest, xmlparser]
import UniDatabase
import UniDAV

suite "WebDAV XML":
  test "parses independent propstat status and sync token":
    let xml = """<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">
      <D:response><D:href>/cal/a.ics</D:href><D:propstat><D:prop>
      <D:getetag>&quot;abc&quot;</D:getetag></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
      <D:sync-token>https://example.test/token/2</D:sync-token></D:multistatus>"""
    let parsed = parseMultiStatus(xml)
    check parsed.syncToken == "https://example.test/token/2"
    check parsed.responses.len == 1
    check parsed.responses[0].status == 200
    check parsed.responses[0].property("getetag") == "\"abc\""

  test "builds escaped sync and multiget reports":
    check syncCollectionBody("a&b").contains("a&amp;b")
    let body = multigetBody("calendar", @["/a&b.ics"])
    check body.contains("calendar-multiget")
    check body.contains("/a&amp;b.ics")
    check xmlEscape("<\"'>") == "&lt;&quot;&apos;&gt;"
    check multigetBody("addressbook", @["/a.vcf"]).contains("addressbook-multiget")
    check propfindBody(@[(DavNamespace, "displayname"),
      (CalDavNamespace, "calendar-home-set"), (CardDavNamespace,
          "addressbook-home-set")])
      .contains("<A:addressbook-home-set/>")
    let calendarQuery = collectionQueryBody("calendar")
    check calendarQuery.contains("calendar-query")
    check calendarQuery.contains("comp-filter name=\"VCALENDAR\"")
    check calendarQuery.contains("calendar-data")
    let todoQuery = collectionQueryBody("calendar", component = "VTODO")
    check todoQuery.contains("comp-filter name=\"VTODO\"")
    discard parseXml(newStringStream(todoQuery))
    let journalQuery = collectionQueryBody("calendar", component = "VJOURNAL")
    check journalQuery.contains("comp-filter name=\"VJOURNAL\"")
    let addressQuery = collectionQueryBody("addressbook")
    check addressQuery.contains("addressbook-query")
    check addressQuery.contains("filter test=\"anyof\"")
    check addressQuery.contains("address-data")
    let emailQuery = collectionQueryBody("addressbook", property = "EMAIL")
    check emailQuery.contains("prop-filter name=\"EMAIL\"")
    let adaQuery = collectionQueryBody("addressbook", property = "FN",
      propertyText = "Ada & Grace")
    check adaQuery.contains("text-match")
    check adaQuery.contains("Ada &amp; Grace")
    expect DavXmlError: discard multigetBody("calendar", @[])
    expect DavXmlError:
      discard multigetBody("calendar", newSeq[string](MaxMultigetHrefs + 1))
    expect DavXmlError: discard multigetBody("unknown", @["/a.ics"])
    expect DavXmlError: discard collectionQueryBody("unknown")
    expect DavXmlError:
      discard collectionQueryBody("calendar", component = "VFREEBUSY")
    expect DavXmlError:
      discard collectionQueryBody("addressbook", component = "VTODO")
    expect DavXmlError:
      discard collectionQueryBody("addressbook", property = "EMAIL\"")
    expect DavXmlError:
      discard collectionQueryBody("calendar", property = "UID")
    expect DavXmlError:
      discard collectionQueryBody("addressbook", propertyText = "Ada\nGrace")

  test "rejects an unrelated XML root":
    expect DavXmlError: discard parseMultiStatus("<not-dav/>")
    expect DavXmlError: discard parseMultiStatus("<D:multistatus",
        maxBytes = 100)
    expect DavXmlError: discard parseMultiStatus(repeat("x", 11), maxBytes = 10)

suite "sync policy":
  test "walks through durable phases":
    var state = startSync("old-token")
    for phase in [spDiscover, spInventory, spDiff, spApplyRemote, spApplyLocal,
        spVerify, spCheckpoint]:
      check state.phase == phase
      state.advance()
    check state.phase == spComplete

  test "classifies HTTP outcomes":
    check decideHttpStatus(207) == rdContinue
    check decideHttpStatus(401) == rdSuspend
    check decideHttpStatus(412) == rdConflict
    check decideHttpStatus(429) == rdRetry
    check decideHttpStatus(418) == rdFail
    check decideHttpStatus(403, invalidSyncToken = true) == rdRefreshInventory
    check retryDelayMs(0) == 500
    check retryDelayMs(99) == 120_000
    check retryDelayMs(2, retryAfterMs = 999_999) == 300_000
    check retryDelayMs(-5, jitterPermille = -999) == 400
    check retryDelayMs(1, jitterPermille = 999) == 1_200

  test "does not advance terminal and retry phases":
    for phase in [spIdle, spComplete, spSuspended, spRetry, spFailed]:
      var state = SyncState(phase: phase)
      state.advance()
      check state.phase == phase

  test "accepts only strong RFC entity tags for write preconditions":
    check isStrongEtag("\"abc\"")
    check isStrongEtag("\"é-tag\"")
    check not isStrongEtag("W/\"abc\"")
    check not isStrongEtag("abc")
    check not isStrongEtag("\"bad\"quote\"")
    check not isStrongEtag("\"bad\x7f\"")
    check not isStrongEtag("")

suite "SQLite store":
  test "persists resources and advances checkpoints explicitly":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/cal/", "calendar", "Work")
    check store.getResource(collection, "/missing.ics").isNone
    store.putResource(ResourceRecord(collectionId: collection,
      href: "/cal/a.ics",
      etag: "\"1\"", contentType: "text/calendar",
      rawData: "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n"))
    let resource = store.getResource(collection, "/cal/a.ics")
    check resource.isSome
    check resource.get.etag == "\"1\""
    check store.syncToken(collection) == ""
    store.checkpoint(collection, "token-2")
    check store.syncToken(collection) == "token-2"

  test "stages idempotent local changes and advances durable journal states":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    check store.schemaVersion == CurrentSchemaVersion
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/cal/", "calendar", "Work")
    let calendar = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    store.stageLocalUpsert("op-create", collection, "/cal/a.ics",
      "text/calendar",
      calendar, "", create = true)
    store.stageLocalUpsert("op-create", collection, "/cal/a.ics",
      "text/calendar",
      calendar, "", create = true)
    let pending = store.nextJournalEntry()
    check pending.isSome
    check pending.get.operation == jokCreate
    check pending.get.state == jsPending
    store.markJournalRunning("op-create")
    check store.getJournalEntry("op-create").get.attempt == 1
    store.markJournalRetry("op-create", "temporary", "2099-01-01T00:00:00Z")
    check store.nextJournalEntry("2026-01-01T00:00:00Z").isNone
    check store.nextJournalEntry("2100-01-01T00:00:00Z").get.operationId == "op-create"
    store.markJournalConflict("op-create", "etag mismatch")
    check store.getJournalEntry("op-create").get.state == jsConflict
    store.markJournalComplete("op-create")
    check store.getJournalEntry("op-create").get.state == jsComplete
    store.stageLocalUpsert("op-recover", collection, "/cal/b.ics",
      "text/calendar",
      calendar, "", create = true)
    discard store.claimNextJournalEntry()
    store.recoverInterruptedOperations()
    check store.getJournalEntry("op-recover").get.state == jsRetry

  test "coalesces consecutive unclaimed edits without changing the safe base":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "Book")
    let original = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Original\r\nEND:VCARD\r\n"
    let first = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:First\r\nEND:VCARD\r\n"
    let second = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Second\r\nEND:VCARD\r\n"
    store.putResource(ResourceRecord(collectionId: collection,
      href: "/book/a.vcf",
      etag: "\"base\"", contentType: "text/vcard", rawData: original))
    check store.coalesceLocalUpsert("first", collection, "/book/a.vcf",
      "text/vcard",
      first, "\"base\"", false) == "first"
    check store.coalesceLocalUpsert("second", collection, "/book/a.vcf",
      "text/vcard",
      second, "\"base\"", false) == "first"
    check store.getJournalEntry("first").get.rawData == second
    check store.getJournalEntry("second").isNone
    check store.getResource(collection, "/book/a.vcf").get.rawData == second

  test "coalesces deletion over pending creates and replacements":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "Book")
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    discard store.coalesceLocalUpsert("create", collection, "/book/new.vcf",
      "text/vcard",
      card, "", true)
    check store.coalesceLocalDelete("delete-new", collection, "/book/new.vcf",
        "") == "create"
    check store.getJournalEntry("create").get.state == jsComplete
    check store.getResource(collection, "/book/new.vcf").get.deleted
    check store.coalesceLocalRestore("restore-create", collection,
      "/book/new.vcf",
      "text/vcard", card, "") == "restore-create"
    check store.getJournalEntry("restore-create").get.operation == jokCreate
    check not store.getResource(collection, "/book/new.vcf").get.deleted

    store.putResource(ResourceRecord(collectionId: collection,
      href: "/book/old.vcf",
      etag: "\"base\"", contentType: "text/vcard", rawData: card))
    discard store.coalesceLocalUpsert("replace", collection, "/book/old.vcf",
      "text/vcard",
      card.replace("Ada", "Grace"), "\"base\"", false)
    check store.coalesceLocalDelete("delete-old", collection, "/book/old.vcf",
      "\"base\"") == "replace"
    check store.getJournalEntry("replace").get.operation == jokDelete
    check store.getResource(collection, "/book/old.vcf").get.deleted
    let edited = card.replace("Ada", "Grace")
    check store.coalesceLocalRestore("ignored", collection, "/book/old.vcf",
      "text/vcard", edited, "\"base\"") == "replace"
    check store.getJournalEntry("replace").get.operation == jokReplace
    check store.getJournalEntry("replace").get.rawData == edited
    check not store.getResource(collection, "/book/old.vcf").get.deleted

    store.putResource(ResourceRecord(collectionId: collection,
      href: "/book/unchanged.vcf",
      etag: "\"same\"", contentType: "text/vcard", rawData: card))
    discard store.coalesceLocalDelete("delete-unchanged", collection,
      "/book/unchanged.vcf", "\"same\"")
    discard store.coalesceLocalRestore("ignored-again", collection,
      "/book/unchanged.vcf",
      "text/vcard", card, "\"same\"")
    check store.getJournalEntry("delete-unchanged").get.state == jsComplete
    check not store.getResource(collection, "/book/unchanged.vcf").get.deleted
    expect LocalChangesPendingError:
      discard store.coalesceLocalRestore("late", collection,
        "/book/missing.vcf",
        "text/vcard", card, "\"same\"")

  test "claims outgoing work only for the requested account":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let firstAccount = store.addAccount("First", "https://first.example.test/")
    let secondAccount = store.addAccount("Second", "https://second.example.test/")
    let firstCollection = store.addCollection(firstAccount, "/first/",
        "addressbook", "First")
    let secondCollection = store.addCollection(secondAccount, "/second/",
        "addressbook", "Second")
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    store.stageLocalUpsert("first-op", firstCollection, "/first/a.vcf",
      "text/vcard",
      card, "", create = true)
    store.stageLocalUpsert("second-op", secondCollection, "/second/a.vcf",
      "text/vcard",
      card, "", create = true)
    check store.claimNextJournalEntryForAccount(
        secondAccount).get.operationId == "second-op"
    check store.getJournalEntry("first-op").get.state == jsPending
    check store.nextJournalEntryForAccount(firstAccount).get.operationId == "first-op"

  test "rolls back a reused operation ID and stages tombstones":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let account = store.addAccount("Test", "https://example.test/")
    let collection = store.addCollection(account, "/book/", "addressbook", "People")
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    store.stageLocalUpsert("op-1", collection, "/book/a.vcf", "text/vcard",
      card, "\"e1\"",
      create = false)
    expect ValueError:
      store.stageLocalUpsert("op-1", collection, "/book/a.vcf", "text/vcard",
        card.replace("Ada", "Grace"), "\"e1\"",
        create = false)
    check store.getResource(collection, "/book/a.vcf").get.rawData == card
    store.stageLocalDelete("op-delete", collection, "/book/a.vcf", "\"e1\"")
    check store.getResource(collection, "/book/a.vcf").get.deleted
    check store.getJournalEntry("op-delete").get.operation == jokDelete
    expect ValueError: store.markJournalRunning("missing")
    expect ValueError: store.markJournalRetry("op-delete", "", "later")
    expect ValueError:
      store.stageLocalDelete("bad-delete", collection, "/book/a.vcf", "")
    expect ValueError:
      store.stageLocalUpsert("bad-upsert", collection, "/book/b.vcf",
        "text/vcard", "broken", "",
        create = true)
    expect ValueError:
      store.stageLocalUpsert("bad-type", collection, "/book/b.vcf",
        "application/json", card, "",
        create = true)
    store.putResource(ResourceRecord(collectionId: collection,
      href: "/book/existing.vcf",
      etag: "\"existing\"", contentType: "text/vcard", rawData: card))
    expect ValueError:
      store.stageLocalUpsert("duplicate-create", collection,
        "/book/existing.vcf", "text/vcard",
        card, "", create = true)
    expect ValueError:
      store.stageLocalUpsert("stale-replace", collection, "/book/a.vcf",
        "text/vcard", card,
        "\"stale\"", create = false)

  test "persists discovered accounts atomically without secret fields":
    let store = openSqliteStore(":memory:")
    defer: store.close()
    let accountId = store.addDiscoveredAccount("Cloud",
      "https://dav.example.test/", [
      CollectionSeed(href: "https://dav.example.test/cal/", kind: "calendar",
        displayName: "Calendar"),
      CollectionSeed(href: "https://dav.example.test/book/",
        kind: "addressbook",
        displayName: "Contacts")])
    let accounts = store.listAccounts()
    check accounts.len == 1
    check accounts[0].id == accountId
    check accounts[0].state == "active"
    check store.getAccount(accountId).get.baseUrl == "https://dav.example.test/"
    let collections = store.listCollections(accountId)
    check collections.len == 2
    check collections[0].kind == "addressbook"
    check collections[1].kind == "calendar"
    store.setAccountState(accountId, "syncing")
    check store.getAccount(accountId).get.state == "syncing"
    expect ValueError: store.setAccountState(accountId, "unknown")

    expect ValueError:
      discard store.addDiscoveredAccount("Broken", "https://bad.example.test/", [
        CollectionSeed(href: "https://bad.example.test/cal/", kind: "calendar",
          displayName: "Calendar"),
        CollectionSeed(href: "", kind: "addressbook", displayName: "Broken")])
    check store.listAccounts().len == 1

  test "migrates version one atomically and rejects future schemas":
    let legacy = createTempFile("unidav-v1-", ".sqlite")
    legacy.cfile.close()
    defer:
      if fileExists(legacy.path): removeFile(legacy.path)
    var raw = openSqlite(legacy.path)
    raw.execute("CREATE TABLE schema_meta (version INTEGER NOT NULL)")
    raw.execute("INSERT INTO schema_meta(version) VALUES (1)")
    raw.close
    let migrated = openSqliteStore(legacy.path)
    check migrated.schemaVersion == CurrentSchemaVersion
    migrated.close()

    let future = createTempFile("unidav-future-", ".sqlite")
    future.cfile.close()
    defer:
      if fileExists(future.path): removeFile(future.path)
    raw = openSqlite(future.path)
    raw.execute("CREATE TABLE schema_meta (version INTEGER NOT NULL)")
    raw.execute("INSERT INTO schema_meta(version) VALUES (999)")
    raw.close
    expect ValueError: discard openSqliteStore(future.path)
