---
id: 0016
title: scanner-output-contract-pins
status: accepted
date: 2026-06-02
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery", "governance/schema/observation.schema.json"]
---

<!-- AI read-contract: authoritative for the THREE structural pins the P3 consumer-drift
     scanner needs before it can emit a conformant observation record, none of which were
     uniquely determined by the prior normative set: (F1) what `runtime.duckdb` carries before
     DuckDB exists (P8) — `"n/a"`, since the observation schema requires the field as a string;
     (F3) the `kind` → `granularity` derivation table (the manifest carries no `granularity`
     field, yet the observation requires one); and (F4) the meaning/scope of the `drift` enum
     value `unknown` (framed now as a determinability fallback; precise trigger conditions are
     pinned at P6 when real consumer scanning exercises the paths). This is the P3.1 opening of
     P3 (after P3.0 = ADR 0015 hash-contract pin), found by a documents-only structural review
     before any scanner code. Introduces NO new phase. Builds on ADR 0001/0002 (Python/DuckDB),
     ADR 0003 (standalone tools), ADR 0014 (document classes), ADR 0015 (hash contract). Read
     on-demand. If reversing, supersede via a new ADR. -->

# 0016 - Scanner output-contract pins (F1/F3/F4)

## Status

Accepted. The **P3.1** opening of P3 (the consumer-drift scanner build), following **P3.0**
([ADR 0015](./0015-canonical-normalized-hash-contract.md), the hash-contract pin). Found by a
documents-only structural review of the normative set (this ADR + the four Tier-P docs +
ADRs 0001-0015 + the schemas), before writing any scanner code. Introduces no new phase.

## Context

