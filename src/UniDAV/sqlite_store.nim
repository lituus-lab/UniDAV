# SPDX-License-Identifier: Apache-2.0
import db_connector/db_sqlite
import std/[options, strutils, times]
import document, editing
import etag

const CurrentSchemaVersion* = 3

type
  AccountRecord* = object
    id*: int64
    name*: string
    baseUrl*: string
    state*: string
    createdAt*: string
  CollectionRecord* = object
    id*: int64
    accountId*: int64
    href*: string
    kind*: string
    displayName*: string
    syncToken*: string
  CollectionSeed* = object
    href*: string
    kind*: string
    displayName*: string
  ResourceRecord* = object
    collectionId*: int64
    href*: string
    etag*: string
    contentType*: string
    rawData*: string
    deleted*: bool
  SqliteStore* = ref object
    db*: DbConn
  LocalChangesPendingError* = object of CatchableError
    href*: string
  RemoteChangeKind* = enum rckUpsert, rckDelete
  RemoteChange* = object
    kind*: RemoteChangeKind
    href*: string
    etag*: string
    contentType*: string
    rawData*: string
  JournalOperationKind* = enum jokCreate, jokReplace, jokDelete
  JournalState* = enum jsPending, jsRunning, jsRetry, jsConflict, jsSuspended,
    jsFailed, jsComplete
  JournalEntry* = object
    operationId*: string
    collectionId*: int64
    operation*: JournalOperationKind
    href*: string
    state*: JournalState
    contentType*: string
    rawData*: string
    baseEtag*: string
    baseData*: string
    attempt*: int
    lastError*: string
    nextAttemptAt*: string
  ConflictRecord* = object
    id*: int64
    operationId*: string
    collectionId*: int64
    href*: string
    localData*: string
    remoteData*: string
    remoteContentType*: string
    baseData*: string
    remoteEtag*: string
    remoteDeleted*: bool
    resolved*: bool

proc operationName(operation: JournalOperationKind): string =
  case operation
  of jokCreate: "create"
  of jokReplace: "replace"
  of jokDelete: "delete"

proc parseOperation(value: string): JournalOperationKind =
  case value
  of "create": jokCreate
  of "replace": jokReplace
  of "delete": jokDelete
  else: raise newException(ValueError, "unknown journal operation: " & value)

proc stateName(state: JournalState): string =
  case state
  of jsPending: "pending"
  of jsRunning: "running"
  of jsRetry: "retry"
  of jsConflict: "conflict"
  of jsSuspended: "suspended"
  of jsFailed: "failed"
  of jsComplete: "complete"

proc parseState(value: string): JournalState =
  case value
  of "pending": jsPending
  of "running": jsRunning
  of "retry": jsRetry
  of "conflict": jsConflict
  of "suspended": jsSuspended
  of "failed": jsFailed
  of "complete": jsComplete
  else: raise newException(ValueError, "unknown journal state: " & value)

