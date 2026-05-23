#!/usr/bin/env python3
"""Self-test fixtures for the psa.py rule catalog.

This file replaces the earlier test_psap_3_4.py — which covered only
PSAP0003 / PSAP0004 — with a full-catalog regression suite. Each of
psa.py's 42 rules has, at minimum, one positive case (rule must fire),
one negative case (rule must NOT fire), and where applicable an edge
case (e.g. false-positive defenses: rule in string literal, in
here-string, in comment, etc.). See README of repo2 (§ Pillar 1) for
the design rationale.

The suite has no third-party dependencies (no pytest, no unittest); it
imports psa.py as a module and invokes the analyzer pipeline directly.
This mirrors the pattern established by the original test_psap_3_4.py
and keeps the suite runnable as:

    python3 test_psa_rules.py

Exit code: 0 if all tests pass, 1 otherwise. A short summary is printed
at the end.

The final section drives psa.py via subprocess to exercise the
--config-check (Pillar 2) and --self-check (Pillar 3) CLI surfaces.
Per the Phase 2 design (Q4 = co-existence), psa.py's own
implementation is the source of truth; the tests here merely lock it
in against regressions.
"""

import os
import subprocess
import sys
import tempfile
import importlib.util
from pathlib import Path

# Import psa.py as a module from the same directory as this test file
PSA_PATH = Path(__file__).parent / "psa.py"
_spec = importlib.util.spec_from_file_location("psa", PSA_PATH)
psa = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(psa)


# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

def _make_cfg(*rule_codes):
    """Build a Config that enables ONLY the listed rule codes.

    Every other rule is forced off so that the test isolates the rule
    under inspection. Severity floor is 'info' so all severities show.
    """
    cfg = psa.Config()
    cfg.enabled = {k: False for k in cfg.enabled}
    for code in rule_codes:
        cfg.enabled[code] = True
    cfg.min_severity = 'info'
    return cfg


def _run_text(rule_codes, source, file_meta=None):
    """Run analyze_text with only *rule_codes* enabled; return results."""
    cfg = _make_cfg(*rule_codes)
    return psa.analyze_text(source, cfg, file_meta=file_meta)


def _count(results, code):
    return sum(1 for r in results if r['code'] == code)


# Each test entry is (test_name, rule_code, source, expected_count).
# For PSA7001 / PSA8001 a different driver is used (see further down).
TESTS = []


def t(name, code, source, expected):
    TESTS.append(('rule', name, code, source, expected, None))


# ---------------------------------------------------------------------------
# PSA1001 — Brace balance (error, default ON)
# ---------------------------------------------------------------------------

t('PSA1001 positive: unbalanced opening brace',
  'PSA1001', 'function Foo {\n', 1)

t('PSA1001 negative: balanced braces',
  'PSA1001', 'function Foo { return 1 }\n', 0)

t('PSA1001 edge: brace inside string literal is ignored',
  'PSA1001', '$x = "literal { with brace"\n', 0)


# ---------------------------------------------------------------------------
# PSA1002 — Paren balance (error, default ON)
# ---------------------------------------------------------------------------

t('PSA1002 positive: unbalanced opening paren',
  'PSA1002', '$x = (1 + 2\n', 1)

t('PSA1002 negative: balanced parens',
  'PSA1002', '$x = (1 + 2)\n', 0)

t('PSA1002 edge: paren in string literal is ignored',
  'PSA1002', '$msg = "Open ( without close"\n', 0)


# ---------------------------------------------------------------------------
# PSA1003 — Bracket balance (error, default ON)
# ---------------------------------------------------------------------------

t('PSA1003 positive: unbalanced opening bracket',
  'PSA1003', '$arr = $list[0\n', 1)

t('PSA1003 negative: balanced brackets',
  'PSA1003', '[int]$x = 1\n', 0)

t('PSA1003 edge: bracket in string literal is ignored',
  'PSA1003', '$x = "[unclosed"\n', 0)


# ---------------------------------------------------------------------------
# PSA2001 — Undefined variable reference (error, default ON)
# ---------------------------------------------------------------------------

t('PSA2001 positive: reference to never-assigned variable',
  'PSA2001',
  'function Foo {\n'
  '    $undefined_var\n'
  '}\n',
  1)

t('PSA2001 negative: assigned before reference',
  'PSA2001',
  'function Foo {\n'
  '    $x = 1\n'
  '    $x\n'
  '}\n',
  0)

t('PSA2001 edge: $Script:/$global: scope-qualified is runtime-deferred',
  'PSA2001',
  'function Foo {\n'
  '    $Script:ScriptVersion\n'
  '    $global:Whatever\n'
  '}\n',
  0)


# ---------------------------------------------------------------------------
# PSA2002 — Auto-variable shadowing (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA2002 positive: assign to $matches (risky auto-var)',
  'PSA2002',
  'function Foo {\n'
  '    $matches = "x"\n'
  '}\n',
  1)

t('PSA2002 negative: assign to ordinary variable',
  'PSA2002',
  'function Foo {\n'
  '    $myVar = "x"\n'
  '}\n',
  0)

t('PSA2002 edge: assign to a non-auto variable named $log is silent',
  'PSA2002',
  'function Foo {\n'
  '    $log = "x"\n'
  '}\n',
  0)

t('PSA2002 edge (v3.6.0): assign to $PSItem (added to RISKY_SHADOW_VARS) is flagged',
  'PSA2002',
  'function Foo {\n'
  '    $PSItem = "x"\n'
  '}\n',
  1)


