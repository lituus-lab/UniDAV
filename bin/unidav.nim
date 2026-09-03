# SPDX-License-Identifier: Apache-2.0
import std/[os]
import UniDAV/[document, projection]

proc usage() =
  stderr.writeLine("usage: unidav <validate|normalize|project|kind> <file.vcf|file.ics>")
  stderr.writeLine("  validate  emit diagnostics; exit 1 for invalid input")
  stderr.writeLine("  normalize emit deterministic CRLF serialization")
  stderr.writeLine("  project   emit the lossless thin-host JSON projection")
  stderr.writeLine("  kind      emit vCard, iCalendar, or unknown")

if paramCount() == 1 and paramStr(1) in ["help", "--help", "-h"]:
  usage()
  quit(0)
if paramCount() != 2 or paramStr(1) notin ["validate", "normalize", "project", "kind"]:
  usage()
  quit(2)

try:
  let input = readFile(paramStr(2))
  case paramStr(1)
  of "validate":
    echo validationJson(input)
    if not isValid(input): quit(1)
  of "normalize":
    if not isValid(input):
      stderr.writeLine("unidav: refusing to normalize an invalid document")
      quit(1)
    stdout.write(normalizeDocument(input))
  of "project":
    if not isValid(input):
      stderr.writeLine("unidav: refusing to project an invalid document")
      quit(1)
    echo projectionJson(input)
  of "kind":
    echo $detectKind(input)
  else: discard
except CatchableError as error:
  stderr.writeLine("unidav: " & error.msg)
  quit(1)
