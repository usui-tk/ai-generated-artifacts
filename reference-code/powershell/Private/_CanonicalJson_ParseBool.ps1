# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsebool version=1.0.0 hash=13b060dca910d5f7 policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseBool {
    param($State)
    $s = $State.s
    if ($State.i + 4 -le $State.n -and $s.Substring($State.i,4) -eq 'true')  { $State.i += 4; return $true }
    if ($State.i + 5 -le $State.n -and $s.Substring($State.i,5) -eq 'false') { $State.i += 5; return $false }
    throw "Invalid literal at position $($State.i)."
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsebool <<<
