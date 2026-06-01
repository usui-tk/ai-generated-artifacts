# CanonSessionState.ps1 - shared test fixture (NOT a canonical/vendored unit).
#
# Reproduces the $Script: session-state initialisation that a CONSUMER script
# performs OUTSIDE the canon helper bodies, before invoking them (ADR 0010).
# The canon helpers (Start-DebugTrace, Write-PhaseHeader, the JSONL trace
# writers, the phase-summary helpers, ...) are vendored into a consumer that
# owns and initialises this state in its own init block; the helpers read it by
# design. Keeping this init in a test fixture - rather than adding it to the
# canon functions - mirrors the real usage model: the canon stays a pure set of
# caller-state-consuming helpers, and the driver supplies the preconditions.
# Source of truth for the values: the consumer
#   scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1.
Set-StrictMode -Version Latest

function Initialize-CanonSessionState {
    [CmdletBinding()]
    param(
        [string]$Module = 'powershell',
        [string]$ScriptRoot = $PSScriptRoot,
        [string]$ScriptTag = 'canon-test',
        [string]$ScriptVersion = '0.0.0-test',
        [string]$ScriptHash = 'testhash'
    )
    & (Get-Module $Module) {
        param($ScriptRoot, $ScriptTag, $ScriptVersion, $ScriptHash)

        # --- Debug-trace core collections (consumer init block) ---
        $Script:DebugTraceStack           = New-Object 'System.Collections.Generic.Stack[object]'
        $Script:DebugTraceCompletedFrames = New-Object 'System.Collections.Generic.List[object]'
        $Script:DebugTraceCompletedCap    = 1024
        $Script:DebugTraceHistoryCap      = 256
        $Script:DebugTraceJsonlLineCap    = 8192
        $Script:DebugTraceJsonDepth       = 100
        $Script:DebugTraceJsonlEnabled    = $false
        $Script:DebugTraceJsonlPath       = $null
        $Script:DebugTraceJsonlBuffer     = New-Object 'System.Collections.Generic.List[string]'
        $Script:DebugTraceJsonlBufferCap  = 4096
        $Script:DebugTraceJsonlWriteCount = 0
        $Script:DebugTraceJsonlErrorCount = 0
        $Script:DebugTraceJsonlLastError  = $null
        $Script:DebugTracePhaseRegistry   = @{}
        $Script:DebugTraceEventSeq        = 0
        $Script:DebugTraceAutoExportEnabled = $false
        $Script:DebugTraceAutoExportDir     = $null

        # --- Phase / run timing (consumer init block) ---
        $Script:CurrentPhaseStart = $null
        $Script:CurrentPhaseId    = $null
        $Script:PhaseTimings      = New-Object 'System.Collections.Generic.List[object]'
        $Script:ScriptStartTime   = Get-Date

        # --- Script identity (consumer init block) ---
        $Script:ScriptRoot     = $ScriptRoot
        $Script:ScriptTag      = $ScriptTag
        $Script:ScriptVersion  = $ScriptVersion
        $Script:ScriptHash     = $ScriptHash
        $Script:ScriptShortTag = ('{0}/{1}' -f $ScriptVersion, $ScriptHash)
    } $ScriptRoot $ScriptTag $ScriptVersion $ScriptHash
}
