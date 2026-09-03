# SPDX-License-Identifier: Apache-2.0
import std/[json, times]
import client, component, document, editing, json_formats, jscontact,
    projection,
    recurrence,
    timezone_registry,
  timezone_recurrence

const Version: cstring = "0.1.0"

const
  UniDavStatusOk = 0.cint
  UniDavStatusInvalidInput = 1.cint
  UniDavStatusFailure = 2.cint

var lastStatus {.threadvar.}: cint

proc failStatus(): cstring =
  lastStatus = UniDavStatusFailure
  nil

proc ownedCString(value: string): cstring =
  let memory = cast[cstring](alloc(value.len + 1))
  if value.len > 0: copyMem(memory, unsafeAddr value[0], value.len)
  cast[ptr char](cast[uint](memory) + value.len.uint)[] = '\0'
  memory


# A shared library runs NimMain from DllMain (Windows) or an ELF constructor;
# a static one has neither, so nothing initializes the Nim runtime. The first
# entry point then enters Nim code whose globals were never set up and the
# process faults. The static-library tasks pass -d:noAutoInit; shared
# builds must not, or NimMain runs twice.
when defined(noAutoInit):
  # A once primitive, not a plain flag: two threads reaching an entry point
  # together would both see the flag unset, both call NimMain, and the second
  # would enter Nim code the first had not finished initializing. The platform
  # primitives block the losers until the winner returns, which a flag cannot.
  #
  # C statics, not Nim globals: module initialization would reset a Nim one and
  # NimMain would run again. NimMain is declared here too — the generated
  # prototype comes after this section.
  {.emit: """/*VARSECTION*/
void NimMain(void);
#ifdef _WIN32
#  include <windows.h>
static INIT_ONCE unidav_runtime_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK unidav_runtime_init(PINIT_ONCE o, PVOID p, PVOID *c) {
  (void)o; (void)p; (void)c; NimMain(); return TRUE;
}
static void unidav_runtime_ensure(void) {
  InitOnceExecuteOnce(&unidav_runtime_once, unidav_runtime_init, NULL, NULL);
}
#else
#  include <pthread.h>
static pthread_once_t unidav_runtime_once = PTHREAD_ONCE_INIT;
static void unidav_runtime_init(void) { NimMain(); }
static void unidav_runtime_ensure(void) {
  pthread_once(&unidav_runtime_once, unidav_runtime_init);
}
#endif
""".}
  template ensureRuntime() =
    {.emit: "  unidav_runtime_ensure();".}
else:
  template ensureRuntime() = discard


{.push exportc, cdecl, dynlib.}
proc unidav_status*(): cint =
  ensureRuntime()
  lastStatus

proc unidav_version*(): cstring =
  ensureRuntime()
  lastStatus = UniDavStatusOk
  Version

proc unidav_validate_json*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return ownedCString($( %*{"valid": false, "diagnostics": [
      {"severity": "dsError", "line": 0, "message": "null input"}
    ]}))
  try:
    lastStatus = UniDavStatusOk
    ownedCString(validationJson($input))
  except CatchableError as error:
    lastStatus = UniDavStatusInvalidInput
    ownedCString($( %*{"valid": false, "diagnostics": [
      {"severity": "dsError", "line": 0, "message": error.msg}
    ]}))

proc unidav_normalize*(input: cstring): cstring =
  ## Returns a deterministic CRLF document. Caller owns it through unidav_free.
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(normalizeDocument($input))
  except CatchableError:
    failStatus()

proc unidav_project_json*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(projectionJson($input))
  except CatchableError: failStatus()

proc unidav_validate_availability*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString($( %*{"valid": validCalendarAvailability($input)}))
  except CatchableError: failStatus()

