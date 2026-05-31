# >>> CANONICAL unit_id=pwsh.helper.get-latestsevenzipurl version=0.1.0 hash=973f44b6539008d4 policy=canonical binding=follow-latest >>>
function Get-LatestSevenZipUrl {
    # Tier 1: 7-zip.org
    try {
        $resp = Invoke-WebRequest -Uri 'https://www.7-zip.org/download.html' -UseBasicParsing -TimeoutSec 30
        $verMatch = [regex]::Match($resp.Content, 'Download 7-Zip\s+(\d+\.\d+)')
        $msiHits  = [regex]::Matches($resp.Content, 'https?://[^\s"''<>)]+?/7z\d+-x64\.msi')
        if ($msiHits.Count -gt 0) {
            return [pscustomobject]@{
                Version = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { $null }
                MsiUrl  = $msiHits[0].Value
                Source  = '7-zip.org (parsed)'
            }
        }
    } catch { Write-Caution "7-zip.org parse failed: $($_.Exception.Message)" }

    # Tier 2: GitHub API
    try {
        $headers = @{ 'User-Agent' = 'PowerShell-Update-WindowsServerIso'; 'Accept' = 'application/vnd.github+json' }
        $api = Invoke-RestMethod -Uri 'https://api.github.com/repos/ip7z/7zip/releases/latest' -Headers $headers -TimeoutSec 30
        $msi = $api.assets | Where-Object { $_.name -match '^7z\d+-x64\.msi$' } | Select-Object -First 1
        if ($msi) {
            return [pscustomobject]@{ Version=$api.tag_name; MsiUrl=$msi.browser_download_url; Source='GitHub Releases API' }
        }
    } catch { Write-Caution "GitHub Releases API failed: $($_.Exception.Message)" }

    # Tier 3: pinned
    Write-Caution 'Both online lookups failed - using pinned URL.'
    return [pscustomobject]@{
        Version='26.01 (pinned)'
        MsiUrl='https://github.com/ip7z/7zip/releases/download/26.01/7z2601-x64.msi'
        Source='pinned fallback'
    }
}
# <<< CANONICAL unit_id=pwsh.helper.get-latestsevenzipurl <<<
