<#
    splice-pass2-patch.ps1

    Splices a pass-two disconfirmations patch into a pass-one synthesis document.

    Clusters: the existing "**Disconfirmations:** Expected in pass two." field is REPLACED.
    Orphans:  pass one writes no disconfirmations field at all, so one is INSERTED at the
              end of the orphan's block.

    Matching is by exact string. Cluster entries match on the full heading text
    ("Cluster 3: Rehearsing a specific high-stakes conversation"); orphan entries match
    on the finding ID pulled from the entry label, accepting both "**Cluster S4-J3**"
    and "**Orphan S4-J3**" since the pass-two prompt's wording has produced both.

    Safety
    ------
    By default nothing is written unless EVERY cluster and orphan in the synthesis has a
    matching patch entry and every patch entry finds a target. A half-spliced synthesis is
    worse than none, so mismatches abort with exit code 1 and a report of what did not line
    up. -Force writes anyway. -InPlace overwrites the synthesis after taking a .bak copy.

    Usage
    -----
      .\splice-pass2-patch.ps1 -SynthesisPath "...\result-pass1-v0.5.md" -PatchPath "...\result-pass2-patch-v0.3.md"
      .\splice-pass2-patch.ps1 -SynthesisPath ... -PatchPath ... -InPlace
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SynthesisPath,
    [Parameter(Mandatory=$true)][string]$PatchPath,
    [string]$OutPath,
    [string]$CorpusDir = (Join-Path $PSScriptRoot '..\inputs\A'),
    [switch]$InPlace,
    [switch]$Force,
    [switch]$NoNotes
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $SynthesisPath)) { throw "Synthesis not found: $SynthesisPath" }
if (-not (Test-Path $PatchPath))     { throw "Patch not found: $PatchPath" }

if (-not $OutPath) {
    if ($InPlace) { $OutPath = $SynthesisPath }
    else {
        $dir  = Split-Path $SynthesisPath -Parent
        $base = [System.IO.Path]::GetFileNameWithoutExtension($SynthesisPath)
        $OutPath = Join-Path $dir "$base-enriched.md"
    }
}

$synth = ([System.IO.File]::ReadAllText($SynthesisPath, [System.Text.Encoding]::UTF8)) -split "`r?`n"
$patch = ([System.IO.File]::ReadAllText($PatchPath,     [System.Text.Encoding]::UTF8)) -split "`r?`n"

# ---------------------------------------------------------------------------
# Parse the patch into: key -> disconfirmations block (list of lines)
# ---------------------------------------------------------------------------

$entries   = @{}
$entryKeys = New-Object System.Collections.Generic.List[string]
$notes     = New-Object System.Collections.Generic.List[string]

$curKey = $null
$buf    = $null
$inNotes = $false

function Save-Entry {
    if ($script:curKey -and $script:buf) {
        while ($script:buf.Count -gt 0 -and $script:buf[$script:buf.Count-1].Trim() -eq '') {
            $script:buf.RemoveAt($script:buf.Count-1)
        }
        # Collapse any run of blank lines directly under the label to exactly one,
        # so spacing does not depend on how the patch happened to be formatted.
        while ($script:buf.Count -gt 2 -and $script:buf[1].Trim() -eq '' -and $script:buf[2].Trim() -eq '') {
            $script:buf.RemoveAt(1)
        }
        if ($script:buf.Count -gt 1 -and $script:buf[1].Trim() -ne '') {
            $script:buf.Insert(1, '')
        }
        # Flat string array. Wrapping this in an extra array layer makes the later
        # [string[]] cast flatten the block into one space-joined line.
        $script:entries[$script:curKey] = @($script:buf.ToArray())
    }
    $script:curKey = $null
    $script:buf    = $null
}

