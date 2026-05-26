# Update-WindowsServerIso.ps1

| Stage | Status |
|:---|:---|
| STAGE 1 — Linux checks (psa.py + PSScriptAnalyzer on pwsh 7) | [![STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml) |
| STAGE 2 — Windows checks (PSScriptAnalyzer on Windows PS 5.1 + smoke test) | [![STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml) |
| STAGE 3 — Windows synthetic full pipeline (`-SyntheticTestMode`) | [![STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml) |

**English** | [日本語](README.ja.md)

Integrate the latest Microsoft Servicing Stack Update, Latest Cumulative
Update, Dynamic Updates, and .NET updates into a Windows Server
evaluation ISO and re-emit a bootable ISO whose embedded `install.wim`,
`boot.wim`, and `winre.wim` already contain those updates. Eliminates
the multi-hour Windows Update step from lab and test bring-up of
Server 2016 / 2019 / 2022 / 2025. Targeted at Windows 11 + Windows
PowerShell 5.1 (also runs on PowerShell 7+).

**Dynamic patch resolution.** The patch set is recorded under
`data/config-<OsKey>.json#/PatchBaseline` and is automatically refreshed
from the Microsoft Update Catalogue when the recorded baseline is
older than the current month's Patch Tuesday. A separate validation
pass uses `wsusscn2.cab` + Windows Update Agent COM API to
authoritatively confirm that the supplied patch set satisfies all
dependency requirements (e.g. the latest LCU's prerequisite SSU)
before any DISM mount is performed.

This script is part of the
[`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
repository, under `scripts/powershell/update-windows-server-iso/`.

## ⚠️ Disclaimer

**USE AT YOUR OWN RISK.** This script is provided "AS IS" without
warranty of any kind, express or implied. The authors and contributors
are not liable for any damages, data loss, account suspension, network
issues, disk space exhaustion, broken installation media, or any other
problems — direct or indirect — that may arise from using, modifying,
or distributing this script.

By running this script, you acknowledge that:

* You are solely responsible for verifying that your use complies with
  the **Microsoft Software Licence Terms** for the evaluation ISO and
  the **Microsoft Update Catalogue Terms of Use** for the patch files
* You are responsible for any consequences of downloading large
  amounts of data (bandwidth costs, storage costs, rate limits, IP
  blocks)
* You will **not redistribute** the output ISO publicly; the
  evaluation licence forbids redistribution of evaluation Microsoft
  binaries
* The output ISO is for internal lab, test, or evaluation use only,
  for the duration permitted by the evaluation licence
* You will review the script's source code and understand its
  behaviour (especially the DISM mount and `oscdimg` write paths)
  before running it in any environment that holds production data
* DISM operations require Administrator and may leave WIM mounts
  behind on abnormal exit; you are responsible for cleaning those up
  if the script's own cleanup pass cannot

For the full disclaimer and self-responsibility terms that apply to
all artifacts in this repository, see the
[root README](../../../README.md)
([Japanese](../../../README.ja.md)).

## License

This project is part of the `usui-tk/ai-generated-artifacts`
repository, which is licensed under the **MIT License**. See the
[`LICENSE`](../../../LICENSE) file at the repository root for the
full license text.

In short: you are free to use, modify, and distribute this software
for any purpose, provided that the original copyright and license
notices are preserved. The software is provided without warranty, as
detailed in the Disclaimer above and in the LICENSE file.

This MIT licence covers **the script itself**. It does NOT cover the
Microsoft binaries that the script processes (evaluation ISO,
Servicing Stack Updates, Latest Cumulative Updates, etc.), which
remain under the **Microsoft Software Licence Terms** that ship with
each asset.

## Folder layout

```
scripts/powershell/update-windows-server-iso/
  Update-WindowsServerIso.ps1     # Main script (this README documents it)
  README.md / README.ja.md        # End-user documentation (you are reading these)
  SPEC.md                          # Developer / LLM specification (English only)
  TESTING.md                       # Verification procedure and verified findings (English only)
  CHANGELOG.md                     # Per-revision change history (English only)
  .psa.config.json                 # psa.py project configuration
  PSScriptAnalyzerSettings.psd1    # PSScriptAnalyzer project configuration
  data/                           # Per-OS configuration profiles
    Server2016.json
    Server2019.json
    Server2022.json
    Server2025.json
  tests/                           # Python self-verification tools (r04.4+)
    README.md                      # per-tool usage guide
    catalog_probe.py               # T1: live Microsoft Update Catalog probe
    catalog_fixture_test.py        # T2: offline HTML fixture regression
    powershell_harness.py          # T3: PS function unit tests via -Action TestHarness
    eval_iso_probe.py              # T4: evaluation ISO endpoint check
    wsusscn2_probe.py              # T5: wsusscn2.cab freshness check
    common/                        # shared HTTP / parser / PS-invoke modules
    fixtures/                      # captured Catalog HTML for offline regression
    snapshots/                     # T1 output (last_probe.json)
```

The PowerShell static analyzer (`psa.py`) used to verify this script
lives at the repository-wide canonical location:
[`scripts/python/powershell-static-analyzer/`](../../python/powershell-static-analyzer/).

GitHub Actions workflows for this script live at the repository-wide
canonical location
[`.github/workflows/`](../../../.github/workflows/), with the
`scripts__powershell__update-windows-server-iso__stage<N>__<runner>.yml`
naming pattern.

If you only want to **run** the script, read this README. If you want
to **extend it or build a similar script**, also read [`SPEC.md`](./SPEC.md).
If you want to know **what has been verified and what is still
operator-pending**, read [`TESTING.md`](./TESTING.md).

## Quick start

```powershell
# 1. Unblock the file (removes the "downloaded from the internet" warning)
Unblock-File .\Update-WindowsServerIso.ps1

# 2. Allow signed-or-local scripts for the current process
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. Show registered phases (no side effects)
.\Update-WindowsServerIso.ps1 -Action ListPhases

# 4. Environment-only smoke check
.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly

# 5. Sandbox dry run for Server 2019 ja-jp (lists planned actions, no DISM writes)
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2019\2026-05' `
    -WorkRoot 'D:\UpdateWsi' `
    -DryRun

# 6. Full local build (requires -Execute; this is the only mode that actually
#    mounts and modifies WIMs)
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2019\2026-05' `
    -WorkRoot 'D:\UpdateWsi' `
    -Execute
```

## Admin actions: Config baseline management

The `data/config-<OsKey>.json` files hold the baseline data the script
uses. Two admin actions let you refresh and inspect that data
without touching any ISO. **The refresh path is two-stage**:
`RefreshSnapshots` populates the upstream `data/raw-*` /
`data/cache-*` files from Microsoft Learn + Microsoft Update
Catalog, then `RefreshAllBaselines` regenerates each
`data/config-Server*.json` `PatchBaseline.NeutralPatches[]` from
those caches. This split matches the SPEC §B.23.14 design.

```powershell
# ---- Stage 1: populate the upstream caches ----
# Fetches the Microsoft Learn release-info page (Markdown form),
# the .NET Framework release-notes index plus every monthly page,
# and probes Microsoft Update Catalog for (Server2022, Server2025) x
# (Setup, SafeOs) Dynamic Updates for the current Patch Tuesday.
# Writes:
#   data/raw-release-info.md           (and .meta.json)
#   data/cache-release-info.json
#   data/raw-dotnet-cu.json
#   data/cache-dotnet-cu.json
#   data/cache-du-Server2022.json
#   data/cache-du-Server2025.json
.\Update-WindowsServerIso.ps1 -Action RefreshSnapshots

# ---- Stage 2: regenerate the baselines from the caches ----
# Walks every OS Config in data/config-Server*.json, reads the three
# caches produced by Stage 1, resolves each KB / UpdateId via
# Microsoft Update Catalog, and writes results back to the JSON.
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines

# Initial fill: also fill in any never-verified field group with an
# auto Refresher available (PatchBaseline, LanguageSpecificPatches).
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Initial

# Force: refresh every group regardless of state.
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Force

# Dry run: show what would change without writing back. Honoured by
# both RefreshSnapshots and RefreshAllBaselines.
.\Update-WindowsServerIso.ps1 -Action RefreshSnapshots    -DryRun
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -DryRun

# Limit scope to one OS / one language (Stage 2 only).
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyOs Server2025
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyLanguage ja-jp

# Dump the field classification metadata as JSON (used by external
# Schema validators or by humans inspecting the data model).
.\Update-WindowsServerIso.ps1 -Action DumpFieldClassification
# -> <WorkRoot>/logs/A02_FieldClassification.json
```

`RefreshSnapshots` exit codes: `0` = every sub-step OK (or skipped
under `-DryRun`); non-zero = at least one sub-step failed. Re-running
is idempotent: successful sub-steps overwrite the cache with the
latest snapshot, so retrying after a transient Microsoft-side
outage is safe.

`RefreshAllBaselines` exit codes: `0` = all OK, `1` = at least one
Refresher failed, `2` = some fields require manual fill (no auto
Refresher available, typically the `LanguageSpecific.<lang>.Iso`
groups for newly-added languages).

**If `RefreshAllBaselines` reports "Discovery returned zero records"
for every OS**, the upstream caches are missing or stale. Run
`-Action RefreshSnapshots` first; the warning explicitly names the
three cache files it expects (`data/cache-release-info.json`,
`data/cache-dotnet-cu.json`, `data/cache-du-Server<N>.json`).

Per-action CSV reports are emitted to:

- `<WorkRoot>/logs/A03_RefreshSnapshots_report.csv`
- `<WorkRoot>/logs/A01_RefreshAllBaselines_report.csv`

## Requirements

| Item | Requirement |
|---|---|
| Operating system | Windows 10/11 Pro/Enterprise/Education or Windows Server 2016+ |
| PowerShell | Windows PowerShell 5.1 (recommended) or PowerShell 7+ |
| Privileges | Administrator (DISM mount requires elevation) |
| Tools | Windows ADK Deployment Tools (`oscdimg.exe`) |
| Free disk space | **100 GB on the `-WorkRoot` drive** (enforced by the workspace preflight before any Action runs; can be bypassed with `-SkipEnvCheck` at the operator's risk) |
| Network | Required for ISO and patch downloads; not needed when `-IsoPath` and `-PatchDirectory` cover all inputs |
| Hyper-V | Optional, required only for `-Action BootTest` |

Optional, only needed for development and CI:

- Python 3.10+ and `psa.py` from
  [`scripts/python/powershell-static-analyzer/`](../../python/powershell-static-analyzer/)

## Supported target OS and languages

| OS key      | Build  | Language tags    | LCU expand mode | UEFI CA 2023 |
|-------------|:------:|------------------|:---------------:|:------------:|
| Server2016  | 14393  | en-us, ja-jp     | Direct          | Not required |
| Server2019  | 17763  | en-us, ja-jp     | Direct          | Not required |
| Server2022  | 20348  | en-us, ja-jp     | Direct          | Not required |
| Server2025  | 26100  | en-us, ja-jp     | MUM/CAB expand  | Required     |

Per-OS profile JSON lives under `data/`. Each profile encodes the
build number, default `boot.wim` indexes, expected installer editions,
and per-language ISO download URLs (Eval Center FwLink primary,
Microsoft download mirror fallback).

## Phase reference

| ID  | Name                       | Group  | What it does                                                                  |
|-----|----------------------------|--------|-------------------------------------------------------------------------------|
| P01 | Initialize                 | Setup  | PowerShell env, admin, ADK, disk, Hyper-V                                     |
| P02 | ResolveInputs              | Setup  | ISO/patch source resolution, Config JSON                                      |
| P03 | RefreshPatchBaseline       | Setup  | Microsoft Update Catalogue scrape, writeback to `data/config-<OsKey>.json`         |
| P04 | FetchAssets                | Fetch  | ISO + patch downloads with hash verification                                  |
| P05 | ExpandIso                  | Plan   | Mount source ISO, copy to workspace, enumerate WIM indexes                    |
| P06 | ValidatePatchSet           | Plan   | wsusscn2.cab offline WUA scan; verify patch set covers all required KBs       |
| P07 | PatchInstallWim            | Build  | For each install.wim index: SSU then LCU then .NET, then DISM cleanup         |
| P08 | PatchBootWim               | Build  | boot.wim (PE + Setup) and winre.wim                                           |
| P09 | AssembleIso                | Build  | Dynamic Update Setup overlay, Export-WindowsImage, oscdimg ISO build          |
| P10 | ConvertPca2023BootManager  | Build  | **OPTIONAL** PCA2023 Secure Boot conversion (`-EnablePca2023BootManager`)     |
| P11 | StaticVerify               | Verify | Mount output ISO, confirm KB packages are present                             |
| P12 | VerifyPca2023Readiness     | Verify | **ALWAYS-RUNS** PCA2023 readiness inspection; emits JSON + Markdown reports   |
| P13 | FinalReport                | Report | End-of-run summary, ISO hash, log paths, PCA2023 summary integration          |

The optional `-Action BootTest` runs a Hyper-V Gen2 smoke test against
the output ISO. See SPEC.md Part B for the full per-phase contracts.

### Secure Boot / PCA2023 boot manager (r05.0+)

The Microsoft "Windows Production PCA 2011" Secure Boot signing
certificate expires in **2026-06**. Firmware that has been updated
to revoke the 2011 cert (per the BlackLotus CVE-2023-24932
mitigation rollout) will refuse to boot ISOs whose boot manager is
still signed via the 2011 chain. P10 / P12 address this:

- **P12 always runs** as part of the Verify group. It reports
  whether the produced ISO is PCA2023-ready (Healthy / Warning /
  Critical / Unknown) and emits `pca2023_readiness.json` +
  `pca2023_readiness.md` under `<WorkRoot>/pca2023/`.

- **P10 is opt-in** via `-EnablePca2023BootManager`. It re-signs
  the boot manager chain by running this script's internal
  `Convert-WimBootToPca2023Signed` (a PSA-clean re-implementation
  of Microsoft's `Make2023BootableMedia.ps1#Copy-2023BootBins`).
  Server 2025 additionally requires `-ForcePca2023OnServer2025`
  because Microsoft's certified Server 2025 platforms ship with
  the 2023 certificates already in firmware (KB 5053484 does not
  list Server 2025 as supported).

- **Source media prerequisite**: the LCU month integrated in the
  source ISO's `install.wim` must be **2024-4B (April 2024) or
  later** for Server 2016/2019/2022 (Server 2022 specifically
  needs 2025-2B per Lenovo lp2353.pdf). P10 pre-flight aborts
  with `Health=Critical` if this prerequisite is not met.

- **Standalone forensic inspection**: pass `-Pca2023OnlyMode
  -IsoPath <existing.iso>` to skip the entire build pipeline and
  run ONLY P12 against an existing ISO. No download, no DISM
  mount of install.wim, no ISO re-assembly.

**Official scope (Microsoft KB 5053484).** The upstream procedure
officially applies to Windows Server 2012/R2/2016/2019/2022 plus
Windows 10/11 client SKUs back to version 1607. **Server 2025 is
deliberately NOT listed** in the official "Applies To" set — its
firmware-provided 2023 certificates make the procedure unnecessary.
This project mirrors the official scope: Server 2016/2019/2022 are
default-targeted by P10, while Server 2025 requires explicit
`-ForcePca2023OnServer2025` opt-in. Client SKUs are out of scope
for this project entirely.

See `SPEC.md` Part D.22 (design lessons learned), `SPEC.md` B.18
(operational model), and `SPEC.md` D.23 (UEFI Secure Boot template
profiles and how to choose the right setting for your target
hardware firmware).

## Parameters (selected)

See `Get-Help .\Update-WindowsServerIso.ps1 -Full` for the complete
parameter list. The most commonly used:

| Parameter                    | Purpose                                                                 |
|------------------------------|-------------------------------------------------------------------------|
| `-Action`                    | Prepare / Build / Verify / PrepareBuildVerify / BootTest / All / Cleanup / ListPhases / GenerateManifest |
| `-OsVersion`                 | Server2016 / Server2019 / Server2022 / Server2025                       |
| `-OsLanguage`                | en-us / ja-jp                                                           |
| `-IsoPath`                   | Local ISO path (mutually exclusive with `-IsoUrl`)                      |
| `-IsoUrl`                    | Explicit ISO download URL                                               |
| `-PatchDirectory`            | Directory containing local MSU/CAB patches                              |
| `-ManifestPath`              | Metalink `.meta4` manifest with hashes                                  |
| `-PatchUrls`                 | Array of explicit patch URLs                                            |
| `-AutoDetectLatestPatches`   | Force a refresh of PatchBaseline from Microsoft Update Catalogue        |
| `-PatchMonth`                | Target patch month for refresh, e.g. `2026-06` (default: current month) |
| `-SkipDynamicPatchRefresh`   | Skip P03 even if PatchBaseline is stale (offline / air-gapped runs)   |
| `-UseBaselineOnly`           | Use PatchBaseline strictly as-is; no Catalog access at all              |
| `-IgnorePatchValidation`     | Demote P06 validation failures from abort to warning (NOT recommended)|
| `-WsusScnCabPath`            | Pre-staged wsusscn2.cab path (skips automatic download)                 |
| `-WorkRoot`                  | Workspace root. Default is `Workspace_UpdateWsi` resolved relative to the script directory (so the workspace lives next to `Update-WindowsServerIso.ps1`). Pass an absolute path to put it on a different drive (e.g. `D:\UpdateWsi`). The drive backing this path must have at least 100 GB free; the preflight aborts otherwise. |
| `-OutputDir`                 | Output ISO directory (default `<WorkRoot>\output`)                      |
| `-OnlyInstallWimIndexes`     | Comma-separated index list (e.g. `'2,4'`) to limit install.wim updates  |
| `-DryRun`                    | Skip Build / Verify phases (Setup / Fetch / Plan only)                  |
| `-SyntheticTestMode`         | CI mode: build a synthetic ISO without touching Microsoft assets        |
| `-EvalIsoMode`               | Allow downloading via Microsoft Evaluation Center fwlink                |
| `-Execute`                    | **Required** for actual DISM writes; without it, Build phases plan only |
| `-EnablePca2023BootManager`   | Opt-in for P10 PCA2023 boot manager conversion (default OFF; see Phase reference) |
| `-ForcePca2023OnServer2025`   | Override Server 2025 default-skip for P10 (advanced use only)           |
| `-Pca2023OnlyMode`            | Standalone P12 inspection of an existing ISO (`-IsoPath` required)      |
| `-Pca2023ScriptPath`          | Use an external `Make2023BootableMedia.ps1` instead of the internal helper |

## Dynamic patch baseline (P03) and dependency validation (P06)

These two phases were introduced to minimise manual patch curation
work and to prevent partial patch sets from producing broken ISOs.

### How it works

```
P02   ResolveInputs
        - Load data/config-<OsKey>.json
        - Read PatchBaseline.PatchTuesdayOfBaseline
        - Compare against Get-LatestPatchTuesday
P03 RefreshPatchBaseline (if baseline is stale OR -AutoDetectLatestPatches)
        - Scrape Microsoft Update Catalogue for the target month
        - Identify SSU + LCU + DynamicUpdate(.Setup/.Component/.SafeOs)
          + .NET CU using title-token heuristics
        - Fetch ScopedViewInline.aspx for Supersedes / SupersededBy lists
        - Write back PatchBaseline.Patches to Config JSON (atomically)
        - LCU.RequiresKbIds is auto-populated with the SSU's KB number
P04   FetchAssets (uses the freshly resolved patch URLs and SHA-256s)
P05   ExpandIso
P06 ValidatePatchSet
        - Download wsusscn2.cab to <WorkRoot>/cache/ when needed:
            * initial run (no cache yet), OR
            * post-Patch-Tuesday run AND cache is older than Patch Tuesday
        - Run Microsoft.Update.Session COM API offline scan
        - Compare WUA-required set against the provided patch set
        - On any missing required patch: ABORT and emit 4 diagnostic
          files under <WorkRoot>/diag/<timestamp>/
P07+  Build / Verify / Report (existing)
```

### Diagnostic data on validation failure

When P06 detects a missing required patch, four files are emitted under
`<WorkRoot>/diag/<yyyy-MM-dd_HH-mm-ss>/` and the script aborts:

| File | Purpose |
|---|---|
| `validation_summary.json` | Top-level result with target, wsusscn2 metadata, provided patches, and the WUA-detected missing list |
| `validation_detail.csv` | One row per patch (provided or missing) with KbId / Title / RequiredByWUA / Severity / ApplyOrder / DownloadHint |
| `wsusscn2_scan_raw.json` | Full raw WUA scan output for forensics |
| `dependency_graph.json` | Adjacency list: Requires + Supersedes edges over the KB nodes |

`-IgnorePatchValidation` demotes the abort to a warning while still
emitting all four files; use only for development.

### Refresh policy

```jsonc
"AutoRefreshPolicy": {
  "Mode": "OnNewPatchTuesday",      // refresh when stale
  "WritebackToConfig": true,         // overwrite data/config-<OsKey>.json
  "FallbackOnScrapeFailure": "UseBaseline",  // or "Abort"
  "ScrapeRetries": 3
}
```

| Scenario | Behaviour |
|---|---|
| Baseline fresh (Patch Tuesday unchanged since last verify) | P03 is a no-op |
| Baseline stale, scrape succeeds | Config is updated and the new patches are used |
| Baseline stale, scrape fails, existing baseline usable | Warning + continue with existing baseline |
| Baseline stale, scrape fails, baseline empty/unusable | ABORT |
| `-UseBaselineOnly` set | P03 skipped unconditionally (offline mode) |
| `-SyntheticTestMode` set | P03 and P06 both skipped (CI mode) |

## Static analysis

Run from the project directory:

```bash
python3 ../../python/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
```

The required gate before any commit is **0 errors / 0 warnings /
0 info**. The current `r01` baseline satisfies this.

## Self-verification tools

The `tests/` subdirectory ships five Python-based self-verification
tools (T1 - T5) that probe the script's external dependencies and
unit-test its PowerShell functions. They are **specific to this
sub-project**, not general-purpose, and use only the Python
standard library (no `pip install` required).

```bash
# Offline tests - safe to run anywhere
python3 tests/catalog_fixture_test.py    # T2: 13 fixture assertions
python3 tests/powershell_harness.py      # T3: 7 PS function assertions

# Live tests - require unrestricted network egress
python3 tests/catalog_probe.py --check all   # T1: Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4: Server<N> Iso CDN
python3 tests/wsusscn2_probe.py              # T5: wsusscn2.cab freshness
```

See [`tests/README.md`](./tests/README.md) for the full
"what to run, when" guide. The suite was added in r04.4 in
response to the three live-test bugs in r04.3 (all caused by
silent Microsoft-side change that no static analysis could have
caught).

## Continuous integration

Four GitHub Actions workflows verify and maintain this script:

| Workflow file | Runs | Triggers |
|---|---|---|
| `scripts__powershell__update-windows-server-iso__stage1__linux.yml` | psa.py + PSScriptAnalyzer (pwsh 7 on Linux) | push, PR |
| `scripts__powershell__update-windows-server-iso__stage2__windows.yml` | PSScriptAnalyzer (Windows PS 5.1) + parse + read-only smoke modes | push, PR |
| `scripts__powershell__update-windows-server-iso__stage3__synthetic.yml` | ADK install + full `-SyntheticTestMode` pipeline | push to `main`, manual |
| `scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml` | `-Action RefreshAllBaselines` then open auto-PR if `data/config-Server*.json` changed | cron `0 2 15 * *` (monthly), manual |

The workflows live at the repository root under
[`.github/workflows/`](../../../.github/workflows/). Per-workflow
change history lives in this project's
[`CHANGELOG.md`](./CHANGELOG.md) (per the repository policy
documented in the root [`SPEC.md`](../../../SPEC.md), §9).

Stage 4 (monthly-refresh) supports `workflow_dispatch` with four
inputs (`mode`, `onlyOs`, `onlyLanguage`, `dryRun`) so maintainers
can trigger an ad-hoc refresh or limit the scope without editing the
workflow. The opened PR is restricted via `add-paths` to
`data/config-*.json`, preventing accidental changes elsewhere.

CRITICAL: Stage 3 NEVER uploads an ISO artifact. The evaluation
licence forbids public distribution of Microsoft binaries.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| `Administrator privilege required` | Running as a non-elevated user | Re-launch PowerShell as Administrator |
| `oscdimg.exe not found` | Windows ADK Deployment Tools not installed | Install the ADK Deployment Tools feature |
| `Workspace preflight failed: drive ... has only NN GB free` | `-WorkRoot` drive has less than 100 GB free | Move `-WorkRoot` to a larger volume, or free up space; the 100 GB minimum covers an end-to-end PrepareBuildVerify run for one OS |
| `Workspace preflight failed: ... required Config file(s) missing` | The `data/config-Server<N>.json` files were deleted, renamed, or not copied when the script was relocated | Restore the `data/` directory alongside `Update-WindowsServerIso.ps1`; all four `Server2016.json` / `Server2019.json` / `Server2022.json` / `Server2025.json` must be present |
| `Catalogue: no narrowed result for ... / Server2022` (or any OS), `Resolved 0 patch entries` | Microsoft changed the Catalogue title format (punctuation drift, e.g. comma removal) | Inspect `Get-CatalogQueryTemplate` and `Get-LanguagePackQueryTemplate.osTitleTokens`; add the new title form to the relevant `TitleTokens` array. See SPEC §D.19 |
| Wrong `Type` on `NeutralPatches[]` entries after RefreshAllBaselines | A new caller of `Convert-CatalogPatchToBaselineEntry` did not pass `-KnownType` | Pass `-KnownType $q.Type` from the Catalogue search context. See SPEC §D.20 |
| .NET CU baseline entry seems to be missing a sub-file | Umbrella KB with multiple .msu files; only one was kept | Confirm `Resolve-PatchSetFromCatalog` routes `Type='DotNet'` through `Select-AllCanonicalPatchFiles`. See SPEC §D.21 |
| `0x800f081e` in Warning lines | Patch not applicable to this SKU | Expected for cross-SKU patch sets; safe to ignore |
| Stale WIM mount | Previous run crashed | Run `dism /Get-MountedImageInfo` and `dism /Cleanup-Mountpoints` |
| ISO SHA-256 mismatch | Snapshot URL was rotated by Microsoft | Update `data/config-<OsKey>.json` `IsoSha256` to the new value |

## Acknowledgements

- The DISM mount + dismount retry pattern (10 s + 30 s) is borrowed
  from [OSDBuilder](https://github.com/OSDeploy/OSDBuilder) (David
  Segura), specifically the `Dismount-InstallwimOS` helper.
- The 0x800f081e suppression heuristic is also from OSDBuilder.
- The three-tier `etfsboot.com` / `efisys.bin` fallback chain comes
  from
  [Win_ISO_Patching_Scripts_zhCN](https://github.com/adavak/Win_ISO_Patching_Scripts_zhCN).
- The Debug Trace Facility, logging conventions, environment-check
  cmdlets, and retry primitives are reused verbatim from the
  companion in-house script
  [`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1).
- The canonical Server 2022 SHA-256 hash was sourced from
  [rgl/windows-evaluation-isos-scraper](https://github.com/rgl/windows-evaluation-isos-scraper).

This script was generated and iteratively refined with Anthropic
Claude (Opus 4.7 era; baseline revision r01 on 2026-05-24).
