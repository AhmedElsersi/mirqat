#!/usr/bin/env python3
"""Generates test/arabic_normalization_tables.dart from the
Unicode Character Database that ships with Python.

Dart has no built-in Unicode normalization and `unorm_dart` is not on the
approved package list (CLAUDE.md A.4), so the tables the NFC algorithm needs
are generated here rather than hand-written. Regenerate and re-run
`flutter test` if the ranges below ever need to widen.

    python3 tools/gen_arabic_normalization_tables.py
"""
import unicodedata

RANGES = [
    (0x0600, 0x06FF, "Arabic"),
    (0x0750, 0x077F, "Arabic Supplement"),
    (0x0870, 0x089F, "Arabic Extended-B"),
    (0x08A0, 0x08FF, "Arabic Extended-A"),
    (0xFB50, 0xFDFF, "Arabic Presentation Forms-A"),
    (0xFE70, 0xFEFF, "Arabic Presentation Forms-B"),
]

OUT = "test/arabic_normalization_tables.dart"


def main() -> None:
    ccc: dict[int, int] = {}
    decomp: dict[int, tuple[int, int]] = {}

    for lo, hi, _ in RANGES:
        for cp in range(lo, hi + 1):
            ch = chr(cp)
            c = unicodedata.combining(ch)
            if c:
                ccc[cp] = c
            d = unicodedata.decomposition(ch)
            if d and not d.startswith("<"):
                parts = [int(x, 16) for x in d.split()]
                if len(parts) == 2:
                    # Composition exclusions would have to be filtered here; a
                    # round-trip assert below proves the Arabic block has none.
                    assert unicodedata.normalize("NFC", chr(parts[0]) + chr(parts[1])) == ch
                    decomp[cp] = (parts[0], parts[1])

    composition: dict[int, dict[int, int]] = {}
    for cp, (base, mark) in decomp.items():
        composition.setdefault(base, {})[mark] = cp

    lines = [
        "// GENERATED FILE - DO NOT EDIT BY HAND.",
        "// Regenerate with: python3 tools/gen_arabic_normalization_tables.py",
        "//",
        f"// Source: Unicode Character Database {unicodedata.unidata_version}, via Python's",
        "// `unicodedata` module. Covers the Arabic blocks only:",
    ]
    for lo, hi, name in RANGES:
        lines.append(f"//   U+{lo:04X}..U+{hi:04X}  {name}")
    lines += [
        "",
        "/// Canonical combining class for every Arabic-range codepoint that has a",
        "/// non-zero one. Codepoints absent from this map are treated as class 0.",
        "const Map<int, int> arabicCombiningClass = <int, int>{",
    ]
    for cp in sorted(ccc):
        lines.append(f"  0x{cp:04X}: {ccc[cp]},")
    lines += [
        "};",
        "",
        "/// Canonical decompositions: precomposed codepoint -> [base, mark].",
        "const Map<int, List<int>> arabicCanonicalDecomposition = <int, List<int>>{",
    ]
    for cp in sorted(decomp):
        base, mark = decomp[cp]
        lines.append(f"  0x{cp:04X}: <int>[0x{base:04X}, 0x{mark:04X}],")
    lines += [
        "};",
        "",
        "/// The inverse of [arabicCanonicalDecomposition]: base -> mark -> composed.",
        "/// The Arabic blocks contain no composition exclusions, so every pair here",
        "/// round-trips.",
        "const Map<int, Map<int, int>> arabicCanonicalComposition =",
        "    <int, Map<int, int>>{",
    ]
    for base in sorted(composition):
        lines.append(f"  0x{base:04X}: <int, int>{{")
        for mark in sorted(composition[base]):
            lines.append(f"    0x{mark:04X}: 0x{composition[base][mark]:04X},")
        lines.append("  },")
    lines += ["};", ""]

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print(f"wrote {OUT}: {len(ccc)} combining classes, {len(decomp)} decompositions")


if __name__ == "__main__":
    main()
