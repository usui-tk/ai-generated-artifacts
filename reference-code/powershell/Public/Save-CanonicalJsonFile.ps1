# >>> CANONICAL unit_id=pwsh.helper.save-canonicaljsonfile version=r01 hash=8cac0388cc0b5da0 policy=canonical binding=follow-latest >>>
function Save-CanonicalJsonFile {
    <#
    .SYNOPSIS
        Write an object to a file as canonical JSON (SPEC Part B.23).
    .DESCRIPTION
        Wraps ConvertTo-CanonicalJson and writes the result to disk as
        UTF-8 (no BOM) with raw byte semantics (no platform newline
        translation). Writes to <Path>.tmp first then renames over
        <Path> for atomic-ish replacement.

        The byte sequence on disk matches what
        save_canonical_json_file() in tests/common/canonical_json.py
        produces for the same logical input.
    .PARAMETER InputObject
        Object to serialize.
    .PARAMETER Path
        Destination file path. Existing files are overwritten.
    .PARAMETER Depth
        See ConvertTo-CanonicalJson.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)] $InputObject,
        [Parameter(Mandatory, Position=1)] [string] $Path,
        [Parameter()] [int] $Depth = 20
    )

    $json = ConvertTo-CanonicalJson -InputObject $InputObject -Depth $Depth

    # UTF-8 without BOM (rule 1), raw bytes so the LFs (rule 2) survive
    # without being translated to CRLF on Windows.
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $tmpPath = $Path + '.tmp'
    [System.IO.File]::WriteAllBytes($tmpPath, $utf8NoBom.GetBytes($json))
    Move-Item -LiteralPath $tmpPath -Destination $Path -Force
}
# <<< CANONICAL unit_id=pwsh.helper.save-canonicaljsonfile <<<
