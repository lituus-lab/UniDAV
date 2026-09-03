# SPDX-License-Identifier: Apache-2.0
import std/[algorithm, strutils, uri]
import client

const
  MaxDnsRecords* = 32
  MaxDnsNameBytes* = 253
  MaxTxtBytes* = 4096

type
  DavSrvRecord* = object
    priority*: uint16
    weight*: uint16
    port*: uint16
    target*: string
  DavDnsResolver* = object
    lookupSrv*: proc(name: string): seq[DavSrvRecord] {.closure.}
    lookupTxt*: proc(name: string): seq[string] {.closure.}
  DavRandomDraw* = proc(upperExclusive: int): int {.closure.}
  DavServiceEndpoint* = object
    url*: string
    secure*: bool
    fromSrv*: bool
    serviceName*: string

proc hasControl(value: string): bool =
  for character in value:
    if character < ' ' or character == '\x7f':
      return true

proc checkedDomain(domain: string): string =
  if domain.len == 0 or domain.len > MaxDnsNameBytes or domain.hasControl or
      domain.contains('/') or domain.contains('@') or domain.contains(':'):
    raise newException(DavClientError, "DAV discovery domain is invalid")
  result = domain.toLowerAscii
  if result.endsWith('.'):
    result.setLen(result.len - 1)
  if result.len == 0 or result.startsWith('.') or result.contains(".."):
    raise newException(DavClientError, "DAV discovery domain is invalid")
  for label in result.split('.'):
    if label.len == 0 or label.len > 63 or label.startsWith('-') or
        label.endsWith('-'):
      raise newException(DavClientError, "DAV discovery domain is invalid")
    for character in label:
      if not (character.isAlphaNumeric or character == '-'):
        raise newException(DavClientError, "DAV discovery domain is invalid")

proc serviceLabel(kind: DavServiceKind; secure: bool): string =
  case kind
  of dskCalendar:
    if secure: "_caldavs._tcp." else: "_caldav._tcp."
  of dskAddressBook:
    if secure: "_carddavs._tcp." else: "_carddav._tcp."

proc checkedRecords(records: seq[DavSrvRecord]): seq[DavSrvRecord] =
  if records.len > MaxDnsRecords:
    raise newException(DavClientError, "DAV SRV response exceeds record limit")
  for record in records:
    if record.target == ".":
      continue
    var target = record.target
    if target.endsWith('.'):
      target.setLen(target.len - 1)
    discard checkedDomain(target)
    if record.port == 0:
      raise newException(DavClientError, "DAV SRV record has an invalid port")
    result.add DavSrvRecord(priority: record.priority, weight: record.weight,
      port: record.port, target: target.toLowerAscii)

proc orderSrvRecords*(records: seq[DavSrvRecord];
    draw: DavRandomDraw): seq[DavSrvRecord] =
  ## Applies RFC 2782 priority and weight selection without hiding randomness.
  if draw.isNil:
    raise newException(DavClientError, "DAV SRV selection requires a random source")
  var remaining = checkedRecords(records)
  while remaining.len > 0:
    var lowest = remaining[0].priority
    for record in remaining:
      if record.priority < lowest:
        lowest = record.priority
    var eligible: seq[int]
    var totalWeight = 0
    for index, record in remaining:
      if record.priority == lowest:
        eligible.add index
        totalWeight += int(record.weight)
    eligible.sort(proc(first, second: int): int =
      cmp(remaining[first].weight, remaining[second].weight))
    let limit = if totalWeight > 0: totalWeight + 1 else: eligible.len
    let selected = draw(limit)
    if selected < 0 or selected >= limit:
      raise newException(DavClientError, "DAV random source returned an invalid value")
    var chosen = eligible[0]
    if totalWeight == 0:
      chosen = eligible[selected]
    else:
      var cumulative = 0
      for index in eligible:
        cumulative += int(remaining[index].weight)
        if cumulative >= selected:
          chosen = index
          break
    result.add remaining[chosen]
    remaining.delete(chosen)

proc txtPath(values: seq[string]): string =
  var total = 0
  for value in values:
    total += value.len
    if total > MaxTxtBytes:
      raise newException(DavClientError, "DAV TXT response exceeds size limit")
    if value.startsWith("path="):
      if result.len > 0:
        raise newException(DavClientError, "DAV TXT response repeats path")
      result = value[5 .. ^1]
  if result.len == 0:
    return
  if result[0] != '/' or result.hasControl or result.contains(' ') or
      result.startsWith("//"):
    raise newException(DavClientError, "DAV TXT path is invalid")
  let parsed = parseUri(result)
  if parsed.scheme.len > 0 or parsed.hostname.len > 0 or parsed.anchor.len > 0:
    raise newException(DavClientError, "DAV TXT path must be an absolute path")

proc locateDavService*(domain: string; kind: DavServiceKind;
    resolver: DavDnsResolver; draw: DavRandomDraw;
    allowPlainHttp = false): seq[DavServiceEndpoint] =
  ## Returns RFC 6764 endpoints in connection-attempt order.
  if resolver.lookupSrv.isNil or resolver.lookupTxt.isNil:
    raise newException(DavClientError, "DAV DNS resolver is incomplete")
  let host = checkedDomain(domain)
  for secure in [true, false]:
    if not secure and not allowPlainHttp:
      continue
    let service = serviceLabel(kind, secure) & host
    let records = resolver.lookupSrv(service)
    var unavailable = false
    for record in records:
      if record.target == ".":
        unavailable = true
    if unavailable and records.len != 1:
      raise newException(DavClientError,
        "DAV SRV response mixes unavailable and service records")
    if unavailable:
      if secure:
        break
      continue
    if records.len == 0:
      continue
    let path = txtPath(resolver.lookupTxt(service))
    for record in orderSrvRecords(records, draw):
      let scheme = if secure: "https" else: "http"
      let contextPath = if path.len > 0: path else:
        (if kind == dskCalendar: "/.well-known/caldav" else: "/.well-known/carddav")
      result.add DavServiceEndpoint(url: scheme & "://" & record.target & ":" &
        $record.port & contextPath, secure: secure, fromSrv: true,
        serviceName: service)
    if result.len > 0:
      return
  let fallback = "https://" & host
  result.add DavServiceEndpoint(url: wellKnownUrl(fallback, kind), secure: true,
    fromSrv: false)