# ---------------------------------------------------------------------------
# PSA2003 — `-match` against bare variable (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA2003 positive: bare variable on right side of -match',
  'PSA2003', 'if ($a -match $b) { }\n', 1)

t('PSA2003 negative: literal regex on right side',
  'PSA2003', 'if ($a -match "^foo") { }\n', 0)


# ---------------------------------------------------------------------------
# PSA2004 — $null should be on the left of -eq/-ne (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA2004 positive: -eq $null on right',
  'PSA2004', 'if ($x -eq $null) { }\n', 1)

t('PSA2004 negative: $null on left',
  'PSA2004', 'if ($null -eq $x) { }\n', 0)


# ---------------------------------------------------------------------------
# PSA2005 — Assignment operator inside conditional (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA2005 positive: assignment in if-condition',
  'PSA2005', 'if ($x = Get-Foo) { }\n', 1)

t('PSA2005 negative: comparison in if-condition',
  'PSA2005', 'if ($x -eq (Get-Foo)) { }\n', 0)


# ---------------------------------------------------------------------------
# PSA2006 — Redirection operator inside conditional (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA2006 positive: $variable > literal inside if-condition',
  'PSA2006', 'if ($x > "out.txt") { }\n', 1)

t('PSA2006 negative: -gt (comparison) inside if-condition',
  'PSA2006', 'if ($x -gt 5) { }\n', 0)


# ---------------------------------------------------------------------------
# PSA2007 — Parameter name shadows a PowerShell automatic variable
# (warning, default ON, new in 3.6.0)
# ---------------------------------------------------------------------------

t('PSA2007 positive: $Event parameter shadows automatic variable',
  'PSA2007',
  'function _Write { param([Parameter(Mandatory)] $Event)\n  $Event.Foo\n}\n',
  1)

t('PSA2007 positive: $Args parameter shadows automatic variable',
  'PSA2007',
  'function Foo { param([string]$Args)\n  $Args\n}\n',
  1)

t('PSA2007 positive: $PSCmdlet parameter with type literal',
  'PSA2007',
  'function Foo { param([Parameter(Mandatory)] [object]$PSCmdlet)\n}\n',
  1)

t('PSA2007 positive: top-level script param block with $Event',
  'PSA2007',
  'param([string]$Event)\nWrite-Host $Event\n',
  1)

t('PSA2007 negative: parameter $EventObject (renamed) is fine',
  'PSA2007',
  'function _Write { param([Parameter(Mandatory)] $EventObject)\n  $EventObject.Foo\n}\n',
  0)

t('PSA2007 negative: bare $Event reference inside body (not a param)',
  'PSA2007',
  'function Subscriber { param($Source)\n  Write-Host $Event.MessageData\n}\n',
  0)

t('PSA2007 edge: $null parameter is exempt (discard idiom not relevant for params, '
  'but null is excluded from RISKY_SHADOW_VARS)',
  'PSA2007',
  'function Foo { param($null = $null)\n}\n',
  0)


# ---------------------------------------------------------------------------
# PSA2008 — $Script:Foo++/+=/-= without prior initialisation
# (info, default ON, new in 3.6.0)
# ---------------------------------------------------------------------------

t('PSA2008 positive: $Script:Count++ without initialisation',
  'PSA2008',
  'function Foo {\n  $Script:Count++\n}\n',
  1)

t('PSA2008 positive: $Script:Total += 5 without initialisation',
  'PSA2008',
  'function Bar {\n  $Script:Total += 5\n}\n',
  1)

t('PSA2008 positive: $Script:Errors-- without initialisation',
  'PSA2008',
  'function Baz {\n  $Script:Errors--\n}\n',
  1)

t('PSA2008 negative: $Script:Count is initialised, then incremented',
  'PSA2008',
  '$Script:Count = 0\nfunction Foo {\n  $Script:Count++\n}\n',
  0)

t('PSA2008 negative: $Script:Total has plain = assignment',
  'PSA2008',
  '$Script:Total = 0\nfunction Bar {\n  $Script:Total += 5\n}\n',
  0)

t('PSA2008 negative: plain ++ on a non-Script variable is fine',
  'PSA2008',
  'function Foo {\n  $local = 0\n  $local++\n}\n',
  0)


# ---------------------------------------------------------------------------
# PSA2009 — PSCustomObject property assigned without prior declaration
# (warning, default ON, new in 3.8.0)
# ---------------------------------------------------------------------------

t('PSA2009 positive: simple undeclared property assignment',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1 }\n$Ctx.Bar = 2\n',
  1)

t('PSA2009 positive: catch-block fallback that itself triggers the rule',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1 }\ntry {\n  $Ctx.WhqlCoSignAnalysis = New-Object\n} catch {\n  $Ctx.WhqlCoSignAnalysis = @()\n}\n',
  2)

t('PSA2009 positive: $Script:-scoped pscustomobject',
  'PSA2009',
  '$Script:Ctx = [pscustomobject]@{ Foo = 1 }\n$Ctx.Bar = 2\n',
  1)

t('PSA2009 negative: declared property assignment',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1; Bar = $null }\n$Ctx.Bar = 2\n',
  0)

t('PSA2009 negative: Add-Member pipe form extends the declared set',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1 }\n$Ctx | Add-Member -MemberType NoteProperty -Name Bar -Value $null\n$Ctx.Bar = 2\n',
  0)

t('PSA2009 negative: Add-Member -InputObject form extends the declared set',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1 }\nAdd-Member -InputObject $Ctx -MemberType NoteProperty -Name Bar -Value $null\n$Ctx.Bar = 2\n',
  0)

