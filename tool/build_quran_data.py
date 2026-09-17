#!/usr/bin/env python3
"""
Build assets/data/quran.db from the QUL downloads.

Sources expected in data/sources/ :
    qpc-hafs-word-by-word.db        words(id, location, surah, ayah, word, text)
    qpc-v1-15-lines.db              pages(page_number, line_number, line_type,
                                          is_centered, first_word_id, last_word_id,
                                          surah_number), info(...)
    quran-metadata-surah-name.json
    quran-metadata-ayah.json        (optional: juz / hizb / sajda)
    quran-metadata-juz.json         (optional fallback)
    quran-metadata-hizb.json        (optional fallback)
    quran-metadata-sajda.json       (optional fallback)

Usage:
    python3 tools/build_quran_data.py
    python3 tools/build_quran_data.py --inspect     # print JSON shapes and exit
"""

import hashlib
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "sources"
OUT = ROOT / "assets" / "data"

SCRIPT_DB = SRC / "qpc-hafs-word-by-word.db"
LAYOUT_DB = SRC / "qpc-v1-15-lines.db"
SURAH_JSON = SRC / "quran-metadata-surah-name.json"
AYAH_JSON = SRC / "quran-metadata-ayah.json"

ARABIC_DIGITS = set("٠١٢٣٤٥٦٧٨٩")

SCHEMA = """
PRAGMA journal_mode = DELETE;

CREATE TABLE surahs (
  id            INTEGER PRIMARY KEY,
  name_ar       TEXT NOT NULL,
  name_translit TEXT NOT NULL,
  ayah_count    INTEGER NOT NULL,
  revelation    TEXT,
  start_page    INTEGER NOT NULL,
  basmala_mode  TEXT NOT NULL
    CHECK (basmala_mode IN ('none', 'first_ayah', 'separate'))
);

CREATE TABLE ayahs (
  id            INTEGER PRIMARY KEY,
  surah         INTEGER NOT NULL,
  ayah          INTEGER NOT NULL,
  text          TEXT NOT NULL,
  page          INTEGER NOT NULL,
  juz           INTEGER,
  hizb          INTEGER,
  sajda         INTEGER NOT NULL DEFAULT 0,
  sajda_type    TEXT,
  first_word_id INTEGER NOT NULL,
  last_word_id  INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_ayah_key  ON ayahs(surah, ayah);
CREATE INDEX        idx_ayah_page ON ayahs(page);

CREATE TABLE words (
  id        INTEGER PRIMARY KEY,
  surah     INTEGER NOT NULL,
  ayah      INTEGER NOT NULL,
  position  INTEGER NOT NULL,
  text      TEXT NOT NULL,
  is_marker INTEGER NOT NULL DEFAULT 0,
  page      INTEGER,
  line      INTEGER
);
CREATE INDEX idx_word_page ON words(page, line);
CREATE INDEX idx_word_ayah ON words(surah, ayah, position);

CREATE TABLE lines (
  page          INTEGER NOT NULL,
  line          INTEGER NOT NULL,
  line_type     TEXT NOT NULL,
  is_centered   INTEGER NOT NULL DEFAULT 0,
  surah_number  INTEGER,
  first_word_id INTEGER,
  last_word_id  INTEGER,
  PRIMARY KEY (page, line)
);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
"""


# ---------------------------------------------------------------- helpers

def die(msg):
    print(f"\n  BUILD FAILED: {msg}\n", file=sys.stderr)
    sys.exit(1)


def pick(d, *candidates):
    """First present, non-null key from candidates."""
    for c in candidates:
        if c in d and d[c] is not None:
            return d[c]
    return None


def as_records(raw):
    """Normalise dict-keyed-by-id or list JSON into a list of dicts."""
    if isinstance(raw, list):
        return [r for r in raw if isinstance(r, dict)]
    if isinstance(raw, dict):
        # {"1": {...}} or {"chapters": [...]} or {"1:1": {...}}
        for key in ("chapters", "surahs", "data", "verses", "ayahs", "result"):
            if key in raw:
                return as_records(raw[key])
        out = []
        for k, v in raw.items():
            if isinstance(v, dict):
                v = dict(v)
                v.setdefault("_key", k)
                out.append(v)
        return out
    return []


