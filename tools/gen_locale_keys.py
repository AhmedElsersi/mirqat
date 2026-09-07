#!/usr/bin/env python3
"""Generates lib/core/localization/locale_keys.dart from the translation files,
so a key can never drift from the JSON that defines it.

    python3 tools/gen_locale_keys.py
"""
import json

AR = "assets/translations/ar.json"
EN = "assets/translations/en.json"
OUT = "lib/core/localization/locale_keys.dart"


def flatten(d: dict, prefix: str = "") -> dict[str, str]:
    out: dict[str, str] = {}
    for k, v in d.items():
        path = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(flatten(v, path + "."))
        else:
            out[path] = v
    return out


def camel(key: str) -> str:
    parts = key.replace(".", "_").split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def main() -> None:
    ar = flatten(json.load(open(AR, encoding="utf-8")))
    en = flatten(json.load(open(EN, encoding="utf-8")))
    if set(ar) != set(en):
        raise SystemExit(
            f"ar/en key mismatch: only ar {sorted(set(ar)-set(en))}, "
            f"only en {sorted(set(en)-set(ar))}"
        )

    names: dict[str, str] = {}
    for key in ar:
        name = camel(key)
        if name in names:
            raise SystemExit(f"key collision: {key} and {names[name]} -> {name}")
        names[name] = key

    lines = [
        "// GENERATED FILE - DO NOT EDIT BY HAND.",
        "// Regenerate with: python3 tools/gen_locale_keys.py",
        "//",
        "// Typed accessors for the keys in assets/translations/*.json. Every",
        "// user-facing string goes through here (CLAUDE.md A.3, Strings).",
        "",
        "class LocaleKeys {",
        "  const LocaleKeys._();",
        "",
    ]
    section = None
    for name, key in sorted(names.items(), key=lambda kv: kv[1]):
        head = key.split(".")[0]
        if head != section:
            if section is not None:
                lines.append("")
            section = head
        lines.append(f"  static const String {name} = '{key}';")
    lines += ["}", ""]

    open(OUT, "w", encoding="utf-8").write("\n".join(lines))
    print(f"wrote {OUT}: {len(names)} keys")


if __name__ == "__main__":
    main()
