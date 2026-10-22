<#
    split-raw-documents.ps1

    Splits each raw analysis response into its Document A and Document B halves.

    The analysis agent produces ONE response per interview containing both documents,
    separated by a line holding exactly:

        =====DOCUMENT-BREAK=====

    This script performs the mechanical split that prompt refers to:

        outputs\raw\S36_JaneD_Segment-raw.md   ->   inputs\A\S36_JaneD_Segment-A.md
                                                    inputs\B\S36_JaneD_Segment-B.md

    Naming: the base name is the raw filename with the raw suffix removed, so the A and B
    files keep the interview ID and interviewer that the rest of the pipeline reads from
    the filename.

    Validation, all of which aborts that one file rather than writing something malformed:
      - exactly one delimiter line, on a line of its own
      - both halves non-empty
      - the A half starts with a DOCUMENT A heading, the B half with DOCUMENT B

    Existing A or B files are not overwritten unless -Overwrite is passed.

    Usage
    -----
      .\split-raw-documents.ps1
      .\split-raw-documents.ps1 -Overwrite
      .\split-raw-documents.ps1 -RawSuffix "-raw.md" -OutSuffixA "-A.md" -OutSuffixB "-B.md"
#>

[CmdletBinding()]
param(
    [string]$RawDir     = (Join-Path $PSScriptRoot '..\outputs\raw'),
    [string]$ADir       = (Join-Path $PSScriptRoot '..\inputs\A'),
    [string]$BDir       = (Join-Path $PSScriptRoot '..\inputs\B'),
    [string]$RawSuffix  = '-raw.md',
    [string]$OutSuffixA = '-A.md',
    [string]$OutSuffixB = '-B.md',
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

$DELIM = '=====DOCUMENT-BREAK====='

if (-not (Test-Path $RawDir)) { throw "Raw folder not found: $RawDir" }
foreach ($d in @($ADir, $BDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }

$files = Get-ChildItem $RawDir -Filter *.md
if ($files.Count -eq 0) { Write-Output "No .md files in $RawDir"; return }

$ok = 0; $skipped = 0
$problems = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
    $base = $f.Name -replace ([regex]::Escape($RawSuffix) + '$'), '' -replace '\.md$', ''
    $lines = ([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)) -split "`r?`n"

    $delimAt = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq $DELIM) { $delimAt += $i }
    }

    if ($delimAt.Count -eq 0) {
        $problems.Add("$($f.Name): no delimiter line found, nothing written")
        $skipped++; continue
    }
    if ($delimAt.Count -gt 1) {
        $problems.Add("$($f.Name): $($delimAt.Count) delimiter lines found, expected 1, nothing written")
        $skipped++; continue
    }

    $cut = $delimAt[0]
    $aLines = @($lines[0..($cut-1)])
    $bLines = if ($cut + 1 -lt $lines.Count) { @($lines[($cut+1)..($lines.Count-1)]) } else { @() }

    foreach ($pair in @(@('A',$aLines), @('B',$bLines))) {
        $half = $pair[1]
        while ($half.Count -gt 0 -and $half[0].Trim() -eq '')               { $half = $half[1..($half.Count-1)] }
        while ($half.Count -gt 0 -and $half[$half.Count-1].Trim() -eq '')   { $half = $half[0..($half.Count-2)] }
        if ($pair[0] -eq 'A') { $aLines = $half } else { $bLines = $half }
    }

    if ($aLines.Count -eq 0) { $problems.Add("$($f.Name): Document A half is empty, nothing written"); $skipped++; continue }
    if ($bLines.Count -eq 0) { $problems.Add("$($f.Name): Document B half is empty, nothing written"); $skipped++; continue }

    if (($aLines -join "`n") -notmatch '(?im)^#\s*DOCUMENT\s+A\b') {
        $problems.Add("$($f.Name): first half does not start with a DOCUMENT A heading, nothing written"); $skipped++; continue
    }
    if (($bLines -join "`n") -notmatch '(?im)^#\s*DOCUMENT\s+B\b') {
        $problems.Add("$($f.Name): second half does not start with a DOCUMENT B heading, nothing written"); $skipped++; continue
    }

    $aPath = Join-Path $ADir "$base$OutSuffixA"
    $bPath = Join-Path $BDir "$base$OutSuffixB"

    if ((Test-Path $aPath) -and -not $Overwrite) { $problems.Add("$($f.Name): $([System.IO.Path]::GetFileName($aPath)) exists, use -Overwrite"); $skipped++; continue }
    if ((Test-Path $bPath) -and -not $Overwrite) { $problems.Add("$($f.Name): $([System.IO.Path]::GetFileName($bPath)) exists, use -Overwrite"); $skipped++; continue }

    [System.IO.File]::WriteAllText($aPath, ($aLines -join "`n"), $utf8)
    [System.IO.File]::WriteAllText($bPath, ($bLines -join "`n"), $utf8)

    $findings = ([regex]::Matches(($aLines -join "`n"), '(?m)^(\*\*Finding ID:\*\*|###)\s*S\d+-J\d+')).Count
    Write-Output ("{0,-58} A={1,6}b  B={2,6}b  findings={3}" -f $base.Substring(0, [Math]::Min(56, $base.Length)), (($aLines -join "`n").Length), (($bLines -join "`n").Length), $findings)
    $ok++
}

Write-Output ""
Write-Output "Raw files    : $($files.Count)"
Write-Output "Split        : $ok"
Write-Output "Skipped      : $skipped"

if ($problems.Count -gt 0) {
    Write-Output ""
    foreach ($p in $problems) { Write-Output "  PROBLEM: $p" }
    exit 1
}

Write-Output ""
Write-Output "Next: run normalize-finding-headings.ps1 to convert bold finding IDs into headings."