t('PSA2009 negative: variable also assigned as plain hashtable is dropped from tracking',
  'PSA2009',
  '$result = [pscustomobject]@{ A = 1 }\n$result = @{ B = 2 }\n$result.X = 3\n',
  0)

t('PSA2009 negative: variable also assigned as [ordered]@{...} is dropped',
  'PSA2009',
  '$result = [pscustomobject]@{ A = 1 }\n$result = [ordered]@{ B = 2 }\n$result.X = 3\n',
  0)

t('PSA2009 negative: well-known dynamic bag $PSBoundParameters is exempt',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1 }\n$PSBoundParameters.Anything = 2\n',
  0)

t('PSA2009 negative: compound += assignment is not flagged',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Counter = 0 }\n$Ctx.Counter += 1\n',
  0)

t('PSA2009 negative: equality comparison (==) is not flagged',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1 }\nif ($Ctx.Bar -eq $null) { Write-Host hi }\n',
  0)

t('PSA2009 negative: read-only property access does not fire',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1 }\nWrite-Host $Ctx.Bar\n',
  0)

t('PSA2009 negative: no pscustomobject initialiser in the file at all',
  'PSA2009',
  '$h = @{ Foo = 1 }\n$h.Bar = 2\n',
  0)

t('PSA2009 negative: variable in [pscustomobject] but property added via inline same statement',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1; Bar = $null; Baz = @() }\n$Ctx.Bar = 2\n$Ctx.Baz = @(1,2,3)\n',
  0)

t('PSA2009 inline-suppress: # psa-disable-line PSA2009 on the assignment line',
  'PSA2009',
  '$Ctx = [pscustomobject]@{ Foo = 1 }\n$Ctx.Bar = 2  # psa-disable-line PSA2009\n',
  0)


# ---------------------------------------------------------------------------
# PSA3001 — Start-Process -ArgumentList (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA3001 positive: Start-Process with -ArgumentList',
  'PSA3001', 'Start-Process notepad.exe -ArgumentList "/foo"\n', 1)

t('PSA3001 negative: Start-Process without -ArgumentList',
  'PSA3001', 'Start-Process notepad.exe\n', 0)

t('PSA3001 edge: "Start-Process -ArgumentList" inside string literal',
  'PSA3001', '$cmd = "Start-Process X -ArgumentList Y"\n', 0)


# ---------------------------------------------------------------------------
# PSA3002 — Backtick continuation before empty line (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA3002 positive: trailing backtick followed by blank line',
  'PSA3002', 'Get-ChildItem `\n\n', 1)

t('PSA3002 negative: trailing backtick followed by continuation',
  'PSA3002', 'Get-ChildItem `\n    -Recurse\n', 0)


# ---------------------------------------------------------------------------
# PSA3003 — -match against empty string (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA3003 positive: -match against empty string literal',
  'PSA3003', 'if ($x -match "") { }\n', 1)

t('PSA3003 negative: -match against non-empty literal',
  'PSA3003', 'if ($x -match "foo") { }\n', 0)


# ---------------------------------------------------------------------------
# PSA3004 — Empty catch block (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA3004 positive: try with empty catch',
  'PSA3004',
  'try { Do-Thing } catch { }\n',
  1)

t('PSA3004 negative: try with non-empty catch',
  'PSA3004',
  'try { Do-Thing } catch { Write-Error $_ }\n',
  0)


# ---------------------------------------------------------------------------
# PSA3005 — Start-Transcript -Path should be -LiteralPath (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA3005 positive: Start-Transcript -Path',
  'PSA3005', 'Start-Transcript -Path "C:\\Logs\\out.log"\n', 1)

t('PSA3005 negative: Start-Transcript -LiteralPath',
  'PSA3005', 'Start-Transcript -LiteralPath "C:\\Logs\\out.log"\n', 0)


# ---------------------------------------------------------------------------
# PSA3006 — Deprecated WMI cmdlet (warning, default ON, new in 3.6.0)
# ---------------------------------------------------------------------------

t('PSA3006 positive: Get-WmiObject usage',
  'PSA3006',
  '$os = Get-WmiObject -Class Win32_OperatingSystem\n',
  1)

t('PSA3006 positive: Invoke-WmiMethod usage',
  'PSA3006',
  'Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList "notepad.exe"\n',
  1)

t('PSA3006 positive: Set-WmiInstance usage',
  'PSA3006',
  'Set-WmiInstance -Class Win32_WMISetting -Argument @{LoggingLevel=2}\n',
  1)

t('PSA3006 positive: gwmi alias usage',
  'PSA3006',
  'gwmi Win32_BIOS\n',
  1)

t('PSA3006 negative: Get-CimInstance (the recommended replacement)',
  'PSA3006',
  '$os = Get-CimInstance -ClassName Win32_OperatingSystem\n',
  0)

t('PSA3006 negative: Invoke-CimMethod (the recommended replacement)',
  'PSA3006',
  'Invoke-CimMethod -ClassName Win32_Process -MethodName Create\n',
  0)

t('PSA3006 edge: "Get-WmiObject" inside string literal is not flagged',
  'PSA3006',
  '$help = "Use Get-WmiObject to query WMI"\n',
  0)

t('PSA3006 edge: "Get-WmiObject" inside a comment is not flagged',
  'PSA3006',
  '# Get-WmiObject is deprecated in PS 7+\n',
  0)


# ---------------------------------------------------------------------------
# PSA4001 — Unfinished marker (info, default ON)
# ---------------------------------------------------------------------------

t('PSA4001 positive: TODO marker in comment',
  'PSA4001', '# TODO: implement this\n', 1)

t('PSA4001 positive: FIXME marker in comment',
  'PSA4001', '# FIXME: bug here\n', 1)

