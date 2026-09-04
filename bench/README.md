# UniDAV benchmarks

The release benchmark uses generated, deterministic PIM corpora and keeps
every result live through a non-inline sink. It measures local CPU work only;
network latency and server behavior are excluded.

```sh
nimble bench
nimble benchReadme
```

`benchReadme` replaces only the block for the current machine. Generated
fragments are ignored; published numbers therefore come from an explicit run.

<!-- bench:insert -->

<!-- bench:machine=macosx-apple-m4 -->
| operation | ns/op | ops/sec |
|---|---:|---:|
| parse vCard | 1708.0 | 585480 |
| parse iCalendar | 2483.5 | 402658 |
| serialize vCard | 611.0 | 1636661 |
| project vCard | 4672.0 | 214041 |
| expand weekly recurrence | 11248.5 | 88901 |
<!-- /bench:machine=macosx-apple-m4 -->

<!-- bench:machine=macosx-arm64 -->
| operation | ns/op | ops/sec |
|---|---:|---:|
| parse vCard | 1388.0 | 720461 |
| parse iCalendar | 1738.0 | 575374 |
| serialize vCard | 586.5 | 1705030 |
| project vCard | 3871.5 | 258298 |
| expand weekly recurrence | 9703.5 | 103056 |
| resolve VTIMEZONE offset | 218.0 | 4587156 |
<!-- /bench:machine=macosx-arm64 -->