foreach ($line in $patch) {

    if ($line -match '^\*\*Pass two notes\*\*\s*$') { Save-Entry; $inNotes = $true; continue }
    if ($inNotes) { $notes.Add($line); continue }

    # Entry header. Pass two has emitted three shapes for orphans across runs, so accept
    # all of them: **Cluster 3: name**, **Cluster S4-J3**, **Orphan S4-J3**, **S4-J3**.
    # The bare form is matched by an explicit finding-ID pattern, never a loose wildcard,
    # so that **Disconfirmations:** can never be mistaken for an entry header.
    if (($line -match '^\*\*(?:Cluster|Orphan)\s+(.+?)\*\*\s*$') -or ($line -match '^\*\*(S\d+-J\d+)\*\*\s*$')) {
        Save-Entry
        $label = $Matches[1].Trim()
        if ($label -match '^(S\d+-J\d+)$') { $curKey = $Matches[1] }        # orphan
        else                               { $curKey = "Cluster $label" }   # cluster
        if (-not $entryKeys.Contains($curKey)) { $entryKeys.Add($curKey) }
        continue
    }

    if ($null -eq $curKey) { continue }

    # The disconfirmations field itself, either inline or as a following block.
    if ($line -match '^\*\*Disconfirmations:\*\*(.*)$') {
        $buf = New-Object System.Collections.Generic.List[string]
        $tail = $Matches[1].Trim()
        if ($tail -ne '') { $buf.Add("**Disconfirmations:** $tail") }
        else              { $buf.Add('**Disconfirmations:**') }
        continue
    }

    if ($null -ne $buf) {
        if ($line -match '^---\s*$') { Save-Entry; continue }
        $buf.Add($line)
    }
}
Save-Entry

while ($notes.Count -gt 0 -and $notes[0].Trim() -eq '')                 { $notes.RemoveAt(0) }
while ($notes.Count -gt 0 -and $notes[$notes.Count-1].Trim() -eq '')    { $notes.RemoveAt($notes.Count-1) }
$notes2 = @($notes | Where-Object { $_ -notmatch '^---\s*$' })

# ---------------------------------------------------------------------------
# Finding ID -> source file, for turning "(source: S21-J9)" into a wikilink
# ---------------------------------------------------------------------------

$findingFile = @{}
if (Test-Path $CorpusDir) {
    foreach ($cf in Get-ChildItem $CorpusDir -Filter *.md) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($cf.Name)
        foreach ($h in (Get-Content $cf.FullName -Encoding UTF8 | Select-String -Pattern '^###\s+(S\d+-J\d+)\s*$')) {
            $findingFile[$h.Matches[0].Groups[1].Value] = $baseName
        }
    }
}

# Rewrite bare "(source: S21-J9)" as a wikilink to that finding's heading. A plain pipe is
# correct here: these attributions sit in prose, not in a table cell, so the escaping the
# tables require would render literally. Already-linked sources and unknown IDs are left alone.
function Add-SourceLinks {
    param([string]$Text)
    if ($findingFile.Count -eq 0) { return $Text }
    return [regex]::Replace($Text, '\(source:\s*(S\d+-J\d+)\)', {
        param($m)
        $id = $m.Groups[1].Value
        if ($findingFile.ContainsKey($id)) { "(source: [[$($findingFile[$id])#$id|$id]])" }
        else                               { $m.Value }
    })
}

# ---------------------------------------------------------------------------
# Locate splice targets in the synthesis
# ---------------------------------------------------------------------------

# Part 2 / Part 3 boundaries so orphans are found in Part 2 only.
$part2 = -1; $part3 = $synth.Count
for ($i = 0; $i -lt $synth.Count; $i++) {
    if ($part2 -lt 0 -and $synth[$i] -match '^#{1,6}\s+(Part\s+2\b|.*\bOrphans?\b)') { $part2 = $i; continue }
    if ($part2 -ge 0 -and $synth[$i] -match '^#{1,6}\s+(Part\s+3\b|.*\bSynthesis\s+notes\b)') { $part3 = $i; break }
}

$targets = New-Object System.Collections.Generic.List[object]   # key, start, stop, kind

$clusterIdx = @()
for ($i = 0; $i -lt $synth.Count; $i++) {
    if ($synth[$i] -match '^#{2,4}\s+Cluster\b') { $clusterIdx += $i }
}
for ($k = 0; $k -lt $clusterIdx.Count; $k++) {
    $start = $clusterIdx[$k]
    $stop  = if ($k + 1 -lt $clusterIdx.Count) { $clusterIdx[$k+1] }
             elseif ($part2 -ge 0)             { $part2 }
             else                              { $synth.Count }
    $key = ($synth[$start] -replace '^#{2,4}\s+', '').Trim()
    $targets.Add([pscustomobject]@{ Key=$key; Start=$start; Stop=$stop; Kind='cluster' })
}

