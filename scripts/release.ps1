#!/usr/bin/env pwsh
# Cuts a release: bumps the version, builds a release APK, and writes a
# version-stamped copy to dist/.
#
# Usage:  .\scripts\release.ps1 [major|minor|patch|build]   (default: build)
#
# Output: dist\qth_dashboard-vX.Y.Z+B.apk
param(
    [ValidateSet('major', 'minor', 'patch', 'build')]
    [string]$Part = 'build'
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..'

# 1. Bump the single source of truth.
& (Join-Path $PSScriptRoot 'bump.ps1') $Part

# 2. Read back the new version.
$content = [IO.File]::ReadAllText((Join-Path $root 'pubspec.yaml'))
$content -match '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)' | Out-Null
$ver = $Matches[1]; $bld = $Matches[2]

# 3. Build the release APK.
Push-Location $root
try {
    # Refresh the bundled ham-radio reference lists (best effort: on failure the
    # previous files are kept and the build continues). $env:SKIP_REFS=1 skips it.
    if ($env:SKIP_REFS -ne '1') {
        dart run tool/fetch_refs.dart
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'Some reference lists failed to update - previous data kept.'
        }
    }

    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }

    $dist = Join-Path $root 'dist'
    if (-not (Test-Path $dist)) { New-Item -ItemType Directory $dist | Out-Null }
    $out = Join-Path $dist "qth_dashboard-v$ver+$bld.apk"
    Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' $out -Force
    Write-Host "`nRelease ready: $out"
}
finally { Pop-Location }
