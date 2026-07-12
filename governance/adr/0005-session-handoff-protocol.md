---
id: 0005
title: session-handoff-protocol
status: superseded
date: 2026-05-31
supersedes: []
superseded_by: ["0032"]
governs: []
---

<!-- AI read-contract: SUPERSEDED by ADR 0032 (four-project session model). This ADR is
     history only — never the basis for a current decision. Read 0032 for the current
     session-handoff protocol. -->

# 0005 — Session-handoff protocol

## Context
The work spans multiple sessions. Context lives in two places: **in-repo** (managed by the
repository's guardrails — CI, the governance scanner, the secret-gate, branch protection)
and a set of **Tier-P design documents** (baseline, plan, spine, register) deliberately kept
**out of the repository**. A stable rule is needed so the handoff does not **fragment** (files
drifting out of sync, partial updates) and does not **bloat per-session context** (multiple
overlapping handoff files re-read at every start).

## Decision
Adopt the **session-handoff protocol**:

1. **Tier-P stays unmanaged (uncommitted).** The four design documents —
   `HANDOFF-baseline-consolidated-design.md`, `IMPLEMENTATION-PLAN-skeleton.md`,
   `TRACEABILITY-SPINE.md`, `TEMPLATE-REQUIREMENTS-REGISTER.md` — remain outside the repo.
   Repo guardrails target governed *assets*; applying them to large, frequently-revised
   design docs is friction with no safety benefit.
2. **Single session entry point = `STATUS.md`** (in-repo, Tier-M). **No separate
   startup-message file.** The Layer-0 startup contract (AGENTS.md, P1.2) makes
   "read `AGENTS.md` + `STATUS.md` at task start" the entry. `STATUS.md` carries: current
   HEAD/phase, phase progress, next action (step granularity), open `[AUTH]`/`[WORKING]`
   items, the Tier-P inventory, the ADR index, and the static-point index.
3. **Static-point = clean boundary + whole bundle.** A static-point is declared only at a
   clean phase/step boundary (no half-done `[AUTH]` edit; Stage-1 gates green; in-repo
   committed). At each static-point the Tier-P substrate is delivered as **one bundle (zip)
   + a `MANIFEST`** (file list · purpose · last-updated · repo HEAD). **Never piecemeal;
   never assume the user already holds a current copy.**
4. **Precedence + non-duplication.** Facts are authoritative **in-repo** (`STATUS.md` / ADRs
   / committed code); the design *narrative* lives in Tier-P. Decisions graduate to **ADRs**
   (in-repo); `STATUS.md` references, does not restate (M7 R3). Rules live in ADRs, not in
   `STATUS.md` (which is bounded current-truth, R1).
5. **Resume sequence.** A fresh session: reads `STATUS.md` first → loads the Tier-P bundle
   into its working dir (reads on-demand, not in full at start) → re-clones and re-verifies
   the repo HEAD before acting (fact-grounding, never assume).

## Consequences
- The handoff cannot fragment: the rule itself is in-repo (this ADR), and Tier-P is always
  delivered whole with a version-stamped MANIFEST.
- Per-session context stays bounded — one entry doc (`STATUS.md`); this ADR and the Tier-P
  set are read on-demand only.
- Tier-P stays free of repo-guardrail burden (the reason it is unmanaged).
- Trade-off: Tier-P currency depends on discipline (always re-bundle at a static-point),
  since it is not version-controlled — mitigated by the MANIFEST stamp and the in-repo
  Tier-P inventory in `STATUS.md`.

## Alternatives considered
- **Commit Tier-P into the repo.** Eliminates the unmanaged category but imposes repo
  guardrails on large, churning design docs (friction, little safety benefit). Rejected for
  the guardrail concern; may be revisited later without breaking this protocol.
- **A separate next-session startup-message file.** Duplicates `STATUS.md` (current HEAD,
  phases, next action, open items) — fragmentation — and adds a file re-read every session.
  Rejected; folded into `STATUS.md`.
