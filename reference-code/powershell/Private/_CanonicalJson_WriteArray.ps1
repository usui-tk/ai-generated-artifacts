# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writearray version=r01 hash=446e70a1f8ecdffa policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteArray {
    param([object[]]$Items, [int]$Depth, [int]$MaxDepth, [string]$IndentUnit, [System.Text.StringBuilder]$Sb)
    if (($Depth + 1) -gt $MaxDepth) { throw "Object nests deeper than allowed depth ($MaxDepth); reached depth $($Depth + 1)." }
    $childIndent = $IndentUnit * ($Depth + 1)
    $closeIndent = $IndentUnit * $Depth
    [void]$Sb.Append("[`n")
    for ($i = 0; $i -lt $Items.Count; $i++) {
        [void]$Sb.Append($childIndent)
        _CanonicalJson_WriteValue -Value $Items[$i] -Depth ($Depth + 1) -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
        if ($i -lt $Items.Count - 1) { [void]$Sb.Append(',') }
        [void]$Sb.Append("`n")
    }
    [void]$Sb.Append($closeIndent); [void]$Sb.Append(']')
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writearray <<<
