# >>> CANONICAL unit_id=pwsh.helper.export-debugtracejson version=0.1.0 hash=4471e5482eaafc8c policy=canonical binding=follow-latest >>>
function Export-DebugTraceJson {
    <#
    .SYNOPSIS
        Write a point-in-time JSON snapshot of the current trace state.
        Use this to share a single diagnostic file (e.g. attach to a
        bug report) instead of the streaming JSONL log.
    .PARAMETER Path
        Output file path.
    .PARAMETER IncludeEvents
        If set, embed the full JSONL replay inside the export. Default
        off because it can produce multi-MB files.
    .PARAMETER Compress
        If set, single-line minified JSON. Default produces indented
        human-readable output.
    .OUTPUTS
        The output file path (for chaining).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)] [string]$Path,
        [switch]$IncludeEvents,
        [switch]$Compress
    )

    # NOTE: Pre-compute every hashtable value into a local variable so
    # no `if/else` expression appears inside [pscustomobject]@{...}; this
    # avoids an AmbiguousParameterSet failure observed on certain PS 5.1
    # ja-JP hosts. Also: instrumented with this section's own
    # Start-DebugTrace / Set-DebugStep so any future failure here
    # surfaces the failing step in the JSONL stream even if the JSON
    # export itself can't be written.
    Start-DebugTrace -Context 'Export-DebugTraceJson'
    try {
        # ------ Section A: active frames (in-progress at snapshot time) -----
        Set-DebugStep 'build activeFrames array'
        $activeFrames = @()
        foreach ($f in $Script:DebugTraceStack.ToArray()) {
            $afStartedAtUtc = $f.StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            $afElapsedMs    = [int]((Get-Date) - $f.StartTime).TotalMilliseconds
            $afSteps        = @()
            foreach ($s in $f.Steps.ToArray()) {
                $afSteps += [pscustomobject]@{
                    step   = $s.Step
                    atUtc  = $s.At.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                    detail = $s.Detail
                }
            }
            $activeFrames += [pscustomobject]@{
                context      = $f.Context
                step         = $f.Step
                phaseId      = $f.PhaseId
                depth        = $f.Depth
                startedAtUtc = $afStartedAtUtc
                elapsedMs    = $afElapsedMs
                steps        = $afSteps
            }
        }

        # ------ Section B: completed frames (history) -----------------------
        Set-DebugStep 'build completedFrames array'
        $completedFrames = @()
        foreach ($f in $Script:DebugTraceCompletedFrames.ToArray()) {
            $cfStartedAtUtc = $f.StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            $cfEndedAtUtc = $null
            if ($f.PSObject.Properties['EndedAt'] -and $f.EndedAt) {
                $cfEndedAtUtc = $f.EndedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            }
            $cfDurationMs = $null
            if ($f.PSObject.Properties['DurationMs']) {
                $cfDurationMs = $f.DurationMs
            }
            $cfSteps = @()
            foreach ($s in $f.Steps.ToArray()) {
                $cfSteps += [pscustomobject]@{
                    step   = $s.Step
                    atUtc  = $s.At.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                    detail = $s.Detail
                }
            }
            $completedFrames += [pscustomobject]@{
                context      = $f.Context
                phaseId      = $f.PhaseId
                outcome      = $f.Outcome
                depth        = $f.Depth
                startedAtUtc = $cfStartedAtUtc
                endedAtUtc   = $cfEndedAtUtc
                durationMs   = $cfDurationMs
                steps        = $cfSteps
            }
        }

        # ------ Section C: phase registry summary ---------------------------
        Set-DebugStep 'build phases array from registry'
        $phaseEntries = @()
        $sortedKeys = @($Script:DebugTracePhaseRegistry.Keys) | Sort-Object
        foreach ($key in $sortedKeys) {
            $reg = $Script:DebugTracePhaseRegistry[$key]
            $peStartedAtUtc = $null
            if ($reg.StartedAt) {
                $peStartedAtUtc = $reg.StartedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            }
            $peEndedAtUtc = $null
            if ($reg.EndedAt) {
                $peEndedAtUtc = $reg.EndedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            }
            $peFailure = $null
            if ($reg.FailureRef) {
                $peFailure = [pscustomobject]@{
                    failedStep       = $reg.FailureRef.FailedStep
                    exType           = $reg.FailureRef.ExType
                    exMessage        = $reg.FailureRef.ExMessage
                    innerType        = $reg.FailureRef.InnerType
                    innerMessage     = $reg.FailureRef.InnerMessage
                    fullyQualifiedId = $reg.FailureRef.FullyQualifiedId
                    scriptStackTrace = $reg.FailureRef.ScriptStackTrace
                }
            }
            $phaseEntries += [pscustomobject]@{
                phaseId      = $reg.PhaseId
                outcome      = $reg.Outcome
                startedAtUtc = $peStartedAtUtc
                endedAtUtc   = $peEndedAtUtc
                failure      = $peFailure
            }
        }

        # ------ Section D: optional JSONL event replay ---------------------
        Set-DebugStep 'optional: replay JSONL events'
        $events = @()
        if ($IncludeEvents -and $Script:DebugTraceJsonlPath -and (Test-Path -LiteralPath $Script:DebugTraceJsonlPath)) {
            try {
                $eventLines = Get-Content -LiteralPath $Script:DebugTraceJsonlPath -ErrorAction Stop
                foreach ($l in $eventLines) {
                    if ([string]::IsNullOrWhiteSpace($l)) { continue }
                    try {
                        $events += (ConvertFrom-Json -InputObject $l -ErrorAction Stop)
                    } catch { } # psa-disable-line PSA3004 -- skip lines that don't parse (malformed truncation)
                }
            } catch { } # psa-disable-line PSA3004 -- ignore file-read errors; events stays empty
        }
        $eventsToSerialize = @()
        $eventCount = -1
        if ($IncludeEvents) {
            $eventsToSerialize = $events
            $eventCount = $events.Count
        }

        # ------ Section E: host + script metadata (pre-computed) ------------
        Set-DebugStep 'compose host + script metadata'
        # Pre-compute the host metadata as a standalone variable so no
        # inline expression appears in the outer hashtable.
        $hostInfo = [pscustomobject]@{
            psVersion   = $PSVersionTable.PSVersion.ToString()
            psEdition   = $PSVersionTable.PSEdition
            # Dual-runtime policy (ADR 0012): $PSVersionTable.CLRVersion exists
            # only on Windows PowerShell 5.1 and is absent on PS 7 (so
            # .ToString() throws). Use [System.Environment]::Version - the
            # executing .NET runtime version, present on both runtimes - and keep
            # the field name 'clrVersion' for export-schema backward compatibility.
            clrVersion  = [System.Environment]::Version.ToString()
            os          = ([System.Environment]::OSVersion.VersionString)
            culture     = (Get-Culture).Name
            uiCulture   = (Get-UICulture).Name
            hostName    = $Host.Name
            hostVersion = $Host.Version.ToString()
        }
        $scriptStartedAtUtc = $null
        if ($Script:ScriptStartTime) {
            $scriptStartedAtUtc = $Script:ScriptStartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        $scriptInfo = [pscustomobject]@{
            version      = $Script:ScriptVersion
            tag          = $Script:ScriptTag
            sha256       = $Script:ScriptHash
            startedAtUtc = $scriptStartedAtUtc
        }
        $fileOutputStatus = Get-DebugTraceFileOutputStatus
        $exportedAtUtcVal = _DebugTrace_Now

        # ------ Section F: compose final snapshot --------------------------
        Set-DebugStep 'compose final snapshot pscustomobject'
        $snapshot = [pscustomobject]@{
            schemaVersion   = '1'
            exportedAtUtc   = $exportedAtUtcVal
            hostInfo        = $hostInfo
            script          = $scriptInfo
            fileOutput      = $fileOutputStatus
            phases          = $phaseEntries
            activeFrames    = $activeFrames
            completedFrames = $completedFrames
            events          = $eventsToSerialize
            eventCount      = $eventCount
        }

        # ------ Section G: ensure output directory exists ------------------
        Set-DebugStep 'ensure parent directory exists'
        # IMPORTANT: [System.IO.Path]::GetDirectoryName instead of
        # `Split-Path -LiteralPath $Path -Parent`. On PS 5.1, those two
        # parameters belong to mutually-exclusive parameter sets
        # (LiteralPathSet vs ParentSet), which causes
        # AmbiguousParameterSet at runtime.
        $parentDir = [System.IO.Path]::GetDirectoryName($Path)
        if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # ------ Section H: serialize and write to disk ---------------------
        Set-DebugStep 'ConvertTo-Json + write to disk'
        if ($Compress) {
            $json = $snapshot | ConvertTo-Json -Depth $Script:DebugTraceJsonDepth -Compress
        } else {
            $json = $snapshot | ConvertTo-Json -Depth $Script:DebugTraceJsonDepth
        }
        # UTF-8 with BOM so the file is correctly read on PS 5.1 ja-JP.
        [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($true))

        Set-DebugStep 'return result path'
        return $Path
    } catch {
        # Surface the failing checkpoint via the Debug Trace Facility
        # itself - this records a failure event in the JSONL stream with
        # the step name + exception details. Then re-throw so the outer
        # caller (e.g. finally block) can warn the user.
        Write-DebugFailureReport $_ -IncludeStepHistory
        throw
    } finally {
        Stop-DebugTrace
    }
}
# <<< CANONICAL unit_id=pwsh.helper.export-debugtracejson <<<
