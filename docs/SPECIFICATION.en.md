# UniDAV — product and technical specification

## Mission and boundary

UniDAV is an Apache-2.0, Nim 2.x engine for lossless vCard/iCalendar processing and
CardDAV/CalDAV synchronization. It owns no UI, user secrets, or commercial policy. Concordia is
its canonical consumer. Conformance is claimed per implemented feature, never as blanket “full
RFC compliance” without the matching normative corpus and interoperability evidence.

## Implemented protocol and data path

The format layer parses bounded content lines, preserves unknown properties and order, validates
vCard 4.0 and core iCalendar containers, and emits deterministic CRLF output with UTF-8-safe
folding. vCard validation applies known singleton cardinalities, registered `KIND`/`GENDER`/`UID`
values, and UTC `REV` timestamps. iCalendar validation also applies the current safe semantic profile: known RFC 5545
`METHOD` and status values, known component cardinality and placement, DTSTART type/order consistency with `DTEND` or `DUE`, structural `RRULE` constraints (FREQ, BY* bounds, UNTIL/COUNT and DTSTART dependencies), temporal consistency for `RDATE`, `EXDATE`, and `RECURRENCE-ID`, `RDATE` periods, date/date-time, duration and offset values, bounds for `PRIORITY`,
`SEQUENCE`, `PERCENT-COMPLETE`, and `REPEAT`, the `DTEND`/`DURATION` and `DUE`/`DURATION` exclusions, and required `UID`/`DTSTAMP`,
UTC `VFREEBUSY` bounds, `FREEBUSY`/`FBTYPE`, `VTIMEZONE`, and `VALARM` properties.
Unknown properties and components remain lossless; this is not yet complete RFC 5545 semantic
validation. The DAV layer parses bounded multistatus XML, discovers principals and calendar/address
book homes, lists collections, and builds `sync-collection` and multiget reports.

The downward synchronizer uses `sync-collection` after a checkpoint exists. Its first pass, or a
server response explicitly containing `DAV:valid-sync-token`, uses `PROPFIND Depth: 1`. A generic
403 remains an authorization error. If RFC 6578 is unsupported (`405`/`501`) or no token property
exists, a complete calendar/address-book query returns full objects and ETags; the empty checkpoint
intentionally causes another full query next time. It compares inventory ETags with the local cache, fetches only
changed objects through bounded calendar/address-book multiget batches, rejects missing,
duplicate, unexpected, non-success, or invalid resources, then commits upserts, tombstones, and
the next token in one SQLite `BEGIN IMMEDIATE` transaction. Any earlier failure leaves both cache
and checkpoint unchanged.
`CancellationToken` lets a host cooperatively stop a pull before durable commit; the engine raises
`SyncCancelledError` and leaves both cache and checkpoint unchanged.

Cross-origin, out-of-collection, nested, query-bearing, and encoded-separator hrefs are rejected.
RFC 6578 truncation is exposed as `moreAvailable` after its intermediate token is committed. A
remote batch intersecting an active local journal operation fails atomically with
`LocalChangesPendingError`, preserving the local-first document and the previous checkpoint.

The outgoing version-3 journal records stable operation IDs, snapshots, common bases, base ETags,
attempt state, and retry time. Creates use `If-None-Match: *`; replacements and deletes require a
strong quoted ETag and use `If-Match`. Ambiguous success without a strong response ETag is verified
by GET. A precondition failure fetches the remote object: normalized equality completes the
operation idempotently, divergence stores an explicit base/local/remote conflict, and a confirmed
remote deletion remains a tombstone. “Keep remote” and “retry local against the remote ETag” are
transactional decisions.
`mergeThreeWay` provides a lossless property-level merge; `resolveConflictMerge` queues its result
only when no conflict remains, otherwise it returns the conflict paths without mutating the store.

## Storage, transports, and public surfaces

The reference SQLite schema contains `schema_meta`, `accounts`, `collections`, `resources`,
`sync_journal`, and `conflicts`, with monotonic migrations, foreign keys, busy timeout, and WAL.
Applications must keep credentials in an OS credential vault, never in this database. Unix and
macOS use the hardened libcurl transport: TLS verification is on, limits are bounded, credentials
are stripped across origins, HTTPS downgrade is rejected and private PKI roots can be supplied by
an explicit CA bundle without disabling verification. Windows uses WinHTTP with TLS 1.2/1.3,
certificate revocation checks, the system proxy and Windows trust stores. WinHTTP automatic
redirects are disabled so the same Nim origin/downgrade/credential policy applies on every host.
Custom PEM bundles are rejected on Windows instead of weakening system validation.

