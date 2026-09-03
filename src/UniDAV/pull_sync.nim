# SPDX-License-Identifier: Apache-2.0
import std/[sets, strutils, tables, uri]
import client, davxml, document, sqlite_store, sync

const DefaultMultigetBatchSize* = 100

type
  PullSyncError* = object of CatchableError
  PullSyncResult* = object
    fullInventory*: bool
    queryFallback*: bool
    moreAvailable*: bool
    fetched*: int
    deleted*: int
    syncToken*: string

proc isInvalidSyncToken(error: ref DavHttpError): bool =
  error.status == 403 and error.responseBody.toLowerAscii.contains("valid-sync-token")

proc canonicalHref(collectionUrl, href: string): string =
  let collection = parseUri(collectionUrl)
  let resolved = parseUri(resolveUrl(collectionUrl, href))
  proc effectivePort(value: Uri): string =
    if value.port.len > 0: value.port
    elif value.scheme.cmpIgnoreCase("https") == 0: "443"
    elif value.scheme.cmpIgnoreCase("http") == 0: "80"
    else: ""
  if collection.scheme notin ["http", "https"] or
      resolved.scheme.cmpIgnoreCase(collection.scheme) != 0 or
      resolved.hostname.cmpIgnoreCase(collection.hostname) != 0 or
      resolved.effectivePort != collection.effectivePort or
      resolved.query.len > 0 or resolved.anchor.len > 0:
    raise newException(PullSyncError, "DAV href escapes its collection origin")
  let basePath = if collection.path.endsWith(
      "/"): collection.path else: collection.path & "/"
  if resolved.path == collection.path or resolved.path == basePath:
    return $resolved
  if not resolved.path.startsWith(basePath):
    raise newException(PullSyncError, "DAV href escapes its collection path")
  let member = resolved.path[basePath.len .. ^1]
  let lowered = member.toLowerAscii
  if member.len == 0 or member.contains('/') or member.contains('\\') or
      lowered.contains("%2f") or lowered.contains("%5c"):
    raise newException(PullSyncError, "DAV href is not a direct collection member")
  $resolved

proc resourceData(response: DavResponse; kind: DavServiceKind): string =
  response.property(if kind == dskCalendar: "calendar-data" else: "address-data")

proc validatedUpsert(response: DavResponse; collectionUrl: string;
                     kind: DavServiceKind): RemoteChange =
  let rawData = response.resourceData(kind)
  let expectedKind = if kind == dskCalendar: dkICalendar else: dkVCard
  if rawData.len == 0 or detectKind(rawData) != expectedKind or not isValid(rawData):
    raise newException(PullSyncError, "DAV report returned invalid resource data")
  let remoteEtag = response.property("getetag").strip
  if remoteEtag.len == 0:
    raise newException(PullSyncError, "DAV report resource omitted its ETag")
  RemoteChange(kind: rckUpsert, href: canonicalHref(collectionUrl,
      response.href),
    etag: remoteEtag,
    contentType: if kind == dskCalendar: "text/calendar" else: "text/vcard",
    rawData: rawData)

proc fetchChanges(client: DavClient; collectionUrl: string; kind: DavServiceKind;
                  hrefs: seq[string]; batchSize: int;
                  cancellation: CancellationToken): seq[RemoteChange] =
  if batchSize < 1 or batchSize > 1000:
    raise newException(ValueError, "DAV multiget batch size must be between 1 and 1000")
  var offset = 0
  while offset < hrefs.len:
    cancellation.checkCancelled()
    let last = min(offset + batchSize, hrefs.len)
    let batch = client.multiget(collectionUrl, kind, hrefs[offset ..< last])
    var received = initHashSet[string]()
    for response in batch.responses:
      cancellation.checkCancelled()
      let href = canonicalHref(collectionUrl, response.href)
      if href notin hrefs[offset ..< last]:
        raise newException(PullSyncError, "DAV multiget returned an unrequested href")
      if href in received:
        raise newException(PullSyncError, "DAV multiget returned a duplicate href")
      received.incl(href)
      if response.status == 404:
        result.add(RemoteChange(kind: rckDelete, href: href))
      elif response.status in 200..299:
        result.add(response.validatedUpsert(collectionUrl, kind))
      else:
        raise newException(PullSyncError, "DAV multiget returned a non-success status")
    if received.len != last - offset:
      raise newException(PullSyncError, "DAV multiget omitted a requested href")
    offset = last

