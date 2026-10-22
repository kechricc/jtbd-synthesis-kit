<#
    normalize-finding-headings.ps1

    Converts each finding's ID line in Document A files from a bold label into a real
    Markdown heading:

        **Finding ID:** S2-J3        ->        ### S2-J3

    Why this exists
    ---------------
    The synthesis output deep-links each finding as an Obsidian anchor, [[file#S2-J3|S2-J3]].
    Obsidian resolves "#" anchors only against real headings, so a bold label produces links
    that are syntactically valid and completely dead. Nothing in the output looks wrong; the
    break only surfaces when a human clicks one.

    The Document A generator prompt emits the bold form, so every fresh batch needs this pass.
    Run it once, on the A files, before pass one.

    Safe to re-run: files already converted are left alone and reported as such.

    Usage
    -----
      .\normalize-finding-headings.ps1                 # inputs\A, with backup
      .\normalize-finding-headings.ps1 -WhatIfOnly     # report what would change, write nothing
      .\normalize-finding-headings.ps1 -Dir "C:\some\other\folder"
#>

[CmdletBinding()]
param(
    [string]$Dir = (Join-Path $PSScriptRoot '..\inputs\A'),
    [switch]$WhatIfOnly,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $Dir)) { throw "Folder not found: $Dir" }

$files = Get-ChildItem $Dir -Filter *.md
if ($files.Count -eq 0) { Write-Output "No .md files in $Dir"; return }

$pattern = '(?m)^\*\*Finding ID:\*\*[ \t]*(S\d+-J\d+)[ \t]*\r?$'

$totalConverted = 0
$totalAlready   = 0
$rows           = New-Object System.Collections.Generic.List[string]

if (-not $WhatIfOnly -and -not $NoBackup) {
    # Backups go OUTSIDE the folder being normalized, with a .bak extension. If this run
    # folder is an Obsidian vault, a copy named *.md sitting anywhere inside it would create
    # a second note with the same name, and wikilinks resolve by unique filename.
    $bak = Join-Path (Split-Path $Dir -Parent) '_backups'
    if (-not (Test-Path $bak)) { New-Item -ItemType Directory -Path $bak | Out-Null }
    foreach ($f in $files) { Copy-Item $f.FullName (Join-Path $bak "$($f.Name).bak") -Force }
    Write-Output "Backup written: $bak (as .bak, not indexed by Obsidian)"
}

foreach ($f in $files) {
    $c = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)

    $toConvert = ([regex]::Matches($c, $pattern)).Count
    $already   = ([regex]::Matches($c, '(?m)^###\s+S\d+-J\d+\s*\r?$')).Count

    if ($toConvert -gt 0 -and -not $WhatIfOnly) {
        $c = [regex]::Replace($c, $pattern, '### $1')
        [System.IO.File]::WriteAllText($f.FullName, $c, $utf8)
    }

    $totalConverted += $toConvert
    $totalAlready   += $already
    $rows.Add(("{0,-58} convert={1,-4} already={2}" -f $f.Name.Substring(0, [Math]::Min(56, $f.Name.Length)), $toConvert, $already))
}

$rows | ForEach-Object { Write-Output $_ }

Write-Output ""
Write-Output "Files            : $($files.Count)"
Write-Output "Headings created : $totalConverted$(if ($WhatIfOnly) { ' (dry run, nothing written)' })"
Write-Output "Already headings : $totalAlready"

# Duplicate anchors inside one file would make Obsidian links ambiguous.
$dupWarn = 0
foreach ($f in $files) {
    $ids = Get-Content $f.FullName -Encoding UTF8 |
           Select-String -Pattern '^###\s+(S\d+-J\d+)\s*$' |
           ForEach-Object { $_.Matches[0].Groups[1].Value }
    $d = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($d) { Write-Output "WARNING duplicate anchors in $($f.Name): $($d.Name -join ', ')"; $dupWarn++ }
}
if ($dupWarn -eq 0) { Write-Output "Duplicate anchors: none" }

# Anything that looks like a finding ID line but did not match the expected shape.
$stragglers = 0
foreach ($f in $files) {
    $s = Get-Content $f.FullName -Encoding UTF8 | Select-String -Pattern 'Finding ID'
    if ($s) { Write-Output "WARNING unconverted 'Finding ID' text in $($f.Name) line $($s[0].LineNumber): $($s[0].Line.Trim())"; $stragglers++ }
}
if ($stragglers -eq 0) { Write-Output "Unconverted 'Finding ID' lines: none" }
