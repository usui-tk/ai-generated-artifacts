# Changelog

All notable changes to `Update-WindowsServerIso.ps1` (and its
companion files in this project directory) are documented in this
file. Per the repository-wide policy documented in the root
[`SPEC.md`](../../../SPEC.md), CI workflow changes are recorded here
too — not inside `.github/workflows/` — because this project is the
CI target.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The script version is held in `$Script:ScriptVersion` near the top of
the script and follows the
`update-wsi-<YYYY.MM.DD>-r<NN>` pattern.

## [Unreleased]

### Planned (M4)
- Server 2025 real `LCUExpandViaMum=true` code path. LCU on 2025 ships
  as a MUM/CAB bundle that must be expanded with `expand.exe -F:*`
  before `Add-WindowsPackage` is invoked.

### Planned (M5)
- Stage 4 CI workflow (`catalog-health`): monthly scheduled run of
  `Resolve-PatchSetFromCatalog` that opens a PR with the resulting
  `Config/<OsKey>.json` diff for human review. Catches Microsoft
  Update Catalogue HTML structure changes within 30 days.

## [update-wsi-2026.05.24-r02.1] - 2026-05-24

### Fixed — Stage 2 PSScriptAnalyzer (Windows PS 5.1) findings

r02 (`50fdb0f`) passed Stage 1 (Linux pwsh 7 + psa.py 0/0/0) but
failed Stage 2 (Windows PS 5.1 + microsoft/psscriptanalyzer-action)
on three rule categories that psa.py does not enforce. r02.1 addresses
all of them while keeping psa.py at 0/0/0.

- **`PSAvoidUsingBrokenHashAlgorithms`** (Severity = Error; the actual
  cause of the Stage 2 exit-code-1 failure) at `Test-PatchIntegrity`'s
  L2a/L2b SHA-1 checks. The function intentionally uses SHA-1 to
  sanity-check the SHA-1 hashes Microsoft Update Catalogue publishes
  alongside its patches, with SHA-256 (L2c) and Authenticode signatures
  (L3) as the real trust anchors. The previous `# psa-disable-line
  PSA5003 -- MS Catalog SHA-1` comments are a psa.py-specific
  suppression and do not affect the upstream `PSAvoidUsing*` rule.
  Replaced with a function-level
  `[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
       'PSAvoidUsingBrokenHashAlgorithms', '', Justification = '...')]`
  which is the canonical PSScriptAnalyzer suppression mechanism.
- **`PSUseDeclaredVarsMoreThanAssignments`** (Severity = Warning) at
  `Invoke-HyperVBootTest`'s `$vm = New-VM ...` assignment. The local
  `$vm` was never read again (subsequent operations use the VM name).
  Replaced with `New-VM ... | Out-Null` to match the surrounding
  Hyper-V calls' style.
- **`PSUseOutputTypeCorrectly`** (Severity = Information; x9 instances)
  at `Get-PhaseListByAction`'s nine `return @(...)` arms. PSSA
  cannot infer that an unannotated `@('a','b')` collection literal
  conforms to the declared `[OutputType([string[]])]`. Each `return`
  is now cast explicitly: `return [string[]]@('P01', 'P02', ...)`.

### Fixed — preventive (not yet observed on CI)

Local PSScriptAnalyzer 1.25.0 also surfaces one `PSReviewUnusedParameter`
warning (`$OsLanguage` declared but unused) inside
`Resolve-PatchSetFromCatalog`. CI's psscriptanalyzer-action@v1.1
appears to ship an earlier PSSA build that does not include this rule,
but to avoid future surprises the parameter is now used by an
informational `Write-Step` call at the head of the function.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,452 lines).
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning / Information.

### Compatibility

- Pure additive / mechanical changes: no behavioural difference from
  r02 at runtime.
- `ScriptVersion` is bumped from `update-wsi-2026.06.10-r02` to
  `update-wsi-2026.05.24-r02.1`; the `r02.1` suffix communicates a
  fix-up release of the r02 line.

