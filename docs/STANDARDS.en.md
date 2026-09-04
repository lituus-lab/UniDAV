# Standards coverage

UniDAV reports conformance per feature and test corpus. A row marked
`implemented` identifies behavior exercised by the named local suite. `Partial`
means that the listed subset exists; it is not a claim for the complete RFC.
Internet-Drafts are tracked separately and do not define stable compatibility.

## Data formats and PIM semantics

| Standard | Scope | Status | Local evidence |
|---|---|---|---|
| RFC 6350 | vCard 4.0 content lines, components, required `VERSION` and `FN`, singleton property cardinalities, bounded `BDAY`/`ANNIVERSARY`/`DEATHDATE`/`GEO`/`UID` values (complete and partial dates, times, and offsets), unique and bounded `PREF`/`PID` parameters, `KIND`/`GENDER` values, and UTC `REV` timestamp | Partial | `tests/test_formats.nim` |
| RFC 6868 | Caret escaping in parameter values | Implemented | `tests/test_formats.nim` |
| RFC 5545 | Single iCalendar container, lossless components, core validation (required UID/DTSTAMP, known component and property placement, component cardinalities, CALSCALE/METHOD/PRODID, RECURRENCE-ID RANGE, temporal VALUE/TZID parameters, positive durations, URI/BINARY Base64 ATTACH values, TRIGGER/RELATED alarm context against DTSTART/DTEND/DUE and ACTION-specific restrictions, local VTIMEZONE observances with annual RDATE/RRULE, VFREEBUSY/FREEBUSY, date-time/offset values, statuses, numeric ranges, DTSTART/DTEND/DUE type and ordering, DTEND/DURATION constraints), structural RRULE validation (FREQ, BY* bounds, BYSETPOS, BYDAY ordinals, UNTIL/COUNT and DTSTART dependencies), temporal consistency for RDATE/EXDATE/RECURRENCE-ID and RDATE periods, bounded UTC SECONDLY/MINUTELY/HOURLY/DAILY/WEEKLY/MONTHLY/YEARLY expansion with BY* filters, and VTIMEZONE observances with bounded RRULE/RDATE transitions | Partial | `tests/test_formats.nim`, `tests/test_recurrence.nim`, `tests/test_timezone_registry.nim` |
| RFC 7095 | Bounded jCard structure, groups, parameters, structured/multi-values, temporal forms and `unknown` extensions | Partial | `tests/test_formats.nim` |
| RFC 7265 | Bounded jCal components, parameters, typed core values, recurrence/period values and nesting | Partial | `tests/test_formats.nim` |
| RFC 7986 | iCalendar properties | Preserved, not semantically validated | `tests/test_formats.nim` |
| RFC 9073 | Event publication extensions | Preserved, not semantically validated | `tests/test_formats.nim` |
| RFC 9074 | VALARM extensions | Preserved, not semantically validated | `tests/test_formats.nim` |
| RFC 9253 | iCalendar relationships | Preserved, not semantically validated | `tests/test_formats.nim` |
| RFC 8984 | JSCalendar 1.0 base `Event`/`Task` projection aliases and lossless patch input | Partial | `tests/test_formats.nim` |
| RFC 9553 | JSContact 1.0 base `Card`/`name.full` projection aliases and lossless patch input | Partial | `tests/test_formats.nim` |
| RFC 9554 | JSContact vCard extensions | Partial | `src/UniDAV/projection.nim`, `tests/test_formats.nim` (`PROP-ID`, `SCRIPT`, `SERVICE-TYPE`, `USERNAME`) |
| RFC 9555 | JSContact/vCard conversion | Partial | bounded Card projection, registered properties (ROLE/FBURL/GEO/TZ/PersonalInfo/ORG-DIRECTORY/SOURCE/BIRTHPLACE/DEATHDATE/DEATHPLACE/X-ABLabel), structural fields and lossless patch bridge |
| RFC 9982 | JSContact 2.0 | Planned | — |

Bounded UTC and explicit-VTIMEZONE recurrence evaluation now covers the principal frequencies and
filters; scheduling, availability, and free-busy are covered by the subsets listed in the tables,
while complete semantics remain implementation gates. Active
IETF work on JSCalendar 2.0, JSCalendar/iCalendar conversion, JSContact 2.0,
and JSContact/vCard conversion is tracked as work in progress.

## DAV protocols

| Standard | Scope | Status | Local evidence |
|---|---|---|---|
| RFC 4918 | PROPFIND, Multi-Status, conditional resource operations | Partial | `tests/test_dav.nim`, `tests/test_client.nim` |
| RFC 5397 | Current principal discovery | Implemented subset | `tests/test_client.nim` |
| RFC 4791 | CalDAV discovery, component filters (`VEVENT`/`VTODO`/`VJOURNAL`), time-ranged queries, multiget and bounded free-busy REPORT | Partial | `tests/test_dav.nim`, `tests/test_client.nim` |
| RFC 6352 | CardDAV discovery, bounded vCard property filters and `text-match`, collection query and multiget | Partial | `tests/test_dav.nim`, `tests/test_client.nim` |
| RFC 6578 | Collection synchronization and invalid-token recovery | Implemented subset | `tests/test_client.nim` |
| RFC 6764 | TLS-first SRV/TXT and well-known discovery planning | Implemented core | `tests/test_client.nim` |
| RFC 6638 | URI and iTIP-method validation with submission to a schedule outbox using `Originator`/`Recipient` | Partial | `tests/test_client.nim` |
| RFC 7809 | `timezone-service-set`/`calendar-timezone-id` discovery and `timezone-id` query element | Partial | `tests/test_client.nim` |
| RFC 7953 | `VAVAILABILITY`/`AVAILABLE` validation and discovery, required UID/DTSTAMP, availability recurrences, `BUSYTYPE` and `X-*` extensions, `PRIORITY`, UTC-or-TZID date-times with a matching `VTIMEZONE`, and temporal bounds | Partial | `tests/test_client.nim`, `tests/test_formats.nim` |

Transport execution, DNS lookup, durable storage, clocks, and time-zone data
are injectable host ports. The native transport implements HTTPS enforcement,
bounded requests and responses, redirect validation, and origin-scoped
credentials; `tests/test_http_transport.nim` exercises the shared policy.

## Interoperability and oracles

The parameterized TLS suite covers discovery, collection listing, conditional
CRUD, query, multiget, ETag handling, and cleanup. A server is named as tested
only with recorded execution evidence. The maintained configurations target
Radicale, SabreDAV, Baïkal, and Nextcloud.

The committed anonymized corpus is round-tripped through pinned vobject and
icalendar releases by `nimble testOracles`; acceptance and preservation of an
unknown marker are asserted without printing the payload. libical, iCal4j,
sabre/vobject and CalDAVTester remain additional gates. No single
implementation overrides the RFC text; every divergence is classified and
reduced to an anonymized local fixture.
