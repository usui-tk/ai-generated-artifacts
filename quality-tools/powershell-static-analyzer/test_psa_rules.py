#!/usr/bin/env python3
"""Self-test fixtures for the psa.py rule catalog.

This file replaces the earlier test_psap_3_4.py — which covered only
PSAP0003 / PSAP0004 — with a full-catalog regression suite. Each rule in
psa.py's runtime RULES registry has, at minimum, one positive case (rule
must fire), one negative case (rule must NOT fire), and where applicable
an edge case (e.g. false-positive defenses: rule in string literal, in
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
# PSA2009 — hashtable-Add + foreach indirect binding (added in 4.0.1)
# ---------------------------------------------------------------------------
# These cases exercise the Step 2c2 false-positive defence: when a foreach
# loop-variable is bound indirectly through $Coll.Add(@{...}) + foreach,
# it must NOT be flagged for PSA2009 (the element is a hashtable, which
# supports free property addition).

t('PSA2009 negative (4.0.1): foreach loopvar bound via $Coll.Add(@{...}) is hashtable',
  'PSA2009',
  '$pending = [pscustomobject]@{ State = 1 }\n'
  '$jobs = New-Object System.Collections.ArrayList\n'
  '[void]$jobs.Add(@{ Handle = $h })\n'
  'foreach ($job in $jobs) { $job.Collected = $true }\n',
  0)

t('PSA2009 negative (4.0.1): [void]$Coll.Add(@{...}) with later foreach',
  'PSA2009',
  '$ctx = [pscustomobject]@{ Phase = 1 }\n'
  '$queue = New-Object System.Collections.ArrayList\n'
  '[void]$queue.Add(@{ Item = $x; Collected = $false })\n'
  'foreach ($q in $queue) { $q.Collected = $true }\n',
  0)

t('PSA2009 negative (4.0.1): pipeline-derived collection ($newlyDone = $jobs | Where-Object)',
  'PSA2009',
  '$ctx = [pscustomobject]@{ Phase = 1 }\n'
  '$jobs = New-Object System.Collections.ArrayList\n'
  '[void]$jobs.Add(@{ Handle = $h; Collected = $false })\n'
  '$newlyDone = $jobs | Where-Object { $_.Handle.IsCompleted }\n'
  'foreach ($job in $newlyDone) { $job.Collected = $true }\n',
  0)

t('PSA2009 negative (4.0.1): .Where() method-derived collection',
  'PSA2009',
  '$ctx = [pscustomobject]@{ Phase = 1 }\n'
  '$jobs = New-Object System.Collections.ArrayList\n'
  '[void]$jobs.Add(@{ Handle = $h })\n'
  '$pending = $jobs.Where({ -not $_.Collected })\n'
  'foreach ($p in $pending) { $p.Collected = $true }\n',
  0)

t('PSA2009 negative (4.0.1): two-hop derivation ($a = $b | ...; $c = $a | ...)',
  'PSA2009',
  '$ctx = [pscustomobject]@{ Phase = 1 }\n'
  '$jobs = New-Object System.Collections.ArrayList\n'
  '[void]$jobs.Add(@{ State = 0 })\n'
  '$filtered = $jobs | Where-Object { $true }\n'
  '$selected = $filtered | Select-Object -First 1\n'
  'foreach ($s in $selected) { $s.NewProp = 1 }\n',
  0)

t('PSA2009 negative (4.0.1): hashtable-Add with explicit [hashtable]@{...} cast',
  'PSA2009',
  '$ctx = [pscustomobject]@{ Phase = 1 }\n'
  '$jobs = New-Object System.Collections.ArrayList\n'
  '[void]$jobs.Add([hashtable]@{ Handle = $h })\n'
  'foreach ($job in $jobs) { $job.NewProp = 1 }\n',
  0)

t('PSA2009 positive (4.0.1): $Coll.Add([pscustomobject]@{...}) does NOT trigger Step 2c2',
  'PSA2009',
  # When the collection holds a pscustomobject (not a hashtable), the
  # element foreach variable should still be tracked. We initialise
  # $job directly with [pscustomobject]@{...} elsewhere too so it
  # remains in `declared`. The .Add([pscustomobject]@{...}) form is
  # NOT a hashtable-Add by design (the @{ is preceded by a cast).
  '$job = [pscustomobject]@{ Foo = 1 }\n'
  '$jobs = New-Object System.Collections.ArrayList\n'
  '[void]$jobs.Add([pscustomobject]@{ Foo = 2 })\n'
  '$job.Bar = 3\n',
  1)


# ---------------------------------------------------------------------------
# PSA2011 — Split-Path -LiteralPath ... -Parent (error, default ON, new in 3.9.0)
# ---------------------------------------------------------------------------
# PSA2011 is file-local; it does not require cross-file context, so we can
# use the standard t() harness via analyze_text. PSA2010 is cross-file and
# uses a dedicated harness further down (see PSA2010_TESTS section).

t('PSA2011 positive: classic form (the r74 Defect A site)',
  'PSA2011',
  '$infDir = Split-Path -LiteralPath $InfPath -Parent\n',
  1)

t('PSA2011 positive: reversed switch order',
  'PSA2011',
  '$infDir = Split-Path -Parent -LiteralPath $InfPath\n',
  1)

t('PSA2011 positive: multi-line backtick continuation',
  'PSA2011',
  '$infDir = Split-Path -LiteralPath $InfPath `\n    -Parent\n',
  1)

t('PSA2011 negative: -Path with -Parent (no -LiteralPath)',
  'PSA2011',
  '$infDir = Split-Path -Path $InfPath -Parent\n',
  0)

t('PSA2011 negative: -LiteralPath with -Leaf (no -Parent)',
  'PSA2011',
  '$leaf = Split-Path -LiteralPath $InfPath -Leaf\n',
  0)

t('PSA2011 negative: positional path with -Parent',
  'PSA2011',
  '$infDir = Split-Path $InfPath -Parent\n',
  0)

t('PSA2011 negative: GetDirectoryName (the recommended r75 fix)',
  'PSA2011',
  '$infDir = [System.IO.Path]::GetDirectoryName($InfPath)\n',
  0)

t('PSA2011 negative: bare Split-Path in a comment',
  'PSA2011',
  '# Reminder: Split-Path -LiteralPath $x -Parent fails on ja-JP\n'
  '$infDir = Split-Path -Path $InfPath -Parent\n',
  0)

t('PSA2011 negative: -LiteralPath and -Parent inside a here-string',
  'PSA2011',
  '$msg = @"\nDo not call Split-Path -LiteralPath x -Parent here\n"@\n',
  0)

t('PSA2011 inline-suppress: # psa-disable-line PSA2011 on the call line',
  'PSA2011',
  '$infDir = Split-Path -LiteralPath $InfPath -Parent  '
  '# psa-disable-line PSA2011\n',
  0)


# ---------------------------------------------------------------------------
# PSA1004 — Bare (if/switch/...) used as expression (error, default ON, new in 4.1.0)
# ---------------------------------------------------------------------------
# Real-world origin: r07.0 Step 18 of the update-windows-server-iso pipeline.
# Five lines in Show-Pca2023ReadinessSnapshot used the bare `(if ...)` form
# which PowerShell parses as a command call to 'if' (no such command). The
# parser accepts it as syntactically valid, so PS Parse / PSScriptAnalyzer
# do not flag it; only runtime execution surfaces the failure.

t('PSA1004 positive: bare (if ...) inside -f operand',
  'PSA1004',
  "Write-Host ('Value: {0}' -f (if ($x) { 'a' } else { 'b' }))\n",
  1)

t('PSA1004 positive: bare (switch ...) used as expression',
  'PSA1004',
  "$result = (switch ($x) { 1 { 'one' } 2 { 'two' } })\n",
  1)

t('PSA1004 positive: bare (foreach ...) used as expression',
  'PSA1004',
  "$results = (foreach ($i in 1..10) { $i * 2 })\n",
  1)

t('PSA1004 negative: $(if ...) subexpression form is correct',
  'PSA1004',
  "Write-Host ('Value: {0}' -f $(if ($x) { 'a' } else { 'b' }))\n",
  0)

t('PSA1004 negative: @(if ...) array subexpression is also correct',
  'PSA1004',
  "$arr = @(if ($x) { 1, 2, 3 } else { @() })\n",
  0)

t('PSA1004 negative: top-level if statement (not a parenthesised expression)',
  'PSA1004',
  "if ($x) { 'yes' } else { 'no' }\n",
  0)

t('PSA1004 edge: false-positive defense for bare (if ...) inside a string literal',
  'PSA1004',
  '$msg = "this string contains (if no problem here) inside it"\n',
  0)

t('PSA1004 edge: false-positive defense for `if in identifier-like spelling',
  'PSA1004',
  '$myiffy = 1\n',
  0)


# ---------------------------------------------------------------------------
# PSA2012 — Positional call to function with insufficient args (error, default ON, new in 4.1.0)
# ---------------------------------------------------------------------------
# Real-world origin: r07.0 Step 17 of the update-windows-server-iso pipeline.
# Show-Pca2023ReadinessSnapshot called Write-PhaseHeader 'name' (one positional
# arg) when the target function had three [Parameter(Mandatory)] declarations.
# PowerShell prompted interactively for the missing -Name, hanging the run.

_PSA2012_WPH_DEF = (
    "function Write-PhaseHeader {\n"
    "    param(\n"
    "        [Parameter(Mandatory)] [string]$Id,\n"
    "        [Parameter(Mandatory)] [string]$Name,\n"
    "        [Parameter(Mandatory)] [string]$Group\n"
    "    )\n"
    "    Write-Host \"$Id\"\n"
    "}\n"
)

t('PSA2012 positive: 1 positional arg, 3-Mandatory target (the Step 17 site)',
  'PSA2012',
  _PSA2012_WPH_DEF + "Write-PhaseHeader 'P12'\n",
  1)

t('PSA2012 positive: 2 positional args, 3-Mandatory target',
  'PSA2012',
  _PSA2012_WPH_DEF + "Write-PhaseHeader 'P12' 'Verify'\n",
  1)

t('PSA2012 negative: all 3 positional args provided',
  'PSA2012',
  _PSA2012_WPH_DEF + "Write-PhaseHeader 'P12' 'Verify' 'Report'\n",
  0)

t('PSA2012 negative: all 3 named args provided',
  'PSA2012',
  _PSA2012_WPH_DEF
  + "Write-PhaseHeader -Id 'P12' -Name 'Verify' -Group 'Report'\n",
  0)

t('PSA2012 negative: function has only 1 Mandatory (single-mandatory tolerated)',
  'PSA2012',
  "function Foo {\n"
  "    param(\n"
  "        [Parameter(Mandatory)] [string]$X\n"
  "    )\n"
  "}\n"
  "Foo  # bare-name reference\n",
  0)

t('PSA2012 edge: bare-name reference (function pointer / doc mention)',
  'PSA2012',
  _PSA2012_WPH_DEF + "$ref = Get-Command Write-PhaseHeader\n",
  0)

t('PSA2012 edge: pipeline-arg call (count is intentionally on stdin)',
  'PSA2012',
  _PSA2012_WPH_DEF + "$x | Write-PhaseHeader\n",
  0)

t('PSA2012 edge: backtick-continued multiline call (all 3 named args)',
  'PSA2012',
  _PSA2012_WPH_DEF
  + "Write-PhaseHeader `\n"
  + "    -Id 'P12' `\n"
  + "    -Name 'Verify' `\n"
  + "    -Group 'Report'\n",
  0)

t('PSA2012 edge: splatting @hashtable satisfies Mandatory params',
  'PSA2012',
  _PSA2012_WPH_DEF
  + "$params = @{ Id = 'P12'; Name = 'Verify'; Group = 'Report' }\n"
  + "Write-PhaseHeader @params\n",
  0)

t('PSA2012 edge: splatting + one positional (still safe via splat)',
  'PSA2012',
  _PSA2012_WPH_DEF
  + "$rest = @{ Name = 'Verify'; Group = 'Report' }\n"
  + "Write-PhaseHeader 'P12' @rest\n",
  0)


# ---------------------------------------------------------------------------
# PSA2013 — $Script: read but never assigned (error, default ON, new in 4.1.0)
# ---------------------------------------------------------------------------
# Real-world origin: r07.0 Step 15 of the update-windows-server-iso pipeline.
# Two $Script: typo variants were silently evaluating to $null: the symptom
# was a misleading throw in P10. The correct names existed; the typos did not.

t('PSA2013 positive: $Script:WorkRootFull read but never assigned',
  'PSA2013',
  "$Script:WorkRoot = 'C:\\Work'\n"
  "function Foo {\n"
  "    $a = $Script:WorkRootFull\n"
  "}\n",
  1)

t('PSA2013 positive: $Script:ExtractedMediaPath typo (the Step 15 site)',
  'PSA2013',
  "$Script:ExtractedDir = Join-Path 'C:' 'extracted'\n"
  "function Bar {\n"
  "    $a = $Script:ExtractedMediaPath\n"
  "}\n",
  1)

t('PSA2013 negative: $Script:Foo correctly assigned at top level',
  'PSA2013',
  "$Script:Foo = 1\n"
  "function Foo { $a = $Script:Foo }\n",
  0)

t('PSA2013 negative: $Script:Bar assigned inside another function',
  'PSA2013',
  "function Init { $Script:Bar = 42 }\n"
  "function Use { $b = $Script:Bar }\n",
  0)

t('PSA2013 negative: well-known auto-vars are allowlisted',
  'PSA2013',
  "function Foo { $a = $Script:MyInvocation }\n",
  0)

t('PSA2013 edge: top-level script parameter (auto-populated $Script:)',
  'PSA2013',
  "param([string]$OsVersion = 'Server2016')\n"
  "function Foo { $a = $Script:OsVersion }\n",
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
# PSAP0005 — Revision reference in comment body (warning, default OFF,
#            new in 4.0.0)
# ---------------------------------------------------------------------------
#
# PSAP0005 has two operational modes selected via the
# ``psap0005_relaxed_mode`` config flag. The TESTS table only drives
# the default (strict) mode via _make_cfg(); the relaxed-mode tests
# are dispatched through a dedicated harness below this section.

# --- Strict mode (default): every rNN in a comment fires ---

t('PSAP0005 strict positive: bare rNN colon (also caught by '
  'PSAP0003, but PSAP0005-only run still fires)',
  'PSAP0005', '# r42: this is a tag\n', 1)

t('PSAP0005 strict positive: SECTION header',
  'PSAP0005', '# SECTION r71: WHQL co-sign pre-detection\n', 1)

t('PSAP0005 strict positive: SPEC cross-reference',
  'PSAP0005',
  '# Phantom file reference detection (r65, SPEC D.24): inspect\n', 1)

t('PSAP0005 strict positive: Added in the rNN release phrasing',
  'PSAP0005',
  '# Build the WHQL co-sign analysis (added with the r71 release)\n', 1)

t('PSAP0005 strict positive: Earlier revisions prose',
  'PSAP0005',
  '# Earlier revisions called Find-Signtool, which was undefined '
  'before r74.\n', 1)

t('PSAP0005 strict positive: As of rNN prose',
  'PSAP0005', '# As of r74, the function builds the set once.\n', 1)

t('PSAP0005 strict positive: parenthesised tag',
  'PSAP0005', '# NOTE (r74): the find-kit fix.\n', 1)

t('PSAP0005 strict negative: rNN inside string literal',
  'PSAP0005', "$x = 'chipset-2026.05.25-r75'\n", 0)

t('PSAP0005 strict negative: comment without rNN',
  'PSAP0005', '# This is the canonical implementation.\n', 0)

t('PSAP0005 strict negative: rNN-like sequence in identifier',
  'PSAP0005', '# Process the radeon-r9000-series binding.\n', 0)

t('PSAP0005 strict negative: rNN-like sequence as variable name',
  'PSAP0005', '$radeonR9000 = 1\n', 0)


# Relaxed-mode tests run through a dedicated harness because TESTS
# uses _make_cfg() which always builds a strict-mode Config.

def _run_psap0005(source, relaxed_mode):
    cfg = _make_cfg('PSAP0005')
    cfg.psap0005_relaxed_mode = relaxed_mode
    results = psa.analyze_text(source, cfg, file_meta=None)
    return _count(results, 'PSAP0005')


_RELAXED_TESTS = [
    # (name, source, expected_count_in_relaxed_mode)
    ('PSAP0005 relaxed: SECTION header exempt',
     '# SECTION r71: WHQL co-sign pre-detection\n', 0),
    ('PSAP0005 relaxed: SECTION header with decoration exempt',
     '# === SECTION r71: WHQL co-sign pre-detection ===\n', 0),
    ('PSAP0005 relaxed: SPEC cross-reference exempt',
     '# Phantom file reference (r65, SPEC D.24): inspect\n', 0),
    ('PSAP0005 relaxed: SPEC §D cross-reference exempt',
     '# Honest correction (r74, SPEC §D.32): no-op\n', 0),
    ('PSAP0005 relaxed: added in the rNN release exempt',
     '# Build the WHQL co-sign analysis (added with the r71 release)\n',
     0),
    ('PSAP0005 relaxed: added in rNN release no article exempt',
     '# Filter added in r71 release.\n', 0),
    ('PSAP0005 relaxed: introduced in rNN release exempt',
     '# Helper introduced in the r68 release.\n', 0),
    ('PSAP0005 relaxed: landed in chipset rNN exempt',
     '# Find-KitTool fix landed in chipset r74 / graphics r40.\n', 0),
    ('PSAP0005 relaxed: ported in rNN exempt',
     '# WHQL helper ported in the r39 release.\n', 0),
    ('PSAP0005 relaxed: earlier revisions prose exempt',
     '# Earlier revisions called Find-Signtool, which was undefined '
     'before r74.\n', 0),
    ('PSAP0005 relaxed: previous releases prose exempt',
     '# Previous releases relied on r71 only.\n', 0),
    # Things NOT in the exemption list still fire in relaxed mode:
    ('PSAP0005 relaxed: As of rNN still fires',
     '# As of r74, the function builds the set once.\n', 1),
    ('PSAP0005 relaxed: parenthesised tag still fires',
     '# NOTE (r74): the find-kit fix.\n', 1),
    ('PSAP0005 relaxed: bare rNN colon still fires',
     '# r42: this is a tag\n', 1),
    ('PSAP0005 relaxed: rNN in string literal still does not fire',
     "$x = 'chipset-2026.05.25-r75'\n", 0),
    # ---- v4.0.2 extension tests (E1-E9) ----
    ('PSAP0005 relaxed v4.0.2 E1: semi-section header exempt',
     '# r71 Pre-check: Path B prerequisite check\n', 0),
    ('PSAP0005 relaxed v4.0.2 E2: SPEC cross-ref with slash separator exempt',
     '# Orphan catalog cleanup (r66 / SPEC D.24): the original\n', 0),
    ('PSAP0005 relaxed v4.0.2 E2: SPEC cross-ref with dash separator exempt',
     '# The set is built in three passes (r75 - SPEC D.33):\n', 0),
    ('PSAP0005 relaxed v4.0.2 E3: rNN preceding SPEC ref (reversed parens) exempt',
     '# r68 (SPEC §D.26): LOADED honesty gate\n', 0),
    ('PSAP0005 relaxed v4.0.2 E4: SPEC ref + rNN co-occurrence exempt',
     '# See SPEC SS D.31 for the full r71 design contract\n', 0),
    ('PSAP0005 relaxed v4.0.2 E4: Until rNN + SPEC ref exempt',
     '# Until r39, Graphics shipped the consumer code (see SPEC SS D.31)\n', 0),
    ('PSAP0005 relaxed v4.0.2 E5: rNN adds ... exempt',
     '# r71 adds two operator-protection mechanisms\n', 0),
    ('PSAP0005 relaxed v4.0.2 E5: the X addition in rNN exempt',
     '# the /all addition in r74.\n', 0),
    ('PSAP0005 relaxed v4.0.2 E5: the original rNN release exempt',
     '# The original r74 release threaded $ourInfSet\n', 0),
    ('PSAP0005 relaxed v4.0.2 E5: documents the rNN exempt',
     '# documents the r72 follow-on I02 short-circuit\n', 0),
    ('PSAP0005 relaxed v4.0.2 E6: prior to rNN exempt',
     '# CSV is also absent (e.g. very old workspace prior to r65),\n', 0),
    ('PSAP0005 relaxed v4.0.2 E6: predates rNN exempt',
     '# the inventory predates r65\n', 0),
    ('PSAP0005 relaxed v4.0.2 E6: from an rNN run exempt',
     '# workspace recovered from an r65 run\n', 0),
    ('PSAP0005 relaxed v4.0.2 E7: rNN (QI-X) Q-reference exempt',
     '# r69 (QI-6): bypass the CRITICAL acknowledgement\n', 0),
    ('PSAP0005 relaxed v4.0.2 E7: (Q-X1, rNN) Q-reference exempt',
     '# Install on legacy Windows Server (Q-X1, r17).\n', 0),
    ('PSAP0005 relaxed v4.0.2 E7: QI-X (rNN, YYYY-MM-DD) exempt',
     '# QI-9 (r69, 2026-05-23): System Restore status check.\n', 0),
    ('PSAP0005 relaxed v4.0.2 E8: cross-port marker (graphics) exempt',
     '# r40 (graphics): build the OEM-name lookup set\n', 0),
    ('PSAP0005 relaxed v4.0.2 E8: cross-port marker (bthpan) exempt',
     '# r22 (bthpan): signal to the phase dispatcher\n', 0),
    ('PSAP0005 relaxed v4.0.2 E9: follow-up sentence (rNN: this declaration) exempt',
     '# property cannot be found). r73: this declaration was added\n', 0),
    # ---- v4.0.2 block-level exempt tests ----
    ('PSAP0005 relaxed v4.0.2 block-exempt: multi-line block with added-in-release trigger',
     ('# WHQL co-signature analysis (added with the r71 release).\n'
      '# Pre-declared as $null so plain .assignment works.\n'
      '# Populated by P05; consumed by I00 (C6 condition),\n'
      '# P06 (-SkipNonCosignedDrivers trim), and I02 (r72 short-circuit\n'
      '# for all-WHQL trimmed install plans).\n'), 0),
    ('PSAP0005 relaxed v4.0.2 block-exempt: strict mode still fires (no exempt)',
     # This is tested in strict mode below; here we verify relaxed mode
     # exempt does NOT leak into unrelated comments.
     '# This block has no rNN at all\n', 0),
]


# v4.0.2 strict-mode regression: the block-level exempt must NOT
# leak into strict mode. Every test case from _RELAXED_TESTS that
# would fire 1+ in strict mode is verified here.
_STRICT_NEW_TESTS = [
    ('PSAP0005 strict v4.0.2: semi-section header NOT exempt in strict',
     '# r71 Pre-check: Path B prerequisite check\n', 1),
    ('PSAP0005 strict v4.0.2: SPEC cross-ref slash NOT exempt in strict',
     '# Orphan catalog cleanup (r66 / SPEC D.24):\n', 1),
    ('PSAP0005 strict v4.0.2: Q-reference NOT exempt in strict',
     '# r69 (QI-6): bypass CRITICAL\n', 1),
    ('PSAP0005 strict v4.0.2: cross-port marker NOT exempt in strict',
     '# r40 (graphics): build the OEM-name lookup\n', 1),
    ('PSAP0005 strict v4.0.2: block-level exempt does NOT leak into strict',
     ('# WHQL co-signature analysis (added with the r71 release).\n'
      '# Populated by P05 and I02 (r72 short-circuit\n'), 2),
]


def _run_psap0005_strict_v402_tests():
    failures = []
    for name, source, expected in _STRICT_NEW_TESTS:
        got = _run_psap0005(source, relaxed_mode=False)
        if got != expected:
            failures.append(
                f'  FAIL: {name}\n'
                f'         expected {expected}, got {got}\n'
                f'         source: {source!r}')
    return failures


def _run_psap0005_relaxed_tests():
    failures = []
    for name, source, expected in _RELAXED_TESTS:
        got = _run_psap0005(source, relaxed_mode=True)
        if got != expected:
            failures.append(
                f'  FAIL: {name}\n'
                f'         expected {expected}, got {got}\n'
                f'         source: {source!r}')
    return failures


# Cross-rule dedupe: when both PSAP0003 and PSAP0005 are enabled, the
# same line should not produce TWO warnings (PSAP0003 owns the line).

def _run_psap0003_0005_dedupe():
    cfg = psa.Config()
    cfg.enabled = {k: False for k in cfg.enabled}
    cfg.enabled['PSAP0003'] = True
    cfg.enabled['PSAP0005'] = True
    cfg.min_severity = 'info'

    source = '# r42: a tag with text\n'
    results = psa.analyze_text(source, cfg, file_meta=None)

    failures = []
    n3 = _count(results, 'PSAP0003')
    n5 = _count(results, 'PSAP0005')
    if not (n3 == 1 and n5 == 0):
        failures.append(
            f'  FAIL: PSAP0003 + PSAP0005 dedupe\n'
            f'         expected PSAP0003=1, PSAP0005=0\n'
            f'         got      PSAP0003={n3}, PSAP0005={n5}')
    return failures


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


# ---------------------------------------------------------------------------
# File-meta rule: PSA7003 - non-ASCII character(s) outside the BOM (warning)
# ---------------------------------------------------------------------------
# PSA7003 fires from analyze_text() ONLY when file_meta carries a
# 'non_ascii_stats' sub-dict whose 'occurrences' list is non-empty. The
# production driver in main() populates it from the decoded body via
# compute_non_ascii_stats(). Non-ASCII chars are written here as \u escapes
# so this test file itself stays ASCII-only.

def _add_psa7003_test(name, non_ascii_stats, expected):
    TESTS.append(('rule', name, 'PSA7003',
                  '$x = 1\n', expected,
                  {'has_bom': True, 'non_ascii_stats': non_ascii_stats}))

_add_psa7003_test(
    'PSA7003 positive: single em dash (U+2014)',
    {'count': 1, 'occurrences': [(1, 5, '\u2014', 0x2014)]},
    1)
_add_psa7003_test(
    'PSA7003 positive: section sign + em dash + curly quote',
    {'count': 3, 'occurrences': [(1, 13, '\u00a7', 0x00a7),
                                 (1, 41, '\u2014', 0x2014),
                                 (3, 12, '\u201c', 0x201c)]},
    1)
_add_psa7003_test(
    'PSA7003 negative: no non-ASCII (empty occurrences)',
    {'count': 0, 'occurrences': []},
    0)


def _add_psa7003_no_stats_test(name, file_meta, expected):
    TESTS.append(('rule', name, 'PSA7003',
                  '$x = 1\n', expected, file_meta))

_add_psa7003_no_stats_test(
    'PSA7003 edge: file_meta with no non_ascii_stats is silent',
    {'has_bom': True}, 0)
_add_psa7003_no_stats_test(
    'PSA7003 edge: file_meta=None is silent (back-compat)',
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


# Direct tests for compute_non_ascii_stats() (PSA7003 support). Non-ASCII
# characters are \u escapes so this test file stays ASCII-only.
NON_ASCII_COMPUTE_TESTS = []

def _add_na_compute_test(name, text, expected_count, expected_first):
    # expected_first is (line, col, codepoint) of the first occurrence, or None.
    NON_ASCII_COMPUTE_TESTS.append((name, text, expected_count, expected_first))

_add_na_compute_test(
    'na compute: pure ASCII -> 0',
    '$x = 1\n$y = 2\n', 0, None)
_add_na_compute_test(
    'na compute: single em dash, col tracking',
    'a \u2014 b\n', 1, (1, 3, 0x2014))
_add_na_compute_test(
    'na compute: char on line 2 (line tracking)',
    '$x = 1\n# \u00a7B.1\n', 1, (2, 3, 0x00a7))
_add_na_compute_test(
    'na compute: CR not counted, col correct across CRLF',
    'ab\r\n\u2014\r\n', 1, (2, 1, 0x2014))
_add_na_compute_test(
    'na compute: two non-ASCII on one line',
    '\u201ca\u201d\n', 2, (1, 1, 0x201c))


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
# Cross-file rule: PSA2010 — Call to undefined function (new in v3.9.0)
# ---------------------------------------------------------------------------
# PSA2010 is implemented at the main() driver level, taking the UNION of
# function definitions across all scanned files plus a known-cmdlet
# whitelist. We test the helper directly with controlled inputs.

def _run_psa2010(source, defined_funcs=None, extra_known=None):
    """Run check_undefined_function_call on synthetic per-file data.

    defined_funcs : iterable of locally-defined function names (lowered),
                    representing what would be collected across the
                    cross-file scan set.
    extra_known   : iterable of cmdlet names beyond the default
                    KNOWN_CMDLETS set (simulates the psa.config.json
                    psa2010_known_cmdlets extension).
    """
    clean = psa.strip_strings_and_comments(source)
    defined = {n.lower() for n in (defined_funcs or [])}
    known = set(psa.KNOWN_CMDLETS_LOWER)
    for n in (extra_known or []):
        known.add(n.lower())
    return psa.check_undefined_function_call(clean, defined, known)


PSA2010_TESTS = []


def t10(name, source, expected_count, defined_funcs=None, extra_known=None):
    PSA2010_TESTS.append((name, source, expected_count,
                          defined_funcs, extra_known))


# Positive: the historical r74 defect (Find-Signtool typo). Not in the
# cmdlet whitelist (it does not exist) and not defined locally.
t10('PSA2010 positive: Find-Signtool typo (the r74 Defect 1 site)',
    'function Test-WhqlCoSignature {\n'
    '    $signtool = Find-Signtool\n'
    '}\n',
    1,
    defined_funcs=['Test-WhqlCoSignature'])

# Positive: undefined helper called from a phase function. The verb
# MUST be in APPROVED_VERBS for PSA2010 to consider the name (this is
# a deliberate false-positive defense — names with non-approved verbs
# are more likely module/repo-specific tokens than user-defined PS
# function calls).
t10('PSA2010 positive: undefined helper called from another helper',
    'function Invoke-Foo { Invoke-NoneSuch }\n',
    1,
    defined_funcs=['Invoke-Foo'])

# Negative: the correct call (Find-KitTool IS in defined_funcs)
t10('PSA2010 negative: Find-KitTool is locally defined',
    'function Test-WhqlCoSignature {\n'
    '    $signtool = Find-KitTool \'signtool.exe\'\n'
    '}\n',
    0,
    defined_funcs=['Test-WhqlCoSignature', 'Find-KitTool'])

# Negative: built-in PowerShell cmdlet
t10('PSA2010 negative: built-in cmdlet Get-Content is in KNOWN_CMDLETS',
    'function Read-Foo { Get-Content -Path bar }\n',
    0,
    defined_funcs=['Read-Foo'])

# Negative: cmdlet from PnpDevice module
t10('PSA2010 negative: Get-PnpDevice (PnpDevice module) in KNOWN_CMDLETS',
    'function Get-AmdInventory { Get-PnpDevice -Class Net }\n',
    0,
    defined_funcs=['Get-AmdInventory'])

# Negative: name does not follow Verb-Noun (no hyphen) — not flagged
t10('PSA2010 negative: external binary (no hyphen) is not flagged',
    'function Invoke-Foo { pnputil /enum-drivers }\n',
    0,
    defined_funcs=['Invoke-Foo'])

# Negative: class method call (.NET, not a function call)
t10('PSA2010 negative: .NET class method call',
    'function Invoke-Foo {\n'
    '    [System.IO.Path]::GetDirectoryName($p)\n'
    '}\n',
    0,
    defined_funcs=['Invoke-Foo'])

# Negative: extension via psa2010_known_cmdlets
t10('PSA2010 negative: third-party cmdlet via psa2010_known_cmdlets',
    'function Invoke-Foo { Get-ThirdParty-Foo }\n',
    0,
    defined_funcs=['Invoke-Foo'],
    extra_known=['Get-ThirdParty-Foo'])

# Negative: name in a string literal (stripped by strip_strings_and_comments)
t10('PSA2010 negative: function name appears only in a string literal',
    'function Invoke-Foo { Write-Host "Find-Signtool is not defined" }\n',
    0,
    defined_funcs=['Invoke-Foo'])

# Negative: name in a comment (stripped by strip_strings_and_comments)
t10('PSA2010 negative: function name appears only in a comment',
    'function Invoke-Foo {\n'
    '    # TODO: implement Find-Signtool later\n'
    '    Get-Content -Path foo\n'
    '}\n',
    0,
    defined_funcs=['Invoke-Foo'])

# Negative: version-like substring (Deploy-AMD-2026.05.25-r75 inside a
# string is stripped; the surrounding context should not fire even if
# the stripper missed it). Test that we're not over-matching on
# arbitrary hyphenated tokens.
t10('PSA2010 negative: bare verb-only token (no hyphenated noun)',
    'function Invoke-Foo { $x = "Deploy" }\n',
    0,
    defined_funcs=['Invoke-Foo'])

# Negative: parameter-like name (-Verbose) is not a function call
t10('PSA2010 negative: parameter -Verbose is not a function call',
    'function Invoke-Foo { Get-Content -Path foo -Verbose }\n',
    0,
    defined_funcs=['Invoke-Foo'])

# Edge: function defined in the SAME file via the standard cross-file
# pass (analyze_text driver builds the union). When defined_funcs
# contains the call name, it must NOT fire.
t10('PSA2010 edge: helper defined in same-file is satisfied via cross-file union',
    'function Find-Signtool { "stub" }\n'
    'function Test-WhqlCoSignature { Find-Signtool }\n',
    0,
    defined_funcs=['Find-Signtool', 'Test-WhqlCoSignature'])


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

    # --- Section 2b: PSA2010 cross-file ---
    print()
    print('=' * 72)
    print(f'Section 2b: PSA2010 cross-file tests ({len(PSA2010_TESTS)} cases)')
    print('=' * 72)
    for name, source, expected_count, defined_funcs, extra_known in PSA2010_TESTS:
        results = _run_psa2010(source,
                               defined_funcs=defined_funcs,
                               extra_known=extra_known)
        got = sum(1 for r in results if r['code'] == 'PSA2010')
        ok = got == expected_count
        status = 'PASS' if ok else 'FAIL'
        print(f'  [{status}] {name}  (PSA2010 hits: {got}/{expected_count})')
        if ok:
            pass_count += 1
        else:
            fail_count += 1
            failures.append((name, [
                f'    L{r["line"]} [{r["code"]}] {r["message"]}'
                for r in results
            ]))

    # --- Section 2c: PSAP0005 relaxed-mode tests ---
    print()
    print('=' * 72)
    print(f'Section 2c: PSAP0005 relaxed-mode tests '
          f'({len(_RELAXED_TESTS)} cases)')
    print('=' * 72)
    relaxed_failures = _run_psap0005_relaxed_tests()
    for name, source, expected in _RELAXED_TESTS:
        got = _run_psap0005(source, relaxed_mode=True)
        ok = got == expected
        status = 'PASS' if ok else 'FAIL'
        print(f'  [{status}] {name}  '
              f'(PSAP0005 hits: {got}/{expected})')
        if ok:
            pass_count += 1
        else:
            fail_count += 1
            failures.append((name, [
                f'    expected {expected}, got {got}',
                f'    source: {source!r}',
            ]))

    # --- Section 2d: PSAP0003 + PSAP0005 dedupe ---
    print()
    print('=' * 72)
    print('Section 2d: PSAP0003 + PSAP0005 dedupe tests (1 case)')
    print('=' * 72)
    dedupe_failures = _run_psap0003_0005_dedupe()
    if not dedupe_failures:
        print('  [PASS] PSAP0003 owns line, PSAP0005 does not double-fire')
        pass_count += 1
    else:
        print('  [FAIL] PSAP0003 + PSAP0005 dedupe')
        fail_count += 1
        failures.append(('PSAP0003 + PSAP0005 dedupe', dedupe_failures))

    # --- Section 2e: v4.0.2 strict-mode regression tests ---
    print()
    print('=' * 72)
    print(f'Section 2e: PSAP0005 strict-mode v4.0.2 regression tests '
          f'({len(_STRICT_NEW_TESTS)} cases)')
    print('=' * 72)
    for name, source, expected in _STRICT_NEW_TESTS:
        got = _run_psap0005(source, relaxed_mode=False)
        ok = got == expected
        status = 'PASS' if ok else 'FAIL'
        print(f'  [{status}] {name}  (PSAP0005 hits: {got}/{expected})')
        if ok:
            pass_count += 1
        else:
            fail_count += 1
            failures.append((name, [
                f'    expected {expected}, got {got}',
                f'    source: {source!r}',
            ]))

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

    # --- Section 2.6: compute_non_ascii_stats helper (PSA7003 support) ---
    print()
    print('=' * 72)
    print(f'Section 2.6: compute_non_ascii_stats tests '
          f'({len(NON_ASCII_COMPUTE_TESTS)} cases)')
    print('=' * 72)
    for name, text, expected_count, expected_first in NON_ASCII_COMPUTE_TESTS:
        stats = psa.compute_non_ascii_stats(text)
        got_count = stats['count']
        occ = stats['occurrences']
        got_first = (occ[0][0], occ[0][1], occ[0][3]) if occ else None
        ok = (got_count == expected_count) and (got_first == expected_first)
        status = 'PASS' if ok else 'FAIL'
        print(f'  [{status}] {name}  (count: {got_count}/{expected_count})')
        if ok:
            pass_count += 1
        else:
            fail_count += 1
            failures.append((name, [
                f'    count: got {got_count}, expected {expected_count}',
                f'    first: got {got_first}, expected {expected_first}',
                f'    full stats: {stats!r}',
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