proc unidav_merge_three_way*(base, local, remote: cstring): cstring =
  ensureRuntime()
  if base.isNil or local.isNil or remote.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    let outcome = mergeThreeWay($base, $local, $remote)
    var conflicts = newJArray()
    for conflict in outcome.conflicts:
      conflicts.add(%*{"path": conflict.path, "property": conflict.property})
    lastStatus = UniDavStatusOk
    ownedCString($(%*{"document": outcome.document, "conflicts": conflicts}))
  except CatchableError: failStatus()

proc unidav_patch_projection*(input, patchJson: cstring): cstring =
  ensureRuntime()
  if input.isNil or patchJson.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(patchedDocument($input, $patchJson))
  except CatchableError: failStatus()

proc unidav_to_jcard*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(jCardJson($input))
  except CatchableError: failStatus()

proc unidav_from_jcard*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(documentFromJCard($input))
  except CatchableError: failStatus()

proc unidav_to_jcal*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(jCalJson($input))
  except CatchableError: failStatus()

proc unidav_from_jcal*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(documentFromJCal($input))
  except CatchableError: failStatus()

proc unidav_to_jscontact*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(jsContactFromVCard($input))
  except CatchableError: failStatus()

proc unidav_from_jscontact*(input: cstring): cstring =
  ensureRuntime()
  if input.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    lastStatus = UniDavStatusOk
    ownedCString(vCardFromJsContact($input))
  except CatchableError: failStatus()

proc unidav_expand_recurrence*(startValue, rule, firstValue, lastValue: cstring;
    maxOccurrences: cint): cstring =
  ensureRuntime()
  if startValue.isNil or rule.isNil or firstValue.isNil or
      lastValue.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    let first = parse($firstValue, "yyyyMMdd'T'HHmmss'Z'", utc())
    let last = parse($lastValue, "yyyyMMdd'T'HHmmss'Z'", utc())
    let values = expandRecurrence($startValue, $rule,
      RecurrenceWindow(first: first, last: last,
          maxOccurrences: maxOccurrences.int))
    var output = newJArray()
    for value in values: output.add(%value)
    lastStatus = UniDavStatusOk
    ownedCString($output)
  except CatchableError: failStatus()

proc unidav_timezone_offset*(vtimezone, tzid, localValue: cstring): cstring =
  ensureRuntime()
  if vtimezone.isNil or tzid.isNil or localValue.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    let roots = parseComponents($vtimezone)
    if roots.len != 1:
      lastStatus = UniDavStatusInvalidInput
      return nil
    let registry = newTimezoneRegistry()
    registry.registerTimezone(roots[0])
    lastStatus = UniDavStatusOk
    ownedCString($(%*{"offsetSeconds": registry.offsetAt($tzid, $localValue)}))
  except CatchableError: failStatus()

proc unidav_expand_recurrence_local*(vtimezone, startValue, rule, tzid,
    firstValue, lastValue: cstring; maxOccurrences: cint): cstring =
  ensureRuntime()
  if vtimezone.isNil or startValue.isNil or rule.isNil or tzid.isNil or
      firstValue.isNil or lastValue.isNil:
    lastStatus = UniDavStatusInvalidInput
    return nil
  try:
    let roots = parseComponents($vtimezone)
    if roots.len != 1:
      lastStatus = UniDavStatusInvalidInput
      return nil
    let registry = newTimezoneRegistry()
    registry.registerTimezone(roots[0])
    let first = parse($firstValue, "yyyyMMdd'T'HHmmss'Z'", utc())
    let last = parse($lastValue, "yyyyMMdd'T'HHmmss'Z'", utc())
    let values = expandRecurrenceLocal($startValue, $rule, $tzid, registry,
      RecurrenceWindow(first: first, last: last,
          maxOccurrences: maxOccurrences.int))
    var output = newJArray()
    for value in values: output.add(%value)
    lastStatus = UniDavStatusOk
    ownedCString($output)
  except CatchableError: failStatus()

proc unidav_free*(value: pointer) =
  ensureRuntime()
  if not value.isNil: dealloc(value)
{.pop.}