proc migrate(db: DbConn) =
  db.exec(sql"PRAGMA foreign_keys = ON")
  db.exec(sql"PRAGMA busy_timeout = 5000")
  discard db.getValue(sql"PRAGMA journal_mode = WAL")
  db.exec(sql"CREATE TABLE IF NOT EXISTS schema_meta (version INTEGER NOT NULL)")
  if db.getValue(sql"SELECT COUNT(*) FROM schema_meta") == "0":
    db.exec(sql"INSERT INTO schema_meta(version) VALUES (1)")
  let schemaVersion = parseInt(db.getValue(
      sql"SELECT version FROM schema_meta LIMIT 1"))
  if schemaVersion > CurrentSchemaVersion:
    raise newException(ValueError, "database schema is newer than this UniDAV build")
  db.exec(sql"""CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY, name TEXT NOT NULL, base_url TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL)""")
  db.exec(sql"""CREATE TABLE IF NOT EXISTS collections (
    id INTEGER PRIMARY KEY, account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    href TEXT NOT NULL, kind TEXT NOT NULL, display_name TEXT NOT NULL DEFAULT '',
    sync_token TEXT NOT NULL DEFAULT '', UNIQUE(account_id, href))""")
  db.exec(sql"""CREATE TABLE IF NOT EXISTS resources (
    id INTEGER PRIMARY KEY, collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    href TEXT NOT NULL, etag TEXT NOT NULL DEFAULT '', content_type TEXT NOT NULL DEFAULT '',
    raw_data TEXT NOT NULL DEFAULT '', deleted INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL, UNIQUE(collection_id, href))""")
  db.exec(sql"""CREATE TABLE IF NOT EXISTS sync_journal (
    operation_id TEXT PRIMARY KEY, collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    operation TEXT NOT NULL, href TEXT NOT NULL, state TEXT NOT NULL,
    attempt INTEGER NOT NULL DEFAULT 0, last_error TEXT NOT NULL DEFAULT '')""")
  db.exec(sql"""CREATE TABLE IF NOT EXISTS conflicts (
    id INTEGER PRIMARY KEY, collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    href TEXT NOT NULL, local_data TEXT NOT NULL, remote_data TEXT NOT NULL,
    base_data TEXT NOT NULL DEFAULT '', resolved INTEGER NOT NULL DEFAULT 0)""")
  if schemaVersion < 2:
    db.exec(sql"BEGIN IMMEDIATE")
    try:
      db.exec(sql"ALTER TABLE sync_journal ADD COLUMN content_type TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE sync_journal ADD COLUMN raw_data TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE sync_journal ADD COLUMN base_etag TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE sync_journal ADD COLUMN next_attempt_at TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE sync_journal ADD COLUMN created_at TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE sync_journal ADD COLUMN updated_at TEXT NOT NULL DEFAULT ''")
      db.exec(sql"UPDATE schema_meta SET version=2")
      db.exec(sql"COMMIT")
    except CatchableError:
      db.exec(sql"ROLLBACK")
      raise
  if schemaVersion < 3:
    db.exec(sql"BEGIN IMMEDIATE")
    try:
      db.exec(sql"ALTER TABLE sync_journal ADD COLUMN base_data TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE conflicts ADD COLUMN operation_id TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE conflicts ADD COLUMN remote_etag TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE conflicts ADD COLUMN remote_content_type TEXT NOT NULL DEFAULT ''")
      db.exec(sql"ALTER TABLE conflicts ADD COLUMN remote_deleted INTEGER NOT NULL DEFAULT 0")
      db.exec(sql"CREATE UNIQUE INDEX IF NOT EXISTS conflicts_operation_id ON conflicts(operation_id) WHERE operation_id<>''")
      db.exec(sql"UPDATE schema_meta SET version=3")
      db.exec(sql"COMMIT")
    except CatchableError:
      db.exec(sql"ROLLBACK")
      raise

proc openSqliteStore*(path: string): SqliteStore =
  new(result)
  result.db = open(path, "", "", "")
  try:
    migrate(result.db)
  except CatchableError:
    result.db.close()
    raise

proc close*(store: SqliteStore) =
  if not store.isNil: store.db.close()

proc addAccount*(store: SqliteStore; name, baseUrl: string): int64 =
  if name.strip.len == 0: raise newException(ValueError, "account name is required")
  if baseUrl.strip.len == 0: raise newException(ValueError, "account base URL is required")
  store.db.insertID(sql"INSERT INTO accounts(name, base_url, created_at) VALUES (?, ?, ?)",
    name.strip, baseUrl.strip, $now().utc)

proc addCollection*(store: SqliteStore; accountId: int64; href, kind,
    displayName: string): int64 =
  if accountId <= 0: raise newException(ValueError, "collection account ID is invalid")
  if href.strip.len == 0: raise newException(ValueError, "collection href is required")
  if kind notin ["calendar", "addressbook"]:
    raise newException(ValueError, "collection kind is invalid")
  store.db.insertID(sql"INSERT INTO collections(account_id, href, kind, display_name) VALUES (?, ?, ?, ?)",
    accountId, href.strip, kind, displayName.strip)

proc addDiscoveredAccount*(store: SqliteStore; name, baseUrl: string;
                           collections: openArray[CollectionSeed]): int64 =
  ## Persists a fully discovered account atomically. Secrets are deliberately absent.
  if collections.len == 0:
    raise newException(ValueError, "discovered account has no collections")
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    result = store.addAccount(name, baseUrl)
    for collection in collections:
      discard store.addCollection(result, collection.href, collection.kind,
        collection.displayName)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc listAccounts*(store: SqliteStore): seq[AccountRecord] =
  for row in store.db.fastRows(sql"SELECT id, name, base_url, state, created_at FROM accounts ORDER BY id"):
    result.add(AccountRecord(id: parseBiggestInt(row[0]).int64, name: row[1],
      baseUrl: row[2], state: row[3], createdAt: row[4]))

