#!/usr/bin/env python3
"""psa.py - PowerShell Static Analyzer (PSScriptAnalyzer-inspired)

A single-file Python 3 static analyzer for PowerShell scripts.
No external dependencies; standard library only.

Rules
-----
Parse / structural (PSA1xxx):
  PSA1001  Brace balance ......................... Error
  PSA1002  Paren balance ......................... Error
  PSA1003  Bracket balance ....................... Error

Variable / scope (PSA2xxx):
  PSA2001  Undefined variable reference .......... Warning
  PSA2002  Auto-variable shadowing ............... Warning
  PSA2003  -match against bare variable .......... Warning
  PSA2004  $x -eq $null  (use $null -eq $x) ...... Warning
  PSA2005  Assignment operator in conditional .... Warning
  PSA2006  Redirection operator in conditional ... Warning

Coding-pattern (PSA3xxx):
  PSA3001  Start-Process -ArgumentList ........... Warning
  PSA3002  Backtick before empty line ............ Warning
  PSA3003  -match against empty string ........... Warning
  PSA3004  Empty catch block ..................... Warning

Style / info (PSA4xxx):
  PSA4001  TODO / FIXME marker ................... Info
  PSA4002  Trailing whitespace ................... Info
  PSA4003  Long line (default: disabled) ......... Info
  PSA4004  Trailing semicolon at line end ........ Info

Security (PSA5xxx):
  PSA5001  Plain-text password parameter ......... Error
  PSA5002  Invoke-Expression usage ............... Warning
  PSA5003  Broken hash algorithm (MD5, SHA1) ..... Warning
  PSA5004  Hardcoded ComputerName ................ Warning

Best-practice (PSA6xxx):
  PSA6001  Non-approved verb in function name .... Warning
  PSA6002  Cmdlet alias (default: disabled) ...... Warning
  PSA6003  Plural noun in function name .......... Warning
  PSA6004  $global: variable definition .......... Warning
  PSA6005  Default value on Mandatory parameter .. Warning
  PSA6006  Switch parameter defaults to $true .... Warning

File format / encoding (PSA7xxx):
  PSA7001  PowerShell script lacks UTF-8 BOM ..... Warning

Usage
-----
  psa.py <file.ps1>                       Analyze a single file
  psa.py file1.ps1 file2.ps1              Multiple files
  psa.py -r <directory>                   Recursive directory scan
  psa.py --format json <file>             JSON output (also: text, sarif)
  psa.py --severity warning <file>        Show warnings and errors only
  psa.py --enable PSA6002 <file>          Enable a disabled-by-default rule
  psa.py --disable PSA2001 <file>         Disable a specific rule
  psa.py --include PSA1001,PSA2001 <f>    Only run listed rules
  psa.py --config .psa.config.json <f>    Use explicit config file
  psa.py --no-color <file>                Disable ANSI color output
  psa.py --list-rules                     Print the rule catalog and exit
  psa.py --version                        Print version and exit

Environment detection
---------------------
psa.py can probe the runtime for PowerShell and PSScriptAnalyzer:

  psa.py --check-env                      Detect and report; do not analyze
  psa.py --show-env <file>                Analyze and prepend env summary

Environment information is purely informational. It is emitted at info
level only, never affects exit codes, and never alters issue counts.
When PSScriptAnalyzer is detected, psa.py prints a recommendation to
also run `Invoke-ScriptAnalyzer` for complementary coverage.

Inline suppression
------------------
  # psa-disable-line PSA3001
  # psa-disable-next-line PSA3001,PSA3002
  # psa-disable-file PSA3001              (suppress for the entire file)

Configuration file (.psa.config.json)
-------------------------------------
  {
    "enable":  ["PSA6002"],
    "disable": ["PSA4001"],
    "severity": "warning",
    "max_line_length": 120
  }

  Configuration files are JSONC: regular JSON plus // line comments and
  /* ... */ block comments. The companion file `.psa.config.json.template`
  in this directory documents every option with its built-in default.

  The --config flag accepts BOTH a local filesystem path AND an
  http(s):// URL:

    psa.py --config ./team-rules.json <script>.ps1
    psa.py --config https://raw.githubusercontent.com/owner/repo/main/.psa.config.json <script>.ps1

  Remote fetch behaviour:
    - Browser-like User-Agent (Chrome 131) + Sec-Ch-Ua client hints,
      so reachable through Cloudflare / WAF defaults that filter
      obvious bot UAs.
    - Explicit TLS 1.2 minimum; maximum auto-negotiated (typically
      TLS 1.3). Older TLS 1.0/1.1 are NOT offered (deprecated, RFC 8996).
    - Exponential-backoff retries on 5xx and network errors. 4xx
      responses are NOT retried.
    - Tunable via env vars: PSA_CONFIG_TIMEOUT (default 30s),
      PSA_CONFIG_MAX_RETRIES (default 3), PSA_CONFIG_QUIET.

Exit codes: 0 = clean, 1 = warnings only, 2 = errors found
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import platform as _platform
import re
import shutil
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

__version__ = '3.3.0'

# ---------------------------------------------------------------------------
# Severity and rule registry
# ---------------------------------------------------------------------------

SEVERITY_ORDER = {'error': 3, 'warning': 2, 'info': 1}

# (new_code, severity, default_enabled, short_message)
#
# Rule ID convention
# ------------------
# PSA1xxx-PSA9xxx  : Generic, project-agnostic rules. Apply to any
#                    PowerShell script. Many are enabled by default.
# PSAP0xxx (new in : Project / pipeline convention rules. Opinionated;
#  v3.2.0)           opt-in only. Designed for repositories that follow
#                    a specific multi-phase pipeline pattern (e.g. the
#                    21-phase Invoke-(Prep|Verify|Inst)Phase\\d{2}_Name
#                    convention used by Deploy-Drivers-For-WindowsServer).
#                    All PSAPxxxx rules are disabled by default; opt in
#                    via .psa.config.json `enable: ["PSAP0001", ...]`
#                    or `--enable PSAP0001` on the command line.
RULES = [
    # -----------------------------------------------------------------
    # Generic rules (PSA1xxx-PSA9xxx)
    # -----------------------------------------------------------------

    # Parse / structural (PSA1xxx)
    ('PSA1001', 'error',   True,
     'Brace balance'),
    ('PSA1002', 'error',   True,
     'Paren balance'),
    ('PSA1003', 'error',   True,
     'Bracket balance'),

    # Variable / scope (PSA2xxx)
    ('PSA2001', 'error',   True,
     'Undefined variable reference'),
    ('PSA2002', 'warning', True,
     'Auto-variable shadowing'),
    ('PSA2003', 'warning', True,
     '-match against bare variable'),
    ('PSA2004', 'warning', True,
     '$null should be on the left side of -eq/-ne'),
    ('PSA2005', 'warning', True,
     'Assignment operator (=) inside conditional'),
    ('PSA2006', 'warning', True,
     'Redirection operator (>, <) inside conditional'),

    # Coding-pattern (PSA3xxx)
    ('PSA3001', 'warning', True,
     'Start-Process -ArgumentList; prefer ProcessStartInfo'),
    ('PSA3002', 'warning', True,
     'Backtick continuation followed by empty line'),
    ('PSA3003', 'warning', True,
     '-match against literal empty string'),
    ('PSA3004', 'warning', True,
     'Empty catch block'),
    ('PSA3005', 'warning', True,
     'Start-Transcript -Path; prefer -LiteralPath for special characters'),

    # Style / info (PSA4xxx)
    ('PSA4001', 'info',    True,
     'Unfinished marker (TODO/FIXME/XXX/HACK)'),
    ('PSA4002', 'info',    True,
     'Trailing whitespace at end of line'),
    ('PSA4003', 'info',    False,
     'Long line exceeds max_line_length'),
    ('PSA4004', 'info',    True,
     'Trailing semicolon at end of line'),

    # Security (PSA5xxx)
    ('PSA5001', 'error',   True,
     'Plain-text password parameter ([string]$Password)'),
    ('PSA5002', 'warning', True,
     'Invoke-Expression should be avoided'),
    ('PSA5003', 'warning', True,
     'Broken hash algorithm (MD5 / SHA1)'),
    ('PSA5004', 'warning', True,
     'Hardcoded ComputerName'),

    # Best-practice (PSA6xxx)
    ('PSA6001', 'warning', True,
     'Function uses non-approved verb'),
    ('PSA6002', 'warning', False,
     'Cmdlet alias used (e.g., ls, cd, dir, where)'),
    ('PSA6003', 'warning', True,
     'Function noun should be singular'),
    ('PSA6004', 'warning', True,
     'Avoid $global: variable definition'),
    ('PSA6005', 'warning', True,
     'Mandatory parameter must not have a default value'),
    ('PSA6006', 'warning', True,
     'Switch parameter must not default to $true'),

    # File format / encoding (PSA7xxx)
    ('PSA7001', 'warning', True,
     'PowerShell script lacks UTF-8 BOM'),

    # Cross-file / multi-script consistency (PSA8xxx, new in v3.2.0)
    ('PSA8001', 'warning', True,
     'Function body hash drift across files in the same scan'),

    # Complexity / metrics (PSA9xxx, new in v3.2.0)
    ('PSA9001', 'info',    False,
     'Function body exceeds max_function_lines'),
    ('PSA9002', 'warning', False,
     'External-process invocation without $LASTEXITCODE check'),

    # -----------------------------------------------------------------
    # Project / pipeline convention rules (PSAPxxxx, new in v3.2.0)
    # All disabled by default; opt in via configuration when your
    # repository follows the relevant convention.
    # -----------------------------------------------------------------
    ('PSAP0001', 'warning', False,
     'Phase function naming convention (Invoke-(Prep|Verify|Inst)PhaseNN_Name)'),
    ('PSAP0002', 'warning', False,
     'Required script identifier variables ($Script:ScriptVersion / Hash / ShortTag)'),
]

CODE_TO_RULE = {r[0]: r for r in RULES}

# ---------------------------------------------------------------------------
# PowerShell approved verbs (subset; from Get-Verb output, Sep 2024)
# ---------------------------------------------------------------------------

APPROVED_VERBS = {
    # Common
    'add', 'clear', 'close', 'copy', 'enter', 'exit', 'find', 'format',
    'get', 'hide', 'join', 'lock', 'move', 'new', 'open', 'optimize',
    'pop', 'push', 'redo', 'remove', 'rename', 'reset', 'resize', 'search',
    'select', 'set', 'show', 'skip', 'split', 'step', 'switch', 'undo',
    'unlock', 'watch',
    # Communications
    'connect', 'disconnect', 'read', 'receive', 'send', 'write',
    # Data
    'backup', 'checkpoint', 'compare', 'compress', 'convert', 'convertfrom',
    'convertto', 'dismount', 'edit', 'expand', 'export', 'group', 'import',
    'initialize', 'limit', 'merge', 'mount', 'out', 'publish', 'restore',
    'save', 'sync', 'unpublish', 'update',
    # Diagnostic
    'debug', 'measure', 'ping', 'repair', 'resolve', 'test', 'trace',
    # Lifecycle
    'approve', 'assert', 'build', 'complete', 'confirm', 'deny', 'deploy',
    'disable', 'enable', 'install', 'invoke', 'register', 'request',
    'restart', 'resume', 'start', 'stop', 'submit', 'suspend',
    'uninstall', 'unregister', 'wait',
    # Security
    'block', 'grant', 'protect', 'revoke', 'unblock', 'unprotect',
    # Other
    'use',
}

# Common cmdlet aliases (subset of Get-Alias output)
CMDLET_ALIASES = {
    'ac', 'asnp', 'cat', 'cd', 'chdir', 'clc', 'clear', 'clhy', 'cli',
    'clp', 'cls', 'clv', 'compare', 'copy', 'cp', 'cpi', 'cpp', 'curl',
    'cvpa', 'dbp', 'del', 'diff', 'dir', 'dnsn', 'ebp', 'echo', 'epal',
    'epcsv', 'epsn', 'erase', 'etsn', 'exsn', 'fc', 'fl', 'foreach',
    'ft', 'fw', 'gal', 'gbp', 'gc', 'gci', 'gcm', 'gcs', 'gdr', 'ghy',
    'gi', 'gjb', 'gl', 'gm', 'gmo', 'gp', 'gps', 'group', 'gsn', 'gsnp',
    'gsv', 'gu', 'gv', 'gwmi', 'h', 'history', 'icm', 'iex', 'ihy', 'ii',
    'ipal', 'ipcsv', 'ipmo', 'ipsn', 'irm', 'ise', 'iwmi', 'iwr', 'kill',
    'lp', 'ls', 'man', 'md', 'measure', 'mi', 'mount', 'move', 'mp',
    'mv', 'nal', 'ndr', 'ni', 'nmo', 'npssc', 'nsn', 'nv', 'ogv', 'oh',
    'popd', 'ps', 'pushd', 'pwd', 'r', 'rbp', 'rcjb', 'rcsn', 'rd',
    'rdr', 'ren', 'ri', 'rjb', 'rm', 'rmdir', 'rmo', 'rni', 'rnp', 'rp',
    'rsn', 'rsnp', 'rujb', 'rv', 'rvpa', 'rwmi', 'sajb', 'sal', 'saps',
    'sasv', 'sbp', 'sc', 'select', 'set', 'shcm', 'si', 'sl', 'sleep',
    'sls', 'sort', 'sp', 'spjb', 'spps', 'spsv', 'start', 'stz', 'sv',
    'swmi', 'tee', 'trcm', 'type', 'where', 'wjb', 'write',
}

# Auto-variables (from about_Automatic_Variables)
AUTO_VARS = {
    '_', '?', '$', '^',
    'args', 'consolefilename', 'error', 'event', 'eventargs',
    'eventsubscriber', 'executioncontext', 'false', 'foreach',
    'home', 'host', 'input', 'lastexitcode', 'matches', 'myinvocation',
    'nestedpromptlevel', 'null', 'ofs', 'pid', 'profile',
    'psboundparameters', 'pscmdlet', 'pscommandpath', 'psculture',
    'psdebugcontext', 'pshome', 'psitem', 'psscriptroot',
    'pssenderinfo', 'psuiculture', 'psversiontable', 'pwd',
    'sender', 'shellid', 'stacktrace', 'switch', 'this', 'true',
}

EXTERNAL_SCOPES = {
    # Truly external, set by the runtime / environment / caller
    'env',         # $env:PATH etc., set by the OS
    'using',       # $using:var, captured from caller scope (Invoke-Command)
    # Explicit scope qualifiers. When the script author writes
    # `$Script:foo` or `$global:foo`, they are signalling "I expect this
    # to be a script-level / global-level variable, possibly set by a
    # top-level param block or by an outer script". Treating these as
    # always-defined avoids a large class of false positives where a
    # top-level `param([switch]$Foo)` declaration is referenced from
    # within a function as `$Script:Foo`. Added in v3.2.0.
    'script',
    'global',
    'local',       # explicit local scope qualifier
    'private',     # explicit private scope qualifier
}

# Auto-variables that are particularly risky to shadow
RISKY_SHADOW_VARS = {
    'args', 'lastexitcode', 'input', 'matches', 'foreach',
    'host', 'true', 'false',
}

# ---------------------------------------------------------------------------
# Tokenizer / string stripper
# ---------------------------------------------------------------------------
# Strategy: a single forward pass that knows about
#   - line comments       (# ... end-of-line)
#   - block comments      (<# ... #>)
#   - single-quoted str   ('...', no interpolation, '' escape)
#   - double-quoted str   ("...", with $var interpolation kept visible)
#   - here-string (sq)    (@'\n ... \n'@)
#   - here-string (dq)    (@"\n ... \n"@, with $var interpolation kept)
# Output: characters at the same position, but with quoted / commented text
# replaced by spaces so that downstream regex sees only "real" PowerShell
# code. The exception is $var inside "..." which we preserve so that
# reference-collection rules still see it.


def strip_strings_and_comments(text):
    """Return a copy of text with all comments and string contents replaced
    by spaces, but with $variables inside double-quoted strings preserved.

    The returned string has the same length and same line breaks as the
    original, so line numbers and column offsets are preserved.
    """
    out = []
    i, n = 0, len(text)
    in_sq = False         # single-quoted string
    in_dq = False         # double-quoted string
    in_lc = False         # single-line comment
    in_bc = False         # block comment
    in_here_sq = False    # @' ... '@
    in_here_dq = False    # @" ... "@

    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ''
        nxt2 = text[i + 2] if i + 2 < n else ''

        # newline always preserved; resets line comment
        if c == '\n':
            out.append('\n')
            if in_lc:
                in_lc = False
            i += 1
            continue

        # --- end of states ---
        if in_lc:
            out.append(' ')
            i += 1
            continue

        if in_bc:
            if c == '#' and nxt == '>':
                out.append('  ')
                in_bc = False
                i += 2
                continue
            out.append(' ')
            i += 1
            continue

        if in_here_sq:
            # close: line-start (or just whitespace) followed by '@
            # PowerShell requires '@ at column 0 of a line; we accept any
            # position for robustness.
            if c == "'" and nxt == '@':
                out.append('  ')
                in_here_sq = False
                i += 2
                continue
            out.append(' ')
            i += 1
            continue

        if in_here_dq:
            if c == '"' and nxt == '@':
                out.append('  ')
                in_here_dq = False
                i += 2
                continue
            # preserve $variables for reference scanning
            if c == '$':
                out.append('$')
                i += 1
                while i < n and (text[i].isalnum() or text[i] in '_:'):
                    out.append(text[i])
                    i += 1
                continue
            out.append(' ')
            i += 1
            continue

        if in_sq:
            if c == "'":
                if nxt == "'":   # '' is an escaped single quote
                    out.append('  ')
                    i += 2
                    continue
                in_sq = False
                out.append(' ')
                i += 1
                continue
            out.append(' ')
            i += 1
            continue

        if in_dq:
            # PowerShell's backtick (`) is the escape character inside
            # double-quoted strings. It consumes the next character (which
            # becomes a literal in the string). This handles:
            #   `"  -> literal "      (so the " does NOT close the string)
            #   `$  -> literal $      (so the $ does NOT start a variable)
            #   ``  -> literal `      (so the second ` is NOT an escape)
            #   `n / `t / etc -> control chars
            # Doing this BEFORE the `"`/`$` checks below avoids two classes
            # of mis-parses: (a) thinking a backtick-escaped `"` ended the
            # string, (b) thinking the SECOND backtick of a `` pair was an
            # escape target. Without this, lines like
            #   "...-CleanWorkRoot ``"
            # (where `` is a literal backtick followed by a closing ") used
            # to leak the dq state to the next line.
            if c == '`':
                # Consume the backtick AND the next character (whatever
                # it is) as a single escape sequence. Output two spaces
                # to preserve column alignment for line/col reporting.
                if i + 1 < n:
                    out.append('  ')
                    i += 2
                else:
                    out.append(' ')
                    i += 1
                continue
            if c == '"':
                # PowerShell escape: "" inside "..." represents a literal "
                # (analogous to '' inside '...'). Skip both characters and
                # remain in double-quoted state. This is essential for
                # strings like "she said ""hello""" which would otherwise
                # be miscounted as having unbalanced quotes.
                if nxt == '"':
                    out.append('  '); i += 2; continue
                in_dq = False
                out.append(' ')
                i += 1
                continue
            if c == '$':
                out.append('$')
                i += 1
                # collect identifier  $var, $scope:var, ${complex}
                if i < n and text[i] == '{':
                    out.append('{')
                    i += 1
                    while i < n and text[i] != '}':
                        out.append(text[i])
                        i += 1
                    if i < n:
                        out.append('}')
                        i += 1
                    continue
                while i < n and (text[i].isalnum() or text[i] in '_:'):
                    out.append(text[i])
                    i += 1
                continue
            out.append(' ')
            i += 1
            continue

        # --- start of states ---
        # here-string start must be checked before single/double quote
        if c == '@' and nxt == "'":
            out.append('  ')
            in_here_sq = True
            i += 2
            continue
        if c == '@' and nxt == '"':
            out.append('  ')
            in_here_dq = True
            i += 2
            continue
        if c == '<' and nxt == '#':
            out.append('  ')
            in_bc = True
            i += 2
            continue
        if c == '#':
            out.append(' ')
            in_lc = True
            i += 1
            continue
        if c == "'":
            in_sq = True
            out.append(' ')
            i += 1
            continue
        if c == '"':
            in_dq = True
            out.append(' ')
            i += 1
            continue

        out.append(c)
        i += 1

    return ''.join(out)


