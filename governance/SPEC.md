# governance/SPEC.md — Governance current-truth (cross-cutting)

<!-- AI read-contract: This is the current-truth view of cross-cutting governance
     decisions. Read THIS for what is true now; consult the governing ADR only for
     rationale and history. Never reconstruct current truth by replaying ADRs. -->

> **Scope.** Family-independent, cross-cutting governance only. Family-specific specs
> live in `governance/spec/<family>.md`; subproject specs in
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
frozen copy was **deleted at psaMove (2026-07-03)** after the cross-repo
zero-LIVE-referrer precondition held — history remains reachable via
`git log --follow` from the governed home; consumers repointed and follow-latest
since the `projects/` migration), and
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

### Whole-tool registration convention

A whole-tool machinery unit (`kind=tool`: psa.py, the canonical-drift-scanner, the
canon-manifest-tool, the canon-drift-trigger, the document-conformance-gate) is registered in
`manifest.jsonl` by filling the region-helper `required` fields with **sentinel values** that carry
no region meaning: `change_policy=canonical`, `binding_mode=follow-latest`,
`platform_scope=cross-platform`, `canonical_version` = **the tool's own SemVer** (e.g. `1.0.0` for
the four reference-code-adjacent tools, `4.3.0` for psa.py), and `tested=true` once the tool's
**own self-test** passes - re-defined for whole-tool to mean self-test green, not the ADR 0007 canon
behavioral suite. The region/hash fields are an **observation**-side concern (the whole-tool null
convention, ADR 0016), not manifest fields, so no manifest null allowance is needed. A whole-tool's
`canonical_version` is **not** a release-gate signal: the ADR 0008 vendoring gate
(`version >= 1.0.0`) does not apply to whole-tool units, which are run-as-is / follow-latest and are
never vendored (only the `reference-code/` region canon is). `platform_scope` is `cross-platform`
for every whole-tool to date (pure-Python, stdlib-only); `windows-enhanced` / `windows-only` stay
defined for honest future classification (mirroring ADR 0013 on the code side), to be exercised by a
future Windows-bound tool.

Governed by [ADR 0021](./adr/0021-whole-tool-registration-convention.md) (whole-tool registration
convention: sentinel values for the region-helper required fields on a `kind=tool` row; `tested`
re-defined as self-test-green for whole-tool; the ADR 0008 vendoring gate does not apply to
whole-tool units; rule-of-two met by psa.py as the SemVer-heterogeneous second instance).

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

### Doc-region normalized-hash contract

The code contract above governs `.ps1` / reference-code regions. **Documentation** regions (the
spec home and the doc-set templates) are governed by a parallel, distinct contract. The
doc-region `hash=` is computed by: take the region body (between the `>>> CANONICAL` and
`<<< CANONICAL` lines), **drop HTML comments** (`<!-- ... -->` - authoring notes, `FILL`, and
`ASSEMBLE` directives, never rendered content), collapse all whitespace runs to one space and
strip (the same whitespace convention as the code hash), then `sha256(normalized)` truncated to
**16 hex**. This hash is defined only for the **verbatim-canonical** content models -
`common-fixed` and `vendored`. `common-parameterized`, `specific`, and `mixed` regions are
**not** hash-pinned: their marker carries `policy=structural` + `hash=NONE`, and they are
verified structurally (region present, `unit_id` resolves to a real L1 doc-format item, marker
coherence, non-empty body). Marker `unit_id`s map to L1 items by stripping the family segment
(`spec.powershell.part-a.X` → `spec.part-a.X`).

All doc-region inspection - marker coherence, the verbatim-canonical hash stamp + verify, the
structural checks, the doc-level YAML front-matter provenance pin (ADR 0019), and L1
item-membership - is owned by the **`quality-tools/document-conformance-gate/`** tool (`--check`
to verify, `--stamp` to write `PENDING` → real hash / structural sentinel). The split from the
code side is firm: the governance-state validator's checks D / G and `canon-hash-restamp` stay
scoped to `powershell-helper` / reference-code and are **never** extended to markdown.

Governed by [ADR 0020](./adr/0020-doc-region-normalized-hash-contract.md) (doc-region
normalized-hash contract + document-conformance gate boundary), complementing ADR 0015 (code
hash) and [ADR 0019](./adr/0019-document-vendor-model-and-provenance-embedding.md) (document
vendor model).

### Doc-region version coupling

For a **HASH-model** doc-region (`common-fixed` / `vendored`) whose marker `unit_id` resolves
by longest dotted prefix to a manifest doc-region unit (`spec-region`; e.g.
`spec.powershell.part-a.logging` → the row `spec.powershell.part-a`), the document-conformance
gate's **check C9** couples the marker `version=` to the manifest `canonical_version`:
`binding=follow-latest` requires **equality**; `binding=pin` may **lag but never lead**
(SemVer comparison; the pin branch is encoded although no doc-region uses it today). Markers
with no registered manifest prefix (template-internal L1 markers) and structural-model regions
are out of scope. C9 runs in both the default (manifest) mode and `--path` mode, so the spec
homes **and** the consumers' vendored copies are covered; it degrades to a no-op when no
manifest exists at the root. Consequence: a manifest-only spec-region version write fails the
gate battery — the write-time refusal (doc_gate as a subprocess gate of the coupled
manifest+marker write) belongs to the deferred `unit-record coupled write`.

Governed by [ADR 0022](./adr/0022-doc-region-version-coupling-gate.md) (doc-region
version-coupling gate; records and closes the proven 2026-06-11 spec-region promotion hole).

