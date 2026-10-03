#!/usr/bin/env python3
"""Sanity checks for the mod's localization files.

Every language must have exactly the same keys as English, files must be UTF-8
with BOM and start with the right l_<language>: header, and values must not
contain stray double quotes (they silently break the line in CK3).

Usage: python3 tools/check_localization.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "localization"
LANGUAGES = ["english", "french", "german", "spanish", "polish", "russian",
             "japanese", "korean", "simp_chinese"]
LINE = re.compile(r'^ ([A-Za-z0-9_.]+):\d* "(.*)"\s*$')


def read_keys(path, language, errors):
    raw = path.read_bytes()
    if not raw.startswith(b"\xef\xbb\xbf"):
        errors.append(f"{path}: missing UTF-8 BOM")
    lines = raw.decode("utf-8-sig").splitlines()
    if not lines or lines[0].strip() != f"l_{language}:":
        errors.append(f"{path}: first line must be 'l_{language}:'")
    keys = {}
    for number, line in enumerate(lines[1:], start=2):
        if not line.strip() or line.strip().startswith("#"):
            continue
        match = LINE.match(line)
        if not match:
            errors.append(f"{path}:{number}: unparsable line")
            continue
        key, value = match.groups()
        if '"' in value:
            errors.append(f"{path}:{number}: double quote inside value of {key}")
        if value.count("[") != value.count("]"):
            errors.append(f"{path}:{number}: unbalanced [] in {key}")
        if value.count("#") - 2 * value.count("#!") > value.count("#!"):
            errors.append(f"{path}:{number}: formatting tag not closed with #! in {key}")
        if key in keys:
            errors.append(f"{path}:{number}: duplicate key {key}")
        keys[key] = value
    return keys


def main():
    errors = []
    reference = {}
    for language in LANGUAGES:
        folder = ROOT / language
        files = sorted(folder.rglob("*.yml")) if folder.exists() else []
        if not files:
            errors.append(f"{language}: no localization files")
            continue
        main_keys, replace_keys = {}, {}
        for path in files:
            if not path.name.endswith(f"_l_{language}.yml"):
                errors.append(f"{path}: file name must end with _l_{language}.yml")
            target = replace_keys if "replace" in path.parts else main_keys
            target.update(read_keys(path, language, errors))
        if language == "english":
            reference = main_keys
            continue
        missing = sorted(set(reference) - set(main_keys))
        extra = sorted(set(main_keys) - set(reference))
        if missing:
            errors.append(f"{language}: missing keys {missing}")
        if extra:
            errors.append(f"{language}: unknown keys {extra}")
    for error in errors:
        print(error)
    print(f"{len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
