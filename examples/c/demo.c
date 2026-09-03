// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include <stdio.h>
#include "UniDAV.h"

int main(void) {
  printf("UniDAV %s\n", unidav_version());
  int ns[] = {0, 1, 10, 20, 50, 90, UNIDAV_FIB_MAX_N};
  for (size_t i = 0; i < sizeof(ns) / sizeof(ns[0]); i++)
    printf("fib(%d) = %lld\n", ns[i], unidav_fibonacci(ns[i]));
  return 0;
}