proc getAccount*(store: SqliteStore; accountId: int64): Option[AccountRecord] =
  let row = store.db.getRow(sql"SELECT name, base_url, state, created_at FROM accounts WHERE id=?",
    accountId)
  if row[0].len == 0: return none(AccountRecord)
  some(AccountRecord(id: accountId, name: row[0], baseUrl: row[1], state: row[2],
    createdAt: row[3]))

proc setAccountState*(store: SqliteStore; accountId: int64; state: string) =
  if state notin ["active", "syncing", "suspended", "error"]:
    raise newException(ValueError, "account state is invalid")
  store.db.exec(sql"UPDATE accounts SET state=? WHERE id=?", state, accountId)

proc listCollections*(store: SqliteStore; accountId: int64): seq[
    CollectionRecord] =
  for row in store.db.fastRows(sql"""SELECT id, href, kind, display_name, sync_token
      FROM collections WHERE account_id=? ORDER BY kind, href""", accountId):
    result.add(CollectionRecord(id: parseBiggestInt(row[0]).int64,
        accountId: accountId,
      href: row[1], kind: row[2], displayName: row[3], syncToken: row[4]))

proc activeJournalCountForAccount*(store: SqliteStore; accountId: int64): int =
  parseInt(store.db.getValue(sql"""SELECT COUNT(*) FROM sync_journal j
    JOIN collections c ON c.id=j.collection_id
    WHERE c.account_id=? AND j.state NOT IN ('complete', 'failed')""", accountId))

proc putResource*(store: SqliteStore; resource: ResourceRecord) =
  store.db.exec(sql"""INSERT INTO resources(collection_id, href, etag, content_type, raw_data, deleted, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(collection_id, href) DO UPDATE SET
    etag=excluded.etag, content_type=excluded.content_type, raw_data=excluded.raw_data,
    deleted=excluded.deleted, updated_at=excluded.updated_at""",
    resource.collectionId,
    resource.href, resource.etag, resource.contentType, resource.rawData,
    ord(resource.deleted), $now().utc)

proc getResource*(store: SqliteStore; collectionId: int64;
    href: string): Option[ResourceRecord] =
  let row = store.db.getRow(sql"SELECT etag, content_type, raw_data, deleted FROM resources WHERE collection_id=? AND href=?",
    collectionId, href)
  if row[0].len == 0 and row[1].len == 0 and row[2].len == 0 and row[3].len ==
      0: return none(ResourceRecord)
  some(ResourceRecord(collectionId: collectionId, href: href, etag: row[0],
    contentType: row[1], rawData: row[2], deleted: row[3] == "1"))

proc listResources*(store: SqliteStore; collectionId: int64;
                    includeDeleted = false): seq[ResourceRecord] =
  let query = if includeDeleted:
      sql"SELECT href, etag, content_type, raw_data, deleted FROM resources WHERE collection_id=? ORDER BY href"
    else:
      sql"SELECT href, etag, content_type, raw_data, deleted FROM resources WHERE collection_id=? AND deleted=0 ORDER BY href"
  for row in store.db.fastRows(query, collectionId):
    result.add(ResourceRecord(collectionId: collectionId, href: row[0],
        etag: row[1],
      contentType: row[2], rawData: row[3], deleted: row[4] == "1"))

proc checkpoint*(store: SqliteStore; collectionId: int64; syncToken: string) =
  store.db.exec(sql"UPDATE collections SET sync_token=? WHERE id=?", syncToken, collectionId)

proc syncToken*(store: SqliteStore; collectionId: int64): string =
  store.db.getValue(sql"SELECT sync_token FROM collections WHERE id=?", collectionId)

proc schemaVersion*(store: SqliteStore): int =
  parseInt(store.db.getValue(sql"SELECT version FROM schema_meta LIMIT 1"))

