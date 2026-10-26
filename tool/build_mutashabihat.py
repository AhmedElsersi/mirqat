#!/usr/bin/env python3
"""Builds assets/data/mutashabihat.json from QUL's "Mutashabihat ul Quran".

    python3 tool/build_mutashabihat.py path/to/mutashabihat.zip
    python3 tool/build_mutashabihat.py path/to/phrases.json

The source is QUL's resource 73 (https://qul.tarteel.ai/resources/mutashabihat/73),
downloaded by hand: QUL serves it only to a signed-in account. Its zip holds
phrases.json — every phrase shared between ayahs, keyed by phrase id, with
the ayahs it occurs in and the word range it covers in each — and
phrase_verses.json, the same mapping turned round, which is not needed here.

Nothing about the Quran is written by this tool. It copies QUL's references
— ayah keys and word ranges, never text — and holds every one of them to
quran.db: the ayah must exist and the range must lie inside its recited
words. A source that disagrees with the text is refused whole, naming what
disagreed: a shared phrase pointing at the wrong words would teach the
reader a confusion the mushaf does not contain.

What it may leave out is said on the command line and in the output:

  --max-ayahs N   phrases found in more than N ayahs (default 40). A phrase
                  that common — a formula repeated across the mushaf — is
                  not what makes two ayahs easy to confuse, and listing its
                  hundreds of ayahs beside each one buries the ones that are.
  --min-words N   phrases shorter than N words (default 2).
  --leave-out PHRASE:SURAH:AYAH
                  one reference of one phrase, named after looking at it,
                  where the source itself is wrong. Repeatable. Every
                  reference it names must exist, or the build is refused —
                  so a leave-out cannot outlive the error it was for. The
                  phrase keeps its other ayahs.
  --correct PHRASE:SURAH:AYAH:FROM-TO=FROM-TO
                  one range of one reference, read in quran.db and put
                  right. Repeatable. It names the source's range as well as
                  the correct one, and the build is refused unless the
                  source holds exactly that range — so a correction cannot
                  outlive the error it was for, or apply to something else.
                  The corrected range is checked like any other.

Known errors in resource 73 (as downloaded 2026-10-21), and what each needs:

  --correct 4970:48:10:23-27=23-25
      "نؤتيه أجرا عظيما" in 48:10 is its last three words, 23-25
      ("فسيؤتيه أجرا عظيما", as 4:74, 4:114 and 4:162 have it, three words);
      QUL records 23-27, past the ayah's 25 words.

Output, compact and ordered so an unchanged source rebuilds byte-identical:

  {"schemaVersion": 1, "source": "...", "phrases": [
     {"id": 50, "ayahs": [[2, 23, 15, 17], [19, 48, 4, 6]]}, ...]}
"""
import argparse
import json
import sqlite3
import sys
import zipfile

TEXT_DB = "assets/data/quran.db"
OUT = "assets/data/mutashabihat.json"
SCHEMA_VERSION = 1
SOURCE = "QUL Mutashabihat ul Quran (qul.tarteel.ai/resources/mutashabihat/73)"


def load_phrases(path: str) -> dict:
    if path.endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if n.rsplit("/", 1)[-1] == "phrases.json"]
            if len(names) != 1:
                sys.exit(f"{path}: expected one phrases.json, found {names}")
            return json.loads(z.read(names[0]).decode("utf-8"))
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def recited_word_counts(db_path: str) -> dict:
    """surah:ayah -> how many recited words (markers left out)."""
    db = sqlite3.connect(db_path)
    counts = {
        f"{s}:{a}": n
        for s, a, n in db.execute(
            "SELECT surah, ayah, COUNT(*) FROM words WHERE is_marker = 0 "
            "GROUP BY surah, ayah"
        )
    }
    db.close()
    return counts


