<#
.SYNOPSIS
    Builds the MediaManager.kpz plugin archive for Koha installation.

.DESCRIPTION
    Zips the Koha/ directory tree into a .kpz file (standard Koha Plugin
    Zip format) that can be uploaded via Koha > Administration > Plugins.
#>

param(
    [string]$OutputName = "MediaManager.kpz"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Remove old build artefact
$outPath = Join-Path $root $OutputName
if (Test-Path $outPath) { Remove-Item $outPath -Force }

# Build the KPZ (a zip containing the Koha/ directory tree)
$kohaDir = Join-Path $root "Koha"
if (-not (Test-Path $kohaDir)) {
    Write-Error "Koha/ directory not found at $kohaDir"
    exit 1
}

Write-Host "Building $OutputName ..." -ForegroundColor Cyan

Compress-Archive -Path $kohaDir -DestinationPath $outPath -CompressionLevel Optimal

# Rename .zip → .kpz if PowerShell added .zip
if (-not (Test-Path $outPath) -and (Test-Path "$outPath.zip")) {
    Rename-Item "$outPath.zip" $outPath
}

$size = (Get-Item $outPath).Length
Write-Host "`n✓  Built: $outPath ($size bytes)" -ForegroundColor Green
Write-Host "   Upload this file via Koha → Administration → Plugins → Upload plugin."
