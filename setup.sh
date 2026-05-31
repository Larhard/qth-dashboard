#!/usr/bin/env bash
# QTH Dashboard -- one-time project setup (Linux / macOS)
# Run from the qth_helper directory:
#   chmod +x setup.sh   # first time only
#   ./setup.sh

set -euo pipefail

SEP=$(printf '%0.s-' {1..77})

echo ""
echo "=== QTH Dashboard Setup ==="

# -- helpers ------------------------------------------------------------------
ok()   { echo "  [OK]  $*"; }
info() { echo "  ...   $*"; }
warn() { echo "  [!!]  $*" >&2; }

# Prefer python3; fall back to python if python3 is absent.
PYTHON=""
for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
        PYTHON="$cmd"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    warn "Python 3 not found. Install it and re-run."
    warn "  Ubuntu/Debian:  sudo apt install python3 python3-pip"
    warn "  Fedora:         sudo dnf install python3 python3-pip"
    warn "  macOS:          brew install python3"
    exit 1
fi
ok "Python found: $($PYTHON --version)"

# -- 1. Check Flutter ---------------------------------------------------------
if ! command -v flutter &>/dev/null; then
    warn "Flutter SDK not found. Install it first:"
    warn "  https://docs.flutter.dev/get-started/install/linux"
    warn "Then add flutter/bin to your PATH and re-run."
    exit 1
fi
FLUTTER_VER=$(flutter --version --machine 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('frameworkVersion',''))" \
    2>/dev/null || echo "(unknown version)")
ok "Flutter found: $FLUTTER_VER"

# -- 2. Flutter packages ------------------------------------------------------
echo ""
info "Running flutter pub get..."
flutter pub get

# -- 3. Asset stubs (instant, no internet) ------------------------------------
echo ""
info "Creating asset stubs..."
"$PYTHON" scripts/create_stubs.py

# -- 4. App icon --------------------------------------------------------------
echo ""
info "Generating app icon..."
"$PYTHON" scripts/generate_icon.py

echo ""
info "Stamping Android launcher icons..."
dart run flutter_launcher_icons

# -- Done ---------------------------------------------------------------------
echo ""
echo "=== Setup complete ==="
echo ""
echo "The app is ready to build and run."
echo ""
echo "Connect your Android device (USB debugging on) or start an emulator, then:"
echo ""
echo "    flutter run"
echo ""
echo "To build a release APK:"
echo ""
echo "    flutter build apk --release"
echo "    # Output: build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "$SEP"
echo "OPTIONAL -- Download full data (requires internet access)"
echo "$SEP"
echo ""
echo "The app works out of the box with the built-in top-5000 city dataset."
echo "For finer city precision and port data, run the fetch scripts manually:"
echo ""
echo "  1. Full city datasets (cities_precise and cities_detailed, ~10 MB):"
echo ""
echo "       $PYTHON scripts/fetch_cities.py"
echo ""
echo "  2. Port data -- requires a free GeoNames account and the NGA WPI CSV."
echo "     See README.md -> Step 3 for detailed instructions."
echo ""
echo "       $PYTHON scripts/fetch_ports.py --wpi-file path/to/UpdatedPub150.csv --user YOUR_USERNAME"
echo ""
echo "The generated files are gitignored; git add . will never accidentally"
echo "commit them."
echo ""
echo "$SEP"
echo ""
