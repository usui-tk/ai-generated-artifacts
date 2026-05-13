# psa.py Specification

> 🇺🇸 English / 🇯🇵 [日本語](./SPEC.ja.md)

This is the formal specification for `psa.py`, the PowerShell static
analyzer maintained in this directory.

**Document version**: 2.3.0
**Applies to**: `psa.py` 2.3.0 and later 2.x releases
**Status**: Normative

For a user-facing overview, see [`README.md`](./README.md). This
document covers the contract between `psa.py` and its callers — CLI,
configuration file, output formats, exit codes, suppression syntax, and
environment detection. Anything not specified here may change between
patch releases without notice.

---

## Table of contents

1. [Scope](#1-scope)
2. [Architecture](#2-architecture)
3. [Command-line interface](#3-command-line-interface)
4. [Rule specifications](#4-rule-specifications)
5. [Configuration file](#5-configuration-file)
6. [Output formats](#6-output-formats)
7. [Inline suppression](#7-inline-suppression)
8. [Environment detection](#8-environment-detection)
9. [Exit codes](#9-exit-codes)
10. [Backward compatibility](#10-backward-compatibility)
11. [Tokenizer behaviour](#11-tokenizer-behaviour)
12. [Extension guide](#12-extension-guide)

---

## 1. Scope

### 1.1 Purpose

`psa.py` is a single-file Python 3 static analyzer for PowerShell
scripts (`.ps1` and `.psm1`). It detects classes of bugs that the
PowerShell parser does not flag at parse time, and that
[PSScriptAnalyzer][PSScriptAnalyzer] does not cover with its default
rule set (notably: brace balance over thousand-line scripts,
heuristically-undefined variable references, security anti-patterns).

[PSScriptAnalyzer]: https://github.com/PowerShell/PSScriptAnalyzer

### 1.2 Non-goals

`psa.py` is **not** a replacement for PSScriptAnalyzer, the PowerShell
parser, or a full PowerShell runtime. The following are explicitly out
of scope:

- Cmdlet existence verification (would require a PowerShell session)
- Type inference (PowerShell is dynamically typed)
- Module import resolution
- AST-level analyses (e.g., consistent indentation, casing) — these are
  PSScriptAnalyzer's domain
- Auto-fix / code rewriting

### 1.3 Design constraints

`psa.py` MUST:

- Be a single Python file
- Use only the Python 3 standard library
- Run on any platform with Python 3.8 or newer
- Produce identical output for a given (file, configuration) pair on
  any platform
- Have a deterministic, finite runtime; static analysis SHOULD complete
  in O(n) over the file in tokens
- Never modify input files

### 1.4 Versioning

`psa.py` follows [Semantic Versioning 2.0.0](https://semver.org/). The
public API surface — for versioning purposes — comprises:

- The command-line interface (flags, exit codes, output format
  identifiers)
- The rule code names (`PSAxxxx`)
- The JSON output schema
- The SARIF output (which is governed by SARIF 2.1.0)
- The configuration file schema

Internal Python module boundaries (function and class names within
`psa.py`) are NOT part of the public API and may change at any time.

---

## 2. Architecture

### 2.1 Component overview

```
                  ┌──────────────────┐
   input          │  expand_paths()  │   recursive glob expansion
   files /        │                  │   (.ps1, .psm1 collection)
   directories ──▶└────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  read_text()     │   UTF-8 decode with replacement
                  └────────┬─────────┘   for malformed bytes
                           │
                           ▼
                  ┌────────────────────────────┐
                  │ strip_strings_and_comments │  preserves line numbers
                  └────────┬───────────────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  analyze_text()  │   runs all enabled rules
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  suppression     │   inline / per-line / per-file
                  │  filter          │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  severity filter │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  formatter       │   text / json / sarif
                  │  (text/json/    │
                  │   sarif)        │
                  └────────┬─────────┘
                           │
                           ▼
                       stdout
```

### 2.2 Processing model

`psa.py` is a batch processor. For each input file:

1. **Read** the file as UTF-8, replacing malformed bytes
2. **Tokenize** by replacing string and comment content with spaces of
   the same length (preserving line and column positions)
3. **Run** every enabled rule against either the raw text or the
   tokenized text, producing a list of issues
4. **Filter** issues by inline suppression directives
5. **Filter** issues by minimum severity (`--severity`)
6. **Deduplicate** identical (code, line, col, message) tuples
7. **Sort** by (line, col, code) for stable, reproducible output

Multiple input files are processed independently; there is no
cross-file analysis.

### 2.3 Issue representation

Internally, every rule produces dicts with these keys:

| Key | Type | Description |
|:---|:---|:---|
| `severity` | str | `"error"`, `"warning"`, or `"info"` |
| `code` | str | The new `PSAxxxx` code |
| `line` | int | 1-based line number; `0` for whole-file issues (e.g., balance) |
| `col` | int | 1-based column number; `0` when not applicable |
| `message` | str | One-line, human-readable description |

---

## 3. Command-line interface

### 3.1 Synopsis

```
psa.py [OPTIONS] [PATH ...]
psa.py --list-rules
psa.py --check-env
psa.py --version
```

### 3.2 Positional arguments

| Argument | Description |
|:---|:---|
| `PATH` | One or more file paths, directory paths, or glob patterns. Glob expansion is performed by `psa.py` itself for portability with non-POSIX shells. Directories are skipped unless `-r` is given. |

### 3.3 Options

| Flag | Argument | Default | Description |
|:---|:---|:---|:---|
| `-r`, `--recursive` | — | off | Recursively scan directory arguments for `*.ps1` and `*.psm1` |
| `--format` | `text\|json\|sarif` | `text` | Output format. See §6. |
| `--severity` | `error\|warning\|info` | (all reported) | Minimum severity to report. |
| `--enable` | `CODE[,CODE...]` | — | Enable specific rule codes. Repeatable. |
| `--disable` | `CODE[,CODE...]` | — | Disable specific rule codes. Repeatable. |
| `--include` | `CODE[,CODE...]` | — | Run ONLY the listed codes (mutually exclusive with `--enable`'s default-set behaviour). Repeatable. |
| `--config` | `PATH_OR_URL` | implicit | Load configuration from a local file or an http(s) URL. See §5.4. |
| `--max-line-length` | `N` | `120` | Threshold for `PSA4003`. |
| `--no-color` | — | auto | Disable ANSI color output. Color is auto-disabled when stdout is not a TTY or when `NO_COLOR` env var is set. |
| `--list-rules` | — | — | Print rule catalog to stdout and exit `0`. |
| `--check-env` | — | — | Run environment detection (§8) and exit `0`. |
| `--show-env` | — | off | Prepend an environment summary to the normal analysis output. Does not affect exit code. |
| `--version` | — | — | Print version and exit `0`. |

### 3.4 Argument forms

Rule codes may be specified in two forms:

- **New form**: `PSAxxxx` (e.g., `PSA2001`)
- **Legacy form**: `Cn` (e.g., `C4`) — case-insensitive

Both forms are accepted everywhere a code is expected (`--enable`,
`--disable`, `--include`, inline suppression comments,
`.psa.config.json`). Legacy codes are mapped internally to their `PSA`
equivalent before any processing.

Comma-separated lists are accepted as a single argument value, e.g.,
`--disable PSA4001,PSA4002`.

### 3.5 Configuration resolution order

Configuration is layered from lowest to highest priority:

1. Built-in defaults (the `RULES` table in `psa.py`)
2. Configuration file (`.psa.config.json`) — see §5
3. CLI flags
4. Inline suppression directives — see §7

Higher-priority settings override lower-priority ones for each rule
independently. There is no "all-or-nothing" cascade; disabling one rule
in `--disable` leaves all other rules at their previous state.

---

## 4. Rule specifications

This section is normative. Each rule's detection logic is described in
sufficient detail that an alternative implementation could reproduce
the same behaviour.

### 4.1 PSA1001 — Brace balance

- **Severity**: Error
- **Default**: enabled
- **Legacy**: —

**Detection**: After string/comment stripping (§11), count occurrences
of `{` and `}` in the cleaned text. Report if counts differ.

**Reported location**: line `0`, col `0` (whole-file).

### 4.2 PSA1002 — Paren balance

- **Severity**: Error
- **Default**: enabled

**Detection**: Same as PSA1001 but for `(` / `)`.

### 4.3 PSA1003 — Bracket balance

- **Severity**: Error
- **Default**: enabled

**Detection**: Same as PSA1001 but for `[` / `]`.

### 4.4 PSA2001 — Undefined variable reference (legacy C4)

- **Severity**: Error
- **Default**: enabled
- **Legacy**: C4

**Detection**: Heuristic. For each function block (`function Name { … }`):

1. Collect locally-assigned names from `$x = …`, `foreach ($x in …)`,
   `for ($x = …`, `param(…)` blocks, and inline parameter lists
2. Collect globally-assigned names (assignments outside any function)
3. Walk all `$variable` references within the function body
4. If a reference is not in the local set, not in the global set, not
   in `AUTO_VARS` (PowerShell automatic variables), and not in an
   external scope (`$env:`, `$using:`), report it once per
   (variable_name, function_name) pair

**Reported location**: line and col within the function body.

**Known limitations**: This rule does not understand
splatting (`@args`), dynamically-resolved variable names
(`Get-Variable`), or modules' exported variables. False positives are
possible; suppress with `# psa-disable-line PSA2001` when intentional.

### 4.5 PSA2002 — Auto-variable shadowing (legacy C5)

- **Severity**: Warning
- **Default**: enabled
- **Legacy**: C5

**Detection**: Any assignment `$name = …` where `name` (lowercased) is
in the RISKY_SHADOW_VARS set:
`args`, `lastexitcode`, `input`, `matches`, `foreach`, `host`,
`true`, `false`.

### 4.6 PSA2003 — `-match` against bare variable (legacy C7)

- **Severity**: Warning
- **Default**: enabled
- **Legacy**: C7

**Detection**: Pattern `-match $name` where `$name` is not `$null`.
This is bug-prone because `-match $null` returns `$true` in PowerShell.

### 4.7 PSA2004 — `$null` on the right side of `-eq`/`-ne`

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern `$variable -eq $null` (also `-ne`, `-ceq`,
`-cne`, `-ieq`, `-ine`). PowerShell's `$null -eq $x` form is safer
because when `$x` is a collection, the right-`$null` form returns
*elements* equal to `$null` rather than a Boolean.

### 4.8 PSA2005 — Assignment operator inside conditional

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern `if|while|elseif ( $variable = ...` where `=`
is not followed by another `=` (avoiding `==` false-positives).

### 4.9 PSA2006 — Redirection operator inside conditional

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern `if|while|elseif ( $variable [<>] ...`.
In PowerShell, `>` and `<` are file redirection, not comparison.
Use `-gt` / `-lt`.

### 4.10 PSA3001 — `Start-Process -ArgumentList` (legacy C6)

- **Severity**: Warning
- **Default**: enabled
- **Legacy**: C6

**Detection**: Pattern `Start-Process … -ArgumentList`. The
`-ArgumentList` parameter has known quoting issues with paths
containing spaces; prefer `System.Diagnostics.ProcessStartInfo`.

### 4.11 PSA3002 — Backtick continuation before empty line (legacy C9)

- **Severity**: Warning
- **Default**: enabled
- **Legacy**: C9

**Detection**: A line ending in a single backtick (not `` `` ``)
followed by a line that is empty or contains only whitespace.

**Source text**: This rule examines the raw text (not the stripped
form) because trailing whitespace after the backtick is significant.

### 4.12 PSA3003 — `-match` against empty string (legacy C10)

- **Severity**: Warning
- **Default**: enabled
- **Legacy**: C10

**Detection**: Pattern `-match ''` or `-match ""`. Always true.

### 4.13 PSA3004 — Empty catch block

- **Severity**: Warning
- **Default**: enabled

**Detection**: `catch [Type]? { }` with no content between the braces.
A 4-line look-ahead window allows `catch {\n}` to be detected.

### 4.14 PSA4001 — Unfinished marker (legacy C8)

- **Severity**: Info
- **Default**: enabled
- **Legacy**: C8

**Detection**: Within a `#` comment, the words `TODO`, `FIXME`, `XXX`,
or `HACK` (case-sensitive, word-bounded).

### 4.15 PSA4002 — Trailing whitespace

- **Severity**: Info
- **Default**: enabled

**Detection**: A line whose final non-newline character is `\t` or `' '`.

### 4.16 PSA4003 — Long line

- **Severity**: Info
- **Default**: **disabled**

**Detection**: A line whose visible length exceeds `max_line_length`
(default 120). Configure via `--max-line-length` or `max_line_length`
in `.psa.config.json`.

### 4.17 PSA4004 — Trailing semicolon

- **Severity**: Info
- **Default**: enabled

**Detection**: A line whose stripped form ends in a single `;`
(`;;` is not flagged — it is more often a deliberate marker).

### 4.18 PSA5001 — Plain-text password parameter

- **Severity**: Error
- **Default**: enabled

**Detection**: Pattern `[string]$NamePassword`,
`[string]$NamePwd`, or `[string]$NameCredential` (case-insensitive,
suffix/prefix-insensitive match). PowerShell offers `[SecureString]`
and `[PSCredential]` for these.

### 4.19 PSA5002 — `Invoke-Expression`

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern `Invoke-Expression` or the alias `iex` as a
command word. Equivalent to `eval()` in other languages.

### 4.20 PSA5003 — Broken hash algorithm

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern `MD5(CryptoServiceProvider|Managed)?`,
`SHA1(CryptoServiceProvider|Managed)?`, or `-Algorithm "MD5"`/`"SHA1"`.

### 4.21 PSA5004 — Hardcoded `ComputerName`

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern `-ComputerName "literal"` (or single-quoted).
The literals `localhost`, `.`, and `127.0.0.1` are whitelisted.

### 4.22 PSA6001 — Non-approved verb

- **Severity**: Warning
- **Default**: enabled

**Detection**: A `function VerbName-NounName` whose verb (lowercased)
is not in the PowerShell approved-verb set (~100 verbs from
`Get-Verb`, hard-coded into `APPROVED_VERBS`).

### 4.23 PSA6002 — Cmdlet alias

- **Severity**: Warning
- **Default**: **disabled**

**Detection**: Any of the standard cmdlet aliases (`ls`, `cd`, `dir`,
`where`, etc.; ~150 aliases hard-coded) used in command position
(line start, after `;`, `|`, `&`, or `(` ).

**Exclusions**:

- `foreach (`, `switch (`, `select (`, `sort (`, `set (` — these are
  PowerShell keyword forms, not aliases
- `name = …` — hashtable key or property assignment

### 4.24 PSA6003 — Plural function noun

- **Severity**: Warning
- **Default**: enabled

**Detection**: A function name `Verb-Noun` where `Noun` ends in `s`
(lowercased) and is NOT in the legitimate-plurals whitelist:
`process`, `address`, `progress`, `access`, `success`, `class`,
`pass`, `business`, `analysis`, `basis`, `series`, `species`,
`thesis`, `crisis`, `status`, `bus`. Names ending in `ss` are also
exempted.

### 4.25 PSA6004 — `$global:` variable definition

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern `$global:Name = …`. Use `$script:` or pass as a
parameter instead.

### 4.26 PSA6005 — Mandatory parameter with default value

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern
`[Parameter(…Mandatory…)] [Type] $Name = default`. A Mandatory
parameter can never use its default; declaring one is misleading.

### 4.27 PSA6006 — Switch parameter defaulting to `$true`

- **Severity**: Warning
- **Default**: enabled

**Detection**: Pattern `[switch]$Name = $true`. A switch always
defaults to `$false`; setting it to `$true` confuses callers.

---

## 5. Configuration file

### 5.1 Location and discovery

`psa.py` resolves the active configuration file from these sources, in
order:

1. The value given to `--config` (a local path OR an http(s) URL — see
   §5.4). If the source cannot be read or parsed, `psa.py` prints an
   error to stderr and exits with code `2`.
2. `.psa.config.json` in the current working directory (implicit
   discovery). Only attempted when `--config` is absent.

If neither is available, built-in defaults apply.

### 5.2 File format

The configuration file is **JSONC**: regular JSON with two extensions:

- `// line comments` — until end of line
- `/* block comments */` — may span multiple lines

Comment-like sequences inside string literals are preserved unchanged.
Newlines inside block comments are preserved so that line numbers in
JSON-parse error messages remain meaningful.

A template file named `.psa.config.json.template` ships alongside
`psa.py` in this directory. It documents every field with its
built-in default and is suitable for `cp .psa.config.json.template
.psa.config.json`.

The file MUST be UTF-8 encoded and MUST parse to a JSON **object**
(not an array or scalar). All top-level fields are optional; `{}` is
a valid configuration.

### 5.3 Schema

```jsonc
{
  // Rule codes to force-enable (overrides default-disabled state)
  "enable": ["PSA6002"],

  // Rule codes to force-disable
  "disable": ["PSA4001"],

  // Minimum severity to report. One of: "error", "warning", "info"
  "severity": "warning",

  // Line-length threshold used by PSA4003
  "max_line_length": 120
}
```

| Field | Type | Default | Notes |
|:---|:---|:---|:---|
| `enable` | array of strings | `[]` | Each string is a rule code (`PSAxxxx` or legacy `Cn`). Unknown codes are silently ignored. |
| `disable` | array of strings | `[]` | Same format as `enable`. |
| `severity` | string | `"info"` | Floor for the displayed severity. |
| `max_line_length` | integer | `120` | Must be positive. |

### 5.4 Remote configuration (HTTP / HTTPS)

`--config` accepts an http(s) URL in addition to a filesystem path:

```bash
psa.py --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json <script>.ps1
```

For GitHub, use the **raw** URL form (`raw.githubusercontent.com/...`).
The regular blob URL (`github.com/.../blob/...`) returns HTML and will
fail JSON parsing.

#### 5.4.1 TLS configuration

`psa.py` builds the SSL context explicitly:

| Setting | Value | Rationale |
|:---|:---|:---|
| `minimum_version` | `TLSv1_2` | Industry baseline since 2020. TLS 1.0/1.1 are deprecated (RFC 8996, 2021) and not offered. GitHub and major CDNs require at least TLS 1.2. |
| `maximum_version` | (default) | Left unset so the handshake auto-negotiates the strongest mutually-supported version, typically TLS 1.3 against modern servers, falling back to TLS 1.2 against older ones. |
| `verify_mode` | `CERT_REQUIRED` | OS trust store is loaded via `ssl.create_default_context()`. Certificate verification is ALWAYS on and cannot be disabled. |
| `check_hostname` | `True` | Hostname mismatch causes the handshake to fail. |

The "automatic downshift to whatever the server supports" behaviour is
therefore intrinsic to the TLS handshake itself — `psa.py` does not
need a custom downgrade-retry loop.

#### 5.4.2 Request headers

To be reachable through CDNs and WAFs (notably Cloudflare-fronted
sites) that default-reject obvious bot User-Agents even on public raw
files, `psa.py` presents itself as a recent Chrome build:

```
User-Agent       : Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36
Accept           : application/json, text/plain, text/*, */*
Accept-Language  : en-US,en;q=0.9
Accept-Encoding  : identity
Sec-Ch-Ua        : "Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"
Sec-Ch-Ua-Mobile : ?0
Sec-Ch-Ua-Platform : "Windows"
```

The Sec-Ch-Ua client hints intentionally agree with the User-Agent
string. The Chrome version is bumped together with the UA when the
template is updated.

#### 5.4.3 Retry policy

`psa.py` retries the fetch on transient failures, with exponential
backoff. Pattern adapted from `Invoke-WebRequestWithRetry` in the
companion `Download-SpeakerDeck.ps1` project.

| Outcome | Action | Backoff before next attempt |
|:---|:---|:---|
| Success (`2xx`) | return body | — |
| Server error (`5xx`) | retry | `2^attempt × 3` seconds (6 s, 12 s, 24 s, …) |
| Network / timeout / connection error | retry | `2^attempt` seconds (2 s, 4 s, 8 s, …) |
| Client error (`4xx`: 404, 403, 401, …) | abort immediately | — (persistent failure; retrying wastes time) |

Total attempts including the first one is `PSA_CONFIG_MAX_RETRIES`
(default 3). On exhaustion, the most recent exception is propagated to
`Config.load()` and surfaced as a user-facing error.

Each retry emits a single-line message to stderr, e.g.::

```
psa.py: HTTP 503 from https://example.com/.psa.config.json; retry 1/2 in 6s
psa.py: HTTP 503 from https://example.com/.psa.config.json; retry 2/2 in 12s
```

Set `PSA_CONFIG_QUIET=1` to suppress these.

#### 5.4.4 Environment-variable tuning

| Variable | Default | Effect |
|:---|---:|:---|
| `PSA_CONFIG_TIMEOUT` | `30` | Per-attempt connect+read timeout in seconds. |
| `PSA_CONFIG_MAX_RETRIES` | `3` | Total attempts including the first. `1` disables retries. |
| `PSA_CONFIG_QUIET` | (unset) | When set (any non-empty value), suppresses retry-progress messages on stderr. |

Invalid values (non-numeric, non-positive) silently revert to the
default to avoid breaking CI on a typo.

#### 5.4.5 Caching

Remote configurations are fetched **once per invocation** and are not
cached on disk. Repeated `psa.py` invocations will hit the upstream
URL each time. In high-frequency CI scenarios, consider mirroring the
config to a local file and pointing `--config` at that.

### 5.5 Precedence

When the same rule appears in both `enable` and `disable`, the result
is implementation-defined; do not rely on either order. CLI flags
always override configuration file settings.

---

## 6. Output formats

### 6.1 Text format

Produced by `--format text` (the default). Output structure:

```
==== psa.py: PowerShell Static Analyzer ====
File   : <path>
Lines  : <total-line-count>
Issues : <N> errors, <M> warnings, <K> info

---- ERROR (<N>) ----
  [<CODE>(=<LEGACY>)? ] line <L>:<C>: <message>
  ...

---- WARNING (<M>) ----
  ...

---- INFO (<K>) ----
  ...
```

When no issues are found, the body is `  (no issues found)`.

ANSI colour escapes are emitted when stdout is a TTY and the
`NO_COLOR` environment variable is not set. `--no-color` forces colour
off unconditionally.

### 6.2 JSON format

Produced by `--format json`. For a single input file:

```jsonc
{
  "file": "<path>",
  "lines": 4106,
  "summary": {
    "errors": 0,
    "warnings": 17,
    "info": 0
  },
  "issues": [
    {
      "code": "PSA3004",
      "legacy_code": null,
      "severity": "warning",
      "line": 211,
      "col": 0,
      "message": "empty catch block"
    },
    // ...
  ],

  // Present only when --show-env was passed:
  "environment": { /* see §8 */ }
}
```

For multiple input files, the top-level is wrapped:

```jsonc
{
  "files": [ /* each file's object as above, but without env */ ],
  "environment": { /* see §8 */ }  // only with --show-env
}
```

The JSON output is always pretty-printed with 2-space indentation and
no ASCII-only escaping (`ensure_ascii=False`).

### 6.3 SARIF 2.1.0 format

Produced by `--format sarif`. Conforms to the SARIF 2.1.0 schema. The
top-level structure:

```jsonc
{
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "psa.py",
          "version": "2.1.0",
          "informationUri": "...",
          "rules": [ /* 27 rule descriptors */ ]
        }
      },
      "results": [ /* one entry per issue */ ],
      "properties": {
        "environment": { /* §8, only with --show-env */ }
      }
    }
  ]
}
```

Severity mapping (SARIF `level` field):

| `psa.py` severity | SARIF `level` |
|:---|:---|
| `error` | `error` |
| `warning` | `warning` |
| `info` | `note` |

The `properties.environment` extension is a `psa.py`-specific
property bag permitted by SARIF for tool extensions.

---

## 7. Inline suppression

### 7.1 Syntax

Suppression directives are PowerShell comments parsed by `psa.py`:

```ebnf
suppression  ::=  "#" whitespace? directive
directive    ::=  scope whitespace codes
scope        ::=  "psa-disable-line"      // suppress on same line
              |  "psa-disable-next-line"  // suppress on following line
              |  "psa-disable-file"        // suppress for whole file
codes        ::=  code ( ( "," | whitespace ) code )*
code         ::=  "PSA" digit{4}  | "C" digit{1,2}
```

The directive name is case-insensitive. Codes may be in either form.

### 7.2 Semantics

- `psa-disable-line CODES` — suppress the listed codes on the same
  source line where the comment appears.
- `psa-disable-next-line CODES` — suppress the listed codes on the
  immediately following source line.
- `psa-disable-file CODES` — suppress the listed codes throughout the
  entire file, regardless of position. Multiple `psa-disable-file`
  comments accumulate.

Suppression applies AFTER rule execution: rules still run, but matching
issues are filtered before output.

### 7.3 Examples

```powershell
$x -match $pattern  # psa-disable-line PSA2003

# psa-disable-next-line PSA3001,PSA3002
Start-Process -ArgumentList $args ...

# psa-disable-file PSA4001
function Do-Something {
  # TODO: this won't be reported
}
```

---

## 8. Environment detection

### 8.1 Purpose

Environment detection is an **informational** feature. It probes the
runtime for PowerShell and PSScriptAnalyzer, so that users running
`psa.py` in a constrained environment (e.g., AI sandboxes without
PowerShell installed) can confirm whether complementary tools are
available. The output is purely advisory: it never affects the exit
code, the issue count, or any filter.

### 8.2 Modes

Two CLI flags trigger environment detection:

- `--check-env`: run detection only and exit. No analysis is performed.
  Exit code is `0` regardless of detection result.
- `--show-env`: prepend an environment summary to the normal analysis
  output. Analysis proceeds as usual; detection adds latency of up to
  approximately 2 × `ENV_PROBE_TIMEOUT` seconds (currently 10s each,
  so ~20s worst case) when PowerShell is installed but slow to start.

### 8.3 Probe procedure

1. **Locate the PowerShell binary**. Try, in order: `pwsh`,
   `powershell`, `powershell.exe`. The first that resolves via
   `shutil.which()` is used.
2. **Probe the PowerShell version**. Execute:

   ```
   <binary> -NoProfile -NonInteractive -Command "$PSVersionTable.PSVersion.ToString()"
   ```

   with a timeout of 10 seconds. If the command times out, exits
   non-zero, or produces empty output, PowerShell is reported as
   unavailable.

3. **Probe PSScriptAnalyzer** (only if step 2 succeeded). Execute:

   ```
   <binary> -NoProfile -NonInteractive -Command \
     "$m = Get-Module -ListAvailable PSScriptAnalyzer | \
      Sort-Object Version -Descending | Select-Object -First 1; \
      if ($m) { $m.Version.ToString() }"
   ```

   with a timeout of 10 seconds. The latest installed version is
   reported.

### 8.4 Output (text format)

```
==== psa.py: Environment Detection ====
psa.py        : <psa version>
Python        : <python version> (<OS> <release>)
PowerShell    : <command> <PSVersion> at <full path>
                ^^^ "not found on PATH" if absent
PSScriptAnalyzer : <module version> (available)
                ^^^ "not installed" if absent

Info:
  <one of three message variants — see §8.5>
```

### 8.5 Recommendation variants

`psa.py` selects one of three info-level messages:

| PowerShell | PSScriptAnalyzer | Message |
|:---:|:---:|:---|
| ✓ | ✓ | "PSScriptAnalyzer is available… consider running both tools" |
| ✓ | ✗ | "PowerShell is available, but PSScriptAnalyzer is not installed. To install:…" |
| ✗ | ✗ | "psa.py is operating in standalone mode. No PowerShell runtime detected on PATH." |

### 8.6 Output (JSON / SARIF)

Returned data structure (used for `--check-env --format json`,
`--show-env --format json`, and SARIF `properties.environment`):

```jsonc
{
  "python_version": "3.12.3",
  "python_executable": "/usr/bin/python3",
  "platform": "Linux 6.18.5",
  "psa_version": "2.1.0",
  "powershell": {
    "command": "pwsh",
    "path": "/usr/bin/pwsh",
    "version": "7.4.6"
  } | null,
  "psscriptanalyzer": {
    "version": "1.22.0"
  } | null
}
```

`powershell` and `psscriptanalyzer` are `null` when unavailable. The
data model is stable; new keys MAY be added in future minor releases
but existing keys will not be renamed or removed within a major
version.

### 8.7 Determinism and side effects

Environment detection is **idempotent** and **side-effect-free**:

- No files are written
- No network calls are made
- No environment variables are mutated
- The probed PowerShell processes run with `-NoProfile -NonInteractive`
  to bypass user profile execution

Probe failures (timeout, missing binary, non-zero exit) are NEVER
propagated as Python exceptions; they always reduce to "the tool was
not detected".

---

## 9. Exit codes

| Exit code | Condition |
|:---:|:---|
| `0` | Analysis succeeded; no errors or warnings reported. Also returned by `--list-rules`, `--check-env`, `--version`, and `--help`. |
| `1` | Analysis succeeded; warnings reported but no errors. Info-level issues alone do NOT produce exit `1`. |
| `2` | Analysis succeeded; one or more errors reported. ALSO returned for fatal startup errors (no input files, unreadable config, etc.). |
| `130` | Interrupted by SIGINT (Ctrl-C). |

The `--show-env` flag NEVER affects the exit code, regardless of what
the environment probe reports.

---

## 10. Backward compatibility

### 10.1 Legacy rule codes

The legacy codes `C1` through `C10` from `psa.py` 1.x are accepted
input forms (in `--enable`, `--disable`, `--include`, configuration
file, inline suppression) and are mapped internally to their `PSA`
equivalents:

| Legacy | New | Note |
|:---:|:---:|:---|
| C1 | PSA1001 | (\*) |
| C2 | PSA1002 | (\*) |
| C3 | PSA1003 | (\*) |
| C4 | PSA2001 | severity preserved (Error) |
| C5 | PSA2002 | |
| C6 | PSA3001 | |
| C7 | PSA2003 | |
| C8 | PSA4001 | |
| C9 | PSA3002 | |
| C10 | PSA3003 | |

(\*) `C1`, `C2`, `C3` mapped to balance rules. The legacy implementation
treated the three brace-types as a single check; the new implementation
splits them, but the legacy alias `C1`/`C2`/`C3` is not strictly
necessary because the brace/paren/bracket checks were already
error-severity in 1.x.

The text output prints both forms when a legacy code exists, e.g.,
`[PSA2003 (=C7)] line 2337: 22: …`. Tools that grep for `C7` in CI
logs continue to function.

### 10.2 Exit code stability

The `0` / `1` / `2` exit code contract is preserved from 1.x. Some
files that produced 0 errors in 1.x might produce errors in 2.x due to
new security rules (notably PSA5001). This is deliberate; the rule set
expanded.

### 10.3 Configuration file stability

`psa.py` 2.x adds the `.psa.config.json` file. Earlier versions ignored
all configuration files; the addition is purely additive.

### 10.4 Removed / changed behaviour

None. `psa.py` 2.x is strictly additive over 1.x feature-wise.

---

## 11. Tokenizer behaviour

The tokenizer (`strip_strings_and_comments`) replaces the content of
strings, here-strings, and comments with space characters while
preserving line numbers and column offsets. This guarantees that
downstream regex-based rules see only "real" PowerShell code without
having to re-implement quoting rules.

### 11.1 Recognized constructs

| Construct | Behaviour |
|:---|:---|
| `# …\n` | Replaced with spaces up to end of line. |
| `<# … #>` | Replaced with spaces; spans multiple lines. |
| `'…'` | Replaced with spaces. `''` is treated as an escaped single quote. |
| `"…"` | Replaced with spaces, BUT `$variable` references inside are preserved (this is essential for undefined-variable detection). `` `" `` is recognized as a backtick-escaped quote. |
| `@'\n…\n'@` | Here-string (single-quoted). Replaced with spaces. |
| `@"\n…\n"@` | Here-string (double-quoted). Same as `"…"`: `$variable` preserved. |

### 11.2 Variable identifier extraction

Inside double-quoted strings and here-strings, variable references are
preserved in these forms:

- `$name` — simple identifier
- `$scope:name` — scoped (`$env:`, `$using:`, etc.)
- `${complex}` — brace-quoted (any content)

### 11.3 Line preservation

The tokenizer's output has exactly the same number of characters per
line and the same number of lines as the input. This is critical for
accurate line / column reporting.

---

## 12. Extension guide

### 12.1 Adding a new rule

To add `PSA7001`:

1. Append an entry to the `RULES` tuple list at the top of `psa.py`:

   ```python
   ('PSA7001', 'warning', None, True, 'Short message'),
   ```

   The 5-tuple is `(code, severity, legacy_code_or_None, default_enabled, short_message)`.

2. Implement a `check_yourthing(...)` function that returns a list of
   issue dicts with the standard 5 keys (see §2.3).

3. Wire it into `analyze_text()`:

   ```python
   if cfg.enabled['PSA7001']:
       raw += check_yourthing(clean)
   ```

4. Add a row to the rule table in `README.md`, `README.ja.md`, and §4
   of this SPEC (and its Japanese counterpart).

5. Bump the minor version (e.g., `2.1.0` → `2.2.0`).

### 12.2 Adding a new output format

1. Implement `format_yourformat(per_file_results, env_info=None)`.

2. Add the format name to the `--format` choices in `parse_args()`:

   ```python
   p.add_argument('--format', choices=('text', 'json', 'sarif', 'yourformat'), ...)
   ```

3. Dispatch in `main()`:

   ```python
   elif cfg.format == 'yourformat':
       print(format_yourformat(per_file, env_info))
   ```

4. Document in §6 of this SPEC.

### 12.3 Adding a new configuration field

1. Add the field to `Config.__init__()` with a default value.

2. Parse it from `data` in `Config.load()`.

3. Use it where needed in the rule implementations.

4. Document in §5.2 of this SPEC.

---

## Appendix A — Rule severity matrix

| Code | Severity | Default | Legacy |
|:---|:---|:---:|:---:|
| PSA1001 | error | ✅ | — |
| PSA1002 | error | ✅ | — |
| PSA1003 | error | ✅ | — |
| PSA2001 | error | ✅ | C4 |
| PSA2002 | warning | ✅ | C5 |
| PSA2003 | warning | ✅ | C7 |
| PSA2004 | warning | ✅ | — |
| PSA2005 | warning | ✅ | — |
| PSA2006 | warning | ✅ | — |
| PSA3001 | warning | ✅ | C6 |
| PSA3002 | warning | ✅ | C9 |
| PSA3003 | warning | ✅ | C10 |
| PSA3004 | warning | ✅ | — |
| PSA4001 | info | ✅ | C8 |
| PSA4002 | info | ✅ | — |
| PSA4003 | info | ⛔ | — |
| PSA4004 | info | ✅ | — |
| PSA5001 | error | ✅ | — |
| PSA5002 | warning | ✅ | — |
| PSA5003 | warning | ✅ | — |
| PSA5004 | warning | ✅ | — |
| PSA6001 | warning | ✅ | — |
| PSA6002 | warning | ⛔ | — |
| PSA6003 | warning | ✅ | — |
| PSA6004 | warning | ✅ | — |
| PSA6005 | warning | ✅ | — |
| PSA6006 | warning | ✅ | — |

---

## Appendix B — Document history

| Version | Date | Changes |
|:---|:---|:---|
| 2.3.0 | 2026 | Remote-config fetch hardened: explicit TLS 1.2 minimum (max auto-negotiated to TLS 1.3); browser-like User-Agent (Chrome 131) + Sec-Ch-Ua client hints; exponential-backoff retries on 5xx and network errors (4xx not retried); env-var tuning (`PSA_CONFIG_TIMEOUT`, `PSA_CONFIG_MAX_RETRIES`, `PSA_CONFIG_QUIET`). See §5.4. |
| 2.2.0 | 2026 | Configuration file becomes JSONC (line `//` and block `/* */` comments). `--config` accepts http(s) URLs in addition to local paths (§5.4). New companion file `.psa.config.json.template` documents every option with built-in defaults. |
| 2.1.0 | 2026 | Initial SPEC document. Adds §8 (environment detection) for `psa.py` 2.1.0. Existing behaviour (rules, formats, CLI) inherited from `psa.py` 2.0.0. |