def skeleton(s):
    """Arabic letters only — every diacritic, digit, space and mark removed."""
    import unicodedata
    return "".join(c for c in (s or "") if unicodedata.category(c) == "Lo")


def is_marker(text):
    t = (text or "").strip()
    return bool(t) and all(ch in ARABIC_DIGITS for ch in t)


def inspect():
    for path in sorted(SRC.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        recs = as_records(raw)
        print(f"\n=== {path.name}")
        print(f"    top-level: {type(raw).__name__}, records: {len(recs)}")
        if recs:
            print(f"    keys: {sorted(recs[0].keys())}")
            print(f"    first: {json.dumps(recs[0], ensure_ascii=False)[:300]}")


# ---------------------------------------------------------------- build

def load_words(out):
    src = sqlite3.connect(SCRIPT_DB)
    rows = src.execute(
        "SELECT id, surah, ayah, word, text FROM words ORDER BY id"
    ).fetchall()
    src.close()
    if not rows:
        die("the words table in the script DB is empty")

    out.executemany(
        "INSERT INTO words (id, surah, ayah, position, text, is_marker) "
        "VALUES (?,?,?,?,?,?)",
        [(r[0], r[1], r[2], r[3], (r[4] or '').strip(),
          1 if is_marker(r[4]) else 0) for r in rows],
    )
    print(f"  words: {len(rows):,}")
    markers = out.execute("SELECT COUNT(*) FROM words WHERE is_marker = 1").fetchone()[0]
    print(f"  ayah-number markers detected: {markers:,}")
    return markers


def load_layout(out):
    src = sqlite3.connect(LAYOUT_DB)
    try:
        info = src.execute("SELECT * FROM info").fetchone()
        print(f"  layout info: {info}")
    except sqlite3.Error:
        pass

    rows = src.execute(
        "SELECT page_number, line_number, line_type, is_centered, "
        "       surah_number, first_word_id, last_word_id "
        "FROM pages ORDER BY page_number, line_number"
    ).fetchall()
    src.close()
    if not rows:
        die("the pages table in the layout DB is empty")

    out.executemany(
        "INSERT INTO lines (page, line, line_type, is_centered, surah_number, "
        "                   first_word_id, last_word_id) VALUES (?,?,?,?,?,?,?)",
        [(r[0], r[1], r[2], r[3] or 0, r[4], r[5], r[6]) for r in rows],
    )
    print(f"  layout lines: {len(rows):,}")

    # stamp page/line onto every word covered by an ayah line.
    # one ranged UPDATE per line (indexed primary key) — far faster than a
    # correlated subquery across ~77k words.
    out.executemany(
        "UPDATE words SET page = ?, line = ? WHERE id BETWEEN ? AND ?",
        [(r[0], r[1], r[5], r[6]) for r in rows if r[5] is not None and r[6] is not None],
    )
    orphans = out.execute("SELECT COUNT(*) FROM words WHERE page IS NULL").fetchone()[0]
    if orphans:
        die(f"{orphans:,} words are not covered by any layout line — your layout DB and "
            f"script DB are not a matching pair")


def build_ayahs(out):
    out.execute(
        "INSERT INTO ayahs (surah, ayah, text, page, first_word_id, last_word_id) "
        "SELECT surah, ayah, "
        "       (SELECT group_concat(w2.text, ' ') FROM ("
        "           SELECT text FROM words w3 "
        "           WHERE w3.surah = w.surah AND w3.ayah = w.ayah AND w3.is_marker = 0 "
        "           ORDER BY w3.position) w2), "
        "       MIN(page), MIN(id), MAX(id) "
        "FROM words w GROUP BY surah, ayah ORDER BY surah, ayah"
    )
    import re as _re
    fixed = 0
    for aid, txt in out.execute("SELECT id, text FROM ayahs").fetchall():
        clean = _re.sub(r"\s+", " ", txt).strip()
        if clean != txt:
            out.execute("UPDATE ayahs SET text = ? WHERE id = ?", (clean, aid))
            fixed += 1
    n = out.execute("SELECT COUNT(*) FROM ayahs").fetchone()[0]
    print(f"  ayahs: {n:,} (whitespace normalised in {fixed:,})")


def build_surahs(out):
    if not SURAH_JSON.exists():
        die(f"missing {SURAH_JSON.name}")
    recs = as_records(json.loads(SURAH_JSON.read_text(encoding="utf-8")))
    if not recs:
        die(f"could not read any records from {SURAH_JSON.name} — run with --inspect")

    by_id = {}
    for r in recs:
        sid = pick(r, "id", "surah_number", "chapter_id", "number", "index", "_key")
        try:
            sid = int(sid)
        except (TypeError, ValueError):
            continue
        by_id[sid] = r

    if len(by_id) != 114:
        die(f"{SURAH_JSON.name} gave {len(by_id)} surahs, expected 114. "
            f"Keys present: {sorted(recs[0].keys())} — run with --inspect and send me this.")

    rows = []
    for sid in range(1, 115):
        r = by_id[sid]
        name_ar = pick(r, "name_arabic", "name_ar", "arabic")
        translit = pick(r, "name_simple", "name", "transliteration", "name_translit")
        revelation = pick(r, "revelation_place", "revelation", "type", "place")
        bismillah_pre = pick(r, "bismillah_pre", "bismillahPre")
        if bismillah_pre is not None:
            expected = "separate" if bismillah_pre else ("first_ayah" if sid == 1 else "none")
            if expected != {1: "first_ayah", 9: "none"}.get(sid, "separate"):
                die(f"surah {sid}: bismillah_pre={bismillah_pre} contradicts the "
                    f"basmala_mode rule — check the source file")
        ayah_count = out.execute(
            "SELECT COUNT(*) FROM ayahs WHERE surah = ?", (sid,)).fetchone()[0]
        start_page = out.execute(
            "SELECT MIN(page) FROM ayahs WHERE surah = ?", (sid,)).fetchone()[0]
        # 'first_ayah': Al-Fatiha, where the basmala IS ayah 1.
        # 'none':       At-Tawba, which has no basmala.
        # 'separate':   every other surah — basmala precedes ayah 1 and is not part of it.
        basmala_mode = {1: "first_ayah", 9: "none"}.get(sid, "separate")
        if not name_ar or not translit:
            die(f"surah {sid} is missing a name: name_ar={name_ar!r} translit={translit!r}")
        rows.append((sid, name_ar, translit, ayah_count,
                     (revelation or "").lower() or None, start_page, basmala_mode))

    out.executemany(
        "INSERT INTO surahs (id, name_ar, name_translit, ayah_count, "
        "revelation, start_page, basmala_mode) VALUES (?,?,?,?,?,?,?)", rows)
    print(f"  surahs: {len(rows)}")


def _expand_mapping(mapping):
    """{"1": "1-7", "2": "1-141"} -> [(surah, ayah), ...]"""
    out = []
    for surah, spec in mapping.items():
        surah = int(surah)
        spec = str(spec)
        lo, _, hi = spec.partition("-")
        for a in range(int(lo), int(hi or lo) + 1):
            out.append((surah, a))
    return out


def apply_ranges(out, path, field, number_key, expected_count):
    """juz / hizb come as verse_mapping ranges, not per-ayah rows."""
    if not path.exists():
        print(f"  ! {path.name} missing, {field} left NULL")
        return
    recs = as_records(json.loads(path.read_text(encoding="utf-8")))
    if len(recs) != expected_count:
        die(f"{path.name}: expected {expected_count} records, got {len(recs)}")
    n = 0
    for r in recs:
        num = pick(r, number_key, "number", "_key")
        mapping = pick(r, "verse_mapping")
        if mapping is None:
            die(f"{path.name}: no verse_mapping key — keys are {sorted(r.keys())}")
        pairs = _expand_mapping(mapping)
        out.executemany(
            f"UPDATE ayahs SET {field} = ? WHERE surah = ? AND ayah = ?",
            [(int(num), s_, a_) for (s_, a_) in pairs])
        n += len(pairs)
    missing = out.execute(
        f"SELECT COUNT(*) FROM ayahs WHERE {field} IS NULL").fetchone()[0]
    print(f"  {field}: {n:,} assignments, {missing} ayahs unassigned")
    if missing:
        die(f"{missing} ayahs have no {field}")


def apply_sajdas(out, path):
    if not path.exists():
        print("  ! sajda file missing")
        return
    recs = as_records(json.loads(path.read_text(encoding="utf-8")))
    for r in recs:
        key = pick(r, "verse_key")
        stype = pick(r, "sajdah_type", "type")
        surah, _, ayah = str(key).partition(":")
        out.execute(
            "UPDATE ayahs SET sajda = 1, sajda_type = ? WHERE surah = ? AND ayah = ?",
            (stype, int(surah), int(ayah)))
    n = out.execute("SELECT COUNT(*) FROM ayahs WHERE sajda = 1").fetchone()[0]
    print(f"  sajdas: {n}")


def cross_check_ayahs(out, path, skip_text=False):
    """quran-metadata-ayah.json carries words_count and an independent text copy."""
    if not path.exists():
        print("  ! ayah metadata missing, skipping cross-check")
        return
    recs = as_records(json.loads(path.read_text(encoding="utf-8")))
    if len(recs) != 6236:
        die(f"{path.name}: expected 6236 records, got {len(recs)}")

    word_bad, text_bad = [], []
    for r in recs:
        key = pick(r, "verse_key", "_key")
        surah = pick(r, "surah_number", "surah")
        ayah = pick(r, "ayah_number", "ayah")
        if surah is None and isinstance(key, str) and ":" in key:
            surah, _, ayah = key.partition(":")
        surah, ayah = int(surah), int(ayah)

        wc = pick(r, "words_count")
        if wc is not None:
            got = out.execute(
                "SELECT COUNT(*) FROM words WHERE surah=? AND ayah=? AND is_marker=0",
                (surah, ayah)).fetchone()[0]
            if got != int(wc):
                word_bad.append(f"{surah}:{ayah} words {got} vs metadata {wc}")

        ref = pick(r, "text")
        if ref and not skip_text:
            ours = out.execute(
                "SELECT text FROM ayahs WHERE surah=? AND ayah=?",
                (surah, ayah)).fetchone()[0]
            if skeleton(ref) != skeleton(ours):
                text_bad.append(f"{surah}:{ayah}")

    print(f"  cross-check: {len(word_bad)} word-count differences, "
          f"{len(text_bad)} text-letter mismatches")

    # Tokenisation differences are NOT errors. Sources legitimately disagree on where a
    # word boundary falls when the Uthmani rasm writes a name with a space inside it
    # (37:130 إل ياسين is the classic case). The script DB owns word ids, and the layout
    # references those ids, so the script DB is authoritative for rendering.
    for m in word_bad[:20]:
        print(f"    - tokenisation differs: {m}")
    if len(word_bad) > 20:
        print(f"    - ... and {len(word_bad) - 20} more")
    if len(word_bad) > 50:
        die(f"{len(word_bad)} word-count differences is too many to be tokenisation "
            f"alone — the layout and script are probably not a matching pair")

    # Letter differences ARE errors. Same letters, different marks is fine; different
    # letters means one source is wrong and nothing should be built on it.
    for m in text_bad[:10]:
        print(f"    ! LETTERS DIFFER at {m}")
    if text_bad:
        die(f"{len(text_bad)} ayahs differ in their letters, not just diacritics. "
            f"Do not proceed; report this.")


# ---------------------------------------------------------------- verify

def verify(out):
    q = lambda s: out.execute(s).fetchone()[0]
    checks = [
        ("114 surahs", "SELECT COUNT(*) FROM surahs", 114),
        ("6236 ayahs", "SELECT COUNT(*) FROM ayahs", 6236),
        ("ayah_count sums to 6236", "SELECT SUM(ayah_count) FROM surahs", 6236),
        ("604 pages", "SELECT COUNT(DISTINCT page) FROM lines", 604),
        ("no page over 15 lines",
         "SELECT COUNT(*) FROM (SELECT page FROM lines GROUP BY page "
         "HAVING COUNT(*) > 15)", 0),
        ("no empty ayah text",
         "SELECT COUNT(*) FROM ayahs WHERE text IS NULL OR text = ''", 0),
        ("no double or edge spaces in ayah text",
         "SELECT COUNT(*) FROM ayahs WHERE text LIKE '%  %' "
         "OR text LIKE ' %' OR text LIKE '% '", 0),
        ("no unplaced words", "SELECT COUNT(*) FROM words WHERE page IS NULL", 0),
        ("ayah counts match words",
         "SELECT COUNT(*) FROM surahs s WHERE s.ayah_count <> "
         "(SELECT COUNT(DISTINCT ayah) FROM words w WHERE w.surah = s.id)", 0),
        ("every surah has both names",
         "SELECT COUNT(*) FROM surahs WHERE name_ar IS NULL OR name_ar = '' "
         "OR name_translit IS NULL OR name_translit = ''", 0),
        ("every ayah has a juz", "SELECT COUNT(*) FROM ayahs WHERE juz IS NULL", 0),
        ("every ayah has a hizb", "SELECT COUNT(*) FROM ayahs WHERE hizb IS NULL", 0),
        ("juz run 1..30", "SELECT COUNT(DISTINCT juz) FROM ayahs", 30),
        ("hizb run 1..60", "SELECT COUNT(DISTINCT hizb) FROM ayahs", 60),
        ("15 sajdas", "SELECT COUNT(*) FROM ayahs WHERE sajda = 1", 15),
        ("At-Tawba basmala_mode is none",
         "SELECT basmala_mode FROM surahs WHERE id = 9", "none"),
        ("Al-Fatiha basmala_mode is first_ayah",
         "SELECT basmala_mode FROM surahs WHERE id = 1", "first_ayah"),
        ("112 surahs have a separate basmala",
         "SELECT COUNT(*) FROM surahs WHERE basmala_mode = 'separate'", 112),
        ("Al-Fatiha has 7 ayahs",
         "SELECT ayah_count FROM surahs WHERE id = 1", 7),
        ("Al-Baqarah has 286 ayahs",
         "SELECT ayah_count FROM surahs WHERE id = 2", 286),
        ("An-Nas has 6 ayahs",
         "SELECT ayah_count FROM surahs WHERE id = 114", 6),
        ("last page is 604", "SELECT MAX(page) FROM ayahs", 604),
    ]
    failed = []
    for label, sql, expected in checks:
        got = q(sql)
        ok = got == expected
        print(f"  [{'ok' if ok else 'FAIL'}] {label}: {got}")
        if not ok:
            failed.append(f"{label}: got {got}, expected {expected}")
    if failed:
        die("verification failed:\n    - " + "\n    - ".join(failed))


def sample(out):
    print("\n  --- eyeball check ---")
    for key in [(1, 1), (2, 255), (112, 1)]:
        t = out.execute("SELECT text FROM ayahs WHERE surah=? AND ayah=?", key).fetchone()
        print(f"  {key[0]}:{key[1]}  {t[0]}")
    line = out.execute(
        "SELECT page, line, line_type, is_centered, surah_number, first_word_id, "
        "last_word_id FROM lines WHERE page = 1 ORDER BY line LIMIT 3").fetchall()
    print(f"  page 1 first lines: {line}")


# ---------------------------------------------------------------- main

def main():
    if "--inspect" in sys.argv:
        inspect()
        return

    for p in (SCRIPT_DB, LAYOUT_DB, SURAH_JSON):
        if not p.exists():
            die(f"missing source file: {p}")
        if p.stat().st_size == 0:
            die(f"source file is empty (0 bytes): {p}")

    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / "quran.db"
    if target.exists():
        target.unlink()

    out = sqlite3.connect(target)
    out.executescript(SCHEMA)

    print("building:")
    load_words(out)
    load_layout(out)
    build_ayahs(out)
    build_surahs(out)
    apply_ranges(out, SRC / "quran-metadata-juz.json", "juz", "juz_number", 30)
    apply_ranges(out, SRC / "quran-metadata-hizb.json", "hizb", "hizb_number", 60)
    apply_sajdas(out, SRC / "quran-metadata-sajda.json")
    cross_check_ayahs(out, AYAH_JSON, skip_text="--no-text-check" in sys.argv)
    out.execute("INSERT INTO meta (key, value) VALUES ('schema_version', '2')")
    out.commit()

    print("\nverifying:")
    verify(out)
    sample(out)

    out.execute("VACUUM")
    out.commit()
    out.close()

    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    print(f"\n  {target.relative_to(ROOT)}  {target.stat().st_size:,} bytes")
    print(f"  sha256 {digest}")
    print("  (no surahs.json is written — the surahs table in quran.db is the catalog)")
    print("\ndone.")


if __name__ == "__main__":
    main()