<#
.SYNOPSIS
    Bulk-download all public decks from a specified Speaker Deck account.

.DESCRIPTION
    Downloads every published slide deck (PDF, or other formats when offered)
    from a Speaker Deck account.

    Repository: https://github.com/usui-tk/ai-generated-artifacts
    Location  : scripts/powershell/download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1
    License   : MIT (see LICENSE at the repository root)

    Prerequisites:
      - Windows PowerShell 5.1+ (also runs on PowerShell 7+)
      - 64-bit process (forcibly checked in Phase 1)
      - Windows 10/11 or Windows Server 2016+
      - Internet access to speakerdeck.com and files.speakerdeck.com
      - TLS 1.2 capable runtime (the script forces TLS 1.2)
      - Optional: registry "LongPathsEnabled" = 1 for paths > 260 chars
      - Optional: python3 + scripts/python/powershell-static-analyzer/psa.py
        (v3.3.0, 36-rule check set PSA1001..PSA9002 plus opt-in
        PSAP0001..PSAP0004) for static analysis

    Known limitations:
      - Speaker Deck only (not designed for SlideShare or other sites)
      - HTML parsing depends on Speaker Deck's current page structure;
        if Speaker Deck restructures their HTML, Phase 2/3/4 may need updates
      - PDF metadata reclassification (Phase 8) uses regex-based parsing
        and may not recover dates from heavily-customized or encrypted PDFs
      - Maximum filename / full-path length is constrained by Windows;
        Phase 1 measures the effective limit in the current environment
      - Re-run idempotency depends on work/logs/year_overrides.csv;
        deleting it resets Phase 8 rescue history

    AI tool: Generated and iteratively refined with Anthropic Claude
            (Sonnet 4.5 / Opus 4.6 era; latest revision r20 on 2026-05-13).

.DESCRIPTION_PHASES
    Phases:
      Phase 1 : Environment evaluation
                (registry check + real-world dummy file creation tests
                 to determine effective filename / full-path limits)
      Phase 2 : Get total deck count from the profile page
      Phase 3 : Listing collection (collect (URL, title) pairs from all pages)
      Phase 4 : Per-deck evaluation (check whether a download URL is exposed)
      Phase 5 : Filename plan
                (pre-compute every output filename + full path, save as
                 P05_filename_plan.csv, detect duplicates and path-limit
                 violations BEFORE any download starts)
      Phase 6 : Adaptive parallel download
                (Runspace Pool, initial 3 / max 5, auto-throttle on 429/503)
      Phase 7 : Reconciliation
                (join plan + download log + disk inventory, save
                 P07_final_state.csv with per-deck Discrepancy flags)
      Phase 8 : PDF-metadata reclassification
                (for any file that landed in _undated/, read its PDF
                 metadata and, if a valid year is found, move it to
                 the corresponding year folder; persist the decision
                 in work/logs/year_overrides.csv for re-run idempotency)
      Phase 9 : Final summary report

    Output filenames use the published title as a prefix.
    When system limits are tight, the script falls back to a shorter
    "<title>_<YYYYMMDD>.<ext>" form.

.PARAMETER Account
    Speaker Deck account name. Default: oracle4engineer

.PARAMETER OutputDir
    Output directory for downloaded decks. Relative paths are resolved
    against the directory containing this script (NOT the current working
    directory), so the output always lands next to the .ps1 file no matter
    where it is invoked from. Default: .\downloads

.PARAMETER WorkDir
    Working directory for diagnostic dumps, temporary files, etc.
    Like OutputDir, relative paths are resolved against the script's
    directory. Default: .\work

.PARAMETER DelaySeconds
    Base wait time between requests, in seconds. Default: 1.0

.PARAMETER JitterSeconds
    Random jitter range added/subtracted from DelaySeconds. Default: 0.3

.PARAMETER MaxConcurrency
    Hard cap for parallel downloads. Default: 5

.PARAMETER InitialConcurrency
    Initial parallel download count. Default: 3

.PARAMETER MinConcurrency
    Floor for parallel downloads (used when throttling). Default: 1

.PARAMETER MaxRetries
    Max retries per download on failure. Default: 3

.PARAMETER Force
    Overwrite existing files. Without this switch, files larger than 1 KB are skipped.

.PARAMETER DryRun
    Run Phase 1 through Phase 5 fully (including the filename plan
    output), explicitly mark Phase 6 (Download) and Phase 7
    (Reconciliation) as SKIPPED, and emit the Phase 9 final report.
    No PDFs are actually downloaded.

.PARAMETER SkipEnvCheck
    Skip Phase 1 and use safe-default thresholds.

.PARAMETER Clean
    Delete the OutputDir and WorkDir trees before running. Used to start
    completely fresh - removes downloaded decks, CSV logs, JSONL error
    logs and diagnostic dumps from previous runs. The script then runs
    normally with the directories recreated empty.

    Safety: refuses to operate if either path equals the script's own
    directory, equals a drive root, or contains the script.

.PARAMETER CleanOnly
    Same deletion behaviour as -Clean, but exits after the cleanup
    instead of running the phases. Useful for tearing down without
    immediately re-downloading.

.PARAMETER FlatLayout
    Save all PDFs directly into OutputDir without year-based subfolders.
    By default (year-folder mode), Phase 5 derives a 4-digit year for
    each deck and writes files into OutputDir\<YYYY>\<filename>. This
    helps users quickly spot stale content as cloud services evolve.

    Year derivation priority (highest first):
      1. YYYYMMDD pattern in OriginalFilename (deck author's intent)
      2. PublishDate from og:meta (Speaker Deck upload date)
      3. Japanese year-suffix pattern in Title (YYYY + year-kanji U+5E74)
      4. Bare 4-digit year (20YY) in Title
      5. Fallback: "_undated" folder

    Year is considered valid only when in range [2010, currentYear + 1].

.EXAMPLE
    .\Download-SpeakerDeck.ps1
    Download all public decks of oracle4engineer to .\downloads, organized
    into year subfolders (default behaviour).

.EXAMPLE
    .\Download-SpeakerDeck.ps1 -FlatLayout
    Download all decks into one flat directory (no year subfolders).

.EXAMPLE
    .\Download-SpeakerDeck.ps1 -DryRun
    Evaluate only; no files are downloaded.

.EXAMPLE
    .\Download-SpeakerDeck.ps1 -Clean
    Wipe previous outputs and logs, then run a full fresh download.

.EXAMPLE
    .\Download-SpeakerDeck.ps1 -CleanOnly
    Just remove previous outputs and logs, then exit.

.EXAMPLE
    .\Download-SpeakerDeck.ps1 -OutputDir "D:\SpeakerDeck" -MaxConcurrency 8
    Use a different output directory and a higher concurrency cap.
#>

[CmdletBinding()]
param(
    [string]$Account            = "oracle4engineer",
    [string]$OutputDir          = ".\downloads",
    [string]$WorkDir            = ".\work",
    [double]$DelaySeconds       = 1.0,
    [double]$JitterSeconds      = 0.3,
    [int]   $MaxConcurrency     = 5,
    [int]   $InitialConcurrency = 3,
    [int]   $MinConcurrency     = 1,
    [int]   $MaxRetries         = 3,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$SkipEnvCheck,
    [switch]$Clean,
    [switch]$CleanOnly,
    [switch]$FlatLayout,
    [switch]$SkipPdfReclassification
)

# Parameter validation: Clean and CleanOnly are mutually exclusive.
# They both mean "wipe everything first"; combining them is ambiguous
# (does the user want to wipe-and-run or wipe-and-exit?), so we reject
# the combination early with a clear message.
if ($Clean -and $CleanOnly) {
    throw "-Clean and -CleanOnly cannot be used together. Pick one."
}

# ============================================================
# Initial setup
# ============================================================

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Reusable host-configuration helpers (Set-ConsoleUtf8 / Set-Tls12)
# ------------------------------------------------------------
# These helpers were extracted from the original inline try-blocks to
# match the convention used by the sister scripts in
# usui-tk/Deploy-Drivers-For-WindowsServer. Each helper is best-effort:
# any failure is swallowed (the empty catch carries an inline
# psa-disable-line comment with a justification) because non-elevated /
# restricted hosts may not allow the assignment, and the script body
# can continue without the optimisation.

function Set-ConsoleUtf8 {
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

function Set-Tls12 {
    <#
    .SYNOPSIS
        Enable TLS 1.2 (and weaker fallbacks) for outbound HTTPS calls.
    .DESCRIPTION
        Required on some Windows PowerShell 5.1 hosts where the default
        SecurityProtocol is still Ssl3 + Tls (1.0). Speaker Deck and
        files.speakerdeck.com both negotiate TLS 1.2+, so the default
        on older hosts results in a handshake failure unless this is
        set. Tls11 and Tls (1.0) are kept in the bitmask as a
        defensive fallback for very old environments; modern hosts
        will negotiate Tls12.
    #>
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls
    } catch { } # psa-disable-line PSA3004 -- older PS hosts may lack newer enum values; ignore silently
}

# Apply host configuration immediately so every subsequent write goes
# through the right encoding and every HTTPS call uses TLS 1.2.
Set-ConsoleUtf8
Set-Tls12

# Load System.Web for HtmlDecode
try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch { } # psa-disable-line PSA3004 -- already uses -ErrorAction SilentlyContinue; catch is a defensive net

# Constants
$Script:BaseUrl   = "https://speakerdeck.com"
$Script:UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

# Browser-like request headers. Without these, some sites (or fronting CDNs)
# treat the request as coming from a bot and return a stripped-down HTML.
# Speaker Deck's profile pages return the deck count badge but NOT the deck
# listing if these headers are missing, which is exactly what we observed.
#
# Notes:
#   - 'User-Agent' itself cannot be set via -Headers in Windows PowerShell 5.1;
#     it must be set via the -UserAgent parameter (handled separately below).
#   - Accept-Encoding is intentionally limited to gzip/deflate; brotli ('br')
#     would be sent in a real browser, but PowerShell 5.1 cannot decompress it.
#   - The Sec-Ch-Ua-* values mirror Chrome 131 to stay self-consistent with
#     the User-Agent string.
$Script:RequestHeaders = @{
    'Accept'                    = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
    'Accept-Language'           = 'en-US,en;q=0.9,ja;q=0.8'
    'Accept-Encoding'           = 'gzip, deflate'
    'Cache-Control'             = 'no-cache'
    'Pragma'                    = 'no-cache'
    'Sec-Ch-Ua'                 = '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"'
    'Sec-Ch-Ua-Mobile'          = '?0'
    'Sec-Ch-Ua-Platform'        = '"Windows"'
    'Sec-Fetch-Dest'            = 'document'
    'Sec-Fetch-Mode'            = 'navigate'
    'Sec-Fetch-Site'            = 'none'
    'Sec-Fetch-User'            = '?1'
    'Upgrade-Insecure-Requests' = '1'
    'DNT'                       = '1'
}

# Promote params to script scope so functions can reach them safely
$Script:DelaySeconds  = $DelaySeconds
$Script:JitterSeconds = $JitterSeconds

# ============================================================
# Path resolution (relative to the script, not the caller's CWD)
# ============================================================
# By default, OutputDir = '.\downloads' and WorkDir = '.\work'.
# We resolve them against $PSScriptRoot (the directory containing this
# .ps1 file), NOT against the caller's current working directory. This
# guarantees that:
#   - Running '.\Download-SpeakerDeck.ps1' from any folder always writes
#     to the same place (next to the script).
#   - Both the download tree and the working tree live under one root,
#     making the script's footprint easy to clean up.
# An absolute path passed to either parameter is honoured as-is.

# $PSScriptRoot is null when the script is dot-sourced or invoked in
# certain unusual ways (e.g. piped from stdin). Fall back to MyInvocation
# in that case, and finally to CWD as a last resort.
$Script:ScriptRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($Script:ScriptRoot)) {
    if ($MyInvocation.MyCommand.Path) {
        $Script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
}
if ([string]::IsNullOrEmpty($Script:ScriptRoot)) {
    $Script:ScriptRoot = (Get-Location).Path
}

function Resolve-RelativeToScript {
    # Make a path absolute. Relative paths resolve against $Script:ScriptRoot.
    param([Parameter(Mandatory)] [string]$Path)
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $Script:ScriptRoot $Path
    }
    return [System.IO.Path]::GetFullPath($Path)
}

$OutputDir = Resolve-RelativeToScript -Path $OutputDir
$WorkDir   = Resolve-RelativeToScript -Path $WorkDir

# Sub-directories that live under WorkDir.
# Created later (after optional -Clean wipe), so do NOT call Test-Path
# / New-Item here. Just compute the paths so functions can reference
# them.
$Script:OutputDir       = $OutputDir
$Script:WorkDir         = $WorkDir
$Script:DiagDir         = Join-Path $WorkDir 'diag'
$Script:FailedDir       = Join-Path $Script:DiagDir 'failed'
$Script:LogsDir         = Join-Path $WorkDir 'logs'
$Script:ErrorsJsonlPath = Join-Path $Script:LogsDir 'P06_errors.jsonl'

function Initialize-RuntimeDirectories {
    # Idempotently (re-)create the directory tree the script needs.
    # Called once during startup, after any optional -Clean wipe.
    # FailedDir is created lazily on first failure (most runs have 0
    # failures, and we don't want an empty 'failed' folder cluttering
    # the workspace).
    foreach ($d in @($Script:OutputDir, $Script:WorkDir, $Script:DiagDir, $Script:LogsDir)) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}

# ============================================================
# Script version identification
# ============================================================
# These constants are bumped manually whenever the script is edited.
# They are displayed in the startup banner and in each phase header
# so the user can verify which revision is running.
#
#   ScriptVersion : bump on every meaningful edit. Format: YYYY.MM.DD-rNN
#   ScriptTag     : short human-readable label describing the build
#   ScriptHash    : auto-computed SHA256 (first 12 chars) of the actual
#                   file being executed. Changes for any byte-level edit;
#                   does NOT need manual bumping.
$Script:ScriptVersion = 'speakerdeck-2026.05.18-r23'
$Script:ScriptTag     = 'debugtrace-facility-and-pdfmeta-poc-removal'
$Script:ScriptHash    = '(unknown)'
try {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptPath)) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }
    if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
        $hashFull = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $Script:ScriptHash = $hashFull.Substring(0, 12).ToLower()
    }
} catch {
    $Script:ScriptHash = '(hash-error)'
}
$Script:ScriptShortTag = ('v{0}/{1}' -f $Script:ScriptVersion, $Script:ScriptHash)

# ============================================================
# Timing state
# ============================================================
# Captured at script load time. Used by Write-PhaseHeader to mark
# per-phase start, by Write-PhaseFooter to compute per-phase elapsed
# time, and by Show-PhaseSummary at the end of the run.
$Script:ScriptStartTime   = Get-Date
$Script:CurrentPhaseStart = $null
$Script:CurrentPhaseId    = $null
$Script:PhaseTimings      = New-Object System.Collections.Generic.List[object]

# ============================================================
# Year-overrides state (populated by Initialize-YearOverrides in
# Phase 5, consulted by Get-DeckYear, mutated by Add-YearOverride
# in Phase 8). Initialized empty here so the variable exists in
# script scope from the start, including for runs where Phase 5
# is the first function to touch it.
# ============================================================
$Script:YearOverrides = @{}

# ============================================================
# SECTION 1b: Debug Trace Facility
# ============================================================
# A reusable diagnostic helper, ported from the
# usui-tk/Deploy-Drivers-For-WindowsServer reference scripts
# (Deploy-AMDChipsetDriverOnWindowsServer.ps1 r60 and
# Deploy-MSBthPanInboxOnWindowsServer.ps1 r10), used to pinpoint the
# exact failing operation inside a complex function body. Three
# integrated subsystems:
#
#   (1) Trace primitives: Start-DebugTrace / Set-DebugStep /
#                         Stop-DebugTrace / Format-DebugFailure /
#                         Write-DebugFailureReport
#   (2) JSONL file output: Real-time append-only event stream to
#                         <WorkDir>\logs\debugtrace.jsonl
#   (3) JSON Export: Point-in-time snapshot with full state,
#                         used manually and auto-triggered on phase
#                         failure.
#
# This complements the existing per-Phase-6 failure diagnostics
# (Write-FailureDiagnostic, Add-ErrorJsonlEntry, P06_errors.jsonl):
# DebugTrace is cross-phase and tracks operation-level steps, while
# the Phase 6 diagnostics are download-specific and track per-deck
# failures. Both coexist without overlap.
#
# Typical usage pattern (function entry/body/catch/finally):
#
#   function Invoke-Something {
#       Start-DebugTrace -Context 'Invoke-Something'
#       try {
#           Set-DebugStep 'validate inputs'
#           ...
#           Set-DebugStep 'fetch URL'
#           ...
#           Set-DebugStep 'parse content'
#           ...
#           return $result
#       } catch {
#           Write-DebugFailureReport $_ -IncludeStepHistory
#           throw
#       } finally {
#           Stop-DebugTrace
#       }
#   }
#
# Nesting: traces stack via Stack<object>; nested traced functions
# don't stomp on each other's state. Format-DebugFailure always
# reports against the frame that was at the top of the stack at the
# moment the exception was caught.
#
# Phase integration: each top-level Invoke-Phase* call may wrap its
# body in Start-DebugTrace -PhaseId 'PNN' / Stop-DebugTrace; the
# Set-DebugStep markers inside the phase body are then attributed to
# that frame. On phase failure, Write-DebugFailureReport -AutoExport
# triggers Export-DebugTraceJson automatically when AutoExport is on.

# --- 1b.1: Module-level state ---------------------------------

# Stack of currently-active trace frames (most recent on top).
# Each frame is a pscustomobject with: Context, Step, Steps,
# StartTime, Echo, Outcome (set on Stop), FailureRef (set on failure).
$Script:DebugTraceStack = New-Object 'System.Collections.Generic.Stack[object]'

# Completed frames retained for JSON Export. Capped to prevent
# unbounded growth in long runs.
$Script:DebugTraceCompletedFrames = New-Object 'System.Collections.Generic.List[object]'
$Script:DebugTraceCompletedCap    = 1024  # cap on retained completed frames

# Step history cap per frame, to prevent unbounded growth in tight
# loops that call Set-DebugStep repeatedly.
$Script:DebugTraceHistoryCap = 256

# Per-event log line size cap (chars). Truncate over-cap fields when
# writing to JSONL so the stream stays grep-able.
$Script:DebugTraceJsonlLineCap = 8192

# ConvertTo-Json depth. 100 = PS 5.1 ConvertTo-Json official maximum.
$Script:DebugTraceJsonDepth = 100

# JSONL writer state. Activated by Enable-DebugTraceFileOutput,
# typically from the main try-block once WorkDir\logs exists.
$Script:DebugTraceJsonlEnabled    = $false
$Script:DebugTraceJsonlPath       = $null
$Script:DebugTraceJsonlBuffer     = New-Object 'System.Collections.Generic.List[string]'  # pre-activation buffer
$Script:DebugTraceJsonlBufferCap  = 4096  # pre-flush buffer cap (entry count)
$Script:DebugTraceJsonlWriteCount = 0
$Script:DebugTraceJsonlErrorCount = 0
$Script:DebugTraceJsonlLastError  = $null

# Auto-export-on-failure state.
$Script:DebugTraceAutoExportEnabled = $false
$Script:DebugTraceAutoExportDir     = $null

# Per-phase trace registry. Phase id -> frame reference + outcome
# metadata. Populated by Start-DebugTrace -PhaseId, finalised by
# Stop-DebugTrace or Write-DebugFailureReport.
$Script:DebugTracePhaseRegistry = @{}

# Script-level event sequence number. Monotonic across the whole run,
# included in every JSONL event so they can be ordered exactly even
# when multiple events share the same millisecond timestamp.
$Script:DebugTraceEventSeq = 0

# --- 1b.2: Internal helpers (not part of public API) ----------

function _DebugTrace_NextSeq {
    # Atomic-ish counter. Single-threaded PowerShell so no Interlocked
    # needed; this is just a small helper for readability.
    $Script:DebugTraceEventSeq++
    return $Script:DebugTraceEventSeq
}

function _DebugTrace_Now {
    # Return current time as ISO 8601 string with milliseconds and Z
    # suffix. Pre-converted to string so ConvertTo-Json doesn't render
    # the PS 5.1 legacy /Date(N)/ format - we want the same machine-
    # readable representation regardless of PS version.
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

function _DebugTrace_WriteJsonlLine {
    # Append one JSONL line to the debugtrace.jsonl file (or to the
    # pre-activation buffer if file output isn't enabled yet). All
    # failures are absorbed so the script body is never disrupted by
    # trace bookkeeping.
    param([Parameter(Mandatory)] $Event)

    # Add monotonic sequence number for stable cross-event ordering.
    $Event | Add-Member -MemberType NoteProperty -Name 'seq' -Value (_DebugTrace_NextSeq) -Force

    try {
        $json = $Event | ConvertTo-Json -Depth $Script:DebugTraceJsonDepth -Compress
    } catch {
        # If JSON conversion fails (e.g. circular reference somewhere),
        # fall back to a minimal hand-written line so we still record
        # something.
        $Script:DebugTraceJsonlErrorCount++
        $Script:DebugTraceJsonlLastError = $_.Exception.Message
        $kind = if ($Event.PSObject.Properties['kind']) { $Event.kind } else { 'unknown' }
        $ctx  = if ($Event.PSObject.Properties['ctx'])  { $Event.ctx  } else { '?' }
        $json = ('{{"ts":"{0}","seq":{1},"kind":"{2}","ctx":"{3}","err":"json-serialize-failed"}}' `
                    -f (_DebugTrace_Now), $Script:DebugTraceEventSeq, $kind, $ctx)
    }

    # Truncate over-cap lines so the JSONL stream stays grep-able.
    if ($json.Length -gt $Script:DebugTraceJsonlLineCap) {
        $json = $json.Substring(0, $Script:DebugTraceJsonlLineCap - 16) + '...","truncated":1}'
    }

    if ($Script:DebugTraceJsonlEnabled -and $Script:DebugTraceJsonlPath) {
        try {
            # IMPORTANT: UTF-8 with BOM. On Windows PowerShell 5.1 with
            # a ja-JP / non-English locale, Get-Content defaults to the
            # OS code page (Shift-JIS on ja-JP), which mojibakes any
            # Japanese / UTF-8 multi-byte content unless the file has
            # a BOM. AppendAllText only writes the BOM when the file is
            # freshly created, so subsequent appends incur no overhead.
            [System.IO.File]::AppendAllText(
                $Script:DebugTraceJsonlPath,
                $json + "`r`n",
                [System.Text.UTF8Encoding]::new($true))
            $Script:DebugTraceJsonlWriteCount++
        } catch {
            # If file write fails (e.g. disk full, perm changed), revert
            # to buffer mode and remember the error for diagnostics.
            $Script:DebugTraceJsonlErrorCount++
            $Script:DebugTraceJsonlLastError = $_.Exception.Message
            $Script:DebugTraceJsonlEnabled = $false
            $Script:DebugTraceJsonlBuffer.Add($json) | Out-Null
            while ($Script:DebugTraceJsonlBuffer.Count -gt $Script:DebugTraceJsonlBufferCap) {
                $Script:DebugTraceJsonlBuffer.RemoveAt(0)
            }
        }
    } else {
        # Pre-activation: buffer in memory. Will be flushed by
        # Enable-DebugTraceFileOutput once the logs directory is ready.
        $Script:DebugTraceJsonlBuffer.Add($json) | Out-Null
        while ($Script:DebugTraceJsonlBuffer.Count -gt $Script:DebugTraceJsonlBufferCap) {
            $Script:DebugTraceJsonlBuffer.RemoveAt(0)
        }
    }
}

function _DebugTrace_RetireFrame {
    # Move a frame from the active stack into the completed list.
    # Handles the history cap. Idempotent: safe to call even if the
    # frame has already been retired.
    param([Parameter(Mandatory)] $Frame, [Parameter(Mandatory)] [string]$Outcome)

    if (-not $Frame.PSObject.Properties['Outcome'] -or -not $Frame.Outcome) {
        $Frame | Add-Member -MemberType NoteProperty -Name 'Outcome'    -Value $Outcome -Force
        $Frame | Add-Member -MemberType NoteProperty -Name 'EndedAt'    -Value (Get-Date) -Force
        $durationMs = [int]((Get-Date) - $Frame.StartTime).TotalMilliseconds
        $Frame | Add-Member -MemberType NoteProperty -Name 'DurationMs' -Value $durationMs -Force
    }

    $Script:DebugTraceCompletedFrames.Add($Frame) | Out-Null
    while ($Script:DebugTraceCompletedFrames.Count -gt $Script:DebugTraceCompletedCap) {
        $Script:DebugTraceCompletedFrames.RemoveAt(0)
    }
}

# --- 1b.3: Public API - trace primitives ----------------------

function Start-DebugTrace {
    <#
    .SYNOPSIS
        Push a new debug trace frame onto the stack. Call at function
        entry.
    .PARAMETER Context
        Human-readable name for this frame, typically the function name
        or 'phase.PNN.<Name>' for phase-level frames.
    .PARAMETER Echo
        If set, every Set-DebugStep call also writes a live [trace] line
        to the console. Default off.
    .PARAMETER PhaseId
        Optional phase identifier (e.g. 'P05'). When set, the frame is
        registered in the per-phase trace registry so Export-DebugTraceJson
        can build a per-phase summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Context,
        [switch]$Echo,
        [string]$PhaseId
    )
    $frame = [pscustomobject]@{
        Context   = $Context
        Step      = 'entry'
        Steps     = (New-Object 'System.Collections.Generic.List[object]')
        StartTime = Get-Date
        Echo      = [bool]$Echo
        PhaseId   = $PhaseId
        Depth     = $Script:DebugTraceStack.Count + 1
    }
    $Script:DebugTraceStack.Push($frame)

    if ($PhaseId) {
        $Script:DebugTracePhaseRegistry[$PhaseId] = [pscustomobject]@{
            PhaseId    = $PhaseId
            Frame      = $frame
            StartedAt  = Get-Date
            EndedAt    = $null
            Outcome    = 'in-progress'
            FailureRef = $null
        }
    }

    _DebugTrace_WriteJsonlLine ([pscustomobject]@{
        ts    = _DebugTrace_Now
        kind  = 'frame.open'
        ctx   = $Context
        depth = $frame.Depth
        phase = $PhaseId
    })
}

function Set-DebugStep {
    <#
    .SYNOPSIS
        Mark the current step inside the active debug trace frame.
        No-op if no frame is active (so functions can use it
        opportunistically without callers having to set up tracing).
    .PARAMETER Step
        Short label describing the operation about to be performed.
    .PARAMETER Detail
        Optional extra context attached to this step in the JSONL log.
        Not surfaced in console output, only in the trace file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)] [string]$Step,
        [string]$Detail
    )
    if ($Script:DebugTraceStack.Count -eq 0) { return }
    $frame = $Script:DebugTraceStack.Peek()
    $frame.Step = $Step
    $now = Get-Date
    $frame.Steps.Add([pscustomobject]@{
        Step   = $Step
        At     = $now
        Detail = $Detail
    }) | Out-Null
    while ($frame.Steps.Count -gt $Script:DebugTraceHistoryCap) {
        $frame.Steps.RemoveAt(0)
    }
    if ($frame.Echo) {
        Write-Host ('[trace:{0}] {1}' -f $frame.Context, $Step) -ForegroundColor DarkMagenta
    }
    _DebugTrace_WriteJsonlLine ([pscustomobject]@{
        ts     = _DebugTrace_Now
        kind   = 'step'
        ctx    = $frame.Context
        step   = $Step
        detail = $Detail
    })
}

function Stop-DebugTrace {
    <#
    .SYNOPSIS
        Pop the most recent trace frame. Call in the finally block.
    .PARAMETER Outcome
        Optional outcome label. Defaults to 'success'. The catch block
        of the same function should set it to 'failure' before throwing
        if it wants the completed-frame record to reflect the failure.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('success','failure','cancelled','unknown')]
        [string]$Outcome = 'success'
    )
    if ($Script:DebugTraceStack.Count -eq 0) { return }
    $frame = $Script:DebugTraceStack.Pop()

    # If the frame was registered as a phase frame, finalise its
    # registry entry too.
    if ($frame.PhaseId -and $Script:DebugTracePhaseRegistry.ContainsKey($frame.PhaseId)) {
        $reg = $Script:DebugTracePhaseRegistry[$frame.PhaseId]
        $reg.EndedAt = Get-Date
        # Don't overwrite an already-set outcome (e.g. 'failure' set by
        # Write-DebugFailureReport).
        if ($reg.Outcome -eq 'in-progress') {
            $reg.Outcome = $Outcome
        }
    }

    _DebugTrace_RetireFrame -Frame $frame -Outcome $Outcome

    _DebugTrace_WriteJsonlLine ([pscustomobject]@{
        ts      = _DebugTrace_Now
        kind    = 'frame.close'
        ctx     = $frame.Context
        outcome = $frame.Outcome
        durMs   = $frame.DurationMs
        steps   = $frame.Steps.Count
        phase   = $frame.PhaseId
    })
}

function Format-DebugFailure {
    <#
    .SYNOPSIS
        Build a structured failure report from an ErrorRecord plus the
        currently-active trace frame. Use when you need the failure
        data programmatically (e.g. relay it elsewhere).
    .PARAMETER ErrorRecord
        The $_ inside a catch block.
    .OUTPUTS
        pscustomobject with: Context, FailedStep, Elapsed, ElapsedMs,
        PhaseId, ExType, ExMessage, InnerType, InnerMessage,
        FullyQualifiedId, ScriptStackTrace, StepHistory (object[]).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $ErrorRecord)
    $ex = $ErrorRecord.Exception
    if ($Script:DebugTraceStack.Count -gt 0) {
        $frame       = $Script:DebugTraceStack.Peek()
        $context     = $frame.Context
        $failedStep  = $frame.Step
        # PS 5.1 ja-JP bug workaround: use .ToArray(), not @($list).
        $stepHistory = $frame.Steps.ToArray()
        $elapsed     = (Get-Date) - $frame.StartTime
        $phaseId     = $frame.PhaseId
    } else {
        $context     = '(no active trace)'
        $failedStep  = '(no active trace)'
        $stepHistory = @()
        $elapsed     = [TimeSpan]::Zero
        $phaseId     = $null
    }
    return [pscustomobject]@{
        Context          = $context
        FailedStep       = $failedStep
        Elapsed          = $elapsed
        ElapsedMs        = [int]$elapsed.TotalMilliseconds
        PhaseId          = $phaseId
        ExType           = $ex.GetType().FullName
        ExMessage        = $ex.Message
        InnerType        = if ($ex.InnerException) { $ex.InnerException.GetType().FullName } else { $null }
        InnerMessage     = if ($ex.InnerException) { $ex.InnerException.Message } else { $null }
        FullyQualifiedId = $ErrorRecord.FullyQualifiedErrorId
        ScriptStackTrace = $ErrorRecord.ScriptStackTrace
        StepHistory      = $stepHistory
    }
}

function Write-DebugFailureReport {
    <#
    .SYNOPSIS
        Emit a formatted failure report via Write-Warn + log the
        failure event to JSONL. Call from a catch block. Also marks
        the active phase's registry entry as 'failure' if applicable.
    .PARAMETER ErrorRecord
        The $_ inside a catch block.
    .PARAMETER IncludeStepHistory
        If set, log every step the trace reached before the failure.
    .PARAMETER AutoExport
        If set, automatically write a JSON snapshot to the configured
        auto-export directory. Use this for top-level catch handlers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $ErrorRecord,
        [switch]$IncludeStepHistory,
        [switch]$AutoExport
    )
    $r = Format-DebugFailure -ErrorRecord $ErrorRecord

    # Update the phase registry if this failure happened inside a phase.
    if ($r.PhaseId -and $Script:DebugTracePhaseRegistry.ContainsKey($r.PhaseId)) {
        $reg = $Script:DebugTracePhaseRegistry[$r.PhaseId]
        $reg.Outcome    = 'failure'
        $reg.FailureRef = $r
    }

    Write-Warn ("{0}: FAILED at step '{1}' (elapsed {2:F2}s)" -f $r.Context, $r.FailedStep, $r.Elapsed.TotalSeconds)
    Write-Warn ("  ExType   : {0}" -f $r.ExType)
    Write-Warn ("  Message  : {0}" -f $r.ExMessage)
    if ($r.InnerType) {
        Write-Warn ("  Inner    : {0} - {1}" -f $r.InnerType, $r.InnerMessage)
    }
    if ($r.FullyQualifiedId) {
        Write-Warn ("  FQErrId  : {0}" -f $r.FullyQualifiedId)
    }
    if ($r.ScriptStackTrace) {
        $stackLines = $r.ScriptStackTrace -split "`r?`n"
        Write-Warn ("  Stack    : {0}" -f $stackLines[0])
        $maxStack = [Math]::Min(3, $stackLines.Count)
        for ($i = 1; $i -lt $maxStack; $i++) {
            Write-Warn ("             {0}" -f $stackLines[$i])
        }
    }
    if ($IncludeStepHistory -and $r.StepHistory.Count -gt 0) {
        Write-Warn ("  Steps    : {0} recorded" -f $r.StepHistory.Count)
        $firstAt = $r.StepHistory[0].At
        foreach ($h in $r.StepHistory) {
            $rel = ($h.At - $firstAt).TotalMilliseconds
            Write-Warn ('    +{0,7:F0}ms  {1}' -f $rel, $h.Step)
        }
    }

    _DebugTrace_WriteJsonlLine ([pscustomobject]@{
        ts          = _DebugTrace_Now
        kind        = 'failure'
        ctx         = $r.Context
        step        = $r.FailedStep
        elapsedMs   = $r.ElapsedMs
        phase       = $r.PhaseId
        exType      = $r.ExType
        msg         = $r.ExMessage
        innerType   = $r.InnerType
        innerMsg    = $r.InnerMessage
        fqErrId     = $r.FullyQualifiedId
        stack       = $r.ScriptStackTrace
        stepHistory = $r.StepHistory
    })

    if ($AutoExport -and $Script:DebugTraceAutoExportEnabled -and $Script:DebugTraceAutoExportDir) {
        try {
            $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $tag = if ($r.PhaseId) { $r.PhaseId } else { 'top' }
            $exportPath = Join-Path $Script:DebugTraceAutoExportDir ("debugtrace_export_{0}_{1}.json" -f $tag, $ts)
            Export-DebugTraceJson -Path $exportPath -IncludeEvents:$false | Out-Null
            Write-Warn ("  TraceJson: {0}" -f $exportPath)
        } catch {
            # Don't let auto-export failures hide the original error.
            Write-Warn ("  TraceJson: auto-export failed: {0}" -f $_.Exception.Message)
        }
    }
}

# --- 1b.4: Public API - file output ---------------------------

function Enable-DebugTraceFileOutput {
    <#
    .SYNOPSIS
        Activate the JSONL writer. Typically called from the main
        try-block once the logs directory exists. Flushes the pre-
        activation buffer into the file in one go.
    .PARAMETER Directory
        Target directory. The file is named 'debugtrace.jsonl' inside
        this dir. If a same-named file exists, it is appended.
    .PARAMETER Force
        If set, switch output to the new directory even if file output
        was already active. (Useful for re-routing.)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Directory,
        [switch]$Force
    )
    if ($Script:DebugTraceJsonlEnabled -and -not $Force) { return }

    try {
        if (-not (Test-Path -LiteralPath $Directory)) {
            New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
        }
        $path = Join-Path $Directory 'debugtrace.jsonl'

        # Probe write a header line so the file exists and is writable.
        # If a same-name lock collision occurs, fall back to per-pid filename.
        # Renamed 'host' to 'hostName' defensively to avoid collision with
        # the $Host auto-variable on certain PS 5.1 parser contexts.
        $headerObj = [pscustomobject]@{
            ts        = _DebugTrace_Now
            kind      = 'file.open'
            scriptVer = $Script:ScriptVersion
            scriptSha = $Script:ScriptHash
            procId    = $PID
            hostName  = $Host.Name
            psVer     = $PSVersionTable.PSVersion.ToString()
            culture   = (Get-Culture).Name
        }
        $headerJson = $headerObj | ConvertTo-Json -Depth $Script:DebugTraceJsonDepth -Compress
        try {
            # UTF-8 with BOM (see _DebugTrace_WriteJsonlLine comment).
            [System.IO.File]::AppendAllText($path, $headerJson + "`r`n", [System.Text.UTF8Encoding]::new($true))
        } catch {
            # Path locked by another process; switch to per-pid filename.
            $path = Join-Path $Directory ("debugtrace_{0}.jsonl" -f $PID)
            [System.IO.File]::AppendAllText($path, $headerJson + "`r`n", [System.Text.UTF8Encoding]::new($true))
        }

        $Script:DebugTraceJsonlPath    = $path
        $Script:DebugTraceJsonlEnabled = $true

        # Flush pre-activation buffer
        if ($Script:DebugTraceJsonlBuffer.Count -gt 0) {
            $bufferedLines = $Script:DebugTraceJsonlBuffer.ToArray()
            $Script:DebugTraceJsonlBuffer.Clear()
            try {
                $blob = ($bufferedLines -join "`r`n") + "`r`n"
                [System.IO.File]::AppendAllText($path, $blob, [System.Text.UTF8Encoding]::new($true))
                $Script:DebugTraceJsonlWriteCount += $bufferedLines.Count
            } catch {
                # If flush fails, re-buffer for the next opportunity.
                foreach ($l in $bufferedLines) { $Script:DebugTraceJsonlBuffer.Add($l) | Out-Null }
                $Script:DebugTraceJsonlErrorCount++
                $Script:DebugTraceJsonlLastError = $_.Exception.Message
                throw
            }
        }

        # Register a one-shot cleanup at PowerShell host exit so the
        # JSONL stream is flushed and a close marker is written even on
        # abnormal termination.
        Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action {
            try {
                if ($Script:DebugTraceJsonlEnabled -and $Script:DebugTraceJsonlPath) {
                    $closeEvent = '{{"ts":"{0}","kind":"file.close","procId":{1}}}' -f `
                        (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'), $PID
                    [System.IO.File]::AppendAllText(
                        $Script:DebugTraceJsonlPath,
                        $closeEvent + "`r`n",
                        [System.Text.UTF8Encoding]::new($true))
                }
            } catch { } # psa-disable-line PSA3004 -- intentional best-effort during PowerShell.Exiting; host is tearing down, surfacing errors is useless
        } | Out-Null

        Write-Host ('[*] Debug trace -> {0}' -f $path) -ForegroundColor DarkGreen
    } catch {
        # Activation failed; stay in buffer mode. The buffer continues
        # to accumulate but we never surface the failure as an error to
        # the caller - trace bookkeeping must not break the script.
        $Script:DebugTraceJsonlEnabled = $false
        $Script:DebugTraceJsonlErrorCount++
        $Script:DebugTraceJsonlLastError = $_.Exception.Message
        Write-Warning ("Debug trace file output activation failed: {0}" -f $_.Exception.Message)
        Write-Warning '   Trace events remain captured in memory and are exportable via Export-DebugTraceJson.'
    }
}

function Disable-DebugTraceFileOutput {
    <#
    .SYNOPSIS
        Stop appending trace events to the JSONL file. Events continue
        to be captured in memory and remain exportable via
        Export-DebugTraceJson.
    #>
    [CmdletBinding()]
    param()
    if (-not $Script:DebugTraceJsonlEnabled) { return }
    _DebugTrace_WriteJsonlLine ([pscustomobject]@{
        ts   = _DebugTrace_Now
        kind = 'file.disable'
    })
    $Script:DebugTraceJsonlEnabled = $false
}

function Get-DebugTraceFileOutputStatus { # psa-disable-line PSA6003 -- "Status" is singular; analyzer false positive on compound name
    <#
    .SYNOPSIS
        Return the current state of the JSONL writer for diagnostics.
    #>
    [CmdletBinding()]
    param()
    return [pscustomobject]@{
        Enabled         = $Script:DebugTraceJsonlEnabled
        Path            = $Script:DebugTraceJsonlPath
        WriteCount      = $Script:DebugTraceJsonlWriteCount
        ErrorCount      = $Script:DebugTraceJsonlErrorCount
        LastError       = $Script:DebugTraceJsonlLastError
        BufferedLines   = $Script:DebugTraceJsonlBuffer.Count
        ActiveFrames    = $Script:DebugTraceStack.Count
        CompletedFrames = $Script:DebugTraceCompletedFrames.Count
    }
}

# --- 1b.5: Public API - JSON Export ---------------------------

function Enable-AutoExportOnPhaseFailure {
    <#
    .SYNOPSIS
        Turn on automatic JSON Export when a phase fails. When enabled,
        Write-DebugFailureReport -AutoExport will write a snapshot to
        the configured directory.
    .PARAMETER OutputDirectory
        Where to write debugtrace_export_<phaseId>_<timestamp>.json files.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$OutputDirectory)
    $Script:DebugTraceAutoExportEnabled = $true
    $Script:DebugTraceAutoExportDir     = $OutputDirectory
}

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
            clrVersion  = $PSVersionTable.CLRVersion.ToString()
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

# ============================================================
# Display utilities
# ============================================================

function Format-Elapsed {
    # Render a TimeSpan in a compact human-readable form.
    # Examples: '0.45s', '12.3s', '5m12.4s', '1h05m12s'
    param([TimeSpan]$Span)
    if ($null -eq $Span) { return '0.00s' }
    if ($Span.TotalSeconds -lt 60) {
        return ('{0:F2}s' -f $Span.TotalSeconds)
    } elseif ($Span.TotalMinutes -lt 60) {
        $m = [int][math]::Floor($Span.TotalMinutes)
        $s = $Span.TotalSeconds - ($m * 60)
        return ('{0}m{1:F1}s' -f $m, $s)
    } else {
        $h = [int][math]::Floor($Span.TotalHours)
        $m = $Span.Minutes
        $s = $Span.Seconds
        return ('{0}h{1:D2}m{2:D2}s' -f $h, $m, $s)
    }
}

function Get-PhaseElapsedTag {
    # Returns elapsed-since-current-phase-start as '[+X.XXs]' or empty.
    if ($null -eq $Script:CurrentPhaseStart) { return '' }
    $span = (Get-Date) - $Script:CurrentPhaseStart
    return ('[+{0}]' -f (Format-Elapsed $span))
}

function _LogLine {
    # Internal: emits '[HH:mm:ss] [+X.XXs]   [marker] message'
    param([string]$Marker, [string]$Msg, [string]$Color)
    $ts  = Get-Date -Format 'HH:mm:ss'
    $tag = Get-PhaseElapsedTag
    if ($tag) {
        Write-Host ("[{0}] {1,-12} {2} {3}" -f $ts, $tag, $Marker, $Msg) -ForegroundColor $Color
    } else {
        Write-Host ("[{0}] {1,-12} {2} {3}" -f $ts, '', $Marker, $Msg) -ForegroundColor $Color
    }
}

# Public log helpers. Names are kept compatible with the prior code so
# all existing callsites continue to work; only the rendering changed.
#
# Marker mapping (matching reference script style):
#   [*] step / in-progress     - cyan
#   [+] success                - green
#   [!] warning                - yellow
#   [X] failure                - red
#   [~] skipped                - dark gray
#
# Canonical names (no duplicates, no trailing-digit suffixes). None of
# these collide with built-in cmdlets - PowerShell has Write-Warning
# and Write-Information but not Write-Warn / Write-Skip / Write-Step.
function Write-Step  { param([string]$m) _LogLine '[*]' $m 'Cyan'     }
function Write-Ok    { param([string]$m) _LogLine '[+]' $m 'Green'    }
function Write-Warn  { param([string]$m) _LogLine '[!]' $m 'Yellow'   }
function Write-Fail  { param([string]$m) _LogLine '[X]' $m 'Red'      }
function Write-Skip  { param([string]$m) _LogLine '[~]' $m 'DarkGray' }

function Write-SubSection {
    # Lightweight section break inside a phase (e.g. [Step A]/[Step B]).
    # Prints with a leading blank line and a horizontal rule.
    param([string]$Title)
    Write-Host ''
    Write-Host (' -- ' + $Title + ' ' + ('-' * [Math]::Max(1, 60 - $Title.Length))) -ForegroundColor Gray
}

function Write-PhaseHeader {
    # Prints a magenta banner that opens a phase. Records phase start
    # time so subsequent log lines can show '[+elapsed]'.
    #
        #   Id    : short identifier (e.g. 'P01', 'P06', etc; always two digits)
    #   Name  : human-readable phase name (e.g. 'Listing-Collection')
    #   Group : phase group (e.g. 'Setup', 'Scan', 'Fetch', 'Report')
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Group
    )
    $Script:CurrentPhaseStart = Get-Date
    $Script:CurrentPhaseId    = $Id
    $startStr = $Script:CurrentPhaseStart.ToString('HH:mm:ss')
    $line = '=' * 72
    Write-Host ''
    Write-Host $line -ForegroundColor Magenta
    Write-Host (' PHASE {0,-4} - {1,-22} ({2,-7}) start: {3}' -f $Id, $Name, $Group, $startStr) -ForegroundColor Magenta
    Write-Host (' script: {0}' -f $Script:ScriptShortTag) -ForegroundColor DarkGray
    Write-Host $line -ForegroundColor Magenta
}

function Write-PhaseFooter {
    # Closes a phase started by Write-PhaseHeader. Records the elapsed
    # duration in $Script:PhaseTimings (used by Show-PhaseSummary).
    #
    # Idempotent: a second call with the same Id is ignored, so wrapping
    # try/finally blocks do not double-count.
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [ValidateSet('done','skipped','failed')] [string]$Status
    )
    foreach ($t in $Script:PhaseTimings) {
        if ($t.Id -eq $Id) { return }
    }
    $color = switch ($Status) {
        'done'    { 'Green' }
        'skipped' { 'DarkGray' }
        'failed'  { 'Red' }
    }
    $elapsed = if ($Script:CurrentPhaseStart) { (Get-Date) - $Script:CurrentPhaseStart } else { [TimeSpan]::Zero }
    $elapsedStr = Format-Elapsed $elapsed

    $Script:PhaseTimings.Add([pscustomobject]@{
        Id      = $Id
        Status  = $Status
        Elapsed = $elapsed
        EndedAt = Get-Date
    }) | Out-Null

    Write-Host (' PHASE {0,-4} -> {1,-7}  elapsed: {2}' -f $Id, $Status.ToUpper(), $elapsedStr) -ForegroundColor $color

    $Script:CurrentPhaseStart = $null
    $Script:CurrentPhaseId    = $null
}

function Show-PhaseSummary {
    # End-of-run summary table, one row per executed phase.
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host ' Phase Timing Summary' -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
    if ($Script:PhaseTimings.Count -eq 0) {
        Write-Host '  (no phases were recorded)' -ForegroundColor DarkGray
    } else {
        foreach ($t in $Script:PhaseTimings) {
            $color = switch ($t.Status) {
                'done'    { 'Green' }
                'skipped' { 'DarkGray' }
                'failed'  { 'Red' }
                default   { 'Gray' }
            }
            Write-Host ('  {0,-4}  {1,-7}  elapsed: {2}' -f $t.Id, $t.Status.ToUpper(), (Format-Elapsed $t.Elapsed)) -ForegroundColor $color
        }
    }
    $totalElapsed = (Get-Date) - $Script:ScriptStartTime
    Write-Host ('  ' + ('-' * 40)) -ForegroundColor DarkGray
    Write-Host ('  Total elapsed: {0}' -f (Format-Elapsed $totalElapsed)) -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

# ============================================================
# Cleanup helpers (used by -Clean / -CleanOnly)
# ============================================================

function Test-DangerousPath {
    # Returns $true if removing this path would be dangerous.
    # Used by Invoke-CleanupDirectories to refuse obviously wrong targets:
    #   - empty / unresolvable path
    #   - drive root (e.g. 'C:\')
    #   - $Script:ScriptRoot itself (would wipe the script)
    #   - a parent of $Script:ScriptRoot
    param([Parameter(Mandatory)] [string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $true }
    try {
        $abs = [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $true
    }
    $abs = $abs.TrimEnd('\','/')
    # Drive root: 'C:' (2 chars), 'C:\' before trim (3 chars).
    # After TrimEnd, 'C:\' becomes 'C:' (2 chars). Treat <=2 as drive root.
    if ($abs.Length -le 3) { return $true }
    $sr = $null
    try { $sr = $Script:ScriptRoot.TrimEnd('\','/') } catch { } # psa-disable-line PSA3004 -- null/missing ScriptRoot is handled by the `if (-not $sr)` guard immediately below
    if (-not $sr) { return $false }
    if ($abs -ieq $sr) { return $true }
    # $abs contains the script (script lives inside $abs)
    if (($sr + '\').StartsWith($abs + '\', [StringComparison]::OrdinalIgnoreCase) -or
        ($sr + '/').StartsWith($abs + '/', [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $false
}

function Invoke-CleanupDirectories {
    # Wipe $OutputDir and $WorkDir trees. Idempotent (missing dirs are
    # silently skipped). Throws if either path looks dangerous.
    param(
        [Parameter(Mandatory)] [string]$OutputDir,
        [Parameter(Mandatory)] [string]$WorkDir
    )
    foreach ($pair in @(
            @{ Name = 'OutputDir'; Path = $OutputDir },
            @{ Name = 'WorkDir';   Path = $WorkDir   })) {

        $name = $pair.Name
        $path = $pair.Path

        if (Test-DangerousPath -Path $path) {
            throw "Refusing to clean $name : path looks unsafe to remove: $path"
        }

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Skip ("  {0,-10} not present (skipped): {1}" -f $name, $path)
            continue
        }

        # Report what we're about to remove.
        $sizeMb   = 0.0
        $fileCnt  = 0
        try {
            $items   = Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue
            $bytes   = ($items | Measure-Object -Property Length -Sum).Sum
            if ($bytes) { $sizeMb = $bytes / 1MB }
            $fileCnt = if ($items) { $items.Count } else { 0 }
        } catch { } # psa-disable-line PSA3004 -- best-effort size/count reporting only; do not block cleanup on stat errors

        Write-Skip ("  removing: {0,-10} ({1,7:N1} MB / {2,5} files): {3}" -f `
            $name, $sizeMb, $fileCnt, $path)
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Skip ("  removed:  {0,-10} {1}" -f $name, $path)
        } catch {
            Write-Fail "Failed to remove $path : $($_.Exception.Message)"
            throw
        }
    }
    Write-Ok "cleanup completed"
}

# ============================================================
# URL handling helper
# ============================================================

function Get-DecodedUrlFilename {
    # Speaker Deck CDN URLs percent-encode non-ASCII filename bytes
    # per RFC 3986. Without decoding, the percent-encoded form leaks
    # into the output file name and produces unreadable artifacts on
    # disk. For example, a Japanese filename like "summary.pdf" (the
    # actual word is non-ASCII) shows up in the URL as something like
    # ".../Real_Application_Testing_%E6%A6%82%E8%A6%81.pdf" and we
    # need to reverse the percent-encoding before storing on disk.
    # This helper extracts the last path segment and UTF-8-decodes it
    # back to its original (display-readable) form.
    param([Parameter(Mandatory)] [string]$Url)
    if ([string]::IsNullOrEmpty($Url)) { return $null }
    $rawFilename = ($Url -split '/')[-1]
    if ([string]::IsNullOrEmpty($rawFilename)) { return $null }
    try {
        return [System.Uri]::UnescapeDataString($rawFilename)
    } catch {
        # Conservative fallback: if decoding throws, keep the raw form.
        return $rawFilename
    }
}

# ============================================================
# Failure diagnostic helpers (Phase 6)
# ============================================================

function Get-FailureCategory {
    # Coarse-grained category used in the Phase 6 failure breakdown
    # table. Maps the rich ErrorDetails captured by the worker into a
    # short, readable label.
    param([Parameter(Mandatory)] $Item)

    $ed = $Item.ErrorDetails
    if (-not $ed) {
        $msg = if ($Item.ErrorMessage) { $Item.ErrorMessage } else { '' }
        if ($msg -match 'Timeout|timed out')         { return 'Timeout' }
        if ($msg -match 'too long|MAX_PATH|path is') { return 'PathTooLong' }
        if ($msg -match 'HTTP\s*(\d{3})')            { return "HTTP $($Matches[1])" }
        return 'Other'
    }

    if ($ed.LastStatusCode) {
        switch ([int]$ed.LastStatusCode) {
            429     { return 'HTTP 429 (Too Many Requests)' }
            503     { return 'HTTP 503 (Service Unavailable)' }
            500     { return 'HTTP 500 (Internal Server Error)' }
            502     { return 'HTTP 502 (Bad Gateway)' }
            504     { return 'HTTP 504 (Gateway Timeout)' }
            403     { return 'HTTP 403 (Forbidden)' }
            404     { return 'HTTP 404 (Not Found)' }
            default { return ('HTTP ' + [int]$ed.LastStatusCode) }
        }
    }

    $et = if ($ed.LastErrorType) { $ed.LastErrorType } else { '' }
    if ($et -match 'TimeoutException')   { return 'Timeout' }
    if ($et -match 'WebException')       { return 'Network/WebException' }
    if ($et -match 'IOException')        { return 'IO error' }

    $em = if ($ed.LastErrorMessage) { $ed.LastErrorMessage } else { '' }
    if ($em -match 'too long|MAX_PATH|path is too long') { return 'PathTooLong' }

    if ($et) { return $et }
    return 'Other'
}

function Write-FailureDiagnostic {
    # Persist a detailed per-failure diagnostic dump under
    # $Script:FailedDir as a plain-text file. One file per failed deck,
    # named '<index4>_<safeslug>.txt' for predictable sorting.
    # Called from the main thread's reaping loop, so concurrent writes
    # are not a concern.
    param([Parameter(Mandatory)] $Item)

    if ([string]::IsNullOrEmpty($Script:FailedDir)) { return }

    # Lazy-create the failed/ directory on first failure.
    if (-not (Test-Path -LiteralPath $Script:FailedDir)) {
        try {
            New-Item -ItemType Directory -Path $Script:FailedDir -Force | Out-Null
        } catch {
            return
        }
    }

    $slug = ($Item.DeckUrl -split '/')[-1]
    if ([string]::IsNullOrEmpty($slug)) { $slug = 'unknown' }
    # Sanitize slug for filename use: replace forbidden chars, truncate.
    $safeSlug = $slug -replace '[<>:"/\\|?*]', '_'
    if ($safeSlug.Length -gt 80) { $safeSlug = $safeSlug.Substring(0, 80) }

    $idx = if ($null -ne $Item.Index) { [int]$Item.Index } else { 0 }
    $fname = ('{0:D4}_{1}.txt' -f $idx, $safeSlug)
    $path  = Join-Path $Script:FailedDir $fname

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine('=' * 72)
    [void]$sb.AppendLine("Failure diagnostic for deck #$idx")
    [void]$sb.AppendLine('=' * 72)
    [void]$sb.AppendLine("Generated at        : $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))")
    [void]$sb.AppendLine("Script version      : $Script:ScriptShortTag")
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('-- Deck info -----------------------------------------------------------')
    [void]$sb.AppendLine("Index               : $($Item.Index)")
    [void]$sb.AppendLine("Title               : $($Item.Title)")
    [void]$sb.AppendLine("Deck URL            : $($Item.DeckUrl)")
    [void]$sb.AppendLine("Download URL        : $($Item.DownloadUrl)")
    [void]$sb.AppendLine("Original filename   : $($Item.OriginalFilename)")
    [void]$sb.AppendLine("Publish date        : $($Item.PublishDate)")
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('-- Output path ---------------------------------------------------------')
    [void]$sb.AppendLine("Output filename     : $($Item.OutputFilename)")
    [void]$sb.AppendLine("Output full path    : $($Item.OutputFullPath)")
    [void]$sb.AppendLine("Output type         : $($Item.OutputType)")
    if ($Item.OutputFullPath) {
        [void]$sb.AppendLine("Path length         : $($Item.OutputFullPath.Length) chars")
    }
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('-- Failure summary -----------------------------------------------------')
    [void]$sb.AppendLine("Status              : $($Item.Status)")
    [void]$sb.AppendLine("Attempts            : $($Item.Attempts)")
    [void]$sb.AppendLine("Duration (ms)       : $($Item.DurationMs)")
    [void]$sb.AppendLine("Bytes received      : $($Item.Bytes)")
    [void]$sb.AppendLine("Category            : $(Get-FailureCategory -Item $Item)")
    [void]$sb.AppendLine('')

    $ed = $Item.ErrorDetails
    if ($ed) {
        [void]$sb.AppendLine('-- Error details -------------------------------------------------------')
        [void]$sb.AppendLine("HTTP status code    : $($ed.LastStatusCode)")
        [void]$sb.AppendLine("Exception type      : $($ed.LastErrorType)")
        [void]$sb.AppendLine("Exception message   : $($ed.LastErrorMessage)")
        if ($ed.InnerErrorType) {
            [void]$sb.AppendLine("Inner type          : $($ed.InnerErrorType)")
            [void]$sb.AppendLine("Inner message       : $($ed.InnerErrorMessage)")
        }
        [void]$sb.AppendLine('')

        if ($ed.ResponseHeaders) {
            [void]$sb.AppendLine('-- Response headers ----------------------------------------------------')
            [void]$sb.AppendLine($ed.ResponseHeaders)
            [void]$sb.AppendLine('')
        }

        if ($ed.ResponseBodyPreview) {
            [void]$sb.AppendLine('-- Response body preview (first ~2KB) ----------------------------------')
            [void]$sb.AppendLine($ed.ResponseBodyPreview)
            [void]$sb.AppendLine('')
        }

        if ($ed.AttemptHistory -and $ed.AttemptHistory.Count -gt 0) {
            [void]$sb.AppendLine('-- Attempt history -----------------------------------------------------')
            foreach ($a in $ed.AttemptHistory) {
                $sc = if ($a.StatusCode) { "HTTP $($a.StatusCode)" } else { 'no HTTP status' }
                $em = if ($a.Message) { $a.Message } else { '' }
                [void]$sb.AppendLine(("  Attempt {0}: {1} ({2}) {3}" -f $a.Attempt, $a.Result, $sc, $em))
            }
            [void]$sb.AppendLine('')
        }

        if ($ed.StackTrace) {
            [void]$sb.AppendLine('-- Stack trace ---------------------------------------------------------')
            [void]$sb.AppendLine($ed.StackTrace)
            [void]$sb.AppendLine('')
        }
    } elseif ($Item.ErrorMessage) {
        [void]$sb.AppendLine('-- Error (legacy) ------------------------------------------------------')
        [void]$sb.AppendLine($Item.ErrorMessage)
        [void]$sb.AppendLine('')
    }

    try {
        # -LiteralPath defensively, even though $path is built from a
        # sanitized slug ($safeSlug = $slug -replace '[<>:"/\\|?*]', '_').
        # Speaker Deck slugs normally lowercase the title and replace
        # special chars (#99 -> number-99), but we use -LiteralPath so
        # any future slug with '[' ']' would still work.
        Set-Content -LiteralPath $path -Value $sb.ToString() -Encoding UTF8 -ErrorAction Stop
    } catch {
        # We're already in a failure path; swallow to avoid compounding.
    }
}

function Add-ErrorJsonlEntry {
    # Append one JSON object (single line) to $Script:ErrorsJsonlPath.
    # JSONL is a streaming-friendly format: one self-contained JSON
    # object per line, ideal for jq / grep / structured analysis.
    param([Parameter(Mandatory)] $Item)

    if ([string]::IsNullOrEmpty($Script:ErrorsJsonlPath)) { return }

    try {
        $obj = [ordered]@{
            timestamp            = (Get-Date).ToString('o')
            scriptVersion        = $Script:ScriptShortTag
            index                = $Item.Index
            title                = $Item.Title
            deckUrl              = $Item.DeckUrl
            downloadUrl          = $Item.DownloadUrl
            originalFilename     = $Item.OriginalFilename
            outputFilename       = $Item.OutputFilename
            outputFullPath       = $Item.OutputFullPath
            outputFullPathLength = if ($Item.OutputFullPath) { $Item.OutputFullPath.Length } else { $null }
            outputType           = $Item.OutputType
            publishDate          = $Item.PublishDate
            status               = $Item.Status
            attempts             = $Item.Attempts
            durationMs           = [int]$Item.DurationMs
            bytes                = $Item.Bytes
            category             = (Get-FailureCategory -Item $Item)
        }
        $ed = $Item.ErrorDetails
        if ($ed) {
            $obj['httpStatusCode']        = $ed.LastStatusCode
            $obj['exceptionType']         = $ed.LastErrorType
            $obj['exceptionMessage']      = $ed.LastErrorMessage
            $obj['innerExceptionType']    = $ed.InnerErrorType
            $obj['innerExceptionMessage'] = $ed.InnerErrorMessage
            $obj['attemptHistory']        = $ed.AttemptHistory
        } else {
            $obj['errorMessage'] = $Item.ErrorMessage
        }
        $json = $obj | ConvertTo-Json -Compress -Depth 8
        Add-Content -Path $Script:ErrorsJsonlPath -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Silently ignore failures here so the main flow is not disrupted.
    }
}

# ============================================================
# Common helpers
# ============================================================

function Wait-WithJitter {
    param(
        [double]$BaseSeconds,
        [double]$JitterRange
    )
    $jitter = Get-Random -Minimum (-$JitterRange) -Maximum $JitterRange
    $actualSleep = [Math]::Max(0.1, $BaseSeconds + $jitter)
    Start-Sleep -Milliseconds ([int]($actualSleep * 1000))
}

function Invoke-WebRequestWithRetry {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [int]$MaxRetries = 3,
        [int]$TimeoutSec = 60
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Uri `
                -UserAgent $Script:UserAgent `
                -Headers $Script:RequestHeaders `
                -TimeoutSec $TimeoutSec `
                -UseBasicParsing `
                -ErrorAction Stop
            return $response
        }
        catch {
            $lastError = $_
            $statusCode = $null
            try { if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode } } catch { } # psa-disable-line PSA3004 -- status code is diagnostic only; the retry loop uses $lastError to decide control flow

            if ($statusCode -eq 429 -or $statusCode -eq 503) {
                $wait = [Math]::Pow(2, $attempt) * 3
                Write-Warn "HTTP $statusCode received. Waiting $wait sec then retry ($attempt/$MaxRetries)"
                Start-Sleep -Seconds $wait
            }
            elseif ($attempt -lt $MaxRetries) {
                $wait = [Math]::Pow(2, $attempt)
                Write-Warn "Network error: $($_.Exception.Message). Retrying in $wait sec ($attempt/$MaxRetries)"
                Start-Sleep -Seconds $wait
            }
        }
    }
    throw $lastError
}

function ConvertFrom-HtmlEntity {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    try {
        return [System.Web.HttpUtility]::HtmlDecode($Text)
    } catch {
        # Fallback if System.Web is unavailable
        return $Text -replace '&amp;','and' -replace '&lt;','(' -replace '&gt;',')' `
                     -replace '&quot;',"'" -replace '&#39;',"'" -replace '&nbsp;',' '
    }
}

# ============================================================
# Filename processing
# ============================================================

function ConvertTo-SafeFilename {
    param([string]$InputString)

    if ([string]::IsNullOrEmpty($InputString)) { return "" }

    # Map Windows-forbidden characters to ASCII-safe substitutes
    #   <  -> (        >  -> )
    #   :  -> -        "  -> '
    #   /  -> _        \  -> _
    #   |  -> _        ?  -> (removed)
    #   *  -> (removed)
    $replacements = @{
        '<' = '('
        '>' = ')'
        ':' = '-'
        '"' = "'"
        '/' = '_'
        '\' = '_'
        '|' = '_'
        '?' = ''
        '*' = ''
    }
    $result = $InputString
    foreach ($key in $replacements.Keys) {
        $result = $result.Replace($key, $replacements[$key])
    }

    # Strip control characters
    $result = $result -replace '[\x00-\x1F\x7F]', ''

    # Collapse runs of whitespace to a single space
    $result = $result -replace '\s+', ' '

    # Strip trailing space / period (illegal at end of Windows filename)
    $result = $result.TrimEnd(' ', '.', "`t")

    return $result.Trim()
}

function Get-DateFromFilename {
    param([string]$Filename)

    # Find an 8-digit YYYYMMDD substring (year 19xx or 20xx)
    $regexMatches = [regex]::Matches($Filename, '(?<![\d])((?:19|20)\d{6})(?![\d])')
    foreach ($m in $regexMatches) {
        $dateStr = $m.Groups[1].Value
        try {
            $year  = [int]$dateStr.Substring(0,4)
            $month = [int]$dateStr.Substring(4,2)
            $day   = [int]$dateStr.Substring(6,2)
            if ($year -ge 1990 -and $year -le 2099 `
                -and $month -ge 1 -and $month -le 12 `
                -and $day -ge 1 -and $day -le 31) {
                return $dateStr
            }
        } catch { } # psa-disable-line PSA3004 -- substring/parse failure means this candidate is invalid; loop continues with next match
    }
    return $null
}

function Convert-DateStringToYYYYMMDD {
    param([string]$DateString)

    if ([string]::IsNullOrEmpty($DateString)) { return $null }

    $formats = @(
        "MMM dd, yyyy",
        "MMMM dd, yyyy",
        "yyyy-MM-ddTHH:mm:sszzz",
        "yyyy-MM-ddTHH:mm:ssZ",
        "yyyy-MM-dd",
        "yyyy/MM/dd"
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    foreach ($fmt in $formats) {
        try {
            $date = [DateTime]::ParseExact($DateString, $fmt, $culture)
            return $date.ToString("yyyyMMdd")
        } catch { } # psa-disable-line PSA3004 -- ParseExact failure means this format does not match; loop tries the next format
    }

    # Final fallback: lenient parse
    try {
        $date = [DateTime]::Parse($DateString, $culture)
        return $date.ToString("yyyyMMdd")
    } catch {
        return $null
    }
}

function Get-PdfMetadata {
    <#
    .SYNOPSIS
        Extract publication metadata from a downloaded PDF (read-only).

    .DESCRIPTION
        Reads up to the first 1MB and the last 512KB of the PDF (PDF
        metadata is conventionally in the Info Dictionary near the
        start, or in the XMP packet just before the cross-reference
        table at the end). Decodes the bytes as Latin-1 so binary
        portions don't raise decode errors while ASCII metadata
        regions remain byte-accurate.

        Used by Phase 8 (Invoke-Phase8UndatedReclassify) to derive a
        publication year for files that Phase 5's Get-DeckYear could
        not classify (and therefore landed in _undated/).

        Priority order for year selection:
          1. /CreationDate (PDF Info Dictionary)         -> PdfInfoDict
          2. xmp:CreateDate (XMP packet)                 -> PdfXmp
          3. xap:CreateDate (legacy XMP namespace)       -> PdfXmpLegacy
          4. pdf:CreationDate (pdf-specific namespace)   -> PdfXmpPdfNs
          5. /ModDate (Info Dict fallback)               -> PdfInfoDictMod
          6. xmp:ModifyDate (XMP fallback)               -> PdfXmpMod

        Valid year range matches Get-DeckYear: [2010, currentYear+1].

        Returns a PSCustomObject with:
          - Year     : "2021" or $null when nothing usable was found
          - Source   : one of the labels above, or $null
          - RawValue : the raw matched string (for diagnostic logging)
          - Error    : exception message, if any I/O / parse error
                       occurred. Empty when extraction succeeded or
                       when the file simply has no metadata.

        Validated against real Speaker Deck PDFs during Phase 8
        productionisation. The parsing logic has been exercised
        against both XMP and Info-Dictionary metadata variants.
    #>
    param([Parameter(Mandatory)][string]$PdfPath)

    $r = [ordered]@{
        Year     = $null
        Source   = $null
        RawValue = ''
        Error    = ''
    }

    try {
        $fi = Get-Item -LiteralPath $PdfPath -ErrorAction Stop
        $headSize = [Math]::Min([int64]$fi.Length, [int64]1MB)
        $tailSize = [Math]::Min([int64]$fi.Length, [int64]512KB)

        $fs = [System.IO.File]::OpenRead($PdfPath)
        try {
            $headBuf = New-Object byte[] $headSize
            [void]$fs.Read($headBuf, 0, $headSize)

            $tailBuf = $null
            if ($fi.Length -gt 1MB) {
                $tailBuf = New-Object byte[] $tailSize
                $fs.Seek(-$tailSize, [IO.SeekOrigin]::End) | Out-Null
                [void]$fs.Read($tailBuf, 0, $tailSize)
            }
        } finally {
            $fs.Close()
        }

        $enc      = [System.Text.Encoding]::GetEncoding('iso-8859-1')
        $headText = $enc.GetString($headBuf)
        $tailText = if ($tailBuf) { $enc.GetString($tailBuf) } else { '' }
        $text     = $headText + "`n----TAIL-BOUNDARY----`n" + $tailText

        # Info Dictionary date: /Key (D:YYYY...)  - only need the year.
        $tryInfoDate = {
            param([string]$Key)
            $m = [regex]::Match($text, ('/{0}\s*\(\s*D:(\d{{4}})' -f $Key))
            if ($m.Success) { return $m.Groups[1].Value }
            return ''
        }

        # XMP date element: <Tag>YYYY-...</Tag>
        $tryXmp = {
            param([string]$Tag)
            $pattern = '<' + [regex]::Escape($Tag) + '>\s*([^<\s]{1,80})\s*</' + [regex]::Escape($Tag) + '>'
            $m = [regex]::Match($text, $pattern)
            if ($m.Success) { return $m.Groups[1].Value }
            return ''
        }

        $candidates = @(
            @{ Value = (& $tryInfoDate 'CreationDate');     Source = 'PdfInfoDict'    },
            @{ Value = (& $tryXmp      'xmp:CreateDate');   Source = 'PdfXmp'         },
            @{ Value = (& $tryXmp      'xap:CreateDate');   Source = 'PdfXmpLegacy'   },
            @{ Value = (& $tryXmp      'pdf:CreationDate'); Source = 'PdfXmpPdfNs'    },
            @{ Value = (& $tryInfoDate 'ModDate');          Source = 'PdfInfoDictMod' },
            @{ Value = (& $tryXmp      'xmp:ModifyDate');   Source = 'PdfXmpMod'      }
        )

        $minYear = 2010
        $maxYear = (Get-Date).Year + 1

        foreach ($c in $candidates) {
            if ([string]::IsNullOrWhiteSpace($c.Value)) { continue }
            $m = [regex]::Match($c.Value, '^(\d{4})')
            if (-not $m.Success) { continue }
            $yInt = [int]$m.Groups[1].Value
            if ($yInt -ge $minYear -and $yInt -le $maxYear) {
                $r.Year     = $m.Groups[1].Value
                $r.Source   = $c.Source
                $r.RawValue = $c.Value
                break
            }
        }
    } catch {
        $r.Error = $_.Exception.Message
    }

    return [PSCustomObject]$r
}

function Initialize-YearOverrides {
    <#
    .SYNOPSIS
        Load year_overrides.csv into $Script:YearOverrides hashtable.

    .DESCRIPTION
        The year_overrides.csv file accumulates "post-download
        reclassification" decisions across runs. Each row maps a
        DeckUrl to the year/source that Phase 8's PDF-metadata
        reclassification derived from inspecting the downloaded PDF.

        Phase 5's Get-DeckYear consults this hashtable at priority 0
        (before any title / filename / og:meta heuristics) so that
        a deck which was rescued in a previous run keeps its derived
        year on the next run, instead of being routed to _undated/
        again and re-rescued (which would also incorrectly trigger
        Phase 7's WrongYearFolder anomaly).

        Loading is idempotent: missing file is fine, the hashtable
        just starts empty. Malformed rows are skipped with a warning.

        Schema of year_overrides.csv:
          DeckUrl, OriginalFilename, PlanYearFolder, ResolvedYearFolder,
          ResolvedDate, YearSource, DetectedAt
    #>
    param([Parameter(Mandatory)][string]$OverridesPath)

    $Script:YearOverrides = @{}

    if (-not (Test-Path -LiteralPath $OverridesPath)) {
        return
    }

    try {
        $rows = @(Import-Csv -LiteralPath $OverridesPath -ErrorAction Stop)
        foreach ($row in $rows) {
            if ([string]::IsNullOrWhiteSpace($row.DeckUrl) -or
                [string]::IsNullOrWhiteSpace($row.ResolvedYearFolder)) {
                continue
            }
            $Script:YearOverrides[$row.DeckUrl] = [PSCustomObject]@{
                ResolvedYearFolder = $row.ResolvedYearFolder
                YearSource         = $row.YearSource
                ResolvedDate       = $row.ResolvedDate
            }
        }
        Write-Ok ("Loaded {0} year override(s) from {1}" -f $Script:YearOverrides.Count, $OverridesPath)
    } catch {
        Write-Warn ("Failed to read overrides CSV (will treat as empty): {0}" -f $_.Exception.Message)
        $Script:YearOverrides = @{}
    }
}

function Add-YearOverride {
    <#
    .SYNOPSIS
        Append a new override row to year_overrides.csv (and update memory).

    .DESCRIPTION
        Called by Invoke-Phase8UndatedReclassify after a successful
        PDF-metadata-based rescue. The CSV is created with a header
        row on the very first call; subsequent calls append.

        We append (not rewrite) to keep the operation cheap and to
        preserve the chronological order of detections, which is
        useful for debugging "when did this deck first get rescued?".
    #>
    param(
        [Parameter(Mandatory)][string]$OverridesPath,
        [Parameter(Mandatory)][string]$DeckUrl,
        [string]$OriginalFilename = '',
        [string]$PlanYearFolder   = '',
        [Parameter(Mandatory)][string]$ResolvedYearFolder,
        [string]$ResolvedDate     = '',
        [Parameter(Mandatory)][string]$YearSource
    )

    $row = [PSCustomObject]@{
        DeckUrl            = $DeckUrl
        OriginalFilename   = $OriginalFilename
        PlanYearFolder     = $PlanYearFolder
        ResolvedYearFolder = $ResolvedYearFolder
        ResolvedDate       = $ResolvedDate
        YearSource         = $YearSource
        DetectedAt         = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
    }

    # First write creates the file with headers; subsequent appends use -Append.
    # Note: Export-Csv -Append requires PS 3.0+, which is far below our PS 5.1
    # minimum, so this is safe.
    if (Test-Path -LiteralPath $OverridesPath) {
        $row | Export-Csv -LiteralPath $OverridesPath -Encoding UTF8 -NoTypeInformation -Append
    } else {
        $row | Export-Csv -LiteralPath $OverridesPath -Encoding UTF8 -NoTypeInformation
    }

    # Update in-memory hashtable so subsequent Get-DeckYear calls in the
    # SAME run see the new entry (relevant when multiple decks get
    # rescued in one Phase 8 pass, though they don't normally collide).
    $Script:YearOverrides[$DeckUrl] = [PSCustomObject]@{
        ResolvedYearFolder = $ResolvedYearFolder
        YearSource         = $YearSource
        ResolvedDate       = $ResolvedDate
    }
}

function Get-DeckYear {
    <#
    .SYNOPSIS
        Determine the year-folder name for a deck.

    .DESCRIPTION
        Returns the 4-digit publication year (e.g., "2024") used as the
        year-subfolder name under OutputDir, or the sentinel "_undated"
        when no usable year can be derived. Phase 5 uses this to plan
        OutputFullPath = OutputDir\<YearFolder>\<filename>.

        Priority order (Judgment D2 - OriginalFilename takes precedence
        over og:meta because the embedded filename date is generally a
        better proxy for "content creation date" than the Speaker Deck
        upload date):
          0. year_overrides.csv hit (from a prior run's PDF-metadata
             rescue) - highest priority so re-runs stay consistent.
             Source: OverrideCsv. Requires -DeckUrl.
          1. OriginalFilename: YYYYMMDD (also YYYY-MM-DD, YYYY_MM_DD)
          2. PublishDate from og:meta (Phase 4): first 4 digits
          3. Title: Japanese year-suffix pattern (YYYY + U+5E74 kanji)
          4. Title: bare 4-digit year (20YY) appearing anywhere
          5. Fallback: "_undated"

        A 4-digit year is considered valid when:
          2010 <= year <= currentYear + 1
        Speaker Deck launched in 2011 (so 2010 gives a 1-year margin).
        The +1 on the upper end accommodates scheduled / post-dated
        publications.

        NOTE on non-ASCII: this file is kept strictly ASCII so we use
        the .NET regex Unicode escape \u5E74 to match the year-kanji
        instead of writing the literal character. The regex engine
        decodes the escape at match time.

        Returns a PSCustomObject with two fields:
          - Year:   "2024" or "_undated"
          - Source: which priority rule matched
                    (OverrideCsv / OriginalFilename / PublishDate /
                     TitleJp / TitleNum / Fallback)
    #>
    param(
        [string]$OriginalFilename,
        [string]$PublishDate,
        [string]$Title,
        [string]$DeckUrl
    )

    $currentYear = (Get-Date).Year
    $minYear = 2010
    $maxYear = $currentYear + 1

    # 0. year_overrides.csv hit (highest priority).
    # If the previous run's Phase 8 rescued this deck, we already know
    # the right year. Re-deriving it from title/filename/og would
    # potentially produce a different (or _undated) answer, which would
    # then trigger Phase 7's WrongYearFolder anomaly when the file is
    # found in the override's year folder. Trusting the override here
    # keeps the system idempotent across runs.
    if (-not [string]::IsNullOrEmpty($DeckUrl) -and `
        $null -ne $Script:YearOverrides -and `
        $Script:YearOverrides.ContainsKey($DeckUrl)) {
        $ov = $Script:YearOverrides[$DeckUrl]
        return [PSCustomObject]@{
            Year   = $ov.ResolvedYearFolder
            Source = 'OverrideCsv'
        }
    }

    # 1. OriginalFilename: YYYYMMDD pattern (or hyphen / underscore variants).
    # Using [regex]::Match directly instead of -match avoids the psa.py
    # PSA2003 warning about -match against a bare variable
    # (which would return true for $null on the left-hand side).
    if (-not [string]::IsNullOrEmpty($OriginalFilename)) {
        $patterns = @(
            '(?<![0-9])(20\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?![0-9])',
            '(?<![0-9])(20\d{2})[-_](0[1-9]|1[0-2])[-_](0[1-9]|[12]\d|3[01])(?![0-9])'
        )
        foreach ($pat in $patterns) {
            $m = [regex]::Match($OriginalFilename, $pat)
            if ($m.Success) {
                $y = [int]$m.Groups[1].Value
                if ($y -ge $minYear -and $y -le $maxYear) {
                    return [PSCustomObject]@{ Year = $m.Groups[1].Value; Source = 'OriginalFilename' }
                }
            }
        }
    }

    # 2. PublishDate from og:meta (YYYYMMDD)
    if (-not [string]::IsNullOrEmpty($PublishDate)) {
        $m = [regex]::Match($PublishDate, '^(\d{4})\d{4}$')
        if ($m.Success) {
            $y = [int]$m.Groups[1].Value
            if ($y -ge $minYear -and $y -le $maxYear) {
                return [PSCustomObject]@{ Year = $m.Groups[1].Value; Source = 'PublishDate' }
            }
        }
    }

    # 3. Title: Japanese year-suffix pattern (YYYY + kanji at U+5E74).
    # The \u5E74 escape lets the regex engine match the kanji while the
    # source remains pure ASCII.
    if (-not [string]::IsNullOrEmpty($Title)) {
        $m = [regex]::Match($Title, '(20\d{2})\u5E74')
        if ($m.Success) {
            $y = [int]$m.Groups[1].Value
            if ($y -ge $minYear -and $y -le $maxYear) {
                return [PSCustomObject]@{ Year = $m.Groups[1].Value; Source = 'TitleJp' }
            }
        }
    }

    # 4. Title: bare 4-digit year
    if (-not [string]::IsNullOrEmpty($Title)) {
        $m = [regex]::Match($Title, '(?<![0-9])(20\d{2})(?![0-9])')
        if ($m.Success) {
            $y = [int]$m.Groups[1].Value
            if ($y -ge $minYear -and $y -le $maxYear) {
                return [PSCustomObject]@{ Year = $m.Groups[1].Value; Source = 'TitleNum' }
            }
        }
    }

    # 5. Fallback
    return [PSCustomObject]@{ Year = '_undated'; Source = 'Fallback' }
}

function Get-OutputFilename {
    <#
        Output naming policy:
          Full form  : <title>__<original_filename>
          Short form : <title>_<YYYYMMDD>.<ext>
          (Falls back to short form when system limits are tight.)
    #>
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$OriginalFilename,
        [string]$PublishDate,                # YYYYMMDD format from per-page extraction
        [Parameter(Mandatory)] [string]$OutputDir,
        [Parameter(Mandatory)] [int]   $MaxFilenameLength,
        [Parameter(Mandatory)] [int]   $MaxFullPathLength
    )

    $safeTitle = ConvertTo-SafeFilename -InputString $Title
    $extension = [System.IO.Path]::GetExtension($OriginalFilename)
    if ([string]::IsNullOrEmpty($extension)) { $extension = ".pdf" }

    # ----- Try full form first -----
    $fullName = "${safeTitle}__${OriginalFilename}"
    $fullPath = Join-Path $OutputDir $fullName

    if ($fullName.Length -le $MaxFilenameLength -and $fullPath.Length -le $MaxFullPathLength) {
        return [PSCustomObject]@{
            Filename = $fullName
            FullPath = $fullPath
            Type     = "Full"
            Reason   = "OK"
        }
    }

    # ----- Try short form -----
    $dateStr = Get-DateFromFilename -Filename $OriginalFilename
    if (-not $dateStr -and $PublishDate) {
        $dateStr = $PublishDate
    }

    if ($dateStr) {
        $shortName = "${safeTitle}_${dateStr}${extension}"
    } else {
        $shortName = "${safeTitle}${extension}"
    }
    $shortPath = Join-Path $OutputDir $shortName

    if ($shortName.Length -le $MaxFilenameLength -and $shortPath.Length -le $MaxFullPathLength) {
        return [PSCustomObject]@{
            Filename = $shortName
            FullPath = $shortPath
            Type     = "Short"
            Reason   = "Full version exceeded limit"
        }
    }

    # ----- Truncate the title if even the short form is too long -----
    $suffixLen = if ($dateStr) { 1 + $dateStr.Length + $extension.Length } else { $extension.Length }

    $availFromName = $MaxFilenameLength - $suffixLen
    $availFromPath = $MaxFullPathLength - ($OutputDir.Length + 1) - $suffixLen
    $available     = [Math]::Min($availFromName, $availFromPath)

    if ($available -lt 10) {
        # Give up on the title and use original filename only
        return [PSCustomObject]@{
            Filename = $OriginalFilename
            FullPath = (Join-Path $OutputDir $OriginalFilename)
            Type     = "OriginalOnly"
            Reason   = "Both full/short exceeded limit"
        }
    }

    $truncTitle = $safeTitle.Substring(0, [Math]::Min($safeTitle.Length, $available))
    if ($dateStr) {
        $shortName = "${truncTitle}_${dateStr}${extension}"
    } else {
        $shortName = "${truncTitle}${extension}"
    }
    $shortPath = Join-Path $OutputDir $shortName

    return [PSCustomObject]@{
        Filename = $shortName
        FullPath = $shortPath
        Type     = "ShortTruncated"
        Reason   = "Title truncated to fit limits"
    }
}

# ============================================================
# Phase 1: Environment evaluation
# ============================================================

function Show-PowerShellEnvironment {
    <#
    .SYNOPSIS
        Dump the PowerShell execution environment for diagnostic purposes.

    .DESCRIPTION
        Emits a multi-section summary of the running PowerShell host,
        used as Phase 1 "Step 0" so that any future bug reports include
        enough context to reproduce the environment. Designed to work
        on Windows PowerShell 5.1 (the targeted baseline) all the way
        through PowerShell 7+ on Windows 10 / 11 and Windows Server
        2016 / 2019 / 2022 / 2025.

        All cmdlets used here exist in PS 5.1 / .NET Framework 4.6+,
        and Win32 OS queries fall back from CIM to WMI for the rare
        environments where CIM service is constrained (e.g. some
        Server Core or container images).

        Output is grouped into three sections:
          1) Engine and process info  - PS version, edition, CLR, bitness
          2) OS / Host / Policy info  - Caption, build, exec policy, TLS
          3) Localization info        - Culture, encoding (incl. console)
          4) Paths                    - Script path and working directory
          5) Compatibility summary    - PS 5.1+ / Edition / Bitness / OS
                                        with [+] / [!] / [X] markers

        Does not throw; even if every WMI/CIM/registry query fails it
        prints best-effort placeholders rather than aborting the phase.

    .NOTES
        Modelled on Show-PowerShellEnvironment from the AMD chipset
        deployment reference script.
    #>
    param()

    # ---- (1) Engine + process ----
    $pv = $PSVersionTable
    $editionDesc = switch ($pv.PSEdition) {
        'Desktop' { 'Windows PowerShell - shipped with Windows' }
        'Core'    { 'PowerShell 7+ / Core - separately installed' }
        default   { '(unknown edition)' }
    }
    Write-Host ('    PowerShell Version  : {0}' -f $pv.PSVersion)
    Write-Host ('    PowerShell Edition  : {0,-25} ({1})' -f $pv.PSEdition, $editionDesc)
    if ($pv.CLRVersion) {
        Write-Host ('    CLR / .NET          : {0}' -f $pv.CLRVersion)
    } else {
        Write-Host  '    CLR / .NET          : (CLRVersion not exposed; PS Core is .NET 5+ via System.Environment.Version)'
    }
    if ($pv.BuildVersion) {
        Write-Host ('    Engine Build        : {0}' -f $pv.BuildVersion)
    }

    $procBitness = if ([Environment]::Is64BitProcess) { '64-bit process' } else { '32-bit process' }
    $procArch    = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { 'unknown' }
    Write-Host ('    Process Architecture: {0,-25} ({1})' -f $procArch, $procBitness)

    # ---- (2) OS / Host / Policy ----
    $os = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    } catch {
        try {
            # Fallback for environments where CIM is constrained.
            # Get-WmiObject is deprecated in PS 7+ but available in PS 5.1.
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        } catch {
            $os = $null
        }
    }
    if ($os) {
        $caption = if ($os.Caption) { $os.Caption.Trim() } else { '(no caption)' }
        $arch    = if ($os.OSArchitecture) { $os.OSArchitecture } else { 'unknown' }
        Write-Host ('    OS                  : {0}' -f $caption)
        Write-Host ('    OS Build            : {0}' -f $os.BuildNumber)
        Write-Host ('    OS Architecture     : {0}' -f $arch)
    } else {
        $fallback = [System.Environment]::OSVersion.VersionString
        Write-Host ('    OS                  : {0} (CIM/WMI unavailable)' -f $fallback) -ForegroundColor Yellow
    }

    Write-Host ('    Host                : {0,-25} (Version {1})' -f $Host.Name, $Host.Version)

    try {
        $pCurrent = Get-ExecutionPolicy
        $pUser    = Get-ExecutionPolicy -Scope CurrentUser  -ErrorAction SilentlyContinue
        $pMachine = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue
        Write-Host ('    Execution Policy    : {0,-25} (CurrentUser: {1}, LocalMachine: {2})' -f $pCurrent, $pUser, $pMachine)
    } catch {
        Write-Host '    Execution Policy    : (query failed)' -ForegroundColor Yellow
    }

    Write-Host ('    TLS Default         : {0}' -f [Net.ServicePointManager]::SecurityProtocol)

    # ---- (3) Localization / encoding ----
    # Console OutputEncoding mismatches with Default Encoding are the
    # #1 cause of mojibake (garbled Japanese) when a Japanese filename
    # is written to a CSV. Showing both lets a user diagnose this in
    # seconds. cp65001 (UTF-8) vs cp932 (Shift-JIS) is the typical
    # combination on Japanese Windows.
    Write-Host ('    Culture             : {0,-25} UICulture: {1}' -f (Get-Culture).Name, (Get-UICulture).Name)
    $defEnc = [System.Text.Encoding]::Default
    Write-Host ('    Default Encoding    : {0,-25} (cp{1})' -f $defEnc.WebName, $defEnc.CodePage)
    Write-Host ('    Console OutputEnc.  : {0,-25} (cp{1})' -f [Console]::OutputEncoding.WebName, [Console]::OutputEncoding.CodePage)

    # ---- (4) Script / working directory ----
    $scriptPath = if (-not [string]::IsNullOrEmpty($Script:ScriptPath)) { $Script:ScriptPath } `
                  elseif ($PSCommandPath) { $PSCommandPath } `
                  else { '(unknown)' }
    Write-Host ('    Script Path         : {0}' -f $scriptPath)
    Write-Host ('    Working Directory   : {0}' -f (Get-Location).Path)

    # ---- (5) Compatibility check summary ----
    # Four-item check matching the script's hard target:
    # PowerShell 5.1+, any Edition, 64-bit process, Windows 10/11 or
    # Windows Server 2016+. Fails are shown in red so they catch the
    # eye in a long log.
    Write-Host ''
    Write-Host '    Compatibility check (target: PS 5.1+ on Windows 10/11 or Windows Server 2016+):'

    $minPs = [Version]'5.1'
    if ($pv.PSVersion -ge $minPs) {
        Write-Host ('      [+] PS 5.1+        OK    ({0} >= {1})' -f $pv.PSVersion, $minPs) -ForegroundColor Green
    } else {
        Write-Host ('      [X] PS 5.1+        FAIL  ({0} < {1})' -f $pv.PSVersion, $minPs) -ForegroundColor Red
    }

    Write-Host ('      [+] Edition        OK    ({0} - both Desktop and Core are supported)' -f $pv.PSEdition) -ForegroundColor Green

    if ([Environment]::Is64BitProcess) {
        Write-Host  '      [+] Bitness        OK    (64-bit process)' -ForegroundColor Green
    } else {
        Write-Host  '      [X] Bitness        FAIL  (32-bit process - launch the 64-bit PowerShell, not "(x86)")' -ForegroundColor Red
    }

    if ($os) {
        $supportedBuilds = @{
            14393 = 'Windows Server 2016'
            17763 = 'Windows Server 2019 / Windows 10 1809'
            19041 = 'Windows 10 2004'
            19044 = 'Windows 10 21H2'
            19045 = 'Windows 10 22H2'
            20348 = 'Windows Server 2022'
            22000 = 'Windows 11 21H2'
            22621 = 'Windows 11 22H2'
            22631 = 'Windows 11 23H2'
            26100 = 'Windows 11 24H2 / Windows Server 2025'
            26200 = 'Windows 11 (recent build)'
        }
        $build = [int]$os.BuildNumber
        if ($supportedBuilds.ContainsKey($build)) {
            Write-Host ('      [+] OS             OK    ({0} / build {1})' -f $supportedBuilds[$build], $build) -ForegroundColor Green
        } elseif ($build -ge 14393) {
            Write-Host ('      [+] OS             OK    (build {0} - newer than the lowest supported; not in known label list)' -f $build) -ForegroundColor Green
        } else {
            Write-Host ('      [!] OS             WARN  (build {0} predates Windows Server 2016; script may still work)' -f $build) -ForegroundColor Yellow
        }
    } else {
        Write-Host  '      [!] OS             WARN  (CIM/WMI both failed; could not determine OS build)' -ForegroundColor Yellow
    }
}

function Assert-PowerShellCompatibility {
    <#
    .SYNOPSIS
        Hard-fail the script early when running on an unsupported host.

    .DESCRIPTION
        Refuses to proceed when:
          - PowerShell version is below 5.1, or
          - The current process is 32-bit.

        Both conditions are categorical incompatibilities (not soft
        warnings): the script's runspace-based concurrency, .NET regex
        Unicode escapes, and large-file handling have all been validated
        only on 5.1+ / 64-bit hosts. Running on a 32-bit host or a
        pre-5.1 engine will produce silent miscompilations or hangs
        rather than honest errors, so we stop here with a clear message.

        Throws a terminating error so the script exits with non-zero
        status; downstream phases never run.
    #>
    param()

    $pv    = $PSVersionTable.PSVersion
    $minPs = [Version]'5.1'
    if ($pv -lt $minPs) {
        throw @"
This script requires PowerShell $minPs or later.
Detected: $pv

This script targets the default PowerShell included with Windows 10 /
11 and Windows Server 2016 / 2019 / 2022 / 2025, which is
PowerShell 5.1. PowerShell 7+ is NOT required, but PowerShell 5.1 is
the minimum.

If you are on Windows 7 / Windows Server 2012 R2 or earlier, install
the Windows Management Framework 5.1 update: https://aka.ms/wmf51
"@
    }
    if (-not [Environment]::Is64BitProcess) {
        throw @'
This script requires a 64-bit PowerShell process. Detected 32-bit.

On a 64-bit Windows, launch from "Windows PowerShell" (NOT "Windows
PowerShell (x86)"). 32-bit hosts may hit issues with concurrent
runspace pools and large file path operations that have only been
validated under 64-bit PowerShell.
'@
    }
}

function Test-Environment {
    param(
        [Parameter(Mandatory)] [string]$TestDir
    )

    Start-DebugTrace -Context 'Test-Environment' -PhaseId 'P01'
    try {
        # NOTE: The phase body retains its original 4-space indentation;
        # see the matching note on Invoke-Phase4Evaluation.
        Set-DebugStep 'phase header'
        Write-PhaseHeader -Id 'P01' -Name 'EnvCheck' -Group 'Setup'

    $result = [ordered]@{
        OS                 = "Unknown"
        PSVersion          = $PSVersionTable.PSVersion.ToString()
        LongPathsRegistry  = "Unknown"
        LongPathsEnabled   = $false
        TestResults        = @()
        MaxSuccessLength   = 0
        EnvironmentClass   = "Unknown"
        MaxFilenameLength  = 200
        MaxFullPathLength  = 240
    }

    # OS info (kept in $result for downstream consumers; the full
    # environment dump now happens in Step 0 via Show-PowerShellEnvironment)
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $result.OS = "$($os.Caption) ($($os.Version))"
        } else {
            $result.OS = "$([System.Environment]::OSVersion.VersionString)"
        }
    } catch {
        $result.OS = "$([System.Environment]::OSVersion.VersionString)"
    }

    # ----- Step 0 : PowerShell execution environment -----
    # Diagnostic dump of the runtime so any future bug report can be
    # reproduced. This replaces the legacy 2-line "OS / PSVersion"
    # header that this section originally carried. See Show-PowerShellEnvironment.
    Write-SubSection "[Step 0] PowerShell execution environment"
    Show-PowerShellEnvironment

    # ----- Step A : Registry check -----
    Write-SubSection "[Step A] Registry check (LongPathsEnabled)"
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        $regVal = Get-ItemProperty -Path $regPath -Name "LongPathsEnabled" -ErrorAction Stop
        if ($regVal.LongPathsEnabled -eq 1) {
            $result.LongPathsEnabled  = $true
            $result.LongPathsRegistry = "1 (enabled)"
            Write-Ok "LongPathsEnabled = 1 (enabled)"
        } else {
            $result.LongPathsRegistry = "$($regVal.LongPathsEnabled) (disabled)"
            Write-Warn "LongPathsEnabled = $($regVal.LongPathsEnabled) (disabled)"
        }
    } catch {
        $result.LongPathsRegistry = "not set (default: disabled)"
        Write-Warn "LongPathsEnabled registry value not set (default: disabled)"
    }

    # ----- Step B : Real dummy file test -----
    Write-SubSection "[Step B] Real-world dummy file test"

    $testFolder = Join-Path $TestDir ("__longpath_test_" + (Get-Date -Format 'yyyyMMddHHmmss') + "__")

    try {
        if (-not (Test-Path -LiteralPath $testFolder)) {
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null
        }
        $testFolderFull = (Resolve-Path -LiteralPath $testFolder).Path

        # Test target full-path lengths
        $testTargets = @(100, 200, 240, 260, 300, 500, 1000)

        $maxOk = 0
        foreach ($target in $testTargets) {
            # Compute the filename length needed to reach $target total
            #   total path = folder path + "\" + filename
            $baseLen = $testFolderFull.Length + 1
            $fnLen   = $target - $baseLen

            if ($fnLen -lt 10) {
                Write-Host ("  [--] Full path {0,4} chars : skipped (base path already too long)" -f $target) -ForegroundColor Gray
                continue
            }

            # NTFS filename component limit (~255 UTF-16 chars)
            $singleCompLimit = 250
            $useSubdirs = $false
            if ($fnLen -gt $singleCompLimit) {
                $useSubdirs = $true
            }

            # Reserve 4 chars for ".tmp"
            $bodyLen = if ($useSubdirs) { $singleCompLimit - 4 } else { $fnLen - 4 }
            if ($bodyLen -lt 5) { continue }

            $body = "test_a" + ("x" * ($bodyLen - 6))
            $testFile = if ($useSubdirs) {
                # Build deeper directories to add length without breaking the NTFS component limit
                $subDepth  = [Math]::Ceiling(($target - $testFolderFull.Length - $singleCompLimit) / 30.0)
                $subPath   = $testFolderFull
                for ($i = 0; $i -lt $subDepth; $i++) {
                    $subPath = Join-Path $subPath ("subdir_" + ("y" * 20))
                }
                Join-Path $subPath ("$body.tmp")
            } else {
                Join-Path $testFolderFull ("$body.tmp")
            }

            $actualLen = $testFile.Length

            try {
                # Create parent directory chain if needed.
                # NOTE: PowerShell 5.1 has a parameter-set quirk where
                # Split-Path's LiteralPathSet does NOT include -Parent,
                # so `Split-Path -LiteralPath $X -Parent` raises a
                # ParameterBindingException. Use the .NET API directly,
                # which is pure string manipulation (no wildcard expansion,
                # no filesystem access) and therefore safe for paths
                # containing '[' ']' or other wildcard characters.
                $parentDir = [System.IO.Path]::GetDirectoryName($testFile)
                if (-not (Test-Path -LiteralPath $parentDir)) {
                    New-Item -ItemType Directory -Path $parentDir -Force -ErrorAction Stop | Out-Null
                }

                # Create the file
                $null = New-Item -ItemType File -Path $testFile -Force -ErrorAction Stop

                # Delete it and continue
                Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue

                $msg = ("Full path {0,4} chars : OK (actual {1} chars)" -f $target, $actualLen)
                Write-Ok $msg
                $result.TestResults += [PSCustomObject]@{ Target = $target; Actual = $actualLen; Success = $true; Error = "" }
                if ($actualLen -gt $maxOk) { $maxOk = $actualLen }
            }
            catch {
                $errType = $_.Exception.GetType().Name
                Write-Fail ("Full path {0,4} chars : FAILED ({1})" -f $target, $errType)
                $result.TestResults += [PSCustomObject]@{ Target = $target; Actual = $actualLen; Success = $false; Error = $_.Exception.Message }
                # On first failure, stop trying longer ones
                break
            }
        }

        $result.MaxSuccessLength = $maxOk

        # ----- Step C : Decide effective limits -----
        Write-SubSection "[Step C] Effective limits"

        if ($maxOk -ge 1000) {
            $result.EnvironmentClass  = "Long-path full support"
            $result.MaxFilenameLength = 240
            $result.MaxFullPathLength = 950
        } elseif ($maxOk -ge 500) {
            $result.EnvironmentClass  = "Long-path partial support"
            $result.MaxFilenameLength = 240
            $result.MaxFullPathLength = 480
        } elseif ($maxOk -ge 260) {
            $result.EnvironmentClass  = "Standard support"
            $result.MaxFilenameLength = 200
            $result.MaxFullPathLength = 240
        } else {
            $result.EnvironmentClass  = "Strict constraints"
            $result.MaxFilenameLength = 150
            $result.MaxFullPathLength = 200
        }

        Write-Host "  Max successful length        : $maxOk chars"
        Write-Host "  Environment class            : $($result.EnvironmentClass)"
        Write-Host "  Effective fallback thresholds:"
        Write-Host "    - filename (single)        : $($result.MaxFilenameLength) chars"
        Write-Host "    - full path (total)        : $($result.MaxFullPathLength) chars"
    }
    finally {
        if (Test-Path -LiteralPath $testFolder) {
            Remove-Item -LiteralPath $testFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-PhaseFooter -Id 'P01' -Status 'done'
        return $result
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        Write-PhaseFooter -Id 'P01' -Status 'failed'
        throw
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase 2: Get total deck count
# ============================================================

function Get-TotalDeckCount {
    param([string]$AccountName)

    Start-DebugTrace -Context 'Get-TotalDeckCount' -PhaseId 'P02'
    try {
        Set-DebugStep 'phase header'
        Write-PhaseHeader -Id 'P02' -Name 'GetTotalCount' -Group 'Scan'

        $url = "$Script:BaseUrl/$AccountName"
        Write-Step "URL: $url"

        $count = 0
        $status = 'done'
        try {
            Set-DebugStep 'HTTP fetch profile page'
            $response = Invoke-WebRequestWithRetry -Uri $url -MaxRetries 3
            $content = $response.Content

            # Look for "NNN Decks" patterns (handles comma-separated thousands)
            Set-DebugStep 'regex match deck count'
            $patterns = @(
                '(\d{1,3}(?:,\d{3})*)\s+Decks',
                '(\d+)\s+Decks',
                '<span[^>]*>\s*(\d{1,3}(?:,\d{3})*)\s*</span>\s*Decks'
            )

            $found = $false
            foreach ($pattern in $patterns) {
                $m = [regex]::Match($content, $pattern)
                if ($m.Success) {
                    $countStr = $m.Groups[1].Value -replace ',', ''
                    $count = [int]$countStr
                    Write-Ok "Total deck count: $count"
                    $found = $true
                    break
                }
            }

            if (-not $found) {
                Write-Warn "Could not extract deck count (HTML structure may have changed)"
            }
        }
        catch {
            Write-Fail "Failed to fetch deck count: $($_.Exception.Message)"
            $status = 'failed'
        }

        Set-DebugStep 'phase footer'
        Write-PhaseFooter -Id 'P02' -Status $status
        return $count
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        Write-PhaseFooter -Id 'P02' -Status 'failed'
        throw
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase 3: Listing collection
# ============================================================

function Get-AllDeckList {
    param([string]$AccountName)

    Start-DebugTrace -Context 'Get-AllDeckList' -PhaseId 'P03'
    try {
        # NOTE: The phase body retains its original 4-space indentation
        # rather than being bulk-reflowed to 8 spaces inside this try
        # block; see the matching note on Invoke-Phase4Evaluation.
        Set-DebugStep 'phase header'
        Write-PhaseHeader -Id 'P03' -Name 'ListCollection' -Group 'Scan'

    $allDecks = New-Object System.Collections.ArrayList
    $seenUrls = @{}
    $page = 1
    $hasNext = $true
    $consecutiveEmptyPages = 0
    $status = 'done'

    # Slugs that exist on every profile page but are NOT decks.
    # Filter them out so they don't pollute the deck list.
    $excludeSlugs = @('collections','following','followers','stars',
                      'feed','subscribe','embed','edit','new','settings')

    while ($hasNext) {
        $url = if ($page -eq 1) {
            "$Script:BaseUrl/$AccountName"
        } else {
            "$Script:BaseUrl/${AccountName}?page=$page"
        }

        Write-Step "Fetching page ${page}: $url"

        try {
            $response = Invoke-WebRequestWithRetry -Uri $url -MaxRetries 3
            $content  = $response.Content

            $accountEsc = [regex]::Escape($AccountName)

            # ----- Primary pattern: extract href + inner text in one pass.
            # Speaker Deck's actual HTML uses <a href="/<account>/<slug>">Title</a>
            # rather than putting title="..." directly on the <a> tag, so we
            # capture the inner link text. Avatar links contain a nested <img>
            # element and therefore fail [^<]+ matching, which conveniently
            # excludes them.
            $primaryPattern = '<a[^>]*\bhref="(/' + $accountEsc + '/([^"/?#]+))"[^>]*>([^<]+)</a>'

            $pageDecks = New-Object System.Collections.ArrayList

            foreach ($m in [regex]::Matches($content, $primaryPattern)) {
                $href     = $m.Groups[1].Value
                $slug     = $m.Groups[2].Value
                $linkText = $m.Groups[3].Value.Trim()

                if ($slug -in $excludeSlugs) { continue }
                if ($href -match '\?' -or $href -match '#') { continue }

                $absUrl = "$Script:BaseUrl$href"
                if (-not $seenUrls.ContainsKey($absUrl)) {
                    $seenUrls[$absUrl] = $true
                    $title = if ([string]::IsNullOrWhiteSpace($linkText)) { $slug }
                             else { ConvertFrom-HtmlEntity -Text $linkText }
                    $deck = [PSCustomObject]@{
                        Index = ($allDecks.Count + 1)
                        Slug  = $slug
                        DeckUrl = $absUrl
                        ListingTitle = $title
                    }
                    [void]$pageDecks.Add($deck)
                    [void]$allDecks.Add($deck)
                }
            }

            # ----- Fallback pattern: when the primary fails (e.g. Speaker Deck
            # changes the link to wrap an image / icon instead of plain text),
            # match href-only and use the slug as the title. Phase 4 fetches
            # each deck page individually and pulls og:title from there, so
            # the ListingTitle here is mostly cosmetic.
            if ($pageDecks.Count -eq 0) {
                $fallbackPattern = '<a[^>]*\bhref="(/' + $accountEsc + '/([^"/?#]+))"'
                foreach ($m in [regex]::Matches($content, $fallbackPattern)) {
                    $href = $m.Groups[1].Value
                    $slug = $m.Groups[2].Value

                    if ($slug -in $excludeSlugs) { continue }
                    if ($href -match '\?' -or $href -match '#') { continue }

                    $absUrl = "$Script:BaseUrl$href"
                    if (-not $seenUrls.ContainsKey($absUrl)) {
                        $seenUrls[$absUrl] = $true
                        $deck = [PSCustomObject]@{
                            Index = ($allDecks.Count + 1)
                            Slug  = $slug
                            DeckUrl = $absUrl
                            ListingTitle = $slug
                        }
                        [void]$pageDecks.Add($deck)
                        [void]$allDecks.Add($deck)
                    }
                }
            }

            Write-Step ("page {0}: +{1} decks (cumulative {2})" -f $page, $pageDecks.Count, $allDecks.Count)

            # Diagnostic: when page 1 returns 0 decks, the HTML structure has
            # likely changed or the server returned a stripped-down response.
            # Save the raw HTML and emit detailed debug info to help diagnose.
            if ($pageDecks.Count -eq 0 -and $page -eq 1) {
                try {
                    $diagFile = Join-Path $Script:DiagDir ("speakerdeck_diag_" + $AccountName + "_" + (Get-Date -Format 'yyyyMMddHHmmss') + ".html")
                    Set-Content -Path $diagFile -Value $content -Encoding UTF8
                    Write-Warn "Page 1 returned 0 decks. HTML structure may have changed."
                    Write-Warn "Raw HTML saved to: $diagFile"

                    $contentSize  = $content.Length
                    $accountRefs  = ([regex]::Matches($content, [regex]::Escape($AccountName))).Count
                    $accountSlugs = ([regex]::Matches($content, '/' + $accountEsc + '/[a-zA-Z0-9_-]+')).Count
                    $allATags     = ([regex]::Matches($content, '<a\b')).Count
                    $titleAttrs   = ([regex]::Matches($content, '\btitle="')).Count
                    Write-Warn "  HTML size           : $contentSize chars"
                    Write-Warn "  '$AccountName' refs : $accountRefs"
                    Write-Warn "  '/$AccountName/...' : $accountSlugs (potential deck links)"
                    Write-Warn "  total <a tags       : $allATags"
                    Write-Warn "  total title= attrs  : $titleAttrs"
                    if ($accountSlugs -eq 0) {
                        Write-Warn "  -> Server returned HTML without deck slugs."
                        Write-Warn "     Likely a bot-detection / UA issue."
                    } else {
                        Write-Warn "  -> Deck slugs exist but regex did not match."
                        Write-Warn "     Inspect the saved HTML to see the new structure."
                    }
                } catch { } # psa-disable-line PSA3004 -- diagnostic stats block; failure here must not mask the original parse-failure path
            }

            if ($pageDecks.Count -eq 0) {
                $consecutiveEmptyPages++
                if ($consecutiveEmptyPages -ge 2) {
                    Write-Warn "Two consecutive empty pages -> stopping"
                    $hasNext = $false
                    break
                }
            } else {
                $consecutiveEmptyPages = 0
            }

            # Check for next page link.
            # Use negative lookahead so '?page=2' is not matched by '?page=20'.
            $nextPage = $page + 1
            $nextRegex = '\?page=' + $nextPage + '(?!\d)'
            if ([regex]::IsMatch($content, $nextRegex)) {
                $hasNext = $true
                $page = $nextPage
                Wait-WithJitter -BaseSeconds $Script:DelaySeconds -JitterRange $Script:JitterSeconds
            } else {
                $hasNext = $false
            }
        }
        catch {
            Write-Fail "Failed to fetch page ${page}: $($_.Exception.Message)"
            $status = 'failed'
            break
        }

        # Safety guard: more than 100 pages is abnormal
        if ($page -gt 100) {
            Write-Warn "Page count exceeded 100 - aborting"
            break
        }
    }

    Write-Ok "Listing complete - $($allDecks.Count) decks collected"
        Set-DebugStep 'phase footer'
        Write-PhaseFooter -Id 'P03' -Status $status
        return $allDecks
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        Write-PhaseFooter -Id 'P03' -Status 'failed'
        throw
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase 4: Per-deck evaluation
# ============================================================

function Get-DeckDetailFromPage {
    <#
        From an individual deck page extract:
          - og:title (the published title)
          - The download URL (PDF or other)
          - The original filename
          - The publish date
    #>
    param(
        [Parameter(Mandatory)] [string]$DeckUrl,
        [int]$MaxRetries = 2
    )

    $detail = [PSCustomObject]@{
        DeckUrl          = $DeckUrl
        Title            = $null
        DownloadUrl      = $null
        OriginalFilename = $null
        FileExtension    = $null
        PublishDate      = $null
        Downloadable     = $false
        Reason           = "Unknown"
    }

    try {
        $response = Invoke-WebRequestWithRetry -Uri $DeckUrl -MaxRetries $MaxRetries
        $content  = $response.Content

        # ----- og:title -----
        if ($content -match '<meta\s+property="og:title"\s+content="([^"]+)"') {
            $detail.Title = ConvertFrom-HtmlEntity -Text $matches[1]
        } elseif ($content -match '<title>([^<]+?)\s*-\s*Speaker Deck\s*</title>') {
            $detail.Title = ConvertFrom-HtmlEntity -Text $matches[1]
        }

        # ----- Download URL -----
        # files.speakerdeck.com/presentations/<UUID>/<filename>.<ext>
        $dlPattern = '(https://files\.speakerdeck\.com/presentations/[a-f0-9]+/[^"<>\s]+?\.(?:pdf|key|pptx|odp|ppt))'
        $dlMatch = [regex]::Match($content, $dlPattern)
        if ($dlMatch.Success) {
            $detail.DownloadUrl      = $dlMatch.Groups[1].Value
            # URL-decode: Speaker Deck percent-encodes non-ASCII bytes
            # in CDN filenames per RFC 3986. See Get-DecodedUrlFilename
            # for the full explanation.
            $detail.OriginalFilename = Get-DecodedUrlFilename -Url $detail.DownloadUrl
            $detail.FileExtension    = [System.IO.Path]::GetExtension($detail.OriginalFilename)
            $detail.Downloadable     = $true
            $detail.Reason           = "OK"
        } else {
            $detail.Reason = "PDF disabled (no download link)"
        }

        # ----- Publish date -----
        # <time datetime="2026-05-08T..."> or "May 08, 2026" plain text
        if ($content -match '<time[^>]*\s+datetime="([^"]+)"') {
            $detail.PublishDate = Convert-DateStringToYYYYMMDD -DateString $matches[1]
        }
        if (-not $detail.PublishDate) {
            if ($content -match '\b((?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4})\b') {
                $detail.PublishDate = Convert-DateStringToYYYYMMDD -DateString $matches[1]
            } elseif ($content -match '\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},\s+\d{4})\b') {
                $detail.PublishDate = Convert-DateStringToYYYYMMDD -DateString $matches[1]
            }
        }

        return $detail
    }
    catch {
        $detail.Reason = "Fetch error: $($_.Exception.Message)"
        return $detail
    }
}

function Invoke-Phase4Evaluation {
    <#
        Fetch every individual page with light parallelism (max 3)
        and decide whether each deck is downloadable.
    #>
    param(
        [Parameter(Mandatory)] $DeckList,
        [int]$ConcurrencyLimit = 3
    )

    Start-DebugTrace -Context 'Invoke-Phase4Evaluation' -PhaseId 'P04'
    try {
        # NOTE: This phase body was wrapped in try/catch/finally to plug
        # into the Debug Trace Facility, but the existing body content
        # retains its original 4-space indentation rather than being
        # bulk-reflowed to 8 spaces. PowerShell does not require uniform
        # indentation inside a try block; this preserves a small,
        # reviewable diff while still allowing every Set-DebugStep call
        # to be attributed to the P04 frame.
        Set-DebugStep 'phase header'
        Write-PhaseHeader -Id 'P04' -Name 'Evaluation' -Group 'Scan'
        Write-Step "Targets: $($DeckList.Count) - light concurrency $ConcurrencyLimit"

        Set-DebugStep 'create runspace pool'
        $results = New-Object System.Collections.ArrayList

        $pool = [runspacefactory]::CreateRunspacePool(1, $ConcurrencyLimit)
        $pool.Open()

    $worker = {
        param($Deck, $UserAgent, $Headers, $BaseSleepSec)

        # Local helpers (must be redefined inside each runspace)
        function ConvertFrom-HtmlEntityLocal { param([string]$Text)
            if ([string]::IsNullOrEmpty($Text)) { return $Text }
            try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
                  return [System.Web.HttpUtility]::HtmlDecode($Text)
            } catch {
                return $Text -replace '&amp;','and' -replace '&lt;','(' `
                             -replace '&gt;',')' -replace '&quot;',"'" `
                             -replace '&#39;',"'" -replace '&nbsp;',' '
            }
        }
        function Convert-DateStringToYYYYMMDDLocal { param([string]$DateString)
            if ([string]::IsNullOrEmpty($DateString)) { return $null }
            $formats = @("MMM dd, yyyy","MMMM dd, yyyy","yyyy-MM-ddTHH:mm:sszzz","yyyy-MM-ddTHH:mm:ssZ","yyyy-MM-dd","yyyy/MM/dd")
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            foreach ($fmt in $formats) {
                try { return ([DateTime]::ParseExact($DateString, $fmt, $culture)).ToString("yyyyMMdd") } catch { } # psa-disable-line PSA3004 -- ParseExact failure means format mismatch; loop tries the next format
            }
            try { return ([DateTime]::Parse($DateString, $culture)).ToString("yyyyMMdd") } catch { return $null }
        }

        $detail = [PSCustomObject]@{
            Index            = $Deck.Index
            DeckUrl          = $Deck.DeckUrl
            ListingTitle     = $Deck.ListingTitle
            Title            = $Deck.ListingTitle
            DownloadUrl      = $null
            OriginalFilename = $null
            FileExtension    = $null
            PublishDate      = $null
            Downloadable     = $false
            Reason           = "Unknown"
        }

        try {
            $resp = Invoke-WebRequest -Uri $Deck.DeckUrl `
                -UserAgent $UserAgent -Headers $Headers `
                -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
            $content = $resp.Content

            if ($content -match '<meta\s+property="og:title"\s+content="([^"]+)"') {
                $detail.Title = ConvertFrom-HtmlEntityLocal -Text $matches[1]
            }

            $dlPattern = '(https://files\.speakerdeck\.com/presentations/[a-f0-9]+/[^"<>\s]+?\.(?:pdf|key|pptx|odp|ppt))'
            $dlMatch = [regex]::Match($content, $dlPattern)
            if ($dlMatch.Success) {
                $detail.DownloadUrl      = $dlMatch.Groups[1].Value
                # Inline URL-decode: this runs inside a runspace where
                # the outer Get-DecodedUrlFilename helper is not defined.
                $rawFn = ($detail.DownloadUrl -split '/')[-1]
                try {
                    $detail.OriginalFilename = [System.Uri]::UnescapeDataString($rawFn)
                } catch {
                    $detail.OriginalFilename = $rawFn
                }
                $detail.FileExtension    = [System.IO.Path]::GetExtension($detail.OriginalFilename)
                $detail.Downloadable     = $true
                $detail.Reason           = "OK"
            } else {
                $detail.Reason = "PDF disabled (no download link)"
            }

            if ($content -match '<time[^>]*\s+datetime="([^"]+)"') {
                $detail.PublishDate = Convert-DateStringToYYYYMMDDLocal -DateString $matches[1]
            }
            if (-not $detail.PublishDate -and $content -match '\b((?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4})\b') {
                $detail.PublishDate = Convert-DateStringToYYYYMMDDLocal -DateString $matches[1]
            }
            if (-not $detail.PublishDate -and $content -match '\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},\s+\d{4})\b') {
                $detail.PublishDate = Convert-DateStringToYYYYMMDDLocal -DateString $matches[1]
            }
        }
        catch {
            $detail.Reason = "Fetch error: $($_.Exception.Message)"
        }

        # Sleep with jitter to be gentle on the server
        $jitter = Get-Random -Minimum -0.3 -Maximum 0.3
        Start-Sleep -Milliseconds ([int](([Math]::Max(0.1, $BaseSleepSec + $jitter)) * 1000))

        return $detail
    }

    # Submit every job
    $jobs = New-Object System.Collections.ArrayList
    foreach ($deck in $DeckList) {
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($worker)
        [void]$ps.AddArgument($deck)
        [void]$ps.AddArgument($Script:UserAgent)
        [void]$ps.AddArgument($Script:RequestHeaders)
        [void]$ps.AddArgument($Script:DelaySeconds)
        $handle = $ps.BeginInvoke()
        [void]$jobs.Add(@{ PS = $ps; Handle = $handle; Deck = $deck })
    }

    # Collect results with progress display
    $completed = 0
    $total = $jobs.Count
    while ($completed -lt $total) {
        $newlyDone = $jobs | Where-Object { $_.Handle.IsCompleted -and -not $_.Collected }
        foreach ($job in $newlyDone) {
            try {
                $r = $job.PS.EndInvoke($job.Handle)
                if ($r) { foreach ($x in $r) { [void]$results.Add($x) } }
            } catch {
                [void]$results.Add([PSCustomObject]@{
                    Index            = $job.Deck.Index
                    DeckUrl          = $job.Deck.DeckUrl
                    ListingTitle     = $job.Deck.ListingTitle
                    Title            = $job.Deck.ListingTitle
                    DownloadUrl      = $null
                    OriginalFilename = $null
                    PublishDate      = $null
                    Downloadable     = $false
                    Reason           = "Worker exception: $($_.Exception.Message)"
                })
            } finally {
                $job.PS.Dispose()
                $job.Collected = $true
                $completed++
            }
        }

        $pct = if ($total -gt 0) { [int](($completed / $total) * 100) } else { 0 }
        Write-Progress -Activity "Phase 4: Evaluating" `
            -Status "$completed / $total ($pct %)" `
            -PercentComplete $pct

        if ($completed -lt $total) {
            Start-Sleep -Milliseconds 200
        }
    }
    Write-Progress -Activity "Phase 4: Evaluating" -Completed

    $pool.Close()
    $pool.Dispose()

    # Sort by original index
    $sorted = $results | Sort-Object Index

    # Summary
    $okCount  = ($sorted | Where-Object { $_.Downloadable }).Count
    $ngCount  = $sorted.Count - $okCount

    $reasonGroups = $sorted | Where-Object { -not $_.Downloadable } |
        Group-Object Reason |
        Sort-Object Count -Descending

    Write-Host ""
    Write-Host (" Evaluation summary")
    Write-Host (" --------------------------------------")
    Write-Host ("  Evaluated         : {0,4}" -f $sorted.Count)
    Write-Host ("  Downloadable      : {0,4} ({1,5:F1} %)" -f $okCount, (($okCount / [Math]::Max(1, $sorted.Count)) * 100)) -ForegroundColor Green
    Write-Host ("  Not downloadable  : {0,4} ({1,5:F1} %)" -f $ngCount, (($ngCount / [Math]::Max(1, $sorted.Count)) * 100)) -ForegroundColor Yellow
    if ($reasonGroups) {
        Write-Host "  Reasons (not downloadable):"
        foreach ($g in $reasonGroups) {
            Write-Host ("       - {0,-40} : {1,4}" -f $g.Name, $g.Count)
        }
    }

        Set-DebugStep 'phase footer'
        Write-PhaseFooter -Id 'P04' -Status 'done'
        return ,@($sorted)
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        Write-PhaseFooter -Id 'P04' -Status 'failed'
        throw
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase 5: Filename plan (pre-compute output filenames)
# ============================================================
#
# Why this phase exists:
#   Earlier versions of this script computed output filenames inside the
#   download phase (Phase 6). That meant DryRun could not show what
#   files WOULD be created on disk, and real runs could not validate
#   the plan (e.g. detect duplicate target paths) before spending
#   bandwidth on actual downloads.
#
# What this phase does:
#   1. For every Downloadable item from Phase 4, call Get-OutputFilename
#      to determine the planned filename, full path, and form (Full /
#      Short / ShortTruncated / OriginalOnly).
#   2. Detect anomalies before download starts:
#        - OutputFullPath duplicates (would cause silent file loss)
#        - Path length over the environment-detected MaxFullPathLength
#   3. Persist the complete plan as work/logs/P05_filename_plan.csv.
#      Includes BOTH downloadable items (with full filename info) and
#      non-downloadable items (filename columns empty + Reason filled),
#      so this single CSV is a strict superset of P04_evaluation_log.csv.
#   4. Return the plan list. Phase 6 (Download) reads from this list
#      directly without recomputing filenames.
#
# Runs in BOTH DryRun and real-run modes.

function Invoke-Phase5FilenamePlan {
    param(
        [Parameter(Mandatory)] $EvalResults,
        [Parameter(Mandatory)] [string]$OutputDir,
        [Parameter(Mandatory)] [int]   $MaxFilenameLength,
        [Parameter(Mandatory)] [int]   $MaxFullPathLength,
        [Parameter(Mandatory)] [string]$LogDir,
        [bool] $FlatLayout = $false
    )

    Start-DebugTrace -Context 'Invoke-Phase5FilenamePlan' -PhaseId 'P05'
    try {
        # NOTE: The phase body retains its original 4-space indentation;
        # see the matching note on Invoke-Phase4Evaluation.
        Set-DebugStep 'phase header'
        Write-PhaseHeader -Id 'P05' -Name 'FilenamePlan' -Group 'Plan'
        if ($FlatLayout) {
            Write-Step ("Computing filenames for $($EvalResults.Count) items (flat layout)")
        } else {
            Write-Step ("Computing filenames for $($EvalResults.Count) items (year-folder layout)")
        }

    # Load year_overrides.csv (if it exists) into $Script:YearOverrides so
    # that Get-DeckYear can consult it at priority 0. This is what makes
    # the PDF-metadata rescue feature idempotent across runs: a deck
    # rescued in a previous run is routed directly to its resolved year
    # folder here, instead of falling back to _undated and being rescued
    # again (which would also incorrectly trigger Phase 7's
    # WrongYearFolder anomaly).
    $overridesPath = Join-Path $LogDir 'year_overrides.csv'
    Initialize-YearOverrides -OverridesPath $overridesPath

    # First pass: compute the plan for each evaluation item.
    $plan = New-Object System.Collections.ArrayList
    foreach ($e in $EvalResults) {
        if ($e.Downloadable -and $e.DownloadUrl -and $e.OriginalFilename) {
            # Determine the year-folder name. In year-folder mode the
            # effective output directory becomes OutputDir\<YearFolder>,
            # so Get-OutputFilename's max-length math automatically
            # reserves the extra characters for the subfolder.
            # DeckUrl is passed so that Get-DeckYear can consult
            # year_overrides.csv (priority 0) for decks previously
            # rescued by Phase 8's PDF-metadata reclassification.
            $yearInfo = Get-DeckYear `
                -OriginalFilename $e.OriginalFilename `
                -PublishDate      $e.PublishDate `
                -Title            $e.Title `
                -DeckUrl          $e.DeckUrl

            $yearFolder = $yearInfo.Year
            $yearSource = $yearInfo.Source

            $effectiveOutputDir = if ($FlatLayout) {
                $OutputDir
            } else {
                Join-Path $OutputDir $yearFolder
            }

            $names = Get-OutputFilename `
                -Title            $e.Title `
                -OriginalFilename $e.OriginalFilename `
                -PublishDate      $e.PublishDate `
                -OutputDir        $effectiveOutputDir `
                -MaxFilenameLength $MaxFilenameLength `
                -MaxFullPathLength $MaxFullPathLength

            $row = [PSCustomObject]@{
                Index            = $e.Index
                Title            = $e.Title
                DeckUrl          = $e.DeckUrl
                DownloadUrl      = $e.DownloadUrl
                OriginalFilename = $e.OriginalFilename
                PublishDate      = $e.PublishDate
                YearFolder       = $yearFolder
                YearSource       = $yearSource
                OutputFilename   = $names.Filename
                OutputFullPath   = $names.FullPath
                OutputType       = $names.Type
                FullPathLength   = $names.FullPath.Length
                PathOverLimit    = $false   # set in 2nd pass
                PathDuplicate    = $false   # set in 2nd pass
                Downloadable     = $true
                Reason           = $e.Reason
            }
        } else {
            # Non-downloadable item: keep it in the plan for completeness
            # (strict superset of evaluation_log.csv) but leave filename
            # fields empty.
            $row = [PSCustomObject]@{
                Index            = $e.Index
                Title            = $e.Title
                DeckUrl          = $e.DeckUrl
                DownloadUrl      = $e.DownloadUrl
                OriginalFilename = $e.OriginalFilename
                PublishDate      = $e.PublishDate
                YearFolder       = ""
                YearSource       = ""
                OutputFilename   = ""
                OutputFullPath   = ""
                OutputType       = ""
                FullPathLength   = 0
                PathOverLimit    = $false
                PathDuplicate    = $false
                Downloadable     = $false
                Reason           = $e.Reason
            }
        }
        [void]$plan.Add($row)
    }

    # Second pass: flag duplicates (OutputFullPath collisions).
    # Only Downloadable items can collide because non-downloadable ones
    # have an empty OutputFullPath.
    $pathCounts = @{}
    foreach ($row in $plan) {
        if (-not $row.Downloadable) { continue }
        $key = $row.OutputFullPath
        if ($pathCounts.ContainsKey($key)) { $pathCounts[$key]++ }
        else                                { $pathCounts[$key] = 1 }
    }
    foreach ($row in $plan) {
        if (-not $row.Downloadable) { continue }
        if ($pathCounts[$row.OutputFullPath] -gt 1) {
            $row.PathDuplicate = $true
        }
        if ($row.FullPathLength -gt $MaxFullPathLength) {
            $row.PathOverLimit = $true
        }
    }

    # Persist the plan as CSV.
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $planPath = Join-Path $LogDir "P05_filename_plan.csv"
    $plan | Export-Csv -Path $planPath -Encoding UTF8 -NoTypeInformation
    Write-Ok "Filename plan saved: $planPath"

    # ----- Plan summary + anomaly warnings -----
    $dlItems       = @($plan | Where-Object { $_.Downloadable })
    $byType        = $dlItems | Group-Object OutputType
    $skippedCount  = @($plan | Where-Object { -not $_.Downloadable }).Count
    $overLimit     = @($plan | Where-Object { $_.PathOverLimit })
    $duplicates    = @($plan | Where-Object { $_.PathDuplicate })

    $lengthStats = if ($dlItems.Count -gt 0) {
        $dlItems | Measure-Object -Property FullPathLength -Minimum -Maximum
    } else { $null }
    $minLen = if ($lengthStats) { [int]$lengthStats.Minimum } else { 0 }
    $maxLen = if ($lengthStats) { [int]$lengthStats.Maximum } else { 0 }

    Write-Host ""
    Write-Host "  Filename plan summary:"
    $shownTypes = @{}
    foreach ($g in $byType) {
        Write-Host ("    {0,-32}: {1,5}" -f $g.Name, $g.Count)
        $shownTypes[$g.Name] = $true
    }
    # Print zero-count rows for known types so the table is consistent
    foreach ($t in @('Full','Short','ShortTruncated','OriginalOnly')) {
        if (-not $shownTypes.ContainsKey($t)) {
            Write-Host ("    {0,-32}: {1,5}" -f $t, 0)
        }
    }
    Write-Host ("    {0,-32}: {1,5}" -f 'Skipped (not downloadable)', $skippedCount)
    Write-Host ""
    Write-Host "    Output path lengths:"
    Write-Host ("      min                           : {0,5} chars" -f $minLen)
    Write-Host ("      max                           : {0,5} chars" -f $maxLen)
    Write-Host ("      effective limit               : {0,5} chars" -f $MaxFullPathLength)
    Write-Host ("      over-limit count              : {0,5}" -f $overLimit.Count)
    Write-Host ("      duplicate count               : {0,5}" -f $duplicates.Count)

    # Year-folder distribution (only meaningful when -FlatLayout is OFF,
    # but still show YearSource breakdown either way for debugging the
    # year-detection logic).
    if (-not $FlatLayout) {
        $byYear   = $dlItems | Group-Object YearFolder   | Sort-Object Name
        $bySource = $dlItems | Group-Object YearSource   | Sort-Object Name
        Write-Host ""
        Write-Host "    Year-folder distribution:"
        foreach ($g in $byYear) {
            $label = if ([string]::IsNullOrEmpty($g.Name)) { '(empty)' } else { $g.Name }
            Write-Host ("      {0,-30}: {1,5}" -f $label, $g.Count)
        }
        Write-Host ""
        Write-Host "    Year-derivation source:"
        foreach ($g in $bySource) {
            $label = if ([string]::IsNullOrEmpty($g.Name)) { '(empty)' } else { $g.Name }
            Write-Host ("      {0,-30}: {1,5}" -f $label, $g.Count)
        }
    }

    # Detail listings only when anomalies exist (keeps normal runs quiet).
    if ($duplicates.Count -gt 0) {
        Write-Host ""
        Write-Warn ("{0} output paths collide (duplicate filename plan):" -f $duplicates.Count)
        # Group by path to show pairs/groups together
        $grouped = $duplicates | Group-Object OutputFullPath
        foreach ($g in $grouped) {
            Write-Warn ("  {0}" -f $g.Name)
            foreach ($r in $g.Group) {
                Write-Warn ("    [#{0,4}] {1}" -f $r.Index, $r.Title)
            }
        }
    }
    if ($overLimit.Count -gt 0) {
        Write-Host ""
        Write-Warn ("{0} output paths exceed MAX_PATH ({1}):" -f $overLimit.Count, $MaxFullPathLength)
        foreach ($r in $overLimit) {
            Write-Warn ("  [#{0,4}] FullPathLength = {1}  type={2}" -f $r.Index, $r.FullPathLength, $r.OutputType)
        }
        Write-Warn "These items may fail at download time"
    }

    Write-PhaseFooter -Id 'P05' -Status 'done'
        return ,@($plan)
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        Write-PhaseFooter -Id 'P05' -Status 'failed'
        throw
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase 6: Adaptive parallel download
# ============================================================

function Invoke-Phase6Download {
    # Takes the pre-computed filename plan from Phase 5 rather than
    # recomputing names internally. This keeps Phase 6 strictly focused
    # on download execution and decouples the naming policy from the
    # download mechanism.
    param(
        [Parameter(Mandatory)] $FilenamePlan,
        [int]$MaxConcurrency     = 5,
        [int]$InitialConcurrency = 3,
        [int]$MinConcurrency     = 1,
        [int]$MaxRetries         = 3,
        [switch]$Force
    )

    Start-DebugTrace -Context 'Invoke-Phase6Download' -PhaseId 'P06'
    try {
        # NOTE: The phase body retains its original 4-space indentation;
        # see the matching note on Invoke-Phase4Evaluation.
        # NOTE: The Runspace Pool worker scriptblock (inside this body)
        # runs in isolated runspaces and CANNOT see the script-scope
        # DebugTrace state. Set-DebugStep markers within the worker
        # would be no-ops. Per-deck failure diagnostics for the worker
        # remain handled by the existing Write-FailureDiagnostic /
        # Add-ErrorJsonlEntry pipeline (P06_errors.jsonl), which is
        # preserved unchanged.
        Set-DebugStep 'phase header'
        Write-PhaseHeader -Id 'P06' -Name 'Download' -Group 'Fetch'

    # Phase 6 consumes the plan from Phase 5. The plan can contain
    # non-downloadable rows (with empty OutputFullPath) - filter those
    # out so the runspace pool only processes real download targets.
    $downloadable = @($FilenamePlan | Where-Object {
        $_.Downloadable -and $_.DownloadUrl -and $_.OutputFullPath
    })

    Write-Step "Targets: $($downloadable.Count) - initial $InitialConcurrency / max $MaxConcurrency"

    if ($downloadable.Count -eq 0) {
        Write-Warn "No items to download"
        Write-PhaseFooter -Id 'P06' -Status 'skipped'
        return @()
    }

    # ----- Build per-item job records from the plan -----
    # Output filename / path were already computed by Phase 5. We just
    # copy them into the job record along with run-time fields that
    # Phase 5 doesn't know about (Status, Bytes, ErrorDetails, etc.).
    $jobItems = New-Object System.Collections.ArrayList
    foreach ($it in $downloadable) {
        $job = [PSCustomObject]@{
            Index            = $it.Index
            DeckUrl          = $it.DeckUrl
            Title            = $it.Title
            DownloadUrl      = $it.DownloadUrl
            OriginalFilename = $it.OriginalFilename
            PublishDate      = $it.PublishDate
            YearFolder       = $it.YearFolder
            YearSource       = $it.YearSource
            OutputFilename   = $it.OutputFilename
            OutputFullPath   = $it.OutputFullPath
            OutputType       = $it.OutputType
            Status           = "Pending"
            Bytes            = 0
            DurationMs       = 0
            ErrorMessage     = ""
            Attempts         = 0
            # Structured error info populated by the runspace worker on
            # failure. Stays $null on success. See Add-ErrorJsonlEntry
            # and Write-FailureDiagnostic.
            ErrorDetails     = $null
        }
        [void]$jobItems.Add($job)
    }

    # ----- Shared state across runspaces -----
    $sync = [hashtable]::Synchronized(@{
        CurrentConcurrency  = $InitialConcurrency
        MaxConcurrency      = $MaxConcurrency
        MinConcurrency      = $MinConcurrency
        Throttled           = $false
        ConsecSuccess       = 0
        ConsecFailure       = 0
        TotalSuccess        = 0
        TotalSkipped        = 0
        TotalFailed         = 0
        Recent429           = 0
        ThrottlePauseUntil  = [DateTime]::MinValue
        LastChangeTime      = Get-Date
        LogLines            = New-Object System.Collections.ArrayList
    })

    # ----- Download worker -----
    $worker = {
        param($Job, $Sync, $UserAgent, $MaxRetries, $Force, $BaseSleepSec, $JitterSec)

        $result = $Job
        $start = Get-Date

        try {
            # Honor any active throttle pause
            while ((Get-Date) -lt $Sync.ThrottlePauseUntil) {
                Start-Sleep -Milliseconds 500
            }

            # Skip when a non-trivial file already exists (unless -Force).
            # IMPORTANT: -LiteralPath is required because OutputFullPath
            # can contain '[' ']' (e.g. titles like "[Oracle TechNight#99]"),
            # which PowerShell otherwise interprets as wildcard character
            # classes - causing the file to silently "not be found".
            if ((-not $Force) -and (Test-Path -LiteralPath $result.OutputFullPath)) {
                $fi = Get-Item -LiteralPath $result.OutputFullPath -ErrorAction SilentlyContinue
                if ($fi -and $fi.Length -gt 1024) {
                    $result.Status = "Skipped"
                    $result.Bytes = $fi.Length
                    $result.DurationMs = ((Get-Date) - $start).TotalMilliseconds

                    [System.Threading.Monitor]::Enter($Sync)
                    try {
                        $Sync.TotalSkipped++
                        $Sync.ConsecSuccess++
                        $Sync.ConsecFailure = 0
                    } finally { [System.Threading.Monitor]::Exit($Sync) }

                    return $result
                }
            }

            # Make sure the parent directory exists.
            # PS 5.1 quirk: `Split-Path -LiteralPath ... -Parent` raises
            # ParameterBindingException because LiteralPathSet does not
            # include -Parent. Use the .NET API instead - it is pure string
            # manipulation, safe for paths with '[' ']' wildcard chars.
            $outDir = [System.IO.Path]::GetDirectoryName($result.OutputFullPath)
            if (-not (Test-Path -LiteralPath $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force -ErrorAction SilentlyContinue | Out-Null
            }

            # Retry loop
            $attempted = 0
            $success = $false
            $lastErr = $null
            $lastStatusCode = $null
            $lastResponseHeaders = $null
            $lastBodyPreview = $null
            $attemptHistory = New-Object System.Collections.ArrayList

            while ($attempted -lt $MaxRetries -and -not $success) {
                $attempted++
                $result.Attempts = $attempted

                # Declare $safeTmp before the try block so the catch
                # block can clean it up. We reset it each iteration so
                # a failed attempt's leftover doesn't persist into the
                # next attempt's cleanup.
                $safeTmp = $null

                try {
                    # Download to a .part file then rename to avoid leaving a partial file.
                    # NOTE on -LiteralPath usage below: $tmpFile and
                    # $result.OutputFullPath may contain '[' ']' chars
                    # (from titles like "[Oracle TechNight#99]"), which
                    # PowerShell otherwise treats as wildcard character
                    # classes - so every file-cmdlet call must take
                    # -LiteralPath to avoid spurious FileNotFoundException.
                    #
                    # CRITICAL: Invoke-WebRequest -OutFile does NOT support
                    # -LiteralPath in PS 5.1; the -OutFile path is internally
                    # processed via Path semantics (wildcards expanded), so
                    # passing a path containing '[' ']' triggers the
                    # FileNotFoundException seen in real-world runs:
                    #   "wildcard path ... could not be resolved to a file"
                    #   (Japanese: ja-JP localized variant of the same).
                    # The only reliable workaround is to download to a
                    # "safe" temporary path with no bracket / hash
                    # characters, then Move-Item -LiteralPath to the real
                    # destination.
                    $tmpFile = "$($result.OutputFullPath).part"

                    # Build a wildcard-free download path:
                    #   <OutputDir>\.dl_<GUID>.part
                    # The GUID has no special chars, so Invoke-WebRequest's
                    # -OutFile is safe. We move from $safeTmp to $tmpFile
                    # via Move-Item -LiteralPath, then continue with the
                    # existing rename-to-final logic.
                    $safeTmpDir  = [System.IO.Path]::GetDirectoryName($result.OutputFullPath)
                    $safeTmpName = '.dl_' + [Guid]::NewGuid().ToString('N') + '.part'
                    $safeTmp     = Join-Path $safeTmpDir $safeTmpName

                    Invoke-WebRequest -Uri $result.DownloadUrl `
                        -OutFile $safeTmp `
                        -UserAgent $UserAgent `
                        -TimeoutSec 300 `
                        -UseBasicParsing `
                        -ErrorAction Stop

                    # Move the safe-named .part file to the real .part path.
                    # Move-Item supports -LiteralPath, so '[' ']' in the
                    # destination is handled correctly here.
                    if (Test-Path -LiteralPath $tmpFile) {
                        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
                    }
                    Move-Item -LiteralPath $safeTmp -Destination $tmpFile -Force

                    # Sanity check on size
                    $fi = Get-Item -LiteralPath $tmpFile -ErrorAction Stop
                    if ($fi.Length -lt 100) {
                        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
                        throw "Downloaded file is too small ($($fi.Length) bytes)"
                    }

                    # Replace existing if any
                    if (Test-Path -LiteralPath $result.OutputFullPath) {
                        Remove-Item -LiteralPath $result.OutputFullPath -Force -ErrorAction SilentlyContinue
                    }
                    Move-Item -LiteralPath $tmpFile -Destination $result.OutputFullPath -Force

                    $result.Bytes  = $fi.Length
                    $result.Status = "Success"
                    $success = $true

                    [void]$attemptHistory.Add([PSCustomObject]@{
                        Attempt    = $attempted
                        Result     = 'Success'
                        StatusCode = 200
                        Message    = ''
                    })

                    # Update shared state on success
                    [System.Threading.Monitor]::Enter($Sync)
                    try {
                        $Sync.TotalSuccess++
                        $Sync.ConsecSuccess++
                        $Sync.ConsecFailure = 0
                        # Ramp up after 10 consecutive successes
                        if ($Sync.ConsecSuccess -ge 10 -and $Sync.CurrentConcurrency -lt $Sync.MaxConcurrency `
                            -and -not $Sync.Throttled) {
                            $Sync.CurrentConcurrency++
                            $Sync.ConsecSuccess = 0
                            $Sync.LastChangeTime = Get-Date
                            [void]$Sync.LogLines.Add("Concurrency raised to $($Sync.CurrentConcurrency)")
                        }
                        # Drop the throttled flag after 5 consecutive successes
                        if ($Sync.Throttled -and $Sync.ConsecSuccess -ge 5) {
                            $Sync.Throttled = $false
                        }
                    } finally { [System.Threading.Monitor]::Exit($Sync) }
                }
                catch {
                    $lastErr = $_
                    $lastStatusCode = $null
                    try { if ($_.Exception.Response) { $lastStatusCode = [int]$_.Exception.Response.StatusCode } } catch { } # psa-disable-line PSA3004 -- status code is diagnostic only; $lastErr drives the retry decision

                    # Capture response headers (if any) for diagnostic purposes.
                    # Each attempt overwrites the previous capture; the final
                    # attempt's data is what gets emitted in the diag file.
                    try {
                        if ($_.Exception.Response -and $_.Exception.Response.Headers) {
                            $hdrSb = New-Object System.Text.StringBuilder
                            $headers = $_.Exception.Response.Headers
                            foreach ($key in $headers.AllKeys) {
                                [void]$hdrSb.AppendLine(("{0}: {1}" -f $key, $headers[$key]))
                            }
                            $lastResponseHeaders = $hdrSb.ToString()
                        }
                    } catch { } # psa-disable-line PSA3004 -- response headers are best-effort diagnostics; never block the retry path on a header read failure

                    # Try to capture the response body. In PS 5.1 the body
                    # of an HTTP error response is usually surfaced via
                    # $_.ErrorDetails.Message. Truncate to ~2KB to keep
                    # the diag file readable.
                    try {
                        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                            $bp = $_.ErrorDetails.Message
                            if ($bp.Length -gt 2048) {
                                $bp = $bp.Substring(0, 2048) + '...(truncated)'
                            }
                            $lastBodyPreview = $bp
                        }
                    } catch { } # psa-disable-line PSA3004 -- body preview is best-effort diagnostics; never block the retry path on a body read failure

                    # Clean up the temp file (may carry wildcard-ish chars
                    # in OutputFullPath, so -LiteralPath is required).
                    $partPath = "$($result.OutputFullPath).part"
                    if (Test-Path -LiteralPath $partPath) {
                        Remove-Item -LiteralPath $partPath -Force -ErrorAction SilentlyContinue
                    }
                    # Also clean up the safe-named .part if it still exists
                    # (Invoke-WebRequest may have created it before failing,
                    # or we failed between -OutFile and the Move-Item to
                    # $tmpFile). $safeTmp has no special chars so plain
                    # Test-Path / Remove-Item would also work, but we use
                    # -LiteralPath for consistency.
                    if ($safeTmp -and (Test-Path -LiteralPath $safeTmp)) {
                        Remove-Item -LiteralPath $safeTmp -Force -ErrorAction SilentlyContinue
                    }

                    [void]$attemptHistory.Add([PSCustomObject]@{
                        Attempt    = $attempted
                        Result     = 'Failed'
                        StatusCode = $lastStatusCode
                        Message    = $_.Exception.Message
                    })

                    if ($lastStatusCode -eq 429) {
                        # 429 -> aggressive throttle
                        [System.Threading.Monitor]::Enter($Sync)
                        try {
                            $Sync.Recent429++
                            $Sync.ConsecFailure++
                            $Sync.ConsecSuccess = 0
                            $newC = [Math]::Max($Sync.MinConcurrency, [int][Math]::Ceiling($Sync.CurrentConcurrency / 2.0))
                            if ($newC -lt $Sync.CurrentConcurrency) {
                                $Sync.CurrentConcurrency = $newC
                                [void]$Sync.LogLines.Add("HTTP 429 -> concurrency lowered to $newC")
                            }
                            $Sync.Throttled = $true
                            $Sync.ThrottlePauseUntil = (Get-Date).AddSeconds(60)
                        } finally { [System.Threading.Monitor]::Exit($Sync) }

                        Start-Sleep -Seconds 60
                    }
                    elseif ($lastStatusCode -in 500,502,503,504) {
                        # 5xx -> step down concurrency, exponential backoff
                        [System.Threading.Monitor]::Enter($Sync)
                        try {
                            $Sync.ConsecFailure++
                            $Sync.ConsecSuccess = 0
                            if ($Sync.CurrentConcurrency -gt $Sync.MinConcurrency) {
                                $Sync.CurrentConcurrency--
                                [void]$Sync.LogLines.Add("HTTP $lastStatusCode -> concurrency lowered to $($Sync.CurrentConcurrency)")
                            }
                            # Emergency brake after 3 consecutive failures
                            if ($Sync.ConsecFailure -ge 3) {
                                $Sync.CurrentConcurrency = $Sync.MinConcurrency
                                $Sync.Throttled = $true
                                $Sync.ThrottlePauseUntil = (Get-Date).AddSeconds(90)
                                [void]$Sync.LogLines.Add("Emergency brake: concurrency forced to min, sleeping 90 sec")
                            }
                        } finally { [System.Threading.Monitor]::Exit($Sync) }
                        Start-Sleep -Seconds ([int][Math]::Pow(2, $attempted) * 2)
                    }
                    else {
                        # Other errors
                        Start-Sleep -Seconds ([int][Math]::Pow(2, $attempted))
                    }
                }
            }

            if (-not $success) {
                $result.Status = "Failed"

                # Build the structured ErrorDetails payload that the main
                # thread consumes to write diag/<n>_<slug>.txt and the
                # errors.jsonl entry. PSCustomObjects round-trip cleanly
                # across runspaces in PS 5.1.
                $innerType = $null
                $innerMsg  = $null
                if ($lastErr -and $lastErr.Exception.InnerException) {
                    $innerType = $lastErr.Exception.InnerException.GetType().FullName
                    $innerMsg  = $lastErr.Exception.InnerException.Message
                }

                $errTypeName = if ($lastErr) { $lastErr.Exception.GetType().FullName } else { 'Unknown' }
                $errMsg      = if ($lastErr) { $lastErr.Exception.Message }            else { 'Unknown error' }
                $stack       = if ($lastErr) { $lastErr.ScriptStackTrace }             else { $null }

                $result.ErrorDetails = [PSCustomObject]@{
                    LastStatusCode      = $lastStatusCode
                    LastErrorType       = $errTypeName
                    LastErrorMessage    = $errMsg
                    InnerErrorType      = $innerType
                    InnerErrorMessage   = $innerMsg
                    ResponseHeaders     = $lastResponseHeaders
                    ResponseBodyPreview = $lastBodyPreview
                    StackTrace          = $stack
                    AttemptHistory      = $attemptHistory.ToArray()
                }

                if ($lastErr) {
                    $result.ErrorMessage = $lastErr.Exception.Message
                    if ($lastStatusCode) { $result.ErrorMessage = "HTTP $lastStatusCode : " + $result.ErrorMessage }
                } else {
                    $result.ErrorMessage = "Unknown error"
                }
                [System.Threading.Monitor]::Enter($Sync)
                try {
                    $Sync.TotalFailed++
                    $Sync.ConsecFailure++
                    $Sync.ConsecSuccess = 0
                } finally { [System.Threading.Monitor]::Exit($Sync) }
            }

            # Light per-download sleep with jitter
            $jitter = Get-Random -Minimum (-$JitterSec) -Maximum $JitterSec
            $sleep = [Math]::Max(0.1, $BaseSleepSec + $jitter)
            Start-Sleep -Milliseconds ([int]($sleep * 1000))
        }
        catch {
            $result.Status = "Failed"
            $result.ErrorMessage = "Worker exception: $($_.Exception.Message)"
        }

        $result.DurationMs = ((Get-Date) - $start).TotalMilliseconds
        return $result
    }

    # ----- Build the runspace pool -----
    # The pool is fixed at MaxConcurrency. The effective concurrency is
    # controlled by how fast the main thread submits jobs.
    $pool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrency)
    $pool.Open()

    $jobs = New-Object System.Collections.ArrayList
    $queue = [System.Collections.Queue]::new()
    foreach ($j in $jobItems) { $queue.Enqueue($j) }

    $finished = New-Object System.Collections.ArrayList
    $totalCount = $jobItems.Count
    $startedAll = Get-Date

    # ----- Submit + collect loop -----
    while ($queue.Count -gt 0 -or ($jobs | Where-Object { -not $_.Collected })) {
        # Reap finished jobs
        foreach ($job in @($jobs | Where-Object { (-not $_.Collected) -and $_.Handle.IsCompleted })) {
            try {
                $r = $job.PS.EndInvoke($job.Handle)
                if ($r) {
                    foreach ($x in $r) {
                        [void]$finished.Add($x)

                        # Real-time failure handling:
                        #   1. Emit a red one-liner so the user sees failures
                        #      as they happen, not just in the final summary.
                        #   2. Persist a detailed per-failure diag dump.
                        #   3. Append a structured JSONL record.
                        # All of this runs on the main thread, so there is
                        # no concurrent-write concern for the JSONL file.
                        if ($x.Status -eq 'Failed') {
                            $cat  = Get-FailureCategory -Item $x
                            $slug = ($x.DeckUrl -split '/')[-1]
                            _LogLine '[X]' (' [#{0,4}] Failed ({1}): {2}' -f $x.Index, $cat, $slug) 'Red'
                            Write-FailureDiagnostic -Item $x
                            Add-ErrorJsonlEntry      -Item $x
                        }
                    }
                }
            } catch {
                $job.Item.Status = "Failed"
                $job.Item.ErrorMessage = "Worker reaping error: $($_.Exception.Message)"
                [void]$finished.Add($job.Item)

                # Reaping itself failed (e.g. runspace bug). Still emit
                # the diag entry so the failure leaves an audit trail.
                _LogLine '[X]' (' [#{0,4}] Reaping error: {1}' -f $job.Item.Index, $_.Exception.Message) 'Red'
                Write-FailureDiagnostic -Item $job.Item
                Add-ErrorJsonlEntry      -Item $job.Item
            } finally {
                $job.PS.Dispose()
                $job.Collected = $true
            }
        }

        # Submit while under the current concurrency target and not paused
        $running = ($jobs | Where-Object { -not $_.Collected }).Count
        while ($queue.Count -gt 0 -and $running -lt $sync.CurrentConcurrency `
               -and (Get-Date) -ge $sync.ThrottlePauseUntil) {

            $item = $queue.Dequeue()

            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($worker)
            [void]$ps.AddArgument($item)
            [void]$ps.AddArgument($sync)
            [void]$ps.AddArgument($Script:UserAgent)
            [void]$ps.AddArgument($MaxRetries)
            [void]$ps.AddArgument($Force.IsPresent)
            [void]$ps.AddArgument($Script:DelaySeconds)
            [void]$ps.AddArgument($Script:JitterSeconds)

            $handle = $ps.BeginInvoke()
            [void]$jobs.Add(@{ PS = $ps; Handle = $handle; Item = $item; Collected = $false })

            $running++
        }

        # Progress display
        $doneCnt = $finished.Count
        $pct = if ($totalCount -gt 0) { [int](($doneCnt / $totalCount) * 100) } else { 0 }
        $eta = "--"
        if ($doneCnt -gt 0) {
            $elapsedSec = ((Get-Date) - $startedAll).TotalSeconds
            $rate = $doneCnt / [Math]::Max(0.1, $elapsedSec)
            $remaining = $totalCount - $doneCnt
            $etaSec = $remaining / [Math]::Max(0.001, $rate)
            $eta = ([TimeSpan]::FromSeconds($etaSec)).ToString("hh\:mm\:ss")
        }

        $statusMsg = ("OK {0} / Skip {1} / Fail {2} / Conc {3}" -f `
            $sync.TotalSuccess, $sync.TotalSkipped, $sync.TotalFailed, $sync.CurrentConcurrency)

        Write-Progress -Activity "Phase 6: Downloading" `
            -Status "$doneCnt / $totalCount ($pct %) - ETA $eta - $statusMsg" `
            -PercentComplete $pct

        # Drain inline log messages
        if ($sync.LogLines.Count -gt 0) {
            [System.Threading.Monitor]::Enter($sync)
            try {
                while ($sync.LogLines.Count -gt 0) {
                    $msg = $sync.LogLines[0]
                    $sync.LogLines.RemoveAt(0)
                    Write-Host "    [INFO] $msg" -ForegroundColor DarkCyan
                }
            } finally { [System.Threading.Monitor]::Exit($sync) }
        }

        if ($queue.Count -eq 0 -and ($jobs | Where-Object { -not $_.Collected }).Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 250
    }

    Write-Progress -Activity "Phase 6: Downloading" -Completed

    $pool.Close()
    $pool.Dispose()

    Write-PhaseFooter -Id 'P06' -Status 'done'
        return ,@($finished | Sort-Object Index)
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        Write-PhaseFooter -Id 'P06' -Status 'failed'
        throw
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase 7: Reconciliation (plan vs download log vs disk inventory)
# ============================================================
#
# Joins three data sources into one consolidated CSV so a human (or a
# follow-up automation) can answer questions like "did everything I
# planned to download actually end up on disk, at the right size?".
#
# Inputs:
#   $Plan            -- the full plan from Phase 5 (one row per evaluated deck)
#   $DownloadResults -- the per-deck outcomes from Phase 6
#   $OutputDir       -- directory to scan with Get-ChildItem -Recurse
#   $LogDir          -- where to write P07_final_state.csv
#
# Output:
#   work\logs\P07_final_state.csv with the columns documented below.
#   Returns the reconciled list of PSCustomObjects (for callers that
#   want to do further processing).
#
# Skipped in DryRun: no download happened, so the disk inventory would
# be empty by design.

function Invoke-Phase7Reconciliation {
    param(
        [Parameter(Mandatory)] $Plan,
        [Parameter(Mandatory)] $DownloadResults,
        [Parameter(Mandatory)] [string]$OutputDir,
        [Parameter(Mandatory)] [string]$LogDir
    )

    Start-DebugTrace -Context 'Invoke-Phase7Reconciliation' -PhaseId 'P07'
    try {
        # NOTE: The phase body retains its original 4-space indentation;
        # see the matching note on Invoke-Phase4Evaluation.
        Set-DebugStep 'phase header'
        Write-PhaseHeader -Id 'P07' -Name 'Reconciliation' -Group 'Verify'
        Write-Step "Joining plan / download log / disk inventory"

    # ----- Helper: extract the year-folder component from a full path.
    # E.g. "D:\downloads\2024\foo.pdf" relative to OutputDir "D:\downloads"
    # returns "2024". For files directly under OutputDir (flat layout)
    # returns "(flat)". Used to populate PlanYearFolder / DiskYearFolder
    # and to detect WrongYearFolder anomalies.
    $normalizedOutputDir = $OutputDir.TrimEnd('\','/')
    function _ExtractYearFolder([string]$FullPath) {
        if ([string]::IsNullOrEmpty($FullPath)) { return '' }
        if (-not $FullPath.StartsWith($normalizedOutputDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            return ''
        }
        $rel = $FullPath.Substring($normalizedOutputDir.Length).TrimStart('\','/')
        if ($rel -match '^([^\\/]+)[\\/]') { return $matches[1] }
        return '(flat)'
    }

    # ----- Build lookup maps from Plan and DownloadResults -----
    # OutputFullPath is the join key, since it is the unique location
    # on disk for each planned item.
    $dlByIndex = @{}
    foreach ($r in $DownloadResults) {
        if ($null -ne $r.Index) { $dlByIndex[[int]$r.Index] = $r }
    }

    $planPathSet = @{}
    foreach ($p in $Plan) {
        if ($p.OutputFullPath) { $planPathSet[$p.OutputFullPath] = $true }
    }

    # ----- Disk scan -----
    $diskFiles = @()
    if (Test-Path -LiteralPath $OutputDir) {
        try {
            $diskFiles = @(Get-ChildItem -LiteralPath $OutputDir -Recurse -File -Force -ErrorAction SilentlyContinue)
        } catch {
            Write-Warn "Disk scan failed: $($_.Exception.Message)"
        }
    }
    $diskByPath = @{}
    $diskByFilename = @{}     # filename -> list of FileInfo (for WrongYearFolder lookup)
    foreach ($f in $diskFiles) {
        $diskByPath[$f.FullName] = $f
        if (-not $diskByFilename.ContainsKey($f.Name)) {
            $diskByFilename[$f.Name] = New-Object System.Collections.ArrayList
        }
        [void]$diskByFilename[$f.Name].Add($f)
    }
    # Files that we attribute to a Plan row via WrongYearFolder detection.
    # These should NOT later be reported as UnexpectedFileOnDisk.
    $consumedByWrongYear = @{}

    $totalDiskBytes = ($diskFiles | Measure-Object -Property Length -Sum).Sum
    $totalDiskMb    = if ($totalDiskBytes) { $totalDiskBytes / 1MB } else { 0 }
    Write-Step ("Disk scan: {0} files in {1} ({2:N1} MB)" -f $diskFiles.Count, $OutputDir, $totalDiskMb)

    # ----- Reconcile each Plan row -----
    $final = New-Object System.Collections.ArrayList
    foreach ($p in $Plan) {
        $dl       = if ($null -ne $p.Index -and $dlByIndex.ContainsKey([int]$p.Index)) { $dlByIndex[[int]$p.Index] } else { $null }
        $fileInfo = if ($p.OutputFullPath -and $diskByPath.ContainsKey($p.OutputFullPath)) { $diskByPath[$p.OutputFullPath] } else { $null }

        # WrongYearFolder detection: if the planned file is not at the
        # expected path but another file with the same filename exists
        # at a different year folder under OutputDir, treat the disk file
        # as the "actual" location and flag this as an anomaly.
        $wrongYearFile = $null
        if (-not $fileInfo -and $p.Downloadable -and $p.OutputFilename) {
            if ($diskByFilename.ContainsKey($p.OutputFilename)) {
                foreach ($candidate in $diskByFilename[$p.OutputFilename]) {
                    if ($candidate.FullName -ne $p.OutputFullPath -and
                        -not $consumedByWrongYear.ContainsKey($candidate.FullName)) {
                        $wrongYearFile = $candidate
                        $consumedByWrongYear[$candidate.FullName] = $true
                        break
                    }
                }
            }
        }

        $dlStatus  = if ($dl) { $dl.Status }       else { 'NotAttempted' }
        $dlAttempts = if ($dl) { [int]$dl.Attempts } else { 0 }
        $dlMs       = if ($dl) { [int]$dl.DurationMs } else { 0 }
        $dlBytes    = if ($dl) { [int64]$dl.Bytes } else { 0 }
        $dlCategory = if ($dl -and $dl.Status -eq 'Failed') { (Get-FailureCategory -Item $dl) } else { '' }
        $dlErrMsg   = if ($dl) { $dl.ErrorMessage } else { '' }

        $fileExists  = ($null -ne $fileInfo)
        $actualBytes = if ($fileInfo) { [int64]$fileInfo.Length } else { 0 }
        $actualMb    = if ($fileInfo) { '{0:N2}' -f ($fileInfo.Length / 1MB) } else { '' }
        $actualMtime = if ($fileInfo) { $fileInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }

        $sizeMatch = if (-not $fileExists -or $dlBytes -eq 0) { '' }
                     else { ($actualBytes -eq $dlBytes).ToString() }

        $planYearFolder = if ($p.PSObject.Properties['YearFolder']) { $p.YearFolder } else { '' }
        $diskYearFolder = ''
        if ($fileInfo) {
            $diskYearFolder = _ExtractYearFolder $fileInfo.FullName
        } elseif ($wrongYearFile) {
            $diskYearFolder = _ExtractYearFolder $wrongYearFile.FullName
        }

        # ----- Discrepancy classification -----
        # WrongYearFolder takes precedence over other "missing" classifications
        # when a same-named file exists at a different year subfolder.
        $disc = 'OK'
        if (-not $p.Downloadable) {
            $disc = 'NotAttempted-NotDownloadable'
        }
        elseif ($null -ne $wrongYearFile) {
            $disc = 'WrongYearFolder'
        }
        elseif ($dlStatus -eq 'Success' -and $fileExists -and ($actualBytes -eq $dlBytes)) {
            $disc = 'OK'
        }
        elseif ($dlStatus -eq 'Skipped' -and $fileExists) {
            $disc = 'OK-Skipped'
        }
        elseif ($dlStatus -eq 'Success' -and (-not $fileExists)) {
            $disc = 'MissingAfterSuccess'
        }
        elseif ($dlStatus -eq 'Success' -and $fileExists -and ($actualBytes -ne $dlBytes)) {
            $disc = 'SizeMismatch'
        }
        elseif ($dlStatus -eq 'Failed' -and (-not $fileExists)) {
            $disc = 'FailedAsExpected'
        }
        elseif ($dlStatus -eq 'Failed' -and $fileExists) {
            $disc = 'FailedButFileExists'
        }
        elseif ($dlStatus -eq 'NotAttempted') {
            $disc = 'NotAttempted'
        }
        else {
            $disc = ('Other (' + $dlStatus + ')')
        }

        $row = [PSCustomObject]@{
            Index                 = $p.Index
            Discrepancy           = $disc
            Title                 = $p.Title
            PlanDownloadable      = $p.Downloadable
            DownloadStatus        = $dlStatus
            FileExists            = $fileExists
            SizeMatch             = $sizeMatch
            DownloadBytes         = $dlBytes
            ActualBytes           = $actualBytes
            ActualSizeMB          = $actualMb
            ActualLastWriteTime   = $actualMtime
            DownloadAttempts      = $dlAttempts
            DownloadDurationMs    = $dlMs
            PathOverLimit         = $p.PathOverLimit
            PathDuplicate         = $p.PathDuplicate
            OutputType            = $p.OutputType
            OutputFilename        = $p.OutputFilename
            FullPathLength        = $p.FullPathLength
            PublishDate           = $p.PublishDate
            OriginalFilename      = $p.OriginalFilename
            PlanYearFolder        = $planYearFolder
            DiskYearFolder        = $diskYearFolder
            DownloadErrorCategory = $dlCategory
            DownloadErrorMessage  = $dlErrMsg
            DeckUrl               = $p.DeckUrl
            DownloadUrl           = $p.DownloadUrl
            OutputFullPath        = $p.OutputFullPath
        }
        [void]$final.Add($row)
    }

    # ----- Append "extra files" rows (files on disk not in plan) -----
    # These could be leftovers from a previous run (when -Clean was not
    # used), .part files from interrupted downloads, or anything the
    # user dropped into the folder manually. Files that have already
    # been attributed to a Plan row via WrongYearFolder detection are
    # skipped here to avoid double counting.
    $extraRows = New-Object System.Collections.ArrayList
    foreach ($f in $diskFiles) {
        if ($planPathSet.ContainsKey($f.FullName)) { continue }
        if ($consumedByWrongYear.ContainsKey($f.FullName)) { continue }

        $isPart = $f.Extension -eq '.part' -or $f.Name.EndsWith('.part')
        $disc   = if ($isPart) { 'PartialDownload' } else { 'UnexpectedFileOnDisk' }

        $row = [PSCustomObject]@{
            Index                 = '(extra)'
            Discrepancy           = $disc
            Title                 = ''
            PlanDownloadable      = $false
            DownloadStatus        = 'NotPlanned'
            FileExists            = $true
            SizeMatch             = ''
            DownloadBytes         = 0
            ActualBytes           = [int64]$f.Length
            ActualSizeMB          = '{0:N2}' -f ($f.Length / 1MB)
            ActualLastWriteTime   = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            DownloadAttempts      = 0
            DownloadDurationMs    = 0
            PathOverLimit         = $false
            PathDuplicate         = $false
            OutputType            = ''
            OutputFilename        = $f.Name
            FullPathLength        = $f.FullName.Length
            PublishDate           = ''
            OriginalFilename      = ''
            PlanYearFolder        = ''
            DiskYearFolder        = (_ExtractYearFolder $f.FullName)
            DownloadErrorCategory = ''
            DownloadErrorMessage  = ''
            DeckUrl               = ''
            DownloadUrl           = ''
            OutputFullPath        = $f.FullName
        }
        [void]$extraRows.Add($row)
    }
    foreach ($r in $extraRows) { [void]$final.Add($r) }

    # ----- Persist final_state.csv -----
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $finalPath = Join-Path $LogDir "P07_final_state.csv"
    $final | Export-Csv -Path $finalPath -Encoding UTF8 -NoTypeInformation
    Write-Ok "final_state.csv saved: $finalPath"

    # ----- Reconciliation summary -----
    $byDisc = $final | Group-Object Discrepancy
    $counts = @{}
    foreach ($g in $byDisc) { $counts[$g.Name] = $g.Count }
    function _RC { param([string]$Name) if ($counts.ContainsKey($Name)) { $counts[$Name] } else { 0 } }

    $plannedCount  = @($Plan).Count
    $okCount       = _RC 'OK'
    $okSkipCount   = _RC 'OK-Skipped'
    $failedExpect  = _RC 'FailedAsExpected'
    $notAttempted  = (_RC 'NotAttempted') + (_RC 'NotAttempted-NotDownloadable')
    $missingAfter  = _RC 'MissingAfterSuccess'
    $sizeMismatch  = _RC 'SizeMismatch'
    $failedButFile = _RC 'FailedButFileExists'
    $wrongYear     = _RC 'WrongYearFolder'
    $unexpected    = _RC 'UnexpectedFileOnDisk'
    $partial       = _RC 'PartialDownload'

    $anomalyCount  = $missingAfter + $sizeMismatch + $failedButFile + $wrongYear + $unexpected + $partial

    Write-Host ""
    Write-Host "  Reconciliation summary:"
    Write-Host ("    Planned items                   : {0,5}" -f $plannedCount)
    Write-Host ("      OK (downloaded + verified)    : {0,5}" -f $okCount) -ForegroundColor Green
    Write-Host ("      OK-Skipped (already existed)  : {0,5}" -f $okSkipCount) -ForegroundColor Green
    Write-Host ("      FailedAsExpected              : {0,5}" -f $failedExpect)
    Write-Host ("      NotAttempted                  : {0,5}" -f $notAttempted)
    $a1col = if ($missingAfter -gt 0) { 'Yellow' } else { 'Gray' }
    $a2col = if ($sizeMismatch -gt 0) { 'Yellow' } else { 'Gray' }
    $a3col = if ($failedButFile -gt 0) { 'Yellow' } else { 'Gray' }
    $a4col = if ($wrongYear -gt 0)     { 'Yellow' } else { 'Gray' }
    Write-Host ("      MissingAfterSuccess           : {0,5}  *" -f $missingAfter) -ForegroundColor $a1col
    Write-Host ("      SizeMismatch                  : {0,5}  *" -f $sizeMismatch) -ForegroundColor $a2col
    Write-Host ("      FailedButFileExists           : {0,5}  *" -f $failedButFile) -ForegroundColor $a3col
    Write-Host ("      WrongYearFolder               : {0,5}  *" -f $wrongYear)    -ForegroundColor $a4col
    Write-Host ("    Extra files on disk             : {0,5}" -f ($unexpected + $partial))
    $b1col = if ($unexpected -gt 0) { 'Yellow' } else { 'Gray' }
    $b2col = if ($partial -gt 0) { 'Yellow' } else { 'Gray' }
    Write-Host ("      UnexpectedFileOnDisk          : {0,5}  *" -f $unexpected) -ForegroundColor $b1col
    Write-Host ("      PartialDownload (.part)       : {0,5}  *" -f $partial) -ForegroundColor $b2col
    Write-Host ""
    Write-Host "    (* = anomalies requiring investigation if non-zero)"
    if ($anomalyCount -gt 0) {
        Write-Warn ("Anomalies detected: {0} item(s). Inspect {1} for details." -f $anomalyCount, $finalPath)
    }

    Write-PhaseFooter -Id 'P07' -Status 'done'
        return ,@($final)
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        Write-PhaseFooter -Id 'P07' -Status 'failed'
        throw
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase 8: PDF-metadata reclassification of _undated files
# ============================================================
#
# Runs between Phase 7 (Reconciliation) and Phase 9 (FinalReport).
# Phase 7 inspects the disk state assuming the plan is authoritative;
# this phase USES that disk state and the plan as input, then
# RECLASSIFIES files that landed in _undated/ by inspecting PDF
# metadata (Info Dictionary /CreationDate, XMP packet, etc).
#
# Why this is a separate phase instead of integrated into Phase 5 or
# Phase 6:
#   - Phase 5 has no access to file content (it only plans names)
#   - Phase 6 is per-worker parallel; reading PDF metadata there would
#     complicate the worker scriptblock and slow the download path
#   - Phase 7 is supposed to be read-only verification; moving files
#     during reconciliation would mix concerns
# Doing it as its own phase keeps responsibilities clean and lets
# us run it conditionally (-SkipPdfReclassification).
#
# Idempotency:
#   On the next run, Phase 5 sees year_overrides.csv and routes the
#   rescued decks DIRECTLY to their resolved year folder (priority 0
#   in Get-DeckYear), so this phase finds nothing to do.

function Invoke-Phase8UndatedReclassify {
    <#
    .SYNOPSIS
        Move successfully-downloaded _undated files to year folders
        derived from their PDF metadata.

    .DESCRIPTION
        For every plan item whose YearFolder is "_undated" and whose
        download succeeded, this function:
          1. Reads the PDF metadata via Get-PdfMetadata (pure regex,
             no external dependencies).
          2. If a valid year (2010..currentYear+1) is found:
             a. Moves the file from OutputDir\_undated\<filename>
                to OutputDir\<year>\<filename>
                (creating the year folder if needed)
             b. Updates the plan item's YearFolder, YearSource and
                OutputFullPath fields in-memory
             c. Updates the matching download result's OutputFullPath
                in-memory so Phase 9 sees the rescued location
             d. Appends a row to year_overrides.csv so the NEXT run's
                Phase 5 routes this deck to the correct folder via
                Get-DeckYear priority 0
          3. If no valid year is found, leaves the file in _undated/.

        Returns a stats object the caller can show in the final report.

        SAFETY:
          - Only operates on successfully-downloaded files
          - Only moves WITHIN OutputDir (never deletes, never
            crosses the workspace boundary)
          - Skipped entirely when -SkipPdfReclassification is set,
            in DryRun mode, or in -FlatLayout mode (no year folders
            to rescue to)
          - Move-Item failures are logged but do not abort the phase
    #>
    param(
        [Parameter(Mandatory)] $Plan,
        [Parameter(Mandatory)] $DownloadResults,
        [Parameter(Mandatory)] [string]$OutputDir,
        [Parameter(Mandatory)] [string]$LogDir,
        [bool] $FlatLayout            = $false,
        [bool] $SkipReclassification  = $false,
        [bool] $IsDryRun              = $false
    )

    Start-DebugTrace -Context 'Invoke-Phase8UndatedReclassify' -PhaseId 'P08'
    try {
        # NOTE: The phase body retains its original 4-space indentation;
        # see the matching note on Invoke-Phase4Evaluation.
        Set-DebugStep 'phase header'
        Write-PhaseHeader -Id 'P08' -Name 'UndatedReclassify' -Group 'Verify'

    $stats = [ordered]@{
        Examined         = 0
        RescuedCount     = 0
        FailedToRead     = 0
        NoUsableMetadata = 0
        FailedToMove     = 0
        BySource         = @{}
    }

    if ($SkipReclassification) {
        Write-Skip 'PDF reclassification phase intentionally skipped (-SkipPdfReclassification)'
        Write-PhaseFooter -Id 'P08' -Status 'skipped'
        Stop-DebugTrace -Outcome 'cancelled'
        return [PSCustomObject]$stats
    }
    if ($IsDryRun) {
        Write-Skip 'DryRun mode: PDF reclassification phase intentionally skipped (no files on disk)'
        Write-PhaseFooter -Id 'P08' -Status 'skipped'
        Stop-DebugTrace -Outcome 'cancelled'
        return [PSCustomObject]$stats
    }
    if ($FlatLayout) {
        Write-Skip 'FlatLayout mode: PDF reclassification phase intentionally skipped (no year folders)'
        Write-PhaseFooter -Id 'P08' -Status 'skipped'
        Stop-DebugTrace -Outcome 'cancelled'
        return [PSCustomObject]$stats
    }

    # Build a lookup from Index to DownloadResult for in-memory updates.
    $resultByIndex = @{}
    foreach ($r in $DownloadResults) {
        if ($r.Index) { $resultByIndex[$r.Index] = $r }
    }

    # Identify rescue candidates: planned _undated, download succeeded.
    $candidates = @($Plan | Where-Object {
        $_.YearFolder -eq '_undated' -and
        $resultByIndex.ContainsKey($_.Index) -and
        $resultByIndex[$_.Index].Status -eq 'Success'
    })

    Write-Step ("Found {0} _undated file(s) eligible for PDF-metadata rescue" -f $candidates.Count)
    if ($candidates.Count -eq 0) {
        Write-Ok 'No rescue work needed. (This is the normal steady-state on re-runs.)'
        Write-PhaseFooter -Id 'P08' -Status 'done'
        Stop-DebugTrace
        return [PSCustomObject]$stats
    }

    $overridesPath = Join-Path $LogDir 'year_overrides.csv'

    foreach ($p in $candidates) {
        $stats.Examined++
        $oldPath = $p.OutputFullPath

        # Defensive: if the file mysteriously isn't there, skip.
        if (-not (Test-Path -LiteralPath $oldPath)) {
            Write-Warn ("[{0}] file not on disk, skipping: {1}" -f $p.Index, $oldPath)
            continue
        }

        # Read PDF metadata.
        $meta = Get-PdfMetadata -PdfPath $oldPath
        if (-not [string]::IsNullOrEmpty($meta.Error)) {
            Write-Fail ("[{0}] PDF read error: {1}" -f $p.Index, $meta.Error)
            $stats.FailedToRead++
            continue
        }
        if ([string]::IsNullOrEmpty($meta.Year)) {
            Write-Skip ("[{0}] no usable date metadata in PDF: {1}" -f $p.Index, $p.OutputFilename)
            $stats.NoUsableMetadata++
            continue
        }

        # Compute new path: OutputDir\<year>\<filename>
        $newDir  = Join-Path $OutputDir $meta.Year
        $newPath = Join-Path $newDir $p.OutputFilename

        # Create the year folder if needed.
        if (-not (Test-Path -LiteralPath $newDir)) {
            try {
                New-Item -Path $newDir -ItemType Directory -Force | Out-Null
            } catch {
                Write-Fail ("[{0}] failed to create year folder {1}: {2}" -f $p.Index, $newDir, $_.Exception.Message)
                $stats.FailedToMove++
                continue
            }
        }

        # If a file already exists at the destination (e.g. partial earlier
        # rescue or manual user action), refuse to overwrite. Better to
        # leave both files and let the user reconcile, than to lose data.
        if (Test-Path -LiteralPath $newPath) {
            Write-Warn ("[{0}] destination already exists, skipping move: {1}" -f $p.Index, $newPath)
            $stats.FailedToMove++
            continue
        }

        # Move the file. Within-volume rename is atomic on NTFS.
        try {
            Move-Item -LiteralPath $oldPath -Destination $newPath -ErrorAction Stop
        } catch {
            Write-Fail ("[{0}] move failed: {1}" -f $p.Index, $_.Exception.Message)
            $stats.FailedToMove++
            continue
        }

        # Update in-memory plan / download result so Phase 9 reflects
        # the rescued state. We can't mutate ArrayList entries by index,
        # but we CAN mutate the properties of the PSCustomObject inside.
        $p.YearFolder     = $meta.Year
        $p.YearSource     = $meta.Source
        $p.OutputFullPath = $newPath
        $resultByIndex[$p.Index].OutputFullPath = $newPath
        # Also keep the download result's YearFolder/YearSource in sync
        # for the final report's year distribution. These columns are
        # always present in DownloadResult objects (set up in Phase 6).
        if ($resultByIndex[$p.Index].PSObject.Properties['YearFolder']) {
            $resultByIndex[$p.Index].YearFolder = $meta.Year
        }
        if ($resultByIndex[$p.Index].PSObject.Properties['YearSource']) {
            $resultByIndex[$p.Index].YearSource = $meta.Source
        }

        # Append to year_overrides.csv so the next run's Phase 5 routes
        # this deck directly to the correct folder.
        Add-YearOverride `
            -OverridesPath      $overridesPath `
            -DeckUrl            $p.DeckUrl `
            -OriginalFilename   $p.OriginalFilename `
            -PlanYearFolder     '_undated' `
            -ResolvedYearFolder $meta.Year `
            -ResolvedDate       $meta.RawValue `
            -YearSource         $meta.Source

        Write-Ok ("[{0}] rescued: _undated -> {1}  (source: {2})" -f $p.Index, $meta.Year, $meta.Source)

        $stats.RescuedCount++
        if (-not $stats.BySource.ContainsKey($meta.Source)) { $stats.BySource[$meta.Source] = 0 }
        $stats.BySource[$meta.Source]++
    }

    # Summary
    Write-Host ''
    Write-Host '  Reclassification summary:'
    Write-Host ('    Examined                 : {0}' -f $stats.Examined)
    if ($stats.RescuedCount -gt 0) {
        Write-Host ('    Rescued                  : {0}' -f $stats.RescuedCount) -ForegroundColor Green
        foreach ($k in ($stats.BySource.Keys | Sort-Object)) {
            Write-Host ('      via {0,-22}: {1}' -f $k, $stats.BySource[$k])
        }
        Write-Host ('    Overrides CSV            : {0}' -f $overridesPath)
    } else {
        Write-Host ('    Rescued                  : 0')
    }
    if ($stats.NoUsableMetadata -gt 0) {
        Write-Host ('    No usable PDF metadata   : {0}' -f $stats.NoUsableMetadata) -ForegroundColor DarkGray
    }
    if ($stats.FailedToRead -gt 0) {
        Write-Host ('    PDF read failures        : {0}' -f $stats.FailedToRead) -ForegroundColor Yellow
    }
    if ($stats.FailedToMove -gt 0) {
        Write-Host ('    Move failures            : {0}' -f $stats.FailedToMove) -ForegroundColor Yellow
    }

    Write-PhaseFooter -Id 'P08' -Status 'done'
        return [PSCustomObject]$stats
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        Write-PhaseFooter -Id 'P08' -Status 'failed'
        throw
    } finally {
        # Only pop if a frame is still on the stack. Early-return branches
        # (SkipReclassification / DryRun / FlatLayout / no candidates) call
        # Stop-DebugTrace explicitly before returning, so the finally
        # block becomes a no-op in those cases.
        if ($Script:DebugTraceStack.Count -gt 0 -and `
            $Script:DebugTraceStack.Peek().Context -eq 'Invoke-Phase8UndatedReclassify') {
            Stop-DebugTrace
        }
    }
}

# ============================================================
# Phase 9: Final report and CSV log
# ============================================================

function Save-DownloadLog {
    # Persist the per-deck download log as CSV. Saved under $LogDir
    # (which the main flow passes as $Script:LogsDir). The downloads
    # directory is kept content-only and never receives CSV files
    # (feedback #1).
    param(
        [Parameter(Mandatory)] $AllResults,
        [Parameter(Mandatory)] [string]$LogDir
    )

    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $logPath = Join-Path $LogDir "P06_download_log.csv"

    $records = $AllResults | ForEach-Object {
        [PSCustomObject]@{
            Index            = $_.Index
            Title            = $_.Title
            DeckUrl          = $_.DeckUrl
            DownloadUrl      = $_.DownloadUrl
            OriginalFilename = $_.OriginalFilename
            PublishDate      = $_.PublishDate
            YearFolder       = $_.YearFolder
            YearSource       = $_.YearSource
            OutputFilename   = $_.OutputFilename
            OutputType       = $_.OutputType
            Status           = $_.Status
            Bytes            = $_.Bytes
            DurationMs       = if ($_.DurationMs) { [int]$_.DurationMs } else { 0 }
            Attempts         = $_.Attempts
            ErrorMessage     = $_.ErrorMessage
        }
    }

    $records | Export-Csv -Path $logPath -Encoding UTF8 -NoTypeInformation
    return $logPath
}

function Show-FinalReport {
    param(
        [int]$TotalDeckCount,
        [int]$ListedCount,
        $EvalResults,
        $DownloadResults,
        [string]$LogPath,
        [bool]$IsDryRun,
        $ReclassifyStats = $null
    )

    Write-PhaseHeader -Id 'P09' -Name 'FinalReport' -Group 'Report'

    $okCount   = ($EvalResults | Where-Object { $_.Downloadable }).Count
    $ngCount   = $EvalResults.Count - $okCount

    Write-Host ""
    Write-Host "  [Evaluation]"
    Write-Host ("    Total decks (profile)   : {0,5}" -f $TotalDeckCount)
    Write-Host ("    Listed                  : {0,5}" -f $ListedCount)
    Write-Host ("    Downloadable            : {0,5} ({1,5:F1} %)" -f `
        $okCount, (($okCount / [Math]::Max(1, $EvalResults.Count)) * 100)) -ForegroundColor Green
    Write-Host ("    Not downloadable        : {0,5} ({1,5:F1} %)" -f `
        $ngCount, (($ngCount / [Math]::Max(1, $EvalResults.Count)) * 100)) -ForegroundColor Yellow

    if ($TotalDeckCount -gt 0 -and $TotalDeckCount -ne $ListedCount) {
        Write-Warn "Profile total ($TotalDeckCount) does not match listed count ($ListedCount)"
    }

    if (-not $IsDryRun -and $DownloadResults) {
        $sCount = ($DownloadResults | Where-Object { $_.Status -eq "Success" }).Count
        $kCount = ($DownloadResults | Where-Object { $_.Status -eq "Skipped" }).Count
        $fCount = ($DownloadResults | Where-Object { $_.Status -eq "Failed" }).Count
        $totalBytes = ($DownloadResults | Where-Object { $_.Status -eq "Success" -or $_.Status -eq "Skipped" } | Measure-Object -Property Bytes -Sum).Sum

        Write-Host ""
        Write-Host "  [Download]"
        Write-Host ("    New downloads (Success) : {0,5}" -f $sCount) -ForegroundColor Green
        Write-Host ("    Skipped (already exist) : {0,5}" -f $kCount) -ForegroundColor Cyan
        Write-Host ("    Failed                  : {0,5}" -f $fCount) -ForegroundColor Red
        if ($totalBytes -gt 0) {
            Write-Host ("    Total size              : {0,8:N1} MB" -f ($totalBytes / 1MB))
        }

        # Failure breakdown table:
        # Group failed downloads by error category so the user can see
        # at a glance what KIND of failure dominated (rate-limit, server
        # error, path-too-long, etc.) and decide whether to re-run with
        # different parameters.
        $failures = @($DownloadResults | Where-Object { $_.Status -eq 'Failed' })
        if ($failures.Count -gt 0) {
            Write-Host ""
            Write-Host "  Failure breakdown:" -ForegroundColor Yellow
            $byCategory = $failures | Group-Object { Get-FailureCategory -Item $_ } | Sort-Object Count -Descending
            foreach ($g in $byCategory) {
                Write-Host ("    {0,-45} : {1,4}" -f $g.Name, $g.Count) -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "  Detailed errors saved to:" -ForegroundColor Yellow
            Write-Host ("    {0}" -f $Script:ErrorsJsonlPath)
            Write-Host ("    {0}\" -f $Script:FailedDir)
        }

        # PDF-metadata reclassification stats (Phase 8).
        # Only show when something was actually rescued (or attempted),
        # otherwise the section is noise. The hashtable BySource is
        # the per-source rescue count (PdfInfoDict / PdfXmp / etc).
        if ($ReclassifyStats -and $ReclassifyStats.Examined -gt 0) {
            Write-Host ''
            Write-Host '  [PDF-metadata reclassification (Phase 8)]'
            Write-Host ('    Examined _undated files  : {0}' -f $ReclassifyStats.Examined)
            if ($ReclassifyStats.RescuedCount -gt 0) {
                Write-Host ('    Rescued to year folder   : {0}' -f $ReclassifyStats.RescuedCount) -ForegroundColor Green
                $sourceMap = $ReclassifyStats.BySource
                if ($sourceMap -and $sourceMap.Count -gt 0) {
                    foreach ($k in ($sourceMap.Keys | Sort-Object)) {
                        Write-Host ('      via {0,-22}: {1}' -f $k, $sourceMap[$k])
                    }
                }
            }
            if ($ReclassifyStats.NoUsableMetadata -gt 0) {
                Write-Host ('    No usable PDF metadata   : {0}' -f $ReclassifyStats.NoUsableMetadata) -ForegroundColor DarkGray
            }
            if ($ReclassifyStats.FailedToRead -gt 0) {
                Write-Host ('    PDF read failures        : {0}' -f $ReclassifyStats.FailedToRead) -ForegroundColor Yellow
            }
            if ($ReclassifyStats.FailedToMove -gt 0) {
                Write-Host ('    Move failures            : {0}' -f $ReclassifyStats.FailedToMove) -ForegroundColor Yellow
            }
        }

        # Year distribution: which years got how many decks, with size.
        # Only meaningful in year-folder mode, but harmless in flat mode
        # (YearFolder may still be populated from Phase 5 for diagnostic
        # purposes). The "_undated" bucket is shown last with explicit
        # separation so it is visually distinct from real years.
        $itemsWithYear = @($DownloadResults | Where-Object {
            $_.PSObject.Properties['YearFolder'] -and
            -not [string]::IsNullOrEmpty($_.YearFolder) -and
            ($_.Status -eq 'Success' -or $_.Status -eq 'Skipped')
        })
        if ($itemsWithYear.Count -gt 0) {
            Write-Host ""
            Write-Host "  [Year distribution]"
            $byYear = $itemsWithYear | Group-Object YearFolder
            $realYears  = $byYear | Where-Object { $_.Name -match '^\d{4}$' } | Sort-Object Name -Descending
            $undatedGrp = $byYear | Where-Object { $_.Name -eq '_undated' }
            $otherGrps  = $byYear | Where-Object { $_.Name -notmatch '^\d{4}$' -and $_.Name -ne '_undated' } | Sort-Object Name
            foreach ($g in $realYears) {
                $sumBytes = ($g.Group | Measure-Object -Property Bytes -Sum).Sum
                Write-Host ("    {0,-10} : {1,4} decks  ({2,8:N1} MB)" -f $g.Name, $g.Count, ($sumBytes / 1MB))
            }
            foreach ($g in $otherGrps) {
                $sumBytes = ($g.Group | Measure-Object -Property Bytes -Sum).Sum
                Write-Host ("    {0,-10} : {1,4} decks  ({2,8:N1} MB)" -f $g.Name, $g.Count, ($sumBytes / 1MB))
            }
            if ($undatedGrp) {
                $sumBytes = ($undatedGrp.Group | Measure-Object -Property Bytes -Sum).Sum
                Write-Host ("    {0,-10} : {1,4} decks  ({2,8:N1} MB)" -f '_undated', $undatedGrp.Count, ($sumBytes / 1MB)) -ForegroundColor DarkGray
            }
        }
    } elseif ($IsDryRun) {
        Write-Host ""
        Write-Host "  [DryRun mode] No actual downloads were performed" -ForegroundColor Magenta

        # DryRun: show year distribution from the plan instead of from
        # actual downloads, so the user can still preview the planned
        # year layout before running for real.
        if ($EvalResults) {
            # In DryRun mode, the plan is what we want to see. But Show-FinalReport
            # only receives EvalResults, not the Plan. So we approximate by
            # computing the year ourselves on the fly using Get-DeckYear.
            $planYears = @{}
            foreach ($e in $EvalResults) {
                if ($e.Downloadable -and $e.OriginalFilename) {
                    $yi = Get-DeckYear -OriginalFilename $e.OriginalFilename -PublishDate $e.PublishDate -Title $e.Title -DeckUrl $e.DeckUrl
                    if (-not $planYears.ContainsKey($yi.Year)) { $planYears[$yi.Year] = 0 }
                    $planYears[$yi.Year]++
                }
            }
            if ($planYears.Count -gt 0) {
                Write-Host ""
                Write-Host "  [Year distribution - planned]"
                $sortedKeys = @($planYears.Keys | Where-Object { $_ -match '^\d{4}$' } | Sort-Object -Descending)
                foreach ($k in $sortedKeys) {
                    Write-Host ("    {0,-10} : {1,4} decks" -f $k, $planYears[$k])
                }
                if ($planYears.ContainsKey('_undated')) {
                    Write-Host ("    {0,-10} : {1,4} decks" -f '_undated', $planYears['_undated']) -ForegroundColor DarkGray
                }
            }
        }
    }

    # Generated log files: enumerate ALL CSV / JSONL artifacts
    # produced by the pipeline so the user is not left wondering which
    # files actually exist. Each entry is shown only if its source file
    # is on disk - this naturally handles DryRun (no P06/P07 files) and
    # also the "no failures, no errors.jsonl" case for real runs.
    $candidates = @(
        @{ Path = (Join-Path $Script:LogsDir 'P04_evaluation_log.csv'); Note = 'Phase 4 - downloadability evaluation (DryRun only)' },
        @{ Path = (Join-Path $Script:LogsDir 'P05_filename_plan.csv');  Note = 'Phase 5 - output filename plan + duplicate/over-limit check' },
        @{ Path = (Join-Path $Script:LogsDir 'P06_download_log.csv');   Note = 'Phase 6 - per-deck download outcomes' },
        @{ Path = $Script:ErrorsJsonlPath;                              Note = 'Phase 6 - structured failure log (JSONL, only when failures occurred)' },
        @{ Path = (Join-Path $Script:LogsDir 'P07_final_state.csv');    Note = 'Phase 7 - reconciliation: plan + download log + disk inventory' }
    )
    $existing = @($candidates | Where-Object { Test-Path -LiteralPath $_.Path })
    if ($existing.Count -gt 0) {
        Write-Host ""
        Write-Host "  Log files generated:"
        foreach ($c in $existing) {
            Write-Host ("    {0}" -f $c.Path)
            Write-Host ("      ({0})" -f $c.Note) -ForegroundColor DarkGray
        }
    }

    Write-PhaseFooter -Id 'P09' -Status 'done'
}

# ============================================================
# Main
# ============================================================

try {
    # Compatibility hard-fail must run before any phase work, but AFTER
    # function definitions have been parsed (PowerShell loads functions
    # top-down). Putting it just inside the main try block gives a
    # clear, actionable error message if the user accidentally launched
    # us in PowerShell 4.x or a 32-bit host.
    Assert-PowerShellCompatibility

    Write-Host ""
    Write-Host ('=' * 72) -ForegroundColor Magenta
    Write-Host "  Speaker Deck Bulk Downloader" -ForegroundColor Magenta
    Write-Host ("  $Script:ScriptShortTag") -ForegroundColor DarkGray
    Write-Host ('=' * 72) -ForegroundColor Magenta
    Write-Host "  Account         : $Account"
    Write-Host "  Script root     : $Script:ScriptRoot"
    Write-Host "  Output dir      : $OutputDir"
    Write-Host "  Work dir        : $WorkDir"
    Write-Host "  Request gap     : $DelaySeconds sec +/- $JitterSeconds"
    Write-Host "  Concurrency     : initial $InitialConcurrency / max $MaxConcurrency / min $MinConcurrency"
    Write-Host "  Retries         : up to $MaxRetries"
    if ($FlatLayout) {
        Write-Host "  Layout          : FLAT (all files in OutputDir, no year subfolders)" -ForegroundColor Yellow
    } else {
        Write-Host "  Layout          : YEAR-FOLDER (default; OutputDir\<YYYY>\file.pdf)" -ForegroundColor Cyan
    }
    if ($Force)                   { Write-Host "  Force                : ON" -ForegroundColor Yellow }
    if ($DryRun)                  { Write-Host "  DryRun               : ON" -ForegroundColor Magenta }
    if ($SkipEnvCheck)            { Write-Host "  SkipEnvCheck         : ON" -ForegroundColor Yellow }
    if ($Clean)                   { Write-Host "  Clean                : ON" -ForegroundColor Yellow }
    if ($CleanOnly)               { Write-Host "  CleanOnly            : ON (will exit after cleanup)" -ForegroundColor Yellow }
    if ($SkipPdfReclassification) { Write-Host "  SkipPdfReclassif.    : ON (Phase 8 will be skipped)" -ForegroundColor Yellow }

    # ===== Optional cleanup phase (-Clean / -CleanOnly) =====
    # Runs BEFORE Initialize-RuntimeDirectories so the cleanup wipes
    # any leftovers from a previous run and we then start with empty
    # fresh trees.
    if ($Clean -or $CleanOnly) {
        Write-Host ''
        Write-Warn "-Clean specified: removing existing directories"
        Invoke-CleanupDirectories -OutputDir $OutputDir -WorkDir $WorkDir

        if ($CleanOnly) {
            Write-Host ''
            Write-Ok "-CleanOnly: cleanup complete, exiting without running phases."
            exit 0
        }
    }

    # Now that any cleanup is done, (re-)create the directory tree.
    Initialize-RuntimeDirectories

    # ===== Activate the Debug Trace Facility =====
    # Now that $Script:LogsDir and $Script:DiagDir exist on disk, route
    # the in-memory JSONL buffer to <work>\logs\debugtrace.jsonl and
    # arm auto-export for phase failures (snapshots land in
    # <work>\diag\debugtrace_export_<phaseId>_<timestamp>.json). Both
    # are best-effort: if either activation fails, the script continues
    # without the diagnostic feature (the failure is surfaced as a
    # warning and trace events stay buffered in memory).
    Enable-DebugTraceFileOutput -Directory $Script:LogsDir
    Enable-AutoExportOnPhaseFailure -OutputDirectory $Script:DiagDir

    # ===== Phase 1: Environment evaluation =====
    if ($SkipEnvCheck) {
        $envResult = [ordered]@{
            EnvironmentClass  = "Skipped"
            MaxFilenameLength = 200
            MaxFullPathLength = 240
        }
        Write-PhaseHeader -Id 'P01' -Name 'EnvCheck' -Group 'Setup'
        Write-Warn "Skipped because -SkipEnvCheck was specified"
        Write-Host "  Using defaults : filename 200 / full path 240"
        Write-PhaseFooter -Id 'P01' -Status 'skipped'
    } else {
        $envResult = Test-Environment -TestDir $OutputDir
    }

    # ===== Phase 2: Get total deck count =====
    $totalCount = Get-TotalDeckCount -AccountName $Account

    # ===== Phase 3: Listing collection =====
    $deckList = Get-AllDeckList -AccountName $Account

    if ($deckList.Count -eq 0) {
        Write-Fail "Listing collection returned 0 - aborting"
        exit 1
    }

    # ===== Phase 4: Evaluation =====
    $evalResults = Invoke-Phase4Evaluation -DeckList $deckList -ConcurrencyLimit 3

    # ===== Phase 5: Filename plan =====
    # Always runs (DryRun and real-run). Pre-computes every output
    # filename so the user can inspect P05_filename_plan.csv before
    # any download starts.
    $filenamePlan = Invoke-Phase5FilenamePlan `
        -EvalResults       $evalResults `
        -OutputDir         $OutputDir `
        -MaxFilenameLength $envResult.MaxFilenameLength `
        -MaxFullPathLength $envResult.MaxFullPathLength `
        -LogDir            $Script:LogsDir `
        -FlatLayout        ([bool]$FlatLayout)

    # ===== Phase 6: Download (skipped on DryRun) =====
    # When -DryRun is set we still want P06 to appear in the Phase
    # Timing Summary (as 'SKIPPED') so the user can see the full
    # pipeline shape at a glance. We therefore emit a tiny header /
    # footer pair instead of completely bypassing the phase.
    $downloadResults = $null
    if ($DryRun) {
        Write-PhaseHeader -Id 'P06' -Name 'Download'       -Group 'Fetch'
        Write-Skip "DryRun mode: download phase intentionally skipped"
        Write-PhaseFooter -Id 'P06' -Status 'skipped'
    } else {
        $downloadablePlanned = @($filenamePlan | Where-Object { $_.Downloadable })
        if ($downloadablePlanned.Count -eq 0) {
            Write-Warn "No downloadable items - skipping Phase 6"
            Write-PhaseHeader -Id 'P06' -Name 'Download'       -Group 'Fetch'
            Write-PhaseFooter -Id 'P06' -Status 'skipped'
        } else {
            $downloadResults = Invoke-Phase6Download `
                -FilenamePlan       $filenamePlan `
                -MaxConcurrency     $MaxConcurrency `
                -InitialConcurrency $InitialConcurrency `
                -MinConcurrency     $MinConcurrency `
                -MaxRetries         $MaxRetries `
                -Force:$Force
        }
    }

    # ===== Phase 7: Reconciliation (skipped on DryRun) =====
    # Same skip-marker treatment as P06 so the Timing Summary shows
    # P07 with status 'SKIPPED' rather than silently disappearing.
    if ($DryRun) {
        Write-PhaseHeader -Id 'P07' -Name 'Reconciliation' -Group 'Verify'
        Write-Skip "DryRun mode: reconciliation phase intentionally skipped (no disk state to verify)"
        Write-PhaseFooter -Id 'P07' -Status 'skipped'
    } elseif ($downloadResults) {
        $null = Invoke-Phase7Reconciliation `
            -Plan            $filenamePlan `
            -DownloadResults $downloadResults `
            -OutputDir       $OutputDir `
            -LogDir          $Script:LogsDir
    } else {
        Write-PhaseHeader -Id 'P07' -Name 'Reconciliation' -Group 'Verify'
        Write-Skip "No download results to reconcile (P06 was skipped or empty)"
        Write-PhaseFooter -Id 'P07' -Status 'skipped'
    }

    # ===== Phase 8: PDF-metadata reclassification of _undated files =====
    # Runs after Phase 7 and before the final report so the year
    # distribution in Phase 9 reflects the post-rescue state. The
    # function mutates $filenamePlan and $downloadResults in-memory.
    $reclassifyStats = $null
    if ($downloadResults) {
        $reclassifyStats = Invoke-Phase8UndatedReclassify `
            -Plan                  $filenamePlan `
            -DownloadResults       $downloadResults `
            -OutputDir             $OutputDir `
            -LogDir                $Script:LogsDir `
            -FlatLayout            $FlatLayout `
            -SkipReclassification  $SkipPdfReclassification `
            -IsDryRun              $DryRun
    } else {
        Write-PhaseHeader -Id 'P08' -Name 'UndatedReclassify' -Group 'Verify'
        Write-Skip "No download results to reclassify"
        Write-PhaseFooter -Id 'P08' -Status 'skipped'
    }

    # ===== Legacy CSV persistence (download_log.csv + DryRun evaluation_log.csv) =====
    $logPath = $null
    if ($downloadResults) {
        # Include items that were not downloadable in the log too
        $allRecords = New-Object System.Collections.ArrayList
        foreach ($d in $downloadResults) { [void]$allRecords.Add($d) }

        $downloadIndices = @{}
        foreach ($d in $downloadResults) { $downloadIndices[$d.Index] = $true }

        foreach ($e in $evalResults) {
            if (-not $e.Downloadable -and -not $downloadIndices.ContainsKey($e.Index)) {
                [void]$allRecords.Add([PSCustomObject]@{
                    Index            = $e.Index
                    Title            = $e.Title
                    DeckUrl          = $e.DeckUrl
                    DownloadUrl      = $e.DownloadUrl
                    OriginalFilename = $e.OriginalFilename
                    PublishDate      = $e.PublishDate
                    YearFolder       = ""
                    YearSource       = ""
                    OutputFilename   = ""
                    OutputType       = ""
                    Status           = "NotDownloadable"
                    Bytes            = 0
                    DurationMs       = 0
                    Attempts         = 0
                    ErrorMessage     = $e.Reason
                })
            }
        }
        $logPath = Save-DownloadLog -AllResults $allRecords -LogDir $Script:LogsDir
    } elseif ($DryRun) {
        # Save evaluation results in DryRun mode too. Like the real-run
        # CSV, this goes into the logs/ folder, NOT into downloads/.
        #
        # This file is intentionally scoped to *just* the evaluation
        # outcome (downloadability per deck). Filename plan information
        # lives in P05_filename_plan.csv, and download / execution
        # outcomes live in P06_download_log.csv and P07_final_state.csv.
        # Keeping P04 strictly evaluation-only avoids the previous
        # problem of "OutputFilename / OutputType columns are always
        # empty here" confusion.
        #
        # YearFolder / YearSource columns are computed here as well so
        # this CSV has the same year-derivation columns as P05 / P06 /
        # P07. This makes cross-CSV grep / join queries (e.g.
        # "find all 2024 decks across every log") work uniformly. The
        # computation is cheap because Get-DeckYear is pure string
        # parsing; no extra HTTP fetches.
        $records = $evalResults | ForEach-Object {
            $yearInfo = Get-DeckYear -Title $_.Title `
                                     -OriginalFilename $_.OriginalFilename `
                                     -PublishDate $_.PublishDate `
                                     -DeckUrl $_.DeckUrl
            [PSCustomObject]@{
                Index            = $_.Index
                Title            = $_.Title
                DeckUrl          = $_.DeckUrl
                DownloadUrl      = $_.DownloadUrl
                OriginalFilename = $_.OriginalFilename
                PublishDate      = $_.PublishDate
                YearFolder       = $yearInfo.Year
                YearSource       = $yearInfo.Source
                Downloadable     = $_.Downloadable
                Status           = if ($_.Downloadable) { "Downloadable" } else { "NotDownloadable" }
                Reason           = $_.Reason
            }
        }
        $logPath = Join-Path $Script:LogsDir "P04_evaluation_log.csv"
        $records | Export-Csv -Path $logPath -Encoding UTF8 -NoTypeInformation
    }

    Show-FinalReport `
        -TotalDeckCount $totalCount `
        -ListedCount $deckList.Count `
        -EvalResults $evalResults `
        -DownloadResults $downloadResults `
        -LogPath $logPath `
        -IsDryRun $DryRun.IsPresent `
        -ReclassifyStats $reclassifyStats

    Show-PhaseSummary
    Write-Host ''
}
catch {
    Write-Host ""
    Write-Host ('=' * 72) -ForegroundColor Red
    Write-Host "  An unexpected error occurred" -ForegroundColor Red
    Write-Host ('=' * 72) -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Stack trace:" -ForegroundColor DarkRed
    Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkRed

    # Emit the structured failure report via the Debug Trace Facility.
    # When the failure occurred inside a phase, this attaches:
    #   - the trace context (function name) and the failing step label
    #   - the full step history leading up to the failure
    #   - an exported JSON snapshot of all completed frames + the
    #     phase registry, written to <work>\diag\debugtrace_export_*.json
    # The DebugTrace facility is best-effort: if it failed to activate
    # earlier, the report degrades gracefully (no JSON export written,
    # just the in-memory step history if available).
    try {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
    } catch { } # psa-disable-line PSA3004 -- defensive: the failure report itself must not mask the original error

    Show-PhaseSummary
    exit 1
}
