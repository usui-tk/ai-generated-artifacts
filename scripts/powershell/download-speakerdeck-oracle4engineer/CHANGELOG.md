# Changelog

All notable changes to `Download-SpeakerDeck.ps1` (the Speaker Deck
bulk downloader in this directory) are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project uses an `rNN` linear revision counter encoded in
`$Script:ScriptVersion` (the AI-generation date stamp + revision tag).
Each revision number is announced in the script banner, in the phase
header lines, and (from r23 onwards) in the Debug Trace Facility's
JSONL stream (`work/logs/debugtrace.jsonl`).

This CHANGELOG is **English only** per the
[repository-wide documentation language policy](../../../README.md#language-policy).

## [Unreleased]

_No unreleased changes at this time._

## [r23] — 2026-05-18 — `debugtrace-facility-and-pdfmeta-poc-removal`

### Added

- **Debug Trace Facility** (Section 1b, ~700 lines) ported from the
  `usui-tk/Deploy-Drivers-For-WindowsServer` reference scripts
  (Chipset r60 / BthPan r10). Three integrated subsystems share one
  set of trace primitives:
  - **Trace primitives** (`Start-DebugTrace` / `Set-DebugStep` /
    `Stop-DebugTrace` / `Format-DebugFailure` /
    `Write-DebugFailureReport`) record per-step checkpoints inside
    complex function bodies so a failure can be localised to a single
    step name rather than just a function name.
  - **JSONL file output** (`Enable-DebugTraceFileOutput` /
    `Disable-DebugTraceFileOutput` /
    `Get-DebugTraceFileOutputStatus`) streams every trace event in
    real time to `work/logs/debugtrace.jsonl` as a UTF-8-with-BOM
    append-only log; events emitted before file activation are
    buffered in memory and flushed in one go when activation
    succeeds.
  - **JSON point-in-time export + auto-export-on-failure**
    (`Export-DebugTraceJson` / `Enable-AutoExportOnPhaseFailure`)
    writes a self-contained snapshot of the active stack, completed
    frames, and per-phase registry to
    `work/diag/debugtrace_export_<phaseId>_<timestamp>.json`; the
    top-level catch handler triggers this automatically when a phase
    throws.
- Each of `Test-Environment`, `Get-TotalDeckCount`, `Get-AllDeckList`,
  `Invoke-Phase4Evaluation`, `Invoke-Phase5FilenamePlan`,
  `Invoke-Phase6Download`, `Invoke-Phase7Reconciliation`, and
  `Invoke-Phase8UndatedReclassify` is now wrapped in
  `Start-DebugTrace -PhaseId 'PNN'` / `Stop-DebugTrace`, with
  `Set-DebugStep` checkpoints at the major operational boundaries
  (HTTP fetches, CSV writes, parallel pool start/stop, etc.).
- Helper functions `Set-ConsoleUtf8` (sets all three encoding sources
  per the repo2 convention) and `Set-Tls12` (TLS 1.2/1.1/1.0
  fallback bitmask) extracted from the original inline `try { }`
  blocks for reuse and clearer call-site intent.

### Changed

- The top-level `catch` handler now calls
  `Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport` in
  addition to its existing `Write-Host` output, so an unhandled
  exception produces a JSON snapshot under `work/diag/` even when
  the user did not invoke any explicit diagnostic command.
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r23`,
  `$Script:ScriptTag` set to
  `debugtrace-facility-and-pdfmeta-poc-removal`.

### Removed

- **`Test-PdfMetadata.ps1`** (the read-only PoC that validated the
  PDF-metadata parsing logic before Phase 8 was productionised) has
  been deleted. The same parsing path now lives in
  `Get-PdfMetadata` inside `Download-SpeakerDeck.ps1`, exercised on
  every real run in Phase 8, so the standalone PoC no longer earned
  its keep. Documentation references to the file have been removed
  from `README.md`, `README.ja.md`, `SPEC.md`, and `TESTING.md` in
  the same revision.

### Verified

- `psa.py` v3.3.0 with `PSAP0003` / `PSAP0004` opt-ins:
  **0 errors / 0 warnings / 0 info** against the 5,156-line script.

### Notes

- This is a feature release that significantly enlarges the script
  (4,107 -> 5,156 lines; +1,049). The added facility is dormant
  unless a function actively calls `Set-DebugStep`; the runtime cost
  on the happy path is bounded by one frame open / one frame close
  per phase plus a handful of `Set-DebugStep` calls inside each
  phase.
- The existing Phase 6 per-deck failure diagnostics
  (`Write-FailureDiagnostic`, `Add-ErrorJsonlEntry`,
  `P06_errors.jsonl`, `work/diag/failed/`) are preserved unchanged.
  DebugTrace is a complementary cross-phase mechanism that operates
  at operation-level granularity, not a replacement for the
  download-specific diagnostics.

## [r22] — 2026-05-18 — `psa-header-comment-sync`

### Changed

- Script header comment block updated to reflect current static-analysis
  toolchain: `psa.py` v3.3.0 (36-rule check set `PSA1001..PSA9002` plus
  opt-in `PSAP0001..PSAP0004`), replacing the previous stale reference
  to `v3.1.0 (28-rule check set PSA1001..PSA7001)`.
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r22`,
  `$Script:ScriptTag` set to `psa-header-comment-sync`.

### Notes

- This release contains no functional changes; behaviour is identical
  to r21. It is a pure documentation cleanup release synchronising the
  in-script reference to the current `psa.py` toolchain.

## [r21] — 2026-05-18 — `changelog-md-policy-cleanup`

### Changed

- All inline `# rNN:`, `(rNN)`, and prose references to past revisions
  (`# before r13`, `# In r06 and earlier`, `# As of r08:`, etc.) have
  been removed from `Download-SpeakerDeck.ps1`. The descriptive prose
  has been rewritten to describe current behaviour in revision-neutral
  terms. Per-release history now lives exclusively in this `CHANGELOG.md`.
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r21`,
  `$Script:ScriptTag` set to `changelog-md-policy-cleanup`.
- Verified clean against `psa.py` 3.3.0 with PSAP0003 and PSAP0004
  enabled: 0 errors, 0 warnings, 0 info.

### Added

- This `CHANGELOG.md` file. Future revisions will be appended here in
  Keep a Changelog 1.1.0 format rather than being recorded in inline
  comments.

### Notes

- This release contains no functional changes; behaviour is identical
  to r20. It is a pure source-code cleanup release applying the
  repository-wide revision-history policy.

## [r20] — Earlier — `upstream-spec-style-alignment`

### Changed

- SPEC.md content and structure aligned with the upstream SPEC pattern
  used in other `scripts/powershell/*` sub-projects.

## [Pre-r20]

The per-revision history for r1 through r19 is not formally recorded
in this CHANGELOG file. Earlier releases tracked changes via inline
`# rNN:` comments in the script body. Those comments were removed in
r21 (see above) per the repository-wide revision-history policy
([root README, "Revision History Policy"](../../../README.md#revision-history-policy)),
which centralises per-release notes in `CHANGELOG.md`.

For the historical context that prior revisions encoded, refer to the
Git history of `Download-SpeakerDeck.ps1` in the
[`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
repository.

---

[Unreleased]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/powershell/download-speakerdeck-oracle4engineer
[r23]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/powershell/download-speakerdeck-oracle4engineer
[r22]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/powershell/download-speakerdeck-oracle4engineer
[r21]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/powershell/download-speakerdeck-oracle4engineer
[r20]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/powershell/download-speakerdeck-oracle4engineer
