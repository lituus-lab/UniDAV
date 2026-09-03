<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# unidav — Python binding

Distributed as `lituus-unidav`, imported as `unidav`: the two names
are separate decisions, and the bare names are not all available on PyPI.

```bash
pip install lituus-unidav
```

From a checkout, `build/unigate pyTest` builds the extension and runs the tests
in one step. The pieces, if you want them apart:

```bash
build/unigate pyLib          # the C library the extension links against
build/unigate buildCython    # the extension, in place
build/unigate pyWheel        # a wheel in py/dist/
```

```python
import unidav

unidav.version()        # the C library's version
unidav.FIB_MAX_N        # 92, read from the C header, not restated here
unidav.fibonacci(10)    # 55
```

`fibonacci` raises `TypeError` for a non-int and `ValueError` outside
`[0, FIB_MAX_N]`. The C ABI clamps instead of reporting; the binding is where
the domain becomes an error, because Python callers expect one.
