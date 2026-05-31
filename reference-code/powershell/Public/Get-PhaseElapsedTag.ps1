# >>> CANONICAL unit_id=pwsh.helper.get-phaseelapsedtag version=r01 hash=79f7a70e60311a27 policy=canonical binding=follow-latest >>>
function Get-PhaseElapsedTag {
    # Returns elapsed-since-current-phase-start as '[+X.XXs]' or empty.
    if ($null -eq $Script:CurrentPhaseStart) { return '' }
    $span = (Get-Date) - $Script:CurrentPhaseStart
    return ('[+{0}]' -f (Format-Elapsed $span))
}
# <<< CANONICAL unit_id=pwsh.helper.get-phaseelapsedtag <<<
