# >>> CANONICAL unit_id=pwsh.helper.write-subsection version=r01 hash=524c6903ce0d76ea policy=canonical binding=follow-latest >>>
function Write-SubSection {
    # Lightweight section break inside a phase (e.g. [Step A]/[Step B]).
    # Prints with a leading blank line and a horizontal rule.
    param([string]$Title)
    Write-Host ''
    Write-Host (' -- ' + $Title + ' ' + ('-' * [Math]::Max(1, 60 - $Title.Length))) -ForegroundColor Gray
}
# <<< CANONICAL unit_id=pwsh.helper.write-subsection <<<
