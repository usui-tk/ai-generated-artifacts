# governance/SPEC.md — Governance current-truth (cross-cutting)

<!-- AI read-contract: This is the current-truth view of cross-cutting governance
     decisions. Read THIS for what is true now; consult the governing ADR only for
     rationale and history. Never reconstruct current truth by replaying ADRs. -->

> **Scope.** Family-independent, cross-cutting governance only. Family-specific specs
> live in `governance/spec/common.<family>.md`; subproject specs in
> `projects/<lang>-<name>/SPEC.md`. English-only (no `.ja` twin). Each section below is
> **governed by an ADR** and links back to it (bidirectional `governs` ↔ back-reference);
> the ADR is the immutable decision log, this section is the mutable current-truth view.

## Tooling

Verification machinery is written in **Python 3 (stdlib-first)**. Gate-only third-party
dependencies (e.g. `jsonschema`) are permitted only where a stdlib equivalent is
impractical; they are stamped per run, never pinned.

Governed by [ADR 0001](./adr/0001-tooling-language-python.md).

## Analysis layer

The analysis layer is **DuckDB**, treated as **disposable** — rebuilt from the committed
JSONL, never the authority — and introduced **only at P8** (the cold reconciliation
loop). It is not part of the hot-path scanner; its files are git-ignored (`*.duckdb`).

Governed by [ADR 0002](./adr/0002-analysis-layer-duckdb-disposable.md).

## Machinery

Each verification tool is **single-file, stdlib-only, and no-cross-reference**: it does
not import sibling project code and it follows-latest (whole-tool granularity, no
region-vendoring). Tools live on the **`quality-tools/`** machinery shelf, one tool per
folder, and never graduate.

The **canonical code itself is quality-assured on three axes**: static lint (psa.py /
PSScriptAnalyzer), consistency/drift (the scanner — a vendored copy must match the canon
at its recorded version), and **functional correctness** — every canonical unit carries a
mandatory behavioral test in its canon test home (`reference-code/<family>/tests/`), run
as a regression suite on any canon change and before a consumer vendors it. A canon-test
failure localizes a problem to the **canon**; a drift failure with canon tests green
localizes it to the **copy**. Folding a consumer's change back into the canon is gated on
the canon regression suite passing. The full canon test set is authored in phase **P2a**.

Governed by [ADR 0003](./adr/0003-standalone-tool-principle.md) (standalone tools) and
[ADR 0007](./adr/0007-canon-code-functional-quality-assurance.md) (canon functional QA).

## Execution framework

Execution is **outcome-based**: each phase is value-anchored (value → entry/exit → gate),
filled with a per-step schema, dry-run self-checked, and human-signed-off before
execution — nothing executes before its sign-off. Work is ordered by a **priority
taxonomy** (must-fix > should > nice-to-fix). A **safety carve-out** is never deferred or
self-accepted: deletes require a zero-referrer grep plus a human checkpoint; Layer-0 and
cross-repo edits require explicit authorization; gate-criterion deviations escalate to the
user.

Governed by [ADR 0004](./adr/0004-outcome-based-execution-framework.md).
