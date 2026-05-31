---
id: 0007
title: canon-code-functional-quality-assurance
status: accepted
date: 2026-05-31
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for how the reference-code canon's own quality is
     assured (the functional/behavioral axis), for canon-vs-copy fault attribution, for
     the regression gate on folding consumer changes back into the canon, and for the
     phase that authors the canon test suite (P2a). Read on-demand. If reversing a point,
     supersede via a new ADR (one decision = one ADR). -->

# 0007 — Canonical code functional quality assurance

## Context
The reference-code canon (`reference-code/<family>/`) is the single source of truth that
consumers vendor; a functional defect in the canon propagates to every consumer — the
highest-leverage class of bug. The plan already assures two quality axes:

- **static / lint** — psa.py / PSScriptAnalyzer, applied to the canon and to copies;
- **consistency / drift** — the scanner: a vendored copy must match the canon at its
  recorded version.

Neither catches a *functional* defect in the canon itself: lint checks form; drift checks
that copies match the canon — and a canon bug matches into every copy. The third axis —
functional/behavioral correctness of the canon — was left implicit and optional (§4.9
"tests (optional)"; the P2.6 acceptance "Pester if tests present"). At P2, only 2 of the
39 PowerShell canonical units had any dedicated test (the canonical-JSON parity tests);
37 had none.

Separately, the upstream-first reconcile loop (a consumer's enhancement/bugfix detected
by the scanner and folded back into the canon, §2.7/§2.8) had no defined safety gate:
folding a change into the canon without a runnable regression suite is blind and breaks
the lifecycle.

## Decision
We make functional quality assurance of the canon a **first-class, mandatory** mechanism —
the third quality axis alongside static-lint and consistency-drift.

1. **Mandatory canon tests (full set).** Every canonical unit MUST have a behavioral test
   in the canon's own test home (`reference-code/<family>/tests/`). Where no test exists,
   we **author one explicitly** (not deferred as optional). The suite targets the canon
   module directly (it loads the canon, not a consumer), so it runs as a standalone
   regression suite.
2. **Two-axis fault attribution.** Canon correctness and copy consistency are independent,
   separately-observable signals: a **canon-test failure ⇒ a canon-level problem**; a
   **drift-gate failure with canon tests green ⇒ a copy-level problem**. Canon
   test/coverage state is a unit attribute recorded in the manifest (`tested`);
   per-instance drift stays in the observation record. The two are never
   conflated.
3. **Regression-gated reconcile-back.** When the scanner detects a consumer divergence
   proposed for upstreaming (DEP-3 `forwarded=pending`, §2.3) and that change is folded
   into the canon, the canon regression suite MUST run and pass **before** the change is
   accepted into the canon and re-vendored to consumers. The canon test suite is the
   safety mechanism that makes canon evolution non-breaking.
4. **New phase P2a (canon functional test suite).** Authoring the full canon test set is a
   distinct phase, inserted **immediately after P2** (the canon code home exists at P2.6)
   and **before P3**, with completion required **before any consumer vendors from the
   canon (P6/P7)**. The only dependency is the canon code home (P2.6); verifying the
   foundation before downstream machinery and before vendoring is the soundest sequencing.
5. **Vendoring precondition.** A consumer MUST NOT vendor a canon unit (P6/P7) unless that
   unit has a passing canon test. By P2a, all canon units do.

This is the concrete trigger to **revisit ADR 0006's "no contract-CI at P1"**: the
canon-test gate and the regression-on-reconcile gate are the CI worth building at P5/P6.

## Consequences
- The canon is verified for correctness, not just form and consistency; a canon bug is
  caught at the canon, before it propagates.
- Problems are localizable to canon vs copy, shortening diagnosis.
- The upstream-first reconcile loop is safe (regression-gated), so consumer improvements
  flow back without breaking other consumers.
- Cost: authoring the ~37 missing tests is real work, **isolated in P2a**; P2.6 stays
  "create + lint-clean", P2.7 records `tested`.
- The manifest schema gains a `tested` field (additive); P2.7 writes it; the
  observation/report layer can join canon-test state with drift for attribution.
  (The CNCF-aligned `maturity` axis, baseline §2.10, is a separate adoption/stability
  metadata deferred to template finalization, not this test-state flag.)
- A new phase (P2a) is introduced **without renumbering P3–P8** (the P0a precedent),
  preserving existing P-step anchors (P6.4, P6.6, P7, …).

## Alternatives considered
- **Keep canon tests optional / incremental backlog.** Rejected: leaves the
  highest-leverage asset unverified and the reconcile-back loop without a safety gate.
- **Author tests per-unit at vendoring time (P6/P7).** Rejected as the primary model: it
  couples test authoring to vendoring and risks vendoring untested units under deadline.
  P2a front-loads it as a clean, dependency-minimal phase; vendoring still gates on a
  passing test as a backstop.
- **Fold test authoring into P2.6.** Rejected: P2.6 (create homes) would balloon;
  separating "create" (P2.6) from "verify" (P2a) keeps each phase coherent.
