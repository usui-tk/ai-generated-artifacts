# >>> CANONICAL unit_id=pwsh.helper.invoke-webrequestwithretry version=1.0.0 hash=959c46975eb04b15 policy=canonical binding=follow-latest >>>
function Invoke-WebRequestWithRetry {
    <#
    .SYNOPSIS
        Wrapper around Invoke-WebRequest with exponential-backoff retry.

    .DESCRIPTION
        Two modes:

          1) In-memory fetch (no -OutFile)
             Returns the BasicHtmlWebResponseObject. Used for HTML/JSON
             scraping (Microsoft Learn release-info, .NET CU index, etc).

          2) File download (-OutFile <path>)
             Delegates to Invoke-DownloadWithProgress, which uses a
             background Start-Job + main-thread file-size polling to
             give the user "X MB / Y MB at Z MB/s ETA Ns" progress
             lines every few seconds. The underlying Invoke-WebRequest
             still runs with ProgressPreference='SilentlyContinue' to
             avoid PS 5.1's O(N^2) progress-bar slowdown on multi-GB
             downloads.

        Retries on transient errors (network + HTTP 429/503) with
        exponential backoff; bails on the final attempt with the
        captured exception. The -MaxAttempts alias is preserved for
        backward compatibility with existing call sites.

    .PARAMETER Uri
        Source URL. Mandatory.

    .PARAMETER OutFile
        When provided, the response body is saved to this path via
        Invoke-DownloadWithProgress. The caller is responsible for
        any post-download verification (SHA-256, atomic move, etc).

    .PARAMETER Headers
        Optional hashtable of HTTP request headers (e.g. custom
        User-Agent). When not provided, Invoke-WebRequest's default
        headers are used.

    .PARAMETER MaxRetries
        Maximum number of attempts before giving up. Default 3. The
        -MaxAttempts alias is honoured for callers that used the
        original parameter name.

    .PARAMETER TimeoutSec
        Per-attempt HTTP timeout. Default 60 for in-memory fetches.
        For -OutFile downloads, this is passed through to
        Invoke-DownloadWithProgress (which uses 600 by default
        internally; the explicit value here wins).
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject])]
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [string]$OutFile,
        [hashtable]$Headers,
        [Alias('MaxAttempts')]
        [int]$MaxRetries = 3,
        [int]$TimeoutSec = 60
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            if ($PSBoundParameters.ContainsKey('OutFile') -and $OutFile) {
                # Delegate to the progress-aware helper. We give it
                # the larger of TimeoutSec (the caller's value) and
                # 600 seconds, because in-memory fetch timeouts are
                # typically small (60s) but a multi-GB ISO can take
                # 15+ minutes - whichever the caller specified, we
                # honour it but never go below 600 for large DLs.
                $effectiveTimeout = [Math]::Max($TimeoutSec, 600)
                $progressParams = @{
                    Uri        = $Uri
                    OutFile    = $OutFile
                    TimeoutSec = $effectiveTimeout
                }
                if ($PSBoundParameters.ContainsKey('Headers') -and $Headers) {
                    $progressParams['Headers'] = $Headers
                }
                Invoke-DownloadWithProgress @progressParams
                return
            }

            # In-memory fetch path: keep using Invoke-WebRequest directly.
            # No progress bar concerns since the payload is small (HTML/JSON).
            $params = @{
                Uri             = $Uri
                TimeoutSec      = $TimeoutSec
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }
            if ($PSBoundParameters.ContainsKey('Headers') -and $Headers) {
                $params['Headers'] = $Headers
            }
            $response = Invoke-WebRequest @params
            return $response
        }
        catch {
            $lastError = $_
            $statusCode = $null
            try { if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode } } catch { } # psa-disable-line PSA3004 -- status code is diagnostic only; the retry loop uses $lastError to decide control flow

            if ($statusCode -eq 429 -or $statusCode -eq 503) {
                $wait = [Math]::Pow(2, $attempt) * 3
                Write-Caution "HTTP $statusCode received. Waiting $wait sec then retry ($attempt/$MaxRetries)"
                Start-Sleep -Seconds $wait
            }
            elseif ($attempt -lt $MaxRetries) {
                $wait = [Math]::Pow(2, $attempt)
                Write-Caution "Network error: $($_.Exception.Message). Retrying in $wait sec ($attempt/$MaxRetries)"
                Start-Sleep -Seconds $wait
            }
        }
    }
    throw $lastError
}
# <<< CANONICAL unit_id=pwsh.helper.invoke-webrequestwithretry <<<
