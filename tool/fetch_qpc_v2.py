#!/usr/bin/env python3
"""Fetches the QPC V2 print's glyph codes and layout, word by word.

QUL publishes this as "QPC V2 Glyph - Word by Word" behind a sign-in; the
public quran.com API (v4), which serves QUL's data, gives the same thing for
each page of the V2 mushaf (`mushaf=1`): every word's glyph code in that
page's font (`code_v2`), its page and line in the V2 print, and its text in
the KFGQPC Hafs script (`text_qpc_hafs`) — which is what lets
tool/build_quran_data.py pin each glyph to a word of quran.db by text rather
than by position.

Writes data/sources/qpc-v2-words.json:

    {"source": ..., "words": [[surah, ayah, position, type, glyph, page,
                                line, text], ...]}   in reading order

Pages already fetched are kept in CACHE (default build/qpc_v2_api) so an
interrupted run picks up where it stopped.

    python3 tool/fetch_qpc_v2.py [CACHE]
"""

import json
import os
import sys
import time
import urllib.request

PAGES = 604
API = ("https://api.quran.com/api/v4/verses/by_page/{page}?words=true"
       "&word_fields=code_v2,page_number,line_number,text_qpc_hafs"
       "&mushaf=1&per_page=300")
# The API turns away Python's default user agent.
HEADERS = {"User-Agent": "Mozilla/5.0 (Macintosh) mirqat-build-tool",
           "Accept": "application/json"}
OUT = os.path.join("data", "sources", "qpc-v2-words.json")


def fetch(page, cache):
    path = os.path.join(cache, f"{page}.json")
    if os.path.exists(path):
        return json.load(open(path))
    for attempt in range(6):
        try:
            req = urllib.request.Request(API.format(page=page), headers=HEADERS)
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.load(r)
            break
        except Exception as e:  # noqa: BLE001 — retried, then reported
            print(f"  page {page}: {e!r}, retrying", flush=True)
            time.sleep(2 * (attempt + 1))
    else:
        sys.exit(f"error: page {page} could not be fetched")
    words = [
        [int(v["verse_key"].split(":")[0]), int(v["verse_key"].split(":")[1]),
         w["position"], w["char_type_name"], w["code_v2"], w["page_number"],
         w["line_number"], w.get("text_qpc_hafs")]
        for v in data["verses"] for w in v["words"]
    ]
    json.dump(words, open(path, "w"), ensure_ascii=False)
    time.sleep(0.15)
    return words


def main():
    cache = sys.argv[1] if len(sys.argv) > 1 else os.path.join("build", "qpc_v2_api")
    os.makedirs(cache, exist_ok=True)
    words = []
    for page in range(1, PAGES + 1):
        words.extend(fetch(page, cache))
        if page % 50 == 0:
            print(f"  {page}/{PAGES}", flush=True)
    with open(OUT, "w") as f:
        json.dump({"source": "api.quran.com v4, mushaf=1 (QPC V2)",
                   "words": words}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(words):,} words -> {OUT}")


if __name__ == "__main__":
    main()
