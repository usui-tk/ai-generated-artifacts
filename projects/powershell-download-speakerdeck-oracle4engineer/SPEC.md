---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-08
---
# PowerShell Script Specification (SPEC) - Download-SpeakerDeck.ps1

> This SPEC documents `Download-SpeakerDeck.ps1`. **Part A** is the repository-wide
> common specification, vendored (L2 -> L3) from the canonical spec home
> [`governance/spec/powershell.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/governance/spec/powershell.md) as gate-managed
> marker+hash regions; **Parts B-D** are specific to this script. The A.14 cross-script
> feature slot holds this script's Debug Trace Facility (project-specific, not vendored).
> History lives in `CHANGELOG.md`; current and forward design lives here. This SPEC is
> reconstructed from the repository template canon and inherits the repository governance
> model rather than asserting its own; see
> [`AGENTS.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md) and the repository root `README.md`.

> **Documentation language policy**: This SPEC is maintained in English only. Japanese
> readers should refer to the English SPEC together with `README.ja.md`. See the repository
> root `README.md` "Language Policy" section for the repository-wide policy.

## Table of Contents

- Part A - Common Specification (vendored by marker+hash from the spec home)
- Part B - Script-Specific Specification
- Part C - Quality Gates & Validation Checklist
- Part D - Known Pitfalls & Lessons Learned

# Part A - Common Specification (inherited; vendored from the spec home)

