# >>> CANONICAL unit_id=pwsh.helper.set-utf8pipelineencoding version=1.0.0 hash=16192049ae7363e8 policy=canonical binding=follow-latest >>>
function Set-Utf8PipelineEncoding {
    <#
    .SYNOPSIS
        Force UTF-8 for console input, output, and pipeline encoding.
    .DESCRIPTION
        On a ja-JP Windows PowerShell 5.1 host, the default console code
        page is cp932 (Shift-JIS). When external tools that write UTF-8
        to stdout are captured via "& tool | Out-String", PS decodes the
        bytes using [Console]::OutputEncoding; if that is cp932 and the
        tool wrote UTF-8, every multibyte character is mojibaked. Set
        all three encodings (Console.OutputEncoding, Console.InputEncoding,
        $OutputEncoding) to UTF-8 for consistent round-trip behaviour.

        Wrapped in try/catch because some pinned-redirected console
        hosts (e.g. CI runners writing to a file with no real console)
        may throw on the assignment; in that case the original encoding
        is preserved and we continue without UTF-8 enforcement.
    #>
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { } # psa-disable-line PSA3004 -- best-effort host config; no real console may exist
    try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch { } # psa-disable-line PSA3004 -- best-effort host config; no real console may exist
    try { Set-Variable -Name OutputEncoding -Scope Global -Value ([System.Text.Encoding]::UTF8) -ErrorAction SilentlyContinue } catch { } # psa-disable-line PSA3004 -- intentional best-effort cleanup; no error to surface
}
# <<< CANONICAL unit_id=pwsh.helper.set-utf8pipelineencoding <<<
