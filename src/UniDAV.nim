# SPDX-License-Identifier: Apache-2.0
import UniDAV/[client, component, contentline, davxml, document, editing, etag,
  journal_sync, json_formats,
  jscontact, projection, pull_sync, recurrence, service_discovery, sqlite_store, sync,
  timezone_registry, timezone_recurrence]
export client, component, contentline, davxml, document, editing, etag,
    journal_sync, json_formats, jscontact, pull_sync,
  projection, recurrence, service_discovery, sqlite_store, sync,
      timezone_registry,
  timezone_recurrence

when not defined(emscripten):
  import UniDAV/http_transport
  export http_transport

const UniDAVVersion* = "0.1.0"
