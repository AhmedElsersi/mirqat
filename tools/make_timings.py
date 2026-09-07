#!/usr/bin/env python3
"""
make_timings.py — propose ayah boundaries for a full-surah recitation recording.

Runs ffmpeg's silencedetect over the file, treats the gaps the reciter leaves
between ayahs as candidate boundaries, and writes the timings JSON the app's
`single_file_with_timings` audio mode expects.

    python3 make_timings.py 001.mp3 --surah 1 --ayahs 7 \
        --reciter ahmed_khalil_shaheen -o 001.json

The output is a PROPOSAL. Always listen back before shipping it — a reciter who
pauses mid-ayah for breath, or runs two short ayahs together, will throw the
detector off. Use --split to also cut real per-ayah files if you would rather
switch the app to `per_ayah_files` mode.

Requires ffmpeg on PATH.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys


def require_ffmpeg():
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH. Install it first (e.g. apt install ffmpeg).")


def duration_ms(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True,
    )
    return int(float(out.stdout.strip()) * 1000)


def detect_silences(path, noise_db, min_silence_s):
    """Return [(start_ms, end_ms)] for each detected silent region."""
    proc = subprocess.run(
        ["ffmpeg", "-i", path, "-af",
         f"silencedetect=noise={noise_db}dB:d={min_silence_s}", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    log = proc.stderr
    starts = [float(m) for m in re.findall(r"silence_start:\s*([0-9.]+)", log)]
    ends = [float(m) for m in re.findall(r"silence_end:\s*([0-9.]+)", log)]
    return [(int(s * 1000), int(e * 1000)) for s, e in zip(starts, ends)]


def pick_boundaries(silences, want, total_ms):
    """Choose the `want` longest silences as ayah separators, in time order."""
    if len(silences) < want:
        return None, len(silences)
    ranked = sorted(silences, key=lambda p: p[1] - p[0], reverse=True)[:want]
    return sorted(ranked, key=lambda p: p[0]), len(silences)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--surah", type=int, required=True)
    ap.add_argument("--ayahs", type=int, required=True,
                    help="expected ayah count for this surah")
    ap.add_argument("--reciter", required=True)
    ap.add_argument("-o", "--output", default="timings.json")
    ap.add_argument("--noise-db", type=float, default=-35.0,
                    help="silence threshold in dBFS (raise toward 0 for noisy recordings)")
    ap.add_argument("--min-silence", type=float, default=0.35,
                    help="minimum silence length in seconds to count as a gap")
    ap.add_argument("--split", action="store_true",
                    help="also write per-ayah mp3 files next to the output")
    args = ap.parse_args()

    require_ffmpeg()
    total = duration_ms(args.audio)
    silences = detect_silences(args.audio, args.noise_db, args.min_silence)

    # n ayahs need n-1 internal separators
    seps, found = pick_boundaries(silences, args.ayahs - 1, total)
    if seps is None:
        sys.exit(
            f"Found only {found} silent gaps but need {args.ayahs - 1}.\n"
            f"Try --min-silence lower (e.g. 0.2) or --noise-db closer to 0 (e.g. -28)."
        )

    # Ayah n runs from the midpoint of the previous gap to the midpoint of the next.
    cuts = [0] + [(s + e) // 2 for s, e in seps] + [total]
    ayahs = [
        {"number": i + 1, "startMs": cuts[i], "endMs": cuts[i + 1]}
        for i in range(args.ayahs)
    ]

    data = {
        "surah": args.surah,
        "reciter": args.reciter,
        "_generatedBy": "make_timings.py — PROPOSAL, verify by ear before shipping",
        "ayahs": ayahs,
    }
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"{found} gaps detected, {args.ayahs - 1} used as separators.")
    for a in ayahs:
        dur = (a["endMs"] - a["startMs"]) / 1000
        print(f"  ayah {a['number']:>3}: {a['startMs']:>7} → {a['endMs']:>7} ms  ({dur:5.2f}s)")
    print(f"\nwrote {args.output}")

    shortest = min(a["endMs"] - a["startMs"] for a in ayahs)
    if shortest < 800:
        print(f"WARNING: shortest segment is {shortest} ms — likely a false boundary. Check by ear.")

    if args.split:
        for a in ayahs:
            name = f"{a['number']:03d}.mp3"
            subprocess.run([
                "ffmpeg", "-y", "-v", "error", "-i", args.audio,
                "-ss", f"{a['startMs'] / 1000:.3f}",
                "-to", f"{a['endMs'] / 1000:.3f}",
                "-c", "copy", name,
            ])
            print(f"  wrote {name}")


if __name__ == "__main__":
    main()
