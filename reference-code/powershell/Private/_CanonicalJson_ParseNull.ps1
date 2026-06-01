# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsenull version=1.0.0 hash=eeefef1e879bac0a policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseNull {
    param($State)
    $s = $State.s
    if ($State.i + 4 -le $State.n -and $s.Substring($State.i,4) -eq 'null') { $State.i += 4; return $null }
    throw "Invalid literal at position $($State.i)."
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsenull <<<
