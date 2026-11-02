#!/usr/bin/env bash
# Regenerates docs/changelog.md from CHANGELOG.md (the single source of truth).
set -euo pipefail
cd "$(dirname "$0")/.."
{
  printf -- '---\ntitle: Changelog\npermalink: /changelog/\n---\n\n# Changelog\n'
  tail -n +2 CHANGELOG.md
} > docs/changelog.md
