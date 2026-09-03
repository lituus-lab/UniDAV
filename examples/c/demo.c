// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
// The same shapes as examples/demo.nim, through the C ABI. Every entry point
// takes and returns JSON or a wire document as a NUL-terminated string, so a
// caller needs no Nim type and no struct layout.
#include <stdio.h>
#include "UniDAV.h"

// Every string this ABI returns is the caller's to free. Printing and freeing
// in one place is what keeps that from being forgotten per call site.
static int show(const char *label, char *owned) {
  if (owned == NULL) {
    printf("%-12s FAILED (status %d)\n", label, unidav_status());
    return 1;
  }
  printf("%-12s %s\n", label, owned);
  unidav_free(owned);
  return 0;
}

int main(void) {
  printf("UniDAV %s\n", unidav_version());

  static const char *card =
      "begin:vcard\nversion:4.0\nuid:urn:uuid:ada\nfn:Ada Lovelace\n"
      "email:ada@example.org\nend:vcard\n";

  int failures = 0;
  failures += show("valid:", unidav_validate_json(card));
  failures += show("normalised:", unidav_normalize(card));
  failures += show("projected:", unidav_project_json(card));
  failures += show("jcard:", unidav_to_jcard(card));
  failures += show("occurrences:",
                   unidav_expand_recurrence("20260105T090000Z",
                                            "FREQ=WEEKLY;BYDAY=MO",
                                            "20260101T000000Z",
                                            "20260201T000000Z", 10));

  // A document that is not one: the failure is a NULL return with a status,
  // never an exception crossing the boundary.
  char *refused = unidav_validate_json("this is not a vCard");
  printf("%-12s %s (status %d)\n", "refused:",
         refused == NULL ? "NULL" : refused, unidav_status());
  unidav_free(refused);

  return failures == 0 ? 0 : 1;
}
