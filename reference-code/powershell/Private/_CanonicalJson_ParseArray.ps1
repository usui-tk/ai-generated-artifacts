# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsearray version=r01 hash=bbf604ace71922f6 policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseArray {
    param($State)
    $arr = [System.Collections.Generic.List[object]]::new()
    $State.i++   # consume '['
    _CanonicalJson_SkipWs $State
    if ($State.i -lt $State.n -and $State.s[$State.i] -eq ']') { $State.i++; return ,$arr.ToArray() }
    while ($true) {
        _CanonicalJson_SkipWs $State
        $val = _CanonicalJson_ParseValue $State
        [void]$arr.Add($val)
        _CanonicalJson_SkipWs $State
        $c = $State.s[$State.i]
        if ($c -eq ',') { $State.i++; continue }
        if ($c -eq ']') { $State.i++; break }
        throw "Expected ',' or ']' at position $($State.i)."
    }
    return ,$arr.ToArray()
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsearray <<<
