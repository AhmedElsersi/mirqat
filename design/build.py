#!/usr/bin/env python3
"""Builds the design mockups in design/screens/ from design/src/.

Every word of Quran in these mockups comes from assets/data/quran.db, byte for
byte, the same as in the app (CLAUDE.md A.2 rule 1): the templates name an ayah
or a page and this script fills it in. Nothing Quranic is typed by hand.

Template tokens:
    {{ayah S:A}}               the ayah's text
    {{words S:A:FROM-TO}}      words FROM..TO of the ayah (1-based, markers out)
    {{surah N}}                the surah's Arabic name
    {{ayahs N}}                its ayah count, in Arabic-Indic digits
    {{marked S:A FROM-TO}}     the whole ayah, words FROM..TO marked as shared
    {{page N [hl=S:A] [veil=S:A] [range=S:A-S:A] [lines=A-B]}}
                               a mushaf page, line by line (or only some lines)
    {{cells N [full=A-B,C] [half=A-B] [rep=A,B]}}
                               one cell per ayah of surah N, by memorisation state
    {{n 123}}                  a number in Arabic-Indic digits

Each template starts with `<!-- title: ... -->` and may say
`<!-- chrome: none -->` for a screen without the status bar.

    python3 design/build.py
"""

import html
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT.parent / "assets" / "data" / "quran.db"
SRC = ROOT / "src"
OUT = ROOT / "screens"

db = sqlite3.connect(DB)
DIGITS = "٠١٢٣٤٥٦٧٨٩"


def n(value):
    return "".join(DIGITS[int(c)] if c.isdigit() else c for c in str(value))


def ref(text):
    s, a = text.split(":")
    return int(s), int(a)


def ayah(s, a):
    row = db.execute("SELECT text FROM ayahs WHERE surah=? AND ayah=?", (s, a)).fetchone()
    if row is None:
        raise SystemExit(f"no ayah {s}:{a}")
    return row[0]


def words(s, a, lo, hi):
    rows = db.execute(
        "SELECT text FROM words WHERE surah=? AND ayah=? AND is_marker=0 "
        "ORDER BY id", (s, a)).fetchall()
    return " ".join(r[0] for r in rows[lo - 1:hi])


def marked(s, a, lo, hi):
    """The ayah whole, with words lo..hi marked — a comparison, never a cut."""
    out = []
    position = 0
    for text, is_marker in db.execute(
            "SELECT text, is_marker FROM words WHERE surah=? AND ayah=? ORDER BY id",
            (s, a)).fetchall():
        if is_marker:
            out.append(f'<span class="m">{html.escape(text)}</span>')
            continue
        position += 1
        shared = " sh" if lo <= position <= hi else ""
        out.append(f'<span class="w{shared}">{html.escape(text)}</span>')
    return " ".join(out)


def spans(spec):
    picked = set()
    for part in (spec or "").split(","):
        if not part:
            continue
        if "-" in part:
            lo, hi = part.split("-")
            picked.update(range(int(lo), int(hi) + 1))
        else:
            picked.add(int(part))
    return picked


def cells(num, full=None, half=None, rep=None):
    """One cell per ayah of a surah: memorised, being memorised, not started."""
    done, started, drilled = spans(full), spans(half), spans(rep)
    out = []
    for a in range(1, ayah_count(num) + 1):
        cls = "full" if a in done else "half" if a in started else ""
        if a in drilled:
            cls = (cls + " rep").strip()
        out.append(f'<b class="{cls}">{n(a)}</b>')
    return "".join(out)


def surah_name(num):
    return db.execute("SELECT name_ar FROM surahs WHERE id=?", (num,)).fetchone()[0]


def ayah_count(num):
    return db.execute("SELECT ayah_count FROM surahs WHERE id=?", (num,)).fetchone()[0]


