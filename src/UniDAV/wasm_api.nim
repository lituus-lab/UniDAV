# SPDX-License-Identifier: Apache-2.0
import c_api

proc unidav_wasm_status*(): cint {.exportc, cdecl.} =
  unidav_status()

proc unidav_wasm_validate*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_validate_json(input)

proc unidav_wasm_normalize*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_normalize(input)

proc unidav_wasm_project*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_project_json(input)

proc unidav_wasm_validate_availability*(input: cstring): cstring {.
    exportc, cdecl.} =
  unidav_validate_availability(input)

proc unidav_wasm_merge_three_way*(base, local, remote: cstring): cstring {.
    exportc, cdecl.} =
  unidav_merge_three_way(base, local, remote)

proc unidav_wasm_patch*(input, patchJson: cstring): cstring {.exportc, cdecl.} =
  unidav_patch_projection(input, patchJson)

proc unidav_wasm_to_jcard*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_to_jcard(input)

proc unidav_wasm_from_jcard*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_from_jcard(input)

proc unidav_wasm_to_jcal*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_to_jcal(input)

proc unidav_wasm_from_jcal*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_from_jcal(input)

proc unidav_wasm_to_jscontact*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_to_jscontact(input)

proc unidav_wasm_from_jscontact*(input: cstring): cstring {.exportc, cdecl.} =
  unidav_from_jscontact(input)

proc unidav_wasm_expand_recurrence*(startValue, rule, firstValue,
    lastValue: cstring; maxOccurrences: cint): cstring {.exportc, cdecl.} =
  unidav_expand_recurrence(startValue, rule, firstValue, lastValue, maxOccurrences)

proc unidav_wasm_timezone_offset*(vtimezone, tzid,
    localValue: cstring): cstring {.
    exportc, cdecl.} =
  unidav_timezone_offset(vtimezone, tzid, localValue)

proc unidav_wasm_expand_recurrence_local*(vtimezone, startValue, rule, tzid,
    firstValue, lastValue: cstring; maxOccurrences: cint): cstring {.
    exportc, cdecl.} =
  unidav_expand_recurrence_local(vtimezone, startValue, rule, tzid, firstValue,
    lastValue, maxOccurrences)

proc unidav_wasm_free*(value: pointer) {.exportc, cdecl.} =
  unidav_free(value)
