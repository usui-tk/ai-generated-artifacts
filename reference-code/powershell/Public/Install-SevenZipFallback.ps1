# >>> CANONICAL unit_id=pwsh.helper.install-sevenzipfallback version=1.0.0 hash=a66ae5d392104ab5 policy=canonical binding=follow-latest >>>
function Install-SevenZipFallback {
    param([string]$DownloadDir)
    $info = Get-LatestSevenZipUrl
    Write-Detail "Version : $($info.Version)"
    Write-Detail "Source  : $($info.Source)"
    Write-Detail "URL     : $($info.MsiUrl)"
    $msi = Join-Path $DownloadDir (Split-Path $info.MsiUrl -Leaf)
    if (-not (Test-Path $msi)) {
        Invoke-WebRequest -Uri $info.MsiUrl -OutFile $msi -UseBasicParsing
    }
    $proc = Start-Process msiexec.exe -ArgumentList @('/i',"`"$msi`"",'/qn','/norestart') -Wait -PassThru # psa-disable-line PSA3001 -- Start-Process -ArgumentList is the canonical pattern for invoking msiexec with explicit args
    if ($proc.ExitCode -ne 0) { throw "7-Zip MSI install failed (exit $($proc.ExitCode))" }
}
# <<< CANONICAL unit_id=pwsh.helper.install-sevenzipfallback <<<
