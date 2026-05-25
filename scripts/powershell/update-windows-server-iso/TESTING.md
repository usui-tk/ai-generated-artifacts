# TESTING.md — Verification Procedure and Verified Findings

This document consolidates everything needed to verify and evaluate
`Update-WindowsServerIso.ps1`. It covers five areas:

1. **Static analysis** — `scripts/python/powershell-static-analyzer/psa.py` gate plus PSScriptAnalyzer (must pass before every commit)
2. **Unit tests** — In-process Pester-style tests for the deterministic helpers (PatchPlan engine, sub-phase sequence builders, supersedence-aware deduplication)
3. **Synthetic smoke tests** — `-SyntheticTestMode -DryRun` runs that exercise the orchestration without touching real Microsoft binaries
4. **Live Microsoft Update Catalogue verification** — Read-only network calls that confirm the production HTTP path still works against the real Catalogue
5. **Operator-pending: real ISO integration** — The end-to-end "build a serviced Server ISO from a real evaluation ISO + the current month's patches" flow. **This has not been executed by the maintainer on a Windows host with full DISM access.** The procedure to run it is documented in Part C of [SPEC.md](./SPEC.md); the results table in §5 of this file is intentionally empty until an operator runs it.

> **Documentation language policy**: This document is maintained in
> English only per the repository-wide policy. See [`README.md`](./README.md)
> and [`README.ja.md`](./README.ja.md) for the bilingual entry-point
> documentation; for the repository-wide language policy see the root
> [`README.md`](../../../README.md) "Language Policy" section.

---

## Table of Contents

