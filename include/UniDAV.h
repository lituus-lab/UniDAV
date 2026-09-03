// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNIDAV_H
#define UNIDAV_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNIDAV_VERSION_MAJOR 0
#define UNIDAV_VERSION_MINOR 1
#define UNIDAV_VERSION_PATCH 0
#define UNIDAV_VERSION "0.1.0"

#define UNIDAV_VERSION_AT_LEAST(ma, mi, pa) \
  ((UNIDAV_VERSION_MAJOR > (ma)) || \
   (UNIDAV_VERSION_MAJOR == (ma) && UNIDAV_VERSION_MINOR > (mi)) || \
   (UNIDAV_VERSION_MAJOR == (ma) && UNIDAV_VERSION_MINOR == (mi) && \
    UNIDAV_VERSION_PATCH >= (pa)))

/* Largest n with unidav_fibonacci(n) fitting in long long (int64). */
#define UNIDAV_FIB_MAX_N 92

/* Static version string; do not free. */
const char *unidav_version(void);

/* fibonacci(n), n clamped to [0, UNIDAV_FIB_MAX_N].
 * n < 0 -> 0; n > UNIDAV_FIB_MAX_N -> fibonacci(UNIDAV_FIB_MAX_N).
 * Never raises. Single-threaded, reentrant. */
long long unidav_fibonacci(int n);

#ifdef __cplusplus
}
#endif

#endif /* UNIDAV_H */
