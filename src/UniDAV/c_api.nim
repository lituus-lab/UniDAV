# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## C ABI for UniDAV. Built --app:staticlib/--app:lib --noMain --mm:arc
## -d:release. Keep in sync with include/UniDAV.h; tests/c links the header
## against this lib, so a header that drifts fails to compile rather than at a
## caller's site.
##
## No Nim exception crosses this boundary: `{.raises: [].}` on every entry
## point is what proves it rather than a convention that has to be remembered.
import ../UniDAV

const UniDAVVersionC: cstring = "0.1.0"

# Unmangled C symbols, C calling convention, exported from the shared lib.
# --noMain suppresses the generated entry point and with it every auto-init
# hook: neither the static nor the shared build emits a DllMain or an ELF
# constructor, so nothing initializes the Nim runtime. The first entry point
# then enters Nim code whose globals were never set up. The shared build was
# assumed to be covered by a loader hook it does not have -- its registries
# stayed empty and the contrast entry answered nan. Every --noMain task passes
# -d:noAutoInit; an ordinary executable linking this module must not, since its
# own main already ran NimMain.
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

{.push exportc, cdecl, dynlib, raises: [].}

proc unidav_fibonacci(n: cint): clonglong =
  ## fibonacci(n), n clamped to [0, FibMaxN]: n < 0 gives 0, n > FibMaxN gives
  ## fibonacci(FibMaxN). Clamps rather than reporting, because the question has
  ## an answer at every n a caller can express.
  ensureRuntime()
  let m = int(n)
  if m < 0:
    return clonglong(0)
  if m > FibMaxN:
    return fibonacci(FibMaxN).clonglong
  fibonacci(m).clonglong

proc unidav_version(): cstring =
  ## Static version string; do not free.
  ensureRuntime()
  UniDAVVersionC

{.pop.}
