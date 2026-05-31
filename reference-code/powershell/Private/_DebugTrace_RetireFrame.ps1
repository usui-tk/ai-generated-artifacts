# >>> CANONICAL unit_id=pwsh.helper.debugtrace-retireframe version=0.1.0 hash=d6ed295961b4416e policy=canonical binding=follow-latest >>>
function _DebugTrace_RetireFrame {
    # Move a frame from the active stack into the completed list.
    # Handles the history cap. Idempotent: safe to call even if the
    # frame has already been retired.
    param([Parameter(Mandatory)] $Frame, [Parameter(Mandatory)] [string]$Outcome)

    if (-not $Frame.PSObject.Properties['Outcome'] -or -not $Frame.Outcome) {
        $Frame | Add-Member -MemberType NoteProperty -Name 'Outcome'   -Value $Outcome -Force
        $Frame | Add-Member -MemberType NoteProperty -Name 'EndedAt'   -Value (Get-Date) -Force
        $durationMs = [int]((Get-Date) - $Frame.StartTime).TotalMilliseconds
        $Frame | Add-Member -MemberType NoteProperty -Name 'DurationMs' -Value $durationMs -Force
    }

    $Script:DebugTraceCompletedFrames.Add($Frame) | Out-Null
    while ($Script:DebugTraceCompletedFrames.Count -gt $Script:DebugTraceCompletedCap) {
        $Script:DebugTraceCompletedFrames.RemoveAt(0)
    }
}
# <<< CANONICAL unit_id=pwsh.helper.debugtrace-retireframe <<<
