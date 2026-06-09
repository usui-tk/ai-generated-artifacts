---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-08
---
# Update-WindowsServerIso.ps1

| Stage | Status |
|:---|:---|
| STAGE 1 — Linux checks (psa.py + PSScriptAnalyzer on pwsh 7) | [![STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml) |
| STAGE 2 — Windows checks (PSScriptAnalyzer on Windows PS 5.1 + smoke test) | [![STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml) |
| STAGE 3 — Synthetic full pipeline (Windows + ADK) | [![STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml) |
| STAGE 4 — Monthly baseline refresh (cron) | [![STAGE 4](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml) |

**English** | [日本語](README.ja.md)

Integrate the latest Microsoft Servicing Stack Update, Latest Cumulative
Update, Dynamic Updates, and .NET Framework cumulative updates into a
Windows Server evaluation ISO, and re-emit a bootable ISO whose embedded
`install.wim`, `boot.wim`, and `winre.wim` already contain those
updates. Targeted at Windows 11 / Windows Server 2016+ host with
Windows PowerShell 5.1 (also runs on PowerShell 7+).

This script is part of the
[`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
repository, under `projects/powershell-update-windows-server-iso/`.

## Why this script exists

Windows Update is the standard way to keep a deployed server current,
but it is **the wrong tool when the same patched OS image must appear
on dozens of machines, repeatedly, predictably, and quickly**. This
script targets four operational scenarios that Windows Update cannot
solve well on its own:

- **Lab / test bring-up at scale**. Spinning up several Server VMs from
  a stale evaluation ISO and then running Windows Update on each takes
  hours per VM. Building one patched ISO once and reusing it cuts the
  per-VM patch time to zero.
- **PCA2011 boot-manager cert expiry (2026-06)**. The Microsoft Windows
  Production PCA 2011 certificate, which signs the boot manager of
  Server 2016 / 2019 / 2022 evaluation ISOs, expires in 2026-06.
  Firmware that has been updated to revoke the 2011 certificate (per
  the BlackLotus CVE-2023-24932 mitigation rollout) refuses to boot
  ISOs whose boot manager is still on the 2011 chain. This script's
  P10 phase re-signs the boot manager via the **'Windows UEFI CA 2023'**
  chain so the resulting ISO boots on revoked-firmware hardware.
- **Air-gapped / offline labs**. Lab networks with no internet egress
  cannot use Windows Update. The script accepts pre-staged MSU / CAB
  files via `-PatchDirectory` so the entire build can run offline.
- **Reproducible patch baselines**. Compliance and forensic-replay
  scenarios require an audited "what was inside this ISO at build time"
  record. The Config baseline (`data/config-Server*.json`) and the
  CHANGELOG together provide that audit trail.

### Who this is for, and who it is not for

| Suitable for | Out of scope |
|:---|:---|
| Infrastructure engineers building lab / pre-production Windows Server fleets | Production patch management (use WSUS, Microsoft Update, or Azure Update Manager) |
| Cloud consultants who need repeatable evaluation-ISO deliverables | Hotpatch in-memory patching (Azure Edition SKU only) |
| Anyone testing PCA2023 readiness against revoked-firmware hardware | Client SKUs (Windows 10 / 11) — out of scope |
| Forensic / compliance replay of past patch baselines (`-PatchMonth`) | ARM64 (x64 only at present) |
| Pre-Patch-Tuesday dry runs against `wsusscn2.cab` (r09.0+) | Driver / FOD / LXP / Appx customization |

### Reader's roadmap

- If you want to **run** the script, this README is enough.
- If you want to **extend it or build a similar script**, also read
  [`SPEC.md`](./SPEC.md) (developer / LLM specification).
- For **verification procedures and recorded results**, see
  [`TESTING.md`](./TESTING.md).
- For **per-revision change history**, see [`CHANGELOG.md`](./CHANGELOG.md).
- For the **repository-wide LLM-agent operating guide** (governance hierarchy, ground-truth extraction, Doc-Touching Matrix, Part A inheritance rule, anti-patterns), see [`AGENTS.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md) at the repository root.
- The **repository-wide** Language Policy, File Format Policy, Disclaimer, and Contribution rules live at the [root `README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md), [`CONTRIBUTING.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/CONTRIBUTING.md), and [`SECURITY.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SECURITY.md).

## ⚠️ Disclaimer

**USE AT YOUR OWN RISK.** This script is provided "AS IS" without
warranty of any kind, express or implied. The authors and contributors
are not liable for any damages, data loss, system corruption, account
suspension, network issues, disk space exhaustion, or any other
problems — direct or indirect — that may arise from using, modifying,
or distributing this script.

By running this script, you acknowledge that:

- You are solely responsible for verifying that your use complies with
  Microsoft's Evaluation Center licence terms and any applicable laws
  or regulations. Microsoft Server evaluation ISOs are time-limited
  and are licensed for evaluation use only.
- You are responsible for any consequences of running DISM against
  WIM images (mount failures can leave stale mount-cache state;
  partial updates can produce non-bootable ISOs; PCA2023 conversion
  can render an ISO unbootable on firmware that doesn't trust the 2023
  certificates).
- You will respect intellectual-property rights — the downloaded
  Microsoft binaries (ISO, MSU, CAB, .NET CU) remain the property of
  Microsoft and may not be redistributed.
- You will review the script's source code before running it in any
  environment. **In particular, never run `-Execute` against a host
  whose disk volume holds production data**: DISM mount operations
  can corrupt the mount point on abnormal termination.
- You will keep the produced ISO inside its evaluation-licence
  boundary. Re-distributing a patched evaluation ISO publicly violates
  the Microsoft licence.

For the full disclaimer and self-responsibility terms that apply to
all artifacts in this repository, see the
[root README](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md)
([Japanese](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.ja.md)).

## License

This project is part of the `usui-tk/ai-generated-artifacts` repository,
which is licensed under the **MIT License**. See the
[`LICENSE`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/LICENSE) file at the repository root for the full
license text.

In short: you are free to use, modify, and distribute this software for
any purpose, provided that the original copyright and license notices
are preserved. The software is provided without warranty, as detailed
in the Disclaimer above and in the LICENSE file. Microsoft binaries
downloaded by the script (ISO / MSU / CAB) remain under Microsoft's
own licences and are not redistributed by this project.

## Folder layout

```
projects/powershell-update-windows-server-iso/
├── Update-WindowsServerIso.ps1     # Main script
├── README.md / README.ja.md         # End-user documentation (you are reading these)
├── SPEC.md (English only)            # Developer / LLM specification
├── TESTING.md (English only)         # Verification procedures
├── CHANGELOG.md (English only)       # Per-revision change history
├── .psa.config.json                  # psa.py project configuration
├── PSScriptAnalyzerSettings.psd1     # PSScriptAnalyzer project configuration
├── data/                             # Persistent inputs (committed, flat layout)
│   ├── config-Server{2016,2019,2022,2025}.json
│   ├── raw-release-info.md (+ .meta.json)
│   ├── raw-dotnet-cu.json
│   ├── cache-release-info.json
│   ├── cache-dotnet-cu.json
│   └── cache-dynamicupdate-Server{2022,2025}.json
├── tests/                            # Self-verification suite (T1-T19 + gates)
└── docs/history/                     # Per-cycle investigation reports
```

The PowerShell static analyzer (`psa.py`) used to verify this script
lives at the repository-wide canonical location:
[`quality-tools/powershell-static-analyzer/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/quality-tools/powershell-static-analyzer/).

## Quick start

```powershell
# 1. Unblock the file and allow local scripts for this process
Unblock-File .\Update-WindowsServerIso.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 2. Read-only orientation (no writes)
.\Update-WindowsServerIso.ps1 -Action ListPhases
.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly
```

### Template (fill in the placeholders)

Use a per-OS `-WorkRoot` so concurrent or repeated runs never share a
DISM mount cache, and auto-timestamp the log so each run is its own file
(no manual date typing):

```powershell
$OsVersion  = 'Server2019'                       # Server2016/2019/2022/2025
$OsLanguage = 'ja-jp'                             # en-us / ja-jp
$IsoPath    = 'D:\ISO\WS2019_ja-jp.iso'
$PatchDir   = 'D:\Patches\Server2019\2026-05'
$WorkRoot   = "D:\UpdateWsi-$OsVersion"           # per-OS workspace
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile    = Join-Path $WorkRoot ('logs\{0}-{1}-{2}.log' -f 'PrepareBuildVerify', $OsVersion, $stamp)

# Dry run first (Setup / Fetch / Plan only; no DISM writes)
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion $OsVersion -OsLanguage $OsLanguage `
    -IsoPath $IsoPath -PatchDirectory $PatchDir `
    -WorkRoot $WorkRoot -LogFile $LogFile

# Real build — add -Execute (the only mode that mounts and modifies WIMs)
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion $OsVersion -OsLanguage $OsLanguage `
    -IsoPath $IsoPath -PatchDirectory $PatchDir `
    -WorkRoot $WorkRoot -LogFile $LogFile `
    -Execute
```

### Worked example: Server 2016 vs Server 2025

The two OSes differ in the PCA2023 boot-manager switches. Server 2016
needs no PCA2023 handling; Server 2025 skips P10 by default and needs
both `-EnablePca2023BootManager` and `-ForcePca2023OnServer2025` to opt
in.

```powershell
# Server 2016 (no PCA2023 switches)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2016 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2016_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2016\2026-05' `
    -WorkRoot 'D:\UpdateWsi-Server2016' `
    -LogFile ('D:\UpdateWsi-Server2016\logs\build-2016-{0}.log' -f $stamp) `
    -Execute

# Server 2025 (opt in to PCA2023 conversion)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2025 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2025_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2025\2026-05' `
    -WorkRoot 'D:\UpdateWsi-Server2025' `
    -LogFile ('D:\UpdateWsi-Server2025\logs\build-2025-{0}.log' -f $stamp) `
    -EnablePca2023BootManager -ForcePca2023OnServer2025 `
    -Execute
```

Without `-Execute`, the Build phases plan but do not commit any DISM
write. This is the **sandbox-by-default** posture documented in
[SPEC.md](./SPEC.md) §D.12.


## Action reference (14 Actions)

The script's `param() ValidateSet` declares fourteen Actions, grouped
by purpose. The default is `PrepareBuildVerify`.

### Standard pipeline Actions

| Action | Phases run | Description |
|:---|:---|:---|
| `Prepare` | P01-P06 | Stage only (no patching, no DISM mount) |
| `Build` | P07-P10 | Patch and assemble (presumes Prepare already staged the workspace) |
| `Verify` | P11-P13 | Verify an existing output ISO (presumes a prior Build -Execute produced it) |
| `PrepareBuildVerify` (default) | P01-P13 | Combined full pipeline |
| `All` | P01-P13 + extras | Full pipeline + post-pipeline steps |

### Specialty Actions

| Action | Description |
|:---|:---|
| `BootTest` | Hyper-V Gen2 boot smoke test against the output ISO (mutually exclusive with `-SyntheticTestMode`) |
| `GenerateManifest` | Compute a manifest of resolved patches (P01-P03 only) |
| `Cleanup` | Clean up workspace and stale DISM mounts |
| `ListPhases` | Dump phase + action registry as JSON |
| `TestHarness` | Eval-PS-function REPL mode used by `tests/powershell_harness.py` (T3); not for human invocation |

### Admin Actions (Config baseline management)

The `data/config-<OsKey>.json` files hold the baseline data the script
uses. Four Admin Actions let you refresh and inspect that data without
touching any ISO. **The refresh path is two-stage**: `RefreshSnapshots`
populates the upstream `data/raw-*` / `data/cache-*` files from
Microsoft Learn + Microsoft Update Catalog, then `RefreshAllBaselines`
regenerates each `data/config-Server*.json` `PatchBaseline.NeutralPatches[]`
from those caches. This split follows the SPEC §B.22.1 refresher architecture.

| Action | Admin Phase | Description |
|:---|:-:|:---|
| `RefreshSnapshots` | A03 | Fetch upstream caches (release-info, .NET CU, Dynamic Update) |
| `RefreshAllBaselines` | A01 | Regenerate `data/config-Server*.json` from the caches |
| `DumpFieldClassification` | A02 | Emit the field-cadence decision matrix as JSON |
| `RefreshDependencyDatabase` | A04 | Refresh `data/servicing-dependency-database.json` (layer 2) from `wsusscn2.cab` via the four-stage parser pipeline (SPEC §B.19.7) |

```powershell
# ---- Stage 1: populate the upstream caches ----
.\Update-WindowsServerIso.ps1 -Action RefreshSnapshots

# ---- Stage 2: regenerate the baselines from the caches ----
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines

# Initial fill (also populate never-verified fields with an auto Refresher available)
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Initial

# Force (refresh every group regardless of state)
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Force

# Limit scope to one OS / one language (Stage 2 only)
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyOs Server2025
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyLanguage ja-jp

# Dump the field classification metadata as JSON (used by external validators)
.\Update-WindowsServerIso.ps1 -Action DumpFieldClassification

# Refresh the Servicing Dependency Database (layer 2) from wsusscn2.cab
#   Full pipeline: Stage 1 cab acquire -> Stage 2 7-Zip extract ->
#   Stage 3 XmlReader stream-parse -> Stage 4 emit
#   data/servicing-dependency-database.json -> Layer 1 config writeback.
#   (Windows + 7-Zip required; Stage 3 parse takes ~4-5 min on the live cab.)
.\Update-WindowsServerIso.ps1 -Action RefreshDependencyDatabase
```

`RefreshSnapshots` exit codes: `0` = every sub-step OK; non-zero =
at least one sub-step failed. Re-running is idempotent.

`RefreshAllBaselines` exit codes: `0` = all OK; `1` = at least one
Refresher failed; `2` = some fields require manual fill (no auto
Refresher available, typically the `LanguageSpecific.<lang>.Iso`
groups for newly-added languages).

## Requirements

| Item | Requirement |
|:---|:---|
| Host OS | Windows 10/11 Pro/Enterprise/Education or Windows Server 2016+ |
| PowerShell | Windows PowerShell 5.1+ (also runs on PowerShell 7+); 64-bit process required |
| Privileges | Administrator (DISM Mount requires elevation) |
| Windows ADK | Deployment Tools feature (provides `oscdimg.exe`); auto-installable via `-AutoInstallAdk` |
| Disk space | 100 GB free on the `-WorkRoot` drive (60 GB minimum, 100 GB enforced by Workspace preflight) |
| Network | Internet access for ISO / patch downloads (when not using `-IsoPath` + `-PatchDirectory`) |
| Static analysis | `python3` + the canonical `psa.py` for static analysis (see "Static analysis" below) |

## Supported target OS and languages

| OS | Languages | Notes |
|:---|:---|:---|
| Server 2016 | en-us, ja-jp | LCU 2024-4B or later required for PCA2023 conversion |
| Server 2019 | en-us, ja-jp | LCU 2024-4B or later required for PCA2023 conversion |
| Server 2022 | en-us, ja-jp | LCU 2025-2B (build 20348.2227) or later required for PCA2023 conversion |
| Server 2025 | en-us, ja-jp | PCA2023 not required by default; firmware-provided 2023 certificates |

Adding a new language is a single-node addition under
`LanguageSpecific` in the relevant `data/config-Server<N>.json`. See
SPEC.md §B.4.5.

## Phase reference

Pipeline of thirteen phases:

| ID | Name | Group | What it does |
|:---|:---|:---|:---|
| P01 | Initialize | Setup | PowerShell environment, admin, ADK, disk, Hyper-V |
| P02 | ResolveInputs | Setup | ISO / patch source resolution, Config JSON load |
| P03 | RefreshPatchBaseline | Setup | Microsoft Update Catalogue scrape; writeback to `data/config-<OsKey>.json` |
| P04 | FetchAssets | Fetch | ISO + patch downloads with hash verification |
| P05 | ExpandIso | Plan | Mount source ISO; copy to workspace; enumerate WIM indexes |
| P06 | ValidatePatchServicing | Plan | Servicing-readiness gate vs the `data/` Layer 2 database (default-ON, blocking) |
| P07 | PatchInstallWim | Build | For each install.wim index: SSU → LCU → .NET → DISM cleanup |
| P08 | PatchBootWim | Build | boot.wim (PE + Setup) and winre.wim |
| P09 | AssembleIso | Build | Dynamic Update Setup overlay; Export-WindowsImage; oscdimg ISO build |
| P10 | ConvertPca2023BootManager | Build | **Opt-in** PCA2023 Secure Boot conversion (`-EnablePca2023BootManager`) |
| P11 | StaticVerify | Verify | Mount output ISO; confirm KB packages are present |
| P12 | VerifyPca2023Readiness | Verify | **Always runs** — emits `pca2023_readiness.json` + `.md` |
| P13 | FinalReport | Report | End-of-run summary; ISO hash; log paths |

See [SPEC.md](./SPEC.md) Part B for the full per-phase contracts.

### Secure Boot / PCA2023 boot manager (r05.0+)

The Microsoft "Windows Production PCA 2011" Secure Boot signing
certificate expires in **2026-06**. Firmware that has been updated to
revoke the 2011 cert refuses to boot ISOs whose boot manager is still
signed via the 2011 chain. P10 / P12 address this; the full operational
model (per-OS defaults, when to set `-ForcePca2023OnServer2025`,
standalone `-Pca2023OnlyMode` forensic inspection) is documented in
SPEC.md §B.17 and §B.18.

Common operator decisions:

- **Server 2016 / 2019 / 2022**: P10 is required if you target firmware
  that has revoked PCA2011 from DBX. Enable with
  `-EnablePca2023BootManager`. The source ISO's `install.wim` LCU month
  must be 2024-4B (April 2024) or later (Server 2022 specifically
  needs 2025-2B per Lenovo lp2353.pdf).
- **Server 2025**: P10 is default-skipped (Microsoft-certified Server
  2025 platforms ship the 2023 certificates in firmware; KB5053484
  does not list Server 2025 as needing the procedure). Override with
  `-ForcePca2023OnServer2025` only when running on non-certified
  hardware that requires PCA2023 conversion.
- **Forensic inspection** of an existing ISO: pass `-Pca2023OnlyMode
  -IsoPath <existing.iso>` to skip the entire build pipeline and run
  ONLY P12 against the ISO.

Full design and verification details: SPEC.md §B.17 (PCA2023 boot
manager support) and §B.18 (Output ISO verification).

## Parameters (complete)

All 35 parameters are listed below, grouped by typical use. The table is
a documentation-time snapshot; the authoritative, always-current list is
`Get-Help .\Update-WindowsServerIso.ps1 -Full`.

| Parameter | Category | Default / ValidateSet | Purpose |
|:---|:---|:---|:---|
| `-Action` | common | `PrepareBuildVerify`; one of the 14 Actions | Which action/pipeline to run |
| `-OsVersion` | common | `Server2016`/`2019`/`2022`/`2025` | Target OS family |
| `-OsLanguage` | common | `en-us` (or `ja-jp`) | Target OS language |
| `-Execute` | common | switch (OFF) | **Required** for real DISM writes; without it Build phases plan only |
| `-WorkRoot` | common | `Workspace_UpdateWsi` (next to script) | Workspace root; drive needs >= 100 GB free |
| `-LogFile` | common | (none) | `Start-Transcript` path for the whole run |
| `-OutputDir` | common | `<WorkRoot>\output` | Output ISO directory |
| `-CleanWorkRoot` | common | switch (OFF) | Clean the workspace before running |
| `-IsoPath` | input | (none) | Local source ISO path (mutually exclusive with `-IsoUrl`) |
| `-IsoUrl` | input | (none) | Explicit source ISO download URL (mutually exclusive with `-IsoPath`) |
| `-EvalIsoMode` | input | switch (OFF) | Allow Microsoft Evaluation Center fwlink download |
| `-PatchDirectory` | input | (none) | Directory of local MSU/CAB patches |
| `-PatchUrls` | input | (none) | Array of explicit patch URLs |
| `-ManifestPath` | input | (none) | Metalink `.meta4` manifest with hashes |
| `-OnlyPhases` | advanced | (none) | Phase-ID array (e.g. `'P04','P07'`) overriding the Action's phase set |
| `-OnlyInstallWimIndexes` | advanced | (none) | Comma-separated index list (e.g. `'2,4'`) limiting install.wim updates |
| `-AutoDetectLatestPatches` | patch | switch (OFF) | Force a P03 PatchBaseline refresh from the Catalog |
| `-PatchMonth` | patch | current month | Target patch month for refresh, e.g. `2026-06` |
| `-SkipDynamicPatchRefresh` | patch | switch (OFF) | Skip P03 even if baseline is stale (offline runs) |
| `-UseBaselineOnly` | patch | switch (OFF) | Use PatchBaseline strictly as-is; no Catalog access |
| `-OfflineSyncPackagePath` | patch | (none) | Pre-staged `wsusscn2.cab` path (skips download) |
| `-EnablePca2023BootManager` | secure-boot | switch (OFF) | Opt-in P10 PCA2023 boot-manager conversion |
| `-ForcePca2023OnServer2025` | secure-boot | switch (OFF) | Override the Server 2025 default-skip for P10 |
| `-Pca2023OnlyMode` | secure-boot | switch (OFF) | Standalone P12 inspection of an existing ISO (`-IsoPath` required) |
| `-Pca2023ScriptPath` | secure-boot | (none) | External `Make2023BootableMedia.ps1` instead of the internal helper |
| `-Mode` | admin | `Monthly` (or `Initial`/`Force`) | `RefreshAllBaselines` refresh mode |
| `-OnlyOs` | admin | `Server2016`/`2019`/`2022`/`2025` | Limit `RefreshAllBaselines` to one OS |
| `-OnlyLanguage` | admin | `en-us`/`ja-jp` | Limit `RefreshAllBaselines` to one language |
| `-AutoInstallAdk` | admin | switch (OFF) | Auto-install Windows ADK if `oscdimg.exe` is missing |
| `-DryRun` | test | switch (OFF) | Setup/Fetch/Plan only; skip Build/Verify |
| `-SyntheticTestMode` | test | switch (OFF) | CI mode: synthetic ISO, no Microsoft assets |
| `-SkipEnvCheck` | test | switch (OFF) | Skip the environment preflight (mutually exclusive with `-EnvironmentInfoOnly`) |
| `-EnvironmentInfoOnly` | test | switch (OFF) | Print environment info and exit (mutually exclusive with `-SkipEnvCheck`) |

### Mutual exclusivity rules

The script enforces several mutual-exclusion constraints:

- `-IsoUrl` / `-IsoPath`
- `-EnvironmentInfoOnly` / `-SkipEnvCheck`
- `-Action BootTest` / `-SyntheticTestMode`
- `-SyntheticTestMode` / `-EvalIsoMode`
- `-SkipDynamicPatchRefresh` / `-AutoDetectLatestPatches`
- `-UseBaselineOnly` / `-AutoDetectLatestPatches`

`-PatchMonth` must match the `YYYY-MM` form (e.g. `2026-06`).


## Dynamic patch baseline (P03) and dependency validation (P06)

These two phases minimise manual patch curation and prevent partial
patch sets from producing broken ISOs.

### How it works

```
P02   ResolveInputs
        - Load data/config-<OsKey>.json
        - Read PatchBaseline.PatchTuesdayOfBaseline
        - Compare against Get-LatestPatchTuesday
P03 RefreshPatchBaseline (if baseline is stale OR -AutoDetectLatestPatches)
        - Scrape Microsoft Update Catalogue for the target month
        - Identify SSU + LCU + DynamicUpdate(.Setup/.Component/.SafeOs)
          + .NET CU using config-driven title-token narrowing
        - Fetch ScopedViewInline.aspx for Supersedes / SupersededBy lists
        - Write back PatchBaseline.NeutralPatches to Config JSON (atomically)
P04   FetchAssets (uses the freshly resolved patch URLs and SHA-256s)
P05   ExpandIso
P06 ValidatePatchServicing
        - Servicing-readiness gate (default-ON, blocking) using
          data/servicing-dependency-database.json (see SPEC.md §B.19.10).
          Validates the resolved patch set against the pre-generated
          Layer 2 dependency database and logs each verdict
          (SsTooOld / NotInDatabase / Superseded / Pass).
        - Blocks on OverallStatus Fail (SsTooOld predicts 0x800f0823, or
          NotInDatabase); warns on Superseded; passes otherwise.
        - Blocks if Layer 2 is absent/unreadable (run -Action
          RefreshDependencyDatabase, or pass -UseBaselineOnly to skip P06).
        - The former live Windows Update Agent offline scan was removed
          (host-relative; produced false negatives on cross-OS builds).
P07+  Build / Verify / Report
```

### Diagnostic data and logs

For troubleshooting a run, these are the files to look at:

| File | When | Content |
|:---|:---|:---|
| `<LogFile>` | When `-LogFile <path>` is passed | Full `Start-Transcript` of the run (every console line) |
| `<WorkRoot>/logs/debugtrace.jsonl` | Always (when a phase uses the trace) | Per-step JSONL trace pinpointing the exact failing step |

### Refresh policy

```jsonc
"AutoRefreshPolicy": {
  "Mode": "OnNewPatchTuesday",       // refresh when stale
  "WritebackToConfig": true,          // overwrite data/config-<OsKey>.json
  "FallbackOnScrapeFailure": "UseBaseline",   // or "Abort"
  "ScrapeRetries": 3
}
```

| Scenario | Behaviour |
|:---|:---|
| Baseline fresh (Patch Tuesday unchanged since last verify) | P03 is a no-op |
| Baseline stale, scrape succeeds | Config is updated and the new patches are used |
| Baseline stale, scrape fails, existing baseline usable | Warning + continue with existing baseline |
| Baseline stale, scrape fails, baseline empty/unusable | ABORT |
| `-UseBaselineOnly` set | P03 skipped unconditionally (offline mode) |
| `-SyntheticTestMode` set | P03 and P06 both skipped (CI mode) |

Full decision matrix: SPEC.md §B.14.

## Static analysis

Run from the project directory:

```bash
python3 ../../python/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
```

The required gate before any commit is **0 errors / 0 warnings / 0
info**. The current build satisfies this; see TESTING.md §0 for the
last-verified row.

## Self-verification tools

The `tests/` subdirectory ships nineteen Python-based self-verification
tools (T1 – T19) plus the data-contract and format gates. They probe the
script's external dependencies, unit-test its PowerShell functions, and
enforce the SPEC §B.23 JSON canonical format. All offline tools use only
the Python standard library (no `pip install` required).

```bash
# Offline tests — safe to run anywhere
python3 tests/catalog_fixture_test.py        # T2: 13 fixture assertions
python3 tests/powershell_harness.py          # T3: 10 PS function assertions
python3 tests/release_info_parser_test.py    # T6: 13 release-info parser assertions
python3 tests/dotnet_cu_parser_test.py       # T7: 16 .NET CU parser assertions
python3 tests/dynamic_update_cache_test.py   # T8: 20 DU cache assertions
python3 tests/catalog_title_tokens_test.py   # T9: 18 Title-token assertions
python3 tests/release_info_resolver_test.py  # T10: 22 resolver assertions
python3 tests/canonical_json_test.py         # T11: 26 PS/Python byte-level parity assertions
python3 tests/servicing_dependency_parser_test.py            # T12: 22 wsusscn2 parser pipeline assertions
python3 tests/servicing_dependency_layer1_test.py            # T13: 14 Layer 1 writeback assertions
python3 tests/servicing_dependency_deny_list_test.py         # T14: 10 EOS/ESU deny-list assertions
python3 tests/servicing_dependency_servicing_stack_test.py   # T15: 16 servicing-stack extraction assertions
python3 tests/servicing_dependency_readiness_verdict_test.py # T16: 21 readiness verdict assertions
python3 tests/servicing_dependency_recency_fallback_test.py  # T17: 15 recency-fallback assertions
python3 tests/servicing_dependency_servicing_stack_populate_test.py # T18: 17 SS-populate assertions
python3 tests/servicing_dependency_data_contract_test.py     # T19: 11 data-contract assertions

# Data-contract / schema / format gates (run on every commit that touches data)
python3 tests/config_schema_test.py                       # config schema gate
python3 tests/servicing_dependency_scope_invariants_test.py # scope-invariants gate: 23 assertions
python3 tests/servicing_dependency_layer2_schema_test.py  # Layer 2 schema gate: 16 assertions
python3 tests/canonical_json_format_check.py              # JSON canonical-format gate; SPEC §C.3.4

# Live tests — require unrestricted network egress
python3 tests/catalog_probe.py --check all   # T1: Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4: Server<N> ISO CDN
python3 tests/wsusscn2_probe.py              # T5: wsusscn2.cab freshness
```

See [`tests/README.md`](./tests/README.md) for the canonical
"what to run, when" guide. Full design and CI mapping: SPEC.md §C.9.

## Continuous integration

Four GitHub Actions workflows verify and maintain this script:

| Workflow file | Runs | Triggers |
|:---|:---|:---|
| `...__stage1__linux.yml` | psa.py + PSScriptAnalyzer (pwsh 7 on Linux) | push, PR |
| `...__stage2__windows.yml` | PSScriptAnalyzer (Windows PS 5.1) + parse + read-only smoke modes | push, PR |
| `...__stage3__synthetic.yml` | ADK install + full `-SyntheticTestMode` pipeline | push to `main`, manual |
| `...__stage4__monthly-refresh.yml` | `-Action RefreshAllBaselines`; open auto-PR if `data/config-Server*.json` changed | cron `0 2 15 * *` (monthly), manual |

The workflows live at
[`.github/workflows/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/.github/workflows/). Per-workflow
change history lives in this project's [`CHANGELOG.md`](./CHANGELOG.md)
(per the repository policy documented in the root
[`SPEC.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SPEC.md) §9).

Stage 4 supports `workflow_dispatch` with four inputs (`mode`,
`onlyOs`, `onlyLanguage`, `dryRun`) so maintainers can trigger an
ad-hoc refresh or limit the scope without editing the workflow. The
opened PR is restricted via `add-paths` to `data/config-*.json` (and
in r09.0+, `data/servicing-dependency-database.json`).

CRITICAL: Stage 3 NEVER uploads an ISO artifact. The evaluation
licence forbids public distribution of Microsoft binaries; the
workflow's explicit `actions/upload-artifact` `path:` enumeration
enforces this per repository SPEC.md §12 (SPEC-CI-081).

## Troubleshooting

| Symptom | Cause | Action |
|:---|:---|:---|
| `Administrator privilege required` | Running as a non-elevated user | Re-launch PowerShell as Administrator |
| `oscdimg.exe not found` | Windows ADK Deployment Tools not installed | Re-run with `-AutoInstallAdk` (auto-installs the ~50-80 MB Deployment Tools feature) or install manually from the [Windows ADK installer](https://go.microsoft.com/fwlink/?linkid=2289980). See SPEC.md §B.22.13 |
| `Workspace preflight failed: drive ... has only NN GB free` | `-WorkRoot` drive has less than 100 GB free | Move `-WorkRoot` to a larger volume, or free up space (the 100 GB minimum covers an end-to-end PrepareBuildVerify run for one OS) |
| `Workspace preflight failed: ... required Config file(s) missing` | The `data/config-Server<N>.json` files were deleted or not copied | Restore the `data/` directory alongside `Update-WindowsServerIso.ps1` (all four `Server2016/2019/2022/2025.json` must be present) |
| `Catalogue: no narrowed result for ... / Server2022`; `Resolved 0 patch entries` | Microsoft changed the Catalogue title format (punctuation drift) | Add the new title form to the relevant `TitleTokens` array in `data/config-Server*.json`. See SPEC.md §D.19 |
| Wrong `Type` on `NeutralPatches[]` entries after RefreshAllBaselines | A new caller of `Convert-CatalogPatchToBaselineEntry` did not pass `-KnownType` | Pass `-KnownType $q.Type` from the Catalogue search context. See SPEC.md §D.20 |
| .NET CU baseline entry seems to be missing a sub-file | Umbrella KB with multiple `.msu` files; only one was kept | Confirm `Resolve-PatchSetFromCatalog` routes `Type='DotNet'` through `Select-AllCanonicalPatchFiles`. See SPEC.md §D.21 |
| `0x800f081e` in Warning lines | Patch not applicable to this SKU | Expected for cross-SKU patch sets; safe to ignore (see SPEC.md §D.8) |
| `0x800f0823 — CBS_E_NEW_SERVICING_STACK_REQUIRED` mid-P07 | LCU's prerequisite SSU is missing from the baseline | Add the prerequisite SSU to `NeutralPatches[]`. The Servicing Dependency Database (SPEC.md §B.19) catches this at P06, a blocking gate, before any DISM mount. See SPEC.md §D.2 |
| Mojibake (doubled Japanese characters) in P05 WIM-index banner | DISM mount-cache poisoning from prior aborted runs | Use **one fresh `-WorkRoot` per OS family** (`D:\UpdateWsi_2016`, `D:\UpdateWsi_2019`, …). See SPEC.md §D.25 |
| Stale WIM mount blocks new run | Previous run crashed mid-mount | Run `dism /Get-MountedImageInfo` then `dism /Cleanup-Mountpoints`. See SPEC.md §D.1 |
| ISO SHA-256 mismatch on download | Microsoft rotated the Evaluation Center snapshot URL | Update `data/config-<OsKey>.json` `LanguageSpecific.<lang>.Iso.Sha256` to the new value. See SPEC.md §D.11 |

For broader investigation context, the per-cycle finding reports under
[`docs/history/`](./docs/history/) carry deep-dive narratives of the
issues that motivated each Pitfall entry in SPEC.md Part D.

## Acknowledgements

- The DISM mount + dismount retry pattern (10 s + 30 s) is borrowed
  from [OSDBuilder](https://github.com/OSDeploy/OSDBuilder) (David
  Segura), specifically the `Dismount-InstallwimOS` helper.
- The 0x800f081e suppression heuristic is also from OSDBuilder.
- The three-tier `etfsboot.com` / `efisys.bin` fallback chain comes
  from [Win_ISO_Patching_Scripts_zhCN](https://github.com/adavak/Win_ISO_Patching_Scripts_zhCN).
- The Debug Trace Facility, logging conventions, environment-check
  cmdlets, and retry primitives are reused verbatim from the companion
  in-house script
  [`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1).
- The 7-Zip helper trio (`Get-SevenZipPath`, `Get-LatestSevenZipUrl`,
  `Install-SevenZipFallback`) is reused from
  `Deploy-AMDChipsetDriverOnWindowsServer.ps1`.
- The canonical Server 2022 SHA-256 hash was sourced from
  [rgl/windows-evaluation-isos-scraper](https://github.com/rgl/windows-evaluation-isos-scraper).
- The PCA2023 boot-manager conversion (P10 `Convert-WimBootToPca2023Signed`)
  is a PSA-clean re-implementation of Microsoft's
  [`Make2023BootableMedia.ps1`](https://github.com/microsoft/secureboot_objects)
  v1.4 `Copy-2023BootBins` (function L829-L941); the upstream-compatible
  output-verification facility (P12 `Test-OutputIsoPca2023Readiness`)
  is a quality extension not present in the Microsoft original.

This script was generated and iteratively refined with Anthropic Claude
(Opus 4.7 era). The script source file currently carries
`$Script:ScriptVersion = 'update-wsi-2026.05.27-r08.0'`; the next
revision (r09.0) will implement the §B.19 Servicing Dependency
Database specified in [SPEC.md](./SPEC.md).