- [0. Verification status summary](#0-verification-status-summary)
- [1. Static analysis gate](#1-static-analysis-gate)
- [2. Unit tests for deterministic helpers](#2-unit-tests-for-deterministic-helpers)
- [3. Synthetic smoke tests](#3-synthetic-smoke-tests)
- [4. Live Catalogue verification (read-only)](#4-live-catalogue-verification-read-only)
- [5. Operator-pending: real ISO integration](#5-operator-pending-real-iso-integration)
- [6. Continuous integration coverage](#6-continuous-integration-coverage)
- [7. Discovered bugs and fix history](#7-discovered-bugs-and-fix-history)

---

## 0. Verification status summary

| Item | Status | Last verified |
|---|---|---|
| `psa.py` (latest mainline; with project `.psa.config.json`) on `Update-WindowsServerIso.ps1` | **0 errors / 0 warnings / 0 info** ✓ | r04.3 build |
| File encoding (UTF-8 BOM, CRLF line endings) | ✓ for the script | r04.3 build |
| `PSAP0003` / `PSAP0004` / `PSAP0005` strict-mode baseline (no inline rNN tags, no in-script REVISION HISTORY block, no rNN references in comment bodies) | **0 findings** ✓ | r04.3 build |
| PSScriptAnalyzer 1.25.0 with project `PSScriptAnalyzerSettings.psd1` | **0 findings** ✓ | r04.3 build |
| Unit tests — PatchPlan engine (4 cases) | ✓ all pass | r04 build |
| Unit tests — Sub-phase sequence builders (5 cases) | ✓ all pass | r04.1 build |
| Unit tests — `Select-LatestPatchBySupersedence` (5 cases) | ✓ all pass | r04.3 build |
| Smoke 1 — `-Action ListPhases` registry dump | ✓ exit 0, 13 phases + 11 actions | r04.3 build |
| Smoke 2 — `-EnvironmentInfoOnly` (P01 only) | ✓ exit 0 on Linux pwsh 7.4.6 | r04.3 build |
| Smoke 3 — `-SyntheticTestMode -DryRun` on Server2019 | ✓ P01–P02.5 complete; P03 reaches `New-SyntheticTestIso` (DISM unavailable on Linux pwsh is expected) | r04.3 build |
| Smoke 4 — `-Action DumpFieldClassification` | ✓ exit 0, JSON written | r04.3 build |
| Smoke 5 — `-Action RefreshAllBaselines -DryRun -OnlyOs Server2025` | ✓ exit 2 (Manual fields remain by design); supersedence dedup exercised on real data | r04.3 build |
| Smoke 6 — `-Mode Force -OnlyLanguage ja-jp` | ✓ Force overrides Skip; OnlyLanguage filter applied | r04 build |
| Smoke 7 — `-Mode Initial` | ✓ same decisions as Monthly for the baseline state | r04 build |
| Live Catalogue scrape (Server2025 / `2026-05`) | ✓ 3 patches resolved; Combined-LCU detection fires; supersedence dedup excludes 1 false-positive | r04.3 build |
| Live Catalogue scrape (Server2022 / `2026-05`) | ✓ 5 patch entries resolved after comma-form fix; supersedence dedup excludes 3 stale .NET candidates; umbrella .NET CU keeps both ndp48 and ndp481 MSUs | r04.3 build |
| Workspace preflight — Config presence (all 4 files present) | ✓ all four `Config/Server<N>.json` listed with byte sizes | r04.3 build |
| Workspace preflight — placement before dispatcher | ✓ runs for `RefreshAllBaselines` / `DumpFieldClassification` (which never run P01); skipped for `ListPhases` / `Cleanup` / `-EnvironmentInfoOnly` / `-SkipEnvCheck` | r04.3 build |
| **Real ISO integration on Windows host (full DISM)** | _Operator-pending_ | — |
| **CI Stage 1 (Linux) workflow run** | _Operator-pending; logic identical to local Linux smoke_ | — |
| **CI Stage 2 (Windows) workflow run** | _Operator-pending_ | — |
| **CI Stage 3 (Synthetic full pipeline) workflow run** | _Operator-pending_ | — |
| **CI Stage 4 (Monthly Baseline Refresh) workflow run** | _Operator-pending_ | — |

---

## 1. Static analysis gate

`psa.py` (latest mainline; rule families `PSA1001`..`PSA9002` plus opt-in
`PSAP0003`..`PSAP0005`) must pass before every commit (see [Part C of
SPEC.md](./SPEC.md#part-c--quality-gates--validation-checklist)). This
project opts in to `PSAP0003`, `PSAP0004`, and `PSAP0005`. `PSAP0005` is
enabled in **strict** mode — `psap0005_relaxed_mode` is intentionally
NOT set in `.psa.config.json`, because this project was authored from
scratch under that discipline and has no migration backlog to soften.
For the canonical version-discovery and refresh workflow, see the
repository root [`README.md`](../../../README.md) "psa.py Versioning
Policy".

`psa.py` auto-discovers `.psa.config.json` in the current working
directory, so the canonical invocation is from this script directory:

```bash
cd scripts/powershell/update-windows-server-iso
python3 ../../python/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
```

Expected output:

```
==== psa.py: PowerShell Static Analyzer ====
File   : Update-WindowsServerIso.ps1
Lines  : 7368
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

The local `.psa.config.json` populates `psa2010_known_cmdlets` with the
DISM, Storage, and Hyper-V cmdlet families used by this script.
Microsoft's in-box cmdlets are not in `psa.py`'s built-in known-cmdlet
table, so listing them in the project config silences `PSA2010`
(undefined function call) without disabling the rule globally. No
`PSAxxxx` rule is disabled at project level; all findings are
addressed at the source via either a fix or a line-local
`# psa-disable-line` comment with an inline justification.

PSScriptAnalyzer 1.25.0 must also report zero findings against the
project `PSScriptAnalyzerSettings.psd1`:

```powershell
Invoke-ScriptAnalyzer `
  -Path Update-WindowsServerIso.ps1 `
  -Settings PSScriptAnalyzerSettings.psd1 `
  -Recurse
```

Expected output: empty (zero findings).

---

## 2. Unit tests for deterministic helpers

The script's deterministic helpers (those that take no I/O and no
mutable global state) carry in-process unit tests that the maintainer
runs alongside the static-analysis gate. The tests load the script as
a library via dot-sourcing through `-Action ListPhases` (which exits
without doing any I/O once the registry has been printed), then
exercise the helpers directly with hand-crafted inputs.

### 2.1 PatchPlan engine (`Build-PatchPlan`, `Get-PatchTargetsForType`)

| Case | Input | Expected outcome |
|------|-------|------------------|
| Typical monthly set | SSU + LCU + .NET + SafeOS + Setup | Install: 3 patches (SSU, .NET, LCU); Boot: 2 (SSU, LCU); WinRE: 2 (SSU, SafeOS); Setup: 1 |
| LP / LXP routing | LCU + LP + LXP | LP appears in Install AND WinRE; LXP is Install-only |
| Unknown Type | Patch with `Type='Mystery'` | Falls back to `[Install]` with a one-time warning; `_UnknownTypes` contains `'Mystery'` |
| Empty input | `@()` | All four target lanes are empty arrays; `_PatchCount` is 0 |

Verified at r04 build — 4/4 PASS.

### 2.2 Sub-phase sequence builders (`Build-InstallApplySequence`, `Build-BootApplySequence`, `Build-WinReApplySequence`)

| Case | Input | Expected outcome |
|------|-------|------------------|
| Install WITHOUT language pack | SSU + LCU + .NET | I7 (LCU SecondPass) is NOT emitted; sequence ends at I6.CleanupAndExport |
| Install WITH language pack | SSU + LP + LCU + .NET | I7 IS emitted with `RequiresRemount = $true` and contains the LCU |
| Boot sequence | SSU + LP + LCU | B1.SSU -> B2.LanguagePack -> B3.LCU -> B4.CleanupAndExport (no twice-apply) |
| WinRE sequence | SSU + LP + SafeOsDU + LCU | W1.SSU -> W2.LanguagePack -> W3.SafeOsDU -> W4.CleanupAndExport (LCU is explicitly NOT in WinRE) |
| Empty input | `@()` | All three sequences emit their skeleton sub-phases, all with 0 patches; no I7 |

Verified at r04.1 build — 5/5 PASS.

### 2.3 Supersedence-aware deduplication (`Select-LatestPatchBySupersedence`, `Get-KbIdFromUpdateTitle`)

| Case | Input | Expected outcome |
|------|-------|------------------|
| Clear supersedence | Two LCU candidates; cand2.Supersedes contains cand1.KbId | Best = cand2; Excluded = [cand1] with `Reason = "Superseded by ..."` |
| Single candidate | One LCU candidate | Best = that one; Excluded = `@()` |
| Ambiguous (no relation) | Two LCU candidates with empty Supersedes on both sides | Best = the one with the lexicographically-later Title (because Catalogue titles start with `YYYY-MM`); Excluded = the other with `Reason = "Ambiguous; chose newest by title"` |
| UpdateId-based match | Supersedes contains the UpdateId GUID, not the KbId | Substring match still succeeds; Best = the superseding candidate |
| Empty input | `@()` | Best = `$null`; Excluded = `@()` |

Verified at r04.2 build — 5/5 PASS.

---

## 3. Synthetic smoke tests

These tests exercise the orchestration without touching real Microsoft
binaries. They are safe to run on any host with PowerShell 7+ (or
Windows PowerShell 5.1 on a Windows host).

### 3.1 Smoke 1 — `-Action ListPhases`

```powershell
.\Update-WindowsServerIso.ps1 -Action ListPhases
```

Acceptance: exit code 0; the registry table prints 13 phases
(P01..P09 plus P02.5, P04.5, A01, A02) and the Action table lists 11
actions (Prepare, Build, Verify, PrepareBuildVerify, BootTest, All,
Cleanup, ListPhases, GenerateManifest, RefreshAllBaselines,
DumpFieldClassification).

### 3.2 Smoke 2 — `-EnvironmentInfoOnly`

```powershell
.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly -WorkRoot 'C:\Temp\uwsi-smoke2'
```

Acceptance: exit code 0; P01 runs Step 0 (PowerShell environment
dump) and exits cleanly. Subsequent phases are not invoked.

### 3.3 Smoke 3 — Synthetic + DryRun

```powershell
.\Update-WindowsServerIso.ps1 `
  -Action PrepareBuildVerify `
  -OsVersion Server2019 -OsLanguage en-us `
  -SyntheticTestMode -DryRun -SkipEnvCheck `
  -WorkRoot 'C:\Temp\uwsi-smoke3'
```

Acceptance on Windows: phases P01..P09 all reach DONE / SKIPPED
(P04 and P04.5 are deliberately removed from the phase list when
`-SyntheticTestMode` is on; the synthetic ISO is not a valid ISO9660
image and `Mount-DiskImage` would reject it). The PatchPlan summary
prints all three sub-phase sequences (InstallSequence,
BootSequence, WinReSequence) with zero patches in each lane.

Acceptance on Linux pwsh: phases P01..P02.5 complete; P03 fails at
`New-SyntheticTestIso` because `dism.exe` is not available on Linux.
This is expected and not a regression.

### 3.4 Smoke 4 — `-Action DumpFieldClassification`

```powershell
.\Update-WindowsServerIso.ps1 -Action DumpFieldClassification -SkipEnvCheck -WorkRoot 'C:\Temp\uwsi-smoke4'
```

Acceptance: exit code 0; `<WorkRoot>\logs\A02_FieldClassification.json`
is written and contains a top-level `Schema = "2.0"`, `GeneratedAt`,
`ScriptVersion`, and a `FieldGroups` array of four entries (Common,
PatchBaseline, LanguageSpecific.<lang>.Iso, and
LanguageSpecific.<lang>.LanguageSpecificPatches).

### 3.5 Smoke 5 — `-Action RefreshAllBaselines -DryRun`

```powershell
.\Update-WindowsServerIso.ps1 `
  -Action RefreshAllBaselines -DryRun `
  -OnlyOs Server2025 -SkipEnvCheck `
  -WorkRoot 'C:\Temp\uwsi-smoke5'
```

Acceptance:
- Exit code 2 (Manual fields require operator fill — by design, because
  `LanguageSpecific.<lang>.Iso._VerifiedDate` is empty out of the box
  and the IsoRelease cadence has no auto Refresher).
- `<WorkRoot>\logs\A01_RefreshAllBaselines_report.csv` is written with
  one row per (OsKey, Lang, Group) combination.
- Per-group decision logged with the correct cadence:
  - `Common` → `Skip` (verified)
  - `PatchBaseline` → `Monthly` (auto-refresh)
  - `LanguageSpecific.en-us.Iso` and `LanguageSpecific.ja-jp.Iso` → `Manual`
  - `LanguageSpecific.en-us.LanguageSpecificPatches` and `LanguageSpecific.ja-jp.LanguageSpecificPatches` → `Monthly`

### 3.6 Smoke 6 — `-Mode Force` override

```powershell
.\Update-WindowsServerIso.ps1 `
  -Action RefreshAllBaselines -DryRun -Mode Force `
  -OnlyOs Server2025 -OnlyLanguage ja-jp -SkipEnvCheck `
  -WorkRoot 'C:\Temp\uwsi-smoke6'
```

Acceptance: under Force, the `Common` group decision changes from
`Skip` to `Manual` (Refresher absent for the Stable cadence); the
en-us language is filtered out by `-OnlyLanguage ja-jp`.

### 3.7 Smoke 7 — `-Mode Initial`

```powershell
.\Update-WindowsServerIso.ps1 `
  -Action RefreshAllBaselines -DryRun -Mode Initial `
  -OnlyOs Server2025 -SkipEnvCheck `
  -WorkRoot 'C:\Temp\uwsi-smoke7'
```

Acceptance: from the baseline state (no `_VerifiedDate` on the patch
groups), Initial mode produces the same decisions as Monthly — both
trigger the PatchTuesday Refresher.

---

## 4. Live Catalogue verification (read-only)

Smoke 5 above also doubles as the live Microsoft Update Catalogue
verification. It performs read-only network calls against
`catalog.update.microsoft.com` to confirm that the production HTTP
scrape path still works:

- The OS-aware query templates (per
  [SPEC.md §B.12](./SPEC.md#b12-patchplan-engine-and-wim-target-mapping-r04))
  return non-empty results for Server2025 + the current month.
- The Combined-LCU detection (`Test-IsCombinedLcuTitle` +
  `Test-IsLcuSsuCombinedMonth`) correctly identifies months where
  Microsoft has not published a standalone SSU.
- The supersedence-aware deduplication (
  [SPEC.md §B.15](./SPEC.md#b15-supersedence-aware-catalogue-candidate-selection-r042))
  fires when the narrowed candidate count exceeds 1. As of the r04.2
  build verified on 2026-05 data, the LCU query for Server2025
  returns two candidates (the canonical LCU and a `.NET Framework
  3.5 and 4.8.1` cumulative update that matches the OS Title token
  as a false positive); the dedup correctly excludes the false
  positive.

The Catalogue HTML structure changes occasionally without notice.
The maintainer relies on the **CI Stage 4 monthly-refresh workflow**
(see §6 below) to catch such changes within ~30 days of occurrence.

---

## 5. Operator-pending: real ISO integration

The script's primary deliverable — a patched, bootable Server ISO —
has not been validated end-to-end by the maintainer because no
suitable Windows host with DISM access has been available. The
documented procedure is available in [SPEC.md Part C](./SPEC.md#part-c--quality-gates--validation-checklist)
and consists of, in order:

1. Acquire an evaluation ISO for the target Server SKU from Microsoft.
2. Run `-Action Prepare` to populate the workspace.
3. Run `-Action Build -Execute` to mount, patch, cleanup, and re-emit.
4. Boot the resulting ISO in a Hyper-V VM and confirm Windows Setup
   completes; confirm `winver` reports the expected post-update build
   number (`PatchBaseline.TargetBuildAfterUpdate` from the
   `Config/<OsKey>.json`).

The results table for §5 is intentionally empty until an operator
runs the procedure end-to-end. Submitting results back to this file
via PR is welcomed.

### 5.1 Expected outcomes (theoretical, not yet verified)

For Server 2025 / en-us with the 2026-05 baseline, the expected
result is:

| Item | Expected value |
|------|---------------|
| `install.wim` index count | 4 (Standard / Standard Core / Datacenter / Datacenter Core) |
| `boot.wim` index count | 2 |
| `winre.wim` build number after patching | 26100.NNNN matching `PatchBaseline.TargetBuildAfterUpdate` |
| Output ISO size | Within ~30% of the input ISO size |
| DISM exit codes during P05/P06 | All zero (no 0x800f0823 servicing-stack mismatch; the pre-apply dependency closure check should have surfaced any mismatch before DISM) |

---

## 6. Continuous integration coverage

The four GitHub Actions workflows for this project are documented in
[`README.md`](./README.md) "Continuous Integration" section. CI runs
that mirror the local smoke tests in §3 above will surface the same
status; CI runs that exercise paths only reachable on Windows
(Stages 2 / 3 / 4) are needed before the §5 status can be filled in.

The CI workflows themselves do NOT run the §5 real-ISO integration:
distributing Microsoft evaluation ISO bytes is forbidden by the
evaluation licence (see [`README.md`](./README.md) "License" and the
inline comments in each workflow's
`scripts__powershell__update-windows-server-iso__stage3__synthetic.yml`).
Stage 3 uses a synthetic ISO produced by `New-SyntheticTestIso`.

The Stage 4 (monthly-refresh) workflow is the operational complement
to §4 live Catalogue verification: it runs `-Action
RefreshAllBaselines` on the 15th of every month and opens an
automated PR when `Config/<OsKey>.json` baselines diverge from the
committed state. Successful Stage 4 runs are themselves a form of
continuous verification that the Catalogue scrape paths still work.

---

## 7. Discovered bugs and fix history

| Build | Symptom | Root cause | Fix |
|-------|---------|-----------|-----|
| r02.5 | `Resolve-PatchSetFromCatalog` picked the wrong KB when the OS Title token matched a neighbouring KB (e.g. ".NET Framework 3.5 and 4.8.1 Cumulative Update" for the LCU query on Server2025) | Single-candidate `narrowed[0]` selection with no supersedence cross-check | r04.2 added `Select-LatestPatchBySupersedence` to dedup multi-candidate narrowed results via the Supersedes / SupersededBy data |
| r03 | `Common` and `PatchBaseline` field groups were never iterated in `A01.RefreshAllBaselines` when `-Mode Force` was used | PowerShell 7 quirk: `if ($cond) { $arr } else { @($null) }` collapses to a bare `$null` instead of a single-element array, so the outer `foreach ($lang in $iterLangs)` body never ran for non-per-language groups | r03 fix: replace with explicit `if ($cond) { $iterLangs = @($supported) } else { $iterLangs = ,$null }` using the comma operator to force a 1-element array |
| r02.2 | Phase functions called `Start-DebugTrace -PhaseName` but the implementation only accepted `-Context / -PhaseId` | API renamed during r02 split-out but not all callers updated | r02.2 cleanup pass; PSScriptAnalyzer would have caught this if PSAvoidUsingUndeclaredParameterNames had been enabled |
| r02.3 | Legacy error helpers used positional arguments inconsistent with newer call sites | Mid-refactor state | r02.3 standardised on `Add-ErrorJsonlEntry -Phase / -Kind / -Properties` |
| r04.2 | Every `Type` field on Catalogue-derived `NeutralPatches` entries was computed by file-name heuristics in `Get-PatchType`, mis-classifying SSU / Safe OS DU / umbrella .NET CU sub-files as `LCU` because their file names lack the expected distinguishing token | The classifier ignored the Catalogue search context (`$q.Type`), which already knew the authoritative Type | r04.3 added `-KnownType` parameter to `Convert-CatalogPatchToBaselineEntry`; `Resolve-PatchSetFromCatalog` now passes `$q.Type` so the heuristic is bypassed when the caller has context. See SPEC §D.20 |
| r04.2 | Server 2022 baseline refresh returned **zero** patch entries; every narrow filter dropped all hits | Microsoft Update Catalogue dropped the comma in Server 2022 update titles ("...operating system, version 21H2" → "...operating system version 21H2"); the hard-coded TitleToken did a `[regex]::Escape` literal match and the comma-bearing template no longer matched anything live | r04.3 changed `TitleTokens` to a multi-form array that accepts both the comma and comma-less variants; the live `Search.aspx` query strings were also updated to the current form. See SPEC §D.19 |
| r04.2 | Umbrella .NET CU UpdateIds (e.g. Server 2019 KB5088864 bundling 4.7.2 and 4.8) lost N-1 sub-files; `Resolve-PatchSetFromCatalog` only kept the highest-scoring single MSU | `Select-CanonicalPatchFile` returns only one result; without an explicit `-DotNetVersion` hint it cannot break the tie between two ndp-runtime variants of the same umbrella KB | r04.3 added `Select-AllCanonicalPatchFiles` and routed `Type='DotNet'` queries through it. Each surviving MSU now gets its own `NeutralPatches` entry sharing `KbId` / `Title` / `UpdateId` / `Supersedes` from the umbrella KB. See SPEC §D.21 |

For per-release detail see [`CHANGELOG.md`](./CHANGELOG.md).