proc applyRemoteBatch*(store: SqliteStore; collectionId: int64;
                       changes: openArray[RemoteChange]; newSyncToken: string) =
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    for change in changes:
      let active = store.db.getValue(sql"""SELECT COUNT(*) FROM sync_journal
        WHERE collection_id=? AND href=? AND state NOT IN ('complete', 'failed')""",
        collectionId, change.href)
      if active != "0":
        var error = newException(LocalChangesPendingError,
          "remote DAV change intersects an active local operation")
        error.href = change.href
        raise error
      store.putResource(ResourceRecord(collectionId: collectionId,
        href: change.href,
        etag: change.etag, contentType: change.contentType,
        rawData: change.rawData,
        deleted: change.kind == rckDelete))
    store.checkpoint(collectionId, newSyncToken)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc journalEntry(row: Row): JournalEntry =
  JournalEntry(operationId: row[0], collectionId: parseBiggestInt(row[1]).int64,
    operation: parseOperation(row[2]), href: row[3], state: parseState(row[4]),
    contentType: row[5], rawData: row[6], baseEtag: row[7], baseData: row[8],
    attempt: parseInt(row[9]), lastError: row[10], nextAttemptAt: row[11])

proc getJournalEntry*(store: SqliteStore; operationId: string): Option[JournalEntry] =
  let row = store.db.getRow(sql"""SELECT operation_id, collection_id, operation, href, state,
    content_type, raw_data, base_etag, base_data, attempt, last_error, next_attempt_at
    FROM sync_journal WHERE operation_id=?""", operationId)
  if row[0].len == 0: return none(JournalEntry)
  some(journalEntry(row))

proc pendingJournalEntryForResource*(store: SqliteStore; collectionId: int64;
                                     href: string): Option[JournalEntry] =
  let row = store.db.getRow(sql"""SELECT operation_id, collection_id, operation, href, state,
    content_type, raw_data, base_etag, base_data, attempt, last_error, next_attempt_at
    FROM sync_journal WHERE collection_id=? AND href=? AND state IN ('pending', 'retry')
    ORDER BY created_at, operation_id LIMIT 1""", collectionId, href)
  if row[0].len == 0: return none(JournalEntry)
  some(journalEntry(row))

proc enqueueOperation(store: SqliteStore; entry: JournalEntry) =
  if entry.operationId.len == 0 or entry.href.len == 0 or
      entry.operationId.contains({'\r', '\n'}) or entry.href.contains({'\r', '\n'}):
    raise newException(ValueError, "journal operation ID and href are required")
  let timestamp = $now().utc
  store.db.exec(sql"""INSERT INTO sync_journal(operation_id, collection_id, operation, href,
    state, content_type, raw_data, base_etag, base_data, attempt, last_error, next_attempt_at,
    created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, '', '', ?, ?)
    ON CONFLICT(operation_id) DO NOTHING""",
    entry.operationId, entry.collectionId, operationName(entry.operation),
        entry.href,
    stateName(jsPending), entry.contentType, entry.rawData, entry.baseEtag,
        entry.baseData,
    timestamp, timestamp)
  let stored = store.getJournalEntry(entry.operationId)
  if stored.isNone or stored.get.collectionId != entry.collectionId or
      stored.get.operation != entry.operation or stored.get.href !=
          entry.href or
      stored.get.contentType != entry.contentType or stored.get.rawData !=
          entry.rawData or
      stored.get.baseEtag != entry.baseEtag or stored.get.baseData !=
          entry.baseData:
    raise newException(ValueError, "operation ID already refers to a different journal entry")

