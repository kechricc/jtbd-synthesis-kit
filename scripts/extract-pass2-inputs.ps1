<#
    extract-pass2-inputs.ps1

    Builds the slim input documents for synthesis pass two:

      pass2-inputs\B-extracts.md          one entry per interview: snapshot + disconfirmations, verbatim
      pass2-inputs\cluster-manifest.md    cluster headings + canonical JTBD statements, then orphan IDs + JTBD
      pass2-inputs\EXTRACTION-ISSUES.txt  problems found, or a clean-run note

    Design notes
    ------------
    Sections and labels are matched by NAME and SHAPE, never by number or by a single
    literal format. Both the analysis prompt and the pass-one synthesis prompt have
    changed repeatedly, and each change altered the output format:

        B files    B1/B2/B3 numbering shifted between prompt versions.
        Orphans    v0.2 wrote "**S3-J5**", v0.3 wrote "**Finding ID:** S3-J5",
                   v0.5 wrote "### [[file#S3-J5\|S3-J5]]".
        Part 2     heading level moved from "##" to "###".

    Every pattern below therefore accepts the known variants and is written to
    tolerate new ones. When something cannot be found, the script says so loudly
    rather than emitting a plausible-looking empty file.

    Usage
    -----
      .\extract-pass2-inputs.ps1
      .\extract-pass2-inputs.ps1 -SynthesisPath "C:\path\to\full-corpus-result.md"
      .\extract-pass2-inputs.ps1 -IncludeMembers        # adds member interview IDs per cluster

    -IncludeMembers exists for pass two's "outside disconfirmations" rule, which marks a
    quote "(did not surface this job)" when it comes from an interviewee who was not in
    the cluster. That decision needs cluster membership, which the manifest otherwise
    strips. Off by default so the manifest stays minimal.

    Exit code is 1 if validation fails. Files are still written so they can be inspected.
#>

[CmdletBinding()]
param(
    # Defaults resolve relative to this script's folder, so the whole run folder can be
    # moved or copied without editing paths.
    [string]$BDir          = (Join-Path $PSScriptRoot '..\inputs\B'),
    [string]$SynthesisPath = (Join-Path $PSScriptRoot '..\outputs\result-pass1.md'),
    [string]$OutDir        = (Join-Path $PSScriptRoot '..\pass2-inputs'),
    [switch]$IncludeMembers
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# Section names to pull from each B file, matched by name. Add aliases if a prompt renames one.
$WANTED = @(
    @{ Label = 'Snapshot';         Patterns = @('interviewee\s+snapshot', '^snapshot$') },
    @{ Label = 'Disconfirmations'; Patterns = @('disconfirmations?') }
)

if (-not (Test-Path $BDir))          { throw "B directory not found: $BDir" }
if (-not (Test-Path $SynthesisPath)) { throw "Synthesis file not found: $SynthesisPath" }
if (-not (Test-Path $OutDir))        { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$issues = New-Object System.Collections.Generic.List[string]
$fatal  = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Verbatim body of the section whose heading text matches any pattern. Runs from the
# line after the heading to the line before the next heading at the same or higher
# level. Leading numbering ("B1.", "3)") is stripped before matching. $null if absent.
function Get-SectionBody {
    param([string[]]$Lines, [string[]]$Patterns)

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -notmatch '^(#{1,6})\s+(.*)$') { continue }

        $level = $Matches[1].Length
        $name  = ($Matches[2] -replace '^\s*[A-Za-z]?\d+[\.\)]?\s*', '').Trim()

        $hit = $false
        foreach ($p in $Patterns) { if ($name -match $p) { $hit = $true; break } }
        if (-not $hit) { continue }

        $body = New-Object System.Collections.Generic.List[string]
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            if ($Lines[$j] -match '^(#{1,6})\s' -and $Matches[1].Length -le $level) { break }
            $body.Add($Lines[$j])
        }

        while ($body.Count -gt 0 -and $body[0].Trim()             -eq '') { $body.RemoveAt(0) }
        while ($body.Count -gt 0 -and $body[$body.Count-1].Trim() -eq '') { $body.RemoveAt($body.Count-1) }

        # LF, matching the source corpus. CRLF would alter multi-line bodies
        # relative to the files they were copied from.
        return ($body -join "`n")
    }
    return $null
}

# First non-blank line after a label line matching $LabelPattern, within a range.
function Get-StatementAfterLabel {
    param([string[]]$Lines, [int]$StartIndex, [int]$StopIndex, [string]$LabelPattern)

    for ($i = $StartIndex; $i -lt $StopIndex; $i++) {
        if ($Lines[$i] -match $LabelPattern) {
            for ($j = $i + 1; $j -lt $StopIndex; $j++) {
                if ($Lines[$j].Trim() -ne '') { return $Lines[$j].Trim() }
            }
        }
    }
    return $null
}

