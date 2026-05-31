# TESTING.md — Verification Procedure and Real-Run Results

This document consolidates everything needed to verify and evaluate
`Download-SpeakerDeck.ps1`. It covers three areas:

1. **Static analysis** — `quality-tools/powershell-static-analyzer/psa.py` gate (must pass before every commit)
2. **Functional verification — DryRun** — Phase 1–5 dry execution against the
   live Speaker Deck site (read-only)
3. **Functional verification — Real run** — full Phase 1–9 download against
   the `oracle4engineer` account, including the historical r16 → r17 regression
   fix evidence

> **Documentation language policy**: This document is maintained in
> English only per the repository-wide policy. See `README.md` and
> `README.ja.md` for the bilingual entry-point documentation; for the
> repository-wide language policy see the root `README.md` "Language
> Policy" section.

---

## Table of Contents

- [0. Verification status summary](#0-verification-status-summary)
- [1. Static analysis gate](#1-static-analysis-gate)
- [2. Functional verification — DryRun mode](#2-functional-verification--dryrun-mode)
- [3. Functional verification — Real run](#3-functional-verification--real-run)
- [4. Historical regression — r16 wildcard bug (resolved in r17)](#4-historical-regression--r16-wildcard-bug-resolved-in-r17)
- [5. Idempotency check (re-run behavior)](#5-idempotency-check-re-run-behavior)
- [6. Discovered bugs and fix history](#6-discovered-bugs-and-fix-history)
- [7. Outlook on CI/CD automation](#7-outlook-on-cicd-automation)
- [8. Debug Trace Facility verification (r23+)](#8-debug-trace-facility-verification-r23)

---

## 0. Verification status summary

| Item | Status | Last verified |
|---|---|---|
| `psa.py` (latest mainline; with project `.psa.config.json`) on `Download-SpeakerDeck.ps1` | **0 errors / 0 warnings / 0 info** ✓ | r27 build (`psa.py 4.0.1`) |
| File encoding (UTF-8 BOM, ASCII-only outside BOM) | ✓ for the script | r27 build |
| `PSAP0005` strict-mode baseline (no `rNN` references in comment bodies) | **0 findings** ✓ | r27 build (`psa.py 4.0.1`) |
| Phase 1 (EnvCheck) — Windows 11 / PS 5.1.26100.8328 | ✓ pass | 2026-05-11 |
| Phase 2–5 (Scan / Plan) — DryRun mode | ✓ 804 decks evaluated | 2026-05-11 |
| Phase 6 (Download) — real run | ✓ **804/804 success** (zero failures) | 2026-05-11 (r17) |
| Phase 7 (Reconciliation) — zero anomalies | ✓ all Discrepancy flags = 0 | 2026-05-11 (r17) |
| Phase 8 (UndatedReclassify) — steady state on re-run | ✓ examined: 0 | 2026-05-11 (r17) |
| Phase 9 (FinalReport) — output validated | ✓ year distribution + log files listed | 2026-05-11 (r17) |
| Total elapsed (real run, ~5.7 GB, 804 files) | 10 min 4 s | 2026-05-11 (r17) |
| Debug Trace Facility (A.14) — `debugtrace.jsonl` created on every run | _pending operator confirmation_ | r27 build (static checks only) |
| Debug Trace Facility (A.14) — stack-balance: every `frame.open` has a matching `frame.close` | _pending operator confirmation_ | r27 build (static checks only) |

---

## 1. Static analysis gate

`psa.py` (latest mainline; rule families `PSA1001`..`PSA9002` plus opt-in
`PSAP0001`..`PSAP0005`) must pass before every commit (see Part C of
[SPEC.md](./SPEC.md)). This project opts in to `PSAP0003`, `PSAP0004`,
and `PSAP0005` (the revision-discipline triad). `PSAP0005` (added in
`psa.py` 4.0.0) is enabled in **strict** mode — `psap0005_relaxed_mode`
is intentionally NOT set in `.psa.config.json`, so any `rNN` reference
inside a comment body is reported. The r21 cleanup commit removed
every such reference, so the strict baseline is the verified
end-state. For the canonical version-discovery and refresh workflow,
see repository root [`README.md`](../../../README.md) "psa.py
Versioning Policy".

`psa.py` auto-discovers `.psa.config.json` in the current working directory,
so the canonical invocation is from this script directory:

```bash
cd scripts/powershell/download-speakerdeck-oracle4engineer
python3 ../../python/powershell-static-analyzer/psa.py Download-SpeakerDeck.ps1
```

The local `.psa.config.json` disables `PSA6003` (plural function noun) and `PSA7003` (non-ASCII script body, default-on since `psa.py` 4.2.0; opted out for the intentional Japanese log strings and em-dashes) for
this directory only. Rationale: three functions in `Download-SpeakerDeck.ps1`
(`Resolve-RuntimeDirectories`, `Invoke-CleanupDirectories`,
`Read-YearOverrides`) intentionally use plural nouns because they operate on
collections of resources. The exemption is documented inline in the config
file. New code should still prefer singular nouns.

Expected output:

```
==== psa.py: PowerShell Static Analyzer ====
File   : Download-SpeakerDeck.ps1
Lines  : 5205
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

Any deviation from `0 / 0 / 0` blocks the commit. See
[`../../python/powershell-static-analyzer/SPEC.md`](../../python/powershell-static-analyzer/SPEC.md)
§4 for the full specification of the 46 rules
(`PSA1xxx` syntax / `PSA2xxx` semantics / `PSA3xxx` style / `PSA4xxx`
hygiene / `PSA5xxx` security / `PSA6xxx` best practice / `PSA7xxx`
file format / `PSA8xxx` cross-file consistency / `PSA9xxx` complexity
metrics / `PSAPxxxx` opt-in pipeline conventions).

### 1.1 Suppression policy

Empty `catch` blocks (`PSA3004`) that are **intentional** carry inline
suppression directives with a justification comment, for example:

```powershell
try { ... } catch { } # psa-disable-line PSA3004 -- diagnostic only; ...
```

Every `psa-disable-line PSA3004` in this script has been individually
reviewed and falls into one of these categories:

- Best-effort diagnostic capture (status code, response headers/body) where
  the retry / error-handling path is driven by other state.
- Fallback within a `foreach`-format / `foreach`-pattern loop where the
  per-iteration failure correctly means "try the next candidate".
- Cross-host compatibility shim (e.g., TLS enum values not present on
  older PowerShell hosts).

---

## 2. Functional verification — DryRun mode

DryRun executes Phase 1 through Phase 5 fully (including the filename plan
CSV output), and explicitly marks Phase 6 / 7 / 8 as SKIPPED. No files are
downloaded.

### Procedure

```powershell
cd D:\Script_OracleDocs
Unblock-File .\Download-SpeakerDeck.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Download-SpeakerDeck.ps1 -DryRun
```

### Expected output (abridged)

```
========================================================================
  Speaker Deck Bulk Downloader
  speakerdeck-2026.05.13-r20/<hash>
========================================================================
  Account         : oracle4engineer
  ...

 PHASE P01  - EnvCheck               (Setup  ) -> DONE  elapsed: 0.30s
 PHASE P02  - GetTotalCount          (Scan   ) -> DONE  elapsed: 0.36s
 PHASE P03  - ListCollection         (Scan   ) -> DONE  elapsed: ~1m
 PHASE P04  - Evaluation             (Scan   ) -> DONE  elapsed: ~7m
 PHASE P05  - FilenamePlan           (Plan   ) -> DONE  elapsed: ~0.5s
 PHASE P06  - Download               (Fetch  ) -> SKIPPED (DryRun mode)
 PHASE P07  - Reconciliation         (Verify ) -> SKIPPED (DryRun mode)
 PHASE P08  - UndatedReclassify      (Verify ) -> SKIPPED (DryRun mode)
 PHASE P09  - FinalReport            (Report ) -> DONE  elapsed: ~0.2s
```

### Verification checklist

- [ ] Phase 1 reports `LongPathsEnabled = 1` and the effective filename /
      full-path thresholds
- [ ] Phase 5 produces `work/logs/P05_filename_plan.csv` with 804 rows
- [ ] Year-folder distribution is shown in Phase 5 summary
- [ ] Phase 9 explicitly marks downloads as skipped (no false claim of success)

---

## 3. Functional verification — Real run

### Procedure

```powershell
cd D:\Script_OracleDocs
.\Download-SpeakerDeck.ps1 -Clean        # Initial run from scratch
# OR
.\Download-SpeakerDeck.ps1               # Incremental run (re-fetch failed only)
```

### Verified result (r17 build, 2026-05-11, oracle4engineer)

```
[Download]
    New downloads (Success) :   804
    Skipped (already exist) :     0
    Failed                  :     0          ← zero failures
    Total size              :  5,676.5 MB

[Year distribution]
    2026 :   64 decks      2025 :  131 decks
    2024 :  134 decks      2023 :  167 decks
    2022 :  143 decks      2021 :  119 decks
    2020 :   42 decks      2019 :    3 decks
    2014 :    1 deck

 PHASE P01  -> DONE     elapsed: 0.30s
 PHASE P02  -> DONE     elapsed: 0.36s
 PHASE P03  -> DONE     elapsed: 1m 2.7s
 PHASE P04  -> DONE     elapsed: 7m 14.5s
 PHASE P05  -> DONE     elapsed: 0.50s
 PHASE P06  -> DONE     elapsed: 1m 45.5s
 PHASE P07  -> DONE     elapsed: 0.30s
 PHASE P08  -> DONE     elapsed: 0.02s
 PHASE P09  -> DONE     elapsed: 0.12s
 ----------------------------------------
 Total elapsed          :        10m 4.4s
```

### Phase 7 Reconciliation (zero anomalies)

```
Reconciliation summary:
  Planned items                   :   804
    OK (downloaded + verified)    :   804
    OK-Skipped (already existed)  :     0
    FailedAsExpected              :     0
    NotAttempted                  :     0
    MissingAfterSuccess           :     0  *
    SizeMismatch                  :     0  *
    FailedButFileExists           :     0  *
    WrongYearFolder               :     0  *
  Extra files on disk             :     0
    UnexpectedFileOnDisk          :     0  *
    PartialDownload (.part)       :     0  *
```

All `*` anomaly flags must be `0` for a successful run.

---

## 4. Historical regression — r16 wildcard bug (resolved in r17)

This section preserves the evidence that the r17 fix actually closed the
regression.

### r16 symptom

```
[14:13:00] [+20.93s]    [X]  [#   6] Failed (System.IO.FileNotFoundException):
                                       oracle-technight-number-97-oracle-ai-database-26ai-updateai
[14:13:16] [+36.89s]    [X]  [#  12] Failed (System.IO.FileNotFoundException):
                                       oawtt26-thr1028
...
76 failures total — all titles contain '[' or ']' characters.
```

### r16 final state

```
[Download]
    New downloads (Success) :   728
    Failed                  :    76
    Total size              :  5,182.7 MB
```

### Root cause (codified in [SPEC.md](./SPEC.md) Part D.6)

`Invoke-WebRequest -OutFile` does **not** support `-LiteralPath` on
PowerShell 5.1; the `-OutFile` path is internally processed via `-Path`
semantics (wildcards expanded). Any path containing `[` or `]` is
interpreted as a wildcard character class and fails with
`FileNotFoundException`.

### r17 fix

Download to a GUID-named safe path first, then `Move-Item -LiteralPath`
to the real destination:

```powershell
$safeTmpName = '.dl_' + [Guid]::NewGuid().ToString('N') + '.part'
$safeTmp     = Join-Path $safeTmpDir $safeTmpName
Invoke-WebRequest -Uri $url -OutFile $safeTmp ...
Move-Item -LiteralPath $safeTmp -Destination $tmpFile -Force
```

### r17 verified result

| Year | r16 success | r17 success | Recovered |
|---:|---:|---:|---:|
| 2026 | 53 | 64 | **+11** |
| 2025 | 108 | 131 | **+23** |
| 2024 | 115 | 134 | **+19** |
| 2023 | 159 | 167 | **+8** |
| 2022 | 139 | 143 | **+4** |
| 2021 | 108 | 119 | **+11** |
| 2020 | 42 | 42 | 0 |
| 2019 | 3 | 3 | 0 |
| 2014 | 1 | 1 | 0 |
| **Total** | **728** | **804** | **+76** |

**The recovered count (76) exactly matches the r16 failure count (76).**
All historically failing decks now succeed; zero regressions on previously
passing decks.

---

## 5. Idempotency check (re-run behavior)

After a successful first run, an immediate re-run should reach a steady
state with zero new work:

### Procedure

```powershell
.\Download-SpeakerDeck.ps1     # No -Clean
```

### Expected steady state

- All 804 files exist on disk; Phase 6 reports `Skipped (already exist) : 804`
- Phase 7 reconciliation: zero anomalies
- Phase 8: `Found 0 _undated file(s) eligible for PDF-metadata rescue`
- Phase 9 shows no new downloads, no failures

### Phase 8 idempotency mechanism

The `work/logs/year_overrides.csv` file persists Phase 8's PDF-metadata
rescue decisions across runs. Phase 5's `Get-DeckYear` consults this
file at priority 0 (highest), so previously-rescued decks are routed
directly to their year folder on subsequent runs instead of being
re-rescued.

To force a complete re-run from scratch:

```powershell
.\Download-SpeakerDeck.ps1 -Clean
```

This wipes `<OutputDir>` and `<WorkDir>` (including `year_overrides.csv`)
before running.

---

## 6. Discovered bugs and fix history

| Revision | Bug | Severity | Fix |
|---|---|---|---|
| r10 | `Test-Path` / `Get-Item` / `Remove-Item` / `Move-Item` fail on paths containing `[ ]` | High | Apply `-LiteralPath` to all path-cmdlet calls |
| r11 | `Split-Path -LiteralPath -Parent` is not a valid PS 5.1 parameter set | Medium | Use `[System.IO.Path]::GetDirectoryName($p)` |
| r12 | _undated/ folder accumulating when no year derivable | Medium | Add year-folder organization + `_undated/` fallback |
| r13 | Environment uncertainty in different ja-JP setups | Low | Add Phase 1 Step 0 full environment dump |
| r14 | CSV columns inconsistent across phases | Low | Codify common 8-column convention |
| r15 | _undated/ files never reclassified even though metadata exists | Medium | Add Phase 8 PDF-metadata reclassification |
| r16 | Phase numbering had decimals (`P6.5`); confusing in logs | Low | Renumber to P01..P09 (1-indexed integers) |
| **r17** | **`Invoke-WebRequest -OutFile` wildcard interpretation breaks `[ ]` paths** | **High** | **Safe-temp GUID file + `Move-Item -LiteralPath`** |
| r18 | Folder layout integration with `ai-generated-artifacts` repo | Cosmetic | Update README + SPEC for repo placement |
| r19 | Single account folder couldn't host multiple targets | Cosmetic | Add `-<account>` suffix to folder name |
| r20 | SPEC file naming inconsistent with upstream | Cosmetic | Rename `spec.en.md` -> `SPEC.md` and `spec.ja.md` -> `SPEC.md`, refresh A.1.x structure, sync psa.py with upstream, add TESTING.md (psa.py later promoted to `quality-tools/powershell-static-analyzer/` as the repository-wide canonical location) |
| r21 | Inline `# rNN:` / "before r13" prose references accumulated in the source, conflicting with the repo-wide revision-history policy | Cosmetic | Strip all per-revision inline comments; centralise per-release history in `CHANGELOG.md`; enable `PSAP0003` / `PSAP0004` to fail any future regression |
| r22 | Script header comment still referred to an earlier upstream `psa.py` revision after upstream had moved to a later rule set | Cosmetic | Sync the in-script reference to the then-current mainline (`PSA1001..PSA9002` plus opt-in `PSAP0001..PSAP0004`) |
| **r23** | **No operation-level diagnostic existed for failures that are NOT per-deck** (e.g. structural exceptions in Phase 5 filename planning, CSV writes); per-deck `P06_errors.jsonl` could not localise such failures to a step inside the function body | **Medium** | **Implement the Debug Trace Facility (Section 1b, ~700 lines); instrument every phase function with `Start-DebugTrace -PhaseId 'PNN'` / `Set-DebugStep` / `Stop-DebugTrace`; activate `Enable-DebugTraceFileOutput` + `Enable-AutoExportOnPhaseFailure` from the main try-block. See SPEC.md A.14** |
| r23 | The standalone PDF-metadata PoC (`Test-PdfMetadata.ps1`) outlived its purpose — the same logic now runs in every real Phase 8 invocation | Cosmetic | Delete the PoC; remove all documentation references in the same revision |
| r24 | In-script comments and the SPEC / CHANGELOG / TESTING docs still pointed at the upstream `usui-tk/Deploy-Drivers-For-WindowsServer` repo even though all referenced helpers (logging, env dump, TLS/UTF-8, Debug Trace Facility) were already embedded in `Download-SpeakerDeck.ps1` after r23. Cross-repo dependency in the docs was now misleading. | Cosmetic | Remove every reference to the upstream repo from the script comments and the four docs; reorganise SPEC.md A.1 so `A.1.3 Companion in-house script` becomes the single canonical reference; simplify A.13 Reuse-before-invention to a two-step procedure |
| r25 | `Script:ScriptShortTag` was constructed as `"v{ScriptVersion}/{ScriptHash}"`, producing strings like `"vspeakerdeck-2026.05.18-r24/<hash>"` in every phase header, banner, and DebugTrace event. The `v` prefix glued directly to `speakerdeck` reads as the meaningless token `vspeakerdeck` to a human eye. | Cosmetic | Drop the `v` literal from the format string (`'{0}/{1}'` instead of `'v{0}/{1}'`); update SPEC A.3 examples, README phase-header samples, and TESTING examples to match |
| **r27** | **Two `psa.py 4.0.0` `PSA2009` warnings on `$job.Collected = $true` in Phase 4 / Phase 6 reaper loops**, although `$job` in those loops is a hashtable element of `$jobs` (not a sealed pscustomobject). PSA2009 used file-level tracking and conflated the foreach loop-variable with an unrelated `$job = [PSCustomObject]@{...}` initialiser in Phase 5. Without a fix, the documented `0 / 0 / 0` quality gate could not be met on `psa.py 4.0.0`. | Cosmetic (false-positive warning, no runtime defect) | **Two-sided fix**: (1) `psa.py 4.0.1` adds Step 2c2 to PSA2009 to recognise `$Coll.Add(@{...})` + `foreach (...) in $Coll` indirect binding (incl. pipeline-derived collections). (2) `Download-SpeakerDeck.ps1` Phase 4 hashtable init is updated to include `Collected = $false` for consistency with Phase 6's init (cosmetic). (3) `.psa.config.json` opts in to `PSAP0005` in strict mode (revision reference in comment body — the `r21` cleanup commit already cleared every site, so strict mode is the verified end-state). The r27 release line is named `psa-py-v4-llm-governance-baseline` to align with the sister `usui-tk/Deploy-Drivers-For-WindowsServer` repository's r76 / r42 / r24 / r20 release. See SPEC.md §A.11 and §D.7 for the full analysis. |

See [SPEC.md](./SPEC.md) Part D for the formalized "Known Pitfalls" entries
that bake each of these fixes into the project's institutional memory.

---

## 7. Implemented CI

As of r26, this sub-project ships **three GitHub Actions workflows**
under `.github/workflows/` at the repository root. They are listed
below in run order. The badges shown in [`README.md`](./README.md) link
directly to the corresponding workflow page.

### 7.1 STAGE 1 — Linux checks

**File**: `scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml`
**Runner**: `ubuntu-latest`
**Triggers**: `push` / `pull_request` on `main` (paths-filtered to
this script, the project `.psa.config.json`, the project
`PSScriptAnalyzerSettings.psd1`, the central `psa.py`, its `VERSION`,
and the workflow file itself), plus `workflow_dispatch` with an
optional `scope` input (`all` / `psa-only` / `pssa-only`).

**Steps**:

1. Checkout + set up Python 3.x.
2. `[psa.py] Run text analysis` — runs the canonical analyzer from the
   project directory (so `.psa.config.json` auto-loads via implicit
   discovery) and writes `psa.log`.
3. `[psa.py] Generate SARIF` — re-runs with `--format sarif` and
   writes `psa.sarif`.
4. `[psa.py] Upload SARIF to Code Scanning` — posts the SARIF to the
   repository's Code Scanning surface so findings appear in the
   Security tab and inline on pull requests.
5. `[PSSA-pwsh7] Run microsoft/psscriptanalyzer-action` — invokes the
   official Marketplace action against `Download-SpeakerDeck.ps1`
   under PowerShell 7.x, using the project-local
   `PSScriptAnalyzerSettings.psd1`. Emits `pssa.sarif`.
6. `[PSSA-pwsh7] Upload SARIF to Code Scanning` — same as for psa.py.
7. `[PSSA-pwsh7] Generate text log from SARIF` — produces a
   human-readable `pssa.log` artifact for grep-based inspection
   alongside the SARIF.
8. `[Summary]` — writes a job-step summary to the Actions UI.
9. `[Artifacts]` — uploads `psa.log`, `psa.sarif`, `pssa.log`, and
   `pssa.sarif` with 14-day retention.

**Timeout**: 90 minutes (T2-extended, see repository-root `/SPEC.md` §4).
**Expected output on a clean tree**: 0 findings at all severities.

### 7.2 STAGE 2 — Windows checks (PowerShell 5.1 + Phase 1 smoke)

**File**: `scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml`
**Runner**: `windows-latest`
**Triggers**: `workflow_run` on STAGE 1 completion (only fires when
the upstream conclusion is `success`), plus `workflow_dispatch`.

**Steps**:

1. Checkout.
2. `[PSSA-pwsh51] Run microsoft/psscriptanalyzer-action` — same action,
   same settings, but running on Windows PowerShell 5.1 — the targeted
   baseline of `Download-SpeakerDeck.ps1`.
3. `[PSSA-pwsh51] Upload SARIF to Code Scanning`.
4. `[PSSA-pwsh51] Generate text log from SARIF`.
5. `[Phase1-smoke] Run Download-SpeakerDeck.ps1 with -EnvironmentInfoOnly`
   — this exercises script loading, parameter binding, and Phase 1
   Step 0 (`Show-PowerShellEnvironment`) on Windows PowerShell 5.1.
   The early-exit added in r26 means Step A (registry), Step B
   (filesystem tests), and Phases 2–8 do not run. Expected: exit 0.
6. `[Summary]` + `[Artifacts]` as in STAGE 1.

**Timeout**: 120 minutes (T2-extended, see repository-root `/SPEC.md` §4).
**Expected output**: 0 PSScriptAnalyzer findings; smoke step exits 0.

### 7.3 STAGE 3 — Windows release verification

**File**: `scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml`
**Runner**: `windows-latest`
**Triggers**: `release/published`, plus manual `workflow_dispatch`
(with an optional free-text `reason` input).

**Steps**:

1. Checkout.
2. `[Release-verify] Full DryRun execution` — runs
   `.\Download-SpeakerDeck.ps1 -DryRun` on Windows PowerShell 5.1.
   This exercises Phase 1–5 end to end (including Speaker Deck network
   access) but writes no files because `-DryRun` marks Phases 6 and 7
   as SKIPPED.
3. `[Summary]` + `[Artifacts]`. Artifacts cover any `*.log` and
   `work/logs/**` produced by the dry run, with 30-day retention.

**Timeout**: 240 minutes (T3, repository-root `/SPEC.md` §4.3).
This is the policy maximum and is appropriate here because the wall
clock is dominated by Speaker Deck network round-trips with
configured delay/jitter, which can vary widely.

### 7.4 The `-EnvironmentInfoOnly` switch

Added in r26 specifically to give STAGE 2 a fast, side-effect-free
smoke test. Behaviour:

- When specified, `Test-Environment` calls `Show-PowerShellEnvironment`
  to print the runtime environment summary (Phase 1 Step 0), then
  exits with status 0.
- Skips Step A (registry check for `LongPathsEnabled`), Step B
  (filesystem long-path tests), and Phases 2 through 8.
- Mutually exclusive with `-SkipEnvCheck`; the validation block
  rejects the combination at startup with a clear error message.
- Safe to combine with `-DryRun` (both are side-effect-free).
- See [`SPEC.md`](./SPEC.md) §A.7 for the parameter contract.

### 7.5 Reading workflow output

Three surfaces show CI results:

1. **Status badges** in [`README.md`](./README.md) — at-a-glance pass/fail.
2. **GitHub Actions tab** — full per-step logs, Step Summaries (the
   compact Markdown rendered above the raw log), and downloadable
   artifacts (`*.log`, `*.sarif`).
3. **GitHub Code Scanning tab** — every `*.sarif` uploaded via
   `github/codeql-action/upload-sarif@v3` (psa.py, PSSA-pwsh7,
   PSSA-pwsh51) lands in the Security → Code Scanning surface,
   complete with inline PR annotations when findings exist.

### 7.6 What CI does NOT cover

A Windows-side functional CI job is **not** part of the chain because:

- Phase 6 (Download) consumes ~5 GB of bandwidth per run.
- Speaker Deck's rate-limit policy would penalize repeated CI runs.
- The functional verification is intentionally a human-operated
  procedure with the operator reviewing the output. STAGE 3 covers
  the closest CI-friendly approximation (full `-DryRun`).

For local verification, the recommended cadence is:

1. **Every commit** — `psa.py` + `Invoke-ScriptAnalyzer` (settings
   `./PSScriptAnalyzerSettings.psd1`) on the developer workstation.
2. **Every PR** — `-DryRun` on the operator's workstation (~9 minutes).
3. **Before tagging a release** — full real run on a clean environment
   (`-Clean`) and capture the Phase Timing Summary into this file (§3).

---

## 8. Debug Trace Facility verification (r23+)

This section describes the recommended verification procedure for the
Debug Trace Facility introduced in r23 (see [SPEC.md A.14](./SPEC.md#a14-debug-trace-facility)
for the authoritative specification).

The DebugTrace facility is **best-effort by design**: a failure to
activate it must not break the script. The verification checks below
distinguish (a) "the facility works as designed" from (b) "the script
keeps running even when the facility is degraded".

### 8.1 Smoke test — happy path

After any real run (e.g. the `-DryRun` cadence in §2 or the full run
in §3), confirm:

```powershell
# 1. The JSONL file exists.
Test-Path .\work\logs\debugtrace.jsonl
# Expected: True

# 2. The first event is 'file.open'.
Get-Content .\work\logs\debugtrace.jsonl -First 1 | ConvertFrom-Json |
    Select-Object kind, scriptVer
# Expected: kind=file.open, scriptVer=speakerdeck-2026.05.18-r25 (or later)

# 3. Stack balance: open count == close count.
$events = Get-Content .\work\logs\debugtrace.jsonl |
    ForEach-Object { $_ | ConvertFrom-Json }
$open  = ($events | Where-Object { $_.kind -eq 'frame.open'  }).Count
$close = ($events | Where-Object { $_.kind -eq 'frame.close' }).Count
"Open: $open / Close: $close (delta=$($open - $close))"
# Expected: delta=0 (perfect balance) for a successful run

# 4. Every phase produced at least one frame.
$events | Where-Object { $_.kind -eq 'frame.open' -and $_.phase } |
    Group-Object phase | Sort-Object Name | Select-Object Name, Count
# Expected: one entry for each of P01..P08 (P09 is a banner, not a
# traced phase). The counts depend on whether DryRun / -SkipEnvCheck
# are in effect.
```

### 8.2 Auto-export verification — failure path

To verify the auto-export-on-failure path WITHOUT inducing a real
failure on the production target:

```powershell
# Run with an intentionally invalid account name to force a Phase 2
# failure (Speaker Deck returns 0 decks).
.\Download-SpeakerDeck.ps1 -Account 'this-account-does-not-exist-xyz' -DryRun
```

Expected outcome:

1. The console shows a `[X]` failure marker inside Phase 2.
2. The top-level catch handler emits the
   `<context>: FAILED at step '...'` block.
3. A new JSON file appears under `.\work\diag\` named
   `debugtrace_export_P02_<timestamp>.json`.
4. The JSON file is valid and contains a `phases[]` array with an
   entry whose `outcome` field is `failure`.

```powershell
$snap = Get-Content .\work\diag\debugtrace_export_P02_*.json -Raw |
    ConvertFrom-Json
$snap.phases | Where-Object outcome -eq 'failure'
# Expected: phaseId=P02 (or whichever phase failed first)
```

### 8.3 Stack-balance check (always required for releases)

Before tagging any release, run the smoke test in §8.1 against a real
run and confirm `delta=0`. A nonzero delta indicates either:

- An early-return branch leaks a frame (matches the pitfall in
  SPEC.md A.14.8 point 2), OR
- A `finally` block was skipped due to a process crash (host
  termination, not a normal exception).

Both cases warrant investigation before the release.

### 8.4 Coexistence check (A.8 / A.14)

After a run where at least one Phase 6 download failed (induce with a
network outage, or use a known-stale account), confirm:

```powershell
# A.8 produced its per-deck records
Test-Path .\work\logs\P06_errors.jsonl       # Expected: True
Test-Path .\work\diag\failed                 # Expected: True (folder)

# A.14 produced its operation-level stream
Test-Path .\work\logs\debugtrace.jsonl       # Expected: True

# No auto-export should appear unless the OUTER phase function itself
# threw. Per-deck worker failures alone do NOT trigger auto-export.
Get-ChildItem .\work\diag\debugtrace_export_*.json -ErrorAction SilentlyContinue
# Expected: nothing, unless a phase-level exception escaped
```

This confirms the two facilities are functioning independently without
overlap, which is the design contract documented in SPEC.md A.8 and
A.14.6.

---

## License

This document is part of the `usui-tk/ai-generated-artifacts` repository,
licensed under the [MIT License](../../../LICENSE).
