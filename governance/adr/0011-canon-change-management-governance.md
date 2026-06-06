---
id: 0011
title: canon-change-management-governance
status: accepted
date: 2026-06-01
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for HOW changes to the canon (reference-code bodies
     AND the manifest that registers them) are governed - the master-data model, the
     tool-mediated CRUD discipline, the trigger -> single change-management process with a
     decision gate, the impact-weighted decision tiers, and the audit trail. This ADR fixes
     the PRINCIPLES; the implementing machinery (CRUD tool, trigger mechanism, decision-gate
     enforcement) is built in a later phase (see the change-management phase added to the
     plan). Complements ADR 0007 (mandatory canon tests / reconcile-back), ADR 0008 (SemVer
     release model), ADR 0009/0010. Read on-demand. If reversing a point, supersede via a
     new ADR. -->

# 0011 - Canon change-management governance

## Status

Accepted. Complements [ADR 0007](./0007-canon-code-functional-quality-assurance.md)
(mandatory canon tests; regression-gated reconcile-back), [ADR 0008](./0008-canon-release-model.md)
(SemVer release model), and builds on [ADR 0010](./0010-canon-test-taxonomy-and-data.md).

## Context

The canon (`reference-code/<family>/` bodies) is vendored into consumers; the registry
`governance/state/manifest.jsonl` is the master record of which units are managed. Two
gaps surfaced:

1. **What is "managed" is not cleanly defined as data.** The governance-state validator's
   canon-coverage check enumerates `reference-code/powershell/**/*.ps1` from disk and
   demands a bijection with the manifest - a *disk-as-master* rule. But the manifest is
   meant to be the master (checks C/D are manifest-driven). The two views conflict: a
   non-unit file added under the canon tree (e.g. test scaffolding) is reported as an
   "unregistered canon file", even though it was never registered as a unit. The fix is
   not an exclusion list bolted onto the validator; it is to make the **manifest the
   single master** and have membership be an explicit registration, not a disk artefact.

2. **Change has no defined management process.** Changes to the canon arrive from several
   triggers - a periodic drift report (scanner, P3), a user decision, or an AI-driven
   development finding (the reconcile-back loop, ADR 0007 §3). Today a change is "apply the
   code + run tests"; there is no defined path that guarantees the manifest is updated in
   lock-step, no decision point on whether a change *should* be taken (distinct from
   whether it is *built correctly*), and no impact-based weighting of that decision. The
   community models the project already draws on - Debian bug severity (weighted by breadth
   of impact, not size), the Go proposal process (trivial vs non-trivial, gated on external
   visibility), and SemVer (major/minor/patch by compatibility) - all converge on the same
   principle: **the kind of change and its consumer impact determine how heavy the decision
   is.**

## Decision

Canon change management is governed by five principles.

### 1. Manifest is the Git-resident master; membership is registration

`governance/state/manifest.jsonl` (Git-resident, append-oriented per ADR 0002's
JSONL-master model) is the **single source of truth** for what is a managed canon unit. A
file is a managed unit **iff it has a manifest record** - not because it sits under the
canon tree. The governance-state validator's canon-coverage check is corrected from
*disk-as-master* (glob the tree, demand bijection) to **manifest-master**: it verifies that
every registered unit's `canonical_location` exists and matches, and that unregistered
files inside the **unit home** (`Public/`, `Private/`) are flagged - while non-unit areas
(`tests/`, `.psm1`/`.psd1` scaffolding per ADR 0010) are simply not managed units. This is
a positive definition of the managed set, not an exclusion list.

### 2. Tool-mediated CRUD; no direct manifest edits

Create / update / delete of manifest records is performed **only through a governance CRUD
tool** (a `quality-tools/` machinery script - the same class as the validator / psa.py /
scanner; **not** a long-running service, consistent with the ephemeral-container model).
Direct hand-editing of `manifest.jsonl` is **prohibited** once the tool exists. The CRUD
tool self-validates (runs the governance-state validator after each operation) so a manifest
mutation cannot leave the master in an invalid state.

### 3. Many triggers, one change-management process

Change triggers are diverse - **periodic-report (scanner / drift)**, **user-initiated**, and
**AI-development-initiated** (reconcile-back, ADR 0007 §3). They are entry points only.
After a trigger fires, every change converges on **one** process: **(i) canon code change ->
(ii) quality gates (canon behavioral tests per ADR 0007 + lint/drift) -> (iii) manifest CRUD
via the tool -> (iv) commit + CHANGELOG**. A single convergence path is what makes
"the manifest is always updated in lock-step" structurally guaranteed rather than
discipline-dependent. The trigger mechanism itself is a governance tool: for the machine
trigger (scanner) it auto-files the change request; for human/AI triggers it is the gate
that turns a judgement into a structured, recorded request (the judgement is human/AI, the
recording is the tool).

