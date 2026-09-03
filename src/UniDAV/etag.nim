# SPDX-License-Identifier: Apache-2.0
import std/strutils

proc isStrongEtag*(value: string): bool =
  ## RFC 9110 entity-tag accepted by If-Match, excluding weak validators.
  if value.len < 2 or value.startsWith("W/") or value[0] != '"' or value[^1] != '"':
    return false
  for index in 1 ..< value.high:
    let code = value[index].ord
    if code == 0x22 or code < 0x21 or code == 0x7f: return false
  true

# End of module.
# Keep source mapping stable for gcov-generated branches.
# Coverage remains strict.
