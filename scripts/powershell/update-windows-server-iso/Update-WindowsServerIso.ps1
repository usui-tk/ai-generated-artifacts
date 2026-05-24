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
    Location  : scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1
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
      - Optional: python3 + scripts/python/powershell-static-analyzer/psa.py
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
    Phases (P01..P09):
      P01 : Initialize        (Setup ) PowerShell env, admin, ADK, disk, Hyper-V
      P02 : ResolveInputs     (Setup ) ISO/patch source resolution, Config JSON
      P03 : FetchAssets       (Fetch ) ISO + patch downloads with hash verify
      P04 : ExpandIso         (Plan  ) Mount source ISO, copy to workspace,
                                       enumerate WIM indexes
      P05 : PatchInstallWim   (Build ) For each install.wim index: SSU then LCU
                                       then .NET, then DISM cleanup
      P06 : PatchBootWim      (Build ) boot.wim (PE + Setup) and winre.wim
      P07 : AssembleIso       (Build ) Dynamic Update Setup overlay,
                                       Export-WindowsImage, oscdimg ISO build
      P08 : StaticVerify      (Verify) Mount output ISO, confirm KB packages
                                       are present
      P09 : FinalReport       (Report) End-of-run summary + ISO hash + log
                                       paths

    Optional out-of-band action: BootTest (Hyper-V VM smoke test, P10 equiv).

.PARAMETER Action
    One of: Prepare / Build / Verify / PrepareBuildVerify / BootTest / All /
    Cleanup / ListPhases / GenerateManifest. Default: PrepareBuildVerify.

.PARAMETER OnlyPhases
    Array of phase IDs (e.g. 'P03','P05') to run. Overrides -Action.

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
    Skip the P02.5 RefreshPatchBaseline phase even if the baseline is
    stale. Useful for offline or air-gapped runs..

.PARAMETER UseBaselineOnly
    Use PatchBaseline.Patches strictly as-is, never scrape, never
    refresh. Equivalent to -SkipDynamicPatchRefresh plus a guarantee
    that no Catalog access occurs..

.PARAMETER IgnorePatchValidation
    Demote P04.5 ValidatePatchSet failures from "abort" to "warning".
    NOT recommended for production runs; intended for development..

.PARAMETER WsusScnCabPath
    Path to a pre-staged wsusscn2.cab file. When specified, the P04.5
    ValidatePatchSet phase will use this file instead of downloading
    one to <WorkRoot>/cache/..

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
#>

[CmdletBinding()]
param(
    [ValidateSet('Prepare','Build','Verify','PrepareBuildVerify','BootTest','All','Cleanup','ListPhases','GenerateManifest','RefreshAllBaselines','DumpFieldClassification')]
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
    [switch]   $IgnorePatchValidation,
    [string]   $WsusScnCabPath,
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

    [string]   $WorkRoot             = 'C:\Temp\Workspace_UpdateWsi',
    [string]   $OutputDir,
    [string]   $OnlyInstallWimIndexes,

    [switch]   $CleanWorkRoot,
    [string]   $LogFile,
    [switch]   $DryRun,
    [switch]   $SkipEnvCheck,
    [switch]   $EnvironmentInfoOnly,

    [switch]   $SyntheticTestMode,
    [switch]   $EvalIsoMode,
    [switch]   $Execute
)

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

# ---- mutual exclusivity / format validation (P02.5 / P04.5 params) ----
if ($SkipDynamicPatchRefresh -and $AutoDetectLatestPatches) {
    throw '-SkipDynamicPatchRefresh and -AutoDetectLatestPatches are mutually exclusive.'
}
if ($UseBaselineOnly -and $AutoDetectLatestPatches) {
    throw '-UseBaselineOnly and -AutoDetectLatestPatches are mutually exclusive.'
}
if ($PatchMonth -and ($PatchMonth -notmatch '^\d{4}-\d{2}$')) {
    throw ('-PatchMonth must be in yyyy-MM format (e.g. 2026-06). Got: "' + $PatchMonth + '"')
}
if ($WsusScnCabPath -and -not (Test-Path -LiteralPath $WsusScnCabPath)) {
    # Just a friendly early warning; the validator will retry/error later.
    Write-Verbose ('Configured -WsusScnCabPath does not yet exist: ' + $WsusScnCabPath)
}
# ----------

# Several non-trivial actions require OsVersion. ListPhases and
# EnvironmentInfoOnly are the only ones that should be allowed without it
# so a CI smoke run can succeed without picking a target OS.
# Some actions don't operate on a single OS instance and therefore
# don't need -OsVersion. ListPhases, EnvironmentInfoOnly, Cleanup,
# and the Admin actions (RefreshAllBaselines, DumpFieldClassification)
# operate on the on-disk Config files or the script itself.
$osLessActions = @('ListPhases','Cleanup','RefreshAllBaselines','DumpFieldClassification')
$needsOsVersion = ($Action -notin $osLessActions) -and (-not $EnvironmentInfoOnly)
if ($needsOsVersion -and [string]::IsNullOrEmpty($OsVersion)) {
    throw '-OsVersion is required for action "' + $Action + '". Specify Server2016 / Server2019 / Server2022 / Server2025.'
}

# ============================================================
# Initial setup
# ============================================================

$ErrorActionPreference = 'Stop'
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

function Resolve-RelativeToScript {
    # Make a path absolute. Relative paths resolve against $Script:ScriptRoot.
    param([Parameter(Mandatory)] [string]$Path)
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $Script:ScriptRoot $Path
    }
    return [System.IO.Path]::GetFullPath($Path)
}

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
$Script:LogsDir           = Join-Path $Script:WorkRoot 'logs'
$Script:DiagDir           = Join-Path $Script:WorkRoot 'diag'
$Script:MarkersDir        = Join-Path $Script:WorkRoot '.markers'

