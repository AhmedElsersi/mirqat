#!/usr/bin/env python3
"""Generates test/fixtures/nfc_cases.json — the differential corpus that checks
Dart's hand-rolled NFC against Python's reference implementation.

    python3 tools/gen_nfc_cases.py
"""
import json
import random
import sqlite3
import unicodedata

random.seed(20260907)

BASES = [0x0627, 0x0648, 0x064A, 0x06C1, 0x06D2, 0x06D5,
         0x0628, 0x062A, 0x0644, 0x0645, 0x0646, 0x0647, 0x0631]
PRECOMPOSED = [0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x06C0, 0x06C2, 0x06D3]
MARKS = [cp for cp in range(0x0600, 0x0700) if unicodedata.combining(chr(cp))]

OUT = "test/fixtures/nfc_cases.json"


def main() -> None:
    cases: list[dict[str, str]] = []

    def add(s: str) -> None:
        cases.append({"in": s, "out": unicodedata.normalize("NFC", s)})

    # Random clusters, with marks deliberately out of canonical order.
    for _ in range(4000):
        s = ""
        for _ in range(random.randint(1, 5)):
            s += chr(random.choice(BASES + PRECOMPOSED))
            for _ in range(random.randint(0, 4)):
                s += chr(random.choice(MARKS))
            if random.random() < 0.3:
                s += " "
        add(s)

    # Every canonical pair, both directions, and with a mark wedged between.
    for cp in PRECOMPOSED:
        d = [int(x, 16) for x in unicodedata.decomposition(chr(cp)).split()]
        add(chr(cp))
        add(chr(d[0]) + chr(d[1]))
        add(chr(d[0]) + chr(0x0650) + chr(d[1]))
        add(chr(d[0]) + chr(d[1]) + chr(0x0650))

    for s in ["", " ", "ٓ", "ٕٔ", "abc", "123 abc",
              "آأ", "لَّ"]:
        add(s)

    # The shipped text of the first surah, as stored and in NFD.
    db = sqlite3.connect("assets/data/quran.db")
    first = db.execute("SELECT MIN(id) FROM surahs").fetchone()[0]
    for (text,) in db.execute(
        "SELECT text FROM ayahs WHERE surah = ? ORDER BY ayah", (first,)
    ):
        add(text)
        add(unicodedata.normalize("NFD", text))
    db.close()

    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(cases, fh, ensure_ascii=False, indent=0)

    changed = sum(1 for c in cases if c["in"] != c["out"])
    print(f"wrote {OUT}: {len(cases)} cases, {changed} of them non-identity")


if __name__ == "__main__":
    main()
