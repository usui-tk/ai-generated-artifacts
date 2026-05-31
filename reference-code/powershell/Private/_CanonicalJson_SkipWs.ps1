# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-skipws version=r01 hash=fb17dca5e9c37829 policy=canonical binding=follow-latest >>>
function _CanonicalJson_SkipWs {
    param($State)
    $s = $State.s
    while ($State.i -lt $State.n) {
        $c = $s[$State.i]
        if ($c -eq ' ' -or $c -eq "`t" -or $c -eq "`n" -or $c -eq "`r") { $State.i++ }
        else { break }
    }
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-skipws <<<
