# >>> CANONICAL unit_id=pwsh.helper.show-phasesummary version=r01 hash=22ed90223f442cc8 policy=canonical binding=follow-latest >>>
function Show-PhaseSummary {
    <#
    .SYNOPSIS
        End-of-run summary table, one row per executed phase.

    .DESCRIPTION
        Two callers exist by design:
          1. P13 FinalReport (`Invoke-ReportPhase13_FinalReport`),
             which calls this as documented in SPEC.md Part B.5
             Step 1 -- the timing table is part of the FinalReport.
          2. The script-tail `finally` block, which calls this as
             a safety net so that a run aborted before P13 (or in
             the outer catch block) still produces a timing table.

        Without coordination, a happy-path run prints the same
        table twice -- once from P13, once from the finally. To
        avoid that visual duplication while keeping the
        safety-net behaviour intact, this function is idempotent:
        the first call prints the table and records the fact via
        `$Script:PhaseSummaryShown`; subsequent calls return
        without printing. Callers that want to force a re-print
        (rare, for testing) can clear the flag first.

    .PARAMETER Force
        If set, prints the table even if it has already been
        printed in this run. Used for ad-hoc inspection; the
        production callers never set this.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [switch]$Force
    )
    if ($Script:PhaseSummaryShown -and -not $Force) {
        return
    }
    $Script:PhaseSummaryShown = $true

    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host ' Phase Timing Summary' -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
    if ($Script:PhaseTimings.Count -eq 0) {
        Write-Host '  (no phases were recorded)' -ForegroundColor DarkGray
    } else {
        foreach ($t in $Script:PhaseTimings) {
            $color = switch ($t.Status) {
                'done'    { 'Green' }
                'skipped' { 'DarkGray' }
                'failed'  { 'Red' }
                default   { 'Gray' }
            }
            Write-Host ('  {0,-4}  {1,-7}  elapsed: {2}' -f $t.Id, $t.Status.ToUpper(), (Format-Elapsed $t.Elapsed)) -ForegroundColor $color
        }
    }
    $totalElapsed = (Get-Date) - $Script:ScriptStartTime
    Write-Host ('  ' + ('-' * 40)) -ForegroundColor DarkGray
    Write-Host ('  Total elapsed: {0}' -f (Format-Elapsed $totalElapsed)) -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}
# <<< CANONICAL unit_id=pwsh.helper.show-phasesummary <<<