Public surfaces are the Nim API, `unidav` CLI, versioned `unidav_` C ABI, Python facade, and a
socket-free WASM JSON facade. These facades include bounded recurrence expansion, explicit
VTIMEZONE offset lookup, and bounded `calendar-availability` validation. C functions contain exceptions and UniDAV-owned allocations are
released with `unidav_free`; `unidav_status()` returns `0` for success, `1` for invalid input and
`2` for a caught engine failure. Browser networking and persistence remain host responsibilities.
The C, Python and WASM facades also expose the bounded JSContact bridge (`unidav_to_jscontact` /
`unidav_from_jscontact`) and preserve unknown vCard members through RFC 9555 `vCardProps`.

Projection patches validate the recurrence profile exposed to thin hosts: one supported `FREQ`,
positive `INTERVAL`/`COUNT`, exclusive `COUNT` or `UNTIL`, bounded month/month-day values, valid
weekday ordinals and no duplicate or unknown clauses. Existing server rules remain lossless when a
host does not edit them; this profile is not claimed as complete RFC 5545 recurrence evaluation.

The engine also exposes `expandRecurrence`, a fail-closed UTC evaluator for bounded `SECONDLY`,
`MINUTELY`, `HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY` and `YEARLY` rules. It supports bounded
`COUNT`, `UNTIL`, `INTERVAL`, `BYHOUR`, `BYMINUTE`, `BYSECOND`, `BYMONTH`, `BYMONTHDAY`,
`BYYEARDAY`, `BYWEEKNO`, `BYSETPOS`, `WKST` and weekday filters, including monthly ordinal `BYDAY`.
Callers provide a window and a maximum of 100,000 occurrences; timezone-local clauses raise
`RecurrenceLimitError`.
`expandRecurrenceSet` adds and removes explicit `RDATE`/`EXDATE` values, deduplicates and sorts the
result, and applies the same output bound.
This is a safe projection primitive, not a replacement for a complete timezone-aware RFC 5545
evaluator.

The contact projection includes registered vCard mappings for `CREATED`, `LANGUAGE`, `PRONOUNS`,
`GRAMGENDER`, `SOCIALPROFILE`, `LANG`, `IMPP`, `EMAIL`, `TEL`, `NOTE`, `N`, `ADR`, `ORG`,
`NICKNAME`, `MEMBER`, `RELATED`, media, keys, and calendar addresses, with bounded
`TYPE`/`PREF`/service parameters and the corresponding RFC 9555 Card shapes. This remains a
projection and lossless patch bridge; it is not yet a complete JSContact converter and does not
claim full RFC 9555 coverage.

`addressbook-query` can target the existence of a named vCard property (for example `EMAIL` or
`TEL`) and apply a Unicode `contains` `text-match`; names and text are bounded before XML
generation and `FN` remains the default.
The CalDAV client discovers `schedule-inbox-URL`, `schedule-outbox-URL`, and
`calendar-user-address-set` when advertised by the principal. `postSchedule` submits a validated
iCalendar message to the schedule outbox with RFC 6638 `Originator` and `Recipient` headers,
after validating each address as an absolute URI without a fragment and the body with exactly one
RFC 5546 iTIP method;
identity, participant, and calendar policy remain application responsibilities.
`capabilities` also reads the `DAV` field from `OPTIONS` and exposes normalized CalDAV tokens,
including `calendar-schedule`, `calendar-auto-schedule`, and `calendar-availability`.
`queryFreeBusy` also emits a bounded RFC 4791 free-busy REPORT with a strictly increasing UTC
range; availability and participation policy are not interpreted locally.
`calendar-query` accepts the same range to filter `VEVENT` components server-side (or explicit
`VTODO`/`VJOURNAL` component filters); partial, reversed, or local ranges are rejected. Component
names are bounded before XML generation.
CalDAV collections expose `calendar-timezone-id` and `timezone-service-set` URLs when advertised
(RFC 7809), and `calendar-query` can send a validated `timezone-id`.
The `calendar-availability` property is retained and validated when it contains exactly one
`VAVAILABILITY`, conforming `AVAILABLE` children, `BUSYTYPE`, `PRIORITY`, and optional `VTIMEZONE`; free-busy calculation
remains server-side.

`TimezoneRegistry` accepts bounded `VTIMEZONE` definitions and resolves the latest
`STANDARD`/`DAYLIGHT` observance offset for a wall time, including bounded `RRULE` and `RDATE`
observance transitions. It rejects malformed offsets, duplicate or missing required properties,
and registry/observance overflows. A system timezone database remains intentionally outside this
primitive.

## Explicit remaining gates

DNS SRV/TXT discovery, complete recurrence/time-zone and scheduling semantics beyond validated
outbox submission, full RFC semantic validation, and complete RFC 9555/RFC 9982 JSContact
conversion remain planned. Three-way merge computation,
journal conflict resolution, and cooperative pull cancellation are delivered as bounded public
primitives. Native Windows execution of the implemented
WinHTTP transport remains a release-evidence gate. Radicale 3.5.4,
SabreDAV 4.6.0, Baïkal 0.10.1, and Nextcloud 33.0.7 interoperability are delivered as opt-in TLS
suites.
