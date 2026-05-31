# >>> CANONICAL unit_id=pwsh.helper.get-sevenzippath version=0.1.0 hash=a3901d3b12779526 policy=canonical binding=follow-latest >>>
function Get-SevenZipPath {
    foreach ($p in @("${env:ProgramFiles}\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # Non-Windows / PATH fallbacks: the Linux p7zip binaries (7z, 7za) used by
    # the offline CI and the test harness. The Windows path is tried first so
    # this never changes behaviour on Windows.
    foreach ($name in @('7z','7za')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}
# <<< CANONICAL unit_id=pwsh.helper.get-sevenzippath <<<
