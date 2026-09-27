#!/usr/bin/env python3
"""Checks every length-limited field in the store listings.

    tool/check_store_listing.py                 # both listings
    tool/check_store_listing.py docs/PLAY_LISTING.md

A field is a `<!-- field: <name> <lang> <limit> -->` comment followed by a
fenced block. Both stores count characters, so this does too.
Exits non-zero if anything is over its limit, and for keywords also if a comma
is followed by a space (which only wastes the budget).
"""
import re
import sys

LISTINGS = ["store/apple/LISTING.md", "docs/PLAY_LISTING.md"]

bad = 0
for path in sys.argv[1:] or LISTINGS:
    text = open(path, encoding="utf-8").read()
    fields = re.findall(
        r"<!-- field: (\w+) (\w+) (\d+) -->.*?```\n(.*?)\n```", text, flags=re.S
    )
    if not fields:
        sys.exit(f"{path}: no fields found — has the file's format changed?")

    print(path)
    for name, lang, limit, body in fields:
        n, limit = len(body), int(limit)
        problems = []
        if n > limit:
            problems.append(f"{n - limit} over")
        if name == "keywords" and ", " in body:
            problems.append("space after a comma")
        print(f"  {name:12} {lang}  {n:4} / {limit:<4} {'  '.join(problems) or 'ok'}")
        bad += bool(problems)
sys.exit(1 if bad else 0)
