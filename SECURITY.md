<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Security policy

Report vulnerabilities privately to the maintainer address recorded in the
git history. Do not open a public issue before a coordinated fix is available.
Include the affected version, impact, minimal reproducer, and whether untrusted
vCard, iCalendar, XML, HTTP, DNS, or database input is required.

## Security boundaries

- Parsers bound bytes, lines, properties, component depth, XML nodes, and
  recurrence expansion.
- External XML entities and network access during XML parsing are forbidden.
- HTTPS certificate and host verification remain enabled.
- Redirects cannot downgrade HTTPS or forward credentials across origins.
- Writes use explicit preconditions and stable operation identifiers.
- Credentials and complete personal payloads never enter logs or fixtures.
- C and WebAssembly callers own their input buffers; UniDAV-owned output is
  released only by the matching `unidav_` free operation.

Only the latest released line receives security fixes. The ABI is not frozen
before the 1.0.0 release.

