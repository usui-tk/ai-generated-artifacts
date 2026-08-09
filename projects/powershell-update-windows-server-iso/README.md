---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-08
---
# Update-WindowsServerIso.ps1

| Stage | Status |
|:---|:---|
| STAGE 1 — Linux checks (psa.py + PSScriptAnalyzer on pwsh 7) | [![STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage1__linux.yml) |
| STAGE 2 — Windows checks (PSScriptAnalyzer on Windows PS 5.1 + smoke test) | [![STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage2__windows.yml) |
| STAGE 3 — Synthetic full pipeline (Windows + ADK) | [![STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage3__synthetic.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage3__synthetic.yml) |
| STAGE 4 — Monthly baseline refresh (cron) | [![STAGE 4](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage4__monthly-refresh.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage4__monthly-refresh.yml) |

**English** | [日本語](README.ja.md)

Integrate the current month's Windows Server updates — the servicing
stack (a standalone SSU on Server 2016; embedded in the combined LCU on
the later generations), the Latest Cumulative Update, Dynamic Updates,
and .NET Framework cumulative updates — into a Windows Server
evaluation ISO, and re-emit a bootable ISO whose coupled servicing
targets are updated together: the embedded `install.wim`, `boot.wim`
and `winre.wim`, the media's Setup file tree under `sources\` (Setup
DU overlay), the Setup binaries synced from the serviced boot.wim, and
the boot files / boot manager. Targeted at Windows 11 / Windows Server
2016+ host with Windows PowerShell 5.1 (also runs on PowerShell 7+).

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
- **Secure Boot 2011-to-2023 certificate transition**. Two distinct
  clocks drive this. *Expiration*: the KEK CA 2011 and UEFI CA 2011
  expired in June 2026 (2026-06-24 / 2026-06-27), and the Microsoft
  Windows Production PCA 2011 — which signs the boot manager of
  Server 2016 / 2019 / 2022 evaluation ISOs — expires on 2026-10-19.
  Expiration by itself does not stop existing media from booting; it
  ends new boot-level protections for the old chain. *Revocation*:
  firmware where the 2011 certificate has been revoked (the BlackLotus
  CVE-2023-24932 mitigation rollout) refuses to start media whose boot
  manager is on the 2011 chain. This script's P10 phase replaces the
  media's boot manager with the **'Windows UEFI CA 2023'**-signed one
  staged by Windows servicing, producing media aimed at firmware that
  trusts the 2023 chain; the P12 report records the measured signature
  state, and whether a specific machine boots the ISO is confirmed by
  a boot test on representative hardware (`-Action BootTest`), not
  assumed from the conversion.
- **Air-gapped / offline labs**. Lab networks with no internet egress
  cannot use Windows Update. The script accepts pre-staged MSU / CAB
  files under `<WorkRoot>/patches/<OsVersion>/` -- with the LCU and any
  checkpoint MSUs under the `cu/` subfolder
  (`<WorkRoot>/patches/<OsVersion>/cu/`), everything else flat -- and
  P04 skips verified files, so the entire build can run offline.
- **Reproducible patch baselines**. Compliance and forensic-replay
  scenarios require an audited "what was inside this ISO at build time"
  record. Two layers provide it: the Config baseline
  (`data/config-Server*.json`) and the CHANGELOG record the *declared*
  baseline and its engineering provenance, while each build's own
  outputs — the build logs, the P11 inspection record, the P12
  PCA2023-readiness report, and the recorded source/output ISO and
  package hashes — carry the evidence against which a *specific* ISO is
  audited and reproduced.

### Who this is for, and who it is not for

| Suitable for | Out of scope |
|:---|:---|
| Infrastructure engineers building lab / pre-production Windows Server fleets | Production patch management (use WSUS, Microsoft Update, or Azure Update Manager) |
| Cloud consultants who need repeatable evaluation-ISO deliverables | Hotpatch in-memory patching (Azure Edition SKU only) |
| Anyone testing PCA2023 readiness against revoked-firmware hardware | Client SKUs (Windows 10 / 11) — out of scope |
| Forensic / compliance replay of past patch baselines (`-PatchMonth`) | ARM64 (x64 only at present) |
| Pre-Patch-Tuesday dry runs (`-Action Prepare`) | Driver / FOD / LXP / Appx customization |

### Reader's roadmap

- If you want to **run** the script, this README is enough.
- If you want to **extend it or build a similar script**, also read
  [`SPEC.md`](./SPEC.md) (developer / LLM specification).
- For **verification procedures and recorded results**, see
  [`TESTING.md`](./TESTING.md).
- For **per-revision change history**, see [`CHANGELOG.md`](./CHANGELOG.md).
- For the **measured research record behind the servicing design**
  (Windows servicing mechanics, evidence taxonomy, dated observations),
  see the repository-level research report
  [`windows-server-iso-update-mechanics.en.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/documents/research/windows-servicing/windows-server-iso-update-mechanics.en.md)
  ([Japanese edition](https://github.com/usui-tk/ai-generated-artifacts/blob/main/documents/research/windows-servicing/windows-server-iso-update-mechanics.ja.md)).
  It records observations; it is **not** this project's specification.
  The division of authority between the report, `SPEC.md`, the
  implementation, and `TESTING.md` is defined in SPEC
  ["Research basis and document roles"](./SPEC.md#research-basis-and-document-roles).
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
│   ├── config-template-v4.json       # Schema 4.0 template for adding an OS
│   ├── raw-release-info.md (+ .meta.json)
│   ├── raw-dotnet-cu.json
│   ├── cache-release-info.json
│   └── cache-dotnet-cu.json
├── schema/                           # Machine-readable config contracts
│   ├── config.schema.json            # Config Schema v3.0 (retained-compatibility)
│   ├── config.schema.v4.json         # Config Schema v4.0 (canonical, r12.00)
│   └── config-seed.schema.json       # SEED projection (SPEC B.14.2)
└── tests/                            # Self-verification suite (sparse T1-T57 + gates; T56 = research-reference drift guard, T57 = A00 guard pin)
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
(no manual date typing). With the patch baseline shipped in `data/`, the
script resolves the source ISO download URL from the OS profile and takes
its patch set from the distributed baseline, so **no `-IsoPath` or
patch parameter is needed**; `-UseBaselineOnly` pins the run to that
shipped baseline, so it never depends on live Catalog / release-info
publication timing:

```powershell
$OsVersion  = 'Server2019'                       # Server2016/2019/2022/2025
$OsLanguage = 'ja-jp'                             # en-us / ja-jp
$WorkRoot   = "D:\UpdateWsi-$OsVersion"           # per-OS workspace
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile    = Join-Path $WorkRoot ('logs\{0}-{1}-{2}.log' -f 'PrepareBuildVerify', $OsVersion, $stamp)

# Dry run first (Setup / Fetch / Plan only; no DISM writes)
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion $OsVersion -OsLanguage $OsLanguage `
    -WorkRoot $WorkRoot -LogFile $LogFile `
    -UseBaselineOnly

# Real build — add -Execute (the only mode that mounts and modifies WIMs)
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion $OsVersion -OsLanguage $OsLanguage `
    -WorkRoot $WorkRoot -LogFile $LogFile `
    -UseBaselineOnly `
    -Execute
```

### Worked example: Server 2016 vs Server 2025

P10 (PCA2023 boot-manager conversion) runs by default,
readiness-driven, for **every supported OS including Server 2025** —
neither example below needs a PCA2023 switch. To keep the shipped
PCA2011-signed boot manager on any OS, opt out with
`-SkipPca2023BootManager`. (`-ForcePca2023OnServer2025` survives only
as a deprecated no-op compatibility slot and emits a caution when
supplied; do not infer current policy from it.)

```powershell
# Server 2016 (no PCA2023 switches)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2016 -OsLanguage ja-jp `
    -WorkRoot 'D:\UpdateWsi-Server2016' `
    -LogFile ('D:\UpdateWsi-Server2016\logs\build-2016-{0}.log' -f $stamp) `
    -UseBaselineOnly `
    -Execute

# Server 2025 (no PCA2023 switches needed -- conversion is default-on)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2025 -OsLanguage ja-jp `
    -WorkRoot 'D:\UpdateWsi-Server2025' `
    -LogFile ('D:\UpdateWsi-Server2025\logs\build-2025-{0}.log' -f $stamp) `
    -UseBaselineOnly `
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
| `BootTest` | Hyper-V Gen2 Secure Boot smoke test against the output ISO: console screenshots for operator review (mutually exclusive with `-SyntheticTestMode`; the full revoked-firmware matrix lives in `tools/boot-verification/`) |
| `GenerateManifest` | **Placeholder**: runs the P01-P03 resolution, then emits a placeholder caution — the manifest-file emission step is not implemented in this revision (SPEC Part H.2) |
| `Cleanup` | Clean up workspace and stale DISM mounts |
| `ListPhases` | Dump phase + action registry as JSON |
| `TestHarness` | Eval-PS-function REPL mode used by `tests/powershell_harness.py` (T3); not for human invocation |

### Admin Actions (Config baseline management)

The `data/config-<OsKey>.json` files hold the baseline data the script
uses. Four Admin Actions let you refresh and inspect that data without
touching any ISO. **The refresh path is two-stage**: `RefreshSnapshots`
populates the upstream `data/raw-*` / `data/cache-*` files from
Microsoft Learn + Microsoft Update Catalog, then `RefreshAllBaselines`
regenerates each `data/config-Server*.json` `PatchBaseline.Lines[]`
from those caches. This split follows the SPEC §B.22.1 refresher architecture. `RebuildDataset` (A00) runs the whole rebuild end-to-end from the committed `data/seed/seed-Server*.json` (validate seeds -> `RefreshSnapshots` -> build each config from its seed -> `RefreshAllBaselines` Force -> verify) and is runnable from empty. **Temporary limitation**: until the v4 seed migration lands, A00 is fail-closed in Stage 0 (the committed seeds are still the legacy 3.0 shape) — do not use it for canonical dataset updates; see SPEC B.14.1.

| Action | Admin Phase | Description |
|:---|:-:|:---|
| `RebuildDataset` | A00 | Rebuild every `data/config-Server*.json` from the seeds + caches; runnable from empty |
| `RefreshSnapshots` | A03 | Fetch upstream caches (release-info, .NET CU, Dynamic Update) |
| `RefreshAllBaselines` | A01 | Regenerate `data/config-Server*.json` from the caches |
| `DumpFieldClassification` | A02 | Emit the field-cadence decision matrix as JSON |

```powershell
# ---- One-shot rebuild from the committed seeds (validate -> snapshots -> build -> fill -> verify) ----
.\Update-WindowsServerIso.ps1 -Action RebuildDataset -PatchMonth 2025-06

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
| Windows ADK | Deployment Tools feature (provides `oscdimg.exe`); auto-installed when missing (no switch) |
| Windows SDK Signing Tools | Provides `signtool.exe` for embedded PCA2023/PCA2011 boot-signature verification (P10/P12 readiness); auto-installed when missing (no switch) |
| Disk space | 100 GB minimum free on the `-WorkRoot` drive, enforced by the Workspace preflight |
| Network | Internet access for ISO / patch downloads (offline: `-IsoPath` + pre-staged patch files under `<WorkRoot>/patches/<OsVersion>/`, LCU + checkpoint MSUs in the `cu/` subfolder) |
| Static analysis | `python3` + the canonical `psa.py` for static analysis (see "Static analysis" below) |

## Supported target OS and languages

| OS | Languages | Notes |
|:---|:---|:---|
| Server 2016 | en-us, ja-jp | LCU 2024-4B or later required for PCA2023 conversion |
| Server 2019 | en-us, ja-jp | LCU 2024-4B or later required for PCA2023 conversion |
| Server 2022 | en-us, ja-jp | LCU 2025-2B (build 20348.2227) or later required for PCA2023 conversion |
| Server 2025 | en-us, ja-jp | PCA2023 conversion default-on (current policy); firmware also provides the 2023 certificates on certified platforms |

Adding a new language is a single-node addition under
`LanguageSpecific` in the relevant `data/config-Server<N>.json`. See
SPEC.md §B.4.5.

## Phase reference

Pipeline (canonical phase model P01-P14, incl. the inserted P08S build phase):

| ID | Name | Group | What it does |
|:---|:---|:---|:---|
| P01 | Initialize | Setup | PowerShell environment, admin, ADK, disk, Hyper-V |
| P02 | ResolveInputs | Setup | ISO / patch source resolution, Config JSON load |
| P03 | RefreshPatchBaseline | Setup | Microsoft Update Catalogue scrape; the refreshed baseline updates the in-memory profile, persisted to `data/config-<OsKey>.json` only when `AutoRefreshPolicy.WritebackToConfig` allows |
| P04 | FetchAssets | Fetch | ISO + patch downloads with hash verification |
| P05 | ExpandIso | Plan | Mount source ISO; copy to workspace; enumerate WIM indexes |
| P06 | ValidatePatchServicing | Plan | PatchModel consistency + pre-servicing inspection of every WIM index (`logs/inspection_pre.json`; on-mount readiness still via P07/P08) |
| P07 | PatchInstallWim | Build | For each install.wim index: SSU → LCU → .NET → DISM cleanup |
| P08 | PatchBootWim | Build | boot.wim (PE + Setup) and winre.wim |
| P08S | SyncSetupBinaries | Build | Explicit sync of setup.exe / setuphost.exe from the serviced boot.wim idx2 to media `sources\` (size/timestamp/SHA-256 recorded before and after; MS media-dynamic-update mandate) |
| P09 | AssembleIso | Build | Dynamic Update Setup overlay; Export-WindowsImage; oscdimg ISO build |
| P10 | ConvertPca2023BootManager | Build | **Default-on**, readiness-driven PCA2023 Secure Boot conversion for every supported OS (opt-out: `-SkipPca2023BootManager`) |
| P11 | StaticVerify | Verify | Mount output ISO; SHA-256 content identity vs the extracted tree; full post-servicing inspection (`logs/inspection_post.json`); per-Kind measured verification (target build, .NET rollup census; KB-name rows on Server 2016 only) |
| P12 | VerifyPca2023Readiness | Verify | **Always runs** — emits `pca2023_readiness.json` + `.md` |
| P13 | FinalReport | Report | End-of-run summary; ISO hash; log paths; pre/post inspection diff + observe-first declared-vs-measured cross-checks |
| P14 | HyperVValidation | Verify | Hyper-V Gen2 Secure Boot validation of the output ISO with identity-bound boot evidence and a separate operator-approval step; runs via `-Action BootTest`, `-Action All`, or `-RunHyperVValidation` (inserted before P13); see SPEC §B.5 |

See [SPEC.md](./SPEC.md) Part B for the full per-phase contracts.

### Secure Boot / PCA2023 boot manager (r05.0+)

The Microsoft "Windows Production PCA 2011" Secure Boot signing
certificate expires in **2026-06**. Firmware that has been updated to
revoke the 2011 cert refuses to boot ISOs whose boot manager is still
signed via the 2011 chain. P10 / P12 address this; the full operational
model (per-OS defaults, standalone `-Pca2023OnlyMode` forensic
inspection) is documented in SPEC.md §B.17 and §B.18.

Common operator decisions:

- **Server 2016 / 2019 / 2022**: P10 runs automatically (the PCA2011
  signing CA expired 2026-06, so conversion is the norm). The
  pre-flight readiness snapshot still gates it: Critical (LCU prereq
  not met) skips with a warning, Healthy (already signed) is a no-op.
  The source ISO's `install.wim` LCU month must be 2024-4B (April
  2024) or later (Server 2022 specifically needs 2025-2B per Lenovo
  lp2353.pdf). Pass `-SkipPca2023BootManager` to keep the shipped
  PCA2011-signed boot manager for older-firmware targets.
- **Server 2025**: P10 also runs by default (`RequiredByDefault=true`
  under the current policy) — media must boot on PCA2023-only
  firmware regardless of what certified platforms carry. The
  conversion mechanism was validated end-to-end on the r12.75
  terminal implementation (historical evidence preserved as
  provenance); the current branch's own outstanding verification
  gates are listed in TESTING.md and are not inferred closed from
  that historical evidence. The retained
  `-ForcePca2023OnServer2025` switch is a deprecated no-op
  compatibility slot (a caution is emitted when it is supplied).
- **Forensic inspection** of an existing ISO: pass `-Pca2023OnlyMode
  -IsoPath <existing.iso>` to skip the entire build pipeline and run
  ONLY P12 against the ISO.

Full design and verification details: SPEC.md §B.17 (PCA2023 boot
manager support) and §B.18 (Output ISO verification).

## Parameters (complete)

Every public parameter is listed below, grouped by typical use (the
authoritative surface is the script's `param()` block). The table is
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
| `-OnlyPhases` | advanced | (none) | Phase-ID array (e.g. `'P04','P07'`) overriding the Action's phase set |
| `-OnlyInstallWimIndexes` | advanced | (none) | Comma-separated index list (e.g. `'2,4'`) limiting install.wim updates |
| `-UseDefenderExclusions` | advanced | switch (OFF) | Opt-in: temporarily exclude the WorkRoot tree + dism/DismHost/TiWorker/TrustedInstaller from Defender for the run (fail-closed; ~35% faster LCU apply) |
| `-SkipResetBaseOnCleanup` | advanced | switch (OFF) | Omit DISM `/ResetBase` on cleanup; do `/StartComponentCleanup`-only scavenging (keeps the superseded component store resettable) |
| `-SkipExportCompress` | advanced | switch (OFF) | Skip `Export-Image /Compress:max`; faster build, larger `install.wim` |
| `-AutoDetectLatestPatches` | patch | switch (OFF) | Force a P03 PatchBaseline refresh from the Catalog |
| `-PatchMonth` | patch | current month | Target patch month for refresh, e.g. `2026-06` |
| `-SkipDynamicPatchRefresh` | patch | switch (OFF) | Skip P03 even if baseline is stale (offline runs) |
| `-UseBaselineOnly` | patch | switch (OFF) | Use PatchBaseline strictly as-is; no Catalog access |
| `-SkipPca2023BootManager` | secure-boot | switch (OFF) | Opt OUT of the default-on P10 PCA2023 boot-manager conversion (keep the shipped PCA2011-signed boot manager) |
| `-ForcePca2023OnServer2025` | secure-boot | switch (OFF) | **Deprecated no-op** compatibility slot (P10 is default-on for Server 2025; a caution is emitted when supplied) |
| `-ResumeFromPhase` | resume | string | Resume an interrupted build from `P08` or `P09`: P01/P02 reconstruct runtime state, the existing WorkRoot is validated, measured patch assets are restored |
| `-ResumePreflightOnly` | resume | switch (OFF) | Validate a P08/P09 resume workspace and rehydrate assets, stopping before any build phase (requires `-ResumeFromPhase`) |
| `-PatchRefreshMode` | patch-selection | string | Explicit patch-selection mode: `PinAll` pins OS and auxiliary KB identities; `PinOs` pins the reviewed OS LCU/SSU/checkpoint while resolving monthly auxiliaries |
| `-ImageDisplayDate` | media | string (yyyy-MM-dd) | Display date rewritten into the serviced install.wim indexes (Windows Setup surfaces the WIM IMAGE CREATIONTIME field) |
| `-RunHyperVValidation` | boot-test | switch (OFF) | Insert P14 before P13 in the standard pipeline (`BootTest`/`All` run P14 regardless) |
| `-HyperVValidationMode` | boot-test | string (BootOnly) | `BootOnly` captures console thumbnails for operator adjudication; `Install` performs an unattended evaluation install and collects evidence via PowerShell Direct |
| `-BootTestIsoPath` | boot-test | string | Validate an ISO moved from its output directory with standalone `-Action BootTest` (SHA-256 must match the P11/P12 evidence index) |
| `-BootEvidenceApprovalPath` | boot-test | string | Operator-controlled JSON approval file promoting existing identity-bound BootOnly evidence to ReleaseReady on a subsequent BootTest invocation |
| `-Pca2023OnlyMode` | secure-boot | switch (OFF) | Standalone P12 inspection of an existing ISO (`-IsoPath` required) |
| `-Pca2023ScriptPath` | secure-boot | (none) | External `Make2023BootableMedia.ps1` instead of the internal helper |
| `-Mode` | admin | `Monthly` (or `Initial`/`Force`) | `RefreshAllBaselines` refresh mode |
| `-OnlyOs` | admin | `Server2016`/`2019`/`2022`/`2025` | Limit `RefreshAllBaselines` to one OS |
| `-OnlyLanguage` | admin | `en-us`/`ja-jp` | Limit `RefreshAllBaselines` to one language |
| `-DryRun` | test | switch (OFF) | Setup/Fetch/Plan only; skip Build/Verify |
| `-SyntheticTestMode` | test | switch (OFF) | CI mode: synthetic ISO, no Microsoft assets |
| `-SkipEnvCheck` | test | switch (OFF) | Skip the environment preflight (mutually exclusive with `-EnvironmentInfoOnly`) |
| `-EnvironmentInfoOnly` | test | switch (OFF) | Print environment info and exit (mutually exclusive with `-SkipEnvCheck`) |

### Mutual exclusivity rules

The script enforces several mutual-exclusion constraints:

- `-IsoUrl` / `-IsoPath`
- `-EnvironmentInfoOnly` / `-SkipEnvCheck`
- `-Action BootTest` / `-SyntheticTestMode`
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
        - Scrape Microsoft Update Catalogue, bounded by the baseline
          month (Dynamic Update / .NET: same month if published,
          otherwise latest prior; never newer than the baseline;
          Preview excluded)
        - Identify SSU + LCU + DynamicUpdate(.Setup/.Component/.SafeOs)
          + .NET CU using config-driven title-token narrowing
        - Fetch ScopedViewInline.aspx for Supersedes / SupersededBy lists
        - Always refresh the effective in-memory PatchBaseline; persist to Config JSON (atomically) only when AutoRefreshPolicy.WritebackToConfig allows
P04   FetchAssets (uses the freshly resolved patch URLs and SHA-256s)
P05   ExpandIso
P06 ValidatePatchServicing
        - Runs the per-PatchModel consistency check (Test-PatchModelConsistency);
          the wsusscn2 Layer 2 graph gate it replaced was removed in the
          data-source migration (SPEC.md §B.19).
        - Real servicing readiness is validated on-mount during the build
          by Test-PatchServicingReadinessOnMount (SPEC.md §B.13, P07/P08).
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
| Baseline stale, scrape succeeds | The effective in-memory baseline is updated and the new patches are used; Config JSON is persisted only when `AutoRefreshPolicy.WritebackToConfig` allows |
| Baseline stale, scrape fails, existing baseline usable | Warning + continue with existing baseline |
| Baseline stale, scrape fails, baseline empty/unusable | ABORT |
| `-UseBaselineOnly` set | P03 skipped unconditionally (offline mode) |
| `-SyntheticTestMode` set | P03 and P06 both skipped (CI mode) |

Full decision matrix: SPEC.md §B.14.

## Static analysis

Run from the project directory:

```bash
python3 ../../quality-tools/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
```

The static-analysis governance is the **adjudicated-debt model**: no
UNADJUDICATED finding is permitted at any severity, while findings
that have been measured, adjudicated and documented (with rationale
and a non-regression baseline) may remain as declared debt; any new
or increased unexplained finding blocks integration. The current
declared baseline and each debt class's rationale live in
TESTING.md §0.

## Self-verification tools

The `tests/` subdirectory ships the Python-based self-verification
suite (sparse T-numbering, T1 – T55; numbers of retired tools are never
reused) plus three format / schema / seed gates. The set includes six
declaration-derived contracts (T41 – T46) that read their expected
values from the config under test rather than hardcoding them, and the
six series-end contracts (T47 – T52) covering the evidence Collector,
the declared oscdimg reference, the Catalog boundary and collection
shapes, the Generic.List binder guard, and the final-writer authority
model. T54 and T55 hold the source-file format contract and the
analyzer debt-baseline gate; the whole offline tier now runs in CI
Stage 1, not only in the local gate battery. The suite is declared in three execution tiers in TESTING.md §5
(offline-deterministic / live-network / user-side evidence); the
offline tier is **all green — no declared red**. Offline tools use the
Python standard library, and most contracts additionally drive the
pinned PowerShell (pwsh) on PATH through a REPL or AST-extraction
harness.

```bash
# Offline tests — safe to run anywhere
python3 tests/catalog_fixture_test.py        # T2: 13 fixture assertions
python3 tests/powershell_harness.py          # T3: 7 PS function assertions
python3 tests/release_info_parser_test.py    # T6: 13 release-info parser assertions
python3 tests/dotnet_cu_parser_test.py       # T7: 16 .NET CU parser assertions
python3 tests/canonical_json_test.py         # T11: 26 PS/Python byte-level parity assertions

# Schema / format gates (run on every commit that touches data)
python3 tests/config_schema_test.py                       # config schema gate
python3 tests/canonical_json_format_check.py              # JSON canonical-format gate; SPEC §C.3.4

# Live tests — require unrestricted network egress
python3 tests/catalog_probe.py --check all   # T1: Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4: Server<N> ISO CDN
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
opened PR is restricted via `add-paths` to `data/config-*.json`.

CRITICAL: Stage 3 NEVER uploads an ISO artifact. The evaluation
licence forbids public distribution of Microsoft binaries; the
workflow's explicit `actions/upload-artifact` `path:` enumeration
enforces this per repository SPEC.md §12 (SPEC-CI-081).

## Troubleshooting

| Symptom | Cause | Action |
|:---|:---|:---|
| `Administrator privilege required` | Running as a non-elevated user | Re-launch PowerShell as Administrator |
| `oscdimg.exe not found` | Windows ADK Deployment Tools not installed | P01 auto-installs the ~50-80 MB Deployment Tools feature when `oscdimg.exe` is missing (no switch); if that fails, install manually from the [Windows ADK installer](https://go.microsoft.com/fwlink/?linkid=2289980). See SPEC.md §B.22.13 |
| `Workspace preflight failed: drive ... has only NN GB free` | `-WorkRoot` drive has less than 100 GB free | Move `-WorkRoot` to a larger volume, or free up space (the 100 GB minimum covers an end-to-end PrepareBuildVerify run for one OS) |
| `Workspace preflight failed: ... required Config file(s) missing` | The `data/config-Server<N>.json` files were deleted or not copied | Restore the `data/` directory alongside `Update-WindowsServerIso.ps1` (all four `Server2016/2019/2022/2025.json` must be present) |
| `Catalogue: no narrowed result for ... / Server2022`; `Resolved 0 patch entries` | The OS Products token in `$script:CatOsDef` no longer matches the Catalogue Products column (e.g. Microsoft renamed the product), or the patch is not yet published | Verify the per-OS Products token against a live Catalogue search. OS-scoping is by the Products column, not the Title (SPEC.md §B.22.2). |
| A resolved set violates the OS servicing model after RefreshAllBaselines | the `Lines[]` misses a Required Kind for the declared `PatchModel`, or a line fails the state-driven integrity rule | P06 `Test-PatchModelConsistency` throws naming the missing Required Kinds (the check enforces Required Kinds and state-driven integrity only; extra Kinds are accepted); confirm `PatchModel` matches the OS. See SPEC.md §B.19 |
| .NET CU baseline entry seems to be missing a sub-file | Umbrella KB with multiple `.msu` files; only one was kept | Confirm the b3 `Resolve-Net` resolver retains every `.msu` sub-file of the umbrella KB. See SPEC.md §D.21 |
| `0x800f081e` in Warning lines | Patch not applicable to this SKU | Expected for cross-SKU patch sets; safe to ignore (see SPEC.md §D.8) |
| `0x800f0823 — CBS_E_NEW_SERVICING_STACK_REQUIRED` mid-P07 | the LCU's prerequisite SSU is missing from the baseline | for `separate-ssu` the P06 `PatchModel` check (SPEC.md §B.19) requires the standalone `SSU` line, so a missing SSU is caught statically; if it still occurs, add the SSU line to `PatchBaseline.Lines[]`. See SPEC.md §D.2 |
| Mojibake (doubled Japanese characters) in P05 WIM-index banner | DISM mount-cache poisoning from prior aborted runs | Use **one fresh `-WorkRoot` per OS family** (`D:\UpdateWsi_2016`, `D:\UpdateWsi_2019`, …). See SPEC.md §D.25 |
| Stale WIM mount blocks new run | Previous run crashed mid-mount | Run `dism /Get-MountedImageInfo` then `dism /Cleanup-Mountpoints`. See SPEC.md §D.1 |
| ISO SHA-256 mismatch on download | Microsoft rotated the Evaluation Center snapshot URL | Update `data/config-<OsKey>.json` `LanguageSpecific.<lang>.Iso.Sha256` to the new value. See SPEC.md §D.11 |

For broader investigation context, the historical rationale behind
each Pitfall entry in SPEC.md Part D is preserved in CHANGELOG.md
(the strongest provenance source in this project) and in the
development archive kept outside the repository tree.

## Acknowledgements

- The DISM mount + dismount retry pattern (10 s + 30 s) is borrowed
  from [OSDBuilder](https://github.com/OSDeploy/OSDBuilder) (David
  Segura), specifically the `Dismount-InstallwimOS` helper.
- The 0x800f081e suppression heuristic is also from OSDBuilder.
- The three-tier `etfsboot.com` / `efisys.bin` fallback chain comes
  from [Win_ISO_Patching_Scripts_zhCN](https://github.com/adavak/Win_ISO_Patching_Scripts_zhCN).
- The canonical Server 2022 SHA-256 hash was sourced from
  [rgl/windows-evaluation-isos-scraper](https://github.com/rgl/windows-evaluation-isos-scraper).
- The PCA2023 boot-manager conversion (P10 `Convert-WimBootToPca2023Signed`)
  is a PSA-clean re-implementation of the `Copy-2023BootBins` function
  from Microsoft's
  [`Make2023BootableMedia.ps1`](https://github.com/microsoft/secureboot_objects);
  the pinned upstream file identity this project tracks is recorded in
  SPEC.md §B.17.4 (tracking is by file identity, not release tag). The
  upstream-compatible output verification (P12
  `Test-OutputIsoPca2023Readiness`) is a quality extension absent from
  the Microsoft original.

This script was generated and iteratively refined with Anthropic Claude.