### Reference-health gate

`quality-tools/reference-health-gate/refcheck.py` (whole-tool, stdlib-only, offline) owns
**Layer-0 reference integrity** — the plane no other gate covers (doc_gate owns
manifest-registered md units and consumer doc-sets; the validator and scanner own
reference-code). Scope: the repo-root `*.md` files + `.github/*.md` only. Checks: **R1**
relative Markdown link/image targets exist (fragments stripped; absolute links out of
scope); **R2** every referenced GitHub Actions workflow filename (repo paths and
`actions/workflows/` badge URLs, offline-decidable by filename) exists under
`.github/workflows/`; **R5** the row-count claims inside STATUS.md's two current-truth
zones (the `| Current phase |` table row and the `Gates green` paragraph) equal the actual
`manifest.jsonl` count — the machine probe for the index==body divergence class.
Authoring constraint (prose-shape rule): a hypothetical, non-existent-by-design workflow
is never written as a contiguous `.github/workflows/<name>.yml` path. Scope claims,
limitations, and the full gate inventory live in `governance/gate-coverage.md`.

Governed by [ADR 0026](./adr/0026-reference-health-gate.md) (reference-health gate;
Layer-0 scope, R1/R2/R5 check set, gate-then-fix closure of the 2026-07-03 residue).

### Decision gate + AI-driven trigger

`quality-tools/canon-drift-trigger/trigger.py` (1.1.0) implements ADR 0011 §3-AI/§4
end-to-end: **`impact --unit-id <id>`** = the machine-measured consumer blast radius
(manifest `consumers[]` + marker placements over both frames — never estimated);
**`propose`** = the AI/human reconcile-back trigger emitting ONE decision-gated change
request; the machine drift path attaches a computed-impact decision block with
`kind=null` (`pending-decision`). Tier rules (confirmed at P7a.1 against the realized
topology): patch→trivial, minor→medium, major→**heavy** — heavy is REFUSED without
enumerated consumers + a migration plan + a full-ADR reference. Approval act = `[AUTH]`
+ the Git commit; emit-only, **no new state store** (the proposals ledger is P8's).
Change-request contract **pinned**: `request_version 1.0.0` / `contract_status
pinned-P7a`. Series order is normative: trigger → decision gate → quality gates →
CRUD/coupled write → commit + CHANGELOG.

Governed by [ADR 0027](./adr/0027-decision-gate-and-ai-trigger-implementation.md)
(decision gate + AI trigger: tier confirmation, machine impact, contract pinning,
heavy-path refusal semantics).

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

### Project-lifecycle maturity model

Every project under `projects/` carries one lifecycle stage — **`sandbox` → `incubating` →
`governed`**, plus terminal **`archived`** — recorded as a `kind=project` manifest row
(`unit_id = project.<dir>`, `canonical_location = projects/<dir>`, `maturity`; the region-unit
fields are absent by contract via the schema's allOf branch, and the CRUD tool enforces the
same shape). The axis applies at **project/tool granularity only**; asset-level release
readiness stays SemVer (ADR 0008/0018). Obligations accumulate by stage: **sandbox** (no
manifest row yet) owes only the birth-kit — template-canon doc-set + provenance pins, AI
disclaimer + language policy, encoding + syntax gates; **incubating** (registered at the
user's continue/publish decision) adds the manifest lifecycle record, STATUS tracking, full
static analysis, doc_gate battery membership and bilingual lock-step enforcement;
**governed** (reached by a B2-style conformance pass) adds vendored Part A where a family
spec home exists, `consumers[]`, offline tests + CI, and the per-phase loop for
governance-relevant changes. **Graduation (separate-repo spin-out) stays a distinct physical
event, orthogonal to maturity, prerequisite `maturity=governed`.** The stage label
`governed` is an explicit ADR 0024 supersession of the TF.1 `graduated` domain pin; the four
live projects are registered `maturity=governed` retroactively. Bootstrap procedure:
AGENTS.md §10 + `governance/templates/scaffold-project-bootstrap-prompt.template.md`.

Governed by [ADR 0024](./adr/0024-project-lifecycle-maturity-model.md) (project-lifecycle
maturity model; stage × obligation table, promotion triggers, the kind=project lifecycle
record).

### Exploration/RE mode

Empirical exploration (probes, reverse engineering, spikes) runs in an official
light-discipline lane: the **default discipline of a sandbox-stage project**, and a
**declarable, time-boxed mode inside an incubating/governed project** (an `[EXPLORATION]`
CHANGELOG entry stating scope, goal, timebox; working artifacts quarantined until exit). In
the mode the per-phase loop is not applied and only the always-on sandbox gates run; the
**hard boundary** is that canon bodies, vendored regions, `governance/`, and Layer-0 root
docs are untouchable from inside the mode — a discovered canon/governance need exits into
the normal `[AUTH]` loop. Genchi-genbutsu narrative may stay in Tier-P notes (ADR 0005); the
SPEC carries the distilled stable contract. **Exit is a conformance pass** (the ADR 0024
promotion triggers, or folding a spike's keepers through the project's full gates).
By-products: knowledge → `documents/research/<topic>/`; runnable tools/scripts → a new
`projects/` entry at sandbox stage (frozen-evidence one-shots may stay as marked research
adjuncts; when in doubt, `projects/` sandbox).

Governed by [ADR 0025](./adr/0025-exploration-mode.md) (exploration/RE mode; entry forms,
light gates, hard boundary, exit criteria, by-product homing).
