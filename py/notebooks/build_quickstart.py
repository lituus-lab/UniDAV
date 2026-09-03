# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Author py/notebooks/quickstart.ipynb, then execute it so the committed file
carries real outputs for GitHub to render. Run from the repo root:

    python3 py/notebooks/build_quickstart.py

CI re-executes the notebook against an installed wheel; this script only
regenerates it after an API change."""
import os

import nbformat as nbf
from nbclient import NotebookClient

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "quickstart.ipynb")

CELLS = [
    ("md", """# UniDAV — Python quickstart

`unidav` is a Cython extension over the UniDAV C ABI, shipped as a
self-contained wheel: the native library travels inside the package, so
installing it needs neither Nim nor a compiler.

```
pip install unidav
```

UniDAV reads and writes vCard and iCalendar, and speaks CardDAV and CalDAV.
Its rule is lossless: the ordered document tree is the source of truth, and a
property the library does not understand survives a round trip untouched.

CI executes this notebook against the wheel the release actually publishes, so
an output below that stops matching fails the build."""),
    ("md", "## The API"),
    ("code", """import json

import unidav

unidav.version()"""),
    ("md", """## Validate, then normalise

Validation reports; it does not throw. A document that is wrong is still a
document you can look at, which is what importing a file from an unknown
source needs."""),
    ("code", """card = ("begin:vcard\\nversion:4.0\\nuid:urn:uuid:ada\\n"
        "fn:Ada Lovelace\\nemail:ada@example.org\\n"
        "x-phone-model:something\\nend:vcard\\n")

unidav.validate(card)"""),
    ("md", """Normalising puts line endings, folding and case right — and leaves
`X-PHONE-MODEL`, which UniDAV has no opinion about, exactly where it was.
Normalising is not filtering."""),
    ("code", 'unidav.normalize(card).split("\\r\\n")'),
    ("md", """## The typed view

A host that wants a name and an address should not have to walk a component
tree. The projection is a *view*: take it to display, keep the document to
store."""),
    ("code", """projection = unidav.project(card)
projection["kind"], projection["uid"], projection["name"]["full"]"""),
    ("md", """`x-phone-model` is absent from the projection and present in the
document. A host round-tripping through the projection alone would drop it."""),
    ("code", '"x-phone-model" in json.dumps(projection).lower()'),
    ("md", "## The JSON encodings"),
    ("code", "unidav.to_jcard(unidav.normalize(card))"),
    ("md", """## Merging is where a sync client lives

Two sides changed the same contact. `merge` takes the common ancestor and both
versions, and answers with a document plus the conflicts it could not decide —
rather than picking a winner quietly."""),
    ("code", """base  = "BEGIN:VCARD\\r\\nVERSION:4.0\\r\\nUID:a\\r\\nFN:Ada\\r\\nEND:VCARD\\r\\n"
local = base.replace("FN:Ada", "FN:Grace")

agreed = unidav.merge(base, local, base)
print("merged FN:Grace:", "FN:Grace" in agreed["document"])
print("conflicts:      ", agreed["conflicts"])"""),
    ("code", """both = base.replace("FN:Ada", "FN:Katherine")
clash = unidav.merge(base, local, both)
print("both sides changed it, conflicts:", len(clash["conflicts"]))"""),
    ("md", """## Recurrence

Every expansion is given a window and a ceiling. A rule with neither UNTIL nor
COUNT is unbounded by definition, so the caller says where to stop rather than
the library guessing."""),
    ("code", """unidav.expand_recurrence("20260105T090000Z", "FREQ=WEEKLY;BYDAY=MO",
                         "20260101T000000Z", "20260201T000000Z", 10)"""),
    ("md", """## The C ABI underneath

The same engine is reachable from anything that speaks C: strings in, strings
out.

```c
char *unidav_normalize(const char *input);
char *unidav_project_json(const char *input);
void  unidav_free(void *value);
```

There every returned string is the caller's, freed exactly once with
`unidav_free`, and a failure is a NULL return with a code in `unidav_status` —
an exception must never unwind across an ABI boundary.

See `include/UniDAV.h`, and the book for the full picture."""),
]


def main():
    nb = nbf.v4.new_notebook()
    nb.cells = [
        nbf.v4.new_markdown_cell(src) if kind == "md" else nbf.v4.new_code_cell(src)
        for kind, src in CELLS
    ]
    nb.metadata["kernelspec"] = {
        "display_name": "Python 3",
        "language": "python",
        "name": "python3",
    }
    # Execute from the repo root, never from py/: there, `import unidav`
    # would resolve to the py/unidav source tree instead of the installed
    # package, and the notebook would stop testing what it claims to test.
    NotebookClient(nb, timeout=120, kernel_name="python3",
                   resources={"metadata": {"path": ROOT}}).execute()
    with open(OUT, "w") as f:
        nbf.write(nb, f)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