t('PSA4001 negative: TODO substring inside string is not flagged',
  'PSA4001', '$msg = "todoist"\n', 0)


# ---------------------------------------------------------------------------
# PSA4002 — Trailing whitespace (info, default ON)
# ---------------------------------------------------------------------------

t('PSA4002 positive: trailing space at end of line',
  'PSA4002', '$x = 1   \n', 1)

t('PSA4002 negative: no trailing whitespace',
  'PSA4002', '$x = 1\n', 0)


# ---------------------------------------------------------------------------
# PSA4003 — Long line (info, default OFF)
# ---------------------------------------------------------------------------

t('PSA4003 positive: line exceeds default 120 cols',
  'PSA4003', '#' + ('x' * 130) + '\n', 1)

t('PSA4003 negative: line within default limit',
  'PSA4003', '#' + ('x' * 80) + '\n', 0)


# ---------------------------------------------------------------------------
# PSA4004 — Trailing semicolon (info, default ON)
# ---------------------------------------------------------------------------

t('PSA4004 positive: trailing semicolon at end of line',
  'PSA4004', '$x = 1;\n', 1)

t('PSA4004 negative: no trailing semicolon',
  'PSA4004', '$x = 1\n', 0)


# ---------------------------------------------------------------------------
# PSA5001 — Plain-text password parameter (error, default ON)
# ---------------------------------------------------------------------------

t('PSA5001 positive: [string]$Password parameter',
  'PSA5001',
  'function Connect-Thing {\n'
  '    param([string]$Password)\n'
  '}\n',
  1)

t('PSA5001 negative: [SecureString]$Password parameter',
  'PSA5001',
  'function Connect-Thing {\n'
  '    param([SecureString]$Password)\n'
  '}\n',
  0)


# ---------------------------------------------------------------------------
# PSA5002 — Invoke-Expression (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA5002 positive: Invoke-Expression call',
  'PSA5002', 'Invoke-Expression "Get-Date"\n', 1)

t('PSA5002 negative: no Invoke-Expression',
  'PSA5002', 'Get-Date\n', 0)

t('PSA5002 edge: "Invoke-Expression" inside string literal',
  'PSA5002', '$cmd = "we use Invoke-Expression rarely"\n', 0)


# ---------------------------------------------------------------------------
# PSA5003 — Broken hash algorithm (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA5003 positive: Get-FileHash -Algorithm MD5',
  'PSA5003', 'Get-FileHash file.txt -Algorithm MD5\n', 1)

t('PSA5003 positive: -Algorithm SHA1',
  'PSA5003', 'Get-FileHash file.txt -Algorithm SHA1\n', 1)

t('PSA5003 negative: -Algorithm SHA256',
  'PSA5003', 'Get-FileHash file.txt -Algorithm SHA256\n', 0)


# ---------------------------------------------------------------------------
# PSA5004 — Hardcoded ComputerName (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA5004 positive: hardcoded -ComputerName "literal"',
  'PSA5004', 'Invoke-Command -ComputerName "server01"\n', 1)

t('PSA5004 positive: hardcoded -ComputerName \'literal\' (single-quoted)',
  'PSA5004', "Invoke-Command -ComputerName 'server01'\n", 1)

t('PSA5004 positive: case-insensitive (-computername)',
  'PSA5004', 'Invoke-Command -computername "server01"\n', 1)

t('PSA5004 negative: -ComputerName from variable',
  'PSA5004', 'Invoke-Command -ComputerName $target\n', 0)

t('PSA5004 whitelist: localhost is allowed',
  'PSA5004', 'Invoke-Command -ComputerName "localhost"\n', 0)

t('PSA5004 whitelist: . (current host) is allowed',
  'PSA5004', 'Invoke-Command -ComputerName "."\n', 0)

t('PSA5004 whitelist: 127.0.0.1 is allowed',
  'PSA5004', 'Invoke-Command -ComputerName "127.0.0.1"\n', 0)

t('PSA5004 edge: -ComputerName inside a comment is not flagged',
  'PSA5004', '# Invoke-Command -ComputerName "server01"\n', 0)

t('PSA5004 edge: -ComputerName inside an outer string literal',
  'PSA5004',
  '$cmd = "Invoke-Command -ComputerName \\"server01\\""\n',
  0)

t('PSA5004 edge: trailing comment after a hardcoded value',
  'PSA5004',
  'Invoke-Command -ComputerName "server01"  # legitimate fix-it\n',
  1)


# ---------------------------------------------------------------------------
# PSA6001 — Non-approved verb (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA6001 positive: function with non-approved verb',
  'PSA6001', 'function Process-Things { }\n', 1)

t('PSA6001 negative: function with approved verb (Get-)',
  'PSA6001', 'function Get-Things { }\n', 0)


# ---------------------------------------------------------------------------
# PSA6002 — Cmdlet alias (warning, default OFF)
# ---------------------------------------------------------------------------

t('PSA6002 positive: ls alias used',
  'PSA6002', 'ls -Recurse\n', 1)

t('PSA6002 negative: full Get-ChildItem name',
  'PSA6002', 'Get-ChildItem -Recurse\n', 0)


# ---------------------------------------------------------------------------
# PSA6003 — Plural function noun (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA6003 positive: plural noun in function name',
  'PSA6003', 'function Get-Files { }\n', 1)

t('PSA6003 negative: singular noun in function name',
  'PSA6003', 'function Get-File { }\n', 0)


# ---------------------------------------------------------------------------
# PSA6004 — $global: variable definition (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA6004 positive: $global: assignment',
  'PSA6004', '$global:MyVar = 1\n', 1)

