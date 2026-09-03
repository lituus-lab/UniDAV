# UniDAV Python binding

The package exposes the UniDAV C ABI for validation, lossless normalization,
projection patches, bounded UTC recurrence expansion, explicit VTIMEZONE offset lookup, and RFC
7095/7265 jCard/jCal conversion, and bounded JSContact 2.0/vCard conversion with RFC 9555
`vCardProps` preservation. `status()` exposes the last ABI status (`0` success, `1` invalid
input, `2` caught engine failure).

`expand_recurrence_local()` expands wall-clock occurrences through a supplied bounded `VTIMEZONE`
definition and returns UTC occurrence strings.

`validate_availability()` validates the bounded RFC 7953 `calendar-availability`/
`VAVAILABILITY` shape without calculating free/busy locally.

`merge()` performs a lossless base/local/remote property merge and returns the merged document
plus explicit conflict paths; unresolved conflicts never mutate the SQLite store.

For a source checkout, build the native library first:

```sh
nimble pyLib
cd py
python -m pip install -e .
python -m pytest -q
```

The source distribution carries the required Nim engine sources and can rebuild
the library when Nim and nimble are available. Runtime payloads and credentials
are never logged by the binding.
