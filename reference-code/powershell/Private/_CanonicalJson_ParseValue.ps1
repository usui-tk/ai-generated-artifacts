# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsevalue version=1.0.0 hash=d4708a17197eae1f policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseValue {
    param($State)
    if ($State.i -ge $State.n) { throw "Unexpected end of input." }
    $c = $State.s[$State.i]
    if ($c -eq '{') { return _CanonicalJson_ParseObject $State }
    if ($c -eq '[') { return _CanonicalJson_ParseArray  $State }
    if ($c -eq '"') { return _CanonicalJson_ParseString $State }
    if ($c -eq '-' -or ($c -ge '0' -and $c -le '9')) { return _CanonicalJson_ParseNumber $State }
    if ($c -eq 't' -or $c -eq 'f') { return _CanonicalJson_ParseBool $State }
    if ($c -eq 'n') { return _CanonicalJson_ParseNull $State }
    throw "Unexpected character '$c' at position $($State.i)."
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsevalue <<<
