#!/usr/bin/env pwsh
# Downloads the full world reference lists (SOTA, POTA, WWFF, IOTA, GMA, BOTA,
# LLOTA, TOTA, WCA) into assets\refs\ — bundled into the next build.
#
# Usage:  .\scripts\fetch_refs.ps1 [--only sota,pota] [--from-file sota=path]
# All arguments are passed to tool/fetch_refs.dart.
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    dart run tool/fetch_refs.dart @args
    exit $LASTEXITCODE
}
finally { Pop-Location }
