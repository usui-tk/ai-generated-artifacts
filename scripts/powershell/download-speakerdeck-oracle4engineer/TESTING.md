# TESTING.md — Verification Procedure and Real-Run Results

This document consolidates everything needed to verify and evaluate
`Download-SpeakerDeck.ps1`. It covers three areas:

1. **Static analysis** — `scripts/python/powershell-static-analyzer/psa.py` gate (must pass before every commit)
2. **Functional verification — DryRun** — Phase 1–5 dry execution against the
   live Speaker Deck site (read-only)
3. **Functional verification — Real run** — full Phase 1–9 download against
   the `oracle4engineer` account, including the historical r16 → r17 regression
   fix evidence

🇯🇵 **Japanese version: see [TESTING.ja.md](./TESTING.ja.md).**

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

---

## 0. Verification status summary

| Item | Status | Last verified |
|---|---|---|
| `psa.py` v3.1.0 on `Download-SpeakerDeck.ps1` (with project `.psa.config.json`) | **0 errors / 0 warnings / 0 info** ✓ | psa-baseline-sync |
| `psa.py` v3.1.0 on `Test-PdfMetadata.ps1` (with project `.psa.config.json`)     | **0 errors / 0 warnings / 0 info** ✓ | psa-baseline-sync |
| File encoding (UTF-8 BOM, ASCII-only outside BOM) | ✓ both `.ps1` files | r20 build |
| Phase 1 (EnvCheck) — Windows 11 / PS 5.1.26100.8328 | ✓ pass | 2026-05-11 |
| Phase 2–5 (Scan / Plan) — DryRun mode | ✓ 804 decks evaluated | 2026-05-11 |
| Phase 6 (Download) — real run | ✓ **804/804 success** (zero failures) | 2026-05-11 (r17) |
| Phase 7 (Reconciliation) — zero anomalies | ✓ all Discrepancy flags = 0 | 2026-05-11 (r17) |
| Phase 8 (UndatedReclassify) — steady state on re-run | ✓ examined: 0 | 2026-05-11 (r17) |
| Phase 9 (FinalReport) — output validated | ✓ year distribution + log files listed | 2026-05-11 (r17) |
| Total elapsed (real run, ~5.7 GB, 804 files) | 10 min 4 s | 2026-05-11 (r17) |

---

## 1. Static analysis gate

`psa.py` v3.1.0 (28-rule check set `PSA1001`..`PSA7001`) must pass before
every commit (see Part C of [SPEC.md](./SPEC.md)).

`psa.py` auto-discovers `.psa.config.json` in the current working directory,
so the canonical invocation is from this script directory:

```bash
cd scripts/powershell/download-speakerdeck-oracle4engineer
python3 ../../python/powershell-static-analyzer/psa.py Download-SpeakerDeck.ps1
python3 ../../python/powershell-static-analyzer/psa.py Test-PdfMetadata.ps1
```

The local `.psa.config.json` disables `PSA6003` (plural function noun) for
this directory only. Rationale: three functions in `Download-SpeakerDeck.ps1`
(`Resolve-RuntimeDirectories`, `Invoke-CleanupDirectories`,
`Read-YearOverrides`) intentionally use plural nouns because they operate on
collections of resources. The exemption is documented inline in the config
file. New code should still prefer singular nouns.

Expected output (both scripts):

```
==== psa.py: PowerShell Static Analyzer ====
File   : Download-SpeakerDeck.ps1
Lines  : 4107
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

Any deviation from `0 / 0 / 0` blocks the commit. See
[`../../python/powershell-static-analyzer/SPEC.md`](../../python/powershell-static-analyzer/SPEC.md)
§4 for the full specification of the 28 rules
(`PSA1xxx` syntax / `PSA2xxx` semantics / `PSA3xxx` style / `PSA4xxx`
hygiene / `PSA5xxx` security / `PSA6xxx` best practice / `PSA7xxx`
file format).

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
  vspeakerdeck-2026.05.13-r20/<hash>
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
| r20 | SPEC file naming inconsistent with upstream | Cosmetic | Rename `spec.en.md` -> `SPEC.md` and `spec.ja.md` -> `SPEC.ja.md`, refresh A.1.x structure, sync psa.py with upstream, add TESTING.md (psa.py later promoted to `scripts/python/powershell-static-analyzer/` as the repository-wide canonical location) |

See [SPEC.md](./SPEC.md) Part D for the formalized "Known Pitfalls" entries
that bake each of these fixes into the project's institutional memory.

---

## 7. Outlook on CI/CD automation

GitHub Actions workflow (Linux runner — Python only, no PowerShell required):

```yaml
name: Static analysis
on: [push, pull_request]

jobs:
  psa:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - name: Static-analyze main script
        run: |
          cd scripts/powershell/download-speakerdeck-oracle4engineer
          python3 ../../python/powershell-static-analyzer/psa.py Download-SpeakerDeck.ps1
      - name: Static-analyze PoC script
        run: |
          cd scripts/powershell/download-speakerdeck-oracle4engineer
          python3 ../../python/powershell-static-analyzer/psa.py Test-PdfMetadata.ps1
```

A Windows-side functional CI job is **not** currently planned because:

- Phase 6 (Download) consumes ~5 GB of bandwidth per run
- Speaker Deck rate limits would penalize repeated CI runs
- The functional verification is intentionally a human-operated procedure
  with the operator reviewing the output

For local verification, the recommended cadence is:

1. **Every commit** — `psa.py` (above)
2. **Every PR** — `-DryRun` on the operator's workstation (~9 minutes)
3. **Before tagging a release** — full real run on a clean environment
   (`-Clean`) and capture the Phase Timing Summary into TESTING.md (this file)

---

## License

This document is part of the `usui-tk/ai-generated-artifacts` repository,
licensed under the [MIT License](../../../LICENSE).
