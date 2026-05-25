# Update-WindowsServerIso.ps1 — Developer Specification (SPEC)

> **Purpose of this document**
>
> Authoritative developer / LLM specification for
> `Update-WindowsServerIso.ps1`. Written so that an LLM (Claude) can be
> dropped into the project mid-stream without having to re-derive the
> design from the source code.
>
> **Important**: this SPEC inherits the **Part A common specification**
> from the repository-wide canonical reference at
> [`scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`](../download-speakerdeck-oracle4engineer/SPEC.md)
> (sections A.1 through A.14). Only the **Part B** (script-specific)
> contract is fully restated here. Parts C and D are this project's
> own quality gates and lessons learned.

---

## Table of Contents

- [Part A — Inherited Common Specification](#part-a--inherited-common-specification)
- [Part B — Script-Specific Specification](#part-b--script-specific-specification)
  - [B.0 Script Identity](#b0-script-identity)
  - [B.1 Inputs and Outputs](#b1-inputs-and-outputs)
  - [B.2 Workspace Layout](#b2-workspace-layout)
  - [B.3 Output ISO Naming](#b3-output-iso-naming)
  - [B.4 OS Profile Schema](#b4-os-profile-schema)
  - [B.5 Phase Contracts (P01–P13)](#b5-phase-contracts-p01p09)
  - [B.6 Action → Phase Mapping](#b6-action--phase-mapping)
  - [B.7 ISO Filename Detection Patterns](#b7-iso-filename-detection-patterns)
  - [B.8 Patch Integrity Check (Three-Layer)](#b8-patch-integrity-check-three-layer)
  - [B.9 Synthetic Test Mode](#b9-synthetic-test-mode)
- [Part C — Quality Gates & Validation Checklist](#part-c--quality-gates--validation-checklist)
- [Part D — Known Pitfalls & Lessons Learned](#part-d--known-pitfalls--lessons-learned)
- [Part E — Roadmap](#part-e--roadmap)
- [Part F — Function Reuse Map](#part-f--function-reuse-map)
- [Part H — Reference Projects](#part-h--reference-projects)

---

# Part A — Inherited Common Specification

This script inherits in full from the repository-wide Part A defined
in
[`scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`](../download-speakerdeck-oracle4engineer/SPEC.md).
Specifically:

| Section | Topic | Status here |
|---|---|---|
| A.1 | Reference Assets (`psa.py` canonical path; companion specs) | Inherited verbatim |
| A.2 | Source File Format (UTF-8 BOM, CRLF, ASCII only) | Inherited verbatim |
| A.3 | Banner & Version Identification | Inherited; this project's `$Script:ScriptVersion = 'update-wsi-2026.05.24-r01'` |
| A.4 | Phase Architecture (registry-driven dispatcher) | Inherited; phases listed in §B.5 |
| A.5 | Logging Conventions (`_LogLine`, `Write-Step/Ok/Warn/Fail/Skip`, phase headers) | Inherited verbatim |
| A.6 | Path Handling (`-LiteralPath` everywhere, no `Split-Path -LiteralPath ... -Parent`) | Inherited verbatim |
| A.7 | Parameter Conventions (PascalCase, `[switch]` for flags, GUID-temp downloads) | Inherited verbatim |
| A.8 | Error & Diagnostic Conventions (`Add-ErrorJsonlEntry`, debug trace auto-export) | Inherited verbatim |
| A.9 | CSV / JSONL Column Conventions | Inherited verbatim |
| A.10 | Environment Evaluation (Phase 1) | Inherited; specialised in §B.5 P01 |
| A.11 | Static Analysis with psa.py | Inherited; project config in `.psa.config.json` |
| A.12 | Documentation Language Policy | Inherited; README.md (en) primary, README.ja.md mirror, SPEC English only |
| A.13 | Development Workflow | Inherited verbatim |
| A.14 | Debug Trace Facility | Inherited verbatim (uses the canonical implementation) |

The reused helper inventory is in [Part F](#part-f--function-reuse-map)
below.

---

# Part B — Script-Specific Specification

## B.0 Script Identity

| Field | Value |
|---|---|
| Filename | `Update-WindowsServerIso.ps1` |
| Project folder | `scripts/powershell/update-windows-server-iso/` |
| Version | `update-wsi-2026.05.24-r02.5` |
| Tag | `dynamic-baseline-and-wsusscn2-validation-fixup` |
| Target OS | Server 2016 / 2019 / 2022 / 2025 |
| Languages | en-us, ja-jp |
| Architecture | x64 only |

## B.1 Inputs and Outputs

### B.1.1 Inputs

| Kind | Source | Notes |
|---|---|---|
| Source ISO | Microsoft Evaluation Center, VLSC, or local file | `-IsoPath` or `-IsoUrl` |
| Patches | Microsoft Update Catalogue (MSU/CAB) | `-PatchUrls`, `-PatchDirectory`, or `-ManifestPath` |
| Per-OS profile | `Config/<OsKey>.json` | Auto-selected by `-OsVersion` |
| Language profile | `Config/<OsKey>.json/Languages/<lang>` | Auto-selected by `-OsLanguage` |
| Optional manifest | Metalink 4 (`.meta4`) | Carries SHA-1 and SHA-256 expected hashes |

### B.1.2 Outputs

| Output | Path |
|---|---|
| Final ISO | `<WorkRoot>/output/<OsShortName>_<lang>_Updated_<yyyy-MM>.iso` |
| Phase CSVs | `<WorkRoot>/logs/P0<N>_<name>.csv` |
| Debug trace JSONL | `<WorkRoot>/logs/debug_<phase>_<timestamp>.jsonl` (file output) |
| Failure diag JSON | `<WorkRoot>/diag/<phase>_failure_<timestamp>.json` (on phase failure) |
| Phase completion markers | `<WorkRoot>/.markers/P0<N>.ok` |
| Transcript (optional) | `-LogFile <path>` |

## B.2 Workspace Layout

```
$WorkRoot/                       (default: C:\Temp\Workspace_UpdateWsi)
  source/
    iso/                         downloaded ISO files
    extracted/                   extracted ISO tree (read/write while editing)
  patches/
    <OsVersion>/                 downloaded patch files
    manifests/                   Metalink .meta4 files
  work/
    mount_install/               install.wim mount target
    mount_boot_idx1/             boot.wim idx 1 mount target
    mount_boot_idx2/             boot.wim idx 2 mount target
    mount_winre/                 winre.wim mount target
    temp/                        scratch for Dynamic Update CAB expansion
  output/                        final ISO output
  logs/                          per-phase CSV + JSONL
  diag/                          debug-trace JSON exports on failure
  pca2023/                       P12 PCA2023 readiness JSON + Markdown (r05.0+)
  .markers/                      P0<N>.ok marker files
```

All paths derive from `$Script:WorkRoot`; overriding `-WorkRoot` re-bases
the whole tree atomically.

## B.3 Output ISO Naming

| Element | Format |
|---|---|
| Filename | `<OsShortName>_<lang>_Updated_<yyyy-MM>.iso` |
| Volume label | `<VolumeLabelPrefix>_UP_<yyyyMM>` (max 32 ASCII chars) |
| Bootdata | `2#p0,e,b<etfsboot.com>#pEF,e,b<efisys.bin>` (UEFI + BIOS) |
| UDF version | 1.02 (`-udfver102`) |
| Optimisation | `-m -o` (no media verify, optimise duplicates) |

Examples:

| OS, lang | Filename | Volume label |
|---|---|---|
| Server 2022 en-us, May 2026 | `WS2022_en-us_Updated_2026-05.iso` | `WS2022EN_UP_202605` |
| Server 2025 ja-jp, May 2026 | `WS2025_ja-jp_Updated_2026-05.iso` | `WS2025JA_UP_202605` |

## B.4 OS Profile Schema

See `Config/Server2025.json` for the most complete example. Fields:

| Field | Type | Notes |
|---|---|---|
| `OsKey` | string | `Server2016`, `Server2019`, `Server2022`, `Server2025` |
| `OsName` | string | "Windows Server <year> Datacenter" |
| `OsShortName` | string | `WS2016`, `WS2019`, `WS2022`, `WS2025` |
| `Build` | int | OS build number (e.g. 26100 for 2025) |
| `Architecture` | string | `x64` |
| `RequireSSUFirst` | bool | Always `true` for current targets |
| `EnableInstallWimUpdate` | bool | Run P07 against install.wim |
| `EnableBootWimUpdate` | bool | Run P08 against boot.wim |
| `EnableWinREUpdate` | bool | Run P08 against winre.wim too |
| `DotNetRequired` | bool | Apply .NET cumulative if present |
| `LCUExpandViaMum` | bool | `true` only for Server 2025; LCU ships as MUM/CAB bundle |
| `RequireUefiCa2023Boot` | bool | `true` only for Server 2025 (Secure Boot CA rotation) |
| `BootWimIndexes` | int[] | Typically `[1, 2]` |
| `InstallWimIndexes` | `"all"` or int[] | Filter for which install.wim indexes to patch |
| `ExpectedEditions` | string[] | For the P11 verification banner |
| `AutoDetectKnownGood` | object | KB IDs frozen as the latest known-good set (M2) |
| `Languages.<lang>.IsoFwLink` | string | Eval Center FwLink URL |
| `Languages.<lang>.IsoSnapshotUrl` | string | Direct snapshot URL (fallback) |
| `Languages.<lang>.IsoSha256` | string | Known-good ISO hash, populated on first run |
| `Languages.<lang>.IsoExpectedSize` | int | Approximate size in bytes |
| `Languages.<lang>.VolumeLabelPrefix` | string | Used in output volume label |

## B.5 Phase Contracts (P01–P13)

Each phase function is `Invoke-<Group>Phase<NN>_<Name>` and is wrapped
in `Start-DebugTrace` / `Stop-DebugTrace`. Phases write a `P0<N>.ok`
marker on success.

### P01 Initialize (Setup)

| Step | What |
|---|---|
| 0 | `Show-PowerShellEnvironment` (no abort, always runs) |
| 1 | `Assert-PowerShellCompatibility` (64-bit, 5.1+) |
| 2 | Administrator check (relaxed for read-only actions) |
| 3 | Tool detection: `dism.exe`, `oscdimg.exe`, `Get-WindowsImage` |
| 4 | Disk-space check: 30 GB hard floor, 60 GB recommended |
| 5 | Hyper-V check (only when `-Action BootTest` or `All`) |

### P02 ResolveInputs (Setup)

| Step | What |
|---|---|
| 1 | Load `Config/<OsVersion>.json`, attach language node |
| 2 | Resolve ISO source: `-SyntheticTestMode` < `-IsoPath` < `-IsoUrl` < FwLink < snapshot |
| 3 | Build patch list from `-PatchUrls` / `-ManifestPath` / `-PatchDirectory` / `-AutoDetectLatestPatches` / PatchBaseline.Patches |
| Output | `logs/P02_inputs_resolved.csv` |

### P03 RefreshPatchBaseline (Setup)

| Step | What |
|---|---|
| 0 | Skip if `-SyntheticTestMode`, `-SkipDynamicPatchRefresh`, or `-UseBaselineOnly` |
| 1 | `Get-LatestPatchTuesday`; compare with `PatchBaseline.PatchTuesdayOfBaseline` |
| 2 | If `Test-PatchBaselineFresh = $true` AND `-AutoDetectLatestPatches` not set: skip |
| 3 | Resolve target patch month (`-PatchMonth` or current Patch Tuesday) |
| 4 | `Resolve-PatchSetFromCatalog`: scrape Microsoft Update Catalogue for SSU + LCU + DynUp Setup + DynUp Component + DynUp SafeOs + .NET CU |
| 5 | For each candidate, run `Get-DownloadLinkFromCatalog` and `Get-SupersedenceFromCatalog` |
| 6 | Auto-link LCU.RequiresKbIds to SSU(s) found in the same pass |
| 7 | Update in-memory `$Script:OsProfile.PatchBaseline`; record `PatchTuesdayOfBaseline`, `LastVerifiedDate`, `LastVerifiedBy = 'auto-scrape'` |
| 8 | If `AutoRefreshPolicy.WritebackToConfig`: `Save-ConfigWithBaseline` (atomic write to Config JSON) |
| 9 | Re-derive `$Script:ResolvedPatches` from the refreshed baseline (when user did not provide an explicit source) |
| Failure | If scrape fails AND `FallbackOnScrapeFailure = 'UseBaseline'` AND baseline usable: warn + continue. Otherwise: throw |

### P04 FetchAssets (Fetch)

| Step | What |
|---|---|
| 1 | Download / use existing ISO; SHA-256 verify if config has one |
| 2 | Download / use existing patches; `Test-PatchIntegrity` per patch |
| Tactics | GUID-suffixed temp paths, atomic move on success, retry via `Invoke-WebRequestWithRetry` |

### P05 ExpandIso (Plan)

| Step | What |
|---|---|
| 1 | `Mount-DiskImage` the source ISO, copy contents to `extracted/`, `Dismount-DiskImage` |
| 2 | Enumerate `install.wim` and `boot.wim` indexes via `Get-WindowsImage` |
| Output | `logs/P04_wim_inventory.csv` |

### P06 ValidatePatchSet (Plan)

| Step | What |
|---|---|
| 0 | Skip if `-SyntheticTestMode`, `-UseBaselineOnly`, or non-Windows host |
| 1 | Resolve `wsusscn2.cab`: `-WsusScnCabPath` < `<WorkRoot>/cache/wsusscn2.cab` cache |
| 2 | Determine download necessity: cache absent, OR cache older than latest Patch Tuesday |
| 3 | If download needed: `Invoke-WebRequestWithRetry` to `<WorkRoot>/cache/wsusscn2.cab.<guid>.part`, atomic move, record SHA-256 |
| 4 | If newly downloaded: persist metadata to Config (`PatchBaseline.WsusScnCab.LastDownloadedDate` etc.) |
| 5 | `Invoke-WuaOfflineScan`: create `Microsoft.Update.Session`, register cab via `AddScanPackageService`, run `IsInstalled=0 and Type='Software' and IsHidden=0` |
| 6 | `Compare-PatchSetVsWuaScan`: classify WUA-required updates as Provided or Missing (excluding `PatchBaseline.ExcludeKbList`) |
| 7 | If any Missing: `Export-PatchValidationReport` emits 4 files; throw unless `-IgnorePatchValidation` |
| Output | `<WorkRoot>/diag/<timestamp>/validation_summary.json`, `validation_detail.csv`, `wsusscn2_scan_raw.json`, `dependency_graph.json` |

### P07 PatchInstallWim (Build)

For each install.wim index filtered by `-OnlyInstallWimIndexes` AND
Config `InstallWimIndexes`:

| Step | What |
|---|---|
| Mount | `Invoke-WimMountSafe` (cleans up stale mount first) |
| Apply | Patches in `Get-PatchApplyOrder` order: SSU → DynUp Setup → LCU → DynUp Component → DynUp SafeOs → .NET → Defender → Edge → Other |
| Cleanup | `Invoke-DismCleanup` (`/StartComponentCleanup /ResetBase`) |
| Dismount | `Invoke-WimDismountSafe` (10 s pre-sleep, 30 s retry on failure) |
| Sandbox | Without `-Execute`, the loop emits a `[PLAN]` row per (index, patch) pair and does NOT mount |
| Output | `logs/P05_patch_inventory.csv` |

### P08 PatchBootWim (Build)

For each boot.wim index in Config `BootWimIndexes` (typically `[1, 2]`):

| Step | What |
|---|---|
| Mount, apply, cleanup, dismount | Same lifecycle as P07, but with the boot-wim patch subset (SSU, LCU, SafeOs DU only) |

Then, if `EnableWinREUpdate`:

| Step | What |
|---|---|
| Extract | Mount install.wim primary index, copy embedded `Windows\System32\Recovery\Winre.wim` to `work/temp/` |
| Patch winre | Mount the copy, apply patches, cleanup, dismount |
| Re-embed | Copy the updated winre.wim back into the mounted install.wim |
| Dismount install.wim | Save + integrity-check |

### P09 AssembleIso (Build)

| Step | What |
|---|---|
| 1 | For each Dynamic Update Setup CAB: `expand.exe -F:*` into temp, overlay onto `extracted/sources/` |
| 2 | `New-BootableIso` invokes oscdimg with the 3-tier `etfsboot.com` / `efisys.bin` fallback chain |
| 3 | Verify the output ISO file exists and is non-empty |

### P10 ConvertPca2023BootManager (Build, OPTIONAL)

This phase is the **only** Build-group phase that is conditional
on operator opt-in (see B.20 for the rationale). It rewrites the
output ISO's boot manager to be signed via the 'Windows UEFI CA
2023' chain instead of the legacy 'Windows Production PCA 2011'.

| Step | What |
|---|---|
| 0a | If `-EnablePca2023BootManager` is NOT set: silent skip, write `P10.skipped` marker |
| 0b | If `OsKey = Server2025` AND `-ForcePca2023OnServer2025` is NOT set: silent skip |
| 0c | Pre-flight `Get-OrEnsurePca2023Snapshot`; if Health = 'Critical' (LCU < 2024-4B): throw |
| 0d | If Health = 'Healthy' (already PCA2023): silent skip |
| 1 | Call `Convert-WimBootToPca2023Signed` (internal, default) OR invoke external `-Pca2023ScriptPath` |
| 2 | Re-assemble output ISO via `New-BootableIso` to embed the updated boot manager |
| 3 | Force-refresh `$Script:Pca2023Snapshot` so downstream phases see new state |
| Output | Updated `extracted/efi/boot/bootx64.efi` + `extracted/bootmgr.efi` + `extracted/efi/microsoft/boot/efisys_ex.bin` + fonts; updated output ISO |

### P11 StaticVerify (Verify)

| Step | What |
|---|---|
| 1 | Output ISO existence + minimum size check |
| 2 | `Mount-DiskImage` the output ISO; confirm `install.wim`, `boot.wim`, `setup.exe` exist |
| 3 | Enumerate WIM indexes; for the primary install.wim index, run `Get-WindowsPackage` and check each expected KB |
| 4 | `Dismount-DiskImage` |
| Output | `logs/P11_verification.csv` |

### P12 VerifyPca2023Readiness (Verify, ALWAYS-RUNS)

Strictly read-only inspection of the produced ISO's PCA2023
readiness state. Always runs as part of the Verify group,
regardless of whether `-EnablePca2023BootManager` was set for P10.

| Step | What |
|---|---|
| 0 | Skip ONLY if no extracted media is available (P05 did not run, or workspace was cleaned) |
| 1 | `Get-OrEnsurePca2023Snapshot -Force` against `<WorkRoot>/extracted/` |
| 2 | Render snapshot to console via `Show-Pca2023ReadinessSnapshot` |
| 3 | Emit `<WorkRoot>/pca2023/pca2023_readiness.json` (machine-readable) |
| 4 | Emit `<WorkRoot>/pca2023/pca2023_readiness.md` (human-readable detail) |
| Output | JSON + Markdown under `<WorkRoot>/pca2023/`. Snapshot is also cached in `$Script:Pca2023Snapshot` for P13 |

### P13 FinalReport (Report)

| Step | What |
|---|---|
| 1 | `Show-PhaseSummary` (timing + status per phase) |
| 2 | Output ISO SHA-256 + size + path |
| 3 | Log / diag directory hints |
| 4 | Inline PCA2023 readiness summary (Compact form) + cross-link to P12's JSON/MD detail files |

## B.6 Action → Phase Mapping

| `-Action`            | Phases run                                                              |
|----------------------|-------------------------------------------------------------------------|
| `Prepare`            | P01, P02, P03, P04, P05, P06                                        |
| `Build`              | P07, P08, P09, P10                                                      |
| `Verify`             | P11, P12, P13                                                           |
| `PrepareBuildVerify` | P01, P02, P03, P04, P05, P06, P07, P08, P09, P10, P11, P12, P13         |
| `All`                | Same as `PrepareBuildVerify` plus BootTest                              |
| `BootTest`           | Out-of-band: Hyper-V Gen2 VM smoke test                                 |
| `Cleanup`            | (no phases) Remove `<WorkRoot>` after safety check                      |
| `ListPhases`         | (no phases) Print the registry and exit                                 |
| `GenerateManifest`   | P01, P02, P03 (Catalog scrape + writeback only)                         |

**Note on `Build` mapping**: P10 is INCLUDED in the `Build` Action
mapping AND in `standardFull` even though it is default-skip.
This is intentional - see B.20 for the design rationale. The
skip gate lives inside the phase function, not at the Action
layer, so operators running `-PhaseIds P10` still get the
explicit "skipped because no opt-in flag" log line rather than
an obscure "P10 not part of Build".

## B.7 ISO Filename Detection Patterns

`Get-IsoMetadata` recognises four shapes:

| # | Pattern (regex) | Examples |
|---|---|---|
| 1 | `^(?<build>\d{5})\.(?<rev>\d+)\.(?<date>\d{6}-\d{4})\.(?<branch>\w+)_(SERVER|CLIENT)_EVAL_(?<arch>x64FRE)_(?<lang>[a-z]{2}-[a-z]{2})\.iso$` | Server 2019/2022/2025 svc_refresh |
| 2 | `^SERVER_EVAL_(?<arch>x64FRE)_(?<lang>[a-z]{2}-[a-z]{2})\.iso$` | Server 2022 initial release |
| 3 | `^Windows_Server_2016_Datacenter_EVAL_(?<lang>[a-z]{2}-[a-z]{2})_(?<build>\d+)_refresh\.iso$` | Server 2016 en-us refresh |
| 4 | `^(?<build>\d{5})\.(?<rev>\d+)\.(?<date>\d{6}-\d{4})\.(?<branch>\w+)_SERVER_EVAL_X64FRE_(?<lang>[A-Z]{2}-[A-Z]{2})\.ISO$` | Server 2016 ja-jp UPPERCASE |

If none matches, `Get-IsoMetadata` returns `$null` and the caller falls
back to the Config-supplied OS/language pair.

## B.8 Patch Integrity Check (Three-Layer)

`Test-PatchIntegrity` runs three layers of checks, in order:

| Layer | Check |
|---|---|
| L1 | File exists; size > 0 |
| L2a | Filename-embedded SHA-1 (last 40 hex chars before `.msu`/`.cab`) matches Metalink SHA-1 (if both present) |
| L2b | Content SHA-1 matches Metalink SHA-1 (intentional use of SHA-1 — see Part D.5) |
| L2c | Content SHA-256 matches Metalink SHA-256 (if present in manifest) |
| L3 | `Get-AuthenticodeSignature -LiteralPath` is `Valid` AND signer is `*Microsoft*` |

Any hard failure throws; L3 is best-effort (some hosts may not have the
cert store) and records "Unverifiable" without throwing.

## B.9 Synthetic Test Mode

Enabled by `-SyntheticTestMode`. Used exclusively by Stage 3 CI:

| Behaviour | Why |
|---|---|
| No Microsoft asset is downloaded | Stays within evaluation licence boundaries for CI |
| ISO is generated via `dism /Capture-Image` on a tiny text payload + oscdimg wrap with stub boot files | Exercises the full DISM-mount + oscdimg pipeline without real binaries |
| Output ISO is intentionally non-bootable | The stub `etfsboot.com` and `efisys.bin` are 4-byte placeholders |
| P11 verification is relaxed (size floor 1 KB, KB list optional) | The synthetic image has no real KBs |
| P03 and P06 are both skipped | No real patches in play; Catalog scrape and wsusscn2 scan are unnecessary |
| CI MUST NOT upload the synthetic ISO | Belt-and-braces guard against accidental Microsoft-content leaks |

## B.10 Config Schema v2.1 (r05.0+)

The `Config/<OsKey>.json` schema is a 3-tier hierarchy. Each field
group carries a verification marker (`_VerifiedDate` / `_VerifiedBy`
for value-only groups, or `LastVerifiedDate` / `LastVerifiedBy` for
groups that also need to record their Patch Tuesday baseline).

**Schema 2.1 introduced in r05.0**: adds the top-level `Pca2023`
block (between `PatchBaseline` and `AutoRefreshPolicy`) that
captures per-OS Secure Boot conversion defaults consumed by
P10 / P12.

```jsonc
{
  "Schema":  "2.1",
  "OsKey":   "Server2025",

  // (A) OS-wide constants: unchanging once verified
  "Common": {
    "Build":              26100,
    "OsShortName":        "WS2025",
    "Edition":            "Datacenter",
    "Architecture":       "x64",
    "WimEdition":         "Windows Server 2025 Datacenter (Desktop Experience)",
    "InstallWimIndex":    4,
    "BootWimIndexes":     [1, 2],
    "WinReWimPath":       "Windows\\System32\\Recovery\\Winre.wim",
    "SupportedLanguages": ["en-us", "ja-jp"],
    "DefaultLanguage":    "en-us",
    "LCUExpandViaMum":    true,
    "_VerifiedDate":      "2026-05-24T00:00:00+09:00",
    "_VerifiedBy":        "manual:initial-r03"
  },

  // (B) Patch baseline: language-neutral patches (Patch Tuesday cadence)
  "PatchBaseline": {
    "Schema":                  "2.0",
    "TargetBuildAfterUpdate":  "26100.32522",
    "PatchTuesdayOfBaseline":  "",                  // YYYY-MM-DD; empty = uninitialised
    "LastVerifiedDate":        "",
    "LastVerifiedBy":          "",
    "VerificationMethod":      "",                  // auto-scrape | manual | auto-scrape+wsusscn2
    "ChecksumAlgorithm":       "SHA256",
    "NeutralPatches": [
      { "Type": "SSU",                  "KbId": "...", "IsCombined": false, ... },
      { "Type": "LCU",                  "KbId": "...", "IsCombined": true,  ... },
      { "Type": "DotNet",               "KbId": "...", ... },
      { "Type": "DynamicUpdate.Setup",  "KbId": "...", ... },
      { "Type": "DynamicUpdate.SafeOs", "KbId": "...", ... }
    ],
    "ExcludeKbList": [...],
    "WsusScnCab": { "SourceUrl": "...", "LocalCachePath": "", ... }
  },

  // (B') PCA2023 / Secure Boot conversion defaults (Schema 2.1+)
  "Pca2023": {
    "RequiredByDefault":          true,   // Server 2016/2019/2022 = true; Server 2025 = false
    "RequiredUpdateLevelKb":      "2024-4B (April 2024 LCU) or later",
    "RequiredUpdateLevelMinDate": "2024-04-09",
    "NotesSource":                [<Microsoft documentation URLs>],
    "Notes":                      "<plain-text operational note>"
  },

  // (C) Auto-refresh policy
  "AutoRefreshPolicy": { ... },

  // (D) Per-language: ISO source and language-specific patches
  "LanguageSpecific": { ... }
}
```

**Per-OS Pca2023 values:**

| OsKey | RequiredByDefault | MinDate | KbLabel |
|---|:---:|:---:|---|
| Server2016 | `true`  | `2024-04-09` | "2024-4B (April 2024 LCU) or later" |
| Server2019 | `true`  | `2024-04-09` | "2024-4B (April 2024 LCU) or later" |
| Server2022 | `true`  | `2025-02-11` | "2025-2B (February 2025 LCU, 20348.2227 baseline) or later" |
| Server2025 | `false` | `""`         | "n/a (firmware-provided 2023 certs)" |

Server 2022 has a later baseline date because the EFI_EX staging
directories appeared in cumulative updates only from the 2025-2B
LCU forward, per Lenovo lp2353.pdf.

Adding a new language is a one-node addition under `LanguageSpecific`
plus an entry in `Common.SupportedLanguages`. No changes are required
in `PatchBaseline` or `Pca2023` (both are language-neutral).

## B.11 Field Cadence and RefreshAllBaselines decision matrix (r03+)

The `$Script:OsConfigFieldGroups` constant (in
`.build_part03_helpers.ps1`) maps each logical field group to a
Cadence and an optional Refresher function. The constant drives the
`-Action RefreshAllBaselines` decision matrix.

| Group Path                                            | Cadence       | Refresher |
|-------------------------------------------------------|---------------|-----------|
| `Common`                                              | Stable        | (none)    |
| `PatchBaseline`                                       | PatchTuesday  | `Resolve-PatchSetFromCatalog` |
| `LanguageSpecific.<lang>.Iso`                         | IsoRelease    | (none)    |
| `LanguageSpecific.<lang>.LanguageSpecificPatches`     | PatchTuesday  | `Resolve-LanguageSpecificPatchesFromCatalog` |

Cadence semantics:
- **Stable**: once verified, never auto-refresh.
- **PatchTuesday**: refresh when recorded `PatchTuesdayOfBaseline`
  is older than the latest Patch Tuesday.
- **IsoRelease**: only refresh when Microsoft re-releases the ISO;
  not auto-refreshed in the current implementation (manual).

Decision matrix (returned by `Get-RefreshDecision`):

| Cadence \\ State      | `_VerifiedDate` empty      | recorded < latest PT | up-to-date |
|----------------------|---------------------------|----------------------|------------|
| Stable               | InitialFill or Manual     | (N/A)                | Skip       |
| PatchTuesday         | Monthly (or Manual if no Refresher) | Monthly  | Skip       |
| IsoRelease           | InitialFill or Manual     | (N/A)                | Skip       |

`-Mode Force` overrides: never returns Skip; collapses to Monthly /
InitialFill / Manual depending on Refresher availability.

The full JSON shape of this constant is exposed via
`-Action DumpFieldClassification` so external tooling (e.g. a Python
JSON Schema validator) can consume it without parsing PowerShell.

## B.12 PatchPlan engine and WIM-target mapping (r04+)

The `Build-PatchPlan` function (in `.build_part09c_patchplan.ps1`)
converts a flat patch list into a target-aware plan with four lanes:
`Install`, `Boot`, `WinRE`, `Setup`. The mapping from patch Type to
target lanes is centralised in `$Script:PatchTargetMap` (in
`.build_part03_helpers.ps1`).

The default mapping follows Microsoft's media-dynamic-update
guidance:

| Type                    | Targets                  | Microsoft reason |
|-------------------------|--------------------------|---|
| SSU                     | Install + Boot + WinRE   | Every serviced WIM needs the latest servicing stack |
| LCU                     | Install + Boot           | WinRE uses Safe OS DU instead |
| DotNet                  | Install                  | .NET 4.x lives in install.wim |
| DynamicUpdate.Component | Install                  | Component-store updates |
| DynamicUpdate.SafeOs    | WinRE                    | WinRE is the "Safe OS" |
| DynamicUpdate.Setup     | Setup                    | Setup binaries (pending.xml) |
| LanguagePack            | Install + WinRE          | User-facing UI + recovery UI |
| LXP                     | Install                  | LXPs are Store apps; no WinRE |
| DotNet.LangPack         | Install                  | .NET satellite assemblies |

Within each lane, patches are ordered by ascending `ApplyOrder`
(secondary key: `KbId`). Phase workers iterate the lane that
matches the WIM they have mounted; the worker for an Install lane
also runs the pre-apply dependency closure check before the first
`Add-WindowsPackage` call.

The plan object also carries diagnostic fields:
- `_GeneratedAt`  : ISO-8601 timestamp
- `_PatchCount`   : total distinct patches across all lanes
- `_TargetCounts` : per-lane counts
- `_UnknownTypes` : list of patch Types seen that were not in the map

Unknown Types fall back to `[Install]` with a one-time warning per
unique Type per run.

`Get-OrInitPatchPlan` is a lazy accessor that builds the plan on
first call and caches it in `$Script:PatchPlan`. P02 forces the
build at the end of ResolveInputs so the plan is ready when later
phases ask for it.

## B.13 Pre-apply dependency closure check (r04+)

`Test-PatchDependencyClosureOnMount` runs inside the per-WIM apply
loop just after `Mount-WindowsImage` and before the first
`Add-WindowsPackage`. For each patch whose `RequiresKbIds` is
non-empty, it enumerates installed packages via `Get-WindowsPackage`
and verifies that every required KB is already present
(`PackageIdentity` substring match against the recorded KB ID).

The check is governed by `$Script:PatchDependencyPolicy`, a
script-scope constant with two valid values:

| Value    | Behaviour |
|----------|-----------|
| `Strict` | **Default.** Throw on the first unsatisfied prerequisite; the run aborts before DISM emits the cryptic 0x800f0823 hex code |
| `Warn`   | Write a warning and continue; useful for runs where the operator has accepted some risk |

There is currently no CLI flag for this policy; a wrapper script
can set `$Script:PatchDependencyPolicy = 'Warn'` before invoking
the entry point if needed.

`-DryRun` short-circuits the check with a notice (no real mount).

## B.14 Microsoft media-dynamic-update sub-phase sequences (r04.1+)

For each WIM target, `Build-PatchPlan` emits an ordered array of
sub-phase descriptors (named after the Microsoft documentation:
I = install, B = boot, W = winre). Each sub-phase carries:

- `Name`            : symbolic identifier (e.g. `I3.LCU.FirstPass`)
- `Description`     : one-line human-readable purpose
- `Patches`         : array of patches that belong to this sub-phase
- `RequiresRemount` : if `$true`, the worker must dismount the WIM,
                      let DISM commit and export it, then re-mount
                      a fresh copy before running this sub-phase
- `IsCleanupMarker` : if `$true`, the worker runs DISM /Cleanup-Image
                      at this point and skips the Add-WindowsPackage
                      loop

**install.wim (P07)**:

| # | Name                       | Microsoft rationale |
|---|----------------------------|---|
| 1 | I1.SSU                     | Servicing stack first |
| 2 | I2.LanguagePack            | UI must be installed BEFORE the LCU's resource files |
| 3 | I3.LCU.FirstPass           | LCU after LP per Microsoft doc |
| 4 | I4.DotNet                  | .NET 4.x cumulative |
| 5 | I5.DynamicUpdate.Component | Component-store DU |
| 6 | I6.CleanupAndExport        | (worker hook for DISM /Cleanup + Export) |
| 7 | I7.LCU.SecondPass          | Emitted ONLY when LP was injected; `RequiresRemount = $true`; the LP injected in I2 can shadow files delivered by the I3 LCU, so the LCU is re-applied on a freshly-exported image |

**boot.wim (P08)**: B1.SSU -> B2.LanguagePack -> B3.LCU ->
B4.CleanupAndExport. No twice-apply needed.

**WinRE.wim (P08 inner block)**: W1.SSU -> W2.LanguagePack ->
W3.SafeOsDU -> W4.CleanupAndExport. The WinRE image is NOT
serviced with LCU; Microsoft delivers a Safe OS Dynamic Update
that plays the LCU role for the recovery environment.

`Invoke-PatchSubPhase` is the single helper that drives the apply
loop for any sub-phase. The phase workers iterate the sequence,
calling `Invoke-PatchSubPhase` for content-bearing sub-phases and
running `Invoke-DismCleanup` for `IsCleanupMarker` sub-phases.

## B.15 Supersedence-aware Catalogue candidate selection (r04.2+)

When the OS-aware Catalogue query for a single patch Type leaves
2 or more narrowed candidates after the Title-token / x64 filter,
the resolver enriches each candidate with the `Supersedes` and
`SupersededBy` arrays from `Get-SupersedenceFromCatalog`, then
calls `Select-LatestPatchBySupersedence` to keep only the latest.

Match rule: candidate `C` is "superseded by" candidate `D` when
`C.KbId` OR `C.UpdateId` is found (as a substring,
case-insensitive) anywhere in `D.Supersedes`. Substring match is
used because Catalogue Supersedes entries are inconsistent: some
contain only the KB number, some the full UpdateId GUID, some a
free-form `Package_for_KBnnnn~...` package identifier.

Selection cases:

| Input | Outcome |
|---|---|
| 0 candidates | `Best = $null`, `Excluded = @()` |
| 1 candidate  | `Best = that one`, `Excluded = @()` |
| 2+ with clear supersedence | `Best = single survivor`, `Excluded = (the rest)` with `Reason = "Superseded by <title>"` |
| 2+ with no supersedence relation | `Best = first by `Title` desc`, `Excluded = (the rest)` with `Reason = "Ambiguous; chose newest by title"` |
| Pathological (all candidates supersede each other) | `Best = first input`, warning logged |

Exclusions are accumulated across all patch Types in a single
Resolve call and exposed via `$Script:LastSupersedenceExclusions`
for the caller (A01 RefreshAllBaselines, P02 ResolveInputs) to
emit a CSV report. Supersedence lookup is a per-candidate HTTP
call, so it only fires when the narrowed count exceeds 1; the
single-candidate path keeps the HTTP cost at zero.

This protects the WIM-target-aware sequence (B.14) against
neighbouring KBs that match the OS Title token by accident, e.g.
a ".NET Framework 3.5 and 4.8.1 Cumulative Update" appearing in
a search for the OS LCU. Without supersedence-aware selection,
the wrong KB could enter the I3.LCU.FirstPass sub-phase and
produce a botched install.wim.

## B.16 Workspace preflight (r04.3+)

A mandatory check that runs **before the Action dispatcher**, so
that every Action (not just Build/Verify which run P01) is
protected. Implemented in `Assert-WorkspacePreflight`. Two checks,
both fatal:

1. **Config presence**. The four canonical `Config/Server<N>.json`
   files (Server2016, Server2019, Server2022, Server2025) must
   exist in the `Config/` directory alongside the script. A
   missing file aborts before any Catalogue scrape or DISM mount,
   with a precise list of which files are missing under which
   path. This protects RefreshAllBaselines and DumpFieldClassification
   from a half-populated workspace.

2. **Drive free space**. The drive backing `-WorkRoot` must have
   at least 100 GB free. This is the documented strict minimum
   for an end-to-end `PrepareBuildVerify` run for a single OS:

       ~7 GB  input ISO
       ~7 GB  extracted source tree
       ~15 GB mounted install.wim scratch
       ~10 GB patch downloads
       ~7 GB  output ISO
       ~5 GB  DISM temp + logs headroom

   The check uses `Get-PSDrive` on the drive letter of `-WorkRoot`.
   For UNC or unrooted paths, the script-root drive is checked as
   a best-effort fallback.

Preflight is skipped for:

| Condition | Rationale |
|---|---|
| `-Action ListPhases` | Quick branch that exits without touching the workspace |
| `-Action Cleanup` | The whole point is to remove a partially-built workspace; requiring 100 GB free would be circular |
| `-EnvironmentInfoOnly` | Operator explicitly asked for the env dump and wants to inspect the host first |
| `-SkipEnvCheck` | Operator override |
| `-DryRun` (disk-check half only) | Dry runs do not write large files; Config-presence check still runs |

This complements the runtime disk-space readout still emitted by
P01 Step 4 (informational only since r04.3; the authoritative
100 GB enforcement is in `Assert-WorkspacePreflight`).

## B.17 TestHarness REPL hook (r04.4+)

A new `-Action TestHarness` branch placed before
`Show-EntryBanner` allows the Python-side self-verification tools
in `tests/` to drive PowerShell functions without launching a fresh
`pwsh` per assertion. The harness:

1. Loads all function definitions in the current PowerShell
   session (because the dispatcher branch runs after the function
   declarations but before any Phase invocation).
2. Reads stdin one line at a time, parsing each line as JSON of
   the form `{"fn":"<FunctionName>","args":{ ... }}`.
3. Invokes the named function with `args` splatted and emits
   a single-line JSON response: `{"ok":true,"fn":"...","result": ...}`
   on success, `{"ok":false,"fn":"...","error":"<message>"}` on
   failure.
4. Exits on EOF.

Output contract: every byte on stdout must be machine-readable
JSON. The entry banner is suppressed by branching before
`Show-EntryBanner`; no Phase logs fire; no workspace contact is
made. The hook is added to the `osLessActions` set and to the
Preflight skip list because no Config / disk-space requirement
applies to in-memory function invocation.

The branch is invisible to human operators by design: it is not
listed in `Show-PhaseList`'s phase summary, has no documented
example invocation outside this section, and the `-Action` help
text explicitly directs operators to ignore it.

The Python driver lives in `tests/common/ps_invoke.py`
(`PSSession` class). All five `tests/*.py` tools that need PS
function output rely on this REPL contract. If the contract
ever has to change (e.g. JSON envelope schema bump), the change
must be co-ordinated between this section, the dispatcher branch
in the script, and `ps_invoke.py`.

## B.18 PCA2023 boot manager support (r05.0+)

This subsystem adds two phases (P10, P12) that address the 2026-06
expiry of the Microsoft "Windows Production PCA 2011" Secure Boot
certificate. Without intervention, ISOs built before 2026-06 will
boot only on firmware that has the 2011 cert in db; firmware that
has been updated to revoke 2011 (BlackLotus CVE-2023-24932
mitigation rollout) will refuse them.

**Operational model.** P12 ALWAYS runs in the Verify group:
operators always see whether their ISO is PCA2023-ready, even
when they are not converting it. P10 runs ONLY when
`-EnablePca2023BootManager` is set, and is silent-skipped for
Server 2025 unless `-ForcePca2023OnServer2025` is also set
(see D.22 for the rationale).

**Three-tier diagnostic.** P12 produces a snapshot composed of
three independent signals:

| Tier | Source | What it tells us |
|---|---|---|
| **1** | `Test-Path` on `boot.wim:\Windows\Boot\EFI_EX\bootmgfw_EX.efi` etc. | The 2024-4B staging directories are physically present in the boot environment WIM |
| **2** | `Get-WindowsPackage` on the mounted install.wim/boot.wim | Specific KB integration level - is the source media itself 2024-4B or later? |
| **3** | `Get-AuthenticodeSignature` chain walk on `efi\boot\bootx64.efi` | What the firmware will actually see - is the boot manager signed via 'Windows UEFI CA 2023' or still 'Windows Production PCA 2011'? |

A `Health` 4-value classification (`Healthy` / `Warning` /
`Critical` / `Unknown`) combines all three signals. The
classification logic is in `Get-Pca2023ReadinessSnapshot`.

**Outputs.** P12 produces two files under
`<WorkRoot>\pca2023\`:

- `pca2023_readiness.json` — machine-readable snapshot for
  downstream tools / dashboards
- `pca2023_readiness.md` — human-readable detail page with
  Reasons[] array unrolled into bullets and a code-block of the
  full inventory

P13 FinalReport additionally renders a Compact summary inline so
operators do not have to chase a second file (3-c output mode).

**Per-OS readiness defaults.** Carried in
`Config/<OsKey>.json#/Pca2023`:

```jsonc
"Pca2023": {
  "RequiredByDefault": true,                              // Server 2016/2019/2022
  "RequiredUpdateLevelKb": "2024-4B (April 2024 LCU) or later",
  "RequiredUpdateLevelMinDate": "2024-04-09",
  "NotesSource": [<URLs>],
  "Notes": "<plain text>"
}
```

For Server 2025 specifically: `RequiredByDefault = false`,
`RequiredUpdateLevelKb = "n/a (firmware-provided 2023 certs)"`.

## B.19 `-Pca2023OnlyMode` standalone inspection (r05.0+)

A side-channel entry point that takes an existing ISO file
(`-IsoPath <path>`) and runs ONLY P12 VerifyPca2023Readiness
against it. Skips all the patching machinery:

- No Microsoft Update Catalog scrape
- No `wsusscn2.cab` download
- No DISM patch integration
- No ISO re-assembly

Use cases:

1. Forensic inspection of an ISO produced by a non-`Update-WindowsServerIso.ps1` pipeline
2. CI smoke-test "would this published ISO still boot on PCA2023-only firmware?"
3. Auditing a media bundle before an air-gapped deployment

The mode short-circuits `Main()` after parameter validation; it
does not write to `<WorkRoot>` (mounts the ISO into a temp
directory under `$env:TEMP` and unmounts on exit). Output JSON
goes to `$env:TEMP\updwsi_pca2023only_<pid>\pca2023_readiness.json`.

## B.20 Build-group optional phase exception (r05.0+)

The Build group historically contains ONLY always-on phases:
P07 PatchInstallWim, P08 PatchBootWim, P09 AssembleIso. Each of
these is essential to producing a valid ISO; running `-Action
Build` without any of them produces undefined behaviour.

P10 ConvertPca2023BootManager is the **first** Build-group phase
that is opt-in. The reasoning is:

1. **P10 mutates an already-finished artifact.** P09 has already
   produced a usable ISO at this point. P10's role is to upgrade
   that ISO's boot manager signer chain, which is genuinely
   optional for operators whose target firmware still trusts
   PCA2011.

2. **Operator choice belongs at the CLI surface, not at runtime.**
   Hiding P10 behind a runtime "do you want to convert?" prompt
   would break the script's non-interactive contract (see B.0,
   "Script Identity"). A flag at script invocation time is the
   only acceptable opt-in mechanism.

3. **Server 2025 introduces a secondary opt-in layer.** Even with
   `-EnablePca2023BootManager`, Server 2025 specifically also
   requires `-ForcePca2023OnServer2025`. This layered gating is
   only possible because P10 has explicit pre-flight gates inside
   the phase function rather than relying on the Action-mapping
   layer for inclusion/exclusion.

**Consequence for `Resolve-PhasesForAction`.** P10 IS in the
`Build` Action's phase list AND in `standardFull`. The default
skip behaviour lives INSIDE the phase function, not in the
mapping. This is intentional: a future operator running
`-PhaseIds P10` should still trigger the skip gate, getting a
clear log line ("Skipped: -EnablePca2023BootManager not
specified") rather than an obscure "P10 was excluded from the
Action mapping".

**Consequence for SPEC.md B.5 phase contracts.** P10's "Always
runs?" column in the B.5 table is `Conditional`, not the usual
`Yes`. P10 is the only Build-group phase with `Conditional`
status; future Build additions should preserve this distinction
or change it deliberately.

## B.21 Update Type Matrix per OS generation (r06.0+, normative)

This section makes the until-now implicit assumption -- that
Server 2016/2019/2022/2025 all draw from the same enumerated
set of patch Types -- *explicit*. The matrix below is the
normative reference for which patch Types each supported OS
actually has on Microsoft Update Catalog, how they ship
(standalone vs. combined), and whether the ISO Factory must
inject them into the offline image.

The matrix was compiled from Microsoft Support KB pages, the
Windows Server release-info dashboard, the Microsoft Update
Catalog, the Microsoft Servicing Stack Update FAQ, and the
hotpatch enablement documentation. It is fixed for r06.0 and
will only be re-baselined when Microsoft publishes a new
servicing model change (e.g. a future OS generation that
unifies SSU into the LCU package for an even older Server
family).

### B.21.1 The matrix

| Patch Type                | Server 2016 (1607)    | Server 2019 (1809)            | Server 2022 (21H2)        | Server 2025 (24H2)        |
|---------------------------|-----------------------|-------------------------------|---------------------------|---------------------------|
| **SSU (standalone)**      | Required, monthly     | Required when Microsoft publishes one (varies) | N/A -- folded into LCU    | N/A -- folded into LCU    |
| **LCU (standalone)**      | Required, monthly     | Required, monthly             | -- (combined only)        | -- (combined only)        |
| **SSU+LCU combined**      | N/A                   | N/A                           | Required, monthly         | Required, monthly         |
| **.NET CU**               | 1 .msu (4.8 only)     | 1 umbrella, 2 files           | 1 umbrella, 2 files       | 1 umbrella, 1 file        |
| **Dynamic Update.Setup**  | Optional, monthly     | Optional, monthly             | Optional, monthly         | Optional, monthly         |
| **Dynamic Update.SafeOs** | Optional, monthly     | Optional, monthly             | Optional, monthly         | Optional, monthly         |
| **Hotpatch**              | N/A                   | N/A                           | Azure Edition only        | All editions (online only)|
| **Out-of-band (OOB)**     | Possible              | Possible                      | Possible                  | Possible                  |

Cell meanings:

- **Required**: must be present in the PatchBaseline.NeutralPatches
  array for a complete ISO build. The Refresher MUST find and
  record this Type each Patch Tuesday; absence indicates an
  upstream regression that warrants investigation.
- **Required when Microsoft publishes one (varies)**: Microsoft
  publishes the standalone SSU only in months where the servicing
  stack itself has changed. For Server 2019 specifically, an
  empty SSU result is not necessarily a Refresher bug -- Microsoft
  may simply have rolled the SSU forward into the LCU for that
  particular month, or skipped publishing a new SSU. Server 2019
  is in this category because the 2021-02 "SSU folded into LCU"
  consolidation Microsoft announced for "Windows 10 version 2004
  and later" does not technically apply to 1809, but in practice
  empty SSU months still occur. The Refresher's behaviour is:
  emit an info-level log, leave the previous SSU entry in place
  (it remains effective because LCUs are cumulative on the SSU
  side too), and do not treat the empty result as a failure.
  Operators should review whether the most-recent SSU on
  Catalogue is still being superseded by a recent LCU.
- **Optional**: included when Microsoft publishes it for that
  month (DU is not published every month for every OS); absence
  is normal and not a failure.
- **N/A**: this Type does not exist as a distinct payload for
  the OS in question. The Refresher MUST NOT try to fabricate
  an entry. Catalogue queries for an N/A Type SHOULD be skipped
  to save HTTP round-trips, but if a query is sent and returns
  zero results, that is the correct outcome and not a regression.
- **Possible**: present in some months and not others (OOB is
  by definition reactive to specific issues). The Refresher
  records OOB entries the same way as B-release entries; they
  participate in normal supersedence chains.

**Note on the 2026-05 production sample.** The PatchBaseline
files captured during the first r05.1 RefreshAllBaselines run
showed Server 2019 with zero SSU entries while Server 2016 had
a fresh SSU (KB5088064). This is consistent with "Required
when Microsoft publishes one (varies)" rather than a Refresher
defect; KB5088064 is a Server 2016 / Windows 10 1607 SSU
specifically and does not apply to 1809. Whether Microsoft
actually published a new Server 2019 SSU in 2026-05 is a
data-quality question that the Phase 2 PoC should answer
authoritatively by cross-referencing release-info against
Catalogue.

### B.21.2 .NET CU multiplicity by OS

The ".NET CU" row of B.21.1 captures the umbrella-vs-multifile
behaviour that motivated the r05.1 KbId fix (see CHANGELOG
[update-wsi-2026.05.25-r05.1]). The exact file counts
observed in production telemetry for 2026-05 are:

| OS           | Umbrella KbId (Title) | Attached .msu files | Per-file KbIds                        |
|--------------|-----------------------|---------------------|---------------------------------------|
| Server 2016  | KB5087065             | 1 (.NET 4.8)        | KB5087065                             |
| Server 2019  | KB5088864             | 2 (.NET 4.7.2, 4.8) | KB5087066, KB5087061                  |
| Server 2022  | KB5088862             | 2 (.NET 4.8, 4.8.1) | KB5087068, KB5087059                  |
| Server 2025  | KB5087051             | 1 (.NET 4.8.1)      | KB5087051                             |

The Refresher uses `Select-AllCanonicalPatchFiles` for any
".NET CU" candidate UpdateId, regardless of OS. The OS-specific
behaviour above is therefore the *expected* count, not a
configuration knob -- if Server 2016 ever shows 2 files or
Server 2019 ever shows 1, that is a Microsoft-side packaging
change worth flagging. Tracking the expected count per OS
under `Common.UpdateTypePolicy` is a candidate r06.x schema
extension (see B.21.5 "Future work").

### B.21.3 Combined LCU package detection

For Server 2022 / 2025 ("N/A standalone SSU" cells in B.21.1),
the LCU package ships with the SSU folded inside. The Refresher
needs to recognise this so that `Build-PatchPlan` does not
demand a non-existent standalone SSU before the LCU.

The detection logic in `Resolve-PatchSetFromCatalog` looks for
two independent signals and treats either as sufficient:

1. **Catalogue-side**: the SSU-typed query returns zero results
   for the requested OS / month, but the LCU-typed query
   returns a result. This is the *implicit* signal.
2. **Title-side**: the LCU's Catalogue Title contains a
   "combined SSU and LCU" phrase. Microsoft's KB pages
   consistently use this wording for combined packages (see,
   e.g., KB5068787 for Server 2022 November 2025).

When either signal fires, the Refresher annotates the LCU
entry with `"IsCombined": true`. `Build-PatchPlan` then skips
the SSU pre-step and applies the LCU directly. This matches
what `wusa.exe /quiet /norestart Windows10.0-KB<LCU>.msu`
does on a live system: SSU is unpacked and applied as part
of LCU installation.

For Server 2016 / 2019 (standalone SSU still exists), the
Refresher MUST find a separate SSU entry; LCU's `IsCombined`
is set to `false` and `Build-PatchPlan` enforces the SSU-then-
LCU ordering. If the SSU query unexpectedly returns zero
results for these OSes, the Refresher emits a warning -- it
is more likely a Catalogue query regression than a genuine
Microsoft-side packaging change.

### B.21.4 Hotpatch is out of scope for the offline image

Hotpatch is an *online-runtime* servicing mechanism delivered
via Windows Update / Azure Arc to a running OS, with the
servicing stack patching kernel-mode code in memory without
a reboot. The hotpatch packages cannot be applied to a mounted
WIM via `Add-WindowsPackage`; they have no equivalent in the
offline image servicing surface that DISM exposes.

This script therefore treats Hotpatch as outside the Patch
Manifest scope. However, Hotpatch *enrollment* imposes a
constraint that the offline ISO can satisfy: a Server 2025
machine wanting to enrol must be on a baseline-month LCU
(January / April / July / October). An ISO built from a
B-release LCU outside those months will still be eligible
to enrol, but the first applied online update will be a
baseline LCU that requires a reboot; an ISO built from a
baseline-month LCU can begin its hotpatch quarter immediately.

This is informational only in r06.0. A future r06.x might
add an opt-in `-PreferBaselineMonthLcu` switch that, when
set for Server 2025, prefers the most recent
January/April/July/October Patch Tuesday LCU even if a
newer B-release exists. Today the user can achieve the same
effect with `-PatchMonth 2026-04` etc.

### B.21.5 Future work (PoC-driven, no schema commitment yet)

The above matrix is the *spec*. The PoC -- to be run separately
before any schema change is committed -- will validate:

- Whether the Microsoft Learn `windows-server-release-info`
  page (markdown rendering: append `?accept=text/markdown` to
  the URL) covers all rows of the matrix above with sufficient
  fidelity that we can drop Catalogue Title-string heuristics.
- Whether Dynamic Update.Setup / Dynamic Update.SafeOs entries
  appear on a sibling release-info page or only on the Catalogue.
- Whether .NET CU per-OS multiplicity can be queried from a
  non-Catalogue source.
- Whether Hotpatch baseline-month detection (which Patch Tuesday
  KBs are baseline vs hotpatch) is queryable without scraping
  the techcommunity blog.

If the PoC succeeds, r06.x may add a `Common.UpdateTypePolicy`
sub-block to Schema 2.2 that codifies B.21.1 per-OS:

```jsonc
// Schema 2.2 candidate (NOT YET ADOPTED -- contingent on PoC)
"Common": {
  ...
  "UpdateTypePolicy": {
    "SSU":                  "standalone",        // or "combined" for 2022/2025
    "LCU":                  "standalone",        // or "combined-with-ssu"
    "DotNetCU": {
      "Required": true,
      "ExpectedFileCount": 1                     // 2 for 2019/2022
    },
    "DynamicUpdateSetup":   "optional",
    "DynamicUpdateSafeOs":  "optional",
    "Hotpatch":             "not-applicable"     // or "online-runtime-only"
  }
}
```

The schema decision is intentionally deferred to PoC outcomes.
This SPEC change (r06.0 Phase 1) does not modify the script
behaviour or the on-disk Config schema; it only makes the
implicit Type matrix normative so that a future schema
extension is grounded in a stated contract.

## B.22 File organisation and naming conventions (r06.0+, normative)

This section is the **governance model** for everything that lives
under the `scripts/powershell/update-windows-server-iso/` subproject
directory. It exists because r06 added a Proof-of-Concept stream
alongside the existing production code and the existing
`tests/` regression harness, and without explicit rules those three
classes of artefacts would start sharing directories and filenames
in confusing ways.

The rules below are normative: any new file added to this subproject
MUST land in the right directory and MUST use the right filename
prefix. The intent is that an outsider reading a filename should
know, without opening the file, **(a)** which artefact class it
belongs to, **(b)** whether it is permanent or disposable, and
**(c)** what role it plays in its class.

### B.22.1 Directory layout

```
scripts/powershell/update-windows-server-iso/
├── Update-WindowsServerIso.ps1     The production script. One file.
├── SPEC.md                         This document.
├── CHANGELOG.md                    Per-release notes.
├── README.md / README.ja.md        Bilingual user-facing readme.
├── PSScriptAnalyzerSettings.psd1   PSScriptAnalyzer config.
├── .psa.config.json                psa.py config.
├── .markdownlint.yaml              Markdownlint config.
├── Config/                         OS-specific JSON configs.
│   └── Server2016.json, Server2019.json, Server2022.json, Server2025.json
├── tests/                          Self-verification tools (see Part G).
│   ├── README.md                   Operational guide for tests/.
│   ├── common/                     Shared modules (HTTP client, parsers).
│   ├── fixtures/                   Saved HTML / JSON inputs for offline regression.
│   ├── snapshots/                  Probe-output snapshots used for drift diffing.
│   ├── <existing T1-T5>.py         Production-grade regression tools.
│   └── poc_<topic>_*.py            Time-bounded PoC scripts (r06+).
└── docs/                           Long-form documentation (r06.0+).
    └── poc/                        PoC reports and findings.
        └── poc-<topic>-<purpose>.md
```

Key points:

- **`Config/`, `tests/`, and `docs/` are the only first-class child
  directories.** No new top-level directories are added without a
  SPEC update; future "PoC ディレクトリ" or "experiments/" would
  violate this rule. PoC code lives under `tests/`, PoC reports
  live under `docs/poc/`, and that is sufficient.
- **PoC artefacts coexist with production artefacts** by filename
  prefix, not by directory. A PoC Python script under `tests/`
  uses the `poc_<topic>_` prefix to distinguish it from a T1-T5
  regression tool that has no such prefix.
- **The `docs/` directory is new in r06.0** and is the canonical
  home for *anything longer than a CHANGELOG entry that is not
  the SPEC itself*. PoC reports, post-mortems, design memos,
  architecture-decision-record-style write-ups all belong here.
- **Snapshot and fixture data follow the same prefix rule under
  `tests/`**: a PoC snapshot goes under
  `tests/snapshots/poc_<topic>/`, not in a sibling top-level
  directory.

### B.22.2 Filename prefix rules

| Class                         | Where it lives                   | Filename pattern                                      | Disposable? |
| ----------------------------- | -------------------------------- | ----------------------------------------------------- | :---------: |
| Production PowerShell         | top level                        | `Update-WindowsServerIso.ps1` (exactly one file)      | No          |
| Production config             | `Config/`                        | `Server<NNNN>.json`                                   | No          |
| Regression test (T1-T5)       | `tests/`                         | `<topic>_<role>.py` (no prefix; existing convention)  | No          |
| Regression test (shared)      | `tests/common/`                  | `<topic>_<role>.py`                                   | No          |
| Regression fixture            | `tests/fixtures/<patch-month>/`  | (per existing convention, see Part G)                 | No          |
| Regression snapshot           | `tests/snapshots/`               | `last_<topic>.json`                                   | No          |
| **PoC script**                | `tests/`                         | `poc_<topic>_<step>_<verb>.py`                        | **Yes**     |
| **PoC fixture / snapshot**    | `tests/fixtures/poc_<topic>/`<br>`tests/snapshots/poc_<topic>/` | (any reasonable filename inside)                      | **Yes**     |
| Production documentation      | `docs/`                          | `<topic>-<purpose>.md`                                | No          |
| **PoC documentation**         | `docs/poc/`                      | `poc-<topic>-<purpose>.md`                            | **Yes**     |
| Top-level docs                | top level                        | `SPEC.md`, `CHANGELOG.md`, `README*.md`               | No          |

"Disposable" means: when the corresponding feature lands in
production (or is decided not to), every file in that class can be
deleted as a single atomic step. PoC artefacts are time-bounded by
design; production artefacts are not.

`<topic>` is a short kebab-case (Markdown) or snake_case (Python)
identifier for the investigation subject. Pick one and use it
consistently across all files in a single PoC. For example, the
r06 Phase 2 PoC uses `release_info` (Python) / `release-info`
(Markdown) throughout.

`<step>` for a multi-step PoC script is a two-digit zero-padded
sequence number (`01`, `02`, ...). It establishes the execution
order so an outsider can run the PoC by sorting the matching
filenames alphabetically.

`<verb>` is a short imperative describing what the step does
(`fetch`, `parse`, `analyse`, `diff`, `validate`, `report`).
Plain past-tense or noun forms are discouraged (`fetched`,
`fetcher`); the imperative form makes the script feel like a
command, which is what it is.

`<purpose>` for a Markdown file is the document's role:
`report` (PoC findings), `readme` (operational guide), `design`
(forward-looking design memo), `decision` (architecture decision
record), `runbook` (operator procedure).

### B.22.3 Worked examples

| File                                              | Class                    | Reading the name                                                              |
| ------------------------------------------------- | ------------------------ | ----------------------------------------------------------------------------- |
| `tests/catalog_fixture_test.py`                   | Regression test (T2)     | "Catalog fixture test" -- no `poc_` prefix means it is permanent.             |
| `tests/poc_release_info_01_fetch.py`              | PoC script step 1        | r06 PoC; release-info topic; step 1; fetches data.                            |
| `tests/poc_release_info_02_parse.py`              | PoC script step 2        | r06 PoC; same topic; step 2; parses the fetched data.                         |
| `tests/poc_release_info_03_analyse.py`            | PoC script step 3        | r06 PoC; same topic; step 3; analyses the parsed data.                        |
| `tests/snapshots/poc_release_info/2026-05-25.md`  | PoC snapshot             | Snapshot for the release_info PoC, dated 2026-05-25.                          |
| `docs/poc/poc-release-info-readme.md`             | PoC documentation        | r06 PoC; release-info topic; "readme" purpose (how to run the scripts).       |
| `docs/poc/poc-release-info-report.md`             | PoC documentation        | r06 PoC; release-info topic; "report" purpose (findings + recommendations).   |

### B.22.4 What this section does NOT cover

- The conventions in `Part A — Inherited Common Specification`
  for end-of-line, BOM, ASCII-only-in-`.ps1`, line-ending in
  Markdown still apply unchanged.
- The conventions in `Part G — Self-verification tools` for the
  T1-T5 regression suite still apply unchanged.
- This section does not retroactively rename any existing file.
  T1-T5 keep their current filenames; they pre-date this rule.
  Only new files added from r06.0 onward must comply.
- Subproject-internal subdirectories under `docs/` other than
  `poc/` (e.g. a hypothetical `docs/architecture/`) are allowed
  when added with a SPEC update that describes them.

## B.14b PatchBaseline schema fields (referenced by B.10)

```jsonc
"PatchBaseline": {
  "Schema": "1.0",
  "TargetBuildAfterUpdate": "26100.4061",
  "PatchTuesdayOfBaseline": "2026-05-12",   // YYYY-MM-DD; empty = uninitialised
  "LastVerifiedDate": "2026-05-13T14:22:00+09:00",
  "LastVerifiedBy": "auto-scrape",          // or manual identifier
  "VerificationMethod": "auto-scrape",      // | manual+wsusscn2 | auto-scrape+wsusscn2
  "VerifiedOsLanguages": ["en-us", "ja-jp"],
  "ChecksumAlgorithm": "SHA256",
  "Patches": [
    {
      "Type": "SSU",                          // SSU | LCU | DynamicUpdate.* | DotNet | Defender | Edge | Other
      "KbId": "KB5055769",
      "Title": "Servicing Stack Update for Windows Server 2025 (KB5055769)",
      "UpdateId": "12345678-90ab-cdef-1234-567890abcdef",
      "DownloadUrl": "https://catalog.s.download.windowsupdate.com/.../ssu-...",
      "FileName": "ssu-26100.4061-x64.cab",
      "SizeBytes": 12345678,
      "Sha256": "abc123...",                  // recorded by P04 first download
      "ReleaseDate": "2026-05-12",
      "Supersedes": ["KB5051234"],
      "RequiresKbIds": [],
      "ApplyOrder": 1,
      "ApplicableArchitecture": "x64",
      "ApplicableLanguages": ["neutral"]
    }
  ],
  "ExcludeKbList": [
    {
      "KbId": "KB5043080",
      "Reason": "Checkpoint Cumulative Update; not required for OS install (per Microsoft Learn)."
    }
  ],
  "WsusScnCab": {
    "SourceUrl": "https://catalog.s.download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab",
    "LocalCachePath": "C:\\Temp\\Workspace_UpdateWsi\\cache\\wsusscn2.cab",
    "LastDownloadedDate": "2026-05-13T10:22:00+09:00",
    "LastDownloadedSha256": "abc123...",
    "LastDownloadedSizeBytes": 1234567890
  }
}

"AutoRefreshPolicy": {
  "Mode": "OnNewPatchTuesday",
  "WritebackToConfig": true,
  "FallbackOnScrapeFailure": "UseBaseline",
  "ScrapeRetries": 3
}
```

### Freshness contract

`Test-PatchBaselineFresh` returns `$true` if and only if all hold:

1. `Baseline` is non-null
2. `PatchTuesdayOfBaseline` is non-empty and parses as `yyyy-MM-dd`
3. `parse(PatchTuesdayOfBaseline) >= Get-LatestPatchTuesday()`
4. `Patches.Count > 0` AND at least one entry has all of
   `KbId`, `DownloadUrl`, `Sha256` populated

If any check fails, the baseline is "stale" and P03 scrapes anew.

### Patch Tuesday calculation

`Get-PatchTuesdayForMonth(Year, Month)` returns the second Tuesday of
the month. `Get-LatestPatchTuesday` returns the second Tuesday at or
before "now", with a 1-day buffer to avoid same-day boundary issues
(see Part D.15).

### Writeback semantics

`Save-ConfigWithBaseline` writes the in-memory `OsProfile` back to
`Config/<OsKey>.json` with these guarantees:

- LF line endings (matches `.gitattributes` `*.json text eol=lf`)
- UTF-8 without BOM
- `ConvertTo-Json -Depth 32` (full PatchBaseline.Patches[] expansion)
- Atomic write via `[System.IO.File]::WriteAllBytes`
- A trailing newline (POSIX-friendly)

The diff produced is small and reviewable: only `PatchTuesdayOfBaseline`,
`LastVerifiedDate`, `Patches[]`, and `WsusScnCab` fields change.

---

# Part C — Quality Gates & Validation Checklist

The following must all pass before any commit to this project.

### C.1 Static analysis

- [ ] `python3 ../../python/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1` returns **0 errors, 0 warnings, 0 info**.
- [ ] PSScriptAnalyzer in `pwsh 7` (Linux) returns no Error or Warning findings against `PSScriptAnalyzerSettings.psd1`.
- [ ] PSScriptAnalyzer in `powershell.exe 5.1` (Windows) returns no Error or Warning findings.

### C.2 Source-file format

- [ ] First 3 bytes of `Update-WindowsServerIso.ps1` are `EF BB BF` (UTF-8 BOM).
- [ ] All bytes after the BOM are `<= 0x7F` (strict ASCII).
- [ ] All newlines are CRLF (`0D 0A`); no bare LF.
- [ ] Indent is 4 spaces; no tabs.

### C.3 Configuration files

- [ ] All four `Config/Server*.json` parse with `json.load(...)` in Python.
- [ ] Every language entry has `IsoFwLink`, `IsoSnapshotUrl`, `IsoSha256`, `VolumeLabelPrefix`.
- [ ] `LCUExpandViaMum` is `true` only for `Server2025.json`.
- [ ] `RequireUefiCa2023Boot` is `true` only for `Server2025.json`.

### C.4 Functional smoke (runs on Windows; CI Stage 2)

- [ ] `.\Update-WindowsServerIso.ps1 -Action ListPhases` exits 0 and prints 9 phases.
- [ ] `.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly` exits 0 after the env dump.
- [ ] `.\Update-WindowsServerIso.ps1 -Action PrepareBuildVerify -OsVersion Server2019 -OsLanguage en-us -SyntheticTestMode -DryRun -SkipEnvCheck` exits 0.

### C.5 Full synthetic pipeline (runs on Windows; CI Stage 3)

- [ ] `.\Update-WindowsServerIso.ps1 -Action PrepareBuildVerify -OsVersion Server2019 -SyntheticTestMode -SkipEnvCheck -Execute` exits 0.
- [ ] An output ISO file is produced under `<WorkRoot>/output/`.
- [ ] **No ISO artifact is uploaded** by the CI job.

### C.5b Monthly baseline refresh (runs on Windows; CI Stage 4) — r03.1+

Stage 4 is an operations workflow that runs `-Action RefreshAllBaselines`
on a `cron` schedule (the 15th of each month at 02:00 UTC, roughly
3-7 days after Patch Tuesday) and on `workflow_dispatch`. Its job
is to keep `Config/Server*.json` baselines in sync with the latest
Microsoft Update Catalog state without manual maintainer effort.

- [ ] Workflow file
      `.github/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml`
      is present and parses as valid YAML.
- [ ] `cron: '0 2 15 * *'` is the only schedule entry.
- [ ] `workflow_dispatch` accepts four inputs: `mode`, `onlyOs`,
      `onlyLanguage`, `dryRun`. Cron uses the defaults (Monthly, all
      OS, all languages, no DryRun).
- [ ] On exit codes 0 (clean) and 2 (Manual fields remain) the
      workflow proceeds to the diff-detect step.
- [ ] On exit code 1 (orchestrator failure) the workflow fails the
      run and does NOT open a PR.
- [ ] When at least one `Config/Server*.json` file differs from the
      committed baseline, an automated PR is opened on branch
      `auto/uwsi-baseline-refresh-<run-id>` with title
      `chore(uwsi): monthly baseline refresh (run #<run-id>)`.
- [ ] PR `add-paths` restricts the diff to
      `scripts/powershell/update-windows-server-iso/Config/*.json`
      so an accidental change to other files cannot ride the auto-PR.
- [ ] PR labels: `automated`, `update-windows-server-iso`,
      `baseline-refresh`.
- [ ] Artefacts uploaded for every run (success or failure):
      `A01_RefreshAllBaselines_report.csv` and `debugtrace.jsonl`,
      retention 30 days.
- [ ] `$env:GITHUB_STEP_SUMMARY` is always populated so the run
      page shows the mode / OnlyOs / OnlyLanguage / DryRun / exit
      code / diff-detected / PR-created status at a glance.

### C.5c CI runner diagnostic pre-flight (r05.0+, all stages)

Each CI stage starts with a `[Diag] Runner environment snapshot` step
that records the runner state up front. This makes triage tractable
when scheduled (Stage 4 cron) or flaky failures occur: every failed
run carries the data needed to diagnose runner-side drift without
re-running the job. The information captured is platform-specific:

| Stage | Diagnostic information captured |
|---|---|
| **Stage 1 (Linux)** | `uname -a`, Python version, `pwsh` presence, CWD, `GITHUB_WORKSPACE` / `RUNNER_TEMP` / `RUNNER_OS` / `RUNNER_ARCH`, repo top-level listing |
| **Stage 2 (Windows)** | `$PSVersionTable`, `Get-Location`, `Get-ExecutionPolicy -List`, console encoding (`Console.OutputEncoding` + `$OutputEncoding`), `whoami` + admin check, env vars, oscdimg.exe presence at canonical ADK paths |
| **Stage 3 (Windows)** | Same as Stage 2 + free disk space on `C:` (Synthetic pipeline needs ~50 GB) |
| **Stage 4 (Windows)** | `$PSVersionTable`, ExecutionPolicy, `whoami`, key env vars |
| **psa.py CI (Linux)** | `uname -a`, Python version, CWD, repo top-level listing |

Each diagnostic step has `$ErrorActionPreference = 'Continue'`
(or `set +e` for bash) so a missing tool does not tank the whole
diagnostic step — the goal is to record what IS available, not to
fail-fast on what is not.

All non-diagnostic Windows PowerShell steps additionally set:

- `$ErrorActionPreference = 'Stop'` — prevents silent error
  swallowing (PS 5.1's default is `Continue`, which can mask
  `Get-ChildItem` / `Remove-Item` failures and produce confusing
  downstream errors).
- `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` —
  PS 5.1's default console encoding is the legacy ANSI code page
  (cp1252 on en-US hosts, cp932 on ja-JP), which mangles non-ASCII
  text written to `$GITHUB_ENV` / `$GITHUB_OUTPUT` / log streams.

The Windows-specific workflows also declare:

```yaml
defaults:
  run:
    shell: powershell
    working-directory: ${{ github.workspace }}
```

so step-level `working-directory` overrides remain visible and
relative paths resolve predictably against the checkout root, not
against `runner.temp` or some other surprising location.

Reference: `documents/ci-engineering/github-actions-windows-powershell-guide.md`
in this repository captures the broader github-actions Windows
runner reference material these conventions are derived from.

### C.6 Documentation cross-checks

- [ ] `README.md` and `README.ja.md` reference the same Disclaimer / License URLs.
- [ ] `README.md` parameter table is consistent with the `param()` block.
- [ ] `SPEC.md` Part B.5 phase contracts match the registered phases in the script.
- [ ] `CHANGELOG.md` has a new entry under `[Unreleased]` if the change is user-visible.

---

# Part D — Known Pitfalls & Lessons Learned

### D.1 DISM mount cleanup (OSDBuilder pattern)

**Symptom.** DISM commonly leaves orphan mounts after abnormal exits.
Subsequent mounts at the same path then fail with
`The directory could not be completely unmounted`.

**Fix.** `Invoke-WimMountSafe` runs `Get-WindowsImage -Mounted` and
discards any entry at the target path before mounting.
`Invoke-WimDismountSafe` follows the OSDBuilder
`Dismount-InstallwimOS` pattern: `Start-Sleep 10` (release Defender /
Indexer locks), attempt dismount silently; on failure, sleep another
30 seconds and try again with error propagation.

### D.2 SSU before LCU

**Symptom.** LCUs from 2018+ declare the SSU as a dependency. Applying
LCU first fails with `0x800f0922` ("CBS_E_INSTALLERS_FAILED_TO_LOAD").

**Fix.** `Get-PatchApplyOrder` returns 1 for `SSU` and 3 for `LCU`. The
P07 loop sorts by `ApplyOrder` before applying.

**OS-generation note (r06.0+).** This pitfall applies only to
Server 2016 / 2019, where SSU and LCU are still distinct
packages. For Server 2022 / 2025 the LCU package already
contains the SSU (combined SSU+LCU); there is no standalone
SSU on Catalogue, so `Get-PatchApplyOrder` simply never
encounters a Type=SSU entry for those OSes. SPEC §B.21.1
("Update Type Matrix per OS generation") and §B.21.3
("Combined LCU package detection") are normative on this
distinction.

### D.3 winre.wim is inside install.wim

**Symptom.** Patching boot.wim leaves the WinRE image stale; users see
old WinRE behaviour after recovery.

**Fix.** P08 includes a dedicated winre.wim sub-phase: mount install.wim
primary index, copy out `Windows\System32\Recovery\Winre.wim` to a
work file, mount the work file, apply patches, cleanup, dismount, copy
the result back into the mounted install.wim, dismount install.wim
with `-Save`.

### D.4 oscdimg etfsboot/efisys 3-tier fallback

**Symptom.** Some extracted ISO trees lack `boot/etfsboot.com` and/or
`efi/microsoft/boot/efisys.bin`. Older ADK installs put oscdimg under
`Program Files (x86)`, newer ones under `Program Files`.

**Fix.** `Resolve-EtfsbootCom`, `Resolve-EfisysBin`, and
`Resolve-OscdimgExe` all walk a three-tier candidate list (extracted
ISO → ADK x86 → ADK x64 → `$env:ISOFACTORY_PE_DIR` if set).

### D.5 SHA-1 is intentional in `Test-PatchIntegrity`

**Symptom.** psa.py PSA5003 warns on `Get-FileHash -Algorithm SHA1`.

**Why we keep it.** The Microsoft Update Catalogue **still publishes
SHA-1 hashes in patch filenames and download UI**. Refusing to verify
those would forfeit a real integrity check available upstream. The
script uses SHA-1 ONLY for that upstream-published sanity check; the
actual trust anchors are SHA-256 (L2c) and Authenticode (L3).

**Fix.** Each SHA-1 line carries an explicit `# psa-disable-line PSA5003`
with the justification.

### D.6 `Split-Path -LiteralPath ... -Parent` is ambiguous on PS 5.1 ja-JP

**Symptom.** PS 5.1 ja-JP locale rejects the combination as
`AmbiguousParameterSet`.

**Fix.** Use `[System.IO.Path]::GetDirectoryName($path)` everywhere a
parent directory is needed.

### D.7 Top-level `param()` variables in nested functions

**Symptom.** psa.py PSA2001 flags any bare `$IsoPath` reference inside
a function as undefined.

**Fix.** Every reference to a top-level param from inside a function is
qualified with `$Script:` (e.g. `$Script:IsoPath`). The param block
itself still uses bare names.

### D.8 0x800f081e is benign per OSDBuilder

**Symptom.** A patch returns `0x800f081e: The required content for this
update is not available for this OS SKU`. Stopping the loop here would
mean any cross-SKU patch set kills the entire run.

**Fix.** `Add-WindowsPackageWithRetry` catches this specific error,
emits a Warning, and returns `'NotApplicable'`. The loop continues.

### D.9 0x800f0a13 is a transient

**Symptom.** Modules Installer occasionally returns 0x800f0a13 under
heavy concurrent disk pressure.

**Fix.** `Add-WindowsPackageWithRetry` retries once after a 10-second
sleep. If the retry succeeds, the status is recorded as `'OkAfterRetry'`.

### D.10 `$args` is an automatic variable

**Symptom.** psa.py PSA2002 flags assignment to `$args` in
`Invoke-DismCleanup`.

**Fix.** Renamed to `$dismArgs`.

### D.11 Microsoft Eval ISO snapshot URLs rotate

**Symptom.** Direct snapshot URLs in `Config/<OsKey>.json` can return
404 after Microsoft rotates them.

**Fix.** Try `IsoFwLink` (which redirects to whatever the current
snapshot is) before falling back to `IsoSnapshotUrl`. Record the
download's actual SHA-256 in `Config/<OsKey>.json/Languages/<lang>/IsoSha256`
the first time a build succeeds, so the next run can verify.

### D.12 Sandbox-by-default

**Symptom.** Running the script interactively from an REPL once mounted
WIMs would commit irreversible changes.

**Fix.** Build phases (P07/P08/P09) default to Sandbox mode and emit
`[PLAN]` rows. The user must add `-Execute` to actually perform DISM
writes. Setup / Fetch / Plan / Verify / Report phases run
unconditionally.

### D.13 `Start-Transcript` has no `-LiteralPath`

**Symptom.** psa.py PSA3005 wants `-LiteralPath` on `Start-Transcript`.
The cmdlet does not support that parameter.

**Fix.** Inline `# psa-disable-next-line PSA3005` with a note explaining
the limitation.

### D.14 PowerShell 5.1 has no ternary operator

**Symptom.** `(if ($x) { 'a' } else { 'b' })` inside a function call's
parameter slot is technically valid but trips PSScriptAnalyzer's
parser on PS 5.1 + some PSSA versions.

**Fix.** Always assign to an explicit local: `if ($x) { $v = 'a' }
else { $v = 'b' }; ... -Status $v`.

### D.15 Patch Tuesday boundary buffer

**Symptom.** Microsoft publishes patches on the second Tuesday US
Pacific time. A user in Tokyo running the script on Wednesday morning
JST could see the local date as "after Patch Tuesday" while the
catalogue has not yet been populated on the Microsoft side.

**Fix.** `Get-LatestPatchTuesday` applies a 1-day buffer: the current
month's Patch Tuesday is only considered "already happened" when
local date is at least 1 day past it. This trades a one-day delay
in detecting fresh patches for elimination of empty-catalogue scrape
failures on Patch Tuesday itself.

### D.16 Microsoft Update Catalogue has no API

**Symptom.** There is no documented REST or SOAP API for
catalog.update.microsoft.com. Community modules (`MSCatalogLTS`,
the OSDSUS-driven Recast tooling, and Kazuro Yamauchi's published
sample) all scrape HTML / DownloadDialog responses.

**Fix.** The scraper functions
(`Get-UpdateIdFromCatalog`,
`Get-DownloadLinkFromCatalog`,
`Get-SupersedenceFromCatalog`)
each accept `-MaxRetries`, set a polite `User-Agent`, and use
`-UseBasicParsing` for Windows PowerShell 5.1 compatibility. The
`AutoRefreshPolicy.FallbackOnScrapeFailure` setting governs what
happens when the HTML structure changes and the regex extraction
fails.

### D.17 Auto-variable `$matches` cannot be reassigned

**Symptom.** Code such as `$matches = Get-UpdateIdFromCatalog ...`
trips `PSA2002 shadowing auto-variable` even though `$matches` is
read-after-`-match`. The analyser does not distinguish read-only
from read-write usage.

**Fix.** Use a non-automatic local name (e.g. `$catMatches`) when
storing collection results, and `[regex]::Match()` (which returns
an explicit `Match` object with `.Groups[N].Value`) instead of the
`-match`/`$matches[N]` pattern whenever a captured group is needed.

### D.18 wsusscn2.cab scans the local host's image, not the WIM

**Symptom.** `Invoke-WuaOfflineScan` is sometimes assumed to scan the
mounted install.wim. It does not. `Microsoft.Update.Session` scans
the local host's installed OS image against the offline catalog.

**Fix.** The validator must therefore run from a Windows host whose
OS family matches the target install.wim (Server 2025 host for a
Server 2025 image). When that match cannot be guaranteed (e.g. CI
runners can build any of the four supported OS versions), the
validator's findings are interpreted as a strong signal but not as
ground truth. P06 still aborts on missing patches because the
WUA-required set is approximately the union of what every supported
Server SKU requires.

### D.19 Catalogue Title comma-form drift (Server 2022)

**Symptom.** A previously-working OS query template suddenly returns
"no narrowed result" for every Type, even though the Catalogue
`Search.aspx` page itself still returns hits for the same query
string. The narrow filter — which compares each hit's `Title`
against an OS TitleToken via `[regex]::Escape(...)` — fails
because the live Title now omits a comma (or other punctuation)
that the template still encodes.

**Concrete case.** Server 2022 update titles historically read
"Microsoft server operating system, version 21H2"
(with a comma). As of 2026-05, Microsoft has dropped the comma to
match the Server 2025 (24H2) format:
"Microsoft server operating system version 21H2". The previous
TitleToken `'Microsoft server operating system, version 21H2'`
matched zero of the live hits.

**Fix.** TitleTokens must be **arrays** of acceptable forms, not
single strings. The narrow filter already iterates and uses
`-match` with `[regex]::Escape`, so accepting both the comma and
comma-less forms is purely a config change. The actual
`Search.aspx` query strings should track the live (current) form,
since that is what the Catalogue index uses for fuzzy ranking.
See `Get-CatalogQueryTemplate` and
`Get-LanguagePackQueryTemplate.osTitleTokens` for the canonical
multi-form pattern.

**Tell-tale log signature.** When this happens, every
`Catalog query: type=...` line for the affected OS is followed by
`Catalogue: no narrowed result for <Type> / <OsVersion>` and
the final `Resolved 0 patch entries from Catalogue` line. CI Stage 4
monthly-refresh runs catch this within ~30 days because the per-
OS pre-Manual count drops to 0; operators should monitor the
Stage 4 PR diff for any OS whose `NeutralPatches` array suddenly
empties.

**Setup vs SafeOs collision on Server 2022 (r05.1 fix).** A
related pitfall: for Server 2022 / 21H2-era Dynamic Updates,
Microsoft publishes Setup DU and Safe OS DU under titles that both
reduce to `"... Dynamic Update for Microsoft server operating
system version 21H2 ... x64"` after OS-title narrowing. The two
queries therefore collide on the same UpdateId, producing two
PatchBaseline entries (`Type=DynamicUpdate.Setup`,
`Type=DynamicUpdate.SafeOs`) that point at the *same* `.cab`
file. `Resolve-PatchSetFromCatalog` now applies a title-keyword
post-filter immediately after OS-title narrowing: Setup queries
keep titles matching `"Setup Dynamic Update"` (or anything that
is not Safe-OS-flavoured); SafeOs queries keep titles matching
`"Safe OS Dynamic Update"` / `"SafeOS"`. Server 2025's 24H2 titles
already include `Setup` and `Safe OS` distinctively, so no
post-filter is required for that OS — but the same logic is
applied uniformly because the cost is negligible.

### D.20 `Get-PatchType` filename heuristic is not authoritative

**Symptom.** A patch is silently routed to the wrong WIM-target
sub-phase (e.g. an SSU gets applied as if it were the LCU; a
Safe OS DU is offered to install.wim instead of WinRE; a .NET CU
sub-file is treated as an LCU). The on-disk Type field looks
plausible (always one of the registered values, never `'Other'`)
but is consistently wrong for certain KBs.

**Root cause.** `Get-PatchType -FileName <fn>` infers Type from
file-name tokens. Microsoft does not encode patch type into file
names consistently. Examples that defeat the heuristic:

- SSU file names like `windows10.0-kb5088064-x64_<sha>.msu`
  contain neither `servicingstack` nor `ssu`; the
  fallback `kb\d+` branch then labels them `LCU`.
- Safe OS DU file names like `windows11.0-kb5087588-x64_<sha>.cab`
  contain `kb\d+` but no `safeos`; same fall-through.
- Umbrella .NET CU sub-files like
  `windows10.0-kb5087061-x64_<sha>.msu` (the 4.7.2 sub-package
  of KB5088864) contain no `ndp<N>` and no `.net`; same fall-
  through.

**Fix.** Callers that already know the patch Type from context
MUST pass it explicitly. `Convert-CatalogPatchToBaselineEntry`
takes a `-KnownType` parameter for exactly this purpose;
`Resolve-PatchSetFromCatalog` populates it from the Catalogue
query bucket (`$q.Type`). The file-name heuristic is retained as
the last-resort fallback for ad-hoc invocations.

**General rule.** Any new caller that constructs a baseline entry
from Catalogue data must pipe the Catalogue's authoritative Type
information through to `Convert-CatalogPatchToBaselineEntry`
via `-KnownType`; never rely on file-name reverse-engineering.

### D.21 Umbrella KBs attach multiple files to one UpdateId

**Symptom.** A `.NET Cumulative Update` is recorded in
`Config/<OsKey>.json` with only one `NeutralPatches` entry, but a
later P07 build on an install.wim that contains the *other*
.NET runtime no-ops the .NET CU because the relevant sub-file
was dropped during baseline resolution.

**Root cause.** Microsoft occasionally publishes a single
Catalogue `UpdateId` that bundles multiple independently-applicable
MSUs — typically one per supported .NET runtime (e.g. 4.7.2 +
4.8 for Server 2019, 3.5 + 4.8 + 4.8.1 for Server 2022).
`Get-DownloadLinkFromCatalog` returns all of them, but
`Select-CanonicalPatchFile` is designed to return a single best
file. Without an explicit `-DotNetVersion` hint, both sub-files
score equally, the stable sort picks the first, and the rest are
silently dropped.

**Tell-tale log signature.** Look for
`<Type>: 2 candidate files; chose <fn>` lines from
`Resolve-PatchSetFromCatalog`'s pass-2 loop. If `<Type>` is
`DotNet` and the count is greater than 1, the dropped file is at
risk.

**Fix.** Use `Select-AllCanonicalPatchFiles` for any Type that can
legitimately have multiple sub-files. `Resolve-PatchSetFromCatalog`
gates this by Type: `DotNet` queries go through the multi-file
picker and emit one PatchBaseline entry per surviving file
(sharing `Title` / `UpdateId` / `Supersedes` from the umbrella KB;
only `FileName`, `DownloadUrl`, and **`KbId`** differ per entry).
Other Types (SSU / LCU / SafeOS / Setup DU) stay on the single-file
picker because Microsoft publishes a single canonical file per
UpdateId for them.

**Per-file KbId (r05.1).** Initially each multi-file entry stored
the umbrella Title's KbId, but production telemetry from
`-Action RefreshAllBaselines` showed that the umbrella label did
not match the actual payload file name (e.g.
`KbId=KB5088864` with `FileName=windows10.0-kb5087066-x64-ndp48_...msu`).
The helper `Get-KbIdFromPatchFileName` now extracts the `kb#######`
token directly from the file name, and `Resolve-PatchSetFromCatalog`
populates each entry's `KbId` from the file name, with the
umbrella Title KB as a fallback for file names that have no kb
token. This also fixes some LCU rows where the Title KB
(`KB5087539` umbrella) and the payload file (`kb5043080` checkpoint)
differed.

**Downstream safety.** `Build-PatchPlan` and the I4.DotNet sub-
phase already loop over multiple DotNet entries (SPEC §B.14), and
`Add-WindowsPackageWithRetry`'s 0x800f081e handling (Part D.8)
treats a "not applicable" return from DISM as benign — so if the
install.wim contains only one of the runtimes, the other entry's
DISM call no-ops safely.

**Normative spec (r06.0+).** SPEC §B.21.2 lists the expected
.NET CU file count for each OS generation (Server 2016 = 1 file,
Server 2019 / 2022 = 2 files, Server 2025 = 1 file). If the
Refresher ever produces a count that disagrees with that row,
it is a Microsoft-side packaging change worth investigating
rather than a bug in this script.


### D.22 Secure Boot baseline considerations (r05.0+)

The PCA2023 boot manager support (P10 / P12) integrates lessons
learned from `microsoft/secureboot_objects`'s upstream
`Make2023BootableMedia.ps1` and from the
`Deploy-Drivers-For-WindowsServer` reference repository's Secure
Boot baseline machinery. These notes capture the non-obvious
design constraints that shape the implementation.

**Why we re-implement `Copy-2023BootBins` rather than bundle MS's
script verbatim.** Microsoft's `Make2023BootableMedia.ps1` (Version
1.4, 2026-03-13) is a 1,141-line script with several non-portable
patterns that conflict with this project's quality gates:

- It uses `$global:WIM_Mount_Path` / `$global:WIM_File_Path` style
  globals that leak across phases. We adopt a Context-bag pattern
  via `$Script:Pca2023Snapshot` instead.
- It does NOT declare `#Requires -RunAsAdministrator`. Our
  re-implementation relies on `Assert-WorkspacePreflight` having
  already validated elevation before P10 dispatch.
- Verbose `[Parameter(Mandatory=$true)]` shorthand. Our project
  standard is the bare `[Parameter(Mandatory)]` form.
- A validator-bypass bug in `-OutputPath`: MS's `[ValidateScript]`
  regex `[<>:"|?*]` rejects every absolute Windows path because
  `:` follows the drive letter. We avoid invoking it directly; the
  `-Pca2023ScriptPath` escape hatch sets `-ISOPath` differently.
- `Write-Host` everywhere instead of structured logging. Our wrapper
  routes through `Write-Step` so the standard transcript / log
  collation works uniformly.
- `exit` statements rather than `throw`. Our phase wrappers cannot
  rely on `exit` because they need to leave DISM mounts cleanly
  unwound; the re-implementation uses `throw` with `try/finally`.

The functional logic (file copies between `EFI_EX` / `FONTS_EX` /
`DVD_EX` and the corresponding boot manager target paths) is
preserved verbatim. See `Convert-WimBootToPca2023Signed` in
the source for the side-by-side mapping.

**Why we read SYSTEM hive offline rather than query live UEFI
variables.** The reference Deploy-Drivers script's
`Get-SecureBootCertificateInventory` queries
`Get-SecureBootUEFI db / KEK / dbx` and reads
`HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing` of
the live host. ISO Factory has neither: there is no UEFI
environment on a Linux/macOS dev host, and `HKLM:` reflects the
build host, not the produced ISO. Our equivalent reads the
**WIM-internal** `SYSTEM` hive via `reg.exe load HKLM\TempHive
<install_wim>\Windows\System32\config\SYSTEM`. This is the only
way to inspect what the ISO would expose at first boot.

**Why locale-independence matters even for offline analysis.** The
Deploy-Drivers Secure Boot machinery had a hard-won lesson: it
originally used `schtasks.exe /Query /TN ... /FO CSV` to detect
the `Secure-Boot-Update` scheduled task state, but the CSV columns
are localized (Japanese: "ステータス" instead of "Status"), so
the parser broke on ja-JP Windows. The fix was to switch to
`Get-ScheduledTask`, which returns CIM objects with English
property names. While our ISO Factory does not parse scheduled
tasks, the broader lesson applies: **all SecureBoot servicing
values we read are checked as English tokens** (`'Updated'`,
`'NotStarted'`, `'Pending'`) because those registry values are
locale-independent by Microsoft design. Do NOT introduce
locale-dependent parsing into the SecureBoot helpers under any
circumstances.

**Why Server 2025 is default-skip for P10.** Per Microsoft's
techcommunity.microsoft.com guidance (2025), certified Server
2025 server platforms include the 2023 certificates in firmware
out of the box. Running `Copy-2023BootBins` against such media
is documented as not required and not officially supported (KB
5053484's supported-OS list does not include Server 2025). P10
gates this via `$Script:OsProfile.OsKey -eq 'Server2025'` and
requires `-ForcePca2023OnServer2025` to override; this matches
the Config schema's `Pca2023.RequiredByDefault = false` for
Server 2025.

**Why P12 reports Health = 'Critical' when LCU < 2024-04-09.**
Microsoft's `Make2023BootableMedia.ps1` halts with the message
"Make sure all required updates (2024-4B or later) have been
applied" if the source media's boot.wim does not include the
EFI_EX staging tree. We pre-flight this same condition: if
`Get-LcuVersionFromInstallWim` reports `MeetsPca2023Prereq =
$false`, we surface Health = `'Critical'` and refuse to run P10
(rather than letting the conversion produce a half-written ISO
that fails verification). The operator can correct the situation
by running `-Action RefreshAllBaselines` or by passing a newer
`-PatchMonth` and rebuilding.

**Reference URLs:**

- Microsoft KB / Support: [Updating Windows bootable media to use the PCA2023-signed boot manager](https://support.microsoft.com/en-us/topic/updating-windows-bootable-media-to-use-the-pca2023-signed-boot-manager-d4064779-0e4e-43ac-b2ce-24f434fcfa0f) — **KB ID 5053484**, original publish date 2025-02-04. Authoritative end-to-end procedure documentation.
- GitHub: [microsoft/secureboot_objects Make2023BootableMedia.ps1](https://github.com/microsoft/secureboot_objects/blob/main/scripts/windows/Make2023BootableMedia.ps1) — Version 1.4 (2026-03-13) was the snapshot analyzed for r05.0; future versions may diverge.
- TechCommunity: [Windows Server Secure Boot playbook for certificates expiring in 2026](https://techcommunity.microsoft.com/blog/windowsservernewsandbestpractices/windows-server-secure-boot-playbook-for-certificates-expiring-in-2026/4495789) (Server 2025 firmware status).
- Microsoft KB 5025885: [How to manage the Windows Boot Manager revocations for Secure Boot changes associated with CVE-2023-24932](https://support.microsoft.com/kb/5025885) — BlackLotus mitigation programme that drives the PCA2011 revocation timeline.

**KB 5053484 official "Applies To" set.** Per the support article header, the procedure officially covers Windows Server 2012, 2012 R2, 2016, 2019, 2022 plus the Windows 10 / 11 client SKUs back to version 1607. **Server 2025 is NOT listed** — its firmware-provided 2023 certificates make the procedure unnecessary. This project mirrors the official scope:

- P10 ConvertPca2023BootManager defaults to enabled for Server 2016/2019/2022.
- For Server 2025, P10 requires both `-EnablePca2023BootManager` and `-ForcePca2023OnServer2025` (operator-acknowledged override).
- Client SKUs (Windows 10/11) and Server 2012/R2 are out of scope for this project, but the underlying technique applies to them per the KB.

**Make2023BootableMedia.ps1 `-MediaPath` accepts three forms.** Upstream supports:

1. An ISO file path (`.iso`)
2. A local directory containing the expanded media tree
3. A network share path (`\\server\share\Media\`)

This project's wrapper currently operates on only one form — the local extracted media tree under `<WorkRoot>/source/extracted/` produced by P05 ExpandIso. The narrowing is intentional: the surrounding pipeline (patching, oscdimg re-assembly, hash verification) requires the directory form for repeatability and auditability. Operators who only need to flip an existing ISO without re-patching it should use `-Pca2023OnlyMode` (read-only inspection) or invoke `Make2023BootableMedia.ps1` directly out of band.


### D.23 UEFI Secure Boot defaults templates (informational, r05.0+)

The `microsoft/secureboot_objects` repository ships five reference UEFI Secure Boot configurations under `Templates/` (each as a TOML file describing PK/KEK/db/dbx contents). These are NOT consumed directly by this project — they describe **firmware-layer** Secure Boot variables, not the OS-layer boot manager signing that P10 / P12 operate on. But operators provisioning Server 2026+ hardware need to understand which template their target firmware is based on, because that determines whether PCA2023-signed media will actually boot.

| Template | db contains | KEK | When firmware uses this |
|---|---|---|---|
| **MicrosoftOnly** | Windows UEFI CA 2023 only | MS Corporation KEK 2K CA 2023 | Windows-only, most restrictive. Firmware revokes PCA2011. PCA2023-signed media REQUIRED. |
| **MicrosoftAndOptionRoms** | 2023 db + Option ROM 2023 CA | MS Corporation KEK 2K CA 2023 | Windows + Option ROM (e.g., RAID controllers, GPU firmware). PCA2023-signed media REQUIRED. |
| **MicrosoftAndThirdParty** | 2023 db + 3P UEFI 2023 CA | MS Corporation KEK 2K CA 2023 | Default for current Server 2025 certified platforms. 3P boot loaders (Linux distros etc.) also work. |
| **MostCompatible** | 2011 + 2023 db + 3P 2011 + 3P 2023 | MS Corporation KEK CA 2011 + KEK 2K CA 2023 | Transitional. PCA2011-signed and PCA2023-signed media BOTH boot. Most current shipping hardware. |
| **LegacyFirmwareDefaults** | 2011 db + 3P 2011 | MS Corporation KEK CA 2011 | Legacy. PCA2011-signed media REQUIRED. Pre-2026-06 hardware that has NOT received the BlackLotus mitigation revocations. |

**Why this matters operationally.** When an operator runs P12 against an ISO and gets `Health = Warning` ("PCA2011 boot manager, but EFI_EX staging present, P10 can promote"), the decision of whether to actually run P10 depends on the **target firmware's template**:

- Target firmware is **LegacyFirmwareDefaults** → PCA2023 media may FAIL to boot. Do NOT run P10. The existing PCA2011 media is correct for this hardware.
- Target firmware is **MostCompatible** → either signing works. Running P10 is forward-compatible but not required today.
- Target firmware is **MicrosoftAndThirdParty** / **MicrosoftAndOptionRoms** / **MicrosoftOnly** → PCA2023 signing is REQUIRED for new builds, P10 must run.

This project does not auto-detect target firmware (the target is by definition not the host running the build). The operator is expected to know which template their target hardware fleet uses. The defaults documented in `Config/<OsKey>.json#/Pca2023` reflect the **most common case for new hardware in 2026**, which is `MicrosoftAndThirdParty` for Server 2025 firmware and the transitional / legacy templates for older Server SKUs.

**References:**

- [microsoft/secureboot_objects/Templates/Readme.md](https://github.com/microsoft/secureboot_objects/blob/main/Templates/Readme.md) — EFI Signature List structure walkthrough.
- [microsoft/secureboot_objects/scripts/information/imaging_binaries_information.md](https://github.com/microsoft/secureboot_objects/blob/main/scripts/information/imaging_binaries_information.md) — PKCS7 / EFI_VARIABLE_AUTHENTICATION_2 descriptor layout for tools provisioning firmware variables (out of scope for this project, but relevant context for tools like WinPE `SetFirmwareVariableEx`).
- [UEFI Specification §32: Secure Boot and Driver Signing](https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html) — the underlying specification.

---

# Part E — Roadmap

| Milestone | Goal | Status |
|:---:|---|:---:|
| **M1** | MVP across all 4 OS x en-us/ja-jp, full registry, full phase set, sandbox + execute, synthetic mode, psa.py clean, README + SPEC + CHANGELOG + CI Stage 1/2/3 | **Done (r01)** |
| **M2** | `-AutoDetectLatestPatches` actually scrapes the Microsoft Update Catalogue (`Resolve-PatchSetFromCatalog`); writes Patch list back to `Config/<OsKey>.json#/PatchBaseline`; freshness gating via `Test-PatchBaselineFresh` | **Done (r02)** |
| **M3** | P06 `ValidatePatchSet` integrating `wsusscn2.cab` + Windows Update Agent COM API for Microsoft-authoritative dependency check; 4-file diagnostic export on failure | **Done (r02)** |
| M4 | Server 2025 `LCUExpandViaMum=true` real implementation (MUM/CAB expand path) | Placeholder |
| **M5** | Stage 4 CI workflow (`monthly-refresh`): monthly scheduled run that exercises `-Action RefreshAllBaselines` and opens a PR with the resulting `Config/<OsKey>.json` diff; catches Microsoft Update Catalogue HTML structure changes and Patch Tuesday drift within ~30 days | **Done (r03.1)** |
| **M6** | Microsoft-official media-dynamic-update servicing sequence: WIM-target-aware patch plan + pre-apply dependency closure check (r04) + LCU twice-apply + WinRE servicing + Language Pack injection (r04.1) | **Done (r04.1)** |
| M6 | Client SKUs (Windows 10/11) support — separate Config family | Future |
| M7 | Driver / FOD / LXP / Appx customisation (OSBuild equivalent) | Future |
| M8 | Output ISO size minimisation (`Export-WindowsImage` with `/Compress:max`) | Future |
| M9 | Multi-target deployment (Hyper-V auto-import, VMM library push) | Future |
| M10 | arm64 evaluation ISOs for Server 2025 (once Microsoft publishes them) | Future |

---

# Part F — Function Reuse Map

### Reused from `Download-SpeakerDeck.ps1` (verbatim)

| Function group | Purpose |
|---|---|
| `Set-ConsoleUtf8`, `Set-Tls12` | Host configuration |
| `Resolve-RelativeToScript`, `Initialize-RuntimeDirectories` | Path discipline |
| `Start-DebugTrace`, `Set-DebugStep`, `Stop-DebugTrace`, `Format-DebugFailure`, `Write-DebugFailureReport`, `Enable-DebugTraceFileOutput`, `Disable-DebugTraceFileOutput`, `Get-DebugTraceFileOutputStatus`, `Enable-AutoExportOnPhaseFailure`, `Export-DebugTraceJson` | Debug Trace Facility |
| `Format-Elapsed`, `Get-PhaseElapsedTag`, `_LogLine` | Time + log primitives |
| `Write-Step`, `Write-Ok`, `Write-Warn`, `Write-Fail`, `Write-Skip`, `Write-SubSection`, `Write-PhaseHeader`, `Write-PhaseFooter`, `Show-PhaseSummary` | Logging UX |
| `Test-DangerousPath`, `Invoke-CleanupDirectories` | Cleanup safety |
| `Get-FailureCategory`, `Write-FailureDiagnostic`, `Add-ErrorJsonlEntry` | Error reporting |
| `Wait-WithJitter`, `Invoke-WebRequestWithRetry` | Network retry |
| `Show-PowerShellEnvironment`, `Assert-PowerShellCompatibility` | Env check (P01) |

### New for `Update-WindowsServerIso.ps1`

| Function | Purpose |
|---|---|
| `Get-ConfigProfile` | Load `Config/<OsKey>.json` and attach the language node |
| `Get-IsoMetadata` | Detect OS/lang from an ISO filename (four patterns) |
| `Resolve-IsoSourceUrl` | Pick the source URL (explicit > FwLink > snapshot) |
| `Read-MetalinkManifest`, `Write-MetalinkManifest` | Metalink 4 (`.meta4`) IO |
| `Test-PatchIntegrity` | L1 + L2a + L2b + L2c + L3 integrity verification |
| `Get-PatchKbId`, `Get-PatchType`, `Get-PatchApplyOrder` | Classification + ordering |
| `Invoke-WimMountSafe`, `Invoke-WimDismountSafe` | DISM mount lifecycle (D.1) |
| `Add-WindowsPackageWithRetry` | DISM apply with 0x800f081e / 0x800f0a13 handling (D.8, D.9) |
| `Invoke-DismCleanup` | `StartComponentCleanup /ResetBase` |
| `Get-WimIndexInventory` | Locale-independent index enumeration |
| `Resolve-EtfsbootCom`, `Resolve-EfisysBin`, `Resolve-OscdimgExe` | 3-tier boot file fallback (D.4) |
| `New-BootableIso` | `oscdimg.exe` wrapper |
| `New-SyntheticTestIso` | CI mode S synthetic ISO (B.9) |
| `Test-AdminPrivilege` | Used by P01 |
| `Invoke-SetupPhase01_Initialize`..`Invoke-ReportPhase13_FinalReport` | The 9 phase workers |
| `Get-PatchListForInstallWim`, `Get-PatchListForBootWim` | Patch filtering per WIM |
| `Resolve-InstallWimTargetIndexes` | `-OnlyInstallWimIndexes` resolution |
| `Get-PhaseListByAction` | `-Action` → `string[]` mapping |
| `Show-PhaseList` | `-Action ListPhases` |
| `Invoke-PhaseRunner` | Registry-driven dispatcher |
| `Invoke-CleanupAction` | `-Action Cleanup` |
| `Invoke-HyperVBootTest` | `-Action BootTest` |
| `Show-EntryBanner` | Top-level banner |

### Added in r02 (dynamic baseline + wsusscn2 validation)

| Function | Purpose |
|---|---|
| `Get-PatchTuesdayForMonth` | Compute second Tuesday of (Year, Month) |
| `Get-LatestPatchTuesday` | Most recent Patch Tuesday on/before today (D.15 buffer) |
| `Format-PatchMonthString` | `datetime` → `'yyyy-MM'` for `-PatchMonth` |
| `Test-PatchBaselineFresh` | True iff baseline is non-stale and usable (B.10) |
| `Test-PatchBaselineUsable` | Like Fresh but ignores age (fallback-on-scrape-failure path) |
| `Save-ConfigWithBaseline` | Atomic JSON writeback (LF / UTF-8 / Depth 32) |
| `Convert-CatalogPatchToBaselineEntry` | Adapter: Catalog DTO → PatchBaseline schema |
| `Get-OsConfigPath` | Resolve `Config/<OsKey>.json` from `$Script:ScriptRoot` |
| `Get-UpdateIdFromCatalog` | `Search.aspx?q=<KB>` HTML scrape; returns array of UpdateId + Title |
| `Get-DownloadLinkFromCatalog` | `DownloadDialog.aspx` POST scrape; returns array of Url + FileName |
| `Get-CatalogQueryTemplate` (r02.5) | OS-specific Catalogue search templates (Server2016/2019/2022/2025) with Title / Product / Description per Microsoft media-dynamic-update guidance |
| `Get-CatalogQueryUrl` (r02.5) | Build Search.aspx URL with quoted Product / Description filter tokens |
| `Select-CanonicalPatchFile` (r02.5) | Scoring-based file picker that rejects Express/Delta/PSF differential packages and returns the single Full standalone file |
| `Test-IsCombinedLcuTitle` (r02.5) | True if an LCU title self-identifies as a combined SSU+LCU package |
| `Get-SupersedenceFromCatalog` | `ScopedViewInline.aspx` HTML scrape; returns Supersedes + SupersededBy |
| `Resolve-PatchSetFromCatalog` | Two-pass orchestrator: pass 1 runs OS-aware Catalogue searches; combined-LCU detector runs on the aggregate; pass 2 picks the canonical Full file per surviving candidate via `Select-CanonicalPatchFile` |
| `Get-LanguagePackQueryTemplate` (r03) | Per-language Catalogue search templates (LanguagePack / LXP / DotNet.LangPack) for OsVersion + OsLanguage + PatchMonth |
| `Resolve-LanguageSpecificPatchesFromCatalog` (r03) | Per-language Catalogue scraper; returns LP / LXP / .NET LP entries; empty result = verified absence |
| `Select-LatestPatchBySupersedence` (r04.2) | Deduplicate Catalogue candidates via their Supersedes / SupersededBy fields; returns the single newest survivor plus a list of excluded entries for diagnostic CSV |
| `Get-KbIdFromUpdateTitle` (r04.2) | Extract the `KB######` substring from a Catalogue update title |
| `Select-AllCanonicalPatchFiles` (r04.3) | Companion to `Select-CanonicalPatchFile`; returns ALL files that survive the scoring filter (Express / Delta / PSF / metadata still rejected) rather than just the highest-scoring one. Used by `Resolve-PatchSetFromCatalog` for `Type='DotNet'` umbrella KBs that attach multiple ndp-runtime MSUs to a single UpdateId |
| `Assert-WorkspacePreflight` (r04.3) | Mandatory preflight that runs before the Action dispatcher; throws if any of the four `Config/Server<N>.json` files are missing OR if the `-WorkRoot` drive has less than 100 GB free. Skipped for `ListPhases` / `Cleanup` / `-EnvironmentInfoOnly` / `-SkipEnvCheck` |
| `Get-PatchTargetsForType` (r04) | Returns the WIM target array for a given patch Type (Install / Boot / WinRE / Setup) via `$Script:PatchTargetMap` |
| `Build-PatchPlan` (r04) | Build a target-aware PatchPlan from the flat ResolvedPatches array, sorted by ApplyOrder within each target lane |
| `Build-InstallApplySequence` (r04.1) | Convert install.wim patch slice into the I1-I7 Microsoft media-dynamic-update sub-phase sequence; emits I7 (LCU second pass with RequiresRemount=$true) only when language packs are present |
| `Build-BootApplySequence` (r04.1) | Convert boot.wim patch slice into B1-B4 sub-phase sequence (SSU/LP/LCU/Cleanup); no twice-apply needed |
| `Build-WinReApplySequence` (r04.1) | Convert WinRE.wim patch slice into W1-W4 sub-phase sequence (SSU/LP/SafeOsDU/Cleanup); LCU is NOT included (Safe OS DU is the Microsoft-supported substitute) |
| `Invoke-PatchSubPhase` (r04.1) | Apply one sub-phase against a mounted WIM, handling DryRun, missing LocalPath, and Add-WindowsPackage failures; emits per-patch result rows |
| `Write-PatchPlanSummary` (r04, extended r04.1) | Human-readable per-target summary of a PatchPlan; r04.1 also prints the InstallSequence / BootSequence / WinReSequence breakdown |
| `Test-PatchDependencyClosureOnMount` (r04) | Pre-apply verification: every patch's RequiresKbIds must already be present in the mounted image (Get-WindowsPackage substring match); Strict mode aborts before DISM 0x800f0823 |
| `Get-OrInitPatchPlan` (r04) | Lazy accessor for `$Script:PatchPlan`; builds on first access |
| `Get-RefreshDecision` (r03) | Decide Skip / InitialFill / Monthly / Manual for a field group given Cadence, verification state, and latest Patch Tuesday |
| `Get-GroupSnapshot` (r03) | Read the verification meta-state for a field group from a raw config JSON object |
| `Set-GroupVerifiedState` (r03) | Update `_VerifiedDate` / `_VerifiedBy` / `LastVerified*` after a successful Refresher call |
| `Invoke-AdminPhaseA01_RefreshAllBaselines` (r03) | A01 admin phase: orchestrate field-group refresh across OS Configs |
| `Invoke-AdminPhaseA02_DumpFieldClassification` (r03) | A02 admin phase: dump `$Script:OsConfigFieldGroups` as JSON |
| `Get-WsusScnCabSourceUrl` | Microsoft canonical wsusscn2.cab URL |
| `Test-WsusScnCabFresh` | Cache freshness vs latest Patch Tuesday |
| `Get-WsusScnCabIfNeeded` | Conditional download with override-path support |
| `Invoke-WuaOfflineScan` | `Microsoft.Update.Session` COM offline scan against the cab |
| `Compare-PatchSetVsWuaScan` | Classify WUA-required updates as Provided / Missing |
| `Export-PatchValidationReport` | Emit 4 diagnostic files on validation failure |
| `Invoke-SetupPhase03_RefreshPatchBaseline` | P03 phase worker |
| `Invoke-PlanPhase06_ValidatePatchSet` | P06 phase worker |

---

# Part G — Self-verification tools (`tests/`)

The `tests/` subdirectory ships a Python-based self-verification
suite that exercises the script's external dependencies and the
PowerShell helpers themselves. It exists because three of the four
r04.3 live-test bugs were caused by silent Microsoft-side change
(comma-form drift in Catalog titles, multi-file `UpdateId` for
umbrella .NET CUs, file-name heuristic vs Catalogue Type bucket)
and no purely-static analysis could have caught any of them.

All tools use standard-library Python only (`urllib`, `re`, `json`,
`subprocess`) so the suite runs on any host with Python 3.10+ and
PowerShell 7+. No `pip install` is required.

| Tool | Verifies | Network |
|---|---|:---:|
| `tests/catalog_probe.py`        (T1) | Live Microsoft Update Catalog: Search.aspx reachable + GUID regex still matches + per-OS title format + ScopedViewInline supersedence panel structure. Diffs results against `tests/snapshots/last_probe.json`. | Yes |
| `tests/catalog_fixture_test.py` (T2) | Offline regression test against saved Catalog HTML in `tests/fixtures/<patch-month>/`. Includes bug-2 (comma-less title) and bug-3 (umbrella .NET CU) regression tests. | No  |
| `tests/powershell_harness.py`   (T3) | Python-side unit tests of `Update-WindowsServerIso.ps1` functions via the `-Action TestHarness` REPL hook (see §B.17). Asserts `Get-CatalogQueryTemplate`, `Select-AllCanonicalPatchFiles`, `Select-CanonicalPatchFile`, `Get-KbIdFromUpdateTitle`, `Test-IsCombinedLcuTitle`. | No  |
| `tests/eval_iso_probe.py`       (T4) | HTTP Range-GET against every `LanguageSpecific.<lang>.Iso.Url` in each `Config/Server<N>.json`; reports total size and `Last-Modified`. Detects snapshot rotation (see §D.11). | Yes |
| `tests/wsusscn2_probe.py`       (T5) | HTTP Range-GET against `wsusscn2.cab`; warns when the cab is older than 60 days. Detects egress-proxy `host_not_allowed` and reports it separately from real Microsoft outages. | Yes |

`tests/common/` holds:

| Module | Role |
|---|---|
| `catalog_client.py` | `urllib` HTTP client with retry-with-jitter; mirrors the PS scraper's User-Agent so probes are indistinguishable from production traffic |
| `html_parsers.py`   | Catalog HTML extractors (UpdateId GUIDs, search-hit titles, DownloadDialog file URLs, supersedence panel). Intentionally duplicates the PS regexes so any drift breaks BOTH sides loudly |
| `ps_invoke.py`      | `PSSession` context manager driving the `-Action TestHarness` REPL (§B.17) |
| `snapshot.py`       | JSON snapshot read/write + `diff_dict()` for surfaceable drift reports |

The suite is documented operationally in
[`tests/README.md`](./tests/README.md), which includes a
"what to run, when" guide for both Claude and human operators.

### Adjunct: PoC scripts under `tests/` (r06.0+)

The PoC scripts described in `B.22 File organisation and naming
conventions` share the `tests/` directory with the T1-T5 regression
suite, but are **distinct from it**:

- They are prefixed `poc_<topic>_<step>_<verb>.py` so they sort
  together and never collide with T1-T5 names.
- They are **time-bounded**: when the corresponding PoC concludes,
  the `poc_<topic>_*.py` files, the `tests/fixtures/poc_<topic>/`,
  the `tests/snapshots/poc_<topic>/`, and any matching
  `docs/poc/poc-<topic>-*.md` documents can all be deleted as a
  single atomic step.
- They do **not** participate in the T-numbered regression suite
  and are not required to be invoked by CI workflows.
- Operational docs (how to run them, what they output, the
  resulting findings) live under `docs/poc/`, not in `README.md`
  here. The PoC's own `docs/poc/poc-<topic>-readme.md` is the
  canonical entry point.

The current PoC tracked under this scheme:

| PoC topic        | Scripts                                              | Documents                                      |
|------------------|------------------------------------------------------|------------------------------------------------|
| `release_info`   | `tests/poc_release_info_01_fetch.py`<br>`tests/poc_release_info_02_parse.py`<br>`tests/poc_release_info_03_analyse.py` | `docs/poc/poc-release-info-readme.md`<br>`docs/poc/poc-release-info-report.md` |

---

# Part H — Reference Projects

- **[OSDBuilder](https://github.com/OSDeploy/OSDBuilder)** (David Segura) v24.10.8.1 — source of the DISM mount/dismount retry pattern (D.1), 0x800f081e suppression (D.8), and the boot file 3-tier idea (D.4). The most production-hardened reference.
- **[WIM Witch](https://github.com/MOOREDOMAIN/WIM-Witch)** — WIM update GUI; informed the boot.wim and winre.wim handling.
- **[Win_ISO_Patching_Scripts_zhCN](https://github.com/adavak/Win_ISO_Patching_Scripts_zhCN)** — direct source for the 3-tier `etfsboot.com` / `efisys.bin` fallback chain.
- **[rgl/windows-evaluation-isos-scraper](https://github.com/rgl/windows-evaluation-isos-scraper)** — canonical Windows Server 2022 SHA-256 hashes (en-us); used to seed `Config/Server2022.json`.
- **[`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1)** — sibling in-house script; the canonical source of the Part A common conventions inherited here.
