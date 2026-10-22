# Project configuration

Fill this in first. Most of the placeholders below appear in one or more prompt files under
`prompts\`. When you have filled them in, do a find-and-replace across all four prompt files,
then delete nothing else: the rest of the prompts are subject-neutral and should be left
exactly as they are.

Two of them, `{{INTERVIEWEE_PLURAL}}` and `{{CORPUS_SIZE}}`, appear in no prompt. They are
passed to `build-super-cluster-view.ps1` on the command line at the last step. They are listed
here so that everything subject-specific lives in one file. Each is marked below.

Work top to bottom. The whole thing takes about twenty minutes and it is the only
subject-specific work in the pipeline.

---

## The placeholders

### `{{PROJECT_CONTEXT}}`

One paragraph. Who commissioned the research, who is being interviewed, and the single
question the project is trying to answer. This is the only place the prompt learns what the
project is about, so be concrete and do not hedge.

Reference version, from the project this kit was extracted from:

> a customer discovery project at a graduate business school's career center. The project's
> question: what is most needed to improve the value of the career center to students?

**Yours:**

```
TODO
```

---

### `{{INTERVIEWEE_NOUN}}` and `{{INTERVIEWEE_PLURAL}}`

The singular and plural noun for the people interviewed. Reference: `student` / `students`.

`{{INTERVIEWEE_NOUN}}` is a prompt placeholder: find-and-replace it. `{{INTERVIEWEE_PLURAL}}`
is not in any prompt; it is passed to the build script at the last step as
`-Noun "<singular>" -NounPlural "<plural>"`.

**Yours:**

```
singular: TODO
plural:   TODO
```

---

### `{{SNAPSHOT_FIELDS}}`

The three to five attributes that meaningfully segment your interviewees, listed as a comma
separated phrase. These populate the one-line description that appears beside every interview
in every cluster table, so pick the attributes you would actually want to see a pattern break
along.

Reference: `program, year, target industry or industries, placed or still searching at time
of interview`.

Choose attributes you can read off every transcript. An attribute present in half the
interviews produces a ragged table and a false sense of a pattern.

**Yours:**

```
TODO
```

---

### `{{PROVIDER_LIST}}`

The candidate things an interviewee might "hire" to get a job done, as a slash separated
list. This is the single most important placeholder to get right, because it determines
what the analysis can see. Write it after skimming three transcripts, not before.

Reference: `career coach / second-year students / student club / alumni / AI tool / self-built workaround /
nothing worked`.

Two rules. Include `self-built workaround` and `nothing worked`, always: they are the two
most informative outcomes and an analyst will not invent them if they are not listed. And
name providers specifically enough that two of them are never the same thing wearing
different words.

**Yours:**

```
TODO
```

---

### `{{FOCAL_PROVIDER}}`

The organization or service whose performance the study is assessing, as it should appear in
a column header. Reference: `Career center`.

Every cluster table carries `{{FOCAL_PROVIDER}} hired` and `{{FOCAL_PROVIDER}} solved`
columns, which is what makes it possible to ask "where were we hired and did we deliver"
independently of "did the person get what they needed".

**If your study has no focal provider** and is simply mapping needs in a space, say so here.
You will then delete those two columns from prompt 2 and set `-JobSolvedColumn 5` when you
run `build-super-cluster-view.ps1`. Everything else is unaffected.

**Yours:**

```
TODO
```

---

### `{{KILL_QUESTION}}`

The one question in your interview guide designed to let someone disagree with your premise,
quoted as you actually asked it. Prompt 1 pulls the verbatim answer into Document B, and pass
two uses those answers as the counter-evidence corpus.

Reference: `whether a coach's lack of knowledge about the student was ever a problem`.

**If you did not ask a consistent disconfirming question,** write `none asked` here. Pass two
will still run, drawing on whatever else in B3 contradicts a cluster, but it will find less,
and you should treat a thin disconfirmations pass as a limitation of the interview guide
rather than evidence that nobody disagreed.

**Yours:**

```
TODO
```

---

### `{{PREMISE}}`

The belief your project would be embarrassed to have wrong, stated in one sentence. Prompt 1
asks each analyst what in the transcript cuts against it.

Reference: `that students need more or better information delivered to coaches or to
themselves`.

**Yours:**

```
TODO
```

---

### `{{TRACK_DIMENSION}}`

The one axis along which a job might legitimately apply to only part of your population, so
clusters can be labelled as confined to it or spanning it. Reference: `recruiting track (e.g.,
only tech recruiting, only non-traditional paths)`.

If nothing like this applies, write `none` and delete the "Track labels" bullet from prompt 2.

**Yours:**

```
TODO
```

---

### `{{CORPUS_SIZE}}`

Not a prompt placeholder. Passed to the build script at the last step as `-CorpusSize <n>`.

The number of interviews. Used only in the super cluster view's preamble, which states the
population size once so that no reader mistakes a count of people for a proportion.

**Yours:**

```
TODO
```

---

## Things not to change

**The interview ID scheme.** Files must be named so that the ID comes first and is followed
by an underscore: `S07_JaneD_<whatever else you want>.md`. Findings are then `S07-J1`,
`S07-J2`, and so on. Every script in `scripts\` matches on the literal pattern `S<digits>-J<digits>`.
The scheme carries no meaning beyond being parseable, so there is no reason to change it, and
changing it means editing regexes in five files.

**The interviewer name in the filename.** Pass one reports when a cluster's support leans on
one interviewer's batch, which is a real and common artifact when interviewers split a corpus
by segment. It can only do that if the name is in the filename. With a single interviewer the
prompt says so once and skips the check.

**The `=====DOCUMENT-BREAK=====` delimiter.** `split-raw-documents.ps1` matches it exactly.

**The four fixed values of "How well the job is served today":** served well, served unevenly,
served only by self-built workarounds, not served. Closed vocabularies are what make the field
countable. The same goes for the three values of "Job solved".
