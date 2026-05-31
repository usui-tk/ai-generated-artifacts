# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parseobject version=0.1.0 hash=85c4245a7afe16d3 policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseObject {
    param($State)
    $obj = [ordered]@{}
    $State.i++   # consume '{'
    _CanonicalJson_SkipWs $State
    if ($State.i -lt $State.n -and $State.s[$State.i] -eq '}') { $State.i++; return [pscustomobject]$obj }
    while ($true) {
        _CanonicalJson_SkipWs $State
        if ($State.s[$State.i] -ne '"') { throw "Expected string key at position $($State.i)." }
        $key = _CanonicalJson_ParseString $State
        _CanonicalJson_SkipWs $State
        if ($State.s[$State.i] -ne ':') { throw "Expected ':' at position $($State.i)." }
        $State.i++   # consume ':'
        _CanonicalJson_SkipWs $State
        $val = _CanonicalJson_ParseValue $State
        $obj[$key] = $val
        _CanonicalJson_SkipWs $State
        $c = $State.s[$State.i]
        if ($c -eq ',') { $State.i++; continue }
        if ($c -eq '}') { $State.i++; break }
        throw "Expected ',' or '}' at position $($State.i)."
    }
    return [pscustomobject]$obj
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parseobject <<<
