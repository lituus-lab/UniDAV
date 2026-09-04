# UniDAV benchmarks

The release benchmark uses generated, deterministic PIM corpora and keeps
every result live through a non-inline sink. It measures local CPU work only;
network latency and server behavior are excluded.

```sh
build/unigate bench          # measure, into bench/.results.md
build/unigate benchReadme    # insert this machine's block below
```

Through the gate, never `nimble <task>` bare: nimble exits 0 even when an
`exec` inside a task failed, so a green run tells you only that nimble ran.

`benchReadme` replaces only the block for the current machine. Generated
fragments are ignored; published numbers therefore come from an explicit run.

Each block is tagged with the machine, and carries the Nim version and build
mode it was measured with -- a number without those is not comparable to
another.

Read them as orders of magnitude, not measurements. Two runs on the same
machine minutes apart gave 1350 and 2480 ns/op for the same vCard parse: what
else the machine was doing dominates. A block is useful for spotting a change
of shape, not a few per cent. A slug like `macosx-arm64` is the fallback the exporter uses when it
cannot read the CPU's brand string, so it names a family rather than a
machine; one like `macosx-apple-m4` names the machine itself.

<!-- bench:insert -->

<!-- bench:machine=macosx-apple-m4 -->
| operation | ns/op | ops/sec |
|---|---:|---:|
| parse vCard | 2480.5 | 403145 |
| parse iCalendar | 3155.5 | 316907 |
| serialize vCard | 894.5 | 1117943 |
| project vCard | 8132.5 | 122963 |
| expand weekly recurrence | 23364.0 | 42801 |
| resolve VTIMEZONE offset | 535.0 | 1869159 |

<!-- bench:nim=2.2.10 mode=release -->
<!-- bench:command=nimble bench -->
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

