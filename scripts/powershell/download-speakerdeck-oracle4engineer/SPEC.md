# PowerShell Script Specification (SPEC)

> **Purpose of this document**
>
> This file is the authoritative specification for building enterprise-grade
> PowerShell scripts in the style used by this repository. It is written to
> be picked up directly by an LLM (Claude) at the start of a new project so
> that the LLM does not have to re-derive conventions from scratch.
>
> **The single most important rule**: when a piece of behavior is described
> in **Part A (Common Spec)**, the new script MUST reuse the existing
> implementation referenced there. Do not re-design phase headers, log
> markers, environment diagnostics, error JSONL formats, or the psa.py
> static analyzer. These have been hardened through many revisions and
> reflect real-world bug fixes; rewriting them invites regressions.
>
> Use **Part B** as a template for documenting the *new* script's unique
> processing logic. Everything in Part A is shared and inherited.

---

## Table of Contents

- [Part A — Common Specification (reusable across all scripts)](#part-a--common-specification-reusable-across-all-scripts)
  - [A.1 Reference Assets](#a1-reference-assets)
  - [A.2 Source File Format](#a2-source-file-format)
  - [A.3 Banner & Version Identification](#a3-banner--version-identification)
  - [A.4 Phase Architecture](#a4-phase-architecture)
  - [A.5 Logging Conventions](#a5-logging-conventions)
  - [A.6 Path Handling (-LiteralPath Rules)](#a6-path-handling--literalpath-rules)
  - [A.7 Parameter Conventions](#a7-parameter-conventions)
  - [A.8 Error & Diagnostic Conventions](#a8-error--diagnostic-conventions)
  - [A.9 CSV / JSONL Column Conventions](#a9-csv--jsonl-column-conventions)
  - [A.10 Environment Evaluation (Phase 1)](#a10-environment-evaluation-phase-1)
  - [A.11 Static Analysis with psa.py](#a11-static-analysis-with-psapy)
  - [A.12 Documentation Language Policy](#a12-documentation-language-policy)
  - [A.13 Development Workflow](#a13-development-workflow)
  - [A.14 Debug Trace Facility](#a14-debug-trace-facility)
- [Part B — Script-Specific Specification (template)](#part-b--script-specific-specification-template)
- [Part C — Quality Gates & Validation Checklist](#part-c--quality-gates--validation-checklist)
- [Part D — Known Pitfalls & Lessons Learned](#part-d--known-pitfalls--lessons-learned)

---

# Part A — Common Specification (reusable across all scripts)

> **Status: Canonical inheritance source.** This Part A is the
> repository's canonical Part A — the source of truth that sibling
> Layer 3 SPECs (currently
> [`scripts/powershell/update-windows-server-iso/SPEC.md`](../update-windows-server-iso/SPEC.md)
> and any future PowerShell script SPEC in this style) inherit by
> reference rather than by restating. Modifications to this Part A
> propagate to every sibling SPEC that inherits it; review the
> cross-script impact before committing changes. The rule, its
> rationale, and the forensic record of past inheritance violations
> (notably the `c40755c` Part A bloat regression) are recorded in
> the repository-wide
> [`AGENTS.md` §6 Part A Inheritance Rule (ABSOLUTE)](../../../AGENTS.md#6-part-a-inheritance-rule-absolute)
> and
> [`AGENTS.md` §9 AP-1](../../../AGENTS.md#9-anti-patterns-forensically-documented).
> LLM agents authoring or revising any Layer 3 Part A MUST consult
> both references before touching the inherited surface.

## A.1 Reference Assets

These are the canonical sources for shared logic in this repository.
**Pull from these directly; do not re-implement.**

### A.1.1 Static analyzer

```
scripts/python/powershell-static-analyzer/psa.py
```

`psa.py` is a **pure Python** static analyzer (no PowerShell installation
required), with a rule set spanning `PSA1001`..`PSA9002` plus
`PSAP0001`..`PSAP0004` (opt-in pipeline-convention rules). Consumers
MUST validate against the latest mainline version; see the repository
root [`README.md`](../../../README.md) "psa.py Versioning Policy" for
the canonical workflow and version discovery. Within this repository
it must be:

- Reused as-is from the canonical location
  `scripts/python/powershell-static-analyzer/psa.py`
  (do not fork or maintain a separate copy)
- Used as the gate before every commit
- Configured per-script-directory via a local `.psa.config.json` when
  rule disables are warranted (see A.11)

See A.11 for project-local conventions and
[`scripts/python/powershell-static-analyzer/SPEC.md`](../../python/powershell-static-analyzer/SPEC.md)
for the authoritative rule specification.

### A.1.2 Companion specifications (this folder)

Each script folder in this style carries the following set of documentation:

- `README.md` / `README.ja.md` — end-user documentation
  (installation, quick start, parameters, troubleshooting)
- `SPEC.md` (English only) — developer / LLM specification (this file)
- `TESTING.md` (English only) — verification procedure and recorded
  real-run results

The `psa.py` static analyzer used by these scripts lives at the
repository-wide canonical location
[`scripts/python/powershell-static-analyzer/`](../../python/powershell-static-analyzer/),
not inside each script folder.

Repository-level files like `LICENSE`, `CONTRIBUTING.md`, and the top-level
`README.md` / `README.ja.md` live at the repository root and are shared
across all scripts in the repository.

### A.1.3 Companion in-house script (latest reference)

The Speaker Deck Bulk Downloader (`Download-SpeakerDeck.ps1`, r24 as of
2026-05-18, located at
`scripts/powershell/download-speakerdeck-oracle4engineer/`) is the
canonical in-house reference and the **single source of truth** for the
following reusable assets:

- 9-phase architecture (`Setup` / `Scan` / `Plan` / `Fetch` / `Verify` /
  `Report` groups) with year-folder output organization
- Logging helpers: `Write-PhaseHeader` / `Write-PhaseFooter` /
  `Format-Elapsed` / `Write-Step` / `Write-Ok` / `Write-Caution` /
  `Write-Fail` / `Write-Skip` / `Write-SubSection`
- Banner block layout (Magenta `=` × 72, script-tag line, phase entry /
  exit)
- Environment dump: `Show-PowerShellEnvironment` /
  `Assert-PowerShellCompatibility`
- Host-configuration helpers: `Set-Utf8PipelineEncoding` / `Set-TlsSecurityProtocol`
- Adaptive parallel download via Runspace Pool
- PDF metadata reclassification (Phase 8 / year_overrides.csv pattern)
- CSV cross-phase column conventions (Section A.9)
- Debug Trace Facility integration pattern (Section A.14; per-phase
  `Start-DebugTrace` / `Stop-DebugTrace` wrapping plus `Set-DebugStep`
  checkpoints, with JSONL streaming and auto-export-on-failure)

When asked to build a new bulk-fetch or data-processing script in this
repo, **start by reading this script** and copying its skeleton verbatim.

### A.1.4 Folder naming convention for target-specific scripts

When a single script is generic enough to be reused against multiple
target accounts, services, or tenants, the script body itself stays
generic (parameterized via `-Account`, `-Subscription`, etc.), but the
**folder** is suffixed with the actual target to avoid collisions when
the same script is deployed for a different target.

Pattern: `<verb-noun>-<target-identifier>/`

Examples:

| Folder | Holds |
|---|---|
| `download-speakerdeck-oracle4engineer/` | The script run against the `oracle4engineer` Speaker Deck account |
| `download-speakerdeck-acmecorp/` | The same script run against `acmecorp` (potentially with slight customizations) |
| `download-githubrepos-anthropics/` | A hypothetical GitHub-repo downloader targeting the `anthropics` org |
| `inventory-aws-prod/` | An AWS inventory script for the `prod` account |

The script's **filename itself stays clean** (`Download-SpeakerDeck.ps1`,
not `Download-SpeakerDeck-oracle4engineer.ps1`). Only the **folder name**
carries the target identifier. This keeps the PowerShell `Verb-Noun.ps1`
idiom intact while preventing name clashes between multiple copies of
the same logic deployed for different targets.

If the script truly is account-agnostic and reused as-is (e.g. its
default value just happens to be one account but `-Account` is fully
exposed), then a single folder is sufficient and the suffix is the
default-account name. When the customizations between two targets become
non-trivial, fork the folder.

## A.2 Source File Format

| Rule | Value |
|---|---|
| Encoding | UTF-8 with BOM (3 bytes `EF BB BF` at start) |
| Source bytes | **Strictly ASCII only outside the BOM** |
| Non-ASCII strategy | Use `.NET` regex Unicode escapes (`\u5E74` for `年`, etc.) and PowerShell's `[char]0xXXXX` for runtime strings |
| Line endings | CRLF on disk (PS 5.1 friendly) |
| Indentation | 4 spaces, no tabs |
| Max line length | No hard limit; favor readability |
| Shebang | None (PowerShell scripts don't use one) |

**Why ASCII-only?** PowerShell 5.1 on `ja-JP` Windows often defaults to
cp932 for default file encoding, and mixing source bytes leads to subtle
parser errors. Keeping the source ASCII eliminates an entire class of
encoding incidents. Japanese text is always emitted at runtime via Unicode
escapes or via reading external files.

**Validation:**

```bash
python3 -c "
with open('script.ps1','rb') as f: d=f.read()
assert d[:3]==bytes([0xEF,0xBB,0xBF]), 'BOM missing'
non_ascii = sum(1 for b in d[3:] if b > 0x7F)
assert non_ascii == 0, f'{non_ascii} non-ASCII bytes'
print('OK')
"
```

## A.3 Banner & Version Identification

### Version string format

```powershell
$Script:ScriptVersion = '<short-name>-YYYY.MM.DD-rNN'
$Script:ScriptTag     = '<short-kebab-tag-describing-the-revision>'
```

Examples:

- `speakerdeck-2026.05.11-r17` / tag `outfile-wildcard-fix`
- `amd-driver-2025.11.04-r12` / tag `windows-server-2025-support`

### Self-fingerprint via SHA256

The script must hash its own file at startup and expose the first 12 hex
chars. This appears in every phase header so logs are reproducible:

```powershell
$Script:ScriptHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.Substring(0,12).ToLower()
$Script:ScriptShortTag = "$Script:ScriptVersion/$Script:ScriptHash"
```

### Banner block

The banner is always printed first (after the security warning if any).
Format:

```
========================================================================
  <Script Display Name>
  <ScriptVersion>/<ScriptHash>
========================================================================
  <Key parameter 1> : <value>
  <Key parameter 2> : <value>
  ...
========================================================================
```

Active opt-in switches are listed below the params block:

```
  Force                : ON
  DryRun               : ON
  SkipEnvCheck         : ON
```

## A.4 Phase Architecture

### Numbering rules

1. **Phases are integers, starting from 1, incremented by 1**.
2. **No decimal phase numbers** (`P6.5` is forbidden; use `P08` instead).
3. Phase IDs are zero-padded: `P01` through `P09`, then `P10`, `P11`, ...
4. Phase IDs are **stable across runs**; do not renumber to accommodate a
   new phase unless renumbering everything (see r16 precedent in the
   Speaker Deck script).

### Phase groups

Every phase belongs to one of these groups (5-char-max identifier):

| Group | Purpose |
|---|---|
| `Setup` | Environment evaluation, sanity checks |
| `Scan` | Read-only data collection from external sources |
| `Plan` | In-memory computation; no side effects on disk or remote |
| `Fetch` | Network operations that produce side effects |
| `Verify` | Reconcile actual state vs plan |
| `Report` | Generate human-readable summary |

### Phase header / footer

Reuse the reference implementation. The on-screen output looks like:

```
========================================================================
 PHASE P03  - ListCollection         (Scan   ) start: 14:04:38
 script: speakerdeck-2026.05.11-r17/b7a478b625b8
========================================================================
...
 PHASE P03  -> DONE     elapsed: 1m3.5s
```

Phase status terminals: `done`, `skipped`, `failed`.

### Phase Timing Summary

At end of run, print a table:

```
========================================================================
 Phase Timing Summary
========================================================================
  P01   DONE     elapsed: 0.38s
  P02   DONE     elapsed: 0.69s
  ...
  ----------------------------------------
  Total elapsed: 20m39.1s
========================================================================
```

The phase-ID column width is `{0,-4}` (sufficient for `P01` … `P99`).

## A.5 Logging Conventions

### Markers

| Marker | Function | Color | Meaning |
|---|---|---|---|
| `[*]` | `Write-Step` | Cyan | Action in progress / informational step |
| `[+]` | `Write-Ok` | Green | Successful completion |
| `[!]` | `Write-Caution` | Yellow | Recoverable warning |
| `[X]` | `Write-Fail` | Red | Failure (non-fatal) |
| `[~]` | `Write-Skip` | DarkGray | Intentionally skipped |

These markers are **5-character (`[X] ` includes trailing space)**, fixed
width, and are emitted *inside* the timestamp/elapsed prefix. Standard line
format:

```
[HH:MM:SS] [+E.EEs]    [+] human-readable message
```

Where `E.EEs` is the elapsed-from-script-start in either:

- `S.SSs` if under 60 seconds
- `MmS.Ss` if 1m–59m
- `HhMmS.Ss` if ≥ 1 hour

Format-Elapsed is the canonical helper; copy it from the reference script.

### Color discipline

| Concept | Color |
|---|---|
| In-progress / info | Cyan |
| Success | Green |
| Warning (recoverable) | Yellow |
| Failure / anomaly | Red |
| Skipped / muted | DarkGray |
| Highlight / dry-run | Magenta |
| Default text | (no color override) |

### Console encoding

Force UTF-8 console output at the top of the script:

```powershell
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }
```

### TLS hardening

Always enforce TLS 1.2+:

```powershell
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor `
        [Net.SecurityProtocolType]::Tls11 -bor `
        [Net.SecurityProtocolType]::Tls
} catch { }
```

## A.6 Path Handling (-LiteralPath Rules)

> **This section encodes hard-won bug fixes. Read carefully.**

### The wildcard-interpretation hazard

PowerShell's path-based cmdlets (`Test-Path`, `Get-Item`, `Remove-Item`,
`Move-Item`, `Copy-Item`, `Set-Content`, `Add-Content`, `Export-Csv` with
`-Path`) treat `[ ]` as wildcard character classes. A path like
`C:\out\[Foo].pdf` will be interpreted as "match one of F, o, o" and fail
with `FileNotFoundException` ("wildcard path … could not be resolved").

Real-world paths can contain:

- `[` `]` in titles like `[TechNight #49]`
- `#` in slug-derived filenames
- Other regex-meaningful chars (rare)

### Rule: use -LiteralPath everywhere

For all paths derived from external data (titles, URLs, user input), use
`-LiteralPath` on every cmdlet that supports it. Add a defensive comment
near the cmdlet noting why.

### Cmdlets that do NOT support -LiteralPath

| Cmdlet | Workaround |
|---|---|
| `Invoke-WebRequest -OutFile` | Download to a GUID-named safe path; `Move-Item -LiteralPath` to the real destination |
| `Start-BitsTransfer -Destination` | Same as above |
| `Split-Path -LiteralPath -Parent` (PS 5.1) | Use `[System.IO.Path]::GetDirectoryName($p)` |
| `Resolve-Path` | Use `[System.IO.Path]::GetFullPath($p)` |

### Canonical safe-temp pattern (for Invoke-WebRequest)

```powershell
# Build a wildcard-free download path: <dir>\.dl_<GUID>.part
$safeTmpDir  = [System.IO.Path]::GetDirectoryName($targetPath)
$safeTmpName = '.dl_' + [Guid]::NewGuid().ToString('N') + '.part'
$safeTmp     = Join-Path $safeTmpDir $safeTmpName

Invoke-WebRequest -Uri $url -OutFile $safeTmp -UseBasicParsing -ErrorAction Stop

# Move to the real .part location (which may contain [ ]); Move-Item
# supports -LiteralPath, so wildcards are not interpreted.
Move-Item -LiteralPath $safeTmp -Destination $realPartPath -Force
```

### Sanitization of derived filenames

When a filename is derived from a URL slug, sanitize as follows:

```powershell
$safe = $slug -replace '[<>:"/\\|?*]', '_'
if ($safe.Length -gt 80) { $safe = $safe.Substring(0, 80) }
```

Note that `[`, `]`, `#` are **legal Windows filename characters** — do not
strip them. The mitigation is `-LiteralPath`, not character removal.

## A.7 Parameter Conventions

### Standard switches (use these names verbatim)

| Switch | Behavior |
|---|---|
| `-DryRun` | Run all read-only phases; explicitly mark Fetch/Verify phases as SKIPPED |
| `-Force` | Overwrite existing outputs |
| `-Clean` | Delete output / work directories before running |
| `-CleanOnly` | Same wipe as `-Clean`, then exit without running phases |
| `-SkipEnvCheck` | Skip Phase 1 and use safe-default thresholds |
| `-EnvironmentInfoOnly` | Run only Phase 1 Step 0 (PowerShell environment dump via `Show-PowerShellEnvironment`), then exit 0. Intended for CI smoke testing; skips Step A (registry), Step B (filesystem tests), and Phases 2–8 |

### Mutual exclusion

Add a validation block right after `param(...)`:

```powershell
if ($Clean -and $CleanOnly) {
    throw 'Specify -Clean OR -CleanOnly, not both.'
}

# -EnvironmentInfoOnly requires Phase 1 to run (it exits inside Step 0).
# -SkipEnvCheck skips Phase 1 entirely. Combining them is meaningless.
if ($EnvironmentInfoOnly -and $SkipEnvCheck) {
    throw '-EnvironmentInfoOnly and -SkipEnvCheck cannot be used together.'
}
```

### Banner display

The banner block (A.3) must display every active opt-in switch, color-coded:

- `-Force`, `-SkipEnvCheck`, `-Clean`, `-CleanOnly` → Yellow
- `-DryRun` → Magenta

## A.8 Error & Diagnostic Conventions

### Three-tier diagnostic output

1. **Console log** — per-attempt failure marker, succinct
2. **Per-failure `.txt` dump** in `<work>\diag\failed\<idx>_<slug>.txt`
3. **Structured JSONL** in `<work>\logs\PNN_errors.jsonl`

### Failure category classification

Group exceptions into coarse categories for the final report's failure
breakdown. Example categories:

```
System.Net.WebException
System.IO.FileNotFoundException
System.IO.IOException
Timeout
HTTPStatus.4XX
HTTPStatus.5XX
Other
```

### Diagnostic .txt dump format

Fixed schema:

```
========================================================================
Failure diagnostic for deck #<idx>
========================================================================
Generated at        : <ISO timestamp>
Script version      : v<ver>/<hash>

-- Deck info ----------------------------------------------------------
<key-value lines>

-- Output path --------------------------------------------------------
<key-value lines>

-- Failure summary ----------------------------------------------------
<key-value lines>

-- Error details ------------------------------------------------------
<key-value lines>

-- Response body preview (first ~2KB) ---------------------------------
<truncated body>

-- Attempt history ----------------------------------------------------
<one line per attempt>

-- Stack trace --------------------------------------------------------
<stack>
```

### JSONL schema (per failure)

One self-contained JSON object per line. Keys are `camelCase`:

```json
{
  "timestamp": "<ISO>",
  "scriptVersion": "<ver>/<hash>",
  "index": 42,
  "title": "...",
  "deckUrl": "...",
  "category": "...",
  "exceptionType": "...",
  "exceptionMessage": "...",
  "attempts": 3,
  "attemptHistory": [ ... ]
}
```

### Relation to the Debug Trace Facility (Section A.14)

This three-tier diagnostic output is **per-record** (one entry per
failed unit of work, e.g. per failed deck download). It is the right
tool when the script processes many items in a loop and each item can
fail independently.

The **Debug Trace Facility (A.14)** is a complementary mechanism that
operates at **operation-level granularity**: it tracks every named
step inside a single function (or phase) and reports which step was
in progress when an exception was raised. It is the right tool when
you need to know "where exactly inside this large function did it
break" rather than "which record failed".

The two facilities coexist without overlap. In `Download-SpeakerDeck.ps1`:

- The Phase 6 per-deck failure path uses the three-tier per-record
  diagnostics (`work/diag/failed/<idx>_<slug>.txt`,
  `work/logs/P06_errors.jsonl`).
- Every Phase 1-8 function wraps its body in `Start-DebugTrace
  -PhaseId 'PNN'` / `Stop-DebugTrace` so any structural failure
  (e.g. inside Phase 5 filename-plan computation, where there is no
  "per-record" notion) lands in the DebugTrace stream
  (`work/logs/debugtrace.jsonl`) and triggers a JSON snapshot under
  `work/diag/debugtrace_export_*.json`.

## A.9 CSV / JSONL Column Conventions

### Common columns across all per-phase CSVs

If a script uses multiple CSV outputs across phases, the following columns
must appear in *every* CSV with **identical names**:

| Column | Meaning |
|---|---|
| `Index` | 1-based record position in the scan order |
| `Title` | Display name (title, label, etc.) |

Beyond these, each script defines its own per-phase additions. Each
later-stage CSV is a **strict superset** of the earlier-stage columns
(plus stage-specific additions), enabling cross-CSV join/grep.

### Filename pattern

```
PNN_<purpose>.csv
PNN_<purpose>.jsonl
```

Examples: `P04_evaluation_log.csv`, `P06_errors.jsonl`, `P07_final_state.csv`.

### Persistent state files

If the script maintains state across runs (overrides, caches), use a flat
filename without the `PNN_` prefix:

```
work/logs/year_overrides.csv
work/logs/url_cache.csv
```

These are separate from per-phase logs and are documented in README.

## A.10 Environment Evaluation (Phase 1)

Every script's Phase 1 must include:

### Step 0: PowerShell Execution Environment

Dump all of:

- PS version, edition (Desktop / Core)
- CLR version, engine build
- Process architecture (must be 64-bit)
- OS name, build number, architecture
- Host, execution policy
- TLS default settings
- Culture, UI culture
- Default encoding, console encoding
- Script path, working directory

Then run `Assert-PowerShellCompatibility`:

- PS 5.1+ required
- 64-bit process required
- Windows 10/11 or Windows Server 2016+ required

### Step A: Registry Check

Read `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled`.

### Step B: Real-world Filesystem Tests

Create dummy files at increasing path lengths (100, 200, 240, 260, 300,
500, 1000 chars) to determine the actual effective limits in the current
environment.

### Step C: Tier Classification

Based on the longest successful path length, classify into:

| Tier | Max length | Effective filename / full-path thresholds |
|---|---|---|
| Tier 1: Modern | ≥ 900 | 240 / 480 |
| Tier 2: Partial | 260–900 | 240 / 480 |
| Tier 3: Conservative | 200–260 | 100 / 240 |
| Tier 4: Restricted | < 200 | 80 / 200 |

## A.11 Static Analysis with psa.py

### Setup

```
<repo>/
  scripts/
    powershell/
      download-speakerdeck-oracle4engineer/
        .psa.config.json     # project-local config (disables PSA6003 + PSA7003)
    python/
      powershell-static-analyzer/
        psa.py               # canonical location, latest mainline
        VERSION              # canonical version string (read with curl/cat)
        SPEC.md              # authoritative analyzer specification (English only)
        CHANGELOG.md         # per-release change log (English only)
```

### Required gate

Before every commit, run `psa.py` from this script directory (so that the
project-local `.psa.config.json` is auto-discovered):

```bash
cd scripts/powershell/download-speakerdeck-oracle4engineer
python3 ../../python/powershell-static-analyzer/psa.py Download-SpeakerDeck.ps1
```

Must pass with **0 errors / 0 warnings / 0 info**.

### Rule coverage (psa.py — latest mainline)

`psa.py` ships with a rule set spanning `PSA1001`..`PSA9002` (generic
rules grouped into nine categories) plus the opt-in pipeline-convention
family `PSAP0001`..`PSAP0005`. All `PSAPxxxx` rules are off by default.
This project opts in to `PSAP0003` (inline revision-tag comments),
`PSAP0004` (end-of-file `REVISION HISTORY` blocks), and **`PSAP0005`
(revision reference in comment body, added in `psa.py` 4.0.0)** in
strict mode (`psap0005_relaxed_mode` is not set, default `false`).
The total rule count is **46** (`PSA1xxx ×3`, `PSA2xxx ×11`,
`PSA3xxx ×6`, `PSA4xxx ×4`, `PSA5xxx ×4`, `PSA6xxx ×8`, `PSA7xxx ×2`,
`PSA8xxx ×1`, `PSA9xxx ×2`, `PSAPxxxx ×5`). A condensed table is
reproduced in [`README.md`](./README.md) and [`README.ja.md`](./README.ja.md).
For the authoritative specification of every rule (severity,
examples, suppression guidance), see
[`../../python/powershell-static-analyzer/SPEC.md`](../../python/powershell-static-analyzer/SPEC.md) §4.

### Project-local suppression policy

This project applies suppression at two levels:

1. **Project-level (`.psa.config.json`)**
   - **`PSAP0003`, `PSAP0004`, and `PSAP0005` are enabled.** The
     revision-discipline triad enforces the repository-wide
     CHANGELOG-centralised history policy:
     - `PSAP0003` catches inline revision-tag comments (`# r24:`,
       `# (r24)`, `# r24-update:`, etc.).
     - `PSAP0004` catches end-of-file `REVISION HISTORY` blocks.
     - `PSAP0005` (added in `psa.py` 4.0.0) catches the broader
       pattern of ANY `rNN` reference inside a comment body,
       including descriptive prose anchors that `PSAP0003`'s
       structured-tag detector misses. This project enables
       `PSAP0005` in **strict** mode (no `psap0005_relaxed_mode`
       key) because the r21 cleanup commit already removed every
       `rNN` reference from the script body; the strict baseline
       is the verified end-state, and there is no migration
       backlog requiring the relaxed-mode exemptions used by
       sister repositories.
   - `PSA6003` (plural function noun) is disabled. The three
     plural-noun functions in `Download-SpeakerDeck.ps1`
     (`Resolve-RuntimeDirectories`, `Invoke-CleanupDirectories`,
     `Read-YearOverrides`) intentionally describe collections, so renaming
     them would either misrepresent behaviour or break call sites. The
     rationale is documented inline in the config file.

2. **Inline (`# psa-disable-line PSA3004 -- <reason>`)**
   - All intentional empty `catch` blocks carry an inline suppression with
     a one-line justification. Categories covered:
     - Best-effort diagnostic capture where the retry/error path is driven
       by other state.
     - `foreach`-format / `foreach`-pattern loops where per-iteration
       failure correctly means "try the next candidate".
     - Cross-host compatibility shims (e.g., TLS enum values not present
       on older PowerShell hosts).

Any new suppression must include a justification comment naming the rule
code and the reason. Suppressions without a reason are not acceptable.

### When psa.py produces false positives

Common cases and their resolutions:

| False positive | Resolution |
|---|---|
| `PSA2001` "undefined variable" for `$Script:Foo` set in a different function | Initialize at script load: `$Script:Foo = $null` |
| `PSA2003` "-match against bare `$variable`" where `$variable` is guaranteed non-null | Wrap with `[string]::IsNullOrEmpty($variable)` guard, or refactor to `[regex]::Match()` |
| `PSA3004` (empty `catch`) intentional silent failure | Add `# psa-disable-line PSA3004 -- <reason>` |
| `PSA6003` plural noun in pre-existing function name | Already disabled at project level in `.psa.config.json` |

If `psa.py` systematically misclassifies a pattern, raise an issue upstream
in the analyzer's own repository rather than suppressing locally.

### Continuous Integration

This sub-project ships three GitHub Actions workflows under
`.github/workflows/` that automate the static-analysis gate plus
Windows-side verification. The workflows are:

| File | STAGE | Runner | Purpose |
|:---|:---|:---|:---|
| `scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml` | STAGE 1 | `ubuntu-latest` | `psa.py` text + SARIF analysis, plus PSScriptAnalyzer on PowerShell 7.x via `microsoft/psscriptanalyzer-action@v1` |
| `scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml` | STAGE 2 | `windows-latest` | PSScriptAnalyzer on Windows PowerShell 5.1, plus `-EnvironmentInfoOnly` smoke test |
| `scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml` | STAGE 3 | `windows-latest` | Full `-DryRun` execution (Phase 1–5 including Speaker Deck network access) on `release/published` or manual dispatch |

STAGE 1 chains to STAGE 2 via `workflow_run` (one hop, well within the
three-hop limit). STAGE 3 is independent of the chain and runs only on
release events or manual dispatch.

Both stages 1 and 2 use the project-local
`PSScriptAnalyzerSettings.psd1` (sibling file). That settings file
documents the six rules excluded project-wide with rationale for each;
per-occurrence exemptions are inline via
`[Diagnostics.CodeAnalysis.SuppressMessageAttribute(...)]` with a
Justification string. The expected output of either stage on a clean
tree is **zero findings** at all severities.

CI governance — design principles, naming conventions, timeout tiers,
fork-PR `if`-guards — is documented in the repository-root `SPEC.md`
at the top of the `ai-generated-artifacts` repository. Per-workflow
change history is recorded in this sub-project's
[`CHANGELOG.md`](./CHANGELOG.md).

The `-EnvironmentInfoOnly` switch (see §A.7 above) was added in r26
specifically to provide STAGE 2 with a quick, side-effect-free smoke
test that exercises script loading, parameter binding, and the Phase 1
Step 0 environment dump without proceeding to the registry / filesystem
checks (which require a Windows host with HKLM write access and a
writable working directory).

## A.12 Documentation Language Policy

This project follows the repository-wide documentation language policy
documented in the `ai-generated-artifacts` root [`README.md`](../../../README.md)
"Language Policy" section. Summary:

### File set

Every script (or script project, when placed inside a multi-script
repository) carries:

| File | Role | Languages maintained |
|---|---|---|
| `README.md` | English, primary documentation (master) | English **and** Japanese (`README.ja.md`) |
| `README.ja.md` | Japanese translation of `README.md`, kept in sync | (paired with `README.md`) |
| `SPEC.md` | Developer / LLM specification | **English only** |
| `TESTING.md` | Test procedures and verification results | **English only** |
| `CHANGELOG.md` (when one exists) | Per-version release notes | **English only** |

When the script lives inside a larger multi-script repository (e.g.,
`usui-tk/ai-generated-artifacts/scripts/powershell/<name>/`), the
`LICENSE` file lives at the repository root and is shared across all
scripts. When the script is its own standalone repo, place a `LICENSE`
file in the same directory.

### Synchronization rule (README only)

**Every script change that touches `README.md` must update `README.ja.md`
in the same commit.** The `Lines : NNNN` field in both files must match.
Don't translate machine-readable fields (paths, parameter names, version
strings) — only translate prose, headers, and explanatory text.

Other documents (`SPEC.md`, `TESTING.md`, `CHANGELOG.md`) are English
only and have no Japanese counterparts to synchronize.

**Every script change that touches `README.md` must update `README.ja.md`
in the same commit.** The `Lines : NNNN` field in both files must match.
Don't translate machine-readable fields (paths, parameter names, version
strings) — only translate prose, headers, and explanatory text.

### Style for `README.ja.md`

- Use 「全角コロン (：)」 in headers and table column descriptions
- Keep code blocks and parameter names in ASCII
- Match the section order and table layout exactly

### A.12.5 Mandatory disclaimer and license sections

Every README (both English and Japanese) MUST begin with two sections,
immediately after the one-line summary and language switcher:

1. **Disclaimer (`## ⚠️ Disclaimer` / `## ⚠️ 免責事項`)**
   - "AS IS" / no-warranty statement
   - Limitation of liability for damages (data loss, account suspension,
     bandwidth/storage costs, rate-limiting, IP blocks)
   - User-responsibility checklist: ToS compliance, IP rights respect,
     source code review before execution
   - "Operate considerately" appeal (do not bypass built-in throttling)

2. **License (`## License` / `## ライセンス`)**
   - State the license name (MIT by default for this script family)
   - Link to the `LICENSE` file at the repo root
   - One-paragraph summary of what users may do (use / modify / distribute)
     and what is required (preserve copyright + license notices)
   - Reiterate that the software is provided without warranty

A separate `LICENSE` file at the repo root contains the full MIT License
text (or whatever license is chosen). The boilerplate copyright header is:

```
MIT License

Copyright (c) <YEAR> <Project Name> contributors

Permission is hereby granted, ...
```

If the project chooses a different license (Apache 2.0, BSD-3-Clause,
GPL-3.0, etc.), the README sections still follow the same structure;
update the license name and one-paragraph summary to match.

## A.13 Development Workflow

### Iteration cycle

```
1. Write or modify code
2. Run psa.py — must be 0/0/0
3. Run with -DryRun first
4. Inspect plan CSVs
5. Run live
6. Inspect error JSONL + final state CSV
7. If new failure pattern found, update SPEC.md Part D
```

### Revision discipline

This project follows the repository-wide
[Revision History Policy](../../../README.md#revision-history-policy)
documented at the root of `ai-generated-artifacts`.

#### Version identifier

- Each meaningful change bumps the `-rNN` suffix in
  `$Script:ScriptVersion` / `$Script:ScriptTag`.
- The `ScriptTag` describes the change in 3-5 kebab-case words.
- Major refactors (e.g., phase renumbering) get their own revision.

#### Where revision history lives

Per-version release notes belong **exclusively** in [`CHANGELOG.md`](./CHANGELOG.md)
alongside `Download-SpeakerDeck.ps1` in this directory. Release notes
do NOT belong in:

- `Download-SpeakerDeck.ps1` source comments — neither inline
  revision-tag comments (`# rNN:`) nor end-of-file `REVISION HISTORY`
  blocks. The `psa.py` rules `PSAP0003` and `PSAP0004` (opt-in via
  `.psa.config.json`) detect this anti-pattern.
- `README.md` (other than a brief pointer to `CHANGELOG.md`).
- This `SPEC.md` (which describes *current* behaviour; historical
  context, when essential, goes in a dedicated section such as a
  Pitfalls / Lessons Learned appendix).

`CHANGELOG.md` follows the [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/)
format and is maintained in **English only** per the repository-wide
documentation language policy.

### Reuse before invention

When a new feature is needed, in order:

1. **Check the in-house reference script** (A.1.3) for the closest
   existing implementation. Copy and adapt.
2. **Only if it does not cover the case**, design from first principles
   — and document the new pattern in this SPEC so the next script can
   reuse it.

## A.14 Debug Trace Facility

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

# Part B — Script-Specific Specification (template)

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

- [ ] `python3 ../../python/powershell-static-analyzer/psa.py <script>.ps1` → 0 errors / 0 warnings / 0 info
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
     `scripts/python/powershell-static-analyzer/psa.py` (do not duplicate
     it into a per-script `tools/` folder)
4. Replace the phase bodies with the new script's logic.
5. Renumber phases starting from P01.
6. Fill in Part B template fields.
7. Run quality gates (Part C).
8. Update SPEC.md Part D if a new pitfall is discovered.

This document is itself versioned. Always check that the SPEC revision you
are reading matches the script revision you are working on.
