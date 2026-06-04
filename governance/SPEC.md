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
Release readiness is carried in each unit's SemVer `canonical_version`: `< 1.0.0` (0.x.y)
is pre-release and MUST NOT be vendored; a unit is promoted to `1.0.0` only after its full
canon test suite passes, and vendoring (P6/P7) is gated on `version >= 1.0.0`.

Governed by [ADR 0003](./adr/0003-standalone-tool-principle.md) (standalone tools),
[ADR 0007](./adr/0007-canon-code-functional-quality-assurance.md) (canon functional QA),
[ADR 0008](./adr/0008-canon-release-model.md) (canon release model), and
[ADR 0009](./adr/0009-psa-canonical-lifecycle.md) (psa.py canonical lifecycle: the
`quality-tools/` copy is the continuously-updated source of truth; the original
`scripts/python/...` copy is frozen until the psaMove contract deletes it after P7;
consumers repoint and follow-latest at the `scripts/`->`projects/` migration), and
[ADR 0010](./adr/0010-canon-test-taxonomy-and-data.md) (canon test taxonomy: dependency
buckets, unit-vs-functional, test-data classes, and the `reference-code/<family>/tests/`
data-management policy - complements ADR 0007's mandatory test rule), and
[ADR 0011](./adr/0011-canon-change-management-governance.md) (canon change-management
governance: manifest = Git-resident master with tool-mediated CRUD; many triggers -> one
process; an impact-weighted decision gate in series before the quality gate; audit trail =
commit + CHANGELOG - principles fixed here, machinery built in a later phase),
[ADR 0012](./adr/0012-dual-runtime-environment-info-policy.md) (dual-runtime environment-info
policy: a dual-runtime canon function reports equivalent-quality info on both PS 5.1 and
7.x, never degrading - the first worked example of the ADR 0011 process), and
[ADR 0013](./adr/0013-multi-platform-multi-version-quality-assurance.md) (multi-platform /
multi-version quality assurance: a three-cell PSScriptAnalyzer compatibility matrix + a
per-unit `platform_scope` manifest classification (cross-platform / windows-enhanced /
windows-only) + classification-backed suppression of intentional OS-specific findings, with
the profile-DB limitation recorded as necessary-but-not-sufficient), and
[ADR 0014](./adr/0014-document-governance-model.md) (document governance model: the three
cross-repo document classes - (A) reference / (B) own-and-reconstruct / (C) vendored-copy;
`governance/templates/` elevated to a document-template canon at code parity, with a
`kind=template` manifest registration, a SemVer release gate, and a conformance gate over
rendered doc-sets; the class-(B) reconstruction procedure including the graduation structural
transform (prefix-strip + relative->absolute link rebinding + ADRs-travel + doc-set
recomputation); and the rule that every reconstruction/sync point is also a quality gate -
the DOCUMENT analog of ADR 0007 + ADR 0008, introducing no new phase: TF and the P4-P7 exit
criteria absorb it; scope clarification (2026-06-04) - the canon governs documents + masterless
repo-structural dotfiles, NOT tool-owned configs such as `.psa.config.json` whose master is the
owning tool canon and which consumers follow-latest per ADR 0009 - discriminator = master-ownership), and
[ADR 0018](./adr/0018-template-canon-version-model.md) (template-canon version model: two
version axes - Axis 1, a per-template body `canonical_version` for provenance; Axis 2, a
single `governance/templates/VERSION` that is the reconstructability gate and the consumer pin
target. The gate axis follows the unit of delivery - per-unit for vendored code (ADR 0008),
per-set for reconstructed doc-sets (ADR 0014 class-(B)). Axis 2 is a release-commit artifact
outside the manifest, like the code canon's `.psd1` `ModuleVersion`, so the ADR 0011 CRUD
manifest-row write-path boundary is unaffected. Refines ADR 0014 §2), and
[ADR 0019](./adr/0019-document-vendor-model-and-provenance-embedding.md) (document vendor model
+ provenance embedding: a three-layer doc model - L1 language-independent format / L2 language
template [common = vendored-from-code + subproject-specific] / L3 rendered doc-set - in which
L2-common content is VENDORED into L3 via a managed region (marker + hash + tool-sync), not
referenced; provenance is embedded two ways (a doc-level YAML front-matter pin + region-level
ADR 0015 markers) feeding a two-level staleness trigger; variance is explicit applicability
metadata, never conditional fold-in; the heavy marker/hash machinery is localized to L2-common
vendored regions while L1/L3 stay light structural conformance. Refines ADR 0014; evolves
AGENTS.md §6 + TR-SPEC-2).

### Canonical normalized-hash contract

The `hash=` on a canonical marker, and the `*_hash_norm` fields on observations, are a single
**computable** value: take the region body (lines strictly between the `>>> CANONICAL` and
`<<< CANONICAL` lines, LF-joined, BOM-stripped), normalize it with the PSA8001 tokenizer
(comments and string contents -> whitespace; `$variables` in double-quoted strings preserved),
collapse all whitespace runs to one space and strip the ends, then take
`sha256(normalized)` truncated to **16 hex**. The gate compares normalized hashes
(encoding-neutral under BOM+CRLF); the verbatim-byte hash is **forensic-only**; `forked`
regions are frozen (`forked-frozen`), not compared; whole-tool records carry null hashes and
`drift=n/a`. The normalizer travels as **reuse-by-copy** (ADR 0003 no-cross-reference), and
every copy's conformance to this one contract is pinned by the golden vectors in the
governance-state-validator self-test, not by a shared import. The 16-hex canonical width is
deliberately **not** unified with psa.py PSA8001's 12-hex relative-comparison hash. The
validator's read-side **check G** recomputes and compares each marker hash (and check D
verifies marker `policy`/`binding` against the manifest); the write side is the
`quality-tools/canon-hash-restamp/` tool (metadata-only; never a code change). Until the
ADR 0011 CRUD tool (P3a), edits to `manifest.jsonl` or a canonical marker MUST pass the
validator (including G) at the §Y dry-run, before the patch is cut — verification-before-patch
is the interim metadata guardrail, with tool-mediated writes as the complement.

