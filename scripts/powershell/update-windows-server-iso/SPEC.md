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
  - [B.5 Phase Contracts (P01–P09)](#b5-phase-contracts-p01p09)
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
| Version | `update-wsi-2026.05.24-r02.2` |
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
| `EnableInstallWimUpdate` | bool | Run P05 against install.wim |
| `EnableBootWimUpdate` | bool | Run P06 against boot.wim |
| `EnableWinREUpdate` | bool | Run P06 against winre.wim too |
| `DotNetRequired` | bool | Apply .NET cumulative if present |
| `LCUExpandViaMum` | bool | `true` only for Server 2025; LCU ships as MUM/CAB bundle |
| `RequireUefiCa2023Boot` | bool | `true` only for Server 2025 (Secure Boot CA rotation) |
| `BootWimIndexes` | int[] | Typically `[1, 2]` |
| `InstallWimIndexes` | `"all"` or int[] | Filter for which install.wim indexes to patch |
| `ExpectedEditions` | string[] | For the P08 verification banner |
| `AutoDetectKnownGood` | object | KB IDs frozen as the latest known-good set (M2) |
| `Languages.<lang>.IsoFwLink` | string | Eval Center FwLink URL |
| `Languages.<lang>.IsoSnapshotUrl` | string | Direct snapshot URL (fallback) |
| `Languages.<lang>.IsoSha256` | string | Known-good ISO hash, populated on first run |
| `Languages.<lang>.IsoExpectedSize` | int | Approximate size in bytes |
| `Languages.<lang>.VolumeLabelPrefix` | string | Used in output volume label |

## B.5 Phase Contracts (P01–P09)

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

### P02.5 RefreshPatchBaseline (Setup)

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

### P03 FetchAssets (Fetch)

| Step | What |
|---|---|
| 1 | Download / use existing ISO; SHA-256 verify if config has one |
| 2 | Download / use existing patches; `Test-PatchIntegrity` per patch |
| Tactics | GUID-suffixed temp paths, atomic move on success, retry via `Invoke-WebRequestWithRetry` |

### P04 ExpandIso (Plan)

| Step | What |
|---|---|
| 1 | `Mount-DiskImage` the source ISO, copy contents to `extracted/`, `Dismount-DiskImage` |
| 2 | Enumerate `install.wim` and `boot.wim` indexes via `Get-WindowsImage` |
| Output | `logs/P04_wim_inventory.csv` |

### P04.5 ValidatePatchSet (Plan)

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

### P05 PatchInstallWim (Build)

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

### P06 PatchBootWim (Build)

For each boot.wim index in Config `BootWimIndexes` (typically `[1, 2]`):

| Step | What |
|---|---|
| Mount, apply, cleanup, dismount | Same lifecycle as P05, but with the boot-wim patch subset (SSU, LCU, SafeOs DU only) |

Then, if `EnableWinREUpdate`:

| Step | What |
|---|---|
| Extract | Mount install.wim primary index, copy embedded `Windows\System32\Recovery\Winre.wim` to `work/temp/` |
| Patch winre | Mount the copy, apply patches, cleanup, dismount |
| Re-embed | Copy the updated winre.wim back into the mounted install.wim |
| Dismount install.wim | Save + integrity-check |

### P07 AssembleIso (Build)

| Step | What |
|---|---|
| 1 | For each Dynamic Update Setup CAB: `expand.exe -F:*` into temp, overlay onto `extracted/sources/` |
| 2 | `New-BootableIso` invokes oscdimg with the 3-tier `etfsboot.com` / `efisys.bin` fallback chain |
| 3 | Verify the output ISO file exists and is non-empty |

### P08 StaticVerify (Verify)

| Step | What |
|---|---|
| 1 | Output ISO existence + minimum size check |
| 2 | `Mount-DiskImage` the output ISO; confirm `install.wim`, `boot.wim`, `setup.exe` exist |
| 3 | Enumerate WIM indexes; for the primary install.wim index, run `Get-WindowsPackage` and check each expected KB |
| 4 | `Dismount-DiskImage` |
| Output | `logs/P08_verification.csv` |

### P09 FinalReport (Report)

| Step | What |
|---|---|
| 1 | `Show-PhaseSummary` (timing + status per phase) |
| 2 | Output ISO SHA-256 + size + path |
| 3 | Log / diag directory hints |

## B.6 Action → Phase Mapping

| `-Action`            | Phases run                                                              |
|----------------------|-------------------------------------------------------------------------|
| `Prepare`            | P01, P02, P02.5, P03, P04, P04.5                                        |
| `Build`              | P05, P06, P07                                                           |
| `Verify`             | P08, P09                                                                |
| `PrepareBuildVerify` | P01, P02, P02.5, P03, P04, P04.5, P05, P06, P07, P08, P09               |
| `All`                | Same as `PrepareBuildVerify` plus BootTest                              |
| `BootTest`           | Out-of-band: Hyper-V Gen2 VM smoke test                                 |
| `Cleanup`            | (no phases) Remove `<WorkRoot>` after safety check                      |
| `ListPhases`         | (no phases) Print the registry and exit                                 |
| `GenerateManifest`   | P01, P02, P02.5 (Catalog scrape + writeback only)                       |

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
| P08 verification is relaxed (size floor 1 KB, KB list optional) | The synthetic image has no real KBs |
| P02.5 and P04.5 are both skipped | No real patches in play; Catalog scrape and wsusscn2 scan are unnecessary |
| CI MUST NOT upload the synthetic ISO | Belt-and-braces guard against accidental Microsoft-content leaks |

## B.10 PatchBaseline Schema

The `PatchBaseline` node in `Config/<OsKey>.json` is the canonical
store of "the latest known-good patch set for this OS". P02.5 reads
and writes this node; P03 fetches the URLs listed under `Patches`;
P04.5 validates the resulting set against `wsusscn2.cab` via WUA.

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
      "Sha256": "abc123...",                  // recorded by P03 first download
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

If any check fails, the baseline is "stale" and P02.5 scrapes anew.

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
P05 loop sorts by `ApplyOrder` before applying.

### D.3 winre.wim is inside install.wim

**Symptom.** Patching boot.wim leaves the WinRE image stale; users see
old WinRE behaviour after recovery.

**Fix.** P06 includes a dedicated winre.wim sub-phase: mount install.wim
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

**Fix.** Build phases (P05/P06/P07) default to Sandbox mode and emit
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
ground truth. P04.5 still aborts on missing patches because the
WUA-required set is approximately the union of what every supported
Server SKU requires.

---

# Part E — Roadmap

| Milestone | Goal | Status |
|:---:|---|:---:|
| **M1** | MVP across all 4 OS x en-us/ja-jp, full registry, full phase set, sandbox + execute, synthetic mode, psa.py clean, README + SPEC + CHANGELOG + CI Stage 1/2/3 | **Done (r01)** |
| **M2** | `-AutoDetectLatestPatches` actually scrapes the Microsoft Update Catalogue (`Resolve-PatchSetFromCatalog`); writes Patch list back to `Config/<OsKey>.json#/PatchBaseline`; freshness gating via `Test-PatchBaselineFresh` | **Done (r02)** |
| **M3** | P04.5 `ValidatePatchSet` integrating `wsusscn2.cab` + Windows Update Agent COM API for Microsoft-authoritative dependency check; 4-file diagnostic export on failure | **Done (r02)** |
| M4 | Server 2025 `LCUExpandViaMum=true` real implementation (MUM/CAB expand path) | Placeholder |
| M5 | Stage 4 CI workflow (`catalog-health`): monthly scheduled run that exercises `Resolve-PatchSetFromCatalog` and opens a PR with the resulting `Config/<OsKey>.json` diff; catches Microsoft Update Catalogue HTML structure changes within 30 days | Future |
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
| `Invoke-SetupPhase01_Initialize`..`Invoke-ReportPhase09_FinalReport` | The 9 phase workers |
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
| `Get-SupersedenceFromCatalog` | `ScopedViewInline.aspx` HTML scrape; returns Supersedes + SupersededBy |
| `Resolve-PatchSetFromCatalog` | Orchestrator: SSU + LCU + DynUp* + .NET for (OsVersion, PatchMonth, x64) |
| `Get-WsusScnCabSourceUrl` | Microsoft canonical wsusscn2.cab URL |
| `Test-WsusScnCabFresh` | Cache freshness vs latest Patch Tuesday |
| `Get-WsusScnCabIfNeeded` | Conditional download with override-path support |
| `Invoke-WuaOfflineScan` | `Microsoft.Update.Session` COM offline scan against the cab |
| `Compare-PatchSetVsWuaScan` | Classify WUA-required updates as Provided / Missing |
| `Export-PatchValidationReport` | Emit 4 diagnostic files on validation failure |
| `Invoke-SetupPhase02_5_RefreshPatchBaseline` | P02.5 phase worker |
| `Invoke-PlanPhase04_5_ValidatePatchSet` | P04.5 phase worker |

---

# Part H — Reference Projects

- **[OSDBuilder](https://github.com/OSDeploy/OSDBuilder)** (David Segura) v24.10.8.1 — source of the DISM mount/dismount retry pattern (D.1), 0x800f081e suppression (D.8), and the boot file 3-tier idea (D.4). The most production-hardened reference.
- **[WIM Witch](https://github.com/MOOREDOMAIN/WIM-Witch)** — WIM update GUI; informed the boot.wim and winre.wim handling.
- **[Win_ISO_Patching_Scripts_zhCN](https://github.com/adavak/Win_ISO_Patching_Scripts_zhCN)** — direct source for the 3-tier `etfsboot.com` / `efisys.bin` fallback chain.
- **[rgl/windows-evaluation-isos-scraper](https://github.com/rgl/windows-evaluation-isos-scraper)** — canonical Windows Server 2022 SHA-256 hashes (en-us); used to seed `Config/Server2022.json`.
- **[`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1)** — sibling in-house script; the canonical source of the Part A common conventions inherited here.
