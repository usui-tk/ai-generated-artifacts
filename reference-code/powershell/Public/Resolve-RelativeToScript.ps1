# >>> CANONICAL unit_id=pwsh.helper.resolve-relativetoscript version=1.0.0 hash=a5655b401eeda2b5 policy=canonical binding=follow-latest >>>
function Resolve-RelativeToScript {
    # Make a path absolute. Relative paths resolve against $Script:ScriptRoot.
    param([Parameter(Mandatory)] [string]$Path)
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $Script:ScriptRoot $Path
    }
    return [System.IO.Path]::GetFullPath($Path)
}
# <<< CANONICAL unit_id=pwsh.helper.resolve-relativetoscript <<<
