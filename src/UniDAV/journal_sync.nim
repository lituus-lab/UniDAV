# SPDX-License-Identifier: Apache-2.0
import std/[options, times]
import client, document, etag, sqlite_store, sync

type
  JournalProcessKind* = enum jpkNoWork, jpkApplied, jpkRetry, jpkConflict,
    jpkSuspended, jpkFailed
  JournalProcessResult* = object
    kind*: JournalProcessKind
    operationId*: string
    message*: string

proc timestamp(value: DateTime): string =
  value.utc.format("yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'")

proc documentsEquivalent(first, second: string): bool

proc persistSuccessfulPut(store: SqliteStore; client: DavClient; entry: JournalEntry;
                          payload: ResourcePayload) =
  var verified = payload
  if not isStrongEtag(verified.etag):
    verified = client.fetchResource(entry.href)
    if not documentsEquivalent(entry.rawData, verified.body) or
        not isStrongEtag(verified.etag):
      raise newException(DavClientError,
        "server accepted DAV write but did not return a verifiable strong ETag")
  store.completeJournalPut(entry.operationId,
    ResourceRecord(collectionId: entry.collectionId, href: entry.href,
      etag: verified.etag, contentType: entry.contentType,
      rawData: entry.rawData, deleted: false))

proc documentsEquivalent(first, second: string): bool =
  if first == second: return true
  try:
    normalizeDocument(first) == normalizeDocument(second)
  except CatchableError:
    false

proc scheduleRetry(store: SqliteStore; entry: JournalEntry; message: string;
                   currentTime: DateTime;
                       jitterPermille: int): JournalProcessResult =
  let delay = retryDelayMs(entry.attempt, jitterPermille = jitterPermille)
  store.markJournalRetry(entry.operationId, message,
    timestamp(currentTime + initDuration(milliseconds = delay)))
  JournalProcessResult(kind: jpkRetry, operationId: entry.operationId,
      message: message)

proc reconcilePrecondition(store: SqliteStore; client: DavClient; entry: JournalEntry;
                           reason: string; currentTime: DateTime;
                           jitterPermille: int): JournalProcessResult =
  result.operationId = entry.operationId
  result.message = reason
  try:
    let remote = client.fetchResource(entry.href)
    let sameDocument = documentsEquivalent(entry.rawData, remote.body)
    if entry.operation != jokDelete and sameDocument and
        isStrongEtag(remote.etag):
      store.completeJournalPut(entry.operationId,
        ResourceRecord(collectionId: entry.collectionId, href: entry.href,
          etag: remote.etag, contentType: entry.contentType,
          rawData: entry.rawData,
          deleted: false))
      result.kind = jpkApplied
    else:
      store.recordJournalConflict(entry, remote.body, remote.contentType,
          remote.etag, reason)
      result.kind = jpkConflict
  except DavHttpError as fetchError:
    if fetchError.status == 404 and entry.operation == jokDelete:
      store.completeJournalDelete(entry.operationId)
      result.kind = jpkApplied
    elif fetchError.status == 404 and entry.operation == jokReplace:
      store.recordJournalConflict(entry, "", "", "",
        "remote resource was deleted",
        remoteDeleted = true)
      result.kind = jpkConflict
      result.message = "remote resource was deleted"
    elif fetchError.status == 404 and entry.operation == jokCreate:
      return scheduleRetry(store, entry,
        "remote resource disappeared during verification",
        currentTime, jitterPermille)
    else:
      case decideHttpStatus(fetchError.status)
      of rdSuspend:
        store.markJournalSuspended(entry.operationId, fetchError.msg)
        result.kind = jpkSuspended
      of rdRetry, rdConflict, rdRefreshInventory:
        return scheduleRetry(store, entry, fetchError.msg, currentTime, jitterPermille)
      else:
        store.markJournalFailed(entry.operationId, fetchError.msg)
        result.kind = jpkFailed
      result.message = fetchError.msg
  except DavTransportError as fetchError:
    return scheduleRetry(store, entry, fetchError.msg, currentTime, jitterPermille)
  except CatchableError as fetchError:
    store.markJournalFailed(entry.operationId, fetchError.msg)
    result.kind = jpkFailed
    result.message = fetchError.msg

proc processNextJournalEntry*(store: SqliteStore; client: DavClient;
                              currentTime = now().utc; jitterPermille = 0;
                              accountId = 0'i64): JournalProcessResult =
  let claimed = if accountId > 0:
      store.claimNextJournalEntryForAccount(accountId, timestamp(currentTime))
    else:
      store.claimNextJournalEntry(timestamp(currentTime))
  if claimed.isNone: return JournalProcessResult(kind: jpkNoWork)
  let entry = claimed.get
  result.operationId = entry.operationId
  try:
    case entry.operation
    of jokCreate:
      let payload = client.putResource(entry.href, entry.rawData,
        entry.contentType,
        WritePrecondition(kind: wpkCreate))
      store.persistSuccessfulPut(client, entry, payload)
    of jokReplace:
      let payload = client.putResource(entry.href, entry.rawData,
        entry.contentType,
        WritePrecondition(kind: wpkReplace, etag: entry.baseEtag))
      store.persistSuccessfulPut(client, entry, payload)
    of jokDelete:
      client.deleteResource(entry.href, entry.baseEtag)
      store.completeJournalDelete(entry.operationId)
    result.kind = jpkApplied
  except DavHttpError as error:
    result.message = error.msg
    if error.status == 404 and entry.operation == jokDelete:
      store.completeJournalDelete(entry.operationId)
      result.kind = jpkApplied
    elif decideHttpStatus(error.status) == rdConflict:
      return reconcilePrecondition(store, client, entry, error.msg, currentTime, jitterPermille)
    else:
      case decideHttpStatus(error.status)
      of rdSuspend:
        store.markJournalSuspended(entry.operationId, error.msg)
        result.kind = jpkSuspended
      of rdRetry:
        return scheduleRetry(store, entry, error.msg, currentTime, jitterPermille)
      else:
        store.markJournalFailed(entry.operationId, error.msg)
        result.kind = jpkFailed
  except DavTransportError as error:
    return scheduleRetry(store, entry, error.msg, currentTime, jitterPermille)
  except CatchableError as error:
    result.message = error.msg
    store.markJournalFailed(entry.operationId, error.msg)
    result.kind = jpkFailed

# Keep source mapping stable for gcov-generated exception branches.
# End of module.
