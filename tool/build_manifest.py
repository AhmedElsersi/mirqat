#!/usr/bin/env python3
"""
Build the CDN's manifest.json and the per-surah audio packs the app downloads.

The app reads two things from the CDN: single ayah files, for streaming, and a
zip per surah, for offline use. Both layouts are fixed by CLAUDE.md A.5, and
this script is what produces the second from the first — plus the manifest that
describes them, digests and all.

Input (you put the mp3s here; nothing else is required):

    <root>/audio/<reciter_id>/reciter.json      {nameAr, nameEn, riwayah, version,
                                                 default_bitrate?}
    <root>/audio/<reciter_id>/<bitrate>/<s3><a3>.mp3

A reciter published at more than one bitrate gets one directory per bitrate.
The default (the lowest, or `default_bitrate`) becomes the reciter's own, and
the rest are published as per-surah `qualities` entries for the app's audio
quality selector.

Output (written by this script):

    <root>/packs/<reciter_id>/<bitrate>/<s3>.zip
    <root>/manifest.json

Ayah 000 is a surah's own basmala recording, and only a `separate` surah has
one. Everything else — ayah counts, which surahs take a basmala — is read from
assets/data/quran.db, never hardcoded (CLAUDE.md A.2 rule 2).

Usage:
    python3 tool/build_manifest.py --root ../iqra-cdn
    python3 tool/build_manifest.py --root ../iqra-cdn --check
    python3 tool/build_manifest.py --root ../iqra-cdn --base-url https://…

Exit status is non-zero when anything failed validation, and nothing is written
in that case: a manifest that half-describes a bucket is worse than no manifest,
because the app believes it.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import sqlite3
import sys
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QURAN_DB = ROOT / "assets" / "data" / "quran.db"
BUNDLED_MANIFEST = ROOT / "assets" / "data" / "manifest.json"
APP_MANIFEST_MODEL = ROOT / "lib" / "data" / "models" / "audio_manifest.dart"

# The bucket the published manifest points at today. Only a default: an
# existing manifest's own baseUrl wins, and --base-url wins over both.
DEFAULT_BASE_URL = "https://pub-f2046e05789e4bd5889880fb0c6d3168.r2.dev"

# Fixed by CLAUDE.md A.5. The app fills {id}, {bitrate}, {s3} and {a3}.
AUDIO_PATH_TEMPLATE = "audio/{id}/{bitrate}/{s3}{a3}.mp3"
PACK_PATH_TEMPLATE = "packs/{id}/{bitrate}/{s3}.zip"

AYAH_FILE = re.compile(r"^(\d{3})(\d{3})\.mp3$")

# Deterministic zips: a fixed timestamp and sorted entries mean rebuilding an
# unchanged surah produces byte-identical output, so the digest in the manifest
# does not churn and `rclone`/`aws s3 sync` has nothing to re-upload.
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


class Problem(Exception):
    """A validation failure worth stopping for."""


def pad3(n: int) -> str:
    return f"{n:03d}"


# --------------------------------------------------------------------------- #
# quran.db — the only source of ayah counts and basmala modes
# --------------------------------------------------------------------------- #


def read_catalog(db_path: Path) -> dict[int, dict[str, object]]:
    if not db_path.exists():
        raise Problem(
            f"{db_path.relative_to(ROOT)} is missing. Run "
            "tool/build_quran_data.py first."
        )
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT id, name_ar, ayah_count, basmala_mode FROM surahs ORDER BY id"
        ).fetchall()
    finally:
        con.close()

    if not rows:
        raise Problem("quran.db has no surahs table rows.")
    return {
        int(i): {"name": name, "ayahs": int(count), "basmala": mode}
        for i, name, count, mode in rows
    }


def app_schema_version() -> int:
    """The schemaVersion the app will accept, read from its own model.

    Kept in step this way rather than by a constant here: the app refuses a
    manifest whose version it does not know, so a mismatch would publish a
    manifest nothing can read.
    """
    try:
        source = APP_MANIFEST_MODEL.read_text(encoding="utf-8")
    except OSError:
        return 1
    match = re.search(r"supportedSchemaVersion\s*=\s*(\d+)", source)
    return int(match.group(1)) if match else 1


# --------------------------------------------------------------------------- #
# Scanning one reciter
# --------------------------------------------------------------------------- #


def read_reciter_meta(directory: Path) -> dict[str, object]:
    meta_file = directory / "reciter.json"
    if not meta_file.exists():
        raise Problem(
            f"audio/{directory.name}/reciter.json is missing. It needs at "
            'least {"nameAr": "…", "nameEn": "…", "riwayah": "…", '
            '"version": "1"}.'
        )
    try:
        meta = json.loads(meta_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise Problem(f"audio/{directory.name}/reciter.json is not JSON: {e}")
    if not isinstance(meta, dict):
        raise Problem(f"audio/{directory.name}/reciter.json is not an object.")

    for key in ("nameAr", "nameEn"):
        value = meta.get(key)
        if not isinstance(value, str) or not value.strip():
            raise Problem(
                f"audio/{directory.name}/reciter.json needs a non-empty "
                f'"{key}".'
            )
    return meta


def bitrate_directories(directory: Path) -> list[tuple[int, Path]]:
    found: list[tuple[int, Path]] = []
    for child in sorted(directory.iterdir()):
        if not child.is_dir():
            continue
        if not child.name.isdigit():
            raise Problem(
                f"audio/{directory.name}/{child.name} is not a bitrate: the "
                "layout is audio/<reciter_id>/<bitrate>/<surah3><ayah3>.mp3."
            )
        found.append((int(child.name), child))
    if not found:
        raise Problem(
            f"audio/{directory.name} has no <bitrate> directory under it."
        )
    return found


def scan_ayah_files(
    directory: Path, reciter_id: str, warnings: list[str]
) -> dict[int, dict[int, Path]]:
    """`{surah: {ayah: file}}` for one bitrate directory."""
    by_surah: dict[int, dict[int, Path]] = {}
    for child in sorted(directory.iterdir()):
        if child.is_dir():
            raise Problem(
                f"{child.relative_to(directory.parent.parent.parent)} is a "
                "directory; a bitrate directory holds ayah files only."
            )
        if child.name.startswith("."):
            continue
        match = AYAH_FILE.match(child.name)
        if not match:
            warnings.append(
                f"{reciter_id}: ignoring {child.name} — not <surah3><ayah3>.mp3"
            )
            continue
        surah, ayah = int(match.group(1)), int(match.group(2))
        by_surah.setdefault(surah, {})[ayah] = child
    return by_surah


def check_audio_file(path: Path) -> str | None:
    """A cheap truthfulness check on one mp3, or a reason it looks wrong.

    Not a decoder: it catches the failures that actually happen — a zero-byte
    file from an interrupted copy, an HTML error page saved with an .mp3 name,
    a placeholder that was never replaced.
    """
    size = path.stat().st_size
    if size == 0:
        return "is empty"
    if size < 1024:
        return f"is only {size} bytes"
    with path.open("rb") as handle:
        head = handle.read(3)
    if head[:3] == b"ID3":
        return None
    if len(head) >= 2 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0:
        return None
    return "does not start with an mp3 frame or an ID3 tag"


def surah_entry(
    *,
    reciter_id: str,
    bitrate: int,
    surah: int,
    files: dict[int, Path],
    catalog: dict[int, dict[str, object]],
    packs_root: Path,
    write: bool,
    warnings: list[str],
) -> dict[str, object]:
    """One `surahs[]` entry at one bitrate, and the pack that backs it."""
    if surah not in catalog:
        raise Problem(
            f"{reciter_id}/{bitrate}: surah {surah} is not in quran.db."
        )

    expected = int(catalog[surah]["ayahs"])
    basmala_mode = str(catalog[surah]["basmala"])

    missing = [a for a in range(1, expected + 1) if a not in files]
    if missing:
        shown = ", ".join(pad3(a) for a in missing[:8])
        more = "" if len(missing) <= 8 else f" … and {len(missing) - 8} more"
        raise Problem(
            f"{reciter_id}/{bitrate}: surah {surah} is missing "
            f"{len(missing)} of the {expected} ayahs quran.db gives it: "
            f"{shown}{more}."
        )

    extra = [a for a in sorted(files) if a > expected]
    if extra:
        raise Problem(
            f"{reciter_id}/{bitrate}: surah {surah} has files past its last "
            f"ayah ({', '.join(pad3(a) for a in extra)}), which quran.db puts "
            f"at {expected}."
        )

    has_basmala_file = 0 in files
    if basmala_mode != "separate" and has_basmala_file:
        raise Problem(
            f"{reciter_id}/{bitrate}: surah {surah} has a basmala file "
            "(ayah 000) but its basmala_mode is "
            f"'{basmala_mode}', so the app would never play it. Remove it."
        )
    if basmala_mode == "separate" and not has_basmala_file:
        # Not fatal: the manifest says hasBasmala false and the app opens the
        # session on ayah 1 instead of a 404.
        warnings.append(
            f"{reciter_id}/{bitrate}: surah {surah} has no basmala (000); the "
            "manifest will declare hasBasmala false"
        )

    for ayah in sorted(files):
        complaint = check_audio_file(files[ayah])
        if complaint:
            raise Problem(
                f"{reciter_id}/{bitrate}: "
                f"{files[ayah].name} {complaint}."
            )

    pack_path = packs_root / PACK_PATH_TEMPLATE.format(
        id=reciter_id, bitrate=bitrate, s3=pad3(surah), a3=""
    )

    # A pack already holding exactly these files is kept, whoever built it.
    # The admin tool writes packs too, and two zip libraries do not agree on
    # bytes they both consider irrelevant — the "created by" byte, the
    # attribute encoding. Rebuilding here would change the digest without
    # changing a single sample of audio, which reads downstream as a new
    # recording and invalidates every install of it.
    existing = read_pack_if_matching(pack_path, files)
    if existing is not None:
        payload = existing
        kept = True
    else:
        payload = build_pack(files)
        kept = False
        if write:
            pack_path.parent.mkdir(parents=True, exist_ok=True)
            pack_path.write_bytes(payload)

    digest = hashlib.sha256(payload).hexdigest()
    if kept:
        warnings.append(
            f"{reciter_id}/{bitrate}: surah {surah} kept the pack already on "
            "disk (same files, same contents)"
        )

    entry: dict[str, object] = {
        "n": surah,
        "ayahs": expected,
        "bytes": len(payload),
        "sha256": digest,
    }
    # Declared only where there is something to declare: a `first_ayah` or
    # `none` surah has no 000 file in any reciter's tree, and the app never
    # asks for one (CLAUDE.md A.5).
    if basmala_mode == "separate":
        entry["hasBasmala"] = has_basmala_file
    return entry


def read_pack_if_matching(pack_path: Path, files: dict[int, Path]) -> bytes | None:
    """The pack at `pack_path`, when it already holds exactly `files`.

    Compared by name, size and CRC — not by rebuilding and diffing, which
    would defeat the purpose.
    """
    if not pack_path.exists():
        return None
    expected = {
        files[ayah].name: (
            files[ayah].stat().st_size,
            zlib.crc32(files[ayah].read_bytes()) & 0xFFFFFFFF,
        )
        for ayah in files
    }
    try:
        with zipfile.ZipFile(pack_path) as zf:
            found = {
                info.filename: (info.file_size, info.CRC) for info in zf.infolist()
            }
    except (zipfile.BadZipFile, OSError):
        return None
    if found != expected:
        return None
    return pack_path.read_bytes()


def build_pack(files: dict[int, Path]) -> bytes:
    """One surah's zip, byte-stable for the same input.

    Stored, not deflated: an mp3 does not compress, so deflating it costs CPU
    on both ends and saves nothing. The entries are flat `<surah3><ayah3>.mp3`
    names, which is what `AudioPackService` reads — it takes each entry's base
    name and ignores any directory part.
    """
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as zf:
        for ayah in sorted(files):
            info = zipfile.ZipInfo(files[ayah].name, date_time=ZIP_TIMESTAMP)
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o644 << 16
            zf.writestr(info, files[ayah].read_bytes())
    return buffer.getvalue()


def build_reciter(
    *,
    directory: Path,
    catalog: dict[int, dict[str, object]],
    root: Path,
    write: bool,
    warnings: list[str],
) -> dict[str, object]:
    reciter_id = directory.name
    meta = read_reciter_meta(directory)

    bitrates = bitrate_directories(directory)

    # The reciter's own bitrate is the one the app falls back to, so it is the
    # `default_bitrate` in reciter.json where there is a choice, and the only
    # one otherwise. Every other bitrate is published as a `qualities` entry
    # on each surah, carrying its own size and digest — a different encode is
    # a different file.
    declared_default = meta.get("default_bitrate")
    available = [b for b, _ in bitrates]
    if declared_default is not None and declared_default not in available:
        raise Problem(
            f"audio/{reciter_id}/reciter.json asks for default_bitrate "
            f"{declared_default}, which has no directory "
            f"({', '.join(str(b) for b in available)})."
        )
    default_bitrate = (
        declared_default if declared_default is not None else min(available)
    )

    # `{bitrate: {surah: entry}}`, built once so each pack is zipped once.
    per_bitrate: dict[int, dict[int, dict[str, object]]] = {}
    for bitrate, bitrate_dir in bitrates:
        by_surah = scan_ayah_files(bitrate_dir, reciter_id, warnings)
        if not by_surah:
            raise Problem(f"audio/{reciter_id}/{bitrate} holds no ayah files.")
        per_bitrate[bitrate] = {
            surah: surah_entry(
                reciter_id=reciter_id,
                bitrate=bitrate,
                surah=surah,
                files=by_surah[surah],
                catalog=catalog,
                packs_root=root,
                write=write,
                warnings=warnings,
            )
            for surah in sorted(by_surah)
        }

    surahs = []
    for surah in sorted(per_bitrate[default_bitrate]):
        entry = dict(per_bitrate[default_bitrate][surah])
        extras = {}
        for bitrate in sorted(per_bitrate):
            if bitrate == default_bitrate:
                continue
            other = per_bitrate[bitrate].get(surah)
            if other is None:
                # A surah published at one bitrate and not another is not an
                # error — it simply has no entry at that quality, and the app
                # falls back to the reciter's own.
                warnings.append(
                    f"{reciter_id}: surah {surah} is missing at {bitrate} kbps"
                )
                continue
            extras[str(bitrate)] = {
                "bytes": other["bytes"],
                "sha256": other["sha256"],
            }
        if extras:
            entry["qualities"] = extras
        surahs.append(entry)

    for bitrate in sorted(per_bitrate):
        if bitrate == default_bitrate:
            continue
        only_here = sorted(
            set(per_bitrate[bitrate]) - set(per_bitrate[default_bitrate])
        )
        if only_here:
            warnings.append(
                f"{reciter_id}: surah(s) "
                f"{', '.join(pad3(s) for s in only_here)} exist at {bitrate} "
                f"kbps but not at the default {default_bitrate} kbps, so the "
                "app will never see them"
            )

    bitrate = default_bitrate
    riwayah = str(meta.get("riwayah") or "")
    if not riwayah:
        warnings.append(
            f"{reciter_id}: no riwayah in reciter.json; publishing it empty"
        )

    return {
        "id": reciter_id,
        "nameAr": str(meta["nameAr"]).strip(),
        "nameEn": str(meta["nameEn"]).strip(),
        "riwayah": riwayah,
        "bitrate": bitrate,
        "version": str(meta.get("version") or "1"),
        "audioPath": AUDIO_PATH_TEMPLATE,
        "packPath": PACK_PATH_TEMPLATE,
        "totalBytes": sum(int(s["bytes"]) for s in surahs),
        "surahs": surahs,
    }


# --------------------------------------------------------------------------- #
# Stale-version check
# --------------------------------------------------------------------------- #


def warn_about_stale_versions(
    previous: dict[str, object] | None,
    manifest: dict[str, object],
    warnings: list[str],
) -> None:
    """A changed recording under an unchanged version is a silent stale install.

    `InstalledPack` records the version it was fetched at, so a re-cut surah
    published under the old version leaves every existing install as the old
    reading with nothing to notice it.
    """
    if not previous:
        return
    old = {r["id"]: r for r in previous.get("reciters", []) if isinstance(r, dict)}

    for reciter in manifest["reciters"]:
        before = old.get(reciter["id"])
        if not isinstance(before, dict):
            continue
        if str(before.get("version") or "") != reciter["version"]:
            continue
        old_digests = {
            s.get("n"): s.get("sha256")
            for s in before.get("surahs", [])
            if isinstance(s, dict)
        }
        changed = [
            s["n"]
            for s in reciter["surahs"]
            if s["n"] in old_digests and old_digests[s["n"]] != s["sha256"]
        ]
        if changed:
            warnings.append(
                f"{reciter['id']}: surah(s) "
                f"{', '.join(pad3(int(n)) for n in changed)} changed but "
                f"version is still \"{reciter['version']}\" — bump it, or "
                "installed copies stay on the old recording"
            )


# --------------------------------------------------------------------------- #
# Report
# --------------------------------------------------------------------------- #


def megabytes(n: int) -> str:
    return f"{n / (1024 * 1024):,.1f} MB"


def print_report(manifest: dict[str, object], root: Path) -> None:
    print("\nmanifest:")
    print(f"  schemaVersion {manifest['schemaVersion']}")
    print(f"  baseUrl       {manifest['baseUrl']}")
    if manifest["mirrors"]:
        print(f"  mirrors       {', '.join(manifest['mirrors'])}")

    if not manifest["reciters"]:
        print("  no reciters — audio/ is empty, which is a readable app with "
              "no downloads")

    for reciter in manifest["reciters"]:
        surahs = reciter["surahs"]
        with_basmala = sum(1 for s in surahs if s.get("hasBasmala") is True)
        print(
            f"\n  {reciter['id']}  ({reciter['nameEn']} / "
            f"{reciter['nameAr']})  v{reciter['version']}  "
            f"{reciter['bitrate']} kbps"
        )
        extra = sorted(
            {
                int(b)
                for s in surahs
                for b in (s.get("qualities") or {})
            }
        )
        print(
            f"    {len(surahs)} surah(s), {megabytes(int(reciter['totalBytes']))}"
            f", {with_basmala} with a basmala file"
            + (
                ""
                if not extra
                else f", also at {', '.join(f'{b} kbps' for b in extra)}"
            )
        )
        for s in surahs:
            flag = (
                ""
                if "hasBasmala" not in s
                else ("  +basmala" if s["hasBasmala"] else "  (no basmala)")
            )
            print(
                f"      {pad3(int(s['n']))}  {int(s['ayahs']):>3} ayahs  "
                f"{megabytes(int(s['bytes'])):>10}  {s['sha256'][:12]}…{flag}"
            )

    print("\nupload:")
    print(f"  rclone sync {root}/audio r2:iqra-cdn/audio --checksum")
    print(f"  rclone sync {root}/packs r2:iqra-cdn/packs --checksum")
    print(
        "  then publish manifest.json to the Pages site, NOT the bucket — the "
        "app reads it from\n  https://ahmedelsersi.github.io/iqra-cdn/"
        "manifest.json, which is what lets the\n  bucket move without an app "
        "update."
    )
    print(
        f"  keep {BUNDLED_MANIFEST.relative_to(ROOT)} a copy of the published "
        "file: it is the\n  first-run fallback."
    )


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #


def load_json(path: Path) -> dict[str, object] | None:
    if not path.exists():
        return None
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return loaded if isinstance(loaded, dict) else None


def build(args: argparse.Namespace) -> int:
    root: Path = args.root.resolve()
    audio_root = root / "audio"
    if not audio_root.is_dir():
        print(
            f"! {audio_root} does not exist. The layout is "
            "<root>/audio/<reciter_id>/<bitrate>/<surah3><ayah3>.mp3",
            file=sys.stderr,
        )
        return 1

    manifest_path = root / "manifest.json"
    previous = load_json(manifest_path)

    warnings: list[str] = []
    problems: list[str] = []
    reciters: list[dict[str, object]] = []

    try:
        catalog = read_catalog(QURAN_DB)
    except Problem as e:
        print(f"! {e}", file=sys.stderr)
        return 1

    for directory in sorted(p for p in audio_root.iterdir() if p.is_dir()):
        try:
            reciters.append(
                build_reciter(
                    directory=directory,
                    catalog=catalog,
                    root=root,
                    # Packs are written as they are built — zipping a full
                    # reciter twice, or holding every pack in memory to defer
                    # it, would both be silly at this size. The *manifest* is
                    # what is held back below, because that is the file the app
                    # believes; an unreferenced pack in the bucket is inert.
                    write=not args.check,
                    warnings=warnings,
                )
            )
        except Problem as e:
            problems.append(str(e))

    if problems:
        print(
            "\nthe manifest was not written. fix these first:\n",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"  ! {problem}", file=sys.stderr)
        return 1

    base_url = (
        args.base_url
        or (str(previous.get("baseUrl")) if previous and previous.get("baseUrl") else None)
        or DEFAULT_BASE_URL
    )
    mirrors = args.mirror or (
        [m for m in previous.get("mirrors", []) if isinstance(m, str)]
        if previous
        else []
    )

    manifest = {
        "schemaVersion": app_schema_version(),
        "baseUrl": base_url.rstrip("/"),
        "mirrors": mirrors,
        "reciters": reciters,
    }
    warn_about_stale_versions(previous, manifest, warnings)

    serialised = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"

    if args.check:
        current = manifest_path.read_text(encoding="utf-8") if manifest_path.exists() else ""
        if current == serialised:
            print(f"{manifest_path} is up to date.")
        else:
            print(
                f"! {manifest_path} does not match the audio tree. Run without "
                "--check to rewrite it.",
                file=sys.stderr,
            )
    else:
        manifest_path.write_text(serialised, encoding="utf-8")
        print(f"wrote {manifest_path}")

    print_report(manifest, root)

    if warnings:
        print("\nwarnings:")
        for warning in warnings:
            print(f"  - {warning}")

    if args.check and manifest_path.exists():
        return 0 if manifest_path.read_text(encoding="utf-8") == serialised else 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Build the CDN manifest and the per-surah audio packs from an "
            "audio tree."
        )
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("cdn"),
        help=(
            "the CDN working tree holding audio/ (packs/ and manifest.json are "
            "written into it). Default: ./cdn"
        ),
    )
    parser.add_argument(
        "--base-url",
        help=(
            "where the audio is served from. Defaults to the existing "
            "manifest's baseUrl, then to the published bucket."
        ),
    )
    parser.add_argument(
        "--mirror",
        action="append",
        help="an extra base url; repeatable. Replaces the existing mirrors.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help=(
            "validate and compare against the existing manifest without "
            "writing anything; non-zero exit when they differ."
        ),
    )
    return build(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
