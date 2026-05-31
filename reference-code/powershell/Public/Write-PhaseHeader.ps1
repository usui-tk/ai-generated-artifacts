# >>> CANONICAL unit_id=pwsh.helper.write-phaseheader version=0.1.0 hash=a002b1883e7d48ba policy=canonical binding=follow-latest >>>
function Write-PhaseHeader {
    # Prints a magenta banner that opens a phase. Records phase start
    # time so subsequent log lines can show '[+elapsed]'.
    #
        #   Id    : short identifier (e.g. 'P01', 'P08', etc; always two digits)
    #   Name  : human-readable phase name (e.g. 'Listing-Collection')
    #   Group : phase group (e.g. 'Setup', 'Scan', 'Fetch', 'Report')
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Group
    )
    $Script:CurrentPhaseStart = Get-Date
    $Script:CurrentPhaseId    = $Id
    $startStr = $Script:CurrentPhaseStart.ToString('HH:mm:ss')
    $line = '=' * 72
    Write-Host ''
    Write-Host $line -ForegroundColor Magenta
    Write-Host (' PHASE {0,-4} - {1,-22} ({2,-7}) start: {3}' -f $Id, $Name, $Group, $startStr) -ForegroundColor Magenta
    Write-Host (' script: {0}' -f $Script:ScriptShortTag) -ForegroundColor DarkGray
    Write-Host $line -ForegroundColor Magenta
}
# <<< CANONICAL unit_id=pwsh.helper.write-phaseheader <<<