proc stageLocalUpsert*(store: SqliteStore; operationId: string; collectionId: int64;
                       href, contentType, rawData, baseEtag: string;
                           create: bool) =
  if contentType notin ["text/calendar", "text/vcard"]:
    raise newException(ValueError, "local DAV content type is unsupported")
  let expectedKind = if contentType == "text/calendar": dkICalendar else: dkVCard
  if detectKind(rawData) != expectedKind or not isValid(rawData):
    raise newException(ValueError, "local DAV resource is invalid for its content type")
  if not create and not isStrongEtag(baseEtag):
    raise newException(ValueError, "local replacement requires a safe base ETag")
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    let prior = store.getJournalEntry(operationId)
    let existing = store.getResource(collectionId, href)
    if create and prior.isNone and existing.isSome and not existing.get.deleted:
      raise newException(ValueError, "local create cannot replace an existing cached resource")
    if not create and existing.isSome and existing.get.etag != baseEtag:
      raise newException(ValueError, "local replacement base ETag does not match cached resource")
    store.putResource(ResourceRecord(collectionId: collectionId, href: href,
      etag: baseEtag,
      contentType: contentType, rawData: rawData, deleted: false))
    store.enqueueOperation(JournalEntry(operationId: operationId,
      collectionId: collectionId,
      operation: if create: jokCreate else: jokReplace, href: href,
      contentType: contentType, rawData: rawData, baseEtag: baseEtag,
      baseData: if prior.isSome: prior.get.baseData
        elif existing.isSome: existing.get.rawData else: ""))
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc coalesceLocalUpsert*(store: SqliteStore; operationId: string; collectionId: int64;
                          href, contentType, rawData, baseEtag: string;
                              create: bool): string =
  ## Replaces the payload of an upload that has not been claimed yet. This
  ## prevents consecutive offline edits from becoming self-conflicting writes.
  let pending = store.pendingJournalEntryForResource(collectionId, href)
  if pending.isNone:
    store.stageLocalUpsert(operationId, collectionId, href, contentType,
        rawData, baseEtag, create)
    return operationId
  let entry = pending.get
  if entry.operation notin {jokCreate, jokReplace} or
      (create and entry.operation != jokCreate):
    raise newException(LocalChangesPendingError,
      "local DAV resource has an incompatible pending operation")
  let expectedKind = if contentType == "text/calendar": dkICalendar else: dkVCard
  if contentType notin ["text/calendar", "text/vcard"] or
      detectKind(rawData) != expectedKind or not isValid(rawData):
    raise newException(ValueError, "local DAV resource is invalid for its content type")
  if entry.baseEtag != baseEtag:
    raise newException(LocalChangesPendingError,
      "local DAV replacement base ETag changed while editing")
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    let locked = store.getJournalEntry(entry.operationId)
    if locked.isNone or locked.get.state notin {jsPending, jsRetry}:
      raise newException(LocalChangesPendingError,
        "local DAV operation was claimed while editing")
    store.putResource(ResourceRecord(collectionId: collectionId, href: href,
      etag: baseEtag, contentType: contentType, rawData: rawData,
      deleted: false))
    store.db.exec(sql"""UPDATE sync_journal SET content_type=?, raw_data=?, state='pending',
      attempt=0, last_error='', next_attempt_at='', updated_at=? WHERE operation_id=?""",
      contentType, rawData, $now().utc, entry.operationId)
    store.db.exec(sql"COMMIT")
    result = entry.operationId
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc stageLocalDelete*(store: SqliteStore; operationId: string; collectionId: int64;
                       href, baseEtag: string) =
  if not isStrongEtag(baseEtag):
    raise newException(ValueError, "local deletion requires a safe base ETag")
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    let prior = store.getJournalEntry(operationId)
    let existing = store.getResource(collectionId, href)
    if existing.isSome and existing.get.etag != baseEtag:
      raise newException(ValueError, "local deletion base ETag does not match cached resource")
    store.putResource(ResourceRecord(collectionId: collectionId, href: href,
      etag: baseEtag,
      contentType: if existing.isSome: existing.get.contentType else: "",
      rawData: if existing.isSome: existing.get.rawData else: "",
      deleted: true))
    store.enqueueOperation(JournalEntry(operationId: operationId,
      collectionId: collectionId,
      operation: jokDelete, href: href, baseEtag: baseEtag,
      baseData: if prior.isSome: prior.get.baseData
        elif existing.isSome: existing.get.rawData else: ""))
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc coalesceLocalDelete*(store: SqliteStore; operationId: string; collectionId: int64;
                          href, baseEtag: string): string =
  ## Cancels an unclaimed create, or turns an unclaimed replacement into one
  ## conditional deletion. No redundant remote write is emitted.
  let pending = store.pendingJournalEntryForResource(collectionId, href)
  if pending.isNone:
    store.stageLocalDelete(operationId, collectionId, href, baseEtag)
    return operationId
  let entry = pending.get
  if entry.operation notin {jokCreate, jokReplace}:
    raise newException(LocalChangesPendingError,
      "local DAV resource has an incompatible pending operation")
  if entry.baseEtag != baseEtag:
    raise newException(LocalChangesPendingError,
      "local DAV deletion base ETag changed while editing")
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    let locked = store.getJournalEntry(entry.operationId)
    if locked.isNone or locked.get.state notin {jsPending, jsRetry}:
      raise newException(LocalChangesPendingError,
        "local DAV operation was claimed while deleting")
    let existing = store.getResource(collectionId, href)
    store.putResource(ResourceRecord(collectionId: collectionId, href: href,
      etag: baseEtag, contentType: if existing.isSome: existing.get.contentType else: "",
      rawData: if existing.isSome: existing.get.rawData else: "",
      deleted: true))
    if entry.operation == jokCreate:
      store.db.exec(sql"""UPDATE sync_journal SET state='complete', last_error='',
        next_attempt_at='', updated_at=? WHERE operation_id=?""", $now().utc,
          entry.operationId)
    else:
      store.db.exec(sql"""UPDATE sync_journal SET operation='delete', state='pending',
        content_type='', raw_data='', attempt=0, last_error='', next_attempt_at='', updated_at=?
        WHERE operation_id=?""", $now().utc, entry.operationId)
    store.db.exec(sql"COMMIT")
    result = entry.operationId
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc coalesceLocalRestore*(store: SqliteStore; operationId: string; collectionId: int64;
                           href, contentType, rawData,
                               baseEtag: string): string =
  ## Reverses an unclaimed local deletion without weakening its original
  ## precondition. An unchanged server resource needs no upload; a replacement
  ## deleted before upload resumes as replace; an unsent create resumes as create.
  let expectedKind = if contentType == "text/calendar": dkICalendar else: dkVCard
  if contentType notin ["text/calendar", "text/vcard"] or
      detectKind(rawData) != expectedKind or not isValid(rawData):
    raise newException(ValueError, "restored DAV resource is invalid for its content type")
  let pending = store.pendingJournalEntryForResource(collectionId, href)
  if pending.isNone:
    if baseEtag.len != 0:
      raise newException(LocalChangesPendingError, "local DAV deletion is no longer reversible")
    store.stageLocalUpsert(operationId, collectionId, href, contentType,
        rawData, "", create = true)
    return operationId
  let entry = pending.get
  if entry.operation != jokDelete or entry.baseEtag != baseEtag:
    raise newException(LocalChangesPendingError,
      "local DAV resource has an incompatible pending operation")
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    let locked = store.getJournalEntry(entry.operationId)
    if locked.isNone or locked.get.state notin {jsPending, jsRetry}:
      raise newException(LocalChangesPendingError,
        "local DAV deletion was claimed while restoring")
    store.putResource(ResourceRecord(collectionId: collectionId, href: href,
      etag: baseEtag, contentType: contentType, rawData: rawData,
      deleted: false))
    if entry.baseData == rawData:
      store.db.exec(sql"""UPDATE sync_journal SET state='complete', last_error='',
        next_attempt_at='', updated_at=? WHERE operation_id=?""", $now().utc,
          entry.operationId)
    else:
      store.db.exec(sql"""UPDATE sync_journal SET operation='replace', state='pending',
        content_type=?, raw_data=?, attempt=0, last_error='', next_attempt_at='', updated_at=?
        WHERE operation_id=?""", contentType, rawData, $now().utc,
          entry.operationId)
    store.db.exec(sql"COMMIT")
    result = entry.operationId
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc nextJournalEntry*(store: SqliteStore; currentTime = ""): Option[JournalEntry] =
  let effectiveTime = if currentTime.len > 0: currentTime else: $now().utc
  let row = store.db.getRow(sql"""SELECT operation_id, collection_id, operation, href, state,
    content_type, raw_data, base_etag, base_data, attempt, last_error, next_attempt_at FROM sync_journal
    WHERE state='pending' OR (state='retry' AND (next_attempt_at='' OR next_attempt_at<=?))
    ORDER BY created_at, operation_id LIMIT 1""", effectiveTime)
  if row[0].len == 0: return none(JournalEntry)
  some(journalEntry(row))

