# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writenumber version=1.0.0 hash=fd7410b6e533b4cd policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteNumber {
    param($N, [System.Text.StringBuilder]$Sb)
    $ic = [System.Globalization.CultureInfo]::InvariantCulture
    if ($N -is [double] -or $N -is [single]) {
        $s = ([double]$N).ToString('R', $ic)
        # Python emits integer-valued floats with a trailing .0 (e.g. 100.0).
        if ($s -notmatch '[.eE]') { $s += '.0' }
    } else {
        $s = ([decimal]$N).ToString($ic)
    }
    $s = [System.Text.RegularExpressions.Regex]::Replace($s, '(?<=\d)E(?=[+\-]?\d)', 'e')
    [void]$Sb.Append($s)
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writenumber <<<
