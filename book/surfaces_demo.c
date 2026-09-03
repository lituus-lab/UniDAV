/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 lituus-lab */
/* Run by book/surfaces.nim during the book build; its output is the page's. */
#include <stdio.h>
#include "UniDAV.h"

int main(void) {
  printf("unidav_version()            = %s\n", unidav_version());
  printf("unidav_fibonacci(10)        = %lld\n", unidav_fibonacci(10));
  printf("unidav_fibonacci(-1)        = %lld   (clamped, not an error)\n",
         unidav_fibonacci(-1));
  printf("unidav_fibonacci(200)       = %lld   (clamped to n = %d)\n",
         unidav_fibonacci(200), UNIDAV_FIB_MAX_N);
  return 0;
}
