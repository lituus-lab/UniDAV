# UniDAV action plan

## Delivered foundation

- Repository and dependency direction follow `UNI_FAMILY_STRUCTURE.md` and the UniTemplate family
  conventions.
- Bounded lossless content-line, vCard, and iCalendar core with validation and deterministic output.
- DAV discovery, multistatus XML, collection enumeration, sync reports, multiget, hardened Unix/macOS
  transport, and conditional writes.
- SQLite schema v3 with atomic downward apply, durable outgoing journal, crash recovery, bounded
  retry, ambiguity verification, and persistent conflicts.
- Nim, CLI, C, Python, and WASM surfaces with debug/release, coverage, sanitizer, and smoke gates.

## Next protocol work

1. Add RFC 6764 SRV/TXT discovery behind a bounded, injectable resolver.
2. Expand namespace-aware XML fixtures and canonicalization/security edge cases.
3. Keep the delivered Radicale, SabreDAV, Baïkal, and Nextcloud TLS matrices current; anonymize
   every compatibility regression into a local fixture.
4. Execute the delivered WinHTTP transport and shared redirect/credential/size suite on native
   Windows CI; keep strict PE32/PE32+ cross-compilation as an earlier gate.

## Next semantic and product work

CalDAV additions delivered: RFC 6638 iTIP schedule-outbox discovery/submission, RFC 4791 bounded
`free-busy` and time-ranged `calendar-query` reports, RFC 7809 time-zone references, and RFC 7953
`calendar-availability`/`VAVAILABILITY` validation. These remain bounded subsets: the engine does
not calculate availability locally and makes no identity or participation decisions.

1. Extend the delivered bounded recurrence expansion and explicit VTIMEZONE registry with DNS
   discovery, full scheduling semantics, and vCard parameter edge cases.
2. Extend the delivered safe three-way field merge beyond the current journal conflict-resolution
   primitive while retaining manual base/local/remote conflict choices.
3. Finish Concordia account lifecycle, OS keychain integration, import/export, accessible calendar,
   contacts, tasks, sync center, and settings in desktop and web shells.
4. Keep English/French product copy synchronized and add keyboard, screen-reader, contrast,
   reduced-motion, responsive, and offline acceptance tests.

## Definition of done

A phase is complete only when its documentation matches shipped behavior, relevant debug/release,
C, Python, WASM, coverage, and sanitizer gates pass, interoperability evidence exists where a
server claim is made, and the family dependency graph remains acyclic.

Unfinished work remains listed in the relevant phases; no temporary audit report is kept in the
delivery tree.
