---
id: 0033
title: pss-test-corpus-governance
status: accepted
date: 2026-08-16
supersedes: []
superseded_by: null
governs: []
---

<!-- AI read-contract: authoritative for how the PowerShell Symbol Surveyor's test
     corpus is defined, identified and maintained - what a corpus entry is, why an entry
     never follows a rename, why an entry is append-only, and the filename-identity rule.
     Also the decision record for the first data subdirectory under quality-tools/. Read
     when touching quality-tools/powershell-symbol-surveyor/; not loaded every session. -->

# 0033 — PSS test-corpus governance (pinned generations, append-only entries)

## Context

The surveyor's requirements are derived from measured damage rather than from
consultation. The reason is structural: a failure nobody noticed cannot be
reported by the people who missed it, so asking "what do you need" returns the
complement of the failure set. Deriving requirements from damage instead needs
real material to measure.

The repository's own git history is that material. The owner controls it; a
committed generation never changes; and it stays reachable even if a project
directory is renamed, made private, or re-published, because history travels
with the repository rather than with a path.

The instruments that produced the first such derivation existed only as
throwaway scripts outside the repository. Three of them walked the same history
in three near-identical ways, two carried a hard-coded absolute path from the
session that wrote them, and one dropped unreadable generations in silence —
the exact defect that had already cost 74 of 230 generations once, undetected.
Un-committed instruments and un-governed sample selection are the same problem
wearing two hats: work that the quality machinery cannot see.

Two prior traps bound the design. `git log --follow` does not compose with
`--reverse`, and `git show <rev>:<current path>` fails for every generation
recorded before a move. Both are consequences of one choice — trying to track a
file across renames — and both had already been paid for.

## Decision

### 1. A corpus entry pins one script at one path

An entry names exactly one `.ps1` file by a repository-relative path, and covers
a contiguous run of generations at that path. Directories, globs and absolute
paths are refused: the boundary is enforced by refusal, as elsewhere in this
repository, not by convention.

### 2. An entry never follows a rename

Rename detection is a heuristic, not a recorded fact. An entry is bound to a
literal path, so every generation it records is one where the blob provably
exists there. When a script moves, the old entry seals and a new entry is
registered for the new path.

This removes both prior traps by construction rather than by defensive coding:
`--follow` is not used, and per-generation path resolution is unnecessary
because the path does not vary. The commit that deletes a path is not a
generation — it carries no blob — and is reported at registration rather than
dropped.

No coverage is lost. The one script that has moved yields 73 + 157 generations
across two entries: the same total `--follow` reports, split at the move.

### 3. An entry is append-only

Re-deriving an entry refuses unless the stored generation list is a strict
prefix of what git reports now. Growth is additive and disturbs no earlier
measurement. A rewritten or truncated history is refused rather than absorbed;
the remedy is a new entry, never an edited one.

Only the trailing extent of an entry may advance. The path, the starting
revision and the identity are fixed for its life.

### 4. Identity is the leading four-digit number in the filename

Everything between the number and the `.json` suffix is descriptive and is never
read back. Renaming an entry file therefore cannot break a reference and cannot
go stale — descriptive text that carries no authority has nothing to drift from.
This is the same move as rule 2, applied to the entry file rather than to the
script: fix the identifier, do not track the name.

Three consequences are enforced rather than assumed. A fifth consecutive digit
is refused, not misread as a shorter number. A duplicate number is refused, not
silently resolved to one of the candidates. Non-conforming files are ignored but
reported, never dropped in silence.

### 5. Entries are tool-written and byte-stable

Entries are written only through `corpus.py`, as the manifest is written only
through `canon-manifest-tool` (ADR 0011), and record the writer in
`generated_by`. The file format follows the in-repo precedent of
`ena-driver-releases.json`: a metadata header followed by one record per line,
so adding a generation is a one-line diff.

A written entry contains no timestamp, environment stamp, or other run-dependent
value. This is load-bearing, not hygiene: detection of growth and of history
rewrite is regeneration plus comparison, and a file that differs on every
regeneration cannot support it.

Each record carries the blob hash alongside the commit hash. The two fail
differently — a rewritten history always changes commit hashes, while a blob
hash changes only if content did — so holding both distinguishes a rewritten
history from an altered one.

Values that can be computed are not stored. Whether an entry is sealed is
derived from whether its path exists at `HEAD`; the header fields that restate
the record range are verified on load rather than trusted.

### 6. Detection reports; re-pinning is adjudicated

`check` reports growth and rewrite as findings and applies nothing. Re-pinning
is a deliberate command whose result travels the ordinary patch flow. This is
the machine-proposes / human-decides split of ADR 0011 and ADR 0027, applied to
sample selection.

`check` is deliberately **not** in the standing gate battery. The scripts it
watches are maintenance-stream property advancing at maintenance speed; wiring
it into the governance battery would convert ordinary project work into a
governance-stream red, contradicting ADR 0029.

### 7. Corpus data lives in a subdirectory of the tool

Entries live in `quality-tools/powershell-symbol-surveyor/corpus/`. This is the
first subdirectory under a `quality-tools/` tool, which until now have been
uniformly flat.

The precedent is opened narrowly and for a stated reason: entry files accumulate
without bound as samples are added, and an unbounded data set at the same level
as the tool's own files would bury them. It licenses a data subdirectory beside
a tool, not a general nesting allowance; tool code stays flat, and analysis
output is not written to disk at all.

## Consequences

Sample selection becomes reviewable. Which generations were measured is a
committed, regenerable fact rather than a property of whichever session ran the
instrument.

An entry is reproducible for as long as its history is reachable, and stops
being silently wrong when it is not: a pin that no longer resolves raises rather
than skips.

Cross-stream coupling is neutralised. A corpus entry depends on pinned history,
which is immutable, so the maintenance stream may change the scripts it names
without breaking anything the governance stream owns.

The cost is duplication of git-derived data in the repository. It is accepted
because the copy is tool-generated, regenerable, and machine-comparable against
its source — the distinction ADR 0031 draws between a derived view and a
hand-maintained list.

Registration is deferred. Neither `pss.py` nor `corpus.py` is a manifest unit
yet; `pss.py` registers when its specification has no provisional items left,
and `corpus.py` registers with it. Registering a helper before the tool it
serves would invert the order.
