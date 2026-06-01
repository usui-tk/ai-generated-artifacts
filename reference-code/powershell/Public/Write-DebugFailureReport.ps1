# >>> CANONICAL unit_id=pwsh.helper.write-debugfailurereport version=1.0.0 hash=8c1dda9940c309c1 policy=canonical binding=follow-latest >>>
function Write-DebugFailureReport {
    <#
    .SYNOPSIS
        Emit a formatted failure report via Write-Caution + log the
        failure event to JSONL. Call from a catch block. Also marks
        the active phase's registry entry as 'failure' if applicable.
    .PARAMETER ErrorRecord
        The $_ inside a catch block.
    .PARAMETER IncludeStepHistory
        If set, log every step the trace reached before the failure.
    .PARAMETER AutoExport
        If set, automatically write a JSON snapshot to the configured
        auto-export directory. Use this for top-level catch handlers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $ErrorRecord,
        [switch]$IncludeStepHistory,
        [switch]$AutoExport
    )
    $r = Format-DebugFailure -ErrorRecord $ErrorRecord

    # Update the phase registry if this failure happened inside a phase.
    if ($r.PhaseId -and $Script:DebugTracePhaseRegistry.ContainsKey($r.PhaseId)) {
        $reg = $Script:DebugTracePhaseRegistry[$r.PhaseId]
        $reg.Outcome    = 'failure'
        $reg.FailureRef = $r
    }

    Write-Caution ("{0}: FAILED at step '{1}' (elapsed {2:F2}s)" -f $r.Context, $r.FailedStep, $r.Elapsed.TotalSeconds)
    Write-Caution ("  ExType   : {0}" -f $r.ExType)
    Write-Caution ("  Message  : {0}" -f $r.ExMessage)
    if ($r.InnerType) {
        Write-Caution ("  Inner    : {0} - {1}" -f $r.InnerType, $r.InnerMessage)
    }
    if ($r.FullyQualifiedId) {
        Write-Caution ("  FQErrId  : {0}" -f $r.FullyQualifiedId)
    }
    if ($r.ScriptStackTrace) {
        $stackLines = $r.ScriptStackTrace -split "`r?`n"
        Write-Caution ("  Stack    : {0}" -f $stackLines[0])
        $maxStack = [Math]::Min(3, $stackLines.Count)
        for ($i = 1; $i -lt $maxStack; $i++) {
            Write-Caution ("             {0}" -f $stackLines[$i])
        }
    }
    if ($IncludeStepHistory -and $r.StepHistory.Count -gt 0) {
        Write-Caution ("  Steps    : {0} recorded" -f $r.StepHistory.Count)
        $firstAt = $r.StepHistory[0].At
        foreach ($h in $r.StepHistory) {
            $rel = ($h.At - $firstAt).TotalMilliseconds
            Write-Caution ('    +{0,7:F0}ms  {1}' -f $rel, $h.Step)
        }
    }

    _DebugTrace_WriteJsonlLine ([pscustomobject]@{
        ts          = _DebugTrace_Now
        kind        = 'failure'
        ctx         = $r.Context
        step        = $r.FailedStep
        elapsedMs   = $r.ElapsedMs
        phase       = $r.PhaseId
        exType      = $r.ExType
        msg         = $r.ExMessage
        innerType   = $r.InnerType
        innerMsg    = $r.InnerMessage
        fqErrId     = $r.FullyQualifiedId
        stack       = $r.ScriptStackTrace
        stepHistory = $r.StepHistory
    })

    if ($AutoExport -and $Script:DebugTraceAutoExportEnabled -and $Script:DebugTraceAutoExportDir) {
        try {
            $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $tag = if ($r.PhaseId) { $r.PhaseId } else { 'top' }
            $exportPath = Join-Path $Script:DebugTraceAutoExportDir ("debugtrace_export_{0}_{1}.json" -f $tag, $ts)
            Export-DebugTraceJson -Path $exportPath -IncludeEvents:$false | Out-Null
            Write-Caution ("  TraceJson: {0}" -f $exportPath)
        } catch {
            # Don't let auto-export failures hide the original error.
            Write-Caution ("  TraceJson: auto-export failed: {0}" -f $_.Exception.Message)
        }
    }
}
# <<< CANONICAL unit_id=pwsh.helper.write-debugfailurereport <<<
