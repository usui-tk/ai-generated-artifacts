---
id: 0032
title: four-project-session-model
status: accepted
date: 2026-07-12
supersedes: ["0005"]
superseded_by: null
governs: []
---

<!-- AI read-contract: authoritative for how work hands off between sessions under the
     four-project Claude Projects model - the session entry points, the thin-slot rules
     (NO verification values), the investigation routing, and the amended static-point
     bundle rule. Supersedes ADR 0005; the surviving 0005 principles are RESTATED here as
     current truth, so this ADR is the one document to read (never replay 0005 for a
     current decision). Read on-demand; not loaded every session. -->

# 0032 — Four-project session model (thin slots, no verification values)

## Context

ADR 0005 established the session-handoff protocol: Tier-P design documents unmanaged
(out of repo), `STATUS.md` as the single in-repo session entry point, and whole-bundle
static-point delivery. Its implementation grew into a centralized STARTUP bundle
(`SESSION-STARTUP.md` entry + `STARTUP-CORE.md` shared mechanics + per-stream
`STARTUP-<stream>.md` slots, restructured 2026-07-03), and that implementation was
diagnosed as structurally flawed in operation:

- **Slots drifted into stale logs.** Snapshot files accumulated per-session narrative
  instead of holding only unresolved items, so they grew unbounded and went stale.
- **Manually maintained verification values went wrong.** Slots carried HEAD hashes,
  tree hashes, and gate-count expectations as text; these drifted from the repository's
  reality and created *false confidence* — the exact failure mode the in-repo governance
  gates exist to prevent, reproduced in an ungated medium.
- **Context-budget overrun.** The bundle's aggregate size exceeded what a session can
  afford to load at start, defeating ADR 0005's bounded-context goal.
- **No machine-enforceable gates.** Out-of-repo files sit outside the battery; no gate
  can catch their drift (the same reasoning as ADR 0023, which moved durable decisions
  in-repo for the same cause).

The remediation returns to ADR 0005's original intent — the in-repo entry is
`STATUS.md`, alone — and splits session context by stream, matching the two-speed
operating model (ADR 0029) and the maintenance-stream ownership boundaries.

## Decision

1. **Session entry = four stream-scoped Claude Projects.** Sessions run inside one of
   four Claude Projects: **AI governance** (this repository's governance stream),
   **PowerShell scripts** (iso, dsd, and the satellite Deploy-Drivers maintenance
   streams), **Bash scripts** (rhel, olaws maintenance streams), and
   **Investigation / reverse engineering** (open-ended research; minimal protocol).
   Each project's *instructions* carry that stream's session contract (startup /
   operating / session-end); its *knowledge* carries thin slot file(s) for its
   stream(s). The living inventory of these files is kept in `STATUS.md`
   §Design substrate (reference-don't-restate, M7 R3) — deliberately NOT enumerated in
   this immutable ADR (the lesson of ADR 0005 §1's baked-in file list).

2. **Thin-slot rules (the load-bearing change).**
   - **No verification values in slots — ever.** HEAD/tree hashes, gate counts, and
     gate expectations are derived fresh from a clone at every session start. The
     authoritative expectations live in-repo: `STATUS.md` and
     `governance/gate-coverage.md`. A slot stating a verification value is a defect.
   - **Slots are snapshots, not logs.** Content is limited to unresolved items, next
     actions, and handoff notes; resolved material is pruned, not appended to
     (the ADR 0005-era bundle's failure mode, and STATUS R1 applied to slots).
   - **Knowledge replacement is a user operation.** The AI presents updated slot files
     at session end and explicitly reminds the user that swapping project knowledge is
     theirs to perform; it never assumes the swap happened.

3. **`STATUS.md` remains the single in-repo entry point** (ADR 0005 §2 preserved).
   Slots are stream-local pointers into it, never a second source of truth; facts stay
   authoritative in-repo (`STATUS.md` / ADRs / committed code — ADR 0005 §4 precedence
   and ADR 0023 unchanged).

4. **Investigation routing (three-way).** Where investigation work runs is decided by
   coupling, keeping protocol overhead proportional:
   - **New / standalone** investigation → the Investigation/RE project directly.
   - **Existing-project-linked but loosely coupled** → an **investigation brief** is
     written in the owning project and carried to the Investigation/RE project as the
     context bridge; results return the same way.
   - **Tightly implementation-coupled** → stays in the owning project under a declared
     **investigation (exploration) mode** — ADR 0025 governs the in-mode discipline and
     hard boundary; this ADR governs only the *placement*. The two are orthogonal and
     compose.

5. **Static-point bundle rule amended** (supersedes ADR 0005 §3's whole-bundle
   delivery). At session end the AI presents the **touched slot file(s)** (plus the
   patch series and the static-point archive per the standing procedure);
   `DESIGN-SUBSTRATE.md` — the low-churn consolidated design master, which stays
   out-of-repo — is re-delivered only when a session changes design substance. Never
   piecemeal within what was touched; never assume the user holds a current copy.

6. **What survives from ADR 0005, restated as current truth:** Tier-P design material
   stays unmanaged (out of repo, repo guardrails target governed assets); `STATUS.md`
   is the entry; in-repo facts take precedence and are never restated into Tier-P as a
   second home; the resume sequence is unchanged in spirit — read the project
   instructions + slot, then `STATUS.md`, then re-clone and re-verify before acting
   (fact-grounding, never assume).

## Consequences

- False confidence from stale slot verification values is eliminated by construction:
  nothing verifiable is written where no gate can check it; everything verifiable is
  derived from the clone each session.
- Per-session context is bounded and stream-scoped: one project's instructions + thin
  slot(s) + `STATUS.md`, instead of a monolithic bundle.
- The handoff rule itself stays in-repo (this ADR), so the protocol cannot fragment.
- Trade-off: currency of the out-of-repo slot/knowledge files still depends on the
  user performing the swap — mitigated by the explicit session-end reminder (Decision
  2) and by keeping slots value-free (a stale slot can mislead about *priorities*, but
  no longer about *facts*, which are re-derived).
- Cross-references: ADR 0023 (durable decisions land in-repo) and ADR 0025
  (exploration-mode discipline) are unchanged and compose with this model; ADR 0029's
  stream split is what the four projects physically realize on the session side.

## Alternatives considered

- **Keep the centralized STARTUP bundle and tighten its update discipline.** Rejected:
  discipline was already the mitigation under ADR 0005 and it failed in practice; an
  ungated medium cannot hold verification values safely, and the aggregate bundle size
  is a structural, not behavioral, problem.
- **Commit the slots into the repository.** Rejected for the same reason ADR 0005
  rejected committing Tier-P (guardrail friction on churning session files), and
  because slots are per-Claude-Project working context, not governed assets; the
  in-repo entry (`STATUS.md`) already exists.
- **A single Claude Project for everything.** Rejected: it reproduces the
  context-budget overrun and mixes stream disciplines that ADR 0029 deliberately
  separates.
