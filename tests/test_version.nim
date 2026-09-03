# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## The version and the domain bound, stated in six places, checked to agree.
##
## Nimble refuses anything but a string literal for `version`, so the manifest
## cannot import a shared constant and no amount of arranging makes one file
## the source the others derive from. What is achievable is proof: this test
## reads every copy and fails when one drifts, which is what a release needs
## before it can claim manifest = header = wheel = tag.
import std/[unittest, os, strutils]
import UniDAV

const Root = currentSourcePath().parentDir.parentDir

proc stated(path, key, opener, closer: string): string =
  ## The first `key … opener VALUE closer` on one line of the file; an empty
  ## `closer` reads to the end of the line. Deliberately crude: a parser per
  ## format would be more code than the thing it checks.
  for line in readFile(Root / path).splitLines:
    let at = line.find(key)
    if at < 0: continue
    let opens = line.find(opener, at + key.len)
    if opens < 0: continue
    let value = line[opens + opener.len .. ^1]
    if closer.len == 0: return value.strip
    let closes = value.find(closer)
    if closes < 0: continue
    return value[0 ..< closes]
  ""

proc valueOf(path, key, opener, closer: string): string =
  ## `stated`, and a failure when it finds nothing.
  ##
  ## The empty string it returns silently makes a check that compares two of
  ## them pass while reading neither. That happened in UniMCP, on both sides of
  ## the same check at once; a missing value is a failed test here.
  result = stated(path, key, opener, closer)
  doAssert result.len > 0,
    "test_version: nothing matched `" & key & "` … `" & opener & "` in " & path

suite "one version, six copies":
  let manifest = valueOf("UniDAV.nimble", "version", "\"", "\"")

  test "the manifest states one":
    check manifest.len > 0
    check manifest.count('.') == 2

  test "the Nim constant agrees":
    check UniDAVVersion == manifest

  test "the C header agrees, macros and string alike":
    let parts = manifest.split('.')
    check valueOf("include/UniDAV.h", "UNIDAV_VERSION_MAJOR", " ",
        "") == parts[0]
    check valueOf("include/UniDAV.h", "UNIDAV_VERSION_MINOR", " ",
        "") == parts[1]
    check valueOf("include/UniDAV.h", "UNIDAV_VERSION_PATCH", " ",
        "") == parts[2]
    check valueOf("include/UniDAV.h", "define UNIDAV_VERSION ", "\"",
        "\"") == manifest

  test "the C ABI reports it":
    # Read from the source rather than called: this suite links no C library.
    check valueOf("src/UniDAV/c_api.nim", "Version: cstring", "\"",
        "\"") == manifest

  test "the Python distribution agrees":
    check valueOf("py/pyproject.toml", "version", "\"", "\"") == manifest

  test "the Python test expects it":
    check valueOf("py/tests/test_binding.py", "unidav.version()", "\"",
        "\"") == manifest
