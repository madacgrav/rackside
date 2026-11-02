#!/usr/bin/env bash
# Fails if an App Store field in docs/app-store/metadata.md (the fenced block under each
# "## Field" heading) or a whats-new/*.md note is longer than App Store Connect allows.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I - <<'PY'
import pathlib, re, sys
LIMITS = {"Name": 30, "Subtitle": 30, "Promotional Text": 170, "Description": 4000,
          "Keywords": 100, "Review Notes": 4000}
fence = re.compile(r"^## ([^\n]+)\n(?:(?!^## ).)*?^```text\n(.*?)^```", re.S | re.M)
bad = False
found = {}
for field, body in fence.findall(pathlib.Path("docs/app-store/metadata.md").read_text(encoding="utf-8")):
    found[field] = len(body.rstrip("\n"))
for field, limit in LIMITS.items():
    n = found.get(field)
    if n is None:
        print(f"MISSING: {field}"); bad = True
    elif n > limit:
        print(f"TOO LONG: {field} {n}/{limit}"); bad = True
    else:
        print(f"ok  {field}: {n}/{limit}")
for note in sorted(pathlib.Path("docs/app-store/whats-new").glob("*.md")):
    m = re.search(r"```text\n(.*?)```", note.read_text(encoding="utf-8"), re.S)
    n = len(m.group(1).rstrip("\n")) if m else None
    if n is None or n > 4000:
        print(f"BAD: {note} ({n}/4000)"); bad = True
    else:
        print(f"ok  {note.name}: {n}/4000")
sys.exit(1 if bad else 0)
PY
