# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## The table of contents, and the two settings that decide the theme.
##
## Four chapters, because the standard asks a chapter for ten slots and a
## single page cannot show them separately. What a reader takes from this book
## is not fibonacci; it is the shape.
import std/tables
import nimibook
# `from ... import` and not a plain import: the theme module re-exports nimib
# for the chapters, and nimib's NbConfig has a `favicon_escaped` field too, so
# a plain import makes `book.favicon_escaped` below ambiguous.
from lituus_theme import faviconTag

var book = initBookWithToc:
  entry("UniDAV", "index.nim")
  entry("Fibonacci", "fibonacci.nim")
  entry("Contracts", "contracts.nim")
  entry("Surfaces", "surfaces.nim")

book.title = "UniDAV"
book.description = "The scaffold every lituus-lab Uni* engine starts from."

# The two BookConfig fields that select a theme. nimibook's inline script picks
# between them with `prefers-color-scheme`, and localStorage overrides.
book.default_theme = "lituus-light"
book.preferred_dark_theme = "lituus-dark"
book.theme_option = {"lituus-light": "Light", "lituus-dark": "Dark"}.toTable

# From the theme package, not from a path beside this checkout: CI checks out
# one repository. Without it nimibook ships nimib's default, a whale emoji.
book.favicon_escaped = faviconTag()

nimibookCli(book)
