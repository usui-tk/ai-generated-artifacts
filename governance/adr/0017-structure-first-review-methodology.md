---
id: 0017
title: structure-first-review-methodology
status: accepted
date: 2026-06-02
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §execution-framework"]
---

<!-- AI read-contract: authoritative for the REVIEW-ORDER methodology used when a new
     finding or design question appears - (い) verify structural validity inside the
     normative set FIRST, (あ) investigate the current state / 現物 SECOND, and on every
     new finding re-scan the governance md/ADRs, run a full forward/back impact analysis,
     and split now-decisions from items deferrable until implementation/現物 is visible.
     This is the epistemic-order complement to ADR 0004 (which governs how execution is
     gated). It is finalized AFTER P3 ran a full cycle (P3.0/P3.1/P3.6/P3.7), so its real
     benefits AND limits are evidenced, not assumed. Read on-demand. If reversing,
     supersede via a new ADR. -->

# 0017 — Structure-first review methodology (い→あ)

## Status

Accepted. Deliberately finalized **after P3 ran a full cycle** (P3.0 hash contract, P3.1
output-contract pins, P3.6 scanner build, P3.7 close) so the methodology is grounded in
worked evidence rather than asserted up front — itself an application of the methodology
(don't finalize a model against no real experience).

## Context

This is a **from-scratch governance model**: the canon, manifest, schemas, markers, gates,
and reconstruction procedures are all being designed and applied for the first time. The
single largest risk is **letting the current artifacts (現物) drive the model** — if a
from-scratch design over-depends on whatever code/markers/values happen to exist now, the
design inherits their accidents and the goal (a clean governance model) cannot be reached.

Two facts make a disciplined review order necessary:

1. **The model is defined across many Markdown files + ADRs** (baseline, plan, spine,
   register, SPEC, the ADR set). A finding in one place can contradict or under-specify
   another, and that is checkable **inside the normative set** without looking at any
   current artifact.
2. **Some defects only appear when the design meets the 現物** — an inlined value with no
   recorded rule, a schema field undifferentiated for a real case, a normalization profile
   that needs a real language idiom. These cannot be found by reading documents alone.

Neither "documents only" nor "現物 only" is sufficient; the **order** matters.

## Decision

Adopt a fixed review order for every new finding or design question:

1. **(い) Structural validity in the normative set, FIRST.** Before inspecting any current
   artifact, check the question against the normative documents alone: is the design
   internally consistent, complete, and unambiguous? This is where contradictions and
   under-specifications are found exhaustively, because the normative set is self-contained.
2. **(あ) Current-state / 現物 investigation, SECOND.** Only after the structure is settled
   do we inspect real artifacts/operations — to *fill* the design (pin values, validate
   applicability, exercise real failure modes), never to *decide* the design. The 現物 fills
   a correct structure; it does not get to define it.

On **every new finding**, run the loop:
- **re-scan** the governance md/ADRs (a finding can change another document's meaning, and
  re-reading can change the finding's own nature);
- run a **full forward/back impact analysis** across the current and later phases;
- **split now-decisions from later-deferrable** ones, and for each deferred item name
  **what** must be decided and **how** it will be investigated when the 現物 is visible.

**Structural correctness sits above the 現物.** When the two appear to conflict, the
normative design is authoritative and the artifact is suspect (e.g. a stale stamped value),
not the reverse.

## Consequences

- Contradictions/under-specifications are caught before code is written, when they are
  cheapest to fix.
- Deferred decisions are explicit and investigable, not silently resolved in code (an
  implicit contract). Each carries a recorded investigation method.
- Re-scanning on each finding prevents a single document from drifting out of sync with the
  rest of the model.
- The complement to ADR 0004: ADR 0004 governs **how execution is gated** (§Y/§Z, priority,
  safety); this ADR governs **the epistemic order of reviewing/deciding** within that
  framework. They are orthogonal and non-overlapping.

### Worked evidence (P3, the cycle this ADR was finalized after)
- **(い) found defects from documents alone:** P3.1 pinned three observation-schema fields
  (F1 `runtime.duckdb`, F3 `kind`→`granularity`, F4 `drift=unknown`) by a documents-only
  structural review — no scanner code, no consumer inspection. P3.0's re-scan *reclassified*
  a finding (the hash gap: contradiction → under-specification) and *corrected* another
  (`python-helper` is whole-tool, not region) — re-scanning changed the findings' nature.
- **(あ) was genuinely necessary — items (い) could not close:** at design time, three P6
  items (region_locator final form, `drift=unknown` precise conditions, the `bash`
  normalization profile); at registration time, the whole-tool sentinel-value convention
  (the manifest schema is undifferentiated for `kind=tool`). Each was deferred with a named
  investigation method, not guessed.

This dual evidence — (い) closing most of the structure, (あ) being unavoidable for a named
remainder — is exactly why the **order** (not one or the other) is the decision.

## Alternatives considered

- **現物-first (inspect artifacts, then design):** rejected — it is the project's main risk
  made into a method; the design would inherit the artifacts' accidents (the P3.0 20-marker
  mis-stamp is a concrete example of a 現物 that, if trusted, would have corrupted the
  contract).
- **Documents-only (never investigate 現物):** rejected — it cannot find applicability
  defects (the whole-tool field gap, the bash profile) and would force speculative pins
  against no real input.
- **Finalize the methodology up front (before P3):** rejected by the user at the time — a
  methodology asserted without a full cycle of evidence risks pinning the wrong rule; this
  ADR was held until P3 surfaced both its strengths and its limits.
- **Leave it as baseline prose (no ADR):** rejected now — after a full cycle the methodology
  is load-bearing for every future phase's review and deserves a durable, supersede-tracked
  decision rather than living only as design-substrate narrative.
