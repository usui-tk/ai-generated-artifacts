# >>> CANONICAL unit_id=pwsh.helper.initialize-runtimedirectories version=r01 hash=30bff32f7d40fca8 policy=canonical binding=follow-latest >>>
function Initialize-RuntimeDirectories { # psa-disable-line PSA6003 -- canonical unit_id retained; noun stays plural by design
    <#
    .SYNOPSIS
        Idempotently (re-)create a set of runtime directories.
    .DESCRIPTION
        Canonical, parameterized form: the caller passes its own directory
        list (each consumer's workspace layout is its own concern); the
        idempotent create loop is the shared canonical logic. Supersedes the
        former per-tool bodies that hard-coded their own $Script: directory
        sets (reconciled at P2.2/P2.3, ADR-tracked).
    .PARAMETER Directory
        One or more directory paths to ensure exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Directory
    )
    foreach ($d in $Directory) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}
# <<< CANONICAL unit_id=pwsh.helper.initialize-runtimedirectories <<<