def page(num, hl=None, veil=None, rng=None, only=None):
    basmala = db.execute(
        "SELECT text FROM words WHERE ayah=1 AND is_marker=0 AND surah=("
        "SELECT id FROM surahs WHERE basmala_mode='first_ayah') ORDER BY id"
    ).fetchall()
    out = []
    for line_type, centred, surah, first, last in db.execute(
            "SELECT line_type, is_centered, surah_number, first_word_id, last_word_id "
            "FROM lines WHERE page=? AND line BETWEEN ? AND ? ORDER BY line",
            (num, *(only or (1, 99)))).fetchall():
        if line_type == "surah_name":
            out.append(
                f'<div class="m-line m-head"><span class="cartouche">'
                f'سورة {html.escape(surah_name(int(surah)))}</span></div>')
            continue
        if line_type == "basmallah":
            spans = "".join(f'<span class="w">{html.escape(t)}</span>' for (t,) in basmala)
            out.append(f'<div class="m-line centred">{spans}</div>')
            continue
        spans = []
        for s, a, t, marker in db.execute(
                "SELECT surah, ayah, text, is_marker FROM words "
                "WHERE id BETWEEN ? AND ? ORDER BY id", (first, last)):
            cls = ["m" if marker else "w"]
            if hl and (s, a) == hl:
                cls.append("hl")
            elif veil and (s, a) == veil:
                cls.append("veil")
            elif rng and rng[0] <= (s, a) <= rng[1]:
                cls.append("rg")
            spans.append(f'<span class="{" ".join(cls)}">{html.escape(t)}</span>')
        out.append(f'<div class="m-line{" centred" if centred else ""}">{"".join(spans)}</div>')
    return "\n".join(out)


def token(match):
    parts = match.group(1).split()
    kind, args = parts[0], parts[1:]
    if kind == "ayah":
        return html.escape(ayah(*ref(args[0])))
    if kind == "words":
        s, a, span = args[0].split(":")
        lo, hi = map(int, span.split("-"))
        return html.escape(words(int(s), int(a), lo, hi))
    if kind == "surah":
        return html.escape(surah_name(int(args[0])))
    if kind == "ayahs":
        return n(ayah_count(int(args[0])))
    if kind == "n":
        return n(args[0])
    if kind == "marked":
        s, a = ref(args[0])
        lo, hi = map(int, args[1].split("-"))
        return marked(s, a, lo, hi)
    if kind == "cells":
        opts = dict(x.split("=") for x in args[1:])
        return cells(int(args[0]), full=opts.get("full"), half=opts.get("half"),
                     rep=opts.get("rep"))
    if kind == "page":
        opts = dict(a.split("=") for a in args[1:])
        rng = None
        if "range" in opts:
            lo, hi = opts["range"].split("-")
            rng = (ref(lo), ref(hi))
        only = None
        if "lines" in opts:
            lo, hi = opts["lines"].split("-")
            only = (int(lo), int(hi))
        return page(int(args[0]),
                    hl=ref(opts["hl"]) if "hl" in opts else None,
                    veil=ref(opts["veil"]) if "veil" in opts else None,
                    rng=rng, only=only)
    raise SystemExit(f"unknown token {kind}")


STATUS = """<div class="status" aria-hidden="true"><span>٩:٤١</span>
<span class="status-icons"><i data-lucide="signal"></i><i data-lucide="wifi"></i><i data-lucide="battery-full"></i></span></div>"""

SHELL = """<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&display=swap">
<link rel="stylesheet" href="../styles/app.css">
<script src="https://unpkg.com/lucide@0.469.0/dist/umd/lucide.min.js"></script>
</head>
<body>
<div class="device{extra}">
{status}
{body}
</div>
<script src="../styles/screen.js"></script>
</body>
</html>
"""


def main():
    OUT.mkdir(exist_ok=True)
    for src in sorted(SRC.glob("*.html")):
        text = src.read_text(encoding="utf-8")
        title = re.search(r"<!-- title: (.*?) -->", text).group(1)
        bare = "<!-- chrome: none -->" in text
        body = re.sub(r"\{\{(.*?)\}\}", token, text)
        body = re.sub(r"<!-- (title|chrome): .*? -->\n?", "", body)
        (OUT / src.name).write_text(
            SHELL.format(title=html.escape(title), status="" if bare else STATUS,
                         body=body, extra=" bare" if bare else ""),
            encoding="utf-8")
        print(f"  {src.name}")


if __name__ == "__main__":
    main()
