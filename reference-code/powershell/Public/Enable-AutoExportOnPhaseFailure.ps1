# >>> CANONICAL unit_id=pwsh.helper.enable-autoexportonphasefailure version=1.0.0 hash=81f2415bbc83f281 policy=canonical binding=follow-latest >>>
function Enable-AutoExportOnPhaseFailure {
    <#
    .SYNOPSIS
        Turn on automatic JSON Export when a phase fails. When enabled,
        Write-DebugFailureReport -AutoExport will write a snapshot to
        the configured directory.
    .PARAMETER OutputDirectory
        Where to write debugtrace_export_<phaseId>_<timestamp>.json files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$OutputDirectory
    )
    $Script:DebugTraceAutoExportEnabled = $true
    $Script:DebugTraceAutoExportDir     = $OutputDirectory
}
# <<< CANONICAL unit_id=pwsh.helper.enable-autoexportonphasefailure <<<
