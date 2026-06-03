#!/usr/bin/env bash
# Cuts a release: bumps the version, builds a release APK, and writes a
# version-stamped copy to dist/.
#
# Usage:  ./scripts/release.sh [major|minor|patch|build]   (default: build)
#
# Output: dist/qth_dashboard-vX.Y.Z+B.apk
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# 1. Bump the single source of truth.
bash "$here/bump.sh" "${1:-build}"

# 2. Read back the new version.
line=$(grep -E '^version: ' "$root/pubspec.yaml")
ver=$(echo "$line" | sed -E 's/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1/')
bld=$(echo "$line" | sed -E 's/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\2/')

# 3. Build the release APK and stamp the output filename.
cd "$root"
flutter build apk --release
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk "dist/qth_dashboard-v${ver}+${bld}.apk"
echo ""
echo "Release ready: dist/qth_dashboard-v${ver}+${bld}.apk"