# ---------------------------------------------------------------------------
# Bracket / paren / brace balance
# ---------------------------------------------------------------------------

def _balance(clean, open_ch, close_ch):
    """Count occurrences of open_ch and close_ch in *clean* (which has had
    comments and strings stripped). Returns (open_count, close_count)."""
    return clean.count(open_ch), clean.count(close_ch)


def check_balance(text, clean, open_ch, close_ch, code):
    o, c = _balance(clean, open_ch, close_ch)
    if o != c:
        return [{
            'severity': 'error', 'code': code, 'line': 0, 'col': 0,
            'message': f'{open_ch}{close_ch} mismatch: {o} {open_ch} vs {c} {close_ch}',
        }]
    return []


# ---------------------------------------------------------------------------
# Function / param parsing
# ---------------------------------------------------------------------------

ASSIGN_PATTERNS = [
    re.compile(r'\$(?:[A-Za-z]+:)?([A-Za-z_][A-Za-z0-9_]*)\s*='),
    re.compile(r'foreach\s*\(\s*\$([A-Za-z_][A-Za-z0-9_]*)\s+in\b',
               re.IGNORECASE),
    re.compile(r'for\s*\(\s*\$([A-Za-z_][A-Za-z0-9_]*)\s*=',
               re.IGNORECASE),
]
PARAM_VAR = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*)')
INLINE_FN_PARAMS = re.compile(
    r'^\s*function\s+[A-Za-z_][A-Za-z0-9_-]*\s*\(([^)]*)\)\s*\{?',
    re.IGNORECASE)
REFERENCE_PATTERN = re.compile(
    r'\$(?:(?P<scope>[A-Za-z]+):)?(?P<name>[A-Za-z_][A-Za-z0-9_]*)')


