# powershell-static-analyzer

> 🇺🇸 English / 🇯🇵 [日本語](./README.ja.md)

A single-file Python 3 static analyzer for PowerShell scripts (`psa.py`).
Catches the classes of bugs that the regular PowerShell parser doesn't
flag at parse time, but which routinely break long-running scripts in
surprising ways.

This directory is the **single canonical source** of `psa.py`. All
consumers — both PowerShell scripts within this `ai-generated-artifacts`
repository and external repositories — reference this file rather than
maintaining their own copy.

For the formal specification (CLI contract, rule semantics, output
schemas, environment detection contract), see [`SPEC.md`](./SPEC.md).
This SPEC is maintained in English only per the repository-wide
documentation language policy; Japanese readers may use the Japanese
overview in [`README.ja.md`](./README.ja.md).

**Current version: 3.3.0**

---

## What's new

### 3.3.0 — Revision-discipline rules (PSAP0003, PSAP0004)

3.3.0 adds two opt-in PSAPxxxx rules that enforce the **"revision history lives in CHANGELOG.md, not in the script body"** discipline. Both are disabled by default and must be enabled per repository via `.psa.config.json`.

**New rules:**

- **`PSAP0003`** (warning, default OFF): inline revision-tag comments. Fires on `# rNN:`, `# rNN+:`, `# rNN-update:`, `# ---- rNN: ----` and `# (rNN) ...` patterns inside comments. Tags inside string literals and uses of `rNN` inside legitimate variables (e.g. `$Script:ScriptVersion = '...-r60'`) are left alone.
- **`PSAP0004`** (warning, default OFF): end-of-file `REVISION HISTORY` / `CHANGELOG` / `VERSION HISTORY` comment blocks. Fires once per matching header line; the operator's task is to relocate the content to the repository's `CHANGELOG.md`.

Both rules complement the existing PSAP0001 / PSAP0002 family and codify the discipline described in Deploy-Drivers-For-WindowsServer `SPEC.md` §A.13 ("Where revision history lives").

**No other rule semantics changed in 3.3.0.** Repositories that do not enable PSAP0003 / PSAP0004 see no behaviour difference vs 3.2.0.

### 3.2.0 — Cross-file consistency (PSA8xxx), complexity (PSA9xxx), project conventions (PSAPxxxx)

3.2.0 expands the analyzer in three orthogonal directions: **cross-file consistency checks**, **complexity metrics**, and a new **project / pipeline convention rule family**. It also rebuilds the string / comment tokenizer to fix a class of long-standing false positives.

**New rule families and rules:**

- **`PSA8xxx` — Cross-file consistency (new category)**
  - **`PSA8001`** (warning, default on, cross-file): function body hash drift across files in the same scan. When two or more files in the same `psa.py` invocation define a function with the same NAME but with different normalized bodies, every occurrence is flagged. The rule is silent on single-file invocations (no peers to compare against). New tunable: `psa8001_ignore_functions` (list of exact names and/or `regex:` patterns) to suppress drift reports for functions that are intentionally per-script.

- **`PSA9xxx` — Complexity metrics (new category)**
  - **`PSA9001`** (info, default OFF): function body exceeds `max_function_lines` (default 200). Opt-in; threshold is project-dependent.
  - **`PSA9002`** (warning, default OFF): external-process invocation (the `&` operator, `msiexec`, `signtool`, `inf2cat`, `pnputil`, `bcdedit`, `sc.exe`, `regsvr32`, `wevtutil`, `dism`, `gpupdate`, `certutil`, `reg.exe`, `cmd.exe`, `powershell`) without a `$LASTEXITCODE` / `$?` / `.ExitCode` / `-PassThru` reference within 5 lines after. Opt-in.

- **`PSAPxxxx` — Project / pipeline convention rules (new family)**
  - **All PSAPxxxx rules are disabled by default**; opt in via `.psa.config.json`. The PSAPxxxx family holds opinionated conventions tied to a specific pipeline style. The conventions shipped in 3.2.0 originated in the Deploy-Drivers-For-WindowsServer repository; other repositories can adopt them via the same opt-in mechanism.
  - **`PSAP0001`** (warning, default OFF): phase function naming convention `Invoke-(Prep|Verify|Inst)PhaseNN_DescriptiveName`.
  - **`PSAP0002`** (warning, default OFF): required script-identifier variables `$Script:ScriptVersion` / `$Script:ScriptHash` / `$Script:ScriptShortTag`.

