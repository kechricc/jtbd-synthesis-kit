<#
    build-super-cluster-view.ps1

    Builds the super cluster view: job clusters from the synthesis, regrouped into the
    analyst's super clusters and ordered by tier.

    Nothing is summarised. Every cluster block is carried through verbatim, only demoted
    one heading level so it nests under its super cluster. Clusters assigned to no super
    cluster are carried at the end rather than dropped, so the view remains a complete
    representation of the synthesis.

    Counts per super cluster
    ------------------------
    Unique interviews          distinct interview IDs across all member clusters, an
                               interview appearing in two member clusters counted once
    Unsolved or partly solved  distinct interviews whose Job solved reads No or
                               "Partially, needs improvement" in at least one member cluster
    Rows                       the raw row total, so the deduplication is visible

    There are deliberately no denominators. A count is a number of people, not a proportion
    of any population. The population size is stated once, in the preamble.

    Usage
    -----
      .\build-super-cluster-view.ps1
      .\build-super-cluster-view.ps1 -Noun "teacher" -NounPlural "teachers" -CorpusSize 22
      .\build-super-cluster-view.ps1 -JobSolvedColumn 5     # if you dropped the two provider columns

    If your table's Job solved column is not the 7th, the script will tell you which column
    index it found it at rather than silently counting the wrong thing.
#>