proc nextJournalEntryForAccount*(store: SqliteStore; accountId: int64;
                                 currentTime = ""): Option[JournalEntry] =
  if accountId <= 0: raise newException(ValueError, "journal account ID is invalid")
  let effectiveTime = if currentTime.len > 0: currentTime else: $now().utc
  let row = store.db.getRow(sql"""SELECT j.operation_id, j.collection_id, j.operation,
      j.href, j.state, j.content_type, j.raw_data, j.base_etag, j.base_data, j.attempt,
      j.last_error, j.next_attempt_at FROM sync_journal j
      JOIN collections c ON c.id=j.collection_id
      WHERE c.account_id=? AND (j.state='pending' OR
        (j.state='retry' AND (j.next_attempt_at='' OR j.next_attempt_at<=?)))
      ORDER BY j.created_at, j.operation_id LIMIT 1""", accountId, effectiveTime)
  if row[0].len == 0: return none(JournalEntry)
  some(journalEntry(row))

proc markJournalState(store: SqliteStore; operationId: string; state: JournalState;
                      lastError = ""; nextAttemptAt = "";
                          incrementAttempt = false) =
  let affected = store.db.execAffectedRows(
    sql"""UPDATE sync_journal SET state=?, last_error=?,
    next_attempt_at=?, attempt=attempt+?, updated_at=? WHERE operation_id=?""",
    stateName(state), lastError, nextAttemptAt, ord(incrementAttempt), $now().utc, operationId)
  if affected != 1: raise newException(ValueError, "journal operation does not exist")

