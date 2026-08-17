---
id: 0036
title: figures-carry-executable-derivations
status: accepted
date: 2026-08-18
supersedes: []
superseded_by: null
governs: []
---

<!-- AI read-contract: authoritative for what an asserted figure must carry before it may
     exist in a specification — an executable derivation, a pinned input, and a stated
     materialisation. Read when adding, correcting or auditing a numeric figure in
     quality-tools/powershell-symbol-surveyor/; not loaded every session. -->

# 0036 — A figure is a query, an input and a materialisation, or it is not a figure

## Context

Three arcs in a row corrected a number that no one could reproduce.

ADR 0034 found `PSS2005` recorded as 2,004 and measuring 2,075, traced it to an
uncommitted instrument, and fixed the half of the problem it could see: an
acceptance figure is measured against a pinned corpus blob, never against a
branch head. ADR 0035 found the same defect one level up — the recorded "ten
field removals" measures eleven at the pin and thirteen at an early generation —
and extended the basis rule from acceptance figures to figures about the model.

Both rules reached the **input**. Neither reached the **question**.

Appendix B.3's `[DERIVATION OWED]` figures were left unasserted by ADR 0034
rather than restamped with a guess, which was correct and which also left them
unexplained. Grounding measured why. Every one of the six committed revisions of
`pss.py`, run against the pinned blob, returns identical values for all of them:
198 distinct script-qualified names, 1,865 script-qualified references, 156
usage maps, 123 signatures, 84 interpolated-reference source lines. **The tool
never moved these numbers.** What moved was the question asked of it.

`$script:`-qualified (`PSS2004`) 1,381 is the clearest case. Under that label
three different queries are equally defensible — 1,865 script-qualified
reference records, 1,812 `PSS2004` records, or 1,381 of them occurring inside a
function — and they differ by hundreds. The recorded figure is the third. It was
recoverable only by trying the readings until one matched, which is not a method
a specification should require.

Two further facts settled the shape of this decision:

- The recorded figures do not describe one artefact. 115 signatures and 83
  interpolation lines are reproduced at generations 104-110 and 88-111 of corpus
  entry `0002`; 1,381 and 156 at generations 132-156. No generation reproduces
  them jointly. The appendix looked like a snapshot and was an accumulation.
- 155, 197 and 555 are reproduced by no generation and no revision. 197 is
  recorded in the document as the *measured* correction, so the corrected value
  was itself an orphan.
- One figure is not axis-invariant. "References outside any function" measures
  485 under the default materialisation and 556 with `local-sites`, because that
  axis retains local reference sites. A count that moves with the materialisation
  is unfalsifiable unless the materialisation is part of its basis — the same
  argument ADR 0034 made about the input, applied to the projection.

## Decision

1. **An asserted figure carries an executable derivation.** The derivation lives
   in the gate that re-derives it (`test_pss.py`), not in the label. A figure a
   reader can only reconstruct by guessing which query was meant is not
   permitted to exist; it is withdrawn or given a derivation.

2. **A figure's basis has three parts**: the derivation, the pinned input, and
   the materialisation it was measured under. ADR 0034 supplied the second and
   ADR 0035 extended it; this decision adds the first and the third. A figure
   that is axis-invariant may state so by omission; a figure that is not states
   its value per materialisation, as `model_shape` already does.

3. **A label may not be shared by two queries.** Where a recorded label covers
   two defensible questions, both are kept as separate figures under separate
   names rather than one being chosen. `script_qualified_refs_at_script_level`
   (484, axis-invariant) and `references_outside_functions` (485 / 556) are the
   worked example: they answer different questions and the recorded 555 answers
   neither.

4. **An unreproducible figure is withdrawn, not restamped**, following ADR
   0034's treatment of 2,004. A figure reproduced at an identifiable earlier
   generation is re-stamped to the pinned basis **with that generation recorded**,
   because the generation is the evidence that the old value was a measurement
   rather than an invention.

5. **The acceptance block may gain rows without the model changing**, and the
   `baseline_digest` therefore moves without invalidating a derived cache.
   Invalidation remains what §5.5 says it is: a change to what the model emits.
   The digest answers "which build"; `model_version` answers "is this
   comparable". SPEC §14.4 records the distinction.

## Consequences

Appendix B.3 no longer carries an owed block. Four figures are re-derived
exactly, two are re-stamped with the generation that reproduces the old value,
and three are withdrawn as orphans. SPEC §13.2's "Derivation owed" row closes.

The gate grows the derivations rather than the document growing prose about
them, so the next session cannot re-invent a query: there is one implementation
and the document is checked against it by value.

`pss.py` is untouched, `MODEL_VERSION` stays `"1"`, and the derived caches on
hand remain sound as data. Their `baseline_digest` no longer equals this build's,
by decision 5, and that is a statement about which build produced them.

The rule generalises beyond this tool, and is deliberately **not** promoted to
`governance/SPEC.md` here: the evidence is one tool's appendix, and the
rule-of-two convention that governs promotion in this repository is not yet met.
A second instance should trigger that promotion rather than a third correction.
