# >>> CANONICAL unit_id=pwsh.helper.debugtrace-nextseq version=r01 hash=40affbda93e0dc92 policy=canonical binding=follow-latest >>>
function _DebugTrace_NextSeq {
    # Atomic-ish counter. Single-threaded PowerShell so no Interlocked
    # needed; this is just a small helper for readability.
    $Script:DebugTraceEventSeq++
    return $Script:DebugTraceEventSeq
}
# <<< CANONICAL unit_id=pwsh.helper.debugtrace-nextseq <<<
