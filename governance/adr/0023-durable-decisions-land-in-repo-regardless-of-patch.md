---
id: 0023
title: durable-decisions-land-in-repo-regardless-of-patch
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: []
---

<!-- AI read-contract: authoritative for the process rule that any durable decision -
     one that binds future sessions - MUST land in-repo as an ADR (plus a SPEC
     current-truth back-reference where it governs a SPEC section), even when the session
     that produced it ships no repository patch. Do not treat Tier-P handoff files as a
     durable decision store. Do not re-decide; supersede via a new ADR if reversing. -->

# 0023 — Durable decisions land in-repo, regardless of whether the session ships a patch

## Context

The session-handoff protocol (ADR 0005) keeps design/discussion artifacts out of the
repository (Tier P) and commits only scrubbed execution status (Tier M: `STATUS.md`) plus
decisions (`governance/adr/`). The working assumption was that durable decisions reach
`governance/adr/` naturally, because decisions are normally made inside a per-phase loop
that ends in a patch.

A 2026-06-11 session broke that assumption: it was a **clarification / plan-review session
with no repo patch**, yet it produced three durable outcomes - a **proven governance hole**
(the spec-region version-coupling gap, now recorded and closed by ADR 0022), a **redesign
of the pending remediation into a gate-then-write sequence**, and the **adoption of a
two-speed operating model**. All three were recorded **only in the out-of-repo Tier-P
handoff bundle**. Consequently the in-repo `STATUS.md` carried the pre-redesign plan for
roughly three weeks, later sessions ran maintenance streams against a stale in-repo "next
action", and the existence of a proven, open gate hole was invisible to anyone (human or
AI) grounding from the repository alone. The knowledge-persistence risk that ADR 0005
accepts for *in-flux discussion* had silently extended to *settled decisions*.

## Decision

1. **A durable decision MUST land in-repo as an ADR** (with a `governance/SPEC.md`
   current-truth back-reference when it governs a SPEC section, per the ADR<->SPEC model),
   **in the same session** that settles it - or, when that session cannot produce even a
   docs-only patch, **as the opening step of the next patch-producing session**.
   "Durable" means: it would bind or reverse a future session's behavior - design
   supersessions of `[DECIDED]` items, proven gate/coverage findings, operating-model
   adoptions, boundary or scope amendments. Ephemeral working notes, open questions, and
   in-flux design remain Tier-P (ADR 0005 unchanged).
2. **A no-patch session that settles a durable decision therefore stops being a no-patch
   session**: it ships a minimal docs-only ADR patch through the normal per-phase loop
   (author -> dry-run -> sign-off -> format-patch -> user pushes). The patch may be small;
   the record must not wait.
3. **`STATUS.md` must reflect the decision in the same patch** (next-action / plan pointers
   updated), so Tier-M never advertises a superseded plan while the superseding decision
   exists only out-of-repo.

## Consequences

- Grounding from the repository alone (re-clone + `STATUS.md` + ADRs) is again sufficient
  to learn every settled decision; the Tier-P bundle returns to its intended role of
  reference and in-flux discussion, never the sole home of anything durable.
- Sessions gain a small overhead (a docs-only ADR patch) in exchange for eliminating the
  class of drift where in-repo status and out-of-repo truth diverge for weeks.
- This ADR itself, together with ADR 0022, retroactively lands the 2026-06-11 outcomes
  that motivated it. The two-speed operating model's full in-repo formalization remains a
  separately tracked item (the gate-coverage / operating-model inventory arc); its
  *adoption* is recorded here as the motivating instance.

## Considered options

- **Keep durable decisions in the Tier-P bundle only (status quo).** Rejected: proven to
  fail (three weeks of divergence; a proven security-relevant gate hole invisible in-repo).
- **Commit the whole Tier-P bundle.** Rejected: ADR 0005's rationale stands - Tier-P
  contains unscrubbed, in-flux material that cannot be mechanically secret-gated.
- **Docs-only ADR patch for durable decisions (chosen).** Minimal, uses existing
  machinery (ADR template, C6 integrity gate, per-phase loop), and restores the property
  that the repository is self-sufficient for grounding.