if ($part2 -ge 0) {
    $orphIdx = @()
    for ($i = $part2 + 1; $i -lt $part3; $i++) {
        $l = $synth[$i]
        if ($l -notmatch 'S\d+-J\d+') { continue }
        if (($l -match '^#{2,5}\s') -or ($l -match '^\*\*\s*S\d+-J\d+\s*\*\*\s*$') -or ($l -match '^\*\*Finding ID:\*\*')) {
            $orphIdx += $i
        }
    }
    for ($k = 0; $k -lt $orphIdx.Count; $k++) {
        $start = $orphIdx[$k]
        $stop  = if ($k + 1 -lt $orphIdx.Count) { $orphIdx[$k+1] } else { $part3 }
        $key = if ($synth[$start] -match '\\\|(S\d+-J\d+)\]\]') { $Matches[1] }
               elseif ($synth[$start] -match '(S\d+-J\d+)')     { $Matches[1] }
               else { $null }
        if ($key) { $targets.Add([pscustomobject]@{ Key=$key; Start=$start; Stop=$stop; Kind='orphan' }) }
    }
}

# ---------------------------------------------------------------------------
# Validate before writing anything
# ---------------------------------------------------------------------------

$problems      = New-Object System.Collections.Generic.List[string]
$targetKeys    = @($targets | ForEach-Object { $_.Key })
$unmatchedTgt  = @($targetKeys  | Where-Object { -not $entries.ContainsKey($_) })
$unmatchedPtch = @($entryKeys   | Where-Object { $targetKeys -notcontains $_ })

foreach ($k in $unmatchedTgt)  { $problems.Add("synthesis target has no patch entry : $k") }
foreach ($k in $unmatchedPtch) { $problems.Add("patch entry matches no target       : $k") }

if ($problems.Count -gt 0 -and -not $Force) {
    Write-Output ""
    Write-Output "SPLICE ABORTED. Nothing written."
    Write-Output "Targets in synthesis : $($targets.Count)   Entries in patch: $($entryKeys.Count)"
    Write-Output ""
    foreach ($p in $problems) { Write-Output "  $p" }
    Write-Output ""
    Write-Output "Cluster names must match byte-for-byte between the two files. Re-run with -Force to splice what does match."
    exit 1
}

# ---------------------------------------------------------------------------
# Splice, walking bottom-up so earlier indexes stay valid
# ---------------------------------------------------------------------------

$outLines = New-Object System.Collections.Generic.List[string]
$outLines.AddRange([string[]]$synth)

$spliced = @{ cluster = 0; orphan = 0; merged = 0 }

