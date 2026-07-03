---
id: 0027
title: decision-gate-and-ai-trigger-implementation
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the P7a implementation of ADR 0011 §3-AI/§4 -
     the decision gate + AI-driven (reconcile-back) trigger + machine impact
     measurement, all inside quality-tools/canon-drift-trigger/trigger.py (1.1.0).
     Change-request contract PINNED at request_version 1.0.0. Tier rules: patch->
     trivial, minor->medium, major->heavy (heavy REFUSED without enumerated consumers
     + migration plan + full-ADR ref). Approval act = [AUTH] + git commit; NO new
     state store (the append-only proposals ledger is P8's). Read SPEC §machinery for
     the current-truth view. Do not re-decide; supersede via a new ADR if reversing. -->

# 0027 — Decision gate + AI-driven trigger: the ADR 0011 §3-AI/§4 implementation (P7a)

## Context

ADR 0011 decided the change-management principles but its §maturity clause deferred
two of them until consumers were vendored and registered: the **AI-driven
(reconcile-back) trigger** (§3-AI) and the **decision gate with impact-weighted
tiers** (§4) — because consumer blast radius could not yet be *measured*, only
estimated. P6/P7 realized the consumer topology (58 + 39 vendored code units across
two PowerShell consumers; 4 doc-region consumers; the first cross-repo satellite),
and G4.1 shipped the coupled write the gated process routes into. P7a is the
re-evaluation point ADR 0011 itself named.

## Decision

1. **P7a.1 — the §4 tier rules are CONFIRMED against the realized topology**
   (no revision of ADR 0011): change kind → SemVer level → decision tier —
   `bug-fix`→patch→**trivial**, `enhancement`/`feature`→minor→**medium**,
   `breaking`→major→**heavy**. Impact is **machine-measured, never estimated**:
   consumer blast radius is computed from the manifest's `consumers[]` plus marker
   placements counted over both frames (code `# >>>` / doc `<!-- >>>`,
   reuse-by-copy per ADR 0003). **Retrospective validation** against the two real
   coupled promotions: `spec.bash.part-a` → 2 consumers / **24 markers** (the
   psaMove 1.0.1 op wrote exactly 24) and `spec.powershell.part-a` → 2 consumers /
   **42 markers** (the G4.1 op wrote exactly 42). Forward validation binds to the
   next real canon change (no artificial change was manufactured; drift is 0).
2. **Implementation home = `canon-drift-trigger` (1.1.0)**, keeping the ADR 0011 §3
   "many triggers, one process" entry point in one tool: `impact --unit-id <id>`
   (standalone measurement), `propose --unit-id <id> --kind <k> --summary <s>
   [--auth <ref>] [--migration <plan>] [--adr <id>]` (the reconcile-back trigger:
   the judgement is human/AI, the recording is the tool), and the machine drift
   path now attaches a computed-impact decision block with `kind=null` →
   `status=pending-decision` (the tool files, a human classifies).
3. **The gate's refusal semantics** (the §4 acceptance rule): a **heavy** decision
   is REFUSED unless the request carries the enumerated affected consumers
   (auto-computed), a migration plan, and a full-ADR reference. Trivial/medium
   paths emit directly. The approval **act** is the existing `[AUTH]` plus the Git
   commit (§4/AUTH: no duplicate sign-off; §5: audit trail = Git + CHANGELOG, so
   **no new state store** — the append-only proposals ledger is P8's cold-loop
   deliverable, deliberately not built here).
4. **The change-request contract is PINNED by its owner.** The P3a trigger shipped
   `request_version 0.1.0-provisional` with tracked-deferral markers precisely
   because the decision gate — the contract's real consumer — did not exist. It now
   does and pins the shape: `request_version 1.0.0`, `contract_status pinned-P7a`.
   Every request carries a `decision` block (kind / semver_level / tier /
   machine-measured impact / approval reference; + migration/adr on the heavy path).
5. **Series order is normative:** trigger (any of the three) → **decision gate
   ("should we?")** → **quality gates ("is it correct?")** → CRUD/coupled write →
   commit + CHANGELOG. The emit-only boundary is unchanged: this tool never writes
   state or applies changes.

## Consequences

- ADR 0011 principles 1–5 are now implemented end-to-end (manifest-master + CRUD at
  P3a; the coupled write at G4.1; the decision gate + AI trigger here).
- The "reference-code deployment timing" question has a machine answer: deployment
  is event-driven (three triggers), gated by tier-weighted decisions whose impact
  half is computed, and executed through the promote/restamp write paths; the
  scheduled detection cadence arrives with P8's cold loop.
- Two small constraints: heavy changes cannot bypass migration/ADR requirements,
  and machine drift requests stay `pending-decision` until a human assigns kind.

## Considered options

- **A separate decision-gate tool.** Rejected (D21): §3's value is one entry point
  per process; splitting would duplicate the request contract across tools.
- **An append-only decision ledger now.** Rejected (D22): §5 forbids a second
  operation-log store; the ledger is P8's deliverable with its own approval loop.
- **Manufacturing a canon change to "really" validate the gate.** Rejected (D23):
  drift is 0; the retrospective reproduction of the two real promotions validates
  the measurement, and the forward validation binds to the next genuine change.