def build(
    phrases: dict,
    counts: dict,
    max_ayahs: int,
    min_words: int,
    leave_out: frozenset = frozenset(),
    corrections: dict = None,
):
    """(kept phrases, problems, how many left out by each filter)."""
    kept = []
    problems = []
    too_common = too_short = single = 0
    unused = set(leave_out)
    corrections = corrections or {}
    uncorrected = set(corrections)

    for raw_id, phrase in phrases.items():
        try:
            pid = int(raw_id)
        except ValueError:
            problems.append(f"phrase id {raw_id!r} is not a number")
            continue
        occurrences = phrase.get("ayah") if isinstance(phrase, dict) else None
        if not isinstance(occurrences, dict):
            problems.append(f"phrase {pid}: no 'ayah' map")
            continue

        rows = []
        for key, ranges in occurrences.items():
            if (pid, key) in leave_out:
                unused.discard((pid, key))
                continue
            if key not in counts:
                problems.append(f"phrase {pid}: {key} is not an ayah of quran.db")
                continue
            if not isinstance(ranges, list):
                problems.append(f"phrase {pid}: {key} has no list of ranges")
                continue
            surah, ayah = (int(x) for x in key.split(":"))
            for r in ranges:
                fix = (pid, key, tuple(r) if isinstance(r, list) else None)
                if fix in corrections:
                    uncorrected.discard(fix)
                    r = list(corrections[fix])
                if (
                    not isinstance(r, list)
                    or len(r) != 2
                    or not all(isinstance(x, int) for x in r)
                    or not 1 <= r[0] <= r[1] <= counts[key]
                ):
                    problems.append(
                        f"phrase {pid}: {key} range {r!r} is outside its "
                        f"{counts[key]} words"
                    )
                    continue
                rows.append([surah, ayah, r[0], r[1]])

        ayahs = {(s, a) for s, a, _, _ in rows}
        if len(ayahs) < 2:
            single += 1
            continue
        if len(ayahs) > max_ayahs:
            too_common += 1
            continue
        if min(t - f + 1 for _, _, f, t in rows) < min_words:
            too_short += 1
            continue
        kept.append({"id": pid, "ayahs": sorted(rows)})

    for pid, key in sorted(unused):
        problems.append(f"--leave-out {pid}:{key} names no reference of the source")
    for pid, key, (f, t) in sorted(uncorrected):
        problems.append(f"--correct {pid}:{key}:{f}-{t} names no range of the source")
    kept.sort(key=lambda p: p["id"])
    return kept, problems, {"too_common": too_common, "too_short": too_short, "single": single}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("source", help="QUL's mutashabihat zip, or its phrases.json")
    ap.add_argument("--db", default=TEXT_DB)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--max-ayahs", type=int, default=40)
    ap.add_argument("--min-words", type=int, default=2)
    ap.add_argument("--leave-out", action="append", default=[], metavar="PHRASE:SURAH:AYAH")
    ap.add_argument(
        "--correct", action="append", default=[], metavar="PHRASE:SURAH:AYAH:FROM-TO=FROM-TO"
    )
    args = ap.parse_args(argv)

    phrases = load_phrases(args.source)
    if not isinstance(phrases, dict) or not phrases:
        print(f"{args.source}: no phrases", file=sys.stderr)
        return 1

    leave_out = set()
    for spec in args.leave_out:
        parts = spec.split(":")
        if len(parts) != 3 or not all(x.isdigit() for x in parts):
            print(f"--leave-out {spec!r}: expected PHRASE:SURAH:AYAH", file=sys.stderr)
            return 1
        leave_out.add((int(parts[0]), f"{parts[1]}:{parts[2]}"))

    corrections = {}
    for spec in args.correct:
        try:
            ref, right = spec.split("=")
            pid, surah, ayah, wrong = ref.split(":")
            wf, wt = (int(x) for x in wrong.split("-"))
            rf, rt = (int(x) for x in right.split("-"))
            corrections[(int(pid), f"{int(surah)}:{int(ayah)}", (wf, wt))] = (rf, rt)
        except ValueError:
            print(
                f"--correct {spec!r}: expected PHRASE:SURAH:AYAH:FROM-TO=FROM-TO",
                file=sys.stderr,
            )
            return 1

    kept, problems, left_out = build(
        phrases,
        recited_word_counts(args.db),
        args.max_ayahs,
        args.min_words,
        frozenset(leave_out),
        corrections,
    )
    if problems:
        print(f"REFUSED: {len(problems)} references disagree with {args.db}:", file=sys.stderr)
        for p in problems[:40]:
            print(f"  {p}", file=sys.stderr)
        if len(problems) > 40:
            print(f"  ... and {len(problems) - 40} more", file=sys.stderr)
        return 1

    out = {"schemaVersion": SCHEMA_VERSION, "source": SOURCE, "phrases": kept}
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")

    print(
        f"ok   {len(kept)} phrases written to {args.out} "
        f"(of {len(phrases)}: {left_out['too_common']} in more than "
        f"{args.max_ayahs} ayahs, {left_out['too_short']} shorter than "
        f"{args.min_words} words, {left_out['single']} in one ayah only)"
    )
    for pid, key in sorted(leave_out):
        print(f"     left out by hand: phrase {pid} in {key}")
    for (pid, key, (wf, wt)), (rf, rt) in sorted(corrections.items()):
        print(f"     corrected by hand: phrase {pid} in {key}, words {wf}-{wt} read as {rf}-{rt}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