[CmdletBinding()]
param(
    [string]$SynthesisPath = (Join-Path $PSScriptRoot '..\outputs\result-pass1-enriched.md'),
    [string]$RationalePath = (Join-Path $PSScriptRoot '..\outputs\super-cluster-rationale.md'),
    [string]$OutPath       = (Join-Path $PSScriptRoot '..\outputs\super-cluster-view.md'),
    [string]$Noun          = 'interviewee',
    [string]$NounPlural    = 'interviewees',
    [int]$CorpusSize       = 0,
    [int]$JobSolvedColumn  = 7,
    [int]$MaxTier          = 4
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($p in @($SynthesisPath, $RationalePath)) {
    if (-not (Test-Path $p)) { throw "Not found: $p" }
}

# ---------------------------------------------------------------------------
# Read the rationale file in @@ marker format
# ---------------------------------------------------------------------------

function Read-Rationale {
    param([string]$Path)
    $list = @(); $cur = $null; $mode = $null
    foreach ($l in (([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)) -split "`r?`n")) {
        if ($l -match '^@@JTBD\s+(.+)$') {
            if ($cur) { $list += $cur }
            $cur = @{ Id=$Matches[1].Trim(); Tier=0; Title=''; Clusters=@();
                      Rationale=New-Object System.Collections.Generic.List[string];
                      Review=New-Object System.Collections.Generic.List[string] }
            $mode = $null; continue
        }
        if ($null -eq $cur) { continue }
        if ($l -match '^@@TIER\s+(\d+)')  { $cur.Tier  = [int]$Matches[1]; $mode=$null; continue }
        if ($l -match '^@@TITLE\s+(.+)$') { $cur.Title = $Matches[1].Trim(); $mode=$null; continue }
        if ($l -match '^@@CLUSTERS\s*(.*)$') {
            $t = $Matches[1].Trim()
            if ($t -eq '') { $cur.Clusters = @() }
            else { $cur.Clusters = @($t -split ',' | ForEach-Object { [int]$_.Trim() }) }
            $mode=$null; continue
        }
        if ($l -match '^@@RATIONALE') { $mode='R'; continue }
        if ($l -match '^@@REVIEW')    { $mode='V'; continue }
        if ($l -match '^@@END')       { $mode=$null; continue }
        if ($mode -eq 'R') { $cur.Rationale.Add($l) } elseif ($mode -eq 'V') { $cur.Review.Add($l) }
    }
    if ($cur) { $list += $cur }
    return $list
}

function Trim-Block {
    param($b)
    while ($b.Count -gt 0 -and ($b[$b.Count-1].Trim() -eq '' -or $b[$b.Count-1] -match '^-{3,}\s*$')) {
        $b.RemoveAt($b.Count-1)
    }
    return $b
}

# ---------------------------------------------------------------------------
# Parse the synthesis: cluster blocks and per-row Job solved values
# ---------------------------------------------------------------------------

$lines  = ([System.IO.File]::ReadAllText($SynthesisPath, [System.Text.Encoding]::UTF8)) -split "`r?`n"
$blocks = @{}; $rows = @{}; $order = @()
$headerChecked = $false
$headerWarn    = $null

$cur = $null; $buf = $null
foreach ($l in $lines) {
    if ($l -match '^##\s+Cluster\s+(\d+):') {
        if ($cur) { $blocks[$cur] = $buf }
        $cur = [int]$Matches[1]; $order += $cur
        $buf = New-Object System.Collections.Generic.List[string]
        $rows[$cur] = @{}
    }
    elseif ($l -match '^#{1,3}\s+Part\s+\d' -and $cur) { $blocks[$cur] = $buf; $cur = $null; $buf = $null }

    if ($cur) {
        $buf.Add($l)

        # Header row: a table line with no wikilink in it. Check once that the configured
        # column really is Job solved, so a changed table shape fails loudly instead of
        # counting whatever happens to sit at that index.
        if (-not $headerChecked -and $l -match '^\s*\|' -and $l -notmatch '\[\[' -and $l -notmatch '^\s*\|[\s\-:|]+\|\s*$') {
            $hc = [regex]::Split($l.Trim(), '(?<!\\)\|')
            $headerChecked = $true
            if ($hc.Count -le $JobSolvedColumn -or $hc[$JobSolvedColumn].Trim() -notmatch '(?i)job\s+solved') {
                $found = -1
                for ($z = 0; $z -lt $hc.Count; $z++) { if ($hc[$z].Trim() -match '(?i)job\s+solved') { $found = $z; break } }
                if ($found -ge 0) {
                    $headerWarn = "Job solved is column $found, not $JobSolvedColumn. Re-run with -JobSolvedColumn $found."
                } else {
                    $headerWarn = "No 'Job solved' column found in the table header. Counts will be empty."
                }
            }
        }

        if ($l -match '^\|' -and $l -match '\[\[') {
            $cells = [regex]::Split($l.Trim(), '(?<!\\)\|')
            if ($cells.Count -gt $JobSolvedColumn) {
                $iv = if ($cells[1] -match '\\\|([^\]]+)\]\]') { $Matches[1].Trim() } else { $cells[1].Trim() }
                $rows[$cur][$iv] = $cells[$JobSolvedColumn].Trim()
            }
        }
    }
}
if ($cur) { $blocks[$cur] = $buf }
foreach ($k in @($blocks.Keys)) { $blocks[$k] = Trim-Block $blocks[$k] }

if ($blocks.Count -eq 0) {
    throw "No clusters matched in $([System.IO.Path]::GetFileName($SynthesisPath)). Expected '## Cluster N:' headings."
}
if ($headerWarn) {
    Write-Output ""
    Write-Output "ABORTED. $headerWarn"
    Write-Output "Nothing written."
    exit 1
}

$sc = Read-Rationale -Path $RationalePath
if ($sc.Count -eq 0) { throw "No @@JTBD blocks found in $([System.IO.Path]::GetFileName($RationalePath))." }

# A cluster in two super clusters is double counted and would otherwise pass silently.
$seen = @{}; $dupes = @()
foreach ($s in $sc) {
    foreach ($c in $s.Clusters) {
        if ($seen.ContainsKey($c)) { $dupes += "Cluster $c is in both $($seen[$c]) and $($s.Id)" }
        else { $seen[$c] = $s.Id }
    }
}

# ---------------------------------------------------------------------------
# Assemble, tier by tier
# ---------------------------------------------------------------------------

$out = New-Object System.Collections.Generic.List[string]
$assigned = @{}

$popLine = if ($CorpusSize -gt 0) { ", out of $CorpusSize interviewed" } else { "" }

$out.Add('# Jobs to be done, super cluster view')
$out.Add('')
$out.Add("Job clusters regrouped into super clusters and ordered by tier. No cluster content is summarised: every cluster is carried through in full beneath its super cluster.")
$out.Add('')
$out.Add("**Counts.** Unique interviews deduplicates across member clusters, so a $Noun who surfaced two member clusters is counted once. The unsolved count is of distinct interviews whose Job solved reads No or Partially, needs improvement in at least one member cluster. Raw rows are shown so the effect of deduplication is visible. There are no denominators anywhere: a count is a number of people$popLine, not a proportion of any population.")
$out.Add('')
$out.Add('**Review notes** under each super cluster assess the tiering rationale against the underlying data. They are not part of the original write up.')
$out.Add('')

function Add-Super {
    param($s)
    $ivs = @{}; $bad = @{}; $raw = 0
    foreach ($c in $s.Clusters) {
        if (-not $script:rows.ContainsKey($c)) { continue }
        foreach ($iv in $script:rows[$c].Keys) {
            $ivs[$iv] = $true; $raw++
            $j = $script:rows[$c][$iv]
            if ($j -eq 'No' -or $j -like 'Partially*') { $bad[$iv] = $true }
        }
        $script:assigned[$c] = $true
    }

    $script:out.Add("## JTBD $($s.Id): $($s.Title)")
    $script:out.Add('')
    if ($s.Clusters.Count -gt 0) {
        $script:out.Add("**Clusters:** $(($s.Clusters | ForEach-Object { "Cluster $_" }) -join ', ')")
        $script:out.Add('')
        $script:out.Add("**Unique interviews:** $($ivs.Count)")
        $script:out.Add('')
        $script:out.Add("**$($script:NounPluralCap) where the job is unsolved or only partly solved:** $($bad.Count)")
        $script:out.Add('')
        $script:out.Add("**Raw rows across member clusters:** $raw")
    } else {
        $script:out.Add('**Clusters:** none mapped')
        $script:out.Add('')
        $script:out.Add('**Unique interviews:** not countable from the cluster set, see the review note')
    }
    $script:out.Add('')
    $script:out.Add('**Tiering rationale:**'); $script:out.Add('')
    foreach ($r in $s.Rationale) { $script:out.Add($r) }
    $script:out.Add('')
    $script:out.Add('**Review note:**'); $script:out.Add('')
    foreach ($r in $s.Review) { $script:out.Add($r) }
    $script:out.Add('')
    foreach ($c in $s.Clusters) {
        if (-not $script:blocks.ContainsKey($c)) { continue }
        foreach ($b in $script:blocks[$c]) {
            if ($b -match '^##\s+Cluster\s+\d+:') { $script:out.Add('#' + $b) } else { $script:out.Add($b) }
        }
        $script:out.Add('')
    }
}

$NounPluralCap = (Get-Culture).TextInfo.ToTitleCase($NounPlural)

foreach ($tier in 1..$MaxTier) {
    $sTier = @($sc | Where-Object { $_.Tier -eq $tier })
    if ($sTier.Count -eq 0) { continue }

    $out.Add('---'); $out.Add('')
    $out.Add("# Tier $tier"); $out.Add('')
    $out.Add("Jobs in this tier: $($sTier.Count).")
    $out.Add('')

    foreach ($s in $sTier) { Add-Super $s }
}

# ---------------------------------------------------------------------------
# Clusters assigned to no super cluster
# ---------------------------------------------------------------------------

$left = @($order | Where-Object { -not $assigned.ContainsKey($_) })
if ($left.Count -gt 0) {
    $lIvs = @{}; $lRows = 0
    foreach ($c in $left) { foreach ($iv in $rows[$c].Keys) { $lIvs[$iv] = $true; $lRows++ } }
    $out.Add('---'); $out.Add('')
    $out.Add('# Clusters not assigned to a super cluster'); $out.Add('')
    $out.Add("These $($left.Count) clusters carry $lRows rows across $($lIvs.Count) unique interviews and appear in no tier. They are reproduced in full so this view stays a complete representation of the synthesis. Their absence from the tiering may be deliberate scoping or an omission; that is a decision to record rather than something the data settles.")
    $out.Add('')
    foreach ($c in $left) {
        foreach ($b in $blocks[$c]) {
            if ($b -match '^##\s+Cluster\s+\d+:') { $out.Add('#' + $b) } else { $out.Add($b) }
        }
        $out.Add('')
    }
}

[System.IO.File]::WriteAllText($OutPath, ($out -join "`n"), $utf8)

foreach ($tier in 1..$MaxTier) {
    $n = @($sc | Where-Object { $_.Tier -eq $tier }).Count
    if ($n -gt 0) { Write-Output ("Tier {0}: {1} jobs" -f $tier, $n) }
}
$noTier = @($sc | Where-Object { $_.Tier -lt 1 -or $_.Tier -gt $MaxTier })
if ($noTier.Count -gt 0) {
    Write-Output ""
    foreach ($s in $noTier) { Write-Output "WARNING: JTBD $($s.Id) has tier $($s.Tier), outside 1..$MaxTier, and was NOT written." }
}

Write-Output ""
Write-Output "Clusters carried : $($assigned.Count) assigned, $($left.Count) unassigned, $($blocks.Count) total"
if ($dupes.Count -gt 0) {
    foreach ($d in $dupes) { Write-Output "WARNING: $d" }
}
Write-Output ("Size             : {0:N0} KB" -f ((Get-Item $OutPath).Length/1KB))
Write-Output ""
Write-Output "Wrote: $OutPath"
