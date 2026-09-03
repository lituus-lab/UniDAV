# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
cdef extern from "UniDAV.h":
    const char *unidav_version()
    long long unidav_fibonacci(int n)
    # The domain bound comes from the header rather than being restated here:
    # one copy fewer to drift, and the Python check enforces exactly what the
    # C ABI clamps to.
    int UNIDAV_FIB_MAX_N


FIB_MAX_N = UNIDAV_FIB_MAX_N


def fibonacci(int n):
    """Raw C call (no domain check). Use unidav.fibonacci."""
    return unidav_fibonacci(n)


def version():
    return unidav_version()
