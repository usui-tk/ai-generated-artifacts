# >>> CANONICAL unit_id=pwsh.helper.write-phasefooter version=0.1.0 hash=762ec88efd33dc33 policy=canonical binding=follow-latest >>>
function Write-PhaseFooter {
    # Closes a phase started by Write-PhaseHeader. Records the elapsed
    # duration in $Script:PhaseTimings (used by run-summary helpers).
    #
    # Idempotent: a second call with the same Id is ignored, so wrapping
    # try/finally blocks do not double-count.
    #
    # Status values:
    #   done    - phase completed successfully
    #   cached  - phase was a no-op because the target state was already met
    #   skipped - phase was intentionally skipped (e.g. -OnlyPhases filter)
    #   failed  - phase threw an exception
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [ValidateSet('done','cached','skipped','failed')] [string]$Status
    )
    foreach ($t in $Script:PhaseTimings) {
        if ($t.Id -eq $Id) { return }
    }
    $color = switch ($Status) {
        'done'    { 'Green' }
        'cached'  { 'DarkGray' }
        'skipped' { 'DarkGray' }
        'failed'  { 'Red' }
    }
    $elapsed = if ($Script:CurrentPhaseStart) { (Get-Date) - $Script:CurrentPhaseStart } else { [TimeSpan]::Zero }
    $elapsedStr = Format-Elapsed $elapsed

    $Script:PhaseTimings.Add([pscustomobject]@{
        Id      = $Id
        Status  = $Status
        Elapsed = $elapsed
        EndedAt = Get-Date
    }) | Out-Null

    Write-Host (' PHASE {0,-4} -> {1,-7}  elapsed: {2}' -f $Id, $Status.ToUpper(), $elapsedStr) -ForegroundColor $color

    # Reset so any stray Write-Step/Ok between phases doesn't show a
    # misleading [+X.XXs] tag inherited from the previous phase.
    $Script:CurrentPhaseStart = $null
    $Script:CurrentPhaseId    = $null
}
# <<< CANONICAL unit_id=pwsh.helper.write-phasefooter <<<
