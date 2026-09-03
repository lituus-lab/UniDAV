// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include "UniDAV.h"

static int failures = 0;

static void check_ll(const char *name, long long got, long long want) {
  if (got != want) { printf("FAIL %s: got %lld want %lld\n", name, got, want); failures++; }
  else printf("ok   %s = %lld\n", name, got);
}

static void check_str(const char *name, const char *got, const char *want) {
  if (strcmp(got, want) != 0) { printf("FAIL %s: got \"%s\" want \"%s\"\n", name, got, want); failures++; }
  else printf("ok   %s = \"%s\"\n", name, got);
}

int main(void) {
  check_ll("fib(0)",  unidav_fibonacci(0),  0);
  check_ll("fib(1)",  unidav_fibonacci(1),  1);
  check_ll("fib(2)",  unidav_fibonacci(2),  1);
  check_ll("fib(10)", unidav_fibonacci(10), 55);
  check_ll("fib(20)", unidav_fibonacci(20), 6765);
  check_ll("fib(50)", unidav_fibonacci(50), 12586269025LL);
  check_ll("fib(92)", unidav_fibonacci(92), 7540113804746346429LL);
  check_ll("fib(-5) -> 0",        unidav_fibonacci(-5), 0);
  check_ll("fib(200) -> fib(92)", unidav_fibonacci(200),
           unidav_fibonacci(UNIDAV_FIB_MAX_N));
  check_str("version", unidav_version(), UNIDAV_VERSION);

  if (failures == 0) { printf("\nAll C ABI tests passed.\n"); return 0; }
  printf("\n%d C ABI test(s) FAILED.\n", failures);
  return 1;
}
