---
id: 0006
title: agent-config-coverage-and-contract-ci-scope
status: accepted
date: 2026-05-31
supersedes: []
superseded_by: null
governs: []
---

<!-- AI read-contract: authoritative for which AI-agent config files this repository
     maintains, and for the scope of the governance-contract CI at P1 (specifically:
     not implemented at P1). Read on-demand; not loaded every session. If reversing a
     point here, supersede via a new ADR (one decision = one ADR). -->

# 0006 — AI-agent config coverage & contract-CI scope

## Context
P1 realizes Topic C — governance must auto-load at task start rather than depend on an
agent *happening* to read it. The loading mechanism is a thin root `CLAUDE.md` that
`@import`s `AGENTS.md` (the single source), whose Session Start Contract directs the
reader to `governance/project-management/STATUS.md`. Two questions remained open at P1:

1. Which *other* AI agents need a dedicated config / steering file.
2. Whether to add a CI gate that *enforces* the governance-loading contract (the
   "contract-only CI" originally planned for P1.5). P1.1 recorded that `CLAUDE.md` is
   advisory (loaded, not enforced); that CI was its intended enforcement.

## Decision
1. **Single AI-agent governance source.** We maintain **`AGENTS.md`** as the one source,
   bridged for Claude Code by the thin root `CLAUDE.md` (`@AGENTS.md`). We do **not**
   create per-agent config / steering files (no `GEMINI.md`, no Kiro steering files, no
   Codex- or Antigravity-specific files). Other agents are expected to consume
   `AGENTS.md` through their native repository-context mechanisms; a bespoke per-agent
   file is added **only on demand**, if and when a concrete need is confirmed at the time
   that agent is adopted. (Per-agent native behaviour is not independently verified here;
   it is re-confirmed on adoption.)
2. **No governance-contract CI gate at P1.** The invariants such a gate would guard
   (presence/integrity of the `CLAUDE.md` `@import`, the `AGENTS.md` Session Start
   Contract, and `STATUS.md`) reduce to trivial presence / substring checks and are
   **not a precondition for any later phase** — the P6/P7 per-PR drift gates and the P8
   cold loop are separate machinery that do not consume this gate. At the current scale
   (single maintainer, AI-assisted), the cost/benefit of a dedicated CI gate for these
   invariants is low. The governance-loading wiring therefore remains **advisory, not
   CI-enforced**.

This is a conscious, surfaced amendment (baseline §10 M2) to the P1 design narrative:
the Tier-P baseline §5.0 P1 exit previously listed "CI = contract-only", and the plan
listed it at P1.5/P1.6. That exit criterion is **removed** from P1; the Tier-P baseline
and plan are updated to reference this ADR.

## Consequences
- P1's value (governance auto-loads) is delivered by the wiring
  (`CLAUDE.md` / `AGENTS.md` / `STATUS.md`); it is **not** machine-enforced against
  regression. A future edit or refactor could silently break the wiring (e.g. drop the
  `@import`, move `STATUS.md`) without any CI failure.
- This regression risk **rises when the file-moving phases begin (P5/P6 `git mv`
  migrations)**. Revisit this ADR then: if the risk materialises, add the contract check
  at that point (as a CI step or a `quality-tools/` tool), recorded as a new ADR that
  supersedes this scoping.
- Fewer files to maintain; no per-agent config drift; the single-source `AGENTS.md`
  principle is preserved.
- The M5 register row for a P1 "CI-contract" enforcement (TR-DOT-4) is amended at P1.6 to
  reflect that P1 contributes no contract-CI; the P6/P7 per-PR drift gate is unaffected.

## Alternatives considered
- **Implement the contract-CI now (as originally planned).** A cheap regression guard
  that would complete Topic C's "enforced" half. Not chosen now on cost/benefit at the
  current scale; deferred for reconsideration at P5/P6 when file moves raise the risk.
- **Per-agent config files (`GEMINI.md`, Kiro steering, etc.).** Rejected: multiplies
  sources, invites drift, and contradicts the single-source `AGENTS.md` principle; added
  only on demand.
