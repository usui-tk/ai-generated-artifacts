# >>> CANONICAL unit_id=pwsh.helper.convertfrom-canonicaljson version=1.0.0 hash=78aca447b9e6ba71 policy=canonical binding=follow-latest >>>
function ConvertFrom-CanonicalJson {
    <#
    .SYNOPSIS
        Parse JSON text into PowerShell objects WITHOUT ConvertFrom-Json.
    .DESCRIPTION
        Hand-rolled recursive-descent parser. Returns order-preserving
        [pscustomobject] for JSON objects, [object[]] for arrays, [string]
        for strings (dates are kept as strings, NOT converted to [datetime],
        so the original textual form survives a round-trip on every PS
        version), [long]/[double] for numbers, [bool], and $null.

        Behaviour matches Python json.loads for the inputs this project
        produces, and is identical on PS 5.1 and PS 7.x.
    .PARAMETER Json
        JSON text to parse.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        [AllowEmptyString()] [string] $Json
    )
    process {
        $state = @{ s = $Json; i = 0; n = $Json.Length }
        _CanonicalJson_SkipWs $state
        $result = _CanonicalJson_ParseValue $state
        _CanonicalJson_SkipWs $state
        if ($state.i -lt $state.n) { throw "Unexpected trailing content at position $($state.i)." }
        return $result
    }
}
# <<< CANONICAL unit_id=pwsh.helper.convertfrom-canonicaljson <<<