## [update-wsi-2026.06.10-r02] - 2026-06-10

### Added — dynamic baseline (M2)

- New parameter `-PatchMonth yyyy-MM` to scope the Catalogue search
  (default: current month's Patch Tuesday).
- New parameter `-SkipDynamicPatchRefresh` to bypass P02.5 even when
  the baseline is stale (offline / air-gapped runs).
- New parameter `-UseBaselineOnly` to forbid all Catalogue access
  and use `PatchBaseline.Patches` strictly as-is.
- New phase **P02.5 RefreshPatchBaseline**: when
  `PatchTuesdayOfBaseline < Get-LatestPatchTuesday()`, scrape the
  Microsoft Update Catalogue for the target month (SSU + LCU +
  DynamicUpdate.Setup + DynamicUpdate.Component + DynamicUpdate.SafeOs
  + .NET CU), populate `PatchBaseline.Patches`, and write back to
  `Config/<OsKey>.json` atomically.
- Three scraper helpers (`Get-UpdateIdFromCatalog`,
  `Get-DownloadLinkFromCatalog`, `Get-SupersedenceFromCatalog`) that
  use `-UseBasicParsing` for Windows PowerShell 5.1 compatibility,
  set a polite User-Agent, and apply up to `ScrapeRetries` retries
  with jitter on transient HTTP failures.
- `Resolve-PatchSetFromCatalog` orchestrator that issues per-patch-type
  Catalogue queries, filters by OS title token + `x64` architecture,
  and auto-links each LCU's `RequiresKbIds` to the SSU(s) found in
  the same pass.
- Patch Tuesday calculator (`Get-PatchTuesdayForMonth`,
  `Get-LatestPatchTuesday`) with a 1-day buffer to avoid same-day
  edge cases (SPEC §D.15).

### Added — dependency validation (M3)

- New parameter `-WsusScnCabPath` to point at a pre-staged
  `wsusscn2.cab` instead of triggering an automatic download.
- New parameter `-IgnorePatchValidation` to demote P04.5 failure
  from abort to warning (NOT recommended for production).
- New phase **P04.5 ValidatePatchSet**: after the install.wim is
  extracted, optionally download (initial run OR cache older than
  current Patch Tuesday) and run a Windows Update Agent COM API
  offline scan with `Microsoft.Update.Session` against the supplied
  patch set. On any missing required patch: ABORT.
- Four diagnostic files emitted under `<WorkRoot>/diag/<timestamp>/`
  on validation failure:
    - `validation_summary.json` (top-level result + missing list)
    - `validation_detail.csv` (one row per patch with Provided / RequiredByWUA / DownloadHint)
    - `wsusscn2_scan_raw.json` (full raw WUA output)
    - `dependency_graph.json` (KB Requires / Supersedes adjacency)
- Diagnostic files are always emitted on detected-missing, regardless
  of `-IgnorePatchValidation`.

### Changed

- ScriptVersion: `update-wsi-2026.06.10-r02`,
  ScriptTag: `dynamic-baseline-and-wsusscn2-validation`.
- Banner unchanged: "Windows Server ISO Updater".
- P02 ResolveInputs: the patch-source resolution chain now also accepts
  "PatchBaseline-driven" when no explicit source (`-PatchUrls` /
  `-PatchDirectory` / `-ManifestPath`) is supplied AND
  `PatchBaseline.Patches` is non-empty (or `-AutoDetectLatestPatches`
  is set, in which case P02.5 will populate it).
- Phase registry: 11 entries (was 9). Action mappings updated to
  include P02.5 before P03 and P04.5 between P04 and P05.
- `Action GenerateManifest` now runs P01, P02, P02.5 (real Catalogue
  scrape that writes back to Config) instead of the r01 placeholder.

### Configuration

- `Config/Server201[6/9].json`, `Config/Server202[2/5].json` extended:
  - Added `PatchBaseline` node (Schema 1.0) with `TargetBuildAfterUpdate`,
    `PatchTuesdayOfBaseline`, `LastVerifiedDate`, `LastVerifiedBy`,
    `VerificationMethod`, `VerifiedOsLanguages`, `ChecksumAlgorithm`,
    `Patches`, `ExcludeKbList`, and `WsusScnCab`.
  - Added `AutoRefreshPolicy` node with `Mode`, `WritebackToConfig`,
    `FallbackOnScrapeFailure`, `ScrapeRetries`.
  - `AutoDetectKnownGood` marked deprecated (kept for r01 compatibility).
  - Server 2025 `ExcludeKbList` populated with KB5043080 (Checkpoint
    Cumulative Update; not required for OS install).

### Quality

- **psa.py**: 0 errors / 0 warnings / 0 info on the
  combined 5,447-line script (was 4,093 lines in r01).
- All r02 helpers have `[OutputType()]` declarations.
- All `r02`-anchored revision tags removed from script body comments
  (PSAP0003 / PSAP0005 compliant — revision history is here in the
  CHANGELOG, not in source comments).
- New `$matches` auto-variable usage in the Catalogue scraper replaced
  with explicit `[regex]::Match(...).Groups[N].Value` to satisfy
  PSA2002 (SPEC §D.17).

### Compatibility

- r01-format `Config/<OsKey>.json` files load unchanged (the `PatchBaseline`
  node is optional from the loader's perspective; if absent at load
  time, P02.5 will create it on first scrape).
- All r01 command lines (`-Action`, `-IsoPath`, `-PatchDirectory`,
  `-ManifestPath`, `-SyntheticTestMode -DryRun`, etc.) continue to
  work identically.

### Known limitations

- The Catalogue scraper depends on the current HTML structure of
  catalog.update.microsoft.com. A Microsoft-side change will break
  the scraper; the `AutoRefreshPolicy.FallbackOnScrapeFailure`
  setting controls the recovery behaviour.
- `Invoke-WuaOfflineScan` scans the local Windows host's installed
  image against the offline catalog; it is NOT a true WIM-level
  scan (SPEC §D.18). The validator's findings remain a strong signal
  for dependency completeness in practice.
- M5 (monthly Stage 4 catalog-health workflow) is not yet implemented.
- M4 (Server 2025 MUM/CAB LCU expand) is still a placeholder.

## [update-wsi-2026.05.24-r01] - 2026-05-24

### Added — script

- Initial MVP (M1 milestone) of `Update-WindowsServerIso.ps1`.
- 4,093-line single-file PowerShell script. UTF-8 with BOM, CRLF
  line endings, ASCII-only source bytes.
- Nine-phase pipeline (P01..P09) driven by a registry of
  `pscustomobject` entries and dispatched by `Invoke-PhaseRunner`.
- Sandbox-by-default semantics; destructive operations require
  `-Execute`.
- Synthetic test mode (`-SyntheticTestMode`) for CI: builds a tiny
  non-bootable ISO without downloading any Microsoft asset.
- Hyper-V Gen2 boot smoke test (`-Action BootTest`).
- Four OS configuration profiles under `Config/`:
  `Server2016.json`, `Server2019.json`, `Server2022.json`,
  `Server2025.json`. Per-language entries for en-us and ja-jp.
- Three-layer patch integrity check (filename SHA-1, content SHA-256,
  Authenticode signature) in `Test-PatchIntegrity`.
- DISM mount lifecycle hardened with OSDBuilder-style cleanup and
  10 s + 30 s retry in `Invoke-WimMountSafe` /
  `Invoke-WimDismountSafe` (see SPEC §D.1).
- `0x800f081e` and `0x800f0a13` suppression as Warning per
  documented heuristics in `Add-WindowsPackageWithRetry`
  (SPEC §D.8, §D.9).
- Three-tier boot file fallback chain (`etfsboot.com`, `efisys.bin`)
  in `Resolve-EtfsbootCom` / `Resolve-EfisysBin` (SPEC §D.4).
- Debug Trace Facility with JSONL output on failure, reused verbatim
  from the companion in-house script
  [`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1).

### Added — configuration files

- `.psa.config.json` — psa.py project configuration. Enables all
  PSAP00xx opt-in rules. Lists every Microsoft in-box cmdlet used by
  this script in `psa2010_known_cmdlets` so that the undefined-call
  rule stays silent.
- `PSScriptAnalyzerSettings.psd1` — PSScriptAnalyzer settings.
  Excludes `PSAvoidUsingWriteHost` (operator-facing UX uses the
  Write-Step / Write-Ok wrappers), `PSUseShouldProcessForStateChangingFunctions`
  (script is invoked via `.\` not as a module), and
  `PSUseCmdletBinding` (top-level CmdletBinding already in place).

### Added — documentation

- `README.md` — English primary user documentation, including
  required `## ⚠️ Disclaimer` and `## License` sections.
- `README.ja.md` — Japanese mirror of `README.md`.
- `SPEC.md` — authoritative developer / LLM specification.
  Inherits Part A from the
  [Download-SpeakerDeck SPEC](../download-speakerdeck-oracle4engineer/SPEC.md);
  Part B contains this script's unique contract (workspace layout,
  output naming, OS profile schema, per-phase contracts,
  action→phase mapping, ISO filename patterns, integrity check,
  synthetic mode); Part C is the quality-gate checklist;
  Part D is the catalogue of known pitfalls.
- `CHANGELOG.md` — this file.

### Added — CI workflows (at repo root `.github/workflows/`)

- `scripts__powershell__update-windows-server-iso__stage1__linux.yml`
  — Stage 1, Linux: `psa.py` + PSScriptAnalyzer in pwsh 7, BOM /
  CRLF / ASCII guard, Config JSON parse check.
- `scripts__powershell__update-windows-server-iso__stage2__windows.yml`
  — Stage 2, Windows: PSScriptAnalyzer in PS 5.1, parse-only check,
  read-only smoke modes (`ListPhases`, `EnvironmentInfoOnly`,
  `-SyntheticTestMode -DryRun`).
- `scripts__powershell__update-windows-server-iso__stage3__synthetic.yml`
  — Stage 3, Windows: ADK install (cached), full
  `-SyntheticTestMode` pipeline with `-Execute`. **No ISO artifact is
  ever uploaded**; only logs and diag are persisted as 14-day
  artifacts.

### Quality

- **psa.py**: 0 errors, 0 warnings, 0 info on
  `Update-WindowsServerIso.ps1`.
- All 13 advanced helper functions declare `[OutputType()]`.
- All top-level `param()` variables are accessed via `$Script:`
  from nested functions (PSA2001 compliance).
- No `Split-Path -LiteralPath ... -Parent` (PowerShell 5.1 ja-JP
  AmbiguousParameterSet workaround applied via
  `[System.IO.Path]::GetDirectoryName`).
- No `$args` shadowing (renamed to `$dismArgs` in
  `Invoke-DismCleanup`).
- All inline `# psa-disable-line` annotations carry an explicit
  justification.

### Compatibility

- Windows PowerShell 5.1: required base.
- PowerShell 7.x: also supported.
- Server 2016 / 2019 / 2022 / 2025: all supported.
- en-us and ja-jp ISOs: all supported.

### Known limitations

- `-AutoDetectLatestPatches` is a placeholder; populate Config
  `AutoDetectKnownGood` manually for now. Real implementation lands
  in M2.
- Server 2025 `LCUExpandViaMum=true` is configured but the actual
  expand-via-MUM code path is a future work item (M3).
- x86 and ARM64 are out of scope.
- BootTest requires a local Windows 11 host with Hyper-V; CI cannot
  exercise nested virtualisation.
- The Microsoft Update Catalogue scraper is local-only and not run
  in CI.