t('PSA6004 negative: $Script: assignment',
  'PSA6004', '$Script:MyVar = 1\n', 0)


# ---------------------------------------------------------------------------
# PSA6005 — Mandatory parameter with default value (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA6005 positive: Mandatory with default value',
  'PSA6005',
  'function Foo {\n'
  '    param([Parameter(Mandatory)][string]$Name = "default")\n'
  '}\n',
  1)

t('PSA6005 negative: Mandatory without default',
  'PSA6005',
  'function Foo {\n'
  '    param([Parameter(Mandatory)][string]$Name)\n'
  '}\n',
  0)


# ---------------------------------------------------------------------------
# PSA6006 — Switch parameter defaulting to $true (warning, default ON)
# ---------------------------------------------------------------------------

t('PSA6006 positive: [switch]$Flag = $true',
  'PSA6006',
  'function Foo {\n'
  '    param([switch]$Flag = $true)\n'
  '}\n',
  1)

t('PSA6006 negative: [switch]$Flag (default $false)',
  'PSA6006',
  'function Foo {\n'
  '    param([switch]$Flag)\n'
  '}\n',
  0)


# ---------------------------------------------------------------------------
# PSA6007 — Advanced function returns a value but lacks [OutputType()]
# (info, default ON, new in 3.6.0)
# ---------------------------------------------------------------------------

t('PSA6007 positive: advanced function returns value but no OutputType',
  'PSA6007',
  'function Get-Foo {\n'
  '    [CmdletBinding()]\n'
  '    param()\n'
  '    return [pscustomobject]@{ A = 1 }\n'
  '}\n',
  1)

t('PSA6007 positive: returns a string, no OutputType',
  'PSA6007',
  'function Get-Bar {\n'
  '    [CmdletBinding()]\n'
  '    param()\n'
  '    return "hello"\n'
  '}\n',
  1)

t('PSA6007 negative: OutputType is declared',
  'PSA6007',
  'function Get-Baz {\n'
  '    [CmdletBinding()]\n'
  '    [OutputType([pscustomobject])]\n'
  '    param()\n'
  '    return [pscustomobject]@{ A = 1 }\n'
  '}\n',
  0)

t('PSA6007 negative: no CmdletBinding (plain helper, exempt)',
  'PSA6007',
  'function Get-Plain {\n'
  '    param()\n'
  '    return 42\n'
  '}\n',
  0)

t('PSA6007 negative: advanced function with no return statement',
  'PSA6007',
  'function Set-Thing {\n'
  '    [CmdletBinding()]\n'
  '    param()\n'
  '    Write-Host "done"\n'
  '}\n',
  0)

t('PSA6007 edge: bare "return" with no value does not fire',
  'PSA6007',
  'function Test-Guard {\n'
  '    [CmdletBinding()]\n'
  '    param()\n'
  '    if (-not $true) { return }\n'
  '    Write-Host "ok"\n'
  '}\n',
  0)


# ---------------------------------------------------------------------------
# PSA6008 — Function with attributes but no explicit param() block
# (info, default ON, new in 3.6.0)
# ---------------------------------------------------------------------------

t('PSA6008 positive: CmdletBinding attribute without param()',
  'PSA6008',
  'function Show-Banner {\n'
  '    [CmdletBinding()]\n'
  '    Write-Host "banner"\n'
  '}\n',
  1)

t('PSA6008 positive: SuppressMessageAttribute without param()',
  'PSA6008',
  'function Show-Status {\n'
  '    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(\n'
  '        "PSAvoidUsingWMICmdlet", "",\n'
  '        Justification = "Intentional WMI fallback for Server Core.")]\n'
  '    Get-WmiObject -Class Win32_BIOS\n'
  '}\n',
  1)

t('PSA6008 negative: CmdletBinding + param() (correct pattern)',
  'PSA6008',
  'function Show-Banner {\n'
  '    [CmdletBinding()]\n'
  '    param()\n'
  '    Write-Host "banner"\n'
  '}\n',
  0)

t('PSA6008 negative: no attributes (plain function, no param required)',
  'PSA6008',
  'function Show-Simple {\n'
  '    Write-Host "simple"\n'
  '}\n',
  0)

t('PSA6008 edge: OutputType attribute alone also requires param()',
  'PSA6008',
  'function Get-Value {\n'
  '    [OutputType([int])]\n'
  '    return 42\n'
  '}\n',
  1)


# ---------------------------------------------------------------------------
# PSA9001 — Function body exceeds max_function_lines (info, default OFF)
# ---------------------------------------------------------------------------

# Build a function with 250 lines (> default 200 threshold)
_long_body = '\n'.join(['    $x = ' + str(i) for i in range(250)])
t('PSA9001 positive: function body of 250 lines (> 200 default)',
  'PSA9001',
  'function Get-Big {\n'
  + _long_body + '\n'
  '}\n',
  1)

t('PSA9001 negative: short function body',
  'PSA9001',
  'function Get-Small {\n'
  '    return 42\n'
  '}\n',
  0)


# ---------------------------------------------------------------------------
# PSA9002 — External-process invocation without $LASTEXITCODE check
#           (warning, default OFF)
# ---------------------------------------------------------------------------

t('PSA9002 positive: native call (& exe) without $LASTEXITCODE check',
  'PSA9002',
  '& notepad.exe /foo\n'
  'Write-Host "done"\n',
  1)

t('PSA9002 positive: cmd.exe call without $LASTEXITCODE check',
  'PSA9002',
  'cmd.exe /c dir\n'
  'Write-Host "done"\n',
  1)

