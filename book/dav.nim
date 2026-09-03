# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "DAV"

nbText: """
# DAV

CardDAV and CalDAV are WebDAV: XML over HTTP, with a handful of methods a
plain client does not have. UniDAV owns the parts that are the same whatever
you are syncing — discovery, the XML, ETags, and what a conflict is — and
leaves the transport separable so a caller can bring their own.

## Discovery

A server is found from a bare domain through `.well-known`. That is a URL
computation, not a request, so it is testable without a network.
"""

nbCode:
  import UniDAV

  echo wellKnownUrl("https://example.org", dskAddressBook)
  echo wellKnownUrl("https://example.org", dskCalendar)
  echo resolveUrl("https://example.org/dav/ada/", "../grace/card.vcf")

nbText: """
## Multi-status

A `PROPFIND` answers with `207 Multi-Status`: one XML document holding a
response per resource, each with its own status. Reading it is where a naive
client goes wrong — a 207 is not success, it is a list of outcomes.
"""

nbCode:
  const multiStatus = """<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/ada/card.vcf</d:href>
    <d:propstat>
      <d:prop><d:getetag>"abc123"</d:getetag></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/ada/missing.vcf</d:href>
    <d:propstat>
      <d:prop><d:getetag/></d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>"""

  for response in parseMultiStatus(multiStatus).responses:
    echo response.href, "  etag=", response.property("getetag")

nbText: """
The parser takes a byte ceiling. A multi-status is attacker-controlled in the
sense that matters here — it is however large the server says — so the bound is
an argument rather than a hope.

## ETags decide what a conflict is

A weak ETag (`W/"..."`) means "semantically the same", which is not enough to
build a conditional write on. UniDAV keeps the distinction rather than
flattening it.
"""

nbCode:
  for tag in ["\"abc123\"", "W/\"abc123\"", ""]:
    echo tag, " -> strong: ", isStrongEtag(tag)

nbText: """
## The transport is yours

`newDavClient` takes a `DavTransport`. The bundled one is libcurl on Unix and
WinHTTP on Windows — hardened, and compiled from `csrc/` — but a caller with
their own HTTP stack, or a test with a fixture, supplies one instead. That is
why every chapter above runs without a network.
"""

nbSave