The P3 consumer-drift scanner's **sole output contract** is
`governance/schema/observation.schema.json` (#8). A documents-only review (deliberately before
touching the consumer scripts — the governance model's structural validity is checkable inside
the normative set, and over-depending on the artifacts is the project's main risk) found three
fields the schema **requires** but the prior normative set did **not** uniquely determine:

1. **F1 - `runtime.duckdb` before P8.** `runtime` is a required object with
   `required: [python, duckdb, scanner_version]` and `additionalProperties: false`; `duckdb` is
   a required string. But [ADR 0002](./0002-analysis-layer-duckdb-disposable.md) introduces
   DuckDB **only at P8** ("not part of the hot-path scanner (P3)"), and baseline §3 fixes the
   runtime as **stamped, not pinned** (record the per-run resolved version). So the P3 scanner
   has no DuckDB to stamp, yet cannot omit the field. The prior set never said what a pre-P8
   scanner writes there. (This is an **underspecification, not a contradiction**: the schema
   asks for a stamp; nothing says the stamp of an absent dependency.)
2. **F3 - `kind` → `granularity`.** The observation **requires** `granularity`
   (`whole-tool` | `region`) and the scanner "keys off `granularity`, not language" (baseline
   §3), but the **manifest carries no `granularity` field** and no document states how it is
   derived. The material exists in baseline §3 but was never assembled into a decision table.
3. **F4 - `drift = unknown`.** The enum includes `unknown`, but no document defines when it is
   emitted (`match`/`drift`/`forked-frozen`/`n/a` are all defined; `unknown` appears only in the
   enum). Left undefined, the scanner would invent the condition in code (an implicit contract).

## Decision

We will pin the three, splitting what must be decided now from what is better decided when real
consumer scanning exists (P6).

1. **F1 - decide now.** A scanner that does not use DuckDB stamps **`runtime.duckdb = "n/a"`**.
   This holds for **every** record (the `runtime` block is required regardless of granularity).
   At **P8**, when the cold loop introduces DuckDB, the stamp becomes the resolved DuckDB
   version. No schema change is needed (`"n/a"` is a valid string); the schema's `duckdb`
   description is annotated to record the convention.
2. **F3 - decide now.** `granularity` is **derived from `kind`** by this fixed table (it is not
   a manifest field; the manifest's `kind` is the source). Promoted into SPEC §machinery:

   | `kind` | `granularity` | basis |
   |---|---|---|
   | `powershell-helper` | `region` | inlined marked code region; normalized-hash body-drift (baseline §3) |
   | `bash-region` | `region` | inlined marked code region (self-contained shell; `source`s config, not code) — body-drift |
   | `spec-region` | `region` | inlined marked spec region (shared Part A) — body-drift |
   | `python-helper` | `whole-tool` | Python **import** model: imported, not inlined — **no inlined copy to body-drift** (baseline §3); version-currency is P8 |
   | `python-tool` | `whole-tool` | whole-tool machinery (no inlined region) |
   | `tool` | `whole-tool` | whole-tool machinery (`psa.py`, the scanner itself) |
   | `governance-doc` | (out of this scanner's body-hash-drift scope) | class-(B) rendered docs carry **no per-file hash/marker** ([ADR 0014](./0014-document-governance-model.md) §2); their integrity is the **document-conformance gate's** job, not this scanner's. If a `governance-doc` instance is ever observed by this scanner it follows the whole-tool null convention (`drift=n/a`, null hashes). Precise wiring stays with ADR 0014 / TF.1. |

   `region` ⇒ the normalized-hash body-drift path (ADR 0015 contract); `whole-tool` ⇒ the
   whole-tool null convention (null region/hash fields, `drift=n/a`; baseline §4.4). The split
   is **import-vs-inline**, not language: a kind has a body to compare iff it is inlined.
3. **F4 - frame now, detail at P6.** `unknown` is the **determinability fallback**: the scanner
   emits it for a `region` instance it located but **could not resolve to a comparison result**
   — so the scanner never crashes, never emits an out-of-enum value, and a human/cold-loop can
   triage. The **precise trigger conditions** (e.g. a malformed/absent marker pair, an
   unresolvable canonical reference, a normalizer error) are **pinned at P6**, when real
   consumer scanning first exercises these paths (consumers carry no vendored markers until
   P6/P7 - manifest `consumers[]` is empty until then; spine: the scanner's first real consumers
   are P6.6/P7.6). Deciding the exact conditions now, against no real input, would be speculation
   - exactly the over-dependence-on-absent-artifacts this review is meant to avoid in reverse.

## Consequences

- The scanner's sole output contract is now uniquely determined for every required field, so
  P3.2+ can author the scanner against a closed contract (it reuse-by-copies the ADR 0015
  normalizer, passes golden vectors GV-1..5, derives `granularity` by the F3 table, stamps
  `duckdb="n/a"`, and reserves `unknown` per F4).
- **Scope clarified (F2, no decision needed):** P3 **builds** the scanner and validates it
  against constructed fixtures (P3.7); its first **real** run is P6 (consumer regions do not
  exist until vendoring). The earlier idea of a first live scan over the two in-repo consumers
  at P3 is withdrawn as inconsistent with the normative set.
- `governance-doc` integrity remains the ADR 0014 document-conformance gate's responsibility,
  not this scanner's — the two gates stay cleanly separated (code/region body-drift vs rendered
  doc conformance).
- No code, no canon, and no schema **structure** changed; the observation schema gains
  description-only annotations pointing at this ADR. The standing gates are unaffected.

## Alternatives considered

- **F1: stamp `"none"` / change the schema to make `duckdb` optional pre-P8.** `"none"` is
  equivalent but `"n/a"` matches the existing `drift="n/a"` whole-tool convention's vocabulary.
  A schema `allOf` branch making `duckdb` optional was rejected as heavier than the problem - a
  sentinel string fully satisfies "stamp the per-run fact (there was no DuckDB)."
- **F3: add a `granularity` field to the manifest.** Rejected: it would duplicate information
  already implied by `kind` (one-home rule, field-ownership), creating a second source of truth
  that could drift from `kind`. Derivation keeps `kind` the single source.
- **F4: fully pin `unknown` now / drop it from the enum.** Fully pinning against no real input
  is speculation (and risks an incomplete list the scanner then violates). Dropping it removes
  the scanner's safe fallback for genuinely indeterminate instances, risking a crash or an
  out-of-enum emission. Framing now + detailing at P6 keeps the contract total without guessing.
