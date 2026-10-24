param([string]$OutputName = 'MediaManager.kpz')
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetFileName($OutputName) -ne $OutputName -or $OutputName -notmatch '\.kpz$') {
    throw 'OutputName must be a .kpz filename within this repository.'
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# The script lives in scripts/; the package is built from and written to the repository root.
$projectRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $projectRoot 'Koha/Plugin/Com/Library'
$relativeFiles = @('MediaManager.pm') + @(Get-ChildItem -LiteralPath (Join-Path $pluginRoot 'MediaManager') -File |
    Where-Object { $_.Extension -in '.pm','.tt','.json' } | ForEach-Object { 'MediaManager/' + $_.Name })
$expected = @('MediaManager.pm','MediaManager/layout.tt','MediaManager/breadcrumbs.tt','MediaManager/continue.tt','MediaManager/configure.tt','MediaManager/tool.tt','MediaManager/error.tt',
    'MediaManager/Security.pm','MediaManager/Store.pm','MediaManager/Health.pm','MediaManager/Controller.pm','MediaManager/openapi.json')
if (@(Compare-Object ($relativeFiles | Sort-Object) ($expected | Sort-Object)).Count) { throw 'Unexpected or missing plugin files.' }
$outPath = Join-Path $projectRoot $OutputName
$buildTime = [DateTimeOffset]::Now
$tempPath = Join-Path $projectRoot ([IO.Path]::GetRandomFileName() + '.zip')
try {
    $archive = [IO.Compression.ZipFile]::Open($tempPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($relative in ($expected | Sort-Object)) {
            $entry = $archive.CreateEntry('Koha/Plugin/Com/Library/' + $relative, [IO.Compression.CompressionLevel]::Optimal)
            # Build time, NOT a fixed date: Koha keeps the extracted file times, and Koha's
            # Template Toolkit cache only recompiles a template whose file is newer than its
            # cached copy. A fixed old date makes Koha keep serving stale templates.
            $entry.LastWriteTime = $buildTime
            $inputStream = [IO.File]::OpenRead((Join-Path $pluginRoot $relative))
            $outputStream = $entry.Open()
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $inputStream.Dispose() }
        }
    } finally { $archive.Dispose() }
    $check = [IO.Compression.ZipFile]::OpenRead($tempPath)
    try {
        $names = @($check.Entries | ForEach-Object { $_.FullName })
        $expectedNames = @($expected | ForEach-Object { 'Koha/Plugin/Com/Library/' + $_ })
        if (@(Compare-Object ($names | Sort-Object) ($expectedNames | Sort-Object)).Count) { throw 'Invalid archive layout.' }
        foreach ($entry in $check.Entries) {
            if ($entry.Length -eq 0 -or $entry.FullName.Contains('\')) { throw 'Invalid archive entry.' }
        }
    } finally { $check.Dispose() }
    Move-Item -LiteralPath $tempPath -Destination $outPath -Force
    # .NET hash, not Get-FileHash: that cmdlet is missing when Windows PowerShell is started from PowerShell 7.
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($outPath)
    try { $hash = -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) } finally { $stream.Dispose(); $sha.Dispose() }
    Write-Output "${OutputName}: SHA256 $hash"
} finally {
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath }
}
