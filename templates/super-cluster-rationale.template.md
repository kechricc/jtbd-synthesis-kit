This file is the input to build-super-cluster-view.ps1. Everything above the first
@@JTBD line is ignored, so these notes can stay here.

Format rules:

  @@JTBD      the analyst's own identifier for the super cluster. Any string. "#6a" is fine.
  @@TIER      a single integer. Must be within 1..MaxTier or the block is skipped with a warning.
  @@TITLE     the job as the analyst named it, one line.
  @@CLUSTERS  comma separated cluster numbers from the synthesis. May be empty.
  @@RATIONALE free markdown, usually bullets. The analyst's argument, in their voice.
  @@REVIEW    free markdown. The audit of that argument against the data.
  @@END       closes the block. Optional but clearer.

A cluster number may appear in at most one @@CLUSTERS line. The build script warns if one
appears in two, because that double counts its interviews.

An empty @@CLUSTERS line is legitimate: it means the analyst named a job that the clustering
never produced. The view will carry it with no counts and the review note should say where its
evidence actually lives.

Delete everything from here up, or leave it. Then replace the example below.

@@JTBD #1
@@TIER 1
@@TITLE The job as the analyst named it, in their words
@@CLUSTERS 1,2,25
@@RATIONALE
- The analyst's first argument for this placement.
- Their second. Reproduced faithfully, not corrected.
- Where they cited a number, it stays as they wrote it.
@@REVIEW
- Whether each number checks out, with the recomputed figure where it does not.
- Which claims the tables cannot test, stated plainly.
- What the placement actually rests on: prevalence, outcome, severity, or tractability.
- Anything contestable, with the reading the placement depends on.
@@END

@@JTBD #2
@@TIER 3
@@TITLE A second job, placed lower
@@CLUSTERS 11
@@RATIONALE
- Why the analyst put this in Tier 3.
@@REVIEW
- Confirmed.
@@END
