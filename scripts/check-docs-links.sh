#!/usr/bin/env bash
# Fails if a relative link or image in docs/ (excluding docs/app-store) or README.md
# points at a file that doesn't exist.
set -euo pipefail
cd "$(dirname "$0")/.."

broken=0
files=$(find docs -name '*.md' -not -path 'docs/app-store/*'; echo README.md)
for file in $files; do
  dir=$(dirname "$file")
  # Markdown links/images: ](target) and HTML src="target"
  links=$( { grep -oE '\]\([^)[:space:]]+' "$file" | sed 's/^](//'; grep -oE 'src="[^"]+"' "$file" | sed -E 's/^src="//; s/"$//'; } || true)
  for link in $links; do
    link=${link%%#*}
    case "$link" in ''|http://*|https://*|mailto:*) continue ;; esac
    if [[ "$link" == /trainme/* ]]; then target="docs/${link#/trainme/}"; else target="$dir/$link"; fi
    t=${target%/}
    if [[ ! -e "$t" && ! -e "$t.md" && ! -e "$t/index.md" ]]; then
      echo "BROKEN: $file -> $link"
      broken=1
    fi
  done
done
exit $broken