foreach ($t in ($targets | Sort-Object Start -Descending)) {
    if (-not $entries.ContainsKey($t.Key)) { continue }
    $block = @($entries[$t.Key])

    # Existing field inside this target's range?
    $fieldAt = -1
    for ($i = $t.Start; $i -lt $t.Stop -and $i -lt $outLines.Count; $i++) {
        if ($outLines[$i] -match '^\*\*Disconfirmations:\*\*') { $fieldAt = $i; break }
    }

    if ($fieldAt -ge 0) {
        # Find the extent of the existing field: to just before the next bold label,
        # heading, or rule.
        $end = $fieldAt + 1
        while ($end -lt $t.Stop -and $end -lt $outLines.Count) {
            $l = $outLines[$end]
            if ($l -match '^\*\*[^*]+:\*\*' -or $l -match '^#{1,6}\s' -or $l -match '^---\s*$') { break }
            $end++
        }
        while ($end -gt $fieldAt + 1 -and $outLines[$end-1].Trim() -eq '') { $end-- }

        $existing     = @($outLines[$fieldAt..($end-1)])
        $existingText = ($existing -join "`n")

        # Pass one fills this field itself when a finding in its own input actively
        # contradicts the cluster. Pass two never sees that, so replacing wholesale would
        # silently destroy real counter-evidence. Merge instead, keeping pass one's text
        # first and appending pass two's quotes beneath it.
        # Test for the placeholder EXACTLY, not as a substring. Pass one may write real
        # counter-evidence and then close with "Otherwise expected in pass two.", which a
        # substring test reads as an empty placeholder and silently overwrites.
        $existingBody = ($existingText -replace '^\*\*Disconfirmations:\*\*', '').Trim()
        if ($existingBody -notmatch '^Expected in pass two\.?$') {

            $preserved = @($existing | ForEach-Object { Add-SourceLinks $_ })

            # Strip pass two's own label line; keep its body.
            $p2body = @()
            for ($k = 0; $k -lt $block.Count; $k++) {
                if ($k -eq 0 -and $block[$k] -match '^\*\*Disconfirmations:\*\*\s*(.*)$') {
                    $tail = $Matches[1].Trim()
                    if ($tail -ne '' -and $tail -notmatch 'None found in review files') { $p2body += $tail }
                    continue
                }
                $p2body += $block[$k]
            }
            # Pass two's block carries its own leading blank under the label. Drop it, or
            # the join with pass one's text doubles up.
            while ($p2body.Count -gt 0 -and $p2body[0].Trim() -eq '') { $p2body = $p2body[1..($p2body.Count-1)] }
            $p2text = ($p2body -join "`n")

            if ($p2text.Trim() -eq '' -or $p2text -match 'None found in review files') {
                $merged = $preserved                       # pass two added nothing
            } else {
                $merged = $preserved + @('') + $p2body
            }

            $outLines.RemoveRange($fieldAt, $end - $fieldAt)
            $outLines.InsertRange($fieldAt, [string[]]$merged)
            $spliced['merged']++
        }
        else {
            $count = $end - $fieldAt
            $outLines.RemoveRange($fieldAt, $count)
            $outLines.InsertRange($fieldAt, [string[]]$block)
            $spliced['cluster']++
        }
    }
    else {
        # No field: insert at the end of this block. Walk back over trailing blanks, and
        # over a trailing horizontal rule if the document separates entries with one,
        # so the field lands inside its own entry rather than after the divider.
        $ins = $t.Stop
        while ($ins -gt $t.Start -and $ins -le $outLines.Count -and $outLines[$ins-1].Trim() -eq '') { $ins-- }
        if ($ins -gt $t.Start -and $outLines[$ins-1] -match '^-{3,}\s*$') {
            $ins--
            while ($ins -gt $t.Start -and $outLines[$ins-1].Trim() -eq '') { $ins-- }
        }
        $payload = New-Object System.Collections.Generic.List[string]
        $payload.Add('')
        $payload.AddRange([string[]]$block)
        # Only pad below if what follows is not already blank, else the boundary doubles up.
        if ($ins -lt $outLines.Count -and $outLines[$ins].Trim() -ne '') { $payload.Add('') }
        $outLines.InsertRange($ins, [string[]]$payload)
        $spliced['orphan']++
    }
}

if ($notes2.Count -gt 0 -and -not $NoNotes) {
    $outLines.Add('')
    $outLines.Add('---')
    $outLines.Add('')
    $outLines.Add('## Pass two notes')
    $outLines.Add('')
    $outLines.AddRange([string[]]$notes2)
}

if ($InPlace) {
    $bak = "$SynthesisPath.bak"
    Copy-Item $SynthesisPath $bak -Force
    Write-Output "Backup written: $bak"
}

[System.IO.File]::WriteAllText($OutPath, ($outLines -join "`n"), $utf8)

Write-Output ""
Write-Output "Synthesis : $([System.IO.Path]::GetFileName($SynthesisPath))"
Write-Output "Patch     : $([System.IO.Path]::GetFileName($PatchPath))"
Write-Output "Clusters spliced (replaced) : $($spliced['cluster'])"
Write-Output "Orphans spliced (inserted)  : $($spliced['orphan'])"
Write-Output "Fields merged, not replaced : $($spliced['merged'])   (pass one had already filled these)"
Write-Output "Pass two notes appended     : $(if ($notes2.Count -gt 0 -and -not $NoNotes) { 'yes' } else { 'no' })"
if ($problems.Count -gt 0) {
    Write-Output ""
    Write-Output "WARNING, forced splice with $($problems.Count) mismatch(es):"
    foreach ($p in $problems) { Write-Output "  $p" }
}
Write-Output ""
Write-Output "Wrote: $OutPath"
