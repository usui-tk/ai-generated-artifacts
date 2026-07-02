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
5. **Self-verification tool suite** — T1 through T27 (canonical inventory in [`tests/README.md`](./tests/README.md))
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
| `psa.py` (latest mainline; with project `.psa.config.json`) on `Update-WindowsServerIso.ps1` | **0 errors / 0 warnings / 0 info** ✓ | r11.1 cross-repo-canon-iso-encoding-tls-rename build (`psa.py` 4.2.0; re-verified) / 2026-05-29 |
| File encoding (UTF-8 with BOM, CRLF line endings, ASCII-only outside literals) | ✓ for the main script | r11.1 cross-repo-canon-iso-encoding-tls-rename build / 2026-05-29 |
| `PSAP0005` strict-mode baseline (no stale `rNN` references in comment bodies) | **0 findings** ✓ | r11.1 cross-repo-canon-iso-encoding-tls-rename build / 2026-05-29 |
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
| T2 catalog_fixture_test.py (13 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T3 powershell_harness.py (10 PS function assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T4 eval_iso_probe.py (4 OS × 2 lang Range-GET) | ✓ live probe passes | CI Stage 4 / 2026-05-15 |
| T6 release_info_parser_test.py (13 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T7 dotnet_cu_parser_test.py (16 assertions) | ✓ all pass | CI Stage 1 (continuous) |
| T11 canonical_json_test.py (26 assertions, PS/Python byte-level parity per SPEC §B.23) | ✓ all pass | r11.1 cross-repo-canon-iso-encoding-tls-rename build (re-verified) / 2026-05-29 |
| T20 removed_live_wua_guard_test.py (20 assertions, offline static guard: the r11.19-removed live-WUA functions/parameters stay absent and P06 ValidatePatchServicing stays a pass-through) | ✓ all pass | migration r11.33 / 2026-06-27 |
| T24 dism_cleanup_args_test.py (6 assertions, `Get-DismCleanupArgumentList`: default three-token `/Cleanup-Image /StartComponentCleanup` vector with no `/ResetBase`, `-IncludeResetBase` appends `/ResetBase`, `-ScratchDir` appends one `/ScratchDir:<path>` token and is omitted otherwise; guards the comma/`+` precedence collapse behind exit 1639) | ✓ all pass | r11.25 p07-resetbase-default-on-scratchdir build / 2026-06-11 |
| T25 dism_export_args_test.py (6 assertions, `Get-DismExportArgumentList` returns the five-token `/Export-Image ... /Compress:max` vector targeting the requested source index, `-ScratchDir` appends one `/ScratchDir:<path>` token and is omitted otherwise; guards the same precedence trap) | ✓ all pass | r11.25 p07-resetbase-default-on-scratchdir build / 2026-06-11 |
| T26 defender_exclusion_plan_test.py (13 assertions, the three pure helpers behind `-UseDefenderExclusions`: `Get-DefenderManagedExclusionSet` (WorkRoot path + four servicing process names), `Get-DefenderExclusionPlan` (add-only-absent, case/slash-insensitive), `Get-DefenderExclusionDecision` (fail-closed -- applies only when every prerequisite is positively satisfied; `$null`/unknown -> skip); the `*-MpPreference`/`Get-MpComputerStatus` wrappers are Windows-only and not exercised) | ✓ all pass | r11.26 defender-exclusion-optin build / 2026-06-11 |
| T27 catalog_patchset_builder_test.py (16 assertions, offline b3 config-dataset builder: drives `ConvertTo-ConfigLines` through the TestHarness REPL against the committed layer-1 raw fixture `tests/fixtures/catalog_raw/resolve-2026-06.json` -- whose SetupDU row is a VERBATIM 2026-07-02 live-Catalog capture, never authored -- to BUILD `PatchBaseline.Lines[]` without live Catalog I/O; asserts per-OS Kinds match the `PatchModel` allowed set, every Line carries a `Digest`, the uup-checkpoint OS builds a `SetupDU` Line at `ApplyOrder` 5, a starved (0-file) in-model Kind HARD-FAILS per the r11.45 silent-starvation guard, and out-of-model empties still drop silently) | ✓ all pass | r11.45 setupdu-discriminator-hardfail / 2026-07-02 |
| T28 setup_du_forbid_test.py (12 assertions, offline `Resolve-SetupDu` Forbid-branch guard: every non-uup-checkpoint OS (2016/2019/2022) returns the empty `SetupDU` "no line" marker -- no files, no Catalog row, Forbid note -- with no network or fixture; complements T27 which covers the 2025 happy path) | ✓ all pass | r11.43 retire-dead-data-contract / 2026-06-28 |
| T29 patch_integrity_digest_test.py (11 assertions, digest-format boundary: `ConvertTo-HexDigestString` base64->hex round-trip vs an independent Python implementation for SHA-1/SHA-256, the live-captured KB5095966 Catalog vector, hex pass-through, garbage/wrong-length rejection, plus static wiring guards -- both `Test-PatchIntegrity` expectations normalized through the boundary and P04 seeds BOTH `Digest`->`sha-1` and `Sha256`->`sha-256`; pins the fix for the base64-vs-hex mismatch that failed every real download verification) | ✓ all pass | r11.44 digest-format-boundary / 2026-07-02 |
| T30 setup_du_discriminator_test.py (8 assertions, `Select-SetupDuCandidate` against rows captured verbatim from the live Catalog 2026-07-02: server 24H2 Setup-DU rows selected, Windows 11 client / arm64 / SafeOS rows excluded, empty input safe, 21H2 selects nothing (2022 has no Setup DU), plus the pinned F1 fact -- the real Setup-DU Products value contains NO 'Setup Dynamic Update' -- and a code-line static guard that the products-based filter cannot resurface) | ✓ all pass | r11.45 setupdu-discriminator-hardfail / 2026-07-02 |
| T31 lcu_target_verify_test.py (24 assertions, TargetBuildAfterUpdate derived-field contract: `Test-LcuTargetApplied` comparator behavior (present/absent/case-insensitive/empty, build annotation), committed configs have `TargetBuildAfterUpdate == <LCU Line>.InScope.build` with no retired fields, seeds reduced to `Schema`+`ChecksumAlgorithm`, both schemas reconciled, and static wiring -- BOTH Lines writers (refresh writeback + the A00/A01 config-object loop) derive TBAU via the single pure `Get-TargetBuildFromLines`, P11 calls the comparator as a hard-Fail row, and no code line touches `VerificationMethod`/`ExcludeKbList`) | ✓ all pass | r11.46 tbau-derived-lcu-verify / 2026-07-02 |
| Part C §C.3.4 — `canonical_json_format_check.py` (26 JSON files canonicalised, format gate) | ✓ all pass | r11.1 cross-repo-canon-iso-encoding-tls-rename build (re-verified) / 2026-05-29 |
| Config schema gate — `config_schema_test.py` (14 assertions, `data/config-Server*.json` vs `schema/config.schema.json`; r10.4) | ✓ all pass | r11.1 cross-repo-canon-iso-encoding-tls-rename build (re-verified) / 2026-05-29 |
| Seed contract gate — `seed_contract_test.py` (17 assertions, `data/seed/seed-Server*.json` vs `schema/config-seed.schema.json` + structural seed rules; the SEED contract for the offline dataset rebuild) | ✓ all pass | r11.42 data-pipeline-rebuilddataset / 2026-06-28 |
| Stage 1 (Linux psa.py + PSScriptAnalyzer + T2/T3/T6/T7/T11/T20/T24-T27 + format gate + config schema gate) | ✓ green | CI continuous |
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
       -PatchDirectory 'D:\Patches\Server2019\2026-05' `
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
    PatchDirectory        = "D:\Patches\$OsVersion\2026-05"
    WorkRoot              = $WorkRoot
    LogFile               = $LogFile
    Execute               = $true
}

# Server 2025 additionally opts in to the PCA2023 boot-manager conversion
if ($OsVersion -eq 'Server2025') {
    .\Update-WindowsServerIso.ps1 @common -EnablePca2023BootManager -ForcePca2023OnServer2025
} else {
    .\Update-WindowsServerIso.ps1 @common
}
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

```bash
# Offline tests — safe everywhere
python3 tests/catalog_fixture_test.py        # T2: 13 fixture assertions
python3 tests/powershell_harness.py          # T3: 10 PS function assertions
python3 tests/release_info_parser_test.py    # T6: 13 release-info parser assertions
python3 tests/dotnet_cu_parser_test.py       # T7: 16 .NET CU parser assertions
python3 tests/canonical_json_test.py         # T11: 26 PS/Python byte-level parity assertions
python3 tests/config_required_ssu_downloadurl_test.py            # T23: 20 required-SSU consistency-contract assertions (PatchBaseline.Lines)
python3 tests/dism_cleanup_args_test.py                          # T24: 6 cleanup-arg-vector assertions (1639 collapse guard + /ResetBase default + /ScratchDir)
python3 tests/dism_export_args_test.py                           # T25: 6 export-arg-vector assertions (Export-Image /Compress:max + /ScratchDir)
python3 tests/defender_exclusion_plan_test.py                    # T26: 13 Defender pure-helper assertions (managed set + add-only-absent plan + fail-closed decision)
python3 tests/catalog_patchset_builder_test.py                   # T27: 16 offline b3 dataset-builder assertions (ConvertTo-ConfigLines from captured raw; SetupDU @ ApplyOrder 5; starvation guard)
python3 tests/setup_du_forbid_test.py                            # T28: 12 Resolve-SetupDu Forbid-branch assertions (non-2025 -> empty SetupDU "no line"; offline, no fixture)
python3 tests/patch_integrity_digest_test.py                     # T29: 11 digest-format boundary assertions (Catalog base64 -> hex at Test-PatchIntegrity; Digest+Sha256 wiring)
python3 tests/setup_du_discriminator_test.py                     # T30: 8 Setup-DU discriminator assertions (title-based selection over verbatim-captured live rows)
python3 tests/lcu_target_verify_test.py                          # T31: 24 TargetBuildAfterUpdate derived-field assertions (comparator + derivation helper + data/schema contract + P11 wiring)

# Schema / format gates (every commit that touches data)
python3 tests/config_schema_test.py                          # config schema gate
python3 tests/seed_contract_test.py                          # seed contract gate (data/seed/* vs config-seed.schema.json)
python3 tests/canonical_json_format_check.py                 # JSON canonical-format gate; SPEC §C.3.4

# Live tests — require unrestricted egress
python3 tests/catalog_probe.py --check all   # T1: Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4: Server<N> ISO CDN
```

### Determinism categories

- **Offline-deterministic** (Stage 1 CI gate, every PR): T2, T3, T6 – T11,
  T20, T23 – T26, plus the canonical JSON format gate and the config
  schema gate.
- **Live-network** (Stage 4 monthly + ad-hoc): T1, T4.

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
| 4 | T3 | `powershell_harness.py` (10 assertions) |
| 5 | T6 – T10 | Five offline parser / cache / resolver regression tests |
| 6 | T11 | `canonical_json_test.py` — PS/Python byte-level parity (26 assertions, SPEC §B.23) |
| 7 | Part C §C.3.4 gate | `canonical_json_format_check.py` — every `data/*.json` / `tests/fixtures/*.json` / `tests/snapshots/*.json` re-serialised byte-identical |
| 8 | config schema gate | `config_schema_test.py` — every `data/config-Server*.json` validated against `schema/config.schema.json` (14 assertions) |

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
  per-`PatchModel` consistency check); the prerequisite-SSU contract is
  enforced statically by T23 and the P06 PatchModel check.

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
| **G3 Standing gates** | `psa.py` 0/0/0, offline suite green, restamp IN SYNC, `doc_gate` PASS, validator A–G green | any non-green |

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

**T23 (`config_required_ssu_downloadurl_test.py`) follows the data, not
the reverse.** It asserts a **hard-coded** Server 2016 SSU KbId. When the
baseline advances, the standalone SSU KbId changes (e.g. 2026-05
`KB5088064` → 2026-06 `KB5094141`), so T23 fails on the freshly
regenerated data until its hard-coded KbId is advanced to the target
month's SSU. **Advancing T23 is part of the *same commit* as the new
`/data` baseline — never commit the baseline without it.** The generic
SSU assertion ("every `Type=SSU` has a non-empty `DownloadUrl`") is
data-driven and stays green, so a lone T23 failure on otherwise-green
gates is the expected signal that only the hard-coded KbId needs bumping.

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
