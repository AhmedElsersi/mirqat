#!/usr/bin/env python3
"""Packs the QPC V2 page fonts for the CDN, and lists them for the app.

The KFGQPC QCF2 mushaf is set in 604 fonts, one per page: each word of a page
is one glyph of that page's font, under the code `quran.db` keeps for it in
`words.glyph_v2`. Together they weigh about 200 MB — far too much to bundle —
so they are published beside the audio, and the app fetches a page's font the
first time that page is drawn in this face (or all of them, if the reader
asks).

This writes, from a folder holding p1.ttf .. p604.ttf (QUL's "QPC V2 Font"
download, unpacked):

  OUT/p001.ttf.gz .. OUT/p604.ttf.gz   gzip -9, mtime 0: the same input always
                                       gives the same bytes, so a re-run uploads
                                       nothing new
  assets/data/qpc_v2_fonts.json        {schemaVersion, path, pages: [{n, bytes,
                                       sha256}]} — what the app checks every
                                       download against before it uses it

  python3 tool/build_qpc_fonts.py ~/Downloads/"QPC V2 Font.ttf" build/qpc_v2
  dart run tool/publish_fonts.dart build/qpc_v2

Each source file is refused unless it is a TrueType font, so a wrong folder
fails here rather than on someone's phone.
"""

import gzip
import hashlib
import json
import os
import sys

PAGES = 604
PATH_TEMPLATE = "fonts/qpc-v2/p{n3}.ttf.gz"
MANIFEST = os.path.join("assets", "data", "qpc_v2_fonts.json")


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 3:
        die("usage: build_qpc_fonts.py SOURCE_DIR OUT_DIR")
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    pages = []
    for n in range(1, PAGES + 1):
        path = os.path.join(src, f"p{n}.ttf")
        if not os.path.isfile(path):
            die(f"{path} is missing")
        data = open(path, "rb").read()
        if data[:4] not in (b"\x00\x01\x00\x00", b"true"):
            die(f"{path} is not a TrueType font")
        packed = gzip.compress(data, compresslevel=9, mtime=0)
        name = f"p{n:03d}.ttf.gz"
        with open(os.path.join(out, name), "wb") as f:
            f.write(packed)
        pages.append({
            "n": n,
            "bytes": len(packed),
            "sha256": hashlib.sha256(packed).hexdigest(),
        })
    manifest = {
        "schemaVersion": 1,
        "path": PATH_TEMPLATE,
        "pages": pages,
    }
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, separators=(",", ":"))
        f.write("\n")
    total = sum(p["bytes"] for p in pages)
    print(f"{len(pages)} pages, {total / 1e6:.1f} MB packed -> {out}")
    print(f"wrote {MANIFEST}")


if __name__ == "__main__":
    main()
