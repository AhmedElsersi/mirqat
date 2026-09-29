#!/usr/bin/env python3
"""
Fetch a QUL ayah-by-ayah recitation export into the tree build_manifest.py reads.

QUL (Quran.com's Quranic Universal Library) exports a recitation as one JSON
object keyed "surah:ayah", each entry naming the ayah's audio_url. This script
downloads those files into

    <root>/audio/<reciter_id>/<bitrate>/<s3><a3>.mp3
    <root>/audio/<reciter_id>/reciter.json

which is exactly what tool/build_manifest.py turns into packs and a manifest.
Ayah numbers come from the entry's surah_number/ayah_number, never from the
URL's file name, so a host's own naming scheme cannot mis-file an ayah.

The recordings are someone's property. This copies them to a bucket of ours,
so it is run only once the owner has agreed to that — the script cannot know,
and does not ask.

    python3 tool/fetch_qul_recitation.py --json export.json \
        --reciter-id muhammad_siddiq_al_minshawi --bitrate 128 \
        --name-ar "محمد صديق المنشاوي" --name-en "Muhammad Siddiq Al-Minshawi" \
        --riwayah "حفص عن عاصم" --root ../iqra-cdn [--surahs 1,114] [--dry-run]

Resumable: a file already there that looks like an mp3 is kept, so a run cut
short is simply run again. Nothing is ever overwritten, and a download that
comes back empty, short of its Content-Length, or not an mp3 at all is deleted
and counted as a failure — the exit status is non-zero until every file is
right, because build_manifest.py would refuse the tree anyway.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

USER_AGENT = "iqra-wartaq fetch_qul_recitation (one-time mirror, with permission)"


def looks_like_mp3(path: Path) -> bool:
    """The same cheap check build_manifest.py applies: size, then the header."""
    try:
        size = path.stat().st_size
    except FileNotFoundError:
        return False
    if size < 1024:
        return False
    with path.open("rb") as handle:
        head = handle.read(3)
    if head[:3] == b"ID3":
        return True
    return len(head) >= 2 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0


def fetch_one(url: str, destination: Path, timeout: int) -> str | None:
    """Downloads url to destination. Returns None on success, else the reason."""
    if looks_like_mp3(destination):
        return None
    partial = destination.with_suffix(".part")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            declared = response.headers.get("Content-Length")
            with partial.open("wb") as out:
                while True:
                    chunk = response.read(1 << 16)
                    if not chunk:
                        break
                    out.write(chunk)
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        partial.unlink(missing_ok=True)
        return f"{e}"
    actual = partial.stat().st_size
    if declared is not None and declared.isdigit() and actual != int(declared):
        partial.unlink(missing_ok=True)
        return f"got {actual} bytes, Content-Length said {declared}"
    if not looks_like_mp3(partial):
        partial.unlink(missing_ok=True)
        return "is not an mp3 (empty, tiny, or an error page)"
    partial.replace(destination)
    return None


def load_export(path: Path) -> list[tuple[int, int, str]]:
    """(surah, ayah, url) for every entry, sorted, with the shape verified."""
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        sys.exit("error: the export is not a JSON object keyed surah:ayah")
    entries: list[tuple[int, int, str]] = []
    for key, entry in data.items():
        if not isinstance(entry, dict):
            sys.exit(f"error: entry {key!r} is not an object")
        surah, ayah, url = (
            entry.get("surah_number"),
            entry.get("ayah_number"),
            entry.get("audio_url"),
        )
        if not (isinstance(surah, int) and isinstance(ayah, int)):
            sys.exit(f"error: entry {key!r} has no surah_number/ayah_number")
        if not (isinstance(url, str) and url.startswith("https://")):
            sys.exit(f"error: entry {key!r} has no https audio_url")
        if key != f"{surah}:{ayah}":
            sys.exit(f"error: entry {key!r} says it is {surah}:{ayah}")
        entries.append((surah, ayah, url))
    entries.sort()
    return entries


def write_reciter_json(directory: Path, args: argparse.Namespace) -> None:
    meta_file = directory / "reciter.json"
    if meta_file.exists():
        return
    if not (args.name_ar and args.name_en):
        sys.exit(
            f"error: {meta_file} does not exist yet, so --name-ar and --name-en "
            "are needed to write it (and --riwayah, unless it is to be empty)."
        )
    meta = {
        "nameAr": args.name_ar,
        "nameEn": args.name_en,
        "riwayah": args.riwayah or "",
        "version": args.version,
    }
    meta_file.write_text(
        json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote {meta_file}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--json", type=Path, required=True, help="the QUL export")
    parser.add_argument("--reciter-id", required=True, help="snake_case, e.g. muhammad_siddiq_al_minshawi")
    parser.add_argument("--bitrate", type=int, required=True, help="the files' bitrate in kbps; names the directory")
    parser.add_argument("--root", type=Path, default=Path("cdn"), help="the CDN working tree (default: ./cdn)")
    parser.add_argument("--name-ar")
    parser.add_argument("--name-en")
    parser.add_argument("--riwayah")
    parser.add_argument("--version", type=int, default=1, help="the reciter's manifest version (default: 1)")
    parser.add_argument("--surahs", help="only these surah numbers, comma-separated")
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--timeout", type=int, default=60, help="seconds per file")
    parser.add_argument("--dry-run", action="store_true", help="count what would be fetched and stop")
    args = parser.parse_args()

    entries = load_export(args.json)
    if args.surahs:
        wanted = {int(s) for s in args.surahs.split(",") if s.strip()}
        entries = [e for e in entries if e[0] in wanted]
    if not entries:
        sys.exit("error: nothing to fetch")

    reciter_dir = args.root / "audio" / args.reciter_id
    audio_dir = reciter_dir / str(args.bitrate)
    jobs = [
        (url, audio_dir / f"{surah:03d}{ayah:03d}.mp3")
        for surah, ayah, url in entries
    ]
    present = sum(1 for _, dest in jobs if looks_like_mp3(dest))
    print(
        f"{len(jobs)} ayahs across {len({s for s, _, _ in entries})} surahs, "
        f"{present} already on disk, {len(jobs) - present} to fetch "
        f"-> {audio_dir}"
    )
    if args.dry_run:
        return 0

    audio_dir.mkdir(parents=True, exist_ok=True)
    write_reciter_json(reciter_dir, args)

    failures: list[tuple[Path, str]] = []
    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(fetch_one, url, dest, args.timeout): dest
            for url, dest in jobs
        }
        for future in as_completed(futures):
            dest = futures[future]
            reason = future.result()
            done += 1
            if reason:
                failures.append((dest, reason))
                print(f"  ! {dest.name}: {reason}", file=sys.stderr)
            elif done % 200 == 0 or done == len(jobs):
                print(f"  {done}/{len(jobs)}")

    if failures:
        print(
            f"\n{len(failures)} of {len(jobs)} files did not arrive; run again "
            "to retry just those.",
            file=sys.stderr,
        )
        return 1
    print(f"\nall {len(jobs)} files in place. Next:")
    print(f"  python3 tool/build_manifest.py --root {args.root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
