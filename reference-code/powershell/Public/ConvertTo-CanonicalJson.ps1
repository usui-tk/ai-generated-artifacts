# >>> CANONICAL unit_id=pwsh.helper.convertto-canonicaljson version=1.0.0 hash=97b75b019e00fc8f policy=canonical binding=follow-latest >>>
function ConvertTo-CanonicalJson {
    <#
    .SYNOPSIS
        Serialize an object to canonical JSON text (SPEC Part B.23), with
        byte output identical on PS 5.1 / 7.x / Python.
    .DESCRIPTION
        Hand-rolled serializer that does NOT call ConvertTo-Json, so the
        emitted bytes are independent of the PowerShell version's
        ConvertTo-Json formatting. Returns a string whose bytes match
        canonical_json_dumps() in tests/common/canonical_json.py for the
        same logical input.

        Accepted input: [ordered] hashtable, [pscustomobject], plain
        [hashtable] (key order then follows enumeration order; prefer
        ordered/pscustomobject for determinism), arrays, and the JSON
        primitives (string, integer, double, bool, $null). [datetime] /
        [datetimeoffset] values are emitted as UTC second-precision ISO-8601
        strings (yyyy-MM-ddTHH:mm:ssZ) as a safety net; the data pipeline
        itself stores dates as strings.
    .PARAMETER InputObject
        Object to serialize.
    .PARAMETER Depth
        Maximum nesting depth (default 20). Matches the Python -Depth.
    .PARAMETER IndentWidth
        Spaces per indent level (default 2).
    .PARAMETER NoTrailingNewline
        When set, the returned string ends without a final LF.
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position=0)] [AllowNull()] $InputObject,
        [Parameter()] [int] $Depth = 20,
        [Parameter()] [int] $IndentWidth = 2,
        [Parameter()] [switch] $NoTrailingNewline
    )
    if ($Depth -lt 1)       { throw "depth must be >= 1, got $Depth" }
    if ($IndentWidth -lt 1) { throw "indent_width must be >= 1, got $IndentWidth" }

    $sb = [System.Text.StringBuilder]::new()
    $indentUnit = ' ' * $IndentWidth
    _CanonicalJson_WriteValue -Value $InputObject -Depth 0 -MaxDepth $Depth -IndentUnit $indentUnit -Sb $sb
    $json = $sb.ToString()
    if (-not $NoTrailingNewline) { $json += "`n" }
    return $json
}
# <<< CANONICAL unit_id=pwsh.helper.convertto-canonicaljson <<<
