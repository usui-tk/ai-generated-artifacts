<#
.SYNOPSIS
    Canon-test gate runner (ADR 0007 / ADR 0010): single entry point that runs the
    full canon behavioral test suite and returns one pass/fail result.

.DESCRIPTION
    The canon's self-verification (distinct from the quality-tools machinery that
    inspects the canon from outside). It runs, in one invocation:
      - Pester: Canon.Unit.Tests.ps1   (U0/U1/U2 buckets)
      - Pester: Canon.Env.Tests.ps1    (F-state/F-env buckets)
      - Pester: Canon.Smoke.Tests.ps1  (cross-bucket smoke)
      - Python: canonical_json_test.py (T11 byte-parity vs the canon oracle)
    and aggregates them. Exit code 0 iff every element passes (skips are allowed
    and reported). This runner is vendored WITH the canon, so a consumer can run
    the same gate against the vendored module.

    The canon module is resolved from $env:CANON_PSD1 if set, else the sibling
    powershell.psd1 (same convention as Invoke-CanonTestHarness.ps1), so the runner
    is self-contained and needs no external setup.

.PARAMETER SkipPython
    Skip the T11 Python parity test (e.g. when python3 is unavailable). The
    PowerShell Pester suites still run.

.OUTPUTS
    A summary object; exit code 0 (all passed) or 1 (any failure).
#>
[CmdletBinding()]
param(
    [switch]$SkipPython
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if ([string]::IsNullOrEmpty($env:CANON_PSD1)) {
    $env:CANON_PSD1 = Join-Path (Split-Path $here -Parent) 'powershell.psd1'
}

$pesterFiles = @(
    'Canon.Unit.Tests.ps1',
    'Canon.Env.Tests.ps1',
    'Canon.Smoke.Tests.ps1'
)

$totalPassed  = 0
$totalFailed  = 0
$totalSkipped = 0
$elements     = New-Object 'System.Collections.Generic.List[object]'

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

foreach ($file in $pesterFiles) {
    $path = Join-Path $here $file
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $path
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'None'
    $result = Invoke-Pester -Configuration $cfg
    $totalPassed  += $result.PassedCount
    $totalFailed  += $result.FailedCount
    $totalSkipped += $result.SkippedCount
    $elements.Add([pscustomobject]@{
        Element = $file
        Passed  = $result.PassedCount
        Failed  = $result.FailedCount
        Skipped = $result.SkippedCount
    })
}

# T11 - Python byte-parity oracle
$pythonPassed = $true
if (-not $SkipPython) {
    $t11 = Join-Path $here 'canonical_json_test.py'
    $py = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
    if ($py) {
        $output = & $py.Source $t11 2>&1
        $pythonPassed = ($LASTEXITCODE -eq 0)
        $summaryLine = ($output | Where-Object { $_ -match 'Summary:' } | Select-Object -Last 1)
        $elements.Add([pscustomobject]@{
            Element = 'canonical_json_test.py (T11)'
            Passed  = if ($pythonPassed) { '(green)' } else { '(FAIL)' }
            Failed  = if ($pythonPassed) { 0 } else { 1 }
            Skipped = 0
        })
        if (-not $pythonPassed) { $totalFailed += 1 }
    } else {
        Write-Warning 'python3 not found; T11 parity test skipped. Use -SkipPython to silence.'
        $elements.Add([pscustomobject]@{ Element = 'canonical_json_test.py (T11)'; Passed = '(skipped: no python)'; Failed = 0; Skipped = 1 })
        $totalSkipped += 1
    }
}

Write-Host ''
Write-Host '=== Canon test gate (ADR 0007/0010) ==='
$elements | ForEach-Object { Write-Host ('  {0,-32} P={1} F={2} Skip={3}' -f $_.Element, $_.Passed, $_.Failed, $_.Skipped) }
Write-Host ('  TOTAL  Passed={0}  Failed={1}  Skipped={2}' -f $totalPassed, $totalFailed, $totalSkipped)

$allGreen = ($totalFailed -eq 0)
Write-Host ('  RESULT: {0}' -f $(if ($allGreen) { 'PASS' } else { 'FAIL' }))

if ($allGreen) { exit 0 } else { exit 1 }
