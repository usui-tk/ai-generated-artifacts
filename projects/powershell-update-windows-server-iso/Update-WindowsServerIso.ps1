<#
.SYNOPSIS
    Build an updated Windows Server ISO by integrating SSU/LCU/Dynamic Updates
    into the install.wim, boot.wim, and winre.wim, then repackaging the media.

.DESCRIPTION
    Takes a Microsoft Evaluation Center (or VLSC) Windows Server ISO and a set
    of patch MSU/CAB files, and produces a new ISO whose embedded Windows
    images already contain the latest cumulative updates. The goal is to
    eliminate the lengthy Windows Update step from lab/test bring-up of
    Server 2016 / 2019 / 2022 / 2025.

    Repository: https://github.com/usui-tk/ai-generated-artifacts
    Location  : projects/powershell-update-windows-server-iso/Update-WindowsServerIso.ps1
    License   : MIT (see LICENSE at the repository root)

    Prerequisites:
      - Windows PowerShell 5.1+ (also runs on PowerShell 7+)
      - 64-bit process (forcibly checked in Phase P01)
      - Windows 10/11 Pro/Enterprise/Education or Windows Server 2016+
      - Administrator (DISM Mount requires elevation)
      - Windows ADK Deployment Tools (for oscdimg.exe)
      - 60 GB free disk space on the WorkRoot drive (30 GB minimum)
      - Internet access for ISO/patch downloads (when not using -IsoPath +
        -PatchDirectory)
      - Optional: python3 + quality-tools/powershell-static-analyzer/psa.py
        from usui-tk/ai-generated-artifacts (latest mainline) for static
        analysis (rule families PSA1001..PSA9002 plus opt-in
        PSAP0001..PSAP0005)

    Known limitations:
      - Server 2016/2019/2022/2025 only; client SKUs out of scope
      - x64 architecture only (no x86, no arm64)
      - No driver / FOD / LXP / Appx customization (OSBuild equivalents are
        out of scope; this is an OSMedia-equivalent tool only)
      - Hyper-V BootTest requires local Windows 11 (CI cannot run nested virt)
      - Microsoft Update Catalog scraping is local-only (not run in CI)

    AI tool: Generated and iteratively refined with Anthropic Claude
            (Opus 4.7 era; baseline revision r01 on 2026-05-24).

.DESCRIPTION_PHASES
    Phases (P01..P13):
      P01 : Initialize        (Setup ) PowerShell env, admin, ADK, disk, Hyper-V
      P02 : ResolveInputs     (Setup ) ISO/patch source resolution, Config JSON
      P04 : FetchAssets       (Fetch ) ISO + patch downloads with hash verify
      P05 : ExpandIso         (Plan  ) Mount source ISO, copy to workspace,
                                       enumerate WIM indexes
      P07 : PatchInstallWim   (Build ) For each install.wim index: SSU then LCU
                                       then .NET, then DISM cleanup
      P08 : PatchBootWim      (Build ) boot.wim (PE + Setup) and winre.wim
      P09 : AssembleIso       (Build ) Dynamic Update Setup overlay,
                                       Export-WindowsImage, oscdimg ISO build
      P11 : StaticVerify      (Verify) Mount output ISO, confirm KB packages
                                       are present
      P13 : FinalReport       (Report) End-of-run summary + ISO hash + log
                                       paths

    Optional out-of-band action: BootTest (Hyper-V VM smoke test, P10 equiv).

.PARAMETER Action
    One of: Prepare / Build / Verify / PrepareBuildVerify / BootTest / All /
    Cleanup / ListPhases / GenerateManifest / RefreshAllBaselines /
    DumpFieldClassification / TestHarness. Default: PrepareBuildVerify.
    The TestHarness action loads all functions and enters a JSON-over-stdin
    REPL used by the Python-side self-verification tools in `tests/`; it
    is not meant for human invocation.

.PARAMETER OnlyPhases
    Array of phase IDs (e.g. 'P04','P07') to run. Overrides -Action.

.PARAMETER OsVersion
    One of: Server2016 / Server2019 / Server2022 / Server2025.

.PARAMETER OsLanguage
    One of: en-us / ja-jp. Default: en-us.

.PARAMETER IsoUrl
    HTTP(S) URL of the source ISO. Mutually exclusive with -IsoPath.

.PARAMETER IsoPath
    Local path of the source ISO. Mutually exclusive with -IsoUrl.

.PARAMETER PatchUrls
    Array of explicit patch URLs (MSU or CAB).

.PARAMETER PatchDirectory
    Directory containing local MSU/CAB patches.

.PARAMETER ManifestPath
    Path to a Metalink (.meta4) manifest file describing the patch set.

.PARAMETER AutoDetectLatestPatches
    Force a refresh of the patch baseline by scraping Microsoft Update
    Catalog regardless of staleness. Result is written back to the
    Config JSON (PatchBaseline). Requires internet access..

.PARAMETER PatchMonth
    Target patch month in yyyy-MM format (e.g. '2026-06'). Used by the
    r02 RefreshPatchBaseline phase to scope the Catalog query. Defaults
    to the current month's Patch Tuesday..

.PARAMETER SkipDynamicPatchRefresh
    Skip the P03 RefreshPatchBaseline phase even if the baseline is
    stale. Useful for offline or air-gapped runs..

.PARAMETER UseBaselineOnly
    Use PatchBaseline.Patches strictly as-is, never scrape, never
    refresh. Equivalent to -SkipDynamicPatchRefresh plus a guarantee
    that no Catalog access occurs..

.PARAMETER Mode
    Only meaningful with -Action RefreshAllBaselines. One of:
      - Initial: refresh all fields whose _VerifiedDate is empty.
      - Monthly: refresh only fields whose Cadence is "PatchTuesday"
                 AND whose recorded PatchTuesdayOfBaseline is older
                 than the latest Patch Tuesday. (default)
      - Force  : refresh every field group regardless of state.
    Configs are refreshed via -Action RefreshAllBaselines.

.PARAMETER OnlyOs
    Only meaningful with -Action RefreshAllBaselines. Limits the
    refresh to a single OS Config (Server2016 / 2019 / 2022 / 2025).
    Without this, all four Configs are processed.

.PARAMETER OnlyLanguage
    Only meaningful with -Action RefreshAllBaselines. Limits the
    LanguageSpecific refresh to a single language (en-us / ja-jp).
    Without this, all SupportedLanguages of each Config are processed.
    Configs are refreshed via -Action RefreshAllBaselines.

.PARAMETER WorkRoot
    Workspace root. Default: C:\Temp\Workspace_UpdateWsi.
    Strong recommendation: -WorkRoot D:\UpdateWsi on data-drive hosts.

.PARAMETER OutputDir
    Output ISO directory. Default: <WorkRoot>\output.

.PARAMETER OnlyInstallWimIndexes
    Comma-separated index list (e.g. '2,4') to limit install.wim updates.
    Default: all indexes in install.wim.

.PARAMETER UseDefenderExclusions
    Opt-in. Temporarily add Windows Defender exclusions (the WorkRoot path and
    the dism/DismHost/TiWorker/TrustedInstaller processes) for the run, then
    remove them. Speeds the LCU apply (~35% in a measured A/B probe); the
    cleanup is storage-bound and unaffected. Fail-closed: applied only when
    Defender is present, running in Normal mode, real-time protection on and
    Tamper Protection off; any other or unknown state -> skipped. Default off.

.PARAMETER CleanWorkRoot
    Delete WorkRoot before starting (preserves the output directory).

.PARAMETER LogFile
    Start-Transcript path for the entire run.

.PARAMETER DryRun
    Run Setup/Fetch/Plan only; Build/Verify are SKIPPED.

.PARAMETER SkipEnvCheck
    Skip Phase P01 entirely and use safe-default thresholds.

.PARAMETER EnvironmentInfoOnly
    Run only the Show-PowerShellEnvironment dump (P01 Step 0) and exit 0.
    Intended for CI smoke testing.

.PARAMETER SyntheticTestMode
    CI-friendly mode S: build a synthetic non-bootable ISO from a tiny
    in-memory WIM. No Microsoft assets are downloaded.

.PARAMETER EvalIsoMode
    Opt-in mode E: download Microsoft Evaluation Center ISO via fwlink and
    run the full pipeline. Output ISO is NOT uploaded as a CI artifact
    (evaluation licence forbids redistribution).

.PARAMETER Execute
    Required for Build phases to actually mount and modify WIMs. Without it,
    Build phases run in Sandbox mode (plan only, no DISM writes).

.EXAMPLE
    .\Update-WindowsServerIso.ps1 -Action ListPhases
    Show the registered phase list and exit.

.EXAMPLE
    .\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly
    CI smoke test: dump environment info and exit 0.

.EXAMPLE
    .\Update-WindowsServerIso.ps1 `
        -Action PrepareBuildVerify `
        -OsVersion Server2019 -OsLanguage ja-jp `
        -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
        -PatchDirectory 'D:\Patches\Server2019\2026-05' `
        -WorkRoot 'D:\UpdateWsi' `
        -Execute
    Full local build with explicit ISO and patch directory inputs.

.EXAMPLE
    .\Update-WindowsServerIso.ps1 `
        -Action PrepareBuildVerify `
        -OsVersion Server2025 -OsLanguage en-us `
        -AutoDetectLatestPatches `
        -EvalIsoMode `
        -WorkRoot 'D:\UpdateWsi' `
        -Execute
    Eval mode: download Microsoft Eval Center ISO via fwlink, auto-detect
    latest patches, run the full pipeline.

.EXAMPLE
    .\Update-WindowsServerIso.ps1 `
        -Action PrepareBuildVerify `
        -OsVersion Server2016 -OsLanguage ja-jp `
        -EvalIsoMode -UseBaselineOnly -EnablePca2023BootManager `
        -WorkRoot 'D:\UpdateWsi'
    Server 2016 ja-jp eval ISO build, dry-run mode (no -Execute). On hosts
    that do not yet have Windows ADK Deployment Tools installed, P01 will
    download and silently install OptionId.DeploymentTools before continuing.
    Add -Execute on a subsequent run to perform the real ISO assembly.
#>

[CmdletBinding()]
param(
    [ValidateSet('Prepare','Build','Verify','PrepareBuildVerify','BootTest','All','Cleanup','ListPhases','GenerateManifest','RefreshSnapshots','RefreshAllBaselines','DumpFieldClassification','TestHarness')]
    [string]   $Action               = 'PrepareBuildVerify',

    [string[]] $OnlyPhases,

    [ValidateSet('Server2016','Server2019','Server2022','Server2025')]
    [string]   $OsVersion,

    [ValidateSet('en-us','ja-jp')]
    [string]   $OsLanguage           = 'en-us',

    [string]   $IsoUrl,
    [string]   $IsoPath,

    [string[]] $PatchUrls,
    [string]   $PatchDirectory,
    [string]   $ManifestPath,
    [switch]   $AutoDetectLatestPatches,

    # ---- dynamic baseline / validation parameters ----
    [string]   $PatchMonth,
    [switch]   $SkipDynamicPatchRefresh,
    [switch]   $UseBaselineOnly,

    # RefreshAllBaselines parameters: control which OS / language /
    # patch month is targeted when running -Action RefreshAllBaselines.
    [ValidateSet('Initial','Monthly','Force')]
    [string]   $Mode                 = 'Monthly',
    [ValidateSet('Server2016','Server2019','Server2022','Server2025')]
    [string]   $OnlyOs,
    [ValidateSet('en-us','ja-jp')]
    [string]   $OnlyLanguage,
    # ------------

    [string]   $WorkRoot             = 'Workspace_UpdateWsi',
    [string]   $OutputDir,
    [string]   $OnlyInstallWimIndexes,

    # P07 install.wim cleanup: by default the per-image DISM cleanup runs
    # /Cleanup-Image /StartComponentCleanup /ResetBase. /ResetBase resets the
    # component-store base (smaller image; applied updates no longer removable),
    # the correct default for a patched golden ISO whose purpose is to ship the
    # latest updates already applied -- uninstalling them is not a use case. On
    # heavily-agented hosts /ResetBase's bulk base reset is also faster than
    # granular /StartComponentCleanup-only scavenging. -SkipResetBaseOnCleanup
    # opts out (keeps updates removable; omits /ResetBase).
    [switch]   $SkipResetBaseOnCleanup,

    # P07 install.wim size optimisation: after all indexes are serviced, a
    # single Export-Image /Compress:max pass recompresses and single-instances
    # files shared across editions, then replaces install.wim. Default ON;
    # -SkipExportCompress opts out (faster build, larger install.wim).
    [switch]   $SkipExportCompress,

    # Opt-in Windows Defender exclusion management (security-affecting; default
    # off). When set, the WorkRoot path and the DISM/CBS servicing processes
    # are excluded from Defender real-time scanning for the run and removed
    # afterwards. Fail-closed (Get-DefenderExclusionDecision) and crash-safe
    # (state file + startup self-heal). Measured A/B: ~35% faster LCU apply;
    # the cleanup is storage-bound and unaffected.
    [switch]   $UseDefenderExclusions,

    [switch]   $CleanWorkRoot,
    [string]   $LogFile,
    [switch]   $DryRun,
    [switch]   $SkipEnvCheck,
    [switch]   $EnvironmentInfoOnly,

    [switch]   $SyntheticTestMode,
    [switch]   $EvalIsoMode,
    [switch]   $Execute,

    # ---- Secure Boot / PCA2023 ----
    # When set, enables P10 ConvertPca2023BootManager which rewrites the
    # output ISO's boot manager to the 'Windows UEFI CA 2023'-signed form
    # (Microsoft KB5053484 / Make2023BootableMedia.ps1 equivalent). Default
    # OFF: the default pipeline produces a PCA2011-signed boot manager,
    # which still boots on Secure Boot firmware that trusts the 2011 CA
    # set (i.e. virtually all hardware shipped before 2026-06 cert expiry).
    [switch]   $EnablePca2023BootManager,

    # When set, P10 ConvertPca2023BootManager still runs against Server
    # 2025 output ISOs (default-skipped because Server 2025 certified
    # server platforms already include the 2023 certs in firmware per
    # Microsoft; the boot-manager conversion is documented as not
    # required). Takes effect only with -EnablePca2023BootManager (P10
    # is opt-in); both are needed to convert on Server 2025. Advanced use.
    [switch]   $ForcePca2023OnServer2025,

    # When set, the script enters a special mode that takes an existing
    # ISO (-IsoPath) and runs ONLY P12 VerifyPca2023Readiness against it,
    # emitting pca2023_readiness.json + pca2023_readiness.md. No download,
    # no patching, no DISM mount of install.wim. Useful for forensic
    # analysis of ISOs built by other pipelines.
    [switch]   $Pca2023OnlyMode,

    # Optional path to an external Make2023BootableMedia.ps1 script. When
    # not specified, the internal Convert-WimBootToPca2023Signed function
    # is used (recommended; PSA-clean re-implementation of Microsoft's
    # Copy-2023BootBins logic). When specified, the external script is
    # invoked as a child PowerShell with -MediaPath / -TargetType ISO /
    # -ISOPath arguments, and its output JSON is parsed back into the
    # Pca2023 snapshot.
    [string]   $Pca2023ScriptPath
)

# Propagate the new PCA2023 switches into Script scope so Phase
# functions can reference them as $Script:* (rather than relying on
# the auto-bound parameter scope, which psa.py's PSA2001 cannot
# reason about reliably). Mirrors how P09 AssembleIso etc. reach
# operator-supplied options.
$Script:EnablePca2023BootManager  = [bool]$EnablePca2023BootManager
$Script:ForcePca2023OnServer2025  = [bool]$ForcePca2023OnServer2025
$Script:Pca2023OnlyMode           = [bool]$Pca2023OnlyMode
$Script:Pca2023ScriptPath         = $Pca2023ScriptPath
$Script:ResetBaseOnCleanup        = -not [bool]$SkipResetBaseOnCleanup
$Script:SkipExportCompress        = [bool]$SkipExportCompress
$Script:UseDefenderExclusions     = [bool]$UseDefenderExclusions

# -----------------
# Parameter validation
# -----------------
# Mutual exclusivity rules are checked here (rather than via [ValidateScript])
# so the user gets a single, clear error before any side effects occur.
if ($IsoUrl -and $IsoPath) {
    throw '-IsoUrl and -IsoPath are mutually exclusive.'
}
if ($EnvironmentInfoOnly -and $SkipEnvCheck) {
    throw '-EnvironmentInfoOnly and -SkipEnvCheck cannot be used together.'
}
if ($Action -eq 'BootTest' -and $SyntheticTestMode) {
    throw 'BootTest requires Hyper-V and is incompatible with -SyntheticTestMode.'
}
if ($SyntheticTestMode -and $EvalIsoMode) {
    throw '-SyntheticTestMode and -EvalIsoMode are mutually exclusive.'
}
if ($PSBoundParameters.ContainsKey('OnlyPhases') -and -not $OnlyPhases) {
    throw '-OnlyPhases was specified but the array is empty.'
}

# ---- mutual exclusivity / format validation (P03 / P06 params) ----
if ($SkipDynamicPatchRefresh -and $AutoDetectLatestPatches) {
    throw '-SkipDynamicPatchRefresh and -AutoDetectLatestPatches are mutually exclusive.'
}
if ($UseBaselineOnly -and $AutoDetectLatestPatches) {
    throw '-UseBaselineOnly and -AutoDetectLatestPatches are mutually exclusive.'
}
if ($PatchMonth -and ($PatchMonth -notmatch '^\d{4}-\d{2}$')) {
    throw ('-PatchMonth must be in yyyy-MM format (e.g. 2026-06). Got: "' + $PatchMonth + '"')
}
# ----------

# Several non-trivial actions require OsVersion. ListPhases and
# EnvironmentInfoOnly are the only ones that should be allowed without it
# so a CI smoke run can succeed without picking a target OS.
# Some actions don't operate on a single OS instance and therefore
# don't need -OsVersion. ListPhases, EnvironmentInfoOnly, Cleanup,
# and the Admin actions (RefreshSnapshots, RefreshAllBaselines,
# DumpFieldClassification) operate on the
# on-disk Config files or the script itself.
$osLessActions = @('ListPhases','Cleanup','RefreshSnapshots','RefreshAllBaselines','DumpFieldClassification','TestHarness')
$needsOsVersion = ($Action -notin $osLessActions) -and (-not $EnvironmentInfoOnly)
if ($needsOsVersion -and [string]::IsNullOrEmpty($OsVersion)) {
    throw '-OsVersion is required for action "' + $Action + '". Specify Server2016 / Server2019 / Server2022 / Server2025.'
}

# ============================================================
# Initial setup
# ============================================================

$ErrorActionPreference = 'Stop'
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

# >>> CANONICAL unit_id=pwsh.helper.set-tlssecurityprotocol version=1.0.0 hash=137ffea3b2034e15 policy=canonical binding=follow-latest >>>
function Set-TlsSecurityProtocol {
    # ====================================================================
    # Enable TLS for outbound HTTPS calls with best-effort multi-version
    # fallback. Tls12 is the baseline (required by most modern endpoints
    # including AMD/Microsoft download servers and Speaker Deck CDN).
    # Tls13 is added when the running .NET supports it (Framework 4.8+,
    # PowerShell 7+, WS2022 / WS2025). Tls11 and Tls (1.0) are added as
    # a defensive fallback for very old environments (WS2016 / WS2019
    # with stock .NET); modern hosts will negotiate Tls13/Tls12 and the
    # legacy bits are ignored by the server. Each enum lookup is wrapped
    # in try/catch because older .NET runtimes raise an enum-value error
    # for protocols they don't recognise.
    # ====================================================================
    $protos = [Net.SecurityProtocolType]::Tls12
    try { $protos = $protos -bor [Net.SecurityProtocolType]::Tls13 } catch { } # psa-disable-line PSA3004 -- Tls13 enum may not exist on older .NET
    try { $protos = $protos -bor [Net.SecurityProtocolType]::Tls11 } catch { } # psa-disable-line PSA3004 -- defensive legacy fallback for very old environments
    try { $protos = $protos -bor [Net.SecurityProtocolType]::Tls   } catch { } # psa-disable-line PSA3004 -- defensive legacy fallback for very old environments
    [Net.ServicePointManager]::SecurityProtocol = $protos
}
# <<< CANONICAL unit_id=pwsh.helper.set-tlssecurityprotocol <<<

# Apply host configuration immediately so every subsequent write goes
# through the right encoding and every HTTPS call uses TLS 1.2.
Set-Utf8PipelineEncoding
Set-TlsSecurityProtocol

# ============================================================
# Path resolution (relative to the script, not the caller's CWD)
# ============================================================
# Resolve $Script:ScriptRoot once, then make every relative path
# (-WorkRoot, -OutputDir, -LogFile) absolute against it. This guarantees
# that running the script from any folder always lands in the same
# workspace.
$Script:ScriptRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($Script:ScriptRoot)) {
    if ($MyInvocation.MyCommand.Path) {
        $Script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
}
if ([string]::IsNullOrEmpty($Script:ScriptRoot)) {
    $Script:ScriptRoot = (Get-Location).Path
}

# >>> CANONICAL unit_id=pwsh.helper.resolve-relativetoscript version=1.0.0 hash=a5655b401eeda2b5 policy=canonical binding=follow-latest >>>
function Resolve-RelativeToScript {
    # Make a path absolute. Relative paths resolve against $Script:ScriptRoot.
    param([Parameter(Mandatory)] [string]$Path)
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $Script:ScriptRoot $Path
    }
    return [System.IO.Path]::GetFullPath($Path)
}
# <<< CANONICAL unit_id=pwsh.helper.resolve-relativetoscript <<<

# -----------------
# Workspace tree resolution
# -----------------
# The ISO Updater workspace layout is documented in SPEC.md Part B.2.
# All sub-directories are derived from $Script:WorkRoot so a single
# -WorkRoot override re-bases the whole tree (used heavily on CI where
# only D: has enough free space).

$Script:WorkRoot   = Resolve-RelativeToScript $WorkRoot

if ([string]::IsNullOrEmpty($OutputDir)) {
    $Script:OutputDir = Join-Path $Script:WorkRoot 'output'
} else {
    $Script:OutputDir = Resolve-RelativeToScript $OutputDir
}

$Script:SourceDir         = Join-Path $Script:WorkRoot 'source'
$Script:IsoSourceDir      = Join-Path $Script:SourceDir 'iso'
$Script:ExtractedDir      = Join-Path $Script:SourceDir 'extracted'
$Script:PatchesDir        = Join-Path $Script:WorkRoot 'patches'
$Script:ManifestsDir      = Join-Path $Script:PatchesDir 'manifests'
$Script:MountInstallDir   = Join-Path $Script:WorkRoot 'work\mount_install'
$Script:MountBoot1Dir     = Join-Path $Script:WorkRoot 'work\mount_boot_idx1'
$Script:MountBoot2Dir     = Join-Path $Script:WorkRoot 'work\mount_boot_idx2'
$Script:MountWinReDir     = Join-Path $Script:WorkRoot 'work\mount_winre'
$Script:TempDir           = Join-Path $Script:WorkRoot 'work\temp'
$Script:ScratchDir        = Join-Path $Script:WorkRoot 'work\scratch'
$Script:LogsDir           = Join-Path $Script:WorkRoot 'logs'
$Script:DiagDir           = Join-Path $Script:WorkRoot 'diag'
$Script:MarkersDir        = Join-Path $Script:WorkRoot '.markers'
$Script:StateDir          = Join-Path $Script:WorkRoot 'state'

# >>> CANONICAL unit_id=pwsh.helper.initialize-runtimedirectories version=1.0.0 hash=30bff32f7d40fca8 policy=canonical binding=follow-latest >>>
function Initialize-RuntimeDirectories { # psa-disable-line PSA6003 -- canonical unit_id retained; noun stays plural by design
    <#
    .SYNOPSIS
        Idempotently (re-)create a set of runtime directories.
    .DESCRIPTION
        Canonical, parameterized form: the caller passes its own directory
        list (each consumer's workspace layout is its own concern); the
        idempotent create loop is the shared canonical logic. Supersedes the
        former per-tool bodies that hard-coded their own $Script: directory
        sets (reconciled at P2.2/P2.3, ADR-tracked).
    .PARAMETER Directory
        One or more directory paths to ensure exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Directory
    )
    foreach ($d in $Directory) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}
# <<< CANONICAL unit_id=pwsh.helper.initialize-runtimedirectories <<<

# ============================================================
# Script version identification
# ============================================================
# These constants are bumped manually whenever the script is edited.
# They are displayed in the startup banner and in each phase header
# so the user can verify which revision is running.
#
#   ScriptVersion : bump on every meaningful edit. Format: <prefix>-YYYY.MM.DD-rNN
#   ScriptTag     : short human-readable label describing the build
#   ScriptHash    : auto-computed SHA256 (first 12 chars) of the actual
#                   file being executed. Changes for any byte-level edit;
#                   does NOT need manual bumping.
$Script:ScriptVersion = 'update-wsi-2026.06.27-r11.38'
$Script:ScriptTag     = 'dism-scratchdir-localisation'
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
$Script:ScriptShortTag = ('{0}/{1}' -f $Script:ScriptVersion, $Script:ScriptHash)

# ============================================================
# Timing and phase tracking state
# ============================================================
$Script:ScriptStartTime   = Get-Date
$Script:CurrentPhaseStart = $null
$Script:CurrentPhaseId    = $null
$Script:PhaseTimings      = New-Object System.Collections.Generic.List[object]
# Idempotency guard for Show-PhaseSummary. P13 FinalReport prints
# the timing table as part of its body (per SPEC.md Part B.5 Step 1);
# the script-tail `finally` block also calls Show-PhaseSummary as a
# safety net for runs that abort before P13. This flag stops the
# safety-net call from printing a duplicate table on a happy-path run.
$Script:PhaseSummaryShown = $false

# Shared data-contract identity: the single source of truth for cross-cutting
# data-quality checks. Stamped into every generated data artifact's _meta
# (the config-Server*.json baselines and the cache-*.json data files) and
# validated across artifacts by Test-DataContractConsistency, so one
# comparison validates the whole set instead of reconciling independent
# per-model schema versions. DataContractVersion is bumped on any breaking
# shape change to any data model.
$Script:DataContractId      = '4c173c61-c099-4512-9283-f5d951beda8b'
$Script:DataContractVersion = 1

# Phase Registry: declared up front so -Action ListPhases can work
# without running any phase functions. Func names are bound by
# convention; Invoke-PhaseRunner resolves them via Get-Command.
$Script:PhaseRegistry = @(
    [pscustomobject]@{ Id='P01';   Name='Initialize';                Group='Setup';  Func='Invoke-SetupPhase01_Initialize' }
    [pscustomobject]@{ Id='P02';   Name='ResolveInputs';             Group='Setup';  Func='Invoke-SetupPhase02_ResolveInputs' }
    [pscustomobject]@{ Id='P03';   Name='RefreshPatchBaseline';    Group='Setup';  Func='Invoke-SetupPhase03_RefreshPatchBaseline' }
    [pscustomobject]@{ Id='P04';   Name='FetchAssets';               Group='Fetch';  Func='Invoke-FetchPhase04_FetchAssets' }
    [pscustomobject]@{ Id='P05';   Name='ExpandIso';                 Group='Plan';   Func='Invoke-PlanPhase05_ExpandIso' }
    [pscustomobject]@{ Id='P06';   Name='ValidatePatchServicing'; Group='Plan';   Func='Invoke-PlanPhase06_ValidatePatchServicing' }
    [pscustomobject]@{ Id='P07';   Name='PatchInstallWim';           Group='Build';  Func='Invoke-BuildPhase07_PatchInstallWim' }
    [pscustomobject]@{ Id='P08';   Name='PatchBootWim';              Group='Build';  Func='Invoke-BuildPhase08_PatchBootWim' }
    [pscustomobject]@{ Id='P09';   Name='AssembleIso';               Group='Build';  Func='Invoke-BuildPhase09_AssembleIso' }
    [pscustomobject]@{ Id='P10';   Name='ConvertPca2023BootManager'; Group='Build';  Func='Invoke-BuildPhase10_ConvertPca2023BootManager' }
    [pscustomobject]@{ Id='P11';   Name='StaticVerify';              Group='Verify'; Func='Invoke-VerifyPhase11_StaticVerify' }
    [pscustomobject]@{ Id='P12';   Name='VerifyPca2023Readiness';    Group='Verify'; Func='Invoke-VerifyPhase12_VerifyPca2023Readiness' }
    [pscustomobject]@{ Id='P13';   Name='FinalReport';               Group='Report'; Func='Invoke-ReportPhase13_FinalReport' }
    [pscustomobject]@{ Id='A01';   Name='RefreshAllBaselines';       Group='Admin';  Func='Invoke-AdminPhaseA01_RefreshAllBaselines' }
    [pscustomobject]@{ Id='A02';   Name='DumpFieldClassification';   Group='Admin';  Func='Invoke-AdminPhaseA02_DumpFieldClassification' }
    [pscustomobject]@{ Id='A03';   Name='RefreshSnapshots';          Group='Admin';  Func='Invoke-AdminPhaseA03_RefreshSnapshots' }
)

# OS Config field classification: drives the RefreshAllBaselines
# decision matrix. Each entry maps a logical field group to a refresh
# cadence and an optional Refresher function. The Path uses "<lang>" as
# a placeholder substituted at runtime for each SupportedLanguages entry.
#
# Cadence semantics:
#   Stable       - Field is OS-wide constant; once verified, never auto-refresh
#   PatchTuesday - Field is monthly cumulative; refresh when recorded
#                  PatchTuesdayOfBaseline < latest Patch Tuesday
#   IsoRelease   - Field changes only on Microsoft media re-release;
#                  not auto-refreshed currently (manual confirmation)
#
# Refresher: PowerShell function to call when refresh is needed.
# $null means no automated refresh; values must be populated manually.
$Script:OsConfigFieldGroups = @(
    [pscustomobject]@{
        Path        = 'Common'
        Cadence     = 'Stable'
        Refresher   = $null
        Description = 'OS-wide constants: build number, edition, WIM index, etc.'
    }
    [pscustomobject]@{
        Path        = 'PatchBaseline'
        Cadence     = 'PatchTuesday'
        Refresher   = 'Invoke-CatalogPatchSetRefresh'
        Description = 'Neutral patches (SSU/LCU/.NET CU/DU.*) shared across all languages.'
    }
    [pscustomobject]@{
        Path        = 'LanguageSpecific.<lang>.Iso'
        Cadence     = 'IsoRelease'
        Refresher   = $null
        Description = 'Per-language ISO source URL and checksums.'
    }
    [pscustomobject]@{
        Path        = 'LanguageSpecific.<lang>.LanguageSpecificPatches'
        Cadence     = 'PatchTuesday'
        Refresher   = 'Resolve-LanguageSpecificPatchesFromCatalog'
        Description = 'Per-language LP / LXP / .NET satellite updates.'
    }
)

# Patch-to-WIM-target mapping: drives which WIMs each Type of
# patch is applied to, per Microsoft's media-dynamic-update servicing
# sequence documented at
# https://learn.microsoft.com/windows/deployment/update/media-dynamic-update.
#
# Target values:
#   Install : install.wim (main OS image)
#   Boot    : boot.wim    (both index 1 and index 2)
#   WinRE   : winre.wim   (recovery environment inside install.wim)
#   Setup   : setup binaries (registered via pending.xml; not WIM-mounted)
#
# A patch may target multiple WIMs. Phase workers (P07/P08) iterate the
# active target set and apply only the patches whose Type maps to that
# target. Unknown Types are treated as Install-only with a warning.
#
# Microsoft public guidance behind this mapping:
#   - SSU                    : required on every serviced WIM
#   - LCU                    : Install + Boot (WinRE uses SafeOS DU instead)
#   - DotNet.Runtime         : Install only (.NET 4.x runtime KB lives in install.wim)
#   - DotNet.OsLevel         : recorded only; OS-offering KB not applied to any WIM
#   - DynamicUpdate.Component: Install only (component-store updates)
#   - DynamicUpdate.SafeOs   : WinRE only (WinRE is the "Safe OS")
#   - DynamicUpdate.Setup    : Setup binaries (handled via pending.xml)
#   - LanguagePack           : Install + WinRE (user-facing UI + recovery UI)
#   - LXP                    : Install only (LXPs are Store apps; no WinRE)
#   - DotNet.LangPack        : Install only (.NET satellite assemblies)
$Script:PatchTargetMap = @{
    # Kind -> WIM targets (Config Schema v3.0 / data-source migration). Neutral Kinds:
    'SSU'             = @('Install', 'Boot', 'WinRE')
    'LCU'             = @('Install', 'Boot')
    'DotNet'          = @('Install')
    'SafeOSDU'        = @('WinRE')
    'SetupDU'         = @('Setup')
    # Language-specific Kinds (produced by Resolve-LanguageSpecificPatchesFromCatalog):
    'LanguagePack'    = @('Install', 'WinRE')
    'LXP'             = @('Install')
    'DotNet.LangPack' = @('Install')
}

# Pre-apply dependency closure check policy.
# When a phase worker is about to Add-WindowsPackage a patch with a
# non-empty RequiresKbIds list, it first calls Get-WindowsPackage
# against the mounted image and verifies that every required KB is
# already present in the package store. Failure to find a required KB
# results in a strict error (the run aborts) so DISM 0x800f0823
# (servicing-stack precondition) is surfaced before DISM itself emits
# the cryptic hex code. The strict-mode toggle exists so the user can
# downgrade to warn-only via $Script:PatchDependencyPolicy = 'Warn'
# (no CLI flag yet; reserved for a future release if demand arises).
$Script:PatchDependencyPolicy = 'Strict'  # 'Strict' | 'Warn'

# Run-state carriers populated by phases; accessed by later phases. The
# OS profile is hydrated by P02 and used by every subsequent build phase.
$Script:OsProfile        = $null
$Script:OsLangProfile    = $null
$Script:IsoLocalPath     = $null
$Script:IsoSha256        = $null
$Script:ResolvedPatches  = @()
$Script:PatchPlan        = $null     # hashtable; built by Build-PatchPlan in P02
$Script:WimIndexInventory = @()
# Most recent supersedence-dedup exclusions emitted by
# Resolve-PatchSetFromReleaseInfo. The A01 and P02 callers read this to
# produce a per-run CSV report. Reset to @() on each new Resolve call.
$Script:LastSupersedenceExclusions = @()
$Script:OutputIsoPath    = $null


# ============================================================
# SECTION 1b: Debug Trace Facility
# ============================================================
# A reusable diagnostic helper used to pinpoint the exact failing
# operation inside a complex function body. Three integrated
# subsystems:
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
# This complements the per-phase errors log emitted by
# Add-ErrorJsonlEntry into $Script:ErrorsJsonlPath: DebugTrace is
# cross-phase and tracks operation-level steps, while Add-ErrorJsonlEntry
# is phase-scoped and records discrete failure events. Both coexist
# without overlap.
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

# >>> CANONICAL unit_id=pwsh.helper.debugtrace-nextseq version=1.0.0 hash=40affbda93e0dc92 policy=canonical binding=follow-latest >>>
function _DebugTrace_NextSeq {
    # Atomic-ish counter. Single-threaded PowerShell so no Interlocked
    # needed; this is just a small helper for readability.
    $Script:DebugTraceEventSeq++
    return $Script:DebugTraceEventSeq
}
# <<< CANONICAL unit_id=pwsh.helper.debugtrace-nextseq <<<

# >>> CANONICAL unit_id=pwsh.helper.debugtrace-now version=1.0.0 hash=6cef1239adbe85aa policy=canonical binding=follow-latest >>>
function _DebugTrace_Now {
    # Return current time as ISO 8601 string with milliseconds and Z
    # suffix. Pre-converted to string so ConvertTo-Json doesn't render
    # the PS 5.1 legacy /Date(N)/ format - we want the same machine-
    # readable representation regardless of PS version.
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}
# <<< CANONICAL unit_id=pwsh.helper.debugtrace-now <<<

# >>> CANONICAL unit_id=pwsh.helper.debugtrace-writejsonlline version=1.0.0 hash=2a6dab2b78cdec25 policy=canonical binding=follow-latest >>>
function _DebugTrace_WriteJsonlLine {
    # Append one JSONL line to the debugtrace.jsonl file (or to the
    # pre-activation buffer if file output isn't enabled yet). All
    # failures are absorbed so the script body is never disrupted by
    # trace bookkeeping.
    #
    # The parameter is named $EventObject (rather than the more natural
    # $Event) because $Event is a PowerShell automatic variable populated
    # inside event-subscriber action blocks (Register-ObjectEvent,
    # Register-WmiEvent, etc.). Reusing the name would shadow that
    # built-in and silently misbehave if this function were ever called
    # from inside such a block. See PSScriptAnalyzer rule
    # PSAvoidAssignmentToAutomaticVariable.
    param([Parameter(Mandatory)] $EventObject)

    # Add monotonic sequence number for stable cross-event ordering.
    $EventObject | Add-Member -MemberType NoteProperty -Name 'seq' -Value (_DebugTrace_NextSeq) -Force

    try {
        $json = $EventObject | ConvertTo-Json -Depth $Script:DebugTraceJsonDepth -Compress
    } catch {
        # If JSON conversion fails (e.g. circular reference somewhere),
        # fall back to a minimal hand-written line so we still record
        # something.
        $Script:DebugTraceJsonlErrorCount++
        $Script:DebugTraceJsonlLastError = $_.Exception.Message
        $kind = if ($EventObject.PSObject.Properties['kind']) { $EventObject.kind } else { 'unknown' }
        $ctx  = if ($EventObject.PSObject.Properties['ctx'])  { $EventObject.ctx  } else { '?' }
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
# <<< CANONICAL unit_id=pwsh.helper.debugtrace-writejsonlline <<<

# >>> CANONICAL unit_id=pwsh.helper.debugtrace-retireframe version=1.0.0 hash=d6ed295961b4416e policy=canonical binding=follow-latest >>>
function _DebugTrace_RetireFrame {
    # Move a frame from the active stack into the completed list.
    # Handles the history cap. Idempotent: safe to call even if the
    # frame has already been retired.
    param([Parameter(Mandatory)] $Frame, [Parameter(Mandatory)] [string]$Outcome)

    if (-not $Frame.PSObject.Properties['Outcome'] -or -not $Frame.Outcome) {
        $Frame | Add-Member -MemberType NoteProperty -Name 'Outcome'   -Value $Outcome -Force
        $Frame | Add-Member -MemberType NoteProperty -Name 'EndedAt'   -Value (Get-Date) -Force
        $durationMs = [int]((Get-Date) - $Frame.StartTime).TotalMilliseconds
        $Frame | Add-Member -MemberType NoteProperty -Name 'DurationMs' -Value $durationMs -Force
    }

    $Script:DebugTraceCompletedFrames.Add($Frame) | Out-Null
    while ($Script:DebugTraceCompletedFrames.Count -gt $Script:DebugTraceCompletedCap) {
        $Script:DebugTraceCompletedFrames.RemoveAt(0)
    }
}
# <<< CANONICAL unit_id=pwsh.helper.debugtrace-retireframe <<<

# --- 1b.3: Public API - trace primitives ----------------------

# >>> CANONICAL unit_id=pwsh.helper.start-debugtrace version=1.0.0 hash=351f92779b47d079 policy=canonical binding=follow-latest >>>
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
        Optional phase identifier (e.g. 'P07'). When set, the frame is
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
# <<< CANONICAL unit_id=pwsh.helper.start-debugtrace <<<

# >>> CANONICAL unit_id=pwsh.helper.set-debugstep version=1.0.0 hash=0ff66497b3b281c8 policy=canonical binding=follow-latest >>>
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
# <<< CANONICAL unit_id=pwsh.helper.set-debugstep <<<

# >>> CANONICAL unit_id=pwsh.helper.stop-debugtrace version=1.0.0 hash=241736610d82b7d1 policy=canonical binding=follow-latest >>>
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
# <<< CANONICAL unit_id=pwsh.helper.stop-debugtrace <<<

# >>> CANONICAL unit_id=pwsh.helper.format-debugfailure version=1.0.0 hash=0ed20da6d346d5b8 policy=canonical binding=follow-latest >>>
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
    [OutputType([pscustomobject])]
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
# <<< CANONICAL unit_id=pwsh.helper.format-debugfailure <<<

# >>> CANONICAL unit_id=pwsh.helper.write-debugfailurereport version=1.0.0 hash=8c1dda9940c309c1 policy=canonical binding=follow-latest >>>
function Write-DebugFailureReport {
    <#
    .SYNOPSIS
        Emit a formatted failure report via Write-Caution + log the
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

    Write-Caution ("{0}: FAILED at step '{1}' (elapsed {2:F2}s)" -f $r.Context, $r.FailedStep, $r.Elapsed.TotalSeconds)
    Write-Caution ("  ExType   : {0}" -f $r.ExType)
    Write-Caution ("  Message  : {0}" -f $r.ExMessage)
    if ($r.InnerType) {
        Write-Caution ("  Inner    : {0} - {1}" -f $r.InnerType, $r.InnerMessage)
    }
    if ($r.FullyQualifiedId) {
        Write-Caution ("  FQErrId  : {0}" -f $r.FullyQualifiedId)
    }
    if ($r.ScriptStackTrace) {
        $stackLines = $r.ScriptStackTrace -split "`r?`n"
        Write-Caution ("  Stack    : {0}" -f $stackLines[0])
        $maxStack = [Math]::Min(3, $stackLines.Count)
        for ($i = 1; $i -lt $maxStack; $i++) {
            Write-Caution ("             {0}" -f $stackLines[$i])
        }
    }
    if ($IncludeStepHistory -and $r.StepHistory.Count -gt 0) {
        Write-Caution ("  Steps    : {0} recorded" -f $r.StepHistory.Count)
        $firstAt = $r.StepHistory[0].At
        foreach ($h in $r.StepHistory) {
            $rel = ($h.At - $firstAt).TotalMilliseconds
            Write-Caution ('    +{0,7:F0}ms  {1}' -f $rel, $h.Step)
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
            Write-Caution ("  TraceJson: {0}" -f $exportPath)
        } catch {
            # Don't let auto-export failures hide the original error.
            Write-Caution ("  TraceJson: auto-export failed: {0}" -f $_.Exception.Message)
        }
    }
}
# <<< CANONICAL unit_id=pwsh.helper.write-debugfailurereport <<<

# --- 1b.4: Public API - file output ---------------------------

# >>> CANONICAL unit_id=pwsh.helper.enable-debugtracefileoutput version=1.0.0 hash=e87c4ef0ecc70f94 policy=canonical binding=follow-latest >>>
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
# <<< CANONICAL unit_id=pwsh.helper.enable-debugtracefileoutput <<<

# >>> CANONICAL unit_id=pwsh.helper.disable-debugtracefileoutput version=1.0.0 hash=0dc4d90f4368280a policy=canonical binding=follow-latest >>>
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
# <<< CANONICAL unit_id=pwsh.helper.disable-debugtracefileoutput <<<

# >>> CANONICAL unit_id=pwsh.helper.get-debugtracefileoutputstatus version=1.0.0 hash=e03887fcc4e39fd3 policy=canonical binding=follow-latest >>>
function Get-DebugTraceFileOutputStatus { # psa-disable-line PSA6003 -- "Status" is singular; analyzer false positive on compound name
    <#
    .SYNOPSIS
        Return the current state of the JSONL writer for diagnostics.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
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
# <<< CANONICAL unit_id=pwsh.helper.get-debugtracefileoutputstatus <<<

# --- 1b.5: Public API - JSON Export ---------------------------

# >>> CANONICAL unit_id=pwsh.helper.enable-autoexportonphasefailure version=1.0.0 hash=81f2415bbc83f281 policy=canonical binding=follow-latest >>>
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
    param(
        [Parameter(Mandatory)] [string]$OutputDirectory
    )
    $Script:DebugTraceAutoExportEnabled = $true
    $Script:DebugTraceAutoExportDir     = $OutputDirectory
}
# <<< CANONICAL unit_id=pwsh.helper.enable-autoexportonphasefailure <<<

# >>> CANONICAL unit_id=pwsh.helper.export-debugtracejson version=1.0.0 hash=d23eeab86dc4fc3a policy=canonical binding=follow-latest >>>
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

# ============================================================
# Display utilities
# ============================================================

# >>> CANONICAL unit_id=pwsh.helper.format-elapsed version=1.0.0 hash=b63f12c32ee28520 policy=canonical binding=follow-latest >>>
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
# <<< CANONICAL unit_id=pwsh.helper.format-elapsed <<<

# >>> CANONICAL unit_id=pwsh.helper.get-phaseelapsedtag version=1.0.0 hash=79f7a70e60311a27 policy=canonical binding=follow-latest >>>
function Get-PhaseElapsedTag {
    # Returns elapsed-since-current-phase-start as '[+X.XXs]' or empty.
    if ($null -eq $Script:CurrentPhaseStart) { return '' }
    $span = (Get-Date) - $Script:CurrentPhaseStart
    return ('[+{0}]' -f (Format-Elapsed $span))
}
# <<< CANONICAL unit_id=pwsh.helper.get-phaseelapsedtag <<<

# >>> CANONICAL unit_id=pwsh.helper.logline version=1.0.0 hash=de5d6e6301d19d87 policy=canonical binding=follow-latest >>>
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
# <<< CANONICAL unit_id=pwsh.helper.logline <<<

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
# and Write-Information but not Write-Caution / Write-Skip / Write-Step.
# >>> CANONICAL unit_id=pwsh.helper.write-step version=1.0.0 hash=257272636c6d4122 policy=canonical binding=follow-latest >>>
function Write-Step  { param($Msg) _LogLine '[*]' $Msg 'Cyan'     }
# <<< CANONICAL unit_id=pwsh.helper.write-step <<<
# >>> CANONICAL unit_id=pwsh.helper.write-ok version=1.0.0 hash=383749ef0ee509b4 policy=canonical binding=follow-latest >>>
function Write-Ok    { param($Msg) _LogLine '[+]' $Msg 'Green'    }
# <<< CANONICAL unit_id=pwsh.helper.write-ok <<<
# >>> CANONICAL unit_id=pwsh.helper.write-caution version=1.0.0 hash=29f499cc2213fcc6 policy=canonical binding=follow-latest >>>
function Write-Caution  { param($Msg) _LogLine '[!]' $Msg 'Yellow'   }
# <<< CANONICAL unit_id=pwsh.helper.write-caution <<<
# >>> CANONICAL unit_id=pwsh.helper.write-fail version=1.0.0 hash=13071c0f83f38048 policy=canonical binding=follow-latest >>>
function Write-Fail  { param($Msg) _LogLine '[X]' $Msg 'Red'      }
# <<< CANONICAL unit_id=pwsh.helper.write-fail <<<
# >>> CANONICAL unit_id=pwsh.helper.write-skip version=1.0.0 hash=1fc992418d41baad policy=canonical binding=follow-latest >>>
function Write-Skip  { param($Msg) _LogLine '[~]' $Msg 'DarkGray' }
# <<< CANONICAL unit_id=pwsh.helper.write-skip <<<
# >>> CANONICAL unit_id=pwsh.helper.write-detail version=1.0.0 hash=7fa6224e26175e15 policy=canonical binding=follow-latest >>>
function Write-Detail {
    # ====================================================================
    # Continuation / detail line for a preceding marker line, or a row
    # inside a section banner block (Show-PowerShellEnvironment,
    # Show-OperatingSystemDetail, Show-SecureBootBaselineSnapshot, etc.).
    # Renders 4-space-indented plain text with NO timestamp or marker
    # prefix, so it visually attaches to the preceding context.
    #
    # ---- Introduced to replace bare `Write-Host " XXX"` calls ----
    # Previously the scripts emitted ~100 bare Write-Host calls with a
    # hard-coded 4-space indent. Routing those through a single helper
    # makes future column-layout tweaks possible without touching every
    # call site, and gives the SPEC-mandated marker pattern a single
    # documented exception ("continuation row of a marker line").
    #
    # The 4-space indent is intentional and matches the historical
    # column convention used inside section-banner tables.
    #
    # -NoNewline mirrors Write-Host's switch and is used by two-part
    # lines that compose a label-then-value pair (e.g. P08's
    # "-> Selected /os:" + colored value).
    # ====================================================================
    param(
        [Parameter(Position=0)][string]$Msg,
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host ("    {0}" -f $Msg) -ForegroundColor $Color -NoNewline
    } else {
        Write-Host ("    {0}" -f $Msg) -ForegroundColor $Color
    }
}
# <<< CANONICAL unit_id=pwsh.helper.write-detail <<<

# >>> CANONICAL unit_id=pwsh.helper.write-subsection version=1.0.0 hash=524c6903ce0d76ea policy=canonical binding=follow-latest >>>
function Write-SubSection {
    # Lightweight section break inside a phase (e.g. [Step A]/[Step B]).
    # Prints with a leading blank line and a horizontal rule.
    param([string]$Title)
    Write-Host ''
    Write-Host (' -- ' + $Title + ' ' + ('-' * [Math]::Max(1, 60 - $Title.Length))) -ForegroundColor Gray
}
# <<< CANONICAL unit_id=pwsh.helper.write-subsection <<<

# >>> CANONICAL unit_id=pwsh.helper.write-phaseheader version=1.0.0 hash=a002b1883e7d48ba policy=canonical binding=follow-latest >>>
function Write-PhaseHeader {
    # Prints a magenta banner that opens a phase. Records phase start
    # time so subsequent log lines can show '[+elapsed]'.
    #
        #   Id    : short identifier (e.g. 'P01', 'P08', etc; always two digits)
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
# <<< CANONICAL unit_id=pwsh.helper.write-phaseheader <<<

# >>> CANONICAL unit_id=pwsh.helper.write-phasefooter version=1.0.0 hash=762ec88efd33dc33 policy=canonical binding=follow-latest >>>
function Write-PhaseFooter {
    # Closes a phase started by Write-PhaseHeader. Records the elapsed
    # duration in $Script:PhaseTimings (used by run-summary helpers).
    #
    # Idempotent: a second call with the same Id is ignored, so wrapping
    # try/finally blocks do not double-count.
    #
    # Status values:
    #   done    - phase completed successfully
    #   cached  - phase was a no-op because the target state was already met
    #   skipped - phase was intentionally skipped (e.g. -OnlyPhases filter)
    #   failed  - phase threw an exception
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [ValidateSet('done','cached','skipped','failed')] [string]$Status
    )
    foreach ($t in $Script:PhaseTimings) {
        if ($t.Id -eq $Id) { return }
    }
    $color = switch ($Status) {
        'done'    { 'Green' }
        'cached'  { 'DarkGray' }
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

    # Reset so any stray Write-Step/Ok between phases doesn't show a
    # misleading [+X.XXs] tag inherited from the previous phase.
    $Script:CurrentPhaseStart = $null
    $Script:CurrentPhaseId    = $null
}
# <<< CANONICAL unit_id=pwsh.helper.write-phasefooter <<<

# >>> CANONICAL unit_id=pwsh.helper.show-phasesummary version=1.0.0 hash=22ed90223f442cc8 policy=canonical binding=follow-latest >>>
function Show-PhaseSummary {
    <#
    .SYNOPSIS
        End-of-run summary table, one row per executed phase.

    .DESCRIPTION
        Two callers exist by design:
          1. P13 FinalReport (`Invoke-ReportPhase13_FinalReport`),
             which calls this as documented in SPEC.md Part B.5
             Step 1 -- the timing table is part of the FinalReport.
          2. The script-tail `finally` block, which calls this as
             a safety net so that a run aborted before P13 (or in
             the outer catch block) still produces a timing table.

        Without coordination, a happy-path run prints the same
        table twice -- once from P13, once from the finally. To
        avoid that visual duplication while keeping the
        safety-net behaviour intact, this function is idempotent:
        the first call prints the table and records the fact via
        `$Script:PhaseSummaryShown`; subsequent calls return
        without printing. Callers that want to force a re-print
        (rare, for testing) can clear the flag first.

    .PARAMETER Force
        If set, prints the table even if it has already been
        printed in this run. Used for ad-hoc inspection; the
        production callers never set this.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [switch]$Force
    )
    if ($Script:PhaseSummaryShown -and -not $Force) {
        return
    }
    $Script:PhaseSummaryShown = $true

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
# <<< CANONICAL unit_id=pwsh.helper.show-phasesummary <<<

# ============================================================
# Cleanup helpers (used by -Clean / -CleanOnly)
# ============================================================

# >>> CANONICAL unit_id=pwsh.helper.test-dangerouspath version=1.0.0 hash=066df8896cbf4d25 policy=canonical binding=follow-latest >>>
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
# <<< CANONICAL unit_id=pwsh.helper.test-dangerouspath <<<

# >>> CANONICAL unit_id=pwsh.helper.invoke-cleanupdirectories version=1.0.0 hash=54e92fb426d23d2b policy=canonical binding=follow-latest >>>
function Invoke-CleanupDirectories { # psa-disable-line PSA6003 -- "Directories" is plural by design; takes multiple directory args
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
# <<< CANONICAL unit_id=pwsh.helper.invoke-cleanupdirectories <<<
# ============================================================
# Error handling helpers
# ============================================================
# `Add-ErrorJsonlEntry` is the single error-recording API used by the
# phase workers and the registry-driven dispatcher. When a phase or a
# sub-step fails, the catch block appends a one-line JSON record to
# $Script:ErrorsJsonlPath so post-run analysis (jq, grep, log shipping)
# can consume the stream without parsing prose.
#
# Schema (one line per record):
#   {
#     "timestamp"     : ISO-8601 with offset,
#     "scriptVersion" : <ScriptVersion>/<short SHA-256 prefix>,
#     "phase"         : "<PNN>"             (e.g. P03, P07),
#     "kind"          : "<kind>"            (e.g. failure, warning),
#     ...properties from -Properties hashtable, merged in...
#   }
#
# Failures inside Add-ErrorJsonlEntry are deliberately swallowed so the
# main pipeline cannot be derailed by a logging glitch.

# >>> CANONICAL unit_id=pwsh.helper.add-errorjsonlentry version=1.0.0 hash=cecbc2af5da9ce31 policy=canonical binding=follow-latest >>>
function Add-ErrorJsonlEntry {
    <#
    .SYNOPSIS
        Append one structured JSON-Lines record to the run-level errors
        log at $Script:ErrorsJsonlPath.
    .PARAMETER Phase
        Phase identifier (e.g. 'P03', 'P07'). Required.
    .PARAMETER Kind
        Short category label for the entry (e.g. 'failure', 'warning').
        Required.
    .PARAMETER Properties
        Free-form hashtable merged into the JSON object. Keys colliding
        with the well-known fields (timestamp / scriptVersion / phase /
        kind) are silently dropped to protect the reserved schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Phase,
        [Parameter(Mandatory)] [string]$Kind,
        [hashtable]$Properties = @{}
    )

    if ([string]::IsNullOrEmpty($Script:ErrorsJsonlPath)) { return }

    try {
        $obj = [ordered]@{
            timestamp     = (Get-Date).ToString('o')
            scriptVersion = $Script:ScriptShortTag
            phase         = $Phase
            kind          = $Kind
        }
        if ($Properties) {
            foreach ($key in $Properties.Keys) {
                # Reserved keys cannot be overridden
                if ($obj.Contains($key)) { continue }
                $obj[$key] = $Properties[$key]
            }
        }
        $json = $obj | ConvertTo-Json -Compress -Depth 8
        Add-Content -Path $Script:ErrorsJsonlPath -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Logging is best-effort: swallow so the main flow is not disrupted
        $null = $_
    }
}
# <<< CANONICAL unit_id=pwsh.helper.add-errorjsonlentry <<<

# ============================================================
# Common helpers
# ============================================================

# >>> CANONICAL unit_id=pwsh.helper.wait-withjitter version=1.0.0 hash=15aba6cbcbfa9966 policy=canonical binding=follow-latest >>>
function Wait-WithJitter {
    param(
        [double]$BaseSeconds,
        [double]$JitterRange
    )
    $jitter = Get-Random -Minimum (-$JitterRange) -Maximum $JitterRange
    $actualSleep = [Math]::Max(0.1, $BaseSeconds + $jitter)
    Start-Sleep -Milliseconds ([int]($actualSleep * 1000))
}
# <<< CANONICAL unit_id=pwsh.helper.wait-withjitter <<<

function Format-MegabyteCount {
    <#
    .SYNOPSIS
        Render a byte count as an "X.X MB" string with one decimal.
        Used by Invoke-DownloadWithProgress and a few other call
        sites that want consistent MB formatting.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [long]$Bytes
    )
    if ($Bytes -lt 0) { return '0.0 MB' }
    return ('{0:N1} MB' -f ($Bytes / 1MB))
}

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

# ============================================================
# Phase 1: Environment evaluation
# ============================================================

# >>> CANONICAL unit_id=pwsh.helper.show-powershellenvironment version=1.0.0 hash=c7b2d656d36133b9 policy=canonical binding=follow-latest >>>
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWMICmdlet', '',
        Justification = 'Intentional Get-WmiObject fallback path. CIM is the primary path; WMI is the secondary path used only when CIM is constrained (some Server Core / container images). PS 5.1 supports both; PS 7+ exposes Get-WmiObject only when the WMI compatibility module is loaded, which is fine because the script declares PS 5.1+ as its baseline.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseCompatibleCommands', '',
        Justification = 'platform_scope=windows-enhanced (ADR 0013). The Get-CimInstance / Get-WmiObject OS-info path is intentionally Windows-specific: on non-Windows it is guarded by try/catch and degrades gracefully to "(CIM/WMI unavailable)". The function itself is cross-platform and runs everywhere; only this OS-detail section is Windows-enhanced. The compatibility gate flags these Windows-only commands on the PS-7-Linux profile; that is expected and accepted for a windows-enhanced unit, not a defect.')]
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
    # CLR / .NET runtime version. Dual-runtime policy (ADR 0012): report the
    # executing .NET runtime version on BOTH PS 5.1 and PS 7.x, never degrade.
    # $PSVersionTable.CLRVersion exists only on Windows PowerShell 5.1 (and the
    # bare property access throws under StrictMode on PS 7 because the key is
    # absent), so use [System.Environment]::Version - same meaning (a [Version]
    # value), present on EVERY supported runtime (.NET 1.1+).
    # NOTE: RuntimeInformation::FrameworkDescription was considered as a
    # human-readable annotation but REMOVED - it requires .NET Framework 4.7.1+
    # and would throw on older PS 5.1 hosts (.NET 4.5-4.7.0), violating the very
    # dual-runtime policy it was meant to serve (the compatibility static-analysis
    # gate surfaced this). Environment.Version alone is the safe, meaning-
    # preserving choice.
    $runtimeVersion = [System.Environment]::Version
    Write-Host ('    CLR / .NET          : {0}' -f $runtimeVersion)
    # Engine build identity. Dual-runtime policy (ADR 0012): BuildVersion is a
    # Windows PowerShell 5.1-only key (absent on PS 7, so the bare access throws
    # under StrictMode). $PSVersionTable is a PSVersionHashTable, so the
    # StrictMode-safe existence test is .ContainsKey(). Fall back to GitCommitId,
    # the PS 7 engine-build identity, so both runtimes report an engine build.
    if ($pv.ContainsKey('BuildVersion') -and $pv.BuildVersion) {
        Write-Host ('    Engine Build        : {0}' -f $pv.BuildVersion)
    } elseif ($pv.ContainsKey('GitCommitId') -and $pv.GitCommitId) {
        Write-Host ('    Engine Build        : {0}' -f $pv.GitCommitId)
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
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop  # psa-disable-line PSA3006 -- intentional fallback for environments where CIM is constrained; PS 5.1 still supports WMI cmdlets
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
# <<< CANONICAL unit_id=pwsh.helper.show-powershellenvironment <<<

# >>> CANONICAL unit_id=pwsh.helper.assert-powershellcompatibility version=1.0.0 hash=cbe202e59516c121 policy=canonical binding=follow-latest >>>
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
# <<< CANONICAL unit_id=pwsh.helper.assert-powershellcompatibility <<<

function Assert-WorkspacePreflight {
    <#
    .SYNOPSIS
        Phase 1 preflight check: verifies that the on-disk workspace
        is laid out correctly and has enough free space to host an
        end-to-end build.
    .DESCRIPTION
        Two checks, both fatal:

        1. Data directory and config files. The script ships with
           four canonical data/config-Server<N>.json files
           (Server2016, Server2019, Server2022, Server2025) alongside
           the script under the data/ directory. They must exist
           before any Phase runs because Get-ConfigProfile is called
           from P02 (load) and A01 (RefreshAllBaselines) and would
           throw a less helpful error if the file is missing. We
           check up-front, in a single place, with a clear "which
           files are missing" message. See SPEC.md for the
           directory layout.

        2. Drive free space. The default workspace ('Workspace_UpdateWsi',
           relative to the script root) sits on whichever drive hosts
           the script. A full PrepareBuildVerify run consumes:

              ~7 GB  input ISO (one OS)
              ~7 GB  extracted source tree
              ~15 GB mounted install.wim scratch (DISM /Cleanup-Image)
              ~10 GB pulled patches
              ~7 GB  output ISO
              ~5 GB  DISM temp + logs headroom

           ~50 GB strict minimum per OS; we require 100 GB free as a
           safety margin to cover concurrent operations, multiple OS
           iterations, and DISM's component-store growth during /ResetBase.

        Honours -DryRun (the disk check is skipped for dry runs since
        no real bytes will be written). Does NOT honour -SyntheticTestMode
        for the Config check because RefreshAllBaselines still needs
        the JSON files to know which targets to refresh.
    #>
    [CmdletBinding()]
    param()

    # ---- Check 1: data/ directory and config files ----
    $dataDir = Join-Path $Script:ScriptRoot 'data'
    if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
        throw ('Workspace preflight failed: data directory not found at "{0}". The script ships data/config-Server<N>.json alongside Update-WindowsServerIso.ps1; ensure the project tree is intact.' -f $dataDir)
    }
    Write-Step ('Data directory: {0}' -f $dataDir)

    $requiredConfigs = @('config-Server2016.json','config-Server2019.json','config-Server2022.json','config-Server2025.json')
    $missingConfigs  = New-Object System.Collections.Generic.List[string]
    foreach ($cfg in $requiredConfigs) {
        $cfgPath = Join-Path $dataDir $cfg
        if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
            $sz = (Get-Item -LiteralPath $cfgPath).Length
            Write-Ok ('  Found data/{0} ({1} bytes)' -f $cfg, $sz)
        } else {
            $missingConfigs.Add($cfg) | Out-Null
            Write-Fail ('  Missing data/{0}' -f $cfg)
        }
    }
    if ($missingConfigs.Count -gt 0) {
        Add-ErrorJsonlEntry -Phase 'P01' -Kind 'workspace-preflight' -Properties @{
            check          = 'config-files'
            missingFiles   = $missingConfigs.ToArray()
            configDirectory = $dataDir
        }
        throw ('Workspace preflight failed: {0} required config file(s) missing under {1}: {2}. All four data/config-Server<N>.json baselines must be present before the script can run any phase.' -f $missingConfigs.Count, $dataDir, ($missingConfigs -join ', '))
    }

    # ---- Check 2: Drive free space (100 GB minimum) ----
    if ($Script:DryRun) {
        Write-Skip 'DryRun: skipping drive free-space check.'
        return
    }
    $minFreeGB = 100
    $rootSlice = $Script:WorkRoot
    if ($rootSlice.Length -ge 2 -and $rootSlice.Substring(1,1) -eq ':') {
        $driveLetter = $rootSlice.Substring(0, 1)
    } else {
        # UNC or unrooted path; fall back to the script root drive
        $driveLetter = $Script:ScriptRoot.Substring(0, 1)
        Write-Caution ('WorkRoot "{0}" is not on a lettered drive; checking script-root drive {1}: instead.' -f $rootSlice, $driveLetter)
    }
    $psDrive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
    if (-not $psDrive) {
        Add-ErrorJsonlEntry -Phase 'P01' -Kind 'workspace-preflight' -Properties @{
            check        = 'drive-free-space'
            driveLetter  = $driveLetter
            error        = 'PSDrive lookup returned null'
        }
        throw ('Workspace preflight failed: could not resolve drive {0}: for free-space check. This usually means the drive is missing or not a fixed disk.' -f $driveLetter)
    }
    $freeGB = [Math]::Round($psDrive.Free / 1GB, 1)
    Write-Step ('Drive {0}: free space: {1} GB (minimum required: {2} GB)' -f $driveLetter, $freeGB, $minFreeGB)
    if ($freeGB -lt $minFreeGB) {
        Add-ErrorJsonlEntry -Phase 'P01' -Kind 'workspace-preflight' -Properties @{
            check        = 'drive-free-space'
            driveLetter  = $driveLetter
            freeGB       = $freeGB
            requiredGB   = $minFreeGB
        }
        throw ('Workspace preflight failed: drive {0}: has only {1} GB free; {2} GB minimum required to host an end-to-end PrepareBuildVerify run. Free up space or pass -WorkRoot on a larger drive.' -f $driveLetter, $freeGB, $minFreeGB)
    }
    Write-Ok ('Drive {0}: OK ({1} GB free, {2} GB required).' -f $driveLetter, $freeGB, $minFreeGB)

    # ---- Check 3: NTFS filesystem on WorkRoot ----
    # WIM mount + DISM operations rely on NTFS-only features:
    #   - Reparse points (used by Mount-WindowsImage to anchor mount targets)
    #   - Per-stream metadata (DISM /Cleanup-Image relies on this)
    #   - Hard-link semantics (Export-WindowsImage)
    # ReFS lacks some of these in earlier versions; FAT32/exFAT lacks all.
    # Microsoft's own Make2023BootableMedia.ps1 (Initialize-StagingDirectory,
    # secureboot_objects repo) enforces the same constraint with an
    # explicit "must target an NTFS formatted file system" check. We
    # mirror that here so a misconfigured -WorkRoot fails the preflight
    # rather than producing silently corrupt WIM mounts later.
    #
    # Skipped under -DryRun (no actual WIM mounts will happen) and on
    # non-Windows hosts (where Get-Volume is unavailable). For non-Windows
    # the check is silent -- Linux-side validation already happens via
    # the PSScriptAnalyzer / synthetic-test pathway.
    if ($Script:DryRun) {
        Write-Skip 'DryRun: skipping filesystem-type check.'
        return
    }
    if (-not $IsWindows -and (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) { # psa-disable-line PSA2001 -- $IsWindows is a PowerShell 6+ automatic variable; psa.py's AUTO_VARS list predates Core
        # Non-Windows pwsh - synthetic CI path; skip silently.
        return
    }
    try {
        $vol = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop
        $fs  = $vol.FileSystem
        if ($fs -ieq 'NTFS') {
            Write-Ok ('Drive {0}: filesystem OK (NTFS).' -f $driveLetter)
        } else {
            Add-ErrorJsonlEntry -Phase 'P01' -Kind 'workspace-preflight' -Properties @{
                check        = 'filesystem-type'
                driveLetter  = $driveLetter
                fileSystem   = $fs
                required     = 'NTFS'
            }
            throw ('Workspace preflight failed: drive {0}: is formatted as "{1}" but WIM mount + DISM operations require NTFS. Reformat the drive as NTFS or pass -WorkRoot on an NTFS-backed path. (This requirement mirrors Microsoft Make2023BootableMedia.ps1 / Initialize-StagingDirectory, which enforces the same constraint for the same reason.)' -f $driveLetter, $fs)
        }
    } catch [System.Management.Automation.CommandNotFoundException] {
        # Get-Volume not available on older PowerShell or non-Windows
        Write-Caution ('Get-Volume not available; skipping filesystem-type check on drive {0}.' -f $driveLetter)
    } catch {
        # Re-throw the original throw if it was ours
        if ($_.Exception.Message -like 'Workspace preflight failed:*') { throw }
        Write-Caution ('Filesystem-type check could not be completed: {0}' -f $_.Exception.Message)
    } # psa-disable-line PSA3004 -- intentional best-effort filesystem type detection; CommandNotFoundException is expected on non-Windows
}

# ============================================================
# ISO Updater specific: configuration profile
# ============================================================

function Get-ConfigProfile {
    <#
    .SYNOPSIS
        Load the OS profile JSON (Config Schema v3.0) for the given OsKey
        and resolve the language sub-profile for OsLang.
    .DESCRIPTION
        v2.0 layout: top-level keys are Schema, OsKey, Common,
        PatchBaseline, AutoRefreshPolicy, LanguageSpecific.<lang>.
        v2.1 (r05.0+) adds an optional top-level Pca2023 block
        between PatchBaseline and AutoRefreshPolicy.

        This loader accepts Schema "2.0" or "2.1" and returns a flat
        pscustomobject for backward-compatible access patterns used by
        downstream phases: properties from Common are promoted to the
        top level of the returned object, PatchBaseline / Pca2023 (if
        present) / AutoRefreshPolicy are passed through verbatim, the
        resolved language sub-profile is attached as 'Language', and
        the entire LanguageSpecific dictionary is attached as
        'LanguageSpecific' for Action workers (RefreshAllBaselines)
        that need cross-language access.

        Legacy v1.0 configs are NOT supported; the loader throws
        immediately if the Schema field is missing or unrecognised.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsKey,
        [Parameter(Mandatory)] [ValidateSet('en-us','ja-jp')] [string]$OsLang,
        [string]$ConfigRoot
    )

    if ([string]::IsNullOrEmpty($ConfigRoot)) {
        $ConfigRoot = Join-Path $Script:ScriptRoot 'data'
    }
    $cfgFile = Join-Path $ConfigRoot ('config-' + $OsKey + '.json')
    if (-not (Test-Path -LiteralPath $cfgFile)) {
        throw ('Config profile not found: {0}' -f $cfgFile)
    }

    $raw = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8
    $json = $raw | ConvertFrom-CanonicalJson

    # Schema validation (v2.0 and v2.1 both accepted)
    $acceptedSchemas = @('3.0')
    if (-not $json.Schema -or ($acceptedSchemas -notcontains $json.Schema)) {
        throw ('Config {0} has Schema="{1}"; expected one of: {2}. Legacy schemas are not supported.' -f $cfgFile, $json.Schema, ($acceptedSchemas -join ', '))
    }
    if (-not $json.Common) {
        throw ('Config {0} has no Common section.' -f $cfgFile)
    }
    if (-not $json.LanguageSpecific) {
        throw ('Config {0} has no LanguageSpecific section.' -f $cfgFile)
    }
    # v2.1 specifically requires the Pca2023 block (the SecureBoot
    # feature documented in SPEC.md B.18). v2.0 configs without
    # Pca2023 are accepted with a soft warning so older installations
    # can still load while migration to v2.1 is in flight.
    if (-not $json.Pca2023) {
        throw ('Config {0} declares Schema="3.0" but has no Pca2023 block. v3.0 requires Pca2023; see SPEC.md B.10.' -f $cfgFile)
    }
    $langNode = $json.LanguageSpecific.$OsLang
    if ($null -eq $langNode) {
        throw ('Config {0} has no LanguageSpecific entry for "{1}".' -f $cfgFile, $OsLang)
    }

    # Build a flat profile object: promote Common fields to top-level
    # so legacy access patterns like $profile.Build still work, then
    # attach the resolved language sub-profile as 'Language' and the
    # full LanguageSpecific dictionary for cross-lang admin access.
    $merged = [pscustomobject]@{
        Schema                 = $json.Schema
        OsKey                  = $json.OsKey
        PatchModel             = $json.PatchModel
        Build                  = $json.Common.Build
        OsShortName            = $json.Common.OsShortName
        Edition                = $json.Common.Edition
        Architecture           = $json.Common.Architecture
        WimEdition             = $json.Common.WimEdition
        InstallWimIndex        = $json.Common.InstallWimIndex
        BootWimIndexes         = $json.Common.BootWimIndexes
        WinReWimPath           = $json.Common.WinReWimPath
        SupportedLanguages     = $json.Common.SupportedLanguages
        DefaultLanguage        = $json.Common.DefaultLanguage
        LCUExpandViaMum        = $json.Common.LCUExpandViaMum
        # Phase build-enable flags: promoted from Common so the build
        # phases (P07 install.wim patching, P08 boot.wim patching) can
        # access them as $Script:OsProfile.<flag> directly. Documented
        # in SPEC.md B.4. These flags must be promoted explicitly here
        # because PowerShell does not auto-flatten nested PSCustomObject
        # properties; without promotion, callers reading the top-level
        # property receive $null and the corresponding phase becomes
        # unconditionally skipped regardless of profile content.
        EnableInstallWimUpdate = $json.Common.EnableInstallWimUpdate
        EnableBootWimUpdate    = $json.Common.EnableBootWimUpdate
        EnableWinREUpdate      = $json.Common.EnableWinREUpdate
        Common                 = $json.Common
        PatchBaseline          = $json.PatchBaseline
        AutoRefreshPolicy      = $json.AutoRefreshPolicy
        LanguageSpecific       = $json.LanguageSpecific
        Language               = $langNode
        LanguageKey            = $OsLang
        # Raw is exposed for admin actions (RefreshAllBaselines) which
        # need to mutate-and-persist the on-disk JSON shape.
        Raw                    = $json
        ConfigFilePath         = $cfgFile
    }
    return $merged
}

function Get-IsoMetadata {
    <#
    .SYNOPSIS
        Best-effort extraction of OS / build / language from an ISO
        filename, using the four patterns documented in SPEC Part B.0.
    .OUTPUTS
        pscustomobject with Build, Language, Architecture, Pattern; or
        $null if no pattern matches.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string]$IsoPath)

    $name = [System.IO.Path]::GetFileName($IsoPath)
    # Pattern 1: Server 2019/2022/2025 svc_refresh form
    $p1 = '^(?<build>\d{5})\.(?<rev>\d+)\.(?<date>\d{6}-\d{4})\.(?<branch>\w+)_(SERVER|CLIENT)_EVAL_(?<arch>x64FRE)_(?<lang>[a-z]{2}-[a-z]{2})\.iso$'
    # psa-disable-next-line PSA2003 -- $p1 is a local string variable, not bare null
    if ($name -match $p1) {
        return [pscustomobject]@{
            Build = [int]$matches['build']; Language = $matches['lang']
            Architecture = $matches['arch']; Pattern = 'p1_svc_refresh'
        }
    }
    # Pattern 2: Server 2022 initial release
    $p2 = '^SERVER_EVAL_(?<arch>x64FRE)_(?<lang>[a-z]{2}-[a-z]{2})\.iso$'
    # psa-disable-next-line PSA2003 -- $p2 is a local string variable, not bare null
    if ($name -match $p2) {
        return [pscustomobject]@{
            Build = 0; Language = $matches['lang']
            Architecture = $matches['arch']; Pattern = 'p2_initial'
        }
    }
    # Pattern 3: Server 2016 EN refresh form
    $p3 = '^Windows_Server_2016_Datacenter_EVAL_(?<lang>[a-z]{2}-[a-z]{2})_(?<build>\d+)_refresh\.iso$'
    # psa-disable-next-line PSA2003 -- $p3 is a local string variable, not bare null
    if ($name -match $p3) {
        return [pscustomobject]@{
            Build = [int]$matches['build']; Language = $matches['lang']
            Architecture = 'x64'; Pattern = 'p3_ws2016_en'
        }
    }
    # Pattern 4: Server 2016 JA UPPERCASE form
    $p4 = '^(?<build>\d{5})\.(?<rev>\d+)\.(?<date>\d{6}-\d{4})\.(?<branch>\w+)_SERVER_EVAL_X64FRE_(?<lang>[A-Z]{2}-[A-Z]{2})\.ISO$'
    # psa-disable-next-line PSA2003 -- $p4 is a local string variable, not bare null
    if ($name -match $p4) {
        return [pscustomobject]@{
            Build = [int]$matches['build']
            Language = $matches['lang'].ToLower()
            Architecture = 'x64'; Pattern = 'p4_ws2016_ja'
        }
    }
    return $null
}

function Resolve-IsoSourceUrl {
    <#
    .SYNOPSIS
        Pick the final ISO download URL according to the priority
        described in SPEC Part B.4 (explicit -IsoUrl, then Iso.Url
        from the per-language v2.0 config).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $LanguageProfile,
        [string]$ExplicitUrl
    )
    if (-not [string]::IsNullOrEmpty($ExplicitUrl)) {
        return $ExplicitUrl
    }
    # v2.0: per-language ISO source is at .Iso.Url; legacy keys removed.
    if ($LanguageProfile.Iso -and -not [string]::IsNullOrEmpty($LanguageProfile.Iso.Url)) {
        return $LanguageProfile.Iso.Url
    }
    throw 'No ISO URL could be resolved from explicit args or config (LanguageSpecific.<lang>.Iso.Url is empty).'
}

# ============================================================
# ISO Updater specific: Metalink (.meta4) IO
# ============================================================

function Read-MetalinkManifest {
    <#
    .SYNOPSIS
        Parse a Metalink 4 (.meta4) manifest into a list of
        pscustomobjects with FileName, Urls (array), Hashes (hashtable).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ('Manifest not found: {0}' -f $Path)
    }
    [xml]$ml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $ns = New-Object System.Xml.XmlNamespaceManager $ml.NameTable
    $ns.AddNamespace('ml', 'urn:ietf:params:xml:ns:metalink')

    $files = New-Object System.Collections.Generic.List[object]
    foreach ($node in $ml.SelectNodes('//ml:file', $ns)) {
        $hashes = @{}
        foreach ($h in $node.SelectNodes('ml:hash', $ns)) {
            $hashes[$h.type] = ([string]$h.'#text').Trim()
        }
        $urls = @()
        foreach ($u in $node.SelectNodes('ml:url', $ns)) {
            $urls += ([string]$u.'#text').Trim()
        }
        $files.Add([pscustomobject]@{
            FileName = $node.name
            Urls     = $urls
            Hashes   = $hashes
        }) | Out-Null
    }
    return $files
}

function Write-MetalinkManifest {
    <#
    .SYNOPSIS
        Emit a Metalink 4 (.meta4) file from an array of pscustomobjects
        whose shape matches the output of Read-MetalinkManifest. Used
        by -Action GenerateManifest.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Files
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<metalink xmlns="urn:ietf:params:xml:ns:metalink"')
    [void]$sb.AppendLine('          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    [void]$sb.AppendLine('          xsi:noNamespaceSchemaLocation="metalink4.xsd">')
    foreach ($f in $Files) {
        [void]$sb.AppendLine(('  <file name="{0}">' -f $f.FileName))
        foreach ($k in $f.Hashes.Keys) {
            [void]$sb.AppendLine(('    <hash type="{0}">{1}</hash>' -f $k, $f.Hashes[$k]))
        }
        foreach ($u in $f.Urls) {
            [void]$sb.AppendLine(('    <url priority="1">{0}</url>' -f $u))
        }
        [void]$sb.AppendLine('  </file>')
    }
    [void]$sb.AppendLine('</metalink>')

    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    # UTF-8 with BOM to match the participating tools (aria2, abbodi1406)
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), $utf8Bom)
}

# ============================================================
# ISO Updater specific: patch integrity verification
# ============================================================

function Test-PatchIntegrity {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingBrokenHashAlgorithms', '',
        Justification = 'Microsoft Update Catalog publishes SHA-1 hashes alongside SHA-256 for every patch. This function sanity-checks both; SHA-256 (L2c) and Authenticode signature (L3) are the actual trust anchors, SHA-1 (L2a/L2b) is only used for integrity verification against upstream-published metadata.'
    )]
    <#
    .SYNOPSIS
        Three-layer integrity check on a downloaded MSU/CAB patch.
    .DESCRIPTION
        L1: existence + non-zero size
        L2a: SHA-1 in filename matches Metalink SHA-1 (if both present)  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        L2b: actual content SHA-1 matches Metalink SHA-1  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        L2c: actual content SHA-256 matches Metalink SHA-256 (if present)
        L3:  Authenticode signature is Valid and signer is Microsoft
        Throws on any hard failure; returns the verification report
        otherwise.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [hashtable]$ExpectedHashes
    )
    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw ('Patch missing: {0}' -f $FilePath)
    }
    $item = Get-Item -LiteralPath $FilePath
    if ($item.Length -le 0) {
        throw ('Patch is empty: {0}' -f $FilePath)
    }

    $fileName = $item.Name
    $report = [pscustomobject]@{
        FilePath = $FilePath; Size = $item.Length
        Sha1     = $null; Sha256 = $null  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        NameSha1Ok = $null; Sha1Ok = $null; Sha256Ok = $null
        SigStatus = $null; SigSubject = $null
    }

    # L2a: filename embedded SHA-1  # psa-disable-line PSA5003 -- MS Catalog SHA-1
    $sha1InName = $null
    if ($fileName -match '_([a-f0-9]{40})\.(msu|cab)$') {
        $sha1InName = $matches[1].ToLower()
    }

    # L2b: actual SHA-1  # psa-disable-line PSA5003 -- MS Catalog SHA-1
    # NOTE: SHA-1 is broken for adversarial use, but Microsoft Update  # psa-disable-line PSA5003 -- MS Catalog SHA-1
    # Catalog still ships SHA-1 hashes in patch filenames and in the  # psa-disable-line PSA5003 -- MS Catalog SHA-1
    # downloads UI. We use SHA-1 ONLY for integrity sanity-checks against  # psa-disable-line PSA5003 -- MS Catalog SHA-1
    # those upstream-published values, with SHA-256 (below) and the
    # Authenticode signature (L3) as the actual trust anchors.
    if ($ExpectedHashes.ContainsKey('sha-1')) {  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        $expSha1 = $ExpectedHashes['sha-1'].ToLower()  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        if ($sha1InName -and ($sha1InName -ne $expSha1)) {  # psa-disable-line PSA5003 -- MS Catalog SHA-1
            throw ('Filename SHA-1 mismatch on {0}: expected {1}, got {2}' -f $fileName, $expSha1, $sha1InName)  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        }
        $report.NameSha1Ok = $true
        # psa-disable-next-line PSA5003 -- intentional, see comment above
        $actualSha1 = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA1).Hash.ToLower()  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        $report.Sha1 = $actualSha1  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        if ($actualSha1 -ne $expSha1) {  # psa-disable-line PSA5003 -- MS Catalog SHA-1
            throw ('SHA-1 content mismatch on {0}: expected {1}, got {2}' -f $fileName, $expSha1, $actualSha1)  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        }
        $report.Sha1Ok = $true
    }

    # L2c: SHA-256 if provided
    if ($ExpectedHashes.ContainsKey('sha-256')) {
        $expSha256 = $ExpectedHashes['sha-256'].ToLower()
        $actualSha256 = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLower()
        $report.Sha256 = $actualSha256
        if ($actualSha256 -ne $expSha256) {
            throw ('SHA-256 content mismatch on {0}: expected {1}, got {2}' -f $fileName, $expSha256, $actualSha256)
        }
        $report.Sha256Ok = $true
    }

    # L3: Authenticode (best-effort - some CI images may lack the cert store)
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $FilePath
        $report.SigStatus = [string]$sig.Status
        if ($sig.SignerCertificate) {
            $report.SigSubject = $sig.SignerCertificate.Subject
        }
        if ($sig.Status -ne 'Valid') {
            throw ('Authenticode signature invalid on {0}: Status={1}' -f $fileName, $sig.Status)
        }
        if ($sig.SignerCertificate -and ($sig.SignerCertificate.Subject -notlike '*Microsoft*')) {
            throw ('Not signed by Microsoft: {0}' -f $fileName)
        }
    } catch {
        # Re-throw if the failure came from our own threshold checks above
        if ($_.Exception.Message -match 'Authenticode|Not signed by Microsoft') { throw }
        # Otherwise: cert store unavailable on this host; record but do not fail
        $report.SigStatus = 'Unverifiable: ' + $_.Exception.Message
    }
    return $report
}

# ============================================================
# ISO Updater specific: KB detection helpers
# ============================================================

function Get-PatchKbId {
    # Best-effort: extract a KB ID from an MSU/CAB filename.
    param([Parameter(Mandatory)] [string]$FileName)
    if ($FileName -match 'KB(\d{6,8})') { return ('KB' + $matches[1]) }
    if ($FileName -match 'kb(\d{6,8})') { return ('KB' + $matches[1]) }
    return 'Unknown'
}

function Get-PatchType {
    <#
    .SYNOPSIS
        Heuristic classification of a patch file as SSU / LCU /
        DotNet.Runtime / DynamicUpdate.* / Defender / Edge / Other.
    .DESCRIPTION
        Microsoft does not embed the patch type in the filename in a
        machine-readable way, so the classifier matches against
        well-known token patterns documented in the Update History
        pages. A .NET-bearing filename always classifies as
        DotNet.Runtime because the OS-offering KB (DotNet.OsLevel)
        has no on-disk payload -- it is recorded in the PatchBaseline
        for traceability only and never reaches this function.
    #>
    param([Parameter(Mandatory)] [string]$FileName)
    $n = $FileName.ToLower()
    if ($n -match 'servicingstack' -or $n -match 'ssu')         { return 'SSU' }
    if ($n -match 'ndp[0-9]+'      -or $n -match '\.net')       { return 'DotNet.Runtime' }
    if ($n -match 'safeos')                                     { return 'DynamicUpdate.SafeOs' }
    if ($n -match 'setupdynamic'   -or $n -match 'setup.*dynamic') { return 'DynamicUpdate.Setup' }
    if ($n -match 'dynamicupdate')                              { return 'DynamicUpdate.Component' }
    if ($n -match 'defender')                                   { return 'Defender' }
    if ($n -match 'edge')                                       { return 'Edge' }
    if ($n -match 'kb\d+' -or $n -match 'cumulative')           { return 'LCU' }
    return 'Other'
}

function Get-PatchApplyOrder {
    # Numeric apply order, lower applies first.
    param([Parameter(Mandatory)] [string]$PatchType)
    switch ($PatchType) {
        'SSU'                       { return 1 }
        'DynamicUpdate.Setup'       { return 2 }
        'LCU'                       { return 3 }
        'DynamicUpdate.Component'   { return 4 }
        'DynamicUpdate.SafeOs'      { return 5 }
        'DotNet.Runtime'            { return 6 }
        'DotNet.OsLevel'            { return 99 }
        'Defender'                  { return 7 }
        'Edge'                      { return 8 }
        default                     { return 99 }
    }
}


# ============================================================
# ISO Updater specific: Patch Tuesday calculator and
# PatchBaseline freshness / IO helpers
# ============================================================

function Get-PatchTuesdayForMonth {
    <#
    .SYNOPSIS
        Compute the date of Patch Tuesday (second Tuesday) for a given month.
    .DESCRIPTION
        Microsoft releases Windows monthly quality updates on the second
        Tuesday of each month (US Pacific time). This helper returns the
        date object (no time component) for that day. The caller is
        expected to compare it against the current local date.

        For boundary safety, the comparison logic in callers should add
        a 24-hour buffer (Microsoft does not push exactly at midnight US
        Pacific) so a same-day execution is not flagged as "post Patch
        Tuesday" prematurely.
    #>
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)] [int]$Year,
        [Parameter(Mandatory)] [ValidateRange(1, 12)] [int]$Month
    )
    $first = [datetime]::new($Year, $Month, 1)
    # DayOfWeek: Sunday=0, Monday=1, Tuesday=2, ...
    $offset = (2 - [int]$first.DayOfWeek + 7) % 7
    return $first.AddDays($offset + 7)
}

function Get-LatestPatchTuesday {
    <#
    .SYNOPSIS
        Returns the most recent Patch Tuesday on or before "now".
    .DESCRIPTION
        Uses the local system clock. If "now" is before this month's
        Patch Tuesday, the previous month's value is returned instead.
        A 1-day buffer is applied (see SPEC D.15) to avoid edge cases
        where the script runs during the US-Pacific evening of Patch
        Tuesday while local time has already rolled to Wednesday.
    #>
    [OutputType([datetime])]
    param()
    $now = (Get-Date).Date
    $thisMonth = Get-PatchTuesdayForMonth -Year $now.Year -Month $now.Month
    # Apply 1-day buffer: only treat current-month Patch Tuesday as
    # "already happened" if local date is at least 1 day past it.
    if ($now -ge $thisMonth.AddDays(1)) {
        return $thisMonth
    }
    # Otherwise return previous month's Patch Tuesday
    $prev = $now.AddMonths(-1)
    return Get-PatchTuesdayForMonth -Year $prev.Year -Month $prev.Month
}

function Format-PatchMonthString {
    <#
    .SYNOPSIS
        Format a datetime as 'yyyy-MM' for Patch Month identifiers.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [datetime]$Date)
    return $Date.ToString('yyyy-MM')
}

function Test-PatchBaselineFresh {
    <#
    .SYNOPSIS
        Returns $true if the supplied PatchBaseline is current enough
        to skip the dynamic Catalog refresh.
    .DESCRIPTION
        Returns $false when either:
          - PatchTuesdayOfBaseline is empty (uninitialised), or
          - PatchTuesdayOfBaseline < latest Patch Tuesday, or
          - PatchBaseline.Lines has zero usable entries
        Returns $true otherwise.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Baseline,
        [Parameter(Mandatory)] [datetime]$LatestPatchTuesday
    )
    if (-not $Baseline) { return $false }
    $ptStr = $Baseline.PatchTuesdayOfBaseline
    if ([string]::IsNullOrWhiteSpace($ptStr)) { return $false }
    if (-not ($ptStr -match '^\d{4}-\d{2}-\d{2}$')) { return $false }
    $baselineDate = [datetime]::ParseExact($ptStr, 'yyyy-MM-dd', $null)
    if ($baselineDate -lt $LatestPatchTuesday) { return $false }
    # Also require at least one usable patch entry
    if (-not $Baseline.Lines -or $Baseline.Lines.Count -eq 0) { return $false }
    $usable = @($Baseline.Lines | Where-Object {
        $_.KbId -and $_.DownloadUrl -and $_.Digest -and ($_.Digest -ne '')
    })
    return ($usable.Count -gt 0)
}

function Test-PatchBaselineUsable {
    <#
    .SYNOPSIS
        Returns $true if PatchBaseline.Lines has any usable entry.
        Distinct from Test-PatchBaselineFresh: this one ignores age.
        Used by the fallback-on-scrape-failure path (SPEC C.3).
    #>
    [OutputType([bool])]
    param([Parameter(Mandatory)] [AllowNull()] $Baseline)
    if (-not $Baseline -or -not $Baseline.Lines) { return $false }
    $usable = @($Baseline.Lines | Where-Object {
        $_.KbId -and $_.DownloadUrl -and $_.Digest -and ($_.Digest -ne '')
    })
    return ($usable.Count -gt 0)
}

function Save-ConfigWithBaseline {
    <#
    .SYNOPSIS
        Write the in-memory OsProfile (with updated PatchBaseline) back
        to its Config JSON file, preserving field order where possible.
    .DESCRIPTION
        Used by P03 when AutoRefreshPolicy.WritebackToConfig = $true.
        Emits LF line endings (per repo .gitattributes for *.json) and
        UTF-8 without BOM. Uses Depth 32 to fully serialise patch arrays.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string]$ConfigPath,
        [Parameter(Mandatory)] $OsProfile
    )
    # Stamp the shared data-contract provenance (_meta) so the config is a
    # contract-bearing artifact classified by Test-DataContractConsistency.
    # Only dataContractId + dataContractVersion are read by the classifier;
    # scriptVersion / generatedAt are informational. Refreshed in place on
    # every write (Layer 1 only writes when a verified value actually
    # changed, so unchanged configs are not rewritten). Built with an
    # order-stable [pscustomobject] for canonical-JSON determinism.
    $contractMeta = [pscustomobject]@{
        dataContractId      = $Script:DataContractId
        dataContractVersion = $Script:DataContractVersion
        scriptVersion       = $Script:ScriptVersion
        generatedAt         = ([datetime]::UtcNow).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    if ($OsProfile.PSObject.Properties['_meta']) {
        $OsProfile._meta = $contractMeta
    } else {
        $OsProfile | Add-Member -NotePropertyName '_meta' -NotePropertyValue $contractMeta
    }

    # Persist the OS profile in canonical JSON format (SPEC Part B.23).
    # Save-CanonicalJsonFile handles all of: UTF-8 (no BOM), LF line
    # endings, 2-space indent, ": " separator, trailing newline, and
    # atomic-ish rename. Depth 32 covers the deepest known nesting in
    # PatchBaseline.Patches.
    Save-CanonicalJsonFile -InputObject $OsProfile -Path $ConfigPath -Depth 32
}

function Convert-CatalogPatchToBaselineEntry {
    <#
    .SYNOPSIS
        Convert a Catalog-scraper result tuple into a PatchBaseline entry
        (the structure stored under PatchBaseline.Patches in the Config).
    .DESCRIPTION
        Bridges the Microsoft Update Catalog DTO (UpdateId/Title/DownloadUrl)
        and our PatchBaseline schema (KbId/Type/ApplyOrder/Sha256/...).
        Computes Type and ApplyOrder via the existing classifiers.

        Type resolution priority:
          1. If the caller passes -KnownType (a non-empty string), that
             value is used verbatim. Callers like Resolve-PatchSetFromCatalog
             already know the Catalog query's Type bucket
             (SSU / LCU / DotNet / DynamicUpdate.SafeOs / DynamicUpdate.Setup)
             and should pass it through to avoid the unreliable filename
             heuristic in Get-PatchType.
          2. Otherwise fall back to Get-PatchType -FileName <fn>. This
             remains the path for older callers that have no contextual
             Type info (e.g. tests, ad-hoc invocations).
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$KbId,
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$UpdateId,
        [Parameter(Mandatory)] [string]$DownloadUrl,
        [string]$FileName,
        [long]$SizeBytes = 0,
        [string]$Sha256  = '',
        [string]$ReleaseDate = '',
        [string[]]$Supersedes  = @(),
        [string[]]$RequiresKbIds = @(),
        [string]$ApplicableArchitecture = 'x64',
        [string[]]$ApplicableLanguages  = @('neutral'),
        [string]$KnownType = ''
    )
    $fn = $FileName
    if ([string]::IsNullOrEmpty($fn) -and $DownloadUrl) {
        # Recover filename from URL leaf
        try { $fn = [System.IO.Path]::GetFileName(([uri]$DownloadUrl).AbsolutePath) }
        catch { $fn = '' }
    }
    if (-not [string]::IsNullOrEmpty($KnownType)) {
        $pType = $KnownType
    } else {
        $pType = Get-PatchType -FileName $fn
    }
    $pOrder = Get-PatchApplyOrder -PatchType $pType
    return [pscustomobject][ordered]@{
        Type                   = $pType
        KbId                   = $KbId
        Title                  = $Title
        UpdateId               = $UpdateId
        DownloadUrl            = $DownloadUrl
        FileName               = $fn
        SizeBytes              = $SizeBytes
        Sha256                 = $Sha256
        ReleaseDate            = $ReleaseDate
        Supersedes             = $Supersedes
        RequiresKbIds          = $RequiresKbIds
        ApplyOrder             = $pOrder
        ApplicableArchitecture = $ApplicableArchitecture
        ApplicableLanguages    = $ApplicableLanguages
    }
}

function Get-OsConfigPath {
    <#
    .SYNOPSIS
        Resolve the on-disk path of the active data/config-<OsKey>.json file,
        so the P03 writeback knows where to save.
    .DESCRIPTION
        OS configuration is stored under data/config-<OsKey>.json. See
        SPEC.md for the three-prefix naming scheme
        (config-/cache-/raw-).
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$OsKey)
    $here = $Script:ScriptRoot
    if ([string]::IsNullOrEmpty($here)) { $here = $PSScriptRoot }
    if ([string]::IsNullOrEmpty($here)) { $here = (Get-Location).Path }
    return (Join-Path $here ('data' + [System.IO.Path]::DirectorySeparatorChar + 'config-' + $OsKey + '.json'))
}

# ============================================================
# Windows ADK Deployment Tools installer (P01 auto-install path)
# ============================================================
#
# When P01 Step 3 finds oscdimg.exe missing, the script auto-installs the
# Deployment Tools (no switch, mirroring the 7-Zip Install-SevenZipFallback
# auto-acquire): it downloads adksetup.exe from the Microsoft Learn published
# fwlink and runs it with /features OptionId.DeploymentTools to install
# only the Deployment Tools feature (~50-80 MB), never the full ADK.
#
# Version pinning rationale:
#   ADK 10.1.26100.2454 (December 2024) is the version Microsoft Learn
#   documents as supporting Windows Server 2025, Server 2022, and every
#   earlier supported Windows 10/11 release. Newer Deployment Tools are
#   forward-compatible: oscdimg.exe from this ADK build can assemble
#   ISO images targeting Server 2016 / 2019 / 2022 / 2025 without
#   needing per-OS ADK variants. The later ADK 10.1.28000.1 (November
#   2025) is Windows 11 26H1 Arm64 only and is NOT appropriate for
#   Server x64 work on the host.
#
# The fwlink URL is stable; Microsoft Learn republishes the same linkid
# whenever it serves a new ADK servicing build. If Microsoft retires
# this linkid, bump the constants below in one place.
#
# Reference:
#   https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
#   "Download the ADK 10.1.26100.2454 (December 2024)"

$Script:AdkInstallerUrl      = 'https://go.microsoft.com/fwlink/?linkid=2289980'
$Script:AdkInstallerVersion  = '10.1.26100.2454'
$Script:AdkInstallerOptionId = 'OptionId.DeploymentTools'

# ============================================================
# Windows SDK Signing Tools installer (signtool.exe acquisition)
# ============================================================
#
# signtool.exe ships in the Windows SDK (NOT the ADK Deployment
# Tools), under Windows Kits\10\bin\<ver>\<arch>\signtool.exe. It
# is acquired with the SAME install-if-missing idiom this script
# already uses for 7-Zip (Get-SevenZipPath / Install-SevenZipFallback)
# and ADK/oscdimg (Resolve-OscdimgExe / Install-WindowsAdkFallback),
# mirroring the Install-WindowsSdkFallback pattern in
# Deploy-AMDChipsetDriverOnWindowsServer.ps1.
#
# Version pinning rationale:
#   winsdksetup.exe is fetched from the Microsoft-published fwlink
#   (linkid=2338977, Windows SDK 10.0.26100.6584) and run with
#   /features OptionId.SigningTools so ONLY the Signing Tools feature
#   (signtool.exe) is installed, never the full SDK. The fwlink is
#   stable; bump the constants below in one place if Microsoft retires
#   it. Unlike oscdimg.exe there is no fixed reference SHA-256 to pin
#   (signtool.exe varies per SDK build), so acquisition trust rests on
#   the Microsoft fwlink + presence verification (see Resolve-SignToolExe).
#
# Reference:
#   https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool
$Script:SdkInstallerUrl      = 'https://go.microsoft.com/fwlink/?linkid=2338977'
$Script:SdkInstallerVersion  = '10.0.26100.6584'
$Script:SdkInstallerOptionId = 'OptionId.SigningTools'

# Runtime memo for the resolved signtool.exe path (set lazily by
# Get-ResolvedSignToolExe): $null = not yet attempted, '' = attempted and
# unavailable, <path> = resolved. Keeps signtool resolution/auto-install to
# at most once per run.
$Script:ResolvedSignToolExe  = $null


# ============================================================
# ISO Updater specific: Microsoft Learn release-info support
# ============================================================
#
# The Microsoft Learn rendering pipeline supports a `?accept=text/markdown`
# content-negotiation switch on every documentation URL. Appending it to
# the Windows Server release-info URL returns the source Markdown table
# verbatim, which is much more stable than scraping the rendered HTML.
# The Refresher consumes that Markdown as the authoritative source for
# monthly LCU KBs and the Server 2022 / Server 2025 Hotpatch calendar.
#
# Files this section reads or writes:
#   data/raw-release-info.md         The Markdown body as fetched.
#   data/raw-release-info.meta.json  HTTP headers + fetch timestamp.
#   data/cache-release-info.json     Parsed structured data for fast access.
#
# See SPEC.md: release-info is the truth source, and data/ uses the
# three-prefix (config-/cache-/raw-) layout.

$Script:ReleaseInfoUrl = (
    'https://learn.microsoft.com/en-us/windows/release-health/' +
    'windows-server-release-info?accept=text/markdown'
)

$Script:ReleaseInfoUserAgent = (
    'ai-generated-artifacts/release-info ' +
    '(+https://github.com/usui-tk/ai-generated-artifacts)'
)

$Script:ReleaseInfoLongToShort = @{
    'Windows Server 2025'                    = 'Server2025'
    'Windows Server 2022'                    = 'Server2022'
    'Windows Server 2019 (version 1809)'     = 'Server2019'
    'Windows Server 2019'                    = 'Server2019'
    'Windows Server 2016 (version 1607)'     = 'Server2016'
    'Windows Server 2016'                    = 'Server2016'
}

$Script:ReleaseInfoMonthNameToNumber = @{
    'January'   = 1;  'February' = 2;  'March'     = 3;  'April'    = 4
    'May'       = 5;  'June'     = 6;  'July'      = 7;  'August'   = 8
    'September' = 9;  'October'  = 10; 'November'  = 11; 'December' = 12
}

$Script:ReleaseInfoMonthlyHeaders = @(
    'Servicing option',
    'Update type',
    'Availability date',
    'Build',
    'KB article'
)

$Script:ReleaseInfoHotpatchHeaders = @(
    'Month',
    'Update type',
    'Type',
    'Availability date',
    'Build',
    'KB article'
)

function Get-DataDirectoryPath {
    <#
    .SYNOPSIS
        Resolve the on-disk path of the data/ directory next to
        Update-WindowsServerIso.ps1.
    .DESCRIPTION
        Used by every cache- and raw- accessor in this section.
        See SPEC.md for the directory layout.
    #>
    [OutputType([string])]
    param()
    $here = $Script:ScriptRoot
    if ([string]::IsNullOrEmpty($here)) { $here = $PSScriptRoot }
    if ([string]::IsNullOrEmpty($here)) { $here = (Get-Location).Path }
    return (Join-Path $here 'data')
}

function Get-ReleaseInfoRawPath {
    <#
    .SYNOPSIS
        Resolve the on-disk path of data/raw-release-info.md.
    #>
    [OutputType([string])]
    param()
    return (Join-Path (Get-DataDirectoryPath) 'raw-release-info.md')
}

function Get-ReleaseInfoRawMetaPath {
    <#
    .SYNOPSIS
        Resolve the on-disk path of data/raw-release-info.meta.json,
        which carries the HTTP headers and fetch timestamp.
    #>
    [OutputType([string])]
    param()
    return (Join-Path (Get-DataDirectoryPath) 'raw-release-info.meta.json')
}

function Get-ReleaseInfoCachePath {
    <#
    .SYNOPSIS
        Resolve the on-disk path of data/cache-release-info.json,
        the parsed structured cache that the Refresher consumes.
    #>
    [OutputType([string])]
    param()
    return (Join-Path (Get-DataDirectoryPath) 'cache-release-info.json')
}

function Invoke-ReleaseInfoFetch {
    <#
    .SYNOPSIS
        Fetch the Microsoft Learn Windows Server release-info page
        (Markdown form) and persist both the body and the response
        metadata under the data/ directory.
    .DESCRIPTION
        Writes:
          data/raw-release-info.md         Markdown body, UTF-8 + LF + no-BOM.
          data/raw-release-info.meta.json  HTTP headers + fetch timestamp.

        Returns the path of the Markdown body file. Throws on any
        non-200 HTTP response.
    #>
    [OutputType([string])]
    param(
        [string]$Url       = $Script:ReleaseInfoUrl,
        [int]   $TimeoutSec = 30
    )

    $rawPath  = Get-ReleaseInfoRawPath
    $metaPath = Get-ReleaseInfoRawMetaPath
    $dataDir  = Split-Path -Parent $rawPath
    if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
        New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
    }

    Write-Step ('Fetching release-info: {0}' -f $Url)

    $resp = Invoke-WebRequest `
        -Uri $Url `
        -Method Get `
        -UserAgent $Script:ReleaseInfoUserAgent `
        -TimeoutSec $TimeoutSec `
        -UseBasicParsing
    if ($resp.StatusCode -ne 200) {
        throw ('release-info fetch failed: HTTP {0} from {1}' -f $resp.StatusCode, $Url)
    }

    # Normalise body to UTF-8 + LF + no-BOM
    $body = $resp.Content
    if ($null -eq $body) {
        throw ('release-info fetch returned empty body from {0}' -f $Url)
    }
    $body = ($body -replace "`r`n", "`n")
    if (-not $body.EndsWith("`n")) { $body = $body + "`n" }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    [System.IO.File]::WriteAllBytes($rawPath, $bodyBytes)

    # Build a meta record
    $headersFlat = New-Object 'System.Collections.Specialized.OrderedDictionary'
    foreach ($k in $resp.Headers.Keys) {
        $headersFlat[$k.ToLower()] = [string]($resp.Headers[$k])
    }
    $rawMeta = [pscustomobject]@{
        Schema       = '1.0'
        SourceUrl    = $Url
        FetchedAt    = (Get-Date).ToUniversalTime().ToString('o')
        StatusCode   = [int]$resp.StatusCode
        BodyBytes    = $bodyBytes.Length
        UserAgent    = $Script:ReleaseInfoUserAgent
        Headers      = $headersFlat
    }
    Save-CanonicalJsonFile -InputObject $rawMeta -Path $metaPath -Depth 8

    Write-Ok ('  raw-release-info.md         : {0} bytes' -f $bodyBytes.Length)
    Write-Ok ('  raw-release-info.meta.json  : {0} bytes' -f (Get-Item -LiteralPath $metaPath).Length)
    return $rawPath
}

function Split-ReleaseInfoTableRow {
    <#
    .SYNOPSIS
        Split a Markdown table row "| a | b | c |" into ['a','b','c'].
        Strips the leading/trailing empty cells that result from the
        outer pipes.
    #>
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string]$Line)
    $parts = $Line -split '\|'
    $parts = $parts | ForEach-Object { $_.Trim() }
    if ($parts.Count -gt 0 -and $parts[0] -eq '') {
        $parts = $parts[1..($parts.Count - 1)]
    }
    if ($parts.Count -gt 0 -and $parts[-1] -eq '') {
        $parts = $parts[0..($parts.Count - 2)]
    }
    return ,([string[]]$parts)
}

function Test-ReleaseInfoTableSeparator {
    <#
    .SYNOPSIS
        Return $true if the line is a Markdown table separator row
        (e.g. '|---|:---|---:|'). False for everything else.
    #>
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$Line)
    $stripped = $Line.Trim()
    if (-not $stripped.StartsWith('|')) { return $false }
    $cells = Split-ReleaseInfoTableRow -Line $stripped
    if ($cells.Count -eq 0) { return $false }
    foreach ($c in $cells) {
        if ($c -notmatch '^:?-+:?$') { return $false }
    }
    return $true
}

function ConvertFrom-ReleaseInfoUpdateType {
    <#
    .SYNOPSIS
        Decompose an Update type label like '2026-04 OOB' or '2026-04 B'
        into (Year, Month, Letter). Unparseable input returns (0, 0, '?').
    #>
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string]$Label)
    $m = [regex]::Match($Label.Trim(), '^(\d{4})-(\d{2})\s+(OOB|[A-E])$')
    if (-not $m.Success) {
        return [pscustomobject]@{ Year = 0; Month = 0; Letter = '?' }
    }
    return [pscustomobject]@{
        Year   = [int]$m.Groups[1].Value
        Month  = [int]$m.Groups[2].Value
        Letter = [string]$m.Groups[3].Value
    }
}

function ConvertFrom-ReleaseInfoKbCell {
    <#
    .SYNOPSIS
        Extract (KbId, KbUrl) from a Markdown table cell like
        '[KB5091122](https://...)' or bare 'KB5091122'.
        An empty cell returns ('', '').
    #>
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Cell)
    $trim = $Cell.Trim()
    if ([string]::IsNullOrEmpty($trim)) {
        return [pscustomobject]@{ KbId = ''; KbUrl = '' }
    }
    $m = [regex]::Match($trim, '\[?KB(\d{4,7})\]?\(?([^)]*)\)?')
    if (-not $m.Success) {
        return [pscustomobject]@{ KbId = ''; KbUrl = '' }
    }
    return [pscustomobject]@{
        KbId  = ('KB' + $m.Groups[1].Value)
        KbUrl = ($m.Groups[2].Value.Trim())
    }
}

function ConvertFrom-ReleaseInfoMarkdown {
    <#
    .SYNOPSIS
        Parse a release-info Markdown body into structured monthly
        release rows and Hotpatch calendar rows.
    .DESCRIPTION
        Returns a pscustomobject with two array properties:

          MonthlyReleases  : per-OS monthly release rows
          HotpatchCalendar : per-OS / per-year hotpatch calendar rows

        The parser is deliberately strict about header text and column
        count; any drift in Microsoft's table format yields a warning
        in stderr (the row is skipped) so the operator can review.
        Returns empty arrays for sections the document does not contain.
    #>
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string]$Markdown)

    $lines = $Markdown -split "`n"
    $monthlyReleases  = New-Object System.Collections.Generic.List[object]
    $hotpatchEntries  = New-Object System.Collections.Generic.List[object]

    $section      = ''
    $currentOsKey = ''
    $currentBuild = ''
    $currentYear  = 0
    $osHeaderPattern = '\*\*Windows Server (\d{4})\s*\(OS build (\d+)\)\*\*'

    $i = 0
    while ($i -lt $lines.Count) {
        $line     = $lines[$i]
        $stripped = $line.Trim()

        if ($stripped.StartsWith('## Windows Server release history')) {
            $section = 'release-history'
            $currentOsKey = ''
            $i += 1
            continue
        }
        if ($stripped.StartsWith('## Windows Server hotpatch calendar')) {
            $section = 'hotpatch-calendar'
            $currentOsKey = ''
            $i += 1
            continue
        }
        if ($stripped.StartsWith('## ') -and ($section -eq 'release-history' -or $section -eq 'hotpatch-calendar')) {
            $section = ''
            $currentOsKey = ''
        }

        $mOs = [regex]::Match($stripped, $osHeaderPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($mOs.Success -and ($section -eq 'release-history' -or $section -eq 'hotpatch-calendar')) {
            $osYear  = $mOs.Groups[1].Value
            $osBuild = $mOs.Groups[2].Value
            $longName = ('Windows Server ' + $osYear)
            $osShort = $null
            if ($Script:ReleaseInfoLongToShort.ContainsKey($longName)) {
                $osShort = $Script:ReleaseInfoLongToShort[$longName]
            }
            if ($osShort) {
                $currentOsKey = $osShort
                $currentBuild = $osBuild
            } else {
                $currentOsKey = ''
            }
            $i += 1
            continue
        }

        $mYr = [regex]::Match($stripped, '^\*\*Calendar year (\d{4})\*\*$')
        if ($mYr.Success -and $section -eq 'hotpatch-calendar') {
            $currentYear = [int]$mYr.Groups[1].Value
            $i += 1
            continue
        }

        if ($stripped.StartsWith('|') -and -not [string]::IsNullOrEmpty($currentOsKey)) {
            $headerCells = Split-ReleaseInfoTableRow -Line $stripped
            $sepIdx = $i + 1
            if ($sepIdx -ge $lines.Count -or -not (Test-ReleaseInfoTableSeparator -Line $lines[$sepIdx])) {
                $i += 1
                continue
            }

            $headerStr = ($headerCells -join '|')
            $monthlyHdr  = ($Script:ReleaseInfoMonthlyHeaders  -join '|')
            $hotpatchHdr = ($Script:ReleaseInfoHotpatchHeaders -join '|')

            $kind = ''
            if ($section -eq 'release-history'  -and $headerStr -eq $monthlyHdr)  { $kind = 'monthly' }
            elseif ($section -eq 'hotpatch-calendar' -and $headerStr -eq $hotpatchHdr) { $kind = 'hotpatch' }

            if ($kind -eq '') {
                Write-Caution ('  release-info parser: unrecognised table header in section {0!s} for {1}: {2!s}' -f $section, $currentOsKey, $headerCells)
                $i = $sepIdx
                continue
            }

            # Collect rows
            $k = $sepIdx + 1
            while ($k -lt $lines.Count) {
                $rl = $lines[$k]
                if (-not $rl.TrimStart().StartsWith('|')) { break }
                $rowCells = Split-ReleaseInfoTableRow -Line $rl

                if ($kind -eq 'monthly') {
                    if ($rowCells.Count -ne $Script:ReleaseInfoMonthlyHeaders.Count) {
                        Write-Caution ('  release-info parser: skipping monthly row with {0} columns for {1}' -f $rowCells.Count, $currentOsKey)
                        $k += 1
                        continue
                    }
                    $servicing = $rowCells[0]
                    $updateType = $rowCells[1]
                    $availDate = $rowCells[2]
                    $buildAfter = $rowCells[3]
                    $kbCell    = $rowCells[4]
                    $ut = ConvertFrom-ReleaseInfoUpdateType -Label $updateType
                    $kb = ConvertFrom-ReleaseInfoKbCell      -Cell  $kbCell
                    $monthlyReleases.Add([pscustomobject]@{
                        OsShortName      = $currentOsKey
                        OsBuild          = $currentBuild
                        ServicingOption  = $servicing
                        UpdateType       = $updateType
                        UpdateTypeYear   = $ut.Year
                        UpdateTypeMonth  = $ut.Month
                        UpdateTypeLetter = $ut.Letter
                        AvailabilityDate = $availDate
                        BuildAfterUpdate = $buildAfter
                        KbId             = $kb.KbId
                        KbUrl            = $kb.KbUrl
                    }) | Out-Null
                } elseif ($kind -eq 'hotpatch') {
                    while ($rowCells.Count -gt $Script:ReleaseInfoHotpatchHeaders.Count -and $rowCells[-1] -eq '') {
                        $rowCells = $rowCells[0..($rowCells.Count - 2)]
                    }
                    if ($rowCells.Count -ne $Script:ReleaseInfoHotpatchHeaders.Count) {
                        Write-Caution ('  release-info parser: skipping hotpatch row with {0} columns for {1}' -f $rowCells.Count, $currentOsKey)
                        $k += 1
                        continue
                    }
                    $monthName    = $rowCells[0]
                    $updateType   = $rowCells[1]
                    $hotpatchType = $rowCells[2]
                    $availDate    = $rowCells[3]
                    $buildAfter   = $rowCells[4]
                    $kbCell       = $rowCells[5]
                    $monthNumber = 0
                    if ($Script:ReleaseInfoMonthNameToNumber.ContainsKey($monthName)) {
                        $monthNumber = [int]$Script:ReleaseInfoMonthNameToNumber[$monthName]
                    }
                    $kb = ConvertFrom-ReleaseInfoKbCell -Cell $kbCell
                    $isBaseline = ($hotpatchType.ToLower().Contains('baseline'))
                    $hotpatchEntries.Add([pscustomobject]@{
                        OsShortName      = $currentOsKey
                        OsBuild          = $currentBuild
                        CalendarYear     = $currentYear
                        MonthName        = $monthName
                        MonthNumber      = $monthNumber
                        UpdateType       = $updateType
                        HotpatchType     = $hotpatchType
                        IsBaseline       = $isBaseline
                        AvailabilityDate = $availDate
                        BuildAfterUpdate = $buildAfter
                        KbId             = $kb.KbId
                        KbUrl            = $kb.KbUrl
                    }) | Out-Null
                }
                $k += 1
            }
            $i = $k
            continue
        }

        $i += 1
    }

    return [pscustomobject]@{
        MonthlyReleases  = @($monthlyReleases.ToArray())
        HotpatchCalendar = @($hotpatchEntries.ToArray())
    }
}

function Update-ReleaseInfoCache {
    <#
    .SYNOPSIS
        Read data/raw-release-info.md, parse it, and write the result to
        data/cache-release-info.json (UTF-8 + LF + no-BOM).
    .DESCRIPTION
        Throws if the raw file is missing. The caller is expected to
        have invoked Invoke-ReleaseInfoFetch (or an equivalent CI step)
        beforehand.

        Returns a summary pscustomobject with row counts so callers can
        log the outcome without re-reading the cache file.
    #>
    [OutputType([pscustomobject])]
    param()
    $rawPath   = Get-ReleaseInfoRawPath
    $cachePath = Get-ReleaseInfoCachePath
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw ('release-info raw file not found at "{0}". Run Invoke-ReleaseInfoFetch first.' -f $rawPath)
    }
    Write-Step ('Parsing release-info: {0}' -f $rawPath)

    $bytes = [System.IO.File]::ReadAllBytes($rawPath)
    $markdown = [System.Text.Encoding]::UTF8.GetString($bytes)
    $parsed = ConvertFrom-ReleaseInfoMarkdown -Markdown $markdown

    # Per-OS counts
    $perOsMonthly  = @{}
    foreach ($r in $parsed.MonthlyReleases)  {
        $k = [string]$r.OsShortName
        if (-not $perOsMonthly.ContainsKey($k))  { $perOsMonthly[$k]  = 0 }
        $perOsMonthly[$k]  = [int]$perOsMonthly[$k]  + 1
    }
    $perOsHotpatch = @{}
    foreach ($h in $parsed.HotpatchCalendar) {
        $k = [string]$h.OsShortName
        if (-not $perOsHotpatch.ContainsKey($k)) { $perOsHotpatch[$k] = 0 }
        $perOsHotpatch[$k] = [int]$perOsHotpatch[$k] + 1
    }

    $cache = [pscustomobject]@{
        Schema             = '1.0'
        GeneratedAt        = (Get-Date).ToUniversalTime().ToString('o')
        SourceUrl          = $Script:ReleaseInfoUrl
        RawMarkdownPath    = (Split-Path -Leaf $rawPath)
        MonthlyRowCount    = [int]$parsed.MonthlyReleases.Count
        HotpatchRowCount   = [int]$parsed.HotpatchCalendar.Count
        PerOsMonthlyCounts = $perOsMonthly
        PerOsHotpatchCounts = $perOsHotpatch
        MonthlyReleases    = $parsed.MonthlyReleases
        HotpatchCalendar   = $parsed.HotpatchCalendar
    }

    Save-CanonicalJsonFile -InputObject $cache -Path $cachePath -Depth 32

    Write-Ok ('  cache-release-info.json     : {0} monthly rows, {1} hotpatch rows ({2} bytes)' -f $cache.MonthlyRowCount, $cache.HotpatchRowCount, (Get-Item -LiteralPath $cachePath).Length)

    return [pscustomobject]@{
        MonthlyRowCount    = $cache.MonthlyRowCount
        HotpatchRowCount   = $cache.HotpatchRowCount
        PerOsMonthlyCounts = $perOsMonthly
        PerOsHotpatchCounts = $perOsHotpatch
    }
}

function Get-ReleaseInfoCache {
    <#
    .SYNOPSIS
        Read data/cache-release-info.json and return the deserialised
        object. Throws if the file is missing.
    .DESCRIPTION
        Refresher consumers (Resolve-PatchSetFromReleaseInfo and its
        peers, added in a later commit) call this to read the cache
        without re-parsing the raw Markdown on every build.
    #>
    [OutputType([pscustomobject])]
    param()
    $cachePath = Get-ReleaseInfoCachePath
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        throw ('release-info cache not found at "{0}". Run Update-ReleaseInfoCache first.' -f $cachePath)
    }
    $bytes = [System.IO.File]::ReadAllBytes($cachePath)
    $json  = [System.Text.Encoding]::UTF8.GetString($bytes)
    return ($json | ConvertFrom-CanonicalJson)
}

# ============================================================
# ISO Updater specific: .NET Framework CU release-notes support
# ============================================================
#
# The Microsoft Learn ".NET Framework release information" page is the
# authoritative index of monthly cumulative-update release-notes pages.
# Like the Windows Server release-info page, each URL supports the
# `?accept=text/markdown` content-negotiation switch and returns the
# source Markdown verbatim. The index lists every monthly CU page back
# to early 2024; each per-month page contains a "Summary tables"
# section that maps OS labels to per-.NET-Framework-version KB IDs.
#
# Files this section reads or writes:
#   data/raw-dotnet-cu.json   Aggregated container holding the index
#                             Markdown plus each monthly page's
#                             Markdown body, plus per-fetch metadata.
#   data/cache-dotnet-cu.json Parsed structured form ready for the
#                             Refresher to consume.
#
# Note that .NET CU uses a single aggregated JSON for the raw layer,
# unlike release-info which uses raw-release-info.md as a single
# Markdown body. The aggregated container exists because .NET CU has
# many monthly pages and one container is easier to review in a
# Patch-Tuesday diff than dozens of per-month files. See SPEC.md
# section B.22.3 for the raw-/cache- prefix convention and section
# B.22.5 for the .NET CU multiplicity background.

$Script:DotNetCuIndexUrl = (
    'https://learn.microsoft.com/en-us/dotnet/framework/release-notes/' +
    'release-notes?accept=text/markdown'
)

$Script:DotNetCuUrlBase = (
    'https://learn.microsoft.com/en-us/dotnet/framework/release-notes/'
)

$Script:DotNetCuUserAgent = (
    'ai-generated-artifacts/dotnet-cu ' +
    '(+https://github.com/usui-tk/ai-generated-artifacts)'
)

# OS-label substring to short-name mapping. Order matters: longer or
# more-specific patterns must precede shorter ones that they contain
# (e.g. "Windows 10 1607 and Windows Server 2016" must precede
# "Windows Server 2016" so the longer joint label wins). The mapping
# covers more OS labels than the production scope on purpose, so the
# parser produces a complete picture; downstream consumers filter to
# the four production OSes (Server2016/2019/2022/2025).
$Script:DotNetCuOsLongToShort = [ordered]@{
    'Microsoft server operating system, version 24H2' = 'Server2025'
    'Microsoft server operating system version 24H2'  = 'Server2025'
    'Microsoft server operating system, version 23H2' = 'Server23H2'
    'Microsoft server operating system version 23H2'  = 'Server23H2'
    'Windows Server 2022'                             = 'Server2022'
    'Windows 10 1809 and Windows Server 2019'         = 'Server2019'
    'Windows Server 2019'                             = 'Server2019'
    'Windows 10 1607 and Windows Server 2016'         = 'Server2016'
    'Windows Server 2016'                             = 'Server2016'
    'Windows Server 2012 R2'                          = 'Server2012R2'
    'Windows Server 2012'                             = 'Server2012'
}

function Get-DotNetCuRawPath {
    <#
    .SYNOPSIS
        Resolve the on-disk path of data/raw-dotnet-cu.json.
    #>
    [OutputType([string])]
    param()
    return (Join-Path (Get-DataDirectoryPath) 'raw-dotnet-cu.json')
}

function Get-DotNetCuCachePath {
    <#
    .SYNOPSIS
        Resolve the on-disk path of data/cache-dotnet-cu.json.
    #>
    [OutputType([string])]
    param()
    return (Join-Path (Get-DataDirectoryPath) 'cache-dotnet-cu.json')
}

function ConvertFrom-DotNetCuOsLabel {
    <#
    .SYNOPSIS
        Map a raw OS label as printed in the release-notes table to a
        normalised short name (e.g. "Server2025"). Returns empty string
        if the label does not match any known pattern.
    .EXAMPLE
        ConvertFrom-DotNetCuOsLabel -Label 'Windows Server 2022'
        # -> 'Server2022'
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Label)
    foreach ($needle in $Script:DotNetCuOsLongToShort.Keys) {
        if ($Label.Contains($needle)) {
            return [string]$Script:DotNetCuOsLongToShort[$needle]
        }
    }
    return ''
}

function Split-DotNetCuMarkdownFrontMatter {
    <#
    .SYNOPSIS
        Return the body of a Markdown document with the optional leading
        YAML front matter block stripped. If no front matter is present
        the input is returned unchanged.
    .DESCRIPTION
        Microsoft Learn pages, when requested with ?accept=text/markdown,
        begin with a YAML block delimited by lines containing exactly
        three dashes ("---"). This helper trims that block so that the
        body line parsers see only the content.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Markdown)
    if (-not $Markdown.StartsWith('---')) {
        return $Markdown
    }
    # Walk forward looking for a line that is exactly "---" (after any \r).
    # Use a regex against the body starting at offset 3 (past the leading dashes).
    $rest = $Markdown.Substring(3)
    $closer = [regex]'(?m)^---\s*$'
    $m = $closer.Match($rest)
    if (-not $m.Success) {
        return $Markdown
    }
    $afterIdx = $m.Index + $m.Length
    $body = $rest.Substring($afterIdx)
    # Trim a single leading CR/LF so the body's first real line is at offset 0.
    return ($body -replace '^[\r\n]+', '')
}

function ConvertFrom-DotNetCuIndexMarkdown {
    <#
    .SYNOPSIS
        Parse the .NET Framework release-notes index page (Markdown form)
        and return a structured object listing every monthly cumulative
        update entry.
    .DESCRIPTION
        The index page lists entries in the form
            "- April 14, 2026 - [cumulative update](2026/04-14-april-cumulative-update)"
        with the date sitting outside the link bracket and only the kind
        text being linked. The most recent entry may carry a trailing
        bolded "**New Release**" suffix which the parser tolerates and
        discards. Date typos that prevent strict %B parsing (the index
        contains at least one such typo in the 2024 history) do not
        drop the entry: the entry is preserved with an empty parsed
        Date but the original DateText is kept.
    .EXAMPLE
        ConvertFrom-DotNetCuIndexMarkdown -Markdown $indexBody
    #>
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string]$Markdown)

    $body = Split-DotNetCuMarkdownFrontMatter -Markdown $Markdown
    $entryRegex = [regex]'^- ([A-Za-z]+ \d{1,2}, \d{4}) - \[([^\]]+)\]\(([^)]+)\)\s*(?:\*\*[^*]+\*\*)?\s*$'

    $entryList = New-Object 'System.Collections.Generic.List[pscustomobject]'
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    foreach ($rawLine in ($body -split "`n")) {
        $line = $rawLine.TrimEnd("`r")
        $regexHit = $entryRegex.Match($line)
        if (-not $regexHit.Success) { continue }
        $dateText = $regexHit.Groups[1].Value
        $kindText = $regexHit.Groups[2].Value.Trim()
        $relUrl   = $regexHit.Groups[3].Value.Trim()

        $isoDate = ''
        try {
            $dt = [datetime]::ParseExact($dateText, 'MMMM d, yyyy', $invariant)
            $isoDate = $dt.ToString('yyyy-MM-dd')
        }
        catch {
            $isoDate = ''
        }

        $absUrl = $Script:DotNetCuUrlBase + $relUrl
        $entryList.Add([pscustomobject]@{
            DateText    = $dateText
            Date        = $isoDate
            Kind        = $kindText
            RelativeUrl = $relUrl
            AbsoluteUrl = $absUrl
        })
    }

    # Compute summary fields. Use only entries with a non-empty parsed date
    # for the date range; that excludes the typo case.
    $datedEntries  = @($entryList | Where-Object { $_.Date -ne '' })
    $sortedDates   = @($datedEntries | ForEach-Object { $_.Date } | Sort-Object)
    $earliestDate  = if ($sortedDates.Count -gt 0) { $sortedDates[0] } else { '' }
    $latestDate    = if ($sortedDates.Count -gt 0) { $sortedDates[$sortedDates.Count - 1] } else { '' }
    $distinctKinds = @($entryList | ForEach-Object { $_.Kind } | Sort-Object -Unique)

    return [pscustomobject]@{
        EntryCount   = $entryList.Count
        Kinds        = $distinctKinds
        EarliestDate = $earliestDate
        LatestDate   = $latestDate
        Entries      = @($entryList.ToArray())
    }
}

function ConvertFrom-DotNetCuMarkdown {
    <#
    .SYNOPSIS
        Parse a single monthly .NET CU release-notes page (Markdown form)
        and return a structured object describing the per-OS table
        blocks under the "Summary tables" heading.
    .DESCRIPTION
        The "Summary tables" section on a monthly page lists, for each
        OS, the per-.NET-Framework-version KB IDs published that month.
        On current pages this section appears AFTER "## Known issues in
        this release", so the parser walks from "## Summary tables" up
        to the next "## " heading or end of document, accepting
        multiple sequential Markdown tables along the way.

        Returns an object with:
          EntryCountTotal       - total OS blocks parsed
          EntryCountRecognised  - OS blocks whose label matched the
                                  Server* / Server23H2 mapping
          RowsPerOs             - hashtable from short OS name to count
                                  of .NET version rows in that block
          Entries               - the OS blocks themselves, each with
                                  OsLabel, OsNormalised, OsOfferingKb
                                  and Rows[].
    .EXAMPLE
        ConvertFrom-DotNetCuMarkdown -Markdown $monthBody
    #>
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string]$Markdown)

    $body = Split-DotNetCuMarkdownFrontMatter -Markdown $Markdown

    $headingRegex   = [regex]'^## Summary tables\s*$'
    $otherHeading2  = [regex]'^## (?!Summary tables\b).+$'
    $headerRowRegex = [regex]'^\|\s*Product version\s*\|'
    $sepRowRegex    = [regex]'^\|\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|\s*$'
    $osRowRegex     = [regex]'^\|\s*\*\*([^|*]+?)\*\*\s*\|\s*(.*?)\s*\|\s*$'
    $netRowRegex    = [regex]'^\|\s*\.NET Framework\s+([^|]+?)\s*\|\s*(.*?)\s*\|\s*$'
    $kbDigitsRegex  = [regex]'(\d{4,7})'

    $inSection = $false
    $blockList = New-Object 'System.Collections.Generic.List[pscustomobject]'
    $currentOs = $null

    foreach ($rawLine in ($body -split "`n")) {
        $line = $rawLine.TrimEnd("`r")

        if (-not $inSection) {
            if ($headingRegex.IsMatch($line)) {
                $inSection = $true
            }
            continue
        }

        # If a new "## " heading other than the one we entered appears,
        # the tables region is closed.
        if ($otherHeading2.IsMatch($line)) {
            break
        }

        # Skip the standard table chrome.
        if ($headerRowRegex.IsMatch($line)) {
            # A new sub-table boundary. Flush the current OS block so
            # the next OS row in the new sub-table starts cleanly.
            if ($null -ne $currentOs) {
                $blockList.Add($currentOs)
                $currentOs = $null
            }
            continue
        }
        if ($sepRowRegex.IsMatch($line)) {
            continue
        }

        # OS row: bolded label, optional bolded KB link in the second cell.
        $osMatch = $osRowRegex.Match($line)
        if ($osMatch.Success) {
            if ($null -ne $currentOs) {
                $blockList.Add($currentOs)
            }
            $osLabel       = $osMatch.Groups[1].Value.Trim()
            $offeringCell  = $osMatch.Groups[2].Value.Trim()
            $offeringKb    = ''
            $kbDigitsHit   = $kbDigitsRegex.Match($offeringCell)
            if ($kbDigitsHit.Success) {
                $offeringKb = 'KB' + $kbDigitsHit.Groups[1].Value
            }
            $currentOs = [pscustomobject]@{
                OsLabel       = $osLabel
                OsNormalised  = (ConvertFrom-DotNetCuOsLabel -Label $osLabel)
                OsOfferingKb  = $offeringKb
                Rows          = New-Object 'System.Collections.Generic.List[pscustomobject]'
            }
            continue
        }

        # .NET version row: unbolded ".NET Framework <versions>" + KB.
        $netMatch = $netRowRegex.Match($line)
        if ($netMatch.Success -and $null -ne $currentOs) {
            $versions = $netMatch.Groups[1].Value.Trim()
            $kbCell   = $netMatch.Groups[2].Value.Trim()
            $kbId     = ''
            $kbDigitsHit2 = $kbDigitsRegex.Match($kbCell)
            if ($kbDigitsHit2.Success) {
                $kbId = 'KB' + $kbDigitsHit2.Groups[1].Value
            }
            $currentOs.Rows.Add([pscustomobject]@{
                DotNetVersions = $versions
                KbId           = $kbId
            })
            continue
        }
        # Any other "| ... |" row (unrecognised pattern) is ignored.
    }

    if ($null -ne $currentOs) {
        $blockList.Add($currentOs)
    }

    # Convert each block's Rows list to an array, and compute summaries.
    $entryArray = @()
    $rowsPerOs  = [ordered]@{}
    $totalCount = 0
    $recogCount = 0
    foreach ($block in $blockList) {
        $totalCount++
        $rowArray = @($block.Rows.ToArray())
        $blockOut = [pscustomobject]@{
            OsLabel       = $block.OsLabel
            OsNormalised  = $block.OsNormalised
            OsOfferingKb  = $block.OsOfferingKb
            Rows          = $rowArray
        }
        $entryArray += $blockOut
        if (-not [string]::IsNullOrEmpty($block.OsNormalised)) {
            $recogCount++
            $rowsPerOs[$block.OsNormalised] = $rowArray.Count
        }
    }

    return [pscustomobject]@{
        EntryCountTotal      = $totalCount
        EntryCountRecognised = $recogCount
        RowsPerOs            = $rowsPerOs
        Entries              = $entryArray
    }
}

function Invoke-DotNetCuFetch {
    <#
    .SYNOPSIS
        Fetch the .NET Framework release-notes index plus every monthly
        cumulative-update page referenced by the index, and write the
        aggregated bodies plus per-fetch metadata to
        data/raw-dotnet-cu.json.
    .DESCRIPTION
        Returns the path of the raw JSON file. Throws on any non-200
        HTTP response from the index fetch (a per-month fetch that
        fails is recorded as a Failed entry in the aggregate so the
        rest of the months are still captured).

        The caller (typically a refresh action) is expected to invoke
        Update-DotNetCuCache afterwards to derive the parsed cache.
    #>
    [OutputType([string])]
    param(
        [string]$IndexUrl   = $Script:DotNetCuIndexUrl,
        [int]   $TimeoutSec = 30
    )

    $rawPath = Get-DotNetCuRawPath
    $dataDir = Split-Path -Parent $rawPath
    if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
        New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
    }

    Write-Step ('Fetching .NET CU index: {0}' -f $IndexUrl)

    $indexResp = Invoke-WebRequest `
        -Uri $IndexUrl `
        -Method Get `
        -UserAgent $Script:DotNetCuUserAgent `
        -TimeoutSec $TimeoutSec `
        -UseBasicParsing
    if ($indexResp.StatusCode -ne 200) {
        throw ('.NET CU index fetch failed: HTTP {0} from {1}' -f $indexResp.StatusCode, $IndexUrl)
    }

    $indexBody = $indexResp.Content
    if ($null -eq $indexBody) {
        throw ('.NET CU index fetch returned empty body from {0}' -f $IndexUrl)
    }
    $indexBody = ($indexBody -replace "`r`n", "`n")
    if (-not $indexBody.EndsWith("`n")) { $indexBody = $indexBody + "`n" }

    $indexHeaders = New-Object 'System.Collections.Specialized.OrderedDictionary'
    foreach ($k in $indexResp.Headers.Keys) {
        $indexHeaders[$k.ToLower()] = [string]($indexResp.Headers[$k])
    }

    # Parse the index inline so we know which month URLs to fetch.
    $indexParsed = ConvertFrom-DotNetCuIndexMarkdown -Markdown $indexBody

    Write-Step ('  Index entries: {0}' -f $indexParsed.EntryCount)

    $monthList = New-Object 'System.Collections.Generic.List[pscustomobject]'
    foreach ($entry in $indexParsed.Entries) {
        $monthUrl = $entry.AbsoluteUrl + '?accept=text/markdown'
        $monthBody    = ''
        $monthOk      = $false
        $monthStatus  = 0
        $monthError   = ''
        $monthHeaders = New-Object 'System.Collections.Specialized.OrderedDictionary'
        try {
            $monthResp = Invoke-WebRequest `
                -Uri $monthUrl `
                -Method Get `
                -UserAgent $Script:DotNetCuUserAgent `
                -TimeoutSec $TimeoutSec `
                -UseBasicParsing
            $monthStatus = [int]$monthResp.StatusCode
            if ($monthStatus -eq 200) {
                $monthBody = $monthResp.Content
                $monthBody = ($monthBody -replace "`r`n", "`n")
                if (-not $monthBody.EndsWith("`n")) { $monthBody = $monthBody + "`n" }
                foreach ($k in $monthResp.Headers.Keys) {
                    $monthHeaders[$k.ToLower()] = [string]($monthResp.Headers[$k])
                }
                $monthOk = $true
            }
            else {
                $monthError = ('HTTP {0}' -f $monthStatus)
            }
        }
        catch {
            $monthError = $_.Exception.Message
        }
        $monthList.Add([pscustomobject]@{
            Date        = $entry.Date
            DateText    = $entry.DateText
            Kind        = $entry.Kind
            RelativeUrl = $entry.RelativeUrl
            AbsoluteUrl = $entry.AbsoluteUrl
            FetchUrl    = $monthUrl
            Ok          = $monthOk
            StatusCode  = $monthStatus
            ErrorText   = $monthError
            Headers     = $monthHeaders
            Markdown    = $monthBody
        })
    }

    $okCount = @($monthList | Where-Object { $_.Ok }).Count
    Write-Ok ('  monthly pages fetched ok: {0} of {1}' -f $okCount, $monthList.Count)

    $rawAggregate = [pscustomobject]@{
        Schema      = '1.0'
        SourceUrl   = $IndexUrl
        FetchedAt   = (Get-Date).ToUniversalTime().ToString('o')
        UserAgent   = $Script:DotNetCuUserAgent
        IndexBody   = $indexBody
        IndexBytes  = [System.Text.Encoding]::UTF8.GetByteCount($indexBody)
        IndexHeaders = $indexHeaders
        Months      = @($monthList.ToArray())
    }

    Save-CanonicalJsonFile -InputObject $rawAggregate -Path $rawPath -Depth 12

    Write-Ok ('  raw-dotnet-cu.json    : {0} bytes' -f (Get-Item -LiteralPath $rawPath).Length)
    return $rawPath
}

function Update-DotNetCuCache {
    <#
    .SYNOPSIS
        Read data/raw-dotnet-cu.json, parse the index plus every
        captured monthly page, and write the parsed structured form to
        data/cache-dotnet-cu.json.
    .DESCRIPTION
        Returns the cache path. Throws if the raw file is missing
        (caller must run Invoke-DotNetCuFetch first).
    #>
    [OutputType([string])]
    param()

    $rawPath = Get-DotNetCuRawPath
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw ('.NET CU raw file not found at "{0}". Run Invoke-DotNetCuFetch first.' -f $rawPath)
    }

    $rawBytes = [System.IO.File]::ReadAllBytes($rawPath)
    $rawJson  = [System.Text.Encoding]::UTF8.GetString($rawBytes)
    $rawAggr  = $rawJson | ConvertFrom-CanonicalJson

    $indexParsed = ConvertFrom-DotNetCuIndexMarkdown -Markdown $rawAggr.IndexBody

    $monthParsedList = New-Object 'System.Collections.Generic.List[pscustomobject]'
    foreach ($monthRaw in $rawAggr.Months) {
        $monthEntries = @()
        $monthSummary = $null
        if ($monthRaw.Ok -and -not [string]::IsNullOrEmpty($monthRaw.Markdown)) {
            $monthSummary = ConvertFrom-DotNetCuMarkdown -Markdown $monthRaw.Markdown
            $monthEntries = $monthSummary.Entries
        }
        $monthParsedList.Add([pscustomobject]@{
            Date        = $monthRaw.Date
            DateText    = $monthRaw.DateText
            Kind        = $monthRaw.Kind
            RelativeUrl = $monthRaw.RelativeUrl
            AbsoluteUrl = $monthRaw.AbsoluteUrl
            Ok          = $monthRaw.Ok
            StatusCode  = $monthRaw.StatusCode
            ErrorText   = $monthRaw.ErrorText
            Entries     = @($monthEntries)
        })
    }

    $cacheOut = [pscustomobject]@{
        Schema             = '1.0'
        GeneratedAt        = (Get-Date).ToUniversalTime().ToString('o')
        SourceFetchedAt    = $rawAggr.FetchedAt
        IndexSummary       = [pscustomobject]@{
            EntryCount   = $indexParsed.EntryCount
            Kinds        = $indexParsed.Kinds
            EarliestDate = $indexParsed.EarliestDate
            LatestDate   = $indexParsed.LatestDate
        }
        Months             = @($monthParsedList.ToArray())
    }

    $cachePath = Get-DotNetCuCachePath
    Save-CanonicalJsonFile -InputObject $cacheOut -Path $cachePath -Depth 32

    Write-Ok ('  cache-dotnet-cu.json : {0} months, {1} bytes' -f $monthParsedList.Count, (Get-Item -LiteralPath $cachePath).Length)
    return $cachePath
}

function Get-DotNetCuCache {
    <#
    .SYNOPSIS
        Read data/cache-dotnet-cu.json and return the deserialised
        object. Throws if the file is missing.
    .DESCRIPTION
        Refresher consumers call this to read the cache without
        re-parsing the raw aggregate on every build.
    #>
    [OutputType([pscustomobject])]
    param()
    $cachePath = Get-DotNetCuCachePath
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        throw ('.NET CU cache not found at "{0}". Run Update-DotNetCuCache first.' -f $cachePath)
    }
    $bytes = [System.IO.File]::ReadAllBytes($cachePath)
    $json  = [System.Text.Encoding]::UTF8.GetString($bytes)
    return ($json | ConvertFrom-CanonicalJson)
}

# ============================================================
# ISO Updater specific: Dynamic Update 36-month per-OS cache
# ============================================================
#
# Microsoft does not publish Setup and Safe OS Dynamic Update packages
# in a strict monthly cadence. Server 2025 Setup DU was published in
# 2025-09, -10 and -11 and has been absent every month since (live
# Catalog probes on 2026-05-26 confirmed 0 hits for 2026-05, -04 and
# -03). Server 2019 and Server 2016 do not publish DU monthly at all.
# An ISO-build run that searches the Catalog for "the current month"
# and errors when zero hits come back is incompatible with both
# observations.
#
# This section maintains, for each in-scope OS, a 36-month rolling
# Catalog probe history in data/cache-dynamicupdate-Server<NNNN>.json. At
# ISO-build time the Refresher consults the cache and selects, for
# each DU type, the most recent publish within the 36-month window. If
# the window contains zero entries, the Refresher logs a warning and
# proceeds without that DU type; if it contains at least one entry,
# the latest is used.
#
# The cache is populated by an out-of-band, Patch-Tuesday-triggered
# refresh action (scheduled for a later commit); ISO-build runs read
# the cache and never hit the Catalog for DU discovery.
#
# Files this section reads or writes:
#   data/cache-dynamicupdate-Server2016.json
#   data/cache-dynamicupdate-Server2019.json
#   data/cache-dynamicupdate-Server2022.json
#   data/cache-dynamicupdate-Server2025.json
#
# See SPEC.md for the design rationale and the cadence
# table that grounded these observations.

$Script:DynamicUpdateCacheWindowMonths = 36
$Script:DynamicUpdateCacheSchema       = '1.0'

function Get-DynamicUpdateCachePath {
    <#
    .SYNOPSIS
        Resolve the on-disk path of data/cache-dynamicupdate-Server<NNNN>.json for
        the given OS.
    .DESCRIPTION
        Tests can override the directory by passing -DataDir; production
        callers omit it and let the default Get-DataDirectoryPath apply.
    .EXAMPLE
        Get-DynamicUpdateCachePath -OsVersion Server2025
        # -> /.../data/cache-dynamicupdate-Server2025.json
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [string]$DataDir = ''
    )
    if ([string]::IsNullOrEmpty($DataDir)) {
        $DataDir = Get-DataDirectoryPath
    }
    return (Join-Path $DataDir ('cache-dynamicupdate-' + $OsVersion + '.json'))
}

function New-EmptyDynamicUpdateCache {
    <#
    .SYNOPSIS
        Return a fresh, empty cache object for an OS that has no
        persisted cache file yet.
    #>
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string]$OsVersion)
    return [pscustomobject]@{
        Schema          = $Script:DynamicUpdateCacheSchema
        OsVersion       = $OsVersion
        LastRefreshedAt = ''
        WindowMonths    = $Script:DynamicUpdateCacheWindowMonths
        Entries         = @()
    }
}

function Get-DynamicUpdateCache {
    <#
    .SYNOPSIS
        Read data/cache-dynamicupdate-Server<NNNN>.json and return the deserialised
        object. Returns a fresh empty cache when the file does not
        exist; never throws on missing-file (matches the "latest known
        good" stance documented in SPEC.md).
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [string]$DataDir = ''
    )
    $cachePath = Get-DynamicUpdateCachePath -OsVersion $OsVersion -DataDir $DataDir
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        return (New-EmptyDynamicUpdateCache -OsVersion $OsVersion)
    }
    $bytes = [System.IO.File]::ReadAllBytes($cachePath)
    $json  = [System.Text.Encoding]::UTF8.GetString($bytes)
    $obj   = ($json | ConvertFrom-CanonicalJson)
    # Defensive: ensure Entries serialises back as an array even if the
    # file recorded a single object due to old ConvertTo-Json behaviour.
    if ($null -eq $obj.Entries) {
        $obj | Add-Member -NotePropertyName 'Entries' -NotePropertyValue @() -Force
    }
    elseif ($obj.Entries -isnot [System.Collections.IEnumerable] -or $obj.Entries -is [string]) {
        $obj.Entries = @($obj.Entries)
    }
    else {
        $obj.Entries = @($obj.Entries)
    }
    return $obj
}

function Save-DynamicUpdateCache {
    <#
    .SYNOPSIS
        Persist a cache object to data/cache-dynamicupdate-Server<NNNN>.json with
        UTF-8 + LF + no-BOM, matching the project-wide cache file
        conventions.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Cache,
        [string]$DataDir = ''
    )
    $cachePath = Get-DynamicUpdateCachePath -OsVersion $Cache.OsVersion -DataDir $DataDir
    $dir = Split-Path -Parent $cachePath
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    Save-CanonicalJsonFile -InputObject $Cache -Path $cachePath -Depth 12
    return $cachePath
}

function Test-DynamicUpdatePatchMonth {
    <#
    .SYNOPSIS
        Validate that a PatchMonth string matches the YYYY-MM convention
        used throughout this subproject. Returns $true / $false.
    #>
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$PatchMonth)
    return ($PatchMonth -match '^\d{4}-(0[1-9]|1[0-2])$')
}

function Add-DynamicUpdateCacheEntry {
    <#
    .SYNOPSIS
        Append (or upsert) one Catalog-probe result into the per-OS
        cache file. If an entry with the same (PatchMonth, DuType)
        already exists, it is replaced in place. The file is persisted
        before the function returns.
    .DESCRIPTION
        The Entry parameter accepts a hashtable / PSCustomObject with
        the following recognised properties (extra properties are
        preserved verbatim, so the cache can carry forensic data
        without schema bumps):

          PatchMonth        string  YYYY-MM (mandatory)
          DuType            string  e.g. DynamicUpdate.Setup (mandatory)
          ProbedAt          string  ISO 8601 UTC timestamp
          Query             string  Search.aspx query the probe used
          SearchHitCount    int     total Search.aspx hits
          MatchingHitCount  int     hits that survived Title filtering
          MatchingHits      array   [{UpdateId,Title},...]
          ChosenUpdateId    string  the selected UpdateId
          ChosenTitle       string  the selected Title
          KbId              string  "KB<digits>" extracted from Title
          Success           bool    publish present (true) or absent (false)
          IsEmptyMarker     bool    Catalog 'noResultText' marker present
          Notes             string  free-form annotation

        The cache's LastRefreshedAt is updated to the entry's ProbedAt
        (or the current UTC time if ProbedAt was not supplied).
    .EXAMPLE
        Add-DynamicUpdateCacheEntry -OsVersion Server2025 -Entry @{
            PatchMonth='2026-05'; DuType='DynamicUpdate.SafeOs';
            ChosenUpdateId='3d3a4626-...'; KbId='KB5087588'; Success=$true
        }
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)]            $Entry,
        [string]$DataDir = ''
    )

    # Normalise Entry to a PSCustomObject so we can access its props uniformly.
    $entryObj = $null
    if ($Entry -is [hashtable]) {
        $entryObj = [pscustomobject]$Entry
    }
    elseif ($Entry -is [pscustomobject]) {
        $entryObj = $Entry
    }
    else {
        # ConvertFrom-Json result (from the TestHarness path) is also
        # PSCustomObject, but bare values are not. Re-roundtrip to normalise.
        $entryObj = ($Entry | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    }

    # Validate the two mandatory fields.
    $patchMonth = [string]$entryObj.PatchMonth
    $duType     = [string]$entryObj.DuType
    if ([string]::IsNullOrEmpty($patchMonth)) {
        throw 'Add-DynamicUpdateCacheEntry: Entry.PatchMonth is required.'
    }
    if (-not (Test-DynamicUpdatePatchMonth -PatchMonth $patchMonth)) {
        throw ('Add-DynamicUpdateCacheEntry: invalid PatchMonth "{0}"; expected YYYY-MM.' -f $patchMonth)
    }
    if ([string]::IsNullOrEmpty($duType)) {
        throw 'Add-DynamicUpdateCacheEntry: Entry.DuType is required.'
    }

    # If ProbedAt is missing, stamp it now.
    $probedAt = [string]$entryObj.ProbedAt
    if ([string]::IsNullOrEmpty($probedAt)) {
        $probedAt = (Get-Date).ToUniversalTime().ToString('o')
        $entryObj | Add-Member -NotePropertyName 'ProbedAt' -NotePropertyValue $probedAt -Force
    }

    $cache = Get-DynamicUpdateCache -OsVersion $OsVersion -DataDir $DataDir

    # Upsert: drop any existing entry with the same (PatchMonth, DuType).
    $kept = @($cache.Entries | Where-Object {
        -not ($_.PatchMonth -eq $patchMonth -and $_.DuType -eq $duType)
    })
    $kept = $kept + $entryObj
    $cache | Add-Member -NotePropertyName 'Entries'         -NotePropertyValue @($kept)  -Force
    $cache | Add-Member -NotePropertyName 'LastRefreshedAt' -NotePropertyValue $probedAt -Force

    $null = Save-DynamicUpdateCache -Cache $cache -DataDir $DataDir
    return $cache
}

function ConvertTo-DynamicUpdatePatchMonthSortKey {
    <#
    .SYNOPSIS
        Convert a YYYY-MM PatchMonth string into an integer (yyyy*100 +
        month) for fast Compare-Object and Sort-Object operations.
    #>
    [OutputType([int])]
    param([Parameter(Mandatory)] [string]$PatchMonth)
    if (-not (Test-DynamicUpdatePatchMonth -PatchMonth $PatchMonth)) {
        return -1
    }
    $parts = $PatchMonth -split '-'
    return ([int]$parts[0] * 100 + [int]$parts[1])
}

function Get-DynamicUpdateWindowEarliestPatchMonth {
    <#
    .SYNOPSIS
        Compute the earliest PatchMonth that still falls inside the
        36-month window relative to a reference date (defaults to now,
        UTC). Returns YYYY-MM.
    .DESCRIPTION
        Tests pass a fixed -Now to make assertions reproducible. The
        window includes the reference month; i.e. for Now=2026-05 the
        earliest in-window month is 2023-06 (35 months earlier),
        yielding a 36-month inclusive range 2023-06..2026-05.
    #>
    [OutputType([string])]
    param(
        [datetime]$Now    = [datetime]::UtcNow,
        [int]     $Months = $Script:DynamicUpdateCacheWindowMonths
    )
    # The reference month inclusive plus the prior (Months-1) months.
    $first = New-Object 'System.DateTime' -ArgumentList $Now.Year, $Now.Month, 1
    $earliest = $first.AddMonths(-($Months - 1))
    return ($earliest.ToString('yyyy-MM'))
}

function Get-LatestDynamicUpdate {
    <#
    .SYNOPSIS
        Return the most-recent successful cache entry for the given
        (OS, DuType) within the 36-month window. Returns $null when no
        in-window entry has Success=true.
    .DESCRIPTION
        Tests can pass a fixed -Now to anchor the window. By default
        the window is anchored on the current UTC clock.

        "Most recent" is decided by PatchMonth, not ProbedAt: the
        cache may have been probed multiple times for the same month,
        but the publishing month is what matters for ISO-build
        applicability. Within the same PatchMonth the upsert in
        Add-DynamicUpdateCacheEntry already keeps only the most
        recent probe.
    .EXAMPLE
        Get-LatestDynamicUpdate -OsVersion Server2025 -DuType DynamicUpdate.SafeOs
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)] [string]$DuType,
        [datetime]$Now    = [datetime]::UtcNow,
        [string]  $DataDir = ''
    )
    $cache = Get-DynamicUpdateCache -OsVersion $OsVersion -DataDir $DataDir
    if ($cache.Entries.Count -eq 0) {
        return $null
    }
    $earliestMonth = Get-DynamicUpdateWindowEarliestPatchMonth -Now $Now
    $earliestKey   = ConvertTo-DynamicUpdatePatchMonthSortKey -PatchMonth $earliestMonth
    $nowKey        = [int]$Now.Year * 100 + [int]$Now.Month

    $candidates = @($cache.Entries | Where-Object {
        $_.DuType  -eq $DuType -and
        $_.Success -eq $true
    } | Where-Object {
        $k = ConvertTo-DynamicUpdatePatchMonthSortKey -PatchMonth ([string]$_.PatchMonth)
        $k -ge $earliestKey -and $k -le $nowKey
    })
    if ($candidates.Count -eq 0) {
        return $null
    }
    # Pick the entry with the highest PatchMonth key.
    $top = $candidates | Sort-Object -Property @{
        Expression = { ConvertTo-DynamicUpdatePatchMonthSortKey -PatchMonth ([string]$_.PatchMonth) }
        Descending = $true
    } | Select-Object -First 1
    return $top
}

function Remove-DynamicUpdateOutsideWindow {
    <#
    .SYNOPSIS
        Drop cache entries whose PatchMonth is earlier than the 36-month
        window relative to a reference date (defaults to now, UTC).
        Persists the trimmed cache. Returns the trimmed cache object.
    .DESCRIPTION
        Tests anchor the window with -Now. Production callers should
        omit -Now and let the current UTC clock apply.

        The function name is singular ("Window") rather than carrying
        the literal month count ("OlderThan36Months") so the verb-noun
        convention is respected; the 36-month size is baked into the
        Get-DynamicUpdateWindowEarliestPatchMonth helper.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [datetime]$Now    = [datetime]::UtcNow,
        [string]  $DataDir = ''
    )
    $cache = Get-DynamicUpdateCache -OsVersion $OsVersion -DataDir $DataDir
    if ($cache.Entries.Count -eq 0) {
        return $cache
    }
    $earliestMonth = Get-DynamicUpdateWindowEarliestPatchMonth -Now $Now
    $earliestKey   = ConvertTo-DynamicUpdatePatchMonthSortKey -PatchMonth $earliestMonth

    $kept = @($cache.Entries | Where-Object {
        (ConvertTo-DynamicUpdatePatchMonthSortKey -PatchMonth ([string]$_.PatchMonth)) -ge $earliestKey
    })
    if ($kept.Count -eq $cache.Entries.Count) {
        # Nothing to drop; avoid a no-op write.
        return $cache
    }
    $cache | Add-Member -NotePropertyName 'Entries' -NotePropertyValue @($kept) -Force
    $null = Save-DynamicUpdateCache -Cache $cache -DataDir $DataDir
    return $cache
}

# ============================================================
# ISO Updater specific: Microsoft Update Catalog scraper
# ============================================================
#
# Implementation note: this module's functions are loosely modelled
# after the PoC PowerShell sample published by Kazuro Yamauchi at
# say-tech.co.jp [2025memo54] and the established community module
# MSCatalogLTS (PowerShell Gallery, owner Marco-online). Both confirm
# the same pattern:
#
#   1. GET  https://www.catalog.update.microsoft.com/Search.aspx?q=<KB>
#      -> HTML; locate goToDetails("<GUID>") calls to extract UpdateId
#   2. POST https://www.catalog.update.microsoft.com/DownloadDialog.aspx
#      with body containing the UpdateID -> JSON-in-text response;
#      extract downloadInformation[N].files[N].url
#   3. GET  https://www.catalog.update.microsoft.com/ScopedViewInline.aspx?
#         updateid=<GUID>
#      -> HTML; the "This update has been superseded by ..." and
#      "This update supersedes ..." sections drive the dependency graph
#
# Caveats (also explicit in SPEC D.16):
#   * Microsoft Update Catalog has no public API. Site HTML structure
#     changes break this code. The caller MUST handle scrape failures
#     via AutoRefreshPolicy.FallbackOnScrapeFailure.
#   * Some updates publish multiple files per UpdateId (e.g. .NET
#     family updates, multi-arch bundles). Use Select-CanonicalPatchFile
#     to pick the right one and reject Express/Delta/PSF variants.
#   * Microsoft Update Catalog requires User-Agent and basic-parsing
#     mode on Windows PowerShell 5.1; we set both unconditionally.

$Script:CatalogTitleNegativeTokens = @(
    'Windows 11',
    'arm64'
)

function Get-CatalogTitleTokenList {
    <#
    .SYNOPSIS
        Return the per-OS positive title-token list from
        data/config-<OsVersion>.json that is used to narrow Microsoft
        Update Catalog responses to the right OS variant.
    .DESCRIPTION
        SPEC.md specifies that the disambiguating token
        list is Config-driven, not hardcoded in PowerShell. This helper
        is the single read path: it parses the OS Config and returns
        the `Common.CatalogTitleTokens` array. When the field is
        absent the function returns an empty array (callers then
        accept the first matching hit, per the SPEC default).

        Companion script-level variable
        `$Script:CatalogTitleNegativeTokens` carries the OS-uniform
        negative exclusion list (e.g. 'Windows 11', 'arm64'). The
        positive and negative lists together form the narrow filter.
    .EXAMPLE
        Get-CatalogTitleTokenList -OsVersion Server2025
        # -> @('Microsoft server operating system version 24H2', 'Windows Server 2025')
    #>
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string]$OsVersion)

    $configPath = Get-OsConfigPath -OsKey $OsVersion
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return @()
    }
    $bytes  = [System.IO.File]::ReadAllBytes($configPath)
    $json   = [System.Text.Encoding]::UTF8.GetString($bytes)
    $config = $json | ConvertFrom-CanonicalJson
    if ($null -eq $config -or $null -eq $config.Common) {
        return @()
    }
    $common = $config.Common
    if (-not ($common.PSObject.Properties.Name -contains 'CatalogTitleTokens')) {
        return @()
    }
    $value = $common.CatalogTitleTokens
    if ($null -eq $value) {
        return @()
    }
    return @($value | ForEach-Object { [string]$_ })
}

function Test-CatalogTitleMatch {
    <#
    .SYNOPSIS
        Decide whether a Microsoft Update Catalog hit title belongs to
        the given OS, based on the Config-driven positive tokens and
        the hardcoded negative exclusion list.
    .DESCRIPTION
        Matching is case-insensitive substring. A title passes when it
        contains ANY positive token AND contains NONE of the negative
        tokens. Empty positive list is permissive (the function then
        returns $true unless the title contains a negative token), to
        match the SPEC default of "accept the first matching hit when
        no per-OS tokens are configured".
    .EXAMPLE
        Test-CatalogTitleMatch -OsVersion Server2019 `
            -Title '2026-05 Cumulative Update for .NET Framework 3.5 and 4.8 for Windows Server 2019 for x64 (KB5087066)'
        # -> True

        Test-CatalogTitleMatch -OsVersion Server2019 `
            -Title '2026-05 Cumulative Update for .NET Framework 3.5 and 4.8 for Windows 10 Version 1809 for x64 (KB5087066)'
        # -> False (no positive token match)
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)] [string]$Title
    )

    if ([string]::IsNullOrEmpty($Title)) { return $false }
    $titleLower = $Title.ToLowerInvariant()

    # Negative exclusion first: a single negative hit disqualifies regardless of positive matches.
    foreach ($neg in $Script:CatalogTitleNegativeTokens) {
        if ([string]::IsNullOrEmpty($neg)) { continue }
        if ($titleLower.Contains($neg.ToLowerInvariant())) {
            return $false
        }
    }

    $positives = @(Get-CatalogTitleTokenList -OsVersion $OsVersion)
    if ($positives.Count -eq 0) {
        # SPEC default: no Config-side narrowing -> permissive accept.
        return $true
    }
    foreach ($pos in $positives) {
        if ([string]::IsNullOrEmpty($pos)) { continue }
        if ($titleLower.Contains($pos.ToLowerInvariant())) {
            return $true
        }
    }
    return $false
}

function Get-UpdateIdFromCatalog {
    <#
    .SYNOPSIS
        Search Microsoft Update Catalog for a KB ID and return an array
        of (UpdateId, Title) tuples.
    .DESCRIPTION
        GETs the Search.aspx page for the given KB number and extracts
        UpdateID GUIDs from goToDetails(...) calls. Returns all matches.
        Caller is expected to narrow down by Title (architecture,
        OS variant) before passing the UpdateId to Get-DownloadLinkFromCatalog.
    .EXAMPLE
        Get-UpdateIdFromCatalog -KbId KB5058524 |
            Where-Object { $_.Title -match 'Server 2025' -and $_.Title -match 'x64' }
    #>
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string]$KbId,
        [int]$MaxRetries = 3
    )
    $searchUri = 'https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($KbId)
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (compatible; UpdateWsi/r02)' }
    $resp = $null
    $attempt = 0
    while ($attempt -lt $MaxRetries -and -not $resp) {
        $attempt++
        try {
            # -UseBasicParsing required on Win PS 5.1 (PSA3005 not applicable here)
            $resp = Invoke-WebRequest -Uri $searchUri -UseBasicParsing -Headers $headers `
                                      -TimeoutSec 60 -ErrorAction Stop
        } catch {
            if ($attempt -ge $MaxRetries) { throw }
            Wait-WithJitter -BaseSeconds 2 -JitterRange 1
        }
    }
    if ($resp.StatusCode -ne 200) {
        throw ('Microsoft Update Catalog returned HTTP {0} for KB {1}.' -f $resp.StatusCode, $KbId)
    }
    $pattern = '(?is)<a[^>]*onclick\s*=\s*(["'']?)goToDetails\(\s*"([0-9A-Fa-f-]{36})"\s*\)\s*;?\s*\1[^>]*>\s*(.*?)\s*</a>'
    $items = New-Object System.Collections.Generic.List[object]
    $matchList = [regex]::Matches($resp.Content, $pattern)
    foreach ($m in $matchList) {
        $guid = $m.Groups[2].Value
        $raw  = $m.Groups[3].Value
        $txt  = ($raw -replace '<[^>]+>', '')
        $txt  = [System.Net.WebUtility]::HtmlDecode($txt)
        $title = ($txt -replace '\s+', ' ').Trim()
        $items.Add([pscustomobject][ordered]@{
            UpdateId = $guid
            Title    = $title
            KbId     = $KbId
        }) | Out-Null
    }
    # Deduplicate by UpdateId
    return @($items | Sort-Object UpdateId -Unique)
}

function Get-DownloadLinkFromCatalog {
    <#
    .SYNOPSIS
        For an UpdateId returned by Get-UpdateIdFromCatalog, POST to
        DownloadDialog.aspx and extract direct download URL(s).
    .DESCRIPTION
        Returns an array of (Url, FileName) tuples. Most updates have
        one file; .NET family updates and bundles may have several.
    #>
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string]$UpdateId,
        [int]$MaxRetries = 3
    )
    $uri = 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx'
    $postJson = @{ size = 0; UpdateID = $UpdateId; UpdateIDInfo = $UpdateId } | ConvertTo-Json -Compress
    $body = @{ UpdateIDs = '[' + $postJson + ']' }
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (compatible; UpdateWsi/r02)' }
    $resp = $null
    $attempt = 0
    while ($attempt -lt $MaxRetries -and -not $resp) {
        $attempt++
        try {
            $resp = Invoke-WebRequest -Uri $uri -Method Post -Body $body `
                                      -ContentType 'application/x-www-form-urlencoded' `
                                      -UseBasicParsing -Headers $headers `
                                      -TimeoutSec 60 -ErrorAction Stop
        } catch {
            if ($attempt -ge $MaxRetries) { throw }
            Wait-WithJitter -BaseSeconds 2 -JitterRange 1
        }
    }
    if ($resp.StatusCode -ne 200) {
        throw ('DownloadDialog returned HTTP {0} for UpdateId {1}.' -f $resp.StatusCode, $UpdateId)
    }
    # Pattern extracts: downloadInformation[N].files[N].url = '<url>';
    $pattern = "downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=\s*'([^']+)'"
    $items = New-Object System.Collections.Generic.List[object]
    $matchList = [regex]::Matches($resp.Content, $pattern)
    foreach ($m in $matchList) {
        $url = $m.Groups[1].Value
        $fn  = [System.IO.Path]::GetFileName(([uri]$url).AbsolutePath)
        $items.Add([pscustomobject][ordered]@{
            Url      = $url
            FileName = $fn
        }) | Out-Null
    }
    return @($items | Sort-Object Url -Unique)
}

function Select-CanonicalPatchFile {
    <#
    .SYNOPSIS
        From a list of download links returned by
        Get-DownloadLinkFromCatalog, pick the ONE file that is the full
        standalone package suitable for offline image servicing.
    .DESCRIPTION
        Microsoft Update Catalogue often publishes multiple files per
        UpdateId. The Catalogue does not annotate them; callers must
        choose by inspecting file names. Examples for a .NET CU:

          windows10.0-kb5037591-x64.msu               (Full, ~110 MB)   <- want this
          windows10.0-kb5037591-x64-express.cab       (Express delta)   <- reject
          windows10.0-kb5037591-x64-delta.cab         (Delta)           <- reject
          windows10.0-kb5037591-x64-pkgProperties.txt (Metadata)        <- reject
          windows10.0-kb5037591-ndp48-x64.msu         (NDP 4.8 variant) <- depends

        Picking Express or Delta breaks Add-WindowsPackage because they
        require a base from which to apply the differential.

        Scoring rules (higher = better):
          +200  ends with .msu
          +100  ends with .cab
          +50   filename contains the requested architecture (e.g. x64)
          +30   filename contains 'full'
          +100  for DotNet type AND filename contains ndp<DotNetVersion>
          -10000 filename contains 'express' (differential package, useless standalone)
          -10000 filename contains 'delta'   (same)
          -10000 filename contains 'psf'     (Patch Storage File only)
          -200   filename ends with .wim or .esd (full image, not a patch)
          -50    filename contains 'arm64' when x64 requested

        Returns the highest-scoring link with score above 0; $null if
        no link survives the filtering.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$Links,
        [Parameter(Mandatory)] [string]$PatchType,
        [string]$Architecture  = 'x64',
        [string]$DotNetVersion = ''
    )
    if (-not $Links -or $Links.Count -eq 0) { return $null }

    $scored = New-Object System.Collections.Generic.List[object]
    foreach ($lnk in $Links) {
        if (-not $lnk -or -not $lnk.FileName) { continue }
        $fn = $lnk.FileName.ToLower()
        $score = 0

        # Disqualifiers (any one of these makes the file unusable standalone)
        if ($fn -match 'express') { $score -= 10000 }
        if ($fn -match 'delta')   { $score -= 10000 }
        if ($fn -match '\.psf$' -or $fn -match '-psf-') { $score -= 10000 }
        if ($fn -match 'pkgproperties' -or $fn -match '\.txt$') { $score -= 10000 }

        # Extension preference
        if ($fn -match '\.msu$') { $score += 200 }
        elseif ($fn -match '\.cab$') { $score += 100 }
        elseif ($fn -match '\.wim$' -or $fn -match '\.esd$') { $score -= 200 }

        # Architecture match
        if ($Architecture) {
            $archLower = $Architecture.ToLower()
            if ($fn -match [regex]::Escape($archLower)) { $score += 50 }
        }

        # Penalise foreign arch when we want x64
        if ($Architecture -eq 'x64') {
            if ($fn -match 'arm64') { $score -= 50 }
            if ($fn -match 'x86' -and $fn -notmatch 'x86_64') { $score -= 50 }
        }

        # Token "full" is a positive signal for standalone packages
        if ($fn -match 'full') { $score += 30 }

        # .NET CU: prefer ndp<version> variant (e.g. ndp48 for .NET 4.8)
        if ($PatchType -eq 'DotNet.Runtime' -and $DotNetVersion) {
            $ndpTok = 'ndp' + ($DotNetVersion -replace '\.', '')
            if ($fn -match [regex]::Escape($ndpTok)) { $score += 100 }
        }

        $scored.Add([pscustomobject]@{
            Link  = $lnk
            Score = $score
        }) | Out-Null
    }

    $best = $scored | Where-Object { $_.Score -gt 0 } | Sort-Object Score -Descending | Select-Object -First 1
    if (-not $best) { return $null }
    return $best.Link
}

# psa-disable-next-line PSA6003 -- function intentionally returns multiple files (companion to the singular Select-CanonicalPatchFile); plural noun accurately describes the return contract
function Select-AllCanonicalPatchFiles {
    <#
    .SYNOPSIS
        From a list of download links returned by
        Get-DownloadLinkFromCatalog, return ALL files that are full
        standalone packages suitable for offline image servicing.
    .DESCRIPTION
        Companion to Select-CanonicalPatchFile. The single-file picker
        is appropriate for SSU / LCU / SafeOS DU / Setup DU, which
        Microsoft publishes as a single .msu or .cab per UpdateId.

        Umbrella .NET CU updates (e.g. Server 2019 KB5088864 which
        bundles .NET 4.7.2 and 4.8 servicing) attach MULTIPLE files
        to a single UpdateId. Calling Select-CanonicalPatchFile on
        such an UpdateId silently drops all but one .msu, leaving
        whichever runtime corresponds to the dropped file unpatched
        in install.wim.

        This function applies the same scoring rules (so Express /
        Delta / PSF / metadata are still rejected) but returns every
        link that scored > 0, sorted descending by Score for
        determinism. Callers should iterate the returned array and
        emit one PatchBaseline entry per file, all keyed off the
        umbrella KB / UpdateId.

        Returns an empty array when no link survives filtering.
    #>
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$Links,
        [Parameter(Mandatory)] [string]$PatchType,
        [string]$Architecture  = 'x64'
    )
    if (-not $Links -or $Links.Count -eq 0) { return @() }

    $scored = New-Object System.Collections.Generic.List[object]
    foreach ($lnk in $Links) {
        if (-not $lnk -or -not $lnk.FileName) { continue }
        $fn = $lnk.FileName.ToLower()
        $score = 0

        # Disqualifiers (any one of these makes the file unusable standalone)
        if ($fn -match 'express') { $score -= 10000 }
        if ($fn -match 'delta')   { $score -= 10000 }
        if ($fn -match '\.psf$' -or $fn -match '-psf-') { $score -= 10000 }
        if ($fn -match 'pkgproperties' -or $fn -match '\.txt$') { $score -= 10000 }

        # Extension preference
        if ($fn -match '\.msu$') { $score += 200 }
        elseif ($fn -match '\.cab$') { $score += 100 }
        elseif ($fn -match '\.wim$' -or $fn -match '\.esd$') { $score -= 200 }

        # Architecture match
        if ($Architecture) {
            $archLower = $Architecture.ToLower()
            if ($fn -match [regex]::Escape($archLower)) { $score += 50 }
        }
        if ($Architecture -eq 'x64') {
            if ($fn -match 'arm64') { $score -= 50 }
            if ($fn -match 'x86' -and $fn -notmatch 'x86_64') { $score -= 50 }
        }

        if ($fn -match 'full') { $score += 30 }

        # .NET CU: prefer ndp<version> variant (e.g. ndp48 for .NET 4.8).
        # Mirrors the same scoring used by Select-CanonicalPatchFile so
        # the multi-file picker preserves the per-runtime preference
        # when multiple .NET CU siblings are present under one umbrella
        # KB.
        if ($PatchType -eq 'DotNet.Runtime') {
            if ($fn -match 'ndp\d+') { $score += 100 }
        }

        $scored.Add([pscustomobject]@{
            Link  = $lnk
            Score = $score
        }) | Out-Null
    }

    $survivors = @($scored | Where-Object { $_.Score -gt 0 } | Sort-Object Score -Descending)
    if ($survivors.Count -eq 0) { return @() }
    return @($survivors | ForEach-Object { $_.Link })
}

function Test-IsCombinedLcuTitle {
    <#
    .SYNOPSIS
        Returns $true if the LCU title self-identifies as a "combined"
        package that embeds the servicing stack update.
    .DESCRIPTION
        Microsoft started embedding the SSU into the LCU "in rare cases
        a breaking change ... requires a standalone servicing stack
        update to be published" (Microsoft Learn). In normal months,
        a standalone SSU is NOT published; the LCU is the combined
        package. This function tries to identify explicit combined
        markers in the title; the orchestrator additionally treats
        any month where "SSU search returned zero AND LCU search
        returned non-zero" as a combined-month even if the title
        does not literally say so.
    #>
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$LcuTitle)
    $t = $LcuTitle.ToLower()
    if ($t -match 'combined') { return $true }
    if ($t -match 'servicing stack') { return $true }
    return $false
}

function Get-CatalogQueryUrl {
    <#
    .SYNOPSIS
        Build the Catalogue Search.aspx URL with optional Product /
        Description filters appended via the search syntax. Filters
        are AND-combined automatically by the Catalogue.
    .DESCRIPTION
        The Catalogue does not have a documented advanced-search API,
        but the public Search.aspx accepts URL-encoded multi-word
        queries that include filter tokens. Tokens are matched against
        the Title / Product / Description columns.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$QueryTemplate,
        [string[]]$ProductFilter = @(),
        [string]$DescriptionFilter = ''
    )
    $parts = @($QueryTemplate)
    foreach ($pf in $ProductFilter) {
        if (-not [string]::IsNullOrWhiteSpace($pf)) { $parts += ('"' + $pf + '"') }
    }
    if (-not [string]::IsNullOrWhiteSpace($DescriptionFilter)) {
        $parts += ('"' + $DescriptionFilter + '"')
    }
    $combined = ($parts -join ' ')
    return 'https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($combined)
}

function ConvertFrom-CatalogSupersedenceSection {
    <#
    .SYNOPSIS
        Parse one ScopedView supersedence section into a deterministic,
        sorted, deduplicated KB list plus the immediate-predecessor KB.
    .DESCRIPTION
        Each section lists the whole chain as repeated
        <div ...>TITLE (KBxxxx)</div> entries. The Catalog reorders these
        per request, so document order is not stable. 'Latest' (the
        immediate predecessor) is the entry carrying the highest yyyy-MM
        title prefix, breaking ties on the highest KB number, and falling
        back to the highest KB number when no entry carries a yyyy-MM
        prefix. See SPEC B.12.
    #>
    [OutputType([pscustomobject])]
    param([string]$Html)
    $kbPattern = 'KB\d{6,7}'
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $latestKb = ''
    $latestYm = ''
    if (-not [string]::IsNullOrEmpty($Html)) {
        foreach ($entry in [regex]::Matches($Html, '(?is)<div[^>]*>(.*?)</div>')) {
            $txt = $entry.Groups[1].Value
            $kbM = [regex]::Match($txt, $kbPattern)
            if (-not $kbM.Success) { continue }
            $kb = $kbM.Value
            [void]$set.Add($kb)
            $ymM = [regex]::Match($txt, '\d{4}-\d{2}')
            $ym  = if ($ymM.Success) { $ymM.Value } else { '' }
            if (($ym -gt $latestYm) -or
                ($ym -eq $latestYm -and [string]::Compare($kb, $latestKb, [System.StringComparison]::Ordinal) -gt 0)) {
                $latestYm = $ym
                $latestKb = $kb
            }
        }
        if ($set.Count -eq 0) {
            foreach ($k in [regex]::Matches($Html, $kbPattern)) { [void]$set.Add($k.Value) }
        }
    }
    $arr = [string[]]@($set)
    [array]::Sort($arr, [System.StringComparer]::Ordinal)
    if ([string]::IsNullOrEmpty($latestKb) -and $arr.Count -gt 0) {
        $latestKb = ($arr | Sort-Object { [int64]($_ -replace '\D', '') } -Descending | Select-Object -First 1)
    }
    return [pscustomobject][ordered]@{ All = @($arr); Latest = $latestKb }
}

function Get-SupersedenceFromCatalog {
    <#
    .SYNOPSIS
        For an UpdateId, fetch ScopedViewInline.aspx and extract the
        "supersedes" and "superseded by" KB lists.
    .DESCRIPTION
        These two lists drive PatchBaseline.Patches[].Supersedes and
        the dependency_graph diagnostic export. They are best-effort:
        the page layout changes occasionally and missing data is not
        a hard failure.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$UpdateId,
        [int]$MaxRetries = 3
    )
    $uri = 'https://www.catalog.update.microsoft.com/ScopedViewInline.aspx?updateid=' + [uri]::EscapeDataString($UpdateId)
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (compatible; UpdateWsi/r02)' }
    $resp = $null
    $attempt = 0
    while ($attempt -lt $MaxRetries -and -not $resp) {
        $attempt++
        try {
            $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -Headers $headers `
                                      -TimeoutSec 60 -ErrorAction Stop
        } catch {
            if ($attempt -ge $MaxRetries) {
                # Supersedence info is best-effort
                return [pscustomobject][ordered]@{
                    Supersedes       = @()
                    SupersedesLatest = ''
                    SupersededBy     = @()
                    Error            = $_.Exception.Message
                }
            }
            Wait-WithJitter -BaseSeconds 2 -JitterRange 1
        }
    }
    # Capture the FULL supersedes / superseded-by sections. Each lists the
    # whole chain as repeated <div>TITLE (KBxxxx)</div> entries and ends at
    # the next id="..." panel. The previous '(.*?)</div>' boundary stopped at
    # the first inner entry, capturing a single KB whose identity was
    # non-deterministic because the Catalog reorders the list per request.
    # ConvertFrom-CatalogSupersedenceSection returns the full sorted chain
    # plus the immediate predecessor (Latest). See SPEC B.12.
    $reSupBy = '(?is)id\s*=\s*["'']supersededbyInfo["''][^>]*>(.*?)(?=\bid\s*=\s*["'']|\z)'
    $reSup   = '(?is)id\s*=\s*["'']supersedesInfo["''][^>]*>(.*?)(?=\bid\s*=\s*["'']|\z)'
    $mBy  = [regex]::Match($resp.Content, $reSupBy)
    $mSup = [regex]::Match($resp.Content, $reSup)
    $byParsed  = ConvertFrom-CatalogSupersedenceSection -Html $(if ($mBy.Success)  { $mBy.Groups[1].Value }  else { '' })
    $supParsed = ConvertFrom-CatalogSupersedenceSection -Html $(if ($mSup.Success) { $mSup.Groups[1].Value } else { '' })
    return [pscustomobject][ordered]@{
        Supersedes       = $supParsed.All
        SupersedesLatest = $supParsed.Latest
        SupersededBy     = $byParsed.All
        Error            = $null
    }
}

function Get-PatchSetFromReleaseInfoDiscovery {
    <#
    .SYNOPSIS
        Pure-cache KB discovery: given an OS and patch month, look up
        the (LCU, .NET CU, DU.*) KB / UpdateId tuples from the three
        local cache files written by the Step 2a refresh layer.
    .DESCRIPTION
        This is the offline half of `Resolve-PatchSetFromReleaseInfo`.
        It performs no network I/O; it reads the local caches under
        data/ (or under -DataDir when tests pass it) and returns a
        structured list of "discovery records" that the orchestrator
        then resolves to file URLs via the Microsoft Update Catalog.

        Each discovery record carries enough information for the
        orchestrator to call the Catalog URL resolver with a KB or an
        UpdateId, plus the canonical Type so the resulting
        PatchBaseline entry classification is unambiguous.

        Return shape per record:
          @{
            Type           = 'LCU' | 'DotNet.Runtime' |
                             'DynamicUpdate.Setup' | 'DynamicUpdate.SafeOs'
            KbId           = 'KB...'              (LCU / .NET CU)
            UpdateId       = '...guid...'         (DU only; '' otherwise)
            SourceCache    = 'release-info' | 'dotnet-cu' | 'dynamic-update'
            SourceRow      = <opaque object from cache, for diagnostics>
            DiscoveryNote  = string
          }

        Behaviours:
        - LCU: read release-info cache, match (OsShortName = OsVersion)
          AND (UpdateTypeYear*100 + UpdateTypeMonth) == requested month.
          One LCU row per month per OS in normal operation; the most
          recently produced row wins when multiples exist (e.g. preview
          + general-availability variants share a month -- the preview
          letter sorts later under Microsoft's UpdateType naming so it
          is preferred).
        - .NET CU: read .NET CU cache, find Months[] entry matching
          the requested month (Date or DateText prefix). Emit ONE
          discovery record per Rows[] entry for the requested OS (per
          SPEC B.22.5 every release-notes row becomes its own
          PatchBaseline entry).
        - DU: read per-OS DU cache, call the in-process
          Get-LatestDynamicUpdate for each of
          (DynamicUpdate.Setup, DynamicUpdate.SafeOs) with the request
          month as -Now anchor. Each successful entry becomes a
          discovery record carrying the cache's ChosenUpdateId; a
          null/$null/IsEmptyMarker entry yields no record (DU is
          legitimately absent for that month, e.g. Server 2025 Setup
          since 2025-12).

        Missing caches are NOT a fatal error; the function silently
        skips that source and continues with the others. The caller
        decides whether to error on empty discovery.

        This discovery step does NOT emit a standalone SSU record.
        On the combined model (e.g. Server 2022/2025) the monthly LCU
        embeds the SSU and carries both .msu URLs under one Catalog
        UpdateId, which the per-file Convert-CatalogPatchToBaselineEntry
        path classifies via filename heuristic. On the separate model
        (e.g. Server 2016/2019) the standalone same-month SSU is handled
        downstream by Resolve-PatchSetFromReleaseInfo.
    .EXAMPLE
        Get-PatchSetFromReleaseInfoDiscovery -OsVersion Server2025 `
            -PatchMonth '2026-05'
    #>
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)] [string]$PatchMonth,
        [string]$DataDir = ''
    )

    if (-not (Test-DynamicUpdatePatchMonth -PatchMonth $PatchMonth)) {
        throw ('Get-PatchSetFromReleaseInfoDiscovery: invalid PatchMonth "{0}"; expected YYYY-MM.' -f $PatchMonth)
    }
    $monthKey = ConvertTo-DynamicUpdatePatchMonthSortKey -PatchMonth $PatchMonth
    $records  = New-Object 'System.Collections.Generic.List[pscustomobject]'

    # ----- LCU from release-info cache -----
    $relInfoCachePath = if ([string]::IsNullOrEmpty($DataDir)) {
        Get-ReleaseInfoCachePath
    } else {
        (Join-Path $DataDir 'cache-release-info.json')
    }
    if (Test-Path -LiteralPath $relInfoCachePath -PathType Leaf) {
        $relJson  = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($relInfoCachePath))
        $relCache = $relJson | ConvertFrom-CanonicalJson
        $monthlyReleases = @()
        if ($null -ne $relCache -and $relCache.PSObject.Properties.Name -contains 'MonthlyReleases') {
            $monthlyReleases = @($relCache.MonthlyReleases)
        }
        $candidates = @($monthlyReleases | Where-Object {
            $row = $_
            if ([string]$row.OsShortName -ne $OsVersion) { return $false }
            $rowKey = ([int]$row.UpdateTypeYear) * 100 + ([int]$row.UpdateTypeMonth)
            return ($rowKey -eq $monthKey)
        })
        if ($candidates.Count -gt 0) {
            # When multiple rows share a month (e.g. baseline + preview), prefer the row
            # with the lexically greatest UpdateType letter, then the latest AvailabilityDate.
            $pickedLcu = @($candidates | Sort-Object @{
                Expression = { [string]$_.UpdateTypeLetter }; Descending = $true
            }, @{
                Expression = { [string]$_.AvailabilityDate }; Descending = $true
            }) | Select-Object -First 1
            if ($null -ne $pickedLcu -and -not [string]::IsNullOrEmpty([string]$pickedLcu.KbId)) {
                $records.Add([pscustomobject]@{
                    Type          = 'LCU'
                    KbId          = [string]$pickedLcu.KbId
                    UpdateId      = ''
                    SourceCache   = 'release-info'
                    SourceRow     = $pickedLcu
                    DiscoveryNote = ('LCU from release-info: UpdateType={0} {1}{2} AvailabilityDate={3}' -f $pickedLcu.UpdateType, $pickedLcu.UpdateTypeYear, $pickedLcu.UpdateTypeMonth, $pickedLcu.AvailabilityDate)
                })
            }
        }
    }

    # ----- .NET CU from dotnet-cu cache -----
    #
    # Build a case-insensitive set of LCU KbIds already discovered above
    # so the .NET CU loop can dedup against them. Per SPEC.md,
    # the Windows 10 1607 / Server 2016 era LCU literally embeds the
    # .NET 3.5 / 4.6.2 / 4.7.x cumulative-update payload as OS components
    # ("sliced cumulative update" design): Microsoft's
    # learn.microsoft.com .NET Framework release-notes consequently
    # re-lists the LCU KB under the Server 2016 .NET CU section
    # (e.g. KB5087537 = LCU of 2026-05 appears both in
    # `windows-server-release-info` and in the .NET release-notes table
    # row "Windows 10 1607 and Windows Server 2016 / .NET Framework
    # 3.5, 4.6.2, 4.7, 4.7.1, 4.7.2"). Emitting both records would
    # cause the resolver to write two Lines entries pointing
    # at the same .msu file with different Type values. LCU is the
    # authoritative source, so any .NET CU row whose KbId matches an
    # already-discovered LCU KbId is skipped here. Server 2019 / 2022
    # / 2025 split the .NET CU into separate KBs and are unaffected.
    $lcuKbSet = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($r in $records) {
        if ([string]$r.Type -eq 'LCU' -and -not [string]::IsNullOrEmpty([string]$r.KbId)) {
            [void]$lcuKbSet.Add([string]$r.KbId)
        }
    }
    # Carry-forward safety (B.22.5): a .NET CU row can carry a KbId that is
    # actually an LCU in some month -- e.g. the Server 2016 sliced cumulative
    # KB5087537, which Microsoft lists under a .NET row. The $records loop
    # above only sees this month's LCU, so when a prior month's .NET rows are
    # carried forward below, a prior-month LCU KbId could resurface as a
    # spurious .NET CU. Seed the dedup set with every LCU KbId release-info
    # lists for this OS (any in-cache month), so a KB that is an LCU in any
    # month is never emitted as a .NET CU.
    if ((Test-Path Variable:monthlyReleases) -and $monthlyReleases) {
        foreach ($row in $monthlyReleases) {
            if ([string]$row.OsShortName -eq $OsVersion -and -not [string]::IsNullOrEmpty([string]$row.KbId)) {
                [void]$lcuKbSet.Add([string]$row.KbId)
            }
        }
    }

    $dotnetCachePath = if ([string]::IsNullOrEmpty($DataDir)) {
        Get-DotNetCuCachePath
    } else {
        (Join-Path $DataDir 'cache-dotnet-cu.json')
    }
    if (Test-Path -LiteralPath $dotnetCachePath -PathType Leaf) {
        $dotnetJson  = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($dotnetCachePath))
        $dotnetCache = $dotnetJson | ConvertFrom-CanonicalJson
        $months = @()
        if ($null -ne $dotnetCache -and $dotnetCache.PSObject.Properties.Name -contains 'Months') {
            $months = @($dotnetCache.Months)
        }
        # Select the .NET CU month: prefer the exact PatchMonth; if that month
        # published no .NET CU for this OS, carry forward the most-recent .NET
        # CU month that is <= PatchMonth, still inside the 36-month lookback
        # window, and that carries a row for this OS. .NET Framework CUs are
        # cumulative and OS-lifecycle-applicable, so the latest-applicable
        # build is the correct content for a fully-patched ISO; silently
        # dropping it on a publication-gap month (a month with no .NET CU)
        # would ship an ISO with no .NET servicing. Mirrors the Dynamic Update
        # 36-month recency (Get-LatestDynamicUpdate); see SPEC B.22.5.
        $dotnetAnchorDate  = [datetime]::ParseExact(($PatchMonth + '-01'), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $dotnetEarliestKey = ConvertTo-DynamicUpdatePatchMonthSortKey -PatchMonth (Get-DynamicUpdateWindowEarliestPatchMonth -Now $dotnetAnchorDate)
        $monthEntry      = $null
        $monthEntryKey   = -1
        $monthEntryMonth = ''
        foreach ($m in $months) {
            $isoDate = [string]$m.Date
            if ([string]::IsNullOrWhiteSpace($isoDate) -or $isoDate.Length -lt 7) { continue }
            $mMonth = $isoDate.Substring(0, 7)
            $mKey   = ConvertTo-DynamicUpdatePatchMonthSortKey -PatchMonth $mMonth
            if ($mKey -lt 0 -or $mKey -gt $monthKey -or $mKey -lt $dotnetEarliestKey) { continue }
            $hasOsRow = $false
            if ($m.PSObject.Properties.Name -contains 'Entries') {
                $hasOsRow = @($m.Entries | Where-Object { [string]$_.OsNormalised -eq $OsVersion }).Count -gt 0
            }
            if (-not $hasOsRow) { continue }
            if ($mKey -gt $monthEntryKey -or ($mKey -eq $monthEntryKey -and $null -ne $monthEntry -and [string]::Compare($isoDate, [string]$monthEntry.Date) -gt 0)) {
                $monthEntry      = $m
                $monthEntryKey   = $mKey
                $monthEntryMonth = $mMonth
            }
        }
        $dotnetCarriedForward = ($null -ne $monthEntry -and $monthEntryMonth -ne $PatchMonth)
        if ($dotnetCarriedForward) {
            Write-Step ('  No .NET CU published for {0} {1}; carried forward the latest in-window .NET CU from {2}.' -f $PatchMonth, $OsVersion, $monthEntryMonth)
        }
        if ($null -ne $monthEntry -and $monthEntry.PSObject.Properties.Name -contains 'Entries') {
            $osBlocks = @($monthEntry.Entries | Where-Object { [string]$_.OsNormalised -eq $OsVersion })
            foreach ($block in $osBlocks) {
                $rows = @()
                if ($block.PSObject.Properties.Name -contains 'Rows') { $rows = @($block.Rows) }
                foreach ($row in $rows) {
                    $rowKb = [string]$row.KbId
                    if ([string]::IsNullOrEmpty($rowKb)) { continue }
                    # SPEC.md LCU-priority dedup: drop any .NET CU
                    # row whose KbId duplicates an LCU KbId already in
                    # $records. See the long comment above the
                    # $lcuKbSet construction for the Microsoft-side
                    # rationale (Server 2016 sliced cumulative update).
                    if ($lcuKbSet.Contains($rowKb)) {
                        Write-Verbose ('Get-PatchSetFromReleaseInfoDiscovery: skipping .NET CU row {0} for OS={1} Month={2}; duplicates an LCU KbId already discovered (per SPEC.md, LCU is authoritative).' -f $rowKb, $OsVersion, $PatchMonth)
                        continue
                    }
                    $records.Add([pscustomobject]@{
                        Type          = 'DotNet.Runtime'
                        KbId          = $rowKb
                        UpdateId      = ''
                        SourceCache   = 'dotnet-cu'
                        SourceRow     = $row
                        DiscoveryNote = (('DotNet.Runtime from dotnet-cu: OsLabel="{0}" versions="{1}"' -f $block.OsLabel, $row.DotNetVersions) + $(if ($dotnetCarriedForward) { ' (carried forward from {0}; no {1} .NET CU published)' -f $monthEntryMonth, $PatchMonth } else { '' }))
                    })
                }
            }
        }
    }

    # ----- DU from per-OS DU cache -----
    $duAnchor = [datetime]::ParseExact(($PatchMonth + '-15'), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    foreach ($duType in @('DynamicUpdate.Setup', 'DynamicUpdate.SafeOs')) {
        $latest = $null
        try {
            $latest = Get-LatestDynamicUpdate -OsVersion $OsVersion -DuType $duType -Now $duAnchor -DataDir $DataDir
        } catch {
            $latest = $null
        }
        if ($null -ne $latest -and -not [string]::IsNullOrEmpty([string]$latest.ChosenUpdateId)) {
            $records.Add([pscustomobject]@{
                Type          = $duType
                KbId          = [string]$latest.KbId
                UpdateId      = [string]$latest.ChosenUpdateId
                SourceCache   = 'dynamic-update'
                SourceRow     = $latest
                DiscoveryNote = ('{0} from dynamic-update: PatchMonth={1} ChosenTitle="{2}"' -f $duType, $latest.PatchMonth, $latest.ChosenTitle)
            })
        }
    }

    return @($records.ToArray())
}

# ============================================================
# b3 layer-1 acquisition: seed-only Microsoft Update Catalog resolver
#   (faithful port of the reference Resolve-CatalogPatchSet.ps1 production
#    half: OS-seed -> Learn LCU + Catalog Search/DownloadDialog -> raw lines.
#    Live fidelity confirmed by the captured resolve.json; oracle-verify half
#    NOT ported. Consumed by ConvertTo-ConfigLines / Resolve-CatalogPatchSetForOs.)
# ============================================================

# Constants
# ============================================================================
$script:CatUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$script:CatSearchUrl   = 'https://www.catalog.update.microsoft.com/Search.aspx'
$script:CatDownloadUrl = 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx'
$script:CatScopedUrl   = 'https://www.catalog.update.microsoft.com/ScopedViewInline.aspx'
$script:CatLearnUrl = 'https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info?accept=text/markdown'
$script:CatCache = (Join-Path $Script:WorkRoot 'cache\catalog-findings')
$script:CatOracleDir = $null
if (-not (Test-Path $script:CatCache)) { New-Item -ItemType Directory -Path $script:CatCache -Force | Out-Null }

# server Products token + Learn build-major + version token, per OS
$script:CatOsDef = @{
    '2016' = @{ products = 'Windows Server 2016';                    buildMajor = '14393'; verToken = $null }
    '2019' = @{ products = 'Windows Server 2019';                    buildMajor = '17763'; verToken = $null }
    '2022' = @{ products = 'Microsoft Server operating system-21H2'; buildMajor = '20348'; verToken = '21H2' }
    '2025' = @{ products = 'Microsoft Server Operating System-24H2'; buildMajor = '26100'; verToken = '24H2' }
}
$script:CatNetQuery = @{
    '2016' = 'Cumulative Update for .NET Framework Windows Server 2016'
    '2019' = 'Cumulative Update for .NET Framework Windows Server 2019'
    '2022' = 'Cumulative Update for .NET Framework Microsoft server operating system version 21H2 x64'
    '2025' = 'Cumulative Update for .NET Framework 4.8.1 Microsoft server operating system version 24H2 x64'
}
# 2022 SafeOS DU is out-of-SOAP-scope; digest is the Catalog/cab-verified value.
$script:CatKnownDuDigest = @{ '2022' = 'w+5dA+5b36FoRspRo6sXEHEmC5Q=' }

# ============================================================================

# ============================================================================
function Convert-HtmlToText {
    param([string]$s)
    if ($null -eq $s) { return '' }
    $s = [regex]::Replace($s, '<[^>]+>', ' ')
    $s = [System.Net.WebUtility]::HtmlDecode($s)
    $s = [regex]::Replace($s, '\s+', ' ')
    return $s.Trim()
}

function Get-CatalogText {
    param([string]$Url, [string]$Tag)
    $p = Join-Path $script:CatCache $Tag
    if (Test-Path $p) { return (Get-Content -LiteralPath $p -Raw) }
    $r = Invoke-WebRequest -Uri $Url -UserAgent $script:CatUA -UseBasicParsing -TimeoutSec 60
    $r.Content | Set-Content -LiteralPath $p -Encoding UTF8 -NoNewline
    Start-Sleep -Milliseconds 600
    return $r.Content
}

function Invoke-CatalogPost {
    param([string]$Url, [string]$Body, [string]$Tag)
    $p = Join-Path $script:CatCache $Tag
    if (Test-Path $p) { return (Get-Content -LiteralPath $p -Raw) }
    $r = Invoke-WebRequest -Uri $Url -Method Post -Body $Body `
        -ContentType 'application/x-www-form-urlencoded' `
        -UserAgent $script:CatUA -UseBasicParsing -TimeoutSec 60
    $r.Content | Set-Content -LiteralPath $p -Encoding UTF8 -NoNewline
    Start-Sleep -Milliseconds 600
    return $r.Content
}

function Get-HeadSize {
    param([string]$Url)
    $cache = Join-Path $script:CatCache 'sizes.json'
    $sizes = @{}
    if (Test-Path $cache) {
        try {
            $j = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json
            foreach ($pr in $j.PSObject.Properties) { $sizes[$pr.Name] = $pr.Value }
        } catch { $sizes = @{} }
    }
    if ($sizes.ContainsKey($Url)) { return $sizes[$Url] }
    $n = $null
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -UserAgent $script:CatUA -UseBasicParsing -TimeoutSec 30
        $cl = $r.Headers['Content-Length']
        if ($cl) { $n = [long]($cl | Select-Object -First 1) }
    } catch { $n = $null }
    $sizes[$Url] = $n
    ($sizes | ConvertTo-Json -Compress) | Set-Content -LiteralPath $cache -Encoding UTF8
    Start-Sleep -Milliseconds 300
    return $n
}

function Search-Catalog {
    param([string]$Query)
    $slug = [regex]::Replace($Query, '[^A-Za-z0-9]+', '_')
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60) }
    $tag = "search.$slug.html"
    $html = Get-CatalogText ($script:CatSearchUrl + '?q=' + [uri]::EscapeDataString($Query)) $tag
    $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $rx = [regex]::new("id=['""]($guid)_link['""][^>]*>(.*?)</a>", 'Singleline,IgnoreCase')
    $rows = @()
    foreach ($m in $rx.Matches($html)) {
        $uid = $m.Groups[1].Value
        $title = Convert-HtmlToText $m.Groups[2].Value
        $cells = @{}
        for ($col = 0; $col -le 7; $col++) {
            $crx = [regex]::new(('id="' + [regex]::Escape($uid) + '_C' + $col + '_R\d+"[^>]*>(.*?)</td>'), 'Singleline,IgnoreCase')
            $cm = $crx.Match($html)
            if ($cm.Success) { $cells[$col] = Convert-HtmlToText $cm.Groups[1].Value } else { $cells[$col] = '' }
        }
        $size = $null
        $smb = [regex]::Match($cells[6], '(\d{4,})')
        if ($smb.Success) { $size = [long]$smb.Groups[1].Value }
        $titleOut = if ($title) { $title } else { $cells[1] }
        $rows += [pscustomobject]@{
            uid = $uid; title = $titleOut; products = $cells[2]; classification = $cells[3]
            lastUpdated = $cells[4]; version = $cells[5]; sizeText = $cells[6]; sizeBytes = $size
        }
    }
    return , $rows
}

function Resolve-CatalogDownload {
    param([string]$Uid)
    $body = 'updateIDs=[{"size":0,"languages":"","uidInfo":"' + $Uid + '","updateID":"' + $Uid + '"}]' +
            '&updateIDsBlockedForImport=&wsusApiPresent=&contentImport=&sku=&serverName=&ssl=&portNumber=&version='
    $tag = "dl.$($Uid.Substring(0,8)).html"
    $html = Invoke-CatalogPost $script:CatDownloadUrl $body $tag
    $files = @{}
    $rx = [regex]::new("files\[(\d+)\]\.(\w+)\s*=\s*'([^']*)'")
    foreach ($m in $rx.Matches($html)) {
        $i = [int]$m.Groups[1].Value; $field = $m.Groups[2].Value; $val = $m.Groups[3].Value
        if (-not $files.ContainsKey($i)) { $files[$i] = @{} }
        $files[$i][$field] = $val
    }
    $out = @()
    foreach ($i in ($files.Keys | Sort-Object)) {
        $f = $files[$i]
        $out += [pscustomobject]@{
            idx = $i
            fileName = $(if ($f.ContainsKey('fileName')) { $f['fileName'] } else { '' })
            url      = $(if ($f.ContainsKey('url'))      { $f['url'] }      else { '' })
            digest   = $(if ($f.ContainsKey('digest'))   { $f['digest'] }   else { '' })
            sha256   = $(if ($f.ContainsKey('sha256'))   { $f['sha256'] }   else { '' })
            enTitle  = $(if ($f.ContainsKey('enTitle'))  { $f['enTitle'] }  else { '' })
        }
    }
    return , $out
}

function Get-CatalogScoped {
    param([string]$Uid)
    $tag = "scoped.$($Uid.Substring(0,8)).html"
    $html = Get-CatalogText ($script:CatScopedUrl + '?updateid=' + $Uid) $tag
    function _grab([string]$anchor) {
        $m = [regex]::Match($html, ('id="' + $anchor + '"[^>]*>(.*?)</div>'), 'Singleline,IgnoreCase')
        if ($m.Success) { return (Convert-HtmlToText $m.Groups[1].Value) } else { return $null }
    }
    $supersededBy = _grab 'supersededbyInfo'
    $isLatest = ($null -ne $supersededBy) -and ($supersededBy.ToLower().StartsWith('n/a'))
    $kbm = [regex]::Match($html, 'KB article numbers:\s*</span>\s*([0-9,\s]+)')
    [pscustomobject]@{
        uid = $Uid; is_latest = $isLatest; supersededByText = $supersededBy
        kb = $(if ($kbm.Success) { $kbm.Groups[1].Value.Trim() } else { $null })
    }
}

# ============================================================================
# SECTION 2 - per-OS resolvers: LCU / SSU / .NET / SafeOS DU
# ============================================================================
function Get-LearnLcuKbs { # psa-disable-line PSA6003 -- ported reference contract; returns a build->KB map (collection)
    $html = Get-CatalogText $script:CatLearnUrl 'learn.release-info.md'
    $best = @{}
    $rx = [regex]::new('\|\s*(\d{5})\.(\d+)\s*\|\s*\[KB(\d+)\]')
    foreach ($m in $rx.Matches($html)) {
        $major = $m.Groups[1].Value; $minor = [int]$m.Groups[2].Value; $kb = $m.Groups[3].Value
        if ((-not $best.ContainsKey($major)) -or ($minor -gt $best[$major].minor)) {
            $best[$major] = [pscustomobject]@{ build = "$major.$minor"; minor = $minor; kb = "KB$kb" }
        }
    }
    return $best
}

function Get-KbOf {
    param([string]$Text)
    $m = [regex]::Match(("$Text"), 'KB(\d+)', 'IgnoreCase')
    if ($m.Success) { return 'KB' + $m.Groups[1].Value } else { return $null }
}

function Get-X64Rows { # psa-disable-line PSA6003 -- ported reference contract; returns multiple rows (collection)
    param($Rows)
    $out = @($Rows | Where-Object { ($_.title.ToLower() -notmatch 'arm64') -and ($_.title.ToLower() -notmatch 'x86') })
    $pref = @($out | Where-Object { $_.title.ToLower() -match 'x64' })
    if ($pref.Count) { return , $pref } else { return , $out }
}

function Get-ServerRow {
    param($Rows, [string]$ProductsToken)
    $pt = $ProductsToken.ToLower()
    $cands = @($Rows | Where-Object { $_.products.ToLower().Contains($pt) })
    $x = @($cands | Where-Object { $_.title.ToLower().Contains('x64') -or $_.sizeText.ToLower().Contains('x64') })
    if ($x.Count) { return $x[0] }
    if ($cands.Count) { return $cands[0] }
    return $null
}

function Get-Newest {
    param($Rows)
    @($Rows) | Sort-Object @{ Expression = {
        $m = [regex]::Match($_.title, '\s*(\d{4})-(\d{2})')
        if ($m.Success) { [int]$m.Groups[1].Value * 100 + [int]$m.Groups[2].Value } else { 0 }
    } } -Descending | Select-Object -First 1
}

function Get-RuntimeCount {
    param([string]$Title)
    ([regex]::Matches($Title, '\b\d+\.\d+(\.\d+)?\b')).Count
}

function New-Line {
    param([string]$Kind, $Row, $Files, $InScope, [string]$Note)
    [pscustomobject]@{
        kind       = $Kind
        kb         = $(if ($Row) { Get-KbOf $Row.title } else { $null })
        catalogUid = $(if ($Row) { $Row.uid } else { $null })
        products   = $(if ($Row) { $Row.products } else { $null })
        title      = $(if ($Row) { $Row.title } else { $null })
        sizeBytes  = $(if ($Row) { $Row.sizeBytes } else { $null })
        files      = $(if ($Files) { @($Files) } else { @() })
        inScope    = $InScope
        note       = $Note
    }
}

function Resolve-Lcu {
    param([string]$OsKey)
    $info = $script:CatOsDef[$OsKey]
    $lcus = Get-LearnLcuKbs
    $bk = $lcus[$info.buildMajor]
    if (-not $bk) { return (New-Line 'LCU' $null @() $null 'LCU not discovered from Learn') }
    $rows = Search-Catalog $bk.kb
    $row = Get-ServerRow $rows $info.products
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $inScope = [pscustomobject]@{ build = $bk.build; files = @($files | ForEach-Object { $_.fileName }) }
    return (New-Line 'LCU' $row $files $inScope ("discovered via Learn (build $($bk.build))"))
}

function Resolve-Ssu2016 {
    $rows = Search-Catalog 'Servicing Stack Update Windows Server 2016'
    $cands = @($rows | Where-Object { $_.title.Contains('Servicing Stack Update') -and $_.products.Contains('Windows Server 2016') })
    $row = Get-Newest $cands
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $inScope = [pscustomobject]@{ standalone = $true; files = @($files | ForEach-Object { $_.fileName }) }
    return (New-Line 'SSU' $row $files $inScope '2016 only: standalone SSU row (apply before LCU)')
}

# in-box / in-scope = the .NET runtime whose payload ships in the base media (BLOCK 0.T).
# Picks the leaf for the OS's default/shipping runtime; 3.5 rides bundled in that leaf.
function Test-NetInScope {
    param([string]$OsKey, [string]$FileName)
    switch ($OsKey) {
        '2019' { return (($FileName -notmatch '-ndp48') -and ($FileName -notmatch '-ndp481')) }  # base 4.7.2 (+3.5)
        '2022' { return (($FileName -match '-ndp48') -and ($FileName -notmatch '-ndp481')) }      # 4.8 (+3.5)
        '2025' { return ($FileName -match '-ndp481') }                                            # 4.8.1 (+3.5)
    }
    return $false
}

function Resolve-Net {
    param([string]$OsKey)
    $info = $script:CatOsDef[$OsKey]
    if ($OsKey -eq '2016') {
        return (New-Line '.NET' $null @() $null ('2016: in-box .NET payload (3.5 + 4.6.2/4.7.x) is serviced INSIDE the LCU; ' +
                'the only standalone WS2016 .NET CU is .NET 4.8 (add-on, NOT in base media) -> out-of-scope. No leaf to fetch.'))
    }
    $q = $script:CatNetQuery[$OsKey]
    $rows = Search-Catalog $q
    $rows = @($rows | Where-Object { $_.products.ToLower().Contains($info.products.ToLower()) })
    $rows = Get-X64Rows $rows
    $nm = Get-Newest $rows
    if (-not $nm) { return (New-Line '.NET' $null @() $null 'no .NET row matched OS token') }
    $month = [regex]::Match($nm.title, '\s*(\d{4}-\d{2})').Groups[1].Value
    $variants = @($rows | Where-Object { $_.title.TrimStart().StartsWith($month) })
    $row = $variants | Sort-Object @{ Expression = { Get-RuntimeCount $_.title } } -Descending | Select-Object -First 1
    $files = Resolve-CatalogDownload $row.uid
    $x64 = @($files | Where-Object { $_.fileName -match '-x64' })
    $sel = @($x64 | Where-Object { Test-NetInScope $OsKey $_.fileName })
    $inScope = [pscustomobject]@{
        inScopeFiles = @($sel | ForEach-Object { $_.fileName })
        inScopeKb    = @($sel | ForEach-Object { Get-KbOf $_.fileName })
    }
    return (New-Line '.NET' $row $files $inScope ("superset rollup; in-scope leaf = $OsKey in-media default .NET runtime (BLOCK 0.T; bundles 3.5)"))
}

function Resolve-SafeOsDu {
    param([string]$OsKey)
    $info = $script:CatOsDef[$OsKey]
    if ($OsKey -eq '2016' -or $OsKey -eq '2019') {
        return (New-Line 'SafeOSDU' $null @() $null "${OsKey}: no monthly SafeOS DU line (matches oracle)")
    }
    $tok = $info.verToken
    $q = if ($OsKey -eq '2022') { 'Dynamic Update Microsoft server operating system version 21H2' }
         else { 'Safe OS Dynamic Update for Microsoft server operating system version 24H2 x64' }
    $rows = Search-Catalog $q
    $cands = @($rows | Where-Object {
        $_.products.Contains('Safe OS Dynamic Update') -and
        $_.title.Contains($tok) -and
        $_.title.ToLower().Contains('server operating system') -and
        ($_.title.ToLower() -notmatch 'arm64')
    })
    $row = Get-Newest $cands
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $x64 = @($files | Where-Object { $_.fileName.Contains('x64') -and $_.fileName.EndsWith('.cab') })
    $inScope = [pscustomobject]@{ files = @($x64 | ForEach-Object { $_.fileName }) }
    return (New-Line 'SafeOSDU' $row $files $inScope "Products has 'Safe OS Dynamic Update' + title version token")
}

function Resolve-SetupDu { # psa-disable-line PSA6003 -- 'Du' is the dynamic-update abbreviation, not a plural; mirrors Resolve-SafeOsDu
    # Setup Dynamic Update (b3 acquisition, sibling of Resolve-SafeOsDu). Setup DU
    # updates the media's setup/installer binaries (the sources\ tree, applied by
    # P09 via expand.exe overlay), NOT a WIM. It is published only for the
    # UUP-checkpoint OS (Server 2025 / 24H2); the separate-ssu / embedded-ssu /
    # embedded-ssu-du models FORBID it (Test-PatchModelConsistency Forbid list), so
    # only the 2025 branch of Resolve-Os requests it. The discriminator mirrors the
    # SafeOS resolver: it differs only in the Catalog Products string
    # ('Setup Dynamic Update' vs 'Safe OS Dynamic Update'), per the legacy
    # @('DynamicUpdate.Setup','DynamicUpdate.SafeOs') discovery pairing.
    param([string]$OsKey)
    $info = $script:CatOsDef[$OsKey]
    if ($OsKey -ne '2025') {
        return (New-Line 'SetupDU' $null @() $null "${OsKey}: no Setup DU line (Forbid; only uup-checkpoint carries SetupDU)")
    }
    $tok = $info.verToken
    $q = 'Setup Dynamic Update for Microsoft server operating system version 24H2 x64'
    $rows = Search-Catalog $q
    $cands = @($rows | Where-Object {
        $_.products.Contains('Setup Dynamic Update') -and
        $_.title.Contains($tok) -and
        $_.title.ToLower().Contains('server operating system') -and
        ($_.title.ToLower() -notmatch 'arm64')
    })
    $row = Get-Newest $cands
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $x64 = @($files | Where-Object { $_.fileName.Contains('x64') -and $_.fileName.EndsWith('.cab') })
    $inScope = [pscustomobject]@{ files = @($x64 | ForEach-Object { $_.fileName }) }
    return (New-Line 'SetupDU' $row $files $inScope "Products has 'Setup Dynamic Update' + title version token")
}

function Resolve-Os { # psa-disable-line PSA6003 -- noun is 'OS' (operating system), not a plural; ported reference contract
    param([string]$OsKey)
    switch ($OsKey) {
        '2016' { return [pscustomobject]@{ os = 'Server2016'; lines = @((Resolve-Lcu '2016'), (Resolve-Ssu2016), (Resolve-Net '2016'), (Resolve-SafeOsDu '2016')) } }
        '2019' { return [pscustomobject]@{ os = 'Server2019'; lines = @((Resolve-Lcu '2019'), (New-Line 'SSU' $null @() $null 'embedded in LCU (no standalone row)'), (Resolve-Net '2019'), (Resolve-SafeOsDu '2019')) } }
        '2022' { return [pscustomobject]@{ os = 'Server2022'; lines = @((Resolve-Lcu '2022'), (New-Line 'SSU' $null @() $null 'embedded in LCU (no standalone row)'), (Resolve-Net '2022'), (Resolve-SafeOsDu '2022')) } }
        '2025' {
            $lcu = Resolve-Lcu '2025'
            $lcuKb = if ($lcu.kb) { $lcu.kb.ToLower() } else { '' }
            $baseline = @($lcu.files | Where-Object {
                $_.fileName.ToLower().EndsWith('.msu') -and (($lcuKb -eq '') -or (-not $_.fileName.ToLower().Contains($lcuKb)))
            })
            $blKb = if ($baseline.Count) { Get-KbOf $baseline[0].fileName } else { $null }
            $ssu = New-Line 'SSU' $null $baseline ([pscustomobject]@{ files = @($baseline | ForEach-Object { $_.fileName }) }) `
                '2025: checkpoint SSU carried by the co-served GA baseline (the non-LCU .msu in the 2-file set)'
            $ssu.kb = $blKb
            return [pscustomobject]@{ os = 'Server2025'; lines = @($lcu, $ssu, (Resolve-Net '2025'), (Resolve-SafeOsDu '2025'), (Resolve-SetupDu '2025')) }
        }
    }
}

# ============================================================================
# SECTION 3 - .NET CU full inventory (collect-don't-drop)
# ============================================================================

# ============================================================
# b3 Catalog patch-set resolver pipeline (data-source migration)
#   layer 1 transform : ConvertTo-ConfigLines (raw acquisition -> Lines[])
#   layer 2 verify     : Get-ReleaseInfoExpectedLcu + Compare-CatalogLcuAgainstReleaseInfo
#   layer 3 structure  : Test-PatchModelConsistency (P06 runtime mirror of the schema)
#   orchestrator       : Resolve-CatalogPatchSetForOs (L1 -> transform -> L2 -> L3)
# Authored + offline-validated against captured real fixtures (see SPEC B.4/B.19).
# ============================================================

function Test-PatchModelConsistency {
    <#
    .SYNOPSIS
        P06 runtime consistency check: assert a per-OS resolved Lines[] set
        matches the invariants its PatchModel declares (the runtime mirror of
        config.schema.json's PatchModel allOf discriminated union, SPEC B.19).
    .DESCRIPTION
        Anti-"forced-uniform" contract (D0 design section 5): each PatchModel
        branch ASSERTS the Kinds it expects and FORBIDS those it must not carry,
        so a resolver anomaly surfaces as a typed error that names the OS, the
        PatchModel, and the violated invariant -- never silently normalised.
        Pure function (no I/O); unit-tested offline against fixture Lines[].
    .OUTPUTS
        pscustomobject { OsKey; PatchModel; IsConsistent[bool]; Errors[string[]] }
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$OsKey,
        [Parameter(Mandatory)][string]$PatchModel,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Lines
    )
    $rules = @{
        'separate-ssu'    = @{ Require = @('SSU','LCU');                    Forbid = @('DotNet','SafeOSDU','SetupDU') }
        'embedded-ssu'    = @{ Require = @('LCU','DotNet');                 Forbid = @('SSU','SafeOSDU','SetupDU') }
        'embedded-ssu-du' = @{ Require = @('LCU','DotNet','SafeOSDU');      Forbid = @('SSU','SetupDU') }
        'uup-checkpoint'  = @{ Require = @('LCU','SSU','DotNet','SafeOSDU'); Forbid = @() }
    }
    if (-not $rules.ContainsKey($PatchModel)) {
        throw "P06 consistency: unknown PatchModel '$PatchModel' for $OsKey (expected: $(($rules.Keys | Sort-Object) -join ', '))."
    }
    $rule    = $rules[$PatchModel]
    $present = @($Lines | ForEach-Object { $_.Kind } | Sort-Object -Unique)
    $errors  = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $rule.Require) {
        if ($present -notcontains $k) { $errors.Add("missing required Kind '$k'") }
    }
    foreach ($k in $rule.Forbid) {
        if ($present -contains $k) { $errors.Add("forbidden Kind '$k' present") }
    }
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace([string]$Lines[$i].Digest)) {
            $errors.Add("Lines[$i] (Kind '$($Lines[$i].Kind)') has empty Digest (integrity key required)")
        }
    }
    return [pscustomobject]@{
        OsKey        = $OsKey
        PatchModel   = $PatchModel
        IsConsistent = ($errors.Count -eq 0)
        Errors       = $errors.ToArray()
    }
}

function ConvertTo-ConfigLines { # psa-disable-line PSA6003 -- returns the Lines[] collection; plural noun intentional
    <#
    .SYNOPSIS
        b3 layer-1 transform: turn the seed-only Catalog resolver's raw per-OS output
        (kind/kb/catalogUid/title/products/files[]/inScope/note) into the config
        PatchBaseline.Lines[] (one Line per in-scope file, with Kind/Digest/ApplyOrder),
        applying the per-PatchModel selections:
          (1) drop placeholder "none" lines (no files);
          (2) 2025 LCU 2-file split -> keep only the LCU-proper file (the baseline .msu is
              the separate SSU line);
          (3) .NET in-scope leaf selection (inScope.inScopeFiles);
          (4) 2016 .NET line is a placeholder -> dropped by (1) (the D0 "remove 2016 .NET"
              correction); SetupDU is added by the resolver extension upstream, not here.
        Pure function; offline-tested against the captured resolve.json.
    .OUTPUTS
        System.Collections.Generic.List[object]  (the Lines[] for one OS)
    #>
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][object]$OsResolved,   # one OS object: { os; lines[] }
        [Parameter(Mandatory)][string]$PatchModel
    )
    $kindMap  = @{ 'LCU'='LCU'; 'SSU'='SSU'; '.NET'='DotNet'; 'SafeOSDU'='SafeOSDU'; 'SetupDU'='SetupDU' }
    $applyMap = @{
        'separate-ssu'    = @{ 'SSU'=1; 'LCU'=2 }
        'embedded-ssu'    = @{ 'LCU'=1; 'DotNet'=2 }
        'embedded-ssu-du' = @{ 'LCU'=1; 'DotNet'=2; 'SafeOSDU'=3 }
        'uup-checkpoint'  = @{ 'SSU'=1; 'LCU'=2; 'DotNet'=3; 'SafeOSDU'=4; 'SetupDU'=5 }
    }
    if (-not $applyMap.ContainsKey($PatchModel)) {
        throw "ConvertTo-ConfigLines: unknown PatchModel '$PatchModel' for $($OsResolved.os)."
    }
    $orders = $applyMap[$PatchModel]
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($L in $OsResolved.lines) {
        if (-not $L.files -or @($L.files).Count -eq 0) { continue }          # (1)
        $kind  = $kindMap[$L.kind]
        $insc  = $L.inScope
        $files = @($L.files)
        $inScopeFiles = if ($insc -and $insc.PSObject.Properties.Name -contains 'inScopeFiles') { @($insc.inScopeFiles) } else { @() }
        if ($inScopeFiles.Count -gt 0) {                                     # (3) .NET leaf
            $files = @($files | Where-Object { $inScopeFiles -contains $_.fileName })
        }
        elseif ($OsResolved.os -eq 'Server2025' -and $L.kind -eq 'LCU') {    # (2) 2025 LCU split
            $lcuTok = ([string]$L.kb).ToLower().Replace('kb','')
            $files = @($files | Where-Object { $_.fileName.ToLower().Contains($lcuTok) })
        }
        $order = $orders[$kind]
        foreach ($f in $files) {
            $out.Add([pscustomobject]@{
                Kind        = $kind
                KbId        = $L.kb
                UpdateId    = $L.catalogUid
                Title       = $L.title
                Products    = $L.products
                Classification = $null
                FileName    = $f.fileName
                DownloadUrl = $f.url
                Digest      = $f.digest
                Sha256      = $(if ($f.PSObject.Properties.Name -contains 'sha256') { $f.sha256 } else { '' })
                SizeBytes   = $null      # per-file HEAD pass refinement
                ApplyOrder  = $order
                InScope     = $insc
                Note        = $L.note
            })
        }
    }
    $sorted = @($out | Sort-Object { if ($null -ne $_.ApplyOrder) { $_.ApplyOrder } else { 99 } })
    return ,$sorted
}

function Get-ReleaseInfoExpectedLcu {
    <#
    .SYNOPSIS
        Verification oracle (b3 hybrid, layer 2): the EXPECTED LCU (KbId + post-update
        build) for an OS + month, read from the Catalog-EXTERNAL release-info cache
        (data/cache-release-info.json MonthlyReleases). This is the human/AI-readable
        published servicing calendar used to VERIFY that the seed-only Catalog acquisition
        (layer 1) found the right KB -- the two sources mutually complement.
    .OUTPUTS
        pscustomobject { OsShortName; ExpectedLcuKb; BuildAfterUpdate; AvailabilityDate } or $null
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$ReleaseInfo,
        [Parameter(Mandatory)][string]$OsShortName,
        [Parameter(Mandatory)][int]$Year,
        [Parameter(Mandatory)][int]$Month
    )
    $rows = @($ReleaseInfo.MonthlyReleases | Where-Object {
        $_.OsShortName -eq $OsShortName -and
        [int]$_.UpdateTypeYear -eq $Year -and
        [int]$_.UpdateTypeMonth -eq $Month
    })
    if ($rows.Count -eq 0) { return $null }
    # Prefer the GA row (UpdateTypeLetter 'B') over a later preview (C/D...) of the same month.
    $row = $rows | Sort-Object UpdateTypeLetter | Select-Object -First 1
    return [pscustomobject]@{
        OsShortName      = $OsShortName
        ExpectedLcuKb    = $row.KbId
        BuildAfterUpdate = $row.BuildAfterUpdate
        AvailabilityDate = $row.AvailabilityDate
    }
}

function Compare-CatalogLcuAgainstReleaseInfo {
    <#
    .SYNOPSIS
        Reconciliation (b3 hybrid, layer 2): cross-check the Catalog-resolved LCU KB (layer 1
        acquisition) against the release-info oracle. Because seed-only acquisition derives the
        KB live from a minimal seed, this independent check confirms the right KB was found.
    .OUTPUTS
        pscustomobject { CatalogLcuKb; ExpectedLcuKb; Verdict; IsConfirmed; BuildNote; Errors[] }
        Verdict in: confirmed | catalog-only | releaseinfo-missing
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$CatalogLcuKb,
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$CatalogBuild,
        [Parameter(Mandatory)][AllowNull()][object]$Expected
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $buildNote = $null
    if ($null -eq $Expected) {
        if ($CatalogLcuKb) { $verdict = 'catalog-only'; $errors.Add("release-info has no LCU row for this OS/month; Catalog $CatalogLcuKb is UNVERIFIED") }
        else { $verdict = 'releaseinfo-missing'; $errors.Add("neither release-info nor Catalog produced an LCU") }
    }
    elseif (-not $CatalogLcuKb) {
        $verdict = 'releaseinfo-missing'; $errors.Add("release-info expects $($Expected.ExpectedLcuKb) but Catalog resolved no LCU")
    }
    elseif ($CatalogLcuKb -eq $Expected.ExpectedLcuKb) {
        $verdict = 'confirmed'
        if ($CatalogBuild -and $Expected.BuildAfterUpdate) {
            if ($CatalogBuild -eq $Expected.BuildAfterUpdate) { $buildNote = "build MATCH ($CatalogBuild)" }
            else { $buildNote = "build DIFFERS: catalog=$CatalogBuild releaseinfo=$($Expected.BuildAfterUpdate)" }
        }
    }
    else {
        $verdict = 'catalog-only'
        $errors.Add("Catalog LCU $CatalogLcuKb != release-info expected $($Expected.ExpectedLcuKb)")
    }
    return [pscustomobject]@{
        CatalogLcuKb  = $CatalogLcuKb
        ExpectedLcuKb = $(if ($Expected) { $Expected.ExpectedLcuKb } else { $null })
        Verdict       = $verdict
        IsConfirmed   = ($verdict -eq 'confirmed')
        BuildNote     = $buildNote
        Errors        = $errors.ToArray()
    }
}

function Resolve-CatalogPatchSetForOs { # psa-disable-line PSA6003 -- noun ends 'OS' (operating system); b3 orchestrator
    <#
    .SYNOPSIS
        b3 orchestrator: produce the validated PatchBaseline.Lines[] for one OS by chaining
        layer 1 (seed-only Catalog acquisition) -> transform -> layer 2 (release-info
        reconciliation) -> layer 3 (PatchModel consistency). Returns the Lines plus both
        verdicts so the caller (A01) can apply policy. The -RawResolved parameter lets the
        acquisition be injected (live Resolve-Os in production; the captured fixture in tests).
    .OUTPUTS
        pscustomobject { OsKey; PatchModel; Lines; Reconcile; Consistency; IsValid; Errors[] }
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$OsShortName,
        [Parameter(Mandatory)][string]$PatchModel,
        [Parameter(Mandatory)][object]$RawResolved,    # layer-1 output { os; lines[] }
        [Parameter(Mandatory)][object]$ReleaseInfo,     # layer-2 oracle (cache-release-info.json)
        [Parameter(Mandatory)][int]$Year,
        [Parameter(Mandatory)][int]$Month
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    # transform (layer 1 shaping)
    $lines = ConvertTo-ConfigLines -OsResolved $RawResolved -PatchModel $PatchModel
    # layer 2: reconcile the LCU anchor against the Catalog-external release-info oracle
    $lcu = @($lines | Where-Object { $_.Kind -eq 'LCU' }) | Select-Object -First 1
    $exp = Get-ReleaseInfoExpectedLcu -ReleaseInfo $ReleaseInfo -OsShortName $OsShortName -Year $Year -Month $Month
    $recon = Compare-CatalogLcuAgainstReleaseInfo -CatalogLcuKb $lcu.KbId -CatalogBuild $lcu.InScope.build -Expected $exp
    foreach ($e in $recon.Errors) { $errors.Add("reconcile: $e") }
    # layer 3: PatchModel structural consistency
    $p06 = Test-PatchModelConsistency -OsKey $OsShortName -PatchModel $PatchModel -Lines @($lines)
    foreach ($e in $p06.Errors) { $errors.Add("consistency: $e") }
    # policy: structurally consistent AND reconciliation not a hard failure.
    #   confirmed      -> verified OK
    #   catalog-only   -> acquired but release-info did not confirm (allow w/ warning; surfaced)
    #   releaseinfo-missing -> hard fail (expected a KB, acquisition produced none)
    $reconOk = ($recon.Verdict -ne 'releaseinfo-missing')
    return [pscustomobject]@{
        OsKey       = $OsShortName
        PatchModel  = $PatchModel
        Lines       = @($lines)
        Reconcile   = $recon
        Consistency = $p06
        IsValid     = ($p06.IsConsistent -and $reconOk)
        Errors      = $errors.ToArray()
    }
}


function Invoke-CatalogPatchSetRefresh {
    <#
    .SYNOPSIS
        Refresher-convention producer (b3 data-source migration): bridges A01's
        -OsVersion/-PatchMonth Refresher call to layer-1 seed-only Catalog acquisition
        (Resolve-Os) + the b3 orchestrator (acquire -> transform -> release-info verify
        -> PatchModel consistency). Returns the resolved PatchBaseline.Lines[].
    #>
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$OsVersion,
        [string]$OsLanguage = 'neutral',
        [Parameter(Mandatory)][string]$PatchMonth,
        [int]$MaxRetries = 3
    )
    $osKeyMap = @{ 'Server2016' = '2016'; 'Server2019' = '2019'; 'Server2022' = '2022'; 'Server2025' = '2025' }
    $modelMap = @{ 'Server2016' = 'separate-ssu'; 'Server2019' = 'embedded-ssu'; 'Server2022' = 'embedded-ssu-du'; 'Server2025' = 'uup-checkpoint' }
    if (-not $osKeyMap.ContainsKey($OsVersion)) { throw ("Invoke-CatalogPatchSetRefresh: unknown OsVersion '{0}'." -f $OsVersion) }
    $osk = $osKeyMap[$OsVersion]; $model = $modelMap[$OsVersion]
    $parts = $PatchMonth.Split('-'); $year = [int]$parts[0]; $month = [int]$parts[1]
    $raw     = Resolve-Os -OsKey $osk            # layer 1: live seed-only Catalog acquisition
    $relInfo = Get-ReleaseInfoCache              # layer 2: Catalog-external release-info oracle
    $res = Resolve-CatalogPatchSetForOs -OsShortName $OsVersion -PatchModel $model `
        -RawResolved $raw -ReleaseInfo $relInfo -Year $year -Month $month
    if (-not $res.IsValid) {
        throw ("Invoke-CatalogPatchSetRefresh: {0} produced an invalid patch set: {1}" -f $OsVersion, ($res.Errors -join '; '))
    }
    if ($res.Reconcile.Verdict -ne 'confirmed') {
        Write-Caution ("{0}: Catalog LCU not confirmed by release-info (verdict={1}). {2}" -f $OsVersion, $res.Reconcile.Verdict, ($res.Reconcile.Errors -join '; '))
    }
    return @($res.Lines)
}

function Resolve-PatchSetFromReleaseInfo {
    <#
    .SYNOPSIS
        Orchestrator: for a given OS / month / language, look up the
        canonical patch set (LCU + embedded SSU + .NET CU per runtime
        + DU.Setup + DU.SafeOs) by reading the release-info, .NET CU
        and Dynamic Update caches, then resolves each discovered KB
        or UpdateId to file URLs via the Microsoft Update Catalog.
    .DESCRIPTION
        This function is the r07.0+ replacement for the r05.1-era
        `Resolve-PatchSetFromCatalog`. The old function performed
        Title-string discovery against the Catalog (one Search.aspx
        query per Type with hand-crafted templates); the new one
        defers discovery to the Step 2a cache layer and uses the
        Catalog only as a URL resolver. SPEC.md documents the
        migration; it also covers the per-OS .NET CU multiplicity
        and the LCU + SSU bundle handling that this function
        inherits unchanged.

        On the combined model the monthly LCU embeds the SSU; on the
        separate model some OSes (e.g. Server 2016 today) still publish a *standalone*
        same-month Servicing Stack Update under a separate Catalog
        UpdateId. After emitting the per-UpdateId records, this
        function searches the Catalog for a same-month "Servicing
        Stack Update" of the OS: when one is found it emits a Type=SSU
        entry and flips the matching LCU to IsCombined=$false; when
        none is found the LCU stays IsCombined=$true (combined
        convention). When an LCU's Catalog UpdateId itself carries
        multiple .msu files, the per-file
        Convert-CatalogPatchToBaselineEntry path still classifies them
        via filename heuristic (Get-PatchType).

        Per SPEC.md, the Catalog narrow-filter consumes
        `Test-CatalogTitleMatch` and the per-OS Config-driven
        `CatalogTitleTokens`, so the URL resolver tolerates
        Microsoft re-naming the Catalog title format by Config
        edit alone.

        Returns an array of fully-populated PatchBaseline entries
        (same shape as the old Resolve-PatchSetFromCatalog return).
        The LCU's IsCombined flag defaults to $true and is set to
        $false when a standalone same-month SSU is discovered for it.
    .EXAMPLE
        Resolve-PatchSetFromReleaseInfo `
            -OsVersion Server2025 -OsLanguage en-us -PatchMonth '2026-05'
    #>
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)] [string]$OsLanguage,
        [Parameter(Mandatory)] [string]$PatchMonth,
        [int]$MaxRetries = 3,
        [string]$DataDir = ''
    )

    Write-Step ('Resolving patch set (release-info path): OS={0} Lang={1} Month={2}' -f $OsVersion, $OsLanguage, $PatchMonth)

    $discoveries = @(Get-PatchSetFromReleaseInfoDiscovery -OsVersion $OsVersion -PatchMonth $PatchMonth -DataDir $DataDir)
    if ($discoveries.Count -eq 0) {
        Write-Caution ('Discovery returned zero records for OS={0} Month={1}. Ensure data/cache-release-info.json, data/cache-dotnet-cu.json and data/cache-dynamicupdate-{0}.json have been populated by the refresh action.' -f $OsVersion, $PatchMonth)
        return @()
    }
    Write-Step ('  Discovered {0} record(s): {1}' -f $discoveries.Count, (($discoveries | ForEach-Object { $_.Type }) -join ', '))

    $resolved = New-Object 'System.Collections.Generic.List[pscustomobject]'
    $supersedenceExclusions = New-Object 'System.Collections.Generic.List[object]'

    foreach ($rec in $discoveries) {
        $isDu  = ($rec.Type -eq 'DynamicUpdate.Setup' -or $rec.Type -eq 'DynamicUpdate.SafeOs')
        $bestUid = ''
        $bestTitle = ''
        # ---- Resolve UpdateId ----
        if ($isDu) {
            # DU records carry the UpdateId from the cache directly.
            $bestUid   = [string]$rec.UpdateId
            $bestTitle = [string]$rec.SourceRow.ChosenTitle
        } else {
            # LCU / .NET CU: KB-only Catalog search, then narrow with the Config-driven helper.
            $hits = $null
            try {
                $hits = Get-UpdateIdFromCatalog -KbId $rec.KbId -MaxRetries $MaxRetries
            } catch {
                Write-Caution ('Catalog KB search failed for {0} {1}: {2}' -f $rec.Type, $rec.KbId, $_.Exception.Message)
                continue
            }
            if (-not $hits -or $hits.Count -eq 0) {
                Write-Caution ('Catalog returned zero hits for {0} {1}.' -f $rec.Type, $rec.KbId)
                continue
            }
            $narrowed = @($hits | Where-Object {
                Test-CatalogTitleMatch -OsVersion $OsVersion -Title ([string]$_.Title)
            })
            if ($narrowed.Count -eq 0) {
                Write-Caution ('Catalog narrow filter rejected all {0} hit(s) for {1} {2}. Check CatalogTitleTokens in data/config-{3}.json.' -f $hits.Count, $rec.Type, $rec.KbId, $OsVersion)
                continue
            }
            $narrowedNoPreview = @($narrowed | Where-Object { [string]$_.Title -notmatch '(?i)preview' })
            if ($narrowedNoPreview.Count -eq 0) { $narrowedNoPreview = $narrowed }
            $bestHit   = $narrowedNoPreview[0]
            $bestUid   = [string]$bestHit.UpdateId
            $bestTitle = [string]$bestHit.Title
        }
        if ([string]::IsNullOrEmpty($bestUid)) {
            Write-Caution ('No UpdateId resolved for {0} {1}.' -f $rec.Type, $rec.KbId)
            continue
        }

        # ---- Resolve download links ----
        $links = $null
        try {
            $links = Get-DownloadLinkFromCatalog -UpdateId $bestUid -MaxRetries $MaxRetries
        } catch {
            Write-Caution ('DownloadDialog failed for {0} UpdateId {1}: {2}' -f $rec.Type, $bestUid, $_.Exception.Message)
            continue
        }
        if (-not $links -or $links.Count -eq 0) {
            Write-Caution ('No download link for {0} UpdateId {1}.' -f $rec.Type, $bestUid)
            continue
        }

        # ---- File selection per Type ----
        if ($rec.Type -eq 'DotNet.Runtime') {
            # Umbrella .NET CU UpdateIds carry multiple .msu files; emit each.
            $primaries = @(Select-AllCanonicalPatchFiles -Links $links -PatchType $rec.Type -Architecture 'x64')
            $passKnownType = $true
        }
        elseif ($rec.Type -eq 'LCU') {
            # Combined-LCU convention (see SPEC.md): take every canonical file
            # (LCU + bundled SSU when present) and let the per-file filename
            # heuristic in Convert-CatalogPatchToBaselineEntry classify Type.
            $primaries = @(Select-AllCanonicalPatchFiles -Links $links -PatchType $rec.Type -Architecture 'x64')
            $passKnownType = $false
        }
        else {
            # SSU (shouldn't reach here -- not discovered), DU.Setup, DU.SafeOs:
            # single canonical file.
            $single = Select-CanonicalPatchFile -Links $links -PatchType $rec.Type -Architecture 'x64'
            $primaries = @()
            if ($null -ne $single) { $primaries = @($single) }
            $passKnownType = $true
        }
        if ($primaries.Count -eq 0) {
            $names = (($links | ForEach-Object { $_.FileName }) -join ', ')
            Write-Caution ('No canonical file for {0} UpdateId {1} (only Express/Delta/PSF?). Files: {2}' -f $rec.Type, $bestUid, $names)
            continue
        }

        # ---- Supersedence (best-effort, shared across this UpdateId's files) ----
        $supers = $null
        try {
            $supers = Get-SupersedenceFromCatalog -UpdateId $bestUid -MaxRetries $MaxRetries
        } catch {
            $supers = $null
        }
        $supersList = if ($null -ne $supers -and $supers.SupersedesLatest) { @($supers.SupersedesLatest) } else { @() }

        foreach ($primary in $primaries) {
            $kbFromFile = Get-KbIdFromPatchFileName -FileName $primary.FileName
            $entryKbId  = if (-not [string]::IsNullOrEmpty($kbFromFile)) { $kbFromFile } else { $rec.KbId }
            $knownArg   = if ($passKnownType) { $rec.Type } else { '' }

            $entry = Convert-CatalogPatchToBaselineEntry `
                -KbId $entryKbId `
                -Title $bestTitle `
                -UpdateId $bestUid `
                -DownloadUrl $primary.Url `
                -FileName $primary.FileName `
                -Sha256 '' `
                -Supersedes $supersList `
                -ApplicableArchitecture 'x64' `
                -ApplicableLanguages @('neutral') `
                -KnownType $knownArg

            if ($entry.Type -eq 'LCU') {
                # Combined-month convention; see SPEC.md.
                $entry | Add-Member -NotePropertyName 'IsCombined' -NotePropertyValue $true -Force
            } else {
                $entry | Add-Member -NotePropertyName 'IsCombined' -NotePropertyValue $false -Force
            }
            $entry | Add-Member -NotePropertyName 'Variant' -NotePropertyValue 'Full' -Force

            $resolved.Add($entry) | Out-Null
        }
    }

    # ----- Standalone servicing-stack update (SSU) discovery -----
    # Some LCUs name a required servicing-stack version that ships as a
    # *standalone* SSU package under a DIFFERENT Catalog UpdateId than the LCU,
    # so the per-UpdateId file walk above never surfaces it. For each resolved
    # LCU, search the Catalog for the same-month "Servicing Stack Update" of this
    # OS; the search result is itself the discriminator:
    #   * found  (e.g. Server 2016 KB5088064) -> emit a Type=SSU NeutralPatch and
    #     flip the LCU to IsCombined=$false (a standalone SSU now accompanies it);
    #   * none   (e.g. Server 2019 post-2021, whose low SS floor is met by the
    #     combined/embedded stack, and combined OSes 2022/2025) -> leave the LCU
    #     IsCombined=$true with no standalone SSU.
    # The same-month + OS-narrowed title filter keeps this precise; the SS-version
    # readiness gate and the downstream DISM apply remain the runtime safety net.
    if (@($resolved | Where-Object { $_.Type -eq 'SSU' }).Count -eq 0) {
        $osTokens = @(Get-CatalogTitleTokenList -OsVersion $OsVersion)
        $osSearchToken = if ($osTokens.Count -gt 0) { [string]$osTokens[0] } else { $OsVersion }
        foreach ($lcu in @($resolved | Where-Object { $_.Type -eq 'LCU' })) {
            $ssuQuery = '{0} Servicing Stack Update {1}' -f $PatchMonth, $osSearchToken
            $ssuHits = $null
            try {
                $ssuHits = Get-UpdateIdFromCatalog -KbId $ssuQuery -MaxRetries $MaxRetries
            } catch {
                Write-Caution ('Standalone SSU search failed for {0} {1}: {2}' -f $OsVersion, $PatchMonth, $_.Exception.Message)
                $ssuHits = $null
            }
            $ssuHits = @($ssuHits | Where-Object {
                (Test-CatalogTitleMatch -OsVersion $OsVersion -Title ([string]$_.Title)) -and
                ([string]$_.Title -match '(?i)servicing stack update') -and
                ([string]$_.Title -notmatch '(?i)preview')
            })
            if ($ssuHits.Count -eq 0) {
                Write-Step ('  No standalone SSU published for {0} {1} (separate-model LCU {2}); leaving IsCombined=$true.' -f $OsVersion, $PatchMonth, $lcu.KbId)
                continue
            }
            $ssuHit = $ssuHits[0]
            $ssuUid = [string]$ssuHit.UpdateId
            $ssuLinks = $null
            try {
                $ssuLinks = Get-DownloadLinkFromCatalog -UpdateId $ssuUid -MaxRetries $MaxRetries
            } catch {
                Write-Caution ('Standalone SSU {0}: DownloadDialog failed: {1}' -f $ssuUid, $_.Exception.Message)
                continue
            }
            if (-not $ssuLinks -or $ssuLinks.Count -eq 0) {
                Write-Caution ('Standalone SSU {0}: no download link; leaving LCU {1} IsCombined=$true.' -f $ssuUid, $lcu.KbId)
                continue
            }
            $ssuFile = Select-CanonicalPatchFile -Links $ssuLinks -PatchType 'SSU' -Architecture 'x64'
            if ($null -eq $ssuFile) {
                Write-Caution ('Standalone SSU {0}: no canonical file; leaving LCU {1} IsCombined=$true.' -f $ssuUid, $lcu.KbId)
                continue
            }
            $ssuKbId = Get-KbIdFromPatchFileName -FileName $ssuFile.FileName
            if ([string]::IsNullOrEmpty($ssuKbId)) {
                if ([string]$ssuHit.Title -match '(?i)\b(KB\d{6,})\b') { $ssuKbId = $matches[1] }
            }
            $ssuSupers = $null
            try { $ssuSupers = Get-SupersedenceFromCatalog -UpdateId $ssuUid -MaxRetries $MaxRetries } catch { $ssuSupers = $null }
            $ssuSupersList = if ($null -ne $ssuSupers -and $ssuSupers.SupersedesLatest) { @($ssuSupers.SupersedesLatest) } else { @() }
            $ssuEntry = Convert-CatalogPatchToBaselineEntry `
                -KbId $ssuKbId `
                -Title ([string]$ssuHit.Title) `
                -UpdateId $ssuUid `
                -DownloadUrl $ssuFile.Url `
                -FileName $ssuFile.FileName `
                -Sha256 '' `
                -Supersedes $ssuSupersList `
                -ApplicableArchitecture 'x64' `
                -ApplicableLanguages @('neutral') `
                -KnownType 'SSU'
            $ssuEntry | Add-Member -NotePropertyName 'IsCombined' -NotePropertyValue $false -Force
            $ssuEntry | Add-Member -NotePropertyName 'Variant' -NotePropertyValue 'Full' -Force
            $lcu | Add-Member -NotePropertyName 'IsCombined' -NotePropertyValue $false -Force
            $resolved.Add($ssuEntry) | Out-Null
            Write-Ok ('  Resolved standalone SSU {0} ({1}) for LCU {2}; LCU set IsCombined=$false.' -f $ssuKbId, $ssuUid, $lcu.KbId)
        }
    }

    # ----- LCU RequiresKbIds dependency annotation -----
    # If a standalone SSU emerged from the LCU's bundle (filename heuristic
    # tagged a file as Type=SSU), link the LCU.RequiresKbIds to it. In
    # combined-only months the LCU keeps IsCombined=$true and its
    # RequiresKbIds remains empty (the SSU is internal to the package).
    $standaloneSsuKbs = @($resolved | Where-Object {
        ($_.Type -eq 'SSU') -and (
            -not ($_.PSObject.Properties.Name -contains 'IsCombined') -or
            (-not $_.IsCombined)
        )
    } | ForEach-Object { $_.KbId })
    if ($standaloneSsuKbs.Count -gt 0) {
        foreach ($p in $resolved) {
            if ($p.Type -eq 'LCU' -and -not $p.IsCombined) {
                $p.RequiresKbIds = $standaloneSsuKbs
            }
        }
    }

    $Script:LastSupersedenceExclusions = $supersedenceExclusions.ToArray()

    if ($resolved.Count -eq 0) {
        Write-Caution 'Resolve-PatchSetFromReleaseInfo: zero patches resolved.'
    } else {
        Write-Ok ('Resolved {0} patch entries via release-info path.' -f $resolved.Count)
    }
    return $resolved.ToArray()
}

# ============================================================
# Language-specific patch scraper
# ============================================================
# Locates per-language artifacts (Language Pack, LXP, .NET LP)
# in the Microsoft Update Catalogue. Returns an array of patch
# entries with shape compatible with PatchBaseline.Lines
# but additionally annotated with .Type in
# { LanguagePack, LXP, DotNet.LangPack }.
#
# Design note: this function provides a best-effort stub
# for OS versions where LP/LXP are not normally published monthly
# (Server 2016 / 2019 LTSC). For Server 2022 / 2025 it issues the
# documented queries; if nothing comes back, returns an empty array
# rather than throwing - downstream RefreshAllBaselines records
# this as "no Refresher result" and keeps the previous baseline.

function Get-LanguagePackQueryTemplate {
    <#
    .SYNOPSIS
        Returns the Catalogue query templates for language-specific
        artifacts of a given OsVersion + OsLanguage + PatchMonth.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)] [string]$OsLanguage,
        [Parameter(Mandatory)] [string]$PatchMonth
    )
    $m = $PatchMonth

    # Language tokens that appear in Catalogue file names
    $langTokens = @{
        'en-us' = @('en-us', 'en_us', 'english')
        'ja-jp' = @('ja-jp', 'ja_jp', 'japanese')
    }
    $tokens = if ($langTokens.ContainsKey($OsLanguage)) { $langTokens[$OsLanguage] } else { @($OsLanguage) }

    # OS-specific Catalogue title fragments
    $osTitleTokens = @{
        'Server2025' = @('Microsoft server operating system version 24H2', 'Windows Server 2025')
        'Server2022' = @(
            'Microsoft server operating system version 21H2',
            'Microsoft server operating system, version 21H2',
            'Windows Server 2022'
        )
        'Server2019' = @('Windows Server 2019')
        'Server2016' = @('Windows Server 2016')
    }
    $osTokensList = if ($osTitleTokens.ContainsKey($OsVersion)) { $osTitleTokens[$OsVersion] } else { @() }

    $queries = New-Object System.Collections.Generic.List[object]
    # LP and LXP are mostly published only for newer OS versions; we
    # issue the queries regardless and let the empty-result path mark
    # "no patch found" for the older LTSC SKUs.
    $queries.Add([pscustomobject]@{
        Type          = 'LanguagePack'
        QueryTemplate = ($m + ' Language Pack ' + $OsLanguage + ' ' + $osTokensList[0])
    }) | Out-Null
    $queries.Add([pscustomobject]@{
        Type          = 'LXP'
        QueryTemplate = ($m + ' Local Experience Pack ' + $OsLanguage + ' ' + $osTokensList[0])
    }) | Out-Null
    $queries.Add([pscustomobject]@{
        Type          = 'DotNet.LangPack'
        QueryTemplate = ($m + ' .NET Framework Language Pack ' + $OsLanguage + ' ' + $osTokensList[0])
    }) | Out-Null

    return @{
        OsTitleTokens   = $osTokensList
        LanguageTokens  = $tokens
        OsLanguage      = $OsLanguage
        Queries         = $queries
    }
}

function Resolve-LanguageSpecificPatchesFromCatalog {
    <#
    .SYNOPSIS
        Per-language Catalogue scraper for Language Pack / LXP /
        .NET Language Pack. Returns an array of entries with .Type
        in {LanguagePack, LXP, DotNet.LangPack}.
    .DESCRIPTION
        Best-effort: any per-type Catalogue search that returns zero
        narrowed results is silently skipped (no warning) because
        Microsoft does not publish LP/LXP for every OS x month combo.
        The caller (RefreshAllBaselines) treats an empty array as
        "verified absence", not as a failure.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)] [string]$OsLanguage,
        [Parameter(Mandatory)] [string]$PatchMonth,
        [int]$MaxRetries = 3
    )
    Write-Step ('Language-specific patches: OS={0} Lang={1} Month={2}' -f $OsVersion, $OsLanguage, $PatchMonth)
    $tmpl = Get-LanguagePackQueryTemplate -OsVersion $OsVersion -OsLanguage $OsLanguage -PatchMonth $PatchMonth

    $resolved = New-Object System.Collections.Generic.List[object]
    foreach ($q in $tmpl.Queries) {
        Write-Step ('  query: type={0} template="{1}"' -f $q.Type, $q.QueryTemplate)
        $hits = $null
        try {
            $hits = Get-UpdateIdFromCatalog -KbId $q.QueryTemplate -MaxRetries $MaxRetries
        } catch {
            Write-Caution ('  Catalogue search failed: {0}' -f $_.Exception.Message)
            continue
        }
        if (-not $hits -or $hits.Count -eq 0) {
            continue
        }

        # Filter by OS title token + language token in file name
        $narrowed = @($hits | Where-Object {
            $title = $_.Title.ToLower()
            $osMatch = $false
            foreach ($t in $tmpl.OsTitleTokens) {
                if ($title -match [regex]::Escape($t.ToLower())) { $osMatch = $true; break }
            }
            $langMatch = $false
            foreach ($lt in $tmpl.LanguageTokens) {
                if ($title -match [regex]::Escape($lt.ToLower())) { $langMatch = $true; break }
            }
            $osMatch -and $langMatch
        })
        if ($narrowed.Count -eq 0) {
            continue
        }
        $best = $narrowed[0]

        # DownloadDialog -> Select-CanonicalPatchFile to pick the proper file
        try {
            $links = Get-DownloadLinkFromCatalog -UpdateId $best.UpdateId -MaxRetries $MaxRetries
        } catch {
            continue
        }
        if (-not $links -or $links.Count -eq 0) { continue }
        $primary = Select-CanonicalPatchFile -Links $links -PatchType $q.Type -Architecture 'x64'
        if (-not $primary) { continue }

        $kbFromTitle = ''
        $kbMatch = [regex]::Match($best.Title, '\((KB\d{6,7})\)')
        if ($kbMatch.Success) { $kbFromTitle = $kbMatch.Groups[1].Value }

        $resolved.Add([pscustomobject]@{
            Type                   = $q.Type
            KbId                   = $kbFromTitle
            Title                  = $best.Title
            UpdateId               = $best.UpdateId
            DownloadUrl            = $primary.Url
            FileName               = $primary.FileName
            SizeBytes              = 0
            Sha256                 = ''
            ReleaseDate            = ''
            Supersedes             = @()
            RequiresKbIds          = @()
            ApplyOrder             = 50
            ApplicableArchitecture = 'x64'
            ApplicableLanguage     = $OsLanguage
            Variant                = 'Full'
        }) | Out-Null
    }

    if ($resolved.Count -eq 0) {
        Write-Step ('  No language-specific patches found for {0} / {1} / {2}.' -f $OsVersion, $OsLanguage, $PatchMonth)
    } else {
        Write-Ok ('  Resolved {0} language-specific patches.' -f $resolved.Count)
    }
    return $resolved.ToArray()
}

# ============================================================
# ISO Updater specific: DISM / WIM operations
# ============================================================

function Invoke-WimMountSafe {
    <#
    .SYNOPSIS
        Mount-WindowsImage wrapper. Cleans up any stale mount at the
        target path, creates the directory if missing, clears the
        ReadOnly attribute on the WIM file when present, and surfaces
        the original DISM error untouched.
    .DESCRIPTION
        DISM frequently leaves orphan mounts behind on abnormal exits.
        Before mounting, we run Get-WindowsImage -Mounted and discard
        any entry pointing at our target path with -Discard. This is
        the OSDBuilder pattern documented in SPEC Part D.1.

        We also clear the ReadOnly attribute on the WIM file before
        invoking Mount-WindowsImage. WIM files extracted from ISO
        media via robocopy /COPY:DAT inherit the ReadOnly attribute
        from the underlying ISO volume (which is by definition a
        read-only medium), and DISM refuses to mount a ReadOnly file
        in read-write mode with "You do not have permissions to mount
        and modify this image" - a misleading message that is not
        about Administrator privilege but about file attributes.
        Clearing the attribute is safe because we own the extracted
        tree under WorkRoot and the WIM is meant to be a writable
        working copy at this point in the pipeline.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$ImagePath,
        [Parameter(Mandatory)] [int]   $Index,
        [Parameter(Mandatory)] [string]$Path,
        [string]$LogDir
    )
    Set-DebugStep -Step ('wim-mount-prepare')

    # Ensure mount directory exists and is empty
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    # Clean up stale mount at this path, if any
    try {
        $existing = Invoke-DismCmdlet -CommandName 'Get-WindowsImage' -Parameters @{ Mounted = $true; ErrorAction = 'SilentlyContinue' }
        foreach ($m in @($existing)) {
            if ($m.Path -and (($m.Path.TrimEnd('\')) -ieq ($Path.TrimEnd('\')))) {
                Write-Caution ('Stale mount detected at {0}; discarding before remount.' -f $Path)
                Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path = $Path; Discard = $true; ErrorAction = 'SilentlyContinue' } | Out-Null
            }
        }
    } catch {
        # Get-WindowsImage may not be available on every host; safe to ignore
        $null = $_
    }

    # Clear ReadOnly attribute on the WIM file before mounting. WIMs
    # extracted from ISO via robocopy /COPY:DAT inherit the ReadOnly
    # bit; DISM then refuses the read-write mount with a misleading
    # "permissions" error. This is a no-op if the attribute is absent.
    Set-DebugStep -Step ('wim-mount-clear-readonly')
    try {
        $wimItem = Get-Item -LiteralPath $ImagePath -Force -ErrorAction Stop
        if ($wimItem.IsReadOnly) {
            $wimItem.IsReadOnly = $false
            Write-Step ('Cleared ReadOnly attribute on WIM: {0}' -f $ImagePath)
        }
    } catch {
        # Best-effort: if attribute manipulation fails for any reason,
        # let Mount-WindowsImage proceed and surface the real DISM error.
        Write-Caution ('Could not inspect or clear ReadOnly attribute on {0}: {1}' -f $ImagePath, $_.Exception.Message)
    } # psa-disable-line PSA3004 -- best-effort attribute clear; the subsequent Mount-WindowsImage will surface the real error if a problem remains

    Set-DebugStep -Step ('wim-mount-image-idx{0}' -f $Index)
    $mountArgs = @{
        ImagePath = $ImagePath
        Index     = $Index
        Path      = $Path
    }
    if (-not [string]::IsNullOrEmpty($Script:ScratchDir)) {
        $mountArgs['ScratchDirectory'] = $Script:ScratchDir
    }
    if ($LogDir) {
        $logPath = Join-Path $LogDir (('mount_idx{0}_{1:yyyyMMdd-HHmmss}.log' -f $Index, (Get-Date)))
        $mountArgs['LogPath'] = $logPath
    }
    Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters $mountArgs | Out-Null
    return $Path
}

function Invoke-WimDismountSafe {
    <#
    .SYNOPSIS
        Dismount-WindowsImage with the OSDBuilder retry pattern.
    .DESCRIPTION
        SPEC Part D.1 / OSDBuilder v24.10.8.1 Dismount-InstallwimOS:
        sleep 10 seconds first (release Defender/Indexer locks), try
        the dismount with -ErrorAction SilentlyContinue, and if that
        fails, sleep another 30 seconds and try again with normal error
        propagation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [switch] $Discard,
        [string] $LogDir
    )
    Set-DebugStep -Step 'wim-dismount-pre-sleep'
    Start-Sleep -Seconds 10

    $extra = @{}
    if ($LogDir) {
        $extra['LogPath'] = (Join-Path $LogDir (('dismount_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))))
    }
    if (-not [string]::IsNullOrEmpty($Script:ScratchDir)) {
        $extra['ScratchDirectory'] = $Script:ScratchDir
    }

    Set-DebugStep -Step 'wim-dismount-first-try'
    try {
        if ($Discard) {
            Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters (@{ Path = $Path; Discard = $true; ErrorAction = 'SilentlyContinue' } + $extra) | Out-Null
        } else {
            Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters (@{ Path = $Path; Save = $true; CheckIntegrity = $true; ErrorAction = 'SilentlyContinue' } + $extra) | Out-Null
        }
    } catch {
        Write-Caution ('First Dismount failed: {0}; waiting 30s and retrying...' -f $_.Exception.Message)
    }

    # Verify the mount is gone; if still present, retry the harder way
    $stillMounted = $false
    try {
        $cur = Invoke-DismCmdlet -CommandName 'Get-WindowsImage' -Parameters @{ Mounted = $true; ErrorAction = 'SilentlyContinue' }
        foreach ($m in @($cur)) {
            if ($m.Path -and (($m.Path.TrimEnd('\')) -ieq ($Path.TrimEnd('\')))) {
                $stillMounted = $true; break
            }
        }
    } catch { $null = $_ }

    if ($stillMounted) {
        Set-DebugStep -Step 'wim-dismount-retry-after-30s'
        Start-Sleep -Seconds 30
        if ($Discard) {
            Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters (@{ Path = $Path; Discard = $true } + $extra) | Out-Null
        } else {
            Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters (@{ Path = $Path; Save = $true; CheckIntegrity = $true } + $extra) | Out-Null
        }
    }
}

function Add-WindowsPackageWithRetry {
    <#
    .SYNOPSIS
        Add-WindowsPackage wrapper that recognises a small set of
        known-benign DISM errors and downgrades them to Warning per
        SPEC Part D.12 (OSDBuilder's 0x800f081e suppression pattern).
    .OUTPUTS
        String status code: 'Ok' | 'OkAfterRetry' | 'NotApplicable'.
        Fatal errors are re-thrown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$MountPath,
        [Parameter(Mandatory)] [string]$PackagePath,
        [string]$LogDir
    )
    if (-not (Test-Path -LiteralPath $PackagePath)) {
        throw ('Package missing: {0}' -f $PackagePath)
    }
    Set-DebugStep -Step ('add-pkg-' + [System.IO.Path]::GetFileName($PackagePath))

    $extraArg = @{}
    if ($LogDir) {
        $extraArg['LogPath'] = Join-Path $LogDir (('addpkg_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)))
    }
    if (-not [string]::IsNullOrEmpty($Script:ScratchDir)) {
        $extraArg['ScratchDirectory'] = $Script:ScratchDir
    }

    try {
        Invoke-DismCmdlet -CommandName 'Add-WindowsPackage' -Parameters (@{ Path = $MountPath; PackagePath = $PackagePath; ErrorAction = 'Stop' } + $extraArg) | Out-Null
        return 'Ok'
    } catch {
        $m = [string]$_.Exception.Message
        if ($m -match '0x800f081e') {
            Write-Caution ('0x800f081e: Package not applicable, skipping: {0}' -f [System.IO.Path]::GetFileName($PackagePath))
            return 'NotApplicable'
        }
        if ($m -match '0x800f0a13') {
            Write-Caution ('0x800f0a13: Modules Installer transient error; retrying after 10s...')
            Start-Sleep -Seconds 10
            Invoke-DismCmdlet -CommandName 'Add-WindowsPackage' -Parameters (@{ Path = $MountPath; PackagePath = $PackagePath; ErrorAction = 'Stop' } + $extraArg) | Out-Null
            return 'OkAfterRetry'
        }
        # All other errors propagate (0x800f0922, 0xC1420127, etc.)
        throw
    }
}

function Write-DismInvocation {
    <#
    .SYNOPSIS
        Uniform logger for every DISM operation the build performs.
    .DESCRIPTION
        DISM is the least predictable and hardest-to-diagnose dependency
        in this pipeline: a malformed argument can fail at runtime with an
        opaque exit code and nothing in the build log to show what was
        actually handed to it. Every DISM operation routes through one of
        two distinct-named chokepoints that call this logger first:
        Invoke-DismCli for dism.exe command-line calls, and Invoke-DismCmdlet
        for every DISM cmdlet, read and write (Get-WindowsImage,
        Get-WindowsPackage, Get-WindowsOptionalFeature, Mount / Dismount /
        Add-WindowsPackage). The in-box cmdlets are never shadowed; callers
        pass the cmdlet name explicitly. Parameters are surfaced into the
        build log BEFORE the operation runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Operation,
        [hashtable]$Parameters = @{}
    )
    Write-Step ('  DISM op: {0}' -f $Operation)
    foreach ($key in ($Parameters.Keys | Sort-Object)) {
        Write-Step ('    {0,-14}: [{1}]' -f $key, $Parameters[$key])
    }
}

function Invoke-DismCli {
    <#
    .SYNOPSIS
        Single chokepoint for every dism.exe command-line invocation.
    .DESCRIPTION
        Logs the fully-resolved command line (every argument) and the
        resulting exit code through Write-DismInvocation, then returns the
        exit code so the caller decides how to treat a failure. Routing all
        dism.exe calls through here means the exact command - including any
        empty or malformed argument - is always visible in the build log,
        the information that was missing when a /Cleanup-Image run failed
        with an opaque exit code 1639. dism.exe stdout is sent to the host
        so it stays on the console without polluting the returned value.
    .OUTPUTS
        Int32 - the dism.exe process exit code.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Arguments,
        [string]$Context = 'dism'
    )
    Set-DebugStep -Step ('dism-cli-' + $Context)
    Write-DismInvocation -Operation ('dism.exe ' + $Context) -Parameters @{ CommandLine = ('dism.exe ' + ($Arguments -join ' ')) }
    & dism.exe @Arguments | Out-Host
    $code = $LASTEXITCODE
    Write-Step ('  DISM op: dism.exe {0} -> exit code {1}' -f $Context, $code)
    return $code
}

function Invoke-DismCmdlet {
    <#
    .SYNOPSIS
        Single chokepoint for every DISM cmdlet invocation, read and write.
    .DESCRIPTION
        Logs the cmdlet name and its fully-resolved parameters through
        Write-DismInvocation, then runs the real cmdlet by name with those
        parameters splatted in, and returns whatever the cmdlet returns.
        Gives uniform, comprehensive visibility of every DISM operation -
        Get-WindowsImage / Get-WindowsPackage / Get-WindowsOptionalFeature
        reads as well as Mount / Dismount / Add-WindowsPackage writes - at the
        point of failure (corrupt or unreadable WIM, version-incompatible
        image, missing servicing command, etc.). The in-box cmdlets are NOT
        shadowed by same-named proxies: callers invoke this helper by its
        distinct name and pass the cmdlet name and a parameter hashtable
        explicitly, so Get-Command, IntelliSense and module auto-loading
        behave normally. Errors and pipeline output propagate unchanged; only
        logging is added (Write-DismInvocation writes via Write-Host, so the
        returned value is exactly the cmdlet's own output).
    .PARAMETER CommandName
        The DISM cmdlet to run, e.g. 'Get-WindowsImage'.
    .PARAMETER Parameters
        Hashtable of parameters splatted into the cmdlet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$CommandName,
        [hashtable]$Parameters = @{}
    )
    Write-DismInvocation -Operation $CommandName -Parameters $Parameters
    & $CommandName @Parameters
}


function Get-DismCleanupArgumentList {
    <#
    .SYNOPSIS
        Build the dism.exe argument vector for the offline /Cleanup-Image pass.
    .DESCRIPTION
        Returns the arguments as a [string[]] so each token reaches dism.exe as
        a SEPARATE argument. Kept as a pure function (no invocation, no side
        effects) so the vector can be unit-tested directly. This guards the
        operator-precedence trap that previously collapsed the vector: written
        as @('/Image:' + $MountPath, '/Cleanup-Image', ...), PowerShell binds
        the comma operator tighter than +, so the expression parsed as
        '/Image:' + ($MountPath, '/Cleanup-Image', ...) -- the trailing array
        was stringified (space-joined) into the /Image: value, yielding a
        SINGLE argument and dism.exe exit code 1639. Using "/Image:$MountPath"
        (interpolation, no + operator) keeps the first element intact.

        By default the vector is /Cleanup-Image /StartComponentCleanup only.
        /ResetBase resets the component-store base (smaller image, applied
        updates no longer removable) but is very slow per index, so it is OFF
        by default (matching Microsoft's released-media practice) and appended
        only when -IncludeResetBase is set. Size is instead recovered by the
        default Export-Image /Compress:max pass.
    .PARAMETER MountPath
        Path to the mounted offline image (the /Image: target).
    .PARAMETER IncludeResetBase
        When set, append /ResetBase to the cleanup vector.
    .OUTPUTS
        String[] - three cleanup arguments by default; four when
        -IncludeResetBase appends /ResetBase.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string]$MountPath,
        [switch]$IncludeResetBase,
        [string]$ScratchDir
    )
    $vector = @("/Image:$MountPath", '/Cleanup-Image', '/StartComponentCleanup')
    if ($IncludeResetBase) {
        $vector += '/ResetBase'
    }
    if (-not [string]::IsNullOrEmpty($ScratchDir)) {
        $vector += "/ScratchDir:$ScratchDir"
    }
    return $vector
}


function Invoke-DismCleanup {
    <#
    .SYNOPSIS
        Run "dism.exe /Image:<path> /Cleanup-Image /StartComponentCleanup"
        against a mounted image (optionally with /ResetBase).
    .DESCRIPTION
        Cleanup runs once per image, AFTER all packages for that image have
        been applied. By default it runs /StartComponentCleanup /ResetBase;
        /ResetBase ($Script:ResetBaseOnCleanup, default ON) resets the
        component-store base so the patched golden image ships the latest
        updates already applied. -SkipResetBaseOnCleanup omits /ResetBase
        (keeps updates removable). A workspace-local /ScratchDir keeps DISM
        temp I/O under the work area.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$MountPath)
    Set-DebugStep -Step 'dism-cleanup-image'
    $dismArgs = Get-DismCleanupArgumentList -MountPath $MountPath -IncludeResetBase:$Script:ResetBaseOnCleanup -ScratchDir $Script:ScratchDir
    $code = Invoke-DismCli -Arguments $dismArgs -Context 'cleanup-image'
    if ($code -ne 0) {
        throw ('dism.exe /Cleanup-Image failed with exit code {0}' -f $code)
    }
}

function Get-DismExportArgumentList {
    <#
    .SYNOPSIS
        Build the dism.exe /Export-Image argument vector for one source index.
    .DESCRIPTION
        Pure function (no invocation) returning the arguments as a [string[]]
        so each token reaches dism.exe separately and the vector can be
        unit-tested. Uses interpolation ("/SourceImageFile:$SourceWim" etc.,
        no + operator) to avoid the comma/+ precedence collapse. /Compress:max
        recompresses and single-instances shared files in the destination WIM.
    .PARAMETER SourceWim
        Path to the source WIM file.
    .PARAMETER SourceIndex
        Image index to export from the source WIM.
    .PARAMETER DestinationWim
        Path to the destination WIM (created, or appended to in index order).
    .OUTPUTS
        String[] - the five dism.exe /Export-Image arguments, in order.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string]$SourceWim,
        [Parameter(Mandatory)] [int]$SourceIndex,
        [Parameter(Mandatory)] [string]$DestinationWim,
        [string]$ScratchDir
    )
    $vector = @(
        '/Export-Image',
        "/SourceImageFile:$SourceWim",
        "/SourceIndex:$SourceIndex",
        "/DestinationImageFile:$DestinationWim",
        '/Compress:max'
    )
    if (-not [string]::IsNullOrEmpty($ScratchDir)) {
        $vector += "/ScratchDir:$ScratchDir"
    }
    return $vector
}

function Export-InstallWimCompressed {
    <#
    .SYNOPSIS
        Recompress + single-instance install.wim via Export-Image /Compress:max.
    .DESCRIPTION
        After every index has been serviced and dismounted, a single
        Export-Image pass over ALL indexes (in index order) into a fresh WIM
        with /Compress:max recompresses and single-instances files shared
        across editions, recovering the size that the now-default-off
        /ResetBase used to reclaim - without the per-index /ResetBase time
        cost. ALL indexes are exported so no edition is dropped (even when only
        a subset was serviced via -OnlyInstallWimIndexes). The exported WIM is
        index-count-verified BEFORE the original is replaced; on any failure or
        count mismatch the original install.wim is left untouched.
    .PARAMETER WimPath
        Path to the serviced install.wim to optimise in place.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$WimPath)
    $before = Get-WimIndexInventory -WimPath $WimPath
    $sourceCount = ($before | Measure-Object).Count
    if ($sourceCount -lt 1) {
        throw ('install.wim reports no indexes; cannot export: {0}' -f $WimPath)
    }
    $exported = $WimPath + '.optimized.wim'
    if (Test-Path -LiteralPath $exported) {
        Remove-Item -LiteralPath $exported -Force
    }
    $origBytes = (Get-Item -LiteralPath $WimPath).Length
    Write-Step ('Export-Image /Compress:max over {0} index(es) to recover size (no /ResetBase).' -f $sourceCount)
    foreach ($img in ($before | Sort-Object ImageIndex)) {
        Set-DebugStep -Step ('export-install-idx-' + $img.ImageIndex)
        $exportArgs = Get-DismExportArgumentList -SourceWim $WimPath -SourceIndex $img.ImageIndex -DestinationWim $exported -ScratchDir $Script:ScratchDir
        $code = Invoke-DismCli -Arguments $exportArgs -Context ('export-image-idx' + $img.ImageIndex)
        if ($code -ne 0) {
            throw ('dism.exe /Export-Image failed (index {0}) with exit code {1}' -f $img.ImageIndex, $code)
        }
    }
    $after = Get-WimIndexInventory -WimPath $exported
    $exportedCount = ($after | Measure-Object).Count
    if ($exportedCount -ne $sourceCount) {
        throw ('Export-Image index-count mismatch (source {0}, exported {1}); leaving install.wim untouched.' -f $sourceCount, $exportedCount)
    }
    Remove-Item -LiteralPath $WimPath -Force
    Move-Item -LiteralPath $exported -Destination $WimPath -Force
    $newBytes = (Get-Item -LiteralPath $WimPath).Length
    $savedPct = if ($origBytes -gt 0) { [Math]::Round((1 - ($newBytes / $origBytes)) * 100, 1) } else { 0 }
    Write-Ok ('install.wim recompressed: {0:N0} -> {1:N0} bytes ({2}% smaller).' -f $origBytes, $newBytes, $savedPct)
}

# ===========================================================================
# Windows Defender exclusion management (opt-in, -UseDefenderExclusions)
# ---------------------------------------------------------------------------
# A real-machine A/B probe (2026-06) measured that excluding the work area
# plus the DISM/CBS servicing processes from Defender real-time scanning cuts
# the LCU apply ~35% (the cleanup is storage-bound and unaffected). OPT-IN and
# security-affecting: exclusions are added for the run and removed afterwards.
# Invariants:
#   * fail-closed -- applied ONLY when every prerequisite is positively
#     confirmed (commands present, WinDefend running, real-time on, Tamper off,
#     AMRunningMode = Normal). Any unknown/unmet condition -> skip (touch
#     nothing). Older Server SKUs that do not report these properties are thus
#     skipped, by design.
#   * only-add-what's-absent + only-remove-what-WE-added -- a state file records
#     exactly what this run added; restore removes only those, never a
#     pre-existing user exclusion.
#   * guaranteed restore (main finally) + startup self-heal of a state file
#     left by a crashed run.
# The pure helpers (Get-DefenderManagedExclusionSet, Get-DefenderExclusionPlan,
# Get-DefenderExclusionDecision) are unit-tested (T26); the
# Get-MpComputerStatus / Add-/Remove-MpPreference calls are thin Windows-only
# wrappers (these cmdlets do not exist on Linux).
# ===========================================================================

function Get-DefenderManagedExclusionSet {
    # Pure. The canonical set this tool manages: the WorkRoot tree (one path
    # exclusion covers all children recursively) and the servicing processes
    # by FILE NAME (TiWorker.exe lives under a versioned WinSxS path, so a full
    # path is not stable; file-name exclusions are version-robust).
    param([Parameter(Mandatory)] [string]$WorkRoot)
    return [pscustomobject]@{
        Paths     = @($WorkRoot)
        Processes = @('dism.exe', 'DismHost.exe', 'TiWorker.exe', 'TrustedInstaller.exe')
    }
}

function Get-DefenderExclusionPlan {
    # Pure. Return only the desired items NOT already present (case-insensitive;
    # paths compared trailing-slash-insensitively). Output preserves desired
    # casing. Guarantees "only add what is absent".
    param(
        [string[]]$DesiredPaths,
        [string[]]$DesiredProcesses,
        [string[]]$ExistingPaths,
        [string[]]$ExistingProcesses
    )
    $existPathSet = @{}
    foreach ($p in @($ExistingPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { $existPathSet[$p.TrimEnd('\').ToLowerInvariant()] = $true }
    }
    $existProcSet = @{}
    foreach ($q in @($ExistingProcesses)) {
        if (-not [string]::IsNullOrWhiteSpace($q)) { $existProcSet[$q.ToLowerInvariant()] = $true }
    }
    $pathsToAdd = @()
    foreach ($p in @($DesiredPaths)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not $existPathSet.ContainsKey($p.TrimEnd('\').ToLowerInvariant())) { $pathsToAdd += $p }
    }
    $procsToAdd = @()
    foreach ($q in @($DesiredProcesses)) {
        if ([string]::IsNullOrWhiteSpace($q)) { continue }
        if (-not $existProcSet.ContainsKey($q.ToLowerInvariant())) { $procsToAdd += $q }
    }
    return [pscustomobject]@{
        PathsToAdd     = @($pathsToAdd)
        ProcessesToAdd = @($procsToAdd)
    }
}

function Get-DefenderExclusionDecision {
    # Pure, fail-closed. Each input is [object] so an unreported value is $null
    # (older Server SKUs may omit AMRunningMode / IsTamperProtected). Apply ONLY
    # when every condition is positively satisfied; otherwise skip with a
    # specific reason. Flat params (not a status object) keep it unit-testable.
    param(
        [object]$CommandsAvailable,
        [object]$ServiceRunning,
        [object]$RealTimeEnabled,
        [object]$TamperProtected,
        [object]$RunningMode
    )
    if ($CommandsAvailable -ne $true) {
        return [pscustomobject]@{ Apply = $false; Reason = 'Defender PowerShell commands are not all available' }
    }
    if ($ServiceRunning -ne $true) {
        return [pscustomobject]@{ Apply = $false; Reason = 'the WinDefend service is absent or not running' }
    }
    if ($RealTimeEnabled -ne $true) {
        return [pscustomobject]@{ Apply = $false; Reason = 'real-time protection is off or unknown (exclusions would have no effect)' }
    }
    if ($TamperProtected -ne $false) {
        return [pscustomobject]@{ Apply = $false; Reason = 'Tamper Protection is on or unknown (exclusions may be ignored)' }
    }
    if ($RunningMode -ne 'Normal') {
        $m = if ($null -eq $RunningMode) { 'unknown' } else { $RunningMode }
        return [pscustomobject]@{ Apply = $false; Reason = ('AMRunningMode is not Normal (got: {0}); another AV may be primary' -f $m) }
    }
    return [pscustomobject]@{ Apply = $true; Reason = 'all prerequisites satisfied (Normal mode, real-time on, Tamper off)' }
}

function Test-DefenderToolingAvailable {
    # Windows-only. Explicit search so a missing cmdlet/service yields $false,
    # not a terminating error (older Server SKUs may differ).
    $cmds = @('Get-MpComputerStatus', 'Get-MpPreference', 'Add-MpPreference', 'Remove-MpPreference')
    $cmdsOk = $true
    foreach ($c in $cmds) {
        if (-not (Get-Command -Name $c -ErrorAction SilentlyContinue)) { $cmdsOk = $false; break }
    }
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'WinDefend' }
    $svcRunning = [bool]($svc -and $svc.Status -eq 'Running')
    return [pscustomobject]@{ CommandsAvailable = $cmdsOk; ServiceRunning = $svcRunning }
}

function Get-DefenderStatusNormalized {
    # Windows-only. Calls Get-MpComputerStatus defensively; normalises the three
    # decision properties to $true/$false/$null (older SKUs may omit
    # AMRunningMode / IsTamperProtected -> $null -> fail-closed skip).
    $tooling = Test-DefenderToolingAvailable
    $rt = $null; $tamper = $null; $mode = $null
    if ($tooling.CommandsAvailable) {
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $names = @($st.PSObject.Properties.Name)
            if ($names -contains 'RealTimeProtectionEnabled') { $rt = [bool]$st.RealTimeProtectionEnabled }
            if ($names -contains 'IsTamperProtected')         { $tamper = [bool]$st.IsTamperProtected }
            if ($names -contains 'AMRunningMode')              { $mode = [string]$st.AMRunningMode }
        } catch {
            $null = $_
        }
    }
    return [pscustomobject]@{
        CommandsAvailable = $tooling.CommandsAvailable
        ServiceRunning    = $tooling.ServiceRunning
        RealTimeEnabled   = $rt
        TamperProtected   = $tamper
        RunningMode       = $mode
    }
}

function Get-DefenderExclusionStatePath {
    return (Join-Path $Script:StateDir 'defender-exclusions.json')
}

function Write-DefenderExclusionState {
    param([string[]]$PathsAdded, [string[]]$ProcessesAdded)
    if (-not (Test-Path -LiteralPath $Script:StateDir)) {
        New-Item -ItemType Directory -Path $Script:StateDir -Force | Out-Null
    }
    $obj = [pscustomobject]@{
        schema         = 'defender-exclusions/1'
        createdUtc     = (Get-Date).ToUniversalTime().ToString('o')
        ownerPid       = $PID
        pathsAdded     = @($PathsAdded)
        processesAdded = @($ProcessesAdded)
    }
    $obj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Get-DefenderExclusionStatePath) -Encoding UTF8
}

function Read-DefenderExclusionState {
    $f = Get-DefenderExclusionStatePath
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) } catch { return $null }
}

function Remove-DefenderExclusionState {
    $f = Get-DefenderExclusionStatePath
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

function Disable-ManagedDefenderExclusion {
    # Windows-only. Remove ONLY what this run recorded, then delete the state
    # file. Idempotent, best-effort, never throws.
    $state = Read-DefenderExclusionState
    if ($null -eq $state) { return }
    try {
        $paths = @($state.pathsAdded) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $procs = @($state.processesAdded) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $hasRemove = [bool](Get-Command -Name 'Remove-MpPreference' -ErrorAction SilentlyContinue)
        if ($hasRemove -and $paths.Count -gt 0) { Remove-MpPreference -ExclusionPath $paths -ErrorAction SilentlyContinue }
        if ($hasRemove -and $procs.Count -gt 0) { Remove-MpPreference -ExclusionProcess $procs -ErrorAction SilentlyContinue }
        Write-Step ('Defender exclusions removed (paths: {0}; processes: {1}).' -f ($paths -join ', '), ($procs -join ', '))
    } catch {
        Write-Caution ('Defender exclusion removal warning: {0}' -f $_.Exception.Message)
    } finally {
        Remove-DefenderExclusionState
    }
}

function Enable-ManagedDefenderExclusion {
    # Windows-only orchestration. Diagnose (fail-closed); only on a fully
    # satisfied environment add the absent exclusions and record them FIRST so
    # restore can always undo them. Never throws into the build.
    if (-not $Script:UseDefenderExclusions) { return }
    try {
        $status = Get-DefenderStatusNormalized
        $modeStr = if ($null -eq $status.RunningMode) { 'unknown' } else { $status.RunningMode }
        Write-Step ('Defender: mode={0} realtime={1} tamper={2} service={3}' -f $modeStr, $status.RealTimeEnabled, $status.TamperProtected, $status.ServiceRunning)
        $decisionArgs = @{
            CommandsAvailable = $status.CommandsAvailable
            ServiceRunning    = $status.ServiceRunning
            RealTimeEnabled   = $status.RealTimeEnabled
            TamperProtected   = $status.TamperProtected
            RunningMode       = $status.RunningMode
        }
        $decision = Get-DefenderExclusionDecision @decisionArgs
        if (-not $decision.Apply) {
            Write-Caution ('Defender exclusions NOT applied: {0}. Build continues without exclusions.' -f $decision.Reason)
            return
        }
        $desired = Get-DefenderManagedExclusionSet -WorkRoot $Script:WorkRoot
        $pref = Get-MpPreference -ErrorAction Stop
        $plan = Get-DefenderExclusionPlan -DesiredPaths $desired.Paths -DesiredProcesses $desired.Processes -ExistingPaths @($pref.ExclusionPath) -ExistingProcesses @($pref.ExclusionProcess)
        if ($plan.PathsToAdd.Count -eq 0 -and $plan.ProcessesToAdd.Count -eq 0) {
            Write-Step 'Defender: every managed exclusion is already present (added outside this tool); nothing added, nothing recorded.'
            return
        }
        Write-DefenderExclusionState -PathsAdded $plan.PathsToAdd -ProcessesAdded $plan.ProcessesToAdd
        if ($plan.PathsToAdd.Count -gt 0)     { Add-MpPreference -ExclusionPath $plan.PathsToAdd -ErrorAction Stop }
        if ($plan.ProcessesToAdd.Count -gt 0) { Add-MpPreference -ExclusionProcess $plan.ProcessesToAdd -ErrorAction Stop }
        $appliedMsg = ('Defender exclusions applied (paths: {0}; processes: {1}). ' -f ($plan.PathsToAdd -join ', '), ($plan.ProcessesToAdd -join ', '))
        $appliedMsg += 'Expected effect: ~35% faster LCU apply; the cleanup is storage-bound and unaffected. Exclusions are removed at the end of the run.'
        Write-Ok $appliedMsg
    } catch {
        Write-Caution ('Defender exclusion setup failed ({0}); rolling back and continuing without exclusions.' -f $_.Exception.Message)
        try { Disable-ManagedDefenderExclusion } catch { $null = $_ }
    }
}

function Invoke-DefenderExclusionSelfHeal {
    # Windows-only. If a state file is present at startup, a previous run left
    # exclusions behind (e.g. the process was killed before its finally ran).
    # Remove exactly those recorded and clear the record. Runs regardless of
    # -UseDefenderExclusions so a crashed run is cleaned on the next invocation
    # that reuses the same WorkRoot.
    $state = Read-DefenderExclusionState
    if ($null -eq $state) { return }
    Write-Caution 'Found a Defender-exclusion state file from a previous run (likely interrupted); restoring those exclusions now.'
    Disable-ManagedDefenderExclusion
}

function Get-WimIndexInventory {
    <#
    .SYNOPSIS
        Wrap Get-WindowsImage -ImagePath to return a normalised list of
        WIM image indexes with their names and sizes. Locale-independent
        (unlike dism.exe text output, which is cp932 in ja-JP).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param([Parameter(Mandatory)] [string]$WimPath)
    if (-not (Test-Path -LiteralPath $WimPath)) {
        throw ('WIM not found: {0}' -f $WimPath)
    }
    $entries = Invoke-DismCmdlet -CommandName 'Get-WindowsImage' -Parameters @{ ImagePath = $WimPath }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($e in $entries) {
        $list.Add([pscustomobject]@{
            ImageIndex       = [int]$e.ImageIndex
            ImageName        = [string]$e.ImageName
            ImageDescription = [string]$e.ImageDescription
            ImageSize        = [long]$e.ImageSize
        }) | Out-Null
    }
    return $list
}

# ============================================================
# ISO Updater specific: boot file resolution + ISO assembly
# ============================================================

function Resolve-EtfsbootCom {
    <#
    .SYNOPSIS
        Locate etfsboot.com using the three-tier fallback chain
        documented in SPEC Part B.5 P09.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$ExtractedIsoRoot)
    $candidates = @(
        (Join-Path $ExtractedIsoRoot 'boot\etfsboot.com')
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\etfsboot.com'
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\etfsboot.com'
    )
    if ($env:ISOFACTORY_PE_DIR) {
        $candidates += (Join-Path $env:ISOFACTORY_PE_DIR 'fwfiles\etfsboot.com')
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    throw 'etfsboot.com not found in any of the expected locations.'
}

function Resolve-EfisysBin {
    <#
    .SYNOPSIS
        Locate efisys.bin using the three-tier fallback chain
        documented in SPEC Part B.5 P09.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$ExtractedIsoRoot)
    $candidates = @(
        (Join-Path $ExtractedIsoRoot 'efi\microsoft\boot\efisys.bin')
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\efisys.bin'
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\efisys.bin'
    )
    if ($env:ISOFACTORY_PE_DIR) {
        $candidates += (Join-Path $env:ISOFACTORY_PE_DIR 'fwfiles\efisys.bin')
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    throw 'efisys.bin not found in any of the expected locations.'
}

function Install-WindowsAdkFallback {
    <#
    .SYNOPSIS
        Download Microsoft's adksetup.exe and silently install the
        Windows ADK Deployment Tools feature (oscdimg.exe).

    .DESCRIPTION
        Called from P01 Step 3 when the Resolve-OscdimgExe search
        failed (oscdimg.exe missing). Mirrors the
        Install-WindowsSdkFallback / Install-WindowsWdkFallback pattern
        in Deploy-AMDChipsetDriverOnWindowsServer.ps1:

          1) Download $Script:AdkInstallerUrl (fwlink, pinned in the
             global-constants block) to <WorkRoot>\cache\adk\adksetup.exe.
             Reuse cache if already present.
          2) Run adksetup.exe with $Script:AdkInstallerOptionId
             (OptionId.DeploymentTools), /quiet /norestart /ceip off,
             and /log <WorkRoot>\logs\adksetup.log.
          3) Defensive verify: a non-zero installer exit code with
             oscdimg.exe present afterwards is treated as
             "already installed" (warn-only). Only a missing oscdimg.exe
             after install is a hard failure.

        Returns the absolute path to the discovered oscdimg.exe so the
        caller does not need to re-invoke Resolve-OscdimgExe (which
        would emit the SHA-256 advisory line a second time).

    .OUTPUTS
        [string] - absolute path to oscdimg.exe

    .NOTES
        Network access is required. The Microsoft Learn page for the
        ADK lists the canonical download URL; see the comment block
        next to $Script:AdkInstallerUrl above.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $cacheDir = Join-Path $Script:WorkRoot 'cache\adk'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $exePath = Join-Path $cacheDir 'adksetup.exe'
    $logPath = Join-Path $Script:LogsDir 'adksetup.log'

    Write-Step ('ADK installer version : {0} (pinned)' -f $Script:AdkInstallerVersion)
    Write-Step ('ADK installer URL     : {0}' -f $Script:AdkInstallerUrl)
    Write-Step ('Cache path            : {0}' -f $exePath)
    Write-Step ('Install log           : {0}' -f $logPath)
    Write-Step ('Feature               : {0}' -f $Script:AdkInstallerOptionId)

    if (Test-Path -LiteralPath $exePath) {
        $fi = Get-Item -LiteralPath $exePath
        Write-Step ('Reusing cached adksetup.exe ({0:N0} bytes)' -f $fi.Length)
    } else {
        Write-Step 'Downloading adksetup.exe from Microsoft Learn fwlink...'
        try {
            # Force TLS 1.2 for compatibility with older Server hosts
            $oldSp = [System.Net.ServicePointManager]::SecurityProtocol
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.SecurityProtocolType]::Tls12
            try {
                Invoke-WebRequest -Uri $Script:AdkInstallerUrl `
                                  -OutFile $exePath `
                                  -UseBasicParsing
            } finally {
                [System.Net.ServicePointManager]::SecurityProtocol = $oldSp
            }
        } catch {
            throw ('ADK installer download failed: {0}' -f $_.Exception.Message)
        }
        if (-not (Test-Path -LiteralPath $exePath)) {
            throw 'ADK installer download appeared to succeed but adksetup.exe is not present.'
        }
        $fi = Get-Item -LiteralPath $exePath
        Write-Ok ('adksetup.exe downloaded ({0:N0} bytes)' -f $fi.Length)
    }

    $installArgs = @(
        '/features', $Script:AdkInstallerOptionId,
        '/quiet',
        '/norestart',
        '/ceip', 'off',
        '/log',   $logPath
    )
    Write-Step ('Running: adksetup.exe {0}' -f ($installArgs -join ' '))

    # psa-disable-next-line PSA3001 -- Start-Process -ArgumentList is the
    # canonical pattern for invoking installer EXEs with explicit args;
    # matches Install-WindowsSdkFallback / Install-WindowsWdkFallback in
    # the SDK/WDK reference implementation.
    $proc = Start-Process -FilePath $exePath `
                          -ArgumentList $installArgs `
                          -Wait -PassThru

    # Defensive verify by tool presence rather than trusting the exit
    # code (matches the SDK/WDK reference behaviour for installer EXEs
    # that exit non-zero when the kit is already on the machine).
    $oscdimgPath = $null
    try {
        $oscdimgPath = Resolve-OscdimgExe
    } catch {
        # Resolve-OscdimgExe throws when no oscdimg.exe is found anywhere.
        # We translate that to a hard failure below.
        $oscdimgPath = $null
    }

    if ($oscdimgPath) {
        if ($proc.ExitCode -ne 0) {
            Write-Caution ('ADK installer exit code {0}; oscdimg.exe is present, treating as already installed.' -f $proc.ExitCode)
        }
        Write-Ok ('Windows ADK Deployment Tools installed: {0}' -f $oscdimgPath)
        return $oscdimgPath
    }
    throw ('Windows ADK install failed (exit {0}); oscdimg.exe still not found. See {1} for installer diagnostics.' -f $proc.ExitCode, $logPath)
}

function Resolve-OscdimgExe {
    <#
    .SYNOPSIS
        Locate oscdimg.exe under the ADK Deployment Tools and verify
        the binary against Microsoft's official Make2023BootableMedia.ps1
        symbol-server-distributed reference hashes.

    .DESCRIPTION
        Returns the absolute path to a usable oscdimg.exe. Also emits an
        advisory message indicating whether the located binary matches
        Microsoft's "ground-truth" SHA-256 for the current architecture.

        The reference hash table is lifted verbatim from Microsoft's
        secureboot_objects repository
        (scripts/windows/Make2023BootableMedia.ps1 v1.6.4-signed / commit bd7abe3,
        $global:oscdimg_known_hashes). These hashes correspond to the
        oscdimg.exe binaries distributed via Microsoft's public symbol
        server (https://msdl.microsoft.com/download/symbols/).

        IMPORTANT: ADK-installed oscdimg.exe binaries may legitimately
        have DIFFERENT hashes per ADK version. A hash mismatch is therefore
        treated as ADVISORY (warning), NOT a hard failure. The check still
        serves a critical purpose: detecting supply-chain attacks where
        the oscdimg.exe binary has been swapped for a malicious version
        on the host running this script.

    .OUTPUTS
        [string] - absolute path to oscdimg.exe
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Microsoft official oscdimg.exe SHA-256 hashes (from secureboot_objects
    # Make2023BootableMedia.ps1 v1.6.4-signed / commit bd7abe3). These are the
    # hashes of binaries downloaded from the Microsoft public symbol server.
    $knownHashes = @{
        'AMD64' = 'ABCD07318EBD8CDBE274B46C9DE78820DCA9709D558CDBC1F5D1730924264D07'
        'ARM64' = 'CDAE3649F6A6DE45F50A0B5FB5E2BBC098503B9EEFB1AE6A398FC955B434F579'
        'x86'   = '85AC2DDD96239D037560E5336727F9A8BE2B902734B9DD88264DD7DB5612EFB9'
    }

    $candidates = @(
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )
    $found = $null
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $found = $c
            break
        }
    }
    if (-not $found) {
        # Try PATH lookup
        $cmd = Get-Command -Name 'oscdimg.exe' -ErrorAction SilentlyContinue
        if ($cmd) { $found = $cmd.Source }
    }
    if (-not $found) {
        throw 'oscdimg.exe not found. Install the Windows ADK Deployment Tools.'
    }

    # Integrity check (advisory only)
    try {
        $arch = $env:PROCESSOR_ARCHITECTURE
        if (-not $arch) { $arch = 'AMD64' }   # sensible default for x64 hosts
        $expectedHash = $knownHashes[$arch]
        if ($expectedHash) {
            $actualHash = (Get-FileHash -LiteralPath $found -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($actualHash -ieq $expectedHash) {
                Write-Step ('oscdimg.exe integrity verified (Microsoft reference hash for {0})' -f $arch)
            } else {
                Write-Caution ('oscdimg.exe SHA-256 differs from the Microsoft reference value for {0}.' -f $arch)
                Write-Caution ('  Found    : {0}' -f $actualHash)
                Write-Caution ('  Reference: {0}' -f $expectedHash)
                Write-Caution '  This is ADVISORY: ADK-installed binaries may legitimately differ per ADK version.'
                Write-Caution '  If you did NOT install oscdimg.exe via the Windows ADK or Microsoft symbol server,'
                Write-Caution '  investigate the origin of this binary before proceeding (supply-chain integrity check).'
            }
        } else {
            Write-Step ('oscdimg.exe integrity check skipped: no reference hash for architecture "{0}".' -f $arch)
        }
    } catch {
        # Best-effort: if hash computation itself fails, that's surprising
        # but not fatal; surface as a debug step rather than aborting.
        Write-Caution ('oscdimg.exe integrity check could not be completed: {0}' -f $_.Exception.Message)
    } # psa-disable-line PSA3004 -- intentional best-effort integrity-check warning; hash mismatch is advisory only

    return $found
}

function Resolve-SignToolExe {
    <#
    .SYNOPSIS
        Locate signtool.exe (Windows SDK Signing Tools). Mirrors the
        Resolve-OscdimgExe / Get-SevenZipPath resolve pattern and the
        Find-KitTool walk in Deploy-AMDChipsetDriverOnWindowsServer.ps1.

    .DESCRIPTION
        Returns the absolute path to a usable signtool.exe, preferring
        the x64 build of the newest installed SDK. Search order:
          1) PATH (Get-Command) - winsdksetup may have updated the env.
          2) Windows Kits\10\bin under Program Files (x86) then Program
             Files, recursing for signtool.exe; prefer an \x64\ hit
             (newest by descending path sort), else any architecture.
        No integrity hash check: unlike oscdimg.exe (which has Microsoft
        symbol-server reference hashes), signtool.exe has no single fixed
        reference SHA-256 - it varies per SDK build - so presence is the
        only check (the SDK is acquired from the Microsoft fwlink).

        Returns $null when signtool.exe is not found anywhere; the caller
        decides whether to Install-WindowsSdkFallback or degrade.

    .OUTPUTS
        [string] - absolute path to signtool.exe, or $null if not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # (1) PATH lookup first (an installer may have updated the environment)
    $cmd = Get-Command -Name 'signtool.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # (2) Walk the Windows Kits bin directories; prefer x64 + newest.
    foreach ($root in @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "${env:ProgramFiles}\Windows Kits\10\bin")) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hits = @(Get-ChildItem -Path $root -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue)
        if ($hits.Count -eq 0) { continue }
        $x64 = $hits | Where-Object { $_.FullName -match '\\x64\\' } |
               Sort-Object FullName -Descending | Select-Object -First 1
        if ($x64) { return $x64.FullName }
        $any = $hits | Sort-Object FullName -Descending | Select-Object -First 1
        if ($any) { return $any.FullName }
    }
    return $null
}

function Install-WindowsSdkFallback {
    <#
    .SYNOPSIS
        Download Microsoft's winsdksetup.exe and silently install the
        Windows SDK Signing Tools feature (signtool.exe).

    .DESCRIPTION
        Called when a signtool.exe consumer (the PCA2023 readiness
        classifier, SPEC.md B.17.2 / B.18.1) finds signtool.exe missing.
        Mirrors Install-WindowsAdkFallback (and the
        Install-WindowsSdkFallback pattern in
        Deploy-AMDChipsetDriverOnWindowsServer.ps1):

          1) Download $Script:SdkInstallerUrl (fwlink, pinned in the
             global-constants block) to <WorkRoot>\cache\sdk\winsdksetup.exe.
             Reuse cache if already present.
          2) Run winsdksetup.exe with /features $Script:SdkInstallerOptionId
             (OptionId.SigningTools) /quiet /norestart.
          3) Defensive verify: a non-zero installer exit code with
             signtool.exe present afterwards is treated as
             "already installed" (warn-only). Only a missing signtool.exe
             after install is a hard failure.

        Returns the absolute path to the discovered signtool.exe so the
        caller does not need to re-invoke Resolve-SignToolExe.

    .OUTPUTS
        [string] - absolute path to signtool.exe

    .NOTES
        Network access is required. signtool.exe is part of the Windows
        SDK; only the SigningTools feature is installed, never the full SDK.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $cacheDir = Join-Path $Script:WorkRoot 'cache\sdk'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $exePath = Join-Path $cacheDir 'winsdksetup.exe'

    Write-Step ('SDK installer version : {0} (pinned)' -f $Script:SdkInstallerVersion)
    Write-Step ('SDK installer URL     : {0}' -f $Script:SdkInstallerUrl)
    Write-Step ('Cache path            : {0}' -f $exePath)
    Write-Step ('Feature               : {0}' -f $Script:SdkInstallerOptionId)

    if (Test-Path -LiteralPath $exePath) {
        $fi = Get-Item -LiteralPath $exePath
        Write-Step ('Reusing cached winsdksetup.exe ({0:N0} bytes)' -f $fi.Length)
    } else {
        Write-Step 'Downloading winsdksetup.exe from Microsoft Learn fwlink...'
        try {
            # Force TLS 1.2 for compatibility with older Server hosts
            $oldSp = [System.Net.ServicePointManager]::SecurityProtocol
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.SecurityProtocolType]::Tls12
            try {
                Invoke-WebRequest -Uri $Script:SdkInstallerUrl `
                                  -OutFile $exePath `
                                  -UseBasicParsing
            } finally {
                [System.Net.ServicePointManager]::SecurityProtocol = $oldSp
            }
        } catch {
            throw ('Windows SDK installer download failed: {0}' -f $_.Exception.Message)
        }
        if (-not (Test-Path -LiteralPath $exePath)) {
            throw 'Windows SDK installer download appeared to succeed but winsdksetup.exe is not present.'
        }
        $fi = Get-Item -LiteralPath $exePath
        Write-Ok ('winsdksetup.exe downloaded ({0:N0} bytes)' -f $fi.Length)
    }

    $installArgs = @(
        '/features', $Script:SdkInstallerOptionId,
        '/quiet',
        '/norestart'
    )
    Write-Step ('Running: winsdksetup.exe {0}' -f ($installArgs -join ' '))

    # psa-disable-next-line PSA3001 -- Start-Process -ArgumentList is the
    # canonical pattern for invoking installer EXEs with explicit args;
    # matches Install-WindowsAdkFallback and the SDK fallback in the
    # Deploy-AMDChipsetDriverOnWindowsServer.ps1 reference.
    $proc = Start-Process -FilePath $exePath `
                          -ArgumentList $installArgs `
                          -Wait -PassThru

    # Defensive verify by tool presence rather than trusting the exit
    # code (winsdksetup.exe can exit non-zero when the kit is already
    # on the machine).
    $signToolPath = Resolve-SignToolExe

    if ($signToolPath) {
        if ($proc.ExitCode -ne 0) {
            Write-Caution ('SDK installer exit code {0}; signtool.exe is present, treating as already installed.' -f $proc.ExitCode)
        }
        Write-Ok ('Windows SDK Signing Tools installed: {0}' -f $signToolPath)
        return $signToolPath
    }
    throw ('Windows SDK install failed (exit {0}); signtool.exe still not found.' -f $proc.ExitCode)
}

function New-BootableIso {
    <#
    .SYNOPSIS
        Build a UEFI + BIOS bootable ISO from an extracted-ISO folder
        using oscdimg, per the OSDBuilder New-OSDBuilderISO pattern.
    .DESCRIPTION
        Uses the bootdata "2#p0,e,b<bios>#pEF,e,b<uefi>" form. Volume
        label is restricted to 32 chars / ASCII.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$ExtractedIsoRoot,
        [Parameter(Mandatory)] [string]$OutputIsoPath,
        [Parameter(Mandatory)] [string]$VolumeLabel
    )
    Set-DebugStep -Step 'oscdimg-resolve-tools'
    $oscdimg  = Resolve-OscdimgExe
    $etfsboot = Resolve-EtfsbootCom -ExtractedIsoRoot $ExtractedIsoRoot
    $efisys   = Resolve-EfisysBin   -ExtractedIsoRoot $ExtractedIsoRoot

    # Sanitise label (oscdimg max 32 chars, ASCII subset)
    $label = $VolumeLabel
    if ($label.Length -gt 32) { $label = $label.Substring(0, 32) }

    $bootData = '2#p0,e,b{0}#pEF,e,b{1}' -f $etfsboot, $efisys
    $oscdimgArgs = @(
        '-m'
        '-o'
        '-u2'
        '-udfver102'
        ('-bootdata:' + $bootData)
        ('-l' + $label)
        $ExtractedIsoRoot
        $OutputIsoPath
    )

    $outDir = [System.IO.Path]::GetDirectoryName($OutputIsoPath)
    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Set-DebugStep -Step 'oscdimg-invoke'
    & $oscdimg @oscdimgArgs
    if ($LASTEXITCODE -ne 0) {
        throw ('oscdimg.exe failed with exit code {0}' -f $LASTEXITCODE)
    }
    if (-not (Test-Path -LiteralPath $OutputIsoPath)) {
        throw ('oscdimg.exe reported success but {0} was not created.' -f $OutputIsoPath)
    }
    return $OutputIsoPath
}

function New-SyntheticTestIso {
    <#
    .SYNOPSIS
        Build a tiny non-bootable ISO used by -SyntheticTestMode so CI
        can exercise the DISM + oscdimg pipeline without touching any
        Microsoft asset.
    .DESCRIPTION
        Captures a small text-file workspace into install.wim with
        /Compress:none, then wraps it in an ISO via oscdimg. The
        result is intentionally NOT bootable - the goal is to verify
        the plumbing, not to ship a usable installer.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$WorkRoot,
        [Parameter(Mandatory)] [string]$OutputIsoPath
    )
    $synthRoot = Join-Path $WorkRoot 'synthetic'
    $synthSrc  = Join-Path $synthRoot 'source'
    $synthIso  = Join-Path $synthRoot 'iso_root'
    $synthSources = Join-Path $synthIso 'sources'

    foreach ($d in @($synthRoot, $synthSrc, $synthIso, $synthSources)) {
        if (Test-Path -LiteralPath $d) {
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }

    # Minimal payload
    'This is a synthetic WIM for CI testing only. Not bootable.' |
        Out-File -LiteralPath (Join-Path $synthSrc 'README.txt') -Encoding ascii

    Set-DebugStep -Step 'synthetic-capture-wim'
    $installWim = Join-Path $synthSources 'install.wim'
    $capArgs = @('/Capture-Image', ('/ImageFile:' + $installWim), ('/CaptureDir:' + $synthSrc), '/Name:Synthetic_For_CI', '/Compress:none')
    $code = Invoke-DismCli -Arguments $capArgs -Context 'capture-synthetic'
    if ($code -ne 0) {
        throw ('dism /Capture-Image failed with exit code {0}' -f $code)
    }

    Set-DebugStep -Step 'synthetic-build-iso'
    # Bypass oscdimg (no ADK assumed); produce a raw archive ISO with
    # an external tool would be ideal, but for synthetic we just wrap
    # the WIM with Compress-Archive + rename so the pipeline can still
    # find install.wim under sources\.
    # However, when ADK IS available, prefer oscdimg for a true ISO.
    $oscdimgFound = $true
    try { Resolve-OscdimgExe | Out-Null } catch { $oscdimgFound = $false }
    if ($oscdimgFound) {
        # Create stub bootmgr/efi files to satisfy oscdimg layout (these
        # are NOT real boot files; the resulting ISO is non-bootable)
        $bootDir = Join-Path $synthIso 'boot'
        New-Item -ItemType Directory -Path $bootDir -Force | Out-Null
        'STUB' | Out-File -LiteralPath (Join-Path $bootDir 'etfsboot.com') -Encoding ascii
        $efiDir = Join-Path $synthIso 'efi\microsoft\boot'
        New-Item -ItemType Directory -Path $efiDir -Force | Out-Null
        'STUB' | Out-File -LiteralPath (Join-Path $efiDir 'efisys.bin') -Encoding ascii
        # NOTE: oscdimg may reject 4-byte boot file. If so, the
        # caller should treat this synthetic mode as best-effort.
        try {
            New-BootableIso -ExtractedIsoRoot $synthIso `
                -OutputIsoPath $OutputIsoPath -VolumeLabel 'SYNTH_IF'
        } catch {
            Write-Caution ('oscdimg failed on synthetic stub: {0}; falling back to raw copy.' -f $_.Exception.Message)
            Copy-Item -LiteralPath $installWim -Destination $OutputIsoPath -Force
        }
    } else {
        # ADK missing - copy the WIM as if it were the ISO. P11 verification
        # in -SyntheticTestMode tolerates this fallback shape.
        Copy-Item -LiteralPath $installWim -Destination $OutputIsoPath -Force
    }

    return $OutputIsoPath
}

# ============================================================
# 7-Zip helpers (ported from Deploy-AMDChipsetDriverOnWindowsServer.ps1)
# ============================================================
#
# These three helpers cooperate to locate or bootstrap 7-Zip, which is
# the Servicing Dependency Database parser's required CAB extractor
# (SPEC Part B.19.4). The function bodies are ported verbatim from the
# sister project except for two logger renames:
#   Write-Caution -> Write-Caution    (same role: yellow warning)
#   Write-Detail  -> Write-Step    (same role: informational output)
# The HTTP calls intentionally use the raw Invoke-WebRequest rather than
# this script's local Invoke-WebRequestWithRetry wrapper; the retry
# semantics are different (Deploy-AMD's pattern is short-circuit on the
# first tier that returns a parseable response) and aligning them is a
# task for a future revision (SPEC Part B.19.4 Implementation Notes).
#
# The decision to require 7-Zip rather than the in-box expand.exe is
# normative; see SPEC Part B.19.4.1 and the research article
# research/windows-servicing/windows-server-iso-update-mechanics.{en,ja}.md
# section 7.2 for the failure-mode evidence.

# >>> CANONICAL unit_id=pwsh.helper.get-sevenzippath version=1.0.0 hash=9fa5a18e04c0f6cb policy=canonical binding=follow-latest >>>
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

# >>> CANONICAL unit_id=pwsh.helper.get-latestsevenzipurl version=1.0.0 hash=df73d0c52090c978 policy=canonical binding=follow-latest >>>
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

# >>> CANONICAL unit_id=pwsh.helper.install-sevenzipfallback version=1.0.0 hash=60007e7fce5e614e policy=canonical binding=follow-latest >>>
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

# ============================================================
# JSON Canonical Serialization helpers
# ============================================================
#
# Repository-canonical JSON serializer with byte-level parity to the
# Python reference implementation in tests/common/canonical_json.py.
# The two implementations together let the data/*.json and
# tests/fixtures/*.json files be edited from either runtime
# (Linux Python 3.x, Linux PowerShell 7.x) without producing
# spurious git diffs from formatter quirks.
#
# ============================================================
# Canonical JSON serialization & parsing (SPEC Part B.23)
# ============================================================
#
# These helpers produce / consume the repository-canonical JSON format
# whose byte sequence matches tests/common/canonical_json.py for the same
# logical input, on BOTH Windows PowerShell 5.1 AND PowerShell 7.x.
#
# Why hand-rolled (no ConvertTo-Json / ConvertFrom-Json):
#   - ConvertTo-Json indentation differs between PS 5.1 (verbose, 2-space
#     after colon, deep indent) and PS 7.x (2-space indent, ": " sep), so
#     the same object serialised on different hosts produced different
#     bytes and broke the cross-runtime byte-match (PS 5.1 / 7.x / Python).
#   - ConvertFrom-Json auto-converts ISO-8601-looking strings to [datetime]
#     on PS 7.x (PS 5.1 keeps them as strings), losing the original textual
#     form (e.g. "+09:00" offsets) and corrupting values on round-trip.
# To get a single canonical byte stream across all three runtimes, both the
# writer and the reader are implemented from scratch here and used in place
# of the built-in cmdlets for all canonical data files (config-*.json,
# cache-*.json, etc.).
#
# Canonical format (SPEC Part B.23):
#   1. UTF-8 (no BOM)              6. Literal non-ASCII (no \uXXXX)
#   2. LF line endings            7. Insertion-order keys (no sort)
#   3. 2-space indentation        8. Exactly one trailing LF
#   4. ": " key/value separator   9. Null values emitted as "key": null
#   5. ",\n<indent>" array sep    10. Depth is caller-controlled

# >>> CANONICAL unit_id=pwsh.helper.convertto-canonicaljson version=1.0.0 hash=efedb9ecf58ea1b3 policy=canonical binding=follow-latest >>>
function ConvertTo-CanonicalJson {
    <#
    .SYNOPSIS
        Serialize an object to canonical JSON text (SPEC Part B.23), with
        byte output identical on PS 5.1 / 7.x / Python.
    .DESCRIPTION
        Hand-rolled serializer that does NOT call ConvertTo-Json, so the
        emitted bytes are independent of the PowerShell version's
        ConvertTo-Json formatting. Returns a string whose bytes match
        canonical_json_dumps() in tests/common/canonical_json.py for the
        same logical input.

        Accepted input: [ordered] hashtable, [pscustomobject], plain
        [hashtable] (key order then follows enumeration order; prefer
        ordered/pscustomobject for determinism), arrays, and the JSON
        primitives (string, integer, double, bool, $null). [datetime] /
        [datetimeoffset] values are emitted as UTC second-precision ISO-8601
        strings (yyyy-MM-ddTHH:mm:ssZ) as a safety net; the data pipeline
        itself stores dates as strings.
    .PARAMETER InputObject
        Object to serialize.
    .PARAMETER Depth
        Maximum nesting depth (default 20). Matches the Python -Depth.
    .PARAMETER IndentWidth
        Spaces per indent level (default 2).
    .PARAMETER NoTrailingNewline
        When set, the returned string ends without a final LF.
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position=0)] [AllowNull()] $InputObject,
        [Parameter()] [int] $Depth = 20,
        [Parameter()] [int] $IndentWidth = 2,
        [Parameter()] [switch] $NoTrailingNewline
    )
    if ($Depth -lt 1)       { throw "depth must be >= 1, got $Depth" }
    if ($IndentWidth -lt 1) { throw "indent_width must be >= 1, got $IndentWidth" }

    $sb = [System.Text.StringBuilder]::new()
    $indentUnit = ' ' * $IndentWidth
    _CanonicalJson_WriteValue -Value $InputObject -Depth 0 -MaxDepth $Depth -IndentUnit $indentUnit -Sb $sb
    $json = $sb.ToString()
    if (-not $NoTrailingNewline) { $json += "`n" }
    return $json
}
# <<< CANONICAL unit_id=pwsh.helper.convertto-canonicaljson <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writevalue version=1.0.0 hash=9e36066de2680f5f policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteValue {
    param($Value, [int]$Depth, [int]$MaxDepth, [string]$IndentUnit, [System.Text.StringBuilder]$Sb)

    if ($null -eq $Value) { [void]$Sb.Append('null'); return }

    if ($Value -is [bool]) { [void]$Sb.Append($(if ($Value) {'true'} else {'false'})); return }

    # DateTime safety net: pipeline stores dates as strings, but emit any
    # stray [datetime] in the same UTC ISO-8601 second form for stability.
    if ($Value -is [datetime]) {
        # Match the pipeline's own date formatting: ToUniversalTime().ToString('o')
        # (round-trip ISO-8601, 7-digit fractional seconds, 'Z' for UTC).
        $ic = [System.Globalization.CultureInfo]::InvariantCulture
        if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) {
            $utc = [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        } else {
            $utc = $Value.ToUniversalTime()
        }
        _CanonicalJson_WriteString -S ($utc.ToString('o', $ic)) -Sb $Sb
        return
    }
    if ($Value -is [System.DateTimeOffset]) {
        $ic = [System.Globalization.CultureInfo]::InvariantCulture
        _CanonicalJson_WriteString -S ($Value.UtcDateTime.ToString('o', $ic)) -Sb $Sb
        return
    }

    if ($Value -is [string] -or $Value -is [char]) {
        _CanonicalJson_WriteString -S ([string]$Value) -Sb $Sb; return
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or `
        $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [uint16] -or `
        $Value -is [uint32] -or $Value -is [uint64]) {
        [void]$Sb.Append([string]$Value); return
    }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        _CanonicalJson_WriteNumber -N $Value -Sb $Sb; return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if ($keys.Count -eq 0) { [void]$Sb.Append('{}'); return }
        $pairs = foreach ($k in $keys) { [pscustomobject]@{ K=[string]$k; V=$Value[$k] } }
        _CanonicalJson_WriteObject -Pairs @($pairs) -Depth $Depth -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { [void]$Sb.Append('[]'); return }
        _CanonicalJson_WriteArray -Items $items -Depth $Depth -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
        return
    }

    $props = @($Value.PSObject.Properties)
    if ($props.Count -eq 0) {
        if ($Value -is [System.Management.Automation.PSCustomObject]) { [void]$Sb.Append('{}') }
        else { _CanonicalJson_WriteString -S ([string]$Value) -Sb $Sb }
        return
    }
    $pairs = foreach ($p in $props) { [pscustomobject]@{ K=$p.Name; V=$p.Value } }
    _CanonicalJson_WriteObject -Pairs @($pairs) -Depth $Depth -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writevalue <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writeobject version=1.0.0 hash=5e9b78c9269b68cb policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteObject {
    param([object[]]$Pairs, [int]$Depth, [int]$MaxDepth, [string]$IndentUnit, [System.Text.StringBuilder]$Sb)
    if (($Depth + 1) -gt $MaxDepth) { throw "Object nests deeper than allowed depth ($MaxDepth); reached depth $($Depth + 1)." }
    $childIndent = $IndentUnit * ($Depth + 1)
    $closeIndent = $IndentUnit * $Depth
    [void]$Sb.Append("{`n")
    for ($i = 0; $i -lt $Pairs.Count; $i++) {
        [void]$Sb.Append($childIndent)
        _CanonicalJson_WriteString -S $Pairs[$i].K -Sb $Sb
        [void]$Sb.Append(': ')
        _CanonicalJson_WriteValue -Value $Pairs[$i].V -Depth ($Depth + 1) -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
        if ($i -lt $Pairs.Count - 1) { [void]$Sb.Append(',') }
        [void]$Sb.Append("`n")
    }
    [void]$Sb.Append($closeIndent); [void]$Sb.Append('}')
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writeobject <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writearray version=1.0.0 hash=7592ea486c2a8c1c policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteArray {
    param([object[]]$Items, [int]$Depth, [int]$MaxDepth, [string]$IndentUnit, [System.Text.StringBuilder]$Sb)
    if (($Depth + 1) -gt $MaxDepth) { throw "Object nests deeper than allowed depth ($MaxDepth); reached depth $($Depth + 1)." }
    $childIndent = $IndentUnit * ($Depth + 1)
    $closeIndent = $IndentUnit * $Depth
    [void]$Sb.Append("[`n")
    for ($i = 0; $i -lt $Items.Count; $i++) {
        [void]$Sb.Append($childIndent)
        _CanonicalJson_WriteValue -Value $Items[$i] -Depth ($Depth + 1) -MaxDepth $MaxDepth -IndentUnit $IndentUnit -Sb $Sb
        if ($i -lt $Items.Count - 1) { [void]$Sb.Append(',') }
        [void]$Sb.Append("`n")
    }
    [void]$Sb.Append($closeIndent); [void]$Sb.Append(']')
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writearray <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writestring version=1.0.0 hash=02854a7bf4fb707d policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteString {
    param([string]$S, [System.Text.StringBuilder]$Sb)
    [void]$Sb.Append('"')
    foreach ($ch in $S.ToCharArray()) {
        $code = [int]$ch
        switch ($code) {
            0x22 { [void]$Sb.Append('\"'); continue }
            0x5C { [void]$Sb.Append('\\'); continue }
            0x08 { [void]$Sb.Append('\b'); continue }
            0x09 { [void]$Sb.Append('\t'); continue }
            0x0A { [void]$Sb.Append('\n'); continue }
            0x0C { [void]$Sb.Append('\f'); continue }
            0x0D { [void]$Sb.Append('\r'); continue }
            default {
                if ($code -lt 0x20) { [void]$Sb.Append(('\u{0:x4}' -f $code)) }
                else { [void]$Sb.Append($ch) }
            }
        }
    }
    [void]$Sb.Append('"')
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writestring <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writenumber version=1.0.0 hash=fd7410b6e533b4cd policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteNumber {
    param($N, [System.Text.StringBuilder]$Sb)
    $ic = [System.Globalization.CultureInfo]::InvariantCulture
    if ($N -is [double] -or $N -is [single]) {
        $s = ([double]$N).ToString('R', $ic)
        # Python emits integer-valued floats with a trailing .0 (e.g. 100.0).
        if ($s -notmatch '[.eE]') { $s += '.0' }
    } else {
        $s = ([decimal]$N).ToString($ic)
    }
    $s = [System.Text.RegularExpressions.Regex]::Replace($s, '(?<=\d)E(?=[+\-]?\d)', 'e')
    [void]$Sb.Append($s)
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writenumber <<<

# >>> CANONICAL unit_id=pwsh.helper.save-canonicaljsonfile version=1.0.0 hash=8cac0388cc0b5da0 policy=canonical binding=follow-latest >>>
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

# >>> CANONICAL unit_id=pwsh.helper.convertfrom-canonicaljson version=1.0.0 hash=5a1072331d093c23 policy=canonical binding=follow-latest >>>
function ConvertFrom-CanonicalJson {
    <#
    .SYNOPSIS
        Parse JSON text into PowerShell objects WITHOUT ConvertFrom-Json.
    .DESCRIPTION
        Hand-rolled recursive-descent parser. Returns order-preserving
        [pscustomobject] for JSON objects, [object[]] for arrays, [string]
        for strings (dates are kept as strings, NOT converted to [datetime],
        so the original textual form survives a round-trip on every PS
        version), [long]/[double] for numbers, [bool], and $null.

        Behaviour matches Python json.loads for the inputs this project
        produces, and is identical on PS 5.1 and PS 7.x.
    .PARAMETER Json
        JSON text to parse.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        [AllowEmptyString()] [string] $Json
    )
    process {
        $state = @{ s = $Json; i = 0; n = $Json.Length }
        _CanonicalJson_SkipWs $state
        $result = _CanonicalJson_ParseValue $state
        _CanonicalJson_SkipWs $state
        if ($state.i -lt $state.n) { throw "Unexpected trailing content at position $($state.i)." }
        return $result
    }
}
# <<< CANONICAL unit_id=pwsh.helper.convertfrom-canonicaljson <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-skipws version=1.0.0 hash=fb17dca5e9c37829 policy=canonical binding=follow-latest >>>
function _CanonicalJson_SkipWs {
    param($State)
    $s = $State.s
    while ($State.i -lt $State.n) {
        $c = $s[$State.i]
        if ($c -eq ' ' -or $c -eq "`t" -or $c -eq "`n" -or $c -eq "`r") { $State.i++ }
        else { break }
    }
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-skipws <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsevalue version=1.0.0 hash=d4708a17197eae1f policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseValue {
    param($State)
    if ($State.i -ge $State.n) { throw "Unexpected end of input." }
    $c = $State.s[$State.i]
    if ($c -eq '{') { return _CanonicalJson_ParseObject $State }
    if ($c -eq '[') { return _CanonicalJson_ParseArray  $State }
    if ($c -eq '"') { return _CanonicalJson_ParseString $State }
    if ($c -eq '-' -or ($c -ge '0' -and $c -le '9')) { return _CanonicalJson_ParseNumber $State }
    if ($c -eq 't' -or $c -eq 'f') { return _CanonicalJson_ParseBool $State }
    if ($c -eq 'n') { return _CanonicalJson_ParseNull $State }
    throw "Unexpected character '$c' at position $($State.i)."
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsevalue <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parseobject version=1.0.0 hash=abf2dd1e42a261a2 policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseObject {
    param($State)
    $obj = [ordered]@{}
    $State.i++   # consume '{'
    _CanonicalJson_SkipWs $State
    if ($State.i -lt $State.n -and $State.s[$State.i] -eq '}') { $State.i++; return [pscustomobject]$obj }
    while ($true) {
        _CanonicalJson_SkipWs $State
        if ($State.s[$State.i] -ne '"') { throw "Expected string key at position $($State.i)." }
        $key = _CanonicalJson_ParseString $State
        _CanonicalJson_SkipWs $State
        if ($State.s[$State.i] -ne ':') { throw "Expected ':' at position $($State.i)." }
        $State.i++   # consume ':'
        _CanonicalJson_SkipWs $State
        $val = _CanonicalJson_ParseValue $State
        $obj[$key] = $val
        _CanonicalJson_SkipWs $State
        $c = $State.s[$State.i]
        if ($c -eq ',') { $State.i++; continue }
        if ($c -eq '}') { $State.i++; break }
        throw "Expected ',' or '}' at position $($State.i)."
    }
    return [pscustomobject]$obj
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parseobject <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsearray version=1.0.0 hash=07283971f638c8b0 policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseArray {
    param($State)
    $arr = [System.Collections.Generic.List[object]]::new()
    $State.i++   # consume '['
    _CanonicalJson_SkipWs $State
    if ($State.i -lt $State.n -and $State.s[$State.i] -eq ']') { $State.i++; return ,$arr.ToArray() }
    while ($true) {
        _CanonicalJson_SkipWs $State
        $val = _CanonicalJson_ParseValue $State
        [void]$arr.Add($val)
        _CanonicalJson_SkipWs $State
        $c = $State.s[$State.i]
        if ($c -eq ',') { $State.i++; continue }
        if ($c -eq ']') { $State.i++; break }
        throw "Expected ',' or ']' at position $($State.i)."
    }
    return ,$arr.ToArray()
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsearray <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsestring version=1.0.0 hash=c2adebf7aec2f1ee policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseString {
    param($State)
    $sb = [System.Text.StringBuilder]::new()
    $State.i++   # consume opening quote
    $s = $State.s
    while ($State.i -lt $State.n) {
        $c = $s[$State.i]; $State.i++
        if ($c -eq '"') { return $sb.ToString() }
        if ($c -eq '\') {
            if ($State.i -ge $State.n) { throw "Unterminated escape." }
            $e = $s[$State.i]; $State.i++
            switch ($e) {
                '"'  { [void]$sb.Append('"') }
                '\'  { [void]$sb.Append('\') }
                '/'  { [void]$sb.Append('/') }
                'b'  { [void]$sb.Append([char]0x08) }
                't'  { [void]$sb.Append([char]0x09) }
                'n'  { [void]$sb.Append([char]0x0A) }
                'f'  { [void]$sb.Append([char]0x0C) }
                'r'  { [void]$sb.Append([char]0x0D) }
                'u'  {
                    if ($State.i + 4 -gt $State.n) { throw "Bad \u escape." }
                    $hex = $s.Substring($State.i, 4); $State.i += 4
                    [void]$sb.Append([char][System.Convert]::ToInt32($hex, 16))
                }
                default { throw "Bad escape '\$e' at position $($State.i)." }
            }
        } else {
            [void]$sb.Append($c)
        }
    }
    throw "Unterminated string."
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsestring <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsenumber version=1.0.0 hash=0624198cd56a3e41 policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseNumber {
    param($State)
    $start = $State.i
    $s = $State.s
    if ($s[$State.i] -eq '-') { $State.i++ }
    while ($State.i -lt $State.n) {
        $c = $s[$State.i]
        if (($c -ge '0' -and $c -le '9') -or $c -eq '.' -or $c -eq 'e' -or $c -eq 'E' -or $c -eq '+' -or $c -eq '-') { $State.i++ }
        else { break }
    }
    $numStr = $s.Substring($start, $State.i - $start)
    $ic = [System.Globalization.CultureInfo]::InvariantCulture
    if ($numStr -notmatch '[.eE]') {
        $asLong = [long]0
        if ([long]::TryParse($numStr, [ref]$asLong)) { return $asLong }
        return [double]::Parse($numStr, $ic)
    }
    return [double]::Parse($numStr, [System.Globalization.NumberStyles]::Float, $ic)
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsenumber <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsebool version=1.0.0 hash=13b060dca910d5f7 policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseBool {
    param($State)
    $s = $State.s
    if ($State.i + 4 -le $State.n -and $s.Substring($State.i,4) -eq 'true')  { $State.i += 4; return $true }
    if ($State.i + 5 -le $State.n -and $s.Substring($State.i,5) -eq 'false') { $State.i += 5; return $false }
    throw "Invalid literal at position $($State.i)."
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsebool <<<

# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsenull version=1.0.0 hash=b1c867999c4d74bb policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseNull {
    param($State)
    $s = $State.s
    if ($State.i + 4 -le $State.n -and $s.Substring($State.i,4) -eq 'null') { $State.i += 4; return $null }
    throw "Invalid literal at position $($State.i)."
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsenull <<<

function Test-DataContractConsistency {
    <#
    .SYNOPSIS
        Cross-cutting data-quality gate: verify every data artifact carries the
        Script's shared data-contract identity (Id + Version).
    .DESCRIPTION
        The sub-project holds a single source of truth for its data contract in
        $Script:DataContractId (a stable family GUID) and
        $Script:DataContractVersion (an epoch bumped on any breaking shape
        change to any data model). Every generated artifact stamps both into
        its _meta, so a single pass validates the whole set rather than
        reconciling independent per-model versions.

        Per-artifact Status:
          Current - id matches and version equals the Script's epoch.
          Stale   - id matches but version is older, OR _meta is present but
                    unstamped (a pre-contract artifact); regenerate via the
                    relevant Refresh action.
          Refuse  - version is newer than this Script understands.
          Foreign - dataContractId is present but is not this family GUID.
          Unknown - file has no _meta (not a contract-bearing artifact).
        OverallStatus is the worst status across all inspected artifacts;
        Unknown does not worsen the overall result.
    .PARAMETER Path
        One or more *.json artifact paths to inspect. When omitted, the
        sub-project data directory is scanned for *.json files.
    .OUTPUTS
        [pscustomobject] with OverallStatus, Files (per-artifact detail),
        and Reasons.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Path = @()
    )

    $targets = New-Object 'System.Collections.Generic.List[string]'
    if ($Path -and $Path.Count -gt 0) {
        foreach ($p in $Path) {
            # A directory argument expands to its *.json files; a file argument
            # is taken as-is. This lets callers pass the data root directly.
            if (Test-Path -LiteralPath $p -PathType Container) {
                foreach ($f in (Get-ChildItem -LiteralPath $p -Filter '*.json' -File)) {
                    $targets.Add($f.FullName)
                }
            } else {
                $targets.Add($p)
            }
        }
    } else {
        $dataDir = Join-Path $Script:ScriptRoot 'data'
        if (Test-Path -LiteralPath $dataDir) {
            foreach ($f in (Get-ChildItem -LiteralPath $dataDir -Filter '*.json' -File)) {
                $targets.Add($f.FullName)
            }
        }
    }

    $rank = @{ 'Current' = 0; 'Unknown' = 0; 'Stale' = 2; 'Refuse' = 3; 'Foreign' = 3 }
    $files   = New-Object 'System.Collections.Generic.List[object]'
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    $worst   = 'Current'

    foreach ($t in $targets) {
        $status       = 'Unknown'
        $foundId      = $null
        $foundVersion = $null
        $reason       = $null
        if (-not (Test-Path -LiteralPath $t -PathType Leaf)) {
            $status = 'Foreign'
            $reason = 'file not found'
        } else {
            $doc = $null
            try {
                $doc = Get-Content -LiteralPath $t -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                $status = 'Foreign'
                $reason = 'not valid JSON'
            }
            if ($doc -and ($doc.PSObject.Properties.Name -contains '_meta')) {
                $meta         = $doc._meta
                $foundId      = $meta.dataContractId
                $foundVersion = $meta.dataContractVersion
                if (-not $foundId) {
                    $status = 'Stale'
                    $reason = 'unstamped (pre-contract) artifact; regenerate'
                } elseif ($foundId -ne $Script:DataContractId) {
                    $status = 'Foreign'
                    $reason = ('dataContractId {0} is not this family' -f $foundId)
                } elseif ($null -eq $foundVersion) {
                    $status = 'Stale'
                    $reason = 'no dataContractVersion; regenerate'
                } elseif ([int]$foundVersion -eq $Script:DataContractVersion) {
                    $status = 'Current'
                } elseif ([int]$foundVersion -lt $Script:DataContractVersion) {
                    $status = 'Stale'
                    $reason = ('dataContractVersion {0} < {1}; regenerate' -f $foundVersion, $Script:DataContractVersion)
                } else {
                    $status = 'Refuse'
                    $reason = ('dataContractVersion {0} > {1}; artifact newer than this script' -f $foundVersion, $Script:DataContractVersion)
                }
            } elseif ($doc) {
                $status = 'Unknown'
                $reason = 'no _meta (not a contract-bearing artifact)'
            }
        }
        if ($reason) { $reasons.Add(('{0}: {1}' -f (Split-Path -Leaf $t), $reason)) }
        $files.Add([pscustomobject]@{
            Path                = $t
            Status              = $status
            DataContractId      = $foundId
            DataContractVersion = $foundVersion
            Reason              = $reason
        })
        if ($rank[$status] -gt $rank[$worst]) { $worst = $status }
    }

    return [pscustomobject]@{
        OverallStatus = $worst
        Files         = $files.ToArray()
        Reasons       = $reasons.ToArray()
    }
}

# ============================================================
# PatchPlan engine
# ============================================================
# Converts a flat list of resolved patches into a target-aware
# PatchPlan that the build phases (P07 install.wim, P08 boot.wim
# / WinRE.wim) consume. Implements Microsoft's media-dynamic-update
# servicing sequence: each WIM target receives only the patches
# whose Type maps to that target via $Script:PatchTargetMap, and
# within each target the patches are sorted by ApplyOrder.
#
# Out of scope for this initial cut (tracked in CHANGELOG and SPEC):
#   * LCU twice-apply pattern around LP injection
#   * WinRE.wim mount/service/dismount worker
#   * Language Pack injection in P07
# This module establishes the structural contract; a later release
# fills in the WinRE worker and the LP-injection sequencing.

function Get-PatchTargetsForType {
    <#
    .SYNOPSIS
        Return the array of WIM targets that a given patch Type applies
        to, per $Script:PatchTargetMap.
    .DESCRIPTION
        Unknown Types fall back to ['Install'] with a one-time warning
        per unique Type seen in the current run. Caller must pre-set
        $Script:PatchTargetMap; this function does not validate it.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$PatchType)

    if (-not $PatchType) {
        return [string[]]@('Install')
    }
    if ($Script:PatchTargetMap.ContainsKey($PatchType)) {
        return [string[]]@($Script:PatchTargetMap[$PatchType])
    }
    # Unknown Type: warn once, fall back to Install
    if (-not $Script:PatchTargetMapWarned) {
        $Script:PatchTargetMapWarned = @{}
    }
    if (-not $Script:PatchTargetMapWarned.ContainsKey($PatchType)) {
        Write-Caution ("Unknown patch Type '{0}'; defaulting target=[Install]. Add this Type to PatchTargetMap to silence." -f $PatchType)
        $Script:PatchTargetMapWarned[$PatchType] = $true
    }
    return [string[]]@('Install')
}

function Build-PatchPlan {
    <#
    .SYNOPSIS
        Construct a PatchPlan object from a flat patch list.
    .DESCRIPTION
        The PatchPlan is a hashtable with keys for each WIM target
        (Install / Boot / WinRE / Setup); each value is an array of
        patch entries sorted by their ApplyOrder field. Patches whose
        Type maps to multiple targets appear in each target's list.

        Returned shape:
            @{
                Install = @(patch1, patch2, ...)
                Boot    = @(patch1, ...)
                WinRE   = @(patch1, patch3, ...)
                Setup   = @(patch5, ...)
                # Diagnostic / summary fields:
                _GeneratedAt    = '<ISO 8601 timestamp>'
                _PatchCount     = <int>
                _TargetCounts   = @{Install=N; Boot=N; WinRE=N; Setup=N}
                _UnknownTypes   = @(<list of unknown Types seen>)
            }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [array]$Patches
    )

    if (-not $Patches) { $Patches = @() }

    $plan = @{
        Install       = New-Object System.Collections.Generic.List[object]
        Boot          = New-Object System.Collections.Generic.List[object]
        WinRE         = New-Object System.Collections.Generic.List[object]
        Setup         = New-Object System.Collections.Generic.List[object]
        _GeneratedAt  = (Get-Date).ToString('o')
        _PatchCount   = 0
        _UnknownTypes = New-Object System.Collections.Generic.List[string]
    }

    foreach ($p in $Patches) {
        if (-not $p) { continue }
        # ResolvedPatches entries built by P02 use PatchType; raw
        # config-* PatchBaseline entries use Type. Get-PatchEntryType
        # normalises both shapes.
        $type = Get-PatchEntryType -Patch $p
        $targets = Get-PatchTargetsForType -PatchType $type
        if (-not $Script:PatchTargetMap.ContainsKey($type) -and -not [string]::IsNullOrEmpty($type)) {
            if ($plan._UnknownTypes -notcontains $type) {
                $plan._UnknownTypes.Add($type) | Out-Null
            }
        }
        foreach ($t in $targets) {
            $plan[$t].Add($p) | Out-Null
        }
        $plan._PatchCount++
    }

    # Sort each target list by ApplyOrder (ascending), then by KbId for stability
    foreach ($t in @('Install', 'Boot', 'WinRE', 'Setup')) {
        $sorted = @($plan[$t] | Sort-Object @{ Expression={ if ($_.PSObject.Properties['ApplyOrder']) { [int]$_.ApplyOrder } else { 99 } } }, @{ Expression='KbId' })
        $plan[$t] = $sorted
    }

    $plan['_TargetCounts'] = @{
        Install = $plan.Install.Count
        Boot    = $plan.Boot.Count
        WinRE   = $plan.WinRE.Count
        Setup   = $plan.Setup.Count
    }

    # Build the sub-phase sequences per Microsoft media-dynamic-update.
    # Each target gets a list of named sub-phases, each carrying its own
    # patch slice. Phase workers iterate the sub-phases in order.
    $plan['InstallSequence'] = Build-InstallApplySequence -InstallPatches $plan.Install
    $plan['BootSequence']    = Build-BootApplySequence    -BootPatches    $plan.Boot
    $plan['WinReSequence']   = Build-WinReApplySequence   -WinRePatches   $plan.WinRE

    return $plan
}

function Get-PatchEntryType {
    <#
    .SYNOPSIS
        Read the patch-kind/type string from a patch entry, preferring
        'PatchType' (P02/P03 ResolvedPatches, which reuse 'Kind' as an
        Iso/Patch input marker), then 'Kind' (raw Config Schema v3.0
        Lines[]), then the legacy 'Type' field.

        Returns an empty string when neither is set. PatchType takes
        precedence when both are present, mirroring the dual-field
        handling in Build-PatchPlan and Write-PatchPlanSummary.

        Centralised so that all five call sites (Build-PatchPlan,
        Write-PatchPlanSummary, Build-InstallApplySequence,
        Build-BootApplySequence, Build-WinReApplySequence) read the
        type field through one canonical helper instead of repeating
        the inline if/elseif chain - which had drifted between call
        sites in earlier revisions and caused sub-phase classification
        to silently produce empty buckets.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Patch)
    if (-not $Patch) { return '' }
    # Precedence: 'PatchType' (P02/P03 ResolvedPatches, which reuse 'Kind' as an
    # Iso/Patch input-source marker, so 'Kind' must NOT win for those) -> 'Kind'
    # (raw Config Schema v3.0 Lines[]: LCU/SSU/DotNet/SafeOSDU/SetupDU) -> 'Type'
    # (language-specific entries: LanguagePack/LXP/DotNet.LangPack).
    if ($Patch.PSObject.Properties['PatchType'] -and $Patch.PatchType) {
        return [string]$Patch.PatchType
    }
    if ($Patch.PSObject.Properties['Kind'] -and $Patch.Kind) {
        return [string]$Patch.Kind
    }
    if ($Patch.PSObject.Properties['Type'] -and $Patch.Type) {
        return [string]$Patch.Type
    }
    return ''
}

function Build-InstallApplySequence {
    <#
    .SYNOPSIS
        Convert the install.wim patch slice into Microsoft's official
        media-dynamic-update servicing sequence (7 sub-phases).
    .DESCRIPTION
        Per Microsoft's media-dynamic-update doc, install.wim is
        serviced in this order (mount once, traverse, dismount):

          I1. SSU                                (servicing stack first)
          I2. LanguagePack injection             (UI must be in place
                                                  before LCU)
          I3. LCU first pass                     (Microsoft requires
                                                  LCU AFTER LP because
                                                  LP can shadow files
                                                  delivered by LCU)
          I4. .NET CU                            (.NET 4.x updates)
          I5. DynamicUpdate.Component            (component-store DU)
          I6. (Cleanup + Export, handled by P07)
          I7. LCU second pass                    (re-applied because the
                                                  LP injection in I2
                                                  shadowed some LCU
                                                  payload files; only
                                                  required when LP was
                                                  actually injected)

        The returned object is an array of sub-phases, each describing
        its name, the patch slice it owns, and a 'RequiresRemount'
        flag that the worker uses to decide whether to re-mount the
        WIM between this sub-phase and the previous one.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$InstallPatches
    )
    # Bucket by Type
    $byType = @{}
    foreach ($p in $InstallPatches) {
        $t = Get-PatchEntryType -Patch $p
        if (-not $byType.ContainsKey($t)) { $byType[$t] = New-Object System.Collections.Generic.List[object] }
        $byType[$t].Add($p) | Out-Null
    }
    $ssu        = @(if ($byType.ContainsKey('SSU')) { $byType['SSU'] } else { @() })
    $lp         = @()
    if ($byType.ContainsKey('LanguagePack')) { $lp += $byType['LanguagePack'] }
    if ($byType.ContainsKey('LXP'))          { $lp += $byType['LXP'] }
    if ($byType.ContainsKey('DotNet.LangPack')) { $lp += $byType['DotNet.LangPack'] }
    $lcu        = @(if ($byType.ContainsKey('LCU')) { $byType['LCU'] } else { @() })
    $dotnet     = @(if ($byType.ContainsKey('DotNet')) { $byType['DotNet'] } else { @() })
    $dynUpComp  = @(if ($byType.ContainsKey('DynamicUpdate.Component')) { $byType['DynamicUpdate.Component'] } else { @() })

    $hasLp = ($lp.Count -gt 0)

    $sequence = New-Object System.Collections.Generic.List[object]
    $sequence.Add([pscustomobject]@{
        Name             = 'I1.SSU'
        Description      = 'Servicing Stack Update (must come first)'
        Patches          = $ssu
        RequiresRemount  = $false
    }) | Out-Null
    $sequence.Add([pscustomobject]@{
        Name             = 'I2.LanguagePack'
        Description      = 'Language Pack injection (UI must be in place before LCU)'
        Patches          = $lp
        RequiresRemount  = $false
    }) | Out-Null
    $sequence.Add([pscustomobject]@{
        Name             = 'I3.LCU.FirstPass'
        Description      = 'Cumulative Update (after LP per Microsoft media-dynamic-update)'
        Patches          = $lcu
        RequiresRemount  = $false
    }) | Out-Null
    $sequence.Add([pscustomobject]@{
        Name             = 'I4.DotNet'
        Description      = '.NET Framework Cumulative Update'
        Patches          = $dotnet
        RequiresRemount  = $false
    }) | Out-Null
    $sequence.Add([pscustomobject]@{
        Name             = 'I5.DynamicUpdate.Component'
        Description      = 'Component-store Dynamic Update'
        Patches          = $dynUpComp
        RequiresRemount  = $false
    }) | Out-Null
    # I6: Component Cleanup + Export are handled by P07's mount-scope
    # finalisation, not as a Patches-bearing sub-phase. Modelled here
    # as a marker entry so the worker can hook in.
    $sequence.Add([pscustomobject]@{
        Name             = 'I6.CleanupAndExport'
        Description      = 'DISM /Cleanup-Image + Export-WindowsImage'
        Patches          = @()
        RequiresRemount  = $false
        IsCleanupMarker  = $true
    }) | Out-Null
    # I7: LCU second pass. Only emit when LP was actually injected,
    # since the official Microsoft rationale for the second pass is
    # "language-pack injection shadows some LCU files".
    if ($hasLp -and $lcu.Count -gt 0) {
        $sequence.Add([pscustomobject]@{
            Name             = 'I7.LCU.SecondPass'
            Description      = 'LCU re-applied (LP shadowed first-pass LCU files)'
            Patches          = $lcu
            RequiresRemount  = $true
        }) | Out-Null
    }
    return $sequence.ToArray()
}

function Build-BootApplySequence {
    <#
    .SYNOPSIS
        Convert the boot.wim patch slice into the documented servicing
        sub-phases (SSU -> LP -> LCU).
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$BootPatches
    )
    $byType = @{}
    foreach ($p in $BootPatches) {
        $t = Get-PatchEntryType -Patch $p
        if (-not $byType.ContainsKey($t)) { $byType[$t] = New-Object System.Collections.Generic.List[object] }
        $byType[$t].Add($p) | Out-Null
    }
    $ssu = @(if ($byType.ContainsKey('SSU')) { $byType['SSU'] } else { @() })
    $lp  = @()
    if ($byType.ContainsKey('LanguagePack')) { $lp += $byType['LanguagePack'] }
    $lcu = @(if ($byType.ContainsKey('LCU')) { $byType['LCU'] } else { @() })

    $seq = New-Object System.Collections.Generic.List[object]
    $seq.Add([pscustomobject]@{ Name='B1.SSU'; Description='SSU'; Patches=$ssu; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='B2.LanguagePack'; Description='Language Pack'; Patches=$lp; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='B3.LCU'; Description='LCU'; Patches=$lcu; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='B4.CleanupAndExport'; Description='Cleanup + Export'; Patches=@(); RequiresRemount=$false; IsCleanupMarker=$true }) | Out-Null
    return $seq.ToArray()
}

function Build-WinReApplySequence {
    <#
    .SYNOPSIS
        Convert the WinRE.wim patch slice into the documented servicing
        sub-phases (SSU -> LP -> SafeOS DU).

        WinRE is NOT serviced with LCU - the Safe OS DU is the
        Microsoft-supported equivalent. WinRE also does NOT need a
        twice-apply pass because there is no LCU in the sequence to
        be shadowed by the language pack.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$WinRePatches
    )
    $byType = @{}
    foreach ($p in $WinRePatches) {
        $t = Get-PatchEntryType -Patch $p
        if (-not $byType.ContainsKey($t)) { $byType[$t] = New-Object System.Collections.Generic.List[object] }
        $byType[$t].Add($p) | Out-Null
    }
    $ssu     = @(if ($byType.ContainsKey('SSU')) { $byType['SSU'] } else { @() })
    $lp      = @()
    if ($byType.ContainsKey('LanguagePack')) { $lp += $byType['LanguagePack'] }
    $safeOs  = @(if ($byType.ContainsKey('SafeOSDU')) { $byType['SafeOSDU'] } else { @() })

    $seq = New-Object System.Collections.Generic.List[object]
    $seq.Add([pscustomobject]@{ Name='W1.SSU'; Description='SSU (or combined LCU surrogate)'; Patches=$ssu; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='W2.LanguagePack'; Description='Recovery UI language pack'; Patches=$lp; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='W3.SafeOsDU'; Description='Safe OS Dynamic Update (WinRE-only LCU substitute)'; Patches=$safeOs; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='W4.CleanupAndExport'; Description='Cleanup + Export /Compress:Recovery'; Patches=@(); RequiresRemount=$false; IsCleanupMarker=$true }) | Out-Null
    return $seq.ToArray()
}

function Write-PatchPlanSummary {
    <#
    .SYNOPSIS
        Emit a human-readable summary of a PatchPlan to the standard
        Write-Step log surface, including the per-target sub-phase
        sequences if present.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Plan
    )
    Write-Step ('PatchPlan: {0} patches across {1} targets' -f $Plan._PatchCount, $Plan._TargetCounts.Count)
    foreach ($t in @('Install', 'Boot', 'WinRE', 'Setup')) {
        $count = $Plan._TargetCounts[$t]
        if ($count -gt 0) {
            $names = ($Plan[$t] | ForEach-Object {
                $kb = if ($_.KbId) { $_.KbId } else { '<no-kb>' }
                # Get-PatchEntryType returns '' when neither PatchType nor
                # Type is set; substitute '?' for the human-readable view.
                $ty = Get-PatchEntryType -Patch $_
                if ([string]::IsNullOrEmpty($ty)) { $ty = '?' }
                "{0}/{1}" -f $ty, $kb
            }) -join ', '
            Write-Step ('  {0,-7} ({1}): {2}' -f $t, $count, $names)
        } else {
            Write-Step ('  {0,-7} (0): (empty)' -f $t)
        }
    }
    if ($Plan._UnknownTypes -and $Plan._UnknownTypes.Count -gt 0) {
        Write-Caution ('Unknown Types in plan (defaulted to Install): {0}' -f ($Plan._UnknownTypes -join ', '))
    }
    # Sub-phase sequences (if any)
    foreach ($seqName in @('InstallSequence','BootSequence','WinReSequence')) {
        if ($Plan.ContainsKey($seqName) -and $Plan[$seqName] -and $Plan[$seqName].Count -gt 0) {
            Write-Step ('  {0}:' -f $seqName)
            foreach ($sp in $Plan[$seqName]) {
                $patchCount = if ($sp.Patches) { @($sp.Patches).Count } else { 0 }
                $marker = if ($sp.PSObject.Properties['IsCleanupMarker'] -and $sp.IsCleanupMarker) { ' [cleanup]' } else { '' }
                $remount = if ($sp.RequiresRemount) { ' [REMOUNT]' } else { '' }
                Write-Step ('    {0,-24} ({1} patch(es)){2}{3}' -f $sp.Name, $patchCount, $marker, $remount)
            }
        }
    }
}

function Test-PatchServicingReadinessOnMount {
    <#
    .SYNOPSIS
        Pre-apply servicing-readiness check on the mounted image (A-3).
    .DESCRIPTION
        For every patch in $PatchesToApply whose RequiresKbIds is
        non-empty, verify via Get-WindowsPackage that each required KB
        is already present in the mounted image's package store. The
        check runs in declaration order; a patch P's prerequisites
        must be satisfied BEFORE P is added to the image.

        Policy is governed by $Script:PatchDependencyPolicy:
          'Strict' -> throw on any missing prerequisite (default)
          'Warn'   -> Write-Caution and continue

        Returns $true if all prerequisites are satisfied (or warned
        through); throws on Strict-mode failure. Designed to be called
        from inside the per-WIM apply loop just after Mount-WindowsImage
        and just before the first Add-WindowsPackage call.

        Implementation note: Get-WindowsPackage returns one row per
        package; the relevant identifier for our purposes is the
        "PackageIdentity" string. KB ids embedded in the patch
        manifest typically match the PackageIdentity prefix
        (e.g. "Package_for_KB5037591~..."), so we substring-match
        rather than relying on exact equality.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$MountPath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$PatchesToApply,
        [string]$ImageLabel = 'image'
    )

    # Collect candidate prerequisites
    $prereqMap = @{}    # KbId -> [string]
    foreach ($p in $PatchesToApply) {
        if (-not $p) { continue }
        if ($p.PSObject.Properties['RequiresKbIds'] -and $p.RequiresKbIds) {
            foreach ($req in @($p.RequiresKbIds)) {
                $reqStr = [string]$req
                if (-not [string]::IsNullOrEmpty($reqStr) -and -not $prereqMap.ContainsKey($reqStr)) {
                    $prereqMap[$reqStr] = ($p.KbId | Out-String).Trim()
                }
            }
        }
    }
    if ($prereqMap.Count -eq 0) {
        Write-Step ('Dependency closure ({0}): no RequiresKbIds declared; skipping.' -f $ImageLabel)
        return $true
    }

    Write-Step ('Dependency closure ({0}): {1} prerequisite KB(s) declared.' -f $ImageLabel, $prereqMap.Count)

    # In DryRun mode we cannot enumerate Get-WindowsPackage; skip with a notice
    if ($Script:DryRun) {
        Write-Step ('  DryRun: skipping Get-WindowsPackage probe of {0}' -f $MountPath)
        return $true
    }

    $installedPackages = @()
    try {
        $installedPackages = @(Invoke-DismCmdlet -CommandName 'Get-WindowsPackage' -Parameters @{ Path = $MountPath; ErrorAction = 'Stop' })
    } catch {
        $msg = ('Get-WindowsPackage failed on {0}: {1}' -f $MountPath, $_.Exception.Message)
        if ($Script:PatchDependencyPolicy -eq 'Strict') {
            throw $msg
        } else {
            Write-Caution $msg
            return $false
        }
    }
    $installedIds = @($installedPackages | ForEach-Object { [string]$_.PackageIdentity })

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($reqKb in $prereqMap.Keys) {
        $found = $false
        foreach ($packageId in $installedIds) {
            if ($packageId -like ("*{0}*" -f $reqKb)) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            $needyKb = $prereqMap[$reqKb]
            $missing.Add(('  required {0} (needed by {1}) NOT FOUND in {2}' -f $reqKb, $needyKb, $ImageLabel)) | Out-Null
        }
    }

    if ($missing.Count -eq 0) {
        Write-Ok ('Dependency closure ({0}): all {1} prerequisite(s) satisfied.' -f $ImageLabel, $prereqMap.Count)
        return $true
    }

    $detail = ($missing -join "`n")
    if ($Script:PatchDependencyPolicy -eq 'Strict') {
        throw ("Dependency closure check failed for {0}; aborting before Add-WindowsPackage to avoid DISM 0x800f0823.`n{1}" -f $ImageLabel, $detail)
    }
    Write-Caution ('Dependency closure ({0}): {1} unsatisfied prerequisite(s); continuing (policy=Warn).' -f $ImageLabel, $missing.Count)
    Write-Caution $detail
    return $false
}

function Invoke-PatchSubPhase {
    <#
    .SYNOPSIS
        Apply one sub-phase of an Install / Boot / WinRE servicing
        sequence against a mounted WIM. Returns the array of per-patch
        result rows the caller appends to its run log.
    .DESCRIPTION
        For each patch in $SubPhase.Patches:
          1. If $Script:DryRun: log 'Planned' and continue.
          2. Otherwise call Add-WindowsPackageWithRetry -PackagePath.
          3. Record outcome (Success / Fail) + elapsed seconds.

        Cleanup-marker sub-phases (IsCleanupMarker = $true) skip the
        Add-WindowsPackage loop entirely; the caller is expected to
        run DISM /Cleanup-Image and Export-WindowsImage separately
        after the marker.

        This helper does NOT mount or dismount the WIM. The caller
        owns the mount lifetime so the same image can flow through
        multiple sub-phases without round-tripping the filesystem.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)] [pscustomobject]$SubPhase,
        [Parameter(Mandatory)] [string]$MountPath,
        [Parameter(Mandatory)] [string]$ImageLabel
    )
    $rows = New-Object System.Collections.Generic.List[object]
    $isCleanupMarker = $SubPhase.PSObject.Properties['IsCleanupMarker'] -and $SubPhase.IsCleanupMarker

    if ($isCleanupMarker) {
        Write-Step ('  Sub-phase {0,-24} [cleanup marker; caller will run DISM /Cleanup-Image]' -f $SubPhase.Name)
        return $rows.ToArray()
    }

    $patches = @($SubPhase.Patches)
    if ($patches.Count -eq 0) {
        Write-Step ('  Sub-phase {0,-24} (no patches; skipping)' -f $SubPhase.Name)
        return $rows.ToArray()
    }

    Write-Step ('  Sub-phase {0,-24} ({1} patch(es)) on {2}' -f $SubPhase.Name, $patches.Count, $ImageLabel)

    foreach ($p in $patches) {
        if (-not $p) { continue }
        $pkgPath = if ($p.PSObject.Properties['LocalPath']) { [string]$p.LocalPath } else { '' }
        $kb      = if ($p.PSObject.Properties['KbId'])      { [string]$p.KbId }      else { '?' }
        # Get-PatchEntryType normalises PatchType / Type field naming;
        # display '?' when neither field is populated.
        $type    = Get-PatchEntryType -Patch $p
        if ([string]::IsNullOrEmpty($type)) { $type = '?' }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $status = 'Planned'
        $errMsg = ''

        if ($Script:DryRun) {
            Write-Step ('    [DryRun] would apply {0}/{1} ({2})' -f $type, $kb, [System.IO.Path]::GetFileName($pkgPath))
            $sw.Stop()
            $rows.Add([pscustomobject]@{
                SubPhase     = $SubPhase.Name
                ImageLabel   = $ImageLabel
                PatchType    = $type
                KbId         = $kb
                FilePath     = $pkgPath
                ApplyStatus  = 'Planned'
                ElapsedSec   = $sw.Elapsed.TotalSeconds
            }) | Out-Null
            continue
        }

        if (-not $pkgPath -or -not (Test-Path -LiteralPath $pkgPath)) {
            $sw.Stop()
            $errMsg = ('LocalPath missing or empty for {0}/{1}; cannot apply' -f $type, $kb)
            Write-Caution ('    [skip] ' + $errMsg)
            $rows.Add([pscustomobject]@{
                SubPhase     = $SubPhase.Name
                ImageLabel   = $ImageLabel
                PatchType    = $type
                KbId         = $kb
                FilePath     = $pkgPath
                ApplyStatus  = 'Skip'
                ElapsedSec   = $sw.Elapsed.TotalSeconds
                Error        = $errMsg
            }) | Out-Null
            continue
        }

        Set-DebugStep -Step ('add-pkg:{0}:{1}' -f $SubPhase.Name, $kb)
        Write-Step ('    Applying {0}/{1} ({2})' -f $type, $kb, [System.IO.Path]::GetFileName($pkgPath))
        try {
            $status = Add-WindowsPackageWithRetry -MountPath $MountPath `
                -PackagePath $pkgPath -LogDir $Script:LogsDir
            Write-Ok ('      status={0}' -f $status)
        } catch {
            $errMsg = $_.Exception.Message
            $status = 'Fail'
            Add-ErrorJsonlEntry -Phase 'P07' -Kind 'sub-phase-failure' -Properties @{
                exType   = $_.Exception.GetType().FullName
                msg      = $errMsg
                subPhase = $SubPhase.Name
                image    = $ImageLabel
                kb       = $kb
                type     = $type
            }
            $sw.Stop()
            $rows.Add([pscustomobject]@{
                SubPhase     = $SubPhase.Name
                ImageLabel   = $ImageLabel
                PatchType    = $type
                KbId         = $kb
                FilePath     = $pkgPath
                ApplyStatus  = 'Fail'
                ElapsedSec   = $sw.Elapsed.TotalSeconds
                Error        = $errMsg
            }) | Out-Null
            throw
        }
        $sw.Stop()
        $rows.Add([pscustomobject]@{
            SubPhase     = $SubPhase.Name
            ImageLabel   = $ImageLabel
            PatchType    = $type
            KbId         = $kb
            FilePath     = $pkgPath
            ApplyStatus  = $status
            ElapsedSec   = $sw.Elapsed.TotalSeconds
        }) | Out-Null
    }
    return $rows.ToArray()
}

# ============================================================
# Supersedence-based patch deduplication
# ============================================================
# When the Catalogue search for a single patch Type returns multiple
# narrowed candidates (typically: preview + final for the same month,
# or carry-over candidates from an earlier month that the OS-aware
# query partially matched), we use the per-candidate Supersedes /
# SupersededBy data already gathered via Get-SupersedenceFromCatalog
# to keep only the newest survivor.
#
# Design notes:
#   * Get-SupersedenceFromCatalog populates Supersedes (this update
#     replaces these KB IDs) and SupersededBy (this update is replaced
#     by these KB IDs) for a given UpdateId via the Catalogue's
#     ScopedViewInline.aspx page.
#   * We exclude any candidate whose KbId appears in another
#     candidate's Supersedes list - that candidate is, by definition,
#     superseded by the other.
#   * If after the exclusion pass we still have multiple survivors
#     (Microsoft's Catalogue is occasionally inconsistent), we sort
#     descending by Title and pick the first - Catalogue titles begin
#     with the year-month prefix (e.g. "2026-05 Cumulative Update for
#     ...") so lexicographic descending sort correlates with newest.
#     The remaining non-winners are emitted with "Ambiguous; chose
#     newest by title" so the operator sees what happened.

function Get-KbIdFromUpdateTitle {
    <#
    .SYNOPSIS
        Extract the KB id (e.g. "KB5037591") from a Catalogue update
        title. Returns an empty string if no KB id pattern is found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Title)
    if (-not $Title) { return '' }
    $m = [regex]::Match($Title, '\((KB\d{6,7})\)')
    if ($m.Success) {
        return $m.Groups[1].Value
    }
    return ''
}

function Get-KbIdFromPatchFileName {
    <#
    .SYNOPSIS
        Extract the KB id from a Microsoft patch file name
        (e.g. "windows10.0-kb5087066-x64-ndp48_086eed6e...msu"
              -> "KB5087066").
    .DESCRIPTION
        Microsoft Update Catalogue often wraps multiple individual KBs
        under a single "umbrella" Title KB. Example: the May 2026 .NET
        Framework cumulative update for Server 2019 is exposed as
        "KB5088864 (umbrella)" with two attached .msu files for
        .NET 4.8 (KB5087066) and .NET 4.8.1 (KB5087061).

        For the PatchBaseline entry to reflect the actual file content,
        each entry's KbId must come from the file name, not from the
        umbrella Title. This helper does exactly that: it scans the
        file name for the standard "kb#######" token (case-insensitive)
        and returns it in upper-case canonical form. Returns an empty
        string if no kb token is present.

        Standard Microsoft file-name patterns this helper recognises:
          - windows10.0-kb5087537-x64_...msu
          - windows10.0-kb5087066-x64-ndp48_...msu
          - windows11.0-kb5043080-x64_...msu
          - windows11.0-kb5087588-x64_...cab    (SafeOS DU)

        If the file name does not contain a kb token (rare, but
        possible for some Dynamic Update payloads), the caller should
        fall back to the umbrella Title KB.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$FileName)
    if (-not $FileName) { return '' }
    $m = [regex]::Match($FileName, '(?i)kb(\d{6,7})')
    if ($m.Success) {
        return 'KB' + $m.Groups[1].Value
    }
    return ''
}

function Select-LatestPatchBySupersedence {
    <#
    .SYNOPSIS
        Apply supersedence-based deduplication to a list of candidate
        patches.

    .DESCRIPTION
        Input: an array of candidate patch entries, each carrying the
        UpdateId, Title, KbId, Supersedes, and SupersededBy fields
        populated by Get-SupersedenceFromCatalog.

        Output: a hashtable with two keys:
            Best     : the single surviving candidate
            Excluded : array of pscustomobjects, one per excluded
                       candidate, with Type / Candidate / SupersededBy
                       / Reason fields suitable for CSV emission.

        When Candidates has 0 entries:
            Best = $null, Excluded = @()
        When Candidates has 1 entry:
            Best = that one, Excluded = @()
        When Candidates has 2+:
            Exclusion pass first (drop candidates that appear in
            another candidate's Supersedes). If exactly one survivor:
            Best = survivor. If multiple survivors: sort descending
            by Title and pick first; mark the rest as ambiguous.

        Matching: a candidate C is considered "superseded by" another
        candidate D if C's KbId OR C's UpdateId is found (as a
        substring) in D's Supersedes array. We accept substring match
        because Catalogue Supersedes entries sometimes contain only
        the KB number, sometimes the full UpdateId, and sometimes a
        free-form "Package_for_KBnnnn~..." identifier.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Candidates,
        [string]$TypeLabel = '<unspecified>'
    )

    $result = @{
        Best     = $null
        Excluded = @()
    }

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return $result
    }
    if ($Candidates.Count -eq 1) {
        $result.Best = $Candidates[0]
        return $result
    }

    $excluded = New-Object System.Collections.Generic.List[object]
    $remaining = New-Object System.Collections.Generic.List[object]

    foreach ($c in $Candidates) {
        $cKbId   = if ($c.PSObject.Properties['KbId'] -and $c.KbId) {
            [string]$c.KbId
        } else {
            Get-KbIdFromUpdateTitle -Title ([string]$c.Title)
        }
        $cUpdateId = if ($c.PSObject.Properties['UpdateId']) { [string]$c.UpdateId } else { '' }

        $isSuperseded  = $false
        $supersededBy  = $null
        $matchedToken  = ''

        foreach ($other in $Candidates) {
            if ([Object]::ReferenceEquals($other, $c)) { continue }
            $otherSupersedes = @()
            if ($other.PSObject.Properties['Supersedes'] -and $other.Supersedes) {
                $otherSupersedes = @($other.Supersedes)
            }
            foreach ($supItem in $otherSupersedes) {
                $supStr = [string]$supItem
                if ([string]::IsNullOrWhiteSpace($supStr)) { continue }
                # Match either by KbId or by UpdateId (substring)
                $hit = $false
                if (-not [string]::IsNullOrEmpty($cKbId)   -and $supStr.IndexOf($cKbId,   [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; $matchedToken = $cKbId }
                if (-not $hit -and -not [string]::IsNullOrEmpty($cUpdateId) -and $supStr.IndexOf($cUpdateId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; $matchedToken = $cUpdateId }
                if ($hit) {
                    $isSuperseded = $true
                    $supersededBy = $other
                    break
                }
            }
            if ($isSuperseded) { break }
        }

        if ($isSuperseded) {
            $excluded.Add([pscustomobject]@{
                Type             = $TypeLabel
                Candidate        = $c
                ExcludedKbId     = $cKbId
                ExcludedTitle    = [string]$c.Title
                SupersededByKbId = if ($supersededBy.PSObject.Properties['KbId']) { [string]$supersededBy.KbId } else { Get-KbIdFromUpdateTitle -Title ([string]$supersededBy.Title) }
                SupersededByTitle = [string]$supersededBy.Title
                MatchedToken     = $matchedToken
                Reason           = ('Superseded by ' + [string]$supersededBy.Title)
            }) | Out-Null
        } else {
            $remaining.Add($c) | Out-Null
        }
    }

    if ($remaining.Count -eq 1) {
        $result.Best = $remaining[0]
        $result.Excluded = $excluded.ToArray()
        return $result
    }
    if ($remaining.Count -gt 1) {
        # Ambiguous: sort by Title desc (Catalogue titles begin with
        # YYYY-MM so lexicographic desc correlates with newest).
        $sorted = @($remaining | Sort-Object @{ Expression = { [string]$_.Title } } -Descending)
        $best = $sorted[0]
        for ($i = 1; $i -lt $sorted.Count; $i++) {
            $loser = $sorted[$i]
            $loserKbId = if ($loser.PSObject.Properties['KbId'] -and $loser.KbId) {
                [string]$loser.KbId
            } else {
                Get-KbIdFromUpdateTitle -Title ([string]$loser.Title)
            }
            $bestKbId = if ($best.PSObject.Properties['KbId'] -and $best.KbId) {
                [string]$best.KbId
            } else {
                Get-KbIdFromUpdateTitle -Title ([string]$best.Title)
            }
            $excluded.Add([pscustomobject]@{
                Type             = $TypeLabel
                Candidate        = $loser
                ExcludedKbId     = $loserKbId
                ExcludedTitle    = [string]$loser.Title
                SupersededByKbId = $bestKbId
                SupersededByTitle = [string]$best.Title
                MatchedToken     = ''
                Reason           = 'Ambiguous; chose newest by title'
            }) | Out-Null
        }
        $result.Best = $best
        $result.Excluded = $excluded.ToArray()
        return $result
    }

    # All candidates excluded each other (shouldn't normally happen).
    # Fall back to the first input candidate and log a warning.
    Write-Caution ('Supersedence dedup: all {0} {1} candidates marked superseded; falling back to first input.' -f $Candidates.Count, $TypeLabel)
    $result.Best = $Candidates[0]
    $result.Excluded = $excluded.ToArray()
    return $result
}

# ============================================================
# Secure Boot / PCA2023 helpers
# ------------------------------------------------------------
# These helpers underpin P10 ConvertPca2023BootManager and P12
# VerifyPca2023Readiness. They are organised as:
#
#   1. Get-LcuVersionFromInstallWim         - which LCU level is in the WIM
#   2. Get-WimSystemHiveValue               - read SOFTWARE/SYSTEM hive
#                                             offline via 'reg load'
#   3. Test-Pca2023AuthenticodeChain        - verify bootx64.efi signer
#   4. Get-IsoBootCertReadiness             - assemble per-ISO inventory
#   5. Get-Pca2023ReadinessSnapshot         - top-level snapshot +
#                                             Health (Healthy / Warning /
#                                             Critical / Unknown) + Reasons
#   6. Show-Pca2023ReadinessSnapshot        - console renderer with -Compact
#   7. Format-Pca2023ReadinessForReport     - StringBuilder text formatter
#   8. Get-OrEnsurePca2023Snapshot          - idempotent cache accessor
#   9. Convert-WimBootToPca2023Signed       - PSA-clean re-implementation
#                                             of Microsoft's Copy-2023BootBins
#
# Design pattern source: Deploy-Drivers-For-WindowsServer's Secure Boot
# baseline machinery (Get-SecureBootCertificateInventory family).
# Adapted for offline ISO analysis - the upstream queries the live
# host UEFI variables and registry, which are not available when
# inspecting an ISO file. Our equivalent reads the offline
# install.wim / boot.wim WIM-internal SYSTEM hive via 'reg load' for
# the same per-machine SecureBoot servicing data, and inspects the
# Authenticode signer chain on efi/boot/bootx64.efi for the firmware-
# layer cert identity.
#
# Locale-independence note: parsed values are compared as English
# tokens ('Updated', 'NotStarted', etc.) because the SecureBoot
# Servicing registry values are locale-independent. We do NOT use
# schtasks.exe-style approaches that emit localized CSV headers on
# ja-JP Windows (see SPEC.md D.22 for the design background).
# ============================================================

function Get-LcuVersionFromInstallWim {
    <#
    .SYNOPSIS
        Determine which LCU month an install.wim or boot.wim image carries.

        Returns a pscustomobject with:
          .Available     - $true if Get-WindowsPackage succeeded
          .ErrorMessage  - reason string when not available
          .HighestKbId   - newest detected LCU KB id (e.g. "KB5043050")
          .HighestKbDate - ISO date of that KB (best-effort parse of
                           KB metadata; may be $null)
          .MeetsPca2023Prereq - $true if any LCU date >= 2024-04-09
                                (the Make2023BootableMedia.ps1 prereq)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$MountPath
    )

    $result = [pscustomobject]@{
        Available           = $false
        ErrorMessage        = $null
        HighestKbId         = $null
        HighestKbDate       = $null
        MeetsPca2023Prereq  = $null
    }

    # The PCA2023 prereq date (2024-4B = Microsoft April 2024 LCU
    # release, which Microsoft published on 2024-04-09).
    $prereqDate = [DateTime]::Parse('2024-04-09')

    try {
        $packages = Invoke-DismCmdlet -CommandName 'Get-WindowsPackage' -Parameters @{ Path = $MountPath; ErrorAction = 'Stop' }
    } catch {
        $result.ErrorMessage = ('Get-WindowsPackage failed: {0}' -f $_.Exception.Message)
        return $result
    }

    # Filter for "Package_for_KB######" entries, which are the LCU
    # packages. We track the highest install-date timestamp.
    $highestDate = $null
    $highestKb   = $null
    foreach ($pkg in $packages) {
        $name = "$($pkg.PackageName)"
        if ($name -match 'Package_for_KB(\d{6,7})') {
            $kbId = ('KB{0}' -f $matches[1])
            $installTime = $pkg.InstallTime
            if ($installTime -and ($null -eq $highestDate -or $installTime -gt $highestDate)) {
                $highestDate = $installTime
                $highestKb   = $kbId
            }
        }
    }
    $result.HighestKbId   = $highestKb
    $result.HighestKbDate = $highestDate
    $result.MeetsPca2023Prereq = if ($highestDate) { $highestDate -ge $prereqDate } else { $false }
    $result.Available = $true
    return $result
}

function Get-WimSystemHiveValue {
    <#
    .SYNOPSIS
        Load an offline SYSTEM hive from a mounted WIM and read one value.

        Uses 'reg.exe load' to mount the WIM's
        \Windows\System32\config\SYSTEM file under
        HKLM\WIMSYSTEM_$Tag (a transient hive name), reads the
        named value with Get-ItemProperty, then unloads the hive.

        Returns $null if the hive could not be loaded OR the value
        does not exist; never throws. Hive unload is best-effort
        (cleanup happens even on error to avoid leaking mounted
        registry state across phase boundaries).

        This helper exists because the live-host equivalent in the
        reference Deploy-Drivers script
        (Get-SecureBootCertificateInventory) reads HKLM:\
        directly. For ISO analysis we have to mount the WIM's
        hive first.
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory)] [string]$WimMountPath,
        [Parameter(Mandatory)] [string]$RelativeRegPath,  # e.g. 'ControlSet001\Control\SecureBoot\Servicing'
        [Parameter(Mandatory)] [string]$ValueName,
        [string]$Tag = ('UPDWSI{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
    )

    $hivePath = Join-Path $WimMountPath 'Windows\System32\config\SYSTEM'
    if (-not (Test-Path -LiteralPath $hivePath)) {
        return $null
    }

    $mountKey = ('HKLM\WIMSYSTEM_{0}' -f $Tag)
    $psPath   = ('HKLM:\WIMSYSTEM_{0}\{1}' -f $Tag, $RelativeRegPath)

    $loaded = $false
    try {
        # reg.exe writes to stderr on success too, hence 2>&1. The
        # captured output is discarded; success is determined by
        # $LASTEXITCODE alone.
        $null = & reg.exe load $mountKey $hivePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        $loaded = $true
        try {
            $rv = Get-ItemProperty -Path $psPath -Name $ValueName -ErrorAction Stop
            return $rv.$ValueName
        } catch {
            return $null
        }
    } finally {
        if ($loaded) {
            try {
                # Force GC to release any registry handles before unload
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                $null = & reg.exe unload $mountKey 2>&1
            } catch {
                # Best-effort cleanup; will be retried on next reboot
            } # psa-disable-line PSA3004 -- intentional best-effort cleanup; the hive will be auto-unloaded on next reboot
        }
    }
}

function Get-SignToolEmbeddedClass {
    <#
    .SYNOPSIS
        Classify a PE file's EMBEDDED Authenticode signatures as PCA2023 /
        PCA2011 using `signtool verify /v /all /pa` (enumerates every embedded
        signature incl. nested co-signatures; embedded-only, revocation not
        checked - offline analysis). Complements the catalog-following
        Get-AuthenticodeSignature path, which under-reports the LCU-materialized
        PCA2023 boot manager (SPEC.md B.16.3 / B.22.22).

    .OUTPUTS
        [pscustomobject] .Parsed .IsPca2023 .IsPca2011 .SigCount .Error
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$SignTool,
        [Parameter(Mandatory)] [string]$Path
    )
    $res = [pscustomobject]@{
        Parsed    = $false
        IsPca2023 = $false
        IsPca2011 = $false
        SigCount  = 0
        Error     = $null
    }
    try {
        # signtool exits non-zero on an untrusted chain; capture stdout
        # regardless of exit code so the enumerated signatures are still read.
        $raw  = & $SignTool verify /v /all /pa $Path 2>&1
        $text = ($raw | Out-String)
    } catch {
        $res.Error = ('signtool invocation failed: {0}' -f $_.Exception.Message)
        return $res
    }
    $lines = @($text -split "`r?`n")
    # Collect 'Issued to:' subjects across all 'Signature Index:' blocks and
    # count the signatures. Plain arrays only (no generic List, no
    # [bool](collection) cast: both threw ArgumentException on the host
    # PowerShell during the S1 diagnosis).
    $tokens = @()
    foreach ($line in $lines) {
        $mTo = [regex]::Match($line, 'Issued to:\s*(.+?)\s*$')
        if ($mTo.Success) { $tokens += ($mTo.Groups[1].Value.Trim()) }
        if ([regex]::IsMatch($line, 'Signature Index:\s*\d+')) { $res.SigCount++ }
    }
    if ($res.SigCount -eq 0 -and $tokens.Count -gt 0) { $res.SigCount = 1 }
    foreach ($t in $tokens) {
        if ($t -match 'Windows UEFI CA 2023') { $res.IsPca2023 = $true }
        if ($t -match 'PCA 2011')             { $res.IsPca2011 = $true }
    }
    if ($tokens.Count -gt 0) {
        $res.Parsed = $true
    } elseif ($text -match 'No signature found' -or $text -match 'is not signed') {
        $res.Error = 'signtool: file is not embedded-signed (may be catalog-signed only).'
    } else {
        $res.Error = 'signtool produced no parseable signature block.'
    }
    return $res
}

function Get-ResolvedSignToolExe {
    <#
    .SYNOPSIS
        Resolve signtool.exe for embedded-signature inspection, acquiring the
        Windows SDK Signing Tools on first use if it is absent (SPEC.md
        B.22.22). Memoized in $Script:ResolvedSignToolExe so resolution and the
        one-time auto-install are attempted at most once per run.

    .OUTPUTS
        [string] absolute path to signtool.exe, or $null if unavailable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($null -ne $Script:ResolvedSignToolExe) {
        # Already attempted this run ('' means tried-and-unavailable).
        return $(if ($Script:ResolvedSignToolExe) { $Script:ResolvedSignToolExe } else { $null })
    }

    $exe = Resolve-SignToolExe
    if (-not $exe) {
        # Not present -> one-time auto-install (mirrors the 7-Zip / ADK
        # acquire-if-missing policy). Failure is non-fatal: the caller falls
        # back to Get-AuthenticodeSignature.
        try {
            $exe = Install-WindowsSdkFallback
        } catch {
            Write-Caution ('signtool.exe unavailable and auto-install failed: {0}. Falling back to Get-AuthenticodeSignature (catalog-path reads may under-report PCA2023; see SPEC.md B.22.22).' -f $_.Exception.Message)
            $exe = $null
        }
    }
    $Script:ResolvedSignToolExe = if ($exe) { $exe } else { '' }
    return $exe
}

function Test-Pca2023AuthenticodeChain {
    <#
    .SYNOPSIS
        Inspect the Authenticode signature on a UEFI boot file and
        report whether it is signed via 'Windows UEFI CA 2023' or the
        legacy 'Windows Production PCA 2011' / 'Microsoft Windows
        Production PCA 2011' chain.

        Returns a pscustomobject:
          .Available     - $true if Get-AuthenticodeSignature ran
          .ErrorMessage  - reason string when not available
          .SignerName    - leaf signer CN (e.g. 'Microsoft Windows')
          .RootChain     - root cert subject CN
          .ChainTokens   - array of subject CNs walking the chain
          .IsPca2023     - $true when 'Windows UEFI CA 2023' appears
          .IsPca2011     - $true when '*PCA 2011' appears
          .Method        - which method set the 2023/2011 verdict:
                           'signtool /v /all /pa (embedded)' (preferred)
                           or 'X509Chain (Get-AuthenticodeSignature)'.

        The 2023/2011 verdict prefers the EMBEDDED signature read by
        signtool '/v /all /pa'. Get-AuthenticodeSignature + X509Chain
        follows the catalog / cross-cert path, which under-reports the
        LCU-materialized PCA2023 boot manager (SPEC.md B.16.3); signtool
        reads the embedded signature directly. signtool.exe is acquired
        on first use (SPEC.md B.22.22); when it is unavailable the
        X509Chain verdict stands and .Method records that. The leaf
        SignerName / RootChain / ChainTokens always come from X509Chain.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    $result = [pscustomobject]@{
        Available     = $false
        ErrorMessage  = $null
        SignerName    = $null
        RootChain     = $null
        ChainTokens   = @()
        IsPca2023     = $false
        IsPca2011     = $false
        Method        = 'X509Chain (Get-AuthenticodeSignature)'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $result.ErrorMessage = ('File not found: {0}' -f $Path)
        return $result
    }

    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    } catch {
        $result.ErrorMessage = ('Get-AuthenticodeSignature failed: {0}' -f $_.Exception.Message)
        return $result
    }
    if ($sig.Status -eq 'NotSigned') {
        $result.ErrorMessage = 'File is not Authenticode-signed.'
        return $result
    }

    $result.Available  = $true
    $result.SignerName = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }

    # Walk the chain via X509Chain so we see every CA, not just the leaf
    $tokens = New-Object System.Collections.Generic.List[string]
    try {
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = 'NoCheck'  # offline analysis
        $null = $chain.Build($sig.SignerCertificate)
        foreach ($element in $chain.ChainElements) {
            $cn = $element.Certificate.Subject
            if ($cn) { $tokens.Add($cn) | Out-Null }
        }
    } catch {
        # Chain build failed; we still have leaf info
    } # psa-disable-line PSA3004 -- best-effort chain walk; leaf info is sufficient for the signer-class decision

    $result.ChainTokens = @($tokens)
    if ($tokens.Count -gt 0) {
        $result.RootChain = $tokens[$tokens.Count - 1]
    }
    foreach ($t in $tokens) {
        if ($t -match 'Windows UEFI CA 2023') { $result.IsPca2023 = $true }
        if ($t -match 'PCA 2011')             { $result.IsPca2011 = $true }
    }
    # Also check the leaf signer name itself (for media where chain
    # build fails but signer subject is informative)
    if (-not $result.IsPca2023 -and $result.SignerName -match 'Windows UEFI CA 2023') {
        $result.IsPca2023 = $true
    }

    # Prefer the EMBEDDED signature for the 2023/2011 verdict. The X509Chain
    # walk above follows the catalog / cross-cert path, which under-reports the
    # LCU-materialized PCA2023 boot manager: for a file whose embedded signature
    # is 'Windows UEFI CA 2023' it can report 'Windows Production PCA 2011'
    # (SPEC.md B.16.3). signtool '/v /all /pa' reads the embedded signature(s)
    # directly; it is acquired on first use (SPEC.md B.22.22). When signtool is
    # unavailable the X509 verdict stands.
    $signTool = Get-ResolvedSignToolExe
    if ($signTool) {
        $embedded = Get-SignToolEmbeddedClass -SignTool $signTool -Path $Path
        if ($embedded.Parsed) {
            $result.IsPca2023 = $embedded.IsPca2023
            $result.IsPca2011 = $embedded.IsPca2011
            $result.Method    = 'signtool /v /all /pa (embedded)'
        }
    }
    return $result
}

function Get-IsoBootCertReadiness {
    <#
    .SYNOPSIS
        Inspect an extracted ISO directory (the staged-media folder
        produced by P05 ExpandIso) and assemble the per-ISO
        readiness inventory used by P12 VerifyPca2023Readiness.

        This is a STRICTLY READ-ONLY function. Side effects are
        limited to a transient 'reg load' (immediately unloaded)
        and a transient Mount-WindowsImage in READ-ONLY mode.

        Returns a rich pscustomobject - see SPEC.md D.22 for the
        field-by-field schema documentation.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$ExtractedMediaPath,
        [string]$WorkRoot
    )

    $inv = [pscustomobject]@{
        Source                     = 'IsoEmbedded'
        Generated                  = (Get-Date)
        Available                  = $false
        ErrorMessage               = $null
        ExtractedMediaPath         = $ExtractedMediaPath
        # File-existence checks (the 2024-4B prerequisite signal)
        HasEfiExDir                = $null
        HasBootMgrFwEx             = $null
        HasBootMgrEx               = $null
        HasFontsEx                 = $null
        HasDvdEx                   = $null
        HasEfisysExBin             = $null
        # Boot manager Authenticode signer chain
        BootX64SignerName          = $null
        BootX64IsPca2023           = $null
        BootX64IsPca2011           = $null
        BootX64ChainTokens         = @()
        BootX64Available           = $false
        # LCU level integrated in install.wim (read via Get-WindowsPackage)
        InstallWimHighestKb        = $null
        InstallWimHighestKbDate    = $null
        InstallWimMeetsPca2023Prereq = $null
        # LCU level integrated in boot.wim
        BootWimHighestKb           = $null
        BootWimHighestKbDate       = $null
        BootWimMeetsPca2023Prereq  = $null
        # SecureBoot servicing keys read from install.wim's SYSTEM hive
        UEFICA2023Status           = $null
        UEFICA2023Error            = $null
        AvailableUpdatesHex        = $null
    }

    # ---- File-existence checks ----
    # These are the markers Microsoft's Make2023BootableMedia.ps1
    # uses to decide that media has the 2024-4B-or-later updates.
    $bootWimPath = Join-Path $ExtractedMediaPath 'sources\boot.wim'
    if (-not (Test-Path -LiteralPath $bootWimPath)) {
        $inv.ErrorMessage = ('boot.wim not found under {0}\sources' -f $ExtractedMediaPath)
        return $inv
    }
    Write-Step ('  [1/4] Mounting boot.wim idx 1 read-only ...')

    # We mount boot.wim index 1 READ-ONLY (boot environment, not WinPE)
    # to inspect Windows\Boot\EFI_EX / FONTS_EX / DVD_EX directories
    $bootMount = if ($WorkRoot) {
        Join-Path $WorkRoot ('mnt_bootwim_pca2023_ro_{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
    } else {
        Join-Path ([System.IO.Path]::GetTempPath()) ('mnt_bootwim_pca2023_ro_{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
    }
    try {
        if (-not (Test-Path -LiteralPath $bootMount)) {
            New-Item -ItemType Directory -Path $bootMount -Force | Out-Null
        }
        $mountedRo = $false
        $stepStart = Get-Date
        try {
            $null = Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters @{ ImagePath = $bootWimPath; Index = 1; Path = $bootMount; ReadOnly = $true; ErrorAction = 'Stop' }
            $mountedRo = $true
            $stepElapsed = [int](New-TimeSpan -Start $stepStart -End (Get-Date)).TotalSeconds
            Write-Step ('         boot.wim mounted ({0}s); inspecting EFI_EX / FONTS_EX / DVD_EX ...' -f $stepElapsed)
            $exBins   = Join-Path $bootMount 'Windows\Boot\EFI_EX'
            $exFonts  = Join-Path $bootMount 'Windows\Boot\FONTS_EX'
            $exDvd    = Join-Path $bootMount 'Windows\Boot\DVD_EX'
            $inv.HasEfiExDir    = Test-Path -LiteralPath $exBins
            $inv.HasFontsEx     = Test-Path -LiteralPath $exFonts
            $inv.HasDvdEx       = Test-Path -LiteralPath $exDvd
            $inv.HasBootMgrFwEx = if ($inv.HasEfiExDir) { Test-Path -LiteralPath (Join-Path $exBins 'bootmgfw_EX.efi') } else { $false }
            $inv.HasBootMgrEx   = if ($inv.HasEfiExDir) { Test-Path -LiteralPath (Join-Path $exBins 'bootmgr_EX.efi')   } else { $false }
            $inv.HasEfisysExBin = if ($inv.HasDvdEx) {
                Test-Path -LiteralPath (Join-Path $exDvd 'EFI\en-US\efisys_EX.bin')
            } else { $false }

            # boot.wim level (LCU month detection)
            Write-Step '         enumerating boot.wim installed packages (Get-WindowsPackage) ...'
            $pkgStart = Get-Date
            $bootLcu = Get-LcuVersionFromInstallWim -MountPath $bootMount
            $pkgElapsed = [int](New-TimeSpan -Start $pkgStart -End (Get-Date)).TotalSeconds
            Write-Step ('         boot.wim LCU level resolved ({0}s): highest KB = {1}' -f $pkgElapsed, $(if ($bootLcu.HighestKbId) { $bootLcu.HighestKbId } else { '(none)' }))
            $inv.BootWimHighestKb         = $bootLcu.HighestKbId
            $inv.BootWimHighestKbDate     = $bootLcu.HighestKbDate
            $inv.BootWimMeetsPca2023Prereq = $bootLcu.MeetsPca2023Prereq
        } finally {
            if ($mountedRo) {
                Write-Step '  [2/4] Dismounting boot.wim (discard) ...'
                $dismountStart = Get-Date
                try {
                    $null = Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path = $bootMount; Discard = $true; ErrorAction = 'Stop' }
                    $dismountElapsed = [int](New-TimeSpan -Start $dismountStart -End (Get-Date)).TotalSeconds
                    Write-Step ('         boot.wim dismounted ({0}s)' -f $dismountElapsed)
                } catch {
                    # Best-effort cleanup
                } # psa-disable-line PSA3004 -- best-effort dismount; the WIM will be auto-released when the process exits
            }
            try {
                if (Test-Path -LiteralPath $bootMount) {
                    Remove-Item -Path $bootMount -Recurse -Force -ErrorAction Stop
                }
            } catch {
                # Mount directory cleanup best-effort
            } # psa-disable-line PSA3004 -- best-effort cleanup; the temp dir will be auto-released eventually
        }
    } catch {
        $inv.ErrorMessage = ('boot.wim inspection failed: {0}' -f $_.Exception.Message)
        return $inv
    }

    # ---- bootx64.efi Authenticode chain check ----
    Write-Step '         Inspecting bootx64.efi Authenticode signer chain ...'
    $bootX64 = Join-Path $ExtractedMediaPath 'efi\boot\bootx64.efi'
    if (Test-Path -LiteralPath $bootX64) {
        $authResult = Test-Pca2023AuthenticodeChain -Path $bootX64
        if ($authResult.Available) {
            $inv.BootX64Available  = $true
            $inv.BootX64SignerName = $authResult.SignerName
            $inv.BootX64IsPca2023  = $authResult.IsPca2023
            $inv.BootX64IsPca2011  = $authResult.IsPca2011
            $inv.BootX64ChainTokens = @($authResult.ChainTokens)
            Write-Step ('         bootx64.efi signer: {0}' -f $authResult.SignerName)
        }
    }

    # ---- install.wim LCU level + SYSTEM hive SecureBoot keys ----
    $installWimPath = Join-Path $ExtractedMediaPath 'sources\install.wim'
    if (Test-Path -LiteralPath $installWimPath) {
        Write-Step ('  [3/4] Mounting install.wim idx 1 read-only ...')
        $installMount = if ($WorkRoot) {
            Join-Path $WorkRoot ('mnt_installwim_pca2023_ro_{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
        } else {
            Join-Path ([System.IO.Path]::GetTempPath()) ('mnt_installwim_pca2023_ro_{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
        }
        try {
            if (-not (Test-Path -LiteralPath $installMount)) {
                New-Item -ItemType Directory -Path $installMount -Force | Out-Null
            }
            $iwMounted = $false
            $iwMountStart = Get-Date
            try {
                $null = Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters @{ ImagePath = $installWimPath; Index = 1; Path = $installMount; ReadOnly = $true; ErrorAction = 'Stop' }
                $iwMounted = $true
                $iwMountElapsed = [int](New-TimeSpan -Start $iwMountStart -End (Get-Date)).TotalSeconds
                Write-Step ('         install.wim mounted ({0}s); enumerating installed packages ...' -f $iwMountElapsed)
                $iwPkgStart = Get-Date
                $installLcu = Get-LcuVersionFromInstallWim -MountPath $installMount
                $iwPkgElapsed = [int](New-TimeSpan -Start $iwPkgStart -End (Get-Date)).TotalSeconds
                Write-Step ('         install.wim LCU level resolved ({0}s): highest KB = {1}' -f $iwPkgElapsed, $(if ($installLcu.HighestKbId) { $installLcu.HighestKbId } else { '(none)' }))
                $inv.InstallWimHighestKb         = $installLcu.HighestKbId
                $inv.InstallWimHighestKbDate     = $installLcu.HighestKbDate
                $inv.InstallWimMeetsPca2023Prereq = $installLcu.MeetsPca2023Prereq

                # SYSTEM hive servicing keys
                Write-Step '         reading SYSTEM hive SecureBoot servicing keys ...'
                $servPath = 'ControlSet001\Control\SecureBoot\Servicing'
                $inv.UEFICA2023Status = Get-WimSystemHiveValue -WimMountPath $installMount -RelativeRegPath $servPath -ValueName 'UEFICA2023Status'
                $inv.UEFICA2023Error  = Get-WimSystemHiveValue -WimMountPath $installMount -RelativeRegPath $servPath -ValueName 'UEFICA2023Error'
                $auRaw = Get-WimSystemHiveValue -WimMountPath $installMount -RelativeRegPath 'ControlSet001\Control\SecureBoot' -ValueName 'AvailableUpdates'
                if ($null -ne $auRaw) {
                    $inv.AvailableUpdatesHex = ('0x{0:X}' -f [int]$auRaw)
                }
            } finally {
                if ($iwMounted) {
                    Write-Step '  [4/4] Dismounting install.wim (discard) ...'
                    $iwDismountStart = Get-Date
                    try {
                        $null = Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path = $installMount; Discard = $true; ErrorAction = 'Stop' }
                        $iwDismountElapsed = [int](New-TimeSpan -Start $iwDismountStart -End (Get-Date)).TotalSeconds
                        Write-Step ('         install.wim dismounted ({0}s)' -f $iwDismountElapsed)
                    } catch {
                        # Best-effort cleanup
                    } # psa-disable-line PSA3004 -- best-effort dismount; the WIM will be auto-released when the process exits
                }
                try {
                    if (Test-Path -LiteralPath $installMount) {
                        Remove-Item -Path $installMount -Recurse -Force -ErrorAction Stop
                    }
                } catch {
                    # Mount directory cleanup best-effort
                } # psa-disable-line PSA3004 -- best-effort cleanup; the temp dir will be auto-released eventually
            }
        } catch {
            # install.wim mount failed - not fatal; we already have
            # boot.wim level data, which is sufficient for PCA2023 readiness.
            # Record but don't abort.
        } # psa-disable-line PSA3004 -- intentional best-effort cleanup; boot.wim level data is the authoritative input for PCA2023 readiness
    }

    $inv.Available = $true
    return $inv
}

function Test-OutputIsoPca2023Readiness {
    <#
    .SYNOPSIS
        Verify an extracted OUTPUT-ISO directory against the five
        conversion targets defined by Microsoft's
        Make2023BootableMedia.ps1 v1.6.4-signed / commit bd7abe3 (Copy-2023BootBins).

        This function performs no DISM mounts and no registry hive
        loads; it inspects a fixed set of paths under the extracted
        media tree. Signer classification uses the shared
        Test-Pca2023AuthenticodeChain helper, which prefers the embedded
        signature read by signtool /v /all /pa and falls back to
        Get-AuthenticodeSignature (SPEC.md B.17.2). signtool.exe is
        acquired on first use if absent (SPEC.md B.22.22), so the
        function is otherwise read-only.

        Complementary to Get-IsoBootCertReadiness:
          - Get-IsoBootCertReadiness  : inspects the INPUT (pre-P10)
                                        media state via boot.wim mount.
          - Test-OutputIsoPca2023Readiness : inspects the OUTPUT
                                        (post-P10) media state via
                                        direct file checks on the
                                        extracted ISO root.

        Microsoft's upstream Make2023BootableMedia.ps1 performs file
        copy only (zero Get-AuthenticodeSignature / signtool calls in
        the 1141-line script); signature verification is by design
        left to the caller. This function is an upstream-compatible
        quality extension that codifies the five Microsoft conversion
        targets as a single Pass / PassWithNotes / Warning / Fail
        verdict.

    .OUTPUTS
        pscustomobject with fields:
          .Available     [bool]     - whether the check could be run
          .ErrorMessage  [string]   - reason string when not available
          .OverallStatus [string]   - 'Pass' / 'PassWithNotes' /
                                      'Warning' / 'Fail' / 'Unknown'
          .TargetChecks  [object[]] - array of per-target pscustomobject:
              .Label, .Path, .ExpectedSignature, .ActualSignature,
              .IsPca2023, .IsPca2011, .Status, .Notes
          .Reasons       [string[]] - human-readable bullets summarising
                                      the non-Pass findings, always
                                      ending with a SCOPE clarifier

        Status mapping (per SPEC.md B.18 and r07.0-followups.md):
          Target #1 (\efi\boot\bootx64.efi or bootaa64.efi)
              PCA2023 -> Pass; PCA2011 -> Fail; missing -> Fail
          Target #2 (\bootmgr.efi)
              any signature or missing -> PassWithNotes
              (Microsoft design; see SPEC B.16.3)
          Target #3 (\efi\microsoft\boot\efisys_ex.bin)
              present -> Pass; missing -> Fail
          Target #4 (\efi\microsoft\boot\fonts\*.ttf)
              present -> Pass; missing or empty -> Warning
          Target #5 (\EFI\Microsoft\Boot\boot.stl)
              present -> Pass; missing -> PassWithNotes

        OverallStatus aggregation: any Fail -> Fail; else any Warning
        -> Warning; else any PassWithNotes -> PassWithNotes; else Pass.

    .NOTES
        SCOPE: file presence + primary signer-chain only. Actual boot
        behaviour on firmware with PCA2011 revoked from DBX is NOT
        verified here. Manual boot test on hardware or a Hyper-V Gen2
        VM with a custom Secure Boot template that revokes PCA2011 in
        DBX is required before production deployment.

        Implementation note: follows the Get-IsoBootCertReadiness
        pattern verbatim (declare $result pscustomobject once at entry,
        mutate properties, convert internal lists to arrays at exit)
        to avoid PowerShell type-inference traps. List[object] holding
        pscustomobject items must be materialised with .ToArray() not
        @(); see the inline comment near the function exit.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$ExtractedMediaPath
    )

    $result = [pscustomobject]@{
        Generated     = (Get-Date)
        Available     = $false
        ErrorMessage  = $null
        ExtractedMediaPath = $ExtractedMediaPath
        OverallStatus = 'Unknown'
        TargetChecks  = @()
        Reasons       = @()
    }

    if (-not (Test-Path -LiteralPath $ExtractedMediaPath)) {
        $result.ErrorMessage = ('ExtractedMediaPath does not exist: {0}' -f $ExtractedMediaPath)
        $result.OverallStatus = 'Fail'
        $result.Reasons = @(('ExtractedMediaPath does not exist: {0}' -f $ExtractedMediaPath))
        return $result
    }

    # Resolve UEFI critical path. Per Microsoft's spec the destination
    # is bootx64.efi on x64 builds or bootaa64.efi on ARM64 builds.
    # We try x64 first (the Server 2016+ default); fall back to ARM64
    # only when x64 is absent. The error message references whichever
    # was probed last, so an x64-only ISO with neither present reports
    # the x64 path.
    $bootx64Path   = Join-Path $ExtractedMediaPath 'efi\boot\bootx64.efi'
    $bootaa64Path  = Join-Path $ExtractedMediaPath 'efi\boot\bootaa64.efi'
    $criticalPath  = $bootx64Path
    $criticalLabel = '\efi\boot\bootx64.efi'
    if (-not (Test-Path -LiteralPath $bootx64Path) -and (Test-Path -LiteralPath $bootaa64Path)) {
        $criticalPath  = $bootaa64Path
        $criticalLabel = '\efi\boot\bootaa64.efi'
    }
    $bootMgrEfiPath = Join-Path $ExtractedMediaPath 'bootmgr.efi'
    $efisysExPath   = Join-Path $ExtractedMediaPath 'efi\microsoft\boot\efisys_ex.bin'
    $fontsDir       = Join-Path $ExtractedMediaPath 'efi\microsoft\boot\fonts'
    $bootStlPath    = Join-Path $ExtractedMediaPath 'EFI\Microsoft\Boot\boot.stl'

    $checks  = New-Object System.Collections.Generic.List[object]
    $reasons = New-Object System.Collections.Generic.List[string]

    # ---- Target #1: UEFI critical path (bootx64.efi / bootaa64.efi) ----
    if (Test-Path -LiteralPath $criticalPath) {
        $chain1    = Test-Pca2023AuthenticodeChain -Path $criticalPath
        $actualSig = if ($chain1.IsPca2023) { 'PCA2023' }
                     elseif ($chain1.IsPca2011) { 'PCA2011' }
                     else { 'unknown' }
        $status1 = 'Fail'
        $notes1  = $null
        if ($chain1.IsPca2023) {
            $status1 = 'Pass'
            $notes1  = 'UEFI Secure Boot critical path is signed via the "Windows UEFI CA 2023" chain.'
        } elseif ($chain1.IsPca2011) {
            $notes1  = 'UEFI Secure Boot critical path is still PCA2011-signed. ISO will not boot on firmware where PCA2011 has been revoked from DBX.'
        } else {
            $notes1  = ('UEFI critical path signature could not be determined: {0}' -f $(if ($chain1.ErrorMessage) { $chain1.ErrorMessage } else { 'no Authenticode signature found' }))
        }
        $checks.Add([pscustomobject]@{
            Label             = ('Target #1 ({0})' -f $criticalLabel)
            Path              = $criticalPath
            ExpectedSignature = 'PCA2023'
            ActualSignature   = $actualSig
            IsPca2023         = $chain1.IsPca2023
            IsPca2011         = $chain1.IsPca2011
            Status            = $status1
            Notes             = $notes1
        }) | Out-Null
        if ($status1 -ne 'Pass') {
            $reasons.Add(('Target #1 ({0}): {1}' -f $criticalLabel, $notes1)) | Out-Null
        }
    } else {
        $checks.Add([pscustomobject]@{
            Label             = ('Target #1 ({0})' -f $criticalLabel)
            Path              = $criticalPath
            ExpectedSignature = 'PCA2023'
            ActualSignature   = 'missing'
            IsPca2023         = $false
            IsPca2011         = $false
            Status            = 'Fail'
            Notes             = ('UEFI critical path file not present at expected location: {0}' -f $criticalPath)
        }) | Out-Null
        $reasons.Add(('Target #1 ({0}): file not present.' -f $criticalLabel)) | Out-Null
    }

    # ---- Target #2: \bootmgr.efi (PCA2011 by Microsoft design) ----
    if (Test-Path -LiteralPath $bootMgrEfiPath) {
        $chain2     = Test-Pca2023AuthenticodeChain -Path $bootMgrEfiPath
        $actualSig2 = if ($chain2.IsPca2023) { 'PCA2023' }
                      elseif ($chain2.IsPca2011) { 'PCA2011' }
                      else { 'unknown' }
        $checks.Add([pscustomobject]@{
            Label             = 'Target #2 (\bootmgr.efi)'
            Path              = $bootMgrEfiPath
            ExpectedSignature = 'PCA2011 (Microsoft design)'
            ActualSignature   = $actualSig2
            IsPca2023         = $chain2.IsPca2023
            IsPca2011         = $chain2.IsPca2011
            Status            = 'PassWithNotes'
            Notes             = 'Per Make2023BootableMedia.ps1 (v1.6.4-signed / commit bd7abe3, Copy-2023BootBins), bootmgr.efi at ISO root is by-design NOT signed with the 2023 cert. UEFI Secure Boot does not consult this file; BIOS/MBR boot paths do.'
        }) | Out-Null
    } else {
        $checks.Add([pscustomobject]@{
            Label             = 'Target #2 (\bootmgr.efi)'
            Path              = $bootMgrEfiPath
            ExpectedSignature = 'PCA2011 (Microsoft design)'
            ActualSignature   = 'missing'
            IsPca2023         = $false
            IsPca2011         = $false
            Status            = 'PassWithNotes'
            Notes             = 'bootmgr.efi at ISO root is missing. Per Microsoft spec (Make2023BootableMedia.ps1 Copy-2023BootBins) this file is optional ("if present in the update, it should be copied").'
        }) | Out-Null
    }

    # ---- Target #3: efisys_ex.bin (required binary) ----
    if (Test-Path -LiteralPath $efisysExPath) {
        $checks.Add([pscustomobject]@{
            Label             = 'Target #3 (\efi\microsoft\boot\efisys_ex.bin)'
            Path              = $efisysExPath
            ExpectedSignature = 'n/a (binary)'
            ActualSignature   = 'present'
            IsPca2023         = $false
            IsPca2011         = $false
            Status            = 'Pass'
            Notes             = 'efisys_ex.bin is present.'
        }) | Out-Null
    } else {
        $checks.Add([pscustomobject]@{
            Label             = 'Target #3 (\efi\microsoft\boot\efisys_ex.bin)'
            Path              = $efisysExPath
            ExpectedSignature = 'n/a (binary)'
            ActualSignature   = 'missing'
            IsPca2023         = $false
            IsPca2011         = $false
            Status            = 'Fail'
            Notes             = 'efisys_ex.bin is required by Make2023BootableMedia.ps1 spec but is not present.'
        }) | Out-Null
        $reasons.Add('Target #3 (efisys_ex.bin): required file not present.') | Out-Null
    }

    # ---- Target #4: fonts/*.ttf (required fonts) ----
    $ttfCount = 0
    if (Test-Path -LiteralPath $fontsDir) {
        try {
            $ttf = @(Get-ChildItem -LiteralPath $fontsDir -Filter '*.ttf' -File -ErrorAction Stop)
            $ttfCount = $ttf.Count
        } catch {
            $ttfCount = 0
        } # psa-disable-line PSA3004 -- best-effort enumeration; ttfCount stays 0 on failure
    }
    if ($ttfCount -gt 0) {
        $checks.Add([pscustomobject]@{
            Label             = 'Target #4 (\efi\microsoft\boot\fonts\*.ttf)'
            Path              = $fontsDir
            ExpectedSignature = 'n/a (fonts)'
            ActualSignature   = ('{0} *.ttf file(s)' -f $ttfCount)
            IsPca2023         = $false
            IsPca2011         = $false
            Status            = 'Pass'
            Notes             = ('{0} *.ttf font file(s) present under fonts/.' -f $ttfCount)
        }) | Out-Null
    } else {
        $checks.Add([pscustomobject]@{
            Label             = 'Target #4 (\efi\microsoft\boot\fonts\*.ttf)'
            Path              = $fontsDir
            ExpectedSignature = 'n/a (fonts)'
            ActualSignature   = 'missing or empty'
            IsPca2023         = $false
            IsPca2011         = $false
            Status            = 'Warning'
            Notes             = 'Fonts directory is missing or contains no *.ttf files. Boot UI may render without proper fonts.'
        }) | Out-Null
        $reasons.Add('Target #4 (fonts): directory missing or contains no *.ttf files.') | Out-Null
    }

    # ---- Target #5: boot.stl (optional cert trust list) ----
    if (Test-Path -LiteralPath $bootStlPath) {
        $checks.Add([pscustomobject]@{
            Label             = 'Target #5 (\EFI\Microsoft\Boot\boot.stl)'
            Path              = $bootStlPath
            ExpectedSignature = 'n/a (cert trust list)'
            ActualSignature   = 'present'
            IsPca2023         = $false
            IsPca2011         = $false
            Status            = 'Pass'
            Notes             = 'boot.stl (certificate trust list) is present.'
        }) | Out-Null
    } else {
        $checks.Add([pscustomobject]@{
            Label             = 'Target #5 (\EFI\Microsoft\Boot\boot.stl)'
            Path              = $bootStlPath
            ExpectedSignature = 'n/a (cert trust list)'
            ActualSignature   = 'missing'
            IsPca2023         = $false
            IsPca2011         = $false
            Status            = 'PassWithNotes'
            Notes             = 'boot.stl is missing. Per Microsoft Make2023BootableMedia.ps1 (Copy-2023BootBins, boot.stl best-effort step) this file is optional and "Skipping" is acceptable when the source carries no boot.stl.'
        }) | Out-Null
    }

    # ---- Aggregate OverallStatus ----
    # Priority: Fail > Warning > PassWithNotes > Pass
    $hasFail          = $false
    $hasWarning       = $false
    $hasPassWithNotes = $false
    foreach ($c in $checks) {
        switch ($c.Status) {
            'Fail'          { $hasFail = $true }
            'Warning'       { $hasWarning = $true }
            'PassWithNotes' { $hasPassWithNotes = $true }
        }
    }
    if     ($hasFail)            { $result.OverallStatus = 'Fail' }
    elseif ($hasWarning)         { $result.OverallStatus = 'Warning' }
    elseif ($hasPassWithNotes)   { $result.OverallStatus = 'PassWithNotes' }
    else                         { $result.OverallStatus = 'Pass' }

    # SCOPE clarifier - always appended so downstream consumers see the
    # exact boundary of what this in-tree check can and cannot prove.
    $reasons.Add('SCOPE: file presence + signer-chain only. Actual boot behaviour on firmware with PCA2011 revoked from DBX is NOT verified here. Manual boot test on hardware or a Hyper-V Gen2 VM with a PCA2023 Secure Boot template is required before production deployment.') | Out-Null

    # IMPORTANT: use $checks.ToArray() rather than @($checks).
    # PowerShell 7.4's @() operator on a System.Collections.Generic.List[object]
    # whose elements are pscustomobject triggers a "Argument types do not match"
    # exception. .ToArray() is the documented safe alternative; see SPEC.md
    # Part D for the rationale and the cross-reference to the finding doc.
    # For List[string] (Reasons below) the @() operator works correctly.
    $result.Available    = $true
    $result.TargetChecks = $checks.ToArray()
    $result.Reasons      = @($reasons)
    return $result
}

function Get-Pca2023ReadinessSnapshot {
    <#
    .SYNOPSIS
        Top-level entry point for P12 VerifyPca2023Readiness.

        Combines:
          .IsoEmbedded   - Get-IsoBootCertReadiness output (always)
          .Health        - 'Healthy' / 'Warning' / 'Critical' / 'Unknown'
          .Reasons[]     - bullet-point explanation of the Health value
          .OutputCheck   - Test-OutputIsoPca2023Readiness output;
                           starts as $null and is populated by P10
                           post-flight or P12 when those phases run.

        Health classification (per SPEC.md D.22):
          Healthy   - bootx64.efi is PCA2023-signed AND install.wim
                      LCU date >= 2024-04-09 AND EFI_EX dir present
          Warning   - bootx64.efi is still PCA2011 BUT install.wim
                      meets the 2024-4B prereq (P10 ConvertPca2023BootManager
                      can be applied safely)
          Critical  - install.wim LCU date < 2024-04-09 (P10 would fail
                      because Microsoft requires 2024-4B+ source media)
          Unknown   - could not inspect ISO at all (mount failure etc.)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$ExtractedMediaPath,
        [Parameter(Mandatory)] [string]$WorkRoot,
        [string]$OsKey
    )

    $emb = Get-IsoBootCertReadiness -ExtractedMediaPath $ExtractedMediaPath -WorkRoot $WorkRoot

    $health = 'Unknown'
    $reasons = New-Object System.Collections.Generic.List[string]

    if (-not $emb.Available) {
        $reasons.Add(('ISO inventory unavailable: {0}' -f $emb.ErrorMessage)) | Out-Null
        return [pscustomobject]@{
            Generated   = (Get-Date)
            Source      = 'IsoEmbedded'
            OsKey       = $OsKey
            IsoEmbedded = $emb
            Health      = $health
            Reasons     = @($reasons)
            OutputCheck = $null
        }
    }

    # Classify
    $isPca2023 = ($emb.BootX64IsPca2023 -eq $true)
    $isPca2011 = ($emb.BootX64IsPca2011 -eq $true)
    $meetsPrereq = ($emb.InstallWimMeetsPca2023Prereq -eq $true) -or ($emb.BootWimMeetsPca2023Prereq -eq $true)
    $hasEfiEx = ($emb.HasEfiExDir -eq $true) -and ($emb.HasBootMgrFwEx -eq $true)

    if (-not $meetsPrereq) {
        $health = 'Critical'
        $reasons.Add('install.wim / boot.wim LCU level is BELOW 2024-04-09 (the Make2023BootableMedia.ps1 prerequisite). P10 ConvertPca2023BootManager would refuse to operate.') | Out-Null
        if ($emb.InstallWimHighestKb) {
            $reasons.Add(('Highest install.wim KB: {0} (date: {1})' -f $emb.InstallWimHighestKb, $emb.InstallWimHighestKbDate)) | Out-Null
        }
    } elseif ($isPca2023) {
        $health = 'Healthy'
        $reasons.Add('bootx64.efi is signed via the "Windows UEFI CA 2023" certificate chain. ISO can boot under PCA2023-only Secure Boot firmware (post 2026-06 cert refresh).') | Out-Null
        if (-not $hasEfiEx) {
            $health = 'Warning'
            $reasons.Add('PCA2023 signer detected but EFI_EX staging directory is missing - boot.wim may be a custom media build. Future maintenance flows may not detect the EFI_EX scaffolding.') | Out-Null
        }
    } elseif ($isPca2011 -and $hasEfiEx) {
        $health = 'Warning'
        $reasons.Add('bootx64.efi is still PCA2011-signed, BUT EFI_EX staging directory is present in boot.wim. P10 ConvertPca2023BootManager (or external Make2023BootableMedia.ps1) can promote this ISO to PCA2023 in one pass.') | Out-Null
    } elseif ($isPca2011) {
        $health = 'Warning'
        $reasons.Add('bootx64.efi is still PCA2011-signed and no EFI_EX staging directory was found. boot.wim may have been built from a source older than 2024-4B; P10 will refuse to operate even though install.wim claims prereq is met.') | Out-Null
    } else {
        # neither flag was set - we could not read the signature at all
        $health = 'Unknown'
        $reasons.Add('Could not determine bootx64.efi signer (no Authenticode chain readable). May indicate damaged ISO, missing OpenSSL/Windows SDK, or Linux pwsh limitations.') | Out-Null
    }

    # Add Server2025-specific advisory
    if ($OsKey -eq 'Server2025') {
        $reasons.Add('NOTE: Server 2025 certified server platforms include the 2023 certificates in firmware. P10 is skipped by default for this OS unless -EnablePca2023BootManager -ForcePca2023OnServer2025 are BOTH set.') | Out-Null
    }

    [pscustomobject]@{
        Generated   = (Get-Date)
        Source      = 'IsoEmbedded'
        OsKey       = $OsKey
        IsoEmbedded = $emb
        Health      = $health
        Reasons     = @($reasons)
        OutputCheck = $null
    }
}

function Show-Pca2023ReadinessSnapshot {
    <#
    .SYNOPSIS
        Render a Pca2023 readiness snapshot in this script's log style.
        With -Compact, prints a single header line for P09 / P12 banners.
        Without -Compact, prints a full breakdown for P13 FinalReport.

        With -OutputCheck $check (a Test-OutputIsoPca2023Readiness
        result), an additional "Output ISO PCA2023 readiness" block is
        rendered after the SecureBoot servicing keys section. In
        Compact mode a one-line summary is added instead. Pass $null
        or omit the parameter to skip this block.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [switch]$Compact,
        $OutputCheck
    )

    if (-not $Snapshot) { return }
    $emb = $Snapshot.IsoEmbedded
    $health = $Snapshot.Health

    if ($Compact) {
        $cn = if ($emb.BootX64IsPca2023) { 'PCA2023' } elseif ($emb.BootX64IsPca2011) { 'PCA2011' } else { 'unknown' }
        $kb = if ($emb.InstallWimHighestKb) { $emb.InstallWimHighestKb } else { 'n/a' }
        Write-Step ('Pca2023 readiness: signer={0,-7} install_lcu={1,-10} health={2}' -f $cn, $kb, $health)
        if ($OutputCheck) {
            $passCount    = @($OutputCheck.TargetChecks | Where-Object { $_.Status -eq 'Pass' }).Count
            $passNotesCnt = @($OutputCheck.TargetChecks | Where-Object { $_.Status -eq 'PassWithNotes' }).Count
            $warnCount    = @($OutputCheck.TargetChecks | Where-Object { $_.Status -eq 'Warning' }).Count
            $failCount    = @($OutputCheck.TargetChecks | Where-Object { $_.Status -eq 'Fail' }).Count
            Write-Step ('Output ISO check : overall={0,-13} targets={1} (Pass={2} PassWithNotes={3} Warn={4} Fail={5})' -f `
                $OutputCheck.OverallStatus, $OutputCheck.TargetChecks.Count, $passCount, $passNotesCnt, $warnCount, $failCount)
        }
        return
    }

    # NOTE: This is the non-compact / detailed rendering of the
    # snapshot. It is called from two sites with no -Compact flag:
    # P12 VerifyPca2023Readiness (after the snapshot is already
    # computed) and the standalone analysis helper at the bottom
    # of the script. In both cases the caller has already emitted
    # a phase or section header, so this function uses
    # Write-SubSection (not Write-PhaseHeader) to avoid both the
    # missing-Mandatory-parameter trap that hits Write-PhaseHeader
    # when called positionally and the duplicate phase-banner
    # visual noise.
    Write-SubSection 'PCA2023 readiness detail'
    Write-Step ('Overall health   : {0}' -f $health)
    foreach ($r in $Snapshot.Reasons) {
        Write-Step ('  - {0}' -f $r)
    }
    Write-Step ''
    Write-Step '[ISO boot environment]'
    # NOTE: PowerShell requires $(...) for `if`-as-expression syntax. Bare
    # `(if ...)` is parsed as a *command* invocation named 'if', which fails
    # at runtime with the localised "term 'if' is not recognized as a name
    # of a cmdlet, function, script file..." error. The $(...) subexpression
    # operator is mandatory. See the SecureBoot/LCU blocks below for the
    # correct pattern. Note that @(if ...) (array subexpression) is also
    # valid PowerShell - only the bare (if ...) form is broken.
    Write-Step ('EFI_EX staging directory : {0}' -f $(if ($null -eq $emb.HasEfiExDir) { 'n/a' } elseif ($emb.HasEfiExDir) { 'present' } else { 'NOT present' }))
    Write-Step ('  bootmgfw_EX.efi        : {0}' -f $(if ($null -eq $emb.HasBootMgrFwEx) { 'n/a' } elseif ($emb.HasBootMgrFwEx) { 'present' } else { 'NOT present' }))
    Write-Step ('  bootmgr_EX.efi         : {0}' -f $(if ($null -eq $emb.HasBootMgrEx) { 'n/a' } elseif ($emb.HasBootMgrEx) { 'present' } else { 'NOT present' }))
    Write-Step ('  FONTS_EX               : {0}' -f $(if ($null -eq $emb.HasFontsEx) { 'n/a' } elseif ($emb.HasFontsEx) { 'present' } else { 'NOT present' }))
    Write-Step ('  DVD_EX/EFI/en-US/efisys_EX.bin : {0}' -f $(if ($null -eq $emb.HasEfisysExBin) { 'n/a' } elseif ($emb.HasEfisysExBin) { 'present' } else { 'NOT present' }))
    Write-Step ''
    Write-Step '[bootx64.efi signer]'
    Write-Step ('  Signer subject  : {0}' -f $(if ($emb.BootX64SignerName) { $emb.BootX64SignerName } else { 'n/a' }))
    Write-Step ('  PCA2023 chain   : {0}' -f $emb.BootX64IsPca2023)
    Write-Step ('  PCA2011 chain   : {0}' -f $emb.BootX64IsPca2011)
    Write-Step ''
    Write-Step '[LCU integration level]'
    Write-Step ('  install.wim KB  : {0} (date: {1})' -f $(if ($emb.InstallWimHighestKb) { $emb.InstallWimHighestKb } else { 'n/a' }), $(if ($emb.InstallWimHighestKbDate) { $emb.InstallWimHighestKbDate } else { 'n/a' }))
    Write-Step ('  install.wim 2024-4B prereq : {0}' -f $emb.InstallWimMeetsPca2023Prereq)
    Write-Step ('  boot.wim    KB  : {0} (date: {1})' -f $(if ($emb.BootWimHighestKb) { $emb.BootWimHighestKb } else { 'n/a' }), $(if ($emb.BootWimHighestKbDate) { $emb.BootWimHighestKbDate } else { 'n/a' }))
    Write-Step ('  boot.wim    2024-4B prereq : {0}' -f $emb.BootWimMeetsPca2023Prereq)
    Write-Step ''
    Write-Step '[SecureBoot servicing keys (from install.wim SYSTEM hive)]'
    Write-Step ('  UEFICA2023Status   : {0}' -f $(if ($emb.UEFICA2023Status) { $emb.UEFICA2023Status } else { 'n/a (key not present)' }))
    Write-Step ('  UEFICA2023Error    : {0}' -f $(if ($null -ne $emb.UEFICA2023Error) { $emb.UEFICA2023Error } else { 'n/a' }))
    Write-Step ('  AvailableUpdates   : {0}' -f $(if ($emb.AvailableUpdatesHex) { $emb.AvailableUpdatesHex } else { 'n/a' }))

    if ($OutputCheck) {
        Write-Step ''
        Write-Step '[Output ISO PCA2023 readiness (post-conversion, file-based)]'
        Write-Step ('  OverallStatus      : {0}' -f $OutputCheck.OverallStatus)
        if ($OutputCheck.Available) {
            Write-Step ('  Targets checked    : {0}' -f $OutputCheck.TargetChecks.Count)
            foreach ($t in $OutputCheck.TargetChecks) {
                Write-Step ('    - [{0,-13}] {1}' -f $t.Status, $t.Label)
                if ($t.ActualSignature) {
                    Write-Step ('        expected = {0,-30} actual = {1}' -f $t.ExpectedSignature, $t.ActualSignature)
                }
                if ($t.Notes) {
                    Write-Step ('        notes    : {0}' -f $t.Notes)
                }
            }
        } elseif ($OutputCheck.ErrorMessage) {
            Write-Step ('  Error             : {0}' -f $OutputCheck.ErrorMessage)
        }
    }
}

function Format-Pca2023ReadinessForReport {
    <#
    .SYNOPSIS
        Render snapshot as a plain-text section suitable for the
        P13 FinalReport appendix and the standalone
        pca2023_readiness.md file.

        With -OutputCheck $check (a Test-OutputIsoPca2023Readiness
        result), an additional "Output ISO PCA2023 readiness" block is
        appended after the SecureBoot servicing section.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Snapshot,
        $OutputCheck
    )

    if (-not $Snapshot) { return '' }
    $emb = $Snapshot.IsoEmbedded

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(('=' * 78))
    [void]$sb.AppendLine('PCA2023 Boot Manager Readiness')
    [void]$sb.AppendLine(('=' * 78))
    [void]$sb.AppendLine(('Captured       : {0}' -f $Snapshot.Generated.ToString('yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine(('OS Key         : {0}' -f $(if ($Snapshot.OsKey) { $Snapshot.OsKey } else { 'n/a' })))
    [void]$sb.AppendLine(('Overall health : {0}' -f $Snapshot.Health))
    if ($Snapshot.Reasons.Count -gt 0) {
        [void]$sb.AppendLine('Reasons        :')
        foreach ($r in $Snapshot.Reasons) {
            [void]$sb.AppendLine(('  - {0}' -f $r))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- ISO boot environment ' + ('-' * 54))
    [void]$sb.AppendLine(('EFI_EX staging directory      : {0}' -f $(if ($null -eq $emb.HasEfiExDir) { 'n/a' } elseif ($emb.HasEfiExDir) { 'present' } else { 'NOT present' })))
    [void]$sb.AppendLine(('  bootmgfw_EX.efi             : {0}' -f $(if ($null -eq $emb.HasBootMgrFwEx) { 'n/a' } elseif ($emb.HasBootMgrFwEx) { 'present' } else { 'NOT present' })))
    [void]$sb.AppendLine(('  bootmgr_EX.efi              : {0}' -f $(if ($null -eq $emb.HasBootMgrEx) { 'n/a' } elseif ($emb.HasBootMgrEx) { 'present' } else { 'NOT present' })))
    [void]$sb.AppendLine(('  FONTS_EX                    : {0}' -f $(if ($null -eq $emb.HasFontsEx) { 'n/a' } elseif ($emb.HasFontsEx) { 'present' } else { 'NOT present' })))
    [void]$sb.AppendLine(('  efisys_EX.bin (DVD_EX)      : {0}' -f $(if ($null -eq $emb.HasEfisysExBin) { 'n/a' } elseif ($emb.HasEfisysExBin) { 'present' } else { 'NOT present' })))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- bootx64.efi signer ' + ('-' * 56))
    [void]$sb.AppendLine(('Signer subject  : {0}' -f $(if ($emb.BootX64SignerName) { $emb.BootX64SignerName } else { 'n/a' })))
    [void]$sb.AppendLine(('PCA2023 chain   : {0}' -f $emb.BootX64IsPca2023))
    [void]$sb.AppendLine(('PCA2011 chain   : {0}' -f $emb.BootX64IsPca2011))
    if ($emb.BootX64ChainTokens.Count -gt 0) {
        [void]$sb.AppendLine('Chain tokens    :')
        foreach ($t in $emb.BootX64ChainTokens) {
            [void]$sb.AppendLine(('  - {0}' -f $t))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- LCU integration level ' + ('-' * 53))
    [void]$sb.AppendLine(('install.wim highest KB           : {0}' -f $(if ($emb.InstallWimHighestKb) { $emb.InstallWimHighestKb } else { 'n/a' })))
    [void]$sb.AppendLine(('install.wim highest KB date      : {0}' -f $(if ($emb.InstallWimHighestKbDate) { $emb.InstallWimHighestKbDate } else { 'n/a' })))
    [void]$sb.AppendLine(('install.wim meets 2024-4B prereq : {0}' -f $emb.InstallWimMeetsPca2023Prereq))
    [void]$sb.AppendLine(('boot.wim    highest KB           : {0}' -f $(if ($emb.BootWimHighestKb) { $emb.BootWimHighestKb } else { 'n/a' })))
    [void]$sb.AppendLine(('boot.wim    highest KB date      : {0}' -f $(if ($emb.BootWimHighestKbDate) { $emb.BootWimHighestKbDate } else { 'n/a' })))
    [void]$sb.AppendLine(('boot.wim    meets 2024-4B prereq : {0}' -f $emb.BootWimMeetsPca2023Prereq))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- SecureBoot servicing (from install.wim SYSTEM hive) ' + ('-' * 23))
    [void]$sb.AppendLine(('UEFICA2023Status    : {0}' -f $(if ($emb.UEFICA2023Status) { $emb.UEFICA2023Status } else { 'n/a' })))
    [void]$sb.AppendLine(('UEFICA2023Error     : {0}' -f $(if ($null -ne $emb.UEFICA2023Error) { $emb.UEFICA2023Error } else { 'n/a' })))
    [void]$sb.AppendLine(('AvailableUpdates    : {0}' -f $(if ($emb.AvailableUpdatesHex) { $emb.AvailableUpdatesHex } else { 'n/a' })))
    [void]$sb.AppendLine('')
    if ($OutputCheck) {
        [void]$sb.AppendLine('-- Output ISO PCA2023 readiness (post-conversion, file-based) ' + ('-' * 15))
        [void]$sb.AppendLine(('OverallStatus       : {0}' -f $OutputCheck.OverallStatus))
        if ($OutputCheck.Available) {
            [void]$sb.AppendLine(('Targets checked     : {0}' -f $OutputCheck.TargetChecks.Count))
            foreach ($t in $OutputCheck.TargetChecks) {
                [void]$sb.AppendLine('')
                [void]$sb.AppendLine(('  [{0,-13}] {1}' -f $t.Status, $t.Label))
                [void]$sb.AppendLine(('      Path     : {0}' -f $t.Path))
                [void]$sb.AppendLine(('      Expected : {0}' -f $t.ExpectedSignature))
                [void]$sb.AppendLine(('      Actual   : {0}' -f $t.ActualSignature))
                if ($t.Notes) {
                    [void]$sb.AppendLine(('      Notes    : {0}' -f $t.Notes))
                }
            }
        } elseif ($OutputCheck.ErrorMessage) {
            [void]$sb.AppendLine(('Error               : {0}' -f $OutputCheck.ErrorMessage))
        }
        [void]$sb.AppendLine('')
    }
    return $sb.ToString()
}

function Get-OrEnsurePca2023Snapshot {
    <#
    .SYNOPSIS
        Idempotent accessor for the cached PCA2023 readiness snapshot.

        On first call, computes a fresh snapshot from the extracted
        media and stashes it on $Script:Pca2023Snapshot. Subsequent
        calls return the cached value unless -Force is specified.

        Used by P12, P13, and the standalone -Pca2023OnlyMode path
        so they all see the same authoritative snapshot without
        re-running the (relatively expensive) WIM-mount + Authenticode
        chain walk.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$ExtractedMediaPath,
        [Parameter(Mandatory)] [string]$WorkRoot,
        [string]$OsKey,
        [switch]$Force
    )

    if ($Force -or -not $Script:Pca2023Snapshot) {
        $Script:Pca2023Snapshot = Get-Pca2023ReadinessSnapshot `
            -ExtractedMediaPath $ExtractedMediaPath `
            -WorkRoot $WorkRoot `
            -OsKey $OsKey
    }
    return $Script:Pca2023Snapshot
}

function Convert-WimBootToPca2023Signed {
    <#
    .SYNOPSIS
        PSA-clean re-implementation of Microsoft's Copy-2023BootBins
        logic (from Make2023BootableMedia.ps1, microsoft/secureboot_objects
        repo, v1.6.4-signed / commit bd7abe3).

        DIFFERENCES from upstream Make2023BootableMedia.ps1:

        1. Uses Context-bag pattern ($Ctx) instead of $global:WIM_*
           globals. This isolates state and avoids leaks across phases.
        2. Uses this script's standard Write-Step / _LogLine / Add-ErrorJsonlEntry
           instead of Write-Host / Write-Dbg-Host.
        3. Throws on error (no 'exit' statements). Phase wrapper
           catches and records.
        4. Uses Invoke-WimMountSafe / Invoke-WimDismountSafe (existing
           DISM helpers in this script) rather than direct
           Mount-WindowsImage so the DISM mount-cache stays clean.
        5. PSA Verb-Noun compliant (Convert-* instead of Copy-2023BootBins).
        6. Mandatory=$true shorthand; #Requires -RunAsAdministrator
           is enforced by Assert-WorkspacePreflight earlier in pipeline.

        Returns a pscustomobject:
          .Success      - $true if all file copies succeeded
          .FilesUpdated - list of files copied
          .ErrorMessage - reason string when not Success
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$ExtractedMediaPath,
        [Parameter(Mandatory)] [string]$WorkRoot
    )

    $result = [pscustomobject]@{
        Success      = $false
        FilesUpdated = @()
        ErrorMessage = $null
    }

    $bootWimPath = Join-Path $ExtractedMediaPath 'sources\boot.wim'
    if (-not (Test-Path -LiteralPath $bootWimPath)) {
        $result.ErrorMessage = ('boot.wim not found: {0}' -f $bootWimPath)
        return $result
    }

    $tag = ('PCA2023CV{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
    $mount = Join-Path $WorkRoot ('mnt_bootwim_pca2023_rw_{0}' -f $tag)
    try {
        if (-not (Test-Path -LiteralPath $mount)) {
            New-Item -ItemType Directory -Path $mount -Force | Out-Null
        }
    } catch {
        $result.ErrorMessage = ('Could not create mount dir {0}: {1}' -f $mount, $_.Exception.Message)
        return $result
    }

    $updated = New-Object System.Collections.Generic.List[string]
    $mounted = $false
    try {
        Write-Step ('Mounting boot.wim (read-only, for PCA2023 source extraction): {0}' -f $bootWimPath)
        $null = Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters @{ ImagePath = $bootWimPath; Index = 1; Path = $mount; ReadOnly = $true; ErrorAction = 'Stop' }
        $mounted = $true

        $exBins  = Join-Path $mount 'Windows\Boot\EFI_EX'
        $exFonts = Join-Path $mount 'Windows\Boot\FONTS_EX'
        $exDvd   = Join-Path $mount 'Windows\Boot\DVD_EX'

        if (-not (Test-Path -LiteralPath $exBins) -or `
            -not (Test-Path -LiteralPath $exFonts) -or `
            -not (Test-Path -LiteralPath $exDvd)) {
            $result.ErrorMessage = 'boot.wim does not contain EFI_EX/FONTS_EX/DVD_EX staging directories. Source media must include 2024-4B (April 2024 LCU) or later. This matches the Make2023BootableMedia.ps1 error "Make sure all required updates (2024-4B or later) have been applied".'
            return $result
        }

        # Determine target boot manager filename. Microsoft media uses
        # bootx64.efi on x64, bootaa64.efi on ARM64.
        $efiBoot = Join-Path $ExtractedMediaPath 'efi\boot'
        $bootmgrName = 'bootx64.efi'
        if (Test-Path -LiteralPath (Join-Path $efiBoot 'bootaa64.efi')) {
            $bootmgrName = 'bootaa64.efi'
        }

        # --- 1. Replace efi/boot/bootx64.efi with bootmgfw_EX.efi ---
        $src = Join-Path $exBins 'bootmgfw_EX.efi'
        $dst = Join-Path $efiBoot $bootmgrName
        Write-Step ('Copying {0} -> {1}' -f $src, $dst)
        Copy-Item -Path $src -Destination $dst -Force -ErrorAction Stop
        $updated.Add($dst) | Out-Null

        # --- 2. Replace /bootmgr.efi with bootmgr_EX.efi (if present) ---
        $srcMgr = Join-Path $exBins 'bootmgr_EX.efi'
        $dstMgr = Join-Path $ExtractedMediaPath 'bootmgr.efi'
        if (Test-Path -LiteralPath $srcMgr) {
            Write-Step ('Copying {0} -> {1}' -f $srcMgr, $dstMgr)
            Copy-Item -Path $srcMgr -Destination $dstMgr -Force -ErrorAction Stop
            $updated.Add($dstMgr) | Out-Null
        }

        # --- 3. Replace efi/microsoft/boot/efisys.bin from efisys_EX.bin ---
        $srcEfisys = Join-Path $exDvd 'EFI\en-US\efisys_EX.bin'
        $dstEfisys = Join-Path $ExtractedMediaPath 'efi\microsoft\boot\efisys_ex.bin'
        $dstEfisysDir = Split-Path -Parent $dstEfisys
        if (-not (Test-Path -LiteralPath $dstEfisysDir)) {
            New-Item -ItemType Directory -Path $dstEfisysDir -Force | Out-Null
        }
        Write-Step ('Copying {0} -> {1}' -f $srcEfisys, $dstEfisys)
        Copy-Item -Path $srcEfisys -Destination $dstEfisys -Force -ErrorAction Stop
        $updated.Add($dstEfisys) | Out-Null

        # --- 4. Stage FONTS_EX to efi/microsoft/boot/fonts (rename _EX.ttf -> .ttf) ---
        $dstFontsDir = Join-Path $ExtractedMediaPath 'efi\microsoft\boot\fonts'
        if (-not (Test-Path -LiteralPath $dstFontsDir)) {
            New-Item -ItemType Directory -Path $dstFontsDir -Force | Out-Null
        }
        Get-ChildItem -Path $exFonts -Filter '*.ttf' | ForEach-Object {
            $newName = $_.Name -replace '_EX\.ttf$', '.ttf'
            $target  = Join-Path $dstFontsDir $newName
            Copy-Item -Path $_.FullName -Destination $target -Force -ErrorAction Stop
            $updated.Add($target) | Out-Null
        }

        # --- 5. boot.stl (best-effort; not all SKUs include it) ---
        $srcStl = Join-Path $mount 'Windows\Boot\EFI\boot.stl'
        $dstStl = Join-Path $ExtractedMediaPath 'EFI\Microsoft\Boot\boot.stl'
        if ((Test-Path -LiteralPath $srcStl) -and -not (Test-Path -LiteralPath $dstStl)) {
            $dstStlDir = Split-Path -Parent $dstStl
            if (-not (Test-Path -LiteralPath $dstStlDir)) {
                New-Item -ItemType Directory -Path $dstStlDir -Force | Out-Null
            }
            Copy-Item -Path $srcStl -Destination $dstStl -Force -ErrorAction Stop
            $updated.Add($dstStl) | Out-Null
        }

        $result.Success      = $true
        $result.FilesUpdated = @($updated)
    } catch {
        $result.ErrorMessage = ('PCA2023 conversion failed: {0}' -f $_.Exception.Message)
    } finally {
        if ($mounted) {
            try {
                $null = Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path = $mount; Discard = $true; ErrorAction = 'Stop' }
            } catch {
                # Best-effort cleanup; subsequent runs may need 'dism /Cleanup-Wim'
            } # psa-disable-line PSA3004 -- intentional best-effort dismount; cleanup happens automatically on next reboot
        }
        try {
            if (Test-Path -LiteralPath $mount) {
                Remove-Item -Path $mount -Recurse -Force -ErrorAction Stop
            }
        } catch {
            # Mount directory cleanup best-effort
        } # psa-disable-line PSA3004 -- best-effort cleanup; the dir will be auto-released eventually
    }
    return $result
}

# ============================================================
# Phase P01: Initialize (Setup group)
# ============================================================

function Test-AdminPrivilege {
    # Returns $true if the current PS session is running elevated.
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SetupPhase01_Initialize {
    <#
    .SYNOPSIS
        P01: Environment evaluation. Hardware/software prerequisites,
        admin privilege, required tools (dism, oscdimg), disk space,
        Hyper-V availability (when BootTest is requested).
    #>
    Start-DebugTrace -Context 'Invoke-SetupPhase01_Initialize' -PhaseId 'P01'
    try {
        # Step 0: PowerShell environment dump
        Set-DebugStep -Step 'env-dump'
        Write-SubSection 'Step 0: PowerShell environment'
        Show-PowerShellEnvironment

        if ($Script:EnvironmentInfoOnly) {
            Write-Ok 'EnvironmentInfoOnly requested; exiting after env dump.'
            return
        }

        # Step 1: PowerShell compatibility assert
        Set-DebugStep -Step 'compat-assert'
        Write-SubSection 'Step 1: PowerShell compatibility assertions'
        Assert-PowerShellCompatibility

        # Step 2: Administrator
        Set-DebugStep -Step 'admin-check'
        Write-SubSection 'Step 2: Administrator privilege'
        if (Test-AdminPrivilege) {
            Write-Ok 'Running as Administrator.'
        } else {
            # Allow non-admin only when read-only / planning actions are requested
            $readOnlyActions = @('ListPhases','GenerateManifest','Cleanup','Verify')
            if ($readOnlyActions -contains $Action) {
                Write-Caution ('Not Administrator, but -Action {0} is read-only; continuing.' -f $Action)
            } else {
                throw 'Administrator privilege required for DISM mount operations. Re-launch PowerShell as Administrator.'
            }
        }

        # Step 3: Required tools
        Set-DebugStep -Step 'tool-detection'
        Write-SubSection 'Step 3: Required tools'
        $dism = Get-Command -Name 'dism.exe' -ErrorAction SilentlyContinue
        if ($dism) {
            Write-Ok ('dism.exe found: {0}' -f $dism.Source)
        } else {
            throw 'dism.exe not found in PATH. This script requires DISM (built into Windows 10/Server 2016+).'
        }
        try {
            $oscdimgPath = Resolve-OscdimgExe
            Write-Ok ('oscdimg.exe found: {0}' -f $oscdimgPath)
        } catch {
            if ($Action -in @('ListPhases','GenerateManifest','Cleanup','Prepare') -or $Script:EnvironmentInfoOnly) {
                Write-Caution ('oscdimg.exe not found, but -Action {0} does not need it; continuing.' -f $Action)
            } elseif ($Script:SyntheticTestMode) {
                Write-Caution 'oscdimg.exe not found; -SyntheticTestMode will use a raw-copy fallback.'
            } else {
                # oscdimg.exe is required and missing -> auto-install the
                # Windows ADK Deployment Tools (no switch; mirrors the 7-Zip
                # Install-SevenZipFallback auto-acquire). Install-WindowsAdkFallback
                # returns the discovered oscdimg.exe path and emits its own
                # Write-Ok line, and throws an actionable error if the install
                # fails or oscdimg.exe is still absent afterwards.
                Write-Step 'oscdimg.exe not found; auto-installing the Windows ADK Deployment Tools (Install-WindowsAdkFallback)...'
                $oscdimgPath = Install-WindowsAdkFallback
                Write-Ok ('oscdimg.exe available: {0}' -f $oscdimgPath)
            }
        }
        $gwi = Get-Command -Name 'Get-WindowsImage' -ErrorAction SilentlyContinue
        if ($gwi) {
            Write-Ok 'Get-WindowsImage cmdlet available (Dism module loaded).'
        } else {
            throw 'Get-WindowsImage cmdlet not available. The Dism PowerShell module is required.'
        }

        # Step 4: Disk space (informational; the authoritative check
        # is Step 0.5 'Workspace preflight' which enforces the 100 GB
        # minimum. This step is kept for backwards-compatible log
        # output and to surface the per-drive free-space value when
        # -SkipEnvCheck bypassed Step 0.5).
        Set-DebugStep -Step 'disk-space-info'
        Write-SubSection 'Step 4: Disk space (informational)'
        $rootDrive = $Script:WorkRoot.Substring(0, 2).TrimEnd(':')
        $psDrive = Get-PSDrive -Name $rootDrive -ErrorAction SilentlyContinue
        if ($psDrive) {
            $freeGB = [Math]::Round($psDrive.Free / 1GB, 1)
            Write-Step ('Free space on {0}: {1} GB' -f $rootDrive, $freeGB)
            if ($freeGB -lt 100) {
                Write-Caution ('Free space below the documented 100 GB minimum; if -SkipEnvCheck was used and a real build is attempted, expect DISM to fail.')
            } else {
                Write-Ok ('Disk space OK ({0} GB free).' -f $freeGB)
            }
        } else {
            Write-Caution ('Could not get PSDrive for {0}: skipping informational disk space readout.' -f $rootDrive)
        }

        # Step 5: Hyper-V (BootTest only)
        if ($Action -in @('BootTest','All')) {
            Set-DebugStep -Step 'hyperv-check'
            Write-SubSection 'Step 5: Hyper-V availability'
            try {
                $hv = Invoke-DismCmdlet -CommandName 'Get-WindowsOptionalFeature' -Parameters @{ Online = $true; FeatureName = 'Microsoft-Hyper-V-All'; ErrorAction = 'Stop' }
                if ($hv.State -eq 'Enabled') {
                    Write-Ok 'Hyper-V is Enabled.'
                } else {
                    throw ('Hyper-V is not enabled (State={0}). Run "Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All".' -f $hv.State)
                }
            } catch {
                if ($Script:SyntheticTestMode) {
                    Write-Caution 'Hyper-V unavailable; allowed under -SyntheticTestMode.'
                } else {
                    throw
                }
            }
        }

        # Mark P01 complete
        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P01.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P02: Resolve inputs (Setup group)
# ============================================================

function Invoke-SetupPhase02_ResolveInputs { # psa-disable-line PSA6003 -- "Inputs" is a phase noun; renaming would break the registry-driven dispatcher
    <#
    .SYNOPSIS
        P02: Hydrate the OS profile, resolve ISO source/path, build the
        patch list, and emit P02_inputs_resolved.csv.
    #>
    Start-DebugTrace -Context 'Invoke-SetupPhase02_ResolveInputs' -PhaseId 'P02'
    try {
        if ([string]::IsNullOrEmpty($Script:OsVersion)) {
            throw '-OsVersion is required for P02 (Server2016 / Server2019 / Server2022 / Server2025).'
        }

        # Load profile
        Set-DebugStep -Step 'load-config-profile'
        Write-SubSection 'Step 1: Load OS profile'
        $Script:OsProfile = Get-ConfigProfile -OsKey $Script:OsVersion -OsLang $Script:OsLanguage
        $Script:OsLangProfile = $Script:OsProfile.Language
        Write-Ok ('Profile loaded: {0} / {1} (build {2})' -f $Script:OsProfile.WimEdition, $Script:OsLanguage, $Script:OsProfile.Build)
        Write-Step ('Volume label prefix: {0}' -f $Script:OsLangProfile.VolumeLabelPrefix)

        # Step 2: Resolve ISO source
        Set-DebugStep -Step 'resolve-iso-source'
        Write-SubSection 'Step 2: Resolve ISO source'
        $isoSourceDesc = ''
        if ($Script:SyntheticTestMode) {
            Write-Step '-SyntheticTestMode is on; ISO will be generated in P04.'
            $Script:IsoLocalPath = Join-Path $Script:IsoSourceDir 'synthetic.iso'
            $isoSourceDesc = '(synthetic, generated in-script)'
        } elseif ($Script:IsoPath) {
            $resolvedIso = Resolve-RelativeToScript $Script:IsoPath
            if (-not (Test-Path -LiteralPath $resolvedIso)) {
                throw ('IsoPath does not exist: {0}' -f $resolvedIso)
            }
            $Script:IsoLocalPath = $resolvedIso
            $isoSourceDesc = $resolvedIso
            Write-Ok ('Using local ISO: {0}' -f $resolvedIso)
        } else {
            $url = Resolve-IsoSourceUrl -LanguageProfile $Script:OsLangProfile -ExplicitUrl $Script:IsoUrl
            Write-Step ('Source URL resolved: {0}' -f $url)
            $isoName = ('{0}_{1}.iso' -f $Script:OsProfile.OsShortName, $Script:OsLanguage)
            $Script:IsoLocalPath = Join-Path $Script:IsoSourceDir $isoName
            $isoSourceDesc = $url
            Write-Ok ('ISO will be downloaded to: {0}' -f $Script:IsoLocalPath)
        }

        # Step 3: Resolve patch list
        Set-DebugStep -Step 'resolve-patch-list'
        Write-SubSection 'Step 3: Resolve patch list'
        $resolved = New-Object System.Collections.Generic.List[object]
        if ($Script:PatchUrls -and $Script:PatchUrls.Count -gt 0) {
            Write-Step ('Using {0} explicit -PatchUrls.' -f $Script:PatchUrls.Count)
            foreach ($u in $Script:PatchUrls) {
                $fn = ([System.IO.Path]::GetFileName($u))
                $resolved.Add([pscustomobject]@{
                    Kind = 'Patch'; Source = $u
                    LocalPath = Join-Path $Script:PatchesDir (Join-Path $Script:OsVersion $fn)
                    KbId = (Get-PatchKbId -FileName $fn)
                    PatchType = (Get-PatchType -FileName $fn)
                    ApplyOrder = 99
                    ExpectedHashes = @{}
                }) | Out-Null
            }
        } elseif ($Script:ManifestPath) {
            Write-Step ('Reading Metalink manifest: {0}' -f $Script:ManifestPath)
            $entries = Read-MetalinkManifest -Path (Resolve-RelativeToScript $Script:ManifestPath)
            foreach ($e in $entries) {
                $resolved.Add([pscustomobject]@{
                    Kind = 'Patch'; Source = ($e.Urls | Select-Object -First 1)
                    LocalPath = Join-Path $Script:PatchesDir (Join-Path $Script:OsVersion $e.FileName)
                    KbId = (Get-PatchKbId -FileName $e.FileName)
                    PatchType = (Get-PatchType -FileName $e.FileName)
                    ApplyOrder = (Get-PatchApplyOrder -PatchType (Get-PatchType -FileName $e.FileName))
                    ExpectedHashes = $e.Hashes
                }) | Out-Null
            }
        } elseif ($Script:PatchDirectory) {
            $dir = Resolve-RelativeToScript $Script:PatchDirectory
            if (-not (Test-Path -LiteralPath $dir)) {
                throw ('PatchDirectory does not exist: {0}' -f $dir)
            }
            Write-Step ('Enumerating patches under: {0}' -f $dir)
            $local = Get-ChildItem -LiteralPath $dir -File -Recurse -Include '*.msu','*.cab' -ErrorAction SilentlyContinue
            foreach ($f in $local) {
                $hashes = @{}
                # Look for a side-car .meta4 in the same folder
                $sideCar = Join-Path $f.DirectoryName ([System.IO.Path]::GetFileNameWithoutExtension($f.FullName) + '.meta4')
                if (Test-Path -LiteralPath $sideCar) {
                    try {
                        $meta = Read-MetalinkManifest -Path $sideCar
                        foreach ($m in $meta) {
                            if ($m.FileName -eq $f.Name) { $hashes = $m.Hashes; break }
                        }
                    } catch { $null = $_ }
                }
                $resolved.Add([pscustomobject]@{
                    Kind = 'Patch'; Source = $f.FullName
                    LocalPath = $f.FullName
                    KbId = (Get-PatchKbId -FileName $f.Name)
                    PatchType = (Get-PatchType -FileName $f.Name)
                    ApplyOrder = (Get-PatchApplyOrder -PatchType (Get-PatchType -FileName $f.Name))
                    ExpectedHashes = $hashes
                }) | Out-Null
            }
        } elseif ($Script:AutoDetectLatestPatches -or $Script:UseBaselineOnly -or `
                  ($Script:OsProfile.PatchBaseline -and `
                   $Script:OsProfile.PatchBaseline.Lines -and `
                   $Script:OsProfile.PatchBaseline.Lines.Count -gt 0)) {
            # PatchBaseline-driven path. The OS-neutral baseline is
            # stored under PatchBaseline.Lines[] (Config Schema v3.0;
            # committed via -Action RefreshAllBaselines, see SPEC B.22.5
            # and B.22.8). P03 (when not skipped via -UseBaselineOnly)
            # may refresh this list from the Microsoft Update Catalog if
            # it is stale or -AutoDetectLatestPatches was passed.
            $bl = $Script:OsProfile.PatchBaseline
            $baselineSource = $null
            $baselineField  = $null
            if ($bl.Lines -and $bl.Lines.Count -gt 0) {
                $baselineSource = $bl.Lines
                $baselineField  = 'Lines'
            }
            if ($baselineSource) {
                Write-Step ('Seeding ResolvedPatches from PatchBaseline.{0}: {1} entries.' -f $baselineField, $baselineSource.Count)
                foreach ($p in $baselineSource) {
                    # Derive LocalPath from FileName when available; fall
                    # back to the URL basename for legacy entries that may
                    # omit FileName. An empty LocalPath would crash
                    # P04 Step 2 'Patches' at 'Split-Path -LiteralPath'
                    # ('cannot bind argument to LiteralPath because it
                    # is an empty string').
                    $pFileName = $p.FileName
                    if (-not $pFileName -and $p.DownloadUrl) {
                        try {
                            $pFileName = [System.IO.Path]::GetFileName(([Uri]$p.DownloadUrl).AbsolutePath)
                        } catch {
                            $pFileName = $null
                        }
                    }
                    if (-not $pFileName) {
                        $pFileName = ('{0}.msu' -f $p.KbId)
                    }
                    # Only declare a sha-256 expected-hash when the
                    # baseline actually has one. Inserting an empty
                    # string would let .ExpectedHashes.Count -gt 0
                    # evaluate true and force Test-PatchIntegrity into
                    # comparing against ''.
                    $expectedHashes = @{}
                    if ($p.Sha256) {
                        $expectedHashes['sha-256'] = $p.Sha256
                    }
                    $resolved.Add([pscustomobject]@{
                        Kind = 'Patch'; Source = $p.DownloadUrl
                        LocalPath = Join-Path $Script:PatchesDir (Join-Path $Script:OsVersion $pFileName)
                        KbId = $p.KbId
                        PatchType = $p.Kind
                        ApplyOrder = $p.ApplyOrder
                        ExpectedHashes = $expectedHashes
                    }) | Out-Null
                }
            } else {
                Write-Step 'PatchBaseline.Lines is empty; P03 will populate from Microsoft Update Catalog.'
            }
        } elseif ($Script:SyntheticTestMode) {
            Write-Step '-SyntheticTestMode is on; no real patches required.'
        } else {
            throw 'No patch source specified. Provide one of: -PatchUrls / -PatchDirectory / -ManifestPath / -AutoDetectLatestPatches, or populate Config PatchBaseline.Lines.'
        }

        # Order by ApplyOrder, then by KbId. Wrap in @() to guarantee
        # an array even when $resolved is null or a single object.
        $Script:ResolvedPatches = @($resolved | Sort-Object ApplyOrder, KbId)
        Write-Ok ('Patch list resolved: {0} entries.' -f $Script:ResolvedPatches.Count)

        # Build the WIM-target-aware PatchPlan and print summary.
        # Even when ResolvedPatches is empty (synthetic test mode), we
        # construct an empty plan so downstream Get-OrInitPatchPlan
        # calls in P07/P08 hit a populated cache.
        Set-DebugStep -Step 'build-patch-plan'
        $Script:PatchPlan = Build-PatchPlan -Patches $Script:ResolvedPatches
        Write-PatchPlanSummary -Plan $Script:PatchPlan

        # Emit CSV
        Set-DebugStep -Step 'emit-inputs-csv'
        $csvPath = Join-Path $Script:LogsDir 'P02_inputs_resolved.csv'
        $rows = New-Object System.Collections.Generic.List[object]
        $rows.Add([pscustomobject]@{
            Kind = 'Iso'; Source = $isoSourceDesc
            LocalPath = $Script:IsoLocalPath; Sha256 = ''; SizeBytes = 0; Status = 'Pending'
        }) | Out-Null
        foreach ($p in $Script:ResolvedPatches) {
            $sha256Expected = ''
            if ($p.ExpectedHashes.ContainsKey('sha-256')) {
                $sha256Expected = $p.ExpectedHashes['sha-256']
            }
            $rows.Add([pscustomobject]@{
                Kind = 'Patch'; Source = $p.Source
                LocalPath = $p.LocalPath
                Sha256 = $sha256Expected
                SizeBytes = 0; Status = 'Pending'
            }) | Out-Null
        }
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Wrote: {0}' -f $csvPath)

        # Marker
        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P02.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}


# ============================================================
# Phase P03: RefreshPatchBaseline
# ============================================================
# Conditionally refresh PatchBaseline by scraping the Microsoft Update
# Catalog when the existing baseline is stale (Patch Tuesday has passed
# since PatchTuesdayOfBaseline). On success, the in-memory $Script:OsProfile
# is updated and (per AutoRefreshPolicy.WritebackToConfig) the Config
# JSON on disk is rewritten.
#
# Skip conditions (any of these short-circuits to "no-op"):
#   - $Script:SyntheticTestMode  (CI synthetic full pipeline)
#   - $Script:SkipDynamicPatchRefresh
#   - $Script:UseBaselineOnly
#   - PatchBaseline is already fresh AND $AutoDetectLatestPatches not set
#
# Failure handling (AutoRefreshPolicy.FallbackOnScrapeFailure):
#   - "UseBaseline" + Test-PatchBaselineUsable = $true  -> warn + continue
#   - "UseBaseline" + Test-PatchBaselineUsable = $false -> throw
#   - "Abort"                                           -> throw

function Invoke-SetupPhase03_RefreshPatchBaseline {
    <#
    .OUTPUTS
        System.Boolean
    #>
    [OutputType([bool])]
    param()
    Start-DebugTrace -Context 'Invoke-SetupPhase03_RefreshPatchBaseline' -PhaseId 'P03'
    try {
        Set-DebugStep -Step 'check-skip-conditions'

        # ---- Skip conditions ----
        if ($Script:SyntheticTestMode) {
            Write-Skip 'P03 skipped: -SyntheticTestMode disables Catalog scraping.'
            return $true
        }
        if ($Script:SkipDynamicPatchRefresh) {
            Write-Skip 'P03 skipped: -SkipDynamicPatchRefresh explicitly set.'
            return $true
        }
        if ($Script:UseBaselineOnly) {
            Write-Skip 'P03 skipped: -UseBaselineOnly explicitly set.'
            return $true
        }

        # Compute latest Patch Tuesday (used by freshness check)
        Set-DebugStep -Step 'compute-patch-tuesday'
        $latestPT = Get-LatestPatchTuesday
        Write-Step ('Latest Patch Tuesday: {0:yyyy-MM-dd}' -f $latestPT)

        # Decide whether to refresh
        Set-DebugStep -Step 'evaluate-baseline-freshness'
        $baseline = $null
        if ($Script:OsProfile -and (Get-Member -InputObject $Script:OsProfile -Name 'PatchBaseline' -ErrorAction SilentlyContinue)) {
            $baseline = $Script:OsProfile.PatchBaseline
        }
        $isFresh = Test-PatchBaselineFresh -Baseline $baseline -LatestPatchTuesday $latestPT
        $forced  = [bool]$Script:AutoDetectLatestPatches

        if ($isFresh -and -not $forced) {
            Write-Skip ('P03 skipped: PatchBaseline is fresh (PatchTuesdayOfBaseline={0}).' -f $baseline.PatchTuesdayOfBaseline)
            return $true
        }
        if ($forced) {
            Write-Step 'P03: -AutoDetectLatestPatches set; forcing refresh.'
        } else {
            Write-Step 'P03: PatchBaseline is stale; refreshing from Catalog.'
        }

        # Determine target patch month
        Set-DebugStep -Step 'resolve-patch-month'
        $patchMonth = $Script:PatchMonth
        if ([string]::IsNullOrWhiteSpace($patchMonth)) {
            $patchMonth = Format-PatchMonthString -Date $latestPT
        }
        Write-Step ('Target patch month: {0}' -f $patchMonth)

        # Resolve AutoRefreshPolicy
        $policy = $null
        if ($Script:OsProfile -and (Get-Member -InputObject $Script:OsProfile -Name 'AutoRefreshPolicy' -ErrorAction SilentlyContinue)) {
            $policy = $Script:OsProfile.AutoRefreshPolicy
        }
        $writeback = $true
        $fallback  = 'UseBaseline'
        $retries   = 3
        if ($policy) {
            if ($null -ne $policy.WritebackToConfig)        { $writeback = [bool]$policy.WritebackToConfig }
            if ($policy.FallbackOnScrapeFailure)            { $fallback  = [string]$policy.FallbackOnScrapeFailure }
            if ($policy.ScrapeRetries -and $policy.ScrapeRetries -gt 0) { $retries = [int]$policy.ScrapeRetries }
        }

        # ---- Scrape ----
        Set-DebugStep -Step 'invoke-catalog-scrape'
        $newPatches = @()
        $scrapeOk = $true
        $scrapeErr = $null
        try {
            $newPatches = Invoke-CatalogPatchSetRefresh `
                            -OsVersion $Script:OsVersion `
                            -OsLanguage $Script:OsLanguage `
                            -PatchMonth $patchMonth `
                            -MaxRetries $retries
        } catch {
            $scrapeOk  = $false
            $scrapeErr = $_.Exception.Message
            Write-Caution ('Catalog scrape failed: ' + $scrapeErr)
        }
        if ($scrapeOk -and (-not $newPatches -or $newPatches.Count -eq 0)) {
            $scrapeOk  = $false
            $scrapeErr = 'Catalog scrape returned zero entries.'
            Write-Caution $scrapeErr
        }

        # ---- Failure handling ----
        if (-not $scrapeOk) {
            if ($fallback -eq 'Abort') {
                throw ('P03 RefreshPatchBaseline failed and AutoRefreshPolicy.FallbackOnScrapeFailure=Abort. Error: ' + $scrapeErr)
            }
            # UseBaseline (default)
            if (Test-PatchBaselineUsable -Baseline $baseline) {
                Write-Caution 'P03: scrape failed but existing PatchBaseline.Lines is usable; continuing.'
                return $true
            }
            throw ('P03 RefreshPatchBaseline failed AND existing PatchBaseline has no usable patches. Cannot proceed.')
        }

        # ---- Update in-memory profile ----
        Set-DebugStep -Step 'update-in-memory-profile'
        if (-not $Script:OsProfile.PatchBaseline) {
            $Script:OsProfile | Add-Member -NotePropertyName 'PatchBaseline' -NotePropertyValue ([pscustomobject][ordered]@{
                Schema = '2.0'
                TargetBuildAfterUpdate = ''
                PatchTuesdayOfBaseline = ''
                LastVerifiedDate = ''
                LastVerifiedBy = ''
                VerificationMethod = ''
                ChecksumAlgorithm = 'SHA256'
                Lines = @()
                ExcludeKbList = @()
            }) -Force
        }

        # An existing PatchBaseline (loaded from config-*.json) may predate
        # some of the properties written below. PowerShell cannot assign to a
        # NoteProperty that does not yet exist (it throws "property cannot be
        # found ... verify that the property exists and can be set"), and this
        # is identical under ConvertFrom-Json and ConvertFrom-CanonicalJson.
        # Ensure every property assigned below is present before assigning.
        # NOTE: resolved patches are stored under Lines[] per the
        # Config Schema v3.0 (SPEC B.4.3); '.Patches' was a legacy field and
        # MUST NOT be (re)introduced here.
        $pb = $Script:OsProfile.PatchBaseline
        foreach ($propName in @('Lines','PatchTuesdayOfBaseline','LastVerifiedDate','LastVerifiedBy','VerificationMethod')) {
            if (-not $pb.PSObject.Properties[$propName]) {
                $pb | Add-Member -NotePropertyName $propName -NotePropertyValue $null -Force
            }
        }
        $Script:OsProfile.PatchBaseline.Lines         = @($newPatches)
        $Script:OsProfile.PatchBaseline.PatchTuesdayOfBaseline = $latestPT.ToString('yyyy-MM-dd')
        $Script:OsProfile.PatchBaseline.LastVerifiedDate       = (Get-Date).ToString('o')
        $Script:OsProfile.PatchBaseline.LastVerifiedBy         = 'auto-scrape'
        $Script:OsProfile.PatchBaseline.VerificationMethod     = 'auto-scrape'
        Write-Ok ('PatchBaseline updated in memory: {0} patches.' -f $newPatches.Count)

        # ---- Writeback ----
        if ($writeback) {
            Set-DebugStep -Step 'writeback-config'
            try {
                $cfgPath = Get-OsConfigPath -OsKey $Script:OsVersion
                Save-ConfigWithBaseline -ConfigPath $cfgPath -OsProfile $Script:OsProfile
                Write-Ok ('PatchBaseline written back to: ' + $cfgPath)
            } catch {
                Write-Caution ('Writeback to Config JSON failed (in-memory baseline is still updated): ' + $_.Exception.Message)
            }
        } else {
            Write-Step 'AutoRefreshPolicy.WritebackToConfig is false; not persisting changes.'
        }

        # ---- Re-derive $Script:ResolvedPatches from new baseline ----
        Set-DebugStep -Step 'derive-resolved-patches'
        # If the user did not provide an explicit patch source, use the
        # refreshed baseline as the source of truth for P04.
        $userProvidedPatches = ($Script:PatchUrls -and $Script:PatchUrls.Count -gt 0) `
                               -or ($Script:PatchDirectory -and (Test-Path -LiteralPath $Script:PatchDirectory)) `
                               -or ($Script:ManifestPath -and (Test-Path -LiteralPath $Script:ManifestPath))
        if (-not $userProvidedPatches) {
            $derived = New-Object System.Collections.Generic.List[object]
            foreach ($p in $newPatches) {
                # Same LocalPath / ExpectedHashes derivation as the P02
                # baseline-seeding path; see SPEC.md for the empty-
                # LocalPath bug this guards against (would crash P04
                # Step 2 'Patches' at 'Split-Path -LiteralPath').
                $pFileName = $p.FileName
                if (-not $pFileName -and $p.DownloadUrl) {
                    try {
                        $pFileName = [System.IO.Path]::GetFileName(([Uri]$p.DownloadUrl).AbsolutePath)
                    } catch {
                        $pFileName = $null
                    }
                }
                if (-not $pFileName) {
                    $pFileName = ('{0}.msu' -f $p.KbId)
                }
                $expectedHashes = @{}
                if ($p.Sha256) {
                    $expectedHashes['sha-256'] = $p.Sha256
                }
                $derived.Add([pscustomobject][ordered]@{
                    Kind            = 'Patch'
                    Source          = $p.DownloadUrl
                    LocalPath       = Join-Path $Script:PatchesDir (Join-Path $Script:OsVersion $pFileName)
                    KbId            = $p.KbId
                    PatchType       = $p.Type
                    ApplyOrder      = $p.ApplyOrder
                    ExpectedHashes  = $expectedHashes
                }) | Out-Null
            }
            $Script:ResolvedPatches = $derived | Sort-Object ApplyOrder, KbId
            Write-Ok ('Derived {0} patch entries from refreshed baseline.' -f $Script:ResolvedPatches.Count)
        }

        return $true
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P04: Fetch assets (Fetch group)
# ============================================================

function Invoke-FetchPhase04_FetchAssets { # psa-disable-line PSA6003 -- "Assets" is a phase noun; renaming would break the registry-driven dispatcher
    <#
    .SYNOPSIS
        P04: Download the source ISO (if URL-based) and any patch files
        that don't exist locally yet. Honours -SyntheticTestMode.
    #>
    Start-DebugTrace -Context 'Invoke-FetchPhase04_FetchAssets' -PhaseId 'P04'
    try {
        # Synthetic mode: build a tiny synthetic ISO instead of downloading
        if ($Script:SyntheticTestMode) {
            Write-SubSection 'Step 1: Build synthetic ISO (no downloads)'
            Set-DebugStep -Step 'synthetic-iso-build'
            New-SyntheticTestIso -WorkRoot $Script:WorkRoot -OutputIsoPath $Script:IsoLocalPath | Out-Null
            Write-Ok ('Synthetic ISO created: {0}' -f $Script:IsoLocalPath)
            New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P04.ok') -Force | Out-Null
            return
        }

        # Step 1: ISO download
        Write-SubSection 'Step 1: Source ISO'
        Set-DebugStep -Step 'iso-fetch'
        if ($Script:IsoPath) {
            Write-Step 'IsoPath provided; no download needed.'
        } else {
            if (Test-Path -LiteralPath $Script:IsoLocalPath) {
                $existing = (Get-Item -LiteralPath $Script:IsoLocalPath).Length
                if ($existing -gt 100MB) {
                    Write-Ok ('Existing ISO found ({0:F2} GB); skipping download.' -f ($existing / 1GB))
                } else {
                    Write-Caution ('Existing ISO is suspiciously small ({0} bytes); re-downloading.' -f $existing)
                    Remove-Item -LiteralPath $Script:IsoLocalPath -Force
                    $existing = 0
                }
            }
            if (-not (Test-Path -LiteralPath $Script:IsoLocalPath)) {
                $url = Resolve-IsoSourceUrl -LanguageProfile $Script:OsLangProfile -ExplicitUrl $Script:IsoUrl
                Write-Step ('Downloading ISO from: {0}' -f $url)
                $tmpPath = Join-Path ([System.IO.Path]::GetDirectoryName($Script:IsoLocalPath)) `
                                     (('.dl_' + [Guid]::NewGuid().Guid + '.part'))
                Invoke-WebRequestWithRetry -Uri $url -OutFile $tmpPath -MaxAttempts 3
                Move-Item -LiteralPath $tmpPath -Destination $Script:IsoLocalPath -Force
                Write-Ok ('ISO downloaded: {0}' -f $Script:IsoLocalPath)
            }
        }

        # Optional integrity check against config-recorded SHA-256
        # (v2.0: per-language Iso.Sha256 from LanguageSpecific.<lang>.Iso)
        $configSha = $null
        if ($Script:OsLangProfile.Iso -and $Script:OsLangProfile.Iso.Sha256) {
            $configSha = $Script:OsLangProfile.Iso.Sha256
        }
        if ($configSha -and $configSha -notmatch '\(.*\)') {
            Set-DebugStep -Step 'iso-sha256-verify'
            $expected = $configSha.ToLower()
            Write-Step ('Verifying ISO SHA-256 against config (expected {0}...)' -f $expected.Substring(0, 16))
            $actual = (Get-FileHash -LiteralPath $Script:IsoLocalPath -Algorithm SHA256).Hash.ToLower()
            $Script:IsoSha256 = $actual
            if ($actual -ne $expected) {
                throw ('ISO SHA-256 mismatch: expected {0}, got {1}.' -f $expected, $actual)
            }
            Write-Ok 'ISO SHA-256 matches.'
        } else {
            # Record the hash for first-time use; user can copy into data/config-<OsKey>.json
            $Script:IsoSha256 = (Get-FileHash -LiteralPath $Script:IsoLocalPath -Algorithm SHA256).Hash.ToLower()
            Write-Step ('Recorded ISO SHA-256: {0}' -f $Script:IsoSha256)
        }

        # Step 2: Patch downloads
        Write-SubSection 'Step 2: Patches'
        Set-DebugStep -Step 'patch-fetch'
        $targetDir = Join-Path $Script:PatchesDir $Script:OsVersion
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        $idx = 0
        foreach ($p in $Script:ResolvedPatches) {
            $idx++
            $leaf = [System.IO.Path]::GetFileName($p.LocalPath)
            Write-Step ('[{0}/{1}] {2}' -f $idx, $Script:ResolvedPatches.Count, $leaf)

            $isUrl = $p.Source -match '^https?://'
            if ($isUrl) {
                if (Test-Path -LiteralPath $p.LocalPath) {
                    # If we have a hash, verify; otherwise trust existing
                    if ($p.ExpectedHashes.Count -gt 0) {
                        try {
                            Test-PatchIntegrity -FilePath $p.LocalPath -ExpectedHashes $p.ExpectedHashes | Out-Null
                            Write-Ok '  cached and verified; skipping download.'
                            continue
                        } catch {
                            Write-Caution ('  cached file failed integrity check ({0}); re-downloading.' -f $_.Exception.Message)
                            Remove-Item -LiteralPath $p.LocalPath -Force
                        }
                    } else {
                        Write-Ok '  cached (no hash to verify); skipping download.'
                        continue
                    }
                }
                $patchTmp = Join-Path $targetDir ('.dl_' + [Guid]::NewGuid().Guid + '.part')
                Invoke-WebRequestWithRetry -Uri $p.Source -OutFile $patchTmp -MaxAttempts 3
                Move-Item -LiteralPath $patchTmp -Destination $p.LocalPath -Force
                Write-Ok ('  downloaded: {0}' -f $p.LocalPath)
            } else {
                if (-not (Test-Path -LiteralPath $p.Source)) {
                    throw ('Local patch missing: {0}' -f $p.Source)
                }
                if ($p.LocalPath -ne $p.Source) {
                    Copy-Item -LiteralPath $p.Source -Destination $p.LocalPath -Force
                }
                Write-Ok ('  ready: {0}' -f $p.LocalPath)
            }

            # Integrity check (if we have expectations)
            if ($p.ExpectedHashes.Count -gt 0) {
                Test-PatchIntegrity -FilePath $p.LocalPath -ExpectedHashes $p.ExpectedHashes | Out-Null
                Write-Ok '  integrity OK.'
            }
        }

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P04.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P05: Expand source ISO (Plan group)
# ============================================================

function Expand-SourceIso {
    <#
    .SYNOPSIS
        Mount the source ISO, copy its full content tree to
        $Script:ExtractedDir, and dismount.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$IsoFile,
        [Parameter(Mandatory)] [string]$DestRoot
    )
    if (Test-Path -LiteralPath $DestRoot) {
        Set-DebugStep -Step 'extracted-cleanup'
        Remove-Item -LiteralPath $DestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null

    Set-DebugStep -Step 'mount-iso'
    $img = Mount-DiskImage -ImagePath $IsoFile -StorageType ISO -PassThru
    try {
        Start-Sleep -Seconds 1
        $vol = $img | Get-Volume
        $driveLetter = $vol.DriveLetter
        if (-not $driveLetter) {
            throw ('Mounted ISO has no drive letter: {0}' -f $IsoFile)
        }
        $src = ($driveLetter + ':\')
        Set-DebugStep -Step 'copy-from-iso'
        Write-Step ('Copying from {0} to {1} ...' -f $src, $DestRoot)
        # Use robocopy.exe (ships with Windows since Vista) rather
        # than Copy-Item. Copy-Item -LiteralPath on a drive root
        # fails with 'the second path fragment must not be a drive
        # name' because PowerShell's Copy-Item invokes
        # System.IO.Path.Combine internally with the drive name
        # ('E:\') as path2, and Path.Combine rejects rooted paths
        # in that position. robocopy handles the drive-root-as-
        # source case correctly and is 5-10x faster for ISO content
        # (typically ~6 GB across thousands of small files).
        $rcLog = Join-Path $Script:LogsDir 'P05_robocopy.log'
        $rcArgs = @(
            $src, $DestRoot,
            '/E',           # Subdirectories including empty ones
            '/COPY:DAT',    # Data, Attributes, Timestamps only - NTFS ACLs are not meaningful for an ISO copy
            '/R:1',         # Retry once on transient failure
            '/W:1',         # Wait 1 second between retries
            '/NP',          # No per-file progress percentage (console clutter)
            '/NDL',         # No directory list (console clutter)
            '/NFL',         # No file list (console clutter)
            '/NJH',         # No job header
            '/NJS',         # No job summary
            ('/LOG:' + $rcLog)
        )
        & robocopy.exe @rcArgs | Out-Null
        $rcExit = $LASTEXITCODE
        # Robocopy exit codes: 0-7 = success / informational,
        # 8+ = failure (some files not copied / fatal error).
        # See https://learn.microsoft.com/windows-server/administration/windows-commands/robocopy
        if ($rcExit -ge 8) {
            throw ('robocopy failed (exit {0}): see {1}' -f $rcExit, $rcLog)
        }
        Write-Ok ('robocopy exit={0} (0-7 = success), log: {1}' -f $rcExit, $rcLog)
    } finally {
        Set-DebugStep -Step 'dismount-iso'
        try {
            Dismount-DiskImage -ImagePath $IsoFile | Out-Null
        } catch {
            Write-Caution ('Dismount-DiskImage failed: {0}' -f $_.Exception.Message)
        }
    }
}

function Invoke-PlanPhase05_ExpandIso {
    <#
    .SYNOPSIS
        P05: Mount and extract the source ISO; enumerate install.wim
        and boot.wim indexes; emit P04_wim_inventory.csv.
    #>
    Start-DebugTrace -Context 'Invoke-PlanPhase05_ExpandIso' -PhaseId 'P05'
    try {
        Write-SubSection 'Step 1: Expand source ISO'
        Expand-SourceIso -IsoFile $Script:IsoLocalPath -DestRoot $Script:ExtractedDir
        Write-Ok ('Extracted ISO contents to: {0}' -f $Script:ExtractedDir)

        Write-SubSection 'Step 2: Enumerate WIM contents'
        Set-DebugStep -Step 'wim-inventory'
        $installWim = Join-Path $Script:ExtractedDir 'sources\install.wim'
        $bootWim    = Join-Path $Script:ExtractedDir 'sources\boot.wim'

        $rows = New-Object System.Collections.Generic.List[object]
        if (Test-Path -LiteralPath $installWim) {
            Write-Step ('install.wim found: {0}' -f $installWim)
            $invInstall = Get-WimIndexInventory -WimPath $installWim
            foreach ($e in $invInstall) {
                Write-Step ('  install.wim idx {0}: {1} ({2:F2} GB)' -f $e.ImageIndex, $e.ImageName, ($e.ImageSize / 1GB))
                $rows.Add([pscustomobject]@{
                    Wim = 'install.wim'; ImageIndex = $e.ImageIndex
                    ImageName = $e.ImageName; ImageDescription = $e.ImageDescription
                    ImageSizeBytes = $e.ImageSize
                }) | Out-Null
            }
            $Script:WimIndexInventory = $invInstall
        } else {
            if ($Script:SyntheticTestMode) {
                Write-Caution 'No install.wim found; expected in -SyntheticTestMode with fallback shape.'
            } else {
                throw ('install.wim not found at expected path: {0}' -f $installWim)
            }
        }

        if (Test-Path -LiteralPath $bootWim) {
            Write-Step ('boot.wim found: {0}' -f $bootWim)
            $invBoot = Get-WimIndexInventory -WimPath $bootWim
            foreach ($e in $invBoot) {
                Write-Step ('  boot.wim idx {0}: {1}' -f $e.ImageIndex, $e.ImageName)
                $rows.Add([pscustomobject]@{
                    Wim = 'boot.wim'; ImageIndex = $e.ImageIndex
                    ImageName = $e.ImageName; ImageDescription = $e.ImageDescription
                    ImageSizeBytes = $e.ImageSize
                }) | Out-Null
            }
        }

        $csvPath = Join-Path $Script:LogsDir 'P04_wim_inventory.csv'
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Wrote: {0}' -f $csvPath)

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P05.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}


# ============================================================
# Phase P06: ValidatePatchServicing
# ============================================================
# Pass-through placeholder pending the Catalog-model consistency check.
#
# The former wsusscn2 Layer 2 dependency-graph servicing-readiness check was
# removed in the data-source migration (wsusscn2.cab -> Microsoft Update
# Catalog); the offline applicability graph is no longer maintained. Its
# replacement -- a per-PatchModel consistency check over the resolved set
# (required/forbidden Kinds + Digest presence) -- lands here in a later patch.
# Real servicing readiness is still validated on-mount during the build by
# Test-PatchServicingReadinessOnMount (P07/P08).

function Invoke-PlanPhase06_ValidatePatchServicing {
    <#
    .OUTPUTS
        System.Boolean
    #>
    [OutputType([bool])]
    param()
    Start-DebugTrace -Context 'Invoke-PlanPhase06_ValidatePatchServicing' -PhaseId 'P06'
    try {
        # P06: per-PatchModel consistency (runtime mirror of config.schema.json's
        # PatchModel discriminated union; SPEC B.19). The on-mount servicing
        # readiness check still runs in P07/P08 (SPEC B.13).
        $p06OsKey = $Script:OsProfile.OsKey
        $p06Model = $Script:OsProfile.PatchModel
        $p06Lines = @($Script:OsProfile.PatchBaseline.Lines)
        $p06 = Test-PatchModelConsistency -OsKey $p06OsKey -PatchModel $p06Model -Lines $p06Lines
        if (-not $p06.IsConsistent) {
            throw ("P06 ValidatePatchServicing FAILED for {0} (PatchModel '{1}'): {2}." -f $p06OsKey, $p06Model, ($p06.Errors -join '; '))
        }
        Write-Ok ("P06 ValidatePatchServicing: {0} PatchModel '{1}' consistent ({2} Lines)." -f $p06OsKey, $p06Model, $p06Lines.Count)
        return $true
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P07: Patch install.wim (Build group)
# ============================================================
#
# Patch selection is driven by the PatchPlan engine
# (Build-PatchPlan in .build_part09c_patchplan.ps1) which consults
# $Script:PatchTargetMap to decide which patches belong to which
# WIM target. The legacy Get-PatchListForInstallWim /
# Get-PatchListForBootWim helpers remain as thin wrappers around
# the PatchPlan API so that downstream code paths (and any caller
# in P08) keep their existing call sites without surgery.

function Get-OrInitPatchPlan {
    <#
    .SYNOPSIS
        Return the cached $Script:PatchPlan; build it on first access.
    .DESCRIPTION
        Lazy initialisation lets phases that don't need the plan (e.g.
        P03 admin path) avoid the construction cost, while ensuring
        each phase that DOES need it sees the same plan instance.
    #>
    if (-not $Script:PatchPlan) {
        $Script:PatchPlan = Build-PatchPlan -Patches $Script:ResolvedPatches
    }
    return $Script:PatchPlan
}

function Get-PatchListForInstallWim {
    # Delegate to PatchPlan; preserves legacy call-site signature.
    $plan = Get-OrInitPatchPlan
    return @($plan.Install)
}

function Get-PatchListForBootWim {
    # Delegate to PatchPlan; preserves legacy call-site signature.
    $plan = Get-OrInitPatchPlan
    return @($plan.Boot)
}

function Get-PatchListForWinReWim {
    # WinRE has its own target lane (Safe OS DU and language packs).
    $plan = Get-OrInitPatchPlan
    return @($plan.WinRE)
}

function Resolve-InstallWimTargetIndexes { # psa-disable-line PSA6003 -- "Indexes" is plural by design; returns a filtered list of WIM image indexes
    # Resolve which install.wim indexes to update based on -OnlyInstallWimIndexes
    # and the Config InstallWimIndexes ("all" or array).
    param([Parameter(Mandatory)] $Inventory)

    if (-not [string]::IsNullOrEmpty($Script:OnlyInstallWimIndexes)) {
        $wanted = @($Script:OnlyInstallWimIndexes -split ',' | ForEach-Object { [int]($_.Trim()) })
        return @($Inventory | Where-Object { $wanted -contains $_.ImageIndex })
    }
    $cfg = $Script:OsProfile.InstallWimIndexes
    if ($cfg -is [string] -and $cfg -eq 'all') {
        return @($Inventory)
    }
    if ($cfg) {
        $wanted = @($cfg | ForEach-Object { [int]$_ })
        return @($Inventory | Where-Object { $wanted -contains $_.ImageIndex })
    }
    return @($Inventory)
}

function Invoke-BuildPhase07_PatchInstallWim {
    <#
    .SYNOPSIS
        P07: For every install.wim image index, mount, apply SSU/LCU/
        .NET/Dynamic Update Component, run DISM cleanup, dismount.
        Emits P05_patch_inventory.csv.
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase07_PatchInstallWim' -PhaseId 'P07'
    try {
        if (-not $Script:OsProfile.EnableInstallWimUpdate) {
            Write-Skip 'EnableInstallWimUpdate is false in profile; skipping P07.'
            return
        }
        $installWim = Join-Path $Script:ExtractedDir 'sources\install.wim'
        if (-not (Test-Path -LiteralPath $installWim)) {
            if ($Script:SyntheticTestMode) {
                Write-Skip 'install.wim absent in -SyntheticTestMode; skipping P07.'
                return
            }
            throw ('install.wim missing: {0}' -f $installWim)
        }

        # Sandbox-mode safety: require -Execute for write operations
        if (-not $Script:Execute -and -not $Script:SyntheticTestMode) {
            Write-Caution 'Running in Sandbox mode (no -Execute). Will list intended actions only.'
        }

        $patches = Get-PatchListForInstallWim
        Write-Step ('install.wim-targeted patches: {0}' -f $patches.Count)

        # Pull the install sub-phase sequence (I1.SSU ... I7.LCU.SecondPass)
        # from the cached PatchPlan. The plan was built in P02.
        $plan = Get-OrInitPatchPlan
        $installSequence = @($plan.InstallSequence)
        Write-Step ('install.wim apply sequence: {0} sub-phase(s)' -f $installSequence.Count)
        foreach ($sp in $installSequence) {
            $patchCount = if ($sp.Patches) { @($sp.Patches).Count } else { 0 }
            $marker = if ($sp.PSObject.Properties['IsCleanupMarker'] -and $sp.IsCleanupMarker) { ' [cleanup]' } else { '' }
            $remount = if ($sp.RequiresRemount) { ' [REMOUNT]' } else { '' }
            Write-Step ('    {0,-24} ({1} patch(es)){2}{3}' -f $sp.Name, $patchCount, $marker, $remount)
        }

        $targets = Resolve-InstallWimTargetIndexes -Inventory $Script:WimIndexInventory
        Write-Step ('install.wim indexes to update: {0}' -f ($targets | Measure-Object).Count)

        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($img in $targets) {
            Write-SubSection ('install.wim index {0}: {1}' -f $img.ImageIndex, $img.ImageName)
            Set-DebugStep -Step ('install-idx-' + $img.ImageIndex)
            $imgLabel = ('install.wim:idx' + $img.ImageIndex)

            # In Plan (non-Execute) mode emit the planned row for every
            # sub-phase + patch and skip the real DISM work. This is
            # the mode CI Stage 2 / Stage 3 DryRun runs use.
            if (-not $Script:Execute -and -not $Script:SyntheticTestMode) {
                foreach ($sp in $installSequence) {
                    foreach ($p in @($sp.Patches)) {
                        if (-not $p) { continue }
                        Write-Step ('  [PLAN] {0}: {1} ({2}) -> {3}' -f $sp.Name, $p.KbId, $p.Type, $imgLabel)
                        $rows.Add([pscustomobject]@{
                            KbId = $p.KbId; PatchType = $p.Kind
                            FilePath = $p.LocalPath; ApplyOrder = $p.ApplyOrder
                            AppliesTo = $imgLabel; SubPhase = $sp.Name
                            ApplyStatus = 'Planned'; ElapsedSeconds = 0
                            DismExitCode = 0
                        }) | Out-Null
                    }
                }
                continue
            }

            # Microsoft media-dynamic-update sequence requires that the
            # install.wim be mounted, traversed through I1..I6 in order,
            # then dismounted+committed+exported, and finally re-mounted
            # for I7 (LCU second pass) IFF a language pack was injected.
            # The Build-InstallApplySequence helper marks I7 with
            # RequiresRemount = $true. We honour that by closing the
            # first mount on the cleanup marker and opening a fresh one
            # for any RequiresRemount sub-phase.

            $remountAndContinue = $false
            $secondPassSubPhases = New-Object System.Collections.Generic.List[object]
            Set-DebugStep -Step ('mount-install-pass1-idx-' + $img.ImageIndex)
            Invoke-WimMountSafe -ImagePath $installWim -Index $img.ImageIndex `
                -Path $Script:MountInstallDir -LogDir $Script:LogsDir | Out-Null
            try {
                # Pre-apply dependency closure check on the first-pass mount.
                # Combine all first-pass patches into the check.
                $firstPassPatches = @($installSequence | Where-Object {
                    -not ($_.PSObject.Properties['IsCleanupMarker'] -and $_.IsCleanupMarker) -and
                    -not $_.RequiresRemount
                } | ForEach-Object { $_.Patches }) | Where-Object { $_ }
                Set-DebugStep -Step ('depcheck-install-idx-' + $img.ImageIndex)
                Test-PatchServicingReadinessOnMount -MountPath $Script:MountInstallDir `
                    -PatchesToApply $firstPassPatches `
                    -ImageLabel $imgLabel | Out-Null

                # Iterate sub-phases in order; deferred (RequiresRemount=$true)
                # sub-phases are stashed for execution after dismount + export.
                foreach ($sp in $installSequence) {
                    if ($sp.PSObject.Properties['IsCleanupMarker'] -and $sp.IsCleanupMarker) {
                        Set-DebugStep -Step ('cleanup-install-idx-' + $img.ImageIndex)
                        Invoke-DismCleanup -MountPath $Script:MountInstallDir
                        continue
                    }
                    if ($sp.RequiresRemount) {
                        Write-Step ('  Deferring sub-phase {0} until after dismount+export.' -f $sp.Name)
                        $secondPassSubPhases.Add($sp) | Out-Null
                        $remountAndContinue = $true
                        continue
                    }
                    $spRows = Invoke-PatchSubPhase -SubPhase $sp -MountPath $Script:MountInstallDir -ImageLabel $imgLabel
                    foreach ($r in $spRows) {
                        $rows.Add([pscustomobject]@{
                            KbId = $r.KbId; PatchType = $r.PatchType
                            FilePath = $r.FilePath; ApplyOrder = 0
                            AppliesTo = $r.ImageLabel; SubPhase = $r.SubPhase
                            ApplyStatus = $r.ApplyStatus
                            ElapsedSeconds = [Math]::Round($r.ElapsedSec, 2)
                            DismExitCode = if ($r.ApplyStatus -eq 'Fail') { -1 } else { 0 }
                        }) | Out-Null
                    }
                }
            } finally {
                Set-DebugStep -Step ('dismount-install-pass1-idx-' + $img.ImageIndex)
                Invoke-WimDismountSafe -Path $Script:MountInstallDir -LogDir $Script:LogsDir
            }

            # Second-pass: LCU re-apply when LP was actually injected.
            # Mount the just-exported image fresh, run the deferred
            # sub-phases, cleanup + export again.
            if ($remountAndContinue -and $secondPassSubPhases.Count -gt 0) {
                Write-Step ('  Re-mounting install.wim idx {0} for LCU second pass ({1} sub-phase(s)).' -f $img.ImageIndex, $secondPassSubPhases.Count)
                Set-DebugStep -Step ('mount-install-pass2-idx-' + $img.ImageIndex)
                Invoke-WimMountSafe -ImagePath $installWim -Index $img.ImageIndex `
                    -Path $Script:MountInstallDir -LogDir $Script:LogsDir | Out-Null
                try {
                    foreach ($sp in $secondPassSubPhases) {
                        $spRows = Invoke-PatchSubPhase -SubPhase $sp -MountPath $Script:MountInstallDir -ImageLabel ($imgLabel + ':pass2')
                        foreach ($r in $spRows) {
                            $rows.Add([pscustomobject]@{
                                KbId = $r.KbId; PatchType = $r.PatchType
                                FilePath = $r.FilePath; ApplyOrder = 0
                                AppliesTo = $r.ImageLabel; SubPhase = $r.SubPhase
                                ApplyStatus = $r.ApplyStatus
                                ElapsedSeconds = [Math]::Round($r.ElapsedSec, 2)
                                DismExitCode = if ($r.ApplyStatus -eq 'Fail') { -1 } else { 0 }
                            }) | Out-Null
                        }
                    }
                    Set-DebugStep -Step ('cleanup-install-pass2-idx-' + $img.ImageIndex)
                    Invoke-DismCleanup -MountPath $Script:MountInstallDir
                } finally {
                    Set-DebugStep -Step ('dismount-install-pass2-idx-' + $img.ImageIndex)
                    Invoke-WimDismountSafe -Path $Script:MountInstallDir -LogDir $Script:LogsDir
                }
            }
        }

        # Recover install.wim size with a single Export-Image /Compress:max pass
        # over all indexes (default ON; -SkipExportCompress opts out). Replaces the
        # /ResetBase size reclamation - now off by default - without the per-index
        # /ResetBase time cost.
        if ($Script:SkipExportCompress) {
            Write-Skip 'Export-Image /Compress:max skipped (-SkipExportCompress); install.wim left as serviced.'
        } elseif ($Script:Execute -and -not $Script:SyntheticTestMode) {
            Set-DebugStep -Step 'export-install-compress'
            Export-InstallWimCompressed -WimPath $installWim
        }

        $csvPath = Join-Path $Script:LogsDir 'P05_patch_inventory.csv'
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Wrote: {0}' -f $csvPath)

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P07.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P08: Patch boot.wim + winre.wim (Build group)
# ============================================================

function Invoke-BuildPhase08_PatchBootWim {
    <#
    .SYNOPSIS
        P08: Apply SSU/LCU/SafeOs DU to boot.wim indexes (PE + Setup)
        and to winre.wim (extracted from install.wim).
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase08_PatchBootWim' -PhaseId 'P08'
    try {
        if (-not $Script:OsProfile.EnableBootWimUpdate) {
            Write-Skip 'EnableBootWimUpdate is false in profile; skipping P08.'
            return
        }
        $bootWim = Join-Path $Script:ExtractedDir 'sources\boot.wim'
        if (-not (Test-Path -LiteralPath $bootWim)) {
            if ($Script:SyntheticTestMode) {
                Write-Skip 'boot.wim absent in -SyntheticTestMode; skipping P08.'
                return
            }
            throw ('boot.wim missing: {0}' -f $bootWim)
        }

        if (-not $Script:Execute -and -not $Script:SyntheticTestMode) {
            Write-Caution 'Running in Sandbox mode (no -Execute); skipping boot.wim modifications.'
            return
        }

        $patches = Get-PatchListForBootWim
        Write-Step ('boot.wim-targeted patches: {0}' -f $patches.Count)

        $bootIndexes = @($Script:OsProfile.BootWimIndexes)
        if (-not $bootIndexes -or $bootIndexes.Count -eq 0) {
            $bootIndexes = @(1, 2)
        }

        # Pull boot.wim apply sequence (B1.SSU -> B2.LP -> B3.LCU -> B4.cleanup)
        $plan = Get-OrInitPatchPlan
        $bootSequence = @($plan.BootSequence)
        Write-Step ('boot.wim apply sequence: {0} sub-phase(s)' -f $bootSequence.Count)

        foreach ($idx in $bootIndexes) {
            Write-SubSection ('boot.wim index {0}' -f $idx)
            Set-DebugStep -Step ('boot-idx-' + $idx)
            $imgLabel = ('boot.wim:idx' + $idx)

            $mountDir = $Script:MountBoot1Dir
            if ($idx -eq 2) { $mountDir = $Script:MountBoot2Dir }

            Invoke-WimMountSafe -ImagePath $bootWim -Index $idx `
                -Path $mountDir -LogDir $Script:LogsDir | Out-Null
            try {
                # Dependency closure check on the union of all sub-phase patches
                $allBootPatches = @($bootSequence | Where-Object {
                    -not ($_.PSObject.Properties['IsCleanupMarker'] -and $_.IsCleanupMarker)
                } | ForEach-Object { $_.Patches }) | Where-Object { $_ }
                Test-PatchServicingReadinessOnMount -MountPath $mountDir `
                    -PatchesToApply $allBootPatches `
                    -ImageLabel $imgLabel | Out-Null

                foreach ($sp in $bootSequence) {
                    if ($sp.PSObject.Properties['IsCleanupMarker'] -and $sp.IsCleanupMarker) {
                        Invoke-DismCleanup -MountPath $mountDir
                        continue
                    }
                    Invoke-PatchSubPhase -SubPhase $sp -MountPath $mountDir -ImageLabel $imgLabel | Out-Null
                }
            } finally {
                Invoke-WimDismountSafe -Path $mountDir -LogDir $Script:LogsDir
            }
        }

        # winre.wim (extracted from install.wim)
        if ($Script:OsProfile.EnableWinREUpdate) {
            Write-SubSection 'winre.wim (extracted from install.wim)'
            Set-DebugStep -Step 'winre-extract'
            $installWim = Join-Path $Script:ExtractedDir 'sources\install.wim'
            $primaryIdx = ($Script:WimIndexInventory | Select-Object -First 1).ImageIndex
            if (-not $primaryIdx) { $primaryIdx = 1 }

            Invoke-WimMountSafe -ImagePath $installWim -Index $primaryIdx `
                -Path $Script:MountInstallDir -LogDir $Script:LogsDir | Out-Null
            $winReInside = Join-Path $Script:MountInstallDir 'Windows\System32\Recovery\Winre.wim'
            $winReWork = Join-Path $Script:TempDir 'winre_work.wim'
            try {
                if (-not (Test-Path -LiteralPath $winReInside)) {
                    Write-Caution 'Winre.wim not found inside install.wim; skipping winre update.'
                } else {
                    # Pull WinRE apply sequence (W1.SSU -> W2.LP -> W3.SafeOsDU -> W4.cleanup)
                    $winReSequence = @($plan.WinReSequence)
                    $winReHasWork = ($winReSequence | Where-Object {
                        -not ($_.PSObject.Properties['IsCleanupMarker'] -and $_.IsCleanupMarker) -and
                        @($_.Patches).Count -gt 0
                    } | Measure-Object).Count -gt 0
                    if (-not $winReHasWork) {
                        Write-Step 'WinRE sequence has no patches; skipping WinRE mount.'
                    } else {
                        Write-Step ('winre.wim apply sequence: {0} sub-phase(s)' -f $winReSequence.Count)
                        Copy-Item -LiteralPath $winReInside -Destination $winReWork -Force
                        # winre.wim is typically a single-index image
                        Invoke-WimMountSafe -ImagePath $winReWork -Index 1 `
                            -Path $Script:MountWinReDir -LogDir $Script:LogsDir | Out-Null
                        try {
                            # Dependency closure for WinRE
                            $allWinRePatches = @($winReSequence | Where-Object {
                                -not ($_.PSObject.Properties['IsCleanupMarker'] -and $_.IsCleanupMarker)
                            } | ForEach-Object { $_.Patches }) | Where-Object { $_ }
                            Test-PatchServicingReadinessOnMount -MountPath $Script:MountWinReDir `
                                -PatchesToApply $allWinRePatches `
                                -ImageLabel 'winre.wim' | Out-Null

                            foreach ($sp in $winReSequence) {
                                if ($sp.PSObject.Properties['IsCleanupMarker'] -and $sp.IsCleanupMarker) {
                                    Invoke-DismCleanup -MountPath $Script:MountWinReDir
                                    continue
                                }
                                Invoke-PatchSubPhase -SubPhase $sp `
                                    -MountPath $Script:MountWinReDir `
                                    -ImageLabel 'winre.wim' | Out-Null
                            }
                        } finally {
                            Invoke-WimDismountSafe -Path $Script:MountWinReDir -LogDir $Script:LogsDir
                        }
                        # Copy the freshly-serviced WinRE back into install.wim's
                        # recovery slot. The outer install.wim mount is still
                        # open at this point, so the file write commits when
                        # the install.wim dismount in our finally block runs.
                        Copy-Item -LiteralPath $winReWork -Destination $winReInside -Force
                    }
                }
            } finally {
                Invoke-WimDismountSafe -Path $Script:MountInstallDir -LogDir $Script:LogsDir
            }
        }

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P08.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P09: Assemble updated ISO (Build group)
# ============================================================

function Invoke-BuildPhase09_AssembleIso {
    <#
    .SYNOPSIS
        P09: Apply Dynamic Update Setup overlay onto sources\, run
        New-BootableIso (oscdimg) to produce the final ISO.
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase09_AssembleIso' -PhaseId 'P09'
    try {
        Write-SubSection 'Step 1: Dynamic Update Setup overlay'
        Set-DebugStep -Step 'dynup-setup-overlay'
        $setupDuPatches = @($Script:ResolvedPatches | Where-Object { $_.PatchType -eq 'SetupDU' })
        if ($setupDuPatches.Count -gt 0 -and -not $Script:SyntheticTestMode) {
            foreach ($p in $setupDuPatches) {
                Write-Step ('Overlaying {0} onto extracted ISO sources\' -f $p.KbId)
                # Dynamic Update Setup CABs are extracted with expand.exe and
                # files are copied into the sources\ tree
                $tmpExtract = Join-Path $Script:TempDir ('dynup_' + $p.KbId)
                if (Test-Path -LiteralPath $tmpExtract) {
                    Remove-Item -LiteralPath $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
                }
                New-Item -ItemType Directory -Path $tmpExtract -Force | Out-Null
                & expand.exe -F:* $p.LocalPath $tmpExtract | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    # -Path (not -LiteralPath) is required when the
                    # source contains a wildcard. -LiteralPath would
                    # look for a file literally named '*' and fail
                    # with 'Cannot find path'.
                    Copy-Item -Path (Join-Path $tmpExtract '*') `
                        -Destination (Join-Path $Script:ExtractedDir 'sources') -Recurse -Force
                    Write-Ok ('Overlay applied: {0}' -f $p.KbId)
                } else {
                    Write-Caution ('expand.exe failed for {0}; skipping overlay.' -f $p.KbId)
                }
            }
        } else {
            Write-Skip 'No Dynamic Update Setup patches to overlay.'
        }

        # Step 2: Build output ISO
        Write-SubSection 'Step 2: Build output ISO (oscdimg)'
        Set-DebugStep -Step 'output-iso-name'
        $monthTag = (Get-Date -Format 'yyyy-MM')
        $outName = ('{0}_{1}_Updated_{2}.iso' -f $Script:OsProfile.OsShortName, $Script:OsLanguage, $monthTag)
        $Script:OutputIsoPath = Join-Path $Script:OutputDir $outName
        Write-Step ('Output: {0}' -f $Script:OutputIsoPath)

        $monthCompact = (Get-Date -Format 'yyyyMM')
        $label = ('{0}_UP_{1}' -f $Script:OsLangProfile.VolumeLabelPrefix, $monthCompact)

        if ($Script:SyntheticTestMode) {
            # In synthetic mode, the source ISO IS the output ISO
            Copy-Item -LiteralPath $Script:IsoLocalPath -Destination $Script:OutputIsoPath -Force
            Write-Ok ('Synthetic output ISO: {0}' -f $Script:OutputIsoPath)
        } else {
            if (-not $Script:Execute) {
                Write-Skip 'Sandbox mode (no -Execute); skipping oscdimg run.'
            } else {
                Set-DebugStep -Step 'oscdimg-build'
                New-BootableIso -ExtractedIsoRoot $Script:ExtractedDir `
                    -OutputIsoPath $Script:OutputIsoPath `
                    -VolumeLabel $label | Out-Null
                Write-Ok ('Built output ISO: {0}' -f $Script:OutputIsoPath)
            }
        }

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P09.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}


# ============================================================
# Phase P10: Convert boot manager to PCA2023-signed (Build group, OPTIONAL)
# ============================================================
# This phase is OPT-IN. It runs only when -EnablePca2023BootManager
# is specified, AND (for Server 2025 specifically) when
# -ForcePca2023OnServer2025 is also specified. Default behaviour
# leaves the ISO with PCA2011-signed boot manager, which still
# boots on every Secure Boot firmware shipped before 2026-06.
#
# Group classification note: P10 lives inside the Build group as
# a Build-group OPTIONAL phase (the only Build-group phase that
# is not always-on). The other Build phases (P07/P08/P09) are
# always-on because they are the core ISO assembly pipeline.
# See SPEC.md B.20 for the design rationale.
# ============================================================

function Invoke-BuildPhase10_ConvertPca2023BootManager {
    <#
    .SYNOPSIS
        P10: Rewrite the output ISO's boot manager to be signed via
        the 'Windows UEFI CA 2023' chain instead of 'Windows Production
        PCA 2011'. Required for booting under firmware that has
        revoked PCA2011 trust (post 2026-06 expiry, post BlackLotus
        CVE-2023-24932 mitigation).

        Implementation: calls Convert-WimBootToPca2023Signed (this
        script's PSA-clean re-implementation of Microsoft's
        Copy-2023BootBins from Make2023BootableMedia.ps1), OR
        invokes an external Make2023BootableMedia.ps1 if the user
        passed -Pca2023ScriptPath.

        Re-runs Get-OrEnsurePca2023Snapshot -Force after the
        conversion so P11/P12/P13 see the updated state.

        Skip conditions (all silent skip, recorded in result):
          - -EnablePca2023BootManager not set
          - OsKey == 'Server2025' AND -ForcePca2023OnServer2025 not set
          - Pre-flight readiness Health == 'Critical' (LCU prereq
            not met; we would only produce a corrupted ISO -- this
            is a SKIP, not a throw, so dry-run inspection can
            proceed to P11+)
          - Pre-flight readiness Health == 'Healthy' (already signed,
            nothing to do)
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase10_ConvertPca2023BootManager' -PhaseId 'P10'
    try {
        Write-SubSection 'Step 1: Pre-flight gates'
        Set-DebugStep -Step 'gate-EnablePca2023BootManager'

        if (-not $Script:EnablePca2023BootManager) {
            Write-Step 'Skipped: -EnablePca2023BootManager not specified (default OFF).'
            New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P10.skipped') -Force | Out-Null
            return
        }

        Set-DebugStep -Step 'gate-Server2025'
        $osKey = if ($Script:OsProfile) { $Script:OsProfile.OsKey } else { $null }
        Write-Step ('OsKey: {0}' -f $osKey)
        if ($osKey -eq 'Server2025' -and -not $Script:ForcePca2023OnServer2025) {
            Write-Step ('Skipped: OsKey={0}. Server 2025 firmware already includes 2023 certs.' -f $osKey)
            Write-Step '         Pass -ForcePca2023OnServer2025 to override (advanced use only).'
            New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P10.skipped') -Force | Out-Null
            return
        }

        Set-DebugStep -Step 'gate-ExtractedDir'
        # The extracted media path is set up by P05 ExpandIso into
        # $Script:ExtractedDir (initialised at script-scope, around
        # L496: Join-Path $Script:SourceDir 'extracted'). The variable
        # rename to $ExtractedMediaPath is only inside the PCA2023
        # helper API surface; the script-scope global keeps the
        # original "ExtractedDir" name.
        $extractedPath = if ($Script:ExtractedDir) { $Script:ExtractedDir } else { $null }
        if (-not $extractedPath -or -not (Test-Path -LiteralPath $extractedPath)) {
            throw 'P10 requires P05 ExpandIso to have produced an extracted media tree. Run -Action All or -Action Build.'
        }
        Write-Step ('Extracted media path: {0}' -f $extractedPath)
        Write-Step 'Pre-flight gates: all passed.'

        # ---- Step 2: Pre-flight readiness snapshot ----
        Write-SubSection 'Step 2: Boot manager readiness snapshot (pre-conversion)'
        Set-DebugStep -Step 'preflight-readiness'
        Write-Step 'Inspecting boot.wim + install.wim for PCA2023 readiness...'
        Write-Step '  (this mounts each WIM read-only and enumerates installed packages;'
        Write-Step '   typical runtime 1-3 minutes for Server 2016/2019/2022 media)'
        $snapshotStart = Get-Date
        $pre = Get-OrEnsurePca2023Snapshot `
            -ExtractedMediaPath $extractedPath `
            -WorkRoot $Script:WorkRoot `
            -OsKey $osKey
        $snapshotElapsed = [int](New-TimeSpan -Start $snapshotStart -End (Get-Date)).TotalSeconds
        Write-Step ('Snapshot Health = {0} (computed in {1}s)' -f $pre.Health, $snapshotElapsed)
        if ($pre.Health -eq 'Critical') {
            # SKIP, not throw: the prereq mismatch is informational
            # for dry-run inspection (PrepareBuildVerify). The
            # downstream phases (P11 StaticVerify, P12 VerifyPca2023Readiness,
            # P13 FinalReport) can still run and surface this state
            # in the final report. A hard throw here would abort
            # PrepareBuildVerify prematurely, hiding the rest of the
            # inspection from the user.
            Write-Caution ('P10 SKIPPED: snapshot Health is ''Critical''. The source media does not meet the 2024-4B (April 2024 LCU) prerequisite for PCA2023 boot manager conversion.')
            foreach ($r in $pre.Reasons) {
                Write-Caution ('  - {0}' -f $r)
            }
            Write-Caution 'To enable PCA2023 conversion on this OS, two conditions must be met:'
            Write-Caution '  1. Profile EnableInstallWimUpdate=true (so P07 applies LCUs to install.wim)'
            Write-Caution '  2. Patch baseline must include the 2024-4B LCU (KB5036899) or a later LCU'
            Write-Caution '     Server 2016/2019/2022 EVAL ISOs ship with 2016/2019/2022-era builds and need years of LCUs first.'
            Write-Caution 'P11 StaticVerify, P12 VerifyPca2023Readiness, and P13 FinalReport will still run and record this state.'
            New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P10.skipped') -Force | Out-Null
            return
        }
        if ($pre.Health -eq 'Healthy') {
            Write-Step 'Skipped: ISO is ALREADY PCA2023-signed (Health=Healthy). No conversion needed.'
            New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P10.skipped') -Force | Out-Null
            return
        }
        Write-Step ('Pre-flight OK: Health={0}. Proceeding with conversion.' -f $pre.Health)

        # ---- Step 3: Run the conversion ----
        Write-SubSection 'Step 3: Convert boot manager to PCA2023 signing'
        Set-DebugStep -Step 'conversion'
        $convResult = $null
        if ($Script:Pca2023ScriptPath) {
            Write-Step ('Using external script: {0}' -f $Script:Pca2023ScriptPath)
            if (-not (Test-Path -LiteralPath $Script:Pca2023ScriptPath)) {
                throw ('External -Pca2023ScriptPath does not exist: {0}' -f $Script:Pca2023ScriptPath)
            }
            # Invoke the external Make2023BootableMedia.ps1 in a child PS
            # process so its globals stay isolated from our session.
            $isoOut = $Script:OutputIsoPath
            $childArgs = @(
                '-NoProfile', '-NonInteractive',
                '-File', $Script:Pca2023ScriptPath,
                '-MediaPath', $extractedPath,
                '-TargetType', 'ISO',
                '-ISOPath', $isoOut
            )
            Write-Step ('Invoking child pwsh with -MediaPath {0} -TargetType ISO -ISOPath {1}' -f $extractedPath, $isoOut)
            $stdout = & pwsh @childArgs 2>&1
            $childExit = $LASTEXITCODE
            $stdout | ForEach-Object { Write-Step ('  [child] {0}' -f $_) }
            if ($childExit -ne 0) {
                throw ('External Make2023BootableMedia.ps1 exited {0}' -f $childExit)
            }
            $convResult = [pscustomobject]@{
                Success      = $true
                FilesUpdated = @('(handled by external script)')
                ErrorMessage = $null
            }
        } else {
            Write-Step 'Using internal Convert-WimBootToPca2023Signed (PSA-clean implementation).'
            $convStart = Get-Date
            $convResult = Convert-WimBootToPca2023Signed `
                -ExtractedMediaPath $extractedPath `
                -WorkRoot $Script:WorkRoot
            $convElapsed = [int](New-TimeSpan -Start $convStart -End (Get-Date)).TotalSeconds
            Write-Step ('Convert-WimBootToPca2023Signed completed in {0}s' -f $convElapsed)
            if (-not $convResult.Success) {
                throw ('Convert-WimBootToPca2023Signed failed: {0}' -f $convResult.ErrorMessage)
            }
        }

        Write-Step ('PCA2023 conversion succeeded. Files updated: {0}' -f $convResult.FilesUpdated.Count)
        foreach ($f in $convResult.FilesUpdated) {
            Write-Step ('  - {0}' -f $f)
        }

        # ---- Step 4: Re-assemble ISO + post-flight verification ----
        Write-SubSection 'Step 4: Re-assemble ISO and post-flight verification'
        # If the user already produced an output ISO in P09, that ISO
        # is now stale: the on-disk file still has the old PCA2011 boot
        # manager. We need to regenerate it from the (now-updated)
        # extracted media tree.
        if ($Script:OutputIsoPath -and (Test-Path -LiteralPath $Script:OutputIsoPath)) {
            Set-DebugStep -Step 'reassemble-iso'
            Write-Step 'Regenerating output ISO from updated extracted media (oscdimg)...'
            # Reuse the existing oscdimg-based assembly helper. The
            # volume label is recovered from the existing output ISO's
            # filename root (Windows Server ISO labels are typically
            # the basename of the .iso file).
            $isoLabel = [System.IO.Path]::GetFileNameWithoutExtension($Script:OutputIsoPath)
            $reasmStart = Get-Date
            New-BootableIso `
                -ExtractedIsoRoot $extractedPath `
                -OutputIsoPath $Script:OutputIsoPath `
                -VolumeLabel $isoLabel | Out-Null
            $reasmElapsed = [int](New-TimeSpan -Start $reasmStart -End (Get-Date)).TotalSeconds
            Write-Step ('ISO re-assembled in {0}s: {1}' -f $reasmElapsed, $Script:OutputIsoPath)
        } else {
            Write-Step 'No output ISO file present (Sandbox/PrepareBuildVerify mode); skipping re-assembly.'
        }

        # ---- Force-refresh the snapshot so downstream phases see new state ----
        Set-DebugStep -Step 'post-flight-snapshot'
        Write-Step 'Re-inspecting boot manager state (post-conversion)...'
        $postStart = Get-Date
        $post = Get-OrEnsurePca2023Snapshot `
            -ExtractedMediaPath $extractedPath `
            -WorkRoot $Script:WorkRoot `
            -OsKey $osKey `
            -Force
        $postElapsed = [int](New-TimeSpan -Start $postStart -End (Get-Date)).TotalSeconds
        Write-Step ('Post-flight snapshot Health = {0} (computed in {1}s)' -f $post.Health, $postElapsed)

        # ---- Test-OutputIsoPca2023Readiness: post-build file-based check ----
        # Run an output-side verification against the five Microsoft
        # conversion targets (SPEC.md B.18). The result is stashed on
        # the snapshot so P12 / P13 see the same authoritative data.
        Set-DebugStep -Step 'post-flight-output-check'
        Write-Step 'Running output-ISO PCA2023 readiness check (5-target file inspection)...'
        $ocStart = Get-Date
        $outputCheck = Test-OutputIsoPca2023Readiness -ExtractedMediaPath $extractedPath
        $ocElapsed = [int](New-TimeSpan -Start $ocStart -End (Get-Date)).TotalSeconds
        $post.OutputCheck = $outputCheck
        Write-Step ('Output ISO check OverallStatus = {0} (computed in {1}s)' -f $outputCheck.OverallStatus, $ocElapsed)
        Show-Pca2023ReadinessSnapshot -Snapshot $post -Compact -OutputCheck $outputCheck

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P10.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}


# ============================================================
# Phase P11: Static verification (Verify group)
# ============================================================

function Invoke-VerifyPhase11_StaticVerify {
    <#
    .SYNOPSIS
        P11: Verify the output ISO without booting it. Mounts the ISO,
        verifies presence of install.wim/boot.wim/setup.exe, runs
        Get-WindowsImage and Get-WindowsPackage to check that the
        expected KB packages have been integrated. Emits
        P11_verification.csv.
    #>
    Start-DebugTrace -Context 'Invoke-VerifyPhase11_StaticVerify' -PhaseId 'P11'
    try {
        if ([string]::IsNullOrEmpty($Script:OutputIsoPath)) {
            # Recover from a Verify-only run
            $monthTag = (Get-Date -Format 'yyyy-MM')
            $outName = ('{0}_{1}_Updated_{2}.iso' -f $Script:OsProfile.OsShortName, $Script:OsLanguage, $monthTag)
            $Script:OutputIsoPath = Join-Path $Script:OutputDir $outName
        }

        $rows = New-Object System.Collections.Generic.List[object]
        function Add-VRow {
            param([string]$Check, [string]$Expected, [string]$Actual, [string]$Status, [string]$Notes)
            $rows.Add([pscustomobject]@{
                Check = $Check; Expected = $Expected; Actual = $Actual
                Status = $Status; Notes = $Notes
            }) | Out-Null
        }

        # Step 1: file existence + size
        Set-DebugStep -Step 'iso-existence'
        Write-SubSection 'Step 1: Output ISO existence + size'
        if (-not (Test-Path -LiteralPath $Script:OutputIsoPath)) {
            Add-VRow -Check 'IsoExists' -Expected 'True' -Actual 'False' -Status 'Fail' -Notes $Script:OutputIsoPath
            Write-Fail ('Output ISO missing: {0}' -f $Script:OutputIsoPath)
            return
        }
        $sz = (Get-Item -LiteralPath $Script:OutputIsoPath).Length
        Add-VRow -Check 'IsoExists' -Expected 'True' -Actual 'True' -Status 'Pass' -Notes $Script:OutputIsoPath
        if ($Script:SyntheticTestMode) { $expSize = 1KB } else { $expSize = 1GB }
        if ($sz -ge $expSize) { $sizeStatus = 'Pass' } else { $sizeStatus = 'Warn' }
        Add-VRow -Check 'IsoSize' -Expected (">= " + $expSize.ToString()) `
            -Actual $sz.ToString() -Status $sizeStatus -Notes ('{0:F2} GB' -f ($sz / 1GB))
        Write-Ok ('Output ISO size: {0:F2} GB' -f ($sz / 1GB))

        # Step 2: mount + WIM presence
        Set-DebugStep -Step 'iso-mount-verify'
        Write-SubSection 'Step 2: Mount output ISO and verify contents'

        $img = $null
        $mountedDrive = $null
        try {
            $img = Mount-DiskImage -ImagePath $Script:OutputIsoPath -StorageType ISO -PassThru -ErrorAction SilentlyContinue
            if ($img) {
                Start-Sleep -Seconds 1
                $vol = $img | Get-Volume
                $mountedDrive = ($vol.DriveLetter + ':\')
            }
        } catch {
            Write-Caution ('Could not mount output ISO: {0}' -f $_.Exception.Message)
        }

        if ($mountedDrive) {
            $installWim = Join-Path $mountedDrive 'sources\install.wim'
            $bootWim    = Join-Path $mountedDrive 'sources\boot.wim'
            $setupExe   = Join-Path $mountedDrive 'setup.exe'

            $hasInst = Test-Path -LiteralPath $installWim
            if ($hasInst) { $instStatus = 'Pass' } else { $instStatus = 'Warn' }
            Add-VRow -Check 'InstallWim' -Expected 'True' -Actual ([string]$hasInst) `
                -Status $instStatus -Notes ''
            $hasBoot = Test-Path -LiteralPath $bootWim
            if ($hasBoot) { $bootStatus = 'Pass' } else { $bootStatus = 'Warn' }
            Add-VRow -Check 'BootWim' -Expected 'True' -Actual ([string]$hasBoot) `
                -Status $bootStatus -Notes ''
            $hasSetup = Test-Path -LiteralPath $setupExe
            if ($hasSetup) { $setupStatus = 'Pass' } else { $setupStatus = 'Warn' }
            Add-VRow -Check 'SetupExe' -Expected 'True' -Actual ([string]$hasSetup) `
                -Status $setupStatus -Notes ''

            Write-Step ('install.wim present: {0}' -f $hasInst)
            Write-Step ('boot.wim present   : {0}' -f $hasBoot)
            Write-Step ('setup.exe present  : {0}' -f $hasSetup)

            if ($hasInst -and -not $Script:SyntheticTestMode) {
                # Confirm WIM is enumerable and the configured KBs are present
                try {
                    Set-DebugStep -Step 'wim-enum-verify'
                    $inv = Get-WimIndexInventory -WimPath $installWim
                    if ($inv.Count -ge 1) { $enumStatus = 'Pass' } else { $enumStatus = 'Fail' }
                    Add-VRow -Check 'WimEnumerable' -Expected '>=1' `
                        -Actual ($inv.Count).ToString() -Status $enumStatus -Notes ''
                    Write-Ok ('install.wim has {0} index(es).' -f $inv.Count)

                    # For each index, run Get-WindowsPackage to confirm KBs
                    $expectedKbs = @($Script:ResolvedPatches | Where-Object { $_.KbId -ne 'Unknown' } | ForEach-Object { $_.KbId })
                    if ($expectedKbs.Count -gt 0 -and $Script:Execute) {
                        $firstIdx = $inv[0].ImageIndex
                        Set-DebugStep -Step ('verify-pkg-idx-' + $firstIdx)
                        $pkgs = Invoke-DismCmdlet -CommandName 'Get-WindowsPackage' -Parameters @{ ImagePath = $installWim; Index = $firstIdx }
                        $pkgNames = @($pkgs | ForEach-Object { $_.PackageName })
                        foreach ($kb in $expectedKbs) {
                            $found = $false
                            foreach ($pn in $pkgNames) {
                                # psa-disable-next-line PSA2003 -- $kb is a non-null string from $expectedKbs
                                if ($pn -match $kb) { $found = $true; break }
                            }
                            if ($found) { $st = 'Pass'; $actualStr = 'Present' }
                            else        { $st = 'Warn'; $actualStr = 'Absent' }
                            Add-VRow -Check ('Kb_' + $kb) -Expected 'Present' `
                                -Actual $actualStr -Status $st `
                                -Notes ('install.wim idx ' + $firstIdx)
                        }
                    }
                } catch {
                    Write-Caution ('WIM enumeration failed: {0}' -f $_.Exception.Message)
                }
            }
        }
        if ($img) {
            try { Dismount-DiskImage -ImagePath $Script:OutputIsoPath -ErrorAction SilentlyContinue | Out-Null } catch { $null = $_ }
        }

        $csvPath = Join-Path $Script:LogsDir 'P11_verification.csv'
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Wrote: {0}' -f $csvPath)

        $failed = $rows | Where-Object { $_.Status -eq 'Fail' }
        if ($failed.Count -gt 0) {
            throw ('P11 verification failed: {0} hard failures.' -f $failed.Count)
        }

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P11.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P12: Verify PCA2023 readiness (Verify group, ALWAYS-RUNS)
# ============================================================
# This phase ALWAYS runs as part of the Verify group, regardless of
# whether -EnablePca2023BootManager was specified for P10. The
# rationale: even when the operator is not converting to PCA2023
# right now, they still want to know whether the resulting ISO
# would boot on PCA2023-only firmware (post 2026-06).
#
# P12 is strictly READ-ONLY. It produces:
#   1. pca2023_readiness.json   (machine-readable snapshot)
#   2. pca2023_readiness.md     (human-readable detail page)
#
# The same snapshot is consumed by P13 FinalReport for the summary
# integration (3-c output mode).
# ============================================================

function Invoke-VerifyPhase12_VerifyPca2023Readiness {
    <#
    .SYNOPSIS
        P12: Inspect the produced ISO's PCA2023 readiness state and
        emit JSON + Markdown reports. Always runs; never modifies
        the ISO.

        Outputs (all under <WorkRoot>\pca2023\):
          - pca2023_readiness.json   - structured snapshot
          - pca2023_readiness.md     - human-readable detail

        The snapshot is also cached in $Script:Pca2023Snapshot for
        P13 FinalReport to integrate as a summary section.
    #>
    Start-DebugTrace -Context 'Invoke-VerifyPhase12_VerifyPca2023Readiness' -PhaseId 'P12'
    try {
        Write-SubSection 'PCA2023 boot manager readiness inspection'

        # See note at L9822 (P10): the script-scope global is
        # $Script:ExtractedDir; the helper API uses $ExtractedMediaPath.
        $extractedPath = if ($Script:ExtractedDir) { $Script:ExtractedDir } else { $null }
        if (-not $extractedPath -or -not (Test-Path -LiteralPath $extractedPath)) {
            Write-Step 'P12 skipped: no extracted media available (P05 did not run, or working tree was cleaned).'
            New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P12.skipped') -Force | Out-Null
            return
        }

        $osKey = if ($Script:OsProfile) { $Script:OsProfile.OsKey } else { $null }

        Set-DebugStep -Step 'snapshot'
        # Force-refresh: if P10 ran, the snapshot may be stale. If P10
        # didn't run, this is the first computation. Either way we
        # want the freshest view.
        $snapshot = Get-OrEnsurePca2023Snapshot `
            -ExtractedMediaPath $extractedPath `
            -WorkRoot $Script:WorkRoot `
            -OsKey $osKey `
            -Force

        # ---- Compute Output ISO readiness check (always; idempotent) ----
        # If P10 already populated $snapshot.OutputCheck during its
        # post-flight, the Force-refresh above reset OutputCheck to
        # $null on the new snapshot object, so we recompute here. This
        # block is idempotent regardless of whether P10 ran.
        Set-DebugStep -Step 'output-check'
        Write-Step 'Running output-ISO PCA2023 readiness check (5-target file inspection)...'
        $ocStart = Get-Date
        $outputCheck = Test-OutputIsoPca2023Readiness -ExtractedMediaPath $extractedPath
        $ocElapsed = [int](New-TimeSpan -Start $ocStart -End (Get-Date)).TotalSeconds
        $snapshot.OutputCheck = $outputCheck  # psa-disable-line PSA2009 -- $snapshot is returned by Get-OrEnsurePca2023Snapshot, which initialises OutputCheck = $null in its [pscustomobject]@{...} return; flow-insensitive analysis cannot trace this.
        Write-Step ('Output ISO check OverallStatus = {0} (computed in {1}s; {2} targets inspected)' -f `
            $outputCheck.OverallStatus, $ocElapsed, $outputCheck.TargetChecks.Count)

        Show-Pca2023ReadinessSnapshot -Snapshot $snapshot -OutputCheck $outputCheck

        # ---- Emit JSON ----
        Set-DebugStep -Step 'emit-json'
        $pcaDir = Join-Path $Script:WorkRoot 'pca2023'
        if (-not (Test-Path -LiteralPath $pcaDir)) {
            New-Item -ItemType Directory -Path $pcaDir -Force | Out-Null
        }
        $jsonPath = Join-Path $pcaDir 'pca2023_readiness.json'
        Save-CanonicalJsonFile -InputObject $snapshot -Path $jsonPath -Depth 10
        Write-Step ('Snapshot JSON: {0}' -f $jsonPath)

        # ---- Emit Markdown ----
        Set-DebugStep -Step 'emit-md'
        $mdPath = Join-Path $pcaDir 'pca2023_readiness.md'
        $mdLines = New-Object System.Collections.Generic.List[string]
        $mdLines.Add('# PCA2023 Boot Manager Readiness Report') | Out-Null
        $mdLines.Add('') | Out-Null
        $mdLines.Add(('- Captured: {0}' -f $snapshot.Generated.ToString('yyyy-MM-dd HH:mm:ss'))) | Out-Null
        $mdLines.Add(('- OS Key: `{0}`' -f $(if ($snapshot.OsKey) { $snapshot.OsKey } else { 'n/a' }))) | Out-Null
        $mdLines.Add(('- **Overall health: `{0}`**' -f $snapshot.Health)) | Out-Null
        $mdLines.Add('') | Out-Null
        if ($snapshot.Reasons.Count -gt 0) {
            $mdLines.Add('## Reasons') | Out-Null
            $mdLines.Add('') | Out-Null
            foreach ($r in $snapshot.Reasons) {
                $mdLines.Add(('- {0}' -f $r)) | Out-Null
            }
            $mdLines.Add('') | Out-Null
        }
        $mdLines.Add('## Detail') | Out-Null
        $mdLines.Add('') | Out-Null
        $mdLines.Add('```text') | Out-Null
        $mdLines.Add((Format-Pca2023ReadinessForReport -Snapshot $snapshot -OutputCheck $outputCheck).TrimEnd()) | Out-Null
        $mdLines.Add('```') | Out-Null
        $mdLines.Add('') | Out-Null
        if ($outputCheck -and $outputCheck.Available) {
            $mdLines.Add('## Output ISO PCA2023 Readiness (post-conversion)') | Out-Null
            $mdLines.Add('') | Out-Null
            $mdLines.Add(('- **OverallStatus**: `{0}`' -f $outputCheck.OverallStatus)) | Out-Null
            $mdLines.Add(('- Targets inspected: {0}' -f $outputCheck.TargetChecks.Count)) | Out-Null
            $mdLines.Add('') | Out-Null
            $mdLines.Add('| # | Target | Expected | Actual | Status | Notes |') | Out-Null
            $mdLines.Add('|---|---|---|---|---|---|') | Out-Null
            $tnum = 0
            foreach ($t in $outputCheck.TargetChecks) {
                $tnum++
                $notesCell = if ($t.Notes) { ($t.Notes -replace '\|', '\\|') } else { '' }
                $mdLines.Add(('| {0} | `{1}` | {2} | {3} | **{4}** | {5} |' -f `
                    $tnum, $t.Label, $t.ExpectedSignature, $t.ActualSignature, $t.Status, $notesCell)) | Out-Null
            }
            $mdLines.Add('') | Out-Null
            if ($outputCheck.Reasons.Count -gt 0) {
                $mdLines.Add('### Reasons') | Out-Null
                $mdLines.Add('') | Out-Null
                foreach ($r in $outputCheck.Reasons) {
                    $mdLines.Add(('- {0}' -f $r)) | Out-Null
                }
                $mdLines.Add('') | Out-Null
            }
        }
        $mdLines.Add('## References') | Out-Null
        $mdLines.Add('') | Out-Null
        $mdLines.Add('- Microsoft: [Updating Windows bootable media to use the PCA2023-signed boot manager](https://support.microsoft.com/en-us/topic/updating-windows-bootable-media-to-use-the-pca2023-signed-boot-manager-d4064779-0e4e-43ac-b2ce-24f434fcfa0f)') | Out-Null
        $mdLines.Add('- GitHub: [microsoft/secureboot_objects Make2023BootableMedia.ps1](https://github.com/microsoft/secureboot_objects/blob/main/scripts/windows/Make2023BootableMedia.ps1)') | Out-Null
        $mdLines.Add('') | Out-Null
        Set-Content -LiteralPath $mdPath -Value ($mdLines -join "`n") -Encoding UTF8 -Force
        Write-Step ('Snapshot Markdown: {0}' -f $mdPath)

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P12.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P13: Final report (Report group)
# ============================================================

function Invoke-ReportPhase13_FinalReport {
    <#
    .SYNOPSIS
        P13: End-of-run summary. Phase timing table, output ISO hash
        and path, log/diag locations.
    #>
    Start-DebugTrace -Context 'Invoke-ReportPhase13_FinalReport' -PhaseId 'P13'
    try {
        Write-SubSection 'Phase Timing Summary'
        Show-PhaseSummary

        if ($Script:OutputIsoPath -and (Test-Path -LiteralPath $Script:OutputIsoPath)) {
            Set-DebugStep -Step 'final-iso-hash'
            $sha = (Get-FileHash -LiteralPath $Script:OutputIsoPath -Algorithm SHA256).Hash.ToLower()
            $sz = (Get-Item -LiteralPath $Script:OutputIsoPath).Length
            Write-SubSection 'Output ISO'
            Write-Ok ('Path  : {0}' -f $Script:OutputIsoPath)
            Write-Ok ('Size  : {0:F2} GB ({1} bytes)' -f ($sz / 1GB), $sz)
            Write-Ok ('SHA256: {0}' -f $sha)
        }

        Write-SubSection 'Log locations'
        Write-Step ('Logs dir: {0}' -f $Script:LogsDir)
        Write-Step ('Diag dir: {0}' -f $Script:DiagDir)
        if ($Script:LogFile) { Write-Step ('Transcript: {0}' -f $Script:LogFile) }

        # ---- PCA2023 readiness summary (integrated from P12 snapshot) ----
        # This is the FinalReport-side of the 3-c output mode:
        # P12 produces the detail files (pca2023_readiness.json/.md),
        # P13 produces the executive summary inline in this report
        # so a reader does not need to chase a second file.
        if ($Script:Pca2023Snapshot) {
            Set-DebugStep -Step 'pca2023-summary'
            Write-SubSection 'PCA2023 Readiness Summary'
            $ocForReport = $null
            if ($Script:Pca2023Snapshot.PSObject.Properties['OutputCheck']) {
                $ocForReport = $Script:Pca2023Snapshot.OutputCheck
            }
            Show-Pca2023ReadinessSnapshot -Snapshot $Script:Pca2023Snapshot -Compact -OutputCheck $ocForReport
            $pcaDir = Join-Path $Script:WorkRoot 'pca2023'
            $jsonPath = Join-Path $pcaDir 'pca2023_readiness.json'
            $mdPath   = Join-Path $pcaDir 'pca2023_readiness.md'
            if (Test-Path -LiteralPath $jsonPath) {
                Write-Step ('Detail (JSON): {0}' -f $jsonPath)
            }
            if (Test-Path -LiteralPath $mdPath) {
                Write-Step ('Detail (Markdown): {0}' -f $mdPath)
            }
        }

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P13.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}


# ============================================================
# Admin phases: RefreshAllBaselines (A01),
#                      DumpFieldClassification (A02)
# ============================================================
# These are "admin" phases in the sense that they don't take an
# OS image as input; they operate on the on-disk data/config-*.json
# files. They are dispatched the same way as regular build phases
# via Invoke-PhaseRunner, but the Action mapping routes them
# through dedicated entry points (-Action RefreshAllBaselines and
# -Action DumpFieldClassification respectively).

function Get-RefreshDecision {
    <#
    .SYNOPSIS
        Decide whether a given field group needs refreshing given the
        current Config state, the chosen Mode, and the latest Patch
        Tuesday. Returns one of: Skip / InitialFill / Monthly / Manual.
    .DESCRIPTION
        Decision matrix (see CHANGELOG and SPEC):

                          | _VerifiedDate empty   | recorded < latest PT  | up-to-date
          ----------------+----------------------+----------------------+-----------
          Stable          | InitialFill / Manual  | (not applicable)      | Skip
          PatchTuesday    | Monthly               | Monthly               | Skip
          IsoRelease      | InitialFill / Manual  | (not applicable)      | Skip

        For Cadence=Stable / IsoRelease, if Refresher is $null the
        decision is reported as "Manual" (script cannot auto-fill).

        With -Mode Force, the decision is always one of Monthly /
        InitialFill / Manual (Skip is never returned).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Group,
        [Parameter(Mandatory)] [pscustomobject]$Snapshot,
        [Parameter(Mandatory)] [ValidateSet('Initial','Monthly','Force')] [string]$Mode,
        [Parameter(Mandatory)] [string]$LatestPatchTuesday
    )
    # Verified flag check (group-scoped meta field _VerifiedDate, or
    # LastVerifiedDate for PatchBaseline / LanguageSpecificPatches).
    $isVerified = [bool]$Snapshot.IsVerified
    $isAutoRefreshable = -not [string]::IsNullOrEmpty($Group.Refresher)

    if ($Mode -eq 'Force') {
        if ($Group.Cadence -eq 'PatchTuesday' -or $isAutoRefreshable) { return 'Monthly' }
        if ($isAutoRefreshable) { return 'InitialFill' }
        return 'Manual'
    }

    switch ($Group.Cadence) {
        'Stable' {
            if ($isVerified) { return 'Skip' }
            if ($isAutoRefreshable) { return 'InitialFill' }
            return 'Manual'
        }
        'IsoRelease' {
            if ($isVerified) { return 'Skip' }
            if ($isAutoRefreshable) { return 'InitialFill' }
            return 'Manual'
        }
        'PatchTuesday' {
            # Initial fill if never verified; Monthly if older than latest PT.
            if (-not $isVerified) {
                if ($Mode -eq 'Initial' -or $Mode -eq 'Monthly') {
                    if ($isAutoRefreshable) { return 'Monthly' }
                    return 'Manual'
                }
                return 'Manual'
            }
            # Verified; compare PatchTuesdayOfBaseline.
            $recorded = $Snapshot.PatchTuesdayOfBaseline
            if ([string]::IsNullOrEmpty($recorded)) {
                if ($isAutoRefreshable) { return 'Monthly' }
                return 'Manual'
            }
            if ([string]::Compare($recorded, $LatestPatchTuesday) -lt 0) {
                if ($isAutoRefreshable) { return 'Monthly' }
                return 'Manual'
            }
            return 'Skip'
        }
        default {
            return 'Manual'
        }
    }
}

function Get-GroupSnapshot {
    <#
    .SYNOPSIS
        Read the verification state and PatchTuesdayOfBaseline for
        the given field group out of a config raw JSON object.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject]$ConfigRaw,
        [Parameter(Mandatory)] [string]$GroupPath,
        [string]$Lang
    )
    $resolvedPath = $GroupPath
    if ($Lang) { $resolvedPath = $resolvedPath -replace '<lang>', $Lang }

    $verifiedDate = ''
    $verifiedBy   = ''
    $ptOfBaseline = ''

    switch -Regex ($resolvedPath) {
        '^Common$' {
            $verifiedDate = if ($ConfigRaw.Common.PSObject.Properties['_VerifiedDate']) { [string]$ConfigRaw.Common._VerifiedDate } else { '' }
            $verifiedBy   = if ($ConfigRaw.Common.PSObject.Properties['_VerifiedBy'])   { [string]$ConfigRaw.Common._VerifiedBy   } else { '' }
            break
        }
        '^PatchBaseline$' {
            $verifiedDate = if ($ConfigRaw.PatchBaseline.PSObject.Properties['LastVerifiedDate']) { [string]$ConfigRaw.PatchBaseline.LastVerifiedDate } else { '' }
            $verifiedBy   = if ($ConfigRaw.PatchBaseline.PSObject.Properties['LastVerifiedBy'])   { [string]$ConfigRaw.PatchBaseline.LastVerifiedBy   } else { '' }
            $ptOfBaseline = if ($ConfigRaw.PatchBaseline.PSObject.Properties['PatchTuesdayOfBaseline']) { [string]$ConfigRaw.PatchBaseline.PatchTuesdayOfBaseline } else { '' }
            break
        }
        '^LanguageSpecific\.(?<lang>[^.]+)\.Iso$' {
            $node = $ConfigRaw.LanguageSpecific.$Lang.Iso
            if ($node) {
                $verifiedDate = if ($node.PSObject.Properties['_VerifiedDate']) { [string]$node._VerifiedDate } else { '' }
                $verifiedBy   = if ($node.PSObject.Properties['_VerifiedBy'])   { [string]$node._VerifiedBy   } else { '' }
            }
            break
        }
        '^LanguageSpecific\.(?<lang>[^.]+)\.LanguageSpecificPatches$' {
            $node = $ConfigRaw.LanguageSpecific.$Lang.LanguageSpecificPatches
            if ($node) {
                $verifiedDate = if ($node.PSObject.Properties['LastVerifiedDate'])       { [string]$node.LastVerifiedDate       } else { '' }
                $verifiedBy   = if ($node.PSObject.Properties['LastVerifiedBy'])         { [string]$node.LastVerifiedBy         } else { '' }
                $ptOfBaseline = if ($node.PSObject.Properties['PatchTuesdayOfBaseline']) { [string]$node.PatchTuesdayOfBaseline } else { '' }
            }
            break
        }
    }
    return [pscustomobject]@{
        ResolvedPath           = $resolvedPath
        IsVerified             = -not [string]::IsNullOrEmpty($verifiedDate)
        VerifiedDate           = $verifiedDate
        VerifiedBy             = $verifiedBy
        PatchTuesdayOfBaseline = $ptOfBaseline
    }
}

function Show-RefreshAllBaselinesSummary {
    <#
    .SYNOPSIS
        Render the rich end-of-run summary for Invoke-AdminPhaseA01_RefreshAllBaselines.
    .DESCRIPTION
        Writes a multi-section console-only summary block:

          1. Decision counts (Skip / Manual / Monthly / InitialFill).
          2. Per-OS patch composition: a one-line-per-OS table showing
             the patch count, the breakdown by Type, the file count,
             and the previous LastVerifiedDate.
          3. KB diff per OS: which KBs were added, which were dropped,
             which stayed. The comparison is between BeforePatches
             (loaded from disk) and AfterPatches (after Refresher).
          4. Manual-fill list: every group path that requires manual
             attention, grouped by OS for easy follow-up.
          5. Pca2023 status table: per-OS RequiredByDefault flag and
             the documented minimum update level KB, so operators can
             see at a glance which OSes still need the PCA2023 boot
             manager pipeline (P10 ConvertPca2023BootManager).
          6. Patch Tuesday timeline: "this run" baseline and the next
             two upcoming Patch Tuesdays so operators can schedule the
             next refresh.
          7. Exit-code outlook: explicit message about what exit code
             this run will produce and why.

        All output goes to Write-Host (the regular console stream).
        Nothing is written to disk by this function: that is by design
        (the user explicitly asked for console-only output suitable
        for CI log capture).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [System.Collections.IEnumerable]$ReportRows,
        [Parameter(Mandatory)] [hashtable]$OsSummaries,
        [Parameter(Mandatory)] [string]$LatestPatchTuesday,
        [Parameter(Mandatory)] [string]$PatchMonth,
        [Parameter(Mandatory)] [bool]$HasUnresolved,
        [Parameter(Mandatory)] [bool]$OkOverall
    )

    $bar = '======================================================================'

    Write-Host ''
    Write-Host $bar -ForegroundColor Cyan
    Write-Host ' Summary  (RefreshAllBaselines)' -ForegroundColor Cyan
    Write-Host $bar -ForegroundColor Cyan

    # ---- 1. Decision counts ------------------------------------------
    Write-Host ''
    Write-Host '  [1] Field-group decisions' -ForegroundColor Yellow
    $byDecision = $ReportRows | Group-Object Decision | Sort-Object Name
    foreach ($g in $byDecision) {
        Write-Host ('        {0,-15} : {1}' -f $g.Name, $g.Count) -ForegroundColor White
    }

    # ---- 2. Per-OS patch composition ---------------------------------
    Write-Host ''
    Write-Host '  [2] Per-OS patch composition (Lines after refresh)' -ForegroundColor Yellow
    Write-Host ('        {0,-12} {1,-8} {2,-7} {3,-50}' -f 'OS', 'Patches', 'Files', 'Types (count)') -ForegroundColor DarkGray
    Write-Host ('        ' + ('-' * 80)) -ForegroundColor DarkGray
    foreach ($osKey in ($OsSummaries.Keys | Sort-Object)) {
        $sum = $OsSummaries[$osKey]
        $after = @($sum.AfterPatches)
        $byType = $after | Group-Object Type | Sort-Object Name
        $typeStr = ($byType | ForEach-Object { ('{0}={1}' -f $_.Name, $_.Count) }) -join ', '
        $fileCount = ($after | Where-Object { $_.FileName }).Count
        Write-Host ('        {0,-12} {1,-8} {2,-7} {3}' -f $osKey, $after.Count, $fileCount, $typeStr) -ForegroundColor White
    }

    # ---- 3. KB diff per OS -------------------------------------------
    Write-Host ''
    Write-Host '  [3] KB delta vs previous PatchBaseline' -ForegroundColor Yellow
    foreach ($osKey in ($OsSummaries.Keys | Sort-Object)) {
        $sum = $OsSummaries[$osKey]
        $beforeKbs = @($sum.BeforePatches | Where-Object { $_.KbId } | ForEach-Object { $_.KbId } | Sort-Object -Unique)
        $afterKbs  = @($sum.AfterPatches  | Where-Object { $_.KbId } | ForEach-Object { $_.KbId } | Sort-Object -Unique)
        $added   = @($afterKbs  | Where-Object { $beforeKbs -notcontains $_ })
        $removed = @($beforeKbs | Where-Object { $afterKbs  -notcontains $_ })
        $stayed  = @($afterKbs  | Where-Object { $beforeKbs -contains $_ })
        Write-Host ('        {0}' -f $osKey) -ForegroundColor White
        if ($added.Count -eq 0 -and $removed.Count -eq 0) {
            Write-Host '          (no KB-level changes)' -ForegroundColor DarkGray
        }
        if ($added.Count -gt 0) {
            Write-Host ('          + added   ({0}): {1}' -f $added.Count,   ($added -join ', ')) -ForegroundColor Green
        }
        if ($removed.Count -gt 0) {
            Write-Host ('          - removed ({0}): {1}' -f $removed.Count, ($removed -join ', ')) -ForegroundColor Red
        }
        if ($stayed.Count -gt 0) {
            Write-Host ('          = unchanged ({0}): {1}' -f $stayed.Count, ($stayed -join ', ')) -ForegroundColor DarkGray
        }
    }

    # ---- 4. Manual-fill list -----------------------------------------
    Write-Host ''
    Write-Host '  [4] Manual fill required (operator follow-up)' -ForegroundColor Yellow
    $totalManual = 0
    foreach ($osKey in ($OsSummaries.Keys | Sort-Object)) {
        $manual = @($OsSummaries[$osKey].ManualGroups)
        if ($manual.Count -gt 0) {
            Write-Host ('        {0}:' -f $osKey) -ForegroundColor White
            foreach ($m in $manual) {
                Write-Host ('          - {0}' -f $m) -ForegroundColor DarkYellow
                $totalManual += 1
            }
        }
    }
    if ($totalManual -eq 0) {
        Write-Host '        (no manual fill required)' -ForegroundColor Green
    } else {
        Write-Host ('        Total manual items: {0}' -f $totalManual) -ForegroundColor DarkYellow
    }

    # ---- 5. Pca2023 status -------------------------------------------
    Write-Host ''
    Write-Host '  [5] Pca2023 readiness (Secure Boot 2026 expiry)' -ForegroundColor Yellow
    Write-Host ('        {0,-12} {1,-20} {2}' -f 'OS', 'RequiredByDefault', 'RequiredUpdateLevelKb') -ForegroundColor DarkGray
    Write-Host ('        ' + ('-' * 80)) -ForegroundColor DarkGray
    foreach ($osKey in ($OsSummaries.Keys | Sort-Object)) {
        $pca = $OsSummaries[$osKey].Pca2023
        if ($null -eq $pca) {
            Write-Host ('        {0,-12} {1,-20} {2}' -f $osKey, '(Schema 2.0)', '(no Pca2023 block)') -ForegroundColor DarkGray
            continue
        }
        $req = [string]$pca.RequiredByDefault
        $ulk = [string]$pca.RequiredUpdateLevelKb
        if ([string]::IsNullOrEmpty($ulk)) { $ulk = '(empty)' }
        $color = if ($req -eq 'True') { 'Yellow' } else { 'White' }
        Write-Host ('        {0,-12} {1,-20} {2}' -f $osKey, $req, $ulk) -ForegroundColor $color
    }

    # ---- 6. Patch Tuesday timeline -----------------------------------
    Write-Host ''
    Write-Host '  [6] Patch Tuesday timeline' -ForegroundColor Yellow
    Write-Host ('        This run baseline   : {0}  (Patch Month = {1})' -f $LatestPatchTuesday, $PatchMonth) -ForegroundColor White
    $baseline = [datetime]::ParseExact($LatestPatchTuesday, 'yyyy-MM-dd', $null)
    $next1 = $baseline.AddMonths(1)
    $next1Pt = Get-PatchTuesdayForMonth -Year $next1.Year -Month $next1.Month
    $next2 = $baseline.AddMonths(2)
    $next2Pt = Get-PatchTuesdayForMonth -Year $next2.Year -Month $next2.Month
    Write-Host ('        Next Patch Tuesday  : {0}' -f $next1Pt.ToString('yyyy-MM-dd')) -ForegroundColor White
    Write-Host ('        Month after next    : {0}' -f $next2Pt.ToString('yyyy-MM-dd')) -ForegroundColor DarkGray

    # ---- 7. Exit-code outlook ----------------------------------------
    Write-Host ''
    Write-Host '  [7] Run outcome' -ForegroundColor Yellow
    if (-not $OkOverall) {
        Write-Host '        Status: FAILED (at least one Refresher raised an error).' -ForegroundColor Red
        Write-Host '        Exit code: 1' -ForegroundColor Red
    } elseif ($HasUnresolved) {
        Write-Host '        Status: PARTIAL (Refreshers ran, manual fill still needed).' -ForegroundColor DarkYellow
        Write-Host '        Exit code: 2' -ForegroundColor DarkYellow
    } else {
        Write-Host '        Status: OK (all groups resolved).' -ForegroundColor Green
        Write-Host '        Exit code: 0' -ForegroundColor Green
    }

    Write-Host $bar -ForegroundColor Cyan
    Write-Host ''
}

function Set-GroupVerifiedState {
    <#
    .SYNOPSIS
        Update the _VerifiedDate / _VerifiedBy / LastVerified* fields
        for a given field group inside a config raw object (in memory).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject]$ConfigRaw,
        [Parameter(Mandatory)] [string]$GroupPath,
        [string]$Lang,
        [string]$PatchTuesday,
        [string]$VerifierTag
    )
    $now = (Get-Date).ToString('o')
    $by = $VerifierTag
    if ([string]::IsNullOrEmpty($by)) { $by = 'auto:RefreshAllBaselines' }

    $resolvedPath = $GroupPath
    if ($Lang) { $resolvedPath = $resolvedPath -replace '<lang>', $Lang }

    switch -Regex ($resolvedPath) {
        '^Common$' {
            $ConfigRaw.Common | Add-Member -NotePropertyName '_VerifiedDate' -NotePropertyValue $now -Force
            $ConfigRaw.Common | Add-Member -NotePropertyName '_VerifiedBy'   -NotePropertyValue $by  -Force
            break
        }
        '^PatchBaseline$' {
            $ConfigRaw.PatchBaseline | Add-Member -NotePropertyName 'LastVerifiedDate'        -NotePropertyValue $now           -Force
            $ConfigRaw.PatchBaseline | Add-Member -NotePropertyName 'LastVerifiedBy'          -NotePropertyValue $by            -Force
            if ($PatchTuesday) {
                $ConfigRaw.PatchBaseline | Add-Member -NotePropertyName 'PatchTuesdayOfBaseline' -NotePropertyValue $PatchTuesday -Force
            }
            break
        }
        '^LanguageSpecific\.(?<lang>[^.]+)\.Iso$' {
            $ConfigRaw.LanguageSpecific.$Lang.Iso | Add-Member -NotePropertyName '_VerifiedDate' -NotePropertyValue $now -Force
            $ConfigRaw.LanguageSpecific.$Lang.Iso | Add-Member -NotePropertyName '_VerifiedBy'   -NotePropertyValue $by  -Force
            break
        }
        '^LanguageSpecific\.(?<lang>[^.]+)\.LanguageSpecificPatches$' {
            $node = $ConfigRaw.LanguageSpecific.$Lang.LanguageSpecificPatches
            $node | Add-Member -NotePropertyName 'LastVerifiedDate' -NotePropertyValue $now -Force
            $node | Add-Member -NotePropertyName 'LastVerifiedBy'   -NotePropertyValue $by  -Force
            if ($PatchTuesday) {
                $node | Add-Member -NotePropertyName 'PatchTuesdayOfBaseline' -NotePropertyValue $PatchTuesday -Force
            }
            break
        }
    }
}

    # psa-disable-next-line PSA6003 -- intentional plural: function refreshes ALL baselines across multiple OS x language combinations
function Invoke-AdminPhaseA01_RefreshAllBaselines {
    <#
    .SYNOPSIS
        Refresh data/config-<OsKey>.json baselines for one or more OS / language
        combinations. Applies the field-group decision matrix and calls
        the appropriate Refresher function per group.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Action name intentionally plural: refreshes ALL baselines across multiple OS x language combinations.')]
    [OutputType([bool])]
    param()

    Start-DebugTrace -Context 'Invoke-AdminPhaseA01_RefreshAllBaselines' -PhaseId 'A01'
    $okOverall = $true
    $hasUnresolved = $false
    try {
        Set-DebugStep -Step 'discover-configs'
        $configRoot = Join-Path $Script:ScriptRoot 'data'
        if (-not (Test-Path -LiteralPath $configRoot)) {
            throw ('Data root not found: {0}' -f $configRoot)
        }

        # Determine which OS configs to process
        $allOsKeys = @('Server2016','Server2019','Server2022','Server2025')
        $targetOsKeys = $allOsKeys
        if ($Script:OnlyOs) { $targetOsKeys = @($Script:OnlyOs) }

        # Resolve Patch Month (used as PatchTuesday baseline marker)
        Set-DebugStep -Step 'resolve-patch-tuesday'
        $latestPt = Get-LatestPatchTuesday | ForEach-Object { $_.ToString('yyyy-MM-dd') }
        $patchMonth = $latestPt.Substring(0,7)        # 'yyyy-MM'
        if (-not [string]::IsNullOrEmpty($Script:PatchMonth)) {
            $patchMonth = $Script:PatchMonth
            Write-Step ('Override patch month: {0}' -f $patchMonth)
            # When the operator pins a specific month, the PatchTuesday-of-
            # baseline marker must reflect THAT month's Patch Tuesday, not the
            # wall-clock latest one (otherwise a May baseline regenerated on
            # June Patch Tuesday would be stamped with June's date). This keeps
            # a pinned-month regeneration both correct and byte-reproducible.
            $pmParts = $patchMonth -split '-'
            if ($pmParts.Count -eq 2) {
                $latestPt = (Get-PatchTuesdayForMonth -Year ([int]$pmParts[0]) -Month ([int]$pmParts[1])).ToString('yyyy-MM-dd')
                Write-Step ('PatchTuesday-of-baseline (from pinned month): {0}' -f $latestPt)
            }
        }

        Write-SubSection 'Refresh plan'
        Write-Step ('Mode               : {0}' -f $Script:Mode)
        Write-Step ('Latest Patch Tuesday: {0}' -f $latestPt)
        Write-Step ('Patch Month        : {0}' -f $patchMonth)
        Write-Step ('Target OS configs  : {0}' -f ($targetOsKeys -join ', '))
        if ($Script:OnlyLanguage) {
            Write-Step ('Only language      : {0}' -f $Script:OnlyLanguage)
        }
        if ($Script:DryRun) {
            Write-Caution 'DryRun is ON: changes will NOT be written back to disk.'
        }

        $reportRows = New-Object System.Collections.Generic.List[object]
        # Per-OS summary collector for the rich end-of-run summary.
        # Key   : OsKey (string)
        # Value : pscustomobject containing:
        #           BeforePatches    - Lines list as it was loaded
        #           AfterPatches     - Lines list after Refresher runs
        #                              (or BeforePatches if nothing changed)
        #           Changed          - $true when at least one writeback would occur
        #           ErrorCount       - count of Refresher failures for this OS
        #           ManualGroups     - list of group paths flagged Manual fill
        #           Pca2023          - pass-through reference to the Pca2023 block
        #                              (or $null when running against a Schema 2.0 Config)
        #           PreviousVerified - $raw.PatchBaseline.LastVerifiedDate as
        #                              read before refresh, so the summary can
        #                              show "last refresh" vs "this refresh".
        $osSummaries = @{}

        foreach ($osKey in $targetOsKeys) {
            Set-DebugStep -Step ('os:' + $osKey)
            $cfgFile = Join-Path $configRoot ('config-' + $osKey + '.json')
            if (-not (Test-Path -LiteralPath $cfgFile)) {
                Write-Caution ('Config not found: {0}' -f $cfgFile)
                continue
            }
            Write-SubSection ('Refreshing {0}' -f $osKey)
            $raw = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8 | ConvertFrom-CanonicalJson
            $acceptedSchemas = @('3.0')
            if ($acceptedSchemas -notcontains $raw.Schema) {
                Write-Caution ('Skipping {0}: Schema is "{1}", expected one of: {2}.' -f $osKey, $raw.Schema, ($acceptedSchemas -join ', '))
                continue
            }

            # Per-OS summary collector entry. Capture the "before"
            # state of Lines (deep clone via JSON round-trip
            # so subsequent in-place mutations to $raw don't pollute
            # the snapshot) plus the previous LastVerifiedDate and a
            # reference to the Pca2023 block (if any).
            $beforeJson = ($raw.PatchBaseline.Lines | ConvertTo-Json -Depth 10 -Compress)
            if ([string]::IsNullOrEmpty($beforeJson) -or $beforeJson -eq 'null') {
                $beforePatches = @()
            } else {
                $beforePatches = @($beforeJson | ConvertFrom-Json)
            }
            $previousVerified = ''
            if ($raw.PatchBaseline.PSObject.Properties.Name -contains 'LastVerifiedDate') {
                $previousVerified = [string]$raw.PatchBaseline.LastVerifiedDate
            }
            $pca2023Ref = $null
            if ($raw.PSObject.Properties.Name -contains 'Pca2023') {
                $pca2023Ref = $raw.Pca2023
            }
            $osSummaries[$osKey] = [pscustomobject]@{
                BeforePatches    = $beforePatches
                AfterPatches     = $beforePatches    # updated below if Refresher changes anything
                Changed          = $false
                ErrorCount       = 0
                ManualGroups     = New-Object System.Collections.Generic.List[string]
                Pca2023          = $pca2023Ref
                PreviousVerified = $previousVerified
            }

            $supportedLangs = @($raw.Common.SupportedLanguages)
            if ($Script:OnlyLanguage) {
                $supportedLangs = @($supportedLangs | Where-Object { $_ -eq $Script:OnlyLanguage })
            }
            $changed = $false

            # ----- Iterate field groups (per FieldGroups constant) -----
            foreach ($g in $Script:OsConfigFieldGroups) {
                # Identify if this group is per-language (path contains <lang>) or global.
                # NOTE: PowerShell 7's `if (...) { ... } else { @($null) }` collapses
                # to a bare $null instead of a single-element array. Use the comma
                # operator (,$null) to force a true 1-element array so the foreach
                # below always executes the body at least once for global groups.
                $isPerLang = ($g.Path -match '<lang>')
                if ($isPerLang) {
                    $iterLangs = @($supportedLangs)
                } else {
                    $iterLangs = ,$null
                }
                foreach ($lang in $iterLangs) {
                    $snap = Get-GroupSnapshot -ConfigRaw $raw -GroupPath $g.Path -Lang $lang
                    $decision = Get-RefreshDecision -Group $g -Snapshot $snap `
                                                    -Mode $Script:Mode -LatestPatchTuesday $latestPt
                    $resolvedPath = $g.Path
                    if ($lang) { $resolvedPath = $resolvedPath -replace '<lang>', $lang }
                    Write-Step ('  Group {0,-55} cadence={1,-12} decision={2}' -f $resolvedPath, $g.Cadence, $decision)

                    $patchCount = 0
                    $errorMsg = ''
                    switch ($decision) {
                        'Skip' {
                            # Nothing to do
                        }
                        'Manual' {
                            $hasUnresolved = $true
                            Write-Caution ('    -> Manual fill required (no auto Refresher for this group).')
                            $osSummaries[$osKey].ManualGroups.Add($resolvedPath) | Out-Null
                        }
                        { $_ -in @('InitialFill','Monthly') } {
                            # Invoke the Refresher
                            $refresher = $g.Refresher
                            if ([string]::IsNullOrEmpty($refresher)) {
                                $hasUnresolved = $true
                                Write-Caution ('    -> No Refresher; field requires manual fill.')
                                $osSummaries[$osKey].ManualGroups.Add($resolvedPath) | Out-Null
                                break
                            }
                            try {
                                if ($refresher -eq 'Invoke-CatalogPatchSetRefresh') {
                                    $patches = @(Invoke-CatalogPatchSetRefresh -OsVersion $osKey `
                                                                              -OsLanguage 'neutral' `
                                                                              -PatchMonth $patchMonth `
                                                                              -MaxRetries 3)
                                    $patchCount = $patches.Count
                                    if (-not $Script:DryRun -and $patchCount -gt 0) {
                                        $raw.PatchBaseline.Lines = $patches
                                        $osSummaries[$osKey].AfterPatches = @($patches)
                                    }
                                    Set-GroupVerifiedState -ConfigRaw $raw -GroupPath $g.Path -Lang $lang `
                                                           -PatchTuesday $latestPt -VerifierTag 'auto:RefreshAllBaselines'
                                    $changed = $true
                                    $osSummaries[$osKey].Changed = $true
                                } elseif ($refresher -eq 'Resolve-LanguageSpecificPatchesFromCatalog') {
                                    $langPatches = @(Resolve-LanguageSpecificPatchesFromCatalog -OsVersion $osKey `
                                                                                                 -OsLanguage $lang `
                                                                                                 -PatchMonth $patchMonth `
                                                                                                 -MaxRetries 3)
                                    $patchCount = $langPatches.Count
                                    if (-not $Script:DryRun) {
                                        $node = $raw.LanguageSpecific.$lang.LanguageSpecificPatches
                                        $lps   = @($langPatches | Where-Object { $_.Type -eq 'LanguagePack' })
                                        $lxps  = @($langPatches | Where-Object { $_.Type -eq 'LXP' })
                                        $dotnetLps = @($langPatches | Where-Object { $_.Type -eq 'DotNet.LangPack' })
                                        $node | Add-Member -NotePropertyName 'LanguagePacks'       -NotePropertyValue $lps       -Force
                                        $node | Add-Member -NotePropertyName 'LxpUpdates'          -NotePropertyValue $lxps      -Force
                                        $node | Add-Member -NotePropertyName 'DotNetLanguagePacks' -NotePropertyValue $dotnetLps -Force
                                    }
                                    Set-GroupVerifiedState -ConfigRaw $raw -GroupPath $g.Path -Lang $lang `
                                                           -PatchTuesday $latestPt -VerifierTag 'auto:RefreshAllBaselines'
                                    $changed = $true
                                    $osSummaries[$osKey].Changed = $true
                                } else {
                                    $hasUnresolved = $true
                                    Write-Caution ('    -> Unknown Refresher "{0}"' -f $refresher)
                                    $osSummaries[$osKey].ManualGroups.Add($resolvedPath) | Out-Null
                                }
                            } catch {
                                $okOverall = $false
                                $errorMsg = $_.Exception.Message
                                Write-Fail ('    -> Refresher failed: {0}' -f $errorMsg)
                                $osSummaries[$osKey].ErrorCount += 1
                            }
                        }
                    }
                    $reportRows.Add([pscustomobject]@{
                        OsKey      = $osKey
                        Lang       = if ($lang) { $lang } else { '-' }
                        Group      = $resolvedPath
                        Cadence    = $g.Cadence
                        Decision   = $decision
                        PatchCount = $patchCount
                        Error      = $errorMsg
                    }) | Out-Null
                }
            }

            # Writeback if anything changed and not DryRun
            if ($changed -and -not $Script:DryRun) {
                Set-DebugStep -Step ('writeback:' + $osKey)
                # Use Save-ConfigWithBaseline for atomic LF/UTF-8 write
                Save-ConfigWithBaseline -ConfigPath $cfgFile -OsProfile $raw
                Write-Ok ('  Wrote: {0}' -f $cfgFile)
            } elseif ($changed -and $Script:DryRun) {
                Write-Caution ('  DryRun: would have written {0}' -f $cfgFile)
            } else {
                Write-Step ('  No changes for {0}' -f $osKey)
            }
        }

        # Emit aggregate report
        Set-DebugStep -Step 'emit-report'
        $reportPath = Join-Path $Script:LogsDir 'A01_RefreshAllBaselines_report.csv'
        $reportRows | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Report: {0}' -f $reportPath)

        # Rich console summary (CI-friendly: console only, no extra files).
        # See Show-RefreshAllBaselinesSummary for the section layout.
        Show-RefreshAllBaselinesSummary `
            -ReportRows $reportRows `
            -OsSummaries $osSummaries `
            -LatestPatchTuesday $latestPt `
            -PatchMonth $patchMonth `
            -HasUnresolved ([bool]$hasUnresolved) `
            -OkOverall ([bool]$okOverall)

        if (-not $okOverall) {
            $Script:ExitCode = 1
            return $false
        }
        if ($hasUnresolved) {
            $Script:ExitCode = 2
            Write-Caution 'Some fields require manual fill; exit code 2.'
        }
        return $true
    } finally {
        Stop-DebugTrace
    }
}

function Invoke-AdminPhaseA02_DumpFieldClassification {
    <#
    .SYNOPSIS
        Dump $Script:OsConfigFieldGroups as JSON for downstream tooling
        (e.g. a future Python schema validator).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Start-DebugTrace -Context 'Invoke-AdminPhaseA02_DumpFieldClassification' -PhaseId 'A02'
    try {
        Set-DebugStep -Step 'serialize-field-groups'
        $outDir = $Script:LogsDir
        if (-not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
        $outPath = Join-Path $outDir 'A02_FieldClassification.json'
        $payload = [ordered]@{
            Schema       = '2.0'
            GeneratedAt  = (Get-Date).ToString('o')
            ScriptVersion = $Script:ScriptVersion
            FieldGroups  = @($Script:OsConfigFieldGroups | ForEach-Object {
                [ordered]@{
                    Path        = $_.Path
                    Cadence     = $_.Cadence
                    Refresher   = if ($_.Refresher) { $_.Refresher } else { $null }
                    Description = $_.Description
                }
            })
        }
        Save-CanonicalJsonFile -InputObject $payload -Path $outPath -Depth 8
        Write-Ok ('Field classification written: {0}' -f $outPath)
        return $true
    } finally {
        Stop-DebugTrace
    }
}

function Get-DynamicUpdateProbePlan {
    <#
    .SYNOPSIS
        Return the per-OS Dynamic Update probe plan used by
        Invoke-AdminPhaseA03_RefreshSnapshots. Each entry describes one
        (OsVersion, DuType, QueryTemplate) probe to issue against the
        Microsoft Update Catalog Search.aspx endpoint.
    .DESCRIPTION
        Server 2019 is intentionally absent: per SPEC.md, Microsoft
        does not publish Setup / Safe OS Dynamic Update packages for the
        Server 2019 (1809) baseline, and T10's resolver test asserts
        this absence. Server 2016 (1607) is likewise absent because the
        modern "Dynamic Update" naming convention starts with the 21H2
        generation; any 2016-era servicing media is delivered through
        the standard LCU channel and is already covered by the
        release-info cache.

        The query template uses Microsoft Learn's media-dynamic-update
        guidance: month + DU label + OS descriptor. The OS descriptor
        deliberately matches the long-form "Microsoft server operating
        system version <NNH>" name that Microsoft has standardised on
        since the 21H2 era; tests/catalog_title_tokens_test.py (T9)
        covers the title narrowing applied to the resulting search
        hits.
    #>
    [OutputType([pscustomobject[]])]
    param()

    return @(
        [pscustomobject]@{
            OsVersion = 'Server2022'
            DuType    = 'DynamicUpdate.Setup'
            Label     = 'Setup Dynamic Update'
            OsToken   = 'Microsoft server operating system version 21H2'
        }
        [pscustomobject]@{
            OsVersion = 'Server2022'
            DuType    = 'DynamicUpdate.SafeOs'
            Label     = 'Safe OS Dynamic Update'
            OsToken   = 'Microsoft server operating system version 21H2'
        }
        [pscustomobject]@{
            OsVersion = 'Server2025'
            DuType    = 'DynamicUpdate.Setup'
            Label     = 'Setup Dynamic Update'
            OsToken   = 'Microsoft server operating system version 24H2'
        }
        [pscustomobject]@{
            OsVersion = 'Server2025'
            DuType    = 'DynamicUpdate.SafeOs'
            Label     = 'Safe OS Dynamic Update'
            OsToken   = 'Microsoft server operating system version 24H2'
        }
    )
}

# psa-disable-next-line PSA6003 -- intentional plural: function refreshes multiple snapshot caches (release-info, dotnet-cu, dynamic-update) in one phase
function Invoke-AdminPhaseA03_RefreshSnapshots {
    <#
    .SYNOPSIS
        Populate data/raw-*.json + data/cache-*.json snapshots from
        Microsoft Learn (release-info, .NET CU release-notes) and
        Microsoft Update Catalog (Dynamic Update probes). This is the
        first stage of the two-stage refresh (see SPEC.md); the
        complementary second stage (-Action RefreshAllBaselines)
        consumes the populated caches to regenerate
        data/config-Server*.json Lines[].
    .DESCRIPTION
        Three sub-steps, each independently fault-tolerant:

        1. release-info: fetch
           learn.microsoft.com/.../windows-server-release-info as
           Markdown via the ?accept=text/markdown query, persist as
           data/raw-release-info.md, then parse into
           data/cache-release-info.json. This is the LCU + Hotpatch
           calendar source used by the discovery layer.

        2. .NET CU: fetch the dotnet/release-notes index plus every
           monthly cumulative-update page it references; persist the
           aggregate into data/raw-dotnet-cu.json and the parsed form
           into data/cache-dotnet-cu.json. This is the .NET Framework
           CU source used by the discovery layer.

        3. Dynamic Update: probe Microsoft Update Catalog for the
           current Patch Tuesday's Setup DU and Safe OS DU per
           supported OS (Server 2022 and Server 2025 only; Server 2019
           per SPEC.md and Server 2016 per the modern-DU naming
           convention have no DU and are skipped). Each probe is
           recorded into data/cache-dynamicupdate-Server<N>.json via
           Add-DynamicUpdateCacheEntry, including the "empty-marker"
           case so the resolver can distinguish "Microsoft has not
           published a DU for this month" from "we have not yet
           probed for this month".

        On step failure the function logs the error, marks the
        sub-step Failed, and continues to the next sub-step. The
        overall return value is $true iff every sub-step reported OK.

        Honours -DryRun: when set, no HTTP fetches are issued and no
        cache files are written. The function reports the plan and
        returns success.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Start-DebugTrace -Context 'Invoke-AdminPhaseA03_RefreshSnapshots' -PhaseId 'A03'
    $okOverall = $true

    # Result trackers (used by the summary block + the CSV report)
    $releaseInfoResult = [pscustomobject]@{
        Status   = 'Pending'
        Monthly  = 0
        Hotpatch = 0
        Bytes    = 0
        Error    = ''
    }
    $dotnetResult = [pscustomobject]@{
        Status     = 'Pending'
        MonthCount = 0
        EntryCount = 0
        Error      = ''
    }
    $duResults = New-Object 'System.Collections.Generic.List[pscustomobject]'

    try {
        # Resolve the Patch Month under refresh. -PatchMonth override is
        # honoured for parity with A01; otherwise we anchor on the latest
        # Patch Tuesday available now.
        Set-DebugStep -Step 'resolve-patch-month'
        $latestPt   = Get-LatestPatchTuesday | ForEach-Object { $_.ToString('yyyy-MM-dd') }
        $patchMonth = $latestPt.Substring(0,7)        # 'yyyy-MM'
        if (-not [string]::IsNullOrEmpty($Script:PatchMonth)) {
            $patchMonth = $Script:PatchMonth
        }

        Write-SubSection 'Snapshot refresh plan'
        Write-Step ('Latest Patch Tuesday : {0}' -f $latestPt)
        Write-Step ('Patch Month          : {0}' -f $patchMonth)
        Write-Step ('Output data dir      : {0}' -f (Get-DataDirectoryPath))
        if ($Script:DryRun) {
            Write-Caution 'DryRun is ON: no HTTP fetches will be issued; no cache files will be written.'
        }

        # ============================================================
        # Sub-step 1: release-info
        # ============================================================
        Write-SubSection '[1/3] release-info (Microsoft Learn)'
        Set-DebugStep -Step 'release-info'
        if ($Script:DryRun) {
            Write-Skip 'release-info refresh skipped (-DryRun).'
            $releaseInfoResult.Status = 'Skipped'
        } else {
            try {
                $rawPath  = Invoke-ReleaseInfoFetch
                $summary  = Update-ReleaseInfoCache
                $rawBytes = (Get-Item -LiteralPath $rawPath).Length
                $releaseInfoResult.Status   = 'OK'
                $releaseInfoResult.Monthly  = [int]$summary.MonthlyRowCount
                $releaseInfoResult.Hotpatch = [int]$summary.HotpatchRowCount
                $releaseInfoResult.Bytes    = [int]$rawBytes
                Write-Ok ('release-info refreshed: {0} monthly rows, {1} hotpatch rows ({2} raw bytes).' -f
                    $releaseInfoResult.Monthly, $releaseInfoResult.Hotpatch, $releaseInfoResult.Bytes)
            } catch {
                $okOverall = $false
                $releaseInfoResult.Status = 'FAIL'
                $releaseInfoResult.Error  = [string]$_.Exception.Message
                Write-Fail ('release-info refresh failed: {0}' -f $_.Exception.Message)
            }
        }

        # ============================================================
        # Sub-step 2: .NET CU release-notes
        # ============================================================
        Write-SubSection '[2/3] .NET Framework CU (Microsoft Learn)'
        Set-DebugStep -Step 'dotnet-cu'
        if ($Script:DryRun) {
            Write-Skip '.NET CU refresh skipped (-DryRun).'
            $dotnetResult.Status = 'Skipped'
        } else {
            try {
                $null      = Invoke-DotNetCuFetch
                $null      = Update-DotNetCuCache
                $dotnetCache = Get-DotNetCuCache
                $totalEntries = 0
                $monthCount   = 0
                if ($null -ne $dotnetCache -and $dotnetCache.PSObject.Properties.Name -contains 'Months') {
                    foreach ($m in @($dotnetCache.Months)) {
                        $monthCount++
                        if ($m -and ($m.PSObject.Properties.Name -contains 'Entries')) {
                            $totalEntries += @($m.Entries).Count
                        }
                    }
                }
                $dotnetResult.Status     = 'OK'
                $dotnetResult.MonthCount = $monthCount
                $dotnetResult.EntryCount = $totalEntries
                Write-Ok ('.NET CU refreshed: {0} months captured, {1} entries total.' -f $monthCount, $totalEntries)
            } catch {
                $okOverall = $false
                $dotnetResult.Status = 'FAIL'
                $dotnetResult.Error  = [string]$_.Exception.Message
                Write-Fail ('.NET CU refresh failed: {0}' -f $_.Exception.Message)
            }
        }

        # ============================================================
        # Sub-step 3: Dynamic Update probes (per OS x DuType)
        # ============================================================
        Write-SubSection '[3/3] Dynamic Update probes (Microsoft Update Catalog)'
        Set-DebugStep -Step 'dynamic-update'
        $plan = Get-DynamicUpdateProbePlan
        Write-Step ('Probe targets: {0} (OS x DuType combinations)' -f $plan.Count)

        foreach ($p in $plan) {
            $probeKey = ('{0} / {1}' -f $p.OsVersion, $p.DuType)
            $probeRes = [pscustomobject]@{
                OsVersion        = $p.OsVersion
                DuType           = $p.DuType
                Query            = ''
                SearchHitCount   = 0
                MatchingHitCount = 0
                ChosenUpdateId   = ''
                ChosenTitle      = ''
                KbId             = ''
                Status           = 'Pending'
                Note             = ''
            }
            if ($Script:DryRun) {
                Write-Skip ('  {0,-40} -> skipped (-DryRun).' -f $probeKey)
                $probeRes.Status = 'Skipped'
                $duResults.Add($probeRes) | Out-Null
                continue
            }
            try {
                # Build the Catalog query string per Microsoft Learn's
                # media-dynamic-update guidance: month + DU label + OS
                # descriptor.
                $query = ('{0} {1} for {2}' -f $patchMonth, $p.Label, $p.OsToken)
                $probeRes.Query = $query
                Write-Step ('  Probe: {0,-40} q="{1}"' -f $probeKey, $query)

                # Get-UpdateIdFromCatalog's -KbId param accepts any query
                # text; internally it URL-encodes it into Search.aspx's
                # 'q=' parameter, which Catalog interprets as a free-text
                # search. The parameter name reflects the function's
                # primary KB-ID use case, but is not narrowed to that.
                $hits = @(Get-UpdateIdFromCatalog -KbId $query)
                $probeRes.SearchHitCount = $hits.Count

                # Title-narrow with the per-OS positive token list + the
                # hardcoded negative list (Windows 11 / arm64).
                $matching = @($hits | Where-Object {
                    Test-CatalogTitleMatch -Title ([string]$_.Title) -OsVersion $p.OsVersion
                })
                $probeRes.MatchingHitCount = $matching.Count

                $entry = @{
                    PatchMonth       = $patchMonth
                    DuType           = $p.DuType
                    ProbedAt         = (Get-Date).ToUniversalTime().ToString('o')
                    Query            = $query
                    SearchHitCount   = $hits.Count
                    MatchingHitCount = $matching.Count
                    MatchingHits     = @($matching | ForEach-Object {
                        @{ UpdateId = [string]$_.UpdateId; Title = [string]$_.Title }
                    })
                }
                if ($matching.Count -eq 0) {
                    $entry.Success       = $false
                    $entry.IsEmptyMarker = $true
                    $entry.Notes         = 'No Catalog hits survived title-narrow filter.'
                    $probeRes.Status     = 'Empty'
                    $probeRes.Note       = $entry.Notes
                    Write-Caution ('    -> Empty: no hits after title-narrow (recorded as IsEmptyMarker).')
                } else {
                    # Deduplicate via Supersedes/SupersededBy when >1 hit.
                    $chosen = $null
                    if ($matching.Count -gt 1) {
                        $sup = Select-LatestPatchBySupersedence -Entries @($matching | ForEach-Object {
                            [pscustomobject]@{ Title=[string]$_.Title; UpdateId=[string]$_.UpdateId }
                        })
                        if ($sup -and $sup.Survivor) {
                            $chosen = $sup.Survivor
                        }
                    }
                    if (-not $chosen) {
                        $chosen = $matching | Select-Object -First 1
                    }
                    $kbId = [string](Get-KbIdFromUpdateTitle -Title ([string]$chosen.Title))
                    $entry.ChosenUpdateId = [string]$chosen.UpdateId
                    $entry.ChosenTitle    = [string]$chosen.Title
                    $entry.KbId           = $kbId
                    $entry.Success        = $true
                    $entry.IsEmptyMarker  = $false
                    $probeRes.ChosenUpdateId = $entry.ChosenUpdateId
                    $probeRes.ChosenTitle    = $entry.ChosenTitle
                    $probeRes.KbId           = $kbId
                    $probeRes.Status         = 'OK'
                    Write-Ok ('    -> {0}  UpdateId={1}  Title="{2}"' -f $kbId, $entry.ChosenUpdateId, $entry.ChosenTitle)
                }

                # Persist to per-OS cache (Add-DynamicUpdateCacheEntry
                # upserts by (PatchMonth, DuType) so re-probing the same
                # month replaces in place rather than duplicating).
                $null = Add-DynamicUpdateCacheEntry -OsVersion $p.OsVersion -Entry $entry
            } catch {
                $okOverall = $false
                $probeRes.Status = 'FAIL'
                $probeRes.Note   = [string]$_.Exception.Message
                Write-Fail ('    -> FAIL: {0}' -f $_.Exception.Message)
            }
            $duResults.Add($probeRes) | Out-Null
        }

        # ============================================================
        # Summary block (mirrors A01's "Summary" rendering for parity)
        # ============================================================
        Show-RefreshSnapshotsSummary `
            -ReleaseInfo $releaseInfoResult `
            -DotNetCu    $dotnetResult `
            -DuResults   @($duResults.ToArray()) `
            -PatchMonth  $patchMonth `
            -LatestPt    $latestPt `
            -OkOverall   $okOverall

        # CSV report (parity with A01_RefreshAllBaselines_report.csv)
        try {
            $reportPath = Join-Path $Script:LogsDir 'A03_RefreshSnapshots_report.csv'
            $reportRows = New-Object System.Collections.Generic.List[object]
            $reportRows.Add([pscustomobject]@{
                Section='release-info'; OsVersion=''; DuType=''
                Status=$releaseInfoResult.Status; Detail=('monthly={0};hotpatch={1};bytes={2}' -f $releaseInfoResult.Monthly,$releaseInfoResult.Hotpatch,$releaseInfoResult.Bytes)
                Error=$releaseInfoResult.Error
            }) | Out-Null
            $reportRows.Add([pscustomobject]@{
                Section='dotnet-cu'; OsVersion=''; DuType=''
                Status=$dotnetResult.Status; Detail=('months={0};entries={1}' -f $dotnetResult.MonthCount,$dotnetResult.EntryCount)
                Error=$dotnetResult.Error
            }) | Out-Null
            foreach ($r in $duResults) {
                $reportRows.Add([pscustomobject]@{
                    Section='dynamic-update'; OsVersion=$r.OsVersion; DuType=$r.DuType
                    Status=$r.Status
                    Detail=('search={0};matching={1};kb={2};updateid={3}' -f $r.SearchHitCount,$r.MatchingHitCount,$r.KbId,$r.ChosenUpdateId)
                    Error=$r.Note
                }) | Out-Null
            }
            $reportRows | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
            Write-Ok ('Report: {0}' -f $reportPath)
        } catch {
            Write-Caution ('Failed to write A03 report CSV: {0}' -f $_.Exception.Message)
        }

        if (-not $okOverall) {
            Write-Caution 'One or more sub-steps reported failures; check the summary above and rerun.'
        }
        return $okOverall
    } finally {
        Stop-DebugTrace
    }
}

function Show-RefreshSnapshotsSummary {
    <#
    .SYNOPSIS
        Render the rich end-of-run summary for
        Invoke-AdminPhaseA03_RefreshSnapshots, mirroring the table
        layout used by A01_RefreshAllBaselines's summary block.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] $ReleaseInfo,
        [Parameter(Mandatory)] $DotNetCu,
        [Parameter(Mandatory)] [pscustomobject[]] $DuResults,
        [Parameter(Mandatory)] [string] $PatchMonth,
        [Parameter(Mandatory)] [string] $LatestPt,
        [Parameter(Mandatory)] [bool]   $OkOverall
    )
    Write-Host ''
    Write-Host '======================================================================'
    Write-Host ' Summary  (RefreshSnapshots)'
    Write-Host '======================================================================'
    Write-Host ''
    Write-Host '  [1] Cache files refreshed'
    Write-Host ('        release-info     : {0,-8} (monthly={1}, hotpatch={2}, raw {3} bytes)' -f $ReleaseInfo.Status, $ReleaseInfo.Monthly, $ReleaseInfo.Hotpatch, $ReleaseInfo.Bytes)
    Write-Host ('        dotnet-cu        : {0,-8} (months={1}, entries={2})' -f $DotNetCu.Status, $DotNetCu.MonthCount, $DotNetCu.EntryCount)
    Write-Host ''
    Write-Host '  [2] Dynamic Update probes (Catalog search.aspx)'
    Write-Host '        OS           DuType                   Status   KbId            UpdateId'
    Write-Host '        --------------------------------------------------------------------------------'
    foreach ($r in $DuResults) {
        $uid = if ($r.ChosenUpdateId) { ($r.ChosenUpdateId.Substring(0,[math]::Min(12,$r.ChosenUpdateId.Length))) + '...' } else { '' }
        Write-Host ('        {0,-12} {1,-23}  {2,-7}  {3,-14}  {4}' -f $r.OsVersion, $r.DuType, $r.Status, $r.KbId, $uid)
    }
    Write-Host ''
    Write-Host '  [3] Patch Tuesday timeline'
    Write-Host ('        This run baseline   : {0}  (Patch Month = {1})' -f $LatestPt, $PatchMonth)
    Write-Host ''
    Write-Host '  [4] Run outcome'
    if ($OkOverall) {
        Write-Host '        Status: OK (every sub-step reported OK or Skipped).'
        Write-Host '        Next step: run `-Action RefreshAllBaselines` to regenerate'
        Write-Host '                   data/config-Server*.json Lines[].'
    } else {
        Write-Host '        Status: PARTIAL (one or more sub-steps failed). Check the'
        Write-Host '                error messages above and rerun. Re-running is'
        Write-Host '                idempotent: successful sub-steps will overwrite'
        Write-Host '                the cache with the latest snapshot.'
    }
    Write-Host '======================================================================'
    Write-Host ''
}

# ============================================================
# Phase dispatcher and Action resolver
# ============================================================

function Get-PhaseListByAction {
    <#
    .SYNOPSIS
        Map -Action to a sequence of phase IDs.
    .DESCRIPTION
        Admin-group actions (RefreshSnapshots, RefreshAllBaselines,
        DumpFieldClassification) and applies a SyntheticTestMode
        skip to P05 / P06. The synthetic ISO produced by P04 is
        not a structurally valid ISO9660 image; Mount-DiskImage in
        P05 therefore fails with "file or directory is corrupted"
        on Windows runners. Stage 3 (Synthetic+Execute) already
        bypasses P05 by going straight to P07; this aligns Stage 2
        Smoke 3 (Synthetic+DryRun) with the same flow.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string]$ActionName)

    # Phases used by the standard build pipeline. When SyntheticTestMode
    # is set, the P05 / P06 pair is removed - synthetic ISOs cannot
    # round-trip through Mount-DiskImage.
    # P10 is listed but is default-skip inside the phase function unless
    # -EnablePca2023BootManager is specified; including it in the
    # standard pipeline ensures the pipeline-level wiring is consistent
    # and the operator's explicit opt-in actually reaches the phase.
    $standardFull = if ($Script:SyntheticTestMode) {
        [string[]]@('P01','P02','P03','P04','P07','P08','P09','P10','P11','P12','P13')
    } else {
        [string[]]@('P01','P02','P03','P04','P05','P06','P07','P08','P09','P10','P11','P12','P13')
    }
    $standardPrepare = if ($Script:SyntheticTestMode) {
        [string[]]@('P01','P02','P03','P04')
    } else {
        [string[]]@('P01','P02','P03','P04','P05','P06')
    }

    switch ($ActionName) {
        'Prepare'                 { return $standardPrepare }
        'Build'                   { return [string[]]@('P07','P08','P09','P10') }
        'Verify'                  { return [string[]]@('P11','P12','P13') }
        'PrepareBuildVerify'      { return $standardFull }
        'All'                     { return $standardFull }
        'BootTest'                { return [string[]]@() }
        'Cleanup'                 { return [string[]]@() }
        'ListPhases'              { return [string[]]@() }
        'GenerateManifest'        { return [string[]]@('P01','P02','P03') }
        'RefreshAllBaselines'      { return [string[]]@('A01') }
        'DumpFieldClassification'  { return [string[]]@('A02') }
        'RefreshSnapshots'         { return [string[]]@('A03') }
        default                   { throw ('Unknown action: {0}' -f $ActionName) }
    }
}

function Show-PhaseList {
    <#
    .SYNOPSIS
        Pretty-print the registered phases (no execution).
    #>
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host ' Registered Phases' -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
    foreach ($p in $Script:PhaseRegistry) {
        Write-Host ('  {0,-4}  {1,-22}  ({2,-7})  -> {3}' -f $p.Id, $p.Name, $p.Group, $p.Func) -ForegroundColor White
    }
    Write-Host ''
    Write-Host ' Actions:' -ForegroundColor Cyan
    foreach ($a in @('Prepare','Build','Verify','PrepareBuildVerify','BootTest','All','Cleanup','ListPhases','GenerateManifest','RefreshSnapshots','RefreshAllBaselines','DumpFieldClassification')) {
        $list = Get-PhaseListByAction -ActionName $a
        if ($list.Count -gt 0) {
            Write-Host ('  {0,-22} : {1}' -f $a, ($list -join ',')) -ForegroundColor DarkCyan
        } else {
            Write-Host ('  {0,-22} : (no registered phases)' -f $a) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
}

function Invoke-PhaseRunner {
    <#
    .SYNOPSIS
        Sequentially execute the requested phases, emitting phase
        banners and recording per-phase timing for Show-PhaseSummary.
    .DESCRIPTION
        On failure, the phase is marked 'failed' in the timing table
        and the exception is re-thrown so the top-level catch can dump
        a Debug Trace export and exit with a non-zero code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]]$PhaseIds
    )
    foreach ($id in $PhaseIds) {
        $entry = $Script:PhaseRegistry | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $entry) {
            Write-Caution ('Phase {0} is not registered; skipping.' -f $id)
            continue
        }
        if ($Script:DryRun -and ($entry.Group -in @('Build','Verify'))) {
            Write-PhaseHeader -Id $entry.Id -Name $entry.Name -Group $entry.Group
            Write-Skip ('DryRun mode: skipping {0} ({1}).' -f $entry.Id, $entry.Group)
            Write-PhaseFooter -Id $entry.Id -Status 'skipped'
            continue
        }
        if ($Script:SkipEnvCheck -and $entry.Id -eq 'P01') {
            Write-PhaseHeader -Id $entry.Id -Name $entry.Name -Group $entry.Group
            Write-Skip 'SkipEnvCheck: bypassing P01.'
            Write-PhaseFooter -Id $entry.Id -Status 'skipped'
            continue
        }

        Write-PhaseHeader -Id $entry.Id -Name $entry.Name -Group $entry.Group
        try {
            $cmd = Get-Command -Name $entry.Func -ErrorAction Stop
            & $cmd
            Write-PhaseFooter -Id $entry.Id -Status 'done'
        } catch {
            Write-PhaseFooter -Id $entry.Id -Status 'failed'
            Add-ErrorJsonlEntry -Phase $entry.Id -Kind 'failure' -Properties @{
                exType = $_.Exception.GetType().FullName
                msg = $_.Exception.Message
            }
            Write-Fail ('Phase {0} ({1}) failed: {2}' -f $entry.Id, $entry.Name, $_.Exception.Message)
            foreach ($line in ($_.ScriptStackTrace -split "`n")) {
                Write-Skip ('    ' + $line.TrimEnd())
            }
            throw
        }
    }
}

# ============================================================
# Cleanup action
# ============================================================

function Invoke-CleanupAction {
    <#
    .SYNOPSIS
        Implements -Action Cleanup. Removes the workspace tree but
        preserves the output directory unless -CleanWorkRoot also
        targets the output explicitly.
    #>
    Write-SubSection 'Cleanup workspace'
    if (Test-DangerousPath -Path $Script:WorkRoot) {
        throw ('Refusing to delete dangerous path: {0}' -f $Script:WorkRoot)
    }
    # Discard any mounts still pointing at our mount dirs
    try {
        $mounted = Invoke-DismCmdlet -CommandName 'Get-WindowsImage' -Parameters @{ Mounted = $true; ErrorAction = 'SilentlyContinue' }
        foreach ($m in @($mounted)) {
            foreach ($d in @($Script:MountInstallDir, $Script:MountBoot1Dir, $Script:MountBoot2Dir, $Script:MountWinReDir)) {
                if ($m.Path -and (($m.Path.TrimEnd('\')) -ieq ($d.TrimEnd('\')))) {
                    Write-Caution ('Discarding stale mount at {0} before cleanup.' -f $d)
                    Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path = $d; Discard = $true; ErrorAction = 'SilentlyContinue' } | Out-Null
                }
            }
        }
    } catch { $null = $_ }

    if (Test-Path -LiteralPath $Script:WorkRoot) {
        Write-Step ('Removing: {0} (preserving the Defender-exclusion state folder)' -f $Script:WorkRoot)
        # Preserve <WorkRoot>\state so a crashed run's self-heal record survives
        # -Action Cleanup; it records machine-global Defender exclusions this
        # tool added, and losing it would orphan them.
        $stateLeaf = Split-Path -Leaf $Script:StateDir
        Get-ChildItem -LiteralPath $Script:WorkRoot -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $stateLeaf } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Ok 'Workspace removed (state folder preserved).'
    } else {
        Write-Step 'Workspace already absent.'
    }
}

# ============================================================
# BootTest action (Hyper-V)
# ============================================================

function Invoke-HyperVBootTest {
    <#
    .SYNOPSIS
        Smoke test the output ISO by creating a Hyper-V Gen2 VM,
        attaching the ISO as a virtual DVD, booting it for a short
        window, then tearing the VM down.
    #>
    Write-SubSection 'Hyper-V BootTest'
    if (-not $Script:OutputIsoPath -or -not (Test-Path -LiteralPath $Script:OutputIsoPath)) {
        throw 'No output ISO is available to BootTest.'
    }
    $vmName = ('UpdateWsi_BootTest_' + (Get-Date -Format 'yyyyMMddHHmmss'))
    $vmDir  = Join-Path $Script:WorkRoot 'boottest'
    if (-not (Test-Path -LiteralPath $vmDir)) {
        New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
    }
    $vhdPath = Join-Path $vmDir ($vmName + '.vhdx')

    Set-DebugStep -Step 'create-vhdx'
    New-VHD -Path $vhdPath -SizeBytes 64GB -Dynamic | Out-Null

    Set-DebugStep -Step 'create-vm'
    New-VM -Name $vmName -Generation 2 -MemoryStartupBytes 4GB -VHDPath $vhdPath -Path $vmDir | Out-Null
    Set-VMProcessor -VMName $vmName -Count 2 | Out-Null
    Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $true -MinimumBytes 1GB -MaximumBytes 8GB -StartupBytes 4GB | Out-Null
    Add-VMDvdDrive -VMName $vmName -Path $Script:OutputIsoPath | Out-Null
    $dvd = Get-VMDvdDrive -VMName $vmName
    Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority | Out-Null
    Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter | Out-Null

    Set-DebugStep -Step 'start-vm'
    Start-VM -Name $vmName | Out-Null
    Write-Step 'VM started; waiting 60 seconds for setup to come up...'
    Start-Sleep -Seconds 60

    $state = (Get-VM -Name $vmName).State
    $heartbeat = (Get-VM -Name $vmName).Heartbeat
    Write-Step ('VM state    : {0}' -f $state)
    Write-Step ('VM heartbeat: {0}' -f $heartbeat)

    Set-DebugStep -Step 'cleanup-vm'
    try { Stop-VM -Name $vmName -TurnOff -Force | Out-Null } catch { $null = $_ }
    Remove-VM -Name $vmName -Force | Out-Null
    if (Test-Path -LiteralPath $vhdPath) {
        Remove-Item -LiteralPath $vhdPath -Force -ErrorAction SilentlyContinue
    }

    if ($state -eq 'Running') {
        Write-Ok 'BootTest passed: VM reached Running state within 60s.'
    } else {
        throw ('BootTest failed: VM state was {0}.' -f $state)
    }
}

# ============================================================
# Top-level orchestration
# ============================================================

function Show-EntryBanner {
    $line = '=' * 72
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Host ' Windows Server ISO Updater' -ForegroundColor Cyan
    Write-Host (' Version: {0}  [{1}]' -f $Script:ScriptVersion, $Script:ScriptTag) -ForegroundColor DarkCyan
    Write-Host (' SHA256 : {0}' -f $Script:ScriptHash) -ForegroundColor DarkCyan
    Write-Host (' Action : {0}' -f $Action) -ForegroundColor White
    if ($Script:OsVersion) {
        Write-Host (' OS     : {0} / {1}' -f $Script:OsVersion, $Script:OsLanguage) -ForegroundColor White
    }
    Write-Host (' WorkRoot: {0}' -f $Script:WorkRoot) -ForegroundColor White
    Write-Host $line -ForegroundColor Cyan
}

# ============================================================
# Main entrypoint
# ============================================================

# Optional -LogFile transcript.
# $Script:TranscriptStarted is set to $true on a successful
# Start-Transcript call so the script-end finally block can decide
# whether to call Stop-Transcript. Without this flag we cannot tell
# whether transcript started successfully vs. failed silently.
$Script:TranscriptStarted = $false
if ($Script:LogFile) {
    $Script:LogFile = Resolve-RelativeToScript $Script:LogFile
    $logParent = [System.IO.Path]::GetDirectoryName($Script:LogFile)
    if (-not (Test-Path -LiteralPath $logParent)) {
        New-Item -ItemType Directory -Path $logParent -Force | Out-Null
    }
    try {
        # psa-disable-next-line PSA3005 -- Start-Transcript has no -LiteralPath parameter; -Path is the only option in PS 5.1/7
        Start-Transcript -Path $Script:LogFile -Append -Force | Out-Null
        $Script:TranscriptStarted = $true
        # Register-EngineEvent PowerShell.Exiting fires only when the
        # PowerShell host process exits (e.g. .\script.ps1 invoked from
        # cmd.exe or a non-interactive shell). When the script is run
        # interactively the host stays alive, so we ALSO call
        # Stop-Transcript explicitly in the script-end finally block;
        # see the finally guard near the script tail.
        Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
            try { Stop-Transcript | Out-Null } catch { $null = $_ }
        } | Out-Null
    } catch {
        Write-Warning ('Could not start transcript: {0}' -f $_.Exception.Message)
    }
}

# TestHarness short-circuit.
# Loads all function definitions into the current PowerShell session and
# enters a JSON-over-stdin REPL: each input line is parsed as JSON
# `{ "fn": "<function-name>", "args": { ... } }`, the named function is
# invoked with the splatted args, and the result is emitted as a single
# JSON line on stdout (`{ "ok": true, "result": ... }` or
# `{ "ok": false, "error": "<message>" }`).
#
# This is the entry point for the Python-side test harness in
# `tests/powershell_harness.py`, which uses it to assert PowerShell-level
# invariants (e.g. that `Get-CatalogQueryTemplate -OsVersion Server2022`
# returns TitleTokens with both comma forms). It is intentionally a
# separate Action rather than a side effect of -EnvironmentInfoOnly or
# -DryRun, because the harness must NOT emit the entry banner or any
# Phase activity: every byte on stdout must be machine-readable JSON.
#
# Lifecycle: enter REPL, exit on EOF (closed stdin). No workspace
# preflight runs because there is no workspace contact; no DISM, no
# Catalogue scrape, no file writes outside what the invoked function
# itself does.
if ($Action -eq 'TestHarness') {
    # Suppress entry banner: we already skipped it above.
    # Now drain stdin one JSON line at a time.
    $ErrorActionPreference = 'Stop'
    while (-not [Console]::In.EndOfStream) {
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { break }
        $line = $line.Trim()
        if ($line -eq '') { continue }
        try {
            $req = $line | ConvertFrom-Json -ErrorAction Stop
            $fnName = [string]$req.fn
            if ([string]::IsNullOrEmpty($fnName)) {
                throw 'Missing "fn" field in request.'
            }
            $cmd = Get-Command -Name $fnName -ErrorAction SilentlyContinue
            if (-not $cmd) {
                throw ('Function not found in session: ' + $fnName)
            }
            $splat = @{}
            if ($req.PSObject.Properties['args'] -and $req.args) {
                foreach ($prop in $req.args.PSObject.Properties) {
                    $splat[$prop.Name] = $prop.Value
                }
            }
            # TestHarness contract: the ONLY thing that may reach stdout per
            # request is the single JSON response line emitted below. Some
            # functions under test route DISM access through Invoke-DismCmdlet,
            # which logs via Write-Host (the information stream). On pwsh 7.x the
            # information stream renders to stdout and would corrupt the
            # one-JSON-object-per-line contract that the Python harness
            # (tests/common/ps_invoke.py) reads. Redirect the information stream
            # to $null for the duration of the call so only the success-stream
            # result is captured; the canonical logging helpers are unchanged.
            $result = & $cmd @splat 6>$null
            $payload = [pscustomobject]@{
                ok     = $true
                fn     = $fnName
                result = $result
            }
            $payload | ConvertTo-Json -Depth 12 -Compress
        } catch {
            $errPayload = [pscustomobject]@{
                ok    = $false
                error = $_.Exception.Message
                fn    = if ($null -ne $req -and $req.PSObject.Properties['fn']) { [string]$req.fn } else { '' }
            }
            $errPayload | ConvertTo-Json -Depth 4 -Compress
        }
    }
    exit 0
}

Show-EntryBanner

# Quick branch for actions that do not need workspace init
if ($Action -eq 'ListPhases') {
    Show-PhaseList
    exit 0
}

# -Pca2023OnlyMode: standalone P12 against an existing ISO.
# Argument set: -IsoPath <existing.iso> -Pca2023OnlyMode
# Skips all the patching machinery; mounts the ISO read-only,
# extracts it into a temporary work tree, runs Get-OrEnsurePca2023Snapshot,
# emits the same pca2023_readiness.{json,md} as P12 would have.
if ($Pca2023OnlyMode) {
    if (-not $IsoPath) {
        throw '-Pca2023OnlyMode requires -IsoPath <path-to-existing-iso>.'
    }
    if (-not (Test-Path -LiteralPath $IsoPath)) {
        throw ('-IsoPath does not exist: {0}' -f $IsoPath)
    }
    Write-Step ('Pca2023OnlyMode: inspecting {0}' -f $IsoPath)

    # Mount ISO and copy to a scratch dir (we need write access to
    # mount the contained WIMs).
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('updwsi_pca2023only_{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
    if (-not (Test-Path -LiteralPath $scratch)) {
        New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    }
    $img = $null
    try {
        $img = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
        $vol = $img | Get-Volume
        $driveLetter = ($vol.DriveLetter + ':')
        Write-Step ('ISO mounted at: {0}' -f $driveLetter)
        $extract = Join-Path $scratch 'extracted'
        Write-Step ('Copying ISO contents to: {0}' -f $extract)
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        Copy-Item -Path ('{0}\*' -f $driveLetter) -Destination $extract -Recurse -Force -ErrorAction Stop
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
        $img = $null

        # Best-effort OsKey inference from ISO filename
        $osKey = $null
        if ($IsoPath -match 'Server\s*2016|WS2016') { $osKey = 'Server2016' }
        elseif ($IsoPath -match 'Server\s*2019|WS2019') { $osKey = 'Server2019' }
        elseif ($IsoPath -match 'Server\s*2022|WS2022') { $osKey = 'Server2022' }
        elseif ($IsoPath -match 'Server\s*2025|WS2025') { $osKey = 'Server2025' }

        $snap = Get-Pca2023ReadinessSnapshot -ExtractedMediaPath $extract -WorkRoot $scratch -OsKey $osKey
        Show-Pca2023ReadinessSnapshot -Snapshot $snap

        $jsonPath = Join-Path $scratch 'pca2023_readiness.json'
        Save-CanonicalJsonFile -InputObject $snap -Path $jsonPath -Depth 10
        Write-Step ('Snapshot written: {0}' -f $jsonPath)
        $reportText = Format-Pca2023ReadinessForReport -Snapshot $snap
        $mdPath = Join-Path $scratch 'pca2023_readiness.txt'
        Set-Content -LiteralPath $mdPath -Value $reportText -Encoding UTF8 -Force
        Write-Step ('Detail text written: {0}' -f $mdPath)
    } finally {
        if ($img) {
            try { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null } catch { $null = $_ }
        }
    }
    exit 0
}

# Workspace preflight.
# Verifies that (1) the data directory and all four canonical
# data/config-Server<N>.json files exist alongside the script, and (2) the
# drive backing -WorkRoot has at least 100 GB free space (the minimum
# required to host an end-to-end PrepareBuildVerify run for one OS:
# input ISO ~7 GB + extracted ~7 GB + mounted WIM ~15 GB + patches
# ~10 GB + output ISO ~7 GB + DISM scratch + headroom).
#
# Preflight runs BEFORE the Action dispatcher (rather than inside P01)
# so that Admin actions like -Action RefreshAllBaselines and
# -Action DumpFieldClassification (which never run P01) are also
# protected. The check is fatal: missing Config files or a too-small
# drive short-circuit the run before any Catalogue scrape or DISM
# mount is attempted.
#
# Skipped for:
#   - 'Cleanup' (the point of Cleanup is to remove a partially-built
#     workspace; requiring 100 GB free would be circular)
#   - -EnvironmentInfoOnly (the user explicitly asked for the env
#     dump only and wants to inspect the host first)
#   - -SkipEnvCheck (operator override)
#
# The disk-space half of the check is also skipped under -DryRun
# (Assert-WorkspacePreflight handles this internally) because dry
# runs do not actually write large files.
if (-not ($Action -eq 'Cleanup' -or $Action -eq 'TestHarness' -or $EnvironmentInfoOnly -or $SkipEnvCheck)) {
    Assert-WorkspacePreflight
}

# Optional clean
if ($Script:CleanWorkRoot -and (Test-Path -LiteralPath $Script:WorkRoot)) {
    Write-Caution ('CleanWorkRoot: deleting {0}' -f $Script:WorkRoot)
    if (Test-DangerousPath -Path $Script:WorkRoot) {
        throw ('Refusing to clean dangerous path: {0}' -f $Script:WorkRoot)
    }
    Remove-Item -LiteralPath $Script:WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Initialize-RuntimeDirectories -Directory @($Script:WorkRoot, $Script:OutputDir, $Script:SourceDir, $Script:IsoSourceDir, $Script:ExtractedDir, $Script:PatchesDir, $Script:ManifestsDir, (Join-Path $Script:WorkRoot 'work'), $Script:TempDir, $Script:ScratchDir, $Script:LogsDir, $Script:DiagDir, $Script:MarkersDir, $Script:StateDir)

# Activate debug trace JSONL file output
try {
    Enable-DebugTraceFileOutput -Directory $Script:LogsDir | Out-Null
    Enable-AutoExportOnPhaseFailure -OutputDirectory $Script:DiagDir | Out-Null
} catch {
    Write-Warning ('Debug Trace setup warning: {0}' -f $_.Exception.Message)
}

$Script:ExitCode = 0
try {
    # Self-heal: remove any Defender exclusions left by a crashed prior run
    # (reads the WorkRoot state file; no-op if absent). Runs for every action.
    Invoke-DefenderExclusionSelfHeal

    if ($Action -eq 'Cleanup') {
        Invoke-CleanupAction
        exit 0
    }

    # Decide phase list
    if ($EnvironmentInfoOnly) {
        # -EnvironmentInfoOnly is a smoke-test convenience: run only P01
        # so Step 0 (PowerShell environment dump) fires, then exit
        # normally. It must NOT progress to P02+, which would require
        # -OsVersion and other inputs the smoke caller did not pass.
        $phaseList = @('P01')
    } elseif ($OnlyPhases -and $OnlyPhases.Count -gt 0) {
        $phaseList = $OnlyPhases
    } else {
        $phaseList = Get-PhaseListByAction -ActionName $Action
    }

    # Opt-in Defender exclusions for the servicing run (fail-closed; removed
    # in the finally below).
    Enable-ManagedDefenderExclusion

    if ($phaseList.Count -gt 0) {
        Invoke-PhaseRunner -PhaseIds $phaseList
    }

    if ($Action -in @('BootTest','All')) {
        try {
            Invoke-HyperVBootTest
        } catch {
            Write-Fail ('BootTest failed: {0}' -f $_.Exception.Message)
            $Script:ExitCode = 1
        }
    }

    if ($Action -eq 'GenerateManifest') {
        Write-Caution 'GenerateManifest action is a placeholder in this revision. See SPEC Part H.2.'
    }
} catch {
    $Script:ExitCode = 1
    Write-Fail ('Run failed: {0}' -f $_.Exception.Message)
    # Auto-export any active debug trace (best-effort).
    # Export-DebugTraceJson takes -Path (a file), not -OutputDir;
    # synthesise a timestamped filename under DiagDir.
    try {
        if (Get-Command -Name 'Export-DebugTraceJson' -ErrorAction SilentlyContinue) {
            if ($Script:DiagDir) {
                if (-not (Test-Path -LiteralPath $Script:DiagDir)) {
                    New-Item -ItemType Directory -Path $Script:DiagDir -Force | Out-Null
                }
                $debugTraceFile = Join-Path $Script:DiagDir ('debugtrace-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))
                Export-DebugTraceJson -Path $debugTraceFile | Out-Null
            }
        }
    } catch { $null = $_ }
} finally {
    # Always remove any Defender exclusions this run added (reads the state
    # file; removes only what we recorded; no-op if none).
    try { Disable-ManagedDefenderExclusion } catch { $null = $_ }
    try {
        Show-PhaseSummary
    } catch { $null = $_ }
    # Always stop transcript when we started one. PowerShell.Exiting
    # only fires on host shutdown, but an interactive .\script.ps1
    # invocation returns to the prompt while the host keeps running,
    # leaving the transcript open until the user types `exit`. The
    # explicit Stop-Transcript here closes that gap.
    if ($Script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { $null = $_ }
        $Script:TranscriptStarted = $false
    }
}

exit $Script:ExitCode