t('PSA9002 negative: native call followed by $LASTEXITCODE check',
  'PSA9002',
  '& notepad.exe /foo\n'
  'if ($LASTEXITCODE -ne 0) { throw "failed" }\n',
  0)


# ---------------------------------------------------------------------------
# PSAP0001 — Phase function naming convention (warning, default OFF)
# ---------------------------------------------------------------------------

t('PSAP0001 positive: malformed phase function name',
  'PSAP0001',
  'function Invoke-PrepPhase_NoDigits { }\n',
  1)

t('PSAP0001 negative: well-formed phase function name',
  'PSAP0001',
  'function Invoke-PrepPhase00_Initialize { }\n',
  0)

t('PSAP0001 negative: non-phase function (not subject to rule)',
  'PSAP0001',
  'function Get-AmdNpuPlatform { }\n',
  0)


# ---------------------------------------------------------------------------
# PSAP0002 — Required script identifier variables (warning, default OFF)
# ---------------------------------------------------------------------------

t('PSAP0002 positive: script missing all three identifier variables',
  'PSAP0002',
  '# script body without identifier variables\n'
  'function Get-Foo { }\n',
  3)  # all three are missing → 3 hits

t('PSAP0002 negative: all three identifier variables present',
  'PSAP0002',
  "$Script:ScriptVersion = '1.0'\n"
  "$Script:ScriptHash = 'aabb'\n"
  "$Script:ScriptShortTag = 'foo'\n"
  'function Get-Foo { }\n',
  0)


# ---------------------------------------------------------------------------
# PSAP0003 — Inline revision-tag comments (warning, default OFF)
#   (existing PSAP0003/0004 coverage kept from test_psap_3_4.py, condensed)
# ---------------------------------------------------------------------------

t('PSAP0003 positive: bare colon form',
  'PSAP0003', '# r42: fixed timezone bug\n$x = 1\n', 1)

t('PSAP0003 positive: parenthesised inline tag',
  'PSAP0003', '# This was added (r42) for compatibility\n', 1)

t('PSAP0003 negative: prose mention without colon/plus/paren',
  'PSAP0003',
  '# Before r13, this did X instead of Y\n'
  '# In r06 and earlier we used Z\n',
  0)

t('PSAP0003 edge: rNN in string literal is not flagged',
  'PSAP0003',
  "$Script:ScriptVersion = 'chipset-2026.05.18-r60'\n",
  0)

t('PSAP0003 edge: rNN in here-string is not flagged',
  'PSAP0003',
  "$banner = @'\n# r42: this is inside a here-string\n'@\n",
  0)


# ---------------------------------------------------------------------------
# PSAP0004 — End-of-file REVISION HISTORY blocks (warning, default OFF)
# ---------------------------------------------------------------------------

t('PSAP0004 positive: bare REVISION HISTORY header',
  'PSAP0004', '# REVISION HISTORY\n', 1)

t('PSAP0004 positive: equals-decorated CHANGELOG header',
  'PSAP0004', '# ======== CHANGELOG ========\n', 1)

t('PSAP0004 positive: case-insensitive VERSION HISTORY',
  'PSAP0004', '# Version History:\n', 1)

t('PSAP0004 negative: header text inside a string literal',
  'PSAP0004', "$x = '# REVISION HISTORY'\n", 0)

t('PSAP0004 negative: ordinary comment',
  'PSAP0004', '# This script does X\n', 0)


# ---------------------------------------------------------------------------
# File-meta rule: PSA7001 — Missing UTF-8 BOM (warning, default ON)
# ---------------------------------------------------------------------------
# PSA7001 fires from analyze_text() ONLY when file_meta carries
# {'has_bom': False}. So we drive it the same way main() does.

def _add_file_meta_test(name, file_meta, expected):
    TESTS.append(('rule', name, 'PSA7001',
                  '$x = 1\n', expected, file_meta))

_add_file_meta_test(
    'PSA7001 positive: file_meta says has_bom=False',
    {'has_bom': False}, 1)
_add_file_meta_test(
    'PSA7001 negative: file_meta says has_bom=True',
    {'has_bom': True}, 0)
_add_file_meta_test(
    'PSA7001 edge: file_meta=None is silent (back-compat)',
    None, 0)


# ---------------------------------------------------------------------------
# File-meta rule: PSA7002 — LF-only / mixed line endings (warning, default ON)
# ---------------------------------------------------------------------------
# PSA7002 fires from analyze_text() ONLY when file_meta carries a
# 'line_ending_stats' sub-dict with lf_only_count > 0. The check
# function reads the stats dict; the production driver in main()
# populates it from raw bytes via compute_line_ending_stats().

def _add_psa7002_test(name, line_ending_stats, expected):
    TESTS.append(('rule', name, 'PSA7002',
                  '$x = 1\n', expected,
                  {'has_bom': True, 'line_ending_stats': line_ending_stats}))

_add_psa7002_test(
    'PSA7002 positive: all-LF (no CR anywhere)',
    {'lf_count': 10, 'cr_count': 0,
     'lf_only_count': 10, 'lf_only_lines': list(range(1, 11))},
    1)
_add_psa7002_test(
    'PSA7002 positive: mixed CRLF + LF (the D.23 case)',
    {'lf_count': 10, 'cr_count': 8,
     'lf_only_count': 2, 'lf_only_lines': [3, 7]},
    1)
_add_psa7002_test(
    'PSA7002 negative: all-CRLF (lf_only_count = 0)',
    {'lf_count': 10, 'cr_count': 10,
     'lf_only_count': 0, 'lf_only_lines': []},
    0)
