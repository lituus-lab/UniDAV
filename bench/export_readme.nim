# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Inserts the current machine's measured block into bench/README.md.
import std/[os, osproc, strutils]

proc slugify(value: string): string =
  result = value.toLowerAscii.multiReplace(
    (" ", "-"), ("(", ""), (")", ""), ("_", "-"))
  while "--" in result:
    result = result.replace("--", "-")
  result = result.strip(chars = {'-'})

proc machineSlug(): string =
  ## The override goes through the same normalisation as a detected name: it
  ## ends up inside an HTML comment marker, and a value with a space or a
  ## bracket makes a marker the exporter cannot find again. A value that
  ## normalises to nothing is no name at all, so detection runs instead.
  if existsEnv("UNIDAV_BENCH_MACHINE"):
    let override = slugify(getEnv("UNIDAV_BENCH_MACHINE"))
    if override.len > 0:
      return override
  var processor = hostCPU
  when defined(macosx):
    let (brand, code) = execCmdEx("sysctl -n machdep.cpu.brand_string")
    if code == 0 and brand.strip.len > 0:
      processor = brand.strip
  elif defined(linux):
    let content = readFile("/proc/cpuinfo")
    for line in content.splitLines:
      if line.startsWith("model name"):
        processor = line.split(':', 1)[^1].strip
        break
  slugify(hostOS & "-" & processor)

proc main() =
  const
    readmePath = "bench/README.md"
    resultsPath = "bench/.results.md"
    marker = "<!-- bench:insert -->"
  if not fileExists(resultsPath):
    quit("benchReadme: run `nimble bench` first", 1)
  let slug = machineSlug()
  let startTag = "<!-- bench:machine=" & slug & " -->"
  let endTag = "<!-- /bench:machine=" & slug & " -->"
  let renderedBlock = startTag & "\n" & readFile(resultsPath).strip & "\n" & endTag
  let current = readFile(readmePath)
  if startTag in current:
    let first = current.find(startTag)
    let last = current.find(endTag, first)
    if last < 0:
      quit("benchReadme: unterminated machine block", 1)
    writeFile(readmePath, current[0 ..< first] & renderedBlock &
      current[last + endTag.len .. ^1])
  else:
    let position = current.find(marker)
    if position < 0:
      quit("benchReadme: insertion marker is missing", 1)
    let after = position + marker.len
    writeFile(readmePath, current[0 ..< after] & "\n\n" & renderedBlock &
      current[after .. ^1])

when isMainModule:
  main()
