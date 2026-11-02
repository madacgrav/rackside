#!/usr/bin/env bash
# Every `backticked` UI label in docs/guide must appear as a string literal in Sources/ or Watch/.
# Labels may contain placeholders ("N", "…" or <name>); only the literal prefix is checked.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I - <<'PY'
import pathlib, re, sys
code = "\n".join(p.read_text(encoding="utf-8") for d in ("Sources", "Watch") for p in pathlib.Path(d).rglob("*.swift"))
missing = []
for page in sorted(pathlib.Path("docs/guide").glob("*.md")):
    for label in sorted(set(re.findall(r"`([^`]+)`", page.read_text(encoding="utf-8")))):
        probe = re.split(r" N\b|<|\.\.\.$", label)[0].rstrip()
        if len(probe) < 3:
            continue
        if f'"{probe}' not in code:
            missing.append(f"{page}: `{label}`")
for m in missing:
    print("MISSING LABEL:", m)
sys.exit(1 if missing else 0)
PY