# Does this line start an orphan entry? Accepts every known format plus plain headings.
# Deliberately strict so prose mentioning a finding ID is not mistaken for an entry.
function Test-OrphanEntryLine {
    param([string]$Line)

    if ($Line -notmatch 'S\d+-J\d+') { return $false }

    return (
        ($Line -match '^#{2,5}\s')                               -or  # ### S4-J3, ### [[..|S4-J3]]
        ($Line -match '^\*\*\s*S\d+-J\d+\s*\*\*\s*$')            -or  # **S3-J5**
        ($Line -match '^\*\*Finding ID:\*\*')                    -or  # **Finding ID:** S3-J5
        ($Line -match '^\*\*\s*Finding\s*\*\*')
    )
}

# Pull the finding ID off an entry line, preferring wikilink display text.
function Get-FindingId {
    param([string]$Line)

    if ($Line -match '\\\|(S\d+-J\d+)\]\]') { return $Matches[1] }   # [[file#S4-J3\|S4-J3]]
    if ($Line -match '\|(S\d+-J\d+)\]\]')   { return $Matches[1] }
    if ($Line -match '(S\d+-J\d+)')         { return $Matches[1] }
    return $Line.Trim()
}

# Member interview IDs from a cluster's table rows. First cell only, so finding IDs
# in later columns are not mistaken for interviews.
function Get-ClusterMembers {
    param([string[]]$Lines, [int]$StartIndex, [int]$StopIndex)

    $ids = New-Object System.Collections.Generic.List[string]
    for ($i = $StartIndex; $i -lt $StopIndex; $i++) {
        $l = $Lines[$i]
        if ($l -notmatch '^\s*\|') { continue }
        if ($l -match '^\s*\|[\s\-:|]+\|\s*$') { continue }          # separator row

        $cells = $l -split '(?<!\\)\|'
        if ($cells.Count -lt 2) { continue }
        $first = $cells[1]

        if ($first -match '\b(S\d+)\b' -and $first -notmatch 'S\d+-J\d+') {
            if (-not $ids.Contains($Matches[1])) { $ids.Add($Matches[1]) }
        }
    }
    return $ids
}

# ---------------------------------------------------------------------------
# Extraction 1: B-extracts
# ---------------------------------------------------------------------------

$out       = New-Object System.Collections.Generic.List[string]
$missing   = 0
$processed = 0

$bFiles = Get-ChildItem $BDir -Filter *.md |
          Sort-Object { if ($_.Name -match '^S(\d+)_') { [int]$Matches[1] } else { [int]::MaxValue } }

if ($bFiles.Count -eq 0) { $fatal.Add("No .md files found in $BDir") }

$out.Add('# Document B extracts for synthesis pass two')
$out.Add('')
$out.Add('Snapshot and disconfirmations for each interview, copied verbatim from the Document B analyst review files.')
$out.Add('')

