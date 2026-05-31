# >>> CANONICAL unit_id=pwsh.helper.disable-debugtracefileoutput version=0.1.0 hash=0dc4d90f4368280a policy=canonical binding=follow-latest >>>
function Disable-DebugTraceFileOutput {
    <#
    .SYNOPSIS
        Stop appending trace events to the JSONL file. Events continue
        to be captured in memory and remain exportable via
        Export-DebugTraceJson.
    #>
    [CmdletBinding()]
    param()
    if (-not $Script:DebugTraceJsonlEnabled) { return }
    _DebugTrace_WriteJsonlLine ([pscustomobject]@{
        ts   = _DebugTrace_Now
        kind = 'file.disable'
    })
    $Script:DebugTraceJsonlEnabled = $false
}
# <<< CANONICAL unit_id=pwsh.helper.disable-debugtracefileoutput <<<
