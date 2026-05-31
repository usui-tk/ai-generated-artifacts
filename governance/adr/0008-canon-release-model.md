---
id: 0008
title: canon-release-model
status: accepted
date: 2026-05-31
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the reference-code canon's release model — what a
     canonical unit's SemVer canonical_version means, the 0.x pre-release guardrail, the
     promotion-to-1.0.0 condition, and the machine-checkable vendoring gate. Refines ADR 0007.
     Read on-demand. If reversing a point, supersede via a new ADR (one decision = one ADR). -->

# 0008 — Canon release model (SemVer pre-release guardrail)

Refines **[ADR 0007](./0007-canon-code-functional-quality-assurance.md)** (canon functional QA).

## Status

Accepted.

## Context

ADR 0007 established the functional/behavioral quality axis for the reference-code
canon and made "the unit's canon test suite passes" the precondition for vendoring it
into a consumer. We still need a single signal — both machine-checkable and
human-readable — of each canonical unit's release/deployment readiness. The marker and
manifest already carry a SemVer `canonical_version`; this ADR gives that field
release-gate semantics rather than treating it as a free-form label.

## Decision

1. Each canonical unit carries a SemVer `canonical_version`.
2. **`< 1.0.0` (0.x.y) is pre-release.** A unit at a 0.x.y version is canon, but it MUST
   NOT be released or vendored into any consumer. The version itself is the guardrail.
3. A unit is **promoted to `1.0.0` only after its full-set behavioral test suite
   (ADR 0007 / phase P2a) passes.** `1.0.0` means released — eligible for vendoring.
4. **Vendoring (P6 / P7) precondition: `version >= 1.0.0`** — a mechanical gate that
   complements ADR 0007's "vendoring precondition = passing canon test" and the manifest
   `tested` fact. The version major is the human-facing release-readiness signal; the
   manifest `tested` flag is the backing evidence. (The manifest `maturity` axis is a
   *separate*, CNCF-aligned adoption/stability metadata, deferred to template
   finalization per baseline §2.10; it is not this release gate.)
5. Initial canon (P2.6) ships all units at **`0.1.0`** (canon present, not yet
   test-verified, not vendorable).
6. Post-`1.0.0` bumps follow standard SemVer: **major** = breaking helper-contract
   change, **minor** = backward-compatible addition, **patch** = behaviour-preserving
   fix. Bumps within `0.x` are unstable/iteration and carry no compatibility promise.

## Consequences

- Release readiness becomes a single, mechanical gate; a consumer (or an LLM agent)
  cannot vendor a unit that has not cleared its full test suite, because its version is
  still `0.x`.
- The marker `version=` token is SemVer, deliberately not an `rNN` revision token, so it
  does not trip the psa.py PSAP0005 guardrail (revision-anchored prose in comment bodies)
  and that guardrail can later be made default-on without conflicting with markers.
- The manifest `tested` flag and the SemVer major stay in lock-step
  (`tested=false` <-> `0.x`; full-suite pass <-> `>= 1.0.0`); divergence is a defect to
  surface, not a state to accept.
