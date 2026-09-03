#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Run independent Python PIM parsers without printing personal payloads."""

import argparse
import json
from pathlib import Path


def result(name, accepted, retained, version):
    return {
        "oracle": name,
        "accepted": accepted,
        "extensionRetained": retained,
        "version": version,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("vcard", "icalendar"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    payload = args.path.read_bytes()
    marker = b"X-UNIDAV-ORACLE"
    reports = []

    import vobject

    try:
        parsed = vobject.readOne(payload.decode("utf-8"))
        rendered = parsed.serialize().encode("utf-8")
        vobject.readOne(rendered.decode("utf-8"))
        reports.append(result("vobject", True, marker in rendered,
                              getattr(vobject, "__version__", "unknown")))
    except Exception:
        reports.append(result("vobject", False, False,
                              getattr(vobject, "__version__", "unknown")))

    if args.kind == "icalendar":
        import icalendar

        try:
            parsed = icalendar.Calendar.from_ical(payload)
            rendered = parsed.to_ical()
            icalendar.Calendar.from_ical(rendered)
            reports.append(result("icalendar", True, marker in rendered,
                                  getattr(icalendar, "__version__", "unknown")))
        except Exception:
            reports.append(result("icalendar", False, False,
                                  getattr(icalendar, "__version__", "unknown")))

    print(json.dumps({"reports": reports}, separators=(",", ":")))


if __name__ == "__main__":
    main()
