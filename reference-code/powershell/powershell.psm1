# powershell.psm1 - canonical shared PowerShell helper module (reference-code canon).
# Test scaffolding only: dot-sources the per-unit files so the canon can be
# Import-Module'd and tested (P2a). NOT itself a vendored/managed unit.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($sub in @('Private', 'Public')) {
    $dir = Join-Path -Path $PSScriptRoot -ChildPath $sub
    if (Test-Path -LiteralPath $dir) {
        Get-ChildItem -Path $dir -Filter '*.ps1' | ForEach-Object {
            . $_.FullName
        }
    }
}

Export-ModuleMember -Function @(
    'Assert-PowerShellCompatibility',
    'Disable-DebugTraceFileOutput',
    'Enable-AutoExportOnPhaseFailure',
    'Enable-DebugTraceFileOutput',
    'Export-DebugTraceJson',
    'Format-DebugFailure',
    'Format-Elapsed',
    'Get-DebugTraceFileOutputStatus',
    'Get-PhaseElapsedTag',
    'Set-DebugStep',
    'Set-TlsSecurityProtocol',
    'Set-Utf8PipelineEncoding',
    'Show-PowerShellEnvironment',
    'Start-DebugTrace',
    'Stop-DebugTrace',
    'Write-Caution',
    'Write-DebugFailureReport',
    'Write-Detail',
    'Write-Fail',
    'Write-Ok',
    'Write-PhaseFooter',
    'Write-PhaseHeader',
    'Write-Skip',
    'Write-Step',
    'Get-SevenZipPath',
    'Get-LatestSevenZipUrl',
    'Install-SevenZipFallback',
    'Invoke-WebRequestWithRetry',
    'Wait-WithJitter',
    'Initialize-RuntimeDirectories',
    'Invoke-CleanupDirectories',
    'Resolve-RelativeToScript',
    'Test-DangerousPath',
    'Add-ErrorJsonlEntry',
    'Show-PhaseSummary',
    'Write-SubSection',
    'Save-CanonicalJsonFile',
    'ConvertTo-CanonicalJson',
    'ConvertFrom-CanonicalJson'
)
