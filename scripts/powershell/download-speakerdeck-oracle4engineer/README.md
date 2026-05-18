# Download-SpeakerDeck.ps1

**English** | [日本語](README.ja.md)

Bulk-download every public deck from a specified Speaker Deck account.
Targeted at Windows 11 + Windows PowerShell 5.1 (also runs on PowerShell 7+).

This script is part of the
[`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
repository, under `scripts/powershell/download-speakerdeck-oracle4engineer/`.

## ⚠️ Disclaimer

**USE AT YOUR OWN RISK.** This script is provided "AS IS" without warranty
of any kind, express or implied. The authors and contributors are not
liable for any damages, data loss, account suspension, network issues,
disk space exhaustion, or any other problems — direct or indirect — that
may arise from using, modifying, or distributing this script.

By running this script, you acknowledge that:

* You are solely responsible for verifying that your use complies with
  Speaker Deck's Terms of Service and any applicable laws or regulations
* You are responsible for any consequences of downloading large numbers
  of files (bandwidth costs, storage costs, rate-limiting, IP blocks)
* You should respect the original authors' rights — downloaded materials
  remain the intellectual property of their respective owners
* You will review the script's source code and understand its behavior
  before running it in any environment

Operate this tool considerately. Respect rate limits (the script has
built-in throttling, but do not bypass it). Avoid downloading content
faster or more often than necessary.

For the full disclaimer and self-responsibility terms that apply to all
artifacts in this repository, see the
[root README](../../../README.md)
([Japanese](../../../README.ja.md)).

## License

This project is part of the `usui-tk/ai-generated-artifacts` repository,
which is licensed under the **MIT License**. See the
[`LICENSE`](../../../LICENSE) file at the repository root for the full
license text.

In short: you are free to use, modify, and distribute this software for
any purpose, provided that the original copyright and license notices
are preserved. The software is provided without warranty, as detailed in
the Disclaimer above and in the LICENSE file.

## Folder layout

```
scripts/powershell/download-speakerdeck-oracle4engineer/
  Download-SpeakerDeck.ps1     # Main script (this README documents it)
  README.md / README.ja.md     # End-user documentation (you are reading these)
  SPEC.md (English only)         # Developer / LLM specification (see "Developer specification" below)
  TESTING.md (English only)   # Verification procedure and real-run results
```

The PowerShell static analyzer (`psa.py`) used to verify this script lives at
the repository-wide canonical location:
[`scripts/python/powershell-static-analyzer/`](../../python/powershell-static-analyzer/).

If you only want to **run** the script, read this README. If you want to
**extend it or build a similar script**, also read `SPEC.md`.

## Quick start

```powershell
# 1. Unblock the file (removes the "downloaded from the internet" warning)
Unblock-File .\Download-SpeakerDeck.ps1

# 2. Allow signed-or-local scripts for the current process
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. Dry run (evaluation only, no downloads)
.\Download-SpeakerDeck.ps1 -DryRun

# 4. Real run with default settings (account: oracle4engineer)
.\Download-SpeakerDeck.ps1
```

## Parameters

| Parameter            | Default          | Description                                                       |
| -------------------- | ---------------- | ----------------------------------------------------------------- |
| `-Account`           | `oracle4engineer`| Speaker Deck account name                                         |
| `-OutputDir`         | `.\downloads`    | Output directory for downloaded decks (resolved against script dir) |
| `-WorkDir`           | `.\work`         | Working directory for diagnostic dumps (resolved against script dir)|
| `-DelaySeconds`      | `1.0`            | Base wait time between requests (seconds)                         |
| `-JitterSeconds`     | `0.3`            | Random jitter range added/subtracted from `DelaySeconds`          |
| `-MaxConcurrency`    | `5`              | Hard cap for parallel downloads                                   |
| `-InitialConcurrency`| `3`              | Initial parallel download count                                   |
| `-MinConcurrency`    | `1`              | Floor for parallel downloads (used during throttling)             |
| `-MaxRetries`        | `3`              | Max retries per download                                          |
| `-Force`             | (off)            | Overwrite existing files (otherwise files > 1 KB are skipped)     |
| `-DryRun`            | (off)            | Run Phase 1-5 fully; Phase 6/7/8 are explicitly marked SKIPPED; Phase 9 still reports |
| `-SkipEnvCheck`      | (off)            | Skip Phase 1 and use safe-default thresholds                      |
| `-Clean`             | (off)            | Delete OutputDir + WorkDir before running (full fresh restart)    |
| `-CleanOnly`         | (off)            | Same wipe as `-Clean`, then exit without running phases           |
| `-FlatLayout`             | (off)            | Save all files into OutputDir as a flat layout (no year subfolders) |
| `-SkipPdfReclassification`| (off)            | Skip Phase 8 (PDF-metadata-based rescue of _undated files)         |

## Year-folder organization (default)

By default the script organizes downloads by publication year:

```
downloads/
  2026/
    [Oracle TechNight#99] ...__file.pdf
  2025/
    ...
  2024/
    ...
  _undated/
    (files for which no year could be determined)
```

The year is derived in this priority order:

1. `YYYYMMDD` (or `YYYY-MM-DD`, `YYYY_MM_DD`) pattern in the **OriginalFilename**
   (deck author's intent - usually the content creation date)
2. `PublishDate` from og:meta on the Speaker Deck page (the upload date)
3. Japanese year-suffix pattern in Title (`YYYY` + kanji at U+5E74)
4. Bare 4-digit year `20YY` anywhere in Title
5. Fallback: `_undated/`

A year is accepted only when it falls within `[2010, currentYear + 1]`.

The intent is to help users **spot stale content quickly** as cloud services
evolve - a 2018 deck is likely outdated even if the title hasn't changed.

Use `-FlatLayout` to disable this and keep the legacy single-folder layout.

## Path resolution

`-OutputDir` and `-WorkDir` are resolved against **the directory containing the
.ps1 file** (`$PSScriptRoot`), NOT against the caller's current working directory.

This means:

* Running `.\Download-SpeakerDeck.ps1` from any folder always writes to the
  same place (next to the script).
* Both the download tree and the working tree live under one root, making the
  script's footprint easy to clean up.

If the script lives at `C:\Temp\download-speakerdeck-oracle4engineer\Download-SpeakerDeck.ps1`, the defaults produce:

```
C:\Temp\download-speakerdeck-oracle4engineer\
  +-- Download-SpeakerDeck.ps1
  +-- downloads\          <- -OutputDir default (content only - PDFs)
  |   +-- <title>__<filename>.<ext>
  +-- work\               <- -WorkDir default (script-managed files)
      +-- diag\
      |   +-- speakerdeck_diag_*.html       <- Phase 2 HTML dumps (only on parse failure)
      |   +-- failed\
      |       +-- 0042_<slug>.txt           <- Per-failure diagnostic (only on Phase 6 failures)
      +-- logs\
          +-- P04_evaluation_log.csv        <- Phase 4 results (DryRun only)
          +-- P05_filename_plan.csv         <- Phase 5 results (always)
          +-- P06_download_log.csv          <- Phase 6 results (real run only)
          +-- P06_errors.jsonl              <- Phase 6 failures (JSONL, only on failure)
          +-- P07_final_state.csv           <- Phase 7 reconciliation (real run only)
```

The `P##_` prefix on every log file makes sorting alphabetical = sorting
by phase, so the data flow through the pipeline is visible at a glance.

Pass an absolute path to either parameter to opt out of the script-relative
behavior:

```powershell
.\Download-SpeakerDeck.ps1 -OutputDir "D:\SpeakerDeck\decks" -WorkDir "D:\SpeakerDeck\work"
```

## Phase structure

```
Phase 1 : Environment evaluation        (Setup)
          - Step 0: PowerShell execution environment dump (PS version,
                    edition, CLR, bitness, OS, exec policy, encoding,
                    TLS, culture, script path) + compatibility check
                    summary
          - Step A: registry check (LongPathsEnabled)
          - Step B: real-world dummy file creation tests
          - Step C: classify environment into 4 tiers and decide thresholds
Phase 2 : Get total deck count          (Scan)
Phase 3 : Listing collection            (Scan)  sequential, all pages
Phase 4 : Per-deck evaluation           (Scan)  light parallel, decides downloadability
Phase 5 : Filename plan                 (Plan)
          - pre-compute output filename + full path for every item
          - detect OutputFullPath duplicates and MAX_PATH violations
          - save P05_filename_plan.csv
Phase 6 : Adaptive parallel download    (Fetch) -- skipped on -DryRun
          - Runspace Pool, initial 3 / max 5
          - Auto-throttle on HTTP 429 (concurrency halved + 60 sec sleep)
          - Step down on HTTP 5xx
          - Emergency brake after 3 consecutive failures (force min + 90 sec)
          - Ramp up by +1 after 10 consecutive successes
Phase 7 : Reconciliation                (Verify) -- skipped on -DryRun
          - join plan + download log + disk inventory
          - per-deck Discrepancy flag (OK / SizeMismatch / MissingAfterSuccess
            / WrongYearFolder / ...)
          - extra "(extra)" rows for files in downloads/ not in plan
          - save P07_final_state.csv
Phase 8 : PDF-metadata reclassification (Verify) -- skipped on -DryRun
          - for each successfully-downloaded file in _undated/, read
            PDF metadata via pure-PowerShell regex
          - if a valid year (2010..currentYear+1) is found in
            /CreationDate, xmp:CreateDate, etc., move the file
            from _undated/<file>.pdf to <year>/<file>.pdf
          - append to work/logs/year_overrides.csv so the NEXT run's
            Phase 5 routes the deck directly to the resolved folder
            (idempotent: re-runs find nothing to do)
          - opt out with -SkipPdfReclassification
          - also skipped automatically when -FlatLayout is set
Phase 9 : Final summary report          (Report)
          - download stats + failure breakdown + year distribution
          - PDF-metadata reclassification stats (Phase 8)
```

## PDF-metadata reclassification (Phase 8)

When a deck's title, original filename, and og:meta all fail to yield
a publication year, Phase 5 routes it to `_undated/`. Phase 8 makes a
second attempt by reading the actual PDF's internal metadata. This
typically rescues decks where:

* Speaker Deck's og:meta has been stripped or never set
* The author's filename has no embedded date
* The title is a slug rather than a real title

Year derivation priority inside the PDF (in order):

1. **PDF Info Dictionary** `/CreationDate (D:YYYYMMDD...)` -> `PdfInfoDict`
2. **XMP** `<xmp:CreateDate>YYYY-...</...>` -> `PdfXmp`
3. **XMP legacy ns** `<xap:CreateDate>` -> `PdfXmpLegacy`
4. **XMP pdf ns** `<pdf:CreationDate>` -> `PdfXmpPdfNs`
5. **Fallback dates** `/ModDate` or `<xmp:ModifyDate>` (only if no CreationDate)

The same `[2010, currentYear + 1]` validity range applies.

### Idempotency across runs (year_overrides.csv)

Each successful rescue is appended to `work/logs/year_overrides.csv`
with these columns:

```
DeckUrl, OriginalFilename, PlanYearFolder, ResolvedYearFolder,
ResolvedDate, YearSource, DetectedAt
```

On the **next** run, Phase 5's `Get-DeckYear` consults this CSV at
**priority 0** (before every other heuristic). This means:

* Decks rescued in a previous run go directly to the correct year
  folder this time
* Phase 6 finds the file already in place and skips re-downloading
* Phase 7 sees no discrepancy (no false `WrongYearFolder` warnings)
* Phase 8 finds nothing to rescue (`Examined: 0`)

To re-trigger rescue from scratch, delete `year_overrides.csv` or
use `-Clean`.

## PowerShell environment requirement

The script targets **Windows PowerShell 5.1** as the minimum (the
default shell that ships with Windows 10, Windows 11, and Windows
Server 2016 / 2019 / 2022 / 2025). PowerShell 7+ is also supported but
not required.

Hard requirements (checked at startup; script refuses to run otherwise):

* PowerShell version >= 5.1
* 64-bit PowerShell process (the `(x86)` host is rejected)

Soft warnings (logged but not blocking):

* OS build number not in the known list (newer builds work; older ones
  may need WMF 5.1)

Full environment diagnostic appears in Phase 1 Step 0 - share that
block when reporting issues so the exact host configuration is
reproducible.

## Output filename convention

* **Full form**  : `<title>__<original_filename>`
* **Short form** : `<title>_<YYYYMMDD>.<ext>` (used when system limits are tight)
* **Truncated**  : Title is truncated to fit the effective filename / full path limit

Windows-forbidden characters are replaced with ASCII-safe substitutes:

| Forbidden | Replacement |
| --------- | ----------- |
| `<`       | `(`         |
| `>`       | `)`         |
| `:`       | `-`         |
| `"`       | `'`         |
| `/` `\` `|` | `_`       |
| `?` `*`   | (removed)   |

## Output files

The `downloads\` tree is content-only (PDFs from Speaker Deck). Everything
script-managed (logs, diagnostic dumps) lives under `work\`. Every CSV /
JSONL log file is prefixed with its emitting phase ID (`P03_`, `P04_`,
etc.) so that alphabetical sorting matches pipeline execution order.

* `<OutputDir>\<title>__<filename>.<ext>`               - downloaded decks (content only)
* `<WorkDir>\logs\P04_evaluation_log.csv`               - Phase 4 per-deck downloadability (DryRun only)
* `<WorkDir>\logs\P05_filename_plan.csv`                - Phase 5 pre-computed filename plan (always)
* `<WorkDir>\logs\P06_download_log.csv`                 - Phase 6 per-deck CSV summary (real-run only)
* `<WorkDir>\logs\P06_errors.jsonl`                     - Phase 6 structured (JSONL) failure log, one line per failed download
* `<WorkDir>\logs\P07_final_state.csv`                  - Phase 7 reconciliation: plan vs download log vs disk inventory, with Discrepancy flag per row (real-run only)
* `<WorkDir>\logs\year_overrides.csv`                   - Phase 8 PDF-metadata rescue history; consulted at priority 0 by next run's Phase 5 (created lazily on first successful rescue)
* `<WorkDir>\logs\debugtrace.jsonl`                     - **Debug Trace Facility**: real-time JSONL stream of frame.open / step / frame.close events (always; see "Debug tracing" section below)
* `<WorkDir>\diag\speakerdeck_diag_<account>_*.html`    - raw HTML dump when Phase 2 detects 0 decks
* `<WorkDir>\diag\failed\<index>_<slug>.txt`            - detailed per-failure diagnostic dump (HTTP status, headers, body preview, stack trace, attempt history)
* `<WorkDir>\diag\debugtrace_export_<phaseId>_<ts>.json` - **Debug Trace Facility**: auto-exported JSON snapshot when a phase throws (only when an unhandled exception escapes; see "Debug tracing" section below)

### CSV column conventions

The four CSV logs (`P04_*`, `P05_*`, `P06_*`, `P07_*`) share a common
naming convention so they can be joined or grep'd across stages. The
following columns have identical names everywhere they appear:

| Column | Meaning | Appears in |
|---|---|---|
| `Index` | 1-based deck position in the scan order | P04, P05, P06, P07 |
| `Title` | og:title of the deck | P04, P05, P06, P07 |
| `DeckUrl` | Speaker Deck deck page URL | P04, P05, P06, P07 |
| `DownloadUrl` | the actual PDF download URL | P04, P05, P06, P07 |
| `OriginalFilename` | filename uploaded by the author (before sanitization) | P04, P05, P06, P07 |
| `PublishDate` | YYYYMMDD from og:meta (Phase 4) | P04, P05, P06, P07 |
| `YearFolder` | year subfolder (`2024`, `2025`, ... or `_undated`) | P04, P05, P06 (P07 splits this into `PlanYearFolder` / `DiskYearFolder`) |
| `YearSource` | which rule derived YearFolder (`OverrideCsv` / `OriginalFilename` / `PublishDate` / `TitleJp` / `TitleNum` / `Fallback` / `PdfInfoDict` / `PdfXmp` ...) | P04, P05, P06 |
| `OutputFilename` | the sanitized filename actually used on disk | P05, P06, P07 |

Each later-stage CSV is a superset of the earlier-stage data plus
stage-specific columns (e.g., P06 adds `Status` / `Bytes` /
`DurationMs` / `Attempts`; P07 adds the reconciliation columns
`Discrepancy` / `PlanYearFolder` / `DiskYearFolder` / `FileExists` /
`SizeMatch`).

The `year_overrides.csv` file (created by Phase 8) is a separate state
file rather than a per-phase log; its columns are documented in the
"PDF-metadata reclassification (Phase 8)" section.

## Troubleshooting

### "セキュリティ警告" / Security warning

```powershell
Unblock-File .\Download-SpeakerDeck.ps1
```

### "このシステムではスクリプトの実行が無効になっている" / Execution policy error

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Many decks land in "Not downloadable"

These are decks where the publisher has disabled downloads. The script
honors this and skips them.

### Repeated HTTP 429 / 503

Automatic throttling kicks in. If errors persist, lower concurrency manually:

```powershell
.\Download-SpeakerDeck.ps1 -MaxConcurrency 2 -InitialConcurrency 1 -DelaySeconds 2.0
```

### Phase 2 returns 0 decks

Speaker Deck's HTML structure may have changed. When page 1 returns 0 decks, the
script automatically dumps the raw HTML to:

```
<WorkDir>\diag\speakerdeck_diag_<account>_<timestamp>.html
```

(Default: `<script_dir>\work\diag\`)

Inspect that file to see the current HTML structure, then adjust the regex
patterns in the `Get-AllDeckList` function accordingly.

The diagnostic output also reports:

* HTML size in characters
* Number of references to the account name in the HTML
* Number of `/<account>/<slug>` candidate paths
* Total `<a` and `title=` attribute counts

If `/<account>/<slug>` count is `0`, the server returned a stripped-down HTML -
likely a User-Agent / bot-detection issue. The script already sends Chrome-like
headers (Accept, Accept-Language, Sec-Fetch-*, Sec-Ch-Ua, etc.) to mitigate
this; if you still hit the issue, inspect the saved HTML in a browser to
compare with what a real Chrome would receive.

### Phase 6 (downloads) had failures

Open the failure breakdown table printed at the end of the run:

```
  Failure breakdown:
    HTTP 503 (Service Unavailable)         :  41
    HTTP 429 (Too Many Requests)           :  18
    Timeout                                :   9
    PathTooLong                            :   5
    Other                                  :   3

  Detailed errors saved to:
    C:\Temp\download-speakerdeck-oracle4engineer\work\logs\P06_errors.jsonl
    C:\Temp\download-speakerdeck-oracle4engineer\work\diag\failed\
```

Two artifacts give you the detail you need to investigate:

1. **`work\logs\P06_errors.jsonl`** - one JSON object per line, machine-readable.
   Parse with `jq`, `ConvertFrom-Json`, or any JSONL tool:

   ```powershell
   Get-Content .\work\logs\P06_errors.jsonl | ForEach-Object {
       $_ | ConvertFrom-Json
   } | Group-Object category | Sort-Object Count -Descending
   ```

2. **`work\diag\failed\<index>_<slug>.txt`** - human-readable per-failure
   dump including HTTP status, response headers, the first ~2KB of the
   response body (if any), the full attempt history, and the script
   stack trace at the time of failure.

For full post-run analysis, also inspect **`work\logs\P07_final_state.csv`**,
which joins the plan + download log + disk inventory and flags any
discrepancies (size mismatch, missing-after-success, partial downloads, etc.).

Common categories and remedies:

| Category                  | Likely cause                  | Remedy                                                                                     |
| ------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------ |
| HTTP 429                  | Speaker Deck rate-limit hit   | Re-run with lower concurrency: `-MaxConcurrency 2 -InitialConcurrency 1 -DelaySeconds 2.0` |
| HTTP 503 / 502 / 504      | Transient server / CDN error  | Re-run; the adaptive retry usually clears these on the second pass                         |
| Timeout                   | Slow connection, large PDF    | Re-run; consider `-MaxRetries 5`                                                           |
| PathTooLong               | NTFS path limit hit           | Move script to a shorter root path, or shorten `-OutputDir`                                |

### Starting completely fresh

```powershell
# Wipe everything and re-run from scratch
.\Download-SpeakerDeck.ps1 -Clean

# Wipe everything without running anything afterwards
.\Download-SpeakerDeck.ps1 -CleanOnly
```

Both switches delete `<OutputDir>` and `<WorkDir>` recursively. Safety
checks refuse to operate if either path equals the script's own
directory, equals a drive root, or contains the script.

## Debug tracing

The script ships with a **Debug Trace Facility** that records per-step
checkpoints inside every phase. Two products are emitted:

| Output | When | Purpose |
|---|---|---|
| `work\logs\debugtrace.jsonl` | Always (every real run) | Real-time JSONL stream of every phase entry, named step, and phase exit. Append-only, UTF-8 with BOM. |
| `work\diag\debugtrace_export_<phaseId>_<timestamp>.json` | Only when a phase throws | Auto-exported point-in-time snapshot. Self-contained: includes active stack, completed frames, per-phase outcomes, and host metadata. |

Activation is automatic at script startup right after the work
directory is created. You should see a one-line confirmation on stdout:

```
[*] Debug trace -> C:\Temp\download-speakerdeck-oracle4engineer\work\logs\debugtrace.jsonl
```

### When this helps

The per-deck Phase 6 failure log (`P06_errors.jsonl`) answers "which
deck failed". The Debug Trace Facility answers a different question:
"which named step inside this function was running when the exception
was raised". It is most useful for diagnosing failures that are NOT
per-deck — e.g. a `PathTooLongException` during filename planning, an
unexpected `System.IO.IOException` while writing a CSV, or a regex
parse failure in Phase 4 evaluation.

### Inspecting `debugtrace.jsonl`

Each line is a self-contained JSON object. Useful one-liners:

```powershell
# Count events by kind
Get-Content .\work\logs\debugtrace.jsonl |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Group-Object kind | Sort-Object Count -Descending

# Show every step that ran inside Phase 5
Get-Content .\work\logs\debugtrace.jsonl |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { $_.kind -eq 'step' -and $_.ctx -eq 'Invoke-Phase5FilenamePlan' } |
    Select-Object ts, step

# Show every failure event with stack
Get-Content .\work\logs\debugtrace.jsonl |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { $_.kind -eq 'failure' } |
    Format-List ts, ctx, step, exType, msg, stack
```

### Inspecting an auto-exported snapshot

When a phase throws, the script's top-level catch handler writes a
single self-contained JSON file under `work\diag\`. The file is named
`debugtrace_export_<phaseId>_<YYYYMMDD-HHmmss>.json` and contains:

| Key | Meaning |
|---|---|
| `script.version` / `script.tag` / `script.sha256` | Which build was running |
| `hostInfo` | PS version, edition, CLR, OS, culture, host name |
| `phases[]` | Per-phase outcome + failure ref if any |
| `activeFrames[]` | Functions still on the trace stack at the moment of failure |
| `completedFrames[]` | History of finished frames, with per-step timing |
| `events[]` | Empty by default; populated when `-IncludeEvents` is passed to `Export-DebugTraceJson` manually |

Attach this single file to a bug report and the maintainer has the full
context for the failure without needing the much larger
`debugtrace.jsonl`.

### Disabling the facility

The facility cannot be disabled from the command line because its
overhead is negligible (~150 KB of JSONL for an 800-deck run, no
network traffic). It is best-effort: if file activation fails (e.g.
disk full, permission denied), the script warns and continues without
the trace file. Trace events stay buffered in memory and remain
exportable via `Export-DebugTraceJson` from a debugger if needed.

For the full specification (event schemas, module-level state, public
API), see [SPEC.md A.14](SPEC.md#a14-debug-trace-facility).

---

## Developer specification

If you want to extend this script, change its phase structure, or build a
similar script in this repo's style, read **[SPEC.md](SPEC.md)** first.
That document captures:

- **Part A (Common Spec)** — conventions inherited by every script in this
  family: source file format (UTF-8 BOM + ASCII-only), phase architecture,
  log markers, `-LiteralPath` rules, CSV column conventions, environment
  diagnostic, static analysis gate, documentation language policy
- **Part B (Script-Specific Spec)** — this script's own phase map, year-folder
  rules, PDF-metadata reclassification details (Phase 8), adaptive download
  settings, failure recovery
- **Part C (Quality Gates)** — the checklist that must pass before every commit
- **Part D (Known Pitfalls)** — documented bugs and their fixes, such as the
  `[ ]` wildcard issue in PowerShell paths and phase-renumbering safety

For the per-release change history, see **[CHANGELOG.md](CHANGELOG.md)**
([Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) format;
English only per the repository-wide documentation language policy).

For the actual verification results (DryRun, real-run output, idempotency
check, regression-fix evidence), see **[TESTING.md](TESTING.md)**. It
documents the most recent successful real-run
(`804/804 decks, zero failures, 10m4.4s total, 5.7 GB`).

For details on the `psa.py` static analyzer (v3.3.0, with `PSA1001..PSA9002`
plus `PSAP0001..PSAP0004` opt-in rules), see
[`../../python/powershell-static-analyzer/README.md`](../../python/powershell-static-analyzer/README.md)
and the full [`SPEC.md`](../../python/powershell-static-analyzer/SPEC.md).

The **single most important rule** for new development: do not re-derive
phase headers, log markers, or psa.py — copy them from the existing
implementation. Reuse before invention.

---

## Developer notes: static analysis

This script is verified with `psa.py` (PowerShell Static Analyzer), which
lives at the repository-wide canonical location
[`scripts/python/powershell-static-analyzer/psa.py`](../../python/powershell-static-analyzer/psa.py).
It is a pure-Python tool with no external dependencies.

```bash
# Run static analysis (psa.py auto-discovers the local .psa.config.json)
cd scripts/powershell/download-speakerdeck-oracle4engineer
python3 ../../python/powershell-static-analyzer/psa.py Download-SpeakerDeck.ps1
```

### Rule coverage (psa.py v3.3.0 — 36 rules)

`psa.py` v3.3.0 groups its 36 rules into nine categories. Categories
`PSA1xxx`..`PSA7xxx` are generic and apply to any PowerShell script;
`PSA8xxx` (cross-file consistency) and `PSA9xxx` (complexity metrics)
were added in 3.2.0; `PSAPxxxx` (project / pipeline conventions) are
opt-in opinionated rules added across 3.2.0 (PSAP0001 / PSAP0002) and
3.3.0 (PSAP0003 / PSAP0004).

| Category | Code range | Examples |
| -------- | ---------- | -------- |
| Syntax balance      | `PSA1001`..`PSA1003` | brace / paren / bracket balance |
| Semantics           | `PSA2001`..`PSA2006` | undefined variable, auto-variable shadowing, `-match` against bare variable, `$null` on the right of `-eq`/`-ne` |
| Style               | `PSA3001`..`PSA3005` | `Start-Process -ArgumentList`, trailing backtick before empty line, empty `catch` block, `Start-Transcript -Path` should be `-LiteralPath` |
| Hygiene             | `PSA4001`..`PSA4004` | unfinished markers, trailing whitespace, long line, trailing semicolon |
| Security            | `PSA5001`..`PSA5004` | plain-text password parameter, `Invoke-Expression`, broken hash algorithm, hardcoded `ComputerName` |
| Best practice       | `PSA6001`..`PSA6006` | non-approved verb, cmdlet alias, plural function noun, `$global:` definition, mandatory parameter with default, switch defaulting to `$true` |
| File format         | `PSA7001`            | PowerShell script lacks UTF-8 BOM (Windows PowerShell 5.1 may misinterpret non-ASCII bytes as Shift-JIS without a BOM) |
| Cross-file consistency | `PSA8001`         | function-body hash drift across files in the same scan |
| Complexity metrics  | `PSA9001`..`PSA9002` | function body length threshold (opt-in), external process invocation without `$LASTEXITCODE` check (opt-in) |
| Project / pipeline conventions | `PSAP0001`..`PSAP0004` | phase function naming, required script-identifier variables, inline revision-tag comments (`PSAP0003`, new in 3.3.0), end-of-file `REVISION HISTORY` blocks (`PSAP0004`, new in 3.3.0). **All PSAPxxxx rules are off by default**; this project opts in to `PSAP0003` and `PSAP0004` |

For the full specification of each rule, see
[`../../python/powershell-static-analyzer/SPEC.md`](../../python/powershell-static-analyzer/SPEC.md) §4.

### Project-local configuration

This script directory ships a `.psa.config.json` that disables `PSA6003`
(plural function noun). Three intentional plural-noun functions in
`Download-SpeakerDeck.ps1` motivate this exemption; the rationale is
recorded inline in the config file. Empty `catch` blocks (`PSA3004`) that
are intentional carry `# psa-disable-line PSA3004 -- <reason>` directives.

### Current verification result

```
==== psa.py: PowerShell Static Analyzer ====
File   : Download-SpeakerDeck.ps1
Lines  : 5152
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

Run the analyzer above before committing any change to the script.
This is also enforced as a quality gate in SPEC.md Part C.

## Console output format

Each log line is prefixed with the wall-clock time and the elapsed time
since the current phase started:

```
[HH:mm:ss] [+X.XXs]   [marker] message
```

Marker symbols:

| Marker | Meaning             | Color     |
| ------ | ------------------- | --------- |
| `[*]`  | step / in-progress  | cyan      |
| `[+]`  | success             | green     |
| `[!]`  | warning             | yellow    |
| `[X]`  | failure             | red       |
| `[~]`  | skipped             | dark gray |

Phase boundaries are marked with magenta banners:

```
========================================================================
 PHASE P03  - ListCollection         (Scan   ) start: 13:04:15
 script: vspeakerdeck-2026.05.18-r24/abc123def456
========================================================================
[13:04:15] [+0.00s]      [*] Fetching page 1: https://speakerdeck.com/...
[13:04:16] [+0.85s]      [*] page 1: +18 decks (cumulative 18)
...
 PHASE P03  -> DONE     elapsed: 1m12.3s
```

A timing summary is printed at the end of every run:

```
========================================================================
 Phase Timing Summary
========================================================================
  P01   DONE     elapsed: 0.55s
  P02   DONE     elapsed: 0.42s
  P03   DONE     elapsed: 1m12.3s
  P04   DONE     elapsed: 4m18.0s
  P05   DONE     elapsed: 0.05s
  P06   DONE     elapsed: 6m02.5s
  P07   DONE     elapsed: 1.20s
  P08   SKIPPED  elapsed: 0.00s
  P09   DONE     elapsed: 0.08s
  ----------------------------------------
  Total elapsed: 11m33.8s
========================================================================
```

## File encoding

* The script is saved as **UTF-8 with BOM** so that Windows PowerShell 5.1
  unambiguously identifies the file as UTF-8 (without the BOM, it falls
  back to the system code page, which on Japanese Windows is Shift-JIS / cp932).
* All console messages and comments are in English to avoid encoding
  issues across diverse environments.
