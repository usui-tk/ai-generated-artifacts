# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writevalue version=0.1.0 hash=9e36066de2680f5f policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteValue {
    param($Value, [int]$Depth, [int]$MaxDepth, [string]$IndentUnit, [System.Text.StringBuilder]$Sb)

    if ($null -eq $Value) { [void]$Sb.Append('null'); return }

    if ($Value -is [bool]) { [void]$Sb.Append($(if ($Value) {'true'} else {'false'})); return }

    # DateTime safety net: pipeline stores dates as strings, but emit any
    # stray [datetime] in the same UTC ISO-8601 second form for stability.
    if ($Value -is [datetime]) {
        # Match the pipeline's own date formatting: ToUniversalTime().ToString('o')
        # (round-trip ISO-8601, 7-digit fractional seconds, 'Z' for UTC).
        $ic = [System.Globalization.CultureInfo]::InvariantCulture
        if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) {
            $utc = [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        } else {
            $utc = $Value.ToUniversalTime()
        }
        _CanonicalJson_WriteString -S ($utc.ToString('o', $ic)) -Sb $Sb
        return
    }
    if ($Value -is [System.DateTimeOffset]) {
        $ic = [System.Globalization.CultureInfo]::InvariantCulture
        _CanonicalJson_WriteString -S ($Value.UtcDateTime.ToString('o', $ic)) -Sb $Sb
        return
    }

    if ($Value -is [string] -or $Value -is [char]) {
        _CanonicalJson_WriteString -S ([string]$Value) -Sb $Sb; return
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or `
        $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [uint16] -or `
        $Value -is [uint32] -or $Value -is [uint64]) {
        [void]$Sb.Append([string]$Value); return
    }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        _CanonicalJson_WriteNumber -N $Value -Sb $Sb; return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if ($keys.Count -eq 0) { [void]$Sb.Append('{}'); return }
        $pairs = foreach ($k in $keys) { [pscustomobject]@{ K=[string]$k; V=$Value[$k] } }
        _CanonicalJson_WriteObject -Pairs @($pairs) -Depth $Depth -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { [void]$Sb.Append('[]'); return }
        _CanonicalJson_WriteArray -Items $items -Depth $Depth -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
        return
    }

    $props = @($Value.PSObject.Properties)
    if ($props.Count -eq 0) {
        if ($Value -is [System.Management.Automation.PSCustomObject]) { [void]$Sb.Append('{}') }
        else { _CanonicalJson_WriteString -S ([string]$Value) -Sb $Sb }
        return
    }
    $pairs = foreach ($p in $props) { [pscustomobject]@{ K=$p.Name; V=$p.Value } }
    _CanonicalJson_WriteObject -Pairs @($pairs) -Depth $Depth -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writevalue <<<
