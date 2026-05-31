---
id: 0004
title: outcome-based-execution-framework
status: accepted
date: 2026-05-31
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §execution-framework"]
---

<!-- AI read-contract: authoritative for the execution framework, priority taxonomy,
     and safety carve-out (M8). -->

# 0004 — Outcome-based execution framework (M8)

## Context
The plan must execute as gated, reversible, value-anchored phases rather than an
open-ended edit stream, with a consistent way to prioritize work and a non-negotiable
safety floor.

## Decision
Adopt the **outcome-based execution framework (M8)**: each phase is value-anchored
(baseline §5.0), filled with a per-step schema, dry-run self-checked (§Y), and
human-signed-off (§Z) before execution — nothing executes before its sign-off. Work is
prioritized by a **priority taxonomy** (must-fix > should > nice-to-fix), and a
**safety carve-out** governs deletes (§9.3 grep + checkpoint), Layer-0/cross-repo edits
([AUTH]), and gate deviations (§8.3 — never self-accepted).

## Consequences
- Predictable, reversible progress with explicit human gates.
- Quality deviations are surfaced and dispositioned by the user, not absorbed silently.
- Per-phase dry-run + sign-off becomes the repeatable operating loop (Path 2).

## Alternatives considered
- Mechanism-first (build all tooling, then apply): risks analysis paralysis and
  unanchored work.
- Outcome-only (skip dry-runs): loses the reversibility/quality guarantees.
