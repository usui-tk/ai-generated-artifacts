# >>> CANONICAL unit_id=pwsh.helper.invoke-downloadwithprogress version=1.0.0 hash=3b9d3842004a91c2 policy=canonical binding=follow-latest >>>
function Invoke-DownloadWithProgress {
    <#
    .SYNOPSIS
        Download a URL to disk while emitting periodic progress
        messages to the script's log channel (Write-Step / Write-Detail).

    .DESCRIPTION
        PS 5.1's Invoke-WebRequest has a notorious O(N^2) progress-bar
        slowdown on multi-GB downloads, so the existing
        Invoke-WebRequestWithRetry wrapper silences ProgressPreference
        for performance. The trade-off is that long downloads (a 6 GB
        ISO can take 10-15 minutes) produce no on-screen feedback for
        the full duration, which is a poor user experience.

        This function recovers visibility WITHOUT re-enabling the
        slow built-in progress bar:

          1. HEAD request first (cheap, ~1 second) to learn the
             expected Content-Length when the server reports it.
          2. Spawn a background Start-Job that runs the actual
             Invoke-WebRequest with ProgressPreference suppressed,
             so the worker still gets the fast-path streaming.
          3. From the main thread, poll the destination file size
             every -ProgressIntervalSec seconds and print:
               "  ... 1,234.5 MB / 6,852.3 MB (18.0%) at 12.3 MB/s ETA 8m 12s"
          4. On completion, print a final summary line with total
             MB, elapsed time, and average MB/s.

        Inspired by the Write-Step / Write-Detail / Set-DebugStep
        idiom in Deploy-AMDChipsetDriverOnWindowsServer.ps1
        (https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)
        but extended with the background-job + polling pattern to
        give real-time feedback rather than only start/end markers.

        Returns nothing; the file is at $OutFile on success and the
        function throws on failure (network error, HTTP error, job
        failure, or empty file).

    .PARAMETER Uri
        Source URL. Mandatory.

    .PARAMETER OutFile
        Destination file path. Mandatory. Parent directory must
        already exist; the caller is responsible for any post-
        download verification (SHA-256, atomic move, etc).

    .PARAMETER Headers
        Optional hashtable of HTTP request headers (e.g. User-Agent
        override for CDNs that reject the default PowerShell UA).

    .PARAMETER TimeoutSec
        Per-attempt HTTP timeout passed to Invoke-WebRequest.
        Default 600 (10 minutes), matching the upper bound the
        Deploy-AMDChipsetDriver reference uses.

    .PARAMETER ProgressIntervalSec
        How often to print a "still going" progress line.
        Default 5. Set to 0 to suppress progress lines and only
        emit start/end markers.

    .PARAMETER MinSizeBytes
        If set (> 0) and the downloaded file is smaller than this,
        the function deletes the file and throws. Defends against
        the CDN-returns-error-page scenario the Deploy-AMD
        reference also guards against (it expects >5 MB; ISO
        downloads should expect >100 MB or >1 GB).

    .NOTES
        Threading model: PowerShell's Start-Job creates a separate
        runspace; the worker has its own $ProgressPreference scope
        and cannot pollute the caller's. The polling loop on the
        main thread reads the *file system* (Get-Item .Length),
        not any shared state with the worker - so there is no race.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [string]$OutFile,
        [hashtable]$Headers,
        [int]$TimeoutSec = 600,
        [int]$ProgressIntervalSec = 5,
        [long]$MinSizeBytes = 0
    )

    # ---- Phase 1: probe expected size via HEAD ----
    Set-DebugStep -Step 'download-head-probe'
    $expectedBytes = $null
    $expectedMB = $null
    try {
        $headParams = @{
            Uri             = $Uri
            Method          = 'Head'
            UseBasicParsing = $true
            TimeoutSec      = 30
            ErrorAction     = 'Stop'
        }
        if ($PSBoundParameters.ContainsKey('Headers') -and $Headers) {
            $headParams['Headers'] = $Headers
        }
        $oldPp = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            $headResp = Invoke-WebRequest @headParams
        } finally {
            $ProgressPreference = $oldPp
        }
        $clen = $null
        if ($headResp.Headers.ContainsKey('Content-Length')) {
            $clen = $headResp.Headers['Content-Length']
        }
        if ($clen) {
            # Headers can be returned as string or string[] depending
            # on the PowerShell version; coerce to the first element.
            if ($clen -is [array]) { $clen = $clen[0] }
            $expectedBytes = [long]$clen
            $expectedMB = [math]::Round($expectedBytes / 1MB, 1)
        }
    } catch {
        # HEAD not supported, or server rejects HEAD (some CDNs do).
        # Continue without an expected-size estimate.
    }

    $fileName = [System.IO.Path]::GetFileName($Uri)
    if ([string]::IsNullOrEmpty($fileName)) { $fileName = '(file)' }

    Write-Step ('Downloading: {0}' -f $fileName)
    Write-Step ('  URL    : {0}' -f $Uri)
    Write-Step ('  Dest   : {0}' -f $OutFile)
    if ($expectedBytes) {
        Write-Step ('  Size   : {0:N1} MB (from Content-Length header)' -f $expectedMB)
    } else {
        Write-Step '  Size   : (unknown; server did not return Content-Length)'
    }
    Write-Step ('  Start  : {0:HH:mm:ss}' -f (Get-Date))

    # ---- Phase 2: spawn background job for the actual download ----
    Set-DebugStep -Step 'download-start-job'
    $startTime = Get-Date
    $workerScript = {
        param($u, $o, $h, $t)
        $oldPp = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            $p = @{
                Uri             = $u
                OutFile         = $o
                UseBasicParsing = $true
                TimeoutSec      = $t
                ErrorAction     = 'Stop'
            }
            if ($h) { $p['Headers'] = $h }
            Invoke-WebRequest @p | Out-Null
        } finally {
            $ProgressPreference = $oldPp
        }
    }
    $headersArg = if ($Headers) { $Headers } else { $null }
    $job = Start-Job -ScriptBlock $workerScript -ArgumentList $Uri, $OutFile, $headersArg, $TimeoutSec

    # ---- Phase 3: poll job state + file size, emit progress lines ----
    Set-DebugStep -Step 'download-progress-poll'
    $lastReportSec = 0
    $progressLines = 0
    try {
        while ($job.State -eq 'Running') {
            Start-Sleep -Milliseconds 500
            if ($ProgressIntervalSec -le 0) { continue }
            $elapsedSec = [int](New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds
            if (($elapsedSec - $lastReportSec) -lt $ProgressIntervalSec) { continue }
            $lastReportSec = $elapsedSec

            if (-not (Test-Path -LiteralPath $OutFile)) { continue }
            $curBytes = (Get-Item -LiteralPath $OutFile -ErrorAction SilentlyContinue).Length
            if (-not $curBytes) { $curBytes = 0 }
            $curMB = [math]::Round($curBytes / 1MB, 1)
            $speedMBs = if ($elapsedSec -gt 0) { [math]::Round(($curBytes / 1MB) / $elapsedSec, 1) } else { 0.0 }

            if ($expectedBytes -and $expectedBytes -gt 0) {
                $pct = [math]::Round((100.0 * $curBytes) / $expectedBytes, 1)
                $remainBytes = $expectedBytes - $curBytes
                if ($speedMBs -gt 0 -and $remainBytes -gt 0) {
                    $etaSec = [int](($remainBytes / 1MB) / $speedMBs)
                    if ($etaSec -ge 60) {
                        $etaStr = ('ETA {0}m {1:00}s' -f [int]($etaSec / 60), ($etaSec % 60))
                    } else {
                        $etaStr = ('ETA {0}s' -f $etaSec)
                    }
                } else {
                    $etaStr = 'ETA --'
                }
                Write-Step ('  ... {0:N1} MB / {1:N1} MB ({2}%) at {3} MB/s {4}' -f $curMB, $expectedMB, $pct, $speedMBs, $etaStr)
            } else {
                # No expected size: print bytes downloaded + speed only
                if ($elapsedSec -ge 60) {
                    $elapsedStr = ('{0}m {1:00}s' -f [int]($elapsedSec / 60), ($elapsedSec % 60))
                } else {
                    $elapsedStr = ('{0}s' -f $elapsedSec)
                }
                Write-Step ('  ... {0:N1} MB at {1} MB/s ({2} elapsed)' -f $curMB, $speedMBs, $elapsedStr)
            }
            $progressLines++
        }

        # ---- Phase 4: receive worker result, propagate errors ----
        Set-DebugStep -Step 'download-job-finalize'
        if ($job.State -eq 'Failed') {
            $jobErr = $null
            try {
                $null = Receive-Job -Job $job -ErrorAction Stop
            } catch {
                $jobErr = $_.Exception.Message
            }
            throw ('Download job failed for {0}: {1}' -f $Uri, $(if ($jobErr) { $jobErr } else { '(no error message)' }))
        }
        # Drain any output from the worker (should be empty -- we Out-Null'd it)
        $null = Receive-Job -Job $job -ErrorAction SilentlyContinue
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    # ---- Phase 5: post-download validation + summary line ----
    Set-DebugStep -Step 'download-postcheck'
    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw ('Download appeared to succeed but {0} does not exist' -f $OutFile)
    }
    $finalBytes = (Get-Item -LiteralPath $OutFile).Length
    $finalMB = [math]::Round($finalBytes / 1MB, 1)
    $totalSec = [int](New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds
    if ($totalSec -lt 1) { $totalSec = 1 } # avoid div-by-zero on cached/very small DLs
    $avgSpeed = [math]::Round(($finalBytes / 1MB) / $totalSec, 1)
    if ($totalSec -ge 60) {
        $totalStr = ('{0}m {1:00}s' -f [int]($totalSec / 60), ($totalSec % 60))
    } else {
        $totalStr = ('{0}s' -f $totalSec)
    }

    if ($MinSizeBytes -gt 0 -and $finalBytes -lt $MinSizeBytes) {
        $minMB = [math]::Round($MinSizeBytes / 1MB, 1)
        try { Remove-Item -LiteralPath $OutFile -Force -ErrorAction Stop } catch {
            # best-effort cleanup; the next call to this function
            # will overwrite the truncated file anyway
        } # psa-disable-line PSA3004 -- best-effort cleanup of a truncated download
        throw ('Downloaded file is only {0:N1} MB (expected >= {1:N1} MB). The CDN likely returned an error page or the connection was truncated. Try -IsoUrl with a known-good direct URL.' -f $finalMB, $minMB)
    }

    Write-Ok ('Downloaded: {0:N1} MB in {1} ({2} MB/s avg)' -f $finalMB, $totalStr, $avgSpeed)
}
# <<< CANONICAL unit_id=pwsh.helper.invoke-downloadwithprogress <<<
