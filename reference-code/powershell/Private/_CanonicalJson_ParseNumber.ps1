# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsenumber version=r01 hash=0624198cd56a3e41 policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseNumber {
    param($State)
    $start = $State.i
    $s = $State.s
    if ($s[$State.i] -eq '-') { $State.i++ }
    while ($State.i -lt $State.n) {
        $c = $s[$State.i]
        if (($c -ge '0' -and $c -le '9') -or $c -eq '.' -or $c -eq 'e' -or $c -eq 'E' -or $c -eq '+' -or $c -eq '-') { $State.i++ }
        else { break }
    }
    $numStr = $s.Substring($start, $State.i - $start)
    $ic = [System.Globalization.CultureInfo]::InvariantCulture
    if ($numStr -notmatch '[.eE]') {
        $asLong = [long]0
        if ([long]::TryParse($numStr, [ref]$asLong)) { return $asLong }
        return [double]::Parse($numStr, $ic)
    }
    return [double]::Parse($numStr, [System.Globalization.NumberStyles]::Float, $ic)
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsenumber <<<