> **Status: inherited - vendored from the spec home.** Per the
> [`AGENTS.md` Section 6 Part A Inheritance Rule (ABSOLUTE)](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md), the 14
> canonical Part A regions below are vendored from
> [`governance/spec/powershell.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/governance/spec/powershell.md) as marker+hash
> regions and are verified against the spec home by the document-conformance gate /
> drift scanner; they are never hand-edited. The A.14 slot below is this consumer's
> project-specific cross-script feature (not vendored).

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.reference-assets version=1.0.0 hash=d1f03d5c548d4f3f policy=canonical binding=follow-latest >>> -->
### A.1 Reference assets

Every PowerShell script in the canon draws on a shared set of reference assets: (1) the
static-analysis configuration and gate (see A.11); (2) the companion specification documents
that make up the doc-set (README + README.ja, SPEC, and where applicable TESTING and
CHANGELOG); (3) the in-house canonical reference script `{{REFERENCE_SCRIPT}}`, the worked
example of these conventions; and (4) the shared helper units vendored from the code canon
(`reference-code/powershell/`). The specific reference script and helper set a consumer uses
are recorded in that consumer's own SPEC; this region only fixes that the assets exist and
where their conventions are defined.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.reference-assets <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.source-file-format version=1.0.0 hash=f7105ebfe3d202ff policy=canonical binding=follow-latest >>> -->
### A.2 Source file format

Script source files are encoded **UTF-8 with BOM** and use **CRLF** line endings. Non-ASCII
characters are confined to intentional data/string literals; identifiers, keywords, and code
are ASCII (the documentation-language policy is A.12). Encoding and line-ending conformance is
enforced by the static-analysis gate (A.11); files that are not BOM+CRLF, or that carry stray
non-ASCII outside sanctioned literals, fail the gate.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.source-file-format <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.banner-version version=1.0.0 hash=9821c85a0e065145 policy=canonical binding=follow-latest >>> -->
### A.3 Banner and version

Each script carries a single canonical **version string** and emits a **startup banner** that
prints the script identity, the version, and a **SHA256 self-fingerprint** of the running
file. The version string is the one source of truth for the script's revision and is the value
recorded in CHANGELOG. The banner format and the fingerprint computation are common; the
concrete version value is per-consumer.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.banner-version <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.phase-architecture version=1.0.0 hash=9af42a0010ff6f52 policy=canonical binding=follow-latest >>> -->
### A.4 Phase architecture

Scripts are organised into **numbered phases**. The numbering convention (monotonic integer
phases, optional phase *groups*, and a uniform per-phase header/footer log line carrying the
phase number, title, and elapsed tag) is common. The **phase count and the phase map**
(which work each phase does) are consumer-specific and are defined in the consumer's **Part
B**, not here.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.phase-architecture <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.logging version=1.0.0 hash=8e1353694d8216fa policy=canonical binding=follow-latest >>> -->
### A.5 Logging conventions

Logging goes through the shared logging helper family (vendored from the code canon). Messages
carry a **severity marker** from the canonical set (informational / detail / caution / error
and the phase markers); console output uses the canonical colour discipline for each severity;
network operations use TLS. Scripts do not write ad-hoc colour or bypass the helpers. The
helper set is fixed by the code canon; this region fixes the *conventions* for using it.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.logging <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.path-handling version=1.0.0 hash=1526d2dbb85bb58f policy=canonical binding=follow-latest >>> -->
### A.6 Path handling

Paths are handled defensively: prefer **`-LiteralPath`** over wildcard-expanding parameters;
never expand wildcards on externally supplied input; build paths with validated joins (not
string concatenation); and confine scratch files to a controlled work root rather than the
current directory or a shared temp location. These rules are common; the specific work-root
location is per-consumer.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.path-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.parameter-handling version=1.0.0 hash=9969ad954a28fc39 policy=canonical binding=follow-latest >>> -->
### A.7 Parameter conventions

Scripts expose the canonical **standard parameter set** (the shared switches every consumer
provides) plus consumer-specific parameters. Mutually exclusive options are validated at
entry; invalid combinations fail fast with a diagnostic. Help/usage shows the startup banner.
The standard switch set and the validation discipline are common; the consumer-specific
parameter list is defined in the consumer's SPEC.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.parameter-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.error-diagnostic version=1.0.0 hash=0d472879675b224b policy=canonical binding=follow-latest >>> -->
### A.8 Error and diagnostic model

Diagnostics are **three-layered**: (1) human-readable console output; (2) a per-run detail log
file; (3) structured per-failure records. Failures are **classified** (e.g. transient vs
fatal vs configuration) so callers can react. Each failure is recorded as a structured entry
following the canonical record shape (A.9 JSONL conventions). If a consumer additionally
provides an **operation-level trace facility** (an optional feature - see the consumer's Part
A.14 / project section), the per-failure records and the operation-level trace coexist; this
region does not require such a facility.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.error-diagnostic <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.csv-conventions version=1.0.0 hash=38cb631efd9af8a9 policy=canonical binding=follow-latest >>> -->
### A.9 CSV conventions

Tabular outputs and state files share common **column-naming** and **file-naming** conventions:
stable snake/Pascal column names, a per-phase output-file naming scheme, and a designated state
file for resumable runs. CSV is the baseline tabular format every consumer supports.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.csv-conventions <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.jsonl-conventions version=1.0.0 hash=3d605116d9e9b33c policy=canonical binding=follow-latest >>> -->
### A.9 (cont.) JSONL conventions - optional feature

A consumer **may** additionally emit JSONL (one JSON object per line) for machine consumption -
notably the per-failure records of A.8. When present, JSONL files follow the canonical naming
(per-phase, purpose-suffixed), use **camelCase** keys, and are LF-terminated. This region is an
**optional feature**: a consumer that emits only CSV omits it.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.jsonl-conventions <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.environment-eval version=1.0.0 hash=669c9ba612d6f35b policy=canonical binding=follow-latest >>> -->
### A.10 Environment evaluation

The **environment-evaluation phase (the first phase of the run)** assesses the host before any
work: it gathers platform/runtime facts in tiers (a baseline probe, then progressively
deeper checks) and **asserts compatibility** (runtime version, privileges, required tooling),
failing fast with a clear diagnostic when a prerequisite is unmet. The tiered model and the
fail-fast compatibility assertion are common; the specific phase number/name and the exact
checks are consumer-specific (Part B).
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.environment-eval <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.static-analysis version=1.0.0 hash=a9e9c8d44b702ac2 policy=canonical binding=follow-latest >>> -->
### A.11 Static analysis

`psa.py` (the canon's PowerShell static analyzer; canonical home in the tool canon) is the
**mandatory static-analysis gate**. Every consumer runs it with a project-local
`.psa.config.json` and MUST be **clean (0 errors / 0 warnings / 0 info)** before each commit.
The `.psa.config.json` **follows-latest** from the analyzer's canonical home (ADR 0009); it is
tool-owned, not part of this doc canon. Which rules a consumer suppresses (with justification)
and any project-specific false-positive dispositions are recorded in the consumer's own SPEC,
not here. CI runs a **three-stage model**: Stage 1 - lint / static analysis (psa.py +
PSScriptAnalyzer), cross-platform; Stage 2 - functional / parse validation (Windows where
required); Stage 3 - release / packaging. The three-stage model is common; the concrete
workflow filenames are path-encoded per consumer (A.13 / the dotfile conventions).
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.static-analysis <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.doc-language-policy version=1.0.0 hash=8e392c54780c4a7f policy=canonical binding=follow-latest >>> -->
### A.12 Documentation language policy

Code, configuration, and the SPEC/TESTING/CHANGELOG doc-set are authored in **English / ASCII**.
Intentional Japanese appears only in (a) the **bilingual README pair** (`README.md` +
`README.ja.md`, twin-file), (b) the **bilingual community-health files**
(`CODE_OF_CONDUCT` / `CONTRIBUTING` / `SECURITY`, in-file English + Japanese sections),
and (c) sanctioned data/string literals. The bilingual *mode* is fixed by document member -
twin-file for README, in-file dual-language for community-health. The doc-set file-set and each document's role follow the
canonical structure (README + README.ja, SPEC, and where applicable TESTING and CHANGELOG):
**history lives in CHANGELOG, current/forward design in SPEC**. `README.md` and `README.ja.md`
are maintained in **lock-step** (AGENTS.md §5). The mandatory README disclaimer and license
sections are defined by the canonical README format (the `readme.disclaimer` / `readme.license`
items) and are **not restated here**.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.doc-language-policy <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.development-workflow version=1.0.0 hash=fdadacb9bf023186 policy=canonical binding=follow-latest >>> -->
### A.13 Development workflow

Changes follow an **iterate-to-green** cycle: edit; run the static-analysis gate (A.11) to
**0/0/0**; run the consumer's verification/tests where present; then commit. Revision history
is recorded in **CHANGELOG** (Keep a Changelog format); the SPEC records the current design,
not a change log. Doc-touching changes keep the doc-set in sync (AGENTS.md §5): a SPEC change
that alters behaviour updates README / README.ja / TESTING in the same change. CI workflow
files are named with a per-consumer path-encoded prefix.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.development-workflow <<< -->

### A.14 Debug Trace Facility (cross-script feature)

The Debug Trace Facility is a reusable operation-level diagnostic
mechanism implemented inside `Download-SpeakerDeck.ps1`. It complements
the per-record diagnostics documented in A.8: where A.8 answers "which
record failed", the Debug Trace Facility answers "which named step
inside this function was in progress when the exception was raised".

This is intentionally placed in **Part A** because the facility is
fully generic: it makes no assumption about phases, records, deck
URLs, or any Speaker-Deck-specific concept. Any future script in this
repository may opt in by copying the same 700-line Section 1b block
verbatim from `Download-SpeakerDeck.ps1`.

### A.14.1 Three subsystems

| Subsystem | Public API |
|---|---|
| Trace primitives | `Start-DebugTrace` / `Set-DebugStep` / `Stop-DebugTrace` / `Format-DebugFailure` / `Write-DebugFailureReport` |
| JSONL file output (real-time stream) | `Enable-DebugTraceFileOutput` / `Disable-DebugTraceFileOutput` / `Get-DebugTraceFileOutputStatus` |
| JSON point-in-time export + auto-export-on-failure | `Export-DebugTraceJson` / `Enable-AutoExportOnPhaseFailure` |

### A.14.2 Module-level state

The facility maintains nine script-scope variables. New scripts MUST
declare them at script-load time so they exist before any function
body references them:

```powershell
$Script:DebugTraceStack             = New-Object 'System.Collections.Generic.Stack[object]'
$Script:DebugTraceCompletedFrames   = New-Object 'System.Collections.Generic.List[object]'
$Script:DebugTraceCompletedCap      = 1024
$Script:DebugTraceHistoryCap        = 256
$Script:DebugTraceJsonlLineCap      = 8192
$Script:DebugTraceJsonDepth         = 100
$Script:DebugTraceJsonlEnabled      = $false
$Script:DebugTraceJsonlPath         = $null
$Script:DebugTraceJsonlBuffer       = New-Object 'System.Collections.Generic.List[string]'
$Script:DebugTraceJsonlBufferCap    = 4096
$Script:DebugTraceJsonlWriteCount   = 0
$Script:DebugTraceJsonlErrorCount   = 0
$Script:DebugTraceJsonlLastError    = $null
$Script:DebugTraceAutoExportEnabled = $false
$Script:DebugTraceAutoExportDir     = $null
$Script:DebugTracePhaseRegistry     = @{}
$Script:DebugTraceEventSeq          = 0
```

### A.14.3 Standard usage pattern

Every function that should participate in tracing follows this
entry / body / catch / finally template:

```powershell
function Invoke-Something {
    Start-DebugTrace -Context 'Invoke-Something' -PhaseId 'PNN'
    try {
        Set-DebugStep 'validate inputs'
        ...
        Set-DebugStep 'fetch resource'
        ...
        Set-DebugStep 'persist result'
        ...
        return $result
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        throw
    } finally {
        Stop-DebugTrace
    }
}
```

Rules:

1. `Start-DebugTrace -PhaseId 'PNN'` is used for **phase-level** frames
   only (every `Invoke-PhaseN*` function in this script). Inner helper
   functions called from a phase body may use `Start-DebugTrace` with
   no `-PhaseId` to nest a sub-frame.
2. `Set-DebugStep` is a no-op when no frame is active, so library-style
   helpers can use it opportunistically without forcing callers to set
   up tracing.
3. `Write-DebugFailureReport -AutoExport` triggers a JSON snapshot only
   when `Enable-AutoExportOnPhaseFailure` has been called previously
   (in `Download-SpeakerDeck.ps1` this is done in the main try-block
   immediately after `Initialize-RuntimeDirectories`).
4. The `finally` block must always call `Stop-DebugTrace` to keep the
   stack balanced. Early-return branches inside the body that bypass
   the natural flow MUST call `Stop-DebugTrace` themselves and the
   `finally` block then becomes a no-op (checked via
   `$Script:DebugTraceStack.Count`).

### A.14.4 Activation order

```powershell
# After cleanup (-Clean/-CleanOnly) and Initialize-RuntimeDirectories.
Enable-DebugTraceFileOutput -Directory $Script:LogsDir
Enable-AutoExportOnPhaseFailure -OutputDirectory $Script:DiagDir
```

Both functions are best-effort: if activation fails (e.g. permission
denied on the logs directory), the script continues without the
diagnostic feature and the failure surfaces as a `Write-Warning`. The
in-memory pre-activation buffer continues to accumulate up to the
buffer cap, so a successful late activation still flushes whatever
trace events occurred during startup.

### A.14.5 Output format

`work/logs/debugtrace.jsonl` — one JSON object per line, UTF-8 with
BOM, append-only. Three event kinds:

| `kind` | Emitted by | Key fields |
|---|---|---|
| `frame.open` | `Start-DebugTrace` | `ctx`, `depth`, `phase` |
| `step` | `Set-DebugStep` | `ctx`, `step`, `detail` |
| `frame.close` | `Stop-DebugTrace` | `ctx`, `outcome`, `durMs`, `steps`, `phase` |
| `failure` | `Write-DebugFailureReport` | `ctx`, `step`, `exType`, `msg`, `stack`, `stepHistory[]` |
| `file.open` / `file.disable` / `file.close` | Lifecycle markers | `procId`, `scriptVer`, `scriptSha` |

`work/diag/debugtrace_export_<phaseId>_<timestamp>.json` — a single
self-contained pscustomobject with the following top-level keys:
`schemaVersion`, `exportedAtUtc`, `hostInfo`, `script`,
`fileOutput`, `phases[]`, `activeFrames[]`, `completedFrames[]`,
`events[]` (only when `-IncludeEvents` is passed; otherwise `[]`),
`eventCount`.

### A.14.6 Coexistence with A.8 (per-record diagnostics)

| Question | Tool |
|---|---|
| Which deck out of 800 failed to download? | A.8 (`P06_errors.jsonl`) |
| Which step inside Phase 5 raised the `PathTooLongException`? | A.14 (`debugtrace.jsonl` + auto-export JSON) |
| Both: a deck failed AND we want to see what step Phase 6's catch handler ran before retrying | Both facilities log independently; consult both files |

The two facilities never share files, never mutate each other's
state, and were designed to coexist on a single phase body without
overlap.

### A.14.7 Runtime overhead

The hot path of `Set-DebugStep` is a single `Add($obj)` into a
`List[object]` plus a JSONL serialise. The list has a cap
(`DebugTraceHistoryCap = 256`), and per-event JSON lines are capped at
`DebugTraceJsonlLineCap = 8192` chars. In `Download-SpeakerDeck.ps1`'s
real run profile (804 decks, 9 phases, ~50 `Set-DebugStep` calls per
phase) the facility produces roughly 600 JSONL events spanning ~150 KB
on disk — negligible compared to the 5.7 GB of PDF downloads.

### A.14.8 Common pitfalls

1. **Inner Set-DebugStep inside a Runspace Pool worker scriptblock is
   a no-op.** Worker scriptblocks run in isolated runspaces and cannot
   see the script-scope `$Script:DebugTraceStack`. This is documented
   inline in `Invoke-Phase6Download` and is intentional: per-deck
   failure inside the worker is captured by A.8's `Add-ErrorJsonlEntry`
   pipeline, not by DebugTrace.
2. **Early `return` from a traced function leaks a frame.** If a
   phase body has an early return for a "nothing to do" path
   (e.g. `Invoke-Phase8UndatedReclassify` returns when the file count
   is 0), the early-return branch MUST call `Stop-DebugTrace`
   explicitly and the surrounding `finally` block must guard against
   double-pop (check `$Script:DebugTraceStack.Peek().Context` matches).
3. **Avoid `host` as a key name in pscustomobjects inside Export.**
   PS 5.1 has been observed to treat `host` as the `$Host` auto-
   variable in certain parser contexts. The reference implementation
   uses `hostName` and `hostInfo` instead.

---

# Part B — Script-Specific Specification

> This section is the template every new script fills in. It captures only
> the things that differ from Part A. Use the Speaker Deck Bulk Downloader
> as the worked example.

## B.1 Identification

| Field | Value |
|---|---|
| Script name | `Download-SpeakerDeck.ps1` |
| Display name | Speaker Deck Bulk Downloader |
| Current revision | r25 (`strip-v-prefix-from-shorttag`); see [`CHANGELOG.md`](./CHANGELOG.md) for the per-release log |
| Purpose | Bulk-download all public PDFs from a Speaker Deck account |
| Owner | (fill in) |

## B.2 Inputs

| Source | Description |
|---|---|
| `-Account` parameter | Speaker Deck account name (default `oracle4engineer`) |
| Speaker Deck web pages | Listing + per-deck detail pages, scraped via HTML parsing |
| (Re-run only) `work/logs/year_overrides.csv` | Year-folder overrides from prior Phase 8 rescues |

## B.3 Outputs

```
<OutputDir>/
  YYYY/
    <title>__<original>.pdf           # year-folder layout (default)
  _undated/
    <title>__<original>.pdf           # when year can't be derived
<WorkDir>/
  logs/
    P04_evaluation_log.csv            # DryRun only
    P05_filename_plan.csv             # always
    P06_download_log.csv              # real-run only
    P06_errors.jsonl                  # only when failures occur
    P07_final_state.csv               # real-run only
    year_overrides.csv                # created lazily by Phase 8
    debugtrace.jsonl                  # Debug Trace Facility (A.14); always
  diag/
    failed/<idx>_<slug>.txt           # per-failure dump
    debugtrace_export_<phaseId>_<ts>.json  # auto-export on phase failure (A.14); only when a phase throws
```

## B.4 Phase Map

| ID | Name | Group | Description |
|---|---|---|---|
| P01 | EnvCheck | Setup | Per Part A.10 |
| P02 | GetTotalCount | Scan | Read profile page, extract total deck count |
| P03 | ListCollection | Scan | Iterate paginated listing, collect (URL, title) |
| P04 | Evaluation | Scan | Per-deck `og:meta` fetch, decide downloadability |
| P05 | FilenamePlan | Plan | Compute filename + full path per deck; flag duplicates / MAX_PATH violations; save CSV |
| P06 | Download | Fetch | Adaptive parallel download (Runspace Pool); throttle on 429/5xx |
| P07 | Reconciliation | Verify | Join plan + download log + disk inventory; flag discrepancies |
| P08 | UndatedReclassify | Verify | Read PDF metadata of files in `_undated/`; move to year folder if year resolved; append `year_overrides.csv` |
| P09 | FinalReport | Report | Stats + failure breakdown + year distribution |

## B.5 Year-folder Organization

Default layout: `<OutputDir>/<YYYY>/<filename>` where `YYYY` is derived
from these signals in order (priority 0 wins):

| # | Source | Label |
|---|---|---|
| 0 | `year_overrides.csv` (prior Phase 8) | `OverrideCsv` |
| 1 | `YYYYMMDD` pattern in `OriginalFilename` | `OriginalFilename` |
| 2 | `og:meta` PublishDate | `PublishDate` |
| 3 | Title contains `YYYY年` (Japanese kanji) | `TitleJp` |
| 4 | Title contains bare 4-digit year | `TitleNum` |
| 5 | None of the above → `_undated/` | `Fallback` |

Valid year range: `[2010, currentYear + 1]`.

Use `-FlatLayout` to disable year folders (legacy single-folder mode).

## B.6 PDF Metadata Reclassification (Phase 8)

Runs after Phase 7. For each file in `_undated/` that downloaded
successfully, read PDF metadata via pure-PowerShell regex (no external
libraries):

| Priority | Source | YearSource label |
|---|---|---|
| 1 | Info Dictionary `/CreationDate` | `PdfInfoDict` |
| 2 | XMP `<xmp:CreateDate>` | `PdfXmp` |
| 3 | XMP legacy `<xap:CreateDate>` | `PdfXmpLegacy` |
| 4 | XMP `<pdf:CreationDate>` | `PdfXmpPdfNs` |
| 5 | Info Dict `/ModDate` (fallback) | `PdfInfoDictMod` |
| 6 | XMP `<xmp:ModifyDate>` (fallback) | `PdfXmpMod` |

If a valid year is found, move the file from `_undated/foo.pdf` to
`<year>/foo.pdf` and append to `year_overrides.csv`.

Opt out via `-SkipPdfReclassification`. Automatically skipped under
`-DryRun` and `-FlatLayout`.

## B.7 Adaptive Parallel Download (Phase 6)

| Setting | Value |
|---|---|
| Initial concurrency | 3 |
| Max concurrency | 5 |
| Min concurrency | 1 |
| Max retries per deck | 3 |
| Per-request timeout | 300 sec |
| Ramp-up trigger | 10 consecutive successes → +1 concurrency |
| Throttle trigger (HTTP 429) | Halve concurrency, sleep 60 sec |
| Step-down trigger (HTTP 5xx) | -1 concurrency |
| Emergency brake | 3 consecutive failures → force min concurrency, sleep 90 sec |

## B.8 Failure Recovery

Phase 6 worker handles two failure shapes:

1. **HTTP errors** (status code present) → retry with backoff, classify
   by category in JSONL
2. **Local I/O errors** (e.g., the r17 wildcard bug) → retry, capture
   full stack trace in `.txt` dump

`.part` files are atomically moved to the final filename only after a
size sanity check (≥ 100 bytes).

See A.6 for the canonical safe-temp download pattern that resolves the
wildcard-in-path issue.

## B.9 Idempotency

Re-running with the same parameters:

- Skips files already on disk (unless `-Force`)
- Reads `year_overrides.csv` at Phase 5 priority 0
- Phase 8 finds 0 rescue candidates ("steady state")

To force a full re-do, use `-Clean` (wipes both `<OutputDir>` and `<WorkDir>`).

---

# Part C — Quality Gates & Validation Checklist

Before any commit, all of the following must pass:

### Static checks

- [ ] `python3 ../../quality-tools/powershell-static-analyzer/psa.py <script>.ps1` → 0 errors / 0 warnings / 0 info
- [ ] `Invoke-ScriptAnalyzer -Path <script>.ps1 -Settings ./PSScriptAnalyzerSettings.psd1 -Severity Error,Warning,Information` → 0 findings (the sibling `PSScriptAnalyzerSettings.psd1` is authoritative; any new finding must be addressed either by code change or by a deliberate, documented suppression)
- [ ] File starts with UTF-8 BOM (`EF BB BF`)
- [ ] No non-ASCII bytes outside the BOM
- [ ] Line count in script matches `Lines : NNNN` in README.md AND README.ja.md
- [ ] `Script:ScriptVersion` and `Script:ScriptTag` updated for the change

### CI gates

- [ ] Workflow YAML files under `.github/workflows/` validate as YAML and pass `actionlint` if available
- [ ] Every job has an explicit `timeout-minutes` and a fork-PR `if`-guard (see repository-root `/SPEC.md` §4 and §5)
- [ ] STAGE 1 (Linux checks) is green on the latest commit to `main` — verify via the badge in `README.md`
- [ ] STAGE 2 (Windows checks) is green on the latest commit to `main` — STAGE 2 fires automatically when STAGE 1 succeeds
- [ ] When releasing, STAGE 3 (release verification) runs automatically via `release/published`

### Functional checks

- [ ] `-DryRun` completes without errors
- [ ] Phase Timing Summary shows expected phase IDs (P01 → PNN, no gaps)
- [ ] All phase CSVs exist with expected column sets
- [ ] Real run produces 0 anomalies in P07 reconciliation (or anomalies
      are explained in P09 output)
- [ ] Re-run shows steady-state (Phase 8 examined: 0, no new failures)

### Documentation checks

- [ ] README.md mentions every new parameter, switch, output file
- [ ] README.ja.md is line-for-line equivalent in structure
- [ ] CHANGELOG comment at top of script lists the change
- [ ] README.md has a **Disclaimer** section near the top (per A.12.5)
- [ ] README.md has a **License** section near the top (per A.12.5)
- [ ] README.ja.md has equivalent **免責事項** and **ライセンス** sections
- [ ] A `LICENSE` file exists at the repo root

### Cross-CSV checks

- [ ] Common columns (Index, Title, DeckUrl, …) have identical names
      across all per-phase CSVs
- [ ] Each later-stage CSV is a superset of earlier-stage columns

### Debug Trace Facility checks (A.14)

- [ ] `work/logs/debugtrace.jsonl` is created on every real run (first
      `kind: file.open` event present, followed by `frame.open` events
      for every phase)
- [ ] No `frame.open` event is left without a matching `frame.close`
      event at end of run (stack-balance check)
- [ ] Top-level `catch` calls `Write-DebugFailureReport $_
      -IncludeStepHistory -AutoExport`
- [ ] Every `Invoke-Phase*` function wraps its body in
      `Start-DebugTrace -PhaseId 'PNN'` / `Stop-DebugTrace`
- [ ] No `Set-DebugStep` call inside a Runspace Pool worker scriptblock
      (worker runspaces cannot see script-scope state; per-record
      diagnostics in A.8 cover this layer)

---

# Part D — Known Pitfalls & Lessons Learned

These are real bugs found in past revisions. Future scripts inherit the
fix; never reintroduce the bug.

## D.1 r10 — Wildcard chars in filenames break Test-Path / Get-Item / Remove-Item / Move-Item

**Symptom:** Files with `[` or `]` in the path (e.g. `[TechNight #49]`)
fail with `FileNotFoundException` during reconciliation.

**Root cause:** PowerShell treats `[` `]` as wildcard character classes
unless `-LiteralPath` is specified.

**Fix:** Use `-LiteralPath` on every `Test-Path`, `Get-Item`, `Remove-Item`,
`Move-Item`, `Copy-Item`, `Set-Content`, `Add-Content`, `Export-Csv`.

## D.2 r11 — `Split-Path -LiteralPath -Parent` doesn't exist on PS 5.1

**Symptom:** `ParameterSetException` when using
`Split-Path -LiteralPath $p -Parent`.

**Root cause:** PS 5.1's `Split-Path` `LiteralPathSet` does not include
`-Parent` (this was added in PS 7).

**Fix:** Use `[System.IO.Path]::GetDirectoryName($p)`.

## D.3 r17 — `Invoke-WebRequest -OutFile` does NOT support `-LiteralPath`

**Symptom:** Downloads silently fail with `FileNotFoundException`
"wildcard path … could not be resolved" for any title containing `[`/`]`.

**Root cause:** `-OutFile` uses `-Path` semantics internally (wildcards
expanded). PS 5.1 has no `-LiteralPath` parameter for `Invoke-WebRequest`.

**Fix:** Download to a GUID-named safe path first, then `Move-Item
-LiteralPath` to the real destination. See A.6 for the canonical pattern.

## D.4 Phase renumbering risk (r16)

**Symptom:** When renumbering phases (e.g., to remove `P6.5`), automated
text substitution can produce false matches — e.g. comments referring to
`Phase 7` (the old final report) get incorrectly migrated to `Phase 9`
when the original mention was about the *rescue* phase.

**Mitigation:** After bulk renumbering, audit every `Phase N` mention in
comments and docstrings against its semantic referent (which named phase
does this prose actually mean?), not its old number.

## D.5 Console encoding on ja-JP Windows

**Symptom:** Japanese characters in scripted output render as `??` or
mojibake, especially in CI / non-interactive shells.

**Fix:** At script top, force both `$OutputEncoding` and
`[Console]::OutputEncoding` to UTF-8.

## D.6 Untyped `[char]0x5E74` vs regex `\u5E74`

When you need to *match* a non-ASCII character in a regex, use the regex
engine's `\uXXXX` escape (kept as literal ASCII in source). When you need
to *emit* a non-ASCII character at runtime (e.g., for a log message),
read it from an external file or build it via `[char]0xXXXX` — never put
it directly in the source.

## D.7 r27 — `psa.py` 4.0.0 `PSA2009` false positive on `$Coll.Add(@{...})` + `foreach` pattern

**Symptom:** `psa.py` 4.0.0 reports two `PSA2009` warnings on
`$job.Collected = $true` lines in Phase 4 and Phase 6 reaper loops,
even though `$job` in those loops is bound to a hashtable element of
`$jobs` (not a sealed pscustomobject). The warning incorrectly claims
that `$job` was initialised with `[pscustomobject]@{...}` that does
not declare `Collected`.

**Root cause:** Two unrelated variables in the file share the name
`$job`:

1. **Phase 5 prepare loop** (`Invoke-Phase05_PreparePlan`):
   `$job = [PSCustomObject]@{ Index = ...; ... }` — a sealed object
   whose property surface does **not** include `Collected`.
2. **Phase 4 / Phase 6 reaper loops**: `foreach ($job in $newlyDone)`
   where `$newlyDone = $jobs | Where-Object {...}`, and `$jobs` is an
   `ArrayList` of hashtables created by `[void]$jobs.Add(@{...})`.

`psa.py` 4.0.0 performs file-level (not function-scope-aware) tracking
for `PSA2009`. The Phase 5 sealed-object initialisation puts `$job`
into the "tracked PSCustomObject" set. The Phase 4 / 6 hashtable
binding is *indirect* — through `$jobs.Add(@{...})` + foreach — which
the file-level detector did not yet recognise, so `$job.Collected =
$true` was flagged.

**Fix (psa.py side):** `psa.py` 4.0.1 adds **Step 2c2** to the
`PSA2009` walk: any foreach loop-variable bound through
`$Coll.Add(@{...})` + `foreach (...) in $Coll` is treated as a
hashtable element, not as a PSCustomObject. Pipeline / method
derivations (`$X = $Coll | ...`, `$X = $Coll.Where(...)`) are
followed to a fixed point, so the common
`$newlyDone = $jobs | Where-Object {...}` idiom is recognised.

**Fix (script side):** As a separate consistency improvement, the
Phase 4 hashtable init (`[void]$jobs.Add(@{ PS = $ps; Handle = $handle;
Deck = $deck })`) is updated to include `Collected = $false` to match
Phase 6's init (`[void]$jobs.Add(@{ ...; Collected = $false })`). The
two reaper loops now both observe `Collected` declared at construction
time; the field is then set to `$true` inside the `finally` block. This
is purely cosmetic — hashtables tolerate dynamic key addition at
runtime — but the explicit declaration aids reader comprehension.

**Adoption:** This release (r27, `psa-py-v4-llm-governance-baseline`)
adopts `psa.py` 4.0.1 as the verification gate and adds `PSAP0005`
to the `.psa.config.json` enable-list in strict mode. The four-script
sister repository (`usui-tk/Deploy-Drivers-For-WindowsServer`) uses
`psa.py` 4.0.0's `PSAP0005` in *relaxed* mode with a documented
migration baseline; this repository is already at the end-state and
needs no migration aid.

**Lesson learned:** Sealed-object semantics in PowerShell 5.1
(`[PSCustomObject]@{...}`) and the dynamic-property-bag semantics of
hashtables (`@{...}`) look very similar at the call site (both use
`.Property` access syntax) but differ sharply in their property-write
semantics. When sharing a variable name across both shapes in the same
file, the static analyser cannot always disambiguate by scope — so
the explicit declaration of every dynamically-added property at
construction time (or via `Add-Member`) is both safer and more
self-documenting than relying on the implicit hashtable add.

---

## Appendix: How to seed a new script from this SPEC

When asked to create a new PowerShell script in this style:

1. Read this SPEC end to end.
2. Identify the closest existing in-house script (A.1.3).
3. Copy:
   - The script's banner / version block
   - `Write-PhaseHeader` / `Write-PhaseFooter` / logging helpers
   - `Show-PowerShellEnvironment` / `Assert-PowerShellCompatibility`
   - `Format-Elapsed`
   - The CSV / JSONL writers
   - Reference the canonical `psa.py` at
     `quality-tools/powershell-static-analyzer/psa.py` (do not duplicate
     it into a per-script `tools/` folder)
4. Replace the phase bodies with the new script's logic.
5. Renumber phases starting from P01.
6. Fill in Part B template fields.
7. Run quality gates (Part C).
8. Update SPEC.md Part D if a new pitfall is discovered.

This document is itself versioned. Always check that the SPEC revision you
are reading matches the script revision you are working on.
