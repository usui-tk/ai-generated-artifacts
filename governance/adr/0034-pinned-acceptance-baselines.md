---
id: 0034
title: pinned-acceptance-baselines
status: accepted
date: 2026-08-17
supersedes: []
superseded_by: null
governs: []
---

<!-- AI read-contract: authoritative for how a tool's acceptance baselines and its
     emitted-model shape are anchored and checked - why a baseline is measured against a
     pinned corpus blob rather than the head of a branch, and why an unchecked baseline is
     not allowed to exist. Read when touching acceptance figures or the model shape of
     quality-tools/powershell-symbol-surveyor/; not loaded every session. -->

# 0034 — Pinned acceptance baselines and a checked model shape

## Context

The PowerShell Symbol Surveyor's specification carries an appendix of
acceptance values: figures a conforming implementation must reproduce over the
reference target. The appendix declared those values as measured "at the head
of `main`".

Three separate failures were traced to that one sentence.

The head of `main` is not a fixed object. The reference target is a
maintenance-stream artefact under ADR 0029; it advances whenever its own
project advances. Over the 230 committed generations the corpus records, the
automatic-variable reference count alone moves between 182 and 2,097. A value
measured against "the head" therefore describes a state that no longer exists
by the time anyone re-reads it, and nothing marks the moment it stopped being
true.

One such value had already gone stale without being noticed. The appendix
recorded 2,004 automatic-variable references. Re-measurement showed the tool
producing 2,075 — and 2,075 is correct: an independent parse by the reference
parser reproduces it exactly, name by name, and reproduces the total variable
reference count as well. The recorded 2,004 could not be reproduced by any
committed revision of the tool against any of the 230 committed generations of
the target. It is an orphan: a number produced once by an instrument that was
never committed, then left in a document that nothing re-derives. This is the
same class of defect ADR 0033 addressed for the corpus itself, surviving one
layer up in the appendix that consumes it.

A second measurement went wrong the same way in the opposite direction. A
throwaway re-measurement produced 1,336 for the same quantity, differing from
the correct value by exactly the number of `$_` references. An uncommitted
instrument is not evidence, whichever answer it gives.

Meanwhile the appendix's own partition had a hole. It divides its figures into
values the tool must reproduce and values that merely characterise the corpus,
precisely because some are defined by a parser predicate the tool cannot reach.
The declaration-form table belonged to neither list. A counter that superficially
resembled one of its rows was therefore compared against a figure that was never
its definition, and the mismatch read as a tool defect rather than as a
classification gap.

Two extractor defects were found underneath that comparison, and they are the
reason the gap matters rather than a separate story. Three of the seven
assignment operators the extractor enumerates cannot be produced by its own
tokenizer, so compound subtraction assignments were recorded as reads; and a
variable used as a dynamic member name on an assignment's left-hand side was
recorded as a declaration, the exact corruption the specification warns against
for static member expressions. Both defects sit entirely inside function scope,
where no acceptance value was defined — which is why they survived every green
gate. An enumerated capability that is never exercised, and a figure that is
never re-derived, are the same failure: something written down that no machine
reads back.

## Decision

**1. An acceptance baseline is measured against a pinned blob, never against a
branch head.** The appendix names the corpus entry, the generation index, the
commit and the blob hash it was measured against. Retrieval is by blob, so the
basis is immutable and remains resolvable however the live path later moves,
is renamed, or is graduated out.

**2. Pinning is what makes the check runnable in the standing battery.** A
baseline check anchored to a branch head would turn ordinary maintenance-stream
work into a governance failure — the reason ADR 0033 kept `corpus.py check` out
of the battery. A check anchored to a pinned blob has no such coupling, so it
is admitted to the battery rather than excluded from it. The pin is not
bookkeeping; it is the precondition.

**3. Every figure in the appendix carries a classification, and the
acceptance-classified figures are machine-checked.** A figure defined by a
parser predicate the tool cannot reach is corpus characterisation and is
re-measured, never asserted. A figure the tool can reach is acceptance and is
asserted. No figure may be unclassified: an unclassified figure is compared
against by whoever reads it, with no rule saying whether the comparison is
meaningful.

**4. A baseline that no automation re-derives is not permitted to exist.**
Where a figure is recorded, a gate re-derives it from the pinned blob and
fails on divergence. Under this rule the orphan value could not have persisted:
it would have failed on the first run after it stopped being true.

**5. The shape of the emitted model is itself a checked baseline.** The set of
key paths the model emits is fingerprinted and recorded, for the default
materialisation and for the full-axis materialisation, so that a change of
shape is a gate failure rather than a silent event. The fingerprint is derived
from the pinned reference target rather than from a synthetic fixture, because
a fixture only fingerprints the fields it happens to reach.

**6. A shape change forces an adjudication, not a particular answer.** When the
fingerprint moves, the version decision — whether the model version advances or
is deliberately held — is made and recorded at that moment. This decision does
not itself set a version policy; it makes the absence of one detectable. The
model version had been held constant across four shape changes, ten of them
field removals, and nothing surfaced that fact until the shapes were compared
by hand.

## Consequences

A baseline is now falsifiable. It names what it was measured against, and a
machine re-derives it, so a stale figure becomes a red gate instead of a
sentence that reads plausibly.

The document's authority narrows honestly. Figures the tool cannot reach are
labelled as characterisation and are no longer available to be mistaken for
requirements, which removes the comparison that made a classification gap look
like a defect.

The maintenance stream is unaffected. The pinned blob does not move when the
live script does, so the two-speed separation ADR 0029 defines is preserved
while the governance stream gains a check it could not previously run.

Baselines age deliberately rather than silently. A pin is a decision to measure
against a specific past state; re-pinning to a newer generation is an explicit,
adjudicated act with re-measurement attached, which is the same discipline ADR
0033 applies to growing a corpus entry.

The cost is that the appendix now describes a state that is not necessarily the
current one. This is accepted: a value that is precisely attributed to a known
state is more useful than a value that claims currency it cannot demonstrate,
and the corpus retains every generation should a newer pin be wanted.