proc pullCollection*(store: SqliteStore; client: DavClient; collectionId: int64;
                     collectionUrl: string; kind: DavServiceKind;
                     batchSize = DefaultMultigetBatchSize;
                     cancellation: CancellationToken = nil): PullSyncResult =
  cancellation.checkCancelled()
  var listing: MultiStatus
  var fullInventory = store.syncToken(collectionId).len == 0
  var queryFallback = false
  if not fullInventory:
    try:
      listing = client.syncCollection(collectionUrl, store.syncToken(collectionId))
    except DavHttpError as error:
      if error.isInvalidSyncToken:
        fullInventory = true
      elif error.status in [405, 501]:
        fullInventory = true
        queryFallback = true
      else:
        raise
  if fullInventory:
    if queryFallback:
      listing = client.queryCollection(collectionUrl, kind)
    else:
      listing = client.inventoryCollection(collectionUrl)
      if listing.syncToken.len == 0:
        listing = client.queryCollection(collectionUrl, kind)
        queryFallback = true

  cancellation.checkCancelled()

  if listing.syncToken.len == 0 and not queryFallback:
    raise newException(PullSyncError, "DAV response omitted the next sync token")

  var changes: seq[RemoteChange]
  var fetchHrefs: seq[string]
  var queryFetched = 0
  var moreAvailable = false
  var remoteHrefs = initHashSet[string]()
  var localEtags = initTable[string, string]()
  for item in store.listResources(collectionId): localEtags[
      item.href] = item.etag

  for response in listing.responses:
    cancellation.checkCancelled()
    let href = canonicalHref(collectionUrl, response.href)
    if href == collectionUrl or response.hasPropertyChild("resourcetype", "collection"):
      if response.status == 507: moreAvailable = true
      continue
    if href in remoteHrefs:
      raise newException(PullSyncError, "DAV listing returned a duplicate href")
    remoteHrefs.incl(href)
    if response.status == 404:
      changes.add(RemoteChange(kind: rckDelete, href: href))
    elif response.status in 200..299:
      if queryFallback:
        let change = response.validatedUpsert(collectionUrl, kind)
        if not localEtags.hasKey(href) or localEtags[href] != change.etag:
          changes.add(change)
          inc queryFetched
      else:
        let remoteEtag = response.property("getetag").strip
        if remoteEtag.len == 0:
          raise newException(PullSyncError, "DAV listing resource omitted its ETag")
        if not localEtags.hasKey(href) or localEtags[href] != remoteEtag:
          fetchHrefs.add(href)
    else:
      raise newException(PullSyncError, "DAV listing returned a non-success status")

  if fullInventory:
    for local in store.listResources(collectionId):
      if local.href notin remoteHrefs:
        changes.add(RemoteChange(kind: rckDelete, href: local.href,
            etag: local.etag))

  let fetched = client.fetchChanges(collectionUrl, kind, fetchHrefs, batchSize,
    cancellation)
  changes.add(fetched)
  cancellation.checkCancelled()
  store.applyRemoteBatch(collectionId, changes, listing.syncToken)
  result = PullSyncResult(fullInventory: fullInventory,
    queryFallback: queryFallback,
    moreAvailable: moreAvailable, fetched: fetched.len + queryFetched,
    syncToken: listing.syncToken)
  for change in changes:
    if change.kind == rckDelete: inc result.deleted

# Keep source mapping stable for gcov-generated exception branches.
# End of module.
