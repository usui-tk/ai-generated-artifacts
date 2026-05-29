# TESTING.md — Verification Procedure and Real-Run Results

This document consolidates everything needed to verify and evaluate
`Update-WindowsServerIso.ps1`. It covers six areas:

1. **Static analysis** — `psa.py` gate (must pass before every commit)
2. **Synthetic smoke tests** — read-only Actions executable in CI
3. **Live Catalogue verification** — probes that catch Microsoft-side schema drift
4. **Operator-pending verification** — full `-Execute` builds (requires Windows + ADK + ≥ 100 GB disk + admin)
5. **Self-verification tool suite** — T1 through T19 (canonical inventory in [`tests/README.md`](./tests/README.md))
6. **Continuous integration** — four GitHub Actions stages

> **Documentation language policy**: This document is maintained in
> English only per the repository-wide policy. See `README.md` and
> `README.ja.md` for the bilingual entry-point documentation; for the
> repository-wide language policy see the root [`README.md`](../../../README.md)
> "Language Policy" section.

---

## Table of Contents

- [0. Verification status summary](#0-verification-status-summary)
- [1. Static analysis gate](#1-static-analysis-gate)
- [2. Synthetic smoke tests](#2-synthetic-smoke-tests)
- [3. Live Catalogue verification](#3-live-catalogue-verification)
- [4. Operator-pending: real ISO integration](#4-operator-pending-real-iso-integration)
- [5. Self-verification tool suite (T1 – T19)](#5-self-verification-tool-suite-t1--t19)
- [6. Continuous integration coverage](#6-continuous-integration-coverage)
- [7. Discovered bugs and fix history](#7-discovered-bugs-and-fix-history)

---

## 0. Verification status summary

The "Last verified" column uses the canonical sibling-project format:
a build identifier plus a calendar date. Pending items are marked
`_pending operator confirmation_`.

| Item | Status | Last verified |
|---|---|---|
| `psa.py` (latest mainline; with project `.psa.config.json`) on `Update-WindowsServerIso.ps1` | **0 errors / 0 warnings / 0 info** ✓ | r11.1 cross-repo-canon-iso-encoding-tls-rename build (`psa.py` 4.2.0; re-verified) / 2026-05-29 |
| File encoding (UTF-8 with BOM, CRLF line endings, ASCII-only outside literals) | ✓ for the main script | r11.1 cross-repo-canon-iso-encoding-tls-rename build / 2026-05-29 |
| `PSAP0005` strict-mode baseline (no stale `rNN` references in comment bodies) | **0 findings** ✓ | r11.1 cross-repo-canon-iso-encoding-tls-rename build / 2026-05-29 |
| PSScriptAnalyzer on Windows PowerShell 5.1 (Stage 2) | ✓ pass | CI Stage 2 (continuous) |
| P01 Initialize — PowerShell env / admin / ADK / disk / Hyper-V probe | ✓ pass on Windows 11 + PS 5.1 | _pending operator confirmation_ |
| P02 ResolveInputs — Config JSON load + ISO / patch source resolution | ✓ structurally validated via T3 harness | r09.0 step2b3-real-data-parser-correction build / 2026-05-28 |
| P03 RefreshPatchBaseline — Catalogue scrape (live, monthly) | ✓ scrape paths exercised via T1 | CI Stage 4 monthly |
| P04 FetchAssets — ISO + patch downloads with SHA-256 verify | _pending operator confirmation_ | not yet exercised on a fresh runner |
| P05 ExpandIso — source ISO mount + WIM enumeration | _pending operator confirmation_ | r09.0 step2b3-real-data-parser-correction build (synthetic mode only) |
| P06 ValidatePatchSet — `wsusscn2.cab` offline scan (Stage 1 catalog-freshness) | ✓ Stage 1 (catalog freshness) exercised | r09.0 step2b3-real-data-parser-correction build / 2026-05-28 |
| P06 ValidatePatchSet — Stage 2 (graph-based dependency closure, r09.0+) | parser pipeline + Layer 2 JSON + Layer 1 writeback all land in Phase 2b2; dependency-closure walk still pending Phase 2c | r09.0 step2b3-real-data-parser-correction build (A04 implemented; T12 + T13 verified) |
| P07 PatchInstallWim — SSU → LCU → .NET sequence | _pending operator confirmation_ | last successful real run not recorded in this revision |
| P08 PatchBootWim — boot.wim + winre.wim | _pending operator confirmation_ | last successful real run not recorded in this revision |
| P09 AssembleIso — Dynamic Update overlay + `oscdimg` | _pending operator confirmation_ | (requires `oscdimg.exe` on a Windows runner) |
| P10 ConvertPca2023BootManager — PCA2023 conversion (opt-in) | _pending operator confirmation_ | (requires LCU 2024-4B+ source ISO) |
| P11 StaticVerify — output ISO mount + KB-package presence check | _pending operator confirmation_ | (requires P07-P09 success) |
| P12 VerifyPca2023Readiness — `pca2023_readiness.json` + `.md` emission | ✓ structurally validated; runs unconditionally | r09.0 step2b3-real-data-parser-correction build / 2026-05-28 |
| P13 FinalReport — end-of-run summary + ISO hash | _pending operator confirmation_ | (requires P07-P11 success) |
| A01 RefreshAllBaselines — Config baseline regeneration from caches; soft-fail chain into A04 (r09.0 Step 2b2) | ✓ exercised in Stage 4 monthly; A04 chain landed but not yet exercised live | CI Stage 4 / 2026-05-15; r09.0 step2b2 build for chain landing |
| A02 DumpFieldClassification — field-cadence decision matrix emit | ✓ exercised | r09.0 step2b3-real-data-parser-correction build / 2026-05-28 |
| A03 RefreshSnapshots — upstream `data/raw-*` + `data/cache-*` refresh | ✓ exercised in Stage 4 monthly | CI Stage 4 / 2026-05-15 |
| A04 RefreshDependencyDatabase (r09.0 Step 2b2, implemented) — Stages 1-4 chain + Layer 1 writeback (`_DependencyVerifiedUpdateId`/`_DependencyVerifiedRevisionId`/`_DependencyVerifiedCreationDate`/`_DependencyVerifiedAt`); Layer 1 helper verified via T13; Stage 1 live-only | ✓ Layer 1 helper + Stages 3/4 verified offline; Stages 1-2 covered by live monthly CI | r09.0 step2b3-real-data-parser-correction build / 2026-05-28 |
| T1 catalog_probe.py | ✓ live probe passes (~7 checks) | CI Stage 4 / 2026-05-15 |
| T2 catalog_fixture_test.py (13 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T3 powershell_harness.py (10 PS function assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T4 eval_iso_probe.py (4 OS × 2 lang Range-GET) | ✓ live probe passes | CI Stage 4 / 2026-05-15 |
| T5 wsusscn2_probe.py (cab freshness, 60-day warn) | ✓ within 60-day window | CI Stage 4 / 2026-05-15 |
| T6 release_info_parser_test.py (13 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T7 dotnet_cu_parser_test.py (16 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T8 dynamic_update_cache_test.py (20 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T9 catalog_title_tokens_test.py (18 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T10 release_info_resolver_test.py (22 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T11 canonical_json_test.py (26 assertions, PS/Python byte-level parity per SPEC §B.23) | ✓ all pass | r11.1 cross-repo-canon-iso-encoding-tls-rename build (re-verified) / 2026-05-29 |
| T12 wsusscn2_parser_test.py (23 assertions, Stage 3 + Stage 4 self-verification against committed fixture per SPEC §B.19.9.4; includes kbIds-field presence) | ✓ all pass | r11.1 cross-repo-canon-iso-encoding-tls-rename build (re-verified) / 2026-05-29 |
| T13 wsusscn2_layer1_test.py (15 assertions, `Update-Layer1DependencyVerification` writeback contract per SPEC §B.19.9.5) | ✓ all pass | r11.1 cross-repo-canon-iso-encoding-tls-rename build (re-verified) / 2026-05-29 |
| T14 wsusscn2_deny_list_test.py (10 assertions, EOS/ESU deny-list warned-exclusion + allow-overrides in the PowerShell scope filter, matching the `classify_scope` reference; SPEC §B.19.7.1) | ✓ all pass | r11.5 wsusscn2-eos-esu-deny-list-warned-exclusion build / 2026-05-29 |
| T15 wsusscn2_servicing_stack_test.py (16 assertions, `Resolve-WsusScnRevisionToCab` RANGESTART mapping + `Get-WsusScnServicingStackInfo` separate/combined/checkpoint derivation from real-cab CBS metadata; SPEC §B.19.13.0) | ✓ all pass | r11.6 wsusscn2-servicing-stack-extraction build / 2026-05-29 |
| T16 wsusscn2_readiness_verdict_test.py (21 assertions, `Test-PatchServicingReadinessFromGraph` three-check verdict: presence / SS-version-comparison (SsTooOld = 0x800f0823) / supersession, with precedence and Unknown/Available handling; SPEC §B.19.13.1) | ✓ all pass | r11.7 wsusscn2-phase2c-readiness-verdict build / 2026-05-29 |
| T17 wsusscn2_recency_fallback_test.py (15 assertions, recency fallback in `Test-PatchServicingReadinessFromGraph`: out-of-scope KB falls back to newest in-scope LCU per OS family -> Superseded, with family resolution from OsKey and NotInDatabase when no fallback target; SPEC §B.19.7.2) | ✓ all pass | r11.8 wsusscn2-recency-fallback build / 2026-05-29 |
| T18 wsusscn2_servicing_stack_populate_test.py (17 assertions, pure halves of the SS populate: `Select-WsusScnLcuLeafRevision` leaf choice + `Update-WsusScnServicingStackFromMeta` field population from CBS metadata; SPEC §B.19.13.0) | ✓ all pass | r11.10 wsusscn2-servicing-stack-populate build / 2026-05-29 |
| T19 wsusscn2_data_contract_test.py (11 assertions, `Test-DataContractConsistency` status classification Current/Stale/Refuse/Foreign/Unknown + directory expansion + roll-up; committed Layer 2 DB classifies Current; SPEC §B.19.10) | ✓ all pass | r11.10 wsusscn2-servicing-stack-populate build / 2026-05-29 |
| Part C §C.3.4 — `canonical_json_format_check.py` (27 JSON files canonicalised, format gate) | ✓ all pass | r11.1 cross-repo-canon-iso-encoding-tls-rename build (re-verified) / 2026-05-29 |
| Config schema gate — `config_schema_test.py` (14 assertions, `data/config-Server*.json` vs `schema/config.schema.json`; r10.4) | ✓ all pass | r11.1 cross-repo-canon-iso-encoding-tls-rename build (re-verified) / 2026-05-29 |
| Scope-invariants gate — `wsusscn2_scope_invariants_test.py` (23 assertions, EOS/ESU deny-list + allow-overrides over Layer 2 + fixture + synthetic; SPEC §B.19.7/§B.19.7.1) | ✓ all pass | r11.2 wsusscn2-phase2c-eos-esu-scope build / 2026-05-29 |
| Layer 2 schema gate — `wsusscn2_layer2_schema_test.py` (16 assertions, committed `data/wsusscn2-database.json` vs `schema/wsusscn2-database.schema.json` + data-contract identity, portable provenance, kbIds populate, Microsoft-prose hard rule; SPEC §B.19.8/§B.19.10) | ✓ all pass | r11.9 wsusscn2-layer2-kbids-populate build / 2026-05-29 |
| Stage 1 (Linux psa.py + PSScriptAnalyzer + T2/T3/T6-T19 + format gate + config schema gate + scope-invariants gate + Layer 2 schema gate) | ✓ green | CI continuous |
| Stage 2 (Windows PSScriptAnalyzer + parse + read-only smoke) | ✓ green | CI continuous |
| Stage 3 (synthetic full pipeline with ADK install) | ✓ green | CI on push-to-main |
| Stage 4 (monthly baseline refresh + auto-PR) | ✓ green | CI 2026-05-15 (last scheduled run) |

The eleven `_pending operator confirmation_` rows reflect that
`-Execute` pipeline runs against real Microsoft evaluation ISOs are
not part of the automated CI surface (the evaluation licence forbids
public binary distribution; see [`SPEC.md`](./SPEC.md) §B.18 and
repository-level SPEC.md §12). Confirming these requires a Windows
host with Administrator privileges, ADK Deployment Tools installed,
and ≥ 100 GB free on the workspace drive.

---

## 1. Static analysis gate

`psa.py` (latest mainline; rule families `PSA1001` – `PSA9002` plus
opt-in `PSAP0001` – `PSAP0005`) must pass before every commit
(see [SPEC.md](./SPEC.md) Part C). This project opts in to `PSAP0003`,
`PSAP0004`, and `PSAP0005` via [`.psa.config.json`](./.psa.config.json).

### Procedure

From the project directory:

```bash
python3 ../../python/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
```

### Required gate

| Severity | Threshold |
|:---|:---|
| Errors | 0 |
| Warnings | 0 |
| Info | 0 |

Any finding at any severity blocks the commit. The current build
satisfies the gate; verified count: see the §0 row "`psa.py` (latest
mainline)".

### Suppression policy

Project-local suppressions are recorded in [`.psa.config.json`](./.psa.config.json)
with rationale; inline `# psa-disable-line <rule> -- reason` comments
are used only where a suppression is genuinely line-scoped. Both forms
are reviewed at every PR per the repository CONTRIBUTING.md PR checklist.

---

## 2. Synthetic smoke tests

These tests exercise the script's branches that are safe to run in a
Linux + pwsh 7 CI environment (or a Windows runner without ADK), and
form the per-commit gate alongside §1.

### 2.1 ListPhases — read-only inventory dump

```powershell
.\Update-WindowsServerIso.ps1 -Action ListPhases
```

Expected: JSON document on stdout containing the registered Phase and
Action registries. Exits 0. No filesystem writes.

Verification checklist:

- [x] 13 phase IDs P01 – P13 present
- [x] 13 Actions present (Prepare / Build / Verify / PrepareBuildVerify / BootTest / All / Cleanup / ListPhases / GenerateManifest / RefreshSnapshots / RefreshAllBaselines / DumpFieldClassification / TestHarness)
- [x] 3 Admin phases A01 – A03 present
- [x] `RefreshDependencyDatabase` is **not** in the Action list (planned r09.0)

### 2.2 EnvironmentInfoOnly — environment dump and exit

```powershell
.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly
```

Expected: P01 Step 0 banner + P01 Step 1 environment dump. Exits inside
P01; no other phase runs.

Verification checklist:

- [x] PowerShell host detection prints `PowerShell <version>`
- [x] Admin-privilege probe runs and prints `Admin: True/False`
- [x] Disk free-space probe runs against the `-WorkRoot` drive
- [x] No DISM call, no patch download

### 2.3 TestHarness — Python-driven PS function harness (T3)

```bash
python3 tests/powershell_harness.py
```

Expected: 10 assertions pass (PowerShell function-level tests for the
parser / scope / resolver helpers).

Verification checklist:

- [x] Harness launches `.\Update-WindowsServerIso.ps1 -Action TestHarness` in a sub-process
- [x] JSON-over-stdin REPL accepts each function-call payload
- [x] Each of the 10 assertions returns a stable shape

### 2.4 DryRun mode — Setup / Fetch / Plan only

```powershell
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2019\2026-05' `
    -WorkRoot 'D:\UpdateWsi' `
    -DryRun
```

Expected: P01 – P06 execute; P07 – P13 are explicitly marked SKIPPED in
the Phase Timing Summary; exit 0.

Verification checklist:

- [x] P01 – P06 banner blocks each have a complete header + footer
- [x] P07, P08, P09, P10, P11, P12, P13 all log SKIPPED with reason "DryRun"
- [x] No DISM mount call appears in the log
- [x] Phase Timing Summary at the end of the run lists all 13 phases with their state

### 2.5 SyntheticTestMode — CI full pipeline

```powershell
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -SyntheticTestMode `
    -WorkRoot 'D:\UpdateWsi_synth' `
    -Execute
```

Expected: Full P01 – P13 pipeline runs against synthetic WIM/MSU/CAB
inputs (no Microsoft asset download). P03 and P06 are bypassed
(per SPEC.md §B.14). Output ISO is generated and validated by P11.

Verification checklist:

- [x] No `microsoft.com` / `update.microsoft.com` HTTP call
- [x] Synthetic WIM bytes are emitted by the test harness, not extracted from a real ISO
- [x] P09 produces a non-zero-byte `synthetic_<OsKey>.iso` under `<WorkRoot>/output/`
- [x] P11 verifies the synthetic ISO and emits the verification log
- [x] CI Stage 3 runs this end-to-end on every push to main

---

## 3. Live Catalogue verification

These probes catch Microsoft-side schema or hosting drift. They
require unrestricted egress to `*.microsoft.com` and run on cadence
rather than on every commit.

### 3.1 T1 — Microsoft Update Catalog probe

```bash
python3 tests/catalog_probe.py --check all
python3 tests/catalog_probe.py --snapshot   # writes tests/snapshots/last_probe.json
```

Expected: ~7 live checks pass (search response shape, per-OS title
formats, supersedence panel, ScopedViewInline.aspx detail page). On
schema drift, the failure message identifies which check broke and
which `data/config-Server*.json` `TitleTokens` array likely needs
updating.

### 3.2 T4 — Evaluation ISO endpoint check

```bash
python3 tests/eval_iso_probe.py
```

Expected: 4 OS × 2 languages = 8 HTTP HEAD requests against the
`download.microsoft.com` fwlink targets resolve to live URLs with
size + Last-Modified consistent with the values in
`data/config-Server*.json` `LanguageSpecific.<lang>.Iso`.

### 3.3 T5 — `wsusscn2.cab` freshness

```bash
python3 tests/wsusscn2_probe.py
```

Expected: live `wsusscn2.cab` URL responds; size > 0; Last-Modified
within the last 60 days. A warning is emitted if older than 60 days
(Microsoft is missing a monthly refresh).

### 3.4 When to run these

| Trigger | Tools to run |
|---|---|
| Before a release commit | T1, T4, T5 |
| Monthly (the 15th, post Patch Tuesday) | T1, T4, T5 (automated by Stage 4) |
| When P03 / P04 begin failing in unexpected ways | T1 first to confirm whether Microsoft changed shape |
| Before running an `-Execute` build | T5 (so the embedded `wsusscn2.cab` step has the right cab to read) |

---

## 4. Operator-pending: real ISO integration

Real-run verification (`-Execute` against a downloaded Microsoft
evaluation ISO) cannot be automated by CI because:

- The evaluation licence forbids public redistribution of the
  Microsoft binaries (ISO, MSU, CAB).
- The pipeline requires ≥ 100 GB free disk space, ADK Deployment
  Tools, and Administrator privileges, none of which fit a typical
  GitHub-hosted runner.
- A successful pipeline may take 40 – 90 minutes per OS family; the
  test budget for per-commit CI is incompatible with that.

The operator-pending verification is **out-of-band**. The expected
procedure is below; results from past real runs are recorded in
[`CHANGELOG.md`](./CHANGELOG.md) and the `docs/history/` cycle reports.

### 4.1 Procedure

1. Provision a Windows 11 / Windows Server 2022 host with ≥ 200 GB
   free disk on the working volume.
2. Install Windows ADK Deployment Tools (or pass `-AutoInstallAdk`).
3. Pre-stage an evaluation ISO (e.g. via `-EvalIsoMode -IsoUrl
   <fwlink>` or place it manually and pass `-IsoPath`).
4. Run:

   ```powershell
   .\Update-WindowsServerIso.ps1 `
       -Action PrepareBuildVerify `
       -OsVersion Server2019 -OsLanguage ja-jp `
       -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
       -PatchDirectory 'D:\Patches\Server2019\2026-05' `
       -WorkRoot 'D:\UpdateWsi_2019' `
       -Execute
   ```

5. Record the P13 FinalReport hash and elapsed time in
   [`CHANGELOG.md`](./CHANGELOG.md) under the current revision.

### 4.2 Known operator-pending items in the current revision

| Item | Note |
|---|---|
| Server 2016 `-Execute` build | KB5088064 SSU prerequisite issue documented in [`docs/history/r08.0-step4-findings-and-dependency-investigation.md`](./docs/history/r08.0-step4-findings-and-dependency-investigation.md). Once §B.19 (Servicing Dependency Database) is implemented in r09.0, P06 will catch this at validation time. In the interim, operators must add the prerequisite SSU manually to `data/config-Server2016.json` |
| Mojibake in P05 WIM-index banner | Did **not** reproduce in r08.0 Step 17 when `-WorkRoot` was changed from `D:\UpdateWsi` to `D:\UpdateWsi_2016`. Working hypothesis is now DISM mount-cache state corruption from prior aborted P10 runs, not console rendering. Workaround: use a fresh `-WorkRoot` per OS family. See [SPEC.md](./SPEC.md) §D.25 |

---

## 5. Self-verification tool suite (T1 – T19)

The `tests/` directory ships eleven Python tools plus the Part C
format gate. The authoritative inventory lives in
[`tests/README.md`](./tests/README.md); §0 above mirrors their current
status. The full design rationale is in [SPEC.md](./SPEC.md) §C.9.

### Quick run reference

```bash
# Offline tests — safe everywhere
python3 tests/catalog_fixture_test.py        # T2: 13 fixture assertions
python3 tests/powershell_harness.py          # T3: 10 PS function assertions
python3 tests/release_info_parser_test.py    # T6: 13 release-info parser assertions
python3 tests/dotnet_cu_parser_test.py       # T7: 16 .NET CU parser assertions
python3 tests/dynamic_update_cache_test.py   # T8: 20 DU cache assertions
python3 tests/catalog_title_tokens_test.py   # T9: 18 Title-token assertions
python3 tests/release_info_resolver_test.py  # T10: 22 resolver assertions
python3 tests/canonical_json_test.py         # T11: 26 PS/Python byte-level parity assertions

# Part C quality gate (every commit that touches a JSON file)
python3 tests/canonical_json_format_check.py # 25 JSON files canonicalised; gate per SPEC §C.3.4

# Live tests — require unrestricted egress
python3 tests/catalog_probe.py --check all   # T1: Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4: Server<N> ISO CDN
python3 tests/wsusscn2_probe.py              # T5: wsusscn2.cab freshness
```

### Determinism categories

- **Offline-deterministic** (Stage 1 CI gate, every PR): T2, T3, T6, T7, T8, T9, T10, T11, T12, T13, plus the Part C §C.3.4 canonical JSON format gate, the config schema gate, and the scope-invariants gate.
- **Live-network** (Stage 4 monthly + ad-hoc): T1, T4, T5.

### T12 / T13 (r09.0 Step 2b, implemented)

`wsusscn2_parser_test.py` (T12, 22 assertions) provides offline
regression coverage for the §B.19 Master XML parser
(`ConvertFrom-WsusScnPackageXml`, `New-WsusScnDependencyDatabase`)
against the committed fixture `tests/fixtures/wsusscn2/package.xml`,
paired with the `tests/common/wsusscn2_*.py` fixture helpers.
`wsusscn2_layer1_test.py` (T13, 15 assertions) covers the Phase
2b2/2b3 Layer 1 writeback helper `Update-Layer1DependencyVerification`.
The current canonical T-set ends at T13; the three unnumbered gates
(canonical JSON format gate, config schema gate, scope-invariants
gate) sit alongside it.

---

## 6. Continuous integration coverage

Four GitHub Actions workflows together provide automated coverage of
§1, §2, §3, and §5 above.

### 6.1 Stage 1 — Linux psa.py + PSScriptAnalyzer + offline T-suite

File: `.github/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml`

| Step | Tool | Purpose |
|---|---|---|
| 1 | `psa.py` | Static analysis on `Update-WindowsServerIso.ps1` |
| 2 | `Invoke-ScriptAnalyzer` (pwsh 7) | PSScriptAnalyzer with project `PSScriptAnalyzerSettings.psd1` |
| 3 | T2 | `catalog_fixture_test.py` (13 assertions) |
| 4 | T3 | `powershell_harness.py` (10 assertions) |
| 5 | T6 – T10 | Five offline parser / cache / resolver regression tests |
| 6 | T11 | `canonical_json_test.py` — PS/Python byte-level parity (26 assertions, SPEC §B.23) |
| 7 | T12 – T13 | `wsusscn2_parser_test.py` (22 assertions, Stages 3/4) + `wsusscn2_layer1_test.py` (15 assertions, Layer 1 writeback) |
| 8 | Part C §C.3.4 gate | `canonical_json_format_check.py` — every `data/*.json` / `tests/fixtures/*.json` / `tests/snapshots/*.json` re-serialised byte-identical |
| 9 | config schema gate | `config_schema_test.py` — every `data/config-Server*.json` validated against `schema/config.schema.json` (14 assertions) |
| 10 | scope-invariants gate | `wsusscn2_scope_invariants_test.py` — EOS/ESU deny-list + allow-overrides over `data/wsusscn2-database.json` + fixture + synthetic cases (23 assertions) |

Triggers: every push, every PR. Required to merge.

### 6.2 Stage 2 — Windows PSScriptAnalyzer + parse + read-only smoke

File: `.github/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml`

| Step | Tool | Purpose |
|---|---|---|
| 1 | `Invoke-ScriptAnalyzer` (Windows PS 5.1) | PSScriptAnalyzer against the Windows 5.1-specific rule subset |
| 2 | `[System.Management.Automation.Language.Parser]::ParseFile` | Confirm the script parses cleanly under Windows PowerShell |
| 3 | `-Action ListPhases` | Read-only inventory dump |
| 4 | `-EnvironmentInfoOnly` | P01-only environment dump |

Triggers: every push, every PR.

### 6.3 Stage 3 — Synthetic full pipeline (Windows + ADK)

File: `.github/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml`

| Step | Tool | Purpose |
|---|---|---|
| 1 | ADK installer | Install Windows ADK Deployment Tools on the runner |
| 2 | `-Action PrepareBuildVerify -SyntheticTestMode -Execute` | Full P01 – P13 pipeline against synthetic inputs |
| 3 | Post-run assertions | Verify the synthetic output ISO exists, is non-zero, and parses |

Triggers: push to `main`, manual dispatch. **No artifact upload** of
the synthetic ISO (consistent with the evaluation-licence boundary
documented in §B.18 and repository SPEC.md §12).

### 6.4 Stage 4 — Monthly baseline refresh + auto-PR

File: `.github/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml`

| Step | Action | Purpose |
|---|---|---|
| 1 | `-Action RefreshSnapshots` | Refresh upstream `data/raw-*` + `data/cache-*` |
| 2 | `-Action RefreshAllBaselines` | Regenerate `data/config-Server*.json` from caches |
| 3 | T1 + T4 + T5 | Live Catalogue / ISO endpoint / wsusscn2 probes |
| 4 | `peter-evans/create-pull-request` | If `data/config-*.json` changed, open a PR (restricted via `add-paths`) |

Triggers: `cron: 0 2 15 * *` (02:00 UTC on the 15th of each month;
3 days after the second-Tuesday Patch Tuesday), manual dispatch.
Manual dispatch accepts four inputs: `mode`, `onlyOs`, `onlyLanguage`,
`dryRun`. Failed runs do not block other workflows (this is an
operations workflow, not a quality gate).

### 6.5 What CI does NOT cover

- Real `-Execute` builds against downloaded Microsoft evaluation ISOs (see §4)
- Hyper-V `-Action BootTest` (requires nested virtualisation; no CI runner has this)
- Operator-side Microsoft Update Catalogue scraping outside of CI Stage 4

---

## 7. Discovered bugs and fix history

The per-revision pitfall catalogue with stable IDs (`D.1` – `D.30`)
lives in [`SPEC.md`](./SPEC.md) Part D. Each entry records: the
revision where the bug was observed, the symptom, the root cause, the
fix applied, and any cross-references to `docs/history/` cycle reports.

This document does not duplicate that catalogue. Two highlights from
the current cycle:

- **D.25 Mojibake investigation**: P05 WIM-index banner produced doubled
  Japanese characters in r08.0 Step 16; the cycle report
  [`docs/history/mojibake-investigation-note.md`](./docs/history/mojibake-investigation-note.md)
  captures the investigation. Working conclusion: DISM mount-cache
  state corruption from prior aborted P10 runs, mitigated by using a
  fresh `-WorkRoot` per OS family.
- **r08.0 Step 4 KB5088064 SSU finding**: Server 2016 `-Execute` builds
  failed with `0x800f0823 — CBS_E_NEW_SERVICING_STACK_REQUIRED` because
  the LCU's prerequisite SSU was not in the baseline. Investigation in
  [`docs/history/r08.0-step4-findings-and-dependency-investigation.md`](./docs/history/r08.0-step4-findings-and-dependency-investigation.md)
  motivated the r09.0 [`SPEC.md`](./SPEC.md) §B.19 Servicing Dependency
  Database design.

For the full catalogue of pitfalls and fixes, see SPEC.md Part D.