_add_psa7002_test(
    'PSA7002 negative: empty file (no newlines at all)',
    {'lf_count': 0, 'cr_count': 0,
     'lf_only_count': 0, 'lf_only_lines': []},
    0)


def _add_psa7002_no_stats_test(name, file_meta, expected):
    TESTS.append(('rule', name, 'PSA7002',
                  '$x = 1\n', expected, file_meta))

_add_psa7002_no_stats_test(
    'PSA7002 edge: file_meta with no line_ending_stats is silent',
    {'has_bom': True}, 0)
_add_psa7002_no_stats_test(
    'PSA7002 edge: file_meta=None is silent (back-compat)',
    None, 0)


# Helper test for compute_line_ending_stats() — it is called by main()
# and must produce the exact dict shape consumed by check_line_endings.
# We exercise it directly with synthetic byte buffers via a dedicated
# test driver (Section 2.5 in the runner), separate from TESTS because
# its tuple shape differs.
COMPUTE_TESTS = []

def _add_compute_test(name, raw_bytes, expected_lf_only_count, expected_cr_count):
    COMPUTE_TESTS.append((name, raw_bytes,
                          expected_lf_only_count, expected_cr_count))

_add_compute_test(
    'compute: 3 CRLF lines, no LF-only',
    b'$x = 1\r\n$y = 2\r\n$z = 3\r\n', 0, 3)
_add_compute_test(
    'compute: 3 LF-only lines, no CR',
    b'$x = 1\n$y = 2\n$z = 3\n', 3, 0)
_add_compute_test(
    'compute: mixed - 2 CRLF then 1 LF-only',
    b'$x = 1\r\n$y = 2\r\n$z = 3\n', 1, 2)
_add_compute_test(
    'compute: file without trailing newline',
    b'$x = 1\r\n$y = 2', 0, 1)
_add_compute_test(
    'compute: empty bytes',
    b'', 0, 0)


# ---------------------------------------------------------------------------
# Cross-file rule: PSA8001 — Function body hash drift
# ---------------------------------------------------------------------------
# PSA8001 is implemented at the main() driver level (check_function_sync
# over collect_function_bodies). We test the helpers directly.

def _psa8001_collect(source):
    clean = psa.strip_strings_and_comments(source)
    return psa.collect_function_bodies(clean)


def _run_psa8001(file_map, ignore=None):
    """Run check_function_sync on synthetic per-file data."""
    per_file = {}
    for path, src in file_map.items():
        per_file[Path(path)] = _psa8001_collect(src)
    return psa.check_function_sync(per_file, ignore_functions=ignore or [])


def _psa8001_count(results_by_path, name_substr=None):
    total = 0
    for _path, issues in results_by_path.items():
        for i in issues:
            if i['code'] != 'PSA8001':
                continue
            if name_substr and name_substr not in i.get('message', ''):
                continue
            total += 1
    return total


PSA8001_TESTS = []


def t8(name, file_map, ignore, expected_total):
    PSA8001_TESTS.append((name, file_map, ignore, expected_total))


# Positive: shared helper drifts between two files. The difference
# must lie outside string literals — strip_strings_and_comments()
# collapses every string to whitespace before hashing, so a body that
# differs only inside a "..." would hash identically. The constant
# multipliers (2 vs 3) below survive the stripper.
_FILE_A = (
    'function Format-Elapsed { param($s) $s * 2 }\n'
    'function Get-AmdChipsetPlatform { 1 }\n'
)
_FILE_B = (
    'function Format-Elapsed { param($s) $s * 3 }\n'  # body drift!
    'function Get-AmdGraphicsPlatform { 2 }\n'
)
t8('PSA8001 positive: shared helper drifts between A and B',
   {'/tmp/a.ps1': _FILE_A, '/tmp/b.ps1': _FILE_B}, None, 2)

# Negative: shared helper has identical body
_FILE_C = _FILE_A  # same body as A
t8('PSA8001 negative: shared helper byte-identical between A and C',
   {'/tmp/a.ps1': _FILE_A, '/tmp/c.ps1': _FILE_C}, None, 0)

# Edge: per-script function ignored via regex (phase functions)
_FILE_D = (
    'function Invoke-PrepPhase00_Initialize { $x = 1 }\n'
)
_FILE_E = (
    'function Invoke-PrepPhase00_Initialize { $x = 2 }\n'
)
t8('PSA8001 edge: phase function pattern ignored via regex',
   {'/tmp/d.ps1': _FILE_D, '/tmp/e.ps1': _FILE_E},
   ['regex:^Invoke-(Prep|Verify|Inst)Phase\\d{2}_'],
   0)


# ---------------------------------------------------------------------------
# CLI tests: --config-check (Pillar 2) and --self-check (Pillar 3)
# ---------------------------------------------------------------------------

CLI_TESTS = []


def cli(name, argv, expected_exit):
    """Drive psa.py via subprocess; only check exit code."""
    CLI_TESTS.append((name, argv, expected_exit))


# --self-check on the shipped tree must pass (Phase 2-C contract)
cli('CLI --self-check: shipped SPEC.md ↔ RULES agree',
    ['--self-check'], 0)

# --config-check on shipped JSONC template must pass
cli('CLI --config-check: shipped .psa.config.json.template is clean',
    ['--config-check', str(PSA_PATH.parent / '.psa.config.json.template')],
    0)


# Will be filled in dynamically at run time, after we create broken
# configs in a tempdir.
_DYNAMIC_CLI = []