foreach ($f in $bFiles) {
    $id = if ($f.Name -match '^(S\d+)_') { $Matches[1] } else { [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
    $lines = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) -split "`r?`n"

    $out.Add('---')
    $out.Add('')
    $out.Add("## $id")
    $out.Add('')
    $out.Add("Source file: $($f.Name)")
    $out.Add('')

    foreach ($w in $WANTED) {
        $body = Get-SectionBody -Lines $lines -Patterns $w.Patterns
        $out.Add("### $($w.Label)")
        $out.Add('')
        if ($null -eq $body) {
            $out.Add("SECTION MISSING: $($w.Label)")
            $issues.Add("$id ($($f.Name)): SECTION MISSING: $($w.Label)")
            $missing++
        } else {
            $out.Add($body)
        }
        $out.Add('')
    }
    $processed++
}

[System.IO.File]::WriteAllText((Join-Path $OutDir 'B-extracts.md'), ($out -join "`n"), $utf8)

# ---------------------------------------------------------------------------
# Extraction 2: cluster manifest
# ---------------------------------------------------------------------------

$sLines = [System.IO.File]::ReadAllText($SynthesisPath, [System.Text.Encoding]::UTF8) -split "`r?`n"

# Part 2 / Part 3 boundaries, by name and at any heading level. Falls back to an
# "Orphans" heading if the "Part N" naming is ever dropped.
$part2 = -1; $part3 = $sLines.Count
for ($i = 0; $i -lt $sLines.Count; $i++) {
    if ($part2 -lt 0 -and $sLines[$i] -match '^#{1,6}\s+(Part\s+2\b|.*\bOrphans?\b)') { $part2 = $i; continue }
    if ($part2 -ge 0 -and $sLines[$i] -match '^#{1,6}\s+(Part\s+3\b|.*\bSynthesis\s+notes\b)') { $part3 = $i; break }
}
if ($part2 -lt 0) { $issues.Add('manifest: no Part 2 / Orphans heading found; no orphans extracted') }

$man = New-Object System.Collections.Generic.List[string]
$man.Add('# Cluster manifest for synthesis pass two')
$man.Add('')
$man.Add("Source: $([System.IO.Path]::GetFileName($SynthesisPath))")
$man.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$man.Add('')
$man.Add('## Clusters')
$man.Add('')

$clusterIdx = @()
for ($i = 0; $i -lt $sLines.Count; $i++) {
    if ($sLines[$i] -match '^#{2,4}\s+Cluster\b') { $clusterIdx += $i }
}

$clusterCount = 0
for ($k = 0; $k -lt $clusterIdx.Count; $k++) {
    $start = $clusterIdx[$k]
    $stop  = if ($k + 1 -lt $clusterIdx.Count) { $clusterIdx[$k + 1] }
             elseif ($part2 -ge 0)             { $part2 }
             else                              { $sLines.Count }

    $man.Add($sLines[$start].Trim())
    $man.Add('')

    $stmt = Get-StatementAfterLabel -Lines $sLines -StartIndex $start -StopIndex $stop -LabelPattern 'Canonical\s+JTBD\s+statement'
    if ($null -eq $stmt) {
        $stmt = Get-StatementAfterLabel -Lines $sLines -StartIndex $start -StopIndex $stop -LabelPattern 'JTBD\s+statement'
    }
    if ($null -eq $stmt) {
        $man.Add('SECTION MISSING: Canonical JTBD statement')
        $issues.Add("manifest: $($sLines[$start].Trim()) has no canonical JTBD statement")
        $missing++
    } else {
        $man.Add($stmt)
    }

    if ($IncludeMembers) {
        $members = Get-ClusterMembers -Lines $sLines -StartIndex $start -StopIndex $stop
        $man.Add('')
        if ($members.Count -gt 0) {
            $man.Add("Members: $($members -join ', ')")
        } else {
            $man.Add('Members: NONE FOUND')
            $issues.Add("manifest: $($sLines[$start].Trim()) has no parseable member interview IDs")
        }
    }

    $man.Add('')
    $clusterCount++
}

$man.Add('## Orphans')
$man.Add('')

$orphanCount = 0
if ($part2 -ge 0) {
    $orphanIdx = @()
    for ($i = $part2 + 1; $i -lt $part3; $i++) {
        if (Test-OrphanEntryLine -Line $sLines[$i]) { $orphanIdx += $i }
    }

    for ($k = 0; $k -lt $orphanIdx.Count; $k++) {
        $start = $orphanIdx[$k]
        $stop  = if ($k + 1 -lt $orphanIdx.Count) { $orphanIdx[$k + 1] } else { $part3 }

        $fid = Get-FindingId -Line $sLines[$start]
        $man.Add("### $fid")
        $man.Add('')

        $stmt = Get-StatementAfterLabel -Lines $sLines -StartIndex $start -StopIndex $stop -LabelPattern 'JTBD\s+statement'
        if ($null -eq $stmt) {
            $man.Add('SECTION MISSING: JTBD statement')
            $issues.Add("manifest: orphan $fid has no JTBD statement")
            $missing++
        } else {
            $man.Add($stmt)
        }
        $man.Add('')
        $orphanCount++
    }
}

[System.IO.File]::WriteAllText((Join-Path $OutDir 'cluster-manifest.md'), ($man -join "`n"), $utf8)

# ---------------------------------------------------------------------------
# Validation, issues log, report
# ---------------------------------------------------------------------------

# A silently empty manifest is the failure mode that matters: the format changed and
# nothing matched. Treat zero clusters as fatal rather than reporting a tidy zero.
if ($clusterCount -eq 0) {
    $fatal.Add("No clusters matched in $([System.IO.Path]::GetFileName($SynthesisPath)). The synthesis format likely changed; check the '## Cluster N:' heading pattern.")
}
if ($processed -eq 0) {
    $fatal.Add("No interviews extracted from $BDir.")
}

foreach ($x in $fatal) { $issues.Insert(0, "FATAL: $x") }

if ($issues.Count -eq 0) {
    $issues.Add('No extraction issues. Every interview yielded both sections, and every cluster and orphan yielded a JTBD statement.')
}
[System.IO.File]::WriteAllText((Join-Path $OutDir 'EXTRACTION-ISSUES.txt'), ($issues -join "`n"), $utf8)

Write-Output ""
Write-Output "Source synthesis     : $([System.IO.Path]::GetFileName($SynthesisPath))"
Write-Output "Interviews extracted : $processed"
Write-Output "Sections missing     : $missing"
Write-Output "Clusters in manifest : $clusterCount"
Write-Output "Orphans in manifest  : $orphanCount"
if ($IncludeMembers) { Write-Output "Cluster members      : included" }
Write-Output ""
Write-Output "Wrote:"
Write-Output "  $(Join-Path $OutDir 'B-extracts.md')"
Write-Output "  $(Join-Path $OutDir 'cluster-manifest.md')"
Write-Output "  $(Join-Path $OutDir 'EXTRACTION-ISSUES.txt')"

if ($fatal.Count -gt 0) {
    Write-Output ""
    foreach ($x in $fatal) { Write-Output "FATAL: $x" }
    exit 1
}
