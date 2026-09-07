#!/usr/bin/env python3
"""Checks that the bundled Quran fonts have a glyph for every codepoint in the
shipped ayah text. A missing glyph renders as a tofu box in scripture, so this
should be run whenever a surah is added.

    python3 tools/check_font_coverage.py

Exits non-zero if any codepoint is uncovered.
"""
import glob
import json
import struct
import sys
import unicodedata

FONTS = [
    "assets/fonts/KFGQPCHafs-Uthmanic-v18.ttf",
    "assets/fonts/AmiriQuran.ttf",
]


def cmap_codepoints(path: str) -> set[int]:
    """Every codepoint mapped to a non-zero glyph, from the font's cmap."""
    d = open(path, "rb").read()
    num_tables = struct.unpack(">H", d[4:6])[0]
    tables = {}
    off = 12
    for _ in range(num_tables):
        tag, _cks, o, ln = struct.unpack(">4sIII", d[off:off + 16])
        off += 16
        tables[tag.decode("latin1")] = (o, ln)

    co = tables["cmap"][0]
    n = struct.unpack(">H", d[co + 2:co + 4])[0]
    cps: set[int] = set()

    for i in range(n):
        sub = co + struct.unpack(">HHI", d[co + 4 + i * 8:co + 12 + i * 8])[2]
        fmt = struct.unpack(">H", d[sub:sub + 2])[0]

        if fmt == 4:
            seg_x2 = struct.unpack(">H", d[sub + 6:sub + 8])[0]
            seg = seg_x2 // 2
            ends = struct.unpack(f">{seg}H", d[sub + 14:sub + 14 + seg_x2])
            starts = struct.unpack(f">{seg}H", d[sub + 16 + seg_x2:sub + 16 + 2 * seg_x2])
            deltas = struct.unpack(f">{seg}h", d[sub + 16 + 2 * seg_x2:sub + 16 + 3 * seg_x2])
            ro_off = sub + 16 + 3 * seg_x2
            ranges = struct.unpack(f">{seg}H", d[ro_off:ro_off + seg_x2])
            for k in range(seg):
                for c in range(starts[k], min(ends[k], 0xFFFF) + 1):
                    if c == 0xFFFF:
                        continue
                    if ranges[k] == 0:
                        g = (c + deltas[k]) & 0xFFFF
                    else:
                        gi = ro_off + k * 2 + ranges[k] + (c - starts[k]) * 2
                        if gi + 2 > len(d):
                            continue
                        g = struct.unpack(">H", d[gi:gi + 2])[0]
                        if g:
                            g = (g + deltas[k]) & 0xFFFF
                    if g:
                        cps.add(c)

        elif fmt == 12:
            ngroups = struct.unpack(">I", d[sub + 12:sub + 16])[0]
            for k in range(ngroups):
                s, e, _gid = struct.unpack(">III", d[sub + 16 + k * 12:sub + 28 + k * 12])
                cps.update(range(s, e + 1))

    return cps


def main() -> int:
    needed: set[int] = set()
    for path in sorted(glob.glob("assets/data/ayahs/*.json")):
        doc = json.load(open(path, encoding="utf-8"))
        for ayah in doc["ayahs"]:
            needed |= {ord(c) for c in ayah["text"] if c != " "}

    if not needed:
        print("no ayah text found under assets/data/ayahs/", file=sys.stderr)
        return 1

    failed = False
    for font in FONTS:
        have = cmap_codepoints(font)
        missing = sorted(needed - have)
        name = font.rsplit("/", 1)[-1]
        if missing:
            failed = True
            detail = ", ".join(
                f"U+{c:04X} {unicodedata.name(chr(c), '?')}" for c in missing
            )
            print(f"FAIL {name}: {len(missing)} missing — {detail}")
        else:
            print(f"ok   {name}: covers all {len(needed)} codepoints "
                  f"({len(have)} glyphs)")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