proc markJournalRunning*(store: SqliteStore; operationId: string) =
  store.markJournalState(operationId, jsRunning, incrementAttempt = true)

proc markJournalRetry*(store: SqliteStore; operationId, lastError,
    nextAttemptAt: string) =
  if lastError.len == 0: raise newException(ValueError, "retry error is required")
  store.markJournalState(operationId, jsRetry, lastError, nextAttemptAt)

proc markJournalConflict*(store: SqliteStore; operationId, lastError: string) =
  store.markJournalState(operationId, jsConflict, lastError)

proc markJournalSuspended*(store: SqliteStore; operationId, lastError: string) =
  store.markJournalState(operationId, jsSuspended, lastError)

proc markJournalFailed*(store: SqliteStore; operationId, lastError: string) =
  store.markJournalState(operationId, jsFailed, lastError)

proc markJournalComplete*(store: SqliteStore; operationId: string) =
  store.markJournalState(operationId, jsComplete)

proc completeJournalPut*(store: SqliteStore; operationId: string;
    resource: ResourceRecord) =
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    store.putResource(resource)
    store.markJournalState(operationId, jsComplete)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc completeJournalDelete*(store: SqliteStore; operationId: string) =
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    store.markJournalState(operationId, jsComplete)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc claimNextJournalEntry*(store: SqliteStore; currentTime = ""): Option[JournalEntry] =
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    let candidate = store.nextJournalEntry(currentTime)
    if candidate.isNone:
      store.db.exec(sql"COMMIT")
      return none(JournalEntry)
    store.markJournalRunning(candidate.get.operationId)
    result = store.getJournalEntry(candidate.get.operationId)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc claimNextJournalEntryForAccount*(store: SqliteStore; accountId: int64;
                                      currentTime = ""): Option[JournalEntry] =
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    let candidate = store.nextJournalEntryForAccount(accountId, currentTime)
    if candidate.isNone:
      store.db.exec(sql"COMMIT")
      return none(JournalEntry)
    store.markJournalRunning(candidate.get.operationId)
    result = store.getJournalEntry(candidate.get.operationId)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc recoverInterruptedOperations*(store: SqliteStore;
    reason = "interrupted before completion") =
  store.db.exec(sql"""UPDATE sync_journal SET state='retry', last_error=?, next_attempt_at='',
    updated_at=? WHERE state='running'""", reason, $now().utc)

proc recoverInterruptedOperationsForAccount*(store: SqliteStore; accountId: int64;
                                              reason = "interrupted before completion") =
  if accountId <= 0: raise newException(ValueError, "recovery account ID is invalid")
  store.db.exec(sql"""UPDATE sync_journal SET state='retry', last_error=?, next_attempt_at='',
    updated_at=? WHERE state='running' AND collection_id IN
      (SELECT id FROM collections WHERE account_id=?)""", reason, $now().utc, accountId)

proc conflictRecord(row: Row): ConflictRecord =
  ConflictRecord(id: parseBiggestInt(row[0]).int64, operationId: row[1],
    collectionId: parseBiggestInt(row[2]).int64, href: row[3], localData: row[4],
    remoteData: row[5], remoteContentType: row[6], baseData: row[7],
        remoteEtag: row[8],
    remoteDeleted: row[9] == "1", resolved: row[10] == "1")

proc getConflictForOperation*(store: SqliteStore; operationId: string): Option[
    ConflictRecord] =
  let row = store.db.getRow(sql"""SELECT id, operation_id, collection_id, href, local_data,
    remote_data, remote_content_type, base_data, remote_etag, remote_deleted, resolved
    FROM conflicts WHERE operation_id=?""", operationId)
  if row[0].len == 0: return none(ConflictRecord)
  some(conflictRecord(row))

