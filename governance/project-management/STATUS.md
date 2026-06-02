# STATUS — Execution Truth & Handoff

> **Tier-M (in-repo PM layer, M7).** Single living current-truth view + session handoff.
> Bounded (R1): current state only — git history is the audit trail. Scrubbed (R2): no
> secrets/credentials/client data. References, does not restate (R3): the design substrate
> lives in the Tier-P handoff docs (baseline / plan / spine / register) and in `../adr/`.
> Decisions are durable in `../adr/`; this file tracks *status*, not decisions.
> **Session entry point** — read first per the AGENTS.md startup contract. Handoff rule:
> **ADR 0005**. Tier-P design docs stay **unmanaged** (out of repo) and ship as one bundle
> + MANIFEST at each static-point (never piecemeal).

_Last updated: 2026-06-02 (UTC) — **ADR 0016 (scanner output-contract pins) accepted; P3.1 complete**. A documents-only structural review (before any scanner code) found three observation-schema fields the prior normative set did not uniquely determine, and pinned them: **F1** `runtime.duckdb = "n/a"` pre-P8 (DuckDB is P8-only, ADR 0002; runtime is stamped not pinned); **F3** the `kind`→`granularity` derivation table in SPEC §machinery (manifest carries no `granularity`; `kind` is the source — powershell-helper/bash-region/spec-region→region, python-helper/python-tool/tool→whole-tool, governance-doc out of body-hash-drift scope per ADR 0014); **F4** `drift=unknown` framed as the determinability fallback (precise conditions pinned at P6). Schema gained description-only annotations (no structure change). Also clarified (no decision): **P3 builds + fixture-tests the scanner; its first real run is P6** (consumers carry no markers until vendoring). Prior: ADR 0015 / P3.0 (hash-contract pin); P2a complete (canon released 1.0.0)._

---

## Current phase

| Field | Value |
|:---|:---|
| Just completed | **ADR 0016 — scanner output-contract pins (P3.1)**: a documents-only structural review pinned three observation-schema fields the prior set left undetermined — **F1** `runtime.duckdb="n/a"` pre-P8; **F3** the `kind`→`granularity` table (SPEC §machinery); **F4** `drift=unknown` = determinability fallback (detail at P6). Description-only schema annotations; no structure/code/canon change. *(Prior: **ADR 0015 / P3.0** hash-contract pin; **P2a** — canon released 1.0.0.)* |
| Current phase | **In P3; P3.0 + P3.1 complete** — the hash contract (ADR 0015) and the scanner output-contract pins (ADR 0016) are both fixed, so the scanner's sole contract is uniquely determined. Next: **P3.2+ — build the scanner** (`quality-tools/canonical-drift-scanner/`; reuse-by-copies the ADR 0015 normalizer, passes GV-1..5, derives `granularity` per ADR 0016, stamps `duckdb="n/a"`; **built + fixture-tested at P3, first real run at P6**), then **P3a** (manifest CRUD tool — direct manifest/marker edits then stop and the interim guardrail is superseded) |
| Operating loop | per phase: fill per-step schema → dry-run §Y → sign-off §Z → execute (Path 2) |

## Phase progress