**New generic rule in an existing category:**

- **`PSA3005`** (warning, default on): `Start-Transcript -Path` should be `-LiteralPath`. `Start-Transcript -Path` performs wildcard expansion on its argument; paths containing PowerShell metacharacters (`[`, `]`, backtick) are misinterpreted. `-LiteralPath` disables expansion and is the safer default.

**Tokenizer false-positive fixes (silent — no script-side change required):**

- **`PSA1001` (brace balance)**: the string tokenizer now correctly handles PowerShell's `""` (double-quote-doubling) escape AND the `` `` `` (double-backtick) escape. The previous implementation could mis-parse strings of the form `` "...`""..." `` or `` "...``\"..." ``, leaving the parser stuck in double-quoted-string state and consequently miscounting braces for the rest of the file.

- **`PSA2001` (undefined variable)**: the scope-qualifier set is extended to include `script`, `global`, `local`, and `private`. References of the form `$Script:Foo` are now treated as runtime-deferred (the author has explicitly declared a scope, so the analyzer respects that intent) and never produce false-positive "undefined variable" reports.

- **`PSA4001` (TODO/FIXME marker)**: the marker-matching now requires a colon or whitespace-then-letter after the marker, and ignores embedded string literals like `"XXX"` inside comments. Previously, comments mentioning marker words inside quoted strings produced spurious reports.

**New configuration tunables:**

- `max_function_lines` (int, default 200): threshold for PSA9001.
- `psa8001_ignore_functions` (list, default `[]`): suppress PSA8001 for the listed function names. Each entry is either an exact case-insensitive name match or a regex pattern prefixed with `regex:`.

### 3.1.0 — UTF-8 BOM enforcement (PSA7xxx category)

- **New rule category `PSA7xxx`** (file format / encoding) introduced
  for file-level checks that operate on raw bytes before UTF-8 decoding.
- **New rule `PSA7001` (warning, default on)**: PowerShell script
  lacks UTF-8 BOM. Windows PowerShell 5.1 falls back to the system
  Active Code Page (Shift-JIS / cp932 on ja-JP) when a `.ps1` file has
  no BOM and contains non-ASCII bytes, causing mojibake. Adding the
  three-byte UTF-8 BOM (`0xEF 0xBB 0xBF`) at the start of the file
  forces correct interpretation regardless of console code page.
- **`analyze_text()` signature** extended with optional `file_meta`
  parameter (backward compatible — existing callers passing only
  `(text, cfg)` are unaffected; PSA7xxx rules become no-ops).
- **`main()` file reader** switched from `path.read_text()` to
  `path.read_bytes()` so the BOM can be inspected before decoding
  (`read_text` silently strips BOM, defeating any in-text inspection).

### 2.3.0 — Hardened remote-config fetch

The `--config <URL>` code path is now production-grade:

- **Browser-like User-Agent** (Chrome 131) plus `Sec-Ch-Ua` client
  hints, so CDN / WAF defaults that block obvious bot UAs (notably
  Cloudflare-fronted sites) do not interfere.
- **Explicit TLS 1.2 minimum**, maximum auto-negotiated to TLS 1.3
  against modern servers. Old TLS 1.0/1.1 are not offered (RFC 8996).
  Certificate verification is always on.
- **Exponential-backoff retries** on transient failures, modelled on
  the `Invoke-WebRequestWithRetry` pattern from the companion
  PowerShell project:
  - 5xx responses → retry, waiting `2^attempt × 3` seconds (6 s, 12 s, …)
  - Network / timeout errors → retry, waiting `2^attempt` seconds (2 s, 4 s, …)
  - 4xx responses → fail immediately (persistent client error)
