---
id: 0028
title: reconciliation-cold-loop
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the P8 cold loop - the scheduled
     drift-reconciliation pipeline (scanner -> DuckDB aggregation -> append-only
     proposals ledger -> human decision). HOT/COLD boundary is load-bearing: the hot
     per-PR battery stays stdlib-only and treats scanner logs as transient; ONLY the
     cold scheduled run commits observations + ledger + reports (with [skip ci]).
     DuckDB is the repository's SOLE DuckDB consumer, cold path only, version
     stamped, disposable. The ledger is append-only: decisions are APPENDED records;
     proposals wrap the PINNED change-request contract 1.0.0 (ADR 0027); skip-key =
     content hash (unchanged re-observed drift is not re-proposed). NO canonical
     mutation happens in the cold path - accepted proposals go through the normal
     human-gated flow. Read SPEC §machinery for current truth. Do not re-decide;
     supersede via a new ADR if reversing. -->

# 0028 — The reconciliation cold loop (P8): scheduled aggregation + proposals ledger

## Context

With ADR 0011 fully implemented (manifest-master + CRUD at P3a, the coupled write at
G4.1, the decision gate + AI trigger at P7a/ADR 0027), drift detection was still
session-driven: the scanner ran when a governance session ran. The design substrate's
P8 charter turns drift into a **continuously tracked, human-governed metric**: a
scheduled cold loop that observes, aggregates and proposes — and never decides.

## Decision

1. **Two-layer shape (D28).** A locally-testable tool,
   `quality-tools/reconciliation-loop/coldloop.py` (1.0.0, self-test 12/12), does all
   the logic; the workflow
   `.github/workflows/governance__reconciliation-cold-loop.yml` is a thin driver
   (daily `17 18 * * *` = 03:17 JST — the cadence the substrate's `[OPEN-exec]`
   confirmed — plus `workflow_dispatch`; T1 timeout; repo-convention action pins).
2. **Hot/cold boundary (load-bearing).** The hot path (the per-phase/per-PR gate
   battery) stays stdlib-only and keeps treating scanner run logs as transient
   (never staged). ONLY the cold scheduled run commits the observation master
   (append-only, hive-partitioned) plus the ledger and reports. Loop safety is a
   double guard: the workflow triggers only on schedule/dispatch (its own push
   cannot retrigger it), and the auto-commit carries `[skip ci]` and touches only
   `governance/state/{observations,reconciliation}/`.
3. **DuckDB enters here and only here.** In-memory, per-run, version stamped into
   the report; `*.duckdb` was already gitignored (ADR 0010). The first real-tree run
   surfaced a schema lesson now pinned by tests: the scanner omits null fields
   entirely, so a drift-free corpus has **no** `reason_class` column — the
   aggregation probes the inferred schema before querying optional columns, and the
   test fixtures mirror the real absent-if-null emission (genchi-genbutsu).
4. **The ledger is append-only and wraps the pinned contract.** Proposals embed the
   ADR 0027 change-request (request_version 1.0.0, machine-measured impact,
   `pending-decision`), derived by subprocessing the canon-drift trigger — the
   contract stays single-sourced. The **skip-key** is a content hash over the drift
   identity + evidence (`unit_id, consumer, region_locator, canonical_hash_norm,
   observed_hash_norm`): an unchanged re-observed drift is not re-proposed; changed
   evidence is a new proposal. Human decisions (`decide --proposal-id … --status
   accepted|rejected --auth …`) are **appended** decision records (D29) — proposals
   are never edited (byte-verified in tests); double-decide and unknown ids are
   refused. `report.json`/`report.md`/`summary.md` are regenerated artifacts, never
   hand-edited.
5. **No canonical mutation in the cold path (P8.4, the safety carve-out).** The
   tool's entire write surface is `governance/state/reconciliation/` (enforced in
   code, verified in tests); it has no write path into the canon, the manifest, or
   any marker file. An **accepted** proposal is executed in a normal governance
   session: `[AUTH]` → promote/restamp → the full battery → user push.
6. **Scope v1 = the central repository (D30).** Deploy-Drivers carries no
   marker-bearing managed units (the D19 deferral); it joins the scan when D19
   lands. **Live-schedule verification is deferred** to the first post-push run
   (the tool and the YAML are verified locally; the schedule itself cannot run in
   the authoring environment).

## Consequences

- Drift becomes a daily-tracked metric (unit × reason-class) with a human-governed
  proposal queue; the P7a decision gate finally has a scheduled feeder.
- The battery gains one cold-path-only dependency for the coldloop self-test
  (`pip install duckdb`); the hot gates remain stdlib-only.
- Operational note: hot-path scanner runs remain transient and are never staged;
  only the cold loop's auto-commits grow the observation master.

## Considered options

- Logic embedded in workflow shell (rejected, D28: untestable in the authoring
  environment; the tool form gets a 12-case self-test and a real-tree rehearsal).
- Editable proposal status fields (rejected, D29: in-place edits break the
  append-only audit property; appended decision records keep history byte-stable).
- Scanning Deploy-Drivers from day one (rejected, D30: zero managed units there
  today — an empty clone step; joins with D19).