| Phase | Status | Notes |
|:--|:--|:--|
| **P0a — Foundation** | ✅ done | scaffold (`governance/ quality-tools/ reference-code/ projects/`), gates, `documents/` consolidation (#19), substrate ADRs, this tracker |
| **psaMove.1** (expand: copy) | ✅ done | byte-identical copy → `quality-tools/powershell-static-analyzer/`; old path coexists |
| **psaMove.2** (expand: migrate/rename) `[AUTH]` | ✅ done | 26 central refs → new path; path-encoding CI workflow renamed; `.ps1` BOM+CRLF preserved; only the 5 old-dir self-refs remain (deleted at psaMove.5, post-P7) |
| **P1.1** — A-4 `@import` gate | ✅ verified | thin `CLAUDE.md` can `@import AGENTS.md` (official Claude Code memory docs); supported as assumed, no deviation; caveats: import is inline (no token saving) + advisory (P1 ships no contract-CI — ADR 0006; wiring stays advisory). See plan P1.1 [VERIFIED] |
| **P1.2–P1.6** — governance model | ✅ done | P1.2 AGENTS.md startup contract (§3) `[AUTH]` · P1.3 thin `CLAUDE.md` `@import` · P1.4 prompt templates (`governance/templates/`) · P1.5 **ADR 0006** (single AGENTS.md source; **no contract-CI at P1**, M2 amends P1 exit) · P1.6 **`governance/SPEC.md`** authored + ADR 0001–0004↔SPEC back-refs closed |
| **P2.1–P2.3** — analyze + classify | ✅ done | inventory of shared functions across 6 consumers; reconcile (consistent + 9 drift, all dispositioned); **39 canonical units** classified (`canonical`/region/follow-latest) + field-ownership map + marker final form |
| **P2.4–P2.5** — schemas | ✅ done | `governance/schema/` `manifest.schema.json` + `observation.schema.json` (draft-07) + `field-ownership.md` |
| **ADR 0007 / P2a insert** — canon functional QA | ✅ done | mandatory full-set canon tests, canon-vs-copy fault attribution, regression-gated reconcile-back; **phase P2a inserted** to author the suite (governs `SPEC §machinery`) |
| **P2.6 (+amend)** — canon code home | ✅ done | `reference-code/powershell/` 39 Public + 19 Private + `.psm1`/`.psd1`; per-unit markers + norm hash; analyzer config (`.psa.config.json` [PSAP0003/4/5] + `PSScriptAnalyzerSettings.psd1`); marker version = **SemVer** (rNN→0.1.0); full config-aware gate 0/0/0 |
| **ADR 0008** — canon release model | ✅ done | SemVer pre-release guardrail: `0.x` not vendorable; promote to `1.0.0` on full-suite pass; vendoring gate `version >= 1.0.0`; refines ADR 0007 |
| **P2.7** — manifest | ✅ done | `governance/state/manifest.jsonl` 58 rows (`canonical_version 0.1.0`, `tested=false`, `consumers=[]`); `tested` added to manifest schema (`maturity` **deferred to TF** — baseline §2.10 CNCF axis, values open until final stage) |
| **P2.8a** — governance-state gate | ✅ done | `quality-tools/governance-state-validator/` (checks A–F: schema · location · manifest↔marker · canon coverage · canonical-JSON); 0 findings on repo, self-test 6/6 |
| **P2.8b** — STATUS + gate clause | ✅ done | STATUS brought current (`10f513d`); AGENTS.md post-flight §14 = governance-state gate |
| **P2 close** — defer manifest maturity | ✅ done | `867efe3`: `maturity` removed from manifest schema/jsonl (deferred to TF — baseline §2.10 CNCF axis); release-readiness via `tested` + SemVer `version` (ADR 0008). P2 closed here |
| **ADR 0009** — psa.py canonical lifecycle | ✅ done | `964752c` `[AUTH]`: psa.py 4.3.0 (`psa2013_known_script_vars`); the `scripts/python/...` psa.py copy frozen at 4.2.0; canon back to 0/0/0 |
| **P2a-prep / Pgov-charter** — ADR 0010/0011 | ✅ done | `56c3dae` **ADR 0010** (canon test taxonomy + JSONL/DuckDB data management); `7027b16` **ADR 0011** (canon change-management governance: manifest = Git-resident master, tool-mediated CRUD [P3a], one process, impact-weighted decision gate, audit trail) + SPEC Machinery back-refs |
| **P2a.1** — canon test home | ✅ done | `98119ed`: `reference-code/powershell/tests/` harness + `CanonSessionState` fixture + Smoke tests + `common/`; governance-state validator check E corrected disk-master → **manifest-master** (ADR 0011 §1; tests/ never flagged), self-test 7/7 |
| **P2a.2** — behavioral suite (58 units) | ✅ done | `879a0da` U0/U1/U2 (41 Pester) + `f38057a` F-state/F-env (Canon.Env). **ADR 0012** (`a3add27` dual-runtime env-info: CLRVersion → `[System.Environment]::Version`, BuildVersion `.ContainsKey` guard) + **ADR 0013** (`3e96cf3` multi-platform/version QA: 3-cell PSScriptAnalyzer compat matrix + per-unit `platform_scope` + classification-backed suppression + FrameworkDescription removal). Real-host verified on PS 5.1 (`4.0.30319.42000`) + PS 7 Linux (`8.0.10`) |
| **P2a.3a** — canon-test gate runner | ✅ done | `ae73339`: `tests/Invoke-CanonTests.ps1` single entry (Pester Unit/Env/Smoke + T11) → **71 passed / 1 skipped / 0 failed, PASS**; canon-resident (vendored with canon); `psa2010_known_cmdlets` for Pester cmdlets |
| **P2a.3b** — SemVer promotion 1.0.0 | ✅ done | `30b67f1`: all 58 units `canonical_version 0.1.0 → 1.0.0` + `tested true`; markers `version=1.0.0` (hash byte-identical); `.psd1` ModuleVersion 1.0.0. **Canon released, vendorable** (ADR 0008 §4: version ≥ 1.0.0) |
| **P2a.4** — close P2a (STATUS) | ✅ done | STATUS brought current to canon 1.0.0 / P2a complete; next phase P3 |
| **ADR 0014** — document governance model | ✅ done | `8249f2e` `[AUTH]` (doc-only): the DOCUMENT analog of ADR 0007+0008. Three cross-repo doc classes (A reference / B own-and-reconstruct / C vendored-copy); `governance/templates/` = document-template canon at code parity (`kind=template` + SemVer release gate + conformance gate over rendered doc-sets); class-(B) reconstruction = graduation structural transform; every reconstruction/sync = a quality gate. **No new phase / no renumbering** (TF + P4–P7 exits absorb it). governs `SPEC §machinery` (bidirectional back-ref). Instance-level wiring deferred to TF.1 |
| **P3.0 / ADR 0015** — canonical normalized-hash contract (P3 opening) | ✅ done | promoted baseline §4.5 → in-repo SPEC §machinery as a **computable** contract (region body → strip comments/strings → collapse whitespace → `sha256`/**16-hex**; gate=normalized, raw=forensic, forked=frozen, whole-tool=null/`n/a`). Validator **check G** (recompute marker hash) + **check D** extended (marker `policy`/`binding` vs manifest); **`quality-tools/canon-hash-restamp/`** write-side tool (metadata-only); conformance pinned by **golden vectors GV-1..5** (no shared import; ADR 0003 reuse-by-copy). Check G caught **20/58 markers mis-stamped at `5d5f0b1`** → re-stamped **no version bump** (bodies byte-identical). Validator self-test **15/15**. Interim **metadata guardrail**: validator (incl. G) green at §Y before patch; bridges to ADR 0011 CRUD tool (P3a) |
| **P3.1 / ADR 0016** — scanner output-contract pins | ✅ done | documents-only structural review (no scanner code yet) pinned 3 undetermined observation-schema fields: **F1** `runtime.duckdb="n/a"` pre-P8 (ADR 0002; runtime stamped not pinned); **F3** `kind`→`granularity` table in SPEC §machinery (manifest has no `granularity`; powershell-helper/bash-region/spec-region→region, python-helper/python-tool/tool→whole-tool, governance-doc out of body-hash-drift scope per ADR 0014); **F4** `drift=unknown` = determinability fallback (conditions pinned at P6). Description-only schema annotations; no structure/code/canon change. Clarified (no decision): **P3 builds+fixture-tests; first real run P6** |

Gates green at HEAD: psa.py 0 (config-aware, incl. the `reference-code/powershell` canon + the canon-test runner via `psa2010_known_cmdlets`) · PSScriptAnalyzer 0/0/0 (standard + the ADR 0013 3-cell compatibility matrix, Public/Private) · governance-state-validator **0 findings (A–G)** (58 manifest rows ↔ 58 canon files; **check G** marker-hash integrity + check D marker `policy`/`binding`; self-test **15/15**) · **canon-test runner PASS (71/1-skip/0)** · **`canon-hash-restamp --check` IN SYNC (58/58)**. Runtimes: pwsh 7.4.6 · PSScriptAnalyzer 1.25.0 · python3 · jsonschema 4.26.0 · Pester 5.7.1.

## Next action
**P3.0 + P3.1 complete** — the hash contract (ADR 0015) and the scanner output-contract pins
(ADR 0016) are both fixed, so `observation.schema.json` is uniquely determined for every
required field. Proceed to **P3.2+ — build the scanner** (`quality-tools/canonical-drift-scanner/`,
single-file, stdlib-only, schema-first): reuse-by-copy the ADR 0015 normalizer (passes
GV-1..5), derive `granularity` per the ADR 0016 `kind`-map, stamp `runtime.duckdb="n/a"`,
reserve `drift=unknown` as the fallback. **It is built and fixture-tested at P3 (P3.7 gate);
its first real run is P6** (consumers carry no vendored markers until then — manifest
`consumers[]` is empty; the (あ) current-state/operational review of the consumers belongs to
that P6 exercise, not P3). It emits `observation.schema.json` records feeding the **ADR 0011**
reconcile-back process. **P3a** then builds the manifest CRUD tool — after which direct
manifest/marker edits stop and the **interim metadata guardrail (ADR 0015 §6) is superseded**.
Vendoring (P6/P7) is UNBLOCKED (canon ≥ 1.0.0) but later. Remediate `$ks` at **P6**.

## Open pointers
- `[WORKING]` psa.py move **CONTRACT** (psaMove.4/.5 — delete the old `scripts/python/powershell-static-analyzer/` path) is **after P7**, gated on a cross-repo zero-referrer grep + §9.3 checkpoint. Both paths coexist until then.
- `[WORKING]` `Deploy-Drivers` 8 references to the old psa path are migrated in **P7** (single PR).
- `[WORKING]` Subproject migration `scripts/<family>/<name>/ → projects/<lang>-<name>/` is **P5/P6**; `reference-code/powershell/` is **released at 1.0.0 (P2a.3b)** — 58 units, full config-aware gate + compatibility matrix + governance-state gate + canon-test runner all green; **vendorable** (ADR 0008 §4); bash/python canon homes still **deferred** (SPINE-2/5; policies decided).
- `[WORKING]` Governance docs for psa.py at its new home = **P4**; template finalization (TF) = before **P5**. **[ADR 0014]** TF now also freezes the **document-conformance gate** + the **class-(B) reconstruction procedure** + `kind=template` registration/version gate (the document side at code parity); `governance/templates/` is the document-template canon.
- Known gate deviation: `Update-WindowsServerIso.ps1` PSScriptAnalyzer `0/1/0` (`$ks`) — user-dispositioned, remediate at **P6**. **[ADR 0014 §4]** locate it by **symbol/context, not a fixed line number** (the script evolves; the line drifts), as part of the P6 conformance pass (§8.3; not accepted-open).
- `[WORKING]` **Interim metadata guardrail (ADR 0015 §6):** until the ADR 0011 CRUD tool (P3a), any edit to `manifest.jsonl` or a canonical marker must pass the governance-state validator (incl. **check G**) at the **§Y dry-run, before `git format-patch`** — verification-before-patch. Tool-mediated writes are the complement: marker hashes via **`quality-tools/canon-hash-restamp/`** now; the CRUD tool at P3a. Superseded by the CRUD tool.
- **ADR 0006:** P1 ships **no contract-CI** (governance-loading wiring is advisory, not CI-enforced). Revisit at **P5/P6** when file moves raise the regression risk — add the contract check then via a new ADR if warranted.
- `[WORKING]` **PSAP0005 default-on** in `psa.py` is a **roadmap** item (psa.py rule-default change + tests + version bump). Canon markers already use a SemVer `version=` (non-rNN), so they stay PSAP0005-clean when it flips on.
- The PowerShell gate (AGENTS.md **§9**) is now the **full config-aware gate** (psa.py config-aware + PSScriptAnalyzer + pwsh ParseFile + import/tests; stand up runtime per baseline §8.2; "no pwsh/deferred" = deviation, M4(A)); the **governance-state gate** (AGENTS.md **§14**) covers `governance/state` + `governance/schema` via the validator (P2.8a).

## ADR index (`../adr/`)
- 0001 — tooling language = Python · 0002 — analysis layer = DuckDB (disposable, P8) · 0003 — standalone-tool principle · 0004 — outcome-based execution framework (M8) · 0005 — session-handoff protocol · 0006 — AI-agent config coverage & contract-CI scope · **0007 — canon code functional QA** (P2a) · **0008 — canon release model** (SemVer pre-release guardrail; refines 0007) · **0009 — psa.py canonical lifecycle** (single canonical psa.py at `quality-tools/`; `scripts/` copy frozen) · **0010 — canon test taxonomy + data management** (test buckets; JSONL master + DuckDB ephemeral) · **0011 — canon change-management governance** (manifest = Git-resident master, tool-mediated CRUD, one process, impact-weighted decision gate, audit trail) · **0012 — dual-runtime env-info policy** (equivalent-quality info on PS 5.1 + 7.x) · **0013 — multi-platform / multi-version QA** (3-cell compat matrix + per-unit `platform_scope` + classification-backed suppression) · **0014 — document governance model** (cross-repo doc classes A/B/C; `governance/templates/` = document-template canon at code parity with version + conformance gate; class-(B) reconstruction incl. the graduation structural transform; every reconstruction/sync = a quality gate; the DOCUMENT analog of ADR 0007+0008; no new phase, TF + P4–P7 exits absorb it) · **0015 — canonical normalized-hash contract** (the computable hash definition promoted from baseline §4.5: region body → strip comments/strings → collapse whitespace → `sha256`/16-hex; validator read-side **check G** + marker `policy`/`binding` check; write-side `canon-hash-restamp` tool; golden-vector conformance; interim metadata guardrail bridging to the ADR 0011 CRUD tool; corrected 20 markers mis-stamped at `5d5f0b1`, no version bump). · **0016 — scanner output-contract pins** (P3.1; documents-only structural review: `runtime.duckdb="n/a"` pre-P8 [F1], the `kind`→`granularity` derivation table in SPEC §machinery [F3], and `drift=unknown` as the determinability fallback framed now / detailed at P6 [F4]; description-only schema annotations; no structure/code change).
- Cross-cutting current-truth view: **`../SPEC.md`** — §tooling/§analysis-layer/§machinery/§execution-framework ← ADR 0001–0004; **§machinery also ← ADR 0007/0008/0011/0012/0013/0014** (bidirectional `governs`↔back-ref).

## Design substrate (Tier-P handoff — referenced, not restated, R3)
- `HANDOFF-baseline-consolidated-design.md` — the living design baseline.
- `IMPLEMENTATION-PLAN-skeleton.md` — the living implementation plan (§0.1 disciplines, §Y dry-run incl. Y.1 P0a + Y.5 psaMove, §Z sign-off).
- `TRACEABILITY-SPINE.md` — outcome→deliverable→producer→dependency→gate spine (orphans = 0).
- `TEMPLATE-REQUIREMENTS-REGISTER.md` — Tier-P template/dotfile requirements register.

_Per **ADR 0005**: the four Tier-P docs stay **unmanaged** (out of repo) and are delivered as **one bundle (zip) + MANIFEST** at each static-point — never piecemeal, never assume a current local copy._

## Static-point index (recoverable points = commits; repo-external Zips per `../static-point-procedure.md`)
| Phase | Commit | Static-point |
|:--|:--|:--|
| P0a | `5490de3` (+ `de39ef9` cleanup) | per procedure (repo-external Zip) |
| psaMove.1 | `f289933` | per procedure |
| psaMove.2 | `f8b942b` | per procedure |
| P1 (governance model) | `1097309`·`dd8f9f3`·`cab8375`·`9a05635`·`9be1056` | per procedure (repo-external Zip at P1 phase-end) |
| P2 (analyze + canon + manifest + gate) | `597638e` … `867efe3` | _repo-external Zip at P2 phase-end_ |
| P2a (canon test suite + release 1.0.0) | `964752c` … `30b67f1` | _repo-external Zip at P2a phase-end (this phase)_ |
