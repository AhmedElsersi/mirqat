#!/usr/bin/env python3
"""Measure every ayah clip of a surah against the words it should hold.

    tool/audit_audio.py --live  [--reciter ID] [SURAH ...]   published packs, from the CDN
    tool/audit_audio.py --dir DIR [SURAH ...]                 local clips, DIR/<NNN>/<NNN><AAA>.mp3

A surah is CLEAN when no clip is out of line with its text. The arithmetic is
the same as `suspectSegments` in lib/admin/services/segment_audit.dart and the
weights the same as lib/admin/services/recitation_weight.dart, so a cut that
the admin tool calls clean is one this calls clean. `--dir` is for checking a
re-cut before anything is uploaded or deleted: export with

    dart run tool/publish_surah.dart --align --export-only 24 39 ...

and point this at build/recut.

Exit status is 1 when any audited surah is not clean.
"""
import argparse, io, json, os, re, sqlite3, subprocess, sys, tempfile, zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = sqlite3.connect(os.path.join(REPO, 'assets', 'data', 'quran.db'))

_LETTER = re.compile('[' + chr(0x0621) + '-' + chr(0x064A) + ']')
_HARAKA = re.compile('[' + chr(0x064B) + '-' + chr(0x0652) + ']')
_MADDAH = chr(0x0653)


def recitation_weight(text):
    """Port of recitationWeight(): letter names and held vowels count for more."""
    total = 0
    for word in text.split():
        n = len(_LETTER.findall(word))
        if n == 0:
            continue
        held = word.count(_MADDAH)
        # Letter names run about a second each; the ones under a maddah are held.
        total += n * 3 + 5 * held if not _HARAKA.search(word) else n + 3 * held
    return total


BASMALA = recitation_weight(DB.execute('select text from ayahs where surah=1 and ayah=1').fetchone()[0])


def _fit(xs, ys):
    n = len(xs); mx = sum(xs) / n; my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs) or 1e-9
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    return my - b * mx, b


def suspects(weights, durations):
    """(index, seconds, expected) for each clip its text cannot explain."""
    if len(weights) < 2:
        return []
    a, b = _fit(weights, durations)
    if len(weights) >= 8:
        res = [d - (a + b * w) for w, d in zip(weights, durations)]
        sd = (sum(r * r for r in res) / len(res)) ** 0.5 or 1e-9
        keep = [(w, d) for w, d, r in zip(weights, durations, res) if abs(r) <= 2.5 * sd]
        if len(keep) >= 6:
            a, b = _fit([k[0] for k in keep], [k[1] for k in keep])
    out = []
    for i, (w, d) in enumerate(zip(weights, durations)):
        e = max(a + b * w, 0.8)
        if (d < 0.45 * e and e - d > 1.5) or (d > 2.2 * e and d - e > 8):
            out.append((i, round(d, 2), round(e, 1)))
    return out


def _duration(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path],
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out else 0.0


def audit(surah, files):
    """files: {ayah_number: path}. Returns a result dict."""
    count, mode = DB.execute('select ayah_count, basmala_mode from surahs where id=?', (surah,)).fetchone()
    texts = dict(DB.execute('select ayah, text from ayahs where surah=?', (surah,)))
    missing = [a for a in range(1, count + 1) if a not in files]
    extra = [a for a in files if a != 0 and a not in texts]
    order = sorted(files)
    weights = [BASMALA if a == 0 else recitation_weight(texts.get(a, '')) for a in order]
    durations = [_duration(files[a]) for a in order]
    flagged = [(order[i], d, e) for i, d, e in suspects(weights, durations)]
    return {
        'surah': surah, 'clips': len(order), 'ayahs': count, 'has_basmala_clip': 0 in files,
        'basmala_mode': mode, 'missing': missing, 'extra': extra, 'suspects': flagged,
        'clean': not missing and not extra and not flagged,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    where = ap.add_mutually_exclusive_group(required=True)
    where.add_argument('--live', action='store_true')
    where.add_argument('--dir')
    ap.add_argument('--reciter')
    ap.add_argument('--json')
    ap.add_argument('surahs', nargs='*', type=int)
    args = ap.parse_args()

    results = []
    if args.dir:
        found = sorted(int(d) for d in os.listdir(args.dir) if d.isdigit() and os.path.isdir(os.path.join(args.dir, d)))
        for n in (args.surahs or found):
            folder = os.path.join(args.dir, f'{n:03d}')
            if not os.path.isdir(folder):
                print(f'{n:3d} MISSING  no directory {folder}'); results.append({'surah': n, 'clean': False}); continue
            files = {int(f[3:6]): os.path.join(folder, f) for f in os.listdir(folder)
                     if re.fullmatch(r'\d{6}\.mp3', f) and int(f[:3]) == n}
            results.append(audit(n, files))
            _report(results[-1])
    else:
        manifest = json.load(open(os.path.join(REPO, 'assets', 'data', 'manifest.json')))
        rec = next(r for r in manifest['reciters'] if not args.reciter or r['id'] == args.reciter)
        base = manifest['baseUrl'].rstrip('/')
        for n in (args.surahs or sorted(s['n'] for s in rec['surahs'])):
            data = subprocess.run(['curl', '-sL', f"{base}/packs/{rec['id']}/{rec['bitrate']}/{n:03d}.zip"],
                                  capture_output=True).stdout
            with tempfile.TemporaryDirectory() as tmp:
                try:
                    z = zipfile.ZipFile(io.BytesIO(data))
                except zipfile.BadZipFile:
                    print(f'{n:3d} MISSING  no pack on the CDN'); results.append({'surah': n, 'clean': False}); continue
                files = {}
                for name in z.namelist():
                    path = os.path.join(tmp, name); open(path, 'wb').write(z.read(name))
                    files[int(name[3:6])] = path
                results.append(audit(n, files))
            _report(results[-1])

    clean = [r['surah'] for r in results if r.get('clean')]
    dirty = [r['surah'] for r in results if not r.get('clean')]
    print(f"\nCLEAN ({len(clean)}): {' '.join(map(str, clean))}")
    print(f"NOT CLEAN ({len(dirty)}): {' '.join(map(str, dirty))}")
    if args.json:
        json.dump(results, open(args.json, 'w'), ensure_ascii=False, indent=1)
    sys.exit(1 if dirty else 0)


def _report(r):
    notes = []
    if r['missing']: notes.append(f"missing ayahs {r['missing'][:8]}")
    if r['extra']:   notes.append(f"unexpected files {r['extra'][:8]}")
    for a, d, e in r['suspects']:
        notes.append(f"{'basmala' if a == 0 else 'ayah ' + str(a)}: {d}s, expected ~{e}s")
    print(f"{r['surah']:3d} {'CLEAN   ' if r['clean'] else 'NOT CLEAN'} {r['clips']:3d} clips  " + '; '.join(notes), flush=True)


if __name__ == '__main__':
    main()