function Initialize-RuntimeDirectories { # psa-disable-line PSA6003 -- "Directories" is plural by design; multiple workspace dirs are created in a single call
    # Idempotently (re-)create the directory tree the script needs.
    # Called once during startup, after any optional -CleanWorkRoot wipe.
    # Mount directories are recreated on demand by P05/P06; only the
    # parent and stable working dirs are touched here.
    foreach ($d in @(
        $Script:WorkRoot, $Script:OutputDir,
        $Script:SourceDir, $Script:IsoSourceDir, $Script:ExtractedDir,
        $Script:PatchesDir, $Script:ManifestsDir,
        (Join-Path $Script:WorkRoot 'work'),
        $Script:TempDir, $Script:LogsDir, $Script:DiagDir, $Script:MarkersDir
    )) {
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
#   ScriptVersion : bump on every meaningful edit. Format: <prefix>-YYYY.MM.DD-rNN
#   ScriptTag     : short human-readable label describing the build
#   ScriptHash    : auto-computed SHA256 (first 12 chars) of the actual
#                   file being executed. Changes for any byte-level edit;
#                   does NOT need manual bumping.
$Script:ScriptVersion = 'update-wsi-2026.05.24-r04'
$Script:ScriptTag     = 'wim-target-aware-patch-plan'
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

# Phase Registry: declared up front so -Action ListPhases can work
# without running any phase functions. Func names are bound by
# convention; Invoke-PhaseRunner resolves them via Get-Command.
$Script:PhaseRegistry = @(
    [pscustomobject]@{ Id='P01';   Name='Initialize';                Group='Setup';  Func='Invoke-SetupPhase01_Initialize' }
    [pscustomobject]@{ Id='P02';   Name='ResolveInputs';             Group='Setup';  Func='Invoke-SetupPhase02_ResolveInputs' }
    [pscustomobject]@{ Id='P02.5'; Name='RefreshPatchBaseline';      Group='Setup';  Func='Invoke-SetupPhase02_5_RefreshPatchBaseline' }
    [pscustomobject]@{ Id='P03';   Name='FetchAssets';               Group='Fetch';  Func='Invoke-FetchPhase03_FetchAssets' }
    [pscustomobject]@{ Id='P04';   Name='ExpandIso';                 Group='Plan';   Func='Invoke-PlanPhase04_ExpandIso' }
    [pscustomobject]@{ Id='P04.5'; Name='ValidatePatchSet';          Group='Plan';   Func='Invoke-PlanPhase04_5_ValidatePatchSet' }
    [pscustomobject]@{ Id='P05';   Name='PatchInstallWim';           Group='Build';  Func='Invoke-BuildPhase05_PatchInstallWim' }
    [pscustomobject]@{ Id='P06';   Name='PatchBootWim';              Group='Build';  Func='Invoke-BuildPhase06_PatchBootWim' }
    [pscustomobject]@{ Id='P07';   Name='AssembleIso';               Group='Build';  Func='Invoke-BuildPhase07_AssembleIso' }
    [pscustomobject]@{ Id='P08';   Name='StaticVerify';              Group='Verify'; Func='Invoke-VerifyPhase08_StaticVerify' }
    [pscustomobject]@{ Id='P09';   Name='FinalReport';               Group='Report'; Func='Invoke-ReportPhase09_FinalReport' }
    [pscustomobject]@{ Id='A01';   Name='RefreshAllBaselines';       Group='Admin';  Func='Invoke-AdminPhaseA01_RefreshAllBaselines' }
    [pscustomobject]@{ Id='A02';   Name='DumpFieldClassification';   Group='Admin';  Func='Invoke-AdminPhaseA02_DumpFieldClassification' }
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
        Refresher   = 'Resolve-PatchSetFromCatalog'
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
# A patch may target multiple WIMs. Phase workers (P05/P06) iterate the
# active target set and apply only the patches whose Type maps to that
# target. Unknown Types are treated as Install-only with a warning.
#
# Microsoft public guidance behind this mapping:
#   - SSU                    : required on every serviced WIM
#   - LCU                    : Install + Boot (WinRE uses SafeOS DU instead)
#   - DotNet                 : Install only (.NET 4.x lives in install.wim)
#   - DynamicUpdate.Component: Install only (component-store updates)
#   - DynamicUpdate.SafeOs   : WinRE only (WinRE is the "Safe OS")
#   - DynamicUpdate.Setup    : Setup binaries (handled via pending.xml)
#   - LanguagePack           : Install + WinRE (user-facing UI + recovery UI)
#   - LXP                    : Install only (LXPs are Store apps; no WinRE)
#   - DotNet.LangPack        : Install only (.NET satellite assemblies)
$Script:PatchTargetMap = @{
    'SSU'                      = @('Install', 'Boot', 'WinRE')
    'LCU'                      = @('Install', 'Boot')
    'DotNet'                   = @('Install')
    'DynamicUpdate.Component'  = @('Install')
    'DynamicUpdate.SafeOs'     = @('WinRE')
    'DynamicUpdate.Setup'      = @('Setup')
    'LanguagePack'             = @('Install', 'WinRE')
    'LXP'                      = @('Install')
    'DotNet.LangPack'          = @('Install')
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
#     "phase"         : "<PNN>"             (e.g. P02.5, P05),
#     "kind"          : "<kind>"            (e.g. failure, warning),
#     ...properties from -Properties hashtable, merged in...
#   }
#
# Failures inside Add-ErrorJsonlEntry are deliberately swallowed so the
# main pipeline cannot be derailed by a logging glitch.

function Add-ErrorJsonlEntry {
    <#
    .SYNOPSIS
        Append one structured JSON-Lines record to the run-level errors
        log at $Script:ErrorsJsonlPath.
    .PARAMETER Phase
        Phase identifier (e.g. 'P02.5', 'P05'). Required.
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWMICmdlet', '',
        Justification = 'Intentional Get-WmiObject fallback path. CIM is the primary path; WMI is the secondary path used only when CIM is constrained (some Server Core / container images). PS 5.1 supports both; PS 7+ exposes Get-WmiObject only when the WMI compatibility module is loaded, which is fine because the script declares PS 5.1+ as its baseline.')]
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

# ============================================================
# ISO Updater specific: configuration profile
# ============================================================

function Get-ConfigProfile {
    <#
    .SYNOPSIS
        Load the OS profile JSON (Schema v2.0) for the given OsKey and
        resolve the language sub-profile for OsLang.
    .DESCRIPTION
        v2.0 layout: top-level keys are Schema, OsKey, Common,
        PatchBaseline, AutoRefreshPolicy, LanguageSpecific.<lang>.
        This loader validates Schema == "2.0" and returns a flat
        pscustomobject for backward-compatible access patterns used by
        downstream phases: properties from Common are promoted to the
        top level of the returned object, PatchBaseline / AutoRefreshPolicy
        are passed through verbatim, the resolved language sub-profile
        is attached as 'Language', and the entire LanguageSpecific
        dictionary is attached as 'LanguageSpecific' for Action workers
        (RefreshAllBaselines) that need cross-language access.

        Legacy v1.0 configs are NOT supported; the loader throws
        immediately if the Schema field is missing or wrong.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsKey,
        [Parameter(Mandatory)] [ValidateSet('en-us','ja-jp')] [string]$OsLang,
        [string]$ConfigRoot
    )

    if ([string]::IsNullOrEmpty($ConfigRoot)) {
        $ConfigRoot = Join-Path $Script:ScriptRoot 'Config'
    }
    $cfgFile = Join-Path $ConfigRoot ($OsKey + '.json')
    if (-not (Test-Path -LiteralPath $cfgFile)) {
        throw ('Config profile not found: {0}' -f $cfgFile)
    }

    $raw = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8
    $json = $raw | ConvertFrom-Json

    # Schema validation (v2.0 strict)
    if (-not $json.Schema -or $json.Schema -ne '2.0') {
        throw ('Config {0} has Schema="{1}"; expected "2.0". Legacy schemas are not supported.' -f $cfgFile, $json.Schema)
    }
    if (-not $json.Common) {
        throw ('Config {0} has no Common section.' -f $cfgFile)
    }
    if (-not $json.LanguageSpecific) {
        throw ('Config {0} has no LanguageSpecific section.' -f $cfgFile)
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
        Schema             = $json.Schema
        OsKey              = $json.OsKey
        Build              = $json.Common.Build
        OsShortName        = $json.Common.OsShortName
        Edition            = $json.Common.Edition
        Architecture       = $json.Common.Architecture
        WimEdition         = $json.Common.WimEdition
        InstallWimIndex    = $json.Common.InstallWimIndex
        BootWimIndexes     = $json.Common.BootWimIndexes
        WinReWimPath       = $json.Common.WinReWimPath
        SupportedLanguages = $json.Common.SupportedLanguages
        DefaultLanguage    = $json.Common.DefaultLanguage
        LCUExpandViaMum    = $json.Common.LCUExpandViaMum
        Common             = $json.Common
        PatchBaseline      = $json.PatchBaseline
        AutoRefreshPolicy  = $json.AutoRefreshPolicy
        LanguageSpecific   = $json.LanguageSpecific
        Language           = $langNode
        LanguageKey        = $OsLang
        # Raw is exposed for admin actions (RefreshAllBaselines) which
        # need to mutate-and-persist the on-disk JSON shape.
        Raw                = $json
        ConfigFilePath     = $cfgFile
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

    $name = Split-Path -LiteralPath $IsoPath -Leaf
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
        Heuristic classification of a patch file as SSU / LCU / DotNet /
        DynamicUpdate.* / Defender / Edge / Other.
    .DESCRIPTION
        Microsoft does not embed the patch type in the filename in a
        machine-readable way, so the classifier matches against
        well-known token patterns documented in the Update History
        pages.
    #>
    param([Parameter(Mandatory)] [string]$FileName)
    $n = $FileName.ToLower()
    if ($n -match 'servicingstack' -or $n -match 'ssu')         { return 'SSU' }
    if ($n -match 'ndp[0-9]+'      -or $n -match '\.net')       { return 'DotNet' }
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
        'DotNet'                    { return 6 }
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
          - PatchBaseline.Patches has zero usable entries
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
    if (-not $Baseline.Patches -or $Baseline.Patches.Count -eq 0) { return $false }
    $usable = @($Baseline.Patches | Where-Object {
        $_.KbId -and $_.DownloadUrl -and $_.Sha256 -and ($_.Sha256 -ne '')
    })
    return ($usable.Count -gt 0)
}

function Test-PatchBaselineUsable {
    <#
    .SYNOPSIS
        Returns $true if PatchBaseline.Patches has any usable entry.
        Distinct from Test-PatchBaselineFresh: this one ignores age.
        Used by the fallback-on-scrape-failure path (SPEC C.3).
    #>
    [OutputType([bool])]
    param([Parameter(Mandatory)] [AllowNull()] $Baseline)
    if (-not $Baseline -or -not $Baseline.Patches) { return $false }
    $usable = @($Baseline.Patches | Where-Object {
        $_.KbId -and $_.DownloadUrl -and $_.Sha256 -and ($_.Sha256 -ne '')
    })
    return ($usable.Count -gt 0)
}

function Save-ConfigWithBaseline {
    <#
    .SYNOPSIS
        Write the in-memory OsProfile (with updated PatchBaseline) back
        to its Config JSON file, preserving field order where possible.
    .DESCRIPTION
        Used by P02.5 when AutoRefreshPolicy.WritebackToConfig = $true.
        Emits LF line endings (per repo .gitattributes for *.json) and
        UTF-8 without BOM. Uses Depth 32 to fully serialise patch arrays.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string]$ConfigPath,
        [Parameter(Mandatory)] $OsProfile
    )
    # ConvertTo-Json with -Depth handles nested PatchBaseline.Patches
    $json = $OsProfile | ConvertTo-Json -Depth 32
    # Normalise to LF (json files are eol=lf per repo .gitattributes)
    $json = $json -replace "`r`n", "`n"
    # Append trailing newline for POSIX-friendliness
    if (-not $json.EndsWith("`n")) { $json = $json + "`n" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    # WriteAllBytes is atomic on the same filesystem
    [System.IO.File]::WriteAllBytes($ConfigPath, $bytes)
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
        [string[]]$ApplicableLanguages  = @('neutral')
    )
    $fn = $FileName
    if ([string]::IsNullOrEmpty($fn) -and $DownloadUrl) {
        # Recover filename from URL leaf
        try { $fn = [System.IO.Path]::GetFileName(([uri]$DownloadUrl).AbsolutePath) }
        catch { $fn = '' }
    }
    $pType  = Get-PatchType -FileName $fn
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
        Resolve the on-disk path of the active Config/<OsKey>.json file,
        so the P02.5 writeback knows where to save.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$OsKey)
    $here = $Script:ScriptRoot
    if ([string]::IsNullOrEmpty($here)) { $here = $PSScriptRoot }
    if ([string]::IsNullOrEmpty($here)) { $here = (Get-Location).Path }
    return (Join-Path $here ('Config' + [System.IO.Path]::DirectorySeparatorChar + $OsKey + '.json'))
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

function Get-CatalogQueryTemplate {
    <#
    .SYNOPSIS
        Returns the canonical Catalogue search query templates and Title
        filter tokens for a given OsVersion, as documented by Microsoft
        in https://learn.microsoft.com/windows/deployment/update/media-dynamic-update.
    .DESCRIPTION
        Each OS version uses a different Title pattern in the Catalogue
        (e.g. Server 2022 uses "...server operating system, version 21H2"
        with a literal comma, Server 2025 uses "...version 24H2" without).
        This helper encapsulates those differences so the caller can do
        a precise OS-specific search rather than the previous loose
        single-token match that conflated OS variants.

        Returned object has shape:
          @{
            OsVersion   = 'Server2022'
            TitleTokens = @('Microsoft server operating system, version 21H2')
            Queries     = @(
                @{ Type='SSU'; QueryTemplate='{0} Servicing Stack Update for Microsoft server operating system, version 21H2'; ... }
                ...
            )
          }
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)] [string]$PatchMonth
    )
    $m = $PatchMonth
    $templates = @{
        'Server2025' = @{
            TitleTokens = @('Microsoft server operating system version 24H2')
            Queries = @(
                @{ Type='SSU';                  QueryTemplate=($m + ' Servicing Stack Update for Microsoft server operating system version 24H2'); ProductFilter=@(); DescriptionFilter='' }
                @{ Type='LCU';                  QueryTemplate=($m + ' Cumulative Update for Microsoft server operating system version 24H2');     ProductFilter=@(); DescriptionFilter='' }
                @{ Type='DynamicUpdate.Setup';  QueryTemplate=($m + ' Setup Dynamic Update for Microsoft server operating system version 24H2');  ProductFilter=@(); DescriptionFilter='' }
                @{ Type='DynamicUpdate.SafeOs'; QueryTemplate=($m + ' Safe OS Dynamic Update for Microsoft server operating system version 24H2'); ProductFilter=@(); DescriptionFilter='' }
                @{ Type='DotNet';               QueryTemplate=($m + ' Cumulative Update for .NET Framework');                                     ProductFilter=@('.NET Framework'); DescriptionFilter='' }
            )
        }
        'Server2022' = @{
            # 2022 uses comma form "...server operating system, version 21H2"
            TitleTokens = @('Microsoft server operating system, version 21H2')
            Queries = @(
                @{ Type='SSU';                  QueryTemplate=($m + ' Servicing Stack Update for Microsoft server operating system, version 21H2'); ProductFilter=@(); DescriptionFilter='' }
                @{ Type='LCU';                  QueryTemplate=($m + ' Cumulative Update for Microsoft server operating system, version 21H2');     ProductFilter=@(); DescriptionFilter='' }
                # 2022 uses "Dynamic Update" without "Setup/Safe OS" prefix in title; Product/Description disambiguates
                @{ Type='DynamicUpdate.Setup';  QueryTemplate=($m + ' Dynamic Update for Microsoft server operating system, version 21H2'); ProductFilter=@('Windows 10 and later Dynamic Update'); DescriptionFilter='SetupUpdate' }
                @{ Type='DynamicUpdate.SafeOs'; QueryTemplate=($m + ' Dynamic Update for Microsoft server operating system, version 21H2'); ProductFilter=@('Windows Safe OS Dynamic Update'); DescriptionFilter='ComponentUpdate' }
                @{ Type='DotNet';               QueryTemplate=($m + ' Cumulative Update for .NET Framework');                              ProductFilter=@('.NET Framework'); DescriptionFilter='' }
            )
        }
        'Server2019' = @{
            TitleTokens = @('Windows Server 2019')
            Queries = @(
                @{ Type='SSU';                  QueryTemplate=($m + ' Servicing Stack Update for Windows Server 2019 for x64-based Systems'); ProductFilter=@(); DescriptionFilter='' }
                @{ Type='LCU';                  QueryTemplate=($m + ' Cumulative Update for Windows Server 2019 for x64-based Systems');      ProductFilter=@(); DescriptionFilter='' }
                # Server 2019 does not ship Setup/SafeOs DU monthly; only on feature-update windows
                @{ Type='DotNet';               QueryTemplate=($m + ' Cumulative Update for .NET Framework');                                  ProductFilter=@('.NET Framework'); DescriptionFilter='' }
            )
        }
        'Server2016' = @{
            TitleTokens = @('Windows Server 2016')
            Queries = @(
                @{ Type='SSU';                  QueryTemplate=($m + ' Servicing Stack Update for Windows Server 2016 for x64-based Systems'); ProductFilter=@(); DescriptionFilter='' }
                @{ Type='LCU';                  QueryTemplate=($m + ' Cumulative Update for Windows Server 2016 for x64-based Systems');      ProductFilter=@(); DescriptionFilter='' }
                @{ Type='DotNet';               QueryTemplate=($m + ' Cumulative Update for .NET Framework');                                  ProductFilter=@('.NET Framework'); DescriptionFilter='' }
            )
        }
    }
    if (-not $templates.ContainsKey($OsVersion)) {
        throw ('No Catalogue query template for OsVersion ' + $OsVersion)
    }
    return $templates[$OsVersion]
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
            Wait-WithJitter -BaseSeconds 2 -MaxSeconds 5
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
            Wait-WithJitter -BaseSeconds 2 -MaxSeconds 5
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
        if ($PatchType -eq 'DotNet' -and $DotNetVersion) {
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
    $supersedes  = New-Object System.Collections.Generic.List[string]
    $supersededBy = New-Object System.Collections.Generic.List[string]
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
                    Supersedes   = @()
                    SupersededBy = @()
                    Error        = $_.Exception.Message
                }
            }
            Wait-WithJitter -BaseSeconds 2 -MaxSeconds 5
        }
    }
    $kbPattern = 'KB\d{6,7}'
    # Section pattern: <div id="supersededbyInfo" ...> ... </div>
    $reSupBy = '(?is)id\s*=\s*["'']supersededbyInfo["''][^>]*>(.*?)</div>'
    $reSup   = '(?is)id\s*=\s*["'']supersedesInfo["''][^>]*>(.*?)</div>'
    $mBy = [regex]::Match($resp.Content, $reSupBy)
    if ($mBy.Success) {
        foreach ($kb in [regex]::Matches($mBy.Groups[1].Value, $kbPattern)) {
            if (-not $supersededBy.Contains($kb.Value)) { $supersededBy.Add($kb.Value) | Out-Null }
        }
    }
    $mSup = [regex]::Match($resp.Content, $reSup)
    if ($mSup.Success) {
        foreach ($kb in [regex]::Matches($mSup.Groups[1].Value, $kbPattern)) {
            if (-not $supersedes.Contains($kb.Value)) { $supersedes.Add($kb.Value) | Out-Null }
        }
    }
    return [pscustomobject][ordered]@{
        Supersedes   = $supersedes.ToArray()
        SupersededBy = $supersededBy.ToArray()
        Error        = $null
    }
}

