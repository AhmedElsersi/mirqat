#!/usr/bin/env python3
"""
Diagnose a text disagreement between quran.db and the legacy per-surah JSON.

    python3 tools/diff_ayah_text.py 58 14
    python3 tools/diff_ayah_text.py 58          # whole surah

Tells you whether the difference is a diacritic-ENCODING difference (two valid
encodings of the same text) or a real letter difference (one source is wrong).
"""
import json, sqlite3, sys, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "assets" / "data" / "quran.db"
LEGACY = ROOT / "assets" / "data" / "ayahs"   # <surah3>.json, CLAUDE.md A.5 shape

# every Arabic combining mark, including the "open" tanween forms
MARKS = {c for c in map(chr, range(0x0600, 0x0900)) if unicodedata.combining(c)}
MARKS |= {chr(c) for c in range(0x08F0, 0x08F3)}          # open fathatan/dammatan/kasratan
MARKS |= {chr(c) for c in range(0x06D6, 0x06ED)}          # small high marks, sukun variants

def skeleton(s: str) -> str:
    """Letters only — strips every diacritic and space.

    Decomposes first: U+0622 (alef with madda) and U+0627 U+0653 are the same
    text, and stripping marks without NFD reports them as different letters.
    """
    s = unicodedata.normalize("NFD", s)
    return "".join(ch for ch in s if ch not in MARKS and not ch.isspace())

def codepoints(s: str) -> str:
    return " ".join(f"{ord(c):04X}" for c in s)

def legacy_text(surah: int, ayah: int) -> str:
    path = LEGACY / f"{surah:03d}.json"
    if not path.exists():
        return ""
    data = json.loads(path.read_text(encoding="utf-8"))
    for rec in data.get("ayahs", []):
        if rec.get("number") == ayah:
            return rec.get("text") or ""
    return ""

def compare(surah, ayah):
    db = sqlite3.connect(DB)
    new = db.execute("SELECT text FROM ayahs WHERE surah=? AND ayah=?",
                     (surah, ayah)).fetchone()[0]
    db.close()
    old = legacy_text(surah, ayah)
    if not old:
        print(f"{surah}:{ayah}  legacy text not found — point LEGACY at the right folder")
        return
    same_letters = skeleton(old) == skeleton(new)
    print(f"\n=== {surah}:{ayah}")
    print(f"  letters identical: {same_letters}")
    if same_letters:
        print("  -> DIACRITIC ENCODING DIFFERENCE, not a textual error.")
    else:
        print("  -> REAL LETTER DIFFERENCE. Stop and check against a printed mushaf.")
        for i, (a, b) in enumerate(zip(skeleton(old), skeleton(new))):
            if a != b:
                print(f"     first divergence at letter {i}: {a!r} vs {b!r}")
                break
    if old != new:
        print(f"  old: {old}")
        print(f"  new: {new}")
        for i, (a, b) in enumerate(zip(old, new)):
            if a != b:
                print(f"  first raw diff at index {i}: "
                      f"{codepoints(old[i:i+3])}  vs  {codepoints(new[i:i+3])}")
                break

if __name__ == "__main__":
    s = int(sys.argv[1])
    if len(sys.argv) > 2:
        compare(s, int(sys.argv[2]))
    else:
        db = sqlite3.connect(DB)
        n = db.execute("SELECT ayah_count FROM surahs WHERE id=?", (s,)).fetchone()[0]
        db.close()
        for a in range(1, n + 1):
            compare(s, a)
