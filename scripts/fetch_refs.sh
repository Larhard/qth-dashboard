#!/usr/bin/env bash
# Downloads the full world reference lists (SOTA, POTA, WWFF, IOTA, GMA, BOTA,
# LLOTA, TOTA, WCA) into assets/refs/ — bundled into the next build.
#
# Usage:  ./scripts/fetch_refs.sh [--only sota,pota] [--from-file sota=path]
# All arguments are passed to tool/fetch_refs.dart.
set -euo pipefail
cd "$(dirname "$0")/.."
dart run tool/fetch_refs.dart "$@"