function Resolve-PatchSetFromCatalog {
    <#
    .SYNOPSIS
        Orchestrator: for a given OS / month / language, look up the
        canonical patch set (SSU + LCU + DynUp Setup + DynUp Component
        + DynUp SafeOs + .NET) in Microsoft Update Catalog and return
        a list of fully-populated PatchBaseline entries.
    .DESCRIPTION
        Implements the "Option X" (r02.5) corrections:

          1. OS-version-aware query templates from Get-CatalogQueryTemplate.
             Each OS uses its own canonical Title / Product / Description
             pattern as documented in Microsoft media-dynamic-update.
             Server 2022 in particular uses a comma form
             ("...server operating system, version 21H2") and requires
             a Product / Description filter to disambiguate from other
             OS versions.

          2. Combined LCU detection. Since Microsoft now embeds SSU into
             LCU and only publishes standalone SSU "in rare cases of a
             breaking change", an empty SSU search result plus a
             non-empty LCU result is treated as a combined month
             (warn + continue) rather than an error.

          3. Per-update file selection via Select-CanonicalPatchFile,
             which rejects Express / Delta / PSF differential packages
             that previously could be silently picked by the naive
             "$links[0]" heuristic.

        Returns an array of fully-populated PatchBaseline entries with
        an additional IsCombined flag on the LCU when applicable.
    #>
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string]$OsVersion,
        [Parameter(Mandatory)] [string]$OsLanguage,
        [Parameter(Mandatory)] [string]$PatchMonth,
        [int]$MaxRetries = 3
    )

    Write-Step ('Resolving patch set: OS={0} Lang={1} Month={2}' -f $OsVersion, $OsLanguage, $PatchMonth)

    # Load OS-specific query template (precise Title patterns from MS Learn)
    $tmpl = Get-CatalogQueryTemplate -OsVersion $OsVersion -PatchMonth $PatchMonth
    $osTitleTokens = $tmpl.TitleTokens

    # ----- PASS 1: per-type Catalogue search -----
    $searchResults = @{}     # Type -> @{ Best=<title-narrowed best>; RawCount=<total hits> }
    foreach ($q in $tmpl.Queries) {
        Write-Step ('Catalog query: type={0} template="{1}"' -f $q.Type, $q.QueryTemplate)
        $hits = $null
        try {
            $hits = Get-UpdateIdFromCatalog -KbId $q.QueryTemplate -MaxRetries $MaxRetries
        } catch {
            Write-Warn ('Catalogue search failed for {0}: {1}' -f $q.Type, $_.Exception.Message)
            $searchResults[$q.Type] = @{ Best=$null; RawCount=0 }
            continue
        }
        if (-not $hits -or $hits.Count -eq 0) {
            $searchResults[$q.Type] = @{ Best=$null; RawCount=0 }
            continue
        }
        # Narrow by OS Title token + x64 architecture
        $narrowed = @($hits | Where-Object {
            $title = $_.Title
            $hit = $false
            foreach ($t in $osTitleTokens) {
                if ($title -match [regex]::Escape($t)) { $hit = $true; break }
            }
            $hit -and ($title -match 'x64')
        })
        if ($narrowed.Count -eq 0) {
            $searchResults[$q.Type] = @{ Best=$null; RawCount=$hits.Count }
            continue
        }
        # Prefer non-Preview entries when multiple narrowed candidates exist
        $sorted = @($narrowed | Sort-Object @{
            Expression = { if ($_.Title -match '(?i)preview') { 1 } else { 0 } }
        }, Title)
        $searchResults[$q.Type] = @{ Best=$sorted[0]; RawCount=$hits.Count }
    }

    # ----- Combined LCU detection -----
    $hasSsu = ($null -ne $searchResults['SSU'].Best)
    $hasLcu = ($null -ne $searchResults['LCU'].Best)
    $isCombinedMonth = (-not $hasSsu) -and $hasLcu
    $lcuTitleSaysCombined = $false
    if ($hasLcu) {
        $lcuTitleSaysCombined = Test-IsCombinedLcuTitle -LcuTitle $searchResults['LCU'].Best.Title
    }
    if ($isCombinedMonth) {
        Write-Warn ('Combined LCU month detected: no standalone SSU for ' + $PatchMonth + '; LCU is assumed to embed the SSU (Microsoft media-dynamic-update guidance).')
    } elseif ($lcuTitleSaysCombined) {
        Write-Step 'LCU title explicitly identifies itself as a combined SSU+LCU package.'
    }

    # ----- PASS 2: resolve download link per surviving search result -----
    $resolved = New-Object System.Collections.Generic.List[object]
    foreach ($q in $tmpl.Queries) {
        $sr = $searchResults[$q.Type]
        if (-not $sr -or -not $sr.Best) {
            if ($q.Type -eq 'SSU' -and $isCombinedMonth) {
                # Expected absence in combined months: no warning
                continue
            }
            if ($q.Type -eq 'SSU') {
                Write-Warn ('Catalogue: no SSU found for ' + $PatchMonth + ' (could be a combined LCU month or a query mismatch).')
            } else {
                Write-Warn ('Catalogue: no narrowed result for {0} / {1}.' -f $q.Type, $OsVersion)
            }
            continue
        }
        $best = $sr.Best
        # Pull the file list from DownloadDialog.aspx
        $links = $null
        try {
            $links = Get-DownloadLinkFromCatalog -UpdateId $best.UpdateId -MaxRetries $MaxRetries
        } catch {
            Write-Warn ('DownloadDialog failed for {0} (UpdateId {1}): {2}' -f $q.Type, $best.UpdateId, $_.Exception.Message)
            continue
        }
        if (-not $links -or $links.Count -eq 0) {
            Write-Warn ('No download link returned for {0} UpdateId {1}.' -f $q.Type, $best.UpdateId)
            continue
        }
        # Pick the canonical (full standalone) file
        $primary = Select-CanonicalPatchFile -Links $links -PatchType $q.Type -Architecture 'x64'
        if (-not $primary) {
            $names = ($links | ForEach-Object { $_.FileName }) -join ', '
            Write-Warn ('No canonical full file for {0} UpdateId {1} (only Express/Delta/PSF available?). Files were: {2}' -f $q.Type, $best.UpdateId, $names)
            continue
        }
        if ($links.Count -gt 1) {
            Write-Step ('  {0}: {1} candidate files; chose {2}' -f $q.Type, $links.Count, $primary.FileName)
        }
        # Supersedence (best-effort)
        $supers = Get-SupersedenceFromCatalog -UpdateId $best.UpdateId -MaxRetries $MaxRetries
        $kbFromTitle = ''
        $kbMatch = [regex]::Match($best.Title, '\((KB\d{6,7})\)')
        if ($kbMatch.Success) { $kbFromTitle = $kbMatch.Groups[1].Value }

        $entry = Convert-CatalogPatchToBaselineEntry `
            -KbId $kbFromTitle `
            -Title $best.Title `
            -UpdateId $best.UpdateId `
            -DownloadUrl $primary.Url `
            -FileName $primary.FileName `
            -Sha256 '' `
            -Supersedes ($supers.Supersedes) `
            -ApplicableArchitecture 'x64' `
            -ApplicableLanguages @('neutral')

        # Annotate IsCombined / Variant fields
        if ($q.Type -eq 'LCU') {
            $combinedFlag = $isCombinedMonth -or $lcuTitleSaysCombined
            $entry | Add-Member -NotePropertyName 'IsCombined' -NotePropertyValue ([bool]$combinedFlag) -Force
        } else {
            $entry | Add-Member -NotePropertyName 'IsCombined' -NotePropertyValue $false -Force
        }
        $entry | Add-Member -NotePropertyName 'Variant' -NotePropertyValue 'Full' -Force

        $resolved.Add($entry) | Out-Null
    }

    # ----- LCU RequiresKbIds dependency annotation -----
    # If we have a standalone SSU AND an LCU, link them. If combined month
    # or combined-title month, leave LCU.RequiresKbIds empty because the
    # SSU is internal to the LCU package.
    $ssuKbs = @($resolved | Where-Object { $_.Type -eq 'SSU' } | ForEach-Object { $_.KbId })
    foreach ($p in $resolved) {
        if ($p.Type -eq 'LCU' -and $ssuKbs.Count -gt 0 -and -not $p.IsCombined) {
            $p.RequiresKbIds = $ssuKbs
        }
    }

    if ($resolved.Count -eq 0) {
        Write-Warn 'Resolve-PatchSetFromCatalog: zero patches resolved.'
    } else {
        Write-Ok ('Resolved {0} patch entries from Catalogue.' -f $resolved.Count)
    }
    return $resolved.ToArray()
}

# ============================================================
# Language-specific patch scraper
# ============================================================
# Locates per-language artifacts (Language Pack, LXP, .NET LP)
# in the Microsoft Update Catalogue. Returns an array of patch
# entries with shape compatible with PatchBaseline.NeutralPatches
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
        'Server2022' = @('Microsoft server operating system, version 21H2', 'Windows Server 2022')
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
            Write-Warn ('  Catalogue search failed: {0}' -f $_.Exception.Message)
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
        target path, creates the directory if missing, and surfaces
        the original DISM error untouched.
    .DESCRIPTION
        DISM frequently leaves orphan mounts behind on abnormal exits.
        Before mounting, we run Get-WindowsImage -Mounted and discard
        any entry pointing at our target path with -Discard. This is
        the OSDBuilder pattern documented in SPEC Part D.1.
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
        $existing = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
        foreach ($m in @($existing)) {
            if ($m.Path -and (($m.Path.TrimEnd('\')) -ieq ($Path.TrimEnd('\')))) {
                Write-Warn ('Stale mount detected at {0}; discarding before remount.' -f $Path)
                Dismount-WindowsImage -Path $Path -Discard -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {
        # Get-WindowsImage may not be available on every host; safe to ignore
        $null = $_
    }

    Set-DebugStep -Step ('wim-mount-image-idx{0}' -f $Index)
    $mountArgs = @{
        ImagePath = $ImagePath
        Index     = $Index
        Path      = $Path
    }
    if ($LogDir) {
        $logPath = Join-Path $LogDir (('mount_idx{0}_{1:yyyyMMdd-HHmmss}.log' -f $Index, (Get-Date)))
        $mountArgs['LogPath'] = $logPath
    }
    Mount-WindowsImage @mountArgs | Out-Null
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

    Set-DebugStep -Step 'wim-dismount-first-try'
    try {
        if ($Discard) {
            Dismount-WindowsImage -Path $Path -Discard @extra -ErrorAction SilentlyContinue | Out-Null
        } else {
            Dismount-WindowsImage -Path $Path -Save -CheckIntegrity @extra -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        Write-Warn ('First Dismount failed: {0}; waiting 30s and retrying...' -f $_.Exception.Message)
    }

    # Verify the mount is gone; if still present, retry the harder way
    $stillMounted = $false
    try {
        $cur = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
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
            Dismount-WindowsImage -Path $Path -Discard @extra | Out-Null
        } else {
            Dismount-WindowsImage -Path $Path -Save -CheckIntegrity @extra | Out-Null
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
    Set-DebugStep -Step ('add-pkg-' + (Split-Path -LiteralPath $PackagePath -Leaf))

    $logArg = @{}
    if ($LogDir) {
        $logArg['LogPath'] = Join-Path $LogDir (('addpkg_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)))
    }

    try {
        Add-WindowsPackage -Path $MountPath -PackagePath $PackagePath @logArg -ErrorAction Stop | Out-Null
        return 'Ok'
    } catch {
        $m = [string]$_.Exception.Message
        if ($m -match '0x800f081e') {
            Write-Warn ('0x800f081e: Package not applicable, skipping: {0}' -f (Split-Path -LiteralPath $PackagePath -Leaf))
            return 'NotApplicable'
        }
        if ($m -match '0x800f0a13') {
            Write-Warn ('0x800f0a13: Modules Installer transient error; retrying after 10s...')
            Start-Sleep -Seconds 10
            Add-WindowsPackage -Path $MountPath -PackagePath $PackagePath @logArg -ErrorAction Stop | Out-Null
            return 'OkAfterRetry'
        }
        # All other errors propagate (0x800f0922, 0xC1420127, etc.)
        throw
    }
}

function Invoke-DismCleanup {
    <#
    .SYNOPSIS
        Invoke "dism.exe /Image:<path> /Cleanup-Image
        /StartComponentCleanup /ResetBase" against a mounted image.
    .DESCRIPTION
        Cleanup is run once per image, AFTER all packages for that
        image have been applied. /ResetBase locks out roll-back of
        previously applied updates and shrinks the WIM substantially.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$MountPath)
    Set-DebugStep -Step 'dism-cleanup-image'
    $dismArgs = @('/Image:' + $MountPath, '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase')
    & dism.exe @dismArgs
    if ($LASTEXITCODE -ne 0) {
        throw ('dism.exe /Cleanup-Image failed with exit code {0}' -f $LASTEXITCODE)
    }
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
    $entries = Get-WindowsImage -ImagePath $WimPath
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
        documented in SPEC Part B.5 P07.
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
        documented in SPEC Part B.5 P07.
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

function Resolve-OscdimgExe {
    <#
    .SYNOPSIS
        Locate oscdimg.exe under the ADK Deployment Tools.
    #>
    $candidates = @(
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    # Try PATH lookup
    $cmd = Get-Command -Name 'oscdimg.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'oscdimg.exe not found. Install the Windows ADK Deployment Tools.'
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
    & dism.exe /Capture-Image ('/ImageFile:' + $installWim) ('/CaptureDir:' + $synthSrc) /Name:Synthetic_For_CI /Compress:none
    if ($LASTEXITCODE -ne 0) {
        throw ('dism /Capture-Image failed with exit code {0}' -f $LASTEXITCODE)
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
            Write-Warn ('oscdimg failed on synthetic stub: {0}; falling back to raw copy.' -f $_.Exception.Message)
            Copy-Item -LiteralPath $installWim -Destination $OutputIsoPath -Force
        }
    } else {
        # ADK missing - copy the WIM as if it were the ISO. P08 verification
        # in -SyntheticTestMode tolerates this fallback shape.
        Copy-Item -LiteralPath $installWim -Destination $OutputIsoPath -Force
    }

    return $OutputIsoPath
}


# ============================================================
# ISO Updater specific: wsusscn2.cab + Windows Update Agent API
# offline scan
# ============================================================
#
# These helpers let P04.5 ValidatePatchSet ask Microsoft's own Update
# Agent (the same component Windows Update uses) whether the supplied
# patch set is sufficient for the target install.wim image. This is the
# only authoritative way to know "LCU X requires SSU Y" because the
# dependency metadata is embedded in the wsusscn2 catalog, not exposed
# via any documented Microsoft API.
#
# References:
#   - https://learn.microsoft.com/windows/win32/wua_sdk/using-the-windows-update-agent-api
#   - https://learn.microsoft.com/windows/deployment/update/catalog-checkpoint-cumulative-updates
#   - PoC scripts published by Kazuro Yamauchi (say-tech.co.jp, 2025memo54)

function Get-WsusScnCabSourceUrl {
    <#
    .SYNOPSIS
        Return the canonical wsusscn2.cab download URL (the one
        Microsoft has used since 2003 for the offline scan tool).
    #>
    [OutputType([string])]
    param()
    return 'https://catalog.s.download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab'
}

function Test-WsusScnCabFresh {
    <#
    .SYNOPSIS
        Decide whether the local wsusscn2.cab is fresh enough to reuse,
        or must be re-downloaded.
    .DESCRIPTION
        Per the contract:
          (a) If LocalCachePath is empty / non-existent: stale (download)
          (b) If LastDownloadedDate is empty: stale (download)
          (c) If now >= latest Patch Tuesday AND
              LastDownloadedDate < latest Patch Tuesday: stale (download)
          (d) Otherwise: fresh (reuse)
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $WsusScnCabMeta,
        [Parameter(Mandatory)] [datetime]$LatestPatchTuesday
    )
    if (-not $WsusScnCabMeta) { return $false }
    $path = $WsusScnCabMeta.LocalCachePath
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $lastStr = $WsusScnCabMeta.LastDownloadedDate
    if ([string]::IsNullOrWhiteSpace($lastStr)) { return $false }
    $lastDate = $null
    if (-not [datetime]::TryParse($lastStr, [ref]$lastDate)) { return $false }
    # Require: last download is on/after the latest Patch Tuesday
    if ($lastDate.Date -lt $LatestPatchTuesday.Date) { return $false }
    return $true
}

function Get-WsusScnCabIfNeeded {
    <#
    .SYNOPSIS
        Conditionally download wsusscn2.cab to a cache directory.
    .DESCRIPTION
        Behaviour:
          1. If -OverridePath is supplied AND the file exists, use that.
          2. Else compute LocalCachePath = <WorkRoot>/cache/wsusscn2.cab
          3. If Test-WsusScnCabFresh returns $true, reuse.
          4. Else download from $SourceUrl with retries.
        Returns a hashtable: @{ Path; SizeBytes; Sha256; DownloadedNow }
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $WsusScnCabMeta,
        [Parameter(Mandatory)] [string]$WorkRoot,
        [Parameter(Mandatory)] [datetime]$LatestPatchTuesday,
        [string]$OverridePath
    )

    # (1) Caller-supplied override (`-WsusScnCabPath`)
    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        if (Test-Path -LiteralPath $OverridePath) {
            $fi = Get-Item -LiteralPath $OverridePath
            return @{
                Path          = $OverridePath
                SizeBytes     = $fi.Length
                Sha256        = ''
                DownloadedNow = $false
                Source        = 'OverridePath'
            }
        }
        Write-Warn ('-WsusScnCabPath was supplied but does not exist: ' + $OverridePath)
    }

    # (2) Default cache location
    $cacheDir  = Join-Path $WorkRoot 'cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $cachePath = Join-Path $cacheDir 'wsusscn2.cab'

    # Construct a meta object reflecting the actual cache location for
    # the freshness check (it may be empty in Config on first run)
    $meta = $WsusScnCabMeta
    if ($meta -and -not $meta.LocalCachePath) {
        $meta = $meta | Select-Object *
        $meta.LocalCachePath = $cachePath
    }

    if (Test-WsusScnCabFresh -WsusScnCabMeta $meta -LatestPatchTuesday $LatestPatchTuesday) {
        $fi = Get-Item -LiteralPath $cachePath
        Write-Step ('wsusscn2.cab cache fresh; reusing: {0} ({1:N0} bytes)' -f $cachePath, $fi.Length)
        return @{
            Path          = $cachePath
            SizeBytes     = $fi.Length
            Sha256        = $meta.LastDownloadedSha256
            DownloadedNow = $false
            Source        = 'Cache'
        }
    }

    # (3) Download
    $url = Get-WsusScnCabSourceUrl
    if ($WsusScnCabMeta -and $WsusScnCabMeta.SourceUrl) {
        $url = $WsusScnCabMeta.SourceUrl
    }
    Write-Step ('Downloading wsusscn2.cab from {0} ...' -f $url)
    $tmp = $cachePath + '.' + ([guid]::NewGuid().ToString('N')) + '.part'
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (compatible; UpdateWsi/r02)' }
    try {
        Invoke-WebRequestWithRetry -Uri $url -OutFile $tmp -Headers $headers -MaxRetries 3 | Out-Null
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        throw ('wsusscn2.cab download failed: ' + $_.Exception.Message)
    }
    # Atomic move
    if (Test-Path -LiteralPath $cachePath) { Remove-Item -LiteralPath $cachePath -Force }
    Move-Item -LiteralPath $tmp -Destination $cachePath -Force
    $fi  = Get-Item -LiteralPath $cachePath
    $sha = (Get-FileHash -LiteralPath $cachePath -Algorithm SHA256).Hash.ToLower()
    Write-Ok ('wsusscn2.cab downloaded: {0:N0} bytes, sha256={1}' -f $fi.Length, $sha.Substring(0, 16) + '...')
    return @{
        Path          = $cachePath
        SizeBytes     = $fi.Length
        Sha256        = $sha
        DownloadedNow = $true
        Source        = 'Download'
    }
}

function Invoke-WuaOfflineScan {
    <#
    .SYNOPSIS
        Run a Windows Update Agent COM API offline scan against an
        install.wim image that is currently mounted at $MountPath.
    .DESCRIPTION
        Uses Microsoft.Update.Session + Microsoft.Update.ServiceManager
        to register the supplied wsusscn2.cab as an offline scan source.
        Then runs $UpdateSearcher.Search("IsInstalled=0 ...") to obtain
        the set of updates that the WUA engine judges as APPLICABLE-
        BUT-NOT-INSTALLED for the current host's OS image.

        IMPORTANT: WUA scans the LOCAL host's OS image, not the mounted
        WIM directly. The caller must therefore run this function FROM
        a Windows host whose OS family matches the install.wim target
        (i.e. Server 2025 host to scan a Server 2025 image). When such
        a host is not available, P04.5 will skip with a warning rather
        than fail.

        Returns: array of [pscustomobject] with UpdateId / Title /
        KbIds / SupersededBy / IsMandatory / Severity / SizeBytes
    #>
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string]$WsusScnCabPath
    )
    if (-not (Test-Path -LiteralPath $WsusScnCabPath)) {
        throw ('wsusscn2.cab not found at ' + $WsusScnCabPath)
    }
    Write-Step 'Creating WUA session for offline scan...'
    $session = $null
    $serviceMgr = $null
    $service = $null
    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session'
        $serviceMgr = New-Object -ComObject 'Microsoft.Update.ServiceManager'
        $service = $serviceMgr.AddScanPackageService('UpdateWsi Offline Sync', $WsusScnCabPath)
    } catch {
        throw ('Failed to register wsusscn2.cab with WUA: ' + $_.Exception.Message)
    }
    $searcher = $session.CreateUpdateSearcher()
    $searcher.ServerSelection = 3 # ssOthers
    $searcher.ServiceID = [string]$service.ServiceID
    Write-Step 'Running WUA search (IsInstalled=0 and Type=Software and IsHidden=0)...'
    $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
    $items = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $u = $result.Updates.Item($i)
        $kbList = New-Object System.Collections.Generic.List[string]
        if ($u.KBArticleIDs) {
            for ($k = 0; $k -lt $u.KBArticleIDs.Count; $k++) {
                $kbList.Add('KB' + $u.KBArticleIDs.Item($k)) | Out-Null
            }
        }
        $sevStr = ''
        try { $sevStr = [string]$u.MsrcSeverity } catch { $sevStr = '' }
        $sizeBytes = 0L
        try { $sizeBytes = [long]$u.MaxDownloadSize } catch { $sizeBytes = 0L }
        $items.Add([pscustomobject][ordered]@{
            UpdateId    = [string]$u.Identity.UpdateID
            Title       = [string]$u.Title
            KbIds       = $kbList.ToArray()
            IsMandatory = [bool]$u.IsMandatory
            Severity    = $sevStr
            SizeBytes   = $sizeBytes
            SupportUrl  = [string]$u.SupportUrl
        }) | Out-Null
    }
    Write-Ok ('WUA scan returned {0} applicable update(s).' -f $items.Count)
    return $items.ToArray()
}

function Compare-PatchSetVsWuaScan {
    <#
    .SYNOPSIS
        Compare the provided PatchBaseline.Patches (or local patch dir)
        against the WUA scan result and classify each WUA-required
        update as Provided / Missing.
    .DESCRIPTION
        Matches by KB number. Excludes Checkpoint Cumulative Updates
        (PatchBaseline.ExcludeKbList) and any patches the user opted
        out of via -OnlyInstallWimIndexes etc.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject[]]$ProvidedPatches,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$WuaRequired,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$ExcludeKbList
    )
    $providedKbSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $ProvidedPatches) {
        if ($p.KbId) { [void]$providedKbSet.Add($p.KbId.ToUpper()) }
    }
    $excludeSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($e in $ExcludeKbList) {
        if ($e -and $e.KbId) { [void]$excludeSet.Add($e.KbId.ToUpper()) }
    }

    $missing = New-Object System.Collections.Generic.List[object]
    $supplied = New-Object System.Collections.Generic.List[object]

    foreach ($w in $WuaRequired) {
        $wKbs = @($w.KbIds | ForEach-Object { $_.ToUpper() })
        $isExcluded = $false
        foreach ($k in $wKbs) {
            if ($excludeSet.Contains($k)) { $isExcluded = $true; break }
        }
        if ($isExcluded) { continue }
        $isProvided = $false
        foreach ($k in $wKbs) {
            if ($providedKbSet.Contains($k)) { $isProvided = $true; break }
        }
        if ($isProvided) {
            $supplied.Add($w) | Out-Null
        } else {
            $missing.Add($w) | Out-Null
        }
    }
    return [pscustomobject][ordered]@{
        Provided      = $supplied.ToArray()
        Missing       = $missing.ToArray()
        ExcludedCount = $excludeSet.Count
    }
}

# ============================================================
# PatchPlan engine
# ============================================================
# Converts a flat list of resolved patches into a target-aware
# PatchPlan that the build phases (P05 install.wim, P06 boot.wim
# / WinRE.wim) consume. Implements Microsoft's media-dynamic-update
# servicing sequence: each WIM target receives only the patches
# whose Type maps to that target via $Script:PatchTargetMap, and
# within each target the patches are sorted by ApplyOrder.
#
# Out of scope for this initial cut (tracked in CHANGELOG and SPEC):
#   * LCU twice-apply pattern around LP injection
#   * WinRE.wim mount/service/dismount worker
#   * Language Pack injection in P05
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
        Write-Warn ("Unknown patch Type '{0}'; defaulting target=[Install]. Add this Type to PatchTargetMap to silence." -f $PatchType)
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
        $type = if ($p.PSObject.Properties['Type']) { [string]$p.Type } else { '' }
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
    return $plan
}

function Write-PatchPlanSummary {
    <#
    .SYNOPSIS
        Emit a human-readable summary of a PatchPlan to the standard
        Write-Step log surface.
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
                $ty = if ($_.Type) { $_.Type } else { '?' }
                "{0}/{1}" -f $ty, $kb
            }) -join ', '
            Write-Step ('  {0,-7} ({1}): {2}' -f $t, $count, $names)
        } else {
            Write-Step ('  {0,-7} (0): (empty)' -f $t)
        }
    }
    if ($Plan._UnknownTypes -and $Plan._UnknownTypes.Count -gt 0) {
        Write-Warn ('Unknown Types in plan (defaulted to Install): {0}' -f ($Plan._UnknownTypes -join ', '))
    }
}

function Test-PatchDependencyClosureOnMount {
    <#
    .SYNOPSIS
        Pre-apply dependency closure check (A-3).
    .DESCRIPTION
        For every patch in $PatchesToApply whose RequiresKbIds is
        non-empty, verify via Get-WindowsPackage that each required KB
        is already present in the mounted image's package store. The
        check runs in declaration order; a patch P's prerequisites
        must be satisfied BEFORE P is added to the image.

        Policy is governed by $Script:PatchDependencyPolicy:
          'Strict' -> throw on any missing prerequisite (default)
          'Warn'   -> Write-Warn and continue

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
        $installedPackages = @(Get-WindowsPackage -Path $MountPath -ErrorAction Stop)
    } catch {
        $msg = ('Get-WindowsPackage failed on {0}: {1}' -f $MountPath, $_.Exception.Message)
        if ($Script:PatchDependencyPolicy -eq 'Strict') {
            throw $msg
        } else {
            Write-Warn $msg
            return $false
        }
    }
    $installedIds = @($installedPackages | ForEach-Object { [string]$_.PackageIdentity })

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($reqKb in $prereqMap.Keys) {
        $found = $false
        foreach ($pid in $installedIds) {
            if ($pid -like ("*{0}*" -f $reqKb)) {
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
    Write-Warn ('Dependency closure ({0}): {1} unsatisfied prerequisite(s); continuing (policy=Warn).' -f $ImageLabel, $missing.Count)
    Write-Warn $detail
    return $false
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
                Write-Warn ('Not Administrator, but -Action {0} is read-only; continuing.' -f $Action)
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
                Write-Warn ('oscdimg.exe not found, but -Action {0} does not need it; continuing.' -f $Action)
            } elseif ($Script:SyntheticTestMode) {
                Write-Warn 'oscdimg.exe not found; -SyntheticTestMode will use a raw-copy fallback.'
            } else {
                throw 'oscdimg.exe not found. Install the Windows ADK Deployment Tools.'
            }
        }
        $gwi = Get-Command -Name 'Get-WindowsImage' -ErrorAction SilentlyContinue
        if ($gwi) {
            Write-Ok 'Get-WindowsImage cmdlet available (Dism module loaded).'
        } else {
            throw 'Get-WindowsImage cmdlet not available. The Dism PowerShell module is required.'
        }

        # Step 4: Disk space
        Set-DebugStep -Step 'disk-space-check'
        Write-SubSection 'Step 4: Disk space'
        $rootDrive = $Script:WorkRoot.Substring(0, 2).TrimEnd(':')
        $psDrive = Get-PSDrive -Name $rootDrive -ErrorAction SilentlyContinue
        if ($psDrive) {
            $freeGB = [Math]::Round($psDrive.Free / 1GB, 1)
            Write-Step ('Free space on {0}: {1} GB' -f $rootDrive, $freeGB)
            if ($freeGB -lt 30 -and -not $Script:DryRun -and -not $Script:EnvironmentInfoOnly -and -not $Script:SkipEnvCheck) {
                throw ('Insufficient free space on {0}: {1} GB free; 30 GB minimum required.' -f $rootDrive, $freeGB)
            }
            if ($freeGB -lt 60) {
                Write-Warn ('Tight free space on {0}: {1} GB free; 60 GB recommended for full builds.' -f $rootDrive, $freeGB)
            } else {
                Write-Ok ('Disk space OK ({0} GB free).' -f $freeGB)
            }
        } else {
            Write-Warn ('Could not get PSDrive for {0}: skipping disk space check.' -f $rootDrive)
        }

        # Step 5: Hyper-V (BootTest only)
        if ($Action -in @('BootTest','All')) {
            Set-DebugStep -Step 'hyperv-check'
            Write-SubSection 'Step 5: Hyper-V availability'
            try {
                $hv = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction Stop
                if ($hv.State -eq 'Enabled') {
                    Write-Ok 'Hyper-V is Enabled.'
                } else {
                    throw ('Hyper-V is not enabled (State={0}). Run "Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All".' -f $hv.State)
                }
            } catch {
                if ($Script:SyntheticTestMode) {
                    Write-Warn 'Hyper-V unavailable; allowed under -SyntheticTestMode.'
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
            Write-Step '-SyntheticTestMode is on; ISO will be generated in P03.'
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
                $sideCar = Join-Path $f.DirectoryName ((Split-Path -LiteralPath $f.FullName -LeafBase) + '.meta4')
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
                  ($Script:OsProfile.PatchBaseline -and $Script:OsProfile.PatchBaseline.Patches -and `
                   $Script:OsProfile.PatchBaseline.Patches.Count -gt 0)) {
            # PatchBaseline-driven path. The patch list is derived from
            # the in-memory $Script:OsProfile.PatchBaseline.Patches. P02.5
            # may refresh this list from the Microsoft Update Catalog if it
            # is stale or -AutoDetectLatestPatches was passed.
            $bl = $Script:OsProfile.PatchBaseline
            if ($bl -and $bl.Patches) {
                Write-Step ('Seeding ResolvedPatches from PatchBaseline: {0} entries.' -f $bl.Patches.Count)
                foreach ($p in $bl.Patches) {
                    $resolved.Add([pscustomobject]@{
                        Kind = 'Patch'; Source = $p.DownloadUrl
                        LocalPath = ''
                        KbId = $p.KbId
                        PatchType = $p.Type
                        ApplyOrder = $p.ApplyOrder
                        ExpectedHashes = @{ 'sha-256' = $p.Sha256 }
                    }) | Out-Null
                }
            } else {
                Write-Step 'PatchBaseline.Patches is empty; P02.5 will populate from Microsoft Update Catalog.'
            }
        } elseif ($Script:SyntheticTestMode) {
            Write-Step '-SyntheticTestMode is on; no real patches required.'
        } else {
            throw 'No patch source specified. Provide one of: -PatchUrls / -PatchDirectory / -ManifestPath / -AutoDetectLatestPatches, or populate Config PatchBaseline.Patches.'
        }

        # Order by ApplyOrder, then by KbId. Wrap in @() to guarantee
        # an array even when $resolved is null or a single object.
        $Script:ResolvedPatches = @($resolved | Sort-Object ApplyOrder, KbId)
        Write-Ok ('Patch list resolved: {0} entries.' -f $Script:ResolvedPatches.Count)

        # Build the WIM-target-aware PatchPlan and print summary.
        # Even when ResolvedPatches is empty (synthetic test mode), we
        # construct an empty plan so downstream Get-OrInitPatchPlan
        # calls in P05/P06 hit a populated cache.
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
# Phase P02.5: RefreshPatchBaseline
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

