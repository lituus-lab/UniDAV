# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, osproc, strutils]
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "The C surface"

const Root = currentSourcePath().parentDir.parentDir

proc run(command: string): string =
  ## A non-zero exit stops the book. Returning the failure as text instead would
  ## publish a page whose "output" is a traceback, from a build that reported
  ## success.
  let (output, code) = execCmdEx("cd " & Root.quoteShell & " && " & command)
  result = output.strip
  if code != 0:
    raise newException(OSError,
      "book: `" & command & "` exited " & $code & "\n" & result)

nbText: """
# The C surface

Strings in, strings out. Every entry point takes a wire document or JSON as a
NUL-terminated string and answers with one, so a caller needs no Nim type and
no struct layout — and neither side has to agree on a calendar model.

```c
const char *unidav_version(void);
int   unidav_status(void);
char *unidav_validate_json(const char *input);
char *unidav_normalize(const char *input);
char *unidav_project_json(const char *input);
char *unidav_to_jcard(const char *input);
char *unidav_expand_recurrence(const char *start, const char *rule,
                               const char *first, const char *last, int max);
void  unidav_free(void *value);
```

## Two rules about memory

- **What you get back is yours.** Every `char *` return is allocated for the
  caller and freed with `unidav_free`, exactly once. This is the opposite of
  the borrowed-pointer convention some engines in this family use, and the
  header says so at each entry point rather than once at the top.
- **NULL means it failed.** The reason is a code from `unidav_status`, not an
  exception: nothing thrown in Nim crosses this boundary.

## Driven from C

`examples/c/demo.c` is compiled and run here.
"""

nbCode:
  echo run("cc -Iinclude -o build/book_c_demo examples/c/demo.c libUniDAV.a" &
          " $(test \"$(uname)\" = Darwin && echo -lcurl || echo -lcurl)" &
          " && ./build/book_c_demo")

nbText: """
No Nim runtime call appears in that program, and none is needed: every entry
point initializes the runtime itself, once, through a platform once-primitive.
The library is built `--noMain`, which suppresses the constructor a shared
library would otherwise get — without that guard the first call would run
against globals nobody had set up.

The link line names `-lcurl` because the engine's own hardened transport is
compiled from `csrc/`; on Windows it is `-lwinhttp` instead. Nothing links
SQLite: the sync cache goes through UniDatabase, which compiles the SQLite
amalgamation in, so there is no library to find and none loaded at run time.
"""

nbSave
