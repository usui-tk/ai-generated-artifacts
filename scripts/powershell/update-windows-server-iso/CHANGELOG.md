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

### Planned (M2)
- Implement `-AutoDetectLatestPatches` as a real Microsoft Update
  Catalogue scraper (currently a placeholder that consults
  Config `AutoDetectKnownGood`).
- Emit a `Manifests/<OsKey>_<lang>_<yyyy-MM>.meta4` file as part of the
  `-Action GenerateManifest` flow so subsequent runs can reproduce the
  same patch set offline.

### Planned (M3)
- Server 2025 real `LCUExpandViaMum=true` code path. LCU on 2025 ships
  as a MUM/CAB bundle that must be expanded with `expand.exe -F:*`
  before `Add-WindowsPackage` is invoked.

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
