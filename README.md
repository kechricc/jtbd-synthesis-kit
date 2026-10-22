# JTBD Synthesis Starter Kit

A pipeline for turning a set of interview transcripts into a tiered, evidence-linked map of the
jobs your interviewees are trying to get done. Every claim in the final document traces back to
a named person's verbatim words in two clicks.

This is a generalized copy of a pipeline that has been run twice on real corpora: 37 interviews
with one population and 8 with another. The prompts and scripts here are the same ones, with
the subject-specific parts replaced by placeholders.

## What this is

Most interview synthesis ends in a summary the reader has to trust. This kit is built so the
reader doesn't have to. It takes a folder of transcripts and produces a tiered map of jobs to
be done where every count is a count of people, every cluster links to the findings inside it,
and every finding links to the verbatim quote it rests on. Supporting evidence and
counter-evidence are gathered by separate passes that never see each other, and the final
tiering is yours, published next to a machine audit of your reasoning rather than replaced by
it.

It runs on Claude Code (or any agent runner that can take a prompt and a file) plus five
PowerShell scripts. No interview data ships with it; `inputs\` and `outputs\` are empty and
`.gitignore` keeps them that way.

## Read this first

`METHODOLOGY.html` — open it in any browser, straight from this folder. It explains what the
pipeline produces, why each stage is built the way it is, what changes for a new subject, and
what the method cannot do. Read it before running anything; the limitations section in
particular is worth knowing before you present results to anyone.

This README is the operating instructions. `METHODOLOGY.html` is the reasoning behind them.

## Before anything else

1. Fill in `PROJECT.md`. It lists nine placeholders and explains each one. Twenty minutes.
2. Find-and-replace those placeholders across all four files in `prompts\`.
3. Put your transcripts in `inputs\transcripts\`, named so the interview ID comes first and is
   followed by an underscore, with the interviewer's name second:

   ```
   S07_JaneD_MidCareer_Healthcare.md
   ```

   The ID must be unique. The interviewer name matters: pass one reports when a cluster's
   support leans on one interviewer's batch, which is a real artifact when interviewers split a
   corpus by segment, and it cannot do that if the names are absent. A single-interviewer corpus
   will say so and skip the check.

**Tune on six to eight interviews before running everything.** Both prior corpora were tuned
small and run large. The failure you are looking for at this stage is a `{{PROVIDER_LIST}}` that
does not fit what people actually hired, and it is much cheaper to find at eight.

## Folder layout

```
METHODOLOGY.html   the method explained, open in a browser
PROJECT.md         the nine placeholders, fill this in first
prompts\           four prompts, numbered in the order they are used
scripts\           five helper scripts
templates\         the rationale file format for stage 5
inputs\transcripts\  <- your transcripts
inputs\A\            <- Document A files, created by script
inputs\B\            <- Document B files, created by script
outputs\           results land here
pass2-inputs\      created by the extraction script
_backups\          created by the normalizer, .bak files, safe to delete
```

Script defaults resolve relative to `scripts\`, so the whole folder can be moved or copied
without editing any paths.

---

## Step 1. Analyze each interview

Prompt: `prompts\1-interview-analysis.md`
Input: one transcript
Output: save the full response to `outputs\raw\<same base name>-raw.md`

**One agent per transcript, each with a fresh context.** This is not an optimization, it is the
design. An analyst who has read the previous six transcripts will find the seventh confirming
what it already believes. Independence is what makes the cross-interview counts mean anything.

In Claude Code, the practical form is: launch a subagent per transcript, giving it the prompt as
its instructions and one transcript as its input. Batch them a few at a time.

Each response contains Document A and Document B separated by `=====DOCUMENT-BREAK=====`.
Document A is the findings, and is all the synthesis ever sees. Document B holds secondhand
claims, disconfirmations, and the contamination log. Nothing is thrown away and nothing weak is
promoted.

## Step 2. Split and normalize

```powershell
.\scripts\split-raw-documents.ps1
.\scripts\normalize-finding-headings.ps1
```

The first splits each raw response into `inputs\A\` and `inputs\B\`, refusing any file whose
delimiter is missing, doubled, or whose halves do not start with the expected headings.

The second converts each `**Finding ID:** S2-J3` into `### S2-J3`.

**Do not skip the second.** The synthesis deep-links every finding as an Obsidian anchor,
`[[file#S2-J3|S2-J3]]`, and Obsidian resolves anchors only against real headings. Against bold
labels the links are syntactically valid and completely dead: nothing in the output looks wrong,
and the break surfaces only when a human clicks one. Safe to re-run; `-WhatIfOnly` shows what
would change without writing.

## Step 3. Pass one, clustering

