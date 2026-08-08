---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-08
---
# TESTING.md — Verification Procedure and Real-Run Results

This document consolidates everything needed to verify and evaluate
`Update-WindowsServerIso.ps1`. It covers six areas:

1. **Static analysis** — `psa.py` gate (must pass before every commit)
2. **Synthetic smoke tests** — read-only Actions executable in CI
3. **Live Catalogue verification** — probes that catch Microsoft-side schema drift
4. **Operator-pending verification** — full `-Execute` builds (requires Windows + ADK + ≥ 100 GB disk + admin)
5. **Self-verification tool suite** — T1 through T52 (canonical inventory in [`tests/README.md`](./tests/README.md); since r12.00 this includes the declaration-derived T41 – T46 set and eight retirements recorded in SPEC §B.15.4; since the series-end test re-implementation campaign it includes the T47 – T52 contracts re-authored from the external implementation's terminal regression set)
6. **Continuous integration** — four GitHub Actions stages

> **Documentation language policy**: This document is maintained in
> English only per the repository-wide policy. See `README.md` and
> `README.ja.md` for the bilingual entry-point documentation; for the
> repository-wide language policy see the root [`README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md)
> "Language Policy" section.

---

## Table of Contents

- [0. Verification status summary](#0-verification-status-summary)
- [1. Static analysis gate](#1-static-analysis-gate)
- [2. Synthetic smoke tests](#2-synthetic-smoke-tests)
- [3. Live Catalogue verification](#3-live-catalogue-verification)
- [4. Operator-pending: real ISO integration](#4-operator-pending-real-iso-integration)
- [5. Self-verification tool suite](#5-self-verification-tool-suite)
- [6. Continuous integration coverage](#6-continuous-integration-coverage)
- [7. Discovered bugs and fix history](#7-discovered-bugs-and-fix-history)
- [8. Monthly baseline regeneration — agent/LLM verification procedure](#8-monthly-baseline-regeneration--agentllm-verification-procedure)

---

## 0. Verification status summary

The "Last verified" column uses the canonical sibling-project format:
a build identifier plus a calendar date. Pending items are marked
`_pending operator confirmation_`.

| Item | Status | Last verified |
|---|---|---|
| `psa.py` (latest mainline; with project `.psa.config.json`) on `Update-WindowsServerIso.ps1` and the Collector | **Adjudicated-debt model** (the standing governance: no UNADJUDICATED finding at any severity; adjudicated findings remain as declared debt with documented cause and a non-regression baseline; new/increased unexplained findings block). Declared baseline after the PSA debt drain: main **1E / 120W / 0I** — the 1E is the measured PSA2001 analyzer false positive (top-level `param()` declarations not harvested) pinned inside a canonical frame with no out-of-frame remediation; the 120W are 87 measured analyzer false positives (77 PSA2009 double-cast + 10 PSA6005 parameter-boundary) awaiting the registered central analyzer fixes plus 33 naming findings deferred to the refactoring campaign. Collector **0E / 4W / 0I** (4 naming, same deferral). Causes and adjudications: CHANGELOG r12.76–r12.82 | r12.82 consolidation-fold / 2026-08-08 |
| File encoding (UTF-8 with BOM, CRLF line endings, ASCII-only outside literals) | ✓ for the main script | r11.51 audit-residue-sweep build (re-verified; also gated per-push by CI Stage 1) / 2026-07-02 |
| `PSAP0005` strict-mode baseline (no stale `rNN` references in comment bodies) | **0 findings** ✓ | r11.51 audit-residue-sweep build (re-verified after the r11.48 canon-conformance fix) / 2026-07-02 |
| PSScriptAnalyzer on Windows PowerShell 5.1 (Stage 2) | ✓ pass | CI Stage 2 (continuous) |
| P01 Initialize — PowerShell env / admin / ADK / disk / Hyper-V probe | ✓ pass on Windows 11 + PS 5.1 | _pending operator confirmation_ |
| P02 ResolveInputs — Config JSON load + ISO / patch source resolution | ✓ structurally validated via T3 harness | r09.0 step2b3-real-data-parser-correction build / 2026-05-28 |
| P03 RefreshPatchBaseline — Catalogue scrape (live, monthly) | ✓ scrape paths exercised via T1 | CI Stage 4 monthly |
| P04 FetchAssets — ISO + patch downloads with SHA-256 verify | _pending operator confirmation_ | not yet exercised on a fresh runner |
| P05 ExpandIso — source ISO mount + WIM enumeration | _pending operator confirmation_ | r09.0 step2b3-real-data-parser-correction build (synthetic mode only) |
| P06 ValidatePatchServicing — per-`PatchModel` consistency check (`Test-PatchModelConsistency` reads the promoted `PatchModel` and throws on mismatch; real readiness on-mount via §B.13) | ✓ consistency check active (`PatchModel` promoted r11.37); gate-wired guard via T20 | r11.37 / 2026-06-28 |
| P07 PatchInstallWim — SSU → LCU → .NET sequence | _pending operator confirmation_ | last successful real run not recorded in this revision |
| P08 PatchBootWim — boot.wim + winre.wim | _pending operator confirmation_ | last successful real run not recorded in this revision |
| P09 AssembleIso — Dynamic Update overlay + `oscdimg` | _pending operator confirmation_ | (requires `oscdimg.exe` on a Windows runner) |
| P10 ConvertPca2023BootManager — PCA2023 conversion (opt-in) | _pending operator confirmation_ | (requires LCU 2024-4B+ source ISO) |
| P11 StaticVerify — output ISO mount + KB-package presence check | _pending operator confirmation_ | (requires P07-P09 success) |
| P12 VerifyPca2023Readiness — `pca2023_readiness.json` + `.md` emission | ✓ structurally validated; runs unconditionally | r09.0 step2b3-real-data-parser-correction build / 2026-05-28 |
| P13 FinalReport — end-of-run summary + ISO hash | _pending operator confirmation_ | (requires P07-P11 success) |
| A01 RefreshAllBaselines — Config baseline regeneration from caches (Catalog-resolved) | ✓ exercised in Stage 4 monthly | CI Stage 4 / 2026-05-15 |
| A02 DumpFieldClassification — field-cadence decision matrix emit | ✓ exercised | r09.0 step2b3-real-data-parser-correction build / 2026-05-28 |
| A03 RefreshSnapshots — upstream `data/raw-*` + `data/cache-*` refresh | ✓ exercised in Stage 4 monthly | CI Stage 4 / 2026-05-15 |
| T1 catalog_probe.py | ✓ live probe passes (~7 checks) | CI Stage 4 / 2026-05-15 |
| T2 catalog_fixture_test.py (13 assertions) | ✓ all pass | local gate battery (offline suite) / 2026-06-28 |
| T3 powershell_harness.py (7 PS function assertions) | ✓ all pass | r11.51 audit-residue-sweep build (re-verified) / 2026-07-02 |
| T4 eval_iso_probe.py (4 OS × 2 lang Range-GET) | ✓ live probe passes | CI Stage 4 / 2026-05-15 |
| T6 release_info_parser_test.py (13 assertions) | ✓ all pass | r11.51 audit-residue-sweep build (re-verified) / 2026-07-02 |
| T7 dotnet_cu_parser_test.py (16 assertions) | ✓ all pass | r11.51 audit-residue-sweep build (re-verified) / 2026-07-02 |
| T11 canonical_json_test.py (26 assertions, PS/Python byte-level parity per SPEC §B.23) | ✓ all pass | r11.51 audit-residue-sweep build (re-verified) / 2026-07-02 |
| T20 removed_live_wua_guard_test.py (20 assertions, offline static guard: the r11.19-removed live-WUA functions/parameters stay absent and P06 ValidatePatchServicing stays a pass-through) | ✓ all pass | r11.51 audit-residue-sweep build (re-verified) / 2026-07-02 |
| T24 dism_cleanup_args_test.py (6 assertions, `Get-DismCleanupArgumentList`: default three-token `/Cleanup-Image /StartComponentCleanup` vector with no `/ResetBase`, `-IncludeResetBase` appends `/ResetBase`, `-ScratchDir` appends one `/ScratchDir:<path>` token and is omitted otherwise; guards the comma/`+` precedence collapse behind exit 1639) | ✓ all pass | r11.25 p07-resetbase-default-on-scratchdir build / 2026-06-11 |
| T25 dism_export_args_test.py (6 assertions, `Get-DismExportArgumentList` returns the five-token `/Export-Image ... /Compress:max` vector targeting the requested source index, `-ScratchDir` appends one `/ScratchDir:<path>` token and is omitted otherwise; guards the same precedence trap) | ✓ all pass | r11.25 p07-resetbase-default-on-scratchdir build / 2026-06-11 |
| T26 defender_exclusion_plan_test.py (13 assertions, the three pure helpers behind `-UseDefenderExclusions`: `Get-DefenderManagedExclusionSet` (WorkRoot path + four servicing process names), `Get-DefenderExclusionPlan` (add-only-absent, case/slash-insensitive), `Get-DefenderExclusionDecision` (fail-closed -- applies only when every prerequisite is positively satisfied; `$null`/unknown -> skip); the `*-MpPreference`/`Get-MpComputerStatus` wrappers are Windows-only and not exercised) | ✓ all pass | r11.26 defender-exclusion-optin build / 2026-06-11 |
| T29 patch_integrity_digest_test.py (14 assertions, digest-format boundary: `ConvertTo-HexDigestString` base64->hex round-trip vs an independent Python implementation for SHA-1/SHA-256, the live-captured KB5095966 Catalog vector, hex pass-through, garbage/wrong-length rejection, plus the r12.00 single-accessor wiring guard -- both `Test-PatchIntegrity` expectations normalized through the boundary; all baseline hash seeding goes through `Get-BaselineHashValue` (canonical `Integrity.<Alg>.Value` node + retained-legacy flat fields); no direct `$p.Digest`/`$p.Sha256` seeding may resurface) | ✓ all pass | r12.00 schema-v4-role-planner / 2026-08-01 |
| T30 setup_du_discriminator_test.py | **RETIRED 2026-08-08** (user adjudication at the consolidation fold): the declared SUPERSEDED-PENDING red is closed by retirement — the discovery model it awaited is landed and guarded by T46, with current selection behaviour covered by T50; the retirement record (what it asserted, why, successors) is SPEC §B.15.4 | r12.82 consolidation fold / 2026-08-08 |
| T32 checkpoint_placement_test.py (15 assertions, checkpoint placement + routing contract: `Get-PatchLocalPath` lands LCU/Checkpoint in the `cu` discovery subfolder and every other Kind flat; `Build-PatchPlan` routes Kind `Checkpoint` to NO WIM target (co-located for DISM PackagePath discovery, never applied standalone); since r12.00 the `PatchModel` Forbid axis is retired -- the test guards its absence and pins the State-driven integrity rule) | ✓ all pass | r12.00 schema-v4-role-planner / 2026-08-01 |
| T35 pca2023_default_auto_test.py (9 assertions, PCA2023 default-auto surface: retired `-EnablePca2023BootManager` token absent, `-SkipPca2023BootManager` + `-ForcePca2023OnServer2025` declared, P10 opt-out gate present, script-scope default falsy (P10 default-on); since the r12.57 default-enable reshape the Server 2025 force-gate is gone by design and the force switch survives only as a deprecated compatibility slot with a wired caution — the force-gate pin was revised T39-style at that merge) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T36 p08_plan_scope_test.py (10 assertions, r11.56 P08 plan-scope + WinRE has-work contract: `Test-WimSequenceHasWork` null-hardening incl. the `@($null)` crash shape; single hoisted `$plan` assignment above the policy branch; has-work decided before the install.wim mount; the inline crash-prone Where-Object gone) | ✓ all pass | r11.60 kb-alias / 2026-07-07 |
| T38 media_inspection_test.py (31 assertions, media-inspection + verify-refit contract: `ConvertFrom-InspectionBuildValue` shape matrix; `Compare-MediaInspection` pure diff (build advance, package delta, prereq flip, `_EX` appearance on BOTH WIM kinds, post-missing, SHA change); `Get-InspectionCrossChecks` observe-first matrix; `Get-DotNetRollupEvidence` census (plain + `_481` suffix + absent) + the DotNet-only KbId/FileName divergence data audit; structure pins -- P06 pre / P11 SHA identity + post / per-Kind rows (`KindVerificationScope`, `DotNetRollupApplied`, Kb_ behind the Server2016 guard, alias extractor gone) / conversion source fallback order + `SourceWim` / skip-aware output check (marker reasons + both call sites) / P13 diff; the invalid `Get-WindowsPackage -ImagePath` path gone) | ✓ all pass (r12.04: Kb_ guard window widened for the grown P11 census block; P10 skip-marker reasons follow the documented-conversion-boundary stance) | r12.04 release-validation-hardening / 2026-08-02 |
| T39 boot_verification_tools_test.py (17 assertions, boot-verification tool-set contract: every tool `.ps1` ParseFile-clean; pure-function REPL matrix -- `Convert-Rgb565ToBmpByte` deterministic BMP with bottom-up rows, `ConvertFrom-EfiSignatureList` synthetic-list walk + garbage degradation, subject presence, adjudicated cell map T1-T12, ledger semantics with unknown-cell throw; autounattend template well-formed + all four tokens + explicit disk-0 wipe; structure pins -- MicrosoftWindows Secure Boot template everywhere, `State=Running` documented as a non-verdict, README T9-first rule + KB5025885 mitigation values) | ✓ all pass (r12.04: the VM-state-is-not-a-verdict honesty pin is structural -- Success derives from guest evidence or forces operator review, never from VmState) | r12.04 release-validation-hardening / 2026-08-02 |
| T40 setup_binaries_sync_test.py (21 assertions, Setup-binary sync contract: plan build gates with the 26100 setuphost.exe boundary and unknown-build degradation (since r12.72 sync plans carry setup.exe + setuphost.exe when present, build-independent); exact size/SHA-256/ISO-8601-UTC file evidence + missing-path shape; closed record vocabulary; structure pins -- SHA-verified copy hard-fails, ReadOnly cleared, CSV/JSON evidence artifacts, console before/after lines, boot.wim-side stash + P09 post-overlay reapply, P11 `SetupBinarySync_*` Fail grading; since the option-B rework the P08S wiring is guarded by a structural invariant (every quoted phase-ID list of three or more elements containing both P08 and P09 must wire P08S strictly between them) plus per-site pins naming the five known pipeline lists, replacing the fragile global token-count proxy; release pin tracks the current ScriptVersion) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T41 apply_plan_conformance_test.py (declaration-derived: every `Lines[]` entry conforms to the config's declared `ServicingModel.ApplyPlans`; expected values read from the config under test; supersedes T27 / T32-routing / T33-ordering; 143 assertions at r12.00, 139 at r12.75 -- the count tracks the declared Lines) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T42 servicing_model_declaration_test.py (declaration-derived: `SourcePrerequisites[]` + `Condition.Mode`, `Common.BootWimUpdateModel`, `ValidationPolicy` flags; supersedes T31 / T34 / T37 / T33-envelope; 30 assertions at r12.00, 37 at r12.75 -- the count tracks the declaration) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T43 line_integrity_declaration_test.py (declaration-derived: `Lines[].Integrity` + `Roles` + parent/URL resolvability; supersedes T23 / T29-wiring; 158 assertions at r12.00, 128 at r12.75 -- the count tracks the baseline Line count) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T44 compatibility_declaration_test.py (declaration-derived meta-contract: `Compatibility.LegacyFieldsRetained` / `.CanonicalV4Fields` disjoint and truthful; 64 assertions) | ✓ all pass | r12.00 schema-v4-role-planner / 2026-08-01 |
| T45 servicing_contract_baseline_test.py (26 assertions, declaration-derived series instrument over `data/servicing-contract-baselines.json`: per-OS contract revisions + SHA-256 pins, plus the campaign extension's script-computed component-hash cross-check -- the contract constructors are extracted from the script's own AST under the pinned pwsh and each of the eight component digests per OS must equal the declared baseline value, closing the loop the declaration-shape assertions leave open; the anchor file exists on the branch since the r12.44 merge, so the NOT-YET path is dormant; the extension section requires pwsh, the declaration-shape sections remain pure Python) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T46 discovery_policy_declaration_test.py (declaration-derived: `DiscoveryPolicy.CatalogAliases` + per-Kind `SearchProfiles` well-formed and consistent; supersedes T28; 112 assertions) | ✓ all pass | r12.00 schema-v4-role-planner / 2026-08-01 |
| T47 collector_artifact_test.py (29 assertions, the Collector's identity and artifact contract: supported deliverable filename present and the retired project-context filename absent; the exact CollectorVersion/SchemaVersion pair pinned and advanced deliberately per Collector release; project-neutral evidence contract (error schema, artifact prefix, OS-tokenized naming); pre-r9 retirement guards with cross-version baseline comparison disabled; collection posture (ESP/MSInfo32 default-on, C:\Temp output contract, mountvol-based read-only ESP access, the eight-function evidence inventory); the no-network invariant; and a Collector parse gate extending the battery beyond the main script) | ✓ all pass | r12.75 series terminal (Collector r12) / 2026-08-07 |
| T48 collector_semantics_test.py (42 assertions, the Collector's behavioral contract over the r10→r12 hardening arc, exercised via AST-extracted functions against fixtures carrying measured four-OS post-install facts: PFRO Advisory/Blocking classification with CBS / Windows Update overrides, Secure Boot event-field parsing, the restart-preflight decision matrix (fail-closed on Advisory/Blocking/Unknown startup states; boot history corroborates but never decides), and the r12 Secure Boot evidence semantics (WinCS parsing, `UEFICA2023Status` as the status authority, stale-1808 rejection, the measured 2019 monitoring divergence held conservative)) | ✓ all pass | r12.75 series terminal (Collector r12) / 2026-08-07 |
| T49 oscdimg_reference_test.py (44 assertions, protection for the declared tool-reference file adopted at r12.63: the D-half asserts `data/tool-references/oscdimg-reference.json` internal coherence and formats only -- the declared file stays the value authority, concrete values are deliberately not duplicated into the test; the B-half pins host non-modification of the legacy ADK fallback, qualification-required wiring for `New-BootableIso`, resolver-failure evidence preservation, and the Microsoft-script reference parser behaviorally) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T50 catalog_semantics_test.py (104 assertions, the Catalog boundary and collection-shape contract over the r12.52→r12.67 hardening arc: the 48-function catalog/collection inventory (each defined exactly once), horizontal static invariants, typed semantic validator wiring with `CATALOG_VALIDATOR_EXECUTION_FAILED` excluded from transient retries, legacy-helper containment, Setup-DU scalar identity pins, and the runtime groups -- semantic retry, typed endpoint semantics (the exact-KB row filter pinned on a single-anchor page because the measured filter is a ±1800-char context-window heuristic), cache identity tags, scalar boundaries, and flat collection shapes from the measured Server 2016 four-row query) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T51 generic_list_binder_test.py (17 assertions, the PowerShell 7.4+ Generic.List binder and collection-materialization guard over the r12.17/r12.64 incident class: no New-Object Generic.List construction in the active script; P11 evidence RowCount from the List Count property directly; the oscdimg resolvers use constructor-created typed lists with explicit ToArray() materialization; behavioral pins under the pinned pwsh confirm the exact incident shapes materialize correctly) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| T52 media_authority_test.py (50 assertions, the P09/P10/P11 final-writer authority model exercised via AST-extracted functions with the DISM boundary mocked: the retained r12.62 media-sync surface and WinPE media-sync runtime (the standard boot-manager target set pinned in platform-invariant normalized form), the r12.72 P10 write-set authority binding, P11 final-identity evidence gating (tampered-ISO and stale-evidence states rejected), the measured Server 2022 reviewed-pinned Catalog identity shape, the measured Server 2019 final Setup-binary authority, and the Setup-DU final manifest validation guards) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| Part C §C.3.4 — `canonical_json_format_check.py` (28 JSON files canonicalised, format gate) | ✓ all pass | r12.75 series terminal / 2026-08-07 |
| Config schema gate — `config_schema_test.py` (20 assertions, declaration-based selection: each config's `Schema` field selects `config.schema.json` (3.0) or `config.schema.v4.json` (4.0); 2020-12 keyword coverage self-tested) | ✓ all pass | r12.00 schema-v4-role-planner / 2026-08-01 |
| Seed contract gate — `seed_contract_test.py` (17 assertions, `data/seed/seed-Server*.json` vs `schema/config-seed.schema.json` + structural seed rules; the SEED contract for the offline dataset rebuild) | ✓ all pass | r11.51 audit-residue-sweep build (re-verified) / 2026-07-02 |
| Stage 1 (Linux: BOM/CRLF/ASCII format check + config schema gate + psa.py text/SARIF + PSScriptAnalyzer/SARIF; the full offline T-suite runs in the local gate battery, not in Stage 1) | ✓ green | CI continuous |
| Stage 2 (Windows PSScriptAnalyzer + parse + read-only smoke) | ✓ green | CI continuous |
| Stage 3 (synthetic full pipeline with ADK install) | ✓ green | CI on push-to-main |
| Stage 4 (monthly baseline refresh + auto-PR) | ✓ green | CI 2026-05-15 (last scheduled run) |

The full offline suite was re-measured at the r12.75 series terminal
(tree `e39c12c8…`) on 2026-08-07: **30 test files PASS + the declared
T30 red only** (the three schema/format gates included); since the
T30 retirement at the 2026-08-08 consolidation fold the offline suite
is **30 test files, ALL PASS — no declared red**. Rows edited
in that re-baseline carry the `r12.75 series terminal / 2026-08-07`
stamp; unedited rows keep their historical verification stamps.

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
python3 ../../quality-tools/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
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
- [x] 14 Actions present (Prepare / Build / Verify / PrepareBuildVerify / BootTest / All / Cleanup / ListPhases / GenerateManifest / RefreshSnapshots / RefreshAllBaselines / RebuildDataset / DumpFieldClassification / TestHarness)
- [x] 4 Admin phases A00 – A03 present

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

Expected: 7 assertions pass (PowerShell function-level tests for the
parser / scope / resolver helpers).

Verification checklist:

- [x] Harness launches `.\Update-WindowsServerIso.ps1 -Action TestHarness` in a sub-process
- [x] JSON-over-stdin REPL accepts each function-call payload
- [x] Each of the 7 assertions returns a stable shape

### 2.4 DryRun mode — Setup / Fetch / Plan only

```powershell
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
    -UseBaselineOnly `
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

### 3.3 When to run these

| Trigger | Tools to run |
|---|---|
| Before a release commit | T1, T4 |
| Monthly (the 15th, post Patch Tuesday) | T1, T4 (automated by Stage 4) |
| When P03 / P04 begin failing in unexpected ways | T1 first to confirm whether Microsoft changed shape |

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
2. Install Windows ADK Deployment Tools (or let P01 auto-install them when `oscdimg.exe` is missing).
3. Pre-stage a source ISO (let P04 download it via the config's
   `Iso.Url` or an explicit `-IsoUrl`, or place one manually and pass
   `-IsoPath`).
4. Run, using a per-OS `-WorkRoot`, an auto-timestamped `-LogFile`, and
   the opt-in servicing-readiness check:

   ```powershell
   $OsVersion = 'Server2019'
   $WorkRoot  = "D:\UpdateWsi-$OsVersion"
   $stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
   $LogFile   = Join-Path $WorkRoot ('logs\PrepareBuildVerify-{0}-{1}.log' -f $OsVersion, $stamp)

   .\Update-WindowsServerIso.ps1 `
       -Action PrepareBuildVerify `
       -OsVersion $OsVersion -OsLanguage ja-jp `
       -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
       -UseBaselineOnly `
       -WorkRoot $WorkRoot -LogFile $LogFile `
       -Execute
   ```

5. Record the P13 FinalReport hash and elapsed time in
   [`CHANGELOG.md`](./CHANGELOG.md) under the current revision.

### 4.2 Known operator-pending items in the current revision

| Item | Note |
|---|---|
| Server 2016 `-Execute` build | The KB5088064 SSU must precede the KB5087537 LCU, or CBS rejects the LCU with `0x800f0823`. P06 ValidatePatchServicing flags this as `SsTooOld` before the mount and blocks by default. The SSU prerequisite is also recorded in `data/config-Server2016.json` so P03/P04 resolve it automatically. |
| Mojibake in P05 WIM-index banner | Did **not** reproduce when `-WorkRoot` was changed from `D:\UpdateWsi` to a per-OS root such as `D:\UpdateWsi-Server2016`. Working hypothesis is DISM mount-cache state corruption from prior aborted P10 runs, not console rendering. Workaround: use a fresh per-OS `-WorkRoot`. See [SPEC.md](./SPEC.md) §D.25 |

### 4.3 Real-machine verification baseline

The recommended baseline for an out-of-band real run combines the
conventions that the operator-pending findings above made necessary, so
that a single invocation is reproducible, self-documenting, and avoids
the two known real-machine pitfalls (the `0x800f0823` servicing-stack gap
and the P05 mojibake from a reused mount cache):

- **Per-OS `-WorkRoot`** (`D:\UpdateWsi-<OsVersion>`) — a fresh workspace
  per OS family avoids the DISM mount-cache corruption behind the §4.2
  mojibake item. Never share one `-WorkRoot` across OS families.
- **Explicit, auto-timestamped `-LogFile`** — one transcript per run,
  named by action/OS/timestamp via `Get-Date`, so reruns never overwrite
  evidence and each run is independently auditable.
- **Servicing-readiness gate (default-ON)** — P06 ValidatePatchServicing
  logs the `0x800f0823` predictor (`SsTooOld`) before the mount and blocks
  on a `Fail`. On Server 2016 / 2019 this surfaces a missing or too-old
  SSU; on Server 2022 / 2025 the check is N/A (the SSU travels inside the
  LCU).
- **`-Execute`** — the only mode that performs DISM writes.

```powershell
# One baseline run, parameterised by OS family
$OsVersion  = 'Server2016'                 # Server2016/2019/2022/2025
$OsLanguage = 'ja-jp'
$WorkRoot   = "D:\UpdateWsi-$OsVersion"     # fresh per-OS workspace
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile    = Join-Path $WorkRoot ('logs\baseline-{0}-{1}.log' -f $OsVersion, $stamp)

$common = @{
    Action                = 'PrepareBuildVerify'
    OsVersion             = $OsVersion
    OsLanguage            = $OsLanguage
    IsoPath               = "D:\ISO\WS$($OsVersion -replace 'Server','')_$OsLanguage.iso"
    UseBaselineOnly       = $true
    WorkRoot              = $WorkRoot
    LogFile               = $LogFile
    Execute               = $true
}

# P10 runs by default (readiness-driven) for every supported OS incl. Server 2025
.\Update-WindowsServerIso.ps1 @common
```

**What to confirm after the run:**

1. The Stage 2 servicing-readiness lines in the transcript show `Pass`
   for every configured patch (any `SsTooOld` / `NotInDatabase` means the
   patch set needs the matching SSU or a baseline refresh before
   `-Execute` is trusted).
2. The P05 WIM-index banner renders correctly (no mojibake); if it does
   not, the `-WorkRoot` was not fresh — clear it and rerun.
3. The P13 FinalReport hash and elapsed time are recorded in
   [`CHANGELOG.md`](./CHANGELOG.md).

---

## 5. Self-verification tool suite

The `tests/` directory ships the Python self-verification tools listed
below plus the config-schema and canonical-format gates. The authoritative inventory
lives in [`tests/README.md`](./tests/README.md); §0 above mirrors their
current status. The full design rationale is in [SPEC.md](./SPEC.md) §C.9.

### Quick run reference

Counts below are the values measured at the r12.75 series terminal
on 2026-08-07 (the declaration-derived contracts track the declared
surface, so their counts move with it):

```bash
# Offline suite — deterministic; most contracts drive the pinned pwsh
python3 tests/catalog_fixture_test.py        # T2: 13 fixture assertions
python3 tests/powershell_harness.py          # T3: 7 PS function assertions (TestHarness REPL)
python3 tests/release_info_parser_test.py    # T6: 13 release-info parser assertions
python3 tests/dotnet_cu_parser_test.py       # T7: 16 .NET CU parser assertions
python3 tests/canonical_json_test.py         # T11: 26 PS/Python byte-level parity assertions
python3 tests/removed_live_wua_guard_test.py # T20: 20 removed-live-WUA static-guard assertions
python3 tests/dism_cleanup_args_test.py      # T24: 6 cleanup-arg-vector assertions
python3 tests/dism_export_args_test.py       # T25: 6 export-arg-vector assertions
python3 tests/defender_exclusion_plan_test.py    # T26: 13 Defender pure-helper assertions
python3 tests/patch_integrity_digest_test.py     # T29: 14 digest-format boundary + single-accessor wiring assertions
python3 tests/checkpoint_placement_test.py       # T32: 15 checkpoint placement + routing + State-integrity assertions
python3 tests/pca2023_default_auto_test.py       # T35: 9 PCA2023 default-auto surface assertions
python3 tests/p08_plan_scope_test.py             # T36: 10 P08 plan-scope + WinRE has-work assertions
python3 tests/media_inspection_test.py           # T38: 31 media-inspection + verify-refit assertions
python3 tests/boot_verification_tools_test.py    # T39: 17 boot-verification tool-set assertions
python3 tests/setup_binaries_sync_test.py        # T40: 21 setup-binary sync assertions (structural P08S invariant + per-site pins)
python3 tests/apply_plan_conformance_test.py     # T41: 139 declared-ApplyPlans conformance assertions
python3 tests/servicing_model_declaration_test.py  # T42: 37 declared-servicing-model assertions
python3 tests/line_integrity_declaration_test.py   # T43: 128 Lines[].Integrity + Roles assertions
python3 tests/compatibility_declaration_test.py    # T44: 64 legacy/canonical meta-contract assertions
python3 tests/servicing_contract_baseline_test.py  # T45: 26 baseline-declaration + component-hash cross-check assertions
python3 tests/discovery_policy_declaration_test.py # T46: 112 DiscoveryPolicy/SearchProfiles assertions
python3 tests/collector_artifact_test.py     # T47: 29 Collector identity/artifact/no-network assertions + Collector parse gate
python3 tests/collector_semantics_test.py    # T48: 42 Collector behavioral assertions (PFRO / restart preflight / Secure Boot)
python3 tests/oscdimg_reference_test.py      # T49: 44 declared oscdimg-reference + qualification-wiring assertions
python3 tests/catalog_semantics_test.py      # T50: 104 Catalog boundary + collection-shape assertions
python3 tests/generic_list_binder_test.py    # T51: 17 Generic.List binder + materialization guard assertions
python3 tests/media_authority_test.py        # T52: 50 final-writer authority-model assertions

# Schema / format gates (every commit that touches data)
python3 tests/config_schema_test.py          # config schema gate (20; declaration-based v3/v4 selection)
python3 tests/seed_contract_test.py          # seed contract gate (17; data/seed/* vs config-seed.schema.json)
python3 tests/canonical_json_format_check.py # JSON canonical-format gate (28 files); SPEC §C.3.4

# Live tests — require unrestricted egress
python3 tests/catalog_probe.py --check all   # T1: Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4: Server<N> ISO CDN
```

### Execution tiers

The suite is declared in three tiers by execution environment. This
tier model is the series-end re-baseline (test re-implementation
campaign, phase E); it replaces the earlier two-bucket determinism
categorisation.

| Tier | Contracts | Environment | Cadence |
|---|---|---|---|
| **1 — Offline-deterministic** | T2, T3, T6, T7, T11, T20, T24 – T26, T29, T32, T35, T36, T38 – T52, plus the config-schema, seed-contract and canonical-format gates | Python 3 + the pinned pwsh (7.4.6) on PATH; runs on Linux; no network. Many contracts drive the script or the Collector through the TestHarness REPL or AST-extraction drivers, so pwsh is a tier-level dependency; a handful (e.g. T20) are pure text scans | Local gate battery on every change; the offline portion of CI |
| **2 — Live-network** | T1, T4 | Unrestricted egress to Microsoft endpoints | Stage 4 monthly + ad-hoc before releases. The design of an expanded live-network tier is a standing consolidation item |
| **3 — Evidence (user-side)** | G2: the required regression set executed on real Windows PowerShell 5.1 against the distribution ZIP. G3: Collector r12 real-machine evidence from the four Server VMs. Plus every `_pending operator confirmation_` pipeline row in §0 | Real Windows hosts / real media; outside the sandbox by nature | At the user's cadence; results recorded in §0 when delivered |

Evidence-tier status: **G3 delivered and closed 2026-08-08** (user
adjudication) — Collector r12 / schema 1.10 evidence from all four
Server VMs (2016/2019/2022/2025), every run Overall=Pass with 21/21
assessment items and checksum-complete artifact sets; the Server 2019
Secure Boot rollout monitoring divergence is graded INFO by design.
The evidence archives themselves stay outside the repository
(input-only). G2 remains open.

### Suite declaration (measured baseline)

The tier-1 baseline since the T30 retirement (2026-08-08 consolidation
fold): **30 test files, ALL PASS — no declared red.** Any red on this
branch is a regression. The per-contract assertion counts are the
values in the quick-run reference above; the declaration-derived
contracts (T41 – T46 and the D-halves of T45/T49) re-derive their
expected values from the declared surfaces at every run, so their
counts move only when the declaration moves.

### E-DEFER register

Empty. The re-implementation campaign's disposition taxonomy reserved
`E-DEFER` for assertion groups that would have required real machines
or real media at test-execution time. The measured outcome is that no
group needed it: every re-authored group runs in tier 1 — including
the WinPE media-sync runtime, the strongest deferral candidate, which
phase C measured as fully runnable under Linux pwsh with only a
platform-invariant normalization of the boot-manager alias set
(Windows de-duplicates case-insensitive alias records; the normalized
unique set is identical on both platforms). Real-machine verification
remains represented in tier 3, not as deferred sandbox tests.

### Absorption boundary

The campaign absorbed the external implementation's terminal required
regression set as an input-only specification source (never adopted
verbatim, per the standing governance ruling). Every source assertion
group received an explicit disposition — re-authored into the T47+
contracts or the T40/T45 reworks, recorded as already covered, or
recorded as dropped with a reason — in an out-of-repo disposition
ledger, all groups landed. The external historical test corpus beyond
the required set is explicitly out of the absorption scope unless a
separate bounded sweep is ordered.

## 6. Continuous integration coverage

Four GitHub Actions workflows together provide automated coverage of
§1, §2, §3, and §5 above.

### 6.1 Stage 1 — Linux psa.py + PSScriptAnalyzer + offline T-suite

File: `.github/workflows/projects__powershell-update-windows-server-iso__stage1__linux.yml`

| Step | Tool | Purpose |
|---|---|---|
| 1 | `psa.py` | Static analysis on `Update-WindowsServerIso.ps1` |
| 2 | `Invoke-ScriptAnalyzer` (pwsh 7) | PSScriptAnalyzer with project `PSScriptAnalyzerSettings.psd1` |
| 3 | T2 | `catalog_fixture_test.py` (13 assertions) |
| 4 | T3 | `powershell_harness.py` (7 assertions) |
| 5 | T6 – T10 | Five offline parser / cache / resolver regression tests |
| 6 | T11 | `canonical_json_test.py` — PS/Python byte-level parity (26 assertions, SPEC §B.23) |
| 7 | Part C §C.3.4 gate | `canonical_json_format_check.py` — every `data/*.json` / `tests/fixtures/*.json` / `tests/snapshots/*.json` re-serialised byte-identical |
| 8 | config schema gate | `config_schema_test.py` — every `data/config-Server*.json` validated against the schema its `Schema` field declares: `config.schema.json` (3.0) or `config.schema.v4.json` (4.0) (20 assertions) |

Triggers: every push, every PR. Required to merge.

### 6.2 Stage 2 — Windows PSScriptAnalyzer + parse + read-only smoke

File: `.github/workflows/projects__powershell-update-windows-server-iso__stage2__windows.yml`

| Step | Tool | Purpose |
|---|---|---|
| 1 | `Invoke-ScriptAnalyzer` (Windows PS 5.1) | PSScriptAnalyzer against the Windows 5.1-specific rule subset |
| 2 | `[System.Management.Automation.Language.Parser]::ParseFile` | Confirm the script parses cleanly under Windows PowerShell |
| 3 | `-Action ListPhases` | Read-only inventory dump |
| 4 | `-EnvironmentInfoOnly` | P01-only environment dump |

Triggers: every push, every PR.

### 6.3 Stage 3 — Synthetic full pipeline (Windows + ADK)

File: `.github/workflows/projects__powershell-update-windows-server-iso__stage3__synthetic.yml`

| Step | Tool | Purpose |
|---|---|---|
| 1 | ADK installer | Install Windows ADK Deployment Tools on the runner |
| 2 | `-Action PrepareBuildVerify -SyntheticTestMode -Execute` | Full P01 – P13 pipeline against synthetic inputs |
| 3 | Post-run assertions | Verify the synthetic output ISO exists, is non-zero, and parses |

Triggers: push to `main`, manual dispatch. **No artifact upload** of
the synthetic ISO (consistent with the evaluation-licence boundary
documented in §B.18 and repository SPEC.md §12).

### 6.4 Stage 4 — Monthly baseline refresh + auto-PR

File: `.github/workflows/projects__powershell-update-windows-server-iso__stage4__monthly-refresh.yml`

| Step | Action | Purpose |
|---|---|---|
| 1 | `-Action RefreshSnapshots` | Refresh upstream `data/raw-*` + `data/cache-*` |
| 2 | `-Action RefreshAllBaselines` | Regenerate `data/config-Server*.json` from caches |
| 3 | T1 + T4 | Live Catalogue / ISO endpoint probes |
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
  motivated the r09.0 servicing-dependency design (`SPEC.md` §B.19, now the
  per-`PatchModel` consistency check); since r12.00 the prerequisite
  contract is declared in `PatchBaseline.SourcePrerequisites[]` and
  enforced by T42/T43 plus the P06 State-driven integrity check (T23 is
  retired; SPEC §B.15.4).

For the full catalogue of pitfalls and fixes, see SPEC.md Part D.

---

## 8. Monthly baseline regeneration — agent/LLM verification procedure

This section records the procedure an operator or coding agent follows
to regenerate a monthly `/data` baseline (`config-Server*.json` plus the
`data/raw-*` and `data/cache-*` mirrors) and the verification
gates that decide whether the result is committable. It was distilled
from the 2026-05 and 2026-06 real runs, and is the LLM-side checklist
to apply on every monthly rebuild.

### 8.0 Preconditions — live site-content gates (G-pre, run first)

Before any fetch or regeneration, confirm the live truth sources
actually carry the target month, so the run cannot silently regenerate
against stale upstream content. All four must PASS; if any fails, **stop
and defer** (G-pre-1 is the same currency wall as G1 below).

| Gate | Check (target month `<yyyy-MM>`) | Source |
|---|---|---|
| **G-pre-1** release-health currency | the page lists `<yyyy-MM> B` for all four OS (the month's LCU KBs) | `learn.microsoft.com/en-us/windows/release-health/windows-server-release-info?accept=text/markdown` (§B.22.1) |
| **G-pre-2** .NET CU source | index reachable; latest listed month `<= <yyyy-MM>` — when the target is a `.NET` publication gap, this is the month carry-forward resolves (§B.22.5) | `learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes?accept=text/markdown` |
| **G-pre-3** Catalog reachable | `Search.aspx?q=<a target LCU KB>` returns HTTP 200 with the KB | `www.catalog.update.microsoft.com` |

Example (bash, same egress path the script uses):

```bash
UA='ai-generated-artifacts/release-info (+https://github.com/usui-tk/ai-generated-artifacts)'
# G-pre-1: expect >= 4 (one row per OS)
curl -fsSL -A "$UA" 'https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info?accept=text/markdown' | grep -c '<yyyy-MM> B'
# G-pre-2: latest .NET CU month listed
curl -fsSL -A "$UA" 'https://learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes?accept=text/markdown' | grep -oE '20[0-9]{2}-[0-9]{2}' | sort -u | tail -1
# G-pre-3: expect 200
curl -s -o /dev/null -w '%{http_code}\n' -A "$UA" 'https://www.catalog.update.microsoft.com/Search.aspx?q=<LCU-KB>'
```

### 8.1 Regeneration sequence

Run from a clean checkout at the target HEAD, with `-SkipEnvCheck` to
bypass the 100 GB `-Execute` preflight (these admin actions mount no WIM).

**Single entry point (r11.42+): `A00 RebuildDataset`.** One command rebuilds
the whole `/data` baseline from the committed seeds
(`data/seed/seed-Server*.json`) plus live upstream, runnable from empty:

```powershell
.\Update-WindowsServerIso.ps1 -Action RebuildDataset -PatchMonth <yyyy-MM> -SkipEnvCheck
```

`A00` is a pure orchestrator over the existing stages: **(0)** validate each
in-scope seed (exists, parses, `OsKey` matches filename); **(1) A03
`RefreshSnapshots`** — refresh `data/raw-*` and `data/cache-*` (release-info
Markdown, .NET CU, Dynamic Update) from the web; **(2)**
`Build-ConfigSkeletonFromSeed` — lay each seed into the full config shape with
empty DERIVED placeholders; **(3) A01 `RefreshAllBaselines -Mode Force`** — fill
`Lines` / `LanguageSpecificPatches` / refresh stamps / `_meta` from the refreshed
caches and the Microsoft Update Catalog; **(4)** verify every config carries a
non-empty `PatchBaseline.Lines`. `-PatchMonth` (required) pins the month and
(r11.20+) derives `PatchTuesdayOfBaseline` from that month's Patch Tuesday
(§B.22.11); `-OnlyOs` narrows scope.

Running A03 then A01 by hand (the pre-r11.42 two-step) still works and is
equivalent for an already-seeded `/data`; `A00` is preferred because it is the
single gate-checked entry point and is runnable from empty.

`A00` chains A03 (observed 2026-06: ~2m28s) + A01 (~6m32s), so it exceeds a
~5–6 min foreground runner budget: run it **detached + polled** with a per-run
work-log (§8.3), never synchronously in the foreground.
Exit code **2 = manual-fill-only** — the 12 `Common` / per-language `Iso`
fields (`cadence=IsoRelease`, `decision=Manual`), which ship **empty** in
the committed baseline — and is **expected**, not a failure.

### 8.2 Verification gates (all must hold before commit)

| Gate | Check | Failure signal |
|---|---|---|
| **G1 Discovery-source currency** *(critical)* | the refreshed `data/raw-release-info.md` already lists the target month | A01 logs `Discovery returned zero records for OS=… Month=<yyyy-MM>` |
| **G2 Stamp / patch-set consistency** | every `config-Server*.json` has `PatchTuesdayOfBaseline` = the target month's Patch Tuesday **and** resolved LCU/SSU KBs belonging to that month | a new-month stamp sitting over previous-month KBs |
| **G3 Standing gates** | `psa.py` at the declared adjudicated-debt baseline (no new/increased unexplained findings), offline suite green, restamp IN SYNC, `doc_gate` PASS, validator A–G green | any regression from the declared baseline |

**G1 is the gate that is easy to miss.** The cab and the Microsoft
Update Catalog lead the release-health page by **a day or more after
Patch Tuesday**. Discovery is release-info-driven (§B.22.1), so a regen
attempted before release-info catches up yields a wrong-month or empty
patch set even though the cab is already updated. When G2 fails, **stop
and defer the regen** — never commit a baseline whose
`PatchTuesdayOfBaseline` is the new month but whose patch entries are
the previous month's KBs.

**Correctness cross-check (G3 add-on).** After regen, confirm each
`config-Server*.json` LCU KbId equals the `<yyyy-MM> B` LCU on the live
release-health page (G-pre-1), and — when the target is a `.NET` gap
month — that every OS carries a non-empty `.NET` CU (carried forward from
the latest `<= <yyyy-MM>` month, §B.22.5). A useful reproducibility check
is to diff the non-`.NET` patch entries (LCU/SSU/DU `KbId`+`DownloadUrl`+
`UpdateId`+`FileName`) against the prior independent regen: they should
match byte-for-byte.

**Historical note (superseded at r12.00).** T23
(`config_required_ssu_downloadurl_test.py`) used to pin a hard-coded
Server 2016 SSU KbId that had to be advanced in the same commit as
every monthly baseline. T23 is retired (SPEC §B.15.4): its successors
T43 / T42 are declaration-derived — they read expected values from the
config under test — so the monthly regeneration no longer requires a
paired test edit for this contract. The general rule stands for any
remaining pinned contract (e.g. T40's release pin): advance the pin in
the *same commit* as the change it tracks.

### 8.3 Work-log convention (compaction resilience)

An agent's working context can be compacted mid-task, erasing what was
verified. So **every agent-run regeneration MUST record a per-run
work-log to a file** as it goes — not only at the end. The log captures:
the exact commands and their timings, the G1–G3 results, the month-over-
month KB delta, and any findings/anomalies. Then:

- the **canonical one-paragraph run summary** is recorded in the work-log;
- any **anomaly / recheck item** (a surprise from the reverse-engineered
  data) is written to the out-of-repo maintenance handoff so the next
  session sees it at A0 — never silently folded into the committed
  baseline.

This is what lets a later session reconstruct state without re-running the
regeneration or rediscovering the detached-run timeout workaround.
