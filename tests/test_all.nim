# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Every suite in one binary. Coverage instruments a single compilation, so a
## second one into the same nimcache would overwrite the first one's data and
## report whichever ran last.
{.push warning[UnusedImport]: off.}
import test_formats
import test_dav
import test_client
import test_recurrence
import test_timezone_registry
# The transport suite opens real sockets, which the Windows runner refuses in
# the sandbox CI gives it.
when not defined(windows): import test_http_transport
import test_version
{.pop.}
