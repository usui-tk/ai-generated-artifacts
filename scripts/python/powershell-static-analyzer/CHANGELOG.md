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

_No unreleased changes at this time._

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
| Rule codes         | `PSA1001`–`PSA9002` (27 rules total)         |
| Output formats     | Text / JSON / SARIF 2.1.0                    |
| Suppression        | `# psa-disable-line`, `next-line`, `file`    |
| Configuration      | `.psa.config.json` + CLI                     |
| File handling      | Multiple files / directories / glob          |
| Color output       | TTY-aware ANSI (NO_COLOR honored)            |
| Heredoc / sub-expr | Full `@"…"@`, `@'…'@`, `$()`, `@()`          |

The rule taxonomy established here (PSA1xxx for structural,
PSA2xxx for variable, PSA3xxx for command, PSA4xxx for comment,
PSA5xxx for security, PSA6xxx for style, PSA9xxx for complexity) has
remained stable since 2.0.0. The `PSA7xxx` (file format / encoding)
and `PSA8xxx` (cross-file consistency) categories, and the `PSAPxxxx`
family (project / pipeline convention), were added in later 3.x
releases.

## [Pre-2.0.0]

Pre-2.0.0 history is not recorded in this file. The 2.0.0 release was
the first formal versioning milestone; earlier development was
single-author exploratory work without numbered releases.

---

[Unreleased]: https://github.com/usui-tk/ai-generated-artifacts/compare/main...HEAD
[3.3.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[3.2.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[3.1.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.3.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.2.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.1.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.0.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