proc recordJournalConflict*(store: SqliteStore; entry: JournalEntry;
                            remoteData, remoteContentType, remoteEtag,
                                reason: string;
                            remoteDeleted = false) =
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    let affected = store.db.execAffectedRows(
      sql"""UPDATE conflicts SET local_data=?,
      remote_data=?, remote_content_type=?, base_data=?, remote_etag=?, remote_deleted=?, resolved=0
      WHERE operation_id=?""", entry.rawData, remoteData, remoteContentType,
      entry.baseData,
      remoteEtag, ord(remoteDeleted), entry.operationId)
    if affected == 0:
      store.db.exec(sql"""INSERT INTO conflicts(operation_id, collection_id, href, local_data,
        remote_data, remote_content_type, base_data, remote_etag, remote_deleted, resolved)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)""", entry.operationId,
        entry.collectionId,
        entry.href, entry.rawData, remoteData, remoteContentType,
        entry.baseData, remoteEtag,
        ord(remoteDeleted))
    store.markJournalState(entry.operationId, jsConflict, reason)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc resolveConflictKeepRemote*(store: SqliteStore; operationId: string) =
  let conflict = store.getConflictForOperation(operationId)
  if conflict.isNone or conflict.get.resolved:
    raise newException(ValueError, "unresolved conflict does not exist")
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    store.putResource(ResourceRecord(collectionId: conflict.get.collectionId,
      href: conflict.get.href, etag: conflict.get.remoteEtag,
      contentType: if conflict.get.remoteDeleted: "" else: conflict.get.remoteContentType,
      rawData: if conflict.get.remoteDeleted: conflict.get.baseData else: conflict.get.remoteData,
      deleted: conflict.get.remoteDeleted))
    store.db.exec(sql"UPDATE conflicts SET resolved=1 WHERE operation_id=?", operationId)
    store.markJournalState(operationId, jsComplete)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc resolveConflictRetryLocal*(store: SqliteStore; operationId: string) =
  let conflict = store.getConflictForOperation(operationId)
  if conflict.isNone or conflict.get.resolved or conflict.get.remoteDeleted or
      not isStrongEtag(conflict.get.remoteEtag):
    raise newException(ValueError, "conflict has no current remote ETag")
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    store.db.exec(sql"""UPDATE sync_journal SET operation='replace', base_etag=?,
      base_data=?, state='pending', last_error='', next_attempt_at='', updated_at=?
      WHERE operation_id=?""", conflict.get.remoteEtag, conflict.get.remoteData,
      $now().utc, operationId)
    store.db.exec(sql"UPDATE resources SET etag=?, updated_at=? WHERE collection_id=? AND href=?",
      conflict.get.remoteEtag, $now().utc, conflict.get.collectionId,
          conflict.get.href)
    store.db.exec(sql"UPDATE conflicts SET resolved=1 WHERE operation_id=?", operationId)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

proc resolveConflictMerge*(store: SqliteStore;
    operationId: string): MergeOutcome =
  ## Merge independent base/local/remote fields and queue the result conditionally.
  ## If conflicts remain, no store state changes and the caller must choose manually.
  let conflict = store.getConflictForOperation(operationId)
  if conflict.isNone or conflict.get.resolved or conflict.get.remoteDeleted or
      not isStrongEtag(conflict.get.remoteEtag):
    raise newException(ValueError, "conflict has no current remote ETag")
  result = mergeThreeWay(conflict.get.baseData, conflict.get.localData,
    conflict.get.remoteData)
  if result.conflicts.len > 0: return
  store.db.exec(sql"BEGIN IMMEDIATE")
  try:
    store.db.exec(sql"""UPDATE sync_journal SET operation='replace', content_type=? ,
      raw_data=?, base_etag=?, base_data=?, state='pending', last_error='',
      next_attempt_at='', updated_at=? WHERE operation_id=?""",
      conflict.get.remoteContentType, result.document, conflict.get.remoteEtag,
      conflict.get.remoteData, $now().utc, operationId)
    store.db.exec(sql"""UPDATE resources SET etag=?, content_type=?, raw_data=? ,
      deleted=0, updated_at=? WHERE collection_id=? AND href=?""",
      conflict.get.remoteEtag, conflict.get.remoteContentType, result.document,
      $now().utc, conflict.get.collectionId, conflict.get.href)
    store.db.exec(sql"UPDATE conflicts SET resolved=1 WHERE operation_id=?",
      operationId)
    store.db.exec(sql"COMMIT")
  except CatchableError:
    store.db.exec(sql"ROLLBACK")
    raise

# Keep source mapping stable for gcov-generated exception branches.
# Atomic apply must retain full branch coverage.
# End of module.
