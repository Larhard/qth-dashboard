#!/usr/bin/env bash
# Bumps the app version in pubspec.yaml — the single source of truth.
#
# Usage:  ./scripts/bump.sh [major|minor|patch|build]   (default: build)
#
# The build number (Android versionCode) is ALWAYS incremented on any bump,
# because Android requires it to strictly increase between installs.
set -euo pipefail

part="${1:-build}"
pubspec="$(cd "$(dirname "$0")/.." && pwd)/pubspec.yaml"

line=$(grep -E '^version: [0-9]+\.[0-9]+\.[0-9]+\+[0-9]+' "$pubspec") \
    || { echo "Could not find 'version: X.Y.Z+B' in pubspec.yaml" >&2; exit 1; }

ver=$(echo "$line" | sed -E 's/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1/')
bld=$(echo "$line" | sed -E 's/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\2/')
IFS=. read -r maj min pat <<< "$ver"

case "$part" in
  major) maj=$((maj + 1)); min=0; pat=0 ;;
  minor) min=$((min + 1)); pat=0 ;;
  patch) pat=$((pat + 1)) ;;
  build) ;;
  *) echo "usage: bump.sh [major|minor|patch|build]" >&2; exit 1 ;;
esac
bld=$((bld + 1))  # versionCode must always increase

new="version: $maj.$min.$pat+$bld"
tmp=$(mktemp)
sed -E "s/^version: [0-9]+\.[0-9]+\.[0-9]+\+[0-9]+.*/$new/" "$pubspec" > "$tmp"
mv "$tmp" "$pubspec"
echo "Version bumped ($part) -> $maj.$min.$pat+$bld"
