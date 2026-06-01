---
id: 0010
title: canon-test-taxonomy-and-data
status: accepted
date: 2026-06-01
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §Machinery"]
---

<!-- AI read-contract: authoritative for HOW the canon behavioral test suite (ADR 0007)
     is structured - the dependency taxonomy each unit is classified under, the unit-vs-
     functional distinction, where test input data lives, and how the driver supplies
     preconditions WITHOUT modifying canon code. Complements ADR 0007 (which makes canon
     tests mandatory): 0007 = "every unit is tested"; 0010 = "this is how the tests are
     organised". Authored at P2a (test home), applied across P2a.2 (full suite). Read
     on-demand. If reversing a point, supersede via a new ADR (one decision = one ADR). -->

# 0010 - Canon test taxonomy and test-data management

## Status

Accepted. Complements [ADR 0007](./0007-canon-code-functional-quality-assurance.md).

## Context

ADR 0007 makes a behavioral test for every canonical unit **mandatory** (the third
quality axis), but leaves the *structure* of that suite undefined: how units are
classified, what the test driver must set up, and where test input data lives.

The canon is a set of shared helpers **extracted from consumer scripts**. Their real
usage model is: a consumer initialises `$Script:` session state in its own init block
(outside the helper bodies) and then calls the helpers; the helpers read/mutate that
caller-owned state by design. A faithful test must reproduce that usage model **without
modifying the canon functions** - dependencies are supplied by the driver, not removed
by editing the canon. (This is the same principle that underlies ADR 0009's external-
scope contract for the static analyzer.)

A per-unit inventory of all 58 units established that their dependencies fall into a
small number of kinds, and that "single function vs multiple functions" is not the right
axis for unit-vs-functional (calling another canon function is resolved transparently by
`Import-Module`). A taxonomy is needed so P2a.2 can author the full suite as a set of
well-defined, repeatable patterns rather than ad hoc per unit.

## Decision

### 1. Dependency taxonomy (what the driver must set up)

Each unit is classified by the dependencies it has:

- **(1) state dependency** - reads/mutates `$Script:` session state owned and initialised
  by the consumer (or module loader), not the unit's own file. Driver supplies it via a
  shared fixture (`Initialize-CanonSessionState`).
- **(2) function dependency** - calls other canon functions. Resolved transparently by
  `Import-Module` (the module dot-sources all units); the driver does **not** set anything
  up for this, and it does **not** by itself make a unit functional.
- **(3) environment dependency** - touches an external resource (filesystem / network /
  process). Driver supplies a Pester `Mock`, stub, or per-test tmpdir.

### 2. Unit vs functional

- **Unit test** - verifies one unit's behaviour. May have (1) state and/or (2) function
  dependencies; both are satisfied by the fixture + module load. The default classification.
- **Functional test** - verifies, deliberately, either a **multi-function lifecycle**
  (e.g. `Start-DebugTrace` -> `Set-DebugStep` -> `Stop-DebugTrace` -> `Export-DebugTraceJson`)
  or an **external-resource interaction** (3). A unit is functional only because the test
  targets coordination or an external resource - never merely because it calls another
  canon function.

### 3. Test-data classes (where the input lives)

- **D-inline** - small / single-use / readable literals in the test, OR a byte-contract
  checked against a reference oracle (the canonical-JSON value matrix vs the Python oracle).
- **D-fixture** - committed input/expected files under `reference-code/<family>/tests/data/`,
  used when the data is **reused** across tests/units, OR carries a **file-level byte
  contract**, OR exceeds a readability threshold (nesting > 3 or > 15 lines). None are
  required at P2a.1; created on first need.
- **D-generated** - state/data built at runtime by the driver (e.g. a trace assembled by
  lifecycle calls). Never a committed file.
- **D-mock** (distinct, not input data) - the *response* an external resource returns,
  defined in a Pester `Mock`. Tracked separately from D-inline/fixture/generated because it
  defines a test-boundary behaviour, not an input to the unit.

### 4. Canon-side test-data management

- All canon test assets live under **`reference-code/<family>/tests/`** (the canon is
  standalone-testable; tests never reach into a consumer / `scripts/` tree). Layout:
  `*.Tests.ps1` (Pester), `common/` (Python oracle + invocation harness), `data/`
  (committed D-fixture inputs/expected, created on first need), and shared fixtures such
  as `CanonSessionState.ps1`.
- Reference/sample data under a consumer's `scripts/.../tests/` is **consumer-domain** and
  is **not** referenced in place. If a sample is needed to test a canon helper, it is
  **copied into `reference-code/<family>/tests/data/` (canon-owned) and trimmed** to the
  canon's need. No `scripts/` edits.
- **D-generated and D-mock are never committed files** - they are produced in
  `BeforeAll`/`BeforeEach` (state) and `Mock` blocks (responses); filesystem writes use a
  per-test tmpdir.

### 5. Relationship to ADR 0007

ADR 0007 establishes **that** every canonical unit is tested (mandatory, full set, the
third quality axis, canon-vs-copy attribution, regression-gated reconcile-back). This ADR
establishes **how** those tests are organised. The canon functions are not modified to
satisfy tests; preconditions are supplied by the driver, mirroring the consumer usage
model. Where ADR 0007 §3 gates reconcile-back on the canon suite, the suite's F-env units
are mock-backed - that is a property the reconcile-back gate inherits.

## Consequences

- P2a.2 authors the full 58-unit suite as a set of bucketed patterns (pure / state-fixture
  / module-load / state-lifecycle / env-mock) rather than ad hoc, with a known driver
  responsibility and data class per unit.
- The canon stays unmodified: no self-init is added to helpers to satisfy a linter or a
  test; the driver reproduces the consumer's init.
- `reference-code/<family>/tests/` gains `common/` and `data/` alongside `*.Tests.ps1`
  (baseline reference-code tree updated; the prior "tests (optional)" note is corrected -
  tests are mandatory per ADR 0007).
- The per-unit test inventory (bucket x data class for all 58 units) is a P2a working
  record, kept with the Tier-P design substrate.
- F-env reconcile-back regression coverage depends on mocks; the realism of those mocks is
  a known quality factor for the P6/P7 reconcile-back gate (recorded, not resolved here).

## Alternatives considered

- **Add initialisation to the canon helpers** so each is self-contained for tests. Rejected:
  it diverges from the real usage model (consumers own the session state), creates
  double-initialisation/competition with the consumer init, and modifies frozen P2.6 canon
  bodies. The driver-supplies-preconditions model keeps the canon a pure set of
  caller-state-consuming helpers.
- **Classify unit-vs-functional by single vs multiple functions.** Rejected: calling another
  canon function is resolved by `Import-Module` and does not change what the test verifies;
  the meaningful axis is whether the test targets a lifecycle or an external resource.