- **Env-var tuning** for CI flexibility:
  - `PSA_CONFIG_TIMEOUT` — per-attempt timeout (default 30s)
  - `PSA_CONFIG_MAX_RETRIES` — total attempts (default 3)
  - `PSA_CONFIG_QUIET` — suppress retry-progress messages on stderr

See [SPEC §5.4](./SPEC.md#54-remote-configuration-http--https) for the
full contract.

### 2.2.0 — JSONC configuration & remote config URLs

- **Configuration files are now JSONC.** Add `// line comments` and
  `/* block comments */` to `.psa.config.json` as freely as you would
  in JavaScript. Comment-like text inside string literals is preserved
  intact.
- **`--config` accepts URLs.** In addition to a local path, you can
  point `--config` at any http(s) URL — most commonly a GitHub raw URL
  for sharing a team-wide configuration:

  ```bash
  psa.py --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json <script>.ps1
  ```
- **Template file shipped.** A new file `.psa.config.json.template`
  ships next to `psa.py` in this directory.

### 2.1.0 — environment detection

Adds a runtime probe (`--check-env` / `--show-env`) that reports
whether PowerShell and PSScriptAnalyzer are available on the current
host. The output is purely informational; it never affects exit codes
or issue counts.

```
==== psa.py: Environment Detection ====
psa.py        : 2.2.0
Python        : 3.12.3 (Linux 6.18.5)
PowerShell    : pwsh 7.4.6 at /usr/bin/pwsh
PSScriptAnalyzer : 1.22.0 (available)

Info:
  PSScriptAnalyzer is available in this environment. For
  comprehensive PowerShell static analysis, consider running
  Microsoft's analyzer in addition to psa.py:

    pwsh -Command "Invoke-ScriptAnalyzer -Path <script>.ps1"
```

This is particularly useful for AI agents (Claude, etc.) and CI
sandboxes where the availability of PowerShell may vary per execution.
The probe is fast, side-effect-free, and bypasses user profiles
(`-NoProfile -NonInteractive`).

### 2.0.0 — rule-taxonomy overhaul

Version 2.0 is a major release inspired by Microsoft's
[PSScriptAnalyzer][PSScriptAnalyzer] and Vidar Holen's
[shellcheck][shellcheck]. It expanded the rule set to **27 rules**
and added JSON / SARIF output, inline suppression, configuration files,
and multi-file scanning — while preserving the single-file,
zero-dependency design.

| Area | Current |
|:---|:---|
| Rule codes | `PSA1001`–`PSA9002` plus `PSAP0001`–`PSAP0004` (36 rules total) |
| Output formats | Text / JSON / SARIF 2.1.0 |
| Suppression | `# psa-disable-line`, `next-line`, `file` |
| Configuration | `.psa.config.json` + CLI |
| File handling | Multiple files / directories / glob |
| Color output | TTY-aware ANSI (NO_COLOR honored) |
| Heredoc / sub-expr | Full `@"…"@`, `@'…'@`, `$()`, `@()` |

[PSScriptAnalyzer]: https://github.com/PowerShell/PSScriptAnalyzer
[shellcheck]: https://github.com/koalaman/shellcheck

---

## Origin & maintenance policy

`psa.py` originated in
[`usui-tk/Deploy-AMD-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer)
under `tools/psa.py`. It was subsequently consolidated into this
`ai-generated-artifacts` repository as the **single canonical source**,
and the original copy under `tools/psa.py` in the
`Deploy-AMD-Drivers-For-WindowsServer` repository was removed. That
repository now references `psa.py` here as an external dependency (see
its [SPEC §A.11](https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/blob/main/SPEC.md#a11-static-analysis-with-psapy)).

**All bug fixes, new checks, and auto-variable list updates must be made
here.** Consumer repositories pull `psa.py` either by `git clone` of
this repository or by single-file download of the raw blob (see Usage
below). No downstream forks are maintained.

---

## Why a custom analyzer?

Microsoft ships [PSScriptAnalyzer][PSScriptAnalyzer], which is excellent
and should be used too. But PSScriptAnalyzer has two limitations:

1. It requires PowerShell 5.1+ to run (chicken-and-egg if your CI
   doesn't have Windows / PowerShell yet).
2. It catches a different set of issues — primarily style and
   best-practice violations. It does **not** by default catch unbalanced
   braces in thousand-line scripts, undefined variable references that
   are typos, or `-match` against a bare `$variable` that returns true
   on `$null`.

`psa.py` is a Python script (running anywhere Python 3 runs) that
performs a complementary set of checks. It is not a drop-in replacement
for PSScriptAnalyzer; it is an extra net, designed to run in CI
pipelines that don't have PowerShell available.

---

## Prerequisites

- Python 3.8 or newer
- Standard library only — **no external dependencies**
- A `.ps1` or `.psm1` file to analyze

---

## Usage

```bash
# Analyze a single script
python3 scripts/python/powershell-static-analyzer/psa.py path/to/script.ps1

# Multiple files / glob
python3 scripts/python/powershell-static-analyzer/psa.py *.ps1

# Recursive directory scan (PS1 + PSM1)
python3 scripts/python/powershell-static-analyzer/psa.py -r ./scripts

# JSON output (machine-readable)
python3 scripts/python/powershell-static-analyzer/psa.py --format json script.ps1

# SARIF output (for GitHub Code Scanning / IDE plugins)
python3 scripts/python/powershell-static-analyzer/psa.py --format sarif script.ps1 > result.sarif

# Filter by severity
python3 scripts/python/powershell-static-analyzer/psa.py --severity error script.ps1

# Enable a disabled-by-default rule
python3 scripts/python/powershell-static-analyzer/psa.py --enable PSA6002 script.ps1

# Disable a specific rule
python3 scripts/python/powershell-static-analyzer/psa.py --disable PSA2001 script.ps1

# Run only a specific subset of rules
python3 scripts/python/powershell-static-analyzer/psa.py --include PSA1001,PSA1002 script.ps1

# Use an explicit configuration file (local path)
python3 scripts/python/powershell-static-analyzer/psa.py --config .psa.config.json script.ps1

# Use a remote configuration file (http(s) URL — GitHub raw recommended)
python3 scripts/python/powershell-static-analyzer/psa.py \
        --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json script.ps1

# Print the rule catalog
python3 scripts/python/powershell-static-analyzer/psa.py --list-rules

# Detect PowerShell / PSScriptAnalyzer availability (informational)
python3 scripts/python/powershell-static-analyzer/psa.py --check-env

# Prepend environment summary to normal analysis output (informational)
python3 scripts/python/powershell-static-analyzer/psa.py --show-env script.ps1
```

### Exit codes

| Code | Meaning |
|:---:|:---|
| `0` | Clean (no errors, no warnings) |
| `1` | Warnings only (CI may treat as soft-fail) |
| `2` | Errors found (CI must fail) |

---

## Output format (text)

```
==== psa.py: PowerShell Static Analyzer ====
File   : path/to/script.ps1
Lines  : 4106
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

When issues are present:

```
==== psa.py: PowerShell Static Analyzer ====
File   : path/to/script.ps1
Lines  : 8792
Issues : 1 errors, 42 warnings, 31 info

---- ERROR (1) ----
  [PSA5001] line   499:  5: plain-text password parameter $PfxPassword;
                                use [SecureString] or [PSCredential]

---- WARNING (42) ----
  [PSA3004]            line  1076     : empty catch block
  [PSA2003]            line  2337: 22: -match against bare $noisePattern ...
  [PSA3001]            line  2422     : Start-Process -ArgumentList; ...
  ...
```

Each issue contains the `PSAxxxx` code, the severity, the line and
optional column, and a short message.

---

## Rule catalog

`PSA1xxx` — parse / structural checks (always Error)

| Code | Default | Description |
|:---|:---:|:---|
| **PSA1001** | ✅ on | Brace balance: `{` count vs `}` count |
| **PSA1002** | ✅ on | Paren balance: `(` vs `)` |
| **PSA1003** | ✅ on | Bracket balance: `[` vs `]` |

`PSA2xxx` — variable / scope (Error / Warning)

| Code | Sev | Default | Description |
|:---|:---:|:---:|:---|
| **PSA2001** | Error | ✅ on | Undefined variable reference (heuristic) |
| **PSA2002** | Warning | ✅ on | Auto-variable shadowing (`$args`, `$matches`, …) |
| **PSA2003** | Warning | ✅ on | `-match` against bare `$variable` |
| **PSA2004** | Warning | ✅ on | `$x -eq $null` (use `$null -eq $x` to avoid the collection trap) |
| **PSA2005** | Warning | ✅ on | Assignment operator (`=`) inside `if` / `while` |
| **PSA2006** | Warning | ✅ on | Redirection operator (`>` / `<`) inside `if` / `while` |

`PSA3xxx` — coding patterns (Warning)

| Code | Default | Description |
|:---|:---:|:---|
| **PSA3001** | ✅ on | `Start-Process -ArgumentList`; prefer `ProcessStartInfo` |
| **PSA3002** | ✅ on | Backtick continuation followed by an empty line |
| **PSA3003** | ✅ on | `-match` against literal empty string |
| **PSA3004** | ✅ on | Empty `catch { }` block |
| **PSA3005** | ✅ on | `Start-Transcript -Path`; prefer `-LiteralPath` for paths containing `[`, `]`, or other wildcard metacharacters (new in 3.2.0) |

`PSA4xxx` — style / informational (Info)

| Code | Default | Description |
|:---|:---:|:---|
| **PSA4001** | ✅ on | Unfinished marker (TODO / FIXME / XXX / HACK) |
| **PSA4002** | ✅ on | Trailing whitespace at end of line |
| **PSA4003** | ⛔ off | Long line exceeds `max_line_length` (default 120) |
| **PSA4004** | ✅ on | Trailing semicolon at end of line |

`PSA5xxx` — security (Error / Warning)

| Code | Sev | Default | Description |
|:---|:---:|:---:|:---|
| **PSA5001** | Error | ✅ on | Plain-text password parameter (`[string]$Password`) |
| **PSA5002** | Warning | ✅ on | `Invoke-Expression` usage |
| **PSA5003** | Warning | ✅ on | Broken hash algorithm (MD5 / SHA1) |
| **PSA5004** | Warning | ✅ on | Hardcoded `ComputerName` (literal string) |

`PSA6xxx` — best-practice (Warning)

| Code | Default | Description |
|:---|:---:|:---|
| **PSA6001** | ✅ on | Function uses non-approved verb (cf. `Get-Verb`) |
| **PSA6002** | ⛔ off | Cmdlet alias used (`ls`, `cd`, `dir`, `where`, …) |
| **PSA6003** | ✅ on | Function noun should be singular |
| **PSA6004** | ✅ on | Avoid `$global:` variable definition |
| **PSA6005** | ✅ on | Mandatory parameter must not have a default value |
| **PSA6006** | ✅ on | Switch parameter must not default to `$true` |

`PSA7xxx` — file format / encoding (Warning)

| Code | Sev | Default | Description |
|:---|:---:|:---:|:---|
| **PSA7001** | Warning | ✅ on | PowerShell script lacks UTF-8 BOM (Windows PowerShell 5.1 may misinterpret non-ASCII as Shift-JIS without BOM) |

`PSA8xxx` — cross-file consistency (Warning) — new in 3.2.0, cross-file

| Code | Default | Description |
|:---|:---:|:---|
| **PSA8001** | ✅ on (silent on single-file invocations) | Function body hash drift across files: when the same function name appears in two or more files in the same scan with different normalized bodies, every occurrence is flagged. Suppress per-function via `psa8001_ignore_functions` (exact names and/or `regex:` patterns). |

`PSA9xxx` — complexity metrics — new in 3.2.0

| Code | Sev | Default | Description |
|:---|:---:|:---:|:---|
| **PSA9001** | Info | ⛔ off | Function body exceeds `max_function_lines` (default 200) |
| **PSA9002** | Warning | ⛔ off | External-process invocation (`&` op or `msiexec` / `signtool` / `inf2cat` / `pnputil` / `bcdedit` / etc.) without a `$LASTEXITCODE` / `$?` / `.ExitCode` / `-PassThru` check within 5 lines |

`PSAPxxxx` — project / pipeline convention rules — new family in 3.2.0, **all default OFF**

| Code | Sev | Default | Description |
|:---|:---:|:---:|:---|
| **PSAP0001** | Warning | ⛔ off (opt-in) | Phase function naming convention: `Invoke-(Prep\|Verify\|Inst)PhaseNN_DescriptiveName`. Fires only on functions whose names start with `Invoke-(Prep\|Verify\|Inst\|Phase\|Pipeline)` but do not match the canonical regex. |
| **PSAP0002** | Warning | ⛔ off (opt-in) | Required script-identifier variables: `$Script:ScriptVersion`, `$Script:ScriptHash`, `$Script:ScriptShortTag`. One PSAP0002 emitted per missing identifier. |

### Why some rules are disabled by default

Two generic rules are off by default to keep the signal-to-noise ratio high on
real-world scripts:

- **PSA4003 (long line)** — line-length is mostly stylistic and very
  context-dependent (comment headers, long URLs, ARN-like strings).
  Enable per project when you have agreed on a length limit.
- **PSA6002 (cmdlet alias)** — many production scripts use `foreach`
  and `where` deliberately. Enable when your style guide forbids
  aliases.

Use `--enable PSA6002` on the command line or add it to your
`.psa.config.json` `enable` list.

---

## What the analyzer does NOT check

- Cmdlet existence (would require a PowerShell session)
- Type correctness (PowerShell is dynamically typed)
- Module imports (`Import-Module` resolution)
- Best-practice style violations covered by PSScriptAnalyzer that need
  AST analysis (e.g., `PSUseConsistentIndentation`, `PSUseCorrectCasing`)

---

## Inline suppression

Per-line:

```powershell
$x -match $pattern  # psa-disable-line PSA2003
```

Next line:

```powershell
# psa-disable-next-line PSA3001,PSA3002
Start-Process -ArgumentList $args ...
```

Whole file (place anywhere, typically near the top):

```powershell
# psa-disable-file PSA4001
```

---

## Configuration file (`.psa.config.json`)

When run from a directory containing `.psa.config.json`, `psa.py` picks
it up automatically. Use `--config PATH_OR_URL` for an explicit file
or a remote one (see "Remote configuration" below).

Configuration files are **JSONC** — JSON plus `//` line comments and
`/* */` block comments.

```jsonc
{
  // Enable rules that are off by default
  "enable":  ["PSA6002"],

  // Disable rules that are on by default
  "disable": ["PSA4001"],

  // Minimum severity to report: "error", "warning", or "info"
  "severity": "warning",

  // Line-length limit for PSA4003
  "max_line_length": 120
}
```

### Template file

A template named [`.psa.config.json.template`](./.psa.config.json.template)
ships in this directory. It documents every option with its built-in
default value, all commented out. Copy it to bootstrap your own
configuration:

```bash
cp scripts/python/powershell-static-analyzer/.psa.config.json.template \
   .psa.config.json
# then uncomment only what you want to override
```

### Remote configuration (HTTP / HTTPS)

`--config` accepts an http(s) URL as well as a local path. This is
ideal for sharing a team-wide configuration stored in a GitHub
repository — use the **raw** URL form:

```bash
psa.py --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json <script>.ps1
```

**Robustness features (since 2.3.0):**

- Sends a Chrome-131 User-Agent + Sec-Ch-Ua client hints, so the
  request passes CDN/WAF default filters that reject obvious bots.
- Builds an explicit TLS 1.2-minimum SSL context; maximum auto-
  negotiated up to TLS 1.3. Certificate verification is always on.
- Retries on 5xx and network errors with exponential backoff
  (6s → 12s → 24s for server errors; 2s → 4s → 8s for network errors).
  4xx responses fail immediately.
- Tunable via env vars: `PSA_CONFIG_TIMEOUT` (default 30s),
  `PSA_CONFIG_MAX_RETRIES` (default 3), `PSA_CONFIG_QUIET`.

Use `raw.githubusercontent.com/...`, NOT the blob URL
(`github.com/.../blob/...`) — the latter returns HTML.

Fetched content is not cached by `psa.py`; each invocation hits the
URL. See [SPEC §5.4](./SPEC.md#54-remote-configuration-http--https)
for the full contract.

### Resolution order (lowest priority → highest priority)

1. Built-in defaults
2. `.psa.config.json` (implicit search) OR `--config` (explicit, local
   or URL)
3. CLI flags (`--enable`, `--disable`, `--include`, `--severity`,
   `--max-line-length`)
4. Inline suppression comments

---

## CI integration example

GitHub Actions workflow snippet (Linux runner, no Windows / PowerShell
required):

```yaml
name: Lint
on: [push, pull_request]

jobs:
  static-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - name: Run psa.py
        run: |
          python3 scripts/python/powershell-static-analyzer/psa.py -r \
                  --format sarif scripts/ > psa.sarif
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: psa.sarif
```

For a minimal text-only run that fails the build on errors only:

```yaml
      - name: Run psa.py (errors only)
        run: |
          python3 scripts/python/powershell-static-analyzer/psa.py \
                  --severity error \
                  scripts/powershell/download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1
```

---

## Running PSScriptAnalyzer alongside

If you have PowerShell 5.1+ available, run both for the best coverage:

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path path/to/script.ps1 -Severity Warning,Error
```

`psa.py` and PSScriptAnalyzer have complementary, mostly non-overlapping
checks; the rules they share (e.g., empty-catch detection) usually
agree.

---

## Adding a new check

The structure of `psa.py` is intentionally minimal. To add a new check
`PSA7001`:

1. Add an entry to the `RULES` tuple list at the top of `psa.py`
   (code, severity, default-enabled, message).
2. Write a `check_yourthing(text|clean)` function that returns a list of
   dicts with keys `severity`, `code`, `line`, `col`, `message`.
3. Call it from `analyze_text()` guarded by
   `if cfg.enabled['PSA7001']:`.
4. Document the new code in the rule catalog above and in
   `README.ja.md`.
5. Notify downstream consumer repositories (e.g.,
   [`Deploy-AMD-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer))
   so they can update their own SPEC / README check tables to match.

The `strip_strings_and_comments(text)` helper is the standard preamble
for any check that wants to ignore content inside `''`, `""`,
`@'…'@`, `@"…"@`, `# …`, and `<# … #>` — use it.

**Reminder:** This directory is the **single canonical source** for
`psa.py`. All changes are made here; downstream consumers pull the
updated file rather than maintaining their own copies.

---

## Verified consumers

The following repositories and PowerShell scripts are verified with
`psa.py` (this canonical source).

### Within this repository

| Script | Path |
|:---|:---|
| `Download-SpeakerDeck.ps1` | [`scripts/powershell/download-speakerdeck-oracle4engineer/`](../../powershell/download-speakerdeck-oracle4engineer/) |
| `Test-PdfMetadata.ps1` | [`scripts/powershell/download-speakerdeck-oracle4engineer/`](../../powershell/download-speakerdeck-oracle4engineer/) |

### External repositories

| Repository | Scripts | Reference |
|:---|:---|:---|
| [`usui-tk/Deploy-AMD-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer) | `Deploy-AMDChipsetDriverOnWindowsServer.ps1`, `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`, `Deploy-AMDNpuDriverOnWindowsServer.ps1` | [SPEC §A.11](https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/blob/main/SPEC.md#a11-static-analysis-with-psapy) |

(Update this list when new PowerShell scripts — internal or external —
adopt `psa.py` for verification.)

---

## Design philosophy

- **Single file, standard library only.** No `pip install`, no virtual
  environment, no version conflicts. Drop `psa.py` anywhere Python 3
  runs.
- **Conservative on false positives.** A static analyzer that cries
  wolf gets ignored. When in doubt, a rule is disabled by default and
  the user opts in.
- **PowerShell-aware tokenizer.** Heredocs (`@"…"@`, `@'…'@`),
  sub-expressions (`$()`, `@()`), and the `$env:` / `$using:` scopes
  are handled correctly so that downstream regex rules see only
  meaningful code.

---

## License

`psa.py` is released under the same MIT License as the rest of this
repository. See the [`LICENSE`](../../../LICENSE) at the repository
root.
