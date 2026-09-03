# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""unidav — Python binding over the UniDAV C library."""
from ._core import fibonacci as _fib_c, version as _version_c, FIB_MAX_N

__version__ = _version_c().decode("ascii")


def fibonacci(n):
    """fib(n) as int. n in [0, FIB_MAX_N]; raises ValueError/TypeError outside."""
    if not isinstance(n, int):
        raise TypeError(f"n must be int, got {type(n).__name__}")
    if not 0 <= n <= FIB_MAX_N:
        raise ValueError(f"n must be in [0, {FIB_MAX_N}], got {n}")
    return _fib_c(n)


def version():
    """C library version string."""
    return _version_c().decode("ascii")


__all__ = ["fibonacci", "version", "FIB_MAX_N", "__version__"]
