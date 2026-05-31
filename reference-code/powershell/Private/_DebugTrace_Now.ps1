# >>> CANONICAL unit_id=pwsh.helper.debugtrace-now version=0.1.0 hash=6cef1239adbe85aa policy=canonical binding=follow-latest >>>
function _DebugTrace_Now {
    # Return current time as ISO 8601 string with milliseconds and Z
    # suffix. Pre-converted to string so ConvertTo-Json doesn't render
    # the PS 5.1 legacy /Date(N)/ format - we want the same machine-
    # readable representation regardless of PS version.
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}
# <<< CANONICAL unit_id=pwsh.helper.debugtrace-now <<<
