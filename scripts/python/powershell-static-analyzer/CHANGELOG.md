# Changelog

All notable changes to `psa.py` (the PowerShell static analyzer in this
directory) are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/).
For the public-API scope governed by SemVer (the CLI surface, rule
code names, JSON / SARIF output schemas, configuration file schema),
see [SPEC.md §1.4 Versioning](./SPEC.md#14-versioning).

This CHANGELOG covers `psa.py` only. For higher-level repository-wide
changes (documentation policy, sister scripts, etc.), see the root
[`README.md`](../../../README.md) of `ai-generated-artifacts`.

## [Unreleased]

### Added

- **GitHub Actions CI workflow enforcing the three self-quality gates
  on every push and pull request.** New workflow:
  `.github/workflows/scripts__python__powershell-static-analyzer.yml`.
  - Pillar 1 (`pytest test_psa_rules.py`) — runs the full rule
    self-test suite that ships in this directory.
  - Pillar 2 (`python3 psa.py --config-check .psa.config.json.template`)
    — validates the shipped configuration template against the
    documented schema.
  - Pillar 3 (`python3 psa.py --self-check`) — verifies that
    `SPEC.md` §4 rule headings agree with the runtime RULES table.
  - Triggers: push / pull_request on `main` when `psa.py`, `VERSION`,
    `test_psa_rules.py`, `SPEC.md`, `.psa.config.json.template`, or
    the workflow file itself changes; plus `workflow_dispatch`.
  - Timeout tier: T1 (30 minutes) per repository-root `/SPEC.md`
    §4.1. Fork-PR `if`-guard per `/SPEC.md` §5.
- **`SPEC.md` §12.6 *Continuous Integration in this repository*.**
  A new subsection that records where the CI workflow lives and
  points to repository-root `/SPEC.md` for governance. The four
  normative subsections §12.1–§12.4 and the informative §12.5 are
  unchanged.
- **CI status badge** in `README.md` and `README.ja.md` immediately
  after the title.

### Changed

- **Documentation: cross-link to consumer-side adoption of the
  self-quality gates.** Following the verified consumer
  [`usui-tk/Deploy-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)
  publishing its own SPEC §A.11.6 *Self-quality gates for `psa.py`
  (consumer-side usage)*, the upstream documentation in this
  directory gained the reciprocal cross-references:
   - `SPEC.md` §12 gained a new (informative, non-normative)
     subsection §12.5 *Consumer-side adoption* that records how
     `--config-check` (§12.2) and `--self-check` (§12.3) are wired
     into a downstream repository's workflow, with a direct link
     to the verified consumer's §A.11.6. The four normative
     subsections §12.1–§12.4 are unchanged; §12.5 is purely a
     pointer to where to read the downstream half of the story.
   - `README.md` and `README.ja.md` *Verified consumers* table
     entry for `Deploy-Drivers-For-WindowsServer` now lists all
     four pipeline scripts (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`,
     `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`,
     `Deploy-AMDNpuDriverOnWindowsServer.ps1`,
     `Deploy-MSBthPanInboxOnWindowsServer.ps1`) — the BthPan script
     was previously omitted — and the Reference column now links
     both to SPEC §A.11 (analyzer setup, version policy, baseline)
     and to SPEC §A.11.6 (consumer-side `--config-check` /
     `--self-check` adoption), giving readers a single hop from
     the upstream consumer list to the downstream usage docs.
- `psa.py` itself, `test_psa_rules.py`, `VERSION`, and the
  `.psa.config.json.template` are unchanged. The three
  self-quality gates remain at the 3.5.1 baseline (104 test cases
  pass, `--self-check` green, `--config-check` clean against the
  shipped template).

## [3.5.1] — 2026-05-19

### Fixed

- **`PSA5004` (Hardcoded `ComputerName`) now actually fires.** The
  rule's regular expression matches the pattern `-ComputerName
  "literal"` (or single-quoted), but `analyze_text()` was passing
  it the output of `strip_strings_and_comments()` — where every
  string literal is collapsed to whitespace — so the rule could
  never observe its intended trigger. The function was changed to
  accept BOTH the raw `text` and the stripped `clean` form
  (matching the existing two-argument pattern used by
  `check_balance(text, clean, ...)` and other rules):

   - The regex now scans the raw `text`, so the string literal is
     visible and its host value can be reported.
   - The matched span is then validated against the same range in
     `clean`: the bareword `-ComputerName` survives the stripper
     when it appears as actual code, but is blanked when it
     appears inside a comment or another string literal. This
     position-based cross-check (sound because
     `strip_strings_and_comments()` preserves character positions
     one-to-one) correctly suppresses three classes of false
     positives:

      - `# Invoke-Command -ComputerName "server01"` (in comments)
      - `$cmd = "Invoke-Command -ComputerName \"server01\""` (in
        outer string literals)
      - `$msg = "Use -ComputerName 'foo' carefully"` (in any other
        string literal that happens to contain the keyword)

  The whitelisted hosts (`localhost`, `.`, `127.0.0.1`) and the
  variable-argument negative case (`-ComputerName $target`)
  continue to be silent. SPEC.md §4.21 already specified this
  behaviour; the implementation was lagging.

- `test_psa_rules.py` PSA5004 coverage was expanded from the
  3.5.0 baseline-locking pair (which pinned the buggy
  non-firing behaviour) to 10 cases that exercise positive
  detection, the three whitelist values, both quote styles,
  case-insensitive matching, and the three false-positive
  defences listed above.

### Notes — verification

- All four `Deploy-Drivers-For-WindowsServer` pipeline scripts
  (Chipset / Graphics / NPU / MSBthPan) remain at the 0 / 0 / 0
  baseline under `psa.py 3.5.1`, both with the
  repository-shipped `.psa.config.json` and under `--include
  PSA5004` (which forces PSA5004 even though it is on by
  default). Manually re-verified: none of the four scripts
  contains a hardcoded `-ComputerName` literal in code paths.

- The three self-quality gates (`test_psa_rules.py`,
  `--self-check`, `--config-check`) all exit `0` on the 3.5.1
  mainline tree. The Pillar 1 suite runs 104 test cases at this
  baseline (96 per-rule + 3 PSA8001 cross-file + 5 CLI
  self-quality, an increase of 8 from the 3.5.0 baseline of 96
  total — entirely the new PSA5004 positive / whitelist / edge
  fixtures).

## [3.5.0] — 2026-05-19

### Added

- **`--config-check PATH_OR_URL`**: validate the schema of a
  `.psa.config.json` (JSONC) file or http(s) URL and exit. The check
  reports unknown top-level keys, unknown rule IDs in `enable` /
  `disable`, `enable` ↔ `disable` conflicts, bad `severity` values,
  non-positive integers for `max_line_length` / `max_function_lines`,
  type errors throughout, and uncompilable regex patterns in
  `psa8001_ignore_functions`. Every problem is enumerated; the
  checker continues to the end rather than stopping at the first
  violation, so a single CI run sees the full picture. Exits `0` on
  a clean config, `2` on any error. (Pillar 2 of the self-quality
  gate design — see SPEC.md §12.2.)

- **`--self-check`**: verify that the sibling `SPEC.md`'s rule
  catalog (every `### 4.N PSAxxxx — Title` heading in §4) matches
  the `RULES` table compiled into the running `psa.py`. The check
  is symmetric — both "documented in SPEC.md but missing from
  RULES" and "in RULES but missing from SPEC.md" are reported. The
  `### 4.32 PSAPxxxx — Project / pipeline convention rules` overview
  heading (an ID-less grouping heading covering §4.33–§4.36) is
  explicitly skipped by the parser. Exits `0` on agreement, `2` on
  drift detected, or `2` if `SPEC.md` cannot be read. (Pillar 3 of
  the self-quality gate design — see SPEC.md §12.3.)

- **`test_psa_rules.py`**: full-catalog regression suite replacing
  `test_psap_3_4.py`. Ships fixtures for every rule in the `RULES`
  table (positive + negative + edge cases per rule), plus PSA8001
  cross-file fixtures driven through `collect_function_bodies()` /
  `check_function_sync()`, plus subprocess-driven CLI assertions
  for `--config-check` and `--self-check` (including dynamically
  created broken configs in a tempdir). 96 test cases at the 3.5.0
  baseline, no third-party dependencies (`python3
  test_psa_rules.py`). (Pillar 1 of the self-quality gate design —
  see SPEC.md §12.1.)

- **SPEC.md §12 "Self-quality gates"**: new normative section
  describing the three pillars (Pillar 1 / Pillar 2 / Pillar 3),
  the design principle that the implementation lives inside `psa.py`
  (not in the test suite) so consumers and CI exercise identical
  code paths, and the release-process checklist that all three
  commands (`test_psa_rules.py`, `--self-check`, `--config-check`)
  must exit `0` on the mainline before a version is tagged.

### Changed

- **`SPEC.md` §3 (Command-line interface)** updated:
   - §3.1 synopsis adds the two new short-form invocations.
   - §3.3 options table adds rows for `--config-check` and
     `--self-check`.
   - New §3.6 documents `--config-check` (categories reported,
     short-circuit semantics: it does NOT read the implicit
     `./.psa.config.json` and runs before `Config.load()` so a
     broken config can still be diagnosed).
   - New §3.7 documents `--self-check` (which §4 headings are
     scanned, which is skipped, and the exit-code contract).

- **`ANSI_GRN`** colour constant added to the small ANSI palette
  used by terminal output, so `--config-check` and `--self-check`
  can show a green "all good" line in addition to the existing red
  / yellow severity colours.

### Notes — known limitation not addressed in this release

- **`PSA5004` (Hardcoded `ComputerName`) is currently a no-op in
  the standard pipeline.** While auditing rule coverage for the
  new test suite, the maintainer observed that
  `check_hardcoded_computername()` matches against a quoted string
  literal, but `analyze_text()` passes it the output of
  `strip_strings_and_comments()` (where every string literal is
  collapsed to whitespace). The rule therefore never fires on its
  intended pattern. `test_psa_rules.py` pins the current (silent)
  behaviour with a baseline test so any future fix is flagged as
  an intentional behaviour change rather than a silent regression.
  This pre-existing gap has not affected the
  `Deploy-Drivers-For-WindowsServer` sister-repository scripts:
  none of the four pipeline scripts contains a hardcoded
  `-ComputerName` literal. Fixing the rule is tracked separately
  and will land in a future release. **(Update: fixed in 3.5.1 —
  see the entry above.)**

## [3.4.0] — 2026-05-19

### Added

- **`VERSION` file** alongside `psa.py` in the same directory. Contains
  a single ASCII line with the current SemVer (no leading `v`, no
  trailing whitespace beyond the terminating newline). This file is
  the **canonical bytes-only carrier** of the analyzer version,
  consumable without invoking Python:

  ```bash
  curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION
  # → 3.4.0
  ```

  This enables AI / LLM-driven and CI workflows to discover the
  current mainline version of `psa.py` cheaply (one HTTP GET,
  no git clone, no Python interpreter required) before deciding
  whether to refresh a locally-cached copy.

- **Startup self-check**: when `psa.py` runs and the `VERSION` file
  is present in the same directory, the analyzer verifies that the
  string in `VERSION` matches `__version__` inside `psa.py`. On
  mismatch it writes a structured warning to stderr containing
  explicit AI / LLM-facing action items (re-fetch the latest
  `psa.py` + `VERSION` pair, re-run the affected PowerShell test
  suites, re-evaluate `.psa.config.json` `enable` lists against
  the latest `SPEC.md`). Analysis still proceeds — results are
  flagged provisional in the warning text but the exit code is
  unchanged. The check is suppressed for `--list-rules` and
  `--check-env` (purely informational modes) and is a silent
  no-op when `VERSION` is absent (the supported single-file
  consumer pattern remains fully compatible).

### Changed

- Documentation throughout the `ai-generated-artifacts` repository
  no longer references a fixed `psa.py` version (e.g. "psa.py
  3.3.0"). Consumers are directed to fetch the latest mainline
  via the `VERSION` file and to re-evaluate their `.psa.config.json`
  whenever the version changes. See repository-root `README.md`
  "psa.py Versioning Policy" for the canonical workflow.

### Notes

- This is a **non-breaking** minor bump. All `3.3.0` rules,
  CLI flags, output formats, and configuration schemas are
  preserved unchanged. The `VERSION` file is additive; the
  startup self-check is additive and produces no behaviour
  change in the matching-version case. Existing consumers that
  copied `psa.py` as a single file without sibling metadata
  continue to work unchanged (no `VERSION` file → no warning).

## [3.3.0] — 2026-05-18

### Added

- **`PSAP0003`** (warning, default OFF, opt-in via `.psa.config.json`):
  inline revision-tag comments. Fires on `# rNN:`, `# rNN+:`,
  `# rNN-update:`, `# ---- rNN: ----`, and `# (rNN) ...` patterns
  inside comments. Tags inside string literals and uses of `rNN`
  inside legitimate variables (e.g. `$Script:ScriptVersion = '...-r60'`)
  are left alone.
- **`PSAP0004`** (warning, default OFF, opt-in via `.psa.config.json`):
  end-of-file `REVISION HISTORY` / `CHANGELOG` / `VERSION HISTORY`
  comment blocks. Fires once per matching header line.
- New `test_psap_3_4.py` self-test fixture (18 cases) verifying both
  rules against positive matches, negative cases (prose mentions,
  string-literal contents, here-strings), and edge combinations.

### Implementation

Both rules share a dedicated PowerShell tokeniser
(`_comment_start_positions`) that classifies every `#` in the input
as comment-start vs in-string vs in-here-string vs in-block-comment.
This is more precise than relying on `strip_strings_and_comments()`
alone because string contents and comment contents are both stripped
to spaces in the latter, making them indistinguishable by position.

### Rationale

Both rules enforce the **"revision history lives in CHANGELOG.md, not
in the script body"** discipline. They complement the existing
PSAP0001 / PSAP0002 family and codify the discipline described in
[Deploy-Drivers-For-WindowsServer `SPEC.md` §A.13](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/blob/main/SPEC.md)
("Where revision history lives").

### Notes

- No other rule semantics changed in 3.3.0. Repositories that do not
  enable `PSAP0003` / `PSAP0004` see no behaviour difference vs 3.2.0.

## [3.2.0] — 2026-05-17

### Added

- **`PSA8xxx` — Cross-file consistency** (new rule category)
  - **`PSA8001`** (warning, default ON, cross-file): function body
    hash drift across files in the same scan. When two or more files
    in the same `psa.py` invocation define a function with the same
    NAME but with different normalized bodies, every occurrence is
    flagged. The rule is silent on single-file invocations (no peers
    to compare against).
  - New tunable `psa8001_ignore_functions` (list of exact names and/or
    `regex:` patterns) to suppress drift reports for functions that
    are intentionally per-script.
- **`PSA9xxx` — Complexity metrics** (new rule category)
  - **`PSA9001`** (info, default OFF): function body exceeds
    `max_function_lines` (default 200). Opt-in; threshold is
    project-dependent.
  - **`PSA9002`** (warning, default OFF): external-process invocation
    (the `&` operator, `msiexec`, `signtool`, `inf2cat`, `pnputil`,
    `bcdedit`, `sc.exe`, `regsvr32`, `wevtutil`, `dism`, `gpupdate`,
    `certutil`, `reg.exe`, `cmd.exe`, `powershell`) without a
    `$LASTEXITCODE` / `$?` / `.ExitCode` / `-PassThru` reference
    within 5 lines after.
- **`PSAPxxxx` — Project / pipeline convention rules** (new rule
  family — **all disabled by default**; opt in via `.psa.config.json`)
  - **`PSAP0001`** (warning, default OFF): phase function naming
    convention `Invoke-(Prep|Verify|Inst)PhaseNN_DescriptiveName`.
  - **`PSAP0002`** (warning, default OFF): required script-identifier
    variables `$Script:ScriptVersion` / `$Script:ScriptHash` /
    `$Script:ScriptShortTag`.

  The `PSAPxxxx` family holds opinionated conventions tied to a
  specific pipeline style. The conventions shipped in 3.2.0 originated
  in the [Deploy-Drivers-For-WindowsServer](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)
  repository; other repositories can adopt them via the same opt-in
  mechanism.
- **`PSA3005`** (warning, default ON): `Start-Transcript -Path` should
  be `-LiteralPath`. `Start-Transcript -Path` performs wildcard
  expansion on its argument; paths containing PowerShell metacharacters
  (`[`, `]`, backtick) are misinterpreted. `-LiteralPath` disables
  expansion and is the safer default.
- New configuration tunables:
  - `max_function_lines` (int, default 200): threshold for PSA9001.
  - `psa8001_ignore_functions` (list, default `[]`): suppress PSA8001
    for the listed function names.

### Fixed

- **`PSA1001` (brace balance)**: the string tokenizer now correctly
  handles PowerShell's `""` (double-quote-doubling) escape AND the
  `` `` `` (double-backtick) escape. The previous implementation could
  mis-parse strings of the form `` "...`""..."` `` or
  `` "...``\"..."` ``, leaving the parser stuck in
  double-quoted-string state and consequently miscounting braces for
  the rest of the file.
- **`PSA2001` (undefined variable)**: the scope-qualifier set is
  extended to include `script`, `global`, `local`, and `private`.
  References of the form `$Script:Foo` are now treated as
  runtime-deferred (the author has explicitly declared a scope, so the
  analyzer respects that intent) and never produce false-positive
  "undefined variable" reports.
- **`PSA4001` (TODO/FIXME marker)**: the marker-matching now requires
  a colon or whitespace-then-letter after the marker, and ignores
  embedded string literals like `"XXX"` inside comments. Previously,
  comments mentioning marker words inside quoted strings produced
  spurious reports.

## [3.1.0] — Earlier

### Added

- **`PSA7xxx` — File format / encoding** (new rule category, for
  file-level checks that operate on raw bytes before UTF-8 decoding).
- **`PSA7001`** (warning, default ON): PowerShell script lacks UTF-8
  BOM. Windows PowerShell 5.1 falls back to the system Active Code
  Page (Shift-JIS / cp932 on ja-JP) when a `.ps1` file has no BOM and
  contains non-ASCII bytes, causing mojibake. Adding the three-byte
  UTF-8 BOM (`0xEF 0xBB 0xBF`) at the start of the file forces correct
  interpretation regardless of console code page.

### Changed

- **`analyze_text()` signature** extended with optional `file_meta`
  parameter (backward compatible — existing callers passing only
  `(text, cfg)` are unaffected; PSA7xxx rules become no-ops when
  `file_meta` is absent).
- **`main()` file reader** switched from `path.read_text()` to
  `path.read_bytes()` so the BOM can be inspected before decoding
  (`read_text` silently strips BOM, defeating any in-text inspection).

## [2.3.0] — Earlier

### Changed

The `--config <URL>` code path is now production-grade:

- **Browser-like User-Agent** (Chrome 131) plus `Sec-Ch-Ua` client
  hints, so CDN / WAF defaults that block obvious bot UAs (notably
  Cloudflare-fronted sites) do not interfere.
- **Explicit TLS 1.2 minimum**, maximum auto-negotiated to TLS 1.3
  against modern servers. Old TLS 1.0 / 1.1 are not offered
  (RFC 8996). Certificate verification is always on.
- **Exponential-backoff retries** on transient failures, modelled on
  the `Invoke-WebRequestWithRetry` pattern from the companion
  PowerShell project:
  - 5xx responses → retry, waiting `2^attempt × 3` seconds
    (6 s, 12 s, …)
  - Network / timeout errors → retry, waiting `2^attempt` seconds
    (2 s, 4 s, …)
  - 4xx responses → fail immediately (persistent client error)

### Added

- Env-var tuning for CI flexibility:
  - `PSA_CONFIG_TIMEOUT` — per-attempt timeout (default 30s)
  - `PSA_CONFIG_MAX_RETRIES` — total attempts (default 3)
  - `PSA_CONFIG_QUIET` — suppress retry-progress messages on stderr

See [SPEC §5.4](./SPEC.md#54-remote-configuration-http--https) for the
full contract.

## [2.2.0] — Earlier

### Changed

- **Configuration files are now JSONC.** Add `// line comments` and
  `/* block comments */` to `.psa.config.json` as freely as you would
  in JavaScript. Comment-like text inside string literals is preserved
  intact.

### Added

- **`--config` accepts URLs.** In addition to a local path, you can
  point `--config` at any http(s) URL — most commonly a GitHub raw URL
  for sharing a team-wide configuration:

  ```bash
  psa.py --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json <script>.ps1
  ```
- **Template file shipped.** A new file `.psa.config.json.template`
  ships next to `psa.py` in this directory.

## [2.1.0] — Earlier

### Added

- Runtime probe (`--check-env` / `--show-env`) that reports whether
  PowerShell and PSScriptAnalyzer are available on the current host.
  The output is purely informational; it never affects exit codes or
  issue counts.

  ```
  ==== psa.py: Environment Detection ====
  psa.py           : 2.2.0
  Python           : 3.12.3 (Linux 6.18.5)
  PowerShell       : pwsh 7.4.6 at /usr/bin/pwsh
  PSScriptAnalyzer : 1.22.0 (available)

  Info:
    PSScriptAnalyzer is available in this environment. For
    comprehensive PowerShell static analysis, consider running
    Microsoft's analyzer in addition to psa.py:

      pwsh -Command "Invoke-ScriptAnalyzer -Path <script>.ps1"
  ```

### Notes

- The probe is particularly useful for AI agents (Claude, etc.) and CI
  sandboxes where the availability of PowerShell may vary per
  execution. It is fast, side-effect-free, and bypasses user profiles
  (`-NoProfile -NonInteractive`).

## [2.0.0] — Earlier

### Added

Major release inspired by Microsoft's [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
and Vidar Holen's [shellcheck](https://github.com/koalaman/shellcheck).
It expanded the rule set to **27 rules** and added JSON / SARIF output,
inline suppression, configuration files, and multi-file scanning —
while preserving the single-file, zero-dependency design.

The capability snapshot at the 2.0.0 release time covered:

| Area               | At 2.0.0                                     |
|:-------------------|:---------------------------------------------|
| Rule codes         | `PSA1001`–`PSA6006` (27 rules total)         |
| Output formats     | Text / JSON / SARIF 2.1.0                    |
| Suppression        | `# psa-disable-line`, `next-line`, `file`    |
| Configuration      | `.psa.config.json` + CLI                     |
| File handling      | Multiple files / directories / glob          |
| Color output       | TTY-aware ANSI (NO_COLOR honored)            |
| Heredoc / sub-expr | Full `@"…"@`, `@'…'@`, `$()`, `@()`          |

The rule taxonomy established here (PSA1xxx for structural,
PSA2xxx for variable, PSA3xxx for command, PSA4xxx for comment,
PSA5xxx for security, PSA6xxx for style) has remained stable since
2.0.0. The `PSA7xxx` (file format / encoding) category was added in
3.1.0, `PSA8xxx` (cross-file consistency) and `PSA9xxx` (complexity
metrics) in 3.2.0, and the `PSAPxxxx` family (project / pipeline
convention) was started in 3.2.0 (PSAP0001 / PSAP0002) and extended
in 3.3.0 (PSAP0003 / PSAP0004).

## [Pre-2.0.0]

Pre-2.0.0 history is not recorded in this file. The 2.0.0 release was
the first formal versioning milestone; earlier development was
single-author exploratory work without numbered releases.

---

[Unreleased]: https://github.com/usui-tk/ai-generated-artifacts/compare/main...HEAD
[3.4.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[3.3.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[3.2.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[3.1.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.3.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.2.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.1.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.0.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