Governed by [ADR 0015](./adr/0015-canonical-normalized-hash-contract.md) (canonical
normalized-hash contract: the computable normalization + sha256/16-hex definition promoted
from baseline §4.5; read-side check G; the write-side re-stamp tool; and the interim
metadata guardrail bridging to the ADR 0011 CRUD tool).

### Scanner output-contract pins

The P3 consumer-drift scanner's sole output contract is `observation.schema.json`. Three of its
required fields are fixed here so the contract is uniquely determined before any scanner code.
**(1) `runtime.duckdb`** is a stamped per-run fact (baseline §3, "stamp not pin"); a scanner that
does not use DuckDB stamps **`"n/a"`** (DuckDB is P8-only, ADR 0002), replaced by the resolved
version at P8. **(2) `granularity`** is **derived from `kind`** (the manifest carries no
`granularity` field; `kind` is the single source): `powershell-helper` / `bash-region` /
`spec-region` → **`region`** (inlined marked region → normalized-hash body-drift, ADR 0015);
`python-helper` / `python-tool` / `tool` → **`whole-tool`** (import or whole-tool machinery — no
inlined body; whole-tool null convention, baseline §4.4); `governance-doc` is **out of this
scanner's body-hash-drift scope** (class-(B) rendered docs carry no per-file hash/marker — ADR
0014 §2 — and are governed by the document-conformance gate, not this scanner). The split is
import-vs-inline, not language. **(3) `drift=unknown`** is the determinability fallback — emitted
for a `region` instance the scanner located but could not resolve to a comparison result (so it
never crashes or emits an out-of-enum value); its precise trigger conditions are pinned at P6,
when real consumer scanning first exercises the paths.

Governed by [ADR 0016](./adr/0016-scanner-output-contract-pins.md) (scanner output-contract
pins: `runtime.duckdb="n/a"` pre-P8; the `kind`→`granularity` derivation table; and the
`drift=unknown` determinability fallback, framed now / detailed at P6).

## Execution framework

Execution is **outcome-based**: each phase is value-anchored (value → entry/exit → gate),
filled with a per-step schema, dry-run self-checked, and human-signed-off before
execution — nothing executes before its sign-off. Work is ordered by a **priority
taxonomy** (must-fix > should > nice-to-fix). A **safety carve-out** is never deferred or
self-accepted: deletes require a zero-referrer grep plus a human checkpoint; Layer-0 and
cross-repo edits require explicit authorization; gate-criterion deviations escalate to the
user.

Governed by [ADR 0004](./adr/0004-outcome-based-execution-framework.md).

Within that framework, the **review order** is fixed (the epistemic-order complement to the
gating above): for any new finding or design question, verify **structural validity inside
the normative set first** (a), then investigate the **current artifacts second** (b) — the
artifacts fill a correct structure, they do not define it; structural correctness sits above the
artifact. On each new finding, re-scan the governance md/ADRs, run a full forward/back impact
analysis, and split now-decisions from items deferrable until implementation/the artifacts are visible
(naming, for each deferral, what to decide and how to investigate it).

Governed by [ADR 0017](./adr/0017-structure-first-review-methodology.md).
