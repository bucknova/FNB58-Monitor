#!/bin/bash
# Prints the release notes for a version, from its CHANGELOG.md entry plus download instructions.
# Fails if the version has no entry, so a release can't go out undocumented.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: release-notes.sh VERSION}"
NOTES="$(awk -v heading="## [$VERSION]" '
  index($0, "## [") == 1 { if (found) exit; found = (index($0, heading) == 1); next }
  found { print }
' CHANGELOG.md)"

if [[ -z "${NOTES//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md has no entry for version $VERSION" >&2
  exit 1
fi

printf '%s\n' "$NOTES" | sed '/./,$!d'
cat <<'FOOTER'

## Download

- **FNB58-Monitor-AppleSilicon.dmg:** smaller, for Macs with an M-series chip
- **FNB58-Monitor-Universal.dmg:** for both Apple Silicon and Intel Macs

Needs macOS 14 or later. It has only been tested on macOS 27 with Apple Silicon.

These builds aren't signed with an Apple Developer ID, so macOS blocks them the first time. See [how to open the app](https://github.com/bucknova/FNB58-Monitor#download).
FOOTER