### 4. Decision gate between trigger and process; impact-weighted

A trigger does **not** unconditionally enter the process. Between trigger and process sits a
**decision gate** that records and approves *whether to take the change* (distinct from the
quality gate, which checks whether it is *built correctly*). The two are in series: the
decision gate ("should we?") precedes the quality gate ("is it correct?"); both must pass
for the canon to change. The decision's weight is set by **change kind x consumer impact
range**, not by size/effort:

- **kind** tags (bug-tracker style, after Debian severity + Go labels): `bug-fix` /
  `enhancement` / `feature` / `breaking`.
- **impact range** = consumer blast radius (after Debian's "breadth of impact" severity
  axis and SemVer's compatibility axis), connected to **ADR 0008's SemVer levels**:
  - **patch** (bug-fix, backward-compatible) -> propagates transparently -> **light
    decision** (one-line decision-log entry + approval; Go-"trivial").
  - **minor** (enhancement, backward-compatible addition) -> bounded impact -> **medium**.
  - **major** (`breaking`: signature/behaviour change, removal, rename) -> can break every
    consumer -> **heavy decision** (full ADR + enumeration of affected consumers + a
    migration plan; Go-"non-trivial" / design-doc).

This reuses the existing SemVer axis (ADR 0008) rather than inventing a new one: change kind
-> SemVer bump -> decision weight.

### 5. Audit trail = Git commit + CHANGELOG

The operation log is the **Git history**: each change-management operation is a commit, and
material changes are recorded in `CHANGELOG`. No separate operation-log store is created;
the JSONL master's append discipline plus Git blame already record who/when/what. This keeps
the audit trail on one substrate (the repo), not two.

## Transitional and boundary clauses

- **[Transitional - principles now, machinery later]** This ADR fixes the principles; the
  CRUD tool, trigger mechanism, and decision-gate enforcement are implemented in a later
  phase. Until the CRUD tool exists, direct manifest edits are **tolerated as an interim
  measure** (e.g. flipping `tested=true` at P2a.3), provided the change-management process
  (kind/impact classification, decision record, commit+CHANGELOG trail) is still walked by
  hand. Direct editing is an interim state to be replaced by the CRUD tool, not the target
  model. Principle 1 (manifest-master validator correction) may land ahead of the tool,
  since it is a read-side check, not a write path.
- **[Relationship to `[AUTH]`]** The decision gate is **not** a second, parallel approval
  regime: it is the existing `[AUTH]` discipline (human approval for Layer-0 / cross-repo
  edits) **extended to the change-management process**. Where a change is already `[AUTH]`,
  the decision gate is that same approval, recorded with kind/impact; it does not impose a
  duplicate sign-off.
- **[Impact-measurement maturity]** Mechanically measuring "consumer blast radius" needs the
  scanner (P3) and registered consumers (P6/P7). Until then, impact range is assessed by
  **human judgement using the kind tag as a first approximation**; it is refined to
  machine-measured impact once the scanner and consumer registration exist. The principle is
  fixed now; its automated measurement matures later.

## Consequences

- The governance-state validator is corrected to manifest-master (principle 1); test
  scaffolding under `reference-code/<family>/tests/` is no longer mis-reported, because it
  was never registered - resolving the issue that surfaced this design without an exclusion
  list. This unblocks P2a.1's test home.
- A later change-management phase implements the CRUD tool, the trigger mechanism, and the
  decision-gate enforcement; this ADR is its charter.
- Reconcile-back (ADR 0007 §3) gains the missing decision relationship: the regression gate
  (quality) is preceded by the decision gate (should this consumer change enter the canon).
- The model stays consistent with the ephemeral-container / Git-as-truth / JSONL-master
  architecture; no service, no second audit store, no new versioning axis.

## Alternatives considered

- **Add a `tests/` exclusion to the validator.** Rejected: a negative, ever-growing rule
  that keeps disk-as-master and accretes exclusion conditions. Manifest-master with explicit
  registration is the positive, bounded definition.
- **Unconditional trigger -> process.** Rejected: lets "correctly built but should-not-take"
  changes through. The decision gate (should?) in series before the quality gate (correct?)
  is required.
- **Weight decisions by change size/effort.** Rejected: the canon is vendored, so impact is
  measured by consumer blast radius, not lines changed - per Debian severity's breadth axis.
