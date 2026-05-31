# >>> CANONICAL unit_id=pwsh.helper.add-errorjsonlentry version=0.1.0 hash=cecbc2af5da9ce31 policy=canonical binding=follow-latest >>>
function Add-ErrorJsonlEntry {
    <#
    .SYNOPSIS
        Append one structured JSON-Lines record to the run-level errors
        log at $Script:ErrorsJsonlPath.
    .PARAMETER Phase
        Phase identifier (e.g. 'P03', 'P07'). Required.
    .PARAMETER Kind
        Short category label for the entry (e.g. 'failure', 'warning').
        Required.
    .PARAMETER Properties
        Free-form hashtable merged into the JSON object. Keys colliding
        with the well-known fields (timestamp / scriptVersion / phase /
        kind) are silently dropped to protect the reserved schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Phase,
        [Parameter(Mandatory)] [string]$Kind,
        [hashtable]$Properties = @{}
    )

    if ([string]::IsNullOrEmpty($Script:ErrorsJsonlPath)) { return }

    try {
        $obj = [ordered]@{
            timestamp     = (Get-Date).ToString('o')
            scriptVersion = $Script:ScriptShortTag
            phase         = $Phase
            kind          = $Kind
        }
        if ($Properties) {
            foreach ($key in $Properties.Keys) {
                # Reserved keys cannot be overridden
                if ($obj.Contains($key)) { continue }
                $obj[$key] = $Properties[$key]
            }
        }
        $json = $obj | ConvertTo-Json -Compress -Depth 8
        Add-Content -Path $Script:ErrorsJsonlPath -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Logging is best-effort: swallow so the main flow is not disrupted
        $null = $_
    }
}
# <<< CANONICAL unit_id=pwsh.helper.add-errorjsonlentry <<<