Prompt: `prompts\2-synthesis-pass1.md`
Input: every file in `inputs\A\`, with filenames visible to the agent
Output: save to `outputs\result-pass1.md`

It clusters findings across interviews by the progress sought, orders clusters by breadth, and
writes orphans and synthesis notes.

**Check these before moving on:**

- Every finding ID appears exactly once, in a cluster or as an orphan
- Every `[[file#Sx-Jy|Sx-Jy]]` anchor resolves to a real `### ` heading in the named file
- Every wikilink inside a table cell escapes the pipe as `\|`, or the table collapses
- No em dashes outside quoted material
- Orphan blocks end with `**Disconfirmations:** Expected in pass two.`
- "How well the job is served today" closes with one of its four fixed terms

Checking link syntax is not enough. Resolve the targets against the actual files.

## Step 4. Build the slim pass-two inputs

```powershell
.\scripts\extract-pass2-inputs.ps1 -IncludeMembers
```

Reads `inputs\B\` and `outputs\result-pass1.md`. Writes `pass2-inputs\B-extracts.md`,
`pass2-inputs\cluster-manifest.md`, and `pass2-inputs\EXTRACTION-ISSUES.txt`.

`-IncludeMembers` is required. Pass two marks a disconfirmation "(did not surface this job)"
when it comes from an interviewee outside the cluster, and the `Members:` line is the only way
it can tell.

If the script finds no clusters it aborts rather than writing a plausible-looking empty
manifest, which is what a pass-one format change looks like from the inside.

## Step 5. Pass two, disconfirmations

Prompt: `prompts\3-synthesis-pass2.md`
Inputs: the two files in `pass2-inputs\`
Output: save to `outputs\result-pass2-patch.md`

Pass two does not reproduce the synthesis. It emits a patch: one entry per cluster and orphan,
containing only the disconfirmations field. Cluster names must be reproduced byte-for-byte,
since the splicer matches on them.

This step is why Document B exists. Counter-evidence is gathered by a pass that has never seen
the supporting evidence, and cannot therefore be talked out of it.

## Step 6. Splice

```powershell
.\scripts\splice-pass2-patch.ps1 -SynthesisPath ".\outputs\result-pass1.md" -PatchPath ".\outputs\result-pass2-patch.md"
```

Writes `outputs\result-pass1-enriched.md`. The original is untouched.

If any cluster name fails to match, the splicer writes nothing and exits 1 with the mismatched
keys on both sides. That is deliberate: a half-spliced document is worse than none. `-Force`
overrides.

**After splicing, read one cluster block and one orphan block top to bottom.** The script's
counts confirm that entries matched, not that the result reads correctly. Every bug found in
this pipeline so far was found by reading output, not by a passing check.

## Step 7. Super clusters and tiering

This is the human step, and the point of the whole pipeline.

**7a. You do the grouping.** Read the enriched synthesis and group clusters into super clusters
by similarity. Assign each a tier reflecting where you intend to focus. Write your reasoning
however you like: a doc, a table, a page of bullets. Do this yourself. Everything up to here was
built so that this judgment rests on something.

**7b. Have it audited.** Prompt: `prompts\4-supercluster-rationale-review.md`, with the enriched
synthesis and your write-up as inputs. It converts your grouping into
`outputs\super-cluster-rationale.md` in the `@@` marker format (see
`templates\super-cluster-rationale.template.md`), reproducing your argument verbatim in
`@@RATIONALE` and putting its audit in a separate `@@REVIEW` field.

The audit verifies every number, names the claims your data cannot test, says what each
placement actually rests on, and flags the contestable ones. It never edits your rationale and
never recommends a tier change.

Read the review notes and revise your rationale where you agree. Re-run. Both fields are
published together in the final view, so a reader sees the argument and the audit side by side.

**7c. Build the view.**

```powershell
.\scripts\build-super-cluster-view.ps1 -Noun "teacher" -NounPlural "teachers" -CorpusSize 22
```

Writes `outputs\super-cluster-view.md`. Per super cluster it computes unique interviews
(deduplicated across member clusters), how many of those had the job unsolved or only partly
solved, and the raw row count so the deduplication is visible. Then it carries every member
cluster through **verbatim**, demoted one heading level. Nothing is summarized; the view is a
reorganization of the synthesis, not a digest of it.

Clusters in no super cluster are carried at the end rather than dropped.

The script aborts if the Job solved column is not where it expects, warns if a cluster is
assigned to two super clusters, and warns if a tier falls outside `1..MaxTier`.

---

## Known limitations

Read these before presenting results to anyone.

**Cluster membership is not reproducible.** Three runs of pass one over an identical corpus
produced 18, 17 and 19 clusters, with only 2 of roughly 9 orphans stable across all three.
Nothing in these prompts targets that. The clusters you get are one draw from a distribution.
Individual findings are stable; the boundaries drawn around them are not. Do not defend a
specific cluster boundary as though it were a finding, and if reproducibility matters for your
purposes, that is a larger problem than anything else here.

**Absence is never evidence.** The prompts enforce this and you should too. An interview where a
job never came up says nothing about that job. This is why no count in the output has a
denominator, and why "surfaced in 4 interviews" never becomes "4 of 22".

**Interview counts are not proportions.** The super cluster view says this in its preamble
because readers reliably do it anyway.

**Populations do not merge.** If you later interview a second population, tier them separately
and never add their counts together. Three of one and three of the other are not six.

**The corpus cannot speak for people who are not in it.** Whoever was hardest to recruit is
whoever your findings are weakest about, and it is usually the people who had already given up.
Where a rationale rests on such a group, the review note should say so as an inference.

## Optional additions

Two things the source project added that are not packaged here, worth knowing exist:

**A leftovers pass.** A separate synthesis over the Document B material that the jobs frame
discards, which surfaces recurring themes that are real but are not jobs. In the source project
its strongest output was a theme that two independent analysis frames had both discarded and
that still recurred in seven interviews.

**A pairing analysis.** With two populations, a pass that takes each belief held by one about
the other and tests it against the other's own corpus, classifying each as supported,
unsupported, or a blind spot. This produced the sharpest findings in the source project. It
needs both corpora run through this pipeline first.

## Obsidian

If you open this folder as a vault, keep filenames unique across it. Wikilinks resolve by
filename alone, so two notes with the same name make links ambiguous. Backups are written as
`.bak` for that reason.

## License

MIT. Use it, change it, ship it; keep the copyright line.
