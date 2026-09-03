# SPDX-License-Identifier: Apache-2.0
## Differential acceptance and extension-retention checks against test-only
## common PIM implementations. The oracle never prints fixture payloads.
import std/[json, osproc, strutils, unittest]

import UniDAV

proc oracleReport(kind, path: string): JsonNode =
  let command = "python3 tests/oracles/python_oracles.py " & kind & " " & path
  let execution = execCmdEx(command)
  if execution.exitCode != 0:
    raise newException(IOError,
      "oracle process failed; install tests/oracles/requirements.txt")
  parseJson(execution.output)

suite "common format oracles":
  test "vCard round-trips through vobject with its extension retained":
    let path = "tests/oracles/fixtures/contact.vcf"
    let source = readFile(path)
    check isValid(source)
    check documentFromJCard(jCardJson(source)).contains("X-UNIDAV-ORACLE")
    let report = oracleReport("vcard", path)["reports"]
    check report.len == 1
    check report[0]["oracle"].getStr == "vobject"
    check report[0]["accepted"].getBool
    check report[0]["extensionRetained"].getBool

  test "iCalendar round-trips through two independent common oracles":
    let path = "tests/oracles/fixtures/calendar.ics"
    let source = readFile(path)
    check isValid(source)
    check documentFromJCal(jCalJson(source)).contains("X-UNIDAV-ORACLE")
    let reports = oracleReport("icalendar", path)["reports"]
    check reports.len == 2
    for report in reports:
      check report["accepted"].getBool
      check report["extensionRetained"].getBool