function Invoke-SetupPhase02_5_RefreshPatchBaseline {
    <#
    .OUTPUTS
        System.Boolean
    #>
    [OutputType([bool])]
    param()
    Start-DebugTrace -Context 'Invoke-SetupPhase02_5_RefreshPatchBaseline' -PhaseId 'P02.5'
    try {
        Set-DebugStep -Step 'check-skip-conditions'

        # ---- Skip conditions ----
        if ($Script:SyntheticTestMode) {
            Write-Skip 'P02.5 skipped: -SyntheticTestMode disables Catalog scraping.'
            return $true
        }
        if ($Script:SkipDynamicPatchRefresh) {
            Write-Skip 'P02.5 skipped: -SkipDynamicPatchRefresh explicitly set.'
            return $true
        }
        if ($Script:UseBaselineOnly) {
            Write-Skip 'P02.5 skipped: -UseBaselineOnly explicitly set.'
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
            Write-Skip ('P02.5 skipped: PatchBaseline is fresh (PatchTuesdayOfBaseline={0}).' -f $baseline.PatchTuesdayOfBaseline)
            return $true
        }
        if ($forced) {
            Write-Step 'P02.5: -AutoDetectLatestPatches set; forcing refresh.'
        } else {
            Write-Step 'P02.5: PatchBaseline is stale; refreshing from Catalog.'
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
            $newPatches = Resolve-PatchSetFromCatalog `
                            -OsVersion $Script:OsVersion `
                            -OsLanguage $Script:OsLanguage `
                            -PatchMonth $patchMonth `
                            -MaxRetries $retries
        } catch {
            $scrapeOk  = $false
            $scrapeErr = $_.Exception.Message
            Write-Warn ('Catalog scrape failed: ' + $scrapeErr)
        }
        if ($scrapeOk -and (-not $newPatches -or $newPatches.Count -eq 0)) {
            $scrapeOk  = $false
            $scrapeErr = 'Catalog scrape returned zero entries.'
            Write-Warn $scrapeErr
        }

        # ---- Failure handling ----
        if (-not $scrapeOk) {
            if ($fallback -eq 'Abort') {
                throw ('P02.5 RefreshPatchBaseline failed and AutoRefreshPolicy.FallbackOnScrapeFailure=Abort. Error: ' + $scrapeErr)
            }
            # UseBaseline (default)
            if (Test-PatchBaselineUsable -Baseline $baseline) {
                Write-Warn 'P02.5: scrape failed but existing PatchBaseline.Patches is usable; continuing.'
                return $true
            }
            throw ('P02.5 RefreshPatchBaseline failed AND existing PatchBaseline has no usable patches. Cannot proceed.')
        }

        # ---- Update in-memory profile ----
        Set-DebugStep -Step 'update-in-memory-profile'
        if (-not $Script:OsProfile.PatchBaseline) {
            $Script:OsProfile | Add-Member -NotePropertyName 'PatchBaseline' -NotePropertyValue ([pscustomobject][ordered]@{
                Schema = '1.0'
                TargetBuildAfterUpdate = ''
                PatchTuesdayOfBaseline = ''
                LastVerifiedDate = ''
                LastVerifiedBy = ''
                VerificationMethod = ''
                VerifiedOsLanguages = @($Script:OsLanguage)
                ChecksumAlgorithm = 'SHA256'
                Patches = @()
                ExcludeKbList = @()
                WsusScnCab = [pscustomobject][ordered]@{
                    SourceUrl = (Get-WsusScnCabSourceUrl)
                    LocalCachePath = ''
                    LastDownloadedDate = ''
                    LastDownloadedSha256 = ''
                    LastDownloadedSizeBytes = 0
                }
            }) -Force
        }
        $Script:OsProfile.PatchBaseline.Patches                = @($newPatches)
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
                Write-Warn ('Writeback to Config JSON failed (in-memory baseline is still updated): ' + $_.Exception.Message)
            }
        } else {
            Write-Step 'AutoRefreshPolicy.WritebackToConfig is false; not persisting changes.'
        }

        # ---- Re-derive $Script:ResolvedPatches from new baseline ----
        Set-DebugStep -Step 'derive-resolved-patches'
        # If the user did not provide an explicit patch source, use the
        # refreshed baseline as the source of truth for P03.
        $userProvidedPatches = ($Script:PatchUrls -and $Script:PatchUrls.Count -gt 0) `
                               -or ($Script:PatchDirectory -and (Test-Path -LiteralPath $Script:PatchDirectory)) `
                               -or ($Script:ManifestPath -and (Test-Path -LiteralPath $Script:ManifestPath))
        if (-not $userProvidedPatches) {
            $derived = New-Object System.Collections.Generic.List[object]
            foreach ($p in $newPatches) {
                $derived.Add([pscustomobject][ordered]@{
                    Kind            = 'Patch'
                    Source          = $p.DownloadUrl
                    LocalPath       = ''
                    KbId            = $p.KbId
                    PatchType       = $p.Type
                    ApplyOrder      = $p.ApplyOrder
                    ExpectedHashes  = @{ 'sha-256' = $p.Sha256 }
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
# Phase P03: Fetch assets (Fetch group)
# ============================================================

function Invoke-FetchPhase03_FetchAssets { # psa-disable-line PSA6003 -- "Assets" is a phase noun; renaming would break the registry-driven dispatcher
    <#
    .SYNOPSIS
        P03: Download the source ISO (if URL-based) and any patch files
        that don't exist locally yet. Honours -SyntheticTestMode.
    #>
    Start-DebugTrace -Context 'Invoke-FetchPhase03_FetchAssets' -PhaseId 'P03'
    try {
        # Synthetic mode: build a tiny synthetic ISO instead of downloading
        if ($Script:SyntheticTestMode) {
            Write-SubSection 'Step 1: Build synthetic ISO (no downloads)'
            Set-DebugStep -Step 'synthetic-iso-build'
            New-SyntheticTestIso -WorkRoot $Script:WorkRoot -OutputIsoPath $Script:IsoLocalPath | Out-Null
            Write-Ok ('Synthetic ISO created: {0}' -f $Script:IsoLocalPath)
            New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P03.ok') -Force | Out-Null
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
                    Write-Warn ('Existing ISO is suspiciously small ({0} bytes); re-downloading.' -f $existing)
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
            # Record the hash for first-time use; user can copy into Config/<OsKey>.json
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
            $leaf = Split-Path -LiteralPath $p.LocalPath -Leaf
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
                            Write-Warn ('  cached file failed integrity check ({0}); re-downloading.' -f $_.Exception.Message)
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

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P03.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P04: Expand source ISO (Plan group)
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
        # Robocopy is faster on large trees, but Copy-Item works without external tools
        Copy-Item -LiteralPath $src -Destination $DestRoot -Recurse -Force
    } finally {
        Set-DebugStep -Step 'dismount-iso'
        try {
            Dismount-DiskImage -ImagePath $IsoFile | Out-Null
        } catch {
            Write-Warn ('Dismount-DiskImage failed: {0}' -f $_.Exception.Message)
        }
    }
}

function Invoke-PlanPhase04_ExpandIso {
    <#
    .SYNOPSIS
        P04: Mount and extract the source ISO; enumerate install.wim
        and boot.wim indexes; emit P04_wim_inventory.csv.
    #>
    Start-DebugTrace -Context 'Invoke-PlanPhase04_ExpandIso' -PhaseId 'P04'
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
                Write-Warn 'No install.wim found; expected in -SyntheticTestMode with fallback shape.'
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

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P04.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}


# ============================================================
# Phase P04.5: ValidatePatchSet
# ============================================================
# After P04 has extracted install.wim, this phase verifies that the
# user-supplied patch set (or the one derived from PatchBaseline) is
# sufficient by running a Windows Update Agent (WUA) offline scan
# against wsusscn2.cab.
#
# Skip conditions:
#   - $Script:SyntheticTestMode  (no real Microsoft assets in play)
#   - $Script:UseBaselineOnly    (caller explicitly opted out of catalog)
#   - WUA scan cannot run from this host (non-Windows or COM blocked)
#
# Failure handling:
#   - Missing patches detected AND $IgnorePatchValidation = $false -> throw
#   - Missing patches detected AND $IgnorePatchValidation = $true  -> warn
#   - Diagnostic data (4 files) is ALWAYS exported on missing-detection,
#     regardless of $IgnorePatchValidation.

function Export-PatchValidationReport {
    <#
    .SYNOPSIS
        Emit the four diagnostic files (validation_summary.json,
        validation_detail.csv, wsusscn2_scan_raw.json, dependency_graph.json)
        documented in SPEC C.4.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$DiagRoot,
        [Parameter(Mandatory)] [pscustomobject]$Comparison,
        [Parameter(Mandatory)] [pscustomobject[]]$ProvidedPatches,
        [Parameter(Mandatory)] [pscustomobject[]]$WuaRaw,
        [Parameter(Mandatory)] [hashtable]$Target,
        [Parameter(Mandatory)] [hashtable]$WsusScnCabInfo,
        [string]$Status = 'Fail',
        [string]$Reason = 'MissingRequiredPatches'
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $dir = Join-Path $DiagRoot $ts
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # validation_summary.json
    $summary = [pscustomobject][ordered]@{
        ValidationTimestamp = (Get-Date).ToString('o')
        Target              = $Target
        WsusScnCab          = $WsusScnCabInfo
        Result              = [pscustomobject][ordered]@{
            Status               = $Status
            Reason               = $Reason
            ProvidedPatchCount   = $ProvidedPatches.Count
            MissingPatchCount    = $Comparison.Missing.Count
            SupersededPatchCount = 0
        }
        ProvidedPatches = $ProvidedPatches
        MissingPatches  = $Comparison.Missing
        SupersededPatches = @()
        Recommendation = @(
            'Run with -AutoDetectLatestPatches to refresh PatchBaseline from Microsoft Update Catalog.',
            'Or download the missing KBs from the Catalog manually and add to -PatchDirectory.'
        )
    }
    $summaryJson = $summary | ConvertTo-Json -Depth 32
    $summaryJson = $summaryJson -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText((Join-Path $dir 'validation_summary.json'), $summaryJson + "`n", [System.Text.Encoding]::UTF8)

    # validation_detail.csv
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($p in $ProvidedPatches) {
        $rows.Add([pscustomobject][ordered]@{
            Type        = $p.Type
            KbId        = $p.KbId
            UpdateId    = $p.UpdateId
            Title       = $p.Title
            Provided    = 'Yes'
            RequiredByWUA = 'No'
            Severity    = ''
            Supersedes  = ($p.Supersedes -join ';')
            RequiresKbIds = ($p.RequiresKbIds -join ';')
            ApplyOrder  = $p.ApplyOrder
            DownloadHint = $p.DownloadUrl
        }) | Out-Null
    }
    foreach ($m in $Comparison.Missing) {
        $kbDisp = ($m.KbIds -join ';')
        $rows.Add([pscustomobject][ordered]@{
            Type        = ''
            KbId        = $kbDisp
            UpdateId    = $m.UpdateId
            Title       = $m.Title
            Provided    = 'No'
            RequiredByWUA = 'Yes'
            Severity    = $m.Severity
            Supersedes  = ''
            RequiresKbIds = ''
            ApplyOrder  = ''
            DownloadHint = 'https://catalog.update.microsoft.com/Search.aspx?q=' + $kbDisp
        }) | Out-Null
    }
    $csvPath = Join-Path $dir 'validation_detail.csv'
    $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    # wsusscn2_scan_raw.json
    $rawJson = $WuaRaw | ConvertTo-Json -Depth 32
    $rawJson = $rawJson -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText((Join-Path $dir 'wsusscn2_scan_raw.json'), $rawJson + "`n", [System.Text.Encoding]::UTF8)

    # dependency_graph.json (simple adjacency from PatchBaseline)
    $nodes = New-Object System.Collections.Generic.List[object]
    $edges = New-Object System.Collections.Generic.List[object]
    foreach ($p in $ProvidedPatches) {
        $nodes.Add([pscustomobject][ordered]@{
            Id    = $p.KbId
            Title = $p.Title
            Type  = $p.Type
            Provided = $true
        }) | Out-Null
        foreach ($req in $p.RequiresKbIds) {
            $edges.Add([pscustomobject][ordered]@{
                From = $p.KbId; To = $req; Kind = 'Requires'
            }) | Out-Null
        }
        foreach ($sup in $p.Supersedes) {
            $edges.Add([pscustomobject][ordered]@{
                From = $p.KbId; To = $sup; Kind = 'Supersedes'
            }) | Out-Null
        }
    }
    foreach ($m in $Comparison.Missing) {
        foreach ($k in $m.KbIds) {
            $nodes.Add([pscustomobject][ordered]@{
                Id = $k; Title = $m.Title; Type = ''; Provided = $false
            }) | Out-Null
        }
    }
    $graph = [pscustomobject][ordered]@{
        Nodes = $nodes.ToArray()
        Edges = $edges.ToArray()
    }
    $graphJson = $graph | ConvertTo-Json -Depth 32
    $graphJson = $graphJson -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText((Join-Path $dir 'dependency_graph.json'), $graphJson + "`n", [System.Text.Encoding]::UTF8)
    return $dir
}

function Invoke-PlanPhase04_5_ValidatePatchSet {
    <#
    .OUTPUTS
        System.Boolean
    #>
    [OutputType([bool])]
    param()
    Start-DebugTrace -Context 'Invoke-PlanPhase04_5_ValidatePatchSet' -PhaseId 'P04.5'
    try {
        Set-DebugStep -Step 'check-skip-conditions'

        # ---- Skip conditions ----
        if ($Script:SyntheticTestMode) {
            Write-Skip 'P04.5 skipped: -SyntheticTestMode disables wsusscn2 validation.'
            return $true
        }
        if ($Script:UseBaselineOnly) {
            Write-Skip 'P04.5 skipped: -UseBaselineOnly explicitly set.'
            return $true
        }
        # Only run on Windows (COM API unavailable elsewhere)
        $isWin = $false
        try { $isWin = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows) }
        catch { $isWin = ($env:OS -eq 'Windows_NT') }
        if (-not $isWin) {
            Write-Skip 'P04.5 skipped: non-Windows host; WUA COM API unavailable.'
            return $true
        }

        Set-DebugStep -Step 'compute-latest-patch-tuesday'
        $latestPT = Get-LatestPatchTuesday

        # ---- Resolve wsusscn2.cab ----
        Set-DebugStep -Step 'resolve-wsusscn2-cab'
        $wsusMeta = $null
        if ($Script:OsProfile -and $Script:OsProfile.PatchBaseline) {
            $wsusMeta = $Script:OsProfile.PatchBaseline.WsusScnCab
        }
        $wsusInfo = $null
        try {
            $wsusInfo = Get-WsusScnCabIfNeeded `
                            -WsusScnCabMeta $wsusMeta `
                            -WorkRoot $Script:WorkRoot `
                            -LatestPatchTuesday $latestPT `
                            -OverridePath $Script:WsusScnCabPath
        } catch {
            $msg = 'P04.5 could not obtain wsusscn2.cab: ' + $_.Exception.Message
            if ($Script:IgnorePatchValidation) {
                Write-Warn ($msg + ' (-IgnorePatchValidation set; continuing)')
                return $true
            }
            throw $msg
        }

        # ---- Persist wsusscn2.cab metadata to Config (if newly downloaded) ----
        if ($wsusInfo.DownloadedNow -and $Script:OsProfile.PatchBaseline) {
            $Script:OsProfile.PatchBaseline.WsusScnCab.LocalCachePath          = $wsusInfo.Path
            $Script:OsProfile.PatchBaseline.WsusScnCab.LastDownloadedDate      = (Get-Date).ToString('o')
            $Script:OsProfile.PatchBaseline.WsusScnCab.LastDownloadedSha256    = $wsusInfo.Sha256
            $Script:OsProfile.PatchBaseline.WsusScnCab.LastDownloadedSizeBytes = $wsusInfo.SizeBytes
            try {
                $cfgPath = Get-OsConfigPath -OsKey $Script:OsVersion
                Save-ConfigWithBaseline -ConfigPath $cfgPath -OsProfile $Script:OsProfile
                Write-Step ('wsusscn2.cab metadata recorded in: ' + $cfgPath)
            } catch {
                Write-Warn ('wsusscn2.cab metadata writeback failed: ' + $_.Exception.Message)
            }
        }

        # ---- Run WUA offline scan ----
        Set-DebugStep -Step 'wua-offline-scan'
        $wuaRaw = $null
        try {
            $wuaRaw = Invoke-WuaOfflineScan -WsusScnCabPath $wsusInfo.Path
        } catch {
            $msg = 'WUA offline scan failed: ' + $_.Exception.Message
            if ($Script:IgnorePatchValidation) {
                Write-Warn ($msg + ' (-IgnorePatchValidation set; continuing)')
                return $true
            }
            throw $msg
        }

        # ---- Compare patch sets ----
        Set-DebugStep -Step 'compare-patch-sets'
        $providedPatches = @()
        if ($Script:OsProfile.PatchBaseline -and $Script:OsProfile.PatchBaseline.Patches) {
            $providedPatches = @($Script:OsProfile.PatchBaseline.Patches)
        }
        $excludeKbList = @()
        if ($Script:OsProfile.PatchBaseline -and $Script:OsProfile.PatchBaseline.ExcludeKbList) {
            $excludeKbList = @($Script:OsProfile.PatchBaseline.ExcludeKbList)
        }
        $comparison = Compare-PatchSetVsWuaScan `
                        -ProvidedPatches $providedPatches `
                        -WuaRequired $wuaRaw `
                        -ExcludeKbList $excludeKbList

        Write-Step ('Patch set comparison: {0} provided / {1} missing / {2} excluded.' -f `
                    $comparison.Provided.Count, $comparison.Missing.Count, $comparison.ExcludedCount)

        # ---- If missing patches: export diagnostics and decide ----
        if ($comparison.Missing.Count -gt 0) {
            Set-DebugStep -Step 'export-diagnostics'
            $diagRoot = Join-Path $Script:WorkRoot 'diag'
            $target = @{
                OsVersion = $Script:OsVersion
                OsLanguage = $Script:OsLanguage
                BaseBuild = $Script:OsProfile.Build
                InstallWimIndex = 'multiple'
                WimEdition = ''
            }
            $wsusInfoHash = @{
                Path = $wsusInfo.Path
                Sha256 = $wsusInfo.Sha256
                DownloadedDate = if ($wsusInfo.DownloadedNow) { (Get-Date).ToString('o') } else { '(cached)' }
                SizeBytes = $wsusInfo.SizeBytes
                Source = $wsusInfo.Source
            }
            $diagDir = Export-PatchValidationReport `
                            -DiagRoot $diagRoot `
                            -Comparison $comparison `
                            -ProvidedPatches $providedPatches `
                            -WuaRaw $wuaRaw `
                            -Target $target `
                            -WsusScnCabInfo $wsusInfoHash `
                            -Status 'Fail' `
                            -Reason 'MissingRequiredPatches'
            Write-Warn '============================================================'
            Write-Warn '  PATCH VALIDATION DETECTED MISSING REQUIRED UPDATES'
            Write-Warn '============================================================'
            foreach ($m in $comparison.Missing) {
                Write-Warn ('  - {0} ({1})' -f ($m.KbIds -join ','), $m.Title)
            }
            Write-Warn ('  Diagnostic data exported to: ' + $diagDir)
            Write-Warn '============================================================'
            if ($Script:IgnorePatchValidation) {
                Write-Warn 'IgnorePatchValidation is set; continuing despite missing patches.'
                return $true
            }
            throw 'P04.5 ValidatePatchSet: required patches missing. See diagnostic data above.'
        }

        Write-Ok 'P04.5 ValidatePatchSet: all required patches are provided.'
        return $true
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P05: Patch install.wim (Build group)
# ============================================================
#
# Patch selection is driven by the PatchPlan engine
# (Build-PatchPlan in .build_part09c_patchplan.ps1) which consults
# $Script:PatchTargetMap to decide which patches belong to which
# WIM target. The legacy Get-PatchListForInstallWim /
# Get-PatchListForBootWim helpers remain as thin wrappers around
# the PatchPlan API so that downstream code paths (and any caller
# in P06) keep their existing call sites without surgery.

function Get-OrInitPatchPlan {
    <#
    .SYNOPSIS
        Return the cached $Script:PatchPlan; build it on first access.
    .DESCRIPTION
        Lazy initialisation lets phases that don't need the plan (e.g.
        P02.5 admin path) avoid the construction cost, while ensuring
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

function Invoke-BuildPhase05_PatchInstallWim {
    <#
    .SYNOPSIS
        P05: For every install.wim image index, mount, apply SSU/LCU/
        .NET/Dynamic Update Component, run DISM cleanup, dismount.
        Emits P05_patch_inventory.csv.
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase05_PatchInstallWim' -PhaseId 'P05'
    try {
        if (-not $Script:OsProfile.EnableInstallWimUpdate) {
            Write-Skip 'EnableInstallWimUpdate is false in profile; skipping P05.'
            return
        }
        $installWim = Join-Path $Script:ExtractedDir 'sources\install.wim'
        if (-not (Test-Path -LiteralPath $installWim)) {
            if ($Script:SyntheticTestMode) {
                Write-Skip 'install.wim absent in -SyntheticTestMode; skipping P05.'
                return
            }
            throw ('install.wim missing: {0}' -f $installWim)
        }

        # Sandbox-mode safety: require -Execute for write operations
        if (-not $Script:Execute -and -not $Script:SyntheticTestMode) {
            Write-Warn 'Running in Sandbox mode (no -Execute). Will list intended actions only.'
        }

        $patches = Get-PatchListForInstallWim
        Write-Step ('install.wim-targeted patches: {0}' -f $patches.Count)

        $targets = Resolve-InstallWimTargetIndexes -Inventory $Script:WimIndexInventory
        Write-Step ('install.wim indexes to update: {0}' -f ($targets | Measure-Object).Count)

        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($img in $targets) {
            Write-SubSection ('install.wim index {0}: {1}' -f $img.ImageIndex, $img.ImageName)
            Set-DebugStep -Step ('install-idx-' + $img.ImageIndex)

            if (-not $Script:Execute -and -not $Script:SyntheticTestMode) {
                foreach ($p in $patches) {
                    Write-Step ('  [PLAN] {0} ({1}) -> idx {2}' -f $p.KbId, $p.PatchType, $img.ImageIndex)
                    $rows.Add([pscustomobject]@{
                        KbId = $p.KbId; PatchType = $p.PatchType
                        FilePath = $p.LocalPath; ApplyOrder = $p.ApplyOrder
                        AppliesTo = ('install.wim:idx' + $img.ImageIndex)
                        ApplyStatus = 'Planned'; ElapsedSeconds = 0
                        DismExitCode = 0
                    }) | Out-Null
                }
                continue
            }

            Set-DebugStep -Step ('mount-install-idx-' + $img.ImageIndex)
            Invoke-WimMountSafe -ImagePath $installWim -Index $img.ImageIndex `
                -Path $Script:MountInstallDir -LogDir $Script:LogsDir | Out-Null
            try {
                # Pre-apply dependency closure check. Verifies
                # that every patch's RequiresKbIds is already satisfied
                # inside the freshly-mounted image. Strict mode (default)
                # aborts the run before Add-WindowsPackage so we surface
                # the precondition failure cleanly rather than letting
                # DISM emit a 0x800f0823 hex code mid-loop.
                Set-DebugStep -Step ('depcheck-install-idx-' + $img.ImageIndex)
                Test-PatchDependencyClosureOnMount -MountPath $Script:MountInstallDir `
                    -PatchesToApply $patches `
                    -ImageLabel ('install.wim:idx' + $img.ImageIndex) | Out-Null

                foreach ($p in $patches) {
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $status = 'Fail'; $exitCode = -1
                    try {
                        $status = Add-WindowsPackageWithRetry -MountPath $Script:MountInstallDir `
                            -PackagePath $p.LocalPath -LogDir $Script:LogsDir
                        $exitCode = 0
                    } catch {
                        Write-Fail ('Add-WindowsPackage failed for {0}: {1}' -f (Split-Path -LiteralPath $p.LocalPath -Leaf), $_.Exception.Message)
                        Add-ErrorJsonlEntry -Phase 'P05' -Kind 'failure' -Properties @{
                            exType = $_.Exception.GetType().FullName
                            msg = $_.Exception.Message
                            wimIndex = $img.ImageIndex
                            kb = $p.KbId
                        }
                        throw
                    } finally {
                        $sw.Stop()
                        $rows.Add([pscustomobject]@{
                            KbId = $p.KbId; PatchType = $p.PatchType
                            FilePath = $p.LocalPath; ApplyOrder = $p.ApplyOrder
                            AppliesTo = ('install.wim:idx' + $img.ImageIndex)
                            ApplyStatus = $status
                            ElapsedSeconds = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
                            DismExitCode = $exitCode
                        }) | Out-Null
                    }
                    Write-Ok ('  Applied {0} ({1}) status={2} elapsed={3:F1}s' -f $p.KbId, $p.PatchType, $status, $sw.Elapsed.TotalSeconds)
                }

                Set-DebugStep -Step ('cleanup-install-idx-' + $img.ImageIndex)
                Invoke-DismCleanup -MountPath $Script:MountInstallDir
            } finally {
                Set-DebugStep -Step ('dismount-install-idx-' + $img.ImageIndex)
                Invoke-WimDismountSafe -Path $Script:MountInstallDir -LogDir $Script:LogsDir
            }
        }

        $csvPath = Join-Path $Script:LogsDir 'P05_patch_inventory.csv'
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Wrote: {0}' -f $csvPath)

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P05.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P06: Patch boot.wim + winre.wim (Build group)
# ============================================================

function Invoke-BuildPhase06_PatchBootWim {
    <#
    .SYNOPSIS
        P06: Apply SSU/LCU/SafeOs DU to boot.wim indexes (PE + Setup)
        and to winre.wim (extracted from install.wim).
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase06_PatchBootWim' -PhaseId 'P06'
    try {
        if (-not $Script:OsProfile.EnableBootWimUpdate) {
            Write-Skip 'EnableBootWimUpdate is false in profile; skipping P06.'
            return
        }
        $bootWim = Join-Path $Script:ExtractedDir 'sources\boot.wim'
        if (-not (Test-Path -LiteralPath $bootWim)) {
            if ($Script:SyntheticTestMode) {
                Write-Skip 'boot.wim absent in -SyntheticTestMode; skipping P06.'
                return
            }
            throw ('boot.wim missing: {0}' -f $bootWim)
        }

        if (-not $Script:Execute -and -not $Script:SyntheticTestMode) {
            Write-Warn 'Running in Sandbox mode (no -Execute); skipping boot.wim modifications.'
            return
        }

        $patches = Get-PatchListForBootWim
        Write-Step ('boot.wim-targeted patches: {0}' -f $patches.Count)

        $bootIndexes = @($Script:OsProfile.BootWimIndexes)
        if (-not $bootIndexes -or $bootIndexes.Count -eq 0) {
            $bootIndexes = @(1, 2)
        }

        foreach ($idx in $bootIndexes) {
            Write-SubSection ('boot.wim index {0}' -f $idx)
            Set-DebugStep -Step ('boot-idx-' + $idx)

            $mountDir = $Script:MountBoot1Dir
            if ($idx -eq 2) { $mountDir = $Script:MountBoot2Dir }

            Invoke-WimMountSafe -ImagePath $bootWim -Index $idx `
                -Path $mountDir -LogDir $Script:LogsDir | Out-Null
            try {
                # Dependency closure check for boot.wim
                Test-PatchDependencyClosureOnMount -MountPath $mountDir `
                    -PatchesToApply $patches `
                    -ImageLabel ('boot.wim:idx' + $idx) | Out-Null

                foreach ($p in $patches) {
                    Write-Step ('  Applying {0} ({1})' -f $p.KbId, $p.PatchType)
                    $status = Add-WindowsPackageWithRetry -MountPath $mountDir `
                        -PackagePath $p.LocalPath -LogDir $Script:LogsDir
                    Write-Ok ('   status={0}' -f $status)
                }
                Invoke-DismCleanup -MountPath $mountDir
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
                    Write-Warn 'Winre.wim not found inside install.wim; skipping winre update.'
                } else {
                    Copy-Item -LiteralPath $winReInside -Destination $winReWork -Force
                    # winre.wim is typically a single-index image
                    Invoke-WimMountSafe -ImagePath $winReWork -Index 1 `
                        -Path $Script:MountWinReDir -LogDir $Script:LogsDir | Out-Null
                    try {
                        foreach ($p in $patches) {
                            Write-Step ('  Applying {0} to winre' -f $p.KbId)
                            Add-WindowsPackageWithRetry -MountPath $Script:MountWinReDir `
                                -PackagePath $p.LocalPath -LogDir $Script:LogsDir | Out-Null
                        }
                        Invoke-DismCleanup -MountPath $Script:MountWinReDir
                    } finally {
                        Invoke-WimDismountSafe -Path $Script:MountWinReDir -LogDir $Script:LogsDir
                    }
                    Copy-Item -LiteralPath $winReWork -Destination $winReInside -Force
                }
            } finally {
                Invoke-WimDismountSafe -Path $Script:MountInstallDir -LogDir $Script:LogsDir
            }
        }

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P06.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P07: Assemble updated ISO (Build group)
# ============================================================

function Invoke-BuildPhase07_AssembleIso {
    <#
    .SYNOPSIS
        P07: Apply Dynamic Update Setup overlay onto sources\, run
        New-BootableIso (oscdimg) to produce the final ISO.
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase07_AssembleIso' -PhaseId 'P07'
    try {
        Write-SubSection 'Step 1: Dynamic Update Setup overlay'
        Set-DebugStep -Step 'dynup-setup-overlay'
        $setupDuPatches = @($Script:ResolvedPatches | Where-Object { $_.PatchType -eq 'DynamicUpdate.Setup' })
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
                    Copy-Item -LiteralPath (Join-Path $tmpExtract '*') `
                        -Destination (Join-Path $Script:ExtractedDir 'sources') -Recurse -Force
                    Write-Ok ('Overlay applied: {0}' -f $p.KbId)
                } else {
                    Write-Warn ('expand.exe failed for {0}; skipping overlay.' -f $p.KbId)
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

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P07.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}


# ============================================================
# Phase P08: Static verification (Verify group)
# ============================================================

function Invoke-VerifyPhase08_StaticVerify {
    <#
    .SYNOPSIS
        P08: Verify the output ISO without booting it. Mounts the ISO,
        verifies presence of install.wim/boot.wim/setup.exe, runs
        Get-WindowsImage and Get-WindowsPackage to check that the
        expected KB packages have been integrated. Emits
        P08_verification.csv.
    #>
    Start-DebugTrace -Context 'Invoke-VerifyPhase08_StaticVerify' -PhaseId 'P08'
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
            Write-Warn ('Could not mount output ISO: {0}' -f $_.Exception.Message)
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
                        $pkgs = Get-WindowsPackage -ImagePath $installWim -Index $firstIdx
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
                    Write-Warn ('WIM enumeration failed: {0}' -f $_.Exception.Message)
                }
            }
        }
        if ($img) {
            try { Dismount-DiskImage -ImagePath $Script:OutputIsoPath -ErrorAction SilentlyContinue | Out-Null } catch { $null = $_ }
        }

        $csvPath = Join-Path $Script:LogsDir 'P08_verification.csv'
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Wrote: {0}' -f $csvPath)

        $failed = $rows | Where-Object { $_.Status -eq 'Fail' }
        if ($failed.Count -gt 0) {
            throw ('P08 verification failed: {0} hard failures.' -f $failed.Count)
        }

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P08.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P09: Final report (Report group)
# ============================================================

function Invoke-ReportPhase09_FinalReport {
    <#
    .SYNOPSIS
        P09: End-of-run summary. Phase timing table, output ISO hash
        and path, log/diag locations.
    #>
    Start-DebugTrace -Context 'Invoke-ReportPhase09_FinalReport' -PhaseId 'P09'
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

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P09.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}


# ============================================================
# Admin phases: RefreshAllBaselines (A01),
#                      DumpFieldClassification (A02)
# ============================================================
# These are "admin" phases in the sense that they don't take an
# OS image as input; they operate on the on-disk Config/*.json
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
        Refresh Config/<OsKey>.json baselines for one or more OS / language
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
        $configRoot = Join-Path $Script:ScriptRoot 'Config'
        if (-not (Test-Path -LiteralPath $configRoot)) {
            throw ('Config root not found: {0}' -f $configRoot)
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
            Write-Warn 'DryRun is ON: changes will NOT be written back to disk.'
        }

        $reportRows = New-Object System.Collections.Generic.List[object]

        foreach ($osKey in $targetOsKeys) {
            Set-DebugStep -Step ('os:' + $osKey)
            $cfgFile = Join-Path $configRoot ($osKey + '.json')
            if (-not (Test-Path -LiteralPath $cfgFile)) {
                Write-Warn ('Config not found: {0}' -f $cfgFile)
                continue
            }
            Write-SubSection ('Refreshing {0}' -f $osKey)
            $raw = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($raw.Schema -ne '2.0') {
                Write-Warn ('Skipping {0}: Schema is "{1}", expected "2.0".' -f $osKey, $raw.Schema)
                continue
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
                            Write-Warn ('    -> Manual fill required (no auto Refresher for this group).')
                        }
                        { $_ -in @('InitialFill','Monthly') } {
                            # Invoke the Refresher
                            $refresher = $g.Refresher
                            if ([string]::IsNullOrEmpty($refresher)) {
                                $hasUnresolved = $true
                                Write-Warn ('    -> No Refresher; field requires manual fill.')
                                break
                            }
                            try {
                                if ($refresher -eq 'Resolve-PatchSetFromCatalog') {
                                    $patches = @(Resolve-PatchSetFromCatalog -OsVersion $osKey `
                                                                              -OsLanguage 'neutral' `
                                                                              -PatchMonth $patchMonth `
                                                                              -MaxRetries 3)
                                    $patchCount = $patches.Count
                                    if (-not $Script:DryRun -and $patchCount -gt 0) {
                                        $raw.PatchBaseline.NeutralPatches = $patches
                                    }
                                    Set-GroupVerifiedState -ConfigRaw $raw -GroupPath $g.Path -Lang $lang `
                                                           -PatchTuesday $latestPt -VerifierTag 'auto:RefreshAllBaselines'
                                    $changed = $true
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
                                } else {
                                    $hasUnresolved = $true
                                    Write-Warn ('    -> Unknown Refresher "{0}"' -f $refresher)
                                }
                            } catch {
                                $okOverall = $false
                                $errorMsg = $_.Exception.Message
                                Write-Fail ('    -> Refresher failed: {0}' -f $errorMsg)
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
                Write-Warn ('  DryRun: would have written {0}' -f $cfgFile)
            } else {
                Write-Step ('  No changes for {0}' -f $osKey)
            }
        }

        # Emit aggregate report
        Set-DebugStep -Step 'emit-report'
        $reportPath = Join-Path $Script:LogsDir 'A01_RefreshAllBaselines_report.csv'
        $reportRows | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Report: {0}' -f $reportPath)

        Write-Host ''
        Write-Host '============================== Summary ==============================' -ForegroundColor Cyan
        $byDecision = $reportRows | Group-Object Decision | Sort-Object Name
        foreach ($g in $byDecision) {
            Write-Host ('  {0,-15} : {1}' -f $g.Name, $g.Count) -ForegroundColor White
        }
        Write-Host ''

        if (-not $okOverall) {
            $Script:ExitCode = 1
            return $false
        }
        if ($hasUnresolved) {
            $Script:ExitCode = 2
            Write-Warn 'Some fields require manual fill; exit code 2.'
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
        $json = $payload | ConvertTo-Json -Depth 8
        Set-Content -LiteralPath $outPath -Value $json -Encoding UTF8 -NoNewline
        Add-Content -LiteralPath $outPath -Value "`n" -Encoding UTF8 -NoNewline
        Write-Ok ('Field classification written: {0}' -f $outPath)
        return $true
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase dispatcher and Action resolver
# ============================================================

function Get-PhaseListByAction {
    <#
    .SYNOPSIS
        Map -Action to a sequence of phase IDs.
    .DESCRIPTION
        Admin-group actions (RefreshAllBaselines,
        DumpFieldClassification) and applies a SyntheticTestMode
        skip to P04 / P04.5. The synthetic ISO produced by P03 is
        not a structurally valid ISO9660 image; Mount-DiskImage in
        P04 therefore fails with "file or directory is corrupted"
        on Windows runners. Stage 3 (Synthetic+Execute) already
        bypasses P04 by going straight to P05; this aligns Stage 2
        Smoke 3 (Synthetic+DryRun) with the same flow.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string]$ActionName)

    # Phases used by the standard build pipeline. When SyntheticTestMode
    # is set, the P04 / P04.5 pair is removed - synthetic ISOs cannot
    # round-trip through Mount-DiskImage.
    $standardFull = if ($Script:SyntheticTestMode) {
        [string[]]@('P01','P02','P02.5','P03','P05','P06','P07','P08','P09')
    } else {
        [string[]]@('P01','P02','P02.5','P03','P04','P04.5','P05','P06','P07','P08','P09')
    }
    $standardPrepare = if ($Script:SyntheticTestMode) {
        [string[]]@('P01','P02','P02.5','P03')
    } else {
        [string[]]@('P01','P02','P02.5','P03','P04','P04.5')
    }

    switch ($ActionName) {
        'Prepare'                 { return $standardPrepare }
        'Build'                   { return [string[]]@('P05','P06','P07') }
        'Verify'                  { return [string[]]@('P08','P09') }
        'PrepareBuildVerify'      { return $standardFull }
        'All'                     { return $standardFull }
        'BootTest'                { return [string[]]@() }
        'Cleanup'                 { return [string[]]@() }
        'ListPhases'              { return [string[]]@() }
        'GenerateManifest'        { return [string[]]@('P01','P02','P02.5') }
        'RefreshAllBaselines'     { return [string[]]@('A01') }
        'DumpFieldClassification' { return [string[]]@('A02') }
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
    foreach ($a in @('Prepare','Build','Verify','PrepareBuildVerify','BootTest','All','Cleanup','ListPhases','GenerateManifest','RefreshAllBaselines','DumpFieldClassification')) {
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
            Write-Warn ('Phase {0} is not registered; skipping.' -f $id)
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
        $mounted = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
        foreach ($m in @($mounted)) {
            foreach ($d in @($Script:MountInstallDir, $Script:MountBoot1Dir, $Script:MountBoot2Dir, $Script:MountWinReDir)) {
                if ($m.Path -and (($m.Path.TrimEnd('\')) -ieq ($d.TrimEnd('\')))) {
                    Write-Warn ('Discarding stale mount at {0} before cleanup.' -f $d)
                    Dismount-WindowsImage -Path $d -Discard -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
    } catch { $null = $_ }

    if (Test-Path -LiteralPath $Script:WorkRoot) {
        Write-Step ('Removing: {0}' -f $Script:WorkRoot)
        Remove-Item -LiteralPath $Script:WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok 'Workspace removed.'
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

# Optional -LogFile transcript
if ($Script:LogFile) {
    $Script:LogFile = Resolve-RelativeToScript $Script:LogFile
    $logParent = [System.IO.Path]::GetDirectoryName($Script:LogFile)
    if (-not (Test-Path -LiteralPath $logParent)) {
        New-Item -ItemType Directory -Path $logParent -Force | Out-Null
    }
    try {
        # psa-disable-next-line PSA3005 -- Start-Transcript has no -LiteralPath parameter; -Path is the only option in PS 5.1/7
        Start-Transcript -Path $Script:LogFile -Append -Force | Out-Null
        Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
            try { Stop-Transcript | Out-Null } catch { $null = $_ }
        } | Out-Null
    } catch {
        Write-Warning ('Could not start transcript: {0}' -f $_.Exception.Message)
    }
}

Show-EntryBanner

# Quick branch for actions that do not need workspace init
if ($Action -eq 'ListPhases') {
    Show-PhaseList
    exit 0
}

# Optional clean
if ($Script:CleanWorkRoot -and (Test-Path -LiteralPath $Script:WorkRoot)) {
    Write-Warn ('CleanWorkRoot: deleting {0}' -f $Script:WorkRoot)
    if (Test-DangerousPath -Path $Script:WorkRoot) {
        throw ('Refusing to clean dangerous path: {0}' -f $Script:WorkRoot)
    }
    Remove-Item -LiteralPath $Script:WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Initialize-RuntimeDirectories

# Activate debug trace JSONL file output
try {
    Enable-DebugTraceFileOutput -Directory $Script:LogsDir | Out-Null
    Enable-AutoExportOnPhaseFailure -OutputDirectory $Script:DiagDir | Out-Null
} catch {
    Write-Warning ('Debug Trace setup warning: {0}' -f $_.Exception.Message)
}

$Script:ExitCode = 0
try {
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
        Write-Warn 'GenerateManifest action is a placeholder in this revision. See SPEC Part H.2.'
    }
} catch {
    $Script:ExitCode = 1
    Write-Fail ('Run failed: {0}' -f $_.Exception.Message)
    # Auto-export any active debug trace (best-effort)
    try {
        if (Get-Command -Name 'Export-DebugTraceJson' -ErrorAction SilentlyContinue) {
            Export-DebugTraceJson -OutputDir $Script:DiagDir | Out-Null
        }
    } catch { $null = $_ }
} finally {
    try {
        Show-PhaseSummary
    } catch { $null = $_ }
}

exit $Script:ExitCode
