---
id: 0030
title: satellite-canon-distribution
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["governance/schema/manifest.schema.json §consumers[].repo", "quality-tools/canonical-drift-scanner/scanner.py §--satellite", ".github/workflows/governance__reconciliation-cold-loop.yml §satellite-step"]
---

<!-- AI read-contract: authoritative for HOW canon units are distributed into a
     SATELLITE repository (first: Deploy-Drivers-For-WindowsServer, "dd") and how
     drift on those instances is watched. Load-bearing decisions: two waves
     (wave-1 = pure-EXACT framing only, wave-2 = per-unit reconciliation with
     exactly three outcomes: canon-reflow via `trigger.py propose`, canon
     adoption, or a declared fork); consumers[] gains an OPTIONAL `repo` field
     (absent = this central repository); the COLD loop clones the satellite
     read-only and scans it against the CENTRAL manifest (observations stay in
     the central ledger, partitioned per repo); the HOT battery SKIPS unmapped
     cross-repo consumers by design (a fetch-based hot gate is deferred); ALL
     dd-side changes land via user-driven PRs. Do not re-decide; supersede via
     a new ADR if reversing. -->

# 0030 — Satellite canon distribution (dd): waves, cross-repo consumers, cold-loop satellite scan

## Context

P7 made `Deploy-Drivers-For-WindowsServer` the first cross-repo satellite
(class-(C) governance bridge; ADR 0014 model), and deferred three D19 items:
dd manifest rows, vendored regions in dd, and cross-repo drift watching. Real
need was declared 2026-07-03, and a machine comparison (dd HEAD `3bda89b`
against the central canon, 58 units @ 1.0.0) grounded the design:

- **20 units are pure-EXACT** — normalized-byte-identical at every occurrence,
  **80 occurrences** across the four sister scripts (debug-trace family,
  `Write-*` family, `_LogLine`, TLS setup, and peers). Framing them with
  canonical markers changes zero bytes of function body.
- **12 units differ everywhere** — **45 occurrences**; the four scripts agree
  with each other (dd-internal sync is healthy), so each unit is a single
  canon-vs-dd delta (similarity 0.00–0.98) needing a per-unit reconciliation
  judgment.
- 430 dd-only functions and 26 canon units with no dd counterpart are out of
  scope.

## Decision

1. **Two waves (adjudicated as D33).** **Wave 1**: frame the 20 pure-EXACT
   units in the four dd sister scripts as marker-bearing vendored regions
   (`policy=canonical binding=follow-latest version=1.0.0`) — framing ONLY, no
   body edits. **Wave 2**: reconcile the 12 differing units one by one; each
   ends in exactly one of: (a) the canon adopts the dd improvement — routed
   through `trigger.py propose` (ADR 0027; no bypass), (b) dd adopts the canon
   body, or (c) the instance is declared a fork (`policy=forked` marker,
   frozen; scanner reports `forked-frozen`, ADR 0016). No blanket rule — the
   deltas range from a single whitespace to a 200-line divergence.

2. **Cross-repo consumers (adjudicated as D34).** A `consumers[]` entry gains
   an OPTIONAL `repo` field; **absent means this central repository**
   (backward-compatible: every existing row is unchanged and means what it
   always meant). Consumer identifiers stay globally unique across repos (the
   dd sisters use the script filename stem); `consumers[]` remains the single
   source of truth for who inlines a unit (baseline §4.1) — the satellite
   carries markers, never governance state.

3. **Satellite scanning is COLD-path-owned (adjudicated as D35).** The
   scheduled cold loop clones the satellite read-only each run and passes the
   scanner a `--satellite <repo>=<path>` mapping (plus the checked-out commit).
   The scanner resolves cross-repo consumer paths against the mapped checkout,
   stamps each record with that consumer's `repo`/`commit` (the observation
   schema has carried `repo` since P3), and writes observations into the
   CENTRAL ledger under its existing `repo=<name>` partition. The HOT battery,
   run without mappings, **skips** cross-repo consumer instances and reports
   the skip count — deliberately not `drift`/`unknown`, so satellite
   unreachability can never fail a local gate. Hot-path blindness to
   satellites is by design; a fetch-based hot gate stays deferred until a
   grounded need (e.g. the first real satellite drift).

4. **Ordering and change flow (adjudicated as D36).** (1) this ADR + the
   central machinery (schema, scanner, cold-loop workflow) → (2) the dd wave-1
   framing patch → (3) consumer-row registration (tool-mediated CRUD), which
   makes the cold-loop watch live → (4) wave 2. **All dd-side changes land via
   user-driven PRs**; governance-origin edits in dd are mechanical-only and
   explicitly flagged (ADR 0029 rule 3); the dd CHANGELOG is a historical
   record — past entries are never rewritten.

## Consequences

- 125 inlined occurrences (80 + 45) converge onto the canon with machine drift
  watching, at the cost of one daily shallow clone in the cold loop.
- The hot battery is byte-for-byte unaffected until step (3); from step (3) on,
  local runs report skipped cross-repo instances and the documented healthy
  baseline is updated in the same patch that registers the rows.
- The scanner's version constant is realigned with its manifest row as part of
  the machinery change (pre-existing mismatch: constant `0.1.0` vs row
  `1.0.0`; both become `1.1.0`), so `runtime.scanner_version` in observations
  matches the governed version from here on.
- Satellite scan results can lead to proposals in the central ledger that a
  human must carry to dd as a PR — the machine proposes, humans decide,
  unchanged (ADR 0028).

## Considered options

- **A shared module file (dot-sourced or submodule) instead of vendored
  regions.** Rejected: the dd sisters are deliberately single-file,
  self-contained deployment tools for offline servers; vendored regions keep
  that property while still converging on the canon (ADR 0008 model).
- **Satellite-side manifest + satellite-side scanning.** Rejected: splits the
  single source of truth (baseline §4.1) and puts governance state where no
  governance machinery lives; the central manifest + cold clone is strictly
  simpler.
- **A fetch-based HOT gate now.** Deferred, not rejected: dd has no drift
  history yet, the daily cold cadence bounds staleness at one day, and the hot
  battery staying network-free is a standing property worth keeping until a
  real incident argues otherwise.
- **Wave-2 blanket rules (all-adopt-canon or all-fork).** Rejected: the
  measured deltas are heterogeneous — a whitespace-only 0.00-similarity
  one-liner and a 200-line environment-report divergence deserve different
  outcomes.
