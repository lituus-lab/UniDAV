# UniDAV architecture

UniDAV separates portable data rules from application and network policy. `contentline` handles the
shared RFC 5545/RFC 6350 syntax and byte-safe folding. `component` builds a recursive, ordered AST
that preserves unknown properties and nested components. `document` exposes bounded normative
validation and deterministic normalization without discarding extension data.
`davxml` encodes requests and parses each member of a WebDAV `207 Multi-Status`. `sync` contains a
deterministic state machine and retry classification. `sqlite_store` supplies the optional durable
cache and only advances collection tokens through an explicit checkpoint. `journal_sync` claims
eligible local operations under an immediate transaction, applies conditional DAV writes and
persists their outcome.

`client` owns protocol sequencing but not sockets: an injected `DavTransport` makes redirects,
authentication, TLS policy and fault injection explicit. Discovery follows well-known endpoint →
current principal → calendar/address-book home → Depth-1 collection inventory.

`http_transport` has narrow native shims: libcurl on Unix/macOS and WinHTTP on Windows. Nim owns the
shared policy: HTTPS by default, certificate and host verification always enabled, manual redirect
validation, no HTTPS downgrade, origin-scoped credentials, and bounded headers/request/response
bodies and timeouts. The WinHTTP shim also enables certificate revocation, restricts TLS to 1.2/1.3
and uses system proxy/trust configuration. Native Windows execution remains a release-evidence gate;
PE32 and PE32+ strict compilation and PE32+ linking are already checked.

## Safety boundaries

- Parsers enforce input byte/line limits and return typed errors.
- DAV XML accepts namespace extensions and ignores unknown elements, as required by WebDAV.
- Remote writes must use ETag preconditions; the transport layer is intentionally not hard-wired.
- Invalid sync tokens trigger full inventory rather than partial cache mutation.
- SQLite foreign keys and unique keys prevent orphan and duplicate resources.
- Local resource staging and its idempotent journal record share one transaction; successful PUT
  metadata and journal completion also share one transaction.
- Restoring an unclaimed deletion is transactional: unchanged remote data cancels the delete,
  edited data resumes its replacement, and an unsent creation is recreated with `If-None-Match: *`.
- A crashed `running` entry is recovered only through an explicit exclusive-startup call, avoiding
  accidental takeover by a second live process.
- Journal schema v3 retains the common-base snapshot. Ambiguous 412/404 outcomes are verified by
  GET; divergent base/local/remote values become durable conflicts. Accept-remote and retry-local
  resolutions update every affected row transactionally.
- `If-Match` accepts only RFC 9110 strong, quoted entity tags. Weak or malformed validators are
  rejected instead of creating a precondition that can never match strongly.
- C/WASM allocations are released only through `unidav_free`/`unidav_wasm_free`.

See [the implementation plan](ACTION_PLAN.md) and [technical specification](SPECIFICATION.md).