def find_function_blocks(clean):
    """Find every 'function Name { ... }' block in *clean* (already stripped).
    Returns list of (name, start_line_1based, end_line_1based, body_text)."""
    blocks = []
    lines = clean.split('\n')
    i = 0
    while i < len(lines):
        m = re.match(
            r'^\s*function\s+([A-Za-z_][A-Za-z0-9_-]*)\s*\{?', lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        start = i
        depth = 0
        seen = False
        j = i
        while j < len(lines):
            for ch in lines[j]:
                if ch == '{':
                    depth += 1
                    seen = True
                elif ch == '}':
                    depth -= 1
            if seen and depth == 0:
                break
            j += 1
        body = '\n'.join(lines[start:j + 1])
        blocks.append((name, start + 1, j + 1, body))
        i = j + 1
    return blocks


def find_param_blocks(body):
    """Find each param(...) block with balanced parens; return inner text."""
    out = []
    pat = re.compile(r'\bparam\s*\(', re.IGNORECASE)
    pos = 0
    while True:
        m = pat.search(body, pos)
        if not m:
            break
        start = m.end()
        depth = 1
        i = start
        while i < len(body) and depth > 0:
            c = body[i]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
            i += 1
        if depth == 0:
            out.append(body[start:i - 1])
        pos = i
    return out


def collect_assignments(body):
    """Collect names that are assigned within *body*. *body* is already
    stripped of strings/comments."""
    assigned = set()
    for line in body.split('\n'):
        for pat in ASSIGN_PATTERNS:
            for m in pat.finditer(line):
                assigned.add(m.group(1).lower())
        m = INLINE_FN_PARAMS.match(line)
        if m:
            for vm in PARAM_VAR.finditer(m.group(1)):
                assigned.add(vm.group(1).lower())
    for block in find_param_blocks(body):
        for vm in PARAM_VAR.finditer(block):
            assigned.add(vm.group(1).lower())
    return assigned


def collect_references(body):
    """Yield (name, relative_line_1based) for each $variable reference
    that is NOT the target of an assignment, and NOT an external scope
    ($env:..., $using:...)."""
    refs = []
    for ln_no, line in enumerate(body.split('\n'), start=1):
        for m in REFERENCE_PATTERN.finditer(line):
            scope = (m.group('scope') or '').lower()
            if scope in EXTERNAL_SCOPES:
                continue
            after = line[m.end():m.end() + 4].lstrip()
            if after.startswith('='):
                continue
            refs.append((m.group('name').lower(), ln_no))
    return refs


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

def check_undefined_vars(text, clean):
    """PSA2001: heuristic undefined-variable warning."""
    issues = []
    blocks = find_function_blocks(clean)
    fn_ranges = [(b[1], b[2]) for b in blocks]

    def in_fn(n):
        return any(s <= n <= e for s, e in fn_ranges)

    global_assigned = set()
    for ln_no, line in enumerate(clean.split('\n'), start=1):
        if in_fn(ln_no):
            continue
        for pat in ASSIGN_PATTERNS:
            for m in pat.finditer(line):
                global_assigned.add(m.group(1).lower())

    seen = set()
    for fname, start, _end, body in blocks:
        local = collect_assignments(body)
        for name, ln in collect_references(body):
            if name in AUTO_VARS or name in local or name in global_assigned:
                continue
            key = (name, fname)
            if key in seen:
                continue
            seen.add(key)
            issues.append({
                'severity': 'error', 'code': 'PSA2001',
                'line': start + ln - 1, 'col': 0,
                'message': f'undefined variable ${name} in function {fname}',
            })
    return issues


def check_shadow(clean):
    """PSA2002: assigning to a risky auto-variable."""
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in re.finditer(r'\$([A-Za-z_][A-Za-z0-9_]*)\s*=', line):
            if m.group(1).lower() in RISKY_SHADOW_VARS:
                out.append({
                    'severity': 'warning', 'code': 'PSA2002',
                    'line': ln, 'col': m.start() + 1,
                    'message': f'shadowing auto-variable ${m.group(1)}',
                })
    return out


def check_match_var(clean):
    """PSA2003: -match against bare $variable."""
    pat = re.compile(
        r'-match\s+\$(?!null\b)([A-Za-z_][A-Za-z0-9_:]*)', re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            out.append({
                'severity': 'warning', 'code': 'PSA2003',
                'line': ln, 'col': m.start() + 1,
                'message': (f'-match against bare ${m.group(1)} - '
                            '$null pattern returns true'),
            })
    return out


def check_null_on_right(clean):
    """PSA2004: $x -eq $null should be $null -eq $x.

    The right-hand-$null form is dangerous when $x is a collection — it
    returns the elements equal to $null, not a boolean.
    """
    pat = re.compile(
        r'\$[A-Za-z_][A-Za-z0-9_:.]*\s*(-eq|-ne|-ceq|-cne|-ieq|-ine)\s*\$null\b',
        re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            out.append({
                'severity': 'warning', 'code': 'PSA2004',
                'line': ln, 'col': m.start() + 1,
                'message': f'place $null on the left side of {m.group(1)}',
            })
    return out


def check_assign_in_conditional(clean):
    """PSA2005: 'if ($x = 5)' is almost always a typo for '-eq'."""
    # Match: if/while/elseif ( $var = <not = or comparison> ... )
    pat = re.compile(
        r'\b(if|while|elseif)\s*\(\s*\$[A-Za-z_][A-Za-z0-9_:.]*\s*=(?!=)',
        re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            out.append({
                'severity': 'warning', 'code': 'PSA2005',
                'line': ln, 'col': m.start() + 1,
                'message': (f'assignment operator (=) inside '
                            f'{m.group(1)} condition; did you mean -eq?'),
            })
    return out


def check_redirect_in_conditional(clean):
    """PSA2006: 'if ($x > 5)' is a redirection, not a comparison."""
    pat = re.compile(
        r'\b(if|while|elseif)\s*\(\s*\$[A-Za-z_][A-Za-z0-9_:.]*\s*[<>][^=\-]',
        re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            out.append({
                'severity': 'warning', 'code': 'PSA2006',
                'line': ln, 'col': m.start() + 1,
                'message': (f'redirection operator inside {m.group(1)} '
                            'condition; use -gt / -lt'),
            })
    return out


def check_argumentlist(clean):
    """PSA3001: Start-Process -ArgumentList."""
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        if re.search(r'Start-Process\b.*-ArgumentList\b',
                     line, re.IGNORECASE):
            out.append({
                'severity': 'warning', 'code': 'PSA3001',
                'line': ln, 'col': 0,
                'message': ('Start-Process -ArgumentList; '
                            'prefer ProcessStartInfo'),
            })
    return out


def check_backtick(text):
    """PSA3002: trailing backtick before empty line.

    Uses the *raw* text so that trailing whitespace after the backtick
    can also be flagged. Comments are unlikely to end in backtick, so we
    skip the strip for this check.
    """
    out = []
    lines = text.split('\n')
    for i, line in enumerate(lines):
        s = line.rstrip('\r\n')
        if s.endswith('`') and not s.endswith('``'):
            if i + 1 < len(lines) and not lines[i + 1].strip():
                out.append({
                    'severity': 'warning', 'code': 'PSA3002',
                    'line': i + 1, 'col': len(s),
                    'message': ('backtick continuation followed by '
                                'empty line'),
                })
    return out


def check_empty_match(clean):
    """PSA3003: -match against literal empty string.

    We rely on the *raw* form via the regex below — but since the strip
    pass replaces quoted contents with spaces, we use a slightly different
    detection: '-match' immediately followed by quote-quote pattern in
    the raw text.
    """
    # Use raw text scan because strip converts "" to spaces.
    return _check_empty_match_raw_marker(clean)


def _check_empty_match_raw_marker(text):
    pat = re.compile(r"-match\s+(?:''|\"\")")
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        if pat.search(line):
            out.append({
                'severity': 'warning', 'code': 'PSA3003',
                'line': ln, 'col': 0,
                'message': '-match against empty string is always true',
            })
    return out


def check_empty_catch(clean):
    """PSA3004: catch { } with no body."""
    pat = re.compile(
        r'\bcatch\s*(\[[^\]]+\]\s*)*\{\s*\}',
        re.IGNORECASE | re.DOTALL)
    out = []
    # Search line-by-line to keep line numbers.  Also handle multi-line
    # 'catch {\n}' by joining short windows.
    lines = clean.split('\n')
    for i, line in enumerate(lines):
        # Look ahead up to 3 lines for opening/closing brace pair.
        window = '\n'.join(lines[i:i + 4])
        m = pat.match(window.lstrip())
        if not m:
            # Try inline match anywhere on this line.
            if pat.search(line):
                out.append({
                    'severity': 'warning', 'code': 'PSA3004',
                    'line': i + 1, 'col': 0,
                    'message': 'empty catch block',
                })
        else:
            out.append({
                'severity': 'warning', 'code': 'PSA3004',
                'line': i + 1, 'col': 0,
                'message': 'empty catch block',
            })
    return out


def check_start_transcript_literalpath(clean):
    """PSA3005: Start-Transcript with -Path should prefer -LiteralPath.

    Rationale: Start-Transcript -Path performs wildcard expansion on its
    argument. Paths containing PowerShell metacharacters such as [, ],
    or backtick will be misinterpreted. -LiteralPath disables expansion
    and is the safer default for log-file capture.

    The rule fires when a Start-Transcript invocation either:
      - explicitly uses -Path, or
      - uses positional binding (which also binds to -Path).
    Invocations already using -LiteralPath are silent.
    """
    out = []
    lines = clean.split('\n')
    for ln_no, raw in enumerate(lines, start=1):
        if 'Start-Transcript' not in raw:
            continue
        # Build the logical line by joining backtick-continuations to
        # avoid splitting an invocation across the LiteralPath check.
        idx = ln_no - 1
        logical = raw
        peek = idx
        while logical.rstrip().endswith('`') and peek + 1 < len(lines):
            peek += 1
            logical = logical.rstrip().rstrip('`') + ' ' + lines[peek]
        # Skip if already using -LiteralPath
        if re.search(r'-LiteralPath\b', logical, re.IGNORECASE):
            continue
        # Match the invocation. Either:
        #   Start-Transcript ... -Path  (explicit)
        #   Start-Transcript <non-switch token>  (positional)
        if re.search(
                r'\bStart-Transcript\b\s+(?:-[A-Za-z][\w-]*\s+\S+\s+)*'
                r'(?:-Path\b|[^\s\-][^\s]*)',
                logical):
            col = raw.find('Start-Transcript') + 1
            out.append({
                'severity': 'warning', 'code': 'PSA3005',
                'line': ln_no, 'col': max(1, col),
                'message': (
                    'Start-Transcript without -LiteralPath; -Path is '
                    'wildcard-expanded and unsafe for paths containing '
                    '[ ] or other PowerShell metacharacters'),
            })
    return out


def check_todo(text):
    """PSA4001: TODO/FIXME markers (in comments only).

    v3.2.0 refinement: require the marker to be a real "actionable"
    marker, not just an English word that happens to be capitalized.
    Real markers follow these forms:
      - TODO:  / FIXME: / XXX: / HACK:   (colon-terminated)
      - "TODO " at the very start of the comment body (after '#')
      - Inline form  '# TODO foo' / '# FIXME bar'
    Excluded (treated as plain prose, not markers):
      - The marker appears inside a quoted string literal embedded
        in the comment, e.g.  # bare `Write-Host "    XXX"` calls
      - The marker is part of a larger identifier (already handled by
        the \b word boundary)
    """
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        if '#' not in line:
            continue
        hash_pos = line.find('#')
        # Skip lines where '#' is inside a string literal. Simple heuristic:
        # count unescaped quotes before the '#'; if odd, we're inside a string.
        before = line[:hash_pos]
        # Drop backtick-escaped quotes
        before_clean = re.sub(r'`.', '', before)
        if before_clean.count('"') % 2 == 1 or before_clean.count("'") % 2 == 1:
            continue
        comment = line[hash_pos + 1:]
        # Strip away any embedded string literals so that markers inside
        # examples like  Write-Host "    XXX"  are ignored.
        comment_stripped = re.sub(r'"[^"]*"', '', comment)
        comment_stripped = re.sub(r"'[^']*'", '', comment_stripped)
        comment_stripped = re.sub(r'`[^`]*`', '', comment_stripped)  # backtick spans
        m = re.search(r'\b(TODO|FIXME|XXX|HACK)\b(\s*:|\s+[A-Za-z])', comment_stripped)
        if m:
            out.append({
                'severity': 'info', 'code': 'PSA4001',
                'line': ln, 'col': line.find(m.group(1), hash_pos) + 1,
                'message': f'unfinished marker: {m.group(1)}',
            })
    return out


def check_trailing_whitespace(text):
    """PSA4002: trailing whitespace at end of line."""
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        s = line.rstrip('\r\n')
        if s and s != s.rstrip():
            out.append({
                'severity': 'info', 'code': 'PSA4002',
                'line': ln, 'col': len(s.rstrip()) + 1,
                'message': 'trailing whitespace',
            })
    return out


def check_long_line(text, max_len):
    """PSA4003: line exceeds max_line_length characters."""
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        s = line.rstrip('\r\n')
        if len(s) > max_len:
            out.append({
                'severity': 'info', 'code': 'PSA4003',
                'line': ln, 'col': max_len + 1,
                'message': f'line is {len(s)} chars (max {max_len})',
            })
    return out


def check_trailing_semicolon(clean):
    """PSA4004: line ends with a semicolon (PowerShell idiom prefers no ;)."""
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        s = line.rstrip()
        if s.endswith(';') and not s.endswith(';;'):
            out.append({
                'severity': 'info', 'code': 'PSA4004',
                'line': ln, 'col': len(s),
                'message': 'trailing semicolon is redundant',
            })
    return out


def check_plaintext_password(clean):
    """PSA5001: [string]$Password (and similar) is plain-text."""
    pat = re.compile(
        r'\[string\]\s*\$(\w*[Pp]assword\w*|\w*[Pp]wd\w*|\w*[Cc]redential\w*)',
        re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            out.append({
                'severity': 'error', 'code': 'PSA5001',
                'line': ln, 'col': m.start() + 1,
                'message': (f'plain-text password parameter ${m.group(1)}; '
                            'use [SecureString] or [PSCredential]'),
            })
    return out


def check_invoke_expression(clean):
    """PSA5002: Invoke-Expression is an arbitrary-code-execution risk."""
    pat = re.compile(r'\b(Invoke-Expression|\biex)\b', re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            out.append({
                'severity': 'warning', 'code': 'PSA5002',
                'line': ln, 'col': m.start() + 1,
                'message': ('Invoke-Expression executes arbitrary strings; '
                            'consider safer alternatives'),
            })
    return out


def check_broken_hash(clean):
    """PSA5003: MD5 / SHA1 are cryptographically broken."""
    pat = re.compile(
        r'(MD5|SHA1)(?:CryptoServiceProvider|Managed)?\b|'
        r'-Algorithm\s+["\']?(MD5|SHA1)\b',
        re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            algo = (m.group(1) or m.group(2)).upper()
            out.append({
                'severity': 'warning', 'code': 'PSA5003',
                'line': ln, 'col': m.start() + 1,
                'message': (f'{algo} is cryptographically broken; '
                            'use SHA-256 or stronger'),
            })
    return out


def check_hardcoded_computername(clean):
    """PSA5004: -ComputerName "literal string" (not $var)."""
    pat = re.compile(
        r'-ComputerName\s+(?:"([^"]+)"|\'([^\']+)\')',
        re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            host = m.group(1) or m.group(2)
            # localhost / . are common legitimate uses
            if host.lower() in ('localhost', '.', '127.0.0.1'):
                continue
            out.append({
                'severity': 'warning', 'code': 'PSA5004',
                'line': ln, 'col': m.start() + 1,
                'message': (f'hardcoded ComputerName "{host}"; '
                            'pass via parameter'),
            })
    return out


def check_approved_verb(clean):
    """PSA6001: function name uses non-approved verb."""
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        m = re.match(
            r'^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)-([A-Za-z_][A-Za-z0-9_]*)',
            line)
        if not m:
            continue
        verb = m.group(1).lower()
        if verb not in APPROVED_VERBS:
            out.append({
                'severity': 'warning', 'code': 'PSA6001',
                'line': ln, 'col': 0,
                'message': (f'non-approved verb "{m.group(1)}"; '
                            'see Get-Verb'),
            })
    return out


def check_cmdlet_alias(clean):
    """PSA6002: alias used instead of a full cmdlet name.

    Only matches at the start of a logical command position: line start,
    after a semicolon, after a pipe, or at the start of a parenthesised
    sub-expression.  This dramatically reduces noise from words like
    'where' appearing inside comments — already stripped — or as a
    parameter value (still possible but rare).

    Special-case: `foreach (` and `switch (` are PowerShell keywords for
    loops, not aliases for `ForEach-Object` / `Switch-Statement`. They
    are excluded.
    """
    out = []
    pat = re.compile(
        r'(?:^|[;|&]|\(\s*)\s*(' + '|'.join(re.escape(a)
                                            for a in sorted(CMDLET_ALIASES,
                                                            key=len,
                                                            reverse=True)) +
        r')\b(?=\s|$)',
        re.IGNORECASE | re.MULTILINE)
    # Keywords that share their name with an alias must be skipped when
    # used in their statement form (followed by '(').
    KEYWORD_FORMS = {'foreach', 'switch', 'select', 'sort', 'set'}
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            alias = m.group(1).lower()
            # Skip the PowerShell keyword form: `foreach (`, `switch (`...
            tail = line[m.end():m.end() + 2].lstrip()
            if alias in KEYWORD_FORMS and tail.startswith('('):
                continue
            # Skip hashtable-key / property-assignment form:
            #   @{ type = 'foo' }  or  $obj.type = 1  etc.
            if re.match(r'\s*=(?!=)', line[m.end():]):
                continue
            out.append({
                'severity': 'warning', 'code': 'PSA6002',
                'line': ln, 'col': m.start(1) + 1,
                'message': (f'cmdlet alias "{alias}" used; '
                            'prefer the full cmdlet name'),
            })
    return out


def check_singular_noun(clean):
    """PSA6003: function noun should be singular (heuristic: ends in 's').

    False-positive prone (e.g., Get-Process is correct), so we use a
    small whitelist of legitimately-plural nouns commonly seen.
    """
    LEGIT_PLURAL = {
        'process', 'address', 'progress', 'access', 'success', 'class',
        'pass', 'business', 'analysis', 'basis', 'series', 'species',
        'thesis', 'crisis', 'status', 'bus',
    }
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        m = re.match(
            r'^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)-'
            r'([A-Za-z_][A-Za-z0-9_]*)',
            line)
        if not m:
            continue
        noun = m.group(2)
        nl = noun.lower()
        if nl.endswith('s') and nl not in LEGIT_PLURAL and not nl.endswith('ss'):
            out.append({
                'severity': 'warning', 'code': 'PSA6003',
                'line': ln, 'col': 0,
                'message': (f'function noun "{noun}" appears plural; '
                            'use singular form'),
            })
    return out


def check_global_var(clean):
    """PSA6004: avoid $global: variable definition."""
    pat = re.compile(r'\$global:[A-Za-z_][A-Za-z0-9_]*\s*=', re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        for m in pat.finditer(line):
            out.append({
                'severity': 'warning', 'code': 'PSA6004',
                'line': ln, 'col': m.start() + 1,
                'message': ('avoid defining $global: variables; '
                            'use $script: or pass as parameter'),
            })
    return out


def check_mandatory_default(clean):
    """PSA6005: [Parameter(Mandatory)] with default value."""
    # Find lines like  [Parameter(Mandatory ...)] [type] $Name = default
    out = []
    pat = re.compile(
        r'\[Parameter\([^)]*Mandatory[^)]*\)\][^=\n]*\$[A-Za-z_]\w*\s*=',
        re.IGNORECASE)
    for ln, line in enumerate(clean.split('\n'), 1):
        if pat.search(line):
            out.append({
                'severity': 'warning', 'code': 'PSA6005',
                'line': ln, 'col': 0,
                'message': ('Mandatory parameter must not have a default '
                            'value'),
            })
    return out


def check_switch_default_true(clean):
    """PSA6006: [switch]$Name = $true."""
    pat = re.compile(
        r'\[switch\]\s*\$[A-Za-z_]\w*\s*=\s*\$true\b',
        re.IGNORECASE)
    out = []
    for ln, line in enumerate(clean.split('\n'), 1):
        if pat.search(line):
            out.append({
                'severity': 'warning', 'code': 'PSA6006',
                'line': ln, 'col': 0,
                'message': ('switch parameter must not default to $true; '
                            'switches default to $false'),
            })
    return out


# ---------------------------------------------------------------------------
# File format / encoding checks (PSA7xxx)
# ---------------------------------------------------------------------------
# These rules operate on file-level metadata rather than on the decoded text
# body, because some checks (BOM presence, byte-encoding sniffing, etc.) need
# information that is lost once Python has decoded the file to a str.
# Such metadata is computed in main() before decoding and passed to
# analyze_text() via the optional file_meta dict.


def check_utf8_bom_missing(file_meta):
    """PSA7001: PowerShell script lacks UTF-8 BOM.

    Windows PowerShell 5.1 falls back to the system Active Code Page
    (Shift-JIS / cp932 on ja-JP locales) when a script has no BOM and
    contains non-ASCII bytes, causing mojibake in the script's log
    output. Including the UTF-8 BOM forces correct interpretation
    regardless of console code page.

    Parameters
    ----------
    file_meta : dict | None
        Optional metadata dict. Must contain 'has_bom' (bool) when this
        rule is to fire meaningfully. When None or missing, the rule
        emits nothing (preserves backward compatibility for callers
        that only pass text).
    """
    if not file_meta:
        return []
    # Default True: when 'has_bom' is unknown (e.g. legacy callers that
    # pass an empty dict), assume a BOM is present and stay silent rather
    # than producing a false positive.
    if file_meta.get('has_bom', True):
        return []
    return [{
        'severity': 'warning', 'code': 'PSA7001',
        'line': 0, 'col': 0,
        'message': ('PowerShell script lacks UTF-8 BOM '
                    '(Windows PowerShell 5.1 may misinterpret non-ASCII '
                    'as Shift-JIS without BOM)'),
    }]


# ---------------------------------------------------------------------------
# Cross-file / multi-script consistency (PSA8xxx)  - new in v3.2.0
# ---------------------------------------------------------------------------
# These rules examine relationships across multiple files in the same scan.
# Single-file invocations of psa.py cannot meaningfully fire any PSA8xxx
# rule; the multi-file analyze() driver in main() collects per-file data
# and runs cross-file checks after the per-file pass.


def collect_function_bodies(clean):
    """Return [(name, start_line, end_line, body_str, body_hash), ...] for
    every top-level `function Name { ... }` block in *clean* (the
    comment- and string-stripped text). Used by PSA8001 to compare
    bodies across files.

    Normalization is aggressive on purpose: differences in comment
    density, blank-line padding, and trailing whitespace MUST NOT
    register as drift, because the rule's intent is to flag CODE
    changes. After strip_strings_and_comments(), comments and strings
    are already whitespace-only; we then collapse all runs of
    whitespace (including newlines) into single spaces before hashing.
    """
    import hashlib
    out = []
    for name, start, end, body in find_function_blocks(clean):
        # body comes from `clean`, so comments and strings are already
        # rendered as whitespace runs. Collapse ALL whitespace into
        # single spaces so that purely-cosmetic differences (extra
        # comment lines, blank lines between code blocks, etc.) cancel.
        normalized = re.sub(r'\s+', ' ', body).strip()
        h = hashlib.sha256(normalized.encode('utf-8')).hexdigest()[:12]
        out.append((name, start, end, body, h))
    return out


def check_function_sync(per_file_function_data, ignore_functions=None):
    """PSA8001: detect function-body hash drift across files.

    *per_file_function_data* is a dict mapping file path -> list of
    (name, start_line, end_line, body, body_hash) tuples as produced by
    collect_function_bodies().

    *ignore_functions* is an optional iterable of function-name patterns
    to skip. Each entry can be either:
      - an exact case-insensitive name match, e.g.
        "Invoke-PrepPhase00_Initialize"
      - a regex pattern prefixed with "regex:", e.g.
        "regex:^Invoke-(Prep|Verify|Inst)Phase\\d{2}_"
    Both forms are matched case-insensitively.

    For each function name that appears in two or more files, all bodies
    must share the same hash. When hashes differ, every occurrence is
    flagged with a PSA8001 entry pointing to the function header line.
    """
    # Compile ignore-list into a fast predicate
    ignore_exact = set()
    ignore_re = []
    for entry in (ignore_functions or []):
        s = entry.strip()
        if not s:
            continue
        if s.lower().startswith('regex:'):
            try:
                ignore_re.append(re.compile(s[6:], re.IGNORECASE))
            except re.error as e:
                print(f'psa.py: invalid PSA8001 ignore regex {s!r}: {e}',
                      file=sys.stderr)
                continue
        else:
            ignore_exact.add(s.lower())

    def is_ignored(name):
        if name.lower() in ignore_exact:
            return True
        for r in ignore_re:
            if r.search(name):
                return True
        return False

    # Build name -> {hash: [(path, start_line), ...]}
    name_index = {}
    for path, fns in per_file_function_data.items():
        for name, start, _end, _body, h in fns:
            if is_ignored(name):
                continue
            name_index.setdefault(name, {}).setdefault(h, []).append(
                (path, start))
    # Emit per-file issues
    issues_by_file = {p: [] for p in per_file_function_data}
    for name, by_hash in name_index.items():
        if len(by_hash) <= 1:
            continue   # only one variant; perfectly synced
        # Drift detected. Build a short summary that names the divergent
        # files so the developer can diff them.
        variants = [(h, locs) for h, locs in by_hash.items()]
        # Sort by number of occurrences descending, so the "majority"
        # variant comes first.
        variants.sort(key=lambda v: -len(v[1]))
        majority_hash = variants[0][0]
        summary_files = []
        for h, locs in variants:
            label = 'canonical' if h == majority_hash else 'drifted'
            summary_files.append(
                f'{label}={h}@{len(locs)} files')
        for h, locs in by_hash.items():
            for path, start in locs:
                msg = (
                    f'function {name} body hash drift across files; '
                    f'this file has hash {h}; '
                    f'observed variants: {", ".join(summary_files)}')
                issues_by_file.setdefault(path, []).append({
                    'severity': 'warning', 'code': 'PSA8001',
                    'line': start, 'col': 0, 'message': msg,
                })
    return issues_by_file


# ---------------------------------------------------------------------------
# Complexity metrics (PSA9xxx) - new in v3.2.0
# ---------------------------------------------------------------------------


def check_long_function(clean, max_lines):
    """PSA9001: function body exceeds *max_lines* (default: 200).

    Counts physical lines from the `function NAME {` header through the
    matching closing brace, inclusive. Comments and blank lines count.
    Disabled by default; opt in via configuration when desired.
    """
    out = []
    for name, start, end, _body in find_function_blocks(clean):
        body_len = end - start + 1
        if body_len > max_lines:
            out.append({
                'severity': 'info', 'code': 'PSA9001',
                'line': start, 'col': 0,
                'message': (
                    f'function {name} is {body_len} lines long '
                    f'(threshold: {max_lines}); consider extracting '
                    f'helpers to keep individual functions reviewable'),
            })
    return out


def check_lastexitcode_unchecked(clean):
    """PSA9002: external-process invocation without a $LASTEXITCODE check.

    PowerShell's `&` operator and native-command invocations do NOT throw
    on non-zero exit. Scripts that drop the exit code silently can mask
    real failures. This rule fires on any line that contains an `& exe`
    or known native-command invocation (msiexec / signtool / inf2cat /
    pnputil / bcdedit / sc.exe / regsvr32 / wevtutil / dism / gpupdate)
    when the next 5 lines do NOT include either:
      - a `$LASTEXITCODE` reference, or
      - an `if (-not $?)` / `$?` reference, or
      - a `-PassThru` capture pattern with subsequent `.ExitCode` access.

    Disabled by default; opt in for scripts that wrap many external
    tools (e.g. driver-deployment / system-administration pipelines).
    """
    out = []
    invocation_pat = re.compile(
        r'(?:\B&\s+[A-Za-z_][\w.\-]*'        # & some-exe
        r'|\b(?:msiexec|signtool|inf2cat|pnputil|bcdedit|sc\.exe|'
        r'regsvr32|wevtutil|dism|gpupdate|certutil|reg\.exe|'
        r'cmd\.exe|cmd|powershell)\b)',
        re.IGNORECASE)
    check_pat = re.compile(
        r'\$LASTEXITCODE\b|\$\?|\.ExitCode\b|-PassThru\b',
        re.IGNORECASE)
    lines = clean.split('\n')
    for ln_no, line in enumerate(lines, start=1):
        if not invocation_pat.search(line):
            continue
        # Skip Start-Process (PowerShell cmdlet, throws on -ErrorAction Stop)
        if re.search(r'\bStart-Process\b', line):
            continue
        window = '\n'.join(lines[ln_no - 1: ln_no + 5])
        if check_pat.search(window):
            continue
        out.append({
            'severity': 'warning', 'code': 'PSA9002',
            'line': ln_no, 'col': 0,
            'message': (
                'external-process invocation without a $LASTEXITCODE / '
                '$? / .ExitCode check within 5 lines; non-zero exits '
                'will be silently ignored'),
        })
    return out


# ---------------------------------------------------------------------------
# Project / pipeline convention rules (PSAPxxxx) - new in v3.2.0
# ---------------------------------------------------------------------------
# These rules encode OPINIONATED conventions specific to a particular
# repository or pipeline style. All PSAPxxxx rules are disabled by default
# and must be explicitly enabled via .psa.config.json or --enable on the
# command line.
#
# Currently shipped conventions:
#   PSAP0001 - 21-phase pipeline naming convention
#              (Invoke-(Prep|Verify|Inst)PhaseNN_Name)
#   PSAP0002 - Required script-identifier variables
#              ($Script:ScriptVersion, $Script:ScriptHash,
#               $Script:ScriptShortTag)
#
# These conventions originated in the Deploy-Drivers-For-WindowsServer
# repository. Adopting repositories should commit a .psa.config.json that
# enables the relevant PSAPxxxx rule(s); see the template in this
# directory.


PHASE_FUNCTION_PAT = re.compile(
    r'^\s*function\s+(Invoke-(?:Prep|Verify|Inst)Phase\d{2}_[A-Za-z][\w]*)\b',
    re.IGNORECASE)
# Anything that LOOKS like a pipeline phase function but doesn't match
# the canonical form. Generous: catches Invoke-Phase00, Invoke-Phase00X,
# Invoke-PrepPhase0_, Invoke-Verify1, etc.
SUSPECTED_PHASE_PAT = re.compile(
    r'^\s*function\s+(Invoke-(?:Prep|Verify|Inst|Phase|Pipeline)\w*)\b',
    re.IGNORECASE)


def check_phase_naming(clean):
    """PSAP0001: phase function naming convention.

    Enforces the 21-phase pipeline naming pattern
    `Invoke-(Prep|Verify|Inst)PhaseNN_DescriptiveName`, used by the
    Deploy-Drivers-For-WindowsServer driver-deployment pipeline. Examples:

        function Invoke-PrepPhase00_Initialize          OK
        function Invoke-VerifyPhase06_HardwareImpact    OK
        function Invoke-InstPhase04_PostInstallVerify   OK

        function Invoke-Phase00                         FAIL
        function Invoke-PrepPhase0_Init                 FAIL
        function Invoke-VerifyHardware                  FAIL

    The rule is intentionally permissive: it only fires on functions
    whose NAMES start with `Invoke-(Prep|Verify|Inst|Phase|Pipeline)`
    but do not match the canonical regex. Other function names are left
    alone.

    Disabled by default. Enable via `enable: ["PSAP0001"]` in your
    .psa.config.json when your repository follows this convention.
    """
    out = []
    for ln_no, line in enumerate(clean.split('\n'), start=1):
        if PHASE_FUNCTION_PAT.match(line):
            continue   # canonical name; OK
        m = SUSPECTED_PHASE_PAT.match(line)
        if not m:
            continue   # not a suspected phase function
        out.append({
            'severity': 'warning', 'code': 'PSAP0001',
            'line': ln_no, 'col': 0,
            'message': (
                f'function {m.group(1)} looks like a pipeline phase '
                f'but does not match the canonical pattern '
                f'Invoke-(Prep|Verify|Inst)PhaseNN_DescriptiveName'),
        })
    return out


REQUIRED_SCRIPT_IDENTIFIERS = [
    'ScriptVersion',
    'ScriptHash',
    'ScriptShortTag',
]


def check_required_script_identifiers(clean):
    """PSAP0002: required script-identifier variables.

    Enforces presence of the script-identification trio used by the
    Deploy-Drivers-For-WindowsServer pipeline scripts:
        $Script:ScriptVersion   = '<family>-<date>-rNN'
        $Script:ScriptHash      = '<git-sha-12>'
        $Script:ScriptShortTag  = ('{0}/{1}' -f $Script:ScriptVersion,
                                   $Script:ScriptHash)
    Reported once per missing identifier at the top of the file. The
    intent is to ensure that PHASE banner output and DebugTrace JSONL
    files contain a stable script-identity field.

    Disabled by default; opt in for repositories that follow this
    convention.
    """
    out = []
    # Assignment patterns: $Script:Name = ...  or  ${Script:Name} = ...
    found = set()
    pat = re.compile(
        r'\$(?:\{)?[Ss]cript:(?P<name>[A-Za-z_][\w]*)(?:\})?\s*=',
        re.MULTILINE)
    for m in pat.finditer(clean):
        found.add(m.group('name'))
    for required in REQUIRED_SCRIPT_IDENTIFIERS:
        if required not in found:
            out.append({
                'severity': 'warning', 'code': 'PSAP0002',
                'line': 1, 'col': 0,
                'message': (
                    f'required script-identifier variable '
                    f'$Script:{required} is not assigned anywhere in '
                    f'this file (pipeline convention; see PSAP0002)'),
            })
    return out


# ---------------------------------------------------------------------------
# Inline suppression
# ---------------------------------------------------------------------------

SUPPRESS_LINE_PAT = re.compile(
    r'#\s*psa-disable-line\s+([A-Z0-9, ]+)', re.IGNORECASE)
SUPPRESS_NEXT_PAT = re.compile(
    r'#\s*psa-disable-next-line\s+([A-Z0-9, ]+)', re.IGNORECASE)
SUPPRESS_FILE_PAT = re.compile(
    r'#\s*psa-disable-file\s+([A-Z0-9, ]+)', re.IGNORECASE)


def _normalize_codes(raw):
    """Accept 'PSA2001', 'PSA2001,PSA2003' -> set of codes."""
    out = set()
    for tok in re.split(r'[,\s]+', raw):
        tok = tok.strip().upper()
        if not tok:
            continue
        out.add(tok)
    return out


def collect_suppressions(text):
    """Parse the raw text for inline-suppression comments.

    Returns:
        file_supp:   set of codes suppressed for the whole file
        line_supp:   {line_no: set(codes)} per-line suppression
    """
    file_supp = set()
    line_supp = {}
    for ln_no, line in enumerate(text.split('\n'), start=1):
        m = SUPPRESS_FILE_PAT.search(line)
        if m:
            file_supp |= _normalize_codes(m.group(1))
        m = SUPPRESS_LINE_PAT.search(line)
        if m:
            line_supp.setdefault(ln_no, set()).update(
                _normalize_codes(m.group(1)))
        m = SUPPRESS_NEXT_PAT.search(line)
        if m:
            line_supp.setdefault(ln_no + 1, set()).update(
                _normalize_codes(m.group(1)))
    return file_supp, line_supp


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# -- Remote-fetch tuning. Environment variables override defaults at startup
#    so that CI pipelines can tune behaviour without code changes:
#
#       PSA_CONFIG_TIMEOUT       per-attempt connect+read timeout (seconds)
#       PSA_CONFIG_MAX_RETRIES   total attempts including the first one
#       PSA_CONFIG_QUIET         set to "1" to suppress retry log lines

def _env_int(name, default):
    """Read a positive integer from the environment, falling back to *default*
    on any error (missing, non-numeric, or non-positive)."""
    raw = os.environ.get(name)
    if not raw:
        return default
    try:
        v = int(raw)
    except ValueError:
        return default
    return v if v > 0 else default


CONFIG_FETCH_TIMEOUT = _env_int('PSA_CONFIG_TIMEOUT', 30)
CONFIG_MAX_RETRIES = _env_int('PSA_CONFIG_MAX_RETRIES', 3)

# -- Browser-like User-Agent. Some CDNs / WAFs (notably Cloudflare-fronted
#    sites) default-reject obviously-bot UAs even on public raw files; a
#    realistic browser identifier is the pragmatic way to be reachable.
#    Updated to mirror Chrome 131 (released late 2024). The accompanying
#    Sec-Ch-Ua client hints MUST agree with this string — keep them in
#    sync if you bump the version.

CONFIG_BROWSER_USER_AGENT = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36'
)

CONFIG_BROWSER_HEADERS = {
    'User-Agent': CONFIG_BROWSER_USER_AGENT,
    'Accept': 'application/json, text/plain, text/*, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    # Identity encoding: avoids the complexity of decompressing gzip /
    # brotli responses inside an analyzer process.
    'Accept-Encoding': 'identity',
    # Client hints that match the Chrome 131 UA above
    'Sec-Ch-Ua': ('"Google Chrome";v="131", "Chromium";v="131", '
                  '"Not_A Brand";v="24"'),
    'Sec-Ch-Ua-Mobile': '?0',
    'Sec-Ch-Ua-Platform': '"Windows"',
}


def _build_tls_context():
    """Return an explicit SSL context with TLS 1.2 minimum.

    - **minimum_version = TLS 1.2**: industry baseline since 2020. GitHub,
      most CDNs, and all major SaaS providers require at least this.
      TLS 1.0 and TLS 1.1 are deprecated (RFC 8996, 2021) and not
      offered here.
    - **maximum_version left at default**: this lets the TLS handshake
      pick the strongest mutually-supported version, typically TLS 1.3
      against modern servers and automatically falling back to TLS 1.2
      against older ones. The "automatic downshift to whatever the
      server supports" behaviour is therefore intrinsic to the
      handshake, not a custom retry loop.
    - **Certificate verification on**: `create_default_context()` loads
      the OS trust store and enables hostname checks. Do not disable.
    """
    ctx = ssl.create_default_context()
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    # ctx.maximum_version is intentionally left unset (default
    # TLSVersion.MAXIMUM_SUPPORTED) so the handshake auto-selects.
    return ctx


def _retry_log(msg):
    """Emit a retry-progress line on stderr unless PSA_CONFIG_QUIET is set."""
    if os.environ.get('PSA_CONFIG_QUIET'):
        return
    print(f'psa.py: {msg}', file=sys.stderr)


def _fetch_remote_config(url):
    """Fetch *url* with browser-like headers, TLS 1.2+, and retry/backoff.

    Retry policy mirrors the Invoke-WebRequestWithRetry pattern used in
    the companion PowerShell project (Download-SpeakerDeck.ps1):

    - **5xx server errors**  → retry, sleeping 2^attempt × 3 seconds
      between tries. Server errors are usually transient (overload,
      brief outage) and benefit from a longer wait.
    - **Network / timeout / connection errors** → retry, sleeping
      2^attempt seconds. Local hiccups recover quickly.
    - **4xx client errors** → NO retry. 404 / 403 / 401 are persistent;
      retrying just wastes time.

    Returns: response body as bytes.
    Raises:  the most recent exception after retries are exhausted.
             Callers are expected to wrap this in a user-facing error.
    """
    ctx = _build_tls_context()
    req = urllib.request.Request(url, headers=dict(CONFIG_BROWSER_HEADERS))

    last_exc = None
    last_attempt = CONFIG_MAX_RETRIES - 1
    for attempt in range(CONFIG_MAX_RETRIES):
        try:
            with urllib.request.urlopen(
                    req,
                    timeout=CONFIG_FETCH_TIMEOUT,
                    context=ctx) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            # 4xx: persistent client error. Don't retry.
            if 400 <= e.code < 500:
                raise
            last_exc = e
            if attempt < last_attempt:
                wait = (2 ** (attempt + 1)) * 3
                _retry_log(
                    f'HTTP {e.code} from {url}; retry '
                    f'{attempt + 1}/{last_attempt} in {wait}s')
                time.sleep(wait)
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last_exc = e
            if attempt < last_attempt:
                wait = 2 ** (attempt + 1)
                _retry_log(
                    f'Network error from {url}: {e}; retry '
                    f'{attempt + 1}/{last_attempt} in {wait}s')
                time.sleep(wait)

    assert last_exc is not None  # safety net; loop runs ≥ once
    raise last_exc


def _strip_jsonc_comments(text):
    """Return *text* with JSONC comments removed.

    Supports two comment forms, like JavaScript / C:
        // line comment, terminated by newline
        /* block comment, may span multiple lines */

    Comment-like sequences inside JSON string literals are preserved.
    Newlines inside block comments are preserved so that downstream
    line numbers in error messages stay meaningful.

    This is intentionally a small handwritten state machine instead of a
    regex: the latter is error-prone with nested-looking strings.
    """
    out = []
    i, n = 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ''

        if in_str:
            out.append(c)
            # Handle backslash-escaped chars, especially \"
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue

        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue

        # Line comment: skip to (but keep) the newline so line numbers
        # in any subsequent JSON parse-error align with the source.
        if c == '/' and nxt == '/':
            while i < n and text[i] != '\n':
                i += 1
            continue

        # Block comment: skip everything until */; emit any newlines we
        # crossed so that line numbers are preserved.
        if c == '/' and nxt == '*':
            i += 2
            while i < n:
                if i + 1 < n and text[i] == '*' and text[i + 1] == '/':
                    i += 2
                    break
                if text[i] == '\n':
                    out.append('\n')
                i += 1
            continue

        out.append(c)
        i += 1

    return ''.join(out)


def _is_url(s):
    """Return True if *s* parses as an http(s) URL."""
    try:
        parsed = urllib.parse.urlparse(s)
    except (ValueError, AttributeError):
        return False
    return parsed.scheme in ('http', 'https') and bool(parsed.netloc)


def _load_config_source(path_or_url):
    """Read configuration content from either a local path or http(s) URL.

    Remote fetches are performed by `_fetch_remote_config()`, which
    applies browser-like headers, an explicit TLS 1.2-minimum context,
    and exponential-backoff retries on transient failures (see that
    function's docstring for the full policy).

    GitHub repositories should be referenced via the raw URL form, e.g.::

        https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json

    A regular blob URL (https://github.com/.../blob/...) returns HTML and
    will not parse as JSON.

    Returns:
        str: The configuration file contents, decoded as UTF-8.

    Raises:
        OSError: Local file unreadable.
        urllib.error.URLError / HTTPError: Remote fetch failed (after
            retries for transient errors).
        UnicodeDecodeError: Remote content not valid UTF-8.

    Callers are expected to catch these and convert into a user-facing
    error; see Config.load().
    """
    if _is_url(path_or_url):
        return _fetch_remote_config(path_or_url).decode('utf-8')
    with open(path_or_url, 'r', encoding='utf-8') as fh:
        return fh.read()


class Config:
    """Resolved configuration for a single analyzer run."""

    def __init__(self):
        # rule_id -> bool (enabled)
        self.enabled = {r[0]: r[2] for r in RULES}
        self.max_line_length = 120
        # PSA9001 threshold. Default 200 reflects the convention that
        # functions longer than ~200 lines are difficult to review or
        # test as a unit. Override via .psa.config.json.
        self.max_function_lines = 200
        # PSA8001 (function-sync) ignore list. When the analyzer is run
        # over multiple files and a function with the same NAME exists
        # in several of them, PSA8001 fires if the bodies disagree.
        # Repositories where many functions are intentionally script-
        # specific (e.g. pipeline phase functions named identically
        # but implementing different driver families) can list those
        # function names here to suppress the drift report.
        # Two forms are supported:
        #   - exact names: ["Invoke-PrepPhase00_Initialize", ...]
        #   - regex patterns starting with "regex:":
        #       ["regex:^Invoke-(Prep|Verify|Inst)Phase\\d{2}_"]
        # All forms are case-insensitive.
        self.psa8001_ignore_functions = []
        self.min_severity = 'info'
        self.format = 'text'
        self.no_color = False

    @classmethod
    def load(cls, args):
        c = cls()
        # 1) config file (lowest priority)
        cfg_path = args.config
        if cfg_path is None:
            # Implicit search: .psa.config.json in current dir
            implicit = Path.cwd() / '.psa.config.json'
            if implicit.exists():
                cfg_path = str(implicit)
        if cfg_path:
            try:
                raw_text = _load_config_source(cfg_path)
                clean_text = _strip_jsonc_comments(raw_text)
                data = json.loads(clean_text)
            except (OSError, urllib.error.URLError,
                    ssl.SSLError,
                    UnicodeDecodeError,
                    json.JSONDecodeError) as e:
                print(f'psa.py: cannot load config {cfg_path}: {e}',
                      file=sys.stderr)
                raise SystemExit(2)
            if not isinstance(data, dict):
                print(f'psa.py: config {cfg_path} did not parse to a '
                      f'JSON object (got {type(data).__name__})',
                      file=sys.stderr)
                raise SystemExit(2)
            for code in data.get('enable', []):
                code = code.upper()
                if code in c.enabled:
                    c.enabled[code] = True
            for code in data.get('disable', []):
                code = code.upper()
                if code in c.enabled:
                    c.enabled[code] = False
            if 'severity' in data:
                c.min_severity = data['severity']
            if 'max_line_length' in data:
                c.max_line_length = int(data['max_line_length'])
            if 'max_function_lines' in data:
                c.max_function_lines = int(data['max_function_lines'])
            if 'psa8001_ignore_functions' in data:
                v = data['psa8001_ignore_functions']
                if isinstance(v, list):
                    c.psa8001_ignore_functions = [str(x) for x in v]
                else:
                    print(f'psa.py: psa8001_ignore_functions must be a '
                          f'list (got {type(v).__name__})',
                          file=sys.stderr)
                    raise SystemExit(2)
        # 2) CLI args (highest priority)
        for code in (args.enable or []):
            code = code.upper()
            if code in c.enabled:
                c.enabled[code] = True
        for code in (args.disable or []):
            code = code.upper()
            if code in c.enabled:
                c.enabled[code] = False
        if args.include:
            include = set()
            for code in args.include:
                include.add(code.upper())
            for k in c.enabled:
                c.enabled[k] = (k in include)
        if args.severity:
            c.min_severity = args.severity
        if args.format:
            c.format = args.format
        if args.no_color or not sys.stdout.isatty() \
                or os.environ.get('NO_COLOR'):
            c.no_color = True
        if args.max_line_length:
            c.max_line_length = args.max_line_length
        return c


# ---------------------------------------------------------------------------
# Analyzer driver
# ---------------------------------------------------------------------------

def analyze_text(text, cfg, file_meta=None):
    """Run every enabled rule over *text*; return a sorted list of issues.

    Parameters
    ----------
    text : str
        The decoded PowerShell source text. The UTF-8 BOM (if any) is
        expected to have already been stripped by the caller.
    cfg : Config
        Resolved analyzer configuration.
    file_meta : dict | None
        Optional file-level metadata (e.g., {'has_bom': True}). Used by
        file-format rules (PSA7xxx). When None, file-format rules emit
        nothing -- preserves backward compatibility for callers that pass
        only ``(text, cfg)``.
    """
    clean = strip_strings_and_comments(text)

    raw = []  # list of issue dicts

    if cfg.enabled['PSA1001']:
        raw += check_balance(text, clean, '{', '}', 'PSA1001')
    if cfg.enabled['PSA1002']:
        raw += check_balance(text, clean, '(', ')', 'PSA1002')
    if cfg.enabled['PSA1003']:
        raw += check_balance(text, clean, '[', ']', 'PSA1003')

    if cfg.enabled['PSA2001']:
        raw += check_undefined_vars(text, clean)
    if cfg.enabled['PSA2002']:
        raw += check_shadow(clean)
    if cfg.enabled['PSA2003']:
        raw += check_match_var(clean)
    if cfg.enabled['PSA2004']:
        raw += check_null_on_right(clean)
    if cfg.enabled['PSA2005']:
        raw += check_assign_in_conditional(clean)
    if cfg.enabled['PSA2006']:
        raw += check_redirect_in_conditional(clean)

    if cfg.enabled['PSA3001']:
        raw += check_argumentlist(clean)
    if cfg.enabled['PSA3002']:
        raw += check_backtick(text)
    if cfg.enabled['PSA3003']:
        raw += _check_empty_match_raw_marker(text)
    if cfg.enabled['PSA3004']:
        raw += check_empty_catch(clean)
    if cfg.enabled['PSA3005']:
        raw += check_start_transcript_literalpath(clean)

    if cfg.enabled['PSA4001']:
        raw += check_todo(text)
    if cfg.enabled['PSA4002']:
        raw += check_trailing_whitespace(text)
    if cfg.enabled['PSA4003']:
        raw += check_long_line(text, cfg.max_line_length)
    if cfg.enabled['PSA4004']:
        raw += check_trailing_semicolon(clean)

    if cfg.enabled['PSA5001']:
        raw += check_plaintext_password(clean)
    if cfg.enabled['PSA5002']:
        raw += check_invoke_expression(clean)
    if cfg.enabled['PSA5003']:
        raw += check_broken_hash(clean)
    if cfg.enabled['PSA5004']:
        raw += check_hardcoded_computername(clean)

    if cfg.enabled['PSA6001']:
        raw += check_approved_verb(clean)
    if cfg.enabled['PSA6002']:
        raw += check_cmdlet_alias(clean)
    if cfg.enabled['PSA6003']:
        raw += check_singular_noun(clean)
    if cfg.enabled['PSA6004']:
        raw += check_global_var(clean)
    if cfg.enabled['PSA6005']:
        raw += check_mandatory_default(clean)
    if cfg.enabled['PSA6006']:
        raw += check_switch_default_true(clean)

    # File format / encoding (PSA7xxx) -- operate on file metadata, not text
    if cfg.enabled['PSA7001']:
        raw += check_utf8_bom_missing(file_meta)

    # Complexity metrics (PSA9xxx) - generic, opt-in
    # PSA8xxx (cross-file consistency) is dispatched from the multi-file
    # driver in main(), AFTER all per-file analyses complete. It cannot
    # fire from analyze_text() because it requires sibling-file context.
    if cfg.enabled['PSA9001']:
        raw += check_long_function(clean, cfg.max_function_lines)
    if cfg.enabled['PSA9002']:
        raw += check_lastexitcode_unchecked(clean)

    # Project / pipeline convention rules (PSAPxxxx) - opt-in
    if cfg.enabled['PSAP0001']:
        raw += check_phase_naming(clean)
    if cfg.enabled['PSAP0002']:
        raw += check_required_script_identifiers(clean)

    # Inline suppression
    file_supp, line_supp = collect_suppressions(text)
    raw = [
        i for i in raw
        if i['code'] not in file_supp
        and i['code'] not in line_supp.get(i['line'], set())
    ]

    # Severity floor
    min_rank = SEVERITY_ORDER.get(cfg.min_severity, 1)
    raw = [i for i in raw if SEVERITY_ORDER[i['severity']] >= min_rank]

    # Deduplicate identical entries (some rules can fire twice on one line)
    seen = set()
    out = []
    for i in raw:
        key = (i['code'], i['line'], i['col'], i['message'])
        if key in seen:
            continue
        seen.add(key)
        out.append(i)

    # Stable sort: by line, then by code
    out.sort(key=lambda x: (x['line'], x['col'], x['code']))
    return out


# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------
# Probe the runtime for PowerShell and PSScriptAnalyzer. Used to inform the
# user that, if those tools are available, they should also run them for
# complementary coverage. Output is purely informational and NEVER affects
# the analyzer's exit code or issue count.

# Timeout in seconds for each external probe; keep small to avoid blocking
# CI runs when PowerShell hangs on first invocation (rare but possible).
ENV_PROBE_TIMEOUT = 10


def _probe_powershell_binary():
    """Locate a usable PowerShell binary.

    Search order is `pwsh` (PowerShell 7+, preferred and cross-platform),
    then `powershell` (Windows PowerShell 5.1, Windows-only), then the
    fully-qualified `powershell.exe` (Windows). Return None if no
    candidate exists on PATH.
    """
    for cmd in ('pwsh', 'powershell', 'powershell.exe'):
        path = shutil.which(cmd)
        if path:
            return cmd, path
    return None, None


def _run_ps(ps_cmd, ps_script):
    """Run a one-liner PowerShell script and return its stdout (stripped).

    On any error (timeout, non-zero exit, missing binary, FileNotFoundError)
    return None. Never raises; environment detection must be best-effort.
    """
    try:
        result = subprocess.run(
            [ps_cmd, '-NoProfile', '-NonInteractive',
             '-Command', ps_script],
            capture_output=True, text=True,
            timeout=ENV_PROBE_TIMEOUT,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None
    if result.returncode != 0:
        return None
    out = (result.stdout or '').strip()
    return out or None


def detect_environment():
    """Detect the runtime environment.

    Returns a dict with these keys:
        python_version       str   e.g. '3.11.4'
        python_executable    str   absolute path to the Python interpreter
        platform             str   e.g. 'Linux 6.5.0-21-generic' / 'Darwin 23.4.0'
        psa_version          str   psa.py's own __version__
        powershell           dict or None:
            command          str   binary name used ('pwsh' / 'powershell' / ...)
            path             str   absolute path of the binary
            version          str   PSVersion string
        psscriptanalyzer     dict or None:
            version          str   module version string

    Either `powershell` or `psscriptanalyzer` (or both) may be None when
    not installed. This function never raises.
    """
    info = {
        'python_version': sys.version.split()[0],
        'python_executable': sys.executable,
        'platform': f'{_platform.system()} {_platform.release()}',
        'psa_version': __version__,
        'powershell': None,
        'psscriptanalyzer': None,
    }

    ps_cmd, ps_path = _probe_powershell_binary()
    if not ps_cmd:
        return info

    # Probe PowerShell version
    ps_version = _run_ps(ps_cmd, '$PSVersionTable.PSVersion.ToString()')
    if ps_version:
        info['powershell'] = {
            'command': ps_cmd,
            'path': ps_path,
            'version': ps_version,
        }
    else:
        # Found the binary but couldn't run it; nothing more to probe.
        return info

    # Probe PSScriptAnalyzer module
    psa_version = _run_ps(
        ps_cmd,
        '$m = Get-Module -ListAvailable PSScriptAnalyzer | '
        'Sort-Object Version -Descending | Select-Object -First 1; '
        'if ($m) { $m.Version.ToString() }'
    )
    if psa_version:
        info['psscriptanalyzer'] = {'version': psa_version}

    return info


def format_environment_text(env, no_color):
    """Render the environment detection result as human-readable text.

    Output is multi-line and uses the same colour scheme as analyzer
    output. Suitable for prepending to a normal analysis report when
    --show-env is passed, or as the entire output of --check-env.
    """
    lines = []
    lines.append(
        _color('==== psa.py: Environment Detection ====',
               ANSI_BLD, no_color))
    lines.append(f'psa.py        : {env["psa_version"]}')
    lines.append(f'Python        : {env["python_version"]} '
                 f'({env["platform"]})')

    ps = env['powershell']
    if ps:
        lines.append(
            f'PowerShell    : {ps["command"]} {ps["version"]} '
            f'at {ps["path"]}')
    else:
        lines.append('PowerShell    : not found on PATH')

    psa_mod = env['psscriptanalyzer']
    if psa_mod:
        lines.append(f'PSScriptAnalyzer : '
                     f'{psa_mod["version"]} (available)')
    else:
        lines.append('PSScriptAnalyzer : not installed')

    lines.append('')

    # Recommendation: pick exactly one of three message variants based on
    # which tools are detected. All three are info-level only; the exit
    # code is unaffected.
    if psa_mod and ps:
        lines.append(_color('Info:', ANSI_CYA, no_color))
        lines.append(
            '  PSScriptAnalyzer is available in this environment. For')
        lines.append(
            '  comprehensive PowerShell static analysis, consider running')
        lines.append(
            '  Microsoft\'s analyzer in addition to psa.py:')
        lines.append('')
        lines.append(
            f'    {ps["command"]} -Command "Invoke-ScriptAnalyzer '
            '-Path <script>.ps1"')
        lines.append('')
        lines.append(
            '  The two tools have largely complementary check sets;')
        lines.append('  running both maximizes coverage.')
    elif ps and not psa_mod:
        lines.append(_color('Info:', ANSI_CYA, no_color))
        lines.append(
            '  PowerShell is available, but PSScriptAnalyzer is not')
        lines.append('  installed. To install it for complementary checks:')
        lines.append('')
        lines.append(
            f'    {ps["command"]} -Command "Install-Module -Name '
            'PSScriptAnalyzer -Scope CurrentUser -Force"')
    else:
        lines.append(_color('Info:', ANSI_CYA, no_color))
        lines.append(
            '  psa.py is operating in standalone mode. No PowerShell')
        lines.append(
            '  runtime was detected on PATH, so PSScriptAnalyzer cannot')
        lines.append(
            '  be invoked from this environment. psa.py will still run')
        lines.append(
            '  its full 27-rule check set against your PowerShell files.')

    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# Formatters
# ---------------------------------------------------------------------------

ANSI_RED = '\x1b[31m'
ANSI_YEL = '\x1b[33m'
ANSI_CYA = '\x1b[36m'
ANSI_BLD = '\x1b[1m'
ANSI_RST = '\x1b[0m'


def _color(s, code, no_color):
    return s if no_color else f'{code}{s}{ANSI_RST}'


def format_text(path, text, issues, no_color):
    err = sum(1 for i in issues if i['severity'] == 'error')
    warn = sum(1 for i in issues if i['severity'] == 'warning')
    info = sum(1 for i in issues if i['severity'] == 'info')
    line_count = len(text.splitlines())
    lines = []
    lines.append(
        _color('==== psa.py: PowerShell Static Analyzer ====',
               ANSI_BLD, no_color))
    lines.append(f'File   : {path}')
    lines.append(f'Lines  : {line_count}')
    lines.append(f'Issues : {err} errors, {warn} warnings, {info} info')
    lines.append('')
    if not issues:
        lines.append('  (no issues found)')
        return '\n'.join(lines)
    for sev, col in (('error', ANSI_RED),
                     ('warning', ANSI_YEL),
                     ('info', ANSI_CYA)):
        sub = [i for i in issues if i['severity'] == sev]
        if not sub:
            continue
        lines.append(_color(f'---- {sev.upper()} ({len(sub)}) ----',
                            col, no_color))
        for i in sub:
            loc = (f"line {i['line']:>5}:{i['col']:>3}"
                   if i['col'] else f"line {i['line']:>5}     ")
            lines.append(
                f"  [{_color(i['code'], col, no_color)}] "
                f"{loc}: {i['message']}")
        lines.append('')
    return '\n'.join(lines)


def format_json(path, text, issues):
    payload = {
        'file': str(path),
        'lines': len(text.splitlines()),
        'summary': {
            'errors':   sum(1 for i in issues if i['severity'] == 'error'),
            'warnings': sum(1 for i in issues if i['severity'] == 'warning'),
            'info':     sum(1 for i in issues if i['severity'] == 'info'),
        },
        'issues': [
            {
                'code': i['code'],
                'severity': i['severity'],
                'line': i['line'],
                'col': i['col'],
                'message': i['message'],
            }
            for i in issues
        ],
    }
    return json.dumps(payload, indent=2, ensure_ascii=False)


def format_sarif(per_file_results, env_info=None):
    """Emit SARIF 2.1.0.

    *per_file_results* is a list of (path, text, issues). *env_info* is the
    optional environment-detection dict returned by detect_environment();
    when present, it is recorded in the SARIF run's `properties` block
    (SARIF spec permits tool-specific properties via the `properties` bag).
    """
    rules_section = []
    for r in RULES:
        code, sev, _enabled, msg = r
        sarif_level = {'error': 'error',
                       'warning': 'warning',
                       'info': 'note'}.get(sev, 'note')
        rules_section.append({
            'id': code,
            'name': code,
            'shortDescription': {'text': msg},
            'fullDescription': {'text': msg},
            'defaultConfiguration': {'level': sarif_level},
            'helpUri': 'https://github.com/usui-tk/ai-generated-artifacts'
                       '/tree/main/scripts/python/powershell-static-analyzer',
        })
    results = []
    for path, _text, issues in per_file_results:
        for i in issues:
            sarif_level = {'error': 'error',
                           'warning': 'warning',
                           'info': 'note'}.get(i['severity'], 'note')
            results.append({
                'ruleId': i['code'],
                'level': sarif_level,
                'message': {'text': i['message']},
                'locations': [{
                    'physicalLocation': {
                        'artifactLocation': {'uri': str(path)},
                        'region': {
                            'startLine': max(i['line'], 1),
                            'startColumn': max(i['col'], 1),
                        },
                    },
                }],
            })
    run = {
        'tool': {
            'driver': {
                'name': 'psa.py',
                'version': __version__,
                'informationUri': 'https://github.com/usui-tk/'
                                  'ai-generated-artifacts',
                'rules': rules_section,
            },
        },
        'results': results,
    }
    if env_info is not None:
        run['properties'] = {'environment': env_info}
    sarif = {
        '$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
        'version': '2.1.0',
        'runs': [run],
    }
    return json.dumps(sarif, indent=2, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Path expansion
# ---------------------------------------------------------------------------

def expand_paths(paths, recursive):
    out = []
    for p in paths:
        # Allow shell globs even on platforms that didn't expand them
        matches = glob.glob(p, recursive=True) or [p]
        for m in matches:
            path = Path(m)
            if path.is_dir():
                if recursive:
                    out.extend(sorted(path.rglob('*.ps1')))
                    out.extend(sorted(path.rglob('*.psm1')))
                else:
                    print(f'psa.py: skipping directory (use -r): {path}',
                          file=sys.stderr)
            else:
                out.append(path)
    # Deduplicate, preserve order
    seen = set()
    uniq = []
    for p in out:
        rp = p.resolve()
        if rp in seen:
            continue
        seen.add(rp)
        uniq.append(p)
    return uniq


# ---------------------------------------------------------------------------
# Argument parsing / main
# ---------------------------------------------------------------------------

def list_rules(no_color):
    print(_color('PSA Rule Catalog', ANSI_BLD, no_color))
    print()
    print(f'{"Code":<8} {"Severity":<8} {"Default":<8} Description')
    print('-' * 78)
    for code, sev, default, msg in RULES:
        default_str = 'on' if default else 'OFF'
        print(f'{code:<8} {sev:<8} {default_str:<8} {msg}')
    return 0


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        prog='psa.py',
        description='PowerShell static analyzer (PSScriptAnalyzer-inspired).',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument('paths', nargs='*',
                   help='PowerShell files or directories to analyze')
    p.add_argument('-r', '--recursive', action='store_true',
                   help='Recursively scan directories for .ps1 / .psm1')
    p.add_argument('--format', choices=('text', 'json', 'sarif'),
                   default='text', help='Output format (default: text)')
    p.add_argument('--severity', choices=('error', 'warning', 'info'),
                   help='Minimum severity to report')
    p.add_argument('--enable', action='append', metavar='CODE',
                   help='Enable a disabled-by-default rule')
    p.add_argument('--disable', action='append', metavar='CODE',
                   help='Disable a specific rule')
    p.add_argument('--include', action='append', metavar='CODE',
                   help='Only run the listed rules (comma-separated OK)')
    p.add_argument('--config', metavar='PATH_OR_URL',
                   help=('Path to a local .psa.config.json (JSONC) file '
                         'OR an http(s):// URL. Default: implicit search '
                         'for .psa.config.json in CWD.'))
    p.add_argument('--max-line-length', type=int, metavar='N',
                   help='Maximum line length for PSA4003 (default: 120)')
    p.add_argument('--no-color', action='store_true',
                   help='Disable ANSI color output')
    p.add_argument('--list-rules', action='store_true',
                   help='Print the rule catalog and exit')
    p.add_argument('--check-env', action='store_true',
                   help=('Detect PowerShell / PSScriptAnalyzer availability '
                         'and exit (informational, exit code 0)'))
    p.add_argument('--show-env', action='store_true',
                   help=('Prepend an environment summary to the normal '
                         'analysis output (informational only)'))
    p.add_argument('--version', action='version',
                   version=f'psa.py {__version__}')

    args = p.parse_args(argv)
    # Allow comma-separated values for --enable/--disable/--include
    for attr in ('enable', 'disable', 'include'):
        vals = getattr(args, attr)
        if vals is None:
            continue
        flat = []
        for v in vals:
            flat.extend(s.strip() for s in v.split(',') if s.strip())
        setattr(args, attr, flat)
    return args


def main(argv=None):
    args = parse_args(argv)

    cfg = Config.load(args)

    if args.list_rules:
        return list_rules(cfg.no_color)

    # --check-env: detect environment and exit (no file analysis)
    if args.check_env:
        env = detect_environment()
        if cfg.format == 'json':
            print(json.dumps(env, indent=2, ensure_ascii=False))
        else:
            print(format_environment_text(env, cfg.no_color))
        return 0

    if not args.paths:
        print('psa.py: no input files specified. Use --help.',
              file=sys.stderr)
        return 2

    # --show-env: prepend env summary to normal output (informational)
    env_info = None
    if args.show_env:
        env_info = detect_environment()
        if cfg.format == 'text':
            print(format_environment_text(env_info, cfg.no_color))
            print()

    files = expand_paths(args.paths, args.recursive)
    if not files:
        print('psa.py: no PowerShell files found.', file=sys.stderr)
        return 2

    per_file = []
    total_err = total_warn = 0
    # For PSA8001 cross-file consistency: collect per-file function bodies
    # so they can be compared after all files have been parsed.
    per_file_fns = {}
    for path in files:
        try:
            raw_bytes = path.read_bytes()
        except OSError as e:
            print(f'psa.py: cannot read {path}: {e}', file=sys.stderr)
            continue
        # Detect BOM before decoding. Python's bytes.decode('utf-8') keeps
        # the BOM as U+FEFF in the resulting str, but our analyzer expects
        # a BOM-free text body. Strip the BOM bytes here and remember the
        # presence flag for the PSA7xxx (file format) rule family.
        has_bom = raw_bytes.startswith(b'\xef\xbb\xbf')
        body = raw_bytes[3:] if has_bom else raw_bytes
        text = body.decode('utf-8', errors='replace')
        file_meta = {'has_bom': has_bom}
        issues = analyze_text(text, cfg, file_meta=file_meta)
        per_file.append((path, text, issues))
        # Collect function bodies for cross-file PSA8001 analysis.
        if cfg.enabled.get('PSA8001'):
            clean = strip_strings_and_comments(text)
            per_file_fns[path] = collect_function_bodies(clean)
        total_err += sum(1 for i in issues if i['severity'] == 'error')
        total_warn += sum(1 for i in issues if i['severity'] == 'warning')

    # PSA8001 (cross-file function sync). Only meaningful when 2+ files
    # are in scope; with a single file there are no peers to compare.
    if cfg.enabled.get('PSA8001') and len(per_file_fns) >= 2:
        cross_issues_by_path = check_function_sync(
            per_file_fns, cfg.psa8001_ignore_functions)
        # Merge cross-file issues into per_file results.
        # PSA8001 issues are subject to the same inline-suppression and
        # severity-floor filters that analyze_text() applies; reapply
        # those here for consistency.
        min_rank = SEVERITY_ORDER.get(cfg.min_severity, 1)
        for idx, (path, text, existing) in enumerate(per_file):
            new = cross_issues_by_path.get(path, [])
            if not new:
                continue
            file_supp, line_supp = collect_suppressions(text)
            new = [
                i for i in new
                if i['code'] not in file_supp
                and i['code'] not in line_supp.get(i['line'], set())
            ]
            new = [i for i in new
                   if SEVERITY_ORDER[i['severity']] >= min_rank]
            merged = existing + new
            merged.sort(key=lambda x: (x['line'], x['col'], x['code']))
            per_file[idx] = (path, text, merged)
            total_err += sum(1 for i in new if i['severity'] == 'error')
            total_warn += sum(1 for i in new if i['severity'] == 'warning')

    if cfg.format == 'sarif':
        print(format_sarif(per_file, env_info))
    elif cfg.format == 'json':
        if len(per_file) == 1:
            path, text, issues = per_file[0]
            payload = json.loads(format_json(path, text, issues))
            if env_info is not None:
                payload['environment'] = env_info
            print(json.dumps(payload, indent=2, ensure_ascii=False))
        else:
            payload = {'files': [json.loads(format_json(p, t, i))
                                 for p, t, i in per_file]}
            if env_info is not None:
                payload['environment'] = env_info
            print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        for path, text, issues in per_file:
            print(format_text(path, text, issues, cfg.no_color))
            if len(per_file) > 1:
                print()

    return 2 if total_err else (1 if total_warn else 0)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except BrokenPipeError:
        # Triggered when output is piped to a consumer that closed early
        # (e.g. `| head`). Suppress the traceback and exit cleanly.
        try:
            sys.stdout.close()
        except Exception:
            pass
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
