[CmdletBinding()]
param(
    [string]$Action = 'TestHarness',
    [string]$CanonModule
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($CanonModule)) {
    if (-not [string]::IsNullOrEmpty($env:CANON_PSD1)) {
        $CanonModule = $env:CANON_PSD1
    } else {
        $CanonModule = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'powershell.psd1'
    }
}
Import-Module -Name $CanonModule -Force

# Load the shared consumer-init fixture (Initialize-CanonSessionState).
. (Join-Path -Path $PSScriptRoot -ChildPath 'CanonSessionState.ps1')

# Reproduce the consumer's $Script: init (the canon's real usage model; ADR 0010)
# so the canon runs under the same preconditions it sees in production.
Initialize-CanonSessionState -Module 'powershell'

if ($Action -eq 'TestHarness') {
    $reader = [Console]::In
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line) { break }
        $line = $line.Trim()
        if ($line -eq '') { continue }
        try {
            $req = $line | ConvertFrom-Json -ErrorAction Stop
            $fnName = [string]$req.fn
            if ([string]::IsNullOrEmpty($fnName)) { throw 'Missing fn field in request.' }
            $cmd = Get-Command -Name $fnName -ErrorAction SilentlyContinue
            if (-not $cmd) { throw ('Function not found in session: ' + $fnName) }
            $splat = @{}
            if ($req.PSObject.Properties['args'] -and $req.args) {
                foreach ($prop in $req.args.PSObject.Properties) { $splat[$prop.Name] = $prop.Value }
            }
            $result = & $cmd @splat
            ([pscustomobject]@{ ok = $true; fn = $fnName; result = $result }) | ConvertTo-Json -Depth 12 -Compress
        } catch {
            $failFn = if ($null -ne $req -and $req.PSObject.Properties['fn']) { [string]$req.fn } else { '' }
            ([pscustomobject]@{ ok = $false; error = $_.Exception.Message; fn = $failFn }) | ConvertTo-Json -Depth 4 -Compress
        }
    }
    exit 0
}
