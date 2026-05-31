# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writeobject version=r01 hash=52773b3f0e258d35 policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteObject {
    param([object[]]$Pairs, [int]$Depth, [int]$MaxDepth, [string]$IndentUnit, [System.Text.StringBuilder]$Sb)
    if (($Depth + 1) -gt $MaxDepth) { throw "Object nests deeper than allowed depth ($MaxDepth); reached depth $($Depth + 1)." }
    $childIndent = $IndentUnit * ($Depth + 1)
    $closeIndent = $IndentUnit * $Depth
    [void]$Sb.Append("{`n")
    for ($i = 0; $i -lt $Pairs.Count; $i++) {
        [void]$Sb.Append($childIndent)
        _CanonicalJson_WriteString -S $Pairs[$i].K -Sb $Sb
        [void]$Sb.Append(': ')
        _CanonicalJson_WriteValue -Value $Pairs[$i].V -Depth ($Depth + 1) -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
        if ($i -lt $Pairs.Count - 1) { [void]$Sb.Append(',') }
        [void]$Sb.Append("`n")
    }
    [void]$Sb.Append($closeIndent); [void]$Sb.Append('}')
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writeobject <<<