def _build_dynamic_cli(tmpdir):
    """Create broken config files and register CLI assertions for them."""
    broken_path = Path(tmpdir) / 'broken.config.json'
    broken_path.write_text(
        '{\n'
        '  "enable": ["PSAP9999"],\n'
        '  "unknown_key": 1\n'
        '}\n',
        encoding='utf-8',
    )
    _DYNAMIC_CLI.append((
        'CLI --config-check: unknown rule ID + unknown top-key → exit 2',
        ['--config-check', str(broken_path)], 2,
    ))

    bad_json_path = Path(tmpdir) / 'malformed.config.json'
    bad_json_path.write_text(
        '{\n'
        '  "enable": [unterminated\n',  # bad JSON
        encoding='utf-8',
    )
    _DYNAMIC_CLI.append((
        'CLI --config-check: malformed JSON → exit 2',
        ['--config-check', str(bad_json_path)], 2,
    ))

    good_path = Path(tmpdir) / 'good.config.json'
    good_path.write_text(
        '{\n'
        '  "enable": ["PSAP0003", "PSAP0004"],\n'
        '  "max_line_length": 120\n'
        '}\n',
        encoding='utf-8',
    )
    _DYNAMIC_CLI.append((
        'CLI --config-check: minimal good config → exit 0',
        ['--config-check', str(good_path)], 0,
    ))


def _run_cli(argv):
    """Invoke psa.py with the given argv tail; return exit code."""
    cmd = [sys.executable, str(PSA_PATH)] + argv
    env = dict(os.environ)
    # Suppress version-self-check noise on stderr during CLI tests.
    env['PSA_CONFIG_QUIET'] = '1'
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return proc.returncode, proc.stdout, proc.stderr


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

def run():
    pass_count = 0
    fail_count = 0
    failures = []

    # --- Section 1: per-rule analyze_text tests ---
    print('=' * 72)
    print(f'Section 1: per-rule analyze_text tests ({len(TESTS)} cases)')
    print('=' * 72)
    for entry in TESTS:
        kind, name, code, source, expected, file_meta = entry
        results = _run_text([code], source, file_meta=file_meta)
        got = _count(results, code)
        ok = got == expected
        status = 'PASS' if ok else 'FAIL'
        line = f'  [{status}] {name}  ({code}: {got}/{expected})'
        print(line)
        if ok:
            pass_count += 1
        else:
            fail_count += 1
            failures.append((name, [
                f'    L{r["line"]} [{r["code"]}] {r["message"]}'
                for r in results
            ]))

    # --- Section 2: PSA8001 cross-file ---
    print()
    print('=' * 72)
    print(f'Section 2: PSA8001 cross-file tests ({len(PSA8001_TESTS)} cases)')
    print('=' * 72)
    for name, file_map, ignore, expected_total in PSA8001_TESTS:
        results = _run_psa8001(file_map, ignore=ignore)
        got = _psa8001_count(results)
        ok = got == expected_total
        status = 'PASS' if ok else 'FAIL'
        print(f'  [{status}] {name}  (PSA8001 hits: {got}/{expected_total})')
        if ok:
            pass_count += 1
        else:
            fail_count += 1
            details = []
            for path, issues in results.items():
                for i in issues:
                    details.append(f'    {path} L{i["line"]} '
                                   f'[{i["code"]}] {i["message"]}')
            failures.append((name, details))

    # --- Section 2.5: compute_line_ending_stats helper (PSA7002 support) ---
    print()
    print('=' * 72)
    print(f'Section 2.5: compute_line_ending_stats tests '
          f'({len(COMPUTE_TESTS)} cases)')
    print('=' * 72)
    for name, raw_bytes, expected_lf_only, expected_cr in COMPUTE_TESTS:
        stats = psa.compute_line_ending_stats(raw_bytes)
        got_lf_only = stats['lf_only_count']
        got_cr = stats['cr_count']
        ok = (got_lf_only == expected_lf_only) and (got_cr == expected_cr)
        status = 'PASS' if ok else 'FAIL'
        print(f'  [{status}] {name}  '
              f'(lf_only: {got_lf_only}/{expected_lf_only}, '
              f'cr: {got_cr}/{expected_cr})')
        if ok:
            pass_count += 1
        else:
            fail_count += 1
            failures.append((name, [
                f'    lf_only_count: got {got_lf_only}, expected {expected_lf_only}',
                f'    cr_count:      got {got_cr}, expected {expected_cr}',
                f'    full stats:    {stats!r}',
            ]))

    # --- Section 3: CLI --config-check / --self-check ---
    with tempfile.TemporaryDirectory(prefix='psa_test_') as tmpdir:
        _build_dynamic_cli(tmpdir)
        all_cli = list(CLI_TESTS) + list(_DYNAMIC_CLI)
        print()
        print('=' * 72)
        print(f'Section 3: CLI self-quality tests ({len(all_cli)} cases)')
        print('=' * 72)
        for name, argv, expected_exit in all_cli:
            rc, _out, _err = _run_cli(argv)
            ok = rc == expected_exit
            status = 'PASS' if ok else 'FAIL'
            print(f'  [{status}] {name}  (exit: {rc}/{expected_exit})')
            if ok:
                pass_count += 1
            else:
                fail_count += 1
                failures.append((name, [
                    f'    stdout: {_out.strip()[:200]}',
                    f'    stderr: {_err.strip()[:200]}',
                ]))

    # --- Summary ---
    print()
    print('=' * 72)
    print(f'Result: {pass_count} passed, {fail_count} failed')
    print('=' * 72)
    if failures:
        print()
        print('Failure details:')
        for name, details in failures:
            print(f'  - {name}')
            for d in details:
                print(d)
    return 0 if fail_count == 0 else 1


if __name__ == '__main__':
    sys.exit(run())
