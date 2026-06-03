#!/usr/bin/env pwsh
# Bumps the app version in pubspec.yaml — the single source of truth.
#
# Usage:  .\scripts\bump.ps1 [major|minor|patch|build]   (default: build)
#
#   major  X.Y.Z+B -> (X+1).0.0+(B+1)
#   minor  X.Y.Z+B -> X.(Y+1).0+(B+1)
#   patch  X.Y.Z+B -> X.Y.(Z+1)+(B+1)
#   build  X.Y.Z+B -> X.Y.Z+(B+1)
#
# The build number (Android versionCode) is ALWAYS incremented on any bump,
# because Android requires it to strictly increase between installs.
param(
    [ValidateSet('major', 'minor', 'patch', 'build')]
    [string]$Part = 'build'
)
$ErrorActionPreference = 'Stop'

$pubspec = Join-Path $PSScriptRoot '..\pubspec.yaml'
$content = [IO.File]::ReadAllText($pubspec)

if ($content -notmatch '(?m)^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    Write-Error "Could not find 'version: X.Y.Z+B' in pubspec.yaml"
}
$maj = [int]$Matches[1]; $min = [int]$Matches[2]
$pat = [int]$Matches[3]; $bld = [int]$Matches[4]

switch ($Part) {
    'major' { $maj++; $min = 0; $pat = 0 }
    'minor' { $min++; $pat = 0 }
    'patch' { $pat++ }
}
$bld++  # versionCode must always increase

$new = "version: $maj.$min.$pat+$bld"
# Match only the version token (not trailing newlines) so surrounding blank
# lines are preserved.
$content = $content -replace '(?m)^version:[ \t]*\d+\.\d+\.\d+\+\d+', $new
[IO.File]::WriteAllText($pubspec, $content)  # UTF-8, no BOM

Write-Host "Version bumped ($Part) -> $maj.$min.$pat+$bld"
