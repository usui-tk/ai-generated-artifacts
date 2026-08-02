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
      - Internet access for ISO/patch downloads (offline runs: pass
        -IsoPath and pre-stage the baseline patch files under
        <WorkRoot>/patches/<OsVersion>/ -- P04 skips verified files)
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
    Phases (P01..P14):
      P01 : Initialize        (Setup ) PowerShell env, admin, ADK, disk, Hyper-V
      P02 : ResolveInputs     (Setup ) ISO/patch source resolution, Schema 3/4
                                       Config JSON, role-based apply plan
      P04 : FetchAssets       (Fetch ) ISO + patch downloads with hash verify
      P05 : ExpandIso         (Plan  ) Mount source ISO, copy to workspace,
                                       enumerate WIM indexes
      P07 : PatchInstallWim   (Build ) Source prerequisite / SSU carrier,
                                       final LCU, cleanup, then .NET per index
      P08 : PatchBootWim      (Build ) boot.wim plus one serviced WinRE copied
                                       to every selected install.wim index
      P09 : AssembleIso       (Build ) Setup Dynamic Update overlay,
                                       Export-WindowsImage, oscdimg ISO build
      P11 : StaticVerify      (Verify) Mount output ISO, confirm KB packages
                                       are present
      P13 : FinalReport       (Report) End-of-run summary + ISO hash + log
                                       paths + release eligibility
      P14 : HyperVValidation  (Verify) Optional Gen2 Secure Boot smoke boot
                                       or unattended installation validation

    BootTest maps to P14. PrepareBuildVerify includes P14 only with
    -RunHyperVValidation; All includes it by default.

.PARAMETER Action
    One of: Prepare / Build / Verify / PrepareBuildVerify / BootTest / All /
    Cleanup / ListPhases / GenerateManifest / RefreshAllBaselines /
    DumpFieldClassification / TestHarness. Default: PrepareBuildVerify.
    The TestHarness action loads all functions and enters a JSON-over-stdin
    REPL used by the Python-side self-verification tools in `tests/`; it
    is not meant for human invocation.

.PARAMETER OnlyPhases
    Array of phase IDs (e.g. 'P04','P07') to run. Overrides -Action.

.PARAMETER ResumeFromPhase
    Resume a previously interrupted build from P08 or P09. The script runs
    P01/P02 to reconstruct runtime state, validates the existing WorkRoot,
    restores boot.wim before P08 when required, and then continues through
    the remaining build/verification phases without re-downloading or
    re-servicing install.wim.

.PARAMETER ResumePreflightOnly
    Validate an existing P08/P09 resume workspace and rehydrate all measured
    patch assets, but stop before any build phase runs. Requires
    -ResumeFromPhase. This is a non-destructive preflight for resume.

.PARAMETER OsVersion
    One of: Server2016 / Server2019 / Server2022 / Server2025.

.PARAMETER OsLanguage
    One of: en-us / ja-jp. Default: en-us.

.PARAMETER IsoUrl
    HTTP(S) URL of the source ISO. Mutually exclusive with -IsoPath.

.PARAMETER IsoPath
    Local path of the source ISO. Mutually exclusive with -IsoUrl.

.PARAMETER AutoDetectLatestPatches
    Force a refresh of the patch baseline by scraping Microsoft Update
    Catalog regardless of staleness. Result is written back to the
    Config JSON (PatchBaseline). Requires internet access..

.PARAMETER PatchMonth
    Target patch month in yyyy-MM format (e.g. '2026-06'). Used by the
    r02 RefreshPatchBaseline phase to scope the Catalog query. Defaults
    to the current month's Patch Tuesday..

.PARAMETER PatchRefreshMode
    Explicit patch-selection mode. PinAll pins OS and auxiliary KB identities;
    PinOs pins the reviewed OS LCU/SSU/checkpoint while resolving monthly
    .NET/Safe OS DU/Setup DU; Auto refreshes both. Legacy switches remain as
    aliases: -UseBaselineOnly=PinAll, -SkipDynamicPatchRefresh=PinOs,
    -AutoDetectLatestPatches=Auto.

.PARAMETER SkipDynamicPatchRefresh
    Skip only the P03 full baseline refresh. P04 may still resolve the
    configured monthly auxiliary selectors (.NET / Safe OS DU / Setup DU)
    when DiscoveryPolicy.ResolveMonthlyAuxiliariesAtFetch is enabled.
    This is the recommended switch when the OS LCU/SSU anchors are already
    pinned to a reviewed month but runtime-specific auxiliary packages must
    still be selected for that month.

.PARAMETER UseBaselineOnly
    Pin the configured PatchBaseline KB identities and roles exactly as-is.
    Disables both P03 baseline discovery and P04 monthly auxiliary replacement.
    P04 may still resolve the current DownloadDialog URL/file identity for an
    already-configured KB whose asset URL is missing; it never substitutes a
    different KB. Pre-stage every configured asset to avoid Catalog access.

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
    Workspace root. Default: <script-root>\Workspace_UpdateWsi.
    Strong recommendation: use a dedicated NTFS data-drive directory for each OS.

.PARAMETER OutputDir
    Compatibility override for the output ISO subdirectory. The resolved path
    MUST remain inside WorkRoot. Relative values resolve against WorkRoot.
    Default: <WorkRoot>\output.

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
    Delete the existing WorkRoot before starting. Because all artifacts are
    workspace-contained, previous logs and output ISOs are also removed.

.PARAMETER LogFile
    Start-Transcript path for the entire run. The resolved path MUST remain
    inside WorkRoot. Relative values resolve against WorkRoot.

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
        -UseBaselineOnly `
        -WorkRoot 'D:\UpdateWsi' `
        -Execute
    Full local build: explicit ISO, patch set pinned to the committed
    PatchBaseline.Lines (pre-stage the files under
    <WorkRoot>/patches/Server2019/ to run offline; P04 skips verified files).

.EXAMPLE
    .\Update-WindowsServerIso.ps1 `
        -Action PrepareBuildVerify `
        -OsVersion Server2025 -OsLanguage en-us `
        -AutoDetectLatestPatches `
        -WorkRoot 'D:\UpdateWsi' `
        -Execute
    Download the source ISO from the config's LanguageSpecific Iso.Url,
    auto-detect the latest patches, run the full pipeline.

.EXAMPLE
    .\Update-WindowsServerIso.ps1 `
        -Action PrepareBuildVerify `
        -OsVersion Server2016 -OsLanguage ja-jp `
        -SkipDynamicPatchRefresh `
        -WorkRoot 'D:\UpdateWsi'
    Server 2016 ja-jp build, dry-run mode (no -Execute). The reviewed OS
    LCU/SSU anchors stay pinned while P04 selects the applicable monthly
    .NET / Safe OS DU / Setup DU packages. Add -Execute on a subsequent run
    to perform the real ISO assembly.
#>

[CmdletBinding()]
param(
    [ValidateSet('Prepare','Build','Verify','PrepareBuildVerify','BootTest','All','Cleanup','ListPhases','GenerateManifest','RefreshSnapshots','RefreshAllBaselines','RebuildDataset','DumpFieldClassification','TestHarness')]
    [string]   $Action               = 'PrepareBuildVerify',

    [string[]] $OnlyPhases,

    [ValidateSet('P08','P09')]
    [string]   $ResumeFromPhase,
    [switch]   $ResumePreflightOnly,

    [ValidateSet('Server2016','Server2019','Server2022','Server2025')]
    [string]   $OsVersion,

    [ValidateSet('en-us','ja-jp')]
    [string]   $OsLanguage           = 'en-us',

    [string]   $IsoUrl,
    [string]   $IsoPath,

    [switch]   $AutoDetectLatestPatches,

    # ---- dynamic baseline / validation parameters ----
    [string]   $PatchMonth,
    [ValidateSet('PinAll','PinOs','Auto')]
    [string]   $PatchRefreshMode,
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
    [switch]   $Execute,

    # ---- Secure Boot / PCA2023 ----
    # When set, enables P10 ConvertPca2023BootManager which rewrites the
    # output ISO's boot manager to the 'Windows UEFI CA 2023'-signed form
    # (Microsoft KB5053484 / Make2023BootableMedia.ps1 equivalent). Default
    # P10 ConvertPca2023BootManager runs BY DEFAULT (readiness-driven:
    # it converts only when the pre-flight snapshot says the media is
    # ready and not already signed; Critical/Healthy states skip). The
    # PCA2011 signing CA expired 2026-06, so a PCA2011-only boot manager
    # is the exception now, not the norm. Set this switch to keep the
    # shipped (PCA2011-signed) boot manager and skip P10 entirely.
    [switch]   $SkipPca2023BootManager,

    # Advanced override for Server 2025. The normal decision is now driven
    # by data/Pca2023.CompliancePolicy. RequirePca2023 may invoke P10
    # automatically; this switch forces the conversion attempt even when
    # the configured policy would otherwise permit audit-only/legacy media.
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
    [string]   $Pca2023ScriptPath,

    # Optional P14. PrepareBuildVerify runs P14 only when this switch is set.
    # -Action BootTest and -Action All run P14 regardless of this switch.
    [switch]   $RunHyperVValidation,

    # BootOnly captures console thumbnails for operator adjudication.
    # Install creates an Autounattend answer ISO, performs an unattended
    # evaluation install, and collects build / WinRE / Secure Boot evidence
    # through PowerShell Direct.
    [ValidateSet('BootOnly','Install')]
    [string]   $HyperVValidationMode = 'BootOnly',

    # Standalone -Action BootTest can validate an ISO moved from its original
    # output directory. The SHA-256 must still match the P11/P12 evidence index.
    [string]   $BootTestIsoPath,

    # BootOnly screenshots are evidence capture, not release approval. Supply
    # an operator-controlled JSON approval file on a subsequent BootTest
    # invocation to promote the same identity-bound evidence to ReleaseReady.
    [string]   $BootEvidenceApprovalPath
)

# Propagate the new PCA2023 switches into Script scope so Phase
# functions can reference them as $Script:* (rather than relying on
# the auto-bound parameter scope, which psa.py's PSA2001 cannot
# reason about reliably). Mirrors how P09 AssembleIso etc. reach
# operator-supplied options.
$Script:SkipPca2023BootManager    = [bool]$SkipPca2023BootManager
$Script:ForcePca2023OnServer2025  = [bool]$ForcePca2023OnServer2025
$Script:Pca2023OnlyMode           = [bool]$Pca2023OnlyMode
$Script:Pca2023ScriptPath         = $Pca2023ScriptPath
$Script:RunHyperVValidation       = [bool]$RunHyperVValidation
$Script:HyperVValidationMode      = $HyperVValidationMode
$Script:BootTestIsoPath           = $BootTestIsoPath
$Script:BootEvidenceApprovalPath  = $BootEvidenceApprovalPath
$Script:ReleaseEligibility        = $null
$Script:RunId                     = ([guid]::NewGuid().Guid)
$Script:ResetBaseOnCleanup        = -not [bool]$SkipResetBaseOnCleanup
$Script:SkipExportCompress        = [bool]$SkipExportCompress
$Script:UseDefenderExclusions     = [bool]$UseDefenderExclusions
$Script:PatchRefreshModeExplicit = if ($PSBoundParameters.ContainsKey('PatchRefreshMode')) { [string]$PatchRefreshMode } else { '' }
# ResumeFromPhase is a validated script parameter. Assigning an unbound
# validated parameter back to the same script-scoped variable triggers
# ValidateSet against the implicit empty string in both Windows PowerShell
# and PowerShell 7. Keep the operator-facing parameter untouched and copy
# only its normalized state to a separate, unconstrained internal variable.
$Script:RequestedResumeFromPhase  = if ($PSBoundParameters.ContainsKey('ResumeFromPhase')) { [string]$ResumeFromPhase } else { $null }
$Script:ResumePreflightOnly        = [bool]$ResumePreflightOnly

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
if ($BootEvidenceApprovalPath -and $Action -ne 'BootTest') {
    throw '-BootEvidenceApprovalPath is supported only with -Action BootTest.'
}
if ($BootEvidenceApprovalPath -and $HyperVValidationMode -ne 'BootOnly') {
    throw '-BootEvidenceApprovalPath is valid only with -HyperVValidationMode BootOnly.'
}
if ($PSBoundParameters.ContainsKey('OnlyPhases') -and -not $OnlyPhases) {
    throw '-OnlyPhases was specified but the array is empty.'
}
if ($ResumeFromPhase -and $OnlyPhases) {
    throw '-ResumeFromPhase and -OnlyPhases are mutually exclusive.'
}
if ($ResumeFromPhase -and $Action -notin @('Build','PrepareBuildVerify')) {
    throw '-ResumeFromPhase is supported only with -Action Build or PrepareBuildVerify.'
}
if ($ResumePreflightOnly -and -not $ResumeFromPhase) {
    throw '-ResumePreflightOnly requires -ResumeFromPhase P08 or P09.'
}

# ---- mutual exclusivity / format validation (P03 / P06 params) ----
if ($PatchRefreshMode -and ($UseBaselineOnly -or $SkipDynamicPatchRefresh -or $AutoDetectLatestPatches)) {
    throw '-PatchRefreshMode cannot be combined with -UseBaselineOnly, -SkipDynamicPatchRefresh, or -AutoDetectLatestPatches.'
}
if ($SkipDynamicPatchRefresh -and $AutoDetectLatestPatches) {
    throw '-SkipDynamicPatchRefresh and -AutoDetectLatestPatches are mutually exclusive.'
}
if ($UseBaselineOnly -and $AutoDetectLatestPatches) {
    throw '-UseBaselineOnly and -AutoDetectLatestPatches are mutually exclusive.'
}
if ($UseBaselineOnly -and $SkipDynamicPatchRefresh) {
    throw '-UseBaselineOnly and -SkipDynamicPatchRefresh are mutually exclusive.'
}
$Script:EffectivePatchRefreshMode = if ($PatchRefreshMode) {
    [string]$PatchRefreshMode
} elseif ($UseBaselineOnly) {
    'PinAll'
} elseif ($SkipDynamicPatchRefresh) {
    'PinOs'
} elseif ($AutoDetectLatestPatches) {
    'Auto'
} else {
    'Auto'
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
$osLessActions = @('ListPhases','Cleanup','RefreshSnapshots','RefreshAllBaselines','RebuildDataset','DumpFieldClassification','TestHarness')
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
# Resolve $Script:ScriptRoot once. WorkRoot itself is resolved against the
# script root. Artifact paths (-OutputDir and -LogFile) are then resolved
# against WorkRoot and rejected when they escape it. This preserves the
# single-workspace artifact contract regardless of the caller's CWD.
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

function Resolve-PathWithinRoot {
    <#
    .SYNOPSIS
        Resolve an artifact path and enforce that it remains inside a root.
    .DESCRIPTION
        Relative values resolve against Root, not the script directory or the
        caller's current directory. Path traversal and absolute paths outside
        Root are rejected before any directory is created.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$ParameterName
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\','/'))
    $candidateInput = $Path
    if (-not [System.IO.Path]::IsPathRooted($candidateInput)) {
        $candidateInput = Join-Path $rootFull $candidateInput
    }
    $candidateFull = [System.IO.Path]::GetFullPath($candidateInput).TrimEnd([char[]]@('\','/'))
    $rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    $inside = (
        [string]::Equals($candidateFull, $rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    )
    if (-not $inside) {
        throw ('{0} must resolve inside WorkRoot. WorkRoot={1}; resolved={2}' -f $ParameterName, $rootFull, $candidateFull)
    }
    return $candidateFull
}

# -----------------
# Workspace tree resolution
# -----------------
# The ISO Updater workspace layout is documented in SPEC.md Part B.2.
# All sub-directories are derived from $Script:WorkRoot so a single
# -WorkRoot override re-bases the whole tree (used heavily on CI where
# only D: has enough free space).

$Script:WorkRoot = Resolve-RelativeToScript $WorkRoot

if ([string]::IsNullOrEmpty($OutputDir)) {
    $Script:OutputDir = Join-Path $Script:WorkRoot 'output'
} else {
    $Script:OutputDir = Resolve-PathWithinRoot -Path $OutputDir -Root $Script:WorkRoot -ParameterName '-OutputDir'
}

if ([string]::IsNullOrEmpty($LogFile)) {
    $Script:LogFile = ''
} else {
    $Script:LogFile = Resolve-PathWithinRoot -Path $LogFile -Root $Script:WorkRoot -ParameterName '-LogFile'
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
$Script:ScriptVersion = 'update-wsi-2026.07.20-r12.25'
$Script:ScriptTag     = 'measured-e2e-os-specific-servicing-and-catalog-rehydration'
$Script:SecureBootObjectsRelease       = 'v1.6.5-signed'
$Script:SecureBootObjectsSourceTag     = 'v1.6.5'
$Script:SecureBootObjectsCommit        = '798cdc5'
$Script:Make2023BootableMediaVersion   = '1.4'
$Script:Make2023BootableMediaDate      = '2026-03-13'
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
$Script:PhaseTimings      = [System.Collections.Generic.List[object]]::new()
# Idempotency guard for Show-PhaseSummary. P13 FinalReport prints
# the timing table as part of its body (per SPEC.md Part B.5 Step 1);
# the script-tail `finally` block also calls Show-PhaseSummary as a
# safety net for runs that abort before P13. This flag stops the
# safety-net call from printing a duplicate table on a happy-path run.
$Script:PhaseSummaryShown = $false

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
    [pscustomobject]@{ Id='P08S';  Name='SyncSetupBinaries';         Group='Build';  Func='Invoke-BuildPhase08S_SyncSetupBinaries' }
    [pscustomobject]@{ Id='P09';   Name='AssembleIso';               Group='Build';  Func='Invoke-BuildPhase09_AssembleIso' }
    [pscustomobject]@{ Id='P10';   Name='ConvertPca2023BootManager'; Group='Build';  Func='Invoke-BuildPhase10_ConvertPca2023BootManager' }
    [pscustomobject]@{ Id='P11';   Name='StaticVerify';              Group='Verify'; Func='Invoke-VerifyPhase11_StaticVerify' }
    [pscustomobject]@{ Id='P12';   Name='VerifyPca2023Readiness';    Group='Verify'; Func='Invoke-VerifyPhase12_VerifyPca2023Readiness' }
    [pscustomobject]@{ Id='P13';   Name='FinalReport';               Group='Report'; Func='Invoke-ReportPhase13_FinalReport' }
    [pscustomobject]@{ Id='P14';   Name='HyperVValidation';          Group='Verify'; Func='Invoke-VerifyPhase14_HyperVValidation' }
    [pscustomobject]@{ Id='A00';   Name='RebuildDataset';           Group='Admin';  Func='Invoke-AdminPhaseA00_RebuildDataset' }
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
#   - SSU / servicing-stack carrier: required on every serviced WIM
#   - LCU             : role-dependent. FinalLCU -> Install/Boot; a combined LCU may also be ServicingStackCarrier -> Install/Boot/WinRE
#   - DotNet          : Install only (.NET 4.x runtime KB lives in install.wim)
#   - SafeOSDU        : WinRE only (WinRE is the "Safe OS")
#   - SetupDU         : Setup binaries (sources overlay; not WIM-mounted)
#   - LanguagePack    : Install + WinRE (user-facing UI + recovery UI)
#   - LXP             : Install only (LXPs are Store apps; no WinRE)
#   - DotNet.LangPack : Install only (.NET satellite assemblies)
$Script:PatchTargetMap = @{
    # Kind -> WIM targets (Config Schema v3.0 / data-source migration). Neutral Kinds:
    'SSU'             = @('Install', 'Boot', 'WinRE')
    'LCU'             = @('Install', 'Boot')
    # Checkpoint cumulative baseline (uup-checkpoint model, 24H2+): NEVER
    # applied standalone. It is downloaded and co-located with the target
    # LCU (same folder); DISM uses the Add-WindowsPackage PackagePath
    # folder to discover and install prerequisite checkpoint MSUs only
    # when the image actually needs them. Force-applying the (older) GA
    # checkpoint onto a newer image is what broke the 2026-07-05 E2E on
    # boot.wim (0x80073712). Basis: MS Learn 'Checkpoint cumulative
    # updates and the Microsoft Update Catalog' + the per-KB DISM
    # guidance (e.g. the KB5094126 page: 'DISM will use the folder
    # specified in PackagePath to discover and install one or more
    # prerequisite MSU files as needed').
    'Checkpoint'      = @()
    # Static per-OS bridge LCU (PatchBaseline.BridgeLcu envelope, SEED):
    # raises an out-of-floor image servicing stack BEFORE the current
    # combined LCU (axis 3; prevents 0x800f0823). Routed to Install AND
    # Boot: the Server 2022 E2E measured the SAME 0x800f0823 on
    # boot.wim (surface message 'An error occurred applying the
    # Unattend.xml file from the .msu package', WARNING line carries
    # the code) once install.wim was bridged -- WinPE shares the
    # image-side floor, so the bridge must precede the target LCU
    # there too (sub-phase B0). NOT routed to WinRE: WinRE is serviced
    # by SSU + SafeOS DU, never an LCU.
    'BridgeLcu'       = @('Install', 'Boot')
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
$Script:DebugTraceCompletedFrames = [System.Collections.Generic.List[object]]::new()
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
$Script:DebugTraceJsonlBuffer     = [System.Collections.Generic.List[string]]::new()  # pre-activation buffer
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
        Steps     = ([System.Collections.Generic.List[object]]::new())
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
    $missingConfigs  = [System.Collections.Generic.List[string]]::new()
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
        Load an OS profile JSON (Config Schema v3.0 or v4.0) and resolve
        the requested language sub-profile.
    .DESCRIPTION
        Schema 4.0 is the canonical model. It separates the monthly
        servicing style, source-media prerequisites, package assets and
        servicing roles. Schema 3.0 remains accepted as a compatibility
        input so existing baselines can be migrated incrementally.

        Common fields are promoted to the returned object to preserve the
        existing single-script phase contract. Schema-4-only sections are
        attached verbatim and are $null for a v3 profile.
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

    $acceptedSchemas = @('3.0', '4.0')
    if (-not $json.Schema -or ($acceptedSchemas -notcontains [string]$json.Schema)) {
        throw ('Config {0} has Schema="{1}"; expected one of: {2}.' -f $cfgFile, $json.Schema, ($acceptedSchemas -join ', '))
    }
    if (-not $json.Common) {
        throw ('Config {0} has no Common section.' -f $cfgFile)
    }
    if (-not $json.PatchBaseline) {
        throw ('Config {0} has no PatchBaseline section.' -f $cfgFile)
    }
    if (-not $json.LanguageSpecific) {
        throw ('Config {0} has no LanguageSpecific section.' -f $cfgFile)
    }
    if (-not $json.Pca2023) {
        throw ('Config {0} has no Pca2023 block.' -f $cfgFile)
    }
    if ([string]$json.Schema -eq '4.0' -and -not $json.ServicingModel) {
        throw ('Config {0} declares Schema="4.0" but has no ServicingModel block.' -f $cfgFile)
    }

    $langNode = $json.LanguageSpecific.$OsLang
    if ($null -eq $langNode) {
        throw ('Config {0} has no LanguageSpecific entry for "{1}".' -f $cfgFile, $OsLang)
    }

    $bootPolicy = Resolve-BootWimLcuPolicyValue -RawValue $json.Common.BootWimLcuPolicy
    $installIndexes = $null
    if ($json.Common.PSObject.Properties['InstallWimIndexes']) {
        $installIndexes = $json.Common.InstallWimIndexes
    }

    $merged = [pscustomobject]@{
        Schema                    = [string]$json.Schema
        OsKey                     = $json.OsKey
        PatchModel                = $json.PatchModel
        Build                     = $json.Common.Build
        OsShortName               = $json.Common.OsShortName
        Edition                   = $json.Common.Edition
        Architecture              = $json.Common.Architecture
        WimEdition                = $json.Common.WimEdition
        InstallWimIndex           = $json.Common.InstallWimIndex
        InstallWimIndexes         = $installIndexes
        BootWimIndexes            = $json.Common.BootWimIndexes
        WinReWimPath              = $json.Common.WinReWimPath
        SupportedLanguages        = $json.Common.SupportedLanguages
        DefaultLanguage           = $json.Common.DefaultLanguage
        LCUExpandViaMum           = $json.Common.LCUExpandViaMum
        EnableInstallWimUpdate    = $json.Common.EnableInstallWimUpdate
        BootWimLcuPolicy          = $bootPolicy
        EnableWinREUpdate         = $json.Common.EnableWinREUpdate
        UpdateAllInstallWimIndexes = $(if ($json.Common.PSObject.Properties['UpdateAllInstallWimIndexes']) { [bool]$json.Common.UpdateAllInstallWimIndexes } else { $true })
        WinReDistributionPolicy   = $(if ($json.Common.PSObject.Properties['WinReDistributionPolicy']) { [string]$json.Common.WinReDistributionPolicy } else { 'ServiceOnceCopyToAllInstallIndexes' })
        BootWimFailurePolicy      = Resolve-BootWimFailurePolicyValue -RawValue $(if ($json.Common.PSObject.Properties['BootWimFailurePolicy']) { [string]$json.Common.BootWimFailurePolicy } else { 'LegacyPolicy' })
        BootWimServicingStrategy  = Resolve-BootWimServicingStrategyValue -RawValue $(if ($json.Common.PSObject.Properties['BootWimServicingStrategy']) { [string]$json.Common.BootWimServicingStrategy } else { '' }) -PackageMode $(if ($json.Common.PSObject.Properties['BootWimPackageMode']) { [string]$json.Common.BootWimPackageMode } else { 'DirectMsu' })
        Common                    = $json.Common
        ServicingModel            = $(if ($json.PSObject.Properties['ServicingModel']) { $json.ServicingModel } else { $null })
        DiscoveryPolicy           = $(if ($json.PSObject.Properties['DiscoveryPolicy']) { $json.DiscoveryPolicy } else { $null })
        ValidationPolicy          = $(if ($json.PSObject.Properties['ValidationPolicy']) { $json.ValidationPolicy } else { $null })
        Compatibility             = $(if ($json.PSObject.Properties['Compatibility']) { $json.Compatibility } else { $null })
        PatchBaseline             = $json.PatchBaseline
        Pca2023                   = $json.Pca2023
        AutoRefreshPolicy         = $json.AutoRefreshPolicy
        LanguageSpecific          = $json.LanguageSpecific
        Language                  = $langNode
        LanguageKey               = $OsLang
        Raw                       = $json
        ConfigFilePath            = $cfgFile
    }

    if ([string]$json.Schema -eq '4.0') {
        Write-Step ('Config Schema 4.0 enabled: MonthlyServicingStyle={0}; BaselineStatus={1}' -f `
            [string]$json.ServicingModel.MonthlyServicingStyle, [string]$json.PatchBaseline.Status)
    }
    return $merged
}

function Resolve-IsoSourceUrl {
    <#
    .SYNOPSIS
        Pick the final ISO download URL according to the priority
        described in SPEC Part B.4: explicit -IsoUrl first, then the
        config's LanguageSpecific.<lang>.Iso.Url.
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
    # The per-language ISO source lives at .Iso.Url.
    if ($LanguageProfile.Iso -and -not [string]::IsNullOrEmpty($LanguageProfile.Iso.Url)) {
        return $LanguageProfile.Iso.Url
    }
    throw 'No ISO URL could be resolved from explicit args or config (LanguageSpecific.<lang>.Iso.Url is empty).'
}

# ============================================================
# ISO Updater specific: patch integrity verification
# ============================================================

function ConvertTo-HexDigestString {
    <#
    .SYNOPSIS
        Normalize an expected digest (Catalog base64 or hex) to lowercase hex.
    .DESCRIPTION
        Config Schema v3.0 stores Line.Digest (SHA-1) and Line.Sha256 exactly  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        as the Microsoft Update Catalog DownloadDialog serves them: BASE64.
        That at-rest format is deliberate (raw Catalog truth; the Digest is
        the cross-surface primary key per the reference architecture memo).
        Get-FileHash yields HEX. This function is the SINGLE conversion
        boundary: expected values are normalized here, at comparison time.
        Hex input passes through unchanged so filename-embedded SHA-1 values  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        and legacy hex metadata keep working.
        Cross-verified 2026-07-02 on a live Catalog file: the base64 digest
        of KB5095966 decodes to exactly its filename-embedded SHA-1  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        (c62ffd61...543c06).
    .OUTPUTS
        System.String (lowercase hex, HashBits/4 characters)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Value,
        [Parameter(Mandatory)] [ValidateSet(160, 256)] [int]$HashBits
    )
    $v = $Value.Trim()
    $hexLen = [int]($HashBits / 4)
    if ($v -match ('^[0-9a-fA-F]{' + $hexLen + '}$')) {
        return $v.ToLower()
    }
    $bytes = $null
    try {
        $bytes = [System.Convert]::FromBase64String($v)
    } catch {
        throw ('Expected digest is neither {0}-char hex nor valid base64: "{1}"' -f $hexLen, $Value)
    }
    if ($bytes.Length -ne [int]($HashBits / 8)) {
        throw ('Expected digest base64 decodes to {0} byte(s); a {1}-bit hash needs {2}: "{3}"' -f $bytes.Length, $HashBits, [int]($HashBits / 8), $Value)
    }
    $sb = [System.Text.StringBuilder]::new($hexLen)
    foreach ($b in $bytes) { [void]$sb.Append($b.ToString('x2')) }
    return $sb.ToString()
}

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
        L2a: SHA-1 in filename matches the expected SHA-1 (if both present)  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        L2b: actual content SHA-1 matches the expected SHA-1  # psa-disable-line PSA5003 -- MS Catalog SHA-1
        L2c: actual content SHA-256 matches the expected SHA-256 (if present)
        Expected values come from the config PatchBaseline.Lines[] fields
        Digest / Sha256, stored BASE64 exactly as the Microsoft Update
        Catalog DownloadDialog serves them; ConvertTo-HexDigestString
        normalizes them to hex at this comparison boundary (the base64-vs-
        hex format gap, when hidden, failed EVERY real download
        verification -- see CHANGELOG, tag 'digest-format-boundary').
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
        $expSha1 = ConvertTo-HexDigestString -Value ([string]$ExpectedHashes['sha-1']) -HashBits 160  # psa-disable-line PSA5003 -- MS Catalog SHA-1
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
        $expSha256 = ConvertTo-HexDigestString -Value ([string]$ExpectedHashes['sha-256']) -HashBits 256
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
        $hasIntegrity = ((Get-BaselineHashValue -Line $_ -Algorithm Sha256) -or (Get-BaselineHashValue -Line $_ -Algorithm Sha1))
        $_.KbId -and $_.DownloadUrl -and $hasIntegrity
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
        $hasIntegrity = ((Get-BaselineHashValue -Line $_ -Algorithm Sha256) -or (Get-BaselineHashValue -Line $_ -Algorithm Sha1))
        $_.KbId -and $_.DownloadUrl -and $hasIntegrity
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
    # Stamp informational provenance (_meta): the script version that last
    # wrote this config and the UTC write time. Refreshed in place on every
    # write (Layer 1 only writes when a verified value actually changed, so
    # unchanged configs are not rewritten). Built with an order-stable
    # [pscustomobject] for canonical-JSON determinism.
    $metaStamp = [pscustomobject]@{
        scriptVersion = $Script:ScriptVersion
        generatedAt   = ([datetime]::UtcNow).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    if ($OsProfile.PSObject.Properties['_meta']) {
        $OsProfile._meta = $metaStamp
    } else {
        $OsProfile | Add-Member -NotePropertyName '_meta' -NotePropertyValue $metaStamp
    }

    # Persist the OS profile in canonical JSON format (SPEC Part B.23).
    # Save-CanonicalJsonFile handles all of: UTF-8 (no BOM), LF line
    # endings, 2-space indent, ": " separator, trailing newline, and
    # atomic-ish rename. Depth 32 covers the deepest known nesting in
    # PatchBaseline.Patches.
    Save-CanonicalJsonFile -InputObject $OsProfile -Path $ConfigPath -Depth 32
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
    $monthlyReleases  = [System.Collections.Generic.List[object]]::new()
    $hotpatchEntries  = [System.Collections.Generic.List[object]]::new()

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
        The b3 producer (Invoke-CatalogPatchSetRefresh) calls this to
        read the cache without re-parsing the raw Markdown on every build.
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

    $entryList = [System.Collections.Generic.List[object]]::new()
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
    $blockList = [System.Collections.Generic.List[object]]::new()
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
                Rows          = [System.Collections.Generic.List[object]]::new()
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

    $monthList = [System.Collections.Generic.List[object]]::new()
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

    $monthParsedList = [System.Collections.Generic.List[object]]::new()
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
    $headers = Get-CatalogRequestHeaders
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
    $items = [System.Collections.Generic.List[object]]::new()
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
    $headers = Get-CatalogRequestHeaders
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
    $items = [System.Collections.Generic.List[object]]::new()
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

    $scored = [System.Collections.Generic.List[object]]::new()
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

        # .NET packages: prefer the ndp<version> variant (e.g. ndp48 for
        # .NET 4.8). Matches every DotNet* Kind (Config Schema v3.0).
        if ($PatchType -like 'DotNet*' -and $DotNetVersion) {
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
# Catalog transport requests English as a best effort only. The live service can
# return a different localized result page even when Accept-Language is present.
# Therefore localized Title/Classification text is observational metadata only;
# asset selection is bound to stable KB, OS-generation, architecture, UpdateId,
# file name and digest identity. Only canonical project metadata is propagated.
$script:CatRequestLocale = 'en-US'
$script:CatAcceptLanguage = 'en-US,en;q=0.9'
$script:CatDisplayLanguagePolicy = 'canonical-project-metadata-only'
$script:CatSelectionPolicy = 'scoped-product-kb-architecture-updateid-file-digest'
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

function Get-CatalogRequestHeaders {
    [OutputType([hashtable])]
    param()
    return @{
        'User-Agent'      = $script:CatUA
        'Accept-Language' = $script:CatAcceptLanguage
        'Cache-Control'   = 'no-cache'
        'Pragma'          = 'no-cache'
    }
}

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
    if (-not (Test-Path -LiteralPath $script:CatCache)) { New-Item -ItemType Directory -Path $script:CatCache -Force | Out-Null }
    $p = Join-Path $script:CatCache $Tag
    if (Test-Path $p) { return (Get-Content -LiteralPath $p -Raw) }
    $r = Invoke-WebRequest -Uri $Url -Headers (Get-CatalogRequestHeaders) -UseBasicParsing -TimeoutSec 60
    $r.Content | Set-Content -LiteralPath $p -Encoding UTF8 -NoNewline
    Start-Sleep -Milliseconds 600
    return $r.Content
}

function Invoke-CatalogPost {
    param([string]$Url, [string]$Body, [string]$Tag)
    if (-not (Test-Path -LiteralPath $script:CatCache)) { New-Item -ItemType Directory -Path $script:CatCache -Force | Out-Null }
    $p = Join-Path $script:CatCache $Tag
    if (Test-Path $p) { return (Get-Content -LiteralPath $p -Raw) }
    $r = Invoke-WebRequest -Uri $Url -Method Post -Body $Body `
        -ContentType 'application/x-www-form-urlencoded' `
        -Headers (Get-CatalogRequestHeaders) -UseBasicParsing -TimeoutSec 60
    $r.Content | Set-Content -LiteralPath $p -Encoding UTF8 -NoNewline
    Start-Sleep -Milliseconds 600
    return $r.Content
}

function Search-Catalog {
    <#
    .SYNOPSIS
        Search Microsoft Update Catalog and return normalized rows.
    .DESCRIPTION
        Catalog has used at least two result-page anchor shapes:
          * id="<GUID>_link"
          * onclick="goToDetails(\"<GUID>\")"
        r12.01 only parsed the first shape.  The 2026-07-12 Server 2016
        run proved that this can return zero rows even though Catalog
        visibly contains the requested update.  r12.02+ parses both
        shapes and merges them by UpdateId.
    #>
    param(
        [string]$Query,
        [switch]$RefreshCache
    )
    $slug = [regex]::Replace($Query, '[^A-Za-z0-9]+', '_')
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60) }
    $tag = "search.$slug.raw.r1219.html"
    if ($RefreshCache) {
        Remove-Item -LiteralPath (Join-Path $script:CatCache $tag) -Force -ErrorAction SilentlyContinue
    }
    $html = Get-CatalogText ($script:CatSearchUrl + '?q=' + [uri]::EscapeDataString($Query)) $tag
    $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $byUid = @{}

    # Shape A: GUID_link anchor.  Accept both quote styles.
    $linkRx = [regex]::new(
        ('id\s*=\s*["''](' + $guid + ')_link["''][^>]*>(.*?)</a>'),
        'Singleline,IgnoreCase'
    )
    foreach ($m in $linkRx.Matches($html)) {
        $uid = $m.Groups[1].Value
        $byUid[$uid] = [pscustomobject]@{
            uid = $uid
            title = (Convert-HtmlToText $m.Groups[2].Value)
            products = ''
            classification = ''
            lastUpdated = ''
            version = ''
            sizeText = ''
            sizeBytes = $null
            parser = 'guid-link'
        }
    }

    # Shape B: goToDetails("GUID") onclick. This is the long-lived
    # Catalog markup and is also used by Get-UpdateIdFromCatalog.
    $detailsRx = [regex]::new(
        ('<a[^>]*onclick\s*=\s*(["'']?)goToDetails\(\s*["''](' + $guid + ')["'']\s*\)\s*;?\s*\1[^>]*>(.*?)</a>'),
        'Singleline,IgnoreCase'
    )
    foreach ($m in $detailsRx.Matches($html)) {
        $uid = $m.Groups[2].Value
        $title = Convert-HtmlToText $m.Groups[3].Value
        if (-not $byUid.ContainsKey($uid)) {
            $byUid[$uid] = [pscustomobject]@{
                uid = $uid
                title = $title
                products = ''
                classification = ''
                lastUpdated = ''
                version = ''
                sizeText = ''
                sizeBytes = $null
                parser = 'goToDetails'
            }
        } elseif (-not $byUid[$uid].title -and $title) {
            $byUid[$uid].title = $title
        }
    }

    # Enrich cells when Catalog exposes the legacy GUID_Cn_Rm ids.
    foreach ($uid in @($byUid.Keys)) {
        $row = $byUid[$uid]
        $cells = @{}
        for ($col = 0; $col -le 7; $col++) {
            $crx = [regex]::new(
                ('id\s*=\s*["'']' + [regex]::Escape($uid) + '_C' + $col + '_R\d+["''][^>]*>(.*?)</td>'),
                'Singleline,IgnoreCase'
            )
            $cm = $crx.Match($html)
            if ($cm.Success) { $cells[$col] = Convert-HtmlToText $cm.Groups[1].Value } else { $cells[$col] = '' }
        }
        # Different Catalog revisions have shifted the visible title
        # column. Never replace an anchor title with a blank cell.
        if (-not $row.title) {
            foreach ($candidateCol in @(1, 0)) {
                if ($cells[$candidateCol]) { $row.title = $cells[$candidateCol]; break }
            }
        }
        # Products/classification are normally C2/C3. These are
        # optional because exact-KB title matching remains authoritative.
        $row.products = $cells[2]
        $row.classification = $cells[3]
        $row.lastUpdated = $cells[4]
        $row.version = $cells[5]
        $row.sizeText = $cells[6]
        $smb = [regex]::Match([string]$cells[6], '(\d{4,})')
        if ($smb.Success) { $row.sizeBytes = [long]$smb.Groups[1].Value }
    }

    # Last-resort fallback to the older, separately tested parser.
    if ($byUid.Count -eq 0) {
        foreach ($item in @(Get-UpdateIdFromCatalog -KbId $Query)) {
            $byUid[[string]$item.UpdateId] = [pscustomobject]@{
                uid = [string]$item.UpdateId
                title = [string]$item.Title
                products = ''
                classification = ''
                lastUpdated = ''
                version = ''
                sizeText = ''
                sizeBytes = $null
                parser = 'legacy-goToDetails'
            }
        }
    }

    return @($byUid.Values | Sort-Object title, uid)
}


function Get-CatalogScopedElementText {
    <# Extract a Catalog detail field by stable ASP.NET control-id suffix. #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Html,
        [Parameter(Mandatory)][string[]]$IdSuffixes
    )
    foreach ($suffix in @($IdSuffixes)) {
        if ([string]::IsNullOrWhiteSpace($suffix)) { continue }
        $pattern = '<[^>]+id\s*=\s*["''][^"'']*' + [regex]::Escape($suffix) + '["''][^>]*>(.*?)</[^>]+>'
        $match = [regex]::Match($Html, $pattern, 'Singleline,IgnoreCase')
        if ($match.Success) {
            $value = Convert-HtmlToText $match.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
    }
    return ''
}

function Get-CatalogScopedLabeledText {
    <# English-label fallback. Control-id extraction remains the primary path. #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$PlainText,
        [Parameter(Mandatory)][string]$StartLabel,
        [Parameter(Mandatory)][string[]]$NextLabels
    )
    $next = @($NextLabels | ForEach-Object { [regex]::Escape([string]$_) }) -join '|'
    $pattern = [regex]::Escape($StartLabel) + '\s*(.*?)\s*(?=' + $next + '|$)'
    $match = [regex]::Match($PlainText, $pattern, 'Singleline,IgnoreCase')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ''
}

function Get-CatalogScopedDetail {
    <#
    .SYNOPSIS
        Read the official Catalog Update Details page for one UpdateId.
    .DESCRIPTION
        Search-result titles are presentation metadata and can be localized.
        The ScopedView endpoint supplies the row's product scope, KB identity,
        architecture and UpdateId. Raw HTML is cached only under WorkRoot.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$UpdateId,
        [switch]$RefreshCache
    )
    $tag = 'scoped.{0}.raw.r1219.html' -f $UpdateId.ToLowerInvariant()
    if ($RefreshCache) {
        Remove-Item -LiteralPath (Join-Path $script:CatCache $tag) -Force -ErrorAction SilentlyContinue
    }
    $url = $script:CatScopedUrl + '?updateid=' + [uri]::EscapeDataString($UpdateId)
    $html = Get-CatalogText -Url $url -Tag $tag
    $plain = Convert-HtmlToText $html

    $detailUpdateId = Get-CatalogScopedElementText -Html $html -IdSuffixes @('labelUpdateID','labelUpdateId','updateID')
    if ([string]::IsNullOrWhiteSpace($detailUpdateId)) {
        $m = [regex]::Match($plain, '(?i)Update\s*ID\s*:\s*([0-9a-f-]{36})')
        if ($m.Success) { $detailUpdateId = $m.Groups[1].Value }
    }
    # Do not substitute the requested UpdateId when the response body does not
    # expose its own identity. A missing/changed ScopedView shape must fail
    # closed instead of making UpdateId verification tautological.

    $architecture = Get-CatalogScopedElementText -Html $html -IdSuffixes @('labelArchitecture','architecture')
    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = Get-CatalogScopedLabeledText -PlainText $plain -StartLabel 'Architecture:' -NextLabels @('Classification:','Supported products:')
    }
    $products = Get-CatalogScopedElementText -Html $html -IdSuffixes @('labelSupportedProducts','supportedProducts')
    if ([string]::IsNullOrWhiteSpace($products)) {
        $products = Get-CatalogScopedLabeledText -PlainText $plain -StartLabel 'Supported products:' -NextLabels @('Supported languages:','MSRC Number:')
    }
    $kbText = Get-CatalogScopedElementText -Html $html -IdSuffixes @('labelKbArticleNumbers','labelKBArticleNumbers','kbArticleNumbers')
    if ([string]::IsNullOrWhiteSpace($kbText)) {
        $kbText = Get-CatalogScopedLabeledText -PlainText $plain -StartLabel 'KB article numbers:' -NextLabels @('More information:','Support Url:')
    }
    $title = Get-CatalogScopedElementText -Html $html -IdSuffixes @('titleText','labelTitle','updateTitle')
    if ([string]::IsNullOrWhiteSpace($title)) {
        $m = [regex]::Match($plain, '(?i)Update Details\s+(.*?)\s+Last Modified:')
        if ($m.Success) { $title = $m.Groups[1].Value.Trim() }
    }

    $kbNumbers = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches([string]$kbText, '\b\d{6,8}\b')) {
        if (-not $kbNumbers.Contains($m.Value)) { $kbNumbers.Add($m.Value) }
    }
    return [pscustomobject][ordered]@{
        RequestedUpdateId = $UpdateId
        UpdateId = $detailUpdateId.Trim()
        Architecture = $architecture.Trim()
        SupportedProducts = $products.Trim()
        KbArticleNumbers = @($kbNumbers.ToArray())
        Title = $title.Trim()
        ParseBasis = $(if ($detailUpdateId -and $products -and $kbNumbers.Count -gt 0) { 'ScopedViewControlIdOrLabel' } else { 'ScopedViewIncomplete' })
        RawSha256 = Get-TextFingerprint -Text $html
        SourceUrl = $url
    }
}

function Test-CatalogProductScope {
    [OutputType([bool])]
    param(
        [AllowEmptyString()][string]$Products,
        [Parameter(Mandatory)]$Rule,
        [switch]$AllowMissing
    )
    if ([string]::IsNullOrWhiteSpace($Products)) { return [bool]$AllowMissing }
    foreach ($token in @($Rule.ProductTokens)) {
        if ($token -and $Products.IndexOf([string]$token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    }
    foreach ($token in @($Rule.ProductRejectTokens)) {
        if ($token -and $Products.IndexOf([string]$token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }
    }
    return $true
}

function Test-CatalogScopedDetailAgainstRule {
    <# Return explicit verification evidence rather than a bare Boolean. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Detail,
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)]$Rule
    )
    $failures = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace([string]$Detail.UpdateId) -or
        [string]::IsNullOrWhiteSpace([string]$Detail.SupportedProducts) -or
        @($Detail.KbArticleNumbers).Count -eq 0) {
        $failures.Add('ScopedIdentityIncomplete')
    }
    if (-not [string]::Equals([string]$Detail.UpdateId, [string]$Row.uid, [System.StringComparison]::OrdinalIgnoreCase)) {
        $failures.Add('UpdateIdMismatch')
    }
    $kbDigits = ([string]$Rule.KbId) -replace '(?i)^KB',''
    if (@($Detail.KbArticleNumbers) -notcontains $kbDigits) { $failures.Add('KbArticleMismatch') }
    if (-not (Test-CatalogProductScope -Products ([string]$Detail.SupportedProducts) -Rule $Rule)) {
        $failures.Add('ProductScopeMismatch')
    }
    $architecture = ([string]$Detail.Architecture).Trim()
    $architectureBasis = 'ScopedView'
    if ([string]::IsNullOrWhiteSpace($architecture) -or $architecture -match '^(?i)n/?a$') {
        $architectureBasis = 'SearchTitleAndDownloadFile'
    } elseif ($architecture -notmatch '^(?i)(AMD64|x64)$') {
        $failures.Add('ArchitectureMismatch')
    }
    return [pscustomobject][ordered]@{
        Verified = [bool]($failures.Count -eq 0)
        Failures = @($failures.ToArray())
        UpdateIdVerified = [bool](-not ($failures.Contains('UpdateIdMismatch')))
        KbVerified = [bool](-not ($failures.Contains('KbArticleMismatch')))
        ProductVerified = [bool](-not ($failures.Contains('ProductScopeMismatch')))
        ArchitectureVerified = [bool](-not ($failures.Contains('ArchitectureMismatch')))
        ArchitectureBasis = $architectureBasis
    }
}

function Resolve-CatalogDownload {
    param(
        [string]$Uid,
        [switch]$RefreshCache
    )
    $body = 'updateIDs=[{"size":0,"languages":"","uidInfo":"' + $Uid + '","updateID":"' + $Uid + '"}]' +
            '&updateIDsBlockedForImport=&wsusApiPresent=&contentImport=&sku=&serverName=&ssl=&portNumber=&version='
    $tag = "dl.$($Uid.Substring(0,8)).raw.r1219.html"
    if ($RefreshCache) {
        Remove-Item -LiteralPath (Join-Path $script:CatCache $tag) -Force -ErrorAction SilentlyContinue
    }
    $html = Invoke-CatalogPost $script:CatDownloadUrl $body $tag
    $files = @{}

    # Response shape A: files[N].field = 'value'
    $rxA = [regex]::new("files\[(\d+)\]\.(\w+)\s*=\s*'([^']*)'", 'IgnoreCase')
    foreach ($m in $rxA.Matches($html)) {
        $i = [int]$m.Groups[1].Value; $field = $m.Groups[2].Value; $val = $m.Groups[3].Value
        if (-not $files.ContainsKey($i)) { $files[$i] = @{} }
        $files[$i][$field] = $val
    }

    # Response shape B: downloadInformation[N].files[M].field
    $rxB = [regex]::new("downloadInformation\[\d+\]\.files\[(\d+)\]\.(\w+)\s*=\s*'([^']*)'", 'IgnoreCase')
    foreach ($m in $rxB.Matches($html)) {
        $i = [int]$m.Groups[1].Value; $field = $m.Groups[2].Value; $val = $m.Groups[3].Value
        if (-not $files.ContainsKey($i)) { $files[$i] = @{} }
        $files[$i][$field] = $val
    }

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($i in ($files.Keys | Sort-Object)) {
        $f = $files[$i]
        $url = $(if ($f.ContainsKey('url')) { [string]$f['url'] } else { '' })
        $fileName = $(if ($f.ContainsKey('fileName')) { [string]$f['fileName'] } else { '' })
        if (-not $fileName -and $url) {
            try { $fileName = [System.IO.Path]::GetFileName(([uri]$url).AbsolutePath) } catch { $fileName = '' }
        }
        if ($url) {
            $out.Add([pscustomobject]@{
                idx = $i
                fileName = $fileName
                url      = $url
                digest   = $(if ($f.ContainsKey('digest')) { $f['digest'] } else { '' })
                sha256   = $(if ($f.ContainsKey('sha256')) { $f['sha256'] } else { '' })
                enTitle  = $(if ($f.ContainsKey('enTitle')) { $f['enTitle'] } else { '' })
                parser   = 'DownloadDialog'
            }) | Out-Null
        }
    }

    # Last-resort fallback uses the older DownloadDialog parser, which
    # derives FileName from each URL. Hashes are calculated after download.
    if ($out.Count -eq 0) {
        foreach ($legacy in @(Get-DownloadLinkFromCatalog -UpdateId $Uid)) {
            $out.Add([pscustomobject]@{
                idx = $out.Count
                fileName = [string]$legacy.FileName
                url      = [string]$legacy.Url
                digest   = ''
                sha256   = ''
                enTitle  = ''
                parser   = 'legacy-downloadInformation'
            }) | Out-Null
        }
    }
    return @($out.ToArray())
}

function Get-CatalogIdentityRule {
    <#
    .SYNOPSIS
        Return stable package-identity rules and separate canonical display metadata.
    .DESCRIPTION
        Microsoft Update Catalog Title and Classification cells are localized and
        are not a trustworthy package-identity boundary. StableTitleTokens contain
        only locale-invariant OS/version markers. TitleTokens and Classification
        are retained solely to assess whether display metadata is canonical EN/JA.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Patch)

    $type = Get-PatchEntryType -Patch $Patch
    $kb = [string]$Patch.KbId
    $osTitle = switch ($Script:OsVersion) {
        'Server2016' { 'Windows Server 2016' }
        'Server2019' { 'Windows Server 2019' }
        'Server2022' { 'Microsoft server operating system version 21H2' }
        'Server2025' { 'Microsoft server operating system version 24H2' }
        default      { '' }
    }
    $osProduct = switch ($Script:OsVersion) {
        'Server2016' { 'Windows Server 2016' }
        'Server2019' { 'Windows Server 2019' }
        'Server2022' { 'Microsoft Server operating system-21H2' }
        'Server2025' { 'Microsoft Server Operating System-24H2' }
        default      { '' }
    }
    $duTitle = switch ($Script:OsVersion) {
        'Server2016' { 'Windows 10 Version 1607' }
        'Server2019' { 'Windows 10 Version 1809' }
        'Server2022' { 'Microsoft server operating system version 21H2' }
        'Server2025' { 'Microsoft server operating system version 24H2' }
        default      { '' }
    }
    $stableOsToken = switch ($Script:OsVersion) {
        'Server2016' { 'Windows Server 2016' }
        'Server2019' { 'Windows Server 2019' }
        'Server2022' { '21H2' }
        'Server2025' { '24H2' }
        default      { '' }
    }
    $stableDuToken = switch ($Script:OsVersion) {
        'Server2016' { '1607' }
        'Server2019' { '1809' }
        'Server2022' { '21H2' }
        'Server2025' { '24H2' }
        default      { '' }
    }

    $titleTokens = [System.Collections.Generic.List[string]]::new()
    $stableTitleTokens = [System.Collections.Generic.List[string]]::new()
    $productTokens = [System.Collections.Generic.List[string]]::new()
    $productReject = [System.Collections.Generic.List[string]]::new()
    $classification = ''
    $expectedExtension = '.msu'

    switch ($type) {
        'SafeOSDU' {
            if ($duTitle) { $titleTokens.Add($duTitle) }
            $titleTokens.Add('Dynamic Update')
            if ($stableDuToken) { $stableTitleTokens.Add($stableDuToken) }
            $productTokens.Add('Windows Safe OS Dynamic Update')
            $classification = 'Critical Updates'
            $expectedExtension = '.cab'
        }
        'SetupDU' {
            if ($duTitle) { $titleTokens.Add($duTitle) }
            $titleTokens.Add('Dynamic Update')
            if ($stableDuToken) { $stableTitleTokens.Add($stableDuToken) }
            $productTokens.Add('Windows 10 and later Dynamic Update')
            $productReject.Add('Windows Safe OS Dynamic Update')
            $classification = 'Critical Updates'
            $expectedExtension = '.cab'
        }
        'DotNet' {
            if ($osTitle) { $titleTokens.Add($osTitle) }
            $titleTokens.Add('.NET Framework')
            if ($stableOsToken) { $stableTitleTokens.Add($stableOsToken) }
            $stableTitleTokens.Add('.NET Framework')
            if ($osProduct) { $productTokens.Add($osProduct) }
            $classification = 'Security Updates'
        }
        'LCU' {
            if ($osTitle) { $titleTokens.Add($osTitle) }
            $titleTokens.Add('Cumulative Update')
            if ($stableOsToken) { $stableTitleTokens.Add($stableOsToken) }
            if ($osProduct) { $productTokens.Add($osProduct) }
            $classification = 'Security Updates'
        }
        'BridgeLcu' {
            if ($osTitle) { $titleTokens.Add($osTitle) }
            $titleTokens.Add('Cumulative Update')
            if ($stableOsToken) { $stableTitleTokens.Add($stableOsToken) }
            if ($osProduct) { $productTokens.Add($osProduct) }
            $classification = 'Security Updates'
        }
        'Checkpoint' {
            if ($osTitle) { $titleTokens.Add($osTitle) }
            $titleTokens.Add('Cumulative Update')
            if ($stableOsToken) { $stableTitleTokens.Add($stableOsToken) }
            if ($osProduct) { $productTokens.Add($osProduct) }
            $classification = 'Security Updates'
        }
        'SSU' {
            if ($osTitle) { $titleTokens.Add($osTitle) }
            if ($stableOsToken) { $stableTitleTokens.Add($stableOsToken) }
            if ($kb -eq 'KB4132216') {
                $titleTokens.Add('Update')
                $classification = 'Critical Updates'
            } else {
                $titleTokens.Add('Servicing Stack Update')
                $classification = 'Security Updates'
            }
            if ($osProduct) { $productTokens.Add($osProduct) }
        }
        default {
            if ($osTitle) { $titleTokens.Add($osTitle) }
            if ($stableOsToken) { $stableTitleTokens.Add($stableOsToken) }
            if ($osProduct) { $productTokens.Add($osProduct) }
        }
    }

    $canonicalTitle = ''
    if ($Patch.PSObject.Properties['Title']) { $canonicalTitle = [string]$Patch.Title }
    if ([string]::IsNullOrWhiteSpace($canonicalTitle)) {
        $canonicalTitle = '{0} {1} for {2} x64' -f $type, $kb, $Script:OsVersion
    }
    $canonicalProducts = [System.Collections.Generic.List[string]]::new()
    if ($Patch.PSObject.Properties['Products'] -and $Patch.Products) {
        foreach ($value in @($Patch.Products)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $canonicalProducts.Add([string]$value) }
        }
    }
    if ($canonicalProducts.Count -eq 0) {
        foreach ($value in @($productTokens.ToArray())) { $canonicalProducts.Add([string]$value) }
    }

    return [pscustomobject]@{
        Type = $type
        KbId = $kb
        TitleTokens = @($titleTokens.ToArray())
        StableTitleTokens = @($stableTitleTokens.ToArray())
        ProductTokens = @($productTokens.ToArray())
        ProductRejectTokens = @($productReject.ToArray())
        Classification = $classification
        CanonicalTitle = $canonicalTitle
        CanonicalProducts = @($canonicalProducts.ToArray())
        CanonicalClassification = $classification
        ExpectedExtension = $expectedExtension
    }
}

function Get-CatalogSemanticAliases {
    <# Canonical English/Japanese display aliases. Never used as asset identity. #>
    [OutputType([string[]])]
    param([AllowEmptyString()][string]$Token)

    switch ($Token.Trim()) {
        'Cumulative Update' {
            return [string[]]@('Cumulative Update','累積更新プログラム','累積更新')
        }
        'Servicing Stack Update' {
            return [string[]]@('Servicing Stack Update','サービス スタック更新プログラム','サービススタック更新プログラム')
        }
        'Dynamic Update' {
            return [string[]]@('Dynamic Update','動的更新プログラム')
        }
        'Security Updates' {
            return [string[]]@('Security Updates','セキュリティ更新プログラム','セキュリティ問題の修正プログラム')
        }
        'Critical Updates' {
            return [string[]]@('Critical Updates','重要な更新プログラム')
        }
        'Update' {
            return [string[]]@('Update','更新プログラム')
        }
        default { return [string[]]@($Token) }
    }
}

function Test-CatalogSemanticContains {
    [OutputType([bool])]
    param(
        [AllowEmptyString()][string]$Text,
        [AllowEmptyString()][string]$CanonicalToken
    )
    if ([string]::IsNullOrWhiteSpace($CanonicalToken)) { return $true }
    foreach ($alias in @(Get-CatalogSemanticAliases -Token $CanonicalToken)) {
        if (-not [string]::IsNullOrWhiteSpace($alias) -and
            $Text.IndexOf($alias, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Test-CatalogSemanticEquals {
    [OutputType([bool])]
    param(
        [AllowEmptyString()][string]$Text,
        [AllowEmptyString()][string]$CanonicalToken
    )
    if ([string]::IsNullOrWhiteSpace($CanonicalToken)) { return $true }
    $actual = $Text.Trim()
    foreach ($alias in @(Get-CatalogSemanticAliases -Token $CanonicalToken)) {
        if ([string]::Equals($actual, $alias, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-TextFingerprint {
    [OutputType([string])]
    param([AllowEmptyString()][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-CatalogDisplayMetadataAssessment {
    <#
    .SYNOPSIS
        Assess display metadata without allowing it to influence package identity.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)]$Rule
    )
    $title = [string]$Row.title
    $products = [string]$Row.products
    $classification = [string]$Row.classification
    $titleCanonical = $true
    foreach ($token in @($Rule.TitleTokens)) {
        if ($token -and -not (Test-CatalogSemanticContains -Text $title -CanonicalToken ([string]$token))) {
            $titleCanonical = $false
            break
        }
    }
    $classificationCanonical = $true
    if ($Rule.Classification) {
        $classificationCanonical = -not [string]::IsNullOrWhiteSpace($classification) -and
            (Test-CatalogSemanticEquals -Text $classification -CanonicalToken ([string]$Rule.Classification))
    }
    $productsCanonical = $true
    if (-not [string]::IsNullOrWhiteSpace($products)) {
        foreach ($token in @($Rule.ProductTokens)) {
            if ($token -and $products.IndexOf([string]$token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                $productsCanonical = $false
                break
            }
        }
    }
    $status = $(if ($titleCanonical -and $classificationCanonical -and $productsCanonical) { 'CanonicalEnOrJa' } else { 'LocalizedOrUnknownIsolated' })
    return [pscustomobject][ordered]@{
        Status = $status
        Canonical = [bool]($status -eq 'CanonicalEnOrJa')
        TitleCanonical = [bool]$titleCanonical
        ClassificationCanonical = [bool]$classificationCanonical
        ProductsCanonical = [bool]$productsCanonical
        TitleSha256 = Get-TextFingerprint -Text $title
        ClassificationSha256 = Get-TextFingerprint -Text $classification
        ProductsSha256 = Get-TextFingerprint -Text $products
    }
}

function Test-CatalogRowAgainstRule {
    <#
    .SYNOPSIS
        Coarse search-row filter. ScopedView performs the authoritative check.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)]$Rule
    )
    $title = [string]$Row.title
    $products = [string]$Row.products

    if ($title -notmatch '(?i)x64' -or $title -match '(?i)arm64|x86') { return $false }
    if ($Rule.KbId -and $title -notmatch [regex]::Escape([string]$Rule.KbId)) { return $false }
    foreach ($token in @($Rule.StableTitleTokens)) {
        if ($token -and $title.IndexOf([string]$token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    }
    # Catalog product taxonomy is a stronger discriminator than localized title
    # prose. Missing cells are allowed here only because ScopedView is mandatory.
    if (-not (Test-CatalogProductScope -Products $products -Rule $Rule -AllowMissing)) { return $false }
    return $true
}

function Get-CatalogRowsForResolvedPatch {
    <#
    .SYNOPSIS
        Resolve an exact KB through Search + authoritative ScopedView identity.
    .DESCRIPTION
        Search-result display text may be localized. Candidate rows are therefore
        verified against each row's official Update Details page using UpdateId,
        KB article number, product scope and architecture. The DownloadDialog file
        identity is checked later. This prevents Server 2025 checkpoint KBs that
        share 24H2/x64/file bytes with Windows 11 from being misclassified.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]$Patch,
        [switch]$RefreshCache
    )

    $kb = [string]$Patch.KbId
    if ([string]::IsNullOrWhiteSpace($kb)) { return @() }
    $rows = @(Search-Catalog -Query $kb -RefreshCache:$RefreshCache)
    if ($rows.Count -eq 0) { return @() }

    $rule = Get-CatalogIdentityRule -Patch $Patch
    $coarse = @($rows | Where-Object { Test-CatalogRowAgainstRule -Row $_ -Rule $rule })
    if ($coarse.Count -eq 0) {
        $observed = @($rows | ForEach-Object {
            '[updateId={0};titleSha256={1};productsSha256={2}]' -f
                $_.uid, (Get-TextFingerprint -Text ([string]$_.title)),
                (Get-TextFingerprint -Text ([string]$_.products))
        }) -join ' | '
        throw ('Microsoft Update Catalog returned no coarse identity row for {0}/{1} on {2}. Observed fingerprints: {3}' -f
            $rule.Type, $rule.KbId, $Script:OsVersion, $observed)
    }

    $configuredUpdateId = ''
    if ($Patch.PSObject.Properties['UpdateId']) { $configuredUpdateId = [string]$Patch.UpdateId }
    if (-not [string]::IsNullOrWhiteSpace($configuredUpdateId)) {
        $exact = @($coarse | Where-Object { [string]::Equals([string]$_.uid, $configuredUpdateId, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($exact.Count -ne 1) {
            throw ('Configured Catalog UpdateId {0} did not identify exactly one coarse row for {1}/{2}; matches={3}. Refusing fallback to another row.' -f
                $configuredUpdateId, $rule.Type, $rule.KbId, $exact.Count)
        }
        $coarse = $exact
    }

    $verified = [System.Collections.Generic.List[object]]::new()
    $rejected = [System.Collections.Generic.List[string]]::new()
    foreach ($row in @($coarse)) {
        try {
            $detail = Get-CatalogScopedDetail -UpdateId ([string]$row.uid) -RefreshCache:$RefreshCache
            $assessment = Test-CatalogScopedDetailAgainstRule -Detail $detail -Row $row -Rule $rule
            if (-not $assessment.Verified) {
                $rejected.Add(('[updateId={0};failures={1};detailSha256={2}]' -f $row.uid, (@($assessment.Failures) -join ','), $detail.RawSha256))
                continue
            }
            $row | Add-Member -NotePropertyName ScopedIdentityVerified -NotePropertyValue $true -Force
            $row | Add-Member -NotePropertyName ScopedIdentityBasis -NotePropertyValue ('UpdateId+KB+Product+{0}' -f $assessment.ArchitectureBasis) -Force
            $row | Add-Member -NotePropertyName ScopedArchitecture -NotePropertyValue ([string]$detail.Architecture) -Force
            $row | Add-Member -NotePropertyName ScopedRawSha256 -NotePropertyValue ([string]$detail.RawSha256) -Force
            $row | Add-Member -NotePropertyName ScopedParseBasis -NotePropertyValue ([string]$detail.ParseBasis) -Force
            $verified.Add($row)
        } catch {
            $rejected.Add(('[updateId={0};errorSha256={1}]' -f $row.uid, (Get-TextFingerprint -Text $_.Exception.Message)))
        }
    }
    if ($verified.Count -eq 0) {
        throw ('Microsoft Update Catalog ScopedView identity verification rejected every candidate for {0}/{1} on {2}. Rejections: {3}' -f
            $rule.Type, $rule.KbId, $Script:OsVersion, (@($rejected.ToArray()) -join ' | '))
    }
    return @($verified.ToArray() | Sort-Object lastUpdated, version -Descending)
}

function Test-IsCatalogPlaceholderFileName {
    <#
    .SYNOPSIS
        Identify a non-authoritative KB-only placeholder such as KB5101007.msu.
    .DESCRIPTION
        r12.19 synthesized these names for metadata-only monthly selectors.  The
        stable-identity selector then treated the placeholder as an exact
        configured filename and rejected the real Catalog asset.  A KB-only
        placeholder is never a Catalog identity and must not constrain P04.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()][string]$FileName,
        [AllowEmptyString()][string]$KbId = ''
    )
    if ([string]::IsNullOrWhiteSpace($FileName)) { return $false }
    $leaf = [System.IO.Path]::GetFileName($FileName).Trim()
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($KbId)) {
        $normalizedKb = $KbId.Trim().ToUpperInvariant()
        if ($normalizedKb -notmatch '^KB\d{6,8}$') { return $false }
        return ($leaf -match ('^(?i){0}\.(msu|cab)$' -f [regex]::Escape($normalizedKb)))
    }
    return ($leaf -match '^(?i)KB\d{6,8}\.(msu|cab)$')
}

function Get-PatchConfiguredCatalogIdentity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)]$Patch)

    $updateId = $(if ($Patch.PSObject.Properties['UpdateId']) { [string]$Patch.UpdateId } else { '' })
    $fileName = $(if ($Patch.PSObject.Properties['FileName']) { [string]$Patch.FileName } else { '' })
    $metadataOnly = [bool]($Patch.PSObject.Properties['IsMetadataOnly'] -and $Patch.IsMetadataOnly)
    $kbId = $(if ($Patch.PSObject.Properties['KbId']) { [string]$Patch.KbId } else { '' })
    if ($metadataOnly -and (Test-IsCatalogPlaceholderFileName -FileName $fileName -KbId $kbId)) {
        $fileName = ''
    }
    # LocalPath is a valid exact constraint only after an asset has been
    # explicitly configured or resolved.  Never promote an unresolved
    # metadata-only landing path into a Catalog filename constraint.
    if ([string]::IsNullOrWhiteSpace($fileName) -and -not $metadataOnly -and $Patch.PSObject.Properties['LocalPath']) {
        $localLeaf = [System.IO.Path]::GetFileName([string]$Patch.LocalPath)
        if (-not (Test-IsCatalogPlaceholderFileName -FileName $localLeaf -KbId $kbId)) {
            $fileName = $localLeaf
        }
    }
    $sha1 = ''
    $sha256 = ''
    if ($Patch.PSObject.Properties['ExpectedHashes'] -and $Patch.ExpectedHashes) {
        $h = $Patch.ExpectedHashes
        if ($h -is [System.Collections.IDictionary]) {
            if ($h.Contains('sha-1')) { $sha1 = [string]$h['sha-1'] }
            if ($h.Contains('sha-256')) { $sha256 = [string]$h['sha-256'] }
        } else {
            if ($h.PSObject.Properties['sha-1']) { $sha1 = [string]$h.'sha-1' }
            if ($h.PSObject.Properties['sha-256']) { $sha256 = [string]$h.'sha-256' }
        }
    }
    if ([string]::IsNullOrWhiteSpace($sha1) -and $Patch.PSObject.Properties['Digest']) { $sha1 = [string]$Patch.Digest }
    if ([string]::IsNullOrWhiteSpace($sha256) -and $Patch.PSObject.Properties['Sha256']) { $sha256 = [string]$Patch.Sha256 }
    return [pscustomobject][ordered]@{
        UpdateId = $updateId
        FileName = $fileName
        Sha1 = $sha1
        Sha256 = $sha256
    }
}

function Select-CatalogCandidateAsset {
    <# Pure selector used by P04 and deterministic regression fixtures. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Patch,
        [Parameter(Mandatory)][object[]]$Candidates,
        [switch]$AllowSha256Refresh
    )
    $pool = @($Candidates)
    if ($pool.Count -eq 0) { throw 'No Catalog row/file candidates were supplied.' }
    $identity = Get-PatchConfiguredCatalogIdentity -Patch $Patch
    $basis = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($identity.UpdateId)) {
        $m = @($pool | Where-Object { [string]::Equals([string]$_.Row.uid, $identity.UpdateId, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($m.Count -eq 0) { throw ('Configured Catalog UpdateId was not present in verified candidates: {0}' -f $identity.UpdateId) }
        $pool = $m; $basis.Add('ConfiguredUpdateId')
    }
    if (-not [string]::IsNullOrWhiteSpace($identity.FileName)) {
        $m = @($pool | Where-Object { [string]::Equals([string]$_.File.fileName, $identity.FileName, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($m.Count -eq 0) { throw ('Configured Catalog file name was not present in verified candidates: {0}' -f $identity.FileName) }
        $pool = $m; $basis.Add('ConfiguredFileName')
    }
    if (-not [string]::IsNullOrWhiteSpace($identity.Sha1)) {
        $m = @($pool | Where-Object { [string]::Equals([string]$_.File.digest, $identity.Sha1, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($m.Count -eq 0) { throw ('Configured Catalog SHA-1 was not present in verified candidates: {0}' -f $identity.Sha1) }
        $pool = $m; $basis.Add('ConfiguredSha1')
    }
    if (-not [string]::IsNullOrWhiteSpace($identity.Sha256)) {
        $m = @($pool | Where-Object { [string]::Equals([string]$_.File.sha256, $identity.Sha256, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($m.Count -eq 0) {
            if (-not $AllowSha256Refresh) {
                throw ('Configured Catalog SHA-256 was not present in verified candidates: {0}' -f $identity.Sha256)
            }
            # Mutable ResearchCandidate/Discovered/Resolved baselines may carry
            # a stale transport digest. Keep the stable UpdateId/file/SHA-1
            # constraints, select exactly one scoped asset, then rehydrate the
            # SHA-256 below. Frozen/Approved baselines never take this path.
            $basis.Add('ConfiguredSha256StaleAllowed')
        } else {
            $pool = $m; $basis.Add('ConfiguredSha256')
        }
    }
    if ($pool.Count -eq 1) {
        if ($basis.Count -eq 0) { $basis.Add('SingleStableCandidate') }
        if (-not $pool[0].Row.PSObject.Properties['ScopedIdentityVerified'] -or -not [bool]$pool[0].Row.ScopedIdentityVerified) {
            throw 'Selected Catalog candidate did not carry successful ScopedView identity verification.'
        }
        $basis.Add('ScopedViewIdentity')
    }
    if ($pool.Count -ne 1) {
        $observed = @($pool | ForEach-Object { '[updateId={0};file={1}]' -f $_.Row.uid, $_.File.fileName }) -join ' | '
        throw ('Catalog stable-identity selection remained ambiguous ({0} candidates): {1}' -f $pool.Count, $observed)
    }
    return [pscustomobject][ordered]@{
        Row = $pool[0].Row
        File = $pool[0].File
        SelectionBasis = ($basis -join '+')
    }
}

function Get-CatalogIdentityRefreshDecision {
    <#
    .SYNOPSIS
        Decide whether Catalog transport/file identity may be rehydrated for
        an already-selected KB.
    .DESCRIPTION
        -UseBaselineOnly pins the selected KB set and disables monthly
        replacement. It does not turn a ResearchCandidate into an immutable
        release. ResearchCandidate/Discovered/Resolved baselines may refresh
        missing or stale Catalog file identity in memory. Frozen/Approved
        baselines remain immutable and fail on any digest change.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyString()][string]$BaselineStatus = '',
        [bool]$UseBaselineOnly
    )
    $status = $BaselineStatus.Trim()
    $mutable = $status -in @('', 'ResearchCandidate', 'Discovered', 'Resolved')
    return [pscustomobject][ordered]@{
        BaselineStatus       = $status
        UseBaselineOnly      = [bool]$UseBaselineOnly
        KbIdentityPinned     = [bool]$UseBaselineOnly
        AllowIdentityRefresh = [bool]$mutable
        Mode                 = $(if ($mutable) { 'MutableCandidateAssetRehydration' } else { 'ImmutableReleaseIdentity' })
    }
}

function Resolve-ResolvedPatchAssetFromCatalog {
    <#
    .SYNOPSIS
        Mutate one runtime ResolvedPatch with the current Catalog URL/file
        identity for its already-selected KB.
    .NOTES
        Safe under -UseBaselineOnly: the KB is never changed. In strict
        baseline mode a configured asset is resolved only when its URL/file
        identity is missing. Mutable ResearchCandidate asset identity may be
        rehydrated with an explicit warning; Frozen/Approved identity is never
        rewritten.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]$Patch,
        [switch]$Force,
        [switch]$RefreshCache
    )

    if (-not $Force -and -not ($Patch.PSObject.Properties['IsMetadataOnly'] -and $Patch.IsMetadataOnly)) {
        return $false
    }
    $kb = [string]$Patch.KbId
    $type = Get-PatchEntryType -Patch $Patch
    $rule = Get-CatalogIdentityRule -Patch $Patch
    $rows = @(Get-CatalogRowsForResolvedPatch -Patch $Patch -RefreshCache:$RefreshCache)
    if ($rows.Count -eq 0) {
        throw ('Microsoft Update Catalog returned no stable x64 row for {0}/{1} on {2}.' -f $type, $kb, $Script:OsVersion)
    }

    $candidateAssets = [System.Collections.Generic.List[object]]::new()
    foreach ($candidateRow in @($rows)) {
        $candidateFiles = @(Resolve-CatalogDownload -Uid ([string]$candidateRow.uid) -RefreshCache:$RefreshCache)
        $kbDigits = $kb -replace '(?i)^KB',''
        $fileCandidates = @($candidateFiles | Where-Object {
            $fn = ([string]$_.fileName).ToLowerInvariant()
            $fn -match 'x64' -and $fn -match [regex]::Escape($kbDigits) -and
            $fn -notmatch 'express|delta|psf|pkgproperties|metadata'
        })
        $preferred = @($fileCandidates | Where-Object {
            ([string]$_.fileName).ToLowerInvariant().EndsWith(([string]$rule.ExpectedExtension).ToLowerInvariant())
        })
        if ($preferred.Count -eq 0 -and $fileCandidates.Count -gt 0) {
            throw ('Catalog DownloadDialog returned KB/x64 files for {0}/{1}, but none had the required extension {2}. Refusing extension fallback.' -f
                $rule.Type, $rule.KbId, $rule.ExpectedExtension)
        }
        foreach ($candidateFile in @($preferred)) {
            $candidateAssets.Add([pscustomobject]@{ Row = $candidateRow; File = $candidateFile }) | Out-Null
        }
    }
    if ($candidateAssets.Count -eq 0) {
        $ids = @($rows | ForEach-Object { [string]$_.uid }) -join ', '
        throw ('Catalog DownloadDialog returned no matching {0} x64 asset for {1}/{2}; row UpdateIds: {3}' -f
            $rule.ExpectedExtension, $type, $kb, $ids)
    }
    # Decide mutability before candidate selection. r12.24 performed this
    # after Select-CatalogCandidateAsset, so a stale SHA-256 on a mutable
    # ResearchCandidate failed before the documented rehydration path ran.
    $baselineStatus = ''
    if ($Script:OsProfile -and $Script:OsProfile.PatchBaseline -and $Script:OsProfile.PatchBaseline.PSObject.Properties['Status']) {
        $baselineStatus = [string]$Script:OsProfile.PatchBaseline.Status
    }
    $identityDecision = Get-CatalogIdentityRefreshDecision `
        -BaselineStatus $baselineStatus `
        -UseBaselineOnly ([bool]$Script:UseBaselineOnly)
    $allowIdentityRefresh = [bool]$identityDecision.AllowIdentityRefresh
    $selectionParameters = @{
        Patch = $Patch
        Candidates = @($candidateAssets.ToArray())
        AllowSha256Refresh = $allowIdentityRefresh
    }
    $selection = Select-CatalogCandidateAsset @selectionParameters
    $row = $selection.Row
    $file = $selection.File
    $displayAssessment = Get-CatalogDisplayMetadataAssessment -Row $row -Rule $rule
    $canonicalProductsText = @($rule.CanonicalProducts) -join ', '
    $parserName = ''
    if ($row.PSObject.Properties['parser']) { $parserName = [string]$row.parser }
    Write-Step ('Catalog row resolved: {0}/{1} UpdateId={2} parser={3} selection={4} displayMetadata={5} classification={6} products={7} title={8}' -f
        $type, $kb, $row.uid, $parserName, $selection.SelectionBasis, $displayAssessment.Status,
        $rule.CanonicalClassification, $canonicalProductsText, $rule.CanonicalTitle)
    if (-not $displayAssessment.Canonical) {
        Write-Caution ('Catalog localized display metadata was isolated for {0}/{1}; canonical project metadata was retained. observed fingerprints: title={2} classification={3} products={4}' -f
            $type, $kb, $displayAssessment.TitleSha256, $displayAssessment.ClassificationSha256, $displayAssessment.ProductsSha256)
    }
    $fileParser = ''
    if ($file.PSObject.Properties['parser']) { $fileParser = [string]$file.parser }
    Write-Step ('Catalog file resolved: {0} parser={1} urlHost={2}' -f $file.fileName, $fileParser, ([uri]$file.url).Host)

    $Patch.Source = [string]$file.url
    $Patch.LocalPath = Get-PatchLocalPath -Kind $type -FileName ([string]$file.fileName)
    if ($Patch.PSObject.Properties['FileName']) { $Patch.FileName = [string]$file.fileName } else { $Patch | Add-Member -NotePropertyName FileName -NotePropertyValue ([string]$file.fileName) -Force }
    if ($Patch.PSObject.Properties['FileNameOrigin']) { $Patch.FileNameOrigin = 'CatalogResolved' } else { $Patch | Add-Member -NotePropertyName FileNameOrigin -NotePropertyValue 'CatalogResolved' -Force }

    # Research candidates are intentionally mutable until Freeze. The exact
    # KB remains fixed while the selected Catalog transport identity is
    # rehydrated. The mutability decision was intentionally made before
    # candidate selection above; immutable baselines still fail on changes.
    $hashes = @{}
    if ($Patch.PSObject.Properties['ExpectedHashes'] -and $Patch.ExpectedHashes) {
        foreach ($key in $Patch.ExpectedHashes.Keys) { $hashes[$key] = $Patch.ExpectedHashes[$key] }
    }
    if ($file.digest) {
        if ($hashes.ContainsKey('sha-1') -and [string]$hashes['sha-1'] -ne [string]$file.digest) {
            if (-not $allowIdentityRefresh) {
                throw ('Catalog SHA-1 changed for immutable baseline {0}/{1}; status={2}; baseline={3}, catalog={4}. Create a ResearchCandidate and validate it before replacing the approved identity.' -f $type, $kb, $baselineStatus, $hashes['sha-1'], $file.digest)
            }
            Write-Caution ('Catalog SHA-1 rehydrated for mutable candidate {0}/{1}: {2} -> {3} (mode={4}; KB identity remains pinned).' -f $type, $kb, $hashes['sha-1'], $file.digest, $identityDecision.Mode)
        }
        $hashes['sha-1'] = [string]$file.digest # Catalog compatibility
    }
    if ($file.sha256) {
        if ($hashes.ContainsKey('sha-256') -and [string]$hashes['sha-256'] -ne [string]$file.sha256) {
            if (-not $allowIdentityRefresh) {
                throw ('Catalog SHA-256 changed for immutable baseline {0}/{1}; status={2}; baseline={3}, catalog={4}. Create a ResearchCandidate and validate it before replacing the approved identity.' -f $type, $kb, $baselineStatus, $hashes['sha-256'], $file.sha256)
            }
            Write-Caution ('Catalog SHA-256 rehydrated for mutable candidate {0}/{1}: {2} -> {3} (mode={4}; KB identity remains pinned).' -f $type, $kb, $hashes['sha-256'], $file.sha256, $identityDecision.Mode)
        }
        $hashes['sha-256'] = [string]$file.sha256
    }
    $Patch.ExpectedHashes = $hashes
    $Patch.IsMetadataOnly = $false
    if (-not $Patch.PSObject.Properties['UpdateId']) {
        $Patch | Add-Member -NotePropertyName UpdateId -NotePropertyValue ([string]$row.uid)
    } else {
        $Patch.UpdateId = [string]$row.uid
    }
    if (-not $Patch.PSObject.Properties['Title'] -or [string]::IsNullOrWhiteSpace([string]$Patch.Title)) {
        if (-not $Patch.PSObject.Properties['Title']) {
            $Patch | Add-Member -NotePropertyName Title -NotePropertyValue ([string]$rule.CanonicalTitle)
        } else {
            $Patch.Title = [string]$rule.CanonicalTitle
        }
    }
    if (-not $Patch.PSObject.Properties['CatalogClassification']) {
        $Patch | Add-Member -NotePropertyName CatalogClassification -NotePropertyValue ([string]$rule.CanonicalClassification)
    } else {
        $Patch.CatalogClassification = [string]$rule.CanonicalClassification
    }
    if (-not $Patch.PSObject.Properties['CatalogProducts']) {
        $Patch | Add-Member -NotePropertyName CatalogProducts -NotePropertyValue $canonicalProductsText
    } else {
        $Patch.CatalogProducts = $canonicalProductsText
    }
    $metadataFields = [ordered]@{
        CatalogDisplayLanguagePolicy = $script:CatDisplayLanguagePolicy
        CatalogSelectionPolicy = $script:CatSelectionPolicy
        CatalogSelectionBasis = [string]$selection.SelectionBasis
        CatalogObservedMetadataStatus = [string]$displayAssessment.Status
        CatalogObservedTitleSha256 = [string]$displayAssessment.TitleSha256
        CatalogObservedClassificationSha256 = [string]$displayAssessment.ClassificationSha256
        CatalogObservedProductsSha256 = [string]$displayAssessment.ProductsSha256
        CatalogScopedIdentityVerified = [bool]($row.PSObject.Properties['ScopedIdentityVerified'] -and $row.ScopedIdentityVerified)
        CatalogScopedIdentityBasis = $(if ($row.PSObject.Properties['ScopedIdentityBasis']) { [string]$row.ScopedIdentityBasis } else { '' })
        CatalogScopedArchitecture = $(if ($row.PSObject.Properties['ScopedArchitecture']) { [string]$row.ScopedArchitecture } else { '' })
        CatalogScopedRawSha256 = $(if ($row.PSObject.Properties['ScopedRawSha256']) { [string]$row.ScopedRawSha256 } else { '' })
        CatalogScopedParseBasis = $(if ($row.PSObject.Properties['ScopedParseBasis']) { [string]$row.ScopedParseBasis } else { '' })
    }
    foreach ($field in $metadataFields.Keys) {
        if (-not $Patch.PSObject.Properties[$field]) {
            $Patch | Add-Member -NotePropertyName $field -NotePropertyValue $metadataFields[$field]
        } else {
            $Patch.$field = $metadataFields[$field]
        }
    }
    Write-Ok ('Catalog asset resolved: {0}/{1} -> {2} (UpdateId {3}; selection {4}; display metadata {5})' -f
        $type, $kb, $file.fileName, $row.uid, $selection.SelectionBasis, $displayAssessment.Status)
    return $true
}

function Merge-ResolvedPatchDuplicates {
    <# Collapse duplicate Kind+KB runtime entries, preferring a resolved asset. #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([AllowEmptyCollection()][object[]]$Patches)

    $byKey = [ordered]@{}
    foreach ($p in @($Patches)) {
        if (-not $p) { continue }
        $type = Get-PatchEntryType -Patch $p
        $key = ('{0}|{1}' -f $type, ([string]$p.KbId).ToUpperInvariant())
        if (-not $byKey.Contains($key)) {
            $byKey[$key] = $p
            continue
        }
        $current = $byKey[$key]
        $currentMetadata = $current.PSObject.Properties['IsMetadataOnly'] -and $current.IsMetadataOnly
        $newMetadata = $p.PSObject.Properties['IsMetadataOnly'] -and $p.IsMetadataOnly
        if ($currentMetadata -and -not $newMetadata) {
            $byKey[$key] = $p
            $current = $p
        }
        $roleSet = @(@(Get-PatchRoles -Patch $current) + @(Get-PatchRoles -Patch $p) | Sort-Object -Unique)
        $current.Roles = $roleSet
        Write-Caution ('Duplicate patch entry collapsed: {0}; retained {1}' -f $key, [string]$current.PackageId)
    }
    return @($byKey.GetEnumerator() | ForEach-Object { $_.Value })
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
    @($Rows) | Sort-Object `
        @{ Expression = {
            $m = [regex]::Match($_.title, '\s*(\d{4})-(\d{2})')
            if ($m.Success) { [int]$m.Groups[1].Value * 100 + [int]$m.Groups[2].Value } else { 0 }
        }; Descending = $true }, `
        @{ Expression = {
            try { [datetime]$_.lastUpdated } catch { [datetime]::MinValue }
        }; Descending = $true }, `
        @{ Expression = { [string]$_.version }; Descending = $true } | Select-Object -First 1
}

function Get-UpdateMonthFromTitle {
    <# Return yyyy-MM from a Catalog title, or $null when no release month is present. #>
    [OutputType([string])]
    param([AllowNull()][string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    $m = [regex]::Match($Title, '(?<!\d)(\d{4})-(\d{2})(?!\d)')
    if (-not $m.Success) { return $null }
    return ('{0}-{1}' -f $m.Groups[1].Value, $m.Groups[2].Value)
}

function Get-NewestAtOrBeforeMonth {
    <#
    Select the newest Catalog row whose title month is not later than the
    Windows baseline month. This enforces the Dynamic Update and .NET policy
    "same month, otherwise latest prior" and prevents a future preview/month
    from leaking into a reproducible baseline.
    #>
    param(
        [AllowNull()][object[]]$Rows,
        [AllowNull()][string]$BaselineMonth,
        [switch]$IncludePreview
    )
    $all = @($Rows)
    if (-not $IncludePreview) {
        $all = @($all | Where-Object { ([string]$_.title) -notmatch '(?i)\bPreview\b' })
    }
    if ($all.Count -eq 0) { return $null }
    if ($BaselineMonth -notmatch '^(\d{4})-(\d{2})$') {
        return (Get-Newest $all)
    }
    $cutoff = ([int]$Matches[1] * 100) + [int]$Matches[2]
    $eligible = @($all | Where-Object {
        $month = Get-UpdateMonthFromTitle -Title ([string]$_.title)
        if ($month -notmatch '^(\d{4})-(\d{2})$') { return $false }
        $value = ([int]$Matches[1] * 100) + [int]$Matches[2]
        return ($value -le $cutoff)
    })
    if ($eligible.Count -eq 0) { return $null }
    return (Get-Newest $eligible)
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
    param([AllowNull()][string]$BaselineMonth)
    $rows = Search-Catalog 'Servicing Stack Update Windows Server 2016'
    $cands = @($rows | Where-Object { $_.title.Contains('Servicing Stack Update') -and $_.products.Contains('Windows Server 2016') })
    $row = Get-NewestAtOrBeforeMonth -Rows $cands -BaselineMonth $BaselineMonth
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $inScope = [pscustomobject]@{ standalone = $true; files = @($files | ForEach-Object { $_.fileName }) }
    return (New-Line 'SSU' $row $files $inScope '2016 only: standalone SSU row (apply before LCU)')
}

# in-box / in-scope = the .NET runtime whose payload ships in the base media (BLOCK 0.T).
# Picks the leaf for the OS's default/shipping runtime; 3.5 rides bundled in that leaf.
function Test-NetInScope {
    param([string]$OsKey, [string]$FileName)
    switch ($OsKey) {
        '2016' { return (($FileName -notmatch '-ndp48') -and ($FileName -notmatch '-ndp481')) }  # base 4.6.2/4.7.x (+3.5)
        '2019' { return (($FileName -notmatch '-ndp48') -and ($FileName -notmatch '-ndp481')) }  # base 4.7.2 (+3.5)
        '2022' { return (($FileName -match '-ndp48') -and ($FileName -notmatch '-ndp481')) }      # 4.8 (+3.5)
        '2025' { return ($FileName -match '-ndp481') }                                            # 4.8.1 (+3.5)
    }
    return $false
}

function Resolve-Net {
    param([string]$OsKey, [AllowNull()][string]$BaselineMonth)
    $info = $script:CatOsDef[$OsKey]
    $q = $script:CatNetQuery[$OsKey]
    $rows = Search-Catalog $q
    $rows = @($rows | Where-Object { $_.products.ToLower().Contains($info.products.ToLower()) })
    $rows = Get-X64Rows $rows
    $nm = Get-NewestAtOrBeforeMonth -Rows $rows -BaselineMonth $BaselineMonth
    if (-not $nm) { return (New-Line '.NET' $null @() $null 'no .NET row matched OS token') }
    $month = [regex]::Match($nm.title, '\s*(\d{4}-\d{2})').Groups[1].Value
    $variants = @($rows | Where-Object { $_.title.TrimStart().StartsWith($month) -and $_.title -notmatch '(?i)\bPreview\b' })
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
    param([string]$OsKey, [AllowNull()][string]$BaselineMonth)
    $aliases = @{
        '2016' = @{ Query='Dynamic Update Windows 10 Version 1607 x64'; Token='Version 1607' }
        '2019' = @{ Query='Dynamic Update Windows 10 Version 1809 x64'; Token='Version 1809' }
        '2022' = @{ Query='Dynamic Update Microsoft server operating system version 21H2 x64'; Token='21H2' }
        '2025' = @{ Query='Safe OS Dynamic Update Microsoft server operating system version 24H2 x64'; Token='24H2' }
    }
    $a = $aliases[$OsKey]
    $rows = Search-Catalog $a.Query
    $cands = @($rows | Where-Object {
        $_.products.Contains('Safe OS Dynamic Update') -and
        $_.title.Contains($a.Token) -and
        $_.title.ToLower().Contains('x64') -and
        ($_.title.ToLower() -notmatch 'arm64|x86-based')
    })
    $row = Get-NewestAtOrBeforeMonth -Rows $cands -BaselineMonth $BaselineMonth
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $x64 = @($files | Where-Object { $_.fileName.ToLower().Contains('x64') -and $_.fileName.ToLower().EndsWith('.cab') })
    $inScope = [pscustomobject]@{ files=@($x64 | ForEach-Object { $_.fileName }); selection='same-month-or-latest-prior' }
    return (New-Line 'SafeOSDU' $row $x64 $inScope "Products contains Windows Safe OS Dynamic Update; OS build-family alias matched")
}

function Select-SetupDuCandidate {
    <# Select Setup DU rows by Dynamic Update product membership, excluding SafeOS. #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Rows,
        [Parameter(Mandatory)] [string]$VersionToken
    )
    $cands = @($Rows | Where-Object {
        $_.title.Contains($VersionToken) -and
        $_.title.ToLower().Contains('x64') -and
        ($_.title.ToLower() -notmatch 'arm64|x86-based') -and
        $_.products.Contains('Dynamic Update') -and
        (-not $_.products.Contains('Safe OS Dynamic Update')) -and
        ($_.title -notmatch 'Cumulative Update')
    })
    $explicit = @($cands | Where-Object { $_.title.Contains('Setup Dynamic Update') })
    if ($explicit.Count -gt 0) { return ,$explicit }
    return ,$cands
}

function Resolve-SetupDu { # psa-disable-line PSA6003 -- dynamic-update abbreviation
    param([string]$OsKey, [AllowNull()][string]$BaselineMonth)
    $aliases = @{
        '2016' = @{ Query='Dynamic Update Windows 10 Version 1607 x64'; Token='Version 1607' }
        '2019' = @{ Query='Dynamic Update Windows 10 Version 1809 x64'; Token='Version 1809' }
        '2022' = @{ Query='Dynamic Update Microsoft server operating system version 21H2 x64'; Token='21H2' }
        '2025' = @{ Query='Setup Dynamic Update Microsoft server operating system version 24H2 x64'; Token='24H2' }
    }
    $a = $aliases[$OsKey]
    $rows = Search-Catalog $a.Query
    $cands = Select-SetupDuCandidate -Rows @($rows) -VersionToken $a.Token
    $row = Get-NewestAtOrBeforeMonth -Rows $cands -BaselineMonth $BaselineMonth
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $x64 = @($files | Where-Object { $_.fileName.ToLower().Contains('x64') -and $_.fileName.ToLower().EndsWith('.cab') })
    $inScope = [pscustomobject]@{ files=@($x64 | ForEach-Object { $_.fileName }); selection='same-month-or-latest-prior' }
    return (New-Line 'SetupDU' $row $x64 $inScope 'Generic Dynamic Update product minus SafeOS; Support KB must confirm Setup role')
}

function Resolve-Os { # psa-disable-line PSA6003 -- noun is 'OS' (operating system), not a plural; ported reference contract
    param([string]$OsKey)

    # Resolve the B/OOB LCU first. Its yyyy-MM title is the cutoff for SSU,
    # .NET and Dynamic Update selection. This prevents a later preview or
    # future-month DU from entering an older reproducible baseline.
    $lcu = Resolve-Lcu $OsKey
    $baselineMonth = Get-UpdateMonthFromTitle -Title ([string]$lcu.title)

    switch ($OsKey) {
        '2016' {
            return [pscustomobject]@{
                os = 'Server2016'
                lines = @(
                    $lcu,
                    (Resolve-Ssu2016 -BaselineMonth $baselineMonth),
                    (Resolve-Net -OsKey '2016' -BaselineMonth $baselineMonth),
                    (Resolve-SafeOsDu -OsKey '2016' -BaselineMonth $baselineMonth),
                    (Resolve-SetupDu -OsKey '2016' -BaselineMonth $baselineMonth)
                )
            }
        }
        '2019' {
            return [pscustomobject]@{
                os = 'Server2019'
                lines = @(
                    $lcu,
                    (New-Line 'SSU' $null @() $null 'monthly SSU embedded in LCU; source prerequisite is modelled separately'),
                    (Resolve-Net -OsKey '2019' -BaselineMonth $baselineMonth),
                    (Resolve-SafeOsDu -OsKey '2019' -BaselineMonth $baselineMonth),
                    (Resolve-SetupDu -OsKey '2019' -BaselineMonth $baselineMonth)
                )
            }
        }
        '2022' {
            return [pscustomobject]@{
                os = 'Server2022'
                lines = @(
                    $lcu,
                    (New-Line 'SSU' $null @() $null 'monthly SSU embedded in LCU; source prerequisite is modelled separately'),
                    (Resolve-Net -OsKey '2022' -BaselineMonth $baselineMonth),
                    (Resolve-SafeOsDu -OsKey '2022' -BaselineMonth $baselineMonth),
                    (Resolve-SetupDu -OsKey '2022' -BaselineMonth $baselineMonth)
                )
            }
        }
        '2025' {
            $lcuKb = if ($lcu.kb) { $lcu.kb.ToLower() } else { '' }
            $checkpointFiles = @($lcu.files | Where-Object {
                $_.fileName.ToLower().EndsWith('.msu') -and (($lcuKb -eq '') -or (-not $_.fileName.ToLower().Contains($lcuKb)))
            })
            $checkpointKb = if ($checkpointFiles.Count) { Get-KbOf $checkpointFiles[0].fileName } else { $null }
            $checkpoint = New-Line 'Checkpoint' $null $checkpointFiles ([pscustomobject]@{ files = @($checkpointFiles | ForEach-Object { $_.fileName }) }) `
                '2025: checkpoint cumulative baseline co-served with the target LCU; keep it in the same package folder for DISM dependency discovery, never target it as the final LCU'
            $checkpoint.kb = $checkpointKb
            return [pscustomobject]@{
                os = 'Server2025'
                lines = @(
                    $lcu,
                    $checkpoint,
                    (Resolve-Net -OsKey '2025' -BaselineMonth $baselineMonth),
                    (Resolve-SafeOsDu -OsKey '2025' -BaselineMonth $baselineMonth),
                    (Resolve-SetupDu -OsKey '2025' -BaselineMonth $baselineMonth)
                )
            }
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
    <# Validate core package invariants without forbidding optional/current DU kinds. #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$OsKey,
        [Parameter(Mandatory)][string]$PatchModel,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Lines
    )
    $rules = @{
        'separate-ssu'    = @{ Require=@('SSU','LCU') }
        'embedded-ssu'    = @{ Require=@('LCU','DotNet') }
        'embedded-ssu-du' = @{ Require=@('LCU','DotNet','SafeOSDU') }
        'uup-checkpoint'  = @{ Require=@('LCU','Checkpoint','DotNet','SafeOSDU','SetupDU') }
    }
    if (-not $rules.ContainsKey($PatchModel)) {
        throw "P06 consistency: unknown PatchModel '$PatchModel' for $OsKey."
    }
    $present = @($Lines | ForEach-Object { $_.Kind } | Sort-Object -Unique)
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($kind in $rules[$PatchModel].Require) {
        if ($present -notcontains $kind) { $errors.Add("missing required Kind '$kind'") }
    }
    for ($i=0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $state = if ($line.PSObject.Properties['State']) { [string]$line.State } else { 'LegacyResolved' }
        $sha1 = Get-BaselineHashValue -Line $line -Algorithm Sha1
        $sha256 = Get-BaselineHashValue -Line $line -Algorithm Sha256
        if ($state -in @('Frozen','E3Validated','E4Validated','E5Validated','Approved') -and -not $sha256) {
            $errors.Add("Lines[$i] (Kind '$($line.Kind)') is state=$state but has no SHA-256")
        } elseif ($state -eq 'LegacyResolved' -and -not $sha1 -and -not $sha256) {
            $errors.Add("Lines[$i] (Kind '$($line.Kind)') has no integrity key")
        }
    }
    return [pscustomobject]@{ OsKey=$OsKey; PatchModel=$PatchModel; IsConsistent=($errors.Count -eq 0); Errors=$errors.ToArray() }
}

function ConvertTo-ConfigLines { # psa-disable-line PSA6003 -- returns the Lines[] collection; plural noun intentional
    <#
    .SYNOPSIS
        b3 layer-1 transform: turn the seed-only Catalog resolver's raw per-OS output
        (kind/kb/catalogUid/title/products/files[]/inScope/note) into the config
        PatchBaseline.Lines[] (one Line per in-scope file, with Kind/Digest/ApplyOrder),
        applying the per-PatchModel selections:
          (1) drop placeholder "none" lines (no files) ONLY for Kinds outside
              the PatchModel's apply map; an in-model Kind with 0 files
              HARD-FAILS (silent-starvation guard, r11.45);
          (2) 2025 LCU 2-file split -> keep only the LCU-proper file (the baseline .msu is
              the separate Checkpoint line);
          (3) .NET in-scope leaf selection (inScope.inScopeFiles);
          (4) all four OS generations may carry .NET, SafeOS DU and Setup DU rows;
              runtime/applicability selection is expressed in v4 metadata rather than
              hard-coded PatchModel exclusion.
        Pure function; offline-tested against the captured resolve.json.
    .OUTPUTS
        System.Collections.Generic.List[object]  (the Lines[] for one OS)
    #>
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][object]$OsResolved,   # one OS object: { os; lines[] }
        [Parameter(Mandatory)][string]$PatchModel
    )
    $kindMap  = @{ 'LCU'='LCU'; 'SSU'='SSU'; 'Checkpoint'='Checkpoint'; '.NET'='DotNet'; 'SafeOSDU'='SafeOSDU'; 'SetupDU'='SetupDU' }
    $applyMap = @{
        'separate-ssu'    = @{ 'SSU'=10; 'LCU'=20; 'SafeOSDU'=40; 'DotNet'=60; 'SetupDU'=80 }
        'embedded-ssu'    = @{ 'LCU'=20; 'SafeOSDU'=40; 'DotNet'=60; 'SetupDU'=80 }
        'embedded-ssu-du' = @{ 'LCU'=20; 'SafeOSDU'=40; 'DotNet'=60; 'SetupDU'=80 }
        'uup-checkpoint'  = @{ 'Checkpoint'=10; 'LCU'=20; 'SafeOSDU'=40; 'DotNet'=60; 'SetupDU'=80 }
    }
    if (-not $applyMap.ContainsKey($PatchModel)) {
        throw "ConvertTo-ConfigLines: unknown PatchModel '$PatchModel' for $($OsResolved.os)."
    }
    $orders = $applyMap[$PatchModel]
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($L in $OsResolved.lines) {
        $kind = $kindMap[$L.kind]
        if (-not $L.files -or @($L.files).Count -eq 0) {                     # (1)
            # Rule (1) drops a placeholder line ONLY when its Kind is OUTSIDE
            # the PatchModel's apply map (for example, a standalone monthly SSU
            # on an integrated-SSU generation). An EMPTY line for an IN-MODEL
            # Kind means the live Catalog resolution silently failed (forensic:
            # the 2025 SetupDU line starved for weeks behind a never-matching
            # Products filter while all gates stayed green) -- HARD FAIL,
            # never a silent drop [DECIDED 2026-07-02, user].
            if ($kind -and $orders.ContainsKey($kind)) {
                throw ("ConvertTo-ConfigLines: Kind '{0}' resolved 0 files for {1}, but PatchModel '{2}' expects it. Refusing to build a silently-degraded dataset -- investigate the resolver/discriminator against the live Catalog. (If a month legitimately lacks this Kind, make an explicit skip decision + flag first.)" -f $kind, $OsResolved.os, $PatchModel)
            }
            continue
        }
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
            $roles = switch ($kind) {
                'SSU'        { @('ServicingStackCarrier') }
                'LCU'        { if ($PatchModel -eq 'separate-ssu') { @('FinalLCU') } else { @('ServicingStackCarrier','FinalLCU') } }
                'Checkpoint' { @('CheckpointDependency') }
                'DotNet'     { @('DotNetLeaf') }
                'SafeOSDU'   { @('SafeOSDU') }
                'SetupDU'    { @('SetupDU') }
                default      { @() }
            }
            $targets = [ordered]@{}
            foreach ($role in $roles) {
                $targets[$role] = switch ($role) {
                    'ServicingStackCarrier' { @('Install','Boot','WinRE') }
                    'FinalLCU'              { @('Install','Boot') }
                    'DotNetLeaf'            { @('Install') }
                    'SafeOSDU'              { @('WinRE') }
                    'SetupDU'               { @('Setup') }
                    default                 { @() }
                }
            }
            $sha256Value = $(if ($f.PSObject.Properties.Name -contains 'sha256') { $f.sha256 } else { '' })
            $out.Add([pscustomobject]@{
                PackageId   = ('{0}-{1}-{2}' -f $OsResolved.os, $L.kb, $f.fileName)
                Kind        = $kind
                KbId        = $L.kb
                ParentKbId  = $null
                UpdateId    = $L.catalogUid
                Revision    = $null
                Title       = $L.title
                Products    = $L.products
                Classification = $null
                Architecture = 'x64'
                ReleaseDate = $null
                ReleaseType = $(if ($kind -in @('SafeOSDU','SetupDU')) { 'DynamicUpdate' } else { 'B' })
                State       = 'Resolved'
                FileName    = $f.fileName
                DownloadUrl = $f.url
                Digest      = $f.digest
                Sha256      = $sha256Value
                SizeBytes   = $null
                ApplyOrder  = $order
                InScope     = $insc
                Note        = $L.note
                Roles       = $roles
                TargetsByRole = [pscustomobject]$targets
                RuntimeSelector = $null
                Applicability = [pscustomobject]@{ Mode = $(if ($kind -eq 'DotNet') { 'IfRuntimeDetectedPerInstallIndex' } elseif ($kind -in @('SafeOSDU','SetupDU')) { 'SameMonthOrLatestPrior' } else { 'Always' }) }
                Dependencies = @()
                Integrity = [pscustomobject]@{
                    Sha1 = $(if ($f.digest) { [pscustomobject]@{ Encoding='base64'; Value=$f.digest; Hex=$null } } else { $null })
                    Sha256 = $(if ($sha256Value) { [pscustomobject]@{ Encoding='base64'; Value=$sha256Value; Hex=$null } } else { $null })
                    SizeBytes = $null
                    AuthenticodeStatus = 'NotTested'
                }
                Evidence = [pscustomobject]@{ Levels=@('E1','E2'); SourceUrls=@(); VerifiedAt=(Get-Date).ToString('o'); VerifiedBy='auto:CatalogRefresh'; Notes=@($L.note) }
            })
        }
    }
    $sorted = @($out | Sort-Object { if ($null -ne $_.ApplyOrder) { $_.ApplyOrder } else { 99 } })
    return ,$sorted
}

function Get-TargetBuildFromLines { # psa-disable-line PSA6003 -- "Lines" is the Config Schema v3.0 field name (PatchBaseline.Lines[]), not a plural noun choice
    <#
    .SYNOPSIS
        Pure derivation: PatchBaseline.TargetBuildAfterUpdate from Lines[].
    .DESCRIPTION
        The LCU Line's Catalog-captured InScope.build IS the post-update OS
        build. This is the SINGLE derivation point [r11.46]; both writers --
        the in-memory refresh writeback and the A00/A01 config-object
        refresh loop -- must call it (the derivation was first wired only
        into the former, and the very first A00 run produced configs with an
        empty TargetBuildAfterUpdate; T31's data contract caught it).
        Returns '' when no LCU Line carries an InScope.build.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()] [object[]]$Lines = @()
    )
    foreach ($ln in @($Lines)) {
        if ($ln.Kind -ne 'LCU') { continue }
        if (-not $ln.PSObject.Properties['InScope'] -or -not $ln.InScope) { continue }
        if (-not $ln.InScope.PSObject.Properties['build']) { continue }
        $b = [string]$ln.InScope.build
        if ($b) { return $b }
    }
    return ''
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
        [Parameter(Mandatory)][string]$PatchMonth,
        [int]$MaxRetries = 3
    )
    $osKeyMap = @{ 'Server2016' = '2016'; 'Server2019' = '2019'; 'Server2022' = '2022'; 'Server2025' = '2025' }
    $modelMap = @{ 'Server2016' = 'separate-ssu'; 'Server2019' = 'embedded-ssu'; 'Server2022' = 'embedded-ssu-du'; 'Server2025' = 'uup-checkpoint' }
    if (-not $osKeyMap.ContainsKey($OsVersion)) { throw ("Invoke-CatalogPatchSetRefresh: unknown OsVersion '{0}'." -f $OsVersion) }
    $osk = $osKeyMap[$OsVersion]; $model = $modelMap[$OsVersion]
    $parts = $PatchMonth.Split('-'); $year = [int]$parts[0]; $month = [int]$parts[1]
    # Layer 1: live seed-only Catalog acquisition. Individual HTTP requests
    # already retry transient network/429/503 inside Invoke-WebRequestWithRetry;
    # $MaxRetries (AutoRefreshPolicy.ScrapeRetries) adds a coarse scrape-level
    # retry so a whole-scrape failure is re-attempted with exponential backoff
    # before giving up.
    $raw = $null
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $raw = Resolve-Os -OsKey $osk
            break
        } catch {
            if ($attempt -ge $MaxRetries) { throw }
            $backoffSec = [int][math]::Pow(2, $attempt - 1)
            Write-Caution ("{0}: Catalog scrape attempt {1}/{2} failed ({3}); retrying in {4}s." -f $OsVersion, $attempt, $MaxRetries, $_.Exception.Message, $backoffSec)
            Start-Sleep -Seconds $backoffSec
        }
    }
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

    $queries = [System.Collections.Generic.List[object]]::new()
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

    $resolved = [System.Collections.Generic.List[object]]::new()
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
        String status code: 'Ok' | 'OkAfterRetry' | 'NotApplicable' |
        'WinReServicingStackKnownIssue'. Fatal errors are re-thrown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$MountPath,
        [Parameter(Mandatory)] [string]$PackagePath,
        [string]$LogDir,
        [switch]$AllowWinReCombinedLcuKnownError,
        [hashtable]$EvidenceMetadata = @{}
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
        $logPathUsed = if ($extraArg.ContainsKey('LogPath')) { [string]$extraArg['LogPath'] } else { '' }
        Write-DismLogClassificationEvidence -LogPath $logPathUsed -OperationStatus 'Ok' -Context ([System.IO.Path]::GetFileName($PackagePath)) -Metadata $EvidenceMetadata | Out-Null
        return 'Ok'
    } catch {
        $m = [string]$_.Exception.Message
        $hresult = [int]$_.Exception.HResult
        # Microsoft's installation-media sample documents 0x8007007e as a
        # known result when a combined LCU is supplied to WinRE only to carry
        # its servicing-stack payload. Suppress it exclusively for that
        # explicit caller-selected role; all other 0x8007007e failures remain fatal.
        if ($AllowWinReCombinedLcuKnownError -and (($m -match '0x8007007e') -or ($hresult -eq -2147024770))) {
            Write-Caution ('0x8007007e: known WinRE combined-LCU servicing-stack result; continuing: {0}' -f [System.IO.Path]::GetFileName($PackagePath))
            $logPathUsed = if ($extraArg.ContainsKey('LogPath')) { [string]$extraArg['LogPath'] } else { '' }
            Write-DismLogClassificationEvidence -LogPath $logPathUsed -OperationStatus 'WinReServicingStackKnownIssue' -Context ([System.IO.Path]::GetFileName($PackagePath)) -Metadata $EvidenceMetadata -Exception $_.Exception -DoNotThrow | Out-Null
            return 'WinReServicingStackKnownIssue'
        }
        if ($m -match '0x800f081e') {
            Write-Caution ('0x800f081e: Package not applicable, skipping: {0}' -f [System.IO.Path]::GetFileName($PackagePath))
            $logPathUsed = if ($extraArg.ContainsKey('LogPath')) { [string]$extraArg['LogPath'] } else { '' }
            Write-DismLogClassificationEvidence -LogPath $logPathUsed -OperationStatus 'NotApplicable' -Context ([System.IO.Path]::GetFileName($PackagePath)) -Metadata $EvidenceMetadata -Exception $_.Exception -DoNotThrow | Out-Null
            return 'NotApplicable'
        }
        if ($m -match '0x800f0a13') {
            Write-Caution ('0x800f0a13: Modules Installer transient error; retrying after 10s...')
            Start-Sleep -Seconds 10
            try {
                Invoke-DismCmdlet -CommandName 'Add-WindowsPackage' -Parameters (@{ Path = $MountPath; PackagePath = $PackagePath; ErrorAction = 'Stop' } + $extraArg) | Out-Null
                $logPathUsed = if ($extraArg.ContainsKey('LogPath')) { [string]$extraArg['LogPath'] } else { '' }
                Write-DismLogClassificationEvidence -LogPath $logPathUsed -OperationStatus 'OkAfterRetry' -Context ([System.IO.Path]::GetFileName($PackagePath)) -Metadata $EvidenceMetadata | Out-Null
                return 'OkAfterRetry'
            } catch {
                $logPathUsed = if ($extraArg.ContainsKey('LogPath')) { [string]$extraArg['LogPath'] } else { '' }
                Write-DismLogClassificationEvidence -LogPath $logPathUsed -OperationStatus 'Fail' -Context ([System.IO.Path]::GetFileName($PackagePath)) -Metadata $EvidenceMetadata -Exception $_.Exception -DoNotThrow | Out-Null
                throw
            }
        }
        # All other errors propagate, but failure evidence is always persisted first.
        $logPathUsed = if ($extraArg.ContainsKey('LogPath')) { [string]$extraArg['LogPath'] } else { '' }
        Write-DismLogClassificationEvidence -LogPath $logPathUsed -OperationStatus 'Fail' -Context ([System.IO.Path]::GetFileName($PackagePath)) -Metadata $EvidenceMetadata -Exception $_.Exception -DoNotThrow | Out-Null
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

function Export-WinReRecoveryCompressed {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WinRePath)
    $exported = $WinRePath + '.recovery.wim'
    if (Test-Path -LiteralPath $exported) { Remove-Item -LiteralPath $exported -Force }
    $args = @(
        '/Export-Image',
        ("/SourceImageFile:$WinRePath"),
        '/SourceIndex:1',
        ("/DestinationImageFile:$exported"),
        '/Compress:recovery',
        ("/ScratchDir:$Script:ScratchDir")
    )
    $code = Invoke-DismCli -Arguments $args -Context 'export-winre-recovery'
    if ($code -ne 0) { throw ('WinRE /Export-Image /Compress:recovery failed with exit code {0}' -f $code) }
    Remove-Item -LiteralPath $WinRePath -Force
    Move-Item -LiteralPath $exported -Destination $WinRePath -Force
}

function Copy-ServicedWinReToInstallIndexes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallWim,
        [Parameter(Mandatory)][string]$ServicedWinRe,
        [Parameter(Mandatory)][array]$Indexes
    )
    $expectedHash = (Get-FileHash -LiteralPath $ServicedWinRe -Algorithm SHA256).Hash
    foreach ($img in $Indexes) {
        $index = if ($img.PSObject.Properties['ImageIndex']) { [int]$img.ImageIndex } else { [int]$img }
        Write-Step ('Distributing serviced WinRE to install.wim index {0}.' -f $index)
        Invoke-WimMountSafe -ImagePath $InstallWim -Index $index -Path $Script:MountInstallDir -LogDir $Script:LogsDir | Out-Null
        $copySucceeded = $false
        try {
            $destination = Join-Path $Script:MountInstallDir 'Windows\System32\Recovery\Winre.wim'
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $ServicedWinRe -Destination $destination -Force
            $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash) {
                throw ('WinRE copy verification failed for install.wim index {0}: expected {1}, actual {2}' -f $index, $expectedHash, $actualHash)
            }
            $copySucceeded = $true
        } finally {
            Invoke-WimDismountSafe -Path $Script:MountInstallDir -Discard:(-not $copySucceeded) -LogDir $Script:LogsDir
        }
    }
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
    $list = [System.Collections.Generic.List[object]]::new()
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
        (scripts/windows/Make2023BootableMedia.ps1 v1.6.5 / v1.6.5-signed / commit 798cdc5,
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
    # Make2023BootableMedia.ps1 v1.6.5 / v1.6.5-signed / commit 798cdc5). These are the
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

function Test-WimSequenceHasWork {
    <#
    .SYNOPSIS
        Pure decision: does an apply-sequence carry at least one
        real patch (ignoring cleanup markers and null slots)?
    .DESCRIPTION
        P08 uses this to decide whether servicing a WIM is worth
        mounting anything at all. Null-safe by construction: a
        $null sequence, a $null element (e.g. @($null) produced by
        wrapping an undefined property), and an empty Patches list
        all mean 'no work'. History: the 2026-07-07 Server 2019 E2E
        died inside an inline Where-Object doing
        $_.PSObject.Properties['IsCleanupMarker'] on a $null element
        ('Cannot index into a null array'); a pure, null-hardened,
        REPL-testable helper is the structural fix for that class.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]]$Sequence
    )
    foreach ($sp in @($Sequence)) {
        if ($null -eq $sp) { continue }
        if ($sp.PSObject.Properties['IsCleanupMarker'] -and $sp.IsCleanupMarker) { continue }
        if (@($sp.Patches).Count -gt 0) { return $true }
    }
    return $false
}

function Resolve-BootWimLcuPolicyValue {
    <#
    .SYNOPSIS
        Validate + default the per-OS boot.wim LCU policy
        (Common.BootWimLcuPolicy: 'enabled' | 'disabled' | 'tolerate').
    .DESCRIPTION
        Replaces the boolean Common.EnableBootWimUpdate (destructive
        rename, no compatibility shim). The 2026-07-05 4-OS E2E proved
        LCU-serviceability of the in-media boot.wim is a PER-OS
        property of the committed source media, not a global truth:
          - 2016 (WinPE 1607): LCU applies cleanly AND materialises
            the EFI_EX/FONTS_EX/DVD_EX PCA2023 staging set -> enabled.
          - 2019 EVAL media: structurally closed (0x80070032 at CBS
            finalize; the 2026-06-12 D1 probe closed all 6 variants)
            -> disabled.
          - 2022: never reached P08 in the E2E (P07 axis-3 failure);
            serviceability UNKNOWN -> tolerate (attempt, downgrade
            failure to Caution, discard the index, continue).
          - 2025 (26100 WinPE): expected serviceable via the r11.52
            checkpoint-model target-only apply -> enabled.
        Missing/empty defaults to 'disabled' (the safe floor: a
        boot.wim left as shipped still boots; a corrupted one does
        not). Unknown values are a typed error, never coerced.
    .OUTPUTS
        System.String -- one of 'enabled' | 'disabled' | 'tolerate'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyString()] [object]$RawValue
    )
    $v = [string]$RawValue
    if ([string]::IsNullOrWhiteSpace($v)) { return 'disabled' }
    $v = $v.Trim().ToLowerInvariant()
    if ($v -in @('enabled', 'disabled', 'tolerate')) { return $v }
    throw ("Common.BootWimLcuPolicy has unknown value '{0}' (expected enabled | disabled | tolerate)." -f $RawValue)
}

function Resolve-BootWimFailurePolicyValue {
    <# Normalize the per-OS boot.wim failure policy. Only measured policies are executable. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$RawValue='')
    $v=[string]$RawValue
    if([string]::IsNullOrWhiteSpace($v)){return 'LegacyPolicy'}
    $v=$v.Trim()
    if($v -in @('FailBuild','UnsupportedByPinnedSourceMedia','ResearchTolerateNotReleaseEligible','LegacyPolicy')){return $v}
    throw ("Common.BootWimFailurePolicy has unknown value '{0}'." -f $RawValue)
}

function Resolve-BootWimServicingStrategyValue {
    <# Resolve an OS-specific boot.wim package strategy, preserving legacy defaults. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$RawValue='',
        [ValidateSet('DirectMsu','ExpandedCab')][string]$PackageMode='DirectMsu'
    )
    $v=[string]$RawValue
    if([string]::IsNullOrWhiteSpace($v)){
        return $(if($PackageMode -eq 'ExpandedCab'){'ExpandedSplitCab'}else{'DirectMsu'})
    }
    $v=$v.Trim()
    if($v -in @('DirectMsu','ExpandedCombinedCab','ExpandedSplitCab')){return $v}
    throw ("Common.BootWimServicingStrategy has unknown value '{0}'." -f $RawValue)
}

function Get-BootWimFailurePolicyDecision {
    <#
    .SYNOPSIS
        Pure decision for measured boot.wim servicing failures.
    .DESCRIPTION
        Server 2019 evaluation media has produced 0x8007371b and 0x80070032
        while install.wim servicing succeeded. Only the explicit
        UnsupportedByPinnedSourceMedia policy may preserve the shipped
        boot.wim for these known codes. Every other error remains fatal.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyString()][string]$FailurePolicy='',
        [AllowEmptyString()][string]$ErrorText='',
        [AllowEmptyString()][string]$ImageLabel=''
    )
    $policy=Resolve-BootWimFailurePolicyValue -RawValue $FailurePolicy
    $code=''
    foreach($known in @('0x8007371b','0x80070032')){
        if($ErrorText -match [regex]::Escape($known)){$code=$known;break}
    }
    $knownFailure=(-not [string]::IsNullOrWhiteSpace($code))
    $allowed=($policy -eq 'UnsupportedByPinnedSourceMedia' -and $knownFailure)
    $reason=if($allowed){
        ('Measured known boot.wim servicing failure {0}; preserve source boot.wim and require P14 Install validation.' -f $code)
    } elseif($policy -eq 'UnsupportedByPinnedSourceMedia') {
        'Failure is outside the measured allow-list; build must fail.'
    } else {
        ('Policy {0} does not authorize source boot.wim preservation.' -f $policy)
    }
    return [pscustomobject][ordered]@{
        Policy=$policy;Allowed=$allowed;KnownFailure=$knownFailure;ErrorCode=$code
        ImageLabel=$ImageLabel;PreserveSourceBootWim=$allowed
        RequiresInstallValidation=$allowed;Reason=$reason
    }
}

function ConvertTo-BridgeLcuResolvedPatch {
    <#
    .SYNOPSIS
        Materialise the PatchBaseline.BridgeLcu SEED envelope as one
        ResolvedPatches entry (PatchType 'BridgeLcu', ApplyOrder 0).
    .DESCRIPTION
        The bridge LCU exists for one documented reason (axis 3,
        image-side servicing-stack floor; MS per-KB pages, e.g.
        KB5094128 for Server 2022): a source medium whose in-image
        servicing stack is OLDER than the floor the current combined
        LCU requires cannot even open that LCU's CBS payload
        (0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED -- observed
        on the 20348.587-era Server 2022 EVAL media, 2026-07-06 E2E).
        Microsoft's remedy is to install a bridge LCU (KB5030216 or
        later for 2022) on the offline media FIRST. Applied
        unconditionally when the envelope is present [DECIDED
        2026-07-06, A1]: DISM supersedence makes a re-apply on an
        already-current image a cheap no-op relative to the failure
        mode it prevents. Both ResolvedPatches writers (P02 baseline
        seeding + the post-refresh re-derivation) call this helper.
        LocalPath goes through Get-PatchLocalPath with the 'BridgeLcu'
        Kind, i.e. the FLAT per-OS folder -- deliberately OUTSIDE the
        cu discovery subfolder (only the target CU + checkpoints may
        live there).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [object]$BridgeLcu
    )
    $expectedHashes = @{}
    if ($BridgeLcu.PSObject.Properties['Digest'] -and $BridgeLcu.Digest) {
        $expectedHashes['sha-1'] = [string]$BridgeLcu.Digest  # psa-disable-line PSA5003 -- MS Catalog SHA-1
    }
    if ($BridgeLcu.PSObject.Properties['Sha256'] -and $BridgeLcu.Sha256) {
        $expectedHashes['sha-256'] = [string]$BridgeLcu.Sha256
    }
    return [pscustomobject]@{
        Kind           = 'Patch'
        Source         = [string]$BridgeLcu.DownloadUrl
        LocalPath      = Get-PatchLocalPath -Kind 'BridgeLcu' -FileName ([string]$BridgeLcu.FileName)
        KbId           = [string]$BridgeLcu.KbId
        PatchType      = 'BridgeLcu'
        ApplyOrder     = 0
        ExpectedHashes = $expectedHashes
    }
}

function Get-BaselineHashValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]$Line,
        [Parameter(Mandatory)][ValidateSet('Sha1','Sha256')][string]$Algorithm
    )
    if (-not $Line) { return '' }
    if ($Algorithm -eq 'Sha1' -and $Line.PSObject.Properties['Digest'] -and $Line.Digest) {
        return [string]$Line.Digest
    }
    if ($Algorithm -eq 'Sha256' -and $Line.PSObject.Properties['Sha256'] -and $Line.Sha256) {
        return [string]$Line.Sha256
    }
    if ($Line.PSObject.Properties['Integrity'] -and $Line.Integrity) {
        $node = $Line.Integrity.$Algorithm
        if ($node -and $node.PSObject.Properties['Value'] -and $node.Value) {
            return [string]$node.Value
        }
    }
    return ''
}

function ConvertTo-ResolvedPatchFromBaselineLine {
    <# Convert one v3/v4 PatchBaseline.Lines entry into the runtime shape. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)]$Line)

    $fileName = [string]$Line.FileName
    $fileNameOrigin = $(if (-not [string]::IsNullOrWhiteSpace($fileName)) { 'Explicit' } else { 'Unresolved' })
    if ([string]::IsNullOrWhiteSpace($fileName) -and $Line.DownloadUrl) {
        try {
            $fileName = [System.IO.Path]::GetFileName(([Uri]$Line.DownloadUrl).AbsolutePath)
            if (-not [string]::IsNullOrWhiteSpace($fileName)) { $fileNameOrigin = 'DownloadUrl' }
        } catch {
            $fileName = ''
            $fileNameOrigin = 'Unresolved'
        }
    }
    # Do not synthesize "KBxxxxxxx.msu" for metadata-only selectors.  It is
    # a landing-path label, not a Catalog identity, and r12.19 incorrectly
    # enforced it as an exact filename during P04.

    $expectedHashes = @{}
    $sha1 = Get-BaselineHashValue -Line $Line -Algorithm Sha1
    $sha256 = Get-BaselineHashValue -Line $Line -Algorithm Sha256
    if ($sha1)   { $expectedHashes['sha-1'] = $sha1 } # psa-disable-line PSA5003 -- Catalog compatibility
    if ($sha256) { $expectedHashes['sha-256'] = $sha256 }

    $roles = @()
    if ($Line.PSObject.Properties['Roles'] -and $Line.Roles) { $roles = @($Line.Roles) }
    $targetsByRole = $null
    if ($Line.PSObject.Properties['TargetsByRole']) { $targetsByRole = $Line.TargetsByRole }
    $applicability = $null
    if ($Line.PSObject.Properties['Applicability']) { $applicability = $Line.Applicability }
    $runtimeSelector = $null
    if ($Line.PSObject.Properties['RuntimeSelector']) { $runtimeSelector = $Line.RuntimeSelector }
    $dependencies = @()
    if ($Line.PSObject.Properties['Dependencies'] -and $Line.Dependencies) { $dependencies = @($Line.Dependencies) }

    return [pscustomobject][ordered]@{
        Kind             = 'Patch'
        PackageId        = $(if ($Line.PSObject.Properties['PackageId']) { [string]$Line.PackageId } else { '' })
        Source           = [string]$Line.DownloadUrl
        FileName         = $fileName
        FileNameOrigin   = $fileNameOrigin
        LocalPath        = $(if ($fileName) { Get-PatchLocalPath -Kind ([string]$Line.Kind) -FileName $fileName } else { '' })
        KbId             = [string]$Line.KbId
        ParentKbId       = $(if ($Line.PSObject.Properties['ParentKbId']) { [string]$Line.ParentKbId } else { '' })
        PatchType        = [string]$Line.Kind
        ApplyOrder       = $(if ($null -ne $Line.ApplyOrder) { [int]$Line.ApplyOrder } else { 99 })
        ExpectedHashes   = $expectedHashes
        Roles            = $roles
        TargetsByRole    = $targetsByRole
        Applicability    = $applicability
        RuntimeSelector  = $runtimeSelector
        Dependencies     = $dependencies
        BaselineState    = $(if ($Line.PSObject.Properties['State']) { [string]$Line.State } else { 'LegacyResolved' })
        State            = $(if ($Line.PSObject.Properties['State']) { [string]$Line.State } else { 'LegacyResolved' })
        ReleaseDate      = $(if ($Line.PSObject.Properties['ReleaseDate']) { [string]$Line.ReleaseDate } else { '' })
        Title            = $(if ($Line.PSObject.Properties['Title']) { [string]$Line.Title } else { '' })
        Products         = $(if ($Line.PSObject.Properties['Products']) { $Line.Products } else { $null })
        IsMetadataOnly   = ([string]::IsNullOrWhiteSpace([string]$Line.DownloadUrl) -or [string]::IsNullOrWhiteSpace($fileName))
    }
}

function ConvertTo-SourcePrerequisiteResolvedPatch {
    <#
    .SYNOPSIS
        Convert a v4 SourcePrerequisites entry into a conditional runtime
        patch. Metadata-only entries remain in the plan so the mounted-image
        condition can be evaluated; if applicable but unresolved, the build
        fails with an actionable message instead of silently omitting it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)]$Prerequisite)

    $asset = $null
    if ($Prerequisite.PSObject.Properties['Asset']) { $asset = $Prerequisite.Asset }
    $kind = [string]$Prerequisite.Kind
    if ($kind -eq 'BridgeLCU') { $kind = 'BridgeLcu' }
    if ($kind -eq 'CheckpointChain') { $kind = 'Checkpoint' }

    $fileName = ''
    $source = ''
    $expectedHashes = @{}
    if ($asset) {
        if ($asset.PSObject.Properties['FileName']) { $fileName = [string]$asset.FileName }
        if ($asset.PSObject.Properties['DownloadUrl']) { $source = [string]$asset.DownloadUrl }
        $sha1 = Get-BaselineHashValue -Line $asset -Algorithm Sha1
        $sha256 = Get-BaselineHashValue -Line $asset -Algorithm Sha256
        if ($sha1) { $expectedHashes['sha-1'] = $sha1 } # psa-disable-line PSA5003 -- Catalog compatibility
        if ($sha256) { $expectedHashes['sha-256'] = $sha256 }
    }

    $targetsByRole = [ordered]@{}
    foreach ($role in @($Prerequisite.Roles)) {
        $targetsByRole[[string]$role] = @($Prerequisite.Targets)
    }

    return [pscustomobject][ordered]@{
        Kind             = 'Patch'
        PackageId        = [string]$Prerequisite.PrerequisiteId
        Source           = $source
        LocalPath        = $(if ($fileName) { Get-PatchLocalPath -Kind $kind -FileName $fileName } else { '' })
        KbId             = [string]$Prerequisite.KbId
        ParentKbId       = ''
        PatchType        = $kind
        ApplyOrder       = 0
        ExpectedHashes   = $expectedHashes
        Roles            = @($Prerequisite.Roles)
        TargetsByRole    = [pscustomobject]$targetsByRole
        Applicability    = $Prerequisite.Condition
        RuntimeSelector  = $null
        Dependencies     = @()
        BaselineState    = [string]$Prerequisite.State
        IsMetadataOnly   = (-not $asset -or -not $fileName -or -not $source)
    }
}

function Get-PatchLocalPath {
    <#
    .SYNOPSIS
        Compute the on-disk landing path for one resolved patch file
        under <WorkRoot>\patches\<OS>\.
    .DESCRIPTION
        Kind 'LCU' and 'Checkpoint' land in the dedicated 'cu'
        subfolder (patches\<OS>\cu\); every other Kind stays in the
        flat per-OS folder. Rationale (MS checkpoint-cumulative
        contract): Add-WindowsPackage is invoked with the TARGET
        cumulative update only, and DISM uses the PackagePath FOLDER
        to discover prerequisite checkpoint MSUs -- Microsoft requires
        that ONLY the target cumulative update and its checkpoint
        cumulative updates be present in that folder (MS Learn
        'Checkpoint cumulative updates and the Microsoft Update
        Catalog'; per-KB pages, e.g. KB5094126). Isolating the CU
        family keeps .NET / SafeOS / SetupDU / SSU files out of the
        discovery folder. Offline pre-place contract follows the same
        layout: LCU + Checkpoint under patches\<OS>\cu\, everything
        else under patches\<OS>\.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Kind,
        [Parameter(Mandatory)] [string]$FileName
    )
    $osDir = Join-Path $Script:PatchesDir $Script:OsVersion
    if ($Kind -in @('LCU', 'Checkpoint')) {
        return (Join-Path (Join-Path $osDir 'cu') $FileName)
    }
    return (Join-Path $osDir $FileName)
}

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

function ConvertTo-PatchPlanTarget {
    <# Normalize schema-v4 target names to the script's existing plan buckets. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Target)
    switch ($Target) {
        'Media' { return 'Setup' }
        default { return $Target }
    }
}

function Build-PatchPlan {
    <# Construct a target plan from v4 roles, with v3 type fallback. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [array]$Patches)

    if (-not $Patches) { $Patches = @() }
    $plan = @{
        Install       = [System.Collections.Generic.List[object]]::new()
        Boot          = [System.Collections.Generic.List[object]]::new()
        WinRE         = [System.Collections.Generic.List[object]]::new()
        Setup         = [System.Collections.Generic.List[object]]::new()
        _GeneratedAt  = (Get-Date).ToString('o')
        _PatchCount   = 0
        _UnknownTypes = [System.Collections.Generic.List[string]]::new()
        _RoleCounts   = @{}
    }

    foreach ($p in $Patches) {
        if (-not $p) { continue }
        $type = Get-PatchEntryType -Patch $p
        $roles = @(Get-PatchRoles -Patch $p)
        foreach ($role in $roles) {
            if (-not $plan._RoleCounts.ContainsKey($role)) { $plan._RoleCounts[$role] = 0 }
            $plan._RoleCounts[$role] = [int]$plan._RoleCounts[$role] + 1
        }
        $targets = Get-PatchTargetsForEntry -Patch $p
        if ($roles.Count -eq 0 -and -not $Script:PatchTargetMap.ContainsKey($type) -and $type) {
            if ($plan._UnknownTypes -notcontains $type) { $plan._UnknownTypes.Add($type) | Out-Null }
        }
        foreach ($target in $targets) {
            $planTarget = ConvertTo-PatchPlanTarget -Target ([string]$target)
            if ($plan.ContainsKey($planTarget)) { $plan[$planTarget].Add($p) | Out-Null }
        }
        $plan._PatchCount++
    }

    foreach ($target in @('Install','Boot','WinRE','Setup')) {
        $plan[$target] = @($plan[$target] | Sort-Object `
            @{ Expression={ if ($_.PSObject.Properties['ApplyOrder']) { [int]$_.ApplyOrder } else { 99 } } }, `
            @{ Expression='KbId' })
    }
    $plan['_TargetCounts'] = @{
        Install = $plan.Install.Count
        Boot    = $plan.Boot.Count
        WinRE   = $plan.WinRE.Count
        Setup   = $plan.Setup.Count
    }
    $plan['InstallSequence'] = Build-InstallApplySequence -InstallPatches $plan.Install
    $plan['BootSequence']    = Build-BootApplySequence -BootPatches $plan.Boot
    $plan['WinReSequence']   = Build-WinReApplySequence -WinRePatches $plan.WinRE
    return $plan
}

function Get-PatchEntryType {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Patch)
    if (-not $Patch) { return '' }
    if ($Patch.PSObject.Properties['PatchType'] -and $Patch.PatchType) { return [string]$Patch.PatchType }
    if ($Patch.PSObject.Properties['Kind'] -and $Patch.Kind) { return [string]$Patch.Kind }
    if ($Patch.PSObject.Properties['Type'] -and $Patch.Type) { return [string]$Patch.Type }
    return ''
}

function Get-PatchRoles {
    <# Return canonical servicing roles, deriving them for a v3 entry. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowNull()]$Patch)
    if (-not $Patch) { return [string[]]@() }
    if ($Patch.PSObject.Properties['Roles'] -and $Patch.Roles -and @($Patch.Roles).Count -gt 0) {
        return [string[]]@($Patch.Roles | ForEach-Object { [string]$_ })
    }
    switch (Get-PatchEntryType -Patch $Patch) {
        'SSU'                     { return [string[]]@('ServicingStackCarrier') }
        'BridgeLcu'               { return [string[]]@('SourcePrerequisite') }
        'LCU'                     { return [string[]]@('FinalLCU') }
        'Checkpoint'              { return [string[]]@('CheckpointDependency') }
        'DotNet'                  { return [string[]]@('DotNetLeaf') }
        'SafeOSDU'                { return [string[]]@('SafeOSDU') }
        'SetupDU'                 { return [string[]]@('SetupDU') }
        'LanguagePack'            { return [string[]]@('LanguagePack') }
        'LXP'                     { return [string[]]@('LXP') }
        'DotNet.LangPack'         { return [string[]]@('DotNetLanguagePack') }
        'DynamicUpdate.Component' { return [string[]]@('DynamicUpdateComponent') }
    }
    return [string[]]@()
}

function Get-PatchTargetsForRole {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Patch,
        [Parameter(Mandatory)][string]$Role
    )
    if ($Patch.PSObject.Properties['TargetsByRole'] -and $Patch.TargetsByRole) {
        $prop = $Patch.TargetsByRole.PSObject.Properties[$Role]
        if ($prop -and $prop.Value) { return [string[]]@($prop.Value) }
    }
    switch ($Role) {
        'SourcePrerequisite'     { return (Get-PatchTargetsForType -PatchType (Get-PatchEntryType -Patch $Patch)) }
        'ServicingStackCarrier'  { return [string[]]@('Install','Boot','WinRE') }
        'FinalLCU'               { return [string[]]@('Install','Boot') }
        'CheckpointDependency'   { return [string[]]@() }
        'DotNetLeaf'             { return [string[]]@('Install') }
        'SafeOSDU'               { return [string[]]@('WinRE') }
        'SetupDU'                { return [string[]]@('Setup') }
        'LanguagePack'           { return [string[]]@('Install','WinRE') }
        'WinPeLanguagePack'      { return [string[]]@('Boot') }
        'WinReLanguagePack'      { return [string[]]@('WinRE') }
        'LXP'                    { return [string[]]@('Install') }
        'DotNetLanguagePack'     { return [string[]]@('Install') }
        'DynamicUpdateComponent'{ return [string[]]@('Install') }
    }
    return [string[]]@()
}

function Get-PatchTargetsForEntry {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Patch)
    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($role in (Get-PatchRoles -Patch $Patch)) {
        foreach ($target in (Get-PatchTargetsForRole -Patch $Patch -Role $role)) {
            if ($targets -notcontains $target) { $targets.Add($target) | Out-Null }
        }
    }
    if ($targets.Count -eq 0) {
        $type = Get-PatchEntryType -Patch $Patch
        foreach ($target in (Get-PatchTargetsForType -PatchType $type)) {
            if ($targets -notcontains $target) { $targets.Add($target) | Out-Null }
        }
    }
    return [string[]]$targets.ToArray()
}

function Test-PatchHasRole {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)]$Patch, [Parameter(Mandatory)][string]$Role)
    return ((Get-PatchRoles -Patch $Patch) -contains $Role)
}

function Get-PatchesForRole {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Patches,
        [Parameter(Mandatory)][string[]]$Roles
    )
    return @($Patches | Where-Object {
        $entry = $_
        $matched = $false
        foreach ($role in $Roles) {
            if (Test-PatchHasRole -Patch $entry -Role $role) { $matched = $true; break }
        }
        $matched
    })
}


function Test-PatchSetsShareAsset {
    <# True when the two role sets contain the same KB/package asset. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyCollection()][array]$First,
        [AllowEmptyCollection()][array]$Second
    )
    foreach ($a in @($First)) {
        foreach ($b in @($Second)) {
            if (-not $a -or -not $b) { continue }
            $aId = if ($a.PSObject.Properties['PackageId'] -and $a.PackageId) { [string]$a.PackageId } else { '' }
            $bId = if ($b.PSObject.Properties['PackageId'] -and $b.PackageId) { [string]$b.PackageId } else { '' }
            if ($aId -and $bId -and $aId -eq $bId) { return $true }
            if ($a.KbId -and $b.KbId -and ([string]$a.KbId -eq [string]$b.KbId)) { return $true }
            if ($a.LocalPath -and $b.LocalPath -and ([string]$a.LocalPath -eq [string]$b.LocalPath)) { return $true }
        }
    }
    return $false
}

function Get-FileSha256OrEmpty {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant())
}

function Read-ReleaseJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-CanonicalJson)
}

function New-ResolvedPatchEvidenceManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($p in @($Script:ResolvedPatches | Sort-Object -Property @('Kind','KbId','PackageId'))) {
        $localPath = if ($p.PSObject.Properties['LocalPath']) { [string]$p.LocalPath } else { '' }
        $integritySha = ''
        if ($p.PSObject.Properties['Integrity'] -and $p.Integrity -and $p.Integrity.PSObject.Properties['Sha256'] -and $p.Integrity.Sha256) {
            if ($p.Integrity.Sha256 -is [string]) { $integritySha = [string]$p.Integrity.Sha256 }
            elseif ($p.Integrity.Sha256.PSObject.Properties['Hex']) { $integritySha = [string]$p.Integrity.Sha256.Hex }
            elseif ($p.Integrity.Sha256.PSObject.Properties['Value']) { $integritySha = [string]$p.Integrity.Sha256.Value }
        }
        $entryType = Get-PatchEntryType -Patch $p
        $items.Add([pscustomobject][ordered]@{
            PackageId=[string]$p.PackageId
            Kind=$entryType
            PatchType=$entryType
            ObjectKind=$(if ($p.PSObject.Properties['Kind']) { [string]$p.Kind } else { '' })
            KbId=[string]$p.KbId
            ParentKbId=$(if ($p.PSObject.Properties['ParentKbId']) { [string]$p.ParentKbId } else { '' })
            UpdateId=$(if ($p.PSObject.Properties['UpdateId']) { [string]$p.UpdateId } else { '' })
            Revision=$(if ($p.PSObject.Properties['Revision']) { [string]$p.Revision } else { '' })
            ReleaseDate=$(if ($p.PSObject.Properties['ReleaseDate']) { [string]$p.ReleaseDate } else { '' })
            FileName=$(if ($p.PSObject.Properties['FileName']) { [string]$p.FileName } else { '' })
            FileNameOrigin=$(if ($p.PSObject.Properties['FileNameOrigin']) { [string]$p.FileNameOrigin } else { '' })
            Source=$(if ($p.PSObject.Properties['Source']) { [string]$p.Source } else { '' })
            LocalPath=$localPath
            IsMetadataOnly=[bool]($p.PSObject.Properties['IsMetadataOnly'] -and $p.IsMetadataOnly)
            SizeBytes=$(if ($p.PSObject.Properties['SizeBytes'] -and $null -ne $p.SizeBytes) { [long]$p.SizeBytes } else { $null })
            DeclaredSha256=$integritySha
            LocalAssetSha256=(Get-FileSha256OrEmpty -Path $localPath)
        }) | Out-Null
    }
    return [pscustomobject][ordered]@{
        SchemaVersion='release-patch-manifest/1.2'
        RunId=$Script:RunId
        OsKey=[string]$Script:OsVersion
        OsLanguage=[string]$Script:OsLanguage
        BaselineId=$(if ($Script:OsProfile -and $Script:OsProfile.PatchBaseline) { [string]$Script:OsProfile.PatchBaseline.BaselineId } else { '' })
        CreatedAtUtc=([datetime]::UtcNow.ToString('o'))
        Patches=$items.ToArray()
    }
}

function Get-ReleaseEvidenceIdentity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string]$OutputIsoPath=$Script:OutputIsoPath)
    if ([string]::IsNullOrWhiteSpace($OutputIsoPath) -or -not (Test-Path -LiteralPath $OutputIsoPath -PathType Leaf)) {
        throw 'Release evidence identity cannot be created because the output ISO is missing.'
    }
    $configPath = Get-OsConfigPath -OsKey $Script:OsVersion
    $manifestPath = Join-Path $Script:LogsDir 'resolved_patch_manifest.json'
    return [pscustomobject][ordered]@{
        SchemaVersion='release-evidence-identity/1.0'
        RunId=[string]$Script:RunId
        OsKey=[string]$Script:OsVersion
        OsLanguage=[string]$Script:OsLanguage
        BaselineId=$(if ($Script:OsProfile -and $Script:OsProfile.PatchBaseline) { [string]$Script:OsProfile.PatchBaseline.BaselineId } else { '' })
        OutputIsoPath=[System.IO.Path]::GetFullPath($OutputIsoPath)
        OutputIsoSha256=(Get-FileSha256OrEmpty -Path $OutputIsoPath)
        ScriptSha256=(Get-FileSha256OrEmpty -Path $PSCommandPath)
        ConfigPath=$configPath
        ConfigSha256=(Get-FileSha256OrEmpty -Path $configPath)
        ResolvedPatchManifestPath=$manifestPath
        ResolvedPatchManifestSha256=(Get-FileSha256OrEmpty -Path $manifestPath)
    }
}

function Test-ReleaseEvidenceIdentity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual
    )
    $mismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($field in @('RunId','OsKey','OsLanguage','BaselineId','OutputIsoSha256','ScriptSha256','ConfigSha256','ResolvedPatchManifestSha256')) {
        $e = if ($Expected.PSObject.Properties[$field]) { [string]$Expected.$field } else { '' }
        $a = if ($Actual.PSObject.Properties[$field]) { [string]$Actual.$field } else { '' }
        if ([string]::IsNullOrWhiteSpace($e) -or [string]::IsNullOrWhiteSpace($a) -or $e -ne $a) {
            $mismatches.Add(('{0}: expected="{1}" actual="{2}"' -f $field,$e,$a)) | Out-Null
        }
    }
    return [pscustomobject]@{ Match=($mismatches.Count -eq 0); Mismatches=$mismatches.ToArray() }
}

function Write-ReleaseEvidenceMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Identity,
        [Parameter(Mandatory)][string]$EvidencePath,
        [string]$Status='Pass',
        [string]$ApprovalPath=''
    )
    $markerPath = Join-Path $Script:MarkersDir $Name
    $marker = [pscustomobject][ordered]@{
        SchemaVersion='release-evidence-marker/1.0'
        Phase=[System.IO.Path]::GetFileNameWithoutExtension($Name)
        Status=$Status
        CreatedAtUtc=([datetime]::UtcNow.ToString('o'))
        Identity=$Identity
        EvidencePath=$EvidencePath
        EvidenceSha256=(Get-FileSha256OrEmpty -Path $EvidencePath)
        ApprovalPath=$ApprovalPath
        ApprovalSha256=(Get-FileSha256OrEmpty -Path $ApprovalPath)
    }
    Save-CanonicalJsonFile -InputObject $marker -Path $markerPath -Depth 12
    return $marker
}

function Get-StaticVerificationAssessment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $markerPath = Join-Path $Script:MarkersDir 'P11.ok'
    $evidencePath = Join-Path $Script:LogsDir 'P11_static_verification.json'
    $marker = Read-ReleaseJsonFile -Path $markerPath
    $evidence = Read-ReleaseJsonFile -Path $evidencePath
    if (-not $marker -or -not $evidence) {
        return [pscustomobject]@{ Eligible=$false; Status='Unknown'; Reason='P11 identity-bound static verification evidence is missing.' }
    }
    try { $current = Get-ReleaseEvidenceIdentity } catch {
        return [pscustomobject]@{ Eligible=$false; Status='Fail'; Reason=$_.Exception.Message }
    }
    $identityCheck = Test-ReleaseEvidenceIdentity -Expected $marker.Identity -Actual $current
    $hashOk = ([string]$marker.EvidenceSha256 -eq (Get-FileSha256OrEmpty -Path $evidencePath))
    $status=[string]$evidence.Status
    $policyPath=if($evidence.PSObject.Properties['PolicyExceptionEvidencePath']){[string]$evidence.PolicyExceptionEvidencePath}else{''}
    $policyHash=if($evidence.PSObject.Properties['PolicyExceptionEvidenceSha256']){[string]$evidence.PolicyExceptionEvidenceSha256}else{''}
    $policyCount=if($evidence.PSObject.Properties['PolicyExceptionCount']){[int]$evidence.PolicyExceptionCount}else{0}
    $policyValid=($status -eq 'PolicyException' -and $policyCount -gt 0 -and -not [string]::IsNullOrWhiteSpace($policyPath) -and (Test-Path -LiteralPath $policyPath -PathType Leaf) -and $policyHash -eq (Get-FileSha256OrEmpty -Path $policyPath))
    $acceptedStatus=($status -eq 'Pass' -or $policyValid)
    $eligible=$identityCheck.Match -and $hashOk -and $acceptedStatus
    $reason = if ($eligible -and $policyValid) { 'P11 accepted an explicit boot.wim source-preservation policy exception; P14 Install validation is mandatory.' } elseif ($eligible) { '' } elseif (-not $identityCheck.Match) { 'P11 evidence identity mismatch: ' + ($identityCheck.Mismatches -join '; ') } elseif (-not $hashOk) { 'P11 evidence file hash does not match P11.ok.' } elseif ($status -eq 'PolicyException') { 'P11 policy-exception evidence is missing or its SHA-256 does not match.' } else { 'P11 static verification status is neither Pass nor an accepted PolicyException.' }
    return [pscustomobject]@{ Eligible=$eligible; Status=$(if($eligible){$status}else{'Fail'}); RequiresInstallValidation=$policyValid; PolicyExceptionEvidencePath=$policyPath; Reason=$reason }
}

function Get-AuxiliaryFreshnessAssessment {
    <#
    .SYNOPSIS
        Assess monthly .NET freshness using both resolved patch metadata and
        the actual per-index servicing inventory emitted by P07.

    .DESCRIPTION
        A resolved patch object is a generic Kind='Patch' object whose
        servicing role is held in PatchType. r12.20 filtered Kind='DotNet'
        and therefore missed every runtime selector. This implementation uses
        Get-PatchEntryType and distinguishes three execution outcomes:

          Fresh         - every applicable .NET package is current.
          NotApplicable - the selected standalone runtime is absent from all
                          install.wim indexes; this is an acceptable item
                          outcome and does not block static eligibility.
          Unknown       - inventory, release date, or execution evidence is
                          missing/inconsistent.

        The aggregate Status remains Fresh/Stale/Unknown. An all-
        NotApplicable .NET set aggregates to Fresh because there is no stale
        applicable runtime on the media.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $issues = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()
    $staleItems = [System.Collections.Generic.List[object]]::new()
    $baselineMonth = ''

    if ($Script:OsProfile -and $Script:OsProfile.PatchBaseline -and $Script:OsProfile.PatchBaseline.PSObject.Properties['BaselineId']) {
        $rawBaseline = [string]$Script:OsProfile.PatchBaseline.BaselineId
        if ($rawBaseline -match '^(\d{4}-\d{2})(?:-B)?$') {
            $baselineMonth = $Matches[1]
        } else {
            $issues.Add([pscustomobject]@{Kind='Baseline';KbId='';ReleaseMonth='';BaselineMonth='';Issue='BaselineId is missing or malformed.'}) | Out-Null
        }
    } else {
        $issues.Add([pscustomobject]@{Kind='Baseline';KbId='';ReleaseMonth='';BaselineMonth='';Issue='PatchBaseline.BaselineId is unavailable.'}) | Out-Null
    }

    $dotNet = @($Script:ResolvedPatches | Where-Object { (Get-PatchEntryType -Patch $_) -eq 'DotNet' })
    if ($dotNet.Count -eq 0) {
        $issues.Add([pscustomobject]@{Kind='DotNet';KbId='';ReleaseMonth='';BaselineMonth=$baselineMonth;Issue='No resolved .NET package was available for freshness assessment.'}) | Out-Null
    }

    $inventoryPath = Join-Path $Script:LogsDir 'P05_patch_inventory.csv'
    $inventory = @()
    if (Test-Path -LiteralPath $inventoryPath -PathType Leaf) {
        try {
            $inventory = @(Import-Csv -LiteralPath $inventoryPath -Encoding UTF8 -ErrorAction Stop)
        } catch {
            $issues.Add([pscustomobject]@{Kind='DotNet';KbId='';ReleaseMonth='';BaselineMonth=$baselineMonth;Issue=('P07 patch inventory could not be read: {0}' -f $_.Exception.Message)}) | Out-Null
        }
    } elseif ($dotNet.Count -gt 0) {
        $issues.Add([pscustomobject]@{Kind='DotNet';KbId='';ReleaseMonth='';BaselineMonth=$baselineMonth;Issue='P07 patch inventory is missing; .NET applicability cannot be proven.'}) | Out-Null
    }

    # Establish the exact install.wim index set that P07 was expected to
    # service. Prefer the in-memory WIM inventory and apply the same operator /
    # profile index filters used by P07. If P12 is reconstructed without that
    # state, derive the expected set from all install.wim rows in the P07 CSV,
    # not from the .NET rows alone (which would make incomplete evidence appear
    # complete).
    $expectedIndexIds = @()
    if ($Script:WimIndexInventory) {
        $expectedInventory = @($Script:WimIndexInventory)
        if (-not [string]::IsNullOrWhiteSpace([string]$Script:OnlyInstallWimIndexes)) {
            $wantedIndexes = @($Script:OnlyInstallWimIndexes -split ',' | ForEach-Object { [int]($_.Trim()) })
            $expectedInventory = @($expectedInventory | Where-Object { $wantedIndexes -contains [int]$_.ImageIndex })
        } elseif ($Script:OsProfile -and $Script:OsProfile.PSObject.Properties['InstallWimIndexes']) {
            $configuredIndexes = $Script:OsProfile.InstallWimIndexes
            $allIndexes = ([string]$configuredIndexes -eq 'all')
            if (-not $allIndexes -and $null -ne $configuredIndexes) {
                $wantedIndexes = @($configuredIndexes | ForEach-Object { [int]$_ })
                $expectedInventory = @($expectedInventory | Where-Object { $wantedIndexes -contains [int]$_.ImageIndex })
            }
        }
        $expectedIndexIds = @($expectedInventory | ForEach-Object { [string][int]$_.ImageIndex } | Sort-Object -Unique)
    }
    if ($expectedIndexIds.Count -eq 0 -and $inventory.Count -gt 0) {
        $expectedIndexIds = @($inventory | ForEach-Object {
            if ([string]$_.AppliesTo -match '^install\.wim:idx(\d+)$') { [string][int]$Matches[1] }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    }
    if ($dotNet.Count -gt 0 -and $expectedIndexIds.Count -eq 0) {
        $issues.Add([pscustomobject]@{Kind='DotNet';KbId='';ReleaseMonth='';BaselineMonth=$baselineMonth;Issue='Expected install.wim index set could not be established; .NET applicability cannot be proven.'}) | Out-Null
    }

    $successStatuses = @('Ok','OkAfterRetry','WinReServicingStackKnownIssue')
    foreach ($p in $dotNet) {
        $releaseMonth = ''
        if ($p.PSObject.Properties['ReleaseDate'] -and $p.ReleaseDate) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse([string]$p.ReleaseDate,[ref]$parsed)) {
                $releaseMonth = $parsed.ToString('yyyy-MM')
            }
        }

        $kbId = [string]$p.KbId
        $rows = @($inventory | Where-Object {
            [string]$_.KbId -eq $kbId -and
            [string]$_.PatchType -eq 'DotNet' -and
            [string]$_.AppliesTo -like 'install.wim:*'
        })
        $statuses = @($rows | ForEach-Object { [string]$_.ApplyStatus } | Sort-Object -Unique)
        $unexpected = @($statuses | Where-Object { $_ -notin ($successStatuses + @('NotApplicable')) })
        $applicableRows = @($rows | Where-Object { [string]$_.ApplyStatus -in $successStatuses })
        $notApplicableRows = @($rows | Where-Object { [string]$_.ApplyStatus -eq 'NotApplicable' })
        $observedIndexIds = @($rows | ForEach-Object {
            if ([string]$_.AppliesTo -match '^install\.wim:idx(\d+)$') { [string][int]$Matches[1] }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $duplicateIndexIds = @($rows | Group-Object AppliesTo | Where-Object { $_.Count -ne 1 } | ForEach-Object {
            if ([string]$_.Name -match '^install\.wim:idx(\d+)$') { [string][int]$Matches[1] }
        })
        $missingIndexIds = @($expectedIndexIds | Where-Object { $_ -notin $observedIndexIds })
        $unexpectedIndexIds = @($observedIndexIds | Where-Object { $_ -notin $expectedIndexIds })
        $coverageComplete = (
            $expectedIndexIds.Count -gt 0 -and
            $missingIndexIds.Count -eq 0 -and
            $unexpectedIndexIds.Count -eq 0 -and
            $duplicateIndexIds.Count -eq 0 -and
            $rows.Count -eq $expectedIndexIds.Count
        )
        $itemStatus = 'Unknown'
        $itemIssue = ''

        if ($rows.Count -eq 0) {
            $itemIssue = 'No install.wim applicability rows were recorded for this .NET package.'
        } elseif (-not $coverageComplete) {
            $itemIssue = ('Incomplete or inconsistent install.wim applicability coverage. Expected=[{0}] Observed=[{1}] Missing=[{2}] Unexpected=[{3}] Duplicate=[{4}].' -f
                ($expectedIndexIds -join ','), ($observedIndexIds -join ','), ($missingIndexIds -join ','), ($unexpectedIndexIds -join ','), ($duplicateIndexIds -join ','))
        } elseif ($unexpected.Count -gt 0) {
            $itemIssue = ('Unexpected P07 applicability status: {0}.' -f ($unexpected -join ', '))
        } elseif ($applicableRows.Count -eq 0 -and $notApplicableRows.Count -eq $rows.Count) {
            $itemStatus = 'NotApplicable'
        } elseif ([string]::IsNullOrWhiteSpace($releaseMonth)) {
            $itemIssue = 'ReleaseDate is missing or invalid for an applicable .NET package.'
        } elseif ([string]::IsNullOrWhiteSpace($baselineMonth)) {
            $itemIssue = 'OS baseline month is unavailable for an applicable .NET package.'
        } elseif ($releaseMonth -lt $baselineMonth) {
            $itemStatus = 'Stale'
            $itemIssue = 'Release month is older than the OS baseline month.'
        } else {
            $itemStatus = 'Fresh'
        }

        $item = [pscustomobject][ordered]@{
            Kind='DotNet'
            KbId=$kbId
            ReleaseMonth=$releaseMonth
            BaselineMonth=$baselineMonth
            Status=$itemStatus
            ExpectedInstallIndexCount=$expectedIndexIds.Count
            ExpectedInstallIndexIds=$expectedIndexIds
            ObservedInstallIndexCount=$observedIndexIds.Count
            ObservedInstallIndexIds=$observedIndexIds
            MissingInstallIndexIds=$missingIndexIds
            UnexpectedInstallIndexIds=$unexpectedIndexIds
            DuplicateInstallIndexIds=$duplicateIndexIds
            CoverageComplete=$coverageComplete
            ApplicableIndexCount=$applicableRows.Count
            NotApplicableIndexCount=$notApplicableRows.Count
            InventoryRowCount=$rows.Count
            ApplyStatuses=$statuses
            Issue=$itemIssue
        }
        $items.Add($item) | Out-Null

        if ($itemStatus -eq 'Stale') {
            $staleItems.Add($item) | Out-Null
            $issues.Add([pscustomobject]@{Kind='DotNet';KbId=$kbId;ReleaseMonth=$releaseMonth;BaselineMonth=$baselineMonth;Issue=$itemIssue}) | Out-Null
        } elseif ($itemStatus -eq 'Unknown') {
            $issues.Add([pscustomobject]@{Kind='DotNet';KbId=$kbId;ReleaseMonth=$releaseMonth;BaselineMonth=$baselineMonth;Issue=$itemIssue}) | Out-Null
        }
    }

    $status = if ($staleItems.Count -gt 0) { 'Stale' } elseif ($issues.Count -gt 0) { 'Unknown' } else { 'Fresh' }
    $applicableCount = @($items.ToArray() | Where-Object { $_.Status -in @('Fresh','Stale') }).Count
    $notApplicableCount = @($items.ToArray() | Where-Object { $_.Status -eq 'NotApplicable' }).Count

    return [pscustomobject][ordered]@{
        SchemaVersion='auxiliary-freshness/1.1'
        BaselineMonth=$baselineMonth
        Status=$status
        IsFresh=($status -eq 'Fresh')
        ApplicabilityStatus=$(if ($dotNet.Count -eq 0) { 'Unknown' } elseif ($applicableCount -gt 0) { 'Applicable' } elseif ($notApplicableCount -eq $dotNet.Count) { 'NotApplicable' } else { 'Unknown' })
        ApplicableItemCount=$applicableCount
        NotApplicableItemCount=$notApplicableCount
        Items=$items.ToArray()
        Issues=$issues.ToArray()
        StaleItems=$staleItems.ToArray()
        InventoryPath=$inventoryPath
    }
}

function Test-BootEvidenceArtifacts {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)]$Evidence)
    $issues = [System.Collections.Generic.List[string]]::new()
    $mode = if ($Evidence.PSObject.Properties['Mode']) { [string]$Evidence.Mode } else { '' }
    if (-not ($Evidence.PSObject.Properties['Success']) -or -not [bool]$Evidence.Success) {
        $issues.Add('P14 evidence does not report Success=true.') | Out-Null
    }
    if ($mode -eq 'BootOnly') {
        if (-not ($Evidence.PSObject.Properties['RequiresOperatorReview']) -or -not [bool]$Evidence.RequiresOperatorReview) {
            $issues.Add('BootOnly evidence must declare RequiresOperatorReview=true.') | Out-Null
        }
        $screens = @()
        if ($Evidence.PSObject.Properties['ScreenshotEvidence']) { $screens = @($Evidence.ScreenshotEvidence) }
        if ($screens.Count -eq 0) {
            $issues.Add('BootOnly evidence has no screenshot integrity records.') | Out-Null
        }
        foreach ($screen in $screens) {
            $path = if ($screen.PSObject.Properties['Path']) { [string]$screen.Path } else { '' }
            $expectedSha = if ($screen.PSObject.Properties['Sha256']) { [string]$screen.Sha256 } else { '' }
            if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                $issues.Add(('BootOnly screenshot is missing: {0}' -f $path)) | Out-Null
                continue
            }
            $actualSha = Get-FileSha256OrEmpty -Path $path
            if ([string]::IsNullOrWhiteSpace($expectedSha) -or $expectedSha -ne $actualSha) {
                $issues.Add(('BootOnly screenshot SHA256 mismatch: {0}' -f $path)) | Out-Null
            }
        }
    } elseif ($mode -eq 'Install') {
        if (-not ($Evidence.PSObject.Properties['GuestEvidence']) -or -not $Evidence.GuestEvidence) {
            $issues.Add('Install validation evidence has no guest evidence.') | Out-Null
        }
    } else {
        $issues.Add(('Unknown P14 evidence mode: {0}' -f $mode)) | Out-Null
    }
    return [pscustomobject]@{ Valid=($issues.Count -eq 0); Issues=$issues.ToArray() }
}

function Get-BootValidationAssessment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $markerPath = Join-Path $Script:MarkersDir 'P14.ok'
    $evidencePath = Join-Path $Script:LogsDir 'P14_hyperv_validation.json'
    $marker = Read-ReleaseJsonFile -Path $markerPath
    $evidence = Read-ReleaseJsonFile -Path $evidencePath
    if (-not $marker -or -not $evidence) {
        return [pscustomobject]@{ Performed=[bool]$evidence; Eligible=$false; Status=$(if($evidence){'ReviewRequired'}else{'NotPerformed'}); Mode=$(if($evidence -and $evidence.PSObject.Properties['Mode']){[string]$evidence.Mode}else{''}); Reason=$(if($evidence){'Boot evidence exists but has not been approved or InstallValidated.'}else{'Hyper-V or equivalent boot/install validation was not performed for this output ISO.'}) }
    }
    try { $current = Get-ReleaseEvidenceIdentity } catch {
        return [pscustomobject]@{ Performed=$true; Eligible=$false; Status='Fail'; Mode=$(if($evidence -and $evidence.PSObject.Properties['Mode']){[string]$evidence.Mode}else{''}); Reason=$_.Exception.Message }
    }
    $identityCheck = Test-ReleaseEvidenceIdentity -Expected $marker.Identity -Actual $current
    $hashOk = ([string]$marker.EvidenceSha256 -eq (Get-FileSha256OrEmpty -Path $evidencePath))
    $artifactCheck = Test-BootEvidenceArtifacts -Evidence $evidence
    $approvalRequired = ([string]$evidence.Mode -eq 'BootOnly')
    $approvalHashOk = $true
    if ($approvalRequired) {
        $approvalPath = if ($marker.PSObject.Properties['ApprovalPath']) { [string]$marker.ApprovalPath } else { '' }
        $approvalHash = if ($marker.PSObject.Properties['ApprovalSha256']) { [string]$marker.ApprovalSha256 } else { '' }
        $approvalHashOk = (-not [string]::IsNullOrWhiteSpace($approvalPath)) -and `
            (Test-Path -LiteralPath $approvalPath -PathType Leaf) -and `
            (-not [string]::IsNullOrWhiteSpace($approvalHash)) -and `
            ($approvalHash -eq (Get-FileSha256OrEmpty -Path $approvalPath))
    }
    $eligible = $identityCheck.Match -and $hashOk -and $artifactCheck.Valid -and $approvalHashOk -and ([string]$marker.Status -eq 'Pass')
    $reason = if ($eligible) { '' } `
        elseif (-not $identityCheck.Match) { 'P14 evidence identity mismatch: ' + ($identityCheck.Mismatches -join '; ') } `
        elseif (-not $hashOk) { 'P14 evidence file hash does not match P14.ok.' } `
        elseif (-not $artifactCheck.Valid) { 'P14 evidence artifact validation failed: ' + ($artifactCheck.Issues -join '; ') } `
        elseif (-not $approvalHashOk) { 'BootOnly approval evidence is missing or its SHA256 does not match P14.ok.' } `
        else { 'P14 evidence is not approved.' }
    return [pscustomobject]@{ Performed=$true; Eligible=$eligible; Status=$(if($eligible){'Pass'}else{'Fail'}); Mode=[string]$evidence.Mode; Reason=$reason }
}

function Save-ReleaseEvidenceIndex {
    [CmdletBinding()]
    param()
    $identity = Get-ReleaseEvidenceIdentity
    $p11Path = Join-Path $Script:LogsDir 'P11_static_verification.json'
    $p12Path = Join-Path $Script:LogsDir 'P12_release_assessment.json'
    $p14Path = Join-Path $Script:LogsDir 'P14_hyperv_validation.json'
    $index = [pscustomobject][ordered]@{
        SchemaVersion='release-evidence-index/1.1'
        UpdatedAtUtc=([datetime]::UtcNow.ToString('o'))
        Identity=$identity
        ReleaseEligibility=$Script:ReleaseEligibility
        Evidence=[pscustomobject][ordered]@{
            P11=$(if (Test-Path -LiteralPath $p11Path -PathType Leaf) { $p11Path } else { $null })
            P12=$(if (Test-Path -LiteralPath $p12Path -PathType Leaf) { $p12Path } else { $null })
            P14=$(if (Test-Path -LiteralPath $p14Path -PathType Leaf) { $p14Path } else { $null })
        }
    }
    Save-CanonicalJsonFile -InputObject $index -Path (Join-Path $Script:LogsDir 'release_evidence_index.json') -Depth 16
    return $index
}

function Initialize-BootTestState {
    [CmdletBinding()]
    param()
    $indexPath = Join-Path $Script:LogsDir 'release_evidence_index.json'
    $index = Read-ReleaseJsonFile -Path $indexPath
    if (-not $index -or -not $index.Identity) {
        throw ('Standalone BootTest requires identity-bound P11/P12 evidence: {0}' -f $indexPath)
    }
    $Script:RunId = [string]$index.Identity.RunId
    $Script:OsVersion = [string]$index.Identity.OsKey
    $Script:OsLanguage = [string]$index.Identity.OsLanguage
    $Script:OsProfile = Get-ConfigProfile -OsKey $Script:OsVersion -OsLang $Script:OsLanguage
    $candidate = if ($Script:BootTestIsoPath) { Resolve-RelativeToScript $Script:BootTestIsoPath } else { [string]$index.Identity.OutputIsoPath }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw ('BootTest ISO not found: {0}' -f $candidate) }
    $Script:OutputIsoPath = $candidate
    $Script:ReleaseEligibility = $index.ReleaseEligibility
    $current = Get-ReleaseEvidenceIdentity -OutputIsoPath $candidate
    $match = Test-ReleaseEvidenceIdentity -Expected $index.Identity -Actual $current
    if (-not $match.Match) { throw ('BootTest evidence identity mismatch: {0}' -f ($match.Mismatches -join '; ')) }
}

function Test-BootEvidenceApproval {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ApprovalPath,
        [Parameter(Mandatory)][string]$EvidencePath,
        [Parameter(Mandatory)]$Identity
    )
    $approval = Read-ReleaseJsonFile -Path $ApprovalPath
    if (-not $approval) { return [pscustomobject]@{Valid=$false;Reason='Approval file is missing or invalid JSON.';Approval=$null} }
    $issues = [System.Collections.Generic.List[string]]::new()
    if ([string]$approval.SchemaVersion -ne 'P14-boot-approval-request/1.0') { $issues.Add('SchemaVersion must be P14-boot-approval-request/1.0.') | Out-Null }
    if ([string]$approval.Decision -ne 'Approve') { $issues.Add('Decision must be Approve.') | Out-Null }
    if ([string]$approval.RunId -ne [string]$Identity.RunId) { $issues.Add('RunId does not match.') | Out-Null }
    if ([string]$approval.OutputIsoSha256 -ne [string]$Identity.OutputIsoSha256) { $issues.Add('OutputIsoSha256 does not match.') | Out-Null }
    $evidenceSha = Get-FileSha256OrEmpty -Path $EvidencePath
    if ([string]$approval.P14EvidenceSha256 -ne $evidenceSha) { $issues.Add('P14EvidenceSha256 does not match.') | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$approval.ApprovedBy)) { $issues.Add('ApprovedBy is required.') | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$approval.ApprovedAtUtc)) {
        $issues.Add('ApprovedAtUtc is required.') | Out-Null
    } else {
        $approvedAt = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$approval.ApprovedAtUtc,[ref]$approvedAt)) {
            $issues.Add('ApprovedAtUtc is not a valid date/time.') | Out-Null
        }
    }
    return [pscustomobject]@{Valid=($issues.Count -eq 0);Reason=($issues -join ' ');Approval=$approval}
}

function Get-Pca2023CompliancePolicy {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $policy = ''
    if ($Script:OsProfile -and $Script:OsProfile.PSObject.Properties['Pca2023'] -and
        $Script:OsProfile.Pca2023 -and $Script:OsProfile.Pca2023.PSObject.Properties['CompliancePolicy']) {
        $policy = [string]$Script:OsProfile.Pca2023.CompliancePolicy
    }
    if ([string]::IsNullOrWhiteSpace($policy)) {
        $policy = if ($Script:OsVersion -eq 'Server2025') { 'AuditOnly' } else { 'RequirePca2023' }
    }
    if ($policy -notin @('RequirePca2023','AllowLegacyPca2011','AuditOnly')) {
        throw ("Unknown Pca2023.CompliancePolicy '{0}'." -f $policy)
    }
    return $policy
}

function Test-Pca2023PolicyCompliance {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$OutputCheck,
        [Parameter(Mandatory)][ValidateSet('RequirePca2023','AllowLegacyPca2011','AuditOnly')][string]$Policy
    )
    $reasons = [System.Collections.Generic.List[string]]::new()
    $eligible = $true
    if (-not $OutputCheck -or -not $OutputCheck.Available) {
        $eligible = $false
        $reasons.Add('PCA2023 output inspection was unavailable.') | Out-Null
    } elseif ($Policy -eq 'RequirePca2023') {
        $critical = @($OutputCheck.TargetChecks | Where-Object { $_.Label -like 'Target #1*' }) | Select-Object -First 1
        $efisys   = @($OutputCheck.TargetChecks | Where-Object { $_.Label -like 'Target #3*' }) | Select-Object -First 1
        if (-not $critical -or -not $critical.IsPca2023) {
            $eligible = $false; $reasons.Add('UEFI critical-path boot manager is not PCA2023-signed.') | Out-Null
        }
        if (-not $efisys -or $efisys.Status -eq 'Fail') {
            $eligible = $false; $reasons.Add('PCA2023 efisys_ex.bin media payload is missing or invalid.') | Out-Null
        }
        if ($OutputCheck.OverallStatus -in @('Fail','Warning','Unknown')) {
            $eligible = $false; $reasons.Add(('Output readiness status is {0}.' -f $OutputCheck.OverallStatus)) | Out-Null
        }
    } elseif ($Policy -eq 'AllowLegacyPca2011') {
        $critical = @($OutputCheck.TargetChecks | Where-Object { $_.Label -like 'Target #1*' }) | Select-Object -First 1
        if (-not $critical -or ($critical.ActualSignature -notin @('PCA2011','PCA2023'))) {
            $eligible = $false; $reasons.Add('UEFI critical-path boot manager is missing or has an unknown signer.') | Out-Null
        }
    } else {
        # AuditOnly records the result without blocking output creation.
        $eligible = $true
        if ($OutputCheck.OverallStatus -ne 'Pass') {
            $reasons.Add(('Audit-only policy accepted readiness status {0}; not production approval.' -f $OutputCheck.OverallStatus)) | Out-Null
        }
    }
    return [pscustomobject]@{
        Policy          = $Policy
        ReleaseEligible = $eligible
        OverallStatus   = $(if ($OutputCheck) { $OutputCheck.OverallStatus } else { 'Unknown' })
        Reasons         = $reasons.ToArray()
    }
}

function Get-DismLogClassification {
    <# Classify the final operation result; do not promote benign CBS child-package noise. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyString()][string]$LogPath,
        [AllowEmptyString()][string]$OperationStatus = 'Ok'
    )
    $text = ''
    if ($LogPath -and (Test-Path -LiteralPath $LogPath)) {
        try { $text = Get-Content -LiteralPath $LogPath -Raw -ErrorAction Stop } catch { $text = '' }
    }

    # Restrict textual adjudication to the tail of the current DISM session.
    # CBS logs routinely contain child-package warnings and recoverable HRESULTs
    # even when the top-level Add-WindowsPackage operation succeeds.
    $tail = $text
    if ($tail.Length -gt 131072) { $tail = $tail.Substring($tail.Length - 131072) }
    $classes = [System.Collections.Generic.List[string]]::new()
    $successStatus = $OperationStatus -in @('Ok','OkAfterRetry','WinReServicingStackKnownIssue')
    $notApplicableStatus = $OperationStatus -eq 'NotApplicable'
    $terminalStatus = $OperationStatus -eq 'Fail'

    if ($notApplicableStatus) { $classes.Add('PackageNotApplicable') | Out-Null }
    if ($tail -match '(?im)(?:restart|reboot)\s+(?:is\s+)?required\s*[:=]\s*(?:yes|true|1)\b|\b(?:a\s+)?(?:restart|reboot)\s+is\s+required\b(?!\s*[:=]\s*(?:no|false|0)\b)') { $classes.Add('RebootRequired') | Out-Null }
    if ($tail -match '(?im)pending operation|Install Pending|pending\.xml') { $classes.Add('PendingOperation') | Out-Null }

    $topLevelFailure = $terminalStatus -or
        ($tail -match '(?im)DISM Package Manager:.*Error in operation|Add-WindowsPackage.*failed|The operation failed|HRESULT\s*=\s*0x8[0-9a-f]{7}')
    $topLevelSuccess = $successStatus -or ($tail -match '(?im)The operation completed successfully\.')

    if ($topLevelFailure -and -not $topLevelSuccess) {
        $classes.Add('TerminalOperationFailure') | Out-Null
    } elseif ($topLevelSuccess) {
        # Record provider warnings only when the final session tail explicitly
        # reports a warning outside CSI/CBS component chatter.
        if ($tail -match '(?im)^(?!.*\b(?:CSI|CBS)\b).*\bWarning\b.*$') {
            $classes.Add('ProviderWarning') | Out-Null
        }
        if ($OperationStatus -eq 'OkAfterRetry') { $classes.Add('RecoveredInternalError') | Out-Null }
    }

    if ($classes.Count -eq 0) { $classes.Add('CleanSuccess') | Out-Null }
    return [pscustomobject]@{
        LogPath          = $LogPath
        OperationStatus  = $OperationStatus
        Classifications  = $classes.ToArray()
        TerminalFailure  = (@($classes.ToArray()) -contains 'TerminalOperationFailure')
    }
}

function Write-DismLogClassificationEvidence {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$LogPath,
        [AllowEmptyString()][string]$OperationStatus='Ok',
        [string]$Context='',
        [hashtable]$Metadata=@{},
        [AllowNull()][object]$Exception,
        [switch]$DoNotThrow
    )
    $ev = Get-DismLogClassification -LogPath $LogPath -OperationStatus $OperationStatus
    if ($Script:LogsDir) {
        $path = Join-Path $Script:LogsDir 'dism_outcomes.jsonl'
        $record=[ordered]@{Timestamp=(Get-Date).ToString('o');Context=$Context;Evidence=$ev}
        foreach($key in @($Metadata.Keys)){ $record[$key]=$Metadata[$key] }
        if($Exception){$record['ExceptionType']=$Exception.GetType().FullName;$record['ExceptionMessage']=$Exception.Message;$record['HResult']=('0x{0:X8}' -f (([int64]$Exception.HResult) -band 0xFFFFFFFFL))}
        [pscustomobject]$record | ConvertTo-Json -Depth 7 -Compress | Add-Content -LiteralPath $path -Encoding UTF8
    }
    if ($ev.TerminalFailure -and -not $DoNotThrow) { throw ('DISM terminal failure classified for {0}; see {1}' -f $Context, $LogPath) }
    return $ev
}

function Write-DismRollbackEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Phase,[Parameter(Mandatory)][string]$Result,[string]$Context='',[AllowEmptyString()][string]$Error='')
    if(-not $Script:LogsDir){return}
    $path=Join-Path $Script:LogsDir 'dism_outcomes.jsonl'
    [pscustomobject][ordered]@{
        Timestamp=(Get-Date).ToString('o');Context=$Context;Phase=$Phase;Kind='Rollback'
        RollbackResult=$Result;Error=$Error
    }|ConvertTo-Json -Depth 5 -Compress|Add-Content -LiteralPath $path -Encoding UTF8
}

function Get-SetupDuFileManifest {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Root, [string]$DestinationRoot='')

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw ('Setup DU manifest root does not exist or is not a directory: {0}' -f $Root)
    }

    $trimChars = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $normalizedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd($trimChars)
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($file in @(Get-ChildItem -LiteralPath $normalizedRoot -File -Recurse -ErrorAction Stop)) {
        $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ('Setup DU manifest file escaped the declared root: {0}' -f $fullPath)
        }
        $rel = $fullPath.Substring($normalizedRoot.Length).TrimStart($trimChars)
        if ([string]::IsNullOrWhiteSpace($rel) -or $rel -match '(^|[\\/])\.\.([\\/]|$)') {
            throw ('Unsafe Setup DU relative path generated from {0}: {1}' -f $fullPath, $rel)
        }
        $dest = if ($DestinationRoot) { Join-Path $DestinationRoot $rel } else { '' }
        $ver = $null
        try { $ver = $file.VersionInfo.FileVersion } catch { $null = $_ }
        $rows.Add([pscustomobject]@{
            RelativePath=$rel; SourcePath=$fullPath; DestinationPath=$dest
            SizeBytes=$file.Length; Sha256=(Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLower()
            FileVersion=$ver
        }) | Out-Null
    }
    return $rows.ToArray()
}

function Get-BootWimPackageMode {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $mode = ''
    if ($Script:OsProfile -and $Script:OsProfile.PSObject.Properties['Common'] -and
        $Script:OsProfile.Common -and $Script:OsProfile.Common.PSObject.Properties['BootWimPackageMode']) {
        $mode = [string]$Script:OsProfile.Common.BootWimPackageMode
    }
    if ([string]::IsNullOrWhiteSpace($mode)) {
        $mode = if ($Script:OsVersion -eq 'Server2019') { 'ExpandedCab' } else { 'DirectMsu' }
    }
    if ($mode -notin @('DirectMsu','ExpandedCab')) {
        throw ('Unsupported Common.BootWimPackageMode: {0}' -f $mode)
    }
    return $mode
}

function Get-BootWimServicingStrategy {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $mode=Get-BootWimPackageMode
    $raw=''
    if($Script:OsProfile -and $Script:OsProfile.PSObject.Properties['BootWimServicingStrategy']){
        $raw=[string]$Script:OsProfile.BootWimServicingStrategy
    } elseif($Script:OsProfile -and $Script:OsProfile.Common -and $Script:OsProfile.Common.PSObject.Properties['BootWimServicingStrategy']){
        $raw=[string]$Script:OsProfile.Common.BootWimServicingStrategy
    }
    return (Resolve-BootWimServicingStrategyValue -RawValue $raw -PackageMode $mode)
}

function Get-ExpandedMsuCabPlan {
    <# Expand an MSU once and select only package-bearing CAB payloads. #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$MsuPath,
        [Parameter(Mandatory)][string]$KbId,
        [string]$ExpansionRoot = ''
    )
    if (-not (Test-Path -LiteralPath $MsuPath -PathType Leaf)) { throw ('MSU not found: {0}' -f $MsuPath) }
    if ([System.IO.Path]::GetExtension($MsuPath) -ine '.msu') { throw ('Expanded CAB mode requires an MSU: {0}' -f $MsuPath) }

    if ([string]::IsNullOrWhiteSpace($ExpansionRoot)) {
        $ExpansionRoot = if ($Script:TempDir) { $Script:TempDir } else { [System.IO.Path]::GetTempPath() }
    }
    $safeName = ([System.IO.Path]::GetFileNameWithoutExtension($MsuPath) -replace '[^A-Za-z0-9._-]','_')
    $expandRoot = Join-Path $ExpansionRoot ('expanded-msu\' + $safeName)
    $payloadRoot = Join-Path $expandRoot 'payload'
    $manifestPath = Join-Path $expandRoot 'cab-plan.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        if (Test-Path -LiteralPath $expandRoot) { Remove-Item -LiteralPath $expandRoot -Recurse -Force }
        New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
        Write-Step ('    Expanding MSU payload: {0}' -f [System.IO.Path]::GetFileName($MsuPath))
        & expand.exe -F:* $MsuPath $payloadRoot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw ('expand.exe failed for {0} with exit code {1}.' -f $MsuPath,$LASTEXITCODE) }

        $plan = [System.Collections.Generic.List[object]]::new()
        foreach ($cab in @(Get-ChildItem -LiteralPath $payloadRoot -File -Recurse -Filter '*.cab' -ErrorAction Stop)) {
            if ($cab.Name -match '(?i)wsusscan|express|delta|metadata') { continue }
            $mumRoot = Join-Path $expandRoot ('mum-' + [Guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $mumRoot -Force | Out-Null
            try {
                & expand.exe -F:*.mum $cab.FullName $mumRoot | Out-Null
                $mums = @(Get-ChildItem -LiteralPath $mumRoot -File -Recurse -Filter '*.mum' -ErrorAction SilentlyContinue)
                $mumNames = @($mums | ForEach-Object { $_.Name })
                $mumContent = @($mums | ForEach-Object {
                    try { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop } catch { '' }
                }) -join "`n"
                $joined = (($mumNames -join ';') + "`n" + $mumContent)
                $role = 'Unknown'
                $order = 90
                $hasSsu = $joined -match '(?i)ServicingStack'
                $hasLcu = $joined -match '(?i)RollupFix'
                if ($hasSsu -and $hasLcu) { $role='Combined'; $order=20 }
                elseif ($hasSsu) { $role='ServicingStack'; $order=10 }
                elseif ($hasLcu) { $role='RollupFix'; $order=30 }
                elseif ($cab.Name -match [regex]::Escape($KbId)) { $role='UpdatePayload'; $order=40 }
                if ($role -ne 'Unknown') {
                    $plan.Add([pscustomobject]@{ CabPath=$cab.FullName; FileName=$cab.Name; Role=$role; Order=$order; MumFiles=$mumNames }) | Out-Null
                }
            } finally {
                Remove-Item -LiteralPath $mumRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if ($plan.Count -eq 0) {
            foreach ($cab in @(Get-ChildItem -LiteralPath $payloadRoot -File -Recurse -Filter '*.cab' | Where-Object { $_.Name -match [regex]::Escape($KbId) -and $_.Name -notmatch '(?i)wsusscan' })) {
                $plan.Add([pscustomobject]@{ CabPath=$cab.FullName; FileName=$cab.Name; Role='UpdatePayload'; Order=40; MumFiles=@() }) | Out-Null
            }
        }
        if ($plan.Count -eq 0) { throw ('No package-bearing CAB payload was found in {0}.' -f $MsuPath) }
        $ordered = @($plan.ToArray() | Sort-Object Order,FileName)
        Save-CanonicalJsonFile -InputObject $ordered -Path $manifestPath -Depth 8
    }
    return @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json))
}

function Add-WindowsPackageFromExpandedMsu {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$MountPath,
        [Parameter(Mandatory)][string]$MsuPath,
        [Parameter(Mandatory)][string]$KbId,
        [string]$LogDir,
        [string[]]$CabRoles=@('ServicingStack','Combined','RollupFix','UpdatePayload'),
        [hashtable]$EvidenceMetadata=@{}
    )
    $plan = @(Get-ExpandedMsuCabPlan -MsuPath $MsuPath -KbId $KbId | Where-Object { $CabRoles -contains [string]$_.Role })
    if($plan.Count -eq 0){throw ('Expanded MSU has no CAB matching roles [{0}] for {1}.' -f ($CabRoles -join ','),$KbId)}
    if($CabRoles.Count -eq 1 -and $CabRoles[0] -eq 'Combined' -and $plan.Count -ne 1){
        throw ('ExpandedCombinedCab requires exactly one Combined CAB for {0}; found {1}.' -f $KbId,$plan.Count)
    }
    $statuses = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $plan) {
        Write-Step ('      Expanded MSU CAB [{0}]: {1}' -f $entry.Role, $entry.FileName)
        $meta=@{}; foreach($k in $EvidenceMetadata.Keys){$meta[$k]=$EvidenceMetadata[$k]};$meta['ExpandedCabRole']=[string]$entry.Role;$meta['ExpandedFromMsu']=[System.IO.Path]::GetFileName($MsuPath)
        $st = Add-WindowsPackageWithRetry -MountPath $MountPath -PackagePath ([string]$entry.CabPath) -LogDir $LogDir -EvidenceMetadata $meta
        $statuses.Add($st) | Out-Null
    }
    if (@($statuses.ToArray() | Where-Object { $_ -eq 'OkAfterRetry' }).Count -gt 0) { return 'OkAfterRetry' }
    if (@($statuses.ToArray() | Where-Object { $_ -notin @('Ok','NotApplicable') }).Count -gt 0) {
        throw ('Expanded MSU CAB application did not complete cleanly for {0}: {1}' -f $KbId, ($statuses.ToArray() -join ','))
    }
    return 'Ok'
}

function Get-ExpandedMsuCabRolesForSubPhase {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$SubPhaseName,
        [AllowEmptyString()][string]$ServicingStrategy=''
    )
    if($ServicingStrategy -eq 'ExpandedCombinedCab'){
        switch($SubPhaseName){
            'B1.ServicingStack' { return [string[]]@() }
            'B3.FinalLCU' { return [string[]]@('Combined') }
            default { return [string[]]@('Combined') }
        }
    }
    if($ServicingStrategy -eq 'ExpandedSplitCab'){
        switch($SubPhaseName){
            'B1.ServicingStack' { return [string[]]@('ServicingStack') }
            'B3.FinalLCU' { return [string[]]@('RollupFix','UpdatePayload') }
            default { return [string[]]@('ServicingStack','RollupFix','UpdatePayload') }
        }
    }
    # Backward-compatible contract used by historical regression fixtures.
    switch ($SubPhaseName) {
        'B1.ServicingStack' { return [string[]]@('ServicingStack') }
        'B3.FinalLCU' { return [string[]]@('Combined','RollupFix','UpdatePayload') }
        default { return [string[]]@('ServicingStack','Combined','RollupFix','UpdatePayload') }
    }
}

function Get-BootSequencePolicyDecision {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateSet('DirectMsu','ExpandedCab')][string]$PackageMode,
        [Parameter(Mandatory)][bool]$SameCombinedAsset,
        [int]$LanguagePackCount=0,
        [AllowEmptyString()][string]$ServicingStrategy=''
    )
    $strategy=Resolve-BootWimServicingStrategyValue -RawValue $ServicingStrategy -PackageMode $PackageMode
    $requiresRemount=$false
    $needsFinal=$false
    $suppressCarrier=$false
    switch($strategy){
        'DirectMsu' {
            $needsFinal=(-not $SameCombinedAsset) -or ($LanguagePackCount -gt 0)
        }
        'ExpandedCombinedCab' {
            # The combined CAB already contains the servicing-stack carrier.
            # Applying its sibling SSU CAB first duplicates that transaction
            # and produced 0x8007371b on measured Server 2019 boot.wim.
            $needsFinal=$true
            $suppressCarrier=$true
        }
        'ExpandedSplitCab' {
            $requiresRemount=$true
            $needsFinal=$true
        }
    }
    [pscustomobject]@{
        ServicingStrategy=$strategy
        RequiresServicingStackRemount=$requiresRemount
        NeedsFinalLcu=$needsFinal
        SuppressServicingStackCarrier=$suppressCarrier
        DuplicateApplySuppressed=($suppressCarrier -or (-not $needsFinal))
    }
}

function Build-InstallApplySequence {
    <#
    .SYNOPSIS
        Build the install.wim sequence from servicing roles.
    .DESCRIPTION
        Source prerequisite -> servicing-stack carrier -> language/FOD ->
        final LCU -> component cleanup -> .NET leaf. The same combined LCU
        asset can appear in the carrier and final-LCU phases without being
        downloaded twice. .NET is intentionally after cleanup.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [array]$InstallPatches)

    $prereq = Get-PatchesForRole -Patches $InstallPatches -Roles @('SourcePrerequisite')
    $stack  = Get-PatchesForRole -Patches $InstallPatches -Roles @('ServicingStackCarrier')
    $lp     = Get-PatchesForRole -Patches $InstallPatches -Roles @('LanguagePack','LXP','DotNetLanguagePack')
    $lcu    = Get-PatchesForRole -Patches $InstallPatches -Roles @('FinalLCU')
    $dyn    = Get-PatchesForRole -Patches $InstallPatches -Roles @('DynamicUpdateComponent')
    $dotnet = Get-PatchesForRole -Patches $InstallPatches -Roles @('DotNetLeaf')

    $seq = [System.Collections.Generic.List[object]]::new()
    $seq.Add([pscustomobject]@{ Name='I0.SourcePrerequisite'; Description='Source-media prerequisite, conditionally injected'; Patches=$prereq; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='I1.ServicingStack'; Description='Standalone SSU or combined-LCU servicing-stack carrier'; Patches=$stack; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='I2.LanguageFodOptional'; Description='Language/FOD/optional-component payloads'; Patches=$lp; RequiresRemount=$false }) | Out-Null
    $sameCombinedAsset = (Test-PatchSetsShareAsset -First $stack -Second $lcu)
    $needsFinalLcu = (-not $sameCombinedAsset) -or ($lp.Count -gt 0) -or ($dyn.Count -gt 0)
    $finalLcuSet = if ($needsFinalLcu) { $lcu } else { @() }
    $finalLcuReason = if ($needsFinalLcu) { 'Final cumulative update after language/component changes' } else { 'Skipped: combined LCU already applied and no intervening language/FOD/component changes occurred' }
    $seq.Add([pscustomobject]@{ Name='I3.FinalLCU'; Description=$finalLcuReason; Patches=$finalLcuSet; RequiresRemount=$false; DuplicateApplySuppressed=(-not $needsFinalLcu) }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='I4.DynamicUpdate.Component'; Description='Component-store Dynamic Update'; Patches=$dyn; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='I5.Cleanup'; Description='DISM /Cleanup-Image before .NET'; Patches=@(); RequiresRemount=$false; IsCleanupMarker=$true }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='I6.DotNet'; Description='.NET Framework cumulative leaf selected for the mounted index'; Patches=$dotnet; RequiresRemount=$false }) | Out-Null
    return $seq.ToArray()
}

function Build-BootApplySequence {
    [CmdletBinding()]
    [OutputType([array])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [array]$BootPatches)

    $prereq = Get-PatchesForRole -Patches $BootPatches -Roles @('SourcePrerequisite')
    $stack  = Get-PatchesForRole -Patches $BootPatches -Roles @('ServicingStackCarrier')
    $lp     = Get-PatchesForRole -Patches $BootPatches -Roles @('WinPeLanguagePack','LanguagePack')
    $lcu    = Get-PatchesForRole -Patches $BootPatches -Roles @('FinalLCU')

    $seq = [System.Collections.Generic.List[object]]::new()
    $seq.Add([pscustomobject]@{ Name='B0.SourcePrerequisite'; Description='Source-media prerequisite, conditionally injected'; Patches=$prereq; RequiresRemount=$false }) | Out-Null
    $packageMode = Get-BootWimPackageMode
    $servicingStrategy = Get-BootWimServicingStrategy
    $sameCombinedAsset = (Test-PatchSetsShareAsset -First $stack -Second $lcu)
    $policyDecision = Get-BootSequencePolicyDecision -PackageMode $packageMode -SameCombinedAsset $sameCombinedAsset -LanguagePackCount $lp.Count -ServicingStrategy $servicingStrategy
    $expandedBoot = ($servicingStrategy -in @('ExpandedCombinedCab','ExpandedSplitCab'))
    $stackSet = if($policyDecision.SuppressServicingStackCarrier){@()}else{$stack}
    $stackDescription = if($policyDecision.SuppressServicingStackCarrier){'Skipped: combined CAB is the sole servicing transaction'}else{'Standalone SSU or combined-LCU servicing-stack carrier'}
    $seq.Add([pscustomobject]@{ Name='B1.ServicingStack'; Description=$stackDescription; Patches=$stackSet; RequiresRemount=$policyDecision.RequiresServicingStackRemount; DuplicateApplySuppressed=$policyDecision.SuppressServicingStackCarrier; ServicingStrategy=$servicingStrategy }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='B2.LanguagePack'; Description='WinPE language pack'; Patches=$lp; RequiresRemount=$false; ServicingStrategy=$servicingStrategy }) | Out-Null
    $needsFinalLcu = [bool]$policyDecision.NeedsFinalLcu
    $finalLcuSet = if ($needsFinalLcu) { $lcu } else { @() }
    $finalDescription = if($servicingStrategy -eq 'ExpandedCombinedCab'){'Apply the combined LCU CAB exactly once (embedded SSU + RollupFix)'}elseif($servicingStrategy -eq 'ExpandedSplitCab'){'Final cumulative payload after standalone SSU commit/remount'}elseif($needsFinalLcu){'Final cumulative update'}else{'Skipped: combined LCU already applied and no intervening WinPE language changes occurred'}
    $seq.Add([pscustomobject]@{ Name='B3.FinalLCU'; Description=$finalDescription; Patches=$finalLcuSet; RequiresRemount=$false; DuplicateApplySuppressed=$policyDecision.DuplicateApplySuppressed; ServicingStrategy=$servicingStrategy }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='B4.Cleanup'; Description='Cleanup + export'; Patches=@(); RequiresRemount=$false; IsCleanupMarker=$true }) | Out-Null
    return $seq.ToArray()
}

function Build-WinReApplySequence {
    <#
    .SYNOPSIS
        Build the WinRE sequence from roles.
    .DESCRIPTION
        A combined LCU can be supplied as the servicing-stack carrier; its
        final OS LCU role is intentionally not targeted to WinRE. SafeOS DU
        remains a separate WinRE payload.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [array]$WinRePatches)

    $prereq = Get-PatchesForRole -Patches $WinRePatches -Roles @('SourcePrerequisite')
    $stack  = Get-PatchesForRole -Patches $WinRePatches -Roles @('ServicingStackCarrier')
    $lp     = Get-PatchesForRole -Patches $WinRePatches -Roles @('WinReLanguagePack','LanguagePack')
    $safeOs = Get-PatchesForRole -Patches $WinRePatches -Roles @('SafeOSDU')

    $seq = [System.Collections.Generic.List[object]]::new()
    $seq.Add([pscustomobject]@{ Name='W0.SourcePrerequisite'; Description='Source-media prerequisite, conditionally injected'; Patches=$prereq; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='W1.ServicingStack'; Description='Standalone SSU or combined-LCU servicing-stack carrier'; Patches=$stack; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='W2.LanguagePack'; Description='Recovery UI language pack'; Patches=$lp; RequiresRemount=$false }) | Out-Null
    $seq.Add([pscustomobject]@{ Name='W3.SafeOsDU'; Description='Safe OS Dynamic Update'; Patches=$safeOs; RequiresRemount=$false }) | Out-Null
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

    $missing = [System.Collections.Generic.List[string]]::new()
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

function Get-OfflineWindowsState {
    <# Read build and .NET Framework state from an offline mounted image. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$MountPath)

    $softwareHive = Join-Path $MountPath 'Windows\System32\Config\SOFTWARE'
    if (-not (Test-Path -LiteralPath $softwareHive)) {
        return [pscustomobject]@{ Build=''; Ubr=0; Version=''; DotNetRelease=0; DotNetVersion='Unknown' }
    }
    $mountName = ('WSI_{0}_{1}' -f $PID, ([Guid]::NewGuid().ToString('N')))
    $regRoot = ('Registry::HKEY_LOCAL_MACHINE\' + $mountName)
    $loaded = $false
    try {
        & reg.exe load ('HKLM\' + $mountName) $softwareHive *> $null
        if ($LASTEXITCODE -ne 0) { throw ('reg.exe load failed with exit code {0}' -f $LASTEXITCODE) }
        $loaded = $true
        $cv = Get-ItemProperty -LiteralPath (Join-Path $regRoot 'Microsoft\Windows NT\CurrentVersion') -ErrorAction Stop
        $build = [string]$cv.CurrentBuildNumber
        $ubr = 0
        if ($cv.PSObject.Properties['UBR']) { $ubr = [int]$cv.UBR }
        $release = 0
        $netPath = Join-Path $regRoot 'Microsoft\NET Framework Setup\NDP\v4\Full'
        if (Test-Path -LiteralPath $netPath) {
            $net = Get-ItemProperty -LiteralPath $netPath -ErrorAction SilentlyContinue
            if ($net -and $net.PSObject.Properties['Release']) { $release = [int]$net.Release }
        }
        $dotNetVersion = 'Unknown'
        if ($release -ge 533320) { $dotNetVersion = '4.8.1' }
        elseif ($release -ge 528040) { $dotNetVersion = '4.8' }
        elseif ($release -ge 461808) { $dotNetVersion = '4.7.2' }
        elseif ($release -ge 394802) { $dotNetVersion = '4.6.2' }
        return [pscustomobject]@{
            Build         = $build
            Ubr           = $ubr
            Version       = $(if ($build) { ('{0}.{1}' -f $build, $ubr) } else { '' })
            DotNetRelease = $release
            DotNetVersion = $dotNetVersion
        }
    } finally {
        if ($loaded) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            & reg.exe unload ('HKLM\' + $mountName) *> $null
        }
    }
}

function Test-KbPresentOnMount {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$MountPath, [Parameter(Mandatory)][string]$KbId)
    if (-not $KbId) { return $false }
    $packages = @(Invoke-DismCmdlet -CommandName 'Get-WindowsPackage' -Parameters @{ Path=$MountPath; ErrorAction='Stop' })
    foreach ($pkg in $packages) {
        if ([string]$pkg.PackageIdentity -like ('*' + $KbId + '*')) { return $true }
    }
    return $false
}

function Test-DotNetRuntimeSelector {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()]$Selector, [Parameter(Mandatory)]$OfflineState)
    if (-not $Selector) { return $true }
    $actual = [string]$OfflineState.DotNetVersion
    if ($Selector.PSObject.Properties['NetFx4Release'] -and $Selector.NetFx4Release) {
        return ($actual -eq [string]$Selector.NetFx4Release)
    }
    if ($Selector.PSObject.Properties['NetFx4ReleaseRange'] -and $Selector.NetFx4ReleaseRange) {
        $range = ([string]$Selector.NetFx4ReleaseRange).Split('-')
        if ($range.Count -eq 2) {
            try {
                return (([version]$actual -ge [version]$range[0]) -and ([version]$actual -le [version]$range[1]))
            } catch { return $false }
        }
    }
    return $true
}

function Get-PatchApplicabilityDecision {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Patch,
        [Parameter(Mandatory)][string]$MountPath,
        [Parameter(Mandatory)]$OfflineState
    )
    $mode = 'Always'
    $rule = $null
    if ($Patch.PSObject.Properties['Applicability'] -and $Patch.Applicability) {
        $rule = $Patch.Applicability
        if ($rule.PSObject.Properties['Mode'] -and $rule.Mode) { $mode = [string]$rule.Mode }
    }
    if ((Get-PatchRoles -Patch $Patch) -contains 'DotNetLeaf') {
        $matches = Test-DotNetRuntimeSelector -Selector $Patch.RuntimeSelector -OfflineState $OfflineState
        return [pscustomobject]@{ Applicable=$matches; Reason=$(if ($matches) { 'runtime matched' } else { 'runtime did not match' }); Mode='IfRuntimeDetectedPerInstallIndex' }
    }
    switch ($mode) {
        'IfPackageAbsent' {
            $present = Test-KbPresentOnMount -MountPath $MountPath -KbId ([string]$Patch.KbId)
            return [pscustomobject]@{ Applicable=(-not $present); Reason=$(if ($present) { 'KB already present' } else { 'KB absent' }); Mode=$mode }
        }
        'IfSourceBelowFloor' {
            $minimum = ''
            if ($rule.PSObject.Properties['MinimumImageBuild']) { $minimum = [string]$rule.MinimumImageBuild }
            if (-not $minimum -and $rule.PSObject.Properties['MinimumServicingStack']) { $minimum = [string]$rule.MinimumServicingStack }
            if (-not $minimum -or -not $OfflineState.Version) {
                return [pscustomobject]@{ Applicable=$true; Reason='source floor could not be proven; fail-safe apply'; Mode=$mode }
            }
            return [pscustomobject]@{ Applicable=([version]$OfflineState.Version -lt [version]$minimum); Reason=('source={0}; floor={1}' -f $OfflineState.Version, $minimum); Mode=$mode }
        }
        'IfLatestSsuNotApplicableOrPackageAbsent' {
            $present = Test-KbPresentOnMount -MountPath $MountPath -KbId ([string]$Patch.KbId)
            return [pscustomobject]@{ Applicable=(-not $present); Reason=$(if ($present) { 'legacy prerequisite already present' } else { 'legacy prerequisite absent' }); Mode=$mode }
        }
        default {
            return [pscustomobject]@{ Applicable=$true; Reason='unconditional or resolver-selected asset'; Mode=$mode }
        }
    }
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
    $rows = [System.Collections.Generic.List[object]]::new()
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

        $offlineState = Get-OfflineWindowsState -MountPath $MountPath
        $decision = Get-PatchApplicabilityDecision -Patch $p -MountPath $MountPath -OfflineState $offlineState
        if (-not $decision.Applicable) {
            Write-Step ('    [SKIP] {0}/{1}: {2}' -f $type, $kb, $decision.Reason)
            $rows.Add([pscustomobject]@{
                SubPhase=$SubPhase.Name; ImageLabel=$ImageLabel; PatchType=$type; KbId=$kb
                FilePath=$pkgPath; ApplyStatus='NotApplicable'; ElapsedSec=0
            }) | Out-Null
            continue
        }
        if ($p.PSObject.Properties['IsMetadataOnly'] -and $p.IsMetadataOnly) {
            throw ('{0}/{1} is required for {2} ({3}) but its Asset is unresolved. Refresh the baseline or populate SourcePrerequisites[].Asset before Build.' -f $type, $kb, $ImageLabel, $decision.Reason)
        }

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
            $phaseForEvidence = if ($ImageLabel -like 'install.wim:*') { 'P07' } else { 'P08' }
            $evidenceMetadata = @{
                Phase=$phaseForEvidence; ImageLabel=$ImageLabel; SubPhase=[string]$SubPhase.Name
                KbId=$kb; PatchType=$type; PackagePath=$pkgPath
            }
            $allowWinReKnownError = (
                $ImageLabel -eq 'winre.wim' -and
                $type -in @('LCU','BridgeLcu') -and
                ((Test-PatchHasRole -Patch $p -Role 'ServicingStackCarrier') -or
                 (Test-PatchHasRole -Patch $p -Role 'SourcePrerequisite'))
            )
            $bootServicingStrategy = if($ImageLabel -like 'boot.wim:*'){Get-BootWimServicingStrategy}else{'DirectMsu'}
            $useExpandedMsu = (
                $ImageLabel -like 'boot.wim:*' -and
                $bootServicingStrategy -in @('ExpandedCombinedCab','ExpandedSplitCab') -and
                $type -eq 'LCU' -and
                [System.IO.Path]::GetExtension($pkgPath) -ieq '.msu'
            )
            if ($useExpandedMsu) {
                Write-Step ('      boot.wim servicing strategy: {0}; using selected expanded CAB payload(s).' -f $bootServicingStrategy)
                $cabRoles = @(Get-ExpandedMsuCabRolesForSubPhase -SubPhaseName ([string]$SubPhase.Name) -ServicingStrategy $bootServicingStrategy)
                $status = Add-WindowsPackageFromExpandedMsu -MountPath $MountPath -MsuPath $pkgPath -KbId $kb -LogDir $Script:LogsDir -CabRoles $cabRoles -EvidenceMetadata $evidenceMetadata
            } else {
                $status = Add-WindowsPackageWithRetry -MountPath $MountPath `
                    -PackagePath $pkgPath -LogDir $Script:LogsDir `
                    -AllowWinReCombinedLcuKnownError:$allowWinReKnownError -EvidenceMetadata $evidenceMetadata
            }
            Write-Ok ('      status={0}' -f $status)
        } catch {
            $errMsg = $_.Exception.Message
            $status = 'Fail'
            Add-ErrorJsonlEntry -Phase $phaseForEvidence -Kind 'sub-phase-failure' -Properties @{
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
# Secure Boot / PCA2023 helpers
# ------------------------------------------------------------
# These helpers underpin P10 ConvertPca2023BootManager and P12
# VerifyPca2023Readiness. They are organised as:
#
#   1. Get-ImageLcuEvidence (+ 4 per-OS resolvers) - which LCU level is in the WIM
#   2. Get-WimOfflineHiveValue              - read SOFTWARE/SYSTEM hive
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

function ConvertTo-TwoPartBuild {
    <#
    .SYNOPSIS
        Judgment-free utility: normalise a dotted build string to its
        first two numeric components as [version] (e.g.
        '20348.5256.1.13' -> [version]'20348.5256'). $null/unparsable
        input returns $null; never throws.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [AllowNull()] [AllowEmptyString()] [string]$BuildString
    )
    if ([string]::IsNullOrWhiteSpace($BuildString)) { return $null }
    $m = [regex]::Match($BuildString.Trim(), '^(\d+)\.(\d+)')
    if (-not $m.Success) { return $null }
    return [version]('{0}.{1}' -f $m.Groups[1].Value, $m.Groups[2].Value)
}

function New-LcuEvidenceObject {
    <#
    .SYNOPSIS
        Judgment-free utility: assemble the common evidence shape from
        per-OS resolver inputs. The JUDGMENT (which package names count
        as the LCU, which build floor applies) lives in the four
        per-OS resolvers; this helper only performs the mechanical
        source-consensus arithmetic every resolver shares:
          Build            = registry > packages > kernel (first non-null)
          BuildSourcesAgree = every non-null source equal (2-part), and
                              at least two sources present
          MeetsPca2023Prereq = Build >= FloorBuild (null build = $false)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsKey,
        [AllowNull()] [string]$LcuPackageName,
        [AllowNull()] [string]$LcuKbId,
        [AllowNull()] [version]$BuildFromPackages,
        [AllowNull()] [version]$BuildFromRegistry,
        [AllowNull()] [version]$BuildFromKernel,
        [Parameter(Mandatory)] [version]$FloorBuild,
        [int]$PackageCount = 0,
        [AllowEmptyCollection()] [string[]]$KbIdsAtBuild = @(),
        [string]$Notes = ''
    )
    $sources = @(@($BuildFromRegistry, $BuildFromPackages, $BuildFromKernel) | Where-Object { $null -ne $_ })
    $build = if ($sources.Count -gt 0) { $sources[0] } else { $null }
    $agree = $false
    if ($sources.Count -ge 2) {
        $agree = @($sources | Sort-Object -Unique).Count -eq 1
    }
    return [pscustomobject]@{
        OsKey              = $OsKey
        LcuPackageName     = $(if ([string]::IsNullOrEmpty($LcuPackageName)) { $null } else { $LcuPackageName })
        LcuKbId            = $(if ([string]::IsNullOrEmpty($LcuKbId)) { $null } else { $LcuKbId })
        KbIdsAtBuild       = @($KbIdsAtBuild)
        BuildFromPackages  = $BuildFromPackages
        BuildFromRegistry  = $BuildFromRegistry
        BuildFromKernel    = $BuildFromKernel
        Build              = $build
        BuildSourcesAgree  = $agree
        Pca2023FloorBuild  = $FloorBuild
        MeetsPca2023Prereq = $(if ($null -ne $build) { $build -ge $FloorBuild } else { $false })
        PackageCount       = $PackageCount
        Notes              = $Notes
    }
}

# ---- Per-OS LCU evidence resolvers (FORKED JUDGMENT) -----------------
# One resolver per OS [user-adjudicated 2026-07-07]: each OS owns its
# LCU package-naming rule and its documented 2024-4B build floor. The
# 2026-07-07 E2E proved the judgment must not be shared: a KB-name-only
# detector worked on 2016 and was structurally blind on every
# RollupFix-named OS (2019/2022/2025 -> false '(none)' verdicts that
# mis-skipped P10 and mis-failed P12 on media whose LCU had in fact
# applied status=Ok). Shared code below is judgment-free I/O only.

function Resolve-LcuEvidence_Server2016 {
    <#
    .SYNOPSIS
        Server 2016 (1607 / 14393) LCU evidence. LCU packages carry the
        KB id AND the build in the package name:
        'Package_for_KB5094141~31bf3856ad364e35~amd64~~14393.9234.1.x'.
        2024-4B floor: KB5036899 = 14393.6897 (MS, April 9 2024 page).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [string[]]$PackageNames,
        [AllowNull()] [string]$RegistryBuild,
        [AllowNull()] [string]$KernelBuild
    )
    $floor = [version]'14393.6897'
    # SSU and LCU are BOTH KB-named on 2016 and can land at the SAME
    # build (2026-07-08 E2E: KB5094141 SSU and KB5094122 LCU at
    # 14393.9234), so single-KB selection misidentifies the LCU.
    # Collect every match; the evidence carries ALL KB ids at the
    # top build and the comparator matches by membership.
    $matches16 = @()
    foreach ($pn in @($PackageNames)) {
        if ([string]::IsNullOrWhiteSpace($pn)) { continue }
        $m = [regex]::Match($pn, '^Package_for_KB(\d{6,7})~31bf3856ad364e35~amd64~~(14393\.[0-9.]+)$')
        if (-not $m.Success) { continue }
        $b = ConvertTo-TwoPartBuild -BuildString $m.Groups[2].Value
        if ($null -eq $b) { continue }
        $matches16 += [pscustomobject]@{ KbId = ('KB{0}' -f $m.Groups[1].Value); Build = $b; Name = $pn }
    }
    $bestBuild = $null; $bestName = $null; $bestKb = $null; $kbsAtBest = @()
    if ($matches16.Count -gt 0) {
        $bestBuild = ($matches16 | ForEach-Object { $_.Build } | Sort-Object -Descending)[0]
        $atBest    = @($matches16 | Where-Object { $_.Build -eq $bestBuild })
        $bestName  = $atBest[0].Name
        $bestKb    = $atBest[0].KbId
        $kbsAtBest = @($atBest | ForEach-Object { $_.KbId })
    }
    return New-LcuEvidenceObject -OsKey 'Server2016' -LcuPackageName $bestName -LcuKbId $bestKb `
        -BuildFromPackages $bestBuild `
        -BuildFromRegistry (ConvertTo-TwoPartBuild -BuildString $RegistryBuild) `
        -BuildFromKernel (ConvertTo-TwoPartBuild -BuildString $KernelBuild) `
        -FloorBuild $floor -PackageCount @($PackageNames).Count -KbIdsAtBuild $kbsAtBest `
        -Notes 'LCU naming: Package_for_KB<id>~~14393.<rev>; SSU and LCU can share the top build, all KB ids at that build are carried'
}

function Resolve-LcuEvidence_Server2019 {
    <#
    .SYNOPSIS
        Server 2019 (1809 / 17763) LCU evidence. The cumulative update
        package is named 'Package_for_RollupFix~31bf3856ad364e35~amd64~
        ~17763.<rev>.1.x' -- NO KB id in the name; the build number IS
        the identity. 2024-4B floor: KB5036896 = 17763.5696 (MS, April
        9 2024 page).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [string[]]$PackageNames,
        [AllowNull()] [string]$RegistryBuild,
        [AllowNull()] [string]$KernelBuild
    )
    $floor = [version]'17763.5696'
    $bestBuild = $null; $bestName = $null
    foreach ($pn in @($PackageNames)) {
        if ([string]::IsNullOrWhiteSpace($pn)) { continue }
        $m = [regex]::Match($pn, '^Package_for_RollupFix~31bf3856ad364e35~amd64~~(17763\.[0-9.]+)$')
        if (-not $m.Success) { continue }
        $b = ConvertTo-TwoPartBuild -BuildString $m.Groups[1].Value
        if ($null -ne $b -and ($null -eq $bestBuild -or $b -gt $bestBuild)) {
            $bestBuild = $b
            $bestName  = $pn
        }
    }
    return New-LcuEvidenceObject -OsKey 'Server2019' -LcuPackageName $bestName -LcuKbId $null `
        -BuildFromPackages $bestBuild `
        -BuildFromRegistry (ConvertTo-TwoPartBuild -BuildString $RegistryBuild) `
        -BuildFromKernel (ConvertTo-TwoPartBuild -BuildString $KernelBuild) `
        -FloorBuild $floor -PackageCount @($PackageNames).Count `
        -Notes 'LCU naming: Package_for_RollupFix~~17763.<rev> (no KB id in name; build is the identity)'
}

function Resolve-LcuEvidence_Server2022 {
    <#
    .SYNOPSIS
        Server 2022 (21H2/22H2 / 20348) LCU evidence. Same
        RollupFix naming as 2019 (no KB id in the name). 2024-4B
        floor: KB5036909 = 20348.2402 (MS, April 9 2024 page).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [string[]]$PackageNames,
        [AllowNull()] [string]$RegistryBuild,
        [AllowNull()] [string]$KernelBuild
    )
    $floor = [version]'20348.2402'
    $bestBuild = $null; $bestName = $null
    foreach ($pn in @($PackageNames)) {
        if ([string]::IsNullOrWhiteSpace($pn)) { continue }
        $m = [regex]::Match($pn, '^Package_for_RollupFix~31bf3856ad364e35~amd64~~(20348\.[0-9.]+)$')
        if (-not $m.Success) { continue }
        $b = ConvertTo-TwoPartBuild -BuildString $m.Groups[1].Value
        if ($null -ne $b -and ($null -eq $bestBuild -or $b -gt $bestBuild)) {
            $bestBuild = $b
            $bestName  = $pn
        }
    }
    return New-LcuEvidenceObject -OsKey 'Server2022' -LcuPackageName $bestName -LcuKbId $null `
        -BuildFromPackages $bestBuild `
        -BuildFromRegistry (ConvertTo-TwoPartBuild -BuildString $RegistryBuild) `
        -BuildFromKernel (ConvertTo-TwoPartBuild -BuildString $KernelBuild) `
        -FloorBuild $floor -PackageCount @($PackageNames).Count `
        -Notes 'LCU naming: Package_for_RollupFix~~20348.<rev> (no KB id in name; build is the identity)'
}

function Resolve-LcuEvidence_Server2025 {
    <#
    .SYNOPSIS
        Server 2025 (24H2 / 26100) LCU evidence. RollupFix naming (no
        KB id); the uup-checkpoint model may leave MULTIPLE RollupFix
        packages visible (checkpoint baselines + target CU) -- the
        HIGHEST build is the serviced level. 2024-4B floor: the 26100
        GA (2024-11) itself postdates April 2024, so ANY 26100 build
        satisfies the prerequisite; floor pinned to 26100.1.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [string[]]$PackageNames,
        [AllowNull()] [string]$RegistryBuild,
        [AllowNull()] [string]$KernelBuild
    )
    $floor = [version]'26100.1'
    $bestBuild = $null; $bestName = $null; $rollupCount = 0
    foreach ($pn in @($PackageNames)) {
        if ([string]::IsNullOrWhiteSpace($pn)) { continue }
        $m = [regex]::Match($pn, '^Package_for_RollupFix~31bf3856ad364e35~amd64~~(26100\.[0-9.]+)$')
        if (-not $m.Success) { continue }
        $rollupCount++
        $b = ConvertTo-TwoPartBuild -BuildString $m.Groups[1].Value
        if ($null -ne $b -and ($null -eq $bestBuild -or $b -gt $bestBuild)) {
            $bestBuild = $b
            $bestName  = $pn
        }
    }
    return New-LcuEvidenceObject -OsKey 'Server2025' -LcuPackageName $bestName -LcuKbId $null `
        -BuildFromPackages $bestBuild `
        -BuildFromRegistry (ConvertTo-TwoPartBuild -BuildString $RegistryBuild) `
        -BuildFromKernel (ConvertTo-TwoPartBuild -BuildString $KernelBuild) `
        -FloorBuild $floor -PackageCount @($PackageNames).Count `
        -Notes ('LCU naming: Package_for_RollupFix~~26100.<rev>; {0} RollupFix package(s) visible (checkpoint model), highest build wins' -f $rollupCount)
}

function Get-WimBuildSources { # psa-disable-line PSA6003 -- "Sources" is plural by design; returns the set of independent build sources
    <#
    .SYNOPSIS
        Judgment-free acquisition: gather the three independent build
        sources from ONE already-mounted image -- package names
        (Get-WindowsPackage), SOFTWARE hive CurrentBuildNumber+UBR, and
        the ntoskrnl.exe file version. Every source is best-effort
        $null/empty; never throws.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$MountPath
    )
    $pkgNames = @()
    try {
        $pkgs = Invoke-DismCmdlet -CommandName 'Get-WindowsPackage' -Parameters @{ Path = $MountPath; ErrorAction = 'Stop' }
        $pkgNames = @($pkgs | ForEach-Object { [string]$_.PackageName })
    } catch {
        Write-Caution ('Get-WimBuildSources: package enumeration failed on {0}: {1}' -f $MountPath, $_.Exception.Message)
    }
    $regBuild = $null
    try {
        $cb  = Get-WimOfflineHiveValue -WimMountPath $MountPath -HiveFile 'SOFTWARE' `
            -RelativeRegPath 'Microsoft\Windows NT\CurrentVersion' -ValueName 'CurrentBuildNumber'
        $ubr = Get-WimOfflineHiveValue -WimMountPath $MountPath -HiveFile 'SOFTWARE' `
            -RelativeRegPath 'Microsoft\Windows NT\CurrentVersion' -ValueName 'UBR'
        if ($cb -and ($null -ne $ubr)) { $regBuild = ('{0}.{1}' -f $cb, $ubr) }
        elseif ($cb) { $regBuild = [string]$cb }
    } catch { $null = $_ }
    $kernBuild = $null
    try {
        $ntos = Join-Path $MountPath 'Windows\System32\ntoskrnl.exe'
        if (Test-Path -LiteralPath $ntos) {
            $fv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ntos)
            # ProductVersion form: 10.0.20348.5256 -> take build.revision
            $pv = [string]$fv.ProductVersion
            $m = [regex]::Match($pv, '(\d+)\.(\d+)$')
            if ($m.Success) { $kernBuild = ('{0}.{1}' -f $m.Groups[1].Value, $m.Groups[2].Value) }
        }
    } catch { $null = $_ }
    return [pscustomobject]@{
        PackageNames  = $pkgNames
        RegistryBuild = $regBuild
        KernelBuild   = $kernBuild
    }
}

function Get-WimIndexInspection {
    <#
    .SYNOPSIS
        Inspect ONE WIM index in ONE read-only mount session
        [user-adjudicated 2026-07-07: acquire everything, once].
    .DESCRIPTION
        Per index: the three build sources + the per-OS LCU evidence,
        the FULL installed-package name list, and kind-specific
        artifacts -- install.wim: winre.wim presence/size/SHA-256 and
        the SYSTEM-hive SecureBoot servicing values; boot.wim: the
        PCA2023 _EX payload directories and files. A failed index
        records ErrorMessage and never throws (inspection must not
        kill a build; its absence must stay visible).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsKey,
        [Parameter(Mandatory)] [string]$WimPath,
        [Parameter(Mandatory)] [int]$Index,
        [Parameter(Mandatory)] [ValidateSet('install', 'boot')] [string]$Kind,
        [Parameter(Mandatory)] [string]$MountDir,
        [Parameter(Mandatory)] [string]$LogDir
    )
    $rec = [ordered]@{
        Kind          = $Kind
        Index         = $Index
        Evidence      = $null
        PackageNames  = @()
        WinRePresent  = $null
        WinReSizeBytes = $null
        WinReSha256   = $null
        DotNetRelease  = 0
        DotNetVersion  = 'Unknown'
        UEFICA2023Status = $null
        UEFICA2023Error  = $null
        AvailableUpdates = $null
        HasEfiExDir   = $null
        HasFontsEx    = $null
        HasDvdEx      = $null
        HasBootMgrFwEx = $null
        HasBootMgrEx  = $null
        HasEfisysExBin = $null
        SetupExe      = $null
        SetupHostExe  = $null
        ErrorMessage  = $null
    }
    $mounted = $false
    try {
        if (Test-Path -LiteralPath $MountDir) {
            Remove-Item -LiteralPath $MountDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $MountDir -Force | Out-Null
        $null = Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters @{
            ImagePath = $WimPath; Index = $Index; Path = $MountDir
            ReadOnly = $true; ErrorAction = 'Stop'
            LogPath = (Join-Path $LogDir ('inspect_mount_{0}_idx{1}.log' -f $Kind, $Index))
        }
        $mounted = $true

        $src = Get-WimBuildSources -MountPath $MountDir
        $rec.PackageNames = @($src.PackageNames)
        $offlineState = Get-OfflineWindowsState -MountPath $MountDir
        $rec.DotNetRelease = $offlineState.DotNetRelease
        $rec.DotNetVersion = $offlineState.DotNetVersion
        switch ($OsKey) {
            'Server2016' { $rec.Evidence = Resolve-LcuEvidence_Server2016 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild }
            'Server2019' { $rec.Evidence = Resolve-LcuEvidence_Server2019 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild }
            'Server2022' { $rec.Evidence = Resolve-LcuEvidence_Server2022 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild }
            'Server2025' { $rec.Evidence = Resolve-LcuEvidence_Server2025 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild }
            default { throw ("Get-WimIndexInspection: unknown OsKey '{0}'." -f $OsKey) }
        }

        # PCA2023 _EX payload census -- BOTH kinds. The LCU stages
        # these into any serviced image; install.wim is the fallback
        # source for the boot-manager conversion when boot.wim is
        # unserviceable (Server 2019: 0x80070032 closure), so its
        # census is as load-bearing as boot.wim's.
        $exBins  = Join-Path $MountDir 'Windows\Boot\EFI_EX'
        $exFonts = Join-Path $MountDir 'Windows\Boot\FONTS_EX'
        $exDvd   = Join-Path $MountDir 'Windows\Boot\DVD_EX'
        $rec.HasEfiExDir    = Test-Path -LiteralPath $exBins
        $rec.HasFontsEx     = Test-Path -LiteralPath $exFonts
        $rec.HasDvdEx       = Test-Path -LiteralPath $exDvd
        $rec.HasBootMgrFwEx = if ($rec.HasEfiExDir) { Test-Path -LiteralPath (Join-Path $exBins 'bootmgfw_EX.efi') } else { $false }
        $rec.HasBootMgrEx   = if ($rec.HasEfiExDir) { Test-Path -LiteralPath (Join-Path $exBins 'bootmgr_EX.efi')   } else { $false }
        $rec.HasEfisysExBin = if ($rec.HasDvdEx) { Test-Path -LiteralPath (Join-Path $exDvd 'EFI\en-US\efisys_EX.bin') } else { $false }
        if ($Kind -eq 'boot') {
            # Setup-binary identity of THIS image: the P11
            # SetupBinarySync check compares these against the media
            # \sources copies (must be byte-identical per MS).
            $rec.SetupExe     = Get-SetupBinaryFileEvidence -Path (Join-Path $MountDir 'sources\setup.exe')
            $rec.SetupHostExe = Get-SetupBinaryFileEvidence -Path (Join-Path $MountDir 'sources\setuphost.exe')
        }

        if ($Kind -eq 'install') {
            $winRe = Join-Path $MountDir 'Windows\System32\Recovery\Winre.wim'
            $rec.WinRePresent = Test-Path -LiteralPath $winRe
            if ($rec.WinRePresent) {
                $wr = Get-Item -LiteralPath $winRe
                $rec.WinReSizeBytes = $wr.Length
                try { $rec.WinReSha256 = (Get-FileHash -LiteralPath $winRe -Algorithm SHA256).Hash.ToLower() } catch { $null = $_ }
            }
            $servPath = 'ControlSet001\Control\SecureBoot\Servicing'
            $rec.UEFICA2023Status = Get-WimOfflineHiveValue -WimMountPath $MountDir -HiveFile 'SYSTEM' -RelativeRegPath $servPath -ValueName 'UEFICA2023Status'
            $rec.UEFICA2023Error  = Get-WimOfflineHiveValue -WimMountPath $MountDir -HiveFile 'SYSTEM' -RelativeRegPath $servPath -ValueName 'UEFICA2023Error'
            $au = Get-WimOfflineHiveValue -WimMountPath $MountDir -HiveFile 'SYSTEM' -RelativeRegPath 'ControlSet001\Control\SecureBoot' -ValueName 'AvailableUpdates'
            if ($null -ne $au) { $rec.AvailableUpdates = ('0x{0:x}' -f [int]$au) }
        }
    } catch {
        $rec.ErrorMessage = $_.Exception.Message
    } finally {
        if ($mounted) {
            try {
                $null = Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path = $MountDir; Discard = $true; ErrorAction = 'Stop' }
            } catch {
                Write-Caution ('Get-WimIndexInspection: dismount failed for {0} idx {1}: {2}' -f $Kind, $Index, $_.Exception.Message)
            } # psa-disable-line PSA3004 -- best-effort dismount; a leaked RO mount is reported, not fatal
        }
    }
    return [pscustomobject]$rec
}

function Get-MediaInspection {
    <#
    .SYNOPSIS
        Full media inspection: EVERY index of install.wim and boot.wim
        under <MediaRoot>\sources, one mount each, plus media-level
        artifacts (boot.stl locations -- required for Secure Boot
        validation when deploying dynamic updates to media, per the MS
        LCU pages (error 0xc0430001 when missing); WIM sizes + SHA-256
        for content-identity proofs).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsKey,
        [Parameter(Mandatory)] [string]$MediaRoot,
        [Parameter(Mandatory)] [ValidateSet('pre', 'post')] [string]$Label,
        [Parameter(Mandatory)] [string]$MountDir,
        [Parameter(Mandatory)] [string]$LogDir
    )
    $installWim = Join-Path $MediaRoot 'sources\install.wim'
    $bootWim    = Join-Path $MediaRoot 'sources\boot.wim'
    $insp = [ordered]@{
        Label        = $Label
        OsKey        = $OsKey
        MediaRoot    = $MediaRoot
        Timestamp    = (Get-Date).ToString('o')
        InstallWim   = [ordered]@{ Path = $installWim; Present = $false; SizeBytes = $null; Sha256 = $null; Indexes = @() }
        BootWim      = [ordered]@{ Path = $bootWim; Present = $false; SizeBytes = $null; Sha256 = $null; Indexes = @() }
        BootStlPaths = @()
        MediaSetupBinaries = [ordered]@{ SetupExe = $null; SetupHostExe = $null }
        ErrorMessage = $null
    }
    try {
        try {
            $stl = @(Get-ChildItem -LiteralPath $MediaRoot -Recurse -Filter 'boot.stl' -File -ErrorAction SilentlyContinue)
            $insp.BootStlPaths = @($stl | ForEach-Object { $_.FullName.Substring($MediaRoot.Length).TrimStart('\', '/') })
        } catch { $null = $_ }
        $insp.MediaSetupBinaries.SetupExe     = Get-SetupBinaryFileEvidence -Path (Join-Path $MediaRoot 'sources\setup.exe')
        $insp.MediaSetupBinaries.SetupHostExe = Get-SetupBinaryFileEvidence -Path (Join-Path $MediaRoot 'sources\setuphost.exe')

        foreach ($entry in @(
            @{ Slot = 'InstallWim'; Path = $installWim; Kind = 'install' },
            @{ Slot = 'BootWim';    Path = $bootWim;    Kind = 'boot' }
        )) {
            $slot = $insp[$entry.Slot]
            if (-not (Test-Path -LiteralPath $entry.Path)) { continue }
            $slot.Present = $true
            $fi = Get-Item -LiteralPath $entry.Path
            $slot.SizeBytes = $fi.Length
            try { $slot.Sha256 = (Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash.ToLower() } catch { $null = $_ }
            $idxList = @()
            try {
                $idxList = @((Get-WimIndexInventory -WimPath $entry.Path) | ForEach-Object { [int]$_.ImageIndex })
            } catch {
                Write-Caution ('Get-MediaInspection: index enumeration failed for {0}: {1}' -f $entry.Path, $_.Exception.Message)
            }
            $records = @()
            foreach ($idx in $idxList) {
                Write-Step ('  inspecting {0}.wim idx {1} ({2}) ...' -f $entry.Kind, $idx, $Label)
                $t0 = Get-Date
                $rec = Get-WimIndexInspection -OsKey $OsKey -WimPath $entry.Path -Index $idx `
                    -Kind $entry.Kind -MountDir $MountDir -LogDir $LogDir
                $secs = [int](New-TimeSpan -Start $t0 -End (Get-Date)).TotalSeconds
                $b = if ($rec.Evidence -and $rec.Evidence.Build) { $rec.Evidence.Build } else { '(none)' }
                if ($rec.ErrorMessage) {
                    Write-Caution ('    idx {0}: inspection error ({1}s): {2}' -f $idx, $secs, $rec.ErrorMessage)
                } else {
                    Write-Step ('    idx {0}: build={1} packages={2} ({3}s)' -f $idx, $b, @($rec.PackageNames).Count, $secs)
                }
                $records += $rec
            }
            $slot.Indexes = $records
        }
    } catch {
        $insp.ErrorMessage = $_.Exception.Message
    }
    return [pscustomobject]$insp
}

function Write-MediaInspectionJson {
    <#
    .SYNOPSIS
        Serialize an inspection object to <LogDir>\inspection_<label>.json
        (runtime artifact; NOT canonical-JSON governed). Returns the path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Inspection,
        [Parameter(Mandatory)] [string]$LogDir
    )
    $path = Join-Path $LogDir ('inspection_{0}.json' -f $Inspection.Label)
    $Inspection | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function ConvertFrom-InspectionBuildValue {
    <#
    .SYNOPSIS
        Judgment-free utility: normalise ANY build-value shape the
        inspection pipeline can hand us into a two-part [version] --
        a live [version], a string, or the {Major, Minor, ...} object
        a [version] becomes after a ConvertTo-Json/ConvertFrom-Json
        round trip. $null/unparsable returns $null; never throws.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [AllowNull()] [object]$Value
    )
    if ($null -eq $Value) { return $null }
    if ($Value -is [version]) { return (ConvertTo-TwoPartBuild -BuildString ([string]$Value)) }
    if ($Value -is [string]) { return (ConvertTo-TwoPartBuild -BuildString $Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains('Major') -and $Value.Contains('Minor')) {
            if (([int]$Value['Major']) -lt 0 -or ([int]$Value['Minor']) -lt 0) { return $null }
            return [version]('{0}.{1}' -f [int]$Value['Major'], [int]$Value['Minor'])
        }
        return $null
    }
    if ($Value.PSObject.Properties['Major'] -and $Value.PSObject.Properties['Minor']) {
        if (([int]$Value.Major) -lt 0 -or ([int]$Value.Minor) -lt 0) { return $null }
        return [version]('{0}.{1}' -f [int]$Value.Major, [int]$Value.Minor)
    }
    return $null
}

function Compare-MediaInspection {
    <#
    .SYNOPSIS
        Pure diff over two media-inspection objects (live or
        JSON-deserialized): per WIM, per index -- build movement,
        package-count delta, 2024-4B prerequisite flips, and (boot)
        the appearance of the PCA2023 _EX payload. No I/O; offline-
        testable (T38).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [object]$Pre,
        [Parameter(Mandatory)] [object]$Post
    )
    $wims = @()
    foreach ($slotName in @('InstallWim', 'BootWim')) {
        $preSlot  = $Pre.$slotName
        $postSlot = $Post.$slotName
        $postByIdx = @{}
        foreach ($r in @($postSlot.Indexes)) {
            if ($null -ne $r) { $postByIdx[[int]$r.Index] = $r }
        }
        $indexDiffs = @()
        foreach ($preRec in @($preSlot.Indexes)) {
            if ($null -eq $preRec) { continue }
            $i = [int]$preRec.Index
            $postRec = $postByIdx[$i]
            $preB  = ConvertFrom-InspectionBuildValue -Value $(if ($preRec.Evidence) { $preRec.Evidence.Build } else { $null })
            $postB = ConvertFrom-InspectionBuildValue -Value $(if ($postRec -and $postRec.Evidence) { $postRec.Evidence.Build } else { $null })
            $exAppeared = [bool](($postRec -and $postRec.HasEfiExDir) -and -not $preRec.HasEfiExDir)
            $indexDiffs += [pscustomobject]@{
                Index              = $i
                BuildBefore        = $preB
                BuildAfter         = $postB
                BuildAdvanced      = [bool]($preB -and $postB -and ($postB -gt $preB))
                PackageCountBefore = @($preRec.PackageNames).Count
                PackageCountAfter  = $(if ($postRec) { @($postRec.PackageNames).Count } else { $null })
                PrereqBefore       = $(if ($preRec.Evidence) { [bool]$preRec.Evidence.MeetsPca2023Prereq } else { $null })
                PrereqAfter        = $(if ($postRec -and $postRec.Evidence) { [bool]$postRec.Evidence.MeetsPca2023Prereq } else { $null })
                ExPayloadAppeared  = $exAppeared
                PostMissing        = [bool]($null -eq $postRec)
            }
        }
        $wims += [pscustomobject]@{
            Wim        = $slotName
            ShaChanged = [bool]($preSlot.Sha256 -and $postSlot.Sha256 -and ($preSlot.Sha256 -ne $postSlot.Sha256))
            Indexes    = $indexDiffs
        }
    }
    return [pscustomobject]@{
        OsKey         = $Pre.OsKey
        PreTimestamp  = $Pre.Timestamp
        PostTimestamp = $Post.Timestamp
        Wims          = $wims
    }
}

function Get-InspectionCrossChecks { # psa-disable-line PSA6003 -- "CrossChecks" is plural by design; returns the full findings list
    <#
    .SYNOPSIS
        Pure observe-first comparator: measured state vs config
        declarations. Emits findings only -- Level 'Warning' means the
        declaration and the measurement disagree (recorded, NEVER
        gated in this arc; measurement-driven gating is a next-arc
        step after the inspection survives one E2E cycle
        [user-adjudicated 2026-07-07]). Level 'Info' documents
        consistency or an expected tolerate-path outcome.
    .OUTPUTS
        Array of pscustomobject: Level / Kind / Message
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)] [string]$BootWimLcuPolicy,
        [AllowNull()] [object]$BridgeMinimumStack,
        [AllowNull()] [object]$PreInstallBuild,
        [AllowNull()] [object]$PreBootBuild,
        [AllowNull()] [object]$PostBootBuild
    )
    $findings = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($Level, $Kind, $Message)
        $findings.Add([pscustomobject]@{ Level = $Level; Kind = $Kind; Message = $Message }) | Out-Null
    }
    $preB  = ConvertFrom-InspectionBuildValue -Value $PreBootBuild
    $postB = ConvertFrom-InspectionBuildValue -Value $PostBootBuild
    $bootAdvanced = [bool]($preB -and $postB -and ($postB -gt $preB))
    $preS  = if ($preB)  { [string]$preB }  else { '(none)' }
    $postS = if ($postB) { [string]$postB } else { '(none)' }
    switch ($BootWimLcuPolicy) {
        'disabled' {
            if ($bootAdvanced) {
                & $add 'Warning' 'boot-policy' ('BootWimLcuPolicy=disabled but the measured boot.wim build ADVANCED ({0} -> {1}); declaration and measurement disagree.' -f $preS, $postS)
            } else {
                & $add 'Info' 'boot-policy' ('BootWimLcuPolicy=disabled and boot.wim build unchanged ({0}); declaration consistent with measurement.' -f $preS)
            }
        }
        'enabled' {
            if (-not $bootAdvanced) {
                & $add 'Warning' 'boot-policy' ('BootWimLcuPolicy=enabled but the measured boot.wim build did NOT advance ({0} -> {1}); declaration and measurement disagree.' -f $preS, $postS)
            } else {
                & $add 'Info' 'boot-policy' ('BootWimLcuPolicy=enabled and boot.wim build advanced ({0} -> {1}); declaration consistent with measurement.' -f $preS, $postS)
            }
        }
        'tolerate' {
            if ($bootAdvanced) {
                & $add 'Info' 'boot-policy' ('BootWimLcuPolicy=tolerate and boot.wim servicing SUCCEEDED ({0} -> {1}); measurement supports flipping this OS to enabled (user adjudication).' -f $preS, $postS)
            } else {
                & $add 'Info' 'boot-policy' ('BootWimLcuPolicy=tolerate and boot.wim build did not advance ({0} -> {1}); the tolerated-failure path was taken, boot.wim ships as-is.' -f $preS, $postS)
            }
        }
        default {
            & $add 'Warning' 'boot-policy' ('Unknown BootWimLcuPolicy value {0}; cannot cross-check.' -f $BootWimLcuPolicy)
        }
    }
    if ($BridgeMinimumStack) {
        $floor = ConvertTo-TwoPartBuild -BuildString ([string]$BridgeMinimumStack)
        $preI  = ConvertFrom-InspectionBuildValue -Value $PreInstallBuild
        if ($floor -and $preI) {
            if ($preI -ge $floor) {
                & $add 'Warning' 'bridge-need' ('BridgeLcu is declared but the PRE-measured install.wim build {0} already meets MinimumImageServicingStack {1}; the bridge may be redundant on this media (supersedence will no-op it) -- config-drift signal.' -f $preI, $floor)
            } else {
                & $add 'Info' 'bridge-need' ('BridgeLcu need CONFIRMED by measurement: pre-measured install.wim build {0} is below MinimumImageServicingStack {1}.' -f $preI, $floor)
            }
        }
    }
    return $findings.ToArray()
}

function Get-ImageLcuEvidence {
    <#
    .SYNOPSIS
        Acquisition shell (judgment-free) + per-OS dispatch: gather the
        three independent build sources from a mounted image in ONE
        mount session -- package names (Get-WindowsPackage), the
        SOFTWARE hive (CurrentBuildNumber + UBR), and the kernel file
        version (ntoskrnl.exe) -- then hand ALL of it to the OS's own
        resolver, which owns the judgment.
    .DESCRIPTION
        Never throws on acquisition failures: each source is
        best-effort $null and the resolver's consensus logic reports
        what it actually had (BuildSourcesAgree). Unknown OsKey IS a
        typed error -- silently mis-inspecting an OS is the exact
        failure this engine replaces.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsKey,
        [Parameter(Mandatory)] [string]$MountPath
    )
    $src = Get-WimBuildSources -MountPath $MountPath
    $pkgNames  = @($src.PackageNames)
    $regBuild  = $src.RegistryBuild
    $kernBuild = $src.KernelBuild

    switch ($OsKey) {
        'Server2016' { return Resolve-LcuEvidence_Server2016 -PackageNames $pkgNames -RegistryBuild $regBuild -KernelBuild $kernBuild }
        'Server2019' { return Resolve-LcuEvidence_Server2019 -PackageNames $pkgNames -RegistryBuild $regBuild -KernelBuild $kernBuild }
        'Server2022' { return Resolve-LcuEvidence_Server2022 -PackageNames $pkgNames -RegistryBuild $regBuild -KernelBuild $kernBuild }
        'Server2025' { return Resolve-LcuEvidence_Server2025 -PackageNames $pkgNames -RegistryBuild $regBuild -KernelBuild $kernBuild }
        default {
            throw ("Get-ImageLcuEvidence: unknown OsKey '{0}' (expected Server2016|Server2019|Server2022|Server2025)." -f $OsKey)
        }
    }
}
function Get-WimOfflineHiveValue {
    <#
    .SYNOPSIS
        Load an offline registry hive (SYSTEM or SOFTWARE) from a
        mounted WIM and read one value. Judgment-free I/O primitive.

        Uses 'reg.exe load' to mount the WIM's
        \Windows\System32\config\<HiveFile> file under
        HKLM\WIMHIVE_$Tag (a transient hive name), reads the
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
        [ValidateSet('SYSTEM', 'SOFTWARE')] [string]$HiveFile = 'SYSTEM',
        [string]$Tag = ('UPDWSI{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
    )

    $hivePath = Join-Path $WimMountPath ('Windows\System32\config\{0}' -f $HiveFile)
    if (-not (Test-Path -LiteralPath $hivePath)) {
        return $null
    }

    $mountKey = ('HKLM\WIMHIVE_{0}' -f $Tag)
    $psPath   = ('HKLM:\WIMHIVE_{0}\{1}' -f $Tag, $RelativeRegPath)

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
        if (-not (Test-Path -LiteralPath $psPath)) { return $null }
        try {
            $rv = Get-ItemProperty -LiteralPath $psPath -Name $ValueName -ErrorAction SilentlyContinue
            if ($null -eq $rv) { return $null }
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
        [pscustomobject] .Parsed .IsPca2023 .IsPca2011 .SigCount
                         .Subjects .Error
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
        Subjects  = @()
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
    $res.Subjects = @($tokens | Select-Object -Unique)
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
          .X509IsPca2023 / .X509IsPca2011
                         - the catalog/cross-cert X509-chain classification.
          .Embedded*     - parsed signtool embedded-signature provenance,
                           including subjects and signature count.

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
        Available                 = $false
        ErrorMessage              = $null
        SignerName                = $null
        RootChain                 = $null
        ChainTokens               = @()
        IsPca2023                 = $false
        IsPca2011                 = $false
        Method                    = 'X509Chain (Get-AuthenticodeSignature)'
        X509IsPca2023             = $false
        X509IsPca2011             = $false
        EmbeddedParsed            = $false
        EmbeddedIsPca2023         = $false
        EmbeddedIsPca2011         = $false
        EmbeddedSignatureCount    = 0
        EmbeddedSubjects          = @()
        EmbeddedError             = $null
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
    $tokens = [System.Collections.Generic.List[string]]::new()
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
    $result.X509IsPca2023 = $result.IsPca2023
    $result.X509IsPca2011 = $result.IsPca2011

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
        $result.EmbeddedParsed         = $embedded.Parsed
        $result.EmbeddedIsPca2023      = $embedded.IsPca2023
        $result.EmbeddedIsPca2011      = $embedded.IsPca2011
        $result.EmbeddedSignatureCount = $embedded.SigCount
        $result.EmbeddedSubjects       = @($embedded.Subjects)
        $result.EmbeddedError          = $embedded.Error
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
        BootX64VerdictMethod       = $null
        BootX64X509IsPca2023       = $null
        BootX64X509IsPca2011       = $null
        BootX64EmbeddedParsed      = $null
        BootX64EmbeddedIsPca2023   = $null
        BootX64EmbeddedIsPca2011   = $null
        BootX64EmbeddedSignatureCount = 0
        BootX64EmbeddedSubjects    = @()
        BootX64EmbeddedError       = $null
        # LCU level integrated in install.wim (read via Get-WindowsPackage)
        InstallWimHighestKb        = $null
        InstallWimBuild            = $null
        InstallWimBuildAgree       = $null
        InstallWimMeetsPca2023Prereq = $null
        # LCU level integrated in boot.wim
        BootWimHighestKb           = $null
        BootWimBuild               = $null
        BootWimBuildAgree          = $null
        BootWimMeetsPca2023Prereq  = $null
        # SecureBoot servicing keys read from install.wim's SYSTEM hive
        UEFICA2023Status           = $null
        UEFICA2023Error            = $null
        AvailableUpdatesHex        = $null
        # PCA2023 _EX payload census inside install.wim (fallback
        # conversion source when boot.wim is unserviceable)
        InstallHasEfiExDir         = $null
        InstallHasBootMgrFwEx      = $null
        InstallHasFontsEx          = $null
        InstallHasDvdEx            = $null
        InstallHasEfisysExBin      = $null
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
            $bootLcu = Get-ImageLcuEvidence -OsKey $Script:OsVersion -MountPath $bootMount
            $pkgElapsed = [int](New-TimeSpan -Start $pkgStart -End (Get-Date)).TotalSeconds
            Write-Step ('         boot.wim LCU evidence ({0}s): build={1} (pkg={2} reg={3} kern={4}; agree={5})' -f $pkgElapsed, `
                $(if ($bootLcu.Build) { $bootLcu.Build } else { '(none)' }), `
                $(if ($bootLcu.BuildFromPackages) { $bootLcu.BuildFromPackages } else { '-' }), `
                $(if ($bootLcu.BuildFromRegistry) { $bootLcu.BuildFromRegistry } else { '-' }), `
                $(if ($bootLcu.BuildFromKernel) { $bootLcu.BuildFromKernel } else { '-' }), $bootLcu.BuildSourcesAgree)
            $inv.BootWimHighestKb         = $bootLcu.LcuKbId
            $inv.BootWimBuild             = $bootLcu.Build
            $inv.BootWimBuildAgree        = $bootLcu.BuildSourcesAgree
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
            $inv.BootX64VerdictMethod = $authResult.Method
            $inv.BootX64X509IsPca2023 = $authResult.X509IsPca2023
            $inv.BootX64X509IsPca2011 = $authResult.X509IsPca2011
            $inv.BootX64EmbeddedParsed = $authResult.EmbeddedParsed
            $inv.BootX64EmbeddedIsPca2023 = $authResult.EmbeddedIsPca2023
            $inv.BootX64EmbeddedIsPca2011 = $authResult.EmbeddedIsPca2011
            $inv.BootX64EmbeddedSignatureCount = $authResult.EmbeddedSignatureCount
            $inv.BootX64EmbeddedSubjects = @($authResult.EmbeddedSubjects)
            $inv.BootX64EmbeddedError = $authResult.EmbeddedError
            Write-Step ('         bootx64.efi signer: {0}; verdict={1}' -f $authResult.SignerName, $authResult.Method)
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
                $installLcu = Get-ImageLcuEvidence -OsKey $Script:OsVersion -MountPath $installMount
                $iwPkgElapsed = [int](New-TimeSpan -Start $iwPkgStart -End (Get-Date)).TotalSeconds
                Write-Step ('         install.wim LCU evidence ({0}s): build={1} (pkg={2} reg={3} kern={4}; agree={5})' -f $iwPkgElapsed, `
                    $(if ($installLcu.Build) { $installLcu.Build } else { '(none)' }), `
                    $(if ($installLcu.BuildFromPackages) { $installLcu.BuildFromPackages } else { '-' }), `
                    $(if ($installLcu.BuildFromRegistry) { $installLcu.BuildFromRegistry } else { '-' }), `
                    $(if ($installLcu.BuildFromKernel) { $installLcu.BuildFromKernel } else { '-' }), $installLcu.BuildSourcesAgree)
                $inv.InstallWimHighestKb         = $installLcu.LcuKbId
                $inv.InstallWimBuild             = $installLcu.Build
                $inv.InstallWimBuildAgree        = $installLcu.BuildSourcesAgree
                $inv.InstallWimMeetsPca2023Prereq = $installLcu.MeetsPca2023Prereq

                # SYSTEM hive servicing keys
                Write-Step '         reading SYSTEM hive SecureBoot servicing keys ...'
                $servPath = 'ControlSet001\Control\SecureBoot\Servicing'
                $inv.UEFICA2023Status = Get-WimOfflineHiveValue -WimMountPath $installMount -HiveFile 'SYSTEM' -RelativeRegPath $servPath -ValueName 'UEFICA2023Status'
                $inv.UEFICA2023Error  = Get-WimOfflineHiveValue -WimMountPath $installMount -HiveFile 'SYSTEM' -RelativeRegPath $servPath -ValueName 'UEFICA2023Error'
                $auRaw = Get-WimOfflineHiveValue -WimMountPath $installMount -HiveFile 'SYSTEM' -RelativeRegPath 'ControlSet001\Control\SecureBoot' -ValueName 'AvailableUpdates'
                if ($null -ne $auRaw) {
                    $inv.AvailableUpdatesHex = ('0x{0:X}' -f [int]$auRaw)
                }

                # PCA2023 _EX census inside install.wim (same mount
                # session -- no extra mount cost). This is the
                # fallback conversion source when boot.wim is
                # unserviceable (Server 2019).
                $iwExBins  = Join-Path $installMount 'Windows\Boot\EFI_EX'
                $iwExFonts = Join-Path $installMount 'Windows\Boot\FONTS_EX'
                $iwExDvd   = Join-Path $installMount 'Windows\Boot\DVD_EX'
                $inv.InstallHasEfiExDir    = Test-Path -LiteralPath $iwExBins
                $inv.InstallHasFontsEx     = Test-Path -LiteralPath $iwExFonts
                $inv.InstallHasDvdEx       = Test-Path -LiteralPath $iwExDvd
                $inv.InstallHasBootMgrFwEx = if ($inv.InstallHasEfiExDir) { Test-Path -LiteralPath (Join-Path $iwExBins 'bootmgfw_EX.efi') } else { $false }
                $inv.InstallHasEfisysExBin = if ($inv.InstallHasDvdEx) { Test-Path -LiteralPath (Join-Path $iwExDvd 'EFI\en-US\efisys_EX.bin') } else { $false }
                Write-Step ('         install.wim _EX census: EFI_EX={0} bootmgfw_EX={1} DVD_EX={2}' -f $inv.InstallHasEfiExDir, $inv.InstallHasBootMgrFwEx, $inv.InstallHasDvdEx)
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

function Get-P10SkipReason {
    <#
    .SYNOPSIS
        Read the reason text recorded in the P10.skipped marker.
        Returns '' when the marker is absent or empty (P10 ran, or a
        pre-r11.64 empty marker).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $marker = Join-Path $Script:MarkersDir 'P10.skipped'
    if (-not (Test-Path -LiteralPath $marker)) { return '' }
    try {
        $txt = [string](Get-Content -LiteralPath $marker -Raw -ErrorAction Stop)
        return $txt.Trim()
    } catch { return '' }
}

function Get-SecureBootWorkflowReference {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    return [pscustomobject][ordered]@{
        Repository='microsoft/secureboot_objects'
        Release=$Script:SecureBootObjectsRelease
        SourceTag=$Script:SecureBootObjectsSourceTag
        Commit=$Script:SecureBootObjectsCommit
        Script='scripts/windows/Make2023BootableMedia.ps1'
        ScriptVersion=$Script:Make2023BootableMediaVersion
        ScriptDate=$Script:Make2023BootableMediaDate
        RequiredServicingFloor='2024-4B or later'
    }
}

function Test-OutputIsoPca2023Readiness {
    <#
    .SYNOPSIS
        Verify an extracted OUTPUT-ISO directory against the five
        conversion targets defined by Microsoft's
        Make2023BootableMedia.ps1 v1.6.5 / v1.6.5-signed / commit 798cdc5 (Copy-2023BootBins).

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
              .IsPca2023, .IsPca2011, .VerdictMethod, .X509IsPca2023,
              .X509IsPca2011, .EmbeddedParsed, .EmbeddedIsPca2023,
              .EmbeddedIsPca2011, .EmbeddedSignatureCount,
              .EmbeddedSubjects, .Status, .Notes
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
        [Parameter(Mandatory)] [string]$ExtractedMediaPath,
        [AllowEmptyString()] [string]$ConversionSkipReason = ''
    )

    $skippedByPolicy = $ConversionSkipReason.StartsWith('skipped-by-policy')
    $result = [pscustomobject]@{
        Generated     = (Get-Date)
        Available     = $false
        ErrorMessage  = $null
        ExtractedMediaPath = $ExtractedMediaPath
        OverallStatus = 'Unknown'
        ConversionSkippedByPolicy = $skippedByPolicy
        ConversionSkipReason      = $ConversionSkipReason
        OfficialWorkflow = (Get-SecureBootWorkflowReference)
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

    $checks  = [System.Collections.Generic.List[object]]::new()
    $reasons = [System.Collections.Generic.List[string]]::new()

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
        } elseif ($chain1.IsPca2011 -and $skippedByPolicy) {
            # An ADJUDICATED skip is not a build failure: grade it
            # Warning and name the policy, so the operator sees the
            # consequence without the run being marked broken.
            $status1 = 'Warning'
            $notes1  = ('UEFI Secure Boot critical path is PCA2011-signed BY POLICY ({0}). The ISO will not boot on firmware where PCA2011 has been revoked from DBX; conversion was intentionally skipped.' -f $ConversionSkipReason)
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
            VerdictMethod     = $chain1.Method
            X509IsPca2023     = $chain1.X509IsPca2023
            X509IsPca2011     = $chain1.X509IsPca2011
            EmbeddedParsed    = $chain1.EmbeddedParsed
            EmbeddedIsPca2023 = $chain1.EmbeddedIsPca2023
            EmbeddedIsPca2011 = $chain1.EmbeddedIsPca2011
            EmbeddedSignatureCount = $chain1.EmbeddedSignatureCount
            EmbeddedSubjects  = @($chain1.EmbeddedSubjects)
            EmbeddedError     = $chain1.EmbeddedError
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
            VerdictMethod     = $chain2.Method
            X509IsPca2023     = $chain2.X509IsPca2023
            X509IsPca2011     = $chain2.X509IsPca2011
            EmbeddedParsed    = $chain2.EmbeddedParsed
            EmbeddedIsPca2023 = $chain2.EmbeddedIsPca2023
            EmbeddedIsPca2011 = $chain2.EmbeddedIsPca2011
            EmbeddedSignatureCount = $chain2.EmbeddedSignatureCount
            EmbeddedSubjects  = @($chain2.EmbeddedSubjects)
            EmbeddedError     = $chain2.EmbeddedError
            Status            = 'PassWithNotes'
            Notes             = 'Per Make2023BootableMedia.ps1 (v1.6.5 / v1.6.5-signed / commit 798cdc5; script Version 1.4 dated 2026-03-13), bootmgr_EX.efi is copied to the ISO root when present even though Microsoft notes that this file is technically not signed with the Windows UEFI CA 2023 certificate. This is therefore PassWithNotes, while bootx64.efi remains the mandatory PCA2023 target.'
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
    $reasons = [System.Collections.Generic.List[string]]::new()

    if (-not $emb.Available) {
        $reasons.Add(('ISO inventory unavailable: {0}' -f $emb.ErrorMessage)) | Out-Null
        return [pscustomobject]@{
            Generated   = (Get-Date)
            Source      = 'IsoEmbedded'
            OsKey       = $OsKey
            OfficialWorkflow = (Get-SecureBootWorkflowReference)
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
    $hasInstallEfiEx = ($emb.InstallHasEfiExDir -eq $true) -and ($emb.InstallHasBootMgrFwEx -eq $true)

    if (-not $meetsPrereq) {
        $health = 'Critical'
        $reasons.Add('install.wim / boot.wim LCU level is BELOW 2024-04-09 (the Make2023BootableMedia.ps1 prerequisite). P10 ConvertPca2023BootManager would refuse to operate.') | Out-Null
        if ($emb.InstallWimBuild) {
            $reasons.Add(('Measured install.wim build: {0}' -f $emb.InstallWimBuild)) | Out-Null
        }
    } elseif ($isPca2023) {
        $health = 'Healthy'
        $reasons.Add('Static signature evidence shows that the UEFI critical boot manager contains a Windows UEFI CA 2023 embedded signature. Actual boot on PCA2023-only Secure Boot firmware remains unverified until P14 or equivalent hardware/VM validation succeeds.') | Out-Null
        if (-not $hasEfiEx -and $hasInstallEfiEx) {
            # The install.wim-fallback configuration (2026-07-08 E2E,
            # Server 2019): the media was converted from the serviced
            # install.wim because boot.wim is unserviceable on this OS
            # and never receives the _EX staging. Expected shape, not a
            # custom build. Stays Warning until the mixed configuration
            # (2023 boot manager + as-shipped WinPE) is proven by a
            # Secure Boot boot test [deferred adjudication 2026-07-08].
            $health = 'Warning'
            $reasons.Add('PCA2023 signer present; boot.wim carries no EFI_EX staging (unserviceable on this OS) while install.wim does -- the install.wim-FALLBACK conversion shape. Boot-manager signing is done; the 2023-bootmgr + as-shipped-WinPE combination awaits a Secure Boot boot test for final proof.') | Out-Null
        } elseif (-not $hasEfiEx) {
            $health = 'Warning'
            $reasons.Add('PCA2023 signer detected but neither boot.wim nor install.wim carries the EFI_EX staging - the media may be a custom build. Future maintenance flows may not detect the EFI_EX scaffolding.') | Out-Null
        }
    } elseif ($isPca2011 -and $hasEfiEx) {
        $health = 'Warning'
        $reasons.Add('bootx64.efi is still PCA2011-signed, BUT EFI_EX staging directory is present in boot.wim. P10 ConvertPca2023BootManager (or external Make2023BootableMedia.ps1) can promote this ISO to PCA2023 in one pass.') | Out-Null
    } elseif ($isPca2011 -and $hasInstallEfiEx) {
        $health = 'Warning'
        $reasons.Add('bootx64.efi is still PCA2011-signed and boot.wim carries no EFI_EX staging (unserviceable boot.wim), BUT the serviced install.wim carries the _EX payloads. P10 sources the PCA2023 boot manager from install.wim (fallback; MS-Q&A-confirmed direct workaround for revoked firmware).') | Out-Null
    } elseif ($isPca2011) {
        $health = 'Warning'
        $reasons.Add('bootx64.efi is still PCA2011-signed and NEITHER boot.wim NOR install.wim carries the EFI_EX staging payloads. Both images predate 2024-4B; P10 has no conversion source and will refuse to operate.') | Out-Null
    } else {
        # neither flag was set - we could not read the signature at all
        $health = 'Unknown'
        $reasons.Add('Could not determine bootx64.efi signer (no Authenticode chain readable). May indicate damaged ISO, missing OpenSSL/Windows SDK, or Linux pwsh limitations.') | Out-Null
    }

    # Add Server2025-specific advisory
    if ($OsKey -eq 'Server2025') {
        $reasons.Add('NOTE: Server 2025 is evaluated against Pca2023.CompliancePolicy, but automatic conversion is not attempted because this project''s Server 2025 conversion E2E has not yet completed. Use the force switch only as an approved experiment.') | Out-Null
    }

    [pscustomobject]@{
        Generated   = (Get-Date)
        Source      = 'IsoEmbedded'
        OsKey       = $OsKey
        OfficialWorkflow = (Get-SecureBootWorkflowReference)
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
        $kb = if ($emb.InstallWimBuild) { [string]$emb.InstallWimBuild } elseif ($emb.InstallWimHighestKb) { $emb.InstallWimHighestKb } else { 'n/a' }
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
    Write-Step ('  install.wim EFI_EX (fallback)  : {0}' -f $(if ($null -eq $emb.InstallHasEfiExDir) { 'n/a' } elseif ($emb.InstallHasEfiExDir) { 'present' } else { 'NOT present' }))
    Write-Step ''
    Write-Step '[bootx64.efi signer]'
    Write-Step ('  Signer subject  : {0}' -f $(if ($emb.BootX64SignerName) { $emb.BootX64SignerName } else { 'n/a' }))
    Write-Step ('  PCA2023 chain   : {0}' -f $emb.BootX64IsPca2023)
    Write-Step ('  PCA2011 chain   : {0}' -f $emb.BootX64IsPca2011)
    Write-Step ''
    Write-Step '[LCU integration level]'
    Write-Step ('  install.wim build : {0} (KB: {1}; sources agree: {2})' -f $(if ($emb.InstallWimBuild) { $emb.InstallWimBuild } else { 'n/a' }), $(if ($emb.InstallWimHighestKb) { $emb.InstallWimHighestKb } else { 'n/a' }), $(if ($null -ne $emb.InstallWimBuildAgree) { $emb.InstallWimBuildAgree } else { 'n/a' }))
    Write-Step ('  install.wim 2024-4B prereq : {0}' -f $emb.InstallWimMeetsPca2023Prereq)
    Write-Step ('  boot.wim    build : {0} (KB: {1}; sources agree: {2})' -f $(if ($emb.BootWimBuild) { $emb.BootWimBuild } else { 'n/a' }), $(if ($emb.BootWimHighestKb) { $emb.BootWimHighestKb } else { 'n/a' }), $(if ($null -ne $emb.BootWimBuildAgree) { $emb.BootWimBuildAgree } else { 'n/a' }))
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
    [void]$sb.AppendLine(('install.wim EFI_EX (fallback src) : {0}' -f $(if ($null -eq $emb.InstallHasEfiExDir) { 'n/a' } elseif ($emb.InstallHasEfiExDir) { 'present' } else { 'NOT present' })))
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
    [void]$sb.AppendLine(('install.wim measured build       : {0}' -f $(if ($emb.InstallWimBuild) { $emb.InstallWimBuild } else { 'n/a' })))
    [void]$sb.AppendLine(('install.wim build sources agree  : {0}' -f $(if ($null -ne $emb.InstallWimBuildAgree) { $emb.InstallWimBuildAgree } else { 'n/a' })))
    [void]$sb.AppendLine(('install.wim meets 2024-4B prereq : {0}' -f $emb.InstallWimMeetsPca2023Prereq))
    [void]$sb.AppendLine(('boot.wim    measured build       : {0}' -f $(if ($emb.BootWimBuild) { $emb.BootWimBuild } else { 'n/a' })))
    [void]$sb.AppendLine(('boot.wim    build sources agree  : {0}' -f $(if ($null -ne $emb.BootWimBuildAgree) { $emb.BootWimBuildAgree } else { 'n/a' })))
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
        repo, v1.6.5 / v1.6.5-signed / commit 798cdc5).

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
        SourceWim    = $null
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

    # Source-candidate order: boot.wim first (aligned with MS's
    # Make2023BootableMedia.ps1, which mounts boot.wim), then the
    # serviced install.wim as fallback. Fallback basis [user-
    # adjudicated 2026-07-07]: firmware Secure Boot verifies the
    # MEDIA's boot manager (not the WinPE behind it); MS Q&A
    # confirms a 2023-signed bootmgfw_EX taken from an updated image
    # boots old media on revoked firmware; and the LCU stages the
    # same _EX payloads into any serviced image. Needed because an
    # unserviceable boot.wim (Server 2019, 0x80070032) never
    # receives the payloads while its install.wim does.
    $installWimPath = Join-Path $ExtractedMediaPath 'sources\install.wim'
    $candidates = [System.Collections.Generic.List[object]]::new()
    $candidates.Add([pscustomobject]@{ Label = 'boot.wim'; Path = $bootWimPath; Index = 1 }) | Out-Null
    if (Test-Path -LiteralPath $installWimPath) {
        $fbIdx = 1
        try {
            $fbInv = Get-WimIndexInventory -WimPath $installWimPath
            if (@($fbInv).Count -ge 1 -and $fbInv[0].ImageIndex) { $fbIdx = [int]$fbInv[0].ImageIndex }
        } catch { $null = $_ }
        $candidates.Add([pscustomobject]@{ Label = 'install.wim'; Path = $installWimPath; Index = $fbIdx }) | Out-Null
    }

    $updated = [System.Collections.Generic.List[string]]::new()
    $mounted = $false
    try {
        $exBins = $null; $exFonts = $null; $exDvd = $null
        foreach ($cand in $candidates) {
            Write-Step ('Mounting {0} idx {1} (read-only, for PCA2023 source extraction): {2}' -f $cand.Label, $cand.Index, $cand.Path)
            $null = Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters @{ ImagePath = $cand.Path; Index = $cand.Index; Path = $mount; ReadOnly = $true; ErrorAction = 'Stop' }
            $mounted = $true

            $candBins  = Join-Path $mount 'Windows\Boot\EFI_EX'
            $candFonts = Join-Path $mount 'Windows\Boot\FONTS_EX'
            $candDvd   = Join-Path $mount 'Windows\Boot\DVD_EX'
            if ((Test-Path -LiteralPath $candBins) -and `
                (Test-Path -LiteralPath $candFonts) -and `
                (Test-Path -LiteralPath $candDvd)) {
                $exBins = $candBins; $exFonts = $candFonts; $exDvd = $candDvd
                $result.SourceWim = $cand.Label
                if ($cand.Label -ne 'boot.wim') {
                    Write-Caution ('PCA2023 source FALLBACK: boot.wim carries no _EX staging; sourcing from the serviced {0} idx {1} instead (measured-evidence path; boot test on PCA2023-only firmware is the final proof).' -f $cand.Label, $cand.Index)
                }
                Write-Step ('PCA2023 source selected: {0} (EFI_EX/FONTS_EX/DVD_EX all present)' -f $cand.Label)
                break
            }

            Write-Step ('{0} idx {1} carries no complete _EX staging set; dismounting and trying the next candidate.' -f $cand.Label, $cand.Index)
            $null = Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path = $mount; Discard = $true; ErrorAction = 'Stop' }
            $mounted = $false
        }

        if (-not $result.SourceWim) {
            $result.ErrorMessage = 'Neither boot.wim nor install.wim contains the EFI_EX/FONTS_EX/DVD_EX staging directories. Both images predate 2024-4B (April 2024 LCU); there is no PCA2023 conversion source on this media. This matches the Make2023BootableMedia.ps1 error "Make sure all required updates (2024-4B or later) have been applied".'
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
        if (($Action -in @('BootTest','All')) -or $Script:RunHyperVValidation) {
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

function Test-Server2025PcaPolicyPreflight {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Policy,[bool]$ForceConversion,[AllowEmptyString()][string]$SourceAssurance='')
    $allowed=$true; $reason='Policy does not require conversion.'
    if ($Policy -eq 'RequirePca2023') {
        $allowed = $ForceConversion -or ($SourceAssurance -eq 'VerifiedPca2023')
        $reason = if ($allowed) { 'RequirePca2023 is backed by an explicit conversion override or verified source-media assurance.' } else { 'Server 2025 RequirePca2023 needs -ForcePca2023OnServer2025 or Pca2023.SourceMediaAssurance=VerifiedPca2023.' }
    }
    [pscustomobject]@{Allowed=$allowed;Reason=$reason}
}

function Write-PatchFreshnessSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Patches,[AllowEmptyString()][string]$BaselineMonth='')
    if (-not $BaselineMonth) { return }
    Write-Step ('Effective PatchRefreshMode: {0}' -f $Script:EffectivePatchRefreshMode)
    foreach($kind in @('DotNet','SafeOSDU','SetupDU')) {
        foreach($patch in @($Patches | Where-Object { (Get-PatchEntryType -Patch $_) -eq $kind })) {
            $release=''; if($patch.PSObject.Properties['ReleaseDate']){$release=[string]$patch.ReleaseDate}
            $month=if($release -match '^(\d{4}-\d{2})'){$Matches[1]}else{'unknown'}
            $state=if($patch.PSObject.Properties['State']){[string]$patch.State}else{''}
            $fresh=if($month -eq $BaselineMonth){'CURRENT'}elseif($month -eq 'unknown'){'UNKNOWN'}else{'FALLBACK/STALE'}
            Write-Step ('  {0,-8}: {1} month={2} [{3}] state={4}' -f $kind,[string]$patch.KbId,$month,$fresh,$state)
        }
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
        if ($Script:OsVersion -eq 'Server2025') {
            $pcaPolicy=if($Script:OsProfile.Pca2023 -and $Script:OsProfile.Pca2023.CompliancePolicy){[string]$Script:OsProfile.Pca2023.CompliancePolicy}else{'AuditOnly'}
            $sourceAssurance=if($Script:OsProfile.Pca2023 -and $Script:OsProfile.Pca2023.PSObject.Properties['SourceMediaAssurance']){[string]$Script:OsProfile.Pca2023.SourceMediaAssurance}else{''}
            $pcaPreflight=Test-Server2025PcaPolicyPreflight -Policy $pcaPolicy -ForceConversion ([bool]$Script:ForcePca2023OnServer2025) -SourceAssurance $sourceAssurance
            if(-not $pcaPreflight.Allowed){throw $pcaPreflight.Reason}
            Write-Step ('Server2025 PCA2023 preflight: policy={0}; {1}' -f $pcaPolicy,$pcaPreflight.Reason)
        }

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
        $resolved = [System.Collections.Generic.List[object]]::new()
        if ($Script:EffectivePatchRefreshMode -in @('Auto','PinAll','PinOs') -or `
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
                    $resolved.Add((ConvertTo-ResolvedPatchFromBaselineLine -Line $p)) | Out-Null
                }
            } else {
                Write-Step 'PatchBaseline.Lines is empty; P03 will populate from Microsoft Update Catalog.'
            }
            # Static bridge LCU (SEED envelope; independent of Lines).
            # See ConvertTo-BridgeLcuResolvedPatch for the axis-3 basis.
            if ($Script:OsProfile.Schema -eq '3.0' -and $bl.PSObject.Properties['BridgeLcu'] -and $bl.BridgeLcu) {
                $bridgeEntry = ConvertTo-BridgeLcuResolvedPatch -BridgeLcu $bl.BridgeLcu
                $resolved.Add($bridgeEntry) | Out-Null
                Write-Step ('Bridge LCU staged: {0} (floor {1}; applied first, I0).' -f `
                    $bridgeEntry.KbId, [string]$bl.BridgeLcu.MinimumImageServicingStack)
            }
            if ($bl.PSObject.Properties['SourcePrerequisites'] -and $bl.SourcePrerequisites) {
                foreach ($prereq in @($bl.SourcePrerequisites)) {
                    $entry = ConvertTo-SourcePrerequisiteResolvedPatch -Prerequisite $prereq
                    # Avoid adding the v3 compatibility BridgeLcu twice.
                    if (-not (@($resolved | ForEach-Object { $_.PackageId }) -contains $entry.PackageId)) {
                        $resolved.Add($entry) | Out-Null
                    }
                }
                Write-Step ('SourcePrerequisites staged: {0} metadata/asset entry(s).' -f @($bl.SourcePrerequisites).Count)
            }
        } elseif ($Script:SyntheticTestMode) {
            Write-Step '-SyntheticTestMode is on; no real patches required.'
        } else {
            throw 'No patch source available. Pass -AutoDetectLatestPatches, or populate Config PatchBaseline.Lines (-Action RefreshAllBaselines).'
        }

        # Order by ApplyOrder, then by KbId. Wrap in @() to guarantee
        # an array even when $resolved is null or a single object.
        $Script:ResolvedPatches = @(Merge-ResolvedPatchDuplicates -Patches @($resolved | Sort-Object ApplyOrder, KbId))
        Write-Ok ('Patch list resolved: {0} unique entries.' -f $Script:ResolvedPatches.Count)

        # Build the WIM-target-aware PatchPlan and print summary.
        # Even when ResolvedPatches is empty (synthetic test mode), we
        # construct an empty plan so downstream Get-OrInitPatchPlan
        # calls in P07/P08 hit a populated cache.
        Set-DebugStep -Step 'build-patch-plan'
        $Script:PatchPlan = Build-PatchPlan -Patches $Script:ResolvedPatches
        Write-PatchPlanSummary -Plan $Script:PatchPlan
        Write-PatchFreshnessSummary -Patches $Script:ResolvedPatches -BaselineMonth (Get-ResearchCandidateBaselineMonth)

        # Emit CSV
        Set-DebugStep -Step 'emit-inputs-csv'
        $csvPath = Join-Path $Script:LogsDir 'P02_inputs_resolved.csv'
        $rows = [System.Collections.Generic.List[object]]::new()
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
        if ($Script:EffectivePatchRefreshMode -in @('PinAll','PinOs')) {
            Write-Skip ('P03 skipped: PatchRefreshMode={0} pins the reviewed OS baseline.' -f $Script:EffectivePatchRefreshMode)
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
                Schema = '3.0'
                TargetBuildAfterUpdate = ''
                PatchTuesdayOfBaseline = ''
                LastVerifiedDate = ''
                LastVerifiedBy = ''
                ChecksumAlgorithm = 'SHA256'
                Lines = @()
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
        foreach ($propName in @('Lines','PatchTuesdayOfBaseline','LastVerifiedDate','LastVerifiedBy','TargetBuildAfterUpdate')) {
            if (-not $pb.PSObject.Properties[$propName]) {
                $pb | Add-Member -NotePropertyName $propName -NotePropertyValue $null -Force
            }
        }
        $Script:OsProfile.PatchBaseline.Lines         = @($newPatches)
        $Script:OsProfile.PatchBaseline.PatchTuesdayOfBaseline = $latestPT.ToString('yyyy-MM-dd')
        $Script:OsProfile.PatchBaseline.LastVerifiedDate       = (Get-Date).ToString('o')
        $Script:OsProfile.PatchBaseline.LastVerifiedBy         = 'auto-scrape'
        # TargetBuildAfterUpdate is DERIVED: the LCU Line's Catalog-captured
        # InScope.build IS the post-update OS build. Hand-maintained seed
        # values proved to go stale silently; deriving at every Lines write
        # makes staleness structurally impossible (history: CHANGELOG,
        # tag 'tbau-derived-lcu-verify').
        $tbau = Get-TargetBuildFromLines -Lines @($newPatches)
        $Script:OsProfile.PatchBaseline.TargetBuildAfterUpdate = $tbau
        Write-Ok ('PatchBaseline updated in memory: {0} patches (TargetBuildAfterUpdate={1}).' -f $newPatches.Count, $(if ($tbau) { $tbau } else { '(none)' }))

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
        $derived = [System.Collections.Generic.List[object]]::new()
        foreach ($p in $newPatches) {
            $derived.Add((ConvertTo-ResolvedPatchFromBaselineLine -Line $p)) | Out-Null
        }
        $blRefreshed = $Script:OsProfile.PatchBaseline
        if ($Script:OsProfile.Schema -eq '3.0' -and $blRefreshed -and $blRefreshed.PSObject.Properties['BridgeLcu'] -and $blRefreshed.BridgeLcu) {
            $derived.Add((ConvertTo-BridgeLcuResolvedPatch -BridgeLcu $blRefreshed.BridgeLcu)) | Out-Null
        }
        if ($blRefreshed -and $blRefreshed.PSObject.Properties['SourcePrerequisites'] -and $blRefreshed.SourcePrerequisites) {
            foreach ($prereq in @($blRefreshed.SourcePrerequisites)) {
                $entry = ConvertTo-SourcePrerequisiteResolvedPatch -Prerequisite $prereq
                if (-not (@($derived | ForEach-Object { $_.PackageId }) -contains $entry.PackageId)) {
                    $derived.Add($entry) | Out-Null
                }
            }
        }
        $Script:ResolvedPatches = @(Merge-ResolvedPatchDuplicates -Patches @($derived | Sort-Object ApplyOrder, KbId))
        $Script:PatchPlan = Build-PatchPlan -Patches $Script:ResolvedPatches
        Write-Ok ('Derived {0} patch entries from refreshed baseline.' -f $Script:ResolvedPatches.Count)

        return $true
    } finally {
        Stop-DebugTrace
    }
}

function Test-RemotePatchUrlStatus {
    <#
    .SYNOPSIS
        Probe a configured patch URL without downloading the complete asset.
    .DESCRIPTION
        Returns Reachable, Missing, or Unknown. Some Windows Update CDN nodes
        reject HEAD, so a one-byte ranged GET is used as the fallback before
        declaring the result inconclusive.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)
    try {
        $r = Invoke-WebRequest -Uri $Uri -Method Head -UserAgent $script:CatUA `
            -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        return [pscustomobject]@{ State = 'Reachable'; StatusCode = [int]$r.StatusCode; Message = 'HEAD' }
    } catch {
        $status = $null
        try {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $status = [int]$_.Exception.Response.StatusCode
            }
        } catch { $status = $null }
        try {
            $r = Invoke-WebRequest -Uri $Uri -Method Get -UserAgent $script:CatUA `
                -Headers @{ Range = 'bytes=0-0' } -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            return [pscustomobject]@{ State = 'Reachable'; StatusCode = [int]$r.StatusCode; Message = 'Range GET fallback' }
        } catch {
            try {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $status = [int]$_.Exception.Response.StatusCode
                }
            } catch { }
            if ($status -in @(404, 410)) {
                return [pscustomobject]@{ State = 'Missing'; StatusCode = $status; Message = $_.Exception.Message }
            }
            return [pscustomobject]@{ State = 'Unknown'; StatusCode = $status; Message = $_.Exception.Message }
        }
    }
}

function Get-ResearchCandidateBaselineMonth {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if (-not $Script:OsProfile -or -not $Script:OsProfile.PatchBaseline) { return '' }
    $pb = $Script:OsProfile.PatchBaseline
    if ($pb.PSObject.Properties['BaselineId']) {
        $m = [regex]::Match([string]$pb.BaselineId, '^(\d{4}-\d{2})')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    if ($pb.PSObject.Properties['PatchTuesdayOfBaseline'] -and $pb.PatchTuesdayOfBaseline) {
        try { return ([datetime]$pb.PatchTuesdayOfBaseline).ToString('yyyy-MM') } catch { }
    }
    return ''
}

function New-DotNetMonthlySelectorLine {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$OsVersion,
        [Parameter(Mandatory)][string]$KbId,
        [Parameter(Mandatory)][string]$DotNetVersions,
        [Parameter(Mandatory)][string]$ReleaseDate,
        [Parameter(Mandatory)][string]$SourceUrl
    )
    $runtime = ''
    if ($DotNetVersions -match '4\.8\.1') { $runtime = '4.8.1' }
    elseif ($DotNetVersions -match '4\.8') { $runtime = '4.8' }
    elseif ($DotNetVersions -match '4\.7\.2') { $runtime = '4.7.2' }
    elseif ($DotNetVersions -match '4\.6\.2') { $runtime = '4.6.2' }
    $selector = [ordered]@{}
    if ($DotNetVersions -match '(^|\D)3\.5(\D|$)') { $selector.NetFx3 = 'PresentOrEnabled' }
    if ($runtime) { $selector.NetFx4Release = $runtime }
    return [pscustomobject][ordered]@{
        PackageId = ('{0}-{1}-x64' -f $OsVersion, $KbId)
        Kind = 'DotNet'; KbId = $KbId; ParentKbId = $null; UpdateId = $null; Revision = $null
        Title = ('Monthly .NET Framework CU selector: {0}' -f $DotNetVersions)
        Products = $null; Classification = $null; Architecture = 'x64'
        ReleaseDate = $ReleaseDate; ReleaseType = 'B'; State = 'Discovered'
        FileName = $null; DownloadUrl = $null; Digest = $null; Sha256 = ''; SizeBytes = $null
        ApplyOrder = 60; InScope = [pscustomobject]@{ DotNetVersions=$DotNetVersions }
        Note = 'Resolved from the official .NET Framework monthly release-notes page at P04.'
        Roles = @('DotNetLeaf'); TargetsByRole = [pscustomobject]@{ DotNetLeaf=@('Install') }
        RuntimeSelector = [pscustomobject]$selector
        Applicability = [pscustomobject]@{ Mode='IfRuntimeDetectedPerInstallIndex' }
        Dependencies = @()
        Integrity = [pscustomobject]@{ Sha1=$null; Sha256=$null; SizeBytes=$null; AuthenticodeStatus='NotTested' }
        Evidence = [pscustomobject]@{ Levels=@('E1'); SourceUrls=@($SourceUrl); VerifiedAt=(Get-Date).ToUniversalTime().ToString('o'); VerifiedBy='auto:DotNetReleaseNotes'; Notes=@('Exact Catalog asset is resolved immediately after selector refresh.') }
    }
}

function Resolve-DotNetMonthlySelectorLines {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$OsVersion,
        [Parameter(Mandatory)][string]$BaselineMonth
    )
    $cutoff = [datetime]::ParseExact(($BaselineMonth + '-28'), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $cache = $null
    try { $cache = Get-DotNetCuCache } catch { }
    $cacheLatest = ''
    if ($cache -and $cache.IndexSummary -and $cache.IndexSummary.LatestDate) { $cacheLatest = [string]$cache.IndexSummary.LatestDate }
    if (-not $cache -or -not $cacheLatest -or $cacheLatest.Substring(0,7) -lt $BaselineMonth) {
        Write-Step ('.NET monthly selector cache is missing/stale; fetching official release notes through {0}.' -f $Script:DotNetCuIndexUrl)
        $null = Invoke-DotNetCuFetch
        $null = Update-DotNetCuCache
        $cache = Get-DotNetCuCache
    }
    $months = @($cache.Months | Where-Object {
        $_.Ok -and $_.Date -and $_.Kind -notmatch '(?i)preview' -and ([datetime]$_.Date) -le $cutoff
    } | Sort-Object { [datetime]$_.Date } -Descending)
    $selectedMonth = $null; $selectedEntry = $null
    foreach ($month in $months) {
        $entry = @($month.Entries | Where-Object { $_.OsNormalised -eq $OsVersion }) | Select-Object -First 1
        if ($entry) { $selectedMonth=$month; $selectedEntry=$entry; break }
    }
    if (-not $selectedEntry) { throw ('.NET release notes did not contain an applicable entry for {0} at or before {1}.' -f $OsVersion, $BaselineMonth) }
    $allowed = switch ($OsVersion) {
        'Server2016' { @('4.8') }
        'Server2019' { @('4.7.2','4.8') }
        'Server2022' { @('4.8','4.8.1') }
        'Server2025' { @('4.8.1') }
        default { @() }
    }
    $lines = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @($selectedEntry.Rows)) {
        if (-not $row.KbId) { continue }
        $matched = $false
        foreach ($v in $allowed) { if ([string]$row.DotNetVersions -match [regex]::Escape($v)) { $matched=$true; break } }
        if (-not $matched) { continue }
        $lines.Add((New-DotNetMonthlySelectorLine -OsVersion $OsVersion -KbId ([string]$row.KbId) -DotNetVersions ([string]$row.DotNetVersions) -ReleaseDate ([string]$selectedMonth.Date) -SourceUrl ([string]$selectedMonth.AbsoluteUrl))) | Out-Null
    }
    if ($lines.Count -eq 0) { throw ('.NET release notes entry for {0} had no supported runtime leaf rows.' -f $OsVersion) }
    Write-Ok ('.NET monthly selectors: {0} ({1}) -> {2}' -f $OsVersion, $selectedMonth.Date, (@($lines | ForEach-Object KbId) -join ', '))
    return @($lines.ToArray())
}

function ConvertTo-StableObjectArray {
    <#
    .SYNOPSIS
        Materialize any enumerable as an ordinary PowerShell object array.
    .DESCRIPTION
        Avoids engine-specific array-subexpression behaviour around generic
        collections.  The optional test switch deliberately round-trips the
        input through Generic.List[object] so the same implementation can be
        exercised under Windows PowerShell 5.1 and PowerShell 7 in CI.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [AllowNull()][object]$InputObject,
        [switch]$SimulateGenericList
    )

    $source = $InputObject
    if ($SimulateGenericList) {
        $generic = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $InputObject) {
            foreach ($item in $InputObject) { $generic.Add($item) | Out-Null }
        }
        $source = $generic
    }

    $result = @()
    if ($null -ne $source) {
        foreach ($item in $source) { $result += ,$item }
    }
    return $result
}

function Get-PatchRefreshDecision {
    <# Pure option-semantics helper used by P03/P04 and runtime tests. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [bool]$UseBaselineOnly,
        [bool]$SkipDynamicPatchRefresh,
        [bool]$AutoDetectLatestPatches,
        [bool]$ConfigResolveMonthlyAuxiliariesAtFetch,
        [AllowEmptyString()][string]$BaselineStatus = '',
        [AllowEmptyString()][ValidateSet('','PinAll','PinOs','Auto')][string]$PatchRefreshMode = ''
    )
    $mutable = $BaselineStatus -in @('', 'ResearchCandidate', 'Discovered', 'Resolved')
    $effective = if ($PatchRefreshMode) { $PatchRefreshMode } elseif ($UseBaselineOnly) { 'PinAll' } elseif ($SkipDynamicPatchRefresh) { 'PinOs' } elseif ($AutoDetectLatestPatches) { 'Auto' } else { 'Auto' }
    switch ($effective) {
        'PinAll' {
            $mode='PinAll'; $refreshBaseline=$false; $refreshMonthly=$false
            $exactAssetPolicy='ConfiguredIdentityMissingAssetOnly'
        }
        'PinOs' {
            $mode='PinOs'; $refreshBaseline=$false
            $refreshMonthly=$mutable -and $ConfigResolveMonthlyAuxiliariesAtFetch
            $exactAssetPolicy=$(if ($mutable) { 'RefreshAllMutableAssets' } else { 'MissingAssetOnly' })
        }
        default {
            $mode='Auto'; $refreshBaseline=$true
            $refreshMonthly=$mutable -and $ConfigResolveMonthlyAuxiliariesAtFetch
            $exactAssetPolicy=$(if ($mutable) { 'RefreshAllMutableAssets' } else { 'MissingAssetOnly' })
        }
    }
    return [pscustomobject][ordered]@{
        Mode=$mode
        RefreshBaseline=[bool]$refreshBaseline
        ResolveMonthlyAuxiliariesAtFetch=[bool]$refreshMonthly
        ExactCatalogAssetPolicy=$exactAssetPolicy
        BaselineMutable=[bool]$mutable
    }
}

function Update-MonthlyAuxiliaryResolvedPatchesAtFetch {
    [CmdletBinding()]
    param()
    if ($Script:EffectivePatchRefreshMode -eq 'PinAll') {
        Write-Skip 'P04 monthly auxiliary refresh skipped: PatchRefreshMode=PinAll pins configured KB identities.'
        return
    }
    $policy = $null
    if ($Script:OsProfile -and $Script:OsProfile.PSObject.Properties['DiscoveryPolicy']) { $policy = $Script:OsProfile.DiscoveryPolicy }
    if (-not $policy -or -not $policy.PSObject.Properties['ResolveMonthlyAuxiliariesAtFetch'] -or -not [bool]$policy.ResolveMonthlyAuxiliariesAtFetch) { return }
    $month = Get-ResearchCandidateBaselineMonth
    if (-not $month) { throw 'ResolveMonthlyAuxiliariesAtFetch is enabled, but the baseline month could not be derived.' }
    Write-SubSection ('Step 0A: Resolve monthly auxiliary packages for {0}' -f $month)
    $osShort = $Script:OsVersion -replace '^Server',''
    $modelMap = @{ Server2016='separate-ssu'; Server2019='embedded-ssu'; Server2022='embedded-ssu-du'; Server2025='uup-checkpoint' }

    # Use ordinary PowerShell arrays here.  Windows PowerShell 5.1 and pwsh
    # 7.6 bind Generic.List[object] differently inside @(...), which caused
    # "Argument types do not match" at the conversion loop in r12.08.
    $freshConfigLines = @()
    if ($Script:OsVersion -eq 'Server2016') {
        $rawSsu = Resolve-Ssu2016 -BaselineMonth $month
        $convertedSsu = @(ConvertTo-ConfigLines -OsResolved ([pscustomobject]@{os=$Script:OsVersion;lines=@($rawSsu)}) -PatchModel $modelMap[$Script:OsVersion])
        foreach ($x in (ConvertTo-StableObjectArray -InputObject $convertedSsu)) { $freshConfigLines += ,$x }
    }
    $duResults = @(
        (Resolve-SafeOsDu -OsKey $osShort -BaselineMonth $month)
        (Resolve-SetupDu -OsKey $osShort -BaselineMonth $month)
    )
    foreach ($rawDu in $duResults) {
        $convertedDu = @(ConvertTo-ConfigLines -OsResolved ([pscustomobject]@{os=$Script:OsVersion;lines=@($rawDu)}) -PatchModel $modelMap[$Script:OsVersion])
        foreach ($x in (ConvertTo-StableObjectArray -InputObject $convertedDu)) { $freshConfigLines += ,$x }
    }
    $dotNetLines = @(Resolve-DotNetMonthlySelectorLines -OsVersion $Script:OsVersion -BaselineMonth $month)
    foreach ($x in (ConvertTo-StableObjectArray -InputObject $dotNetLines)) { $freshConfigLines += ,$x }

    $kept = @()
    foreach ($p in @($Script:ResolvedPatches)) {
        $roles = @(Get-PatchRoles -Patch $p)
        $t = Get-PatchEntryType -Patch $p
        $isSourcePrereq = $roles -contains 'SourcePrerequisite'
        if ($isSourcePrereq -or $t -in @('LCU','Checkpoint','BridgeLcu')) { $kept += ,$p }
    }
    foreach ($line in (ConvertTo-StableObjectArray -InputObject $freshConfigLines)) {
        $resolvedLine = ConvertTo-ResolvedPatchFromBaselineLine -Line $line
        $kept += ,$resolvedLine
    }
    $sortedPatches = @($kept | Sort-Object ApplyOrder,KbId)
    $Script:ResolvedPatches = @(Merge-ResolvedPatchDuplicates -Patches $sortedPatches)
    $Script:PatchPlan = Build-PatchPlan -Patches $Script:ResolvedPatches
    $evidencePath = Join-Path $Script:LogsDir 'P04_monthly_auxiliary_selection.json'
    @(ConvertTo-StableObjectArray -InputObject $freshConfigLines) | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    Write-Ok ('Monthly auxiliary selection written: {0}' -f $evidencePath)
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

        # Step 0: perform a complete exact-KB Catalog preflight before
        # downloading the multi-GB source ISO. Mutable research candidates
        # normally refresh every exact-KB asset. -UseBaselineOnly pins KB
        # identities and refreshes only assets whose URL/file identity is
        # missing. Frozen/Approved baselines follow the same missing-only rule.
        Write-SubSection 'Step 0: Cross-check all exact-KB Catalog assets'
        Set-DebugStep -Step 'patch-asset-crosscheck'
        $baselineStatus = ''
        if ($Script:OsProfile -and $Script:OsProfile.PatchBaseline -and $Script:OsProfile.PatchBaseline.PSObject.Properties['Status']) {
            $baselineStatus = [string]$Script:OsProfile.PatchBaseline.Status
        }
        $configResolveAux = $false
        if ($Script:OsProfile -and $Script:OsProfile.PSObject.Properties['DiscoveryPolicy'] -and
            $Script:OsProfile.DiscoveryPolicy -and
            $Script:OsProfile.DiscoveryPolicy.PSObject.Properties['ResolveMonthlyAuxiliariesAtFetch']) {
            $configResolveAux = [bool]$Script:OsProfile.DiscoveryPolicy.ResolveMonthlyAuxiliariesAtFetch
        }
        $refreshDecision = Get-PatchRefreshDecision `
            -UseBaselineOnly ([bool]$Script:UseBaselineOnly) `
            -SkipDynamicPatchRefresh ([bool]$Script:SkipDynamicPatchRefresh) `
            -AutoDetectLatestPatches ([bool]$Script:AutoDetectLatestPatches) `
            -ConfigResolveMonthlyAuxiliariesAtFetch $configResolveAux `
            -BaselineStatus $baselineStatus `
            -PatchRefreshMode ([string]$Script:EffectivePatchRefreshMode)
        Write-Step ('Effective patch refresh mode: {0}; monthly auxiliaries={1}; exact assets={2}' -f
            $refreshDecision.Mode, $refreshDecision.ResolveMonthlyAuxiliariesAtFetch, $refreshDecision.ExactCatalogAssetPolicy)
        Write-Step ('Catalog identity policy: requestLocale={0} (best-effort); selection={1}; propagatedDisplayMetadata={2}' -f
            $script:CatRequestLocale, $script:CatSelectionPolicy, $script:CatDisplayLanguagePolicy)
        if ($refreshDecision.ResolveMonthlyAuxiliariesAtFetch) {
            Update-MonthlyAuxiliaryResolvedPatchesAtFetch
        } else {
            Write-Skip ('P04 monthly auxiliary replacement disabled by effective mode: {0}.' -f $refreshDecision.Mode)
        }
        $refreshAllMutableAssets = $refreshDecision.ExactCatalogAssetPolicy -eq 'RefreshAllMutableAssets'
        foreach ($p in @($Script:ResolvedPatches)) {
            if (-not $p -or [string]::IsNullOrWhiteSpace([string]$p.KbId)) { continue }
            $type = Get-PatchEntryType -Patch $p
            $isMetadataOnly = ($p.PSObject.Properties['IsMetadataOnly'] -and $p.IsMetadataOnly)
            $sourceMissing = [string]::IsNullOrWhiteSpace([string]$p.Source)
            $needsAssetResolution = $isMetadataOnly -or $sourceMissing
            if ($refreshAllMutableAssets -or $needsAssetResolution) {
                Write-Step ('Catalog cross-check: {0}/{1} on {2}' -f $type, $p.KbId, $Script:OsVersion)
                $null = Resolve-ResolvedPatchAssetFromCatalog -Patch $p -Force -RefreshCache:$refreshAllMutableAssets
                $probe = Test-RemotePatchUrlStatus -Uri ([string]$p.Source)
                if ($probe.State -eq 'Missing') {
                    throw ('Catalog returned a missing content URL (HTTP {0}) for {1}/{2}: {3}' -f $probe.StatusCode, $type, $p.KbId, $p.Source)
                }
                if ($probe.State -eq 'Unknown') {
                    Write-Caution ('Catalog content probe was inconclusive for {0}/{1}; download retry and integrity validation remain authoritative. {2}' -f $type, $p.KbId, $probe.Message)
                } else {
                    Write-Ok ('Catalog content URL reachable: {0}/{1} ({2} HTTP {3})' -f $type, $p.KbId, $probe.Message, $probe.StatusCode)
                }
                continue
            }
            if ([string]$p.Source -match '^https?://') {
                $probe = Test-RemotePatchUrlStatus -Uri ([string]$p.Source)
                if ($probe.State -eq 'Missing') {
                    throw ('Frozen baseline URL returned HTTP {0} for {1}/{2}. Create and validate a new candidate; the frozen identity will not be mutated.' -f $probe.StatusCode, $type, $p.KbId)
                } elseif ($probe.State -eq 'Unknown') {
                    Write-Step ('Frozen URL preflight inconclusive for {0}/{1}; download integrity remains authoritative. {2}' -f $type, $p.KbId, $probe.Message)
                }
            }
        }
        $catalogEvidence = @($Script:ResolvedPatches | ForEach-Object {
            [pscustomobject]@{
                OsKey = $Script:OsVersion
                Kind = (Get-PatchEntryType -Patch $_)
                KbId = [string]$_.KbId
                UpdateId = $(if ($_.PSObject.Properties['UpdateId']) { [string]$_.UpdateId } else { '' })
                Title = $(if ($_.PSObject.Properties['Title']) { [string]$_.Title } else { '' })
                CatalogClassification = $(if ($_.PSObject.Properties['CatalogClassification']) { [string]$_.CatalogClassification } else { '' })
                CatalogProducts = $(if ($_.PSObject.Properties['CatalogProducts']) { [string]$_.CatalogProducts } else { '' })
                CatalogDisplayLanguagePolicy = $script:CatDisplayLanguagePolicy
                CatalogSelectionPolicy = $script:CatSelectionPolicy
                CatalogSelectionBasis = $(if ($_.PSObject.Properties['CatalogSelectionBasis']) { [string]$_.CatalogSelectionBasis } else { '' })
                CatalogObservedMetadataStatus = $(if ($_.PSObject.Properties['CatalogObservedMetadataStatus']) { [string]$_.CatalogObservedMetadataStatus } else { '' })
                CatalogObservedTitleSha256 = $(if ($_.PSObject.Properties['CatalogObservedTitleSha256']) { [string]$_.CatalogObservedTitleSha256 } else { '' })
                CatalogObservedClassificationSha256 = $(if ($_.PSObject.Properties['CatalogObservedClassificationSha256']) { [string]$_.CatalogObservedClassificationSha256 } else { '' })
                CatalogObservedProductsSha256 = $(if ($_.PSObject.Properties['CatalogObservedProductsSha256']) { [string]$_.CatalogObservedProductsSha256 } else { '' })
                CatalogScopedIdentityVerified = [bool]($_.PSObject.Properties['CatalogScopedIdentityVerified'] -and $_.CatalogScopedIdentityVerified)
                CatalogScopedIdentityBasis = $(if ($_.PSObject.Properties['CatalogScopedIdentityBasis']) { [string]$_.CatalogScopedIdentityBasis } else { '' })
                CatalogScopedArchitecture = $(if ($_.PSObject.Properties['CatalogScopedArchitecture']) { [string]$_.CatalogScopedArchitecture } else { '' })
                CatalogScopedRawSha256 = $(if ($_.PSObject.Properties['CatalogScopedRawSha256']) { [string]$_.CatalogScopedRawSha256 } else { '' })
                CatalogScopedParseBasis = $(if ($_.PSObject.Properties['CatalogScopedParseBasis']) { [string]$_.CatalogScopedParseBasis } else { '' })
                CatalogRequestLocale = $script:CatRequestLocale
                Source = [string]$_.Source
                FileName = [System.IO.Path]::GetFileName([string]$_.LocalPath)
                MetadataOnly = [bool]($_.PSObject.Properties['IsMetadataOnly'] -and $_.IsMetadataOnly)
            }
        })
        $catalogEvidencePath = Join-Path $Script:LogsDir 'P04_catalog_crosscheck.json'
        $catalogEvidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $catalogEvidencePath -Encoding UTF8
        Write-Ok ('Catalog cross-check evidence written: {0}' -f $catalogEvidencePath)
        $Script:PatchPlan = Build-PatchPlan -Patches $Script:ResolvedPatches

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

        # Optional integrity check against the config-recorded SHA-256
        # (per-language LanguageSpecific.<lang>.Iso.Sha256)
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
            if ($p.PSObject.Properties['IsMetadataOnly'] -and $p.IsMetadataOnly) {
                throw ('Patch asset remains unresolved after exact-KB Catalog resolution: {0}/{1}.' -f (Get-PatchEntryType -Patch $p), $p.KbId)
            }
            $leaf = [System.IO.Path]::GetFileName($p.LocalPath)
            # Per-patch landing directory: LCU/Checkpoint land in the
            # cu\ discovery subfolder (Get-PatchLocalPath), so the
            # parent may not exist yet on a fresh WorkRoot.
            $patchParent = [System.IO.Path]::GetDirectoryName($p.LocalPath)
            if ($patchParent -and -not (Test-Path -LiteralPath $patchParent)) {
                New-Item -ItemType Directory -Path $patchParent -Force | Out-Null
            }
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
                try {
                    Invoke-WebRequestWithRetry -Uri $p.Source -OutFile $patchTmp -MaxAttempts 3
                } catch {
                    Remove-Item -LiteralPath $patchTmp -Force -ErrorAction SilentlyContinue
                    Write-Caution ('  committed download URL failed ({0}); re-resolving exact KB {1} from Catalog.' -f $_.Exception.Message, $p.KbId)
                    $null = Resolve-ResolvedPatchAssetFromCatalog -Patch $p -Force -RefreshCache
                    $patchParent = [System.IO.Path]::GetDirectoryName($p.LocalPath)
                    if ($patchParent -and -not (Test-Path -LiteralPath $patchParent)) {
                        New-Item -ItemType Directory -Path $patchParent -Force | Out-Null
                    }
                    $patchTmp = Join-Path $targetDir ('.dl_' + [Guid]::NewGuid().Guid + '.part')
                    Invoke-WebRequestWithRetry -Uri $p.Source -OutFile $patchTmp -MaxAttempts 3
                }
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

        $rows = [System.Collections.Generic.List[object]]::new()
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

        # ---- Pre-servicing media inspection [user-adjudicated 2026-07-07] ----
        # Records the state of EVERY WIM index BEFORE any patch is
        # applied (one mount per index, everything in one pass), so
        # P13 can diff before/after and observe-first cross-checks
        # have a measured baseline. Failure here is a Warning + an
        # errors.jsonl entry, never a phase failure: the build must
        # not die because the microscope broke.
        $preWim = Join-Path $Script:ExtractedDir 'sources\install.wim'
        if ($Script:Execute -and -not $Script:SyntheticTestMode -and (Test-Path -LiteralPath $preWim)) {
            Set-DebugStep -Step 'pre-inspection'
            Write-SubSection 'Pre-servicing media inspection'
            try {
                $preMount = Join-Path $Script:WorkRoot 'work\inspect_mount'
                $preInsp = Get-MediaInspection -OsKey $Script:OsVersion -MediaRoot $Script:ExtractedDir `
                    -Label 'pre' -MountDir $preMount -LogDir $Script:LogsDir
                $preJson = Write-MediaInspectionJson -Inspection $preInsp -LogDir $Script:LogsDir
                Write-Ok ('Pre-servicing inspection written: {0}' -f $preJson)
            } catch {
                Write-Caution ('Pre-servicing inspection failed: {0}' -f $_.Exception.Message)
                Add-ErrorJsonlEntry -Phase 'P06' -Kind 'warning' -Properties @{
                    subsystem = 'media-inspection'; label = 'pre'
                    message = $_.Exception.Message
                }
            }
        } elseif ($Script:Execute -and -not $Script:SyntheticTestMode) {
            Write-Step 'Pre-servicing inspection skipped (extracted media not present yet in this run shape).'
        }
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
    $p07Succeeded = $false
    $p07Backup = ''
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
        } elseif ($Script:Execute -and -not $Script:SyntheticTestMode) {
            $backupDir = Join-Path $Script:StateDir 'p07-backup'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            $p07Backup = Join-Path $backupDir 'install.wim.pre-p07'
            $p07BackupPart = $p07Backup + '.part'
            Write-Step ('Creating P07 transaction backup: {0}' -f $p07Backup)
            Remove-Item -LiteralPath $p07BackupPart -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $installWim -Destination $p07BackupPart -Force
            Move-Item -LiteralPath $p07BackupPart -Destination $p07Backup -Force
            Set-Content -LiteralPath ($p07Backup + '.sha256') -Value ((Get-FileHash -LiteralPath $p07Backup -Algorithm SHA256).Hash.ToLower()) -Encoding ASCII
        }

        $patches = Get-PatchListForInstallWim
        Write-Step ('install.wim-targeted patches: {0}' -f $patches.Count)

        # Pull the role-based install sequence from the cached PatchPlan.
        # Current order is prerequisite/carrier -> language/FOD -> final LCU
        # -> cleanup -> .NET -> export. The plan was built in P02.
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

        $rows = [System.Collections.Generic.List[object]]::new()
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
                        $plannedType = Get-PatchEntryType -Patch $p
                        Write-Step ('  [PLAN] {0}: {1} ({2}) -> {3}' -f $sp.Name, $p.KbId, $plannedType, $imgLabel)
                        $rows.Add([pscustomobject]@{
                            KbId = $p.KbId; PatchType = $plannedType
                            FilePath = $p.LocalPath; ApplyOrder = $p.ApplyOrder
                            AppliesTo = $imgLabel; SubPhase = $sp.Name
                            ApplyStatus = 'Planned'; ElapsedSeconds = 0
                            DismExitCode = 0
                        }) | Out-Null
                    }
                }
                continue
            }

            # Execute the generated role-based sequence in order. The generic
            # remount path remains for compatibility with a future or legacy
            # plan that explicitly marks a sub-phase RequiresRemount; the v4
            # default sequence does not rely on a hard-coded I7 second pass.

            $remountAndContinue = $false
            $secondPassSubPhases = [System.Collections.Generic.List[object]]::new()
            Set-DebugStep -Step ('mount-install-pass1-idx-' + $img.ImageIndex)
            Invoke-WimMountSafe -ImagePath $installWim -Index $img.ImageIndex `
                -Path $Script:MountInstallDir -LogDir $Script:LogsDir | Out-Null
            $pass1Succeeded = $false
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
                $pass1Succeeded = $true
            } finally {
                Set-DebugStep -Step ('dismount-install-pass1-idx-' + $img.ImageIndex)
                Invoke-WimDismountSafe -Path $Script:MountInstallDir -Discard:(-not $pass1Succeeded) -LogDir $Script:LogsDir
            }

            # Second-pass: LCU re-apply when LP was actually injected.
            # Mount the just-exported image fresh, run the deferred
            # sub-phases, cleanup + export again.
            if ($remountAndContinue -and $secondPassSubPhases.Count -gt 0) {
                Write-Step ('  Re-mounting install.wim idx {0} for LCU second pass ({1} sub-phase(s)).' -f $img.ImageIndex, $secondPassSubPhases.Count)
                Set-DebugStep -Step ('mount-install-pass2-idx-' + $img.ImageIndex)
                Invoke-WimMountSafe -ImagePath $installWim -Index $img.ImageIndex `
                    -Path $Script:MountInstallDir -LogDir $Script:LogsDir | Out-Null
                $pass2Succeeded = $false
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
                    $pass2Succeeded = $true
                } finally {
                    Set-DebugStep -Step ('dismount-install-pass2-idx-' + $img.ImageIndex)
                    Invoke-WimDismountSafe -Path $Script:MountInstallDir -Discard:(-not $pass2Succeeded) -LogDir $Script:LogsDir
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
        $p07Succeeded = $true
    } finally {
        if ($p07Backup -and -not $p07Succeeded -and (Test-Path -LiteralPath $p07Backup)) {
            Write-Caution 'P07 failed; restoring install.wim from the transaction backup.'
            try {
                Copy-Item -LiteralPath $p07Backup -Destination (Join-Path $Script:ExtractedDir 'sources\install.wim') -Force
                Write-DismRollbackEvidence -Phase 'P07' -Result 'Restored' -Context 'install.wim transaction backup'
            } catch {
                Write-DismRollbackEvidence -Phase 'P07' -Result 'Failed' -Context 'install.wim transaction backup' -Error $_.Exception.Message
                throw
            }
            Remove-Item -LiteralPath (Join-Path $Script:MarkersDir 'P07.ok') -Force -ErrorAction SilentlyContinue
        }
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P08: Patch boot.wim + winre.wim (Build group)
# ============================================================

function Assert-ExpandedBootLcuTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MountPath,[Parameter(Mandatory)][string]$ImageLabel)
    if((Get-BootWimPackageMode) -ne 'ExpandedCab'){return}
    $lcu=@($Script:OsProfile.PatchBaseline.Lines|Where-Object{$_.Kind -eq 'LCU' -and $_.KbId})|Select-Object -First 1
    if(-not $lcu){throw 'Expanded boot servicing requires a baseline LCU definition.'}
    $src=Get-WimBuildSources -MountPath $MountPath
    $ev=switch($Script:OsVersion){
        'Server2016'{Resolve-LcuEvidence_Server2016 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild}
        'Server2019'{Resolve-LcuEvidence_Server2019 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild}
        'Server2022'{Resolve-LcuEvidence_Server2022 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild}
        'Server2025'{Resolve-LcuEvidence_Server2025 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild}
    }
    $row=Test-LcuTargetApplied -OsKey $Script:OsVersion -ExpectedKbId ([string]$lcu.KbId) -ExpectedBuild ([string]$Script:OsProfile.PatchBaseline.TargetBuildAfterUpdate) -Evidence $ev
    if($row.Status -ne 'Pass'){throw ('{0} did not reach expanded-CAB LCU target: {1}' -f $ImageLabel,$row.Notes)}
    Write-Ok ('{0}: expanded-CAB target verified ({1}).' -f $ImageLabel,$row.Notes)
}

function Invoke-BuildPhase08_PatchBootWim {
    <#
    .SYNOPSIS
        P08: Service boot.wim indexes (PE + Setup) under the per-OS
        Common.BootWimLcuPolicy (enabled | disabled | tolerate), and
        winre.wim (extracted from install.wim) under EnableWinREUpdate.
    .DESCRIPTION
        BootWimLcuPolicy governs ONLY the boot.wim loop:
          enabled  -- current strict behaviour (a failure aborts P08).
          disabled -- boot.wim left as shipped; WinRE servicing below
                      STILL RUNS (the old boolean gate skipped both,
                      which silently dropped SafeOS DU servicing).
          tolerate -- attempt; on failure Write-Caution, dismount the
                      index with -Discard (never commit a partial CBS
                      transaction), continue with the next index and
                      the WinRE section. Purpose: measure per-media
                      LCU-serviceability (2022) without losing the run.
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase08_PatchBootWim' -PhaseId 'P08'
    $p08Succeeded = $false
    $p08BootBackup = ''
    $p08InstallBackup = ''
    try {
        $bootPolicy = Resolve-BootWimLcuPolicyValue -RawValue $Script:OsProfile.BootWimLcuPolicy
        $bootFailurePolicy = Resolve-BootWimFailurePolicyValue -RawValue $Script:OsProfile.BootWimFailurePolicy
        $bootServicingStrategy = Get-BootWimServicingStrategy
        $bootPolicyException = $null
        $bootPolicyExceptionPath = Join-Path $Script:LogsDir 'P08_bootwim_policy_exception.json'
        Remove-Item -LiteralPath $bootPolicyExceptionPath -Force -ErrorAction SilentlyContinue
        Write-Step ('boot.wim LCU policy: {0}; failure policy: {1}; servicing strategy: {2}' -f $bootPolicy,$bootFailurePolicy,$bootServicingStrategy)
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

        if ($Script:Execute -and -not $Script:SyntheticTestMode) {
            $backupDir = Join-Path $Script:StateDir 'p08-backup'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            $p08BootBackup = Join-Path $backupDir 'boot.wim.pre-p08'
            $p08InstallBackup = Join-Path $backupDir 'install.wim.pre-p08'
            $installForBackup = Join-Path $Script:ExtractedDir 'sources\install.wim'
            Write-Step 'Creating P08 transaction backups for boot.wim and install.wim.'
            $bootPart = $p08BootBackup + '.part'
            $installPart = $p08InstallBackup + '.part'
            Remove-Item -LiteralPath $bootPart,$installPart -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $bootWim -Destination $bootPart -Force
            Copy-Item -LiteralPath $installForBackup -Destination $installPart -Force
            Move-Item -LiteralPath $bootPart -Destination $p08BootBackup -Force
            Move-Item -LiteralPath $installPart -Destination $p08InstallBackup -Force
            Save-CanonicalJsonFile -InputObject ([pscustomobject]@{
                Timestamp=(Get-Date).ToString('o')
                BootWimSha256=(Get-FileHash -LiteralPath $p08BootBackup -Algorithm SHA256).Hash.ToLower()
                InstallWimSha256=(Get-FileHash -LiteralPath $p08InstallBackup -Algorithm SHA256).Hash.ToLower()
            }) -Path (Join-Path $backupDir 'backup-manifest.json') -Depth 4
        }

        # The patch plan is shared state for BOTH the boot.wim loop
        # and the WinRE section below; it must exist on every policy
        # path. (History: assigning it only inside the non-disabled
        # branch left the WinRE section dereferencing an undefined
        # variable on the disabled path -- 2026-07-07 Server 2019 E2E.)
        $plan = Get-OrInitPatchPlan

        if ($bootPolicy -eq 'disabled') {
            Write-Skip 'BootWimLcuPolicy=disabled; boot.wim left as shipped (2019 EVAL media: LCU-on-WinPE is structurally closed). WinRE servicing below still runs.'
        } else {
        $patches = Get-PatchListForBootWim
        Write-Step ('boot.wim-targeted patches: {0}' -f $patches.Count)

        $bootIndexes = @($Script:OsProfile.BootWimIndexes)
        if (-not $bootIndexes -or $bootIndexes.Count -eq 0) {
            $bootIndexes = @(1, 2)
        }

        # Pull the role-based boot.wim sequence (prerequisite/carrier -> language -> final LCU -> cleanup/export)
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
            $idxSucceeded = $false
            $idxFailed = $false
            $isMounted = $true
            try {
                try {
                    $allBootPatches = @($bootSequence | Where-Object {
                        -not ($_.PSObject.Properties['IsCleanupMarker'] -and $_.IsCleanupMarker)
                    } | ForEach-Object { $_.Patches }) | Where-Object { $_ }
                    Test-PatchServicingReadinessOnMount -MountPath $mountDir -PatchesToApply $allBootPatches -ImageLabel $imgLabel | Out-Null

                    foreach ($sp in $bootSequence) {
                        if ($sp.PSObject.Properties['IsCleanupMarker'] -and $sp.IsCleanupMarker) {
                            Invoke-DismCleanup -MountPath $mountDir
                            continue
                        }
                        Invoke-PatchSubPhase -SubPhase $sp -MountPath $mountDir -ImageLabel $imgLabel | Out-Null
                        if ($sp.PSObject.Properties['RequiresRemount'] -and [bool]$sp.RequiresRemount) {
                            Write-Step ('  Sub-phase {0} requires servicing-stack activation: committing and remounting {1}.' -f $sp.Name,$imgLabel)
                            Invoke-WimDismountSafe -Path $mountDir -LogDir $Script:LogsDir
                            $isMounted=$false
                            Invoke-WimMountSafe -ImagePath $bootWim -Index $idx -Path $mountDir -LogDir $Script:LogsDir | Out-Null
                            $isMounted=$true
                        }
                    }
                    Assert-ExpandedBootLcuTarget -MountPath $mountDir -ImageLabel $imgLabel
                    $idxSucceeded = $true
                } catch {
                    $failureDecision=Get-BootWimFailurePolicyDecision -FailurePolicy $bootFailurePolicy -ErrorText ([string]$_.Exception.Message) -ImageLabel $imgLabel
                    if($failureDecision.Allowed){
                        $idxFailed=$true
                        $bootPolicyException=[pscustomobject][ordered]@{
                            SchemaVersion='P08-bootwim-policy-exception/1.0';Active=$true
                            CreatedAtUtc=([datetime]::UtcNow.ToString('o'));OsKey=$Script:OsVersion
                            ImageLabel=$imgLabel;BootWimLcuPolicy=$bootPolicy
                            BootWimFailurePolicy=$bootFailurePolicy;BootWimServicingStrategy=$bootServicingStrategy
                            ErrorCode=$failureDecision.ErrorCode;ErrorMessage=[string]$_.Exception.Message
                            PreserveSourceBootWim=$true;RequiresInstallValidation=$true
                            Reason=$failureDecision.Reason
                        }
                        Write-Caution ('{0}: {1} The mounted index will be discarded; the complete source boot.wim will be restored.' -f $imgLabel,$failureDecision.Reason)
                        Add-ErrorJsonlEntry -Phase 'P08' -Kind 'bootwim-policy-exception' -Properties @{exType=$_.Exception.GetType().FullName;msg=$_.Exception.Message;image=$imgLabel;policy=$bootFailurePolicy;strategy=$bootServicingStrategy;errorCode=$failureDecision.ErrorCode;requiresInstallValidation=$true}
                    } elseif ($bootPolicy -eq 'tolerate') {
                        $idxFailed = $true
                        Write-Caution ('{0}: boot.wim servicing failed under BootWimLcuPolicy=tolerate; DISCARDING this index and continuing. Error: {1}' -f $imgLabel, $_.Exception.Message)
                        Add-ErrorJsonlEntry -Phase 'P08' -Kind 'bootwim-tolerated-failure' -Properties @{exType=$_.Exception.GetType().FullName;msg=$_.Exception.Message;image=$imgLabel}
                    } else {
                        throw
                    }
                }
            } finally {
                if ($isMounted) {
                    if ($idxFailed -or -not $idxSucceeded) { Invoke-WimDismountSafe -Path $mountDir -Discard -LogDir $Script:LogsDir }
                    else { Invoke-WimDismountSafe -Path $mountDir -LogDir $Script:LogsDir }
                }
            }
            if($bootPolicyException){break}
        }
        if($bootPolicyException){
            if(-not $p08BootBackup -or -not (Test-Path -LiteralPath $p08BootBackup -PathType Leaf)){
                throw 'boot.wim policy exception was authorized, but the P08 source boot.wim backup is unavailable.'
            }
            $sourceBootWimSha256=(Get-FileHash -LiteralPath $p08BootBackup -Algorithm SHA256).Hash.ToLowerInvariant()
            Copy-Item -LiteralPath $p08BootBackup -Destination $bootWim -Force
            $restoredBootWimSha256=(Get-FileHash -LiteralPath $bootWim -Algorithm SHA256).Hash.ToLowerInvariant()
            if($sourceBootWimSha256 -ne $restoredBootWimSha256){
                throw ('boot.wim policy-exception restore hash mismatch: source={0}; restored={1}' -f $sourceBootWimSha256,$restoredBootWimSha256)
            }
            $bootPolicyException | Add-Member -NotePropertyName SourceBootWimSha256 -NotePropertyValue $sourceBootWimSha256 -Force
            $bootPolicyException | Add-Member -NotePropertyName RestoredBootWimSha256 -NotePropertyValue $restoredBootWimSha256 -Force
            $bootPolicyException | Add-Member -NotePropertyName RestoreVerified -NotePropertyValue $true -Force
            $bootPolicyException | Add-Member -NotePropertyName EvidencePath -NotePropertyValue $bootPolicyExceptionPath -Force
            Save-CanonicalJsonFile -InputObject $bootPolicyException -Path $bootPolicyExceptionPath -Depth 12
            $Script:BootWimPolicyException=$bootPolicyException
            Write-Caution ('Source boot.wim restored under explicit policy exception. Evidence: {0}. P14 Hyper-V Install validation is mandatory.' -f $bootPolicyExceptionPath)
        }
        }

        # winre.wim: service once, then copy the identical result to every
        # selected install.wim index. This prevents Standard/Datacenter or
        # Core/Desktop indexes from retaining the source-media WinRE.
        if ($Script:OsProfile.EnableWinREUpdate) {
            Write-SubSection 'winre.wim (service once; distribute to all install.wim indexes)'
            Set-DebugStep -Step 'winre-extract'
            $winReSequence = @($plan.WinReSequence)
            $winReHasWork = Test-WimSequenceHasWork -Sequence $winReSequence
            if (-not $winReHasWork) {
                Write-Step 'WinRE sequence has no patches; skipping WinRE servicing.'
            } else {
                $installWim = Join-Path $Script:ExtractedDir 'sources\install.wim'
                $targets = @(Resolve-InstallWimTargetIndexes -Inventory $Script:WimIndexInventory)
                if ($targets.Count -eq 0) { throw 'No install.wim indexes are selected for WinRE distribution.' }
                $primaryIdx = [int]$targets[0].ImageIndex
                $winReWork = Join-Path $Script:TempDir 'winre_work.wim'

                # Extract from one index without modifying it yet.
                Invoke-WimMountSafe -ImagePath $installWim -Index $primaryIdx -Path $Script:MountInstallDir -LogDir $Script:LogsDir | Out-Null
                try {
                    $winReInside = Join-Path $Script:MountInstallDir 'Windows\System32\Recovery\Winre.wim'
                    if (-not (Test-Path -LiteralPath $winReInside)) { throw ('Winre.wim not found in install.wim index {0}.' -f $primaryIdx) }
                    Copy-Item -LiteralPath $winReInside -Destination $winReWork -Force
                } finally {
                    Invoke-WimDismountSafe -Path $Script:MountInstallDir -Discard -LogDir $Script:LogsDir
                }

                Invoke-WimMountSafe -ImagePath $winReWork -Index 1 -Path $Script:MountWinReDir -LogDir $Script:LogsDir | Out-Null
                $winReSucceeded = $false
                try {
                    $allWinRePatches = @($winReSequence | Where-Object {
                        -not ($_.PSObject.Properties['IsCleanupMarker'] -and $_.IsCleanupMarker)
                    } | ForEach-Object { $_.Patches }) | Where-Object { $_ }
                    Test-PatchServicingReadinessOnMount -MountPath $Script:MountWinReDir -PatchesToApply $allWinRePatches -ImageLabel 'winre.wim' | Out-Null
                    foreach ($sp in $winReSequence) {
                        if ($sp.PSObject.Properties['IsCleanupMarker'] -and $sp.IsCleanupMarker) {
                            Invoke-DismCleanup -MountPath $Script:MountWinReDir
                            continue
                        }
                        Invoke-PatchSubPhase -SubPhase $sp -MountPath $Script:MountWinReDir -ImageLabel 'winre.wim' | Out-Null
                    }
                    $winReSucceeded = $true
                } finally {
                    Invoke-WimDismountSafe -Path $Script:MountWinReDir -Discard:(-not $winReSucceeded) -LogDir $Script:LogsDir
                }
                Export-WinReRecoveryCompressed -WinRePath $winReWork
                Copy-ServicedWinReToInstallIndexes -InstallWim $installWim -ServicedWinRe $winReWork -Indexes $targets
                Write-Ok ('Serviced WinRE distributed to {0} install.wim index(es).' -f $targets.Count)
            }
        }

        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P08.ok') -Force | Out-Null
        $p08Succeeded = $true
    } finally {
        if (-not $p08Succeeded -and $p08BootBackup -and (Test-Path -LiteralPath $p08BootBackup)) {
            Write-Caution 'P08 failed; restoring boot.wim and install.wim from transaction backups.'
            try {
                Copy-Item -LiteralPath $p08BootBackup -Destination (Join-Path $Script:ExtractedDir 'sources\boot.wim') -Force
                if ($p08InstallBackup -and (Test-Path -LiteralPath $p08InstallBackup)) {
                    Copy-Item -LiteralPath $p08InstallBackup -Destination (Join-Path $Script:ExtractedDir 'sources\install.wim') -Force
                }
                Write-DismRollbackEvidence -Phase 'P08' -Result 'Restored' -Context 'boot.wim/install.wim transaction backups'
            } catch {
                Write-DismRollbackEvidence -Phase 'P08' -Result 'Failed' -Context 'boot.wim/install.wim transaction backups' -Error $_.Exception.Message
                throw
            }
            Remove-Item -LiteralPath (Join-Path $Script:MarkersDir 'P08.ok') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $Script:MarkersDir 'P08S.ok') -Force -ErrorAction SilentlyContinue
        }
        Stop-DebugTrace
    }
}

# ============================================================
# ============================================================
# Phase P08S: Sync Setup binaries from serviced boot.wim to media
# ============================================================
# Root cause record [measured 2026-07-11]: P08 services boot.wim
# (the Setup engine) but the media \sources setup binaries stayed at
# their shipped versions. Microsoft's media-dynamic-update guidance
# is explicit: setup.exe (and setuphost.exe on 10.0.26100+) from the
# serviced boot.wim must match \sources\setup.exe /
# \sources\setuphost.exe -- "If these binaries aren't identical,
# Windows Setup will fail during installation." Measured on the
# Hyper-V rig: Server 2016/2022/2025 output ISOs failed before
# edition selection ("a media driver ... is missing"; WinPE could dir
# the 8.4 GB install.wim and diskpart saw the disk, eliminating the
# media-read and storage-driver hypotheses); the failing VM showed
# X:\sources\setup.exe 333,304 B (2026-07-08) vs D:\sources\
# setup.exe 333,184 B (2026-01-15). Server 2019 escaped only because
# its boot.wim is pinned at 17763.3650 (0x80070032 closure).
# This phase is the EXPLICIT sync [user requirement 2026-07-11]:
# before/after size + timestamp + SHA-256 of every file are recorded
# to the console, to logs\P08S_setup_binaries_sync.csv and to
# logs\setup_binaries_sync.json -- never an implicit side effect.
# This sync remains mandatory even when a Setup Dynamic Update is
# available: the serviced boot.wim index 2 is the authoritative source
# for matching setup.exe (and setuphost.exe on build 26100+).

function Get-SetupBinarySyncPlan {
    <#
    .SYNOPSIS
        Pure: which Setup binaries must be synced for a given boot.wim
        idx2 build number. setup.exe always; setuphost.exe on
        10.0.26100+ (Windows Server 2025 / 24H2 era), per the MS
        media-dynamic-update procedure.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [object]$BuildNumber
    )
    $n = $null
    if ($null -ne $BuildNumber) {
        try { $n = [int]$BuildNumber } catch { $n = $null }
    }
    if ($null -eq $n) {
        return [pscustomobject]@{
            Files  = @('setup.exe')
            Reason = 'boot.wim idx2 build unknown; syncing setup.exe only (setuphost.exe is a 26100+ requirement)'
        }
    }
    if ($n -ge 26100) {
        return [pscustomobject]@{
            Files  = @('setup.exe', 'setuphost.exe')
            Reason = ('build {0} >= 26100: setup.exe + setuphost.exe (MS: required starting with 24H2/Server 2025)' -f $n)
        }
    }
    return [pscustomobject]@{
        Files  = @('setup.exe')
        Reason = ('build {0} < 26100: setup.exe only' -f $n)
    }
}

function Get-SetupBinaryFileEvidence {
    <#
    .SYNOPSIS
        Measured identity of one file: presence, size, last-write time
        (UTC, ISO 8601) and SHA-256. The unit of evidence this phase
        records before and after every copy.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path = $Path; Present = $false; SizeBytes = $null; LastWriteTimeUtc = $null; Sha256 = $null }
    }
    $fi = Get-Item -LiteralPath $Path
    $sha = $null
    try { $sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() } catch { $null = $_ }
    return [pscustomobject]@{
        Path             = $Path
        Present          = $true
        SizeBytes        = [int64]$fi.Length
        LastWriteTimeUtc = $fi.LastWriteTimeUtc.ToString('o')
        Sha256           = $sha
    }
}

function New-SetupBinarySyncRecord {
    <#
    .SYNOPSIS
        Pure: one per-file sync record -- source (boot.wim idx2 side),
        media before, media after, the action taken and why.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$FileName,
        [Parameter(Mandatory)] [ValidateSet('copied', 'already-identical', 'source-missing')] [string]$Action,
        [Parameter(Mandatory)] [pscustomobject]$Source,
        [Parameter(Mandatory)] [pscustomobject]$MediaBefore,
        [AllowNull()] [pscustomobject]$MediaAfter = $null,
        [string]$Notes = ''
    )
    return [pscustomobject]@{
        FileName    = $FileName
        Action      = $Action
        Source      = $Source
        MediaBefore = $MediaBefore
        MediaAfter  = $MediaAfter
        Notes       = $Notes
    }
}

function Invoke-BuildPhase08S_SyncSetupBinaries { # psa-disable-line PSA6003 -- the phase syncs the SET of Setup binaries (setup.exe + setuphost.exe); the plural is the accurate contract (exemption style mirrors Resolve-SetupDu)
    <#
    .SYNOPSIS
        P08S: copy the serviced boot.wim idx2 Setup binaries over the
        media \sources copies, recording before/after evidence
        (size, timestamp, SHA-256) for every file -- an explicit,
        verifiable sync, not an implicit side effect.
    .DESCRIPTION
        Mounts boot.wim idx2 read-only, plans the file set from the
        image build (Get-SetupBinarySyncPlan), then per file: record
        media BEFORE -> compare SHA-256 -> copy only on difference ->
        record media AFTER -> verify media SHA-256 now equals the
        boot.wim side (hard failure if not). Artifacts:
        logs\P08S_setup_binaries_sync.csv and
        logs\setup_binaries_sync.json.
    #>
    Start-DebugTrace -Context 'Invoke-BuildPhase08S_SyncSetupBinaries' -PhaseId 'P08S'
    try {
        $bootWim = Join-Path $Script:ExtractedDir 'sources\boot.wim'
        if (-not (Test-Path -LiteralPath $bootWim)) {
            if ($Script:SyntheticTestMode) {
                Write-Skip 'boot.wim absent in -SyntheticTestMode; skipping P08S.'
                return
            }
            throw ('boot.wim missing: {0}' -f $bootWim)
        }
        if (-not $Script:Execute -and -not $Script:SyntheticTestMode) {
            Write-Caution 'Running in Sandbox mode (no -Execute); skipping Setup-binary sync.'
            return
        }

        Set-DebugStep -Step 'plan'
        $buildNumber = $null
        try {
            $img = Invoke-DismCmdlet -CommandName 'Get-WindowsImage' -Parameters @{ ImagePath = $bootWim; Index = 2 }
            if ($img -and $img.Version) { $buildNumber = ([version][string]$img.Version).Build }
        } catch {
            Write-Caution ('boot.wim idx2 version query failed: {0}' -f $_.Exception.Message)
        }
        $plan = Get-SetupBinarySyncPlan -BuildNumber $buildNumber
        Write-Step ('Sync plan: {0} -- {1}' -f (@($plan.Files) -join ', '), $plan.Reason)

        $mountDir = Join-Path $Script:WorkRoot 'work\p08s_mount'
        if (Test-Path -LiteralPath $mountDir) {
            Remove-Item -LiteralPath $mountDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $mountDir -Force | Out-Null

        $records = [System.Collections.Generic.List[object]]::new()
        $mounted = $false
        Set-DebugStep -Step 'mount-boot-idx2'
        try {
            $null = Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters @{
                ImagePath = $bootWim; Index = 2; Path = $mountDir
                ReadOnly = $true; ErrorAction = 'Stop'
                LogPath = (Join-Path $Script:LogsDir 'p08s_mount_boot_idx2.log')
            }
            $mounted = $true

            foreach ($fileName in @($plan.Files)) {
                Set-DebugStep -Step ('sync-' + $fileName)
                $srcPath   = Join-Path $mountDir ('sources\' + $fileName)
                $mediaPath = Join-Path $Script:ExtractedDir ('sources\' + $fileName)
                $srcEv   = Get-SetupBinaryFileEvidence -Path $srcPath
                $beforeEv = Get-SetupBinaryFileEvidence -Path $mediaPath
                Write-Step ('{0}: boot.wim idx2 side : Present={1} Size={2} LastWriteUtc={3} Sha256={4}' -f $fileName, $srcEv.Present, $srcEv.SizeBytes, $srcEv.LastWriteTimeUtc, $srcEv.Sha256)
                Write-Step ('{0}: media BEFORE       : Present={1} Size={2} LastWriteUtc={3} Sha256={4}' -f $fileName, $beforeEv.Present, $beforeEv.SizeBytes, $beforeEv.LastWriteTimeUtc, $beforeEv.Sha256)

                if (-not $srcEv.Present) {
                    if ($fileName -eq 'setup.exe') {
                        throw ('boot.wim idx2 carries no sources\setup.exe; the serviced Setup image is not usable as a sync source.')
                    }
                    Write-Caution ('{0}: absent in boot.wim idx2; recording and continuing (nothing to sync).' -f $fileName)
                    $records.Add((New-SetupBinarySyncRecord -FileName $fileName -Action 'source-missing' `
                        -Source $srcEv -MediaBefore $beforeEv -Notes 'planned by build gate but not present in the image')) | Out-Null
                    continue
                }

                # Stash the boot.wim-side binary (MS media-dynamic-update
                # order: after a Setup DU overlay, THESE copies win; P09
                # reapplies the stash after its overlay step).
                $stashDir = Join-Path $Script:WorkRoot 'work\p08s_setup_binaries'
                if (-not (Test-Path -LiteralPath $stashDir)) {
                    New-Item -ItemType Directory -Path $stashDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $srcPath -Destination (Join-Path $stashDir $fileName) -Force

                if ($beforeEv.Present -and $beforeEv.Sha256 -and $beforeEv.Sha256 -eq $srcEv.Sha256) {
                    Write-Ok ('{0}: media already identical to boot.wim idx2 (SHA-256 match); no copy.' -f $fileName)
                    $records.Add((New-SetupBinarySyncRecord -FileName $fileName -Action 'already-identical' `
                        -Source $srcEv -MediaBefore $beforeEv -MediaAfter $beforeEv -Notes 'SHA-256 equal before sync')) | Out-Null
                    continue
                }

                if ($beforeEv.Present) {
                    $mediaItem = Get-Item -LiteralPath $mediaPath
                    if ($mediaItem.IsReadOnly) {
                        # ISO-extracted files commonly carry the ReadOnly
                        # attribute; clear it or Copy-Item -Force fails.
                        $mediaItem.IsReadOnly = $false
                    }
                }
                Copy-Item -LiteralPath $srcPath -Destination $mediaPath -Force
                $afterEv = Get-SetupBinaryFileEvidence -Path $mediaPath
                Write-Step ('{0}: media AFTER        : Present={1} Size={2} LastWriteUtc={3} Sha256={4}' -f $fileName, $afterEv.Present, $afterEv.SizeBytes, $afterEv.LastWriteTimeUtc, $afterEv.Sha256)
                if (-not $afterEv.Present -or $afterEv.Sha256 -ne $srcEv.Sha256) {
                    throw ('{0}: post-copy verification FAILED (media SHA-256 {1} != boot.wim side {2}).' -f $fileName, $afterEv.Sha256, $srcEv.Sha256)
                }
                Write-Ok ('{0}: synced and verified (media SHA-256 now equals boot.wim idx2 side).' -f $fileName)
                $records.Add((New-SetupBinarySyncRecord -FileName $fileName -Action 'copied' `
                    -Source $srcEv -MediaBefore $beforeEv -MediaAfter $afterEv -Notes 'copied; post-copy SHA-256 verified')) | Out-Null
            }
        } finally {
            if ($mounted) {
                try {
                    $null = Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path = $mountDir; Discard = $true; ErrorAction = 'Stop' }
                } catch {
                    Write-Caution ('P08S: boot.wim dismount failed: {0}' -f $_.Exception.Message)
                }
            }
        }

        Set-DebugStep -Step 'persist-evidence'
        $csvRows = @($records | ForEach-Object {
            [pscustomobject]@{
                File                    = $_.FileName
                Action                  = $_.Action
                SourceSizeBytes         = $_.Source.SizeBytes
                SourceLastWriteUtc      = $_.Source.LastWriteTimeUtc
                SourceSha256            = $_.Source.Sha256
                MediaBeforeSizeBytes    = $_.MediaBefore.SizeBytes
                MediaBeforeLastWriteUtc = $_.MediaBefore.LastWriteTimeUtc
                MediaBeforeSha256       = $_.MediaBefore.Sha256
                MediaAfterSizeBytes     = if ($_.MediaAfter) { $_.MediaAfter.SizeBytes } else { $null }
                MediaAfterLastWriteUtc  = if ($_.MediaAfter) { $_.MediaAfter.LastWriteTimeUtc } else { $null }
                MediaAfterSha256        = if ($_.MediaAfter) { $_.MediaAfter.Sha256 } else { $null }
                Notes                   = $_.Notes
            }
        })
        $csvPath = Join-Path $Script:LogsDir 'P08S_setup_binaries_sync.csv'
        $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        $jsonPath = Join-Path $Script:LogsDir 'setup_binaries_sync.json'
        [pscustomobject]@{
            Schema         = 'setup-binaries-sync/1'
            Timestamp      = (Get-Date).ToString('o')
            OsKey          = $Script:OsVersion
            BootWimPath    = $bootWim
            BootWimIdx2Build = $buildNumber
            Plan           = $plan
            Records        = $records.ToArray()
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        Write-Ok ('Setup-binary sync evidence written: {0} / {1}' -f $csvPath, $jsonPath)
        New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P08S.ok') -Force | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

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
                if (($p.PSObject.Properties['IsMetadataOnly'] -and $p.IsMetadataOnly) -or [string]::IsNullOrWhiteSpace([string]$p.LocalPath)) {
                    throw ('Setup DU {0} is required by the v4 baseline but its distributable asset is unresolved. Run DiscoverBaseline/ResolveAssets/FreezeBaseline, or populate FileName, DownloadUrl, and SHA-256 before Build.' -f $p.KbId)
                }
                if (-not (Test-Path -LiteralPath $p.LocalPath)) {
                    throw ('Setup DU asset was resolved but is not present locally: {0} ({1})' -f $p.KbId, $p.LocalPath)
                }
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
                    $setupDestRoot = Join-Path $Script:ExtractedDir 'sources'
                    $sourceManifest = @(Get-SetupDuFileManifest -Root $tmpExtract -DestinationRoot $setupDestRoot)
                    # -Path (not -LiteralPath) is required when the
                    # source contains a wildcard. -LiteralPath would
                    # look for a file literally named '*' and fail
                    # with 'Cannot find path'.
                    Copy-Item -Path (Join-Path $tmpExtract '*') `
                        -Destination $setupDestRoot -Recurse -Force
                    $overlayRecords = [System.Collections.Generic.List[object]]::new()
                    foreach ($mr in $sourceManifest) {
                        $destPresent = Test-Path -LiteralPath $mr.DestinationPath
                        $destHash = if ($destPresent) { (Get-FileHash -LiteralPath $mr.DestinationPath -Algorithm SHA256).Hash.ToLower() } else { $null }
                        $isSetupBinary = ([System.IO.Path]::GetFileName($mr.RelativePath) -in @('setup.exe','setuphost.exe'))
                        $overlayRecords.Add([pscustomobject]@{
                            KbId=$p.KbId; RelativePath=$mr.RelativePath; DestinationPath=$mr.DestinationPath
                            SourceSizeBytes=$mr.SizeBytes; SourceSha256=$mr.Sha256; SourceFileVersion=$mr.FileVersion
                            DestinationPresent=$destPresent; DestinationSha256AfterOverlay=$destHash
                            MatchAfterOverlay=($destPresent -and $destHash -eq $mr.Sha256)
                            OverriddenByBootWim=$isSetupBinary
                        }) | Out-Null
                    }
                    $setupEvidencePath = Join-Path $Script:LogsDir 'setupdu_overlay_manifest.json'
                    [pscustomobject]@{ Schema='setupdu-overlay/1'; Timestamp=(Get-Date).ToString('o'); OsKey=$Script:OsVersion; KbId=$p.KbId; Records=$overlayRecords.ToArray() } |
                        ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $setupEvidencePath -Encoding UTF8
                    Write-Ok ('Overlay applied: {0}; evidence: {1}' -f $p.KbId, $setupEvidencePath)
                } else {
                    throw ('expand.exe failed for required Setup DU {0} with exit code {1}.' -f $p.KbId,$LASTEXITCODE)
                }
            }
        } else {
            Write-Skip 'No Dynamic Update Setup patches to overlay.'
        }

        # Post-overlay reapply of the boot.wim-side Setup binaries (MS
        # media-dynamic-update order: the Setup DU overlay updates
        # sources\, THEN setup.exe/setuphost.exe saved from the
        # serviced boot.wim are copied over -- the boot.wim copies must
        # win or Setup fails on the binary mismatch). Dormant while no
        # SetupDU resolves; wired so a future SetupDU cannot silently
        # undo the P08S sync.
        if ($setupDuPatches.Count -gt 0 -and -not $Script:SyntheticTestMode) {
            Set-DebugStep -Step 'reapply-setup-binaries'
            $stashDir = Join-Path $Script:WorkRoot 'work\p08s_setup_binaries'
            if (Test-Path -LiteralPath $stashDir) {
                foreach ($stashed in @(Get-ChildItem -LiteralPath $stashDir -File)) {
                    $dest = Join-Path $Script:ExtractedDir ('sources\' + $stashed.Name)
                    $beforeEv = Get-SetupBinaryFileEvidence -Path $dest
                    if (Test-Path -LiteralPath $dest) {
                        $destItem = Get-Item -LiteralPath $dest
                        if ($destItem.IsReadOnly) { $destItem.IsReadOnly = $false }
                    }
                    Copy-Item -LiteralPath $stashed.FullName -Destination $dest -Force
                    $afterEv = Get-SetupBinaryFileEvidence -Path $dest
                    Write-Step ('{0}: reapplied boot.wim copy after Setup DU overlay (before sha={1} -> after sha={2}).' -f $stashed.Name, $beforeEv.Sha256, $afterEv.Sha256)
                }
            } else {
                Write-Caution 'Setup DU overlay ran but no P08S stash exists; media setup binaries may not match the serviced boot.wim (run the full pipeline including P08S).'
            }
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
# This phase runs BY DEFAULT (readiness-driven; opt-OUT via
# -SkipPca2023BootManager). The PCA2011 signing CA expired 2026-06,
# so leaving the shipped PCA2011-signed boot manager is now the
# exception (older firmware without the 2023 certs), not the norm.
# Server 2025 remains audit/gate-only by default as a PROJECT safety policy
# until this project's Server 2025 conversion E2E is completed. Microsoft's
# current Make2023BootableMedia.ps1 is generic Windows-media tooling and does
# not express a Server 2025 exclusion. Conversion therefore still requires
# -ForcePca2023OnServer2025 for now; this is not an upstream support claim.
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
          - -SkipPca2023BootManager set (operator opt-out)
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
        Set-DebugStep -Step 'gate-SkipPca2023BootManager'

        if ($Script:SkipPca2023BootManager) {
            Write-Step 'Skipped: -SkipPca2023BootManager specified (operator opt-out; boot manager left as shipped).'
            Set-Content -LiteralPath (Join-Path $Script:MarkersDir 'P10.skipped') -Value 'skipped-by-policy: operator opt-out (-SkipPca2023BootManager)' -Encoding UTF8
            return
        }

        Set-DebugStep -Step 'gate-Server2025'
        $osKey = if ($Script:OsProfile) { $Script:OsProfile.OsKey } else { $null }
        Write-Step ('OsKey: {0}' -f $osKey)
        $pcaPolicyForGate = Get-Pca2023CompliancePolicy
        if ($osKey -eq 'Server2025' -and -not $Script:ForcePca2023OnServer2025) {
            Write-Step ('Skipped: OsKey={0}; Microsoft conversion workflow is not documented for Server 2025 (policy={1}).' -f $osKey,$pcaPolicyForGate)
            Write-Step '         Use -ForcePca2023OnServer2025 only for an explicitly approved experimental conversion.'
            Set-Content -LiteralPath (Join-Path $Script:MarkersDir 'P10.skipped') -Value ('skipped-by-policy: Server2025 documented-conversion boundary; policy=' + $pcaPolicyForGate) -Encoding UTF8
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
            Set-Content -LiteralPath (Join-Path $Script:MarkersDir 'P10.skipped') -Value 'prereq-critical: media below the 2024-4B floor; no conversion source' -Encoding UTF8
            return
        }
        if ($pre.Health -eq 'Healthy') {
            Write-Step 'Skipped: ISO is ALREADY PCA2023-signed (Health=Healthy). No conversion needed.'
            Set-Content -LiteralPath (Join-Path $Script:MarkersDir 'P10.skipped') -Value 'already-healthy: bootx64.efi is already PCA2023-signed' -Encoding UTF8
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

        $convSrc = if ($convResult.PSObject.Properties['SourceWim'] -and $convResult.SourceWim) { $convResult.SourceWim } else { '(external script)' }
        Write-Step ('PCA2023 conversion succeeded. Source: {0}; files updated: {1}' -f $convSrc, $convResult.FilesUpdated.Count)
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
        $outputCheck = Test-OutputIsoPca2023Readiness -ExtractedMediaPath $extractedPath -ConversionSkipReason (Get-P10SkipReason)
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

function Get-DotNetRollupEvidence {
    <#
    .SYNOPSIS
        Pure census: the .NET cumulative package inside a serviced
        image, from its installed-package name list.
    .DESCRIPTION
        E2E-measured naming (2026-07-08): the .NET monthly cumulative
        surfaces as 'Package_for_DotNetRollup~...~~10.0.4802.1'
        (Server 2019/2022) or with a framework suffix
        'Package_for_DotNetRollup_481~...~~10.0.9335.3' (Server 2025,
        .NET 4.8.1). NO KB id appears in the name (neither the
        Catalog's offering KB nor the child MSU KB), so presence +
        measured version IS the media-level verification for the
        DotNet Kind. Highest version wins when several match.
    .OUTPUTS
        pscustomobject: Present / PackageName / Version (raw string)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [string[]]$PackageNames
    )
    $best = $null
    $bestVer = $null
    foreach ($pn in @($PackageNames)) {
        if ([string]::IsNullOrWhiteSpace($pn)) { continue }
        $m = [regex]::Match($pn, '^Package_for_DotNetRollup(_\d+)?~31bf3856ad364e35~amd64~~([0-9.]+)$')
        if (-not $m.Success) { continue }
        $vRaw = $m.Groups[2].Value
        $v = $null
        try { $v = [version]$vRaw } catch { $null = $_ }
        if ($null -eq $best -or ($v -and $bestVer -and $v -gt $bestVer) -or ($v -and -not $bestVer)) {
            $best = $pn
            $bestVer = $v
        }
    }
    return [pscustomobject]@{
        Present     = [bool]$best
        PackageName = $best
        Version     = $(if ($best) { ($best -split '~~')[-1] } else { $null })
    }
}

function Test-LcuTargetApplied {
    <#
    .SYNOPSIS
        Pure per-OS comparator: did the serviced image reach the
        baseline LCU / TargetBuildAfterUpdate? Offline-testable (T31).
    .DESCRIPTION
        Judgment is per-OS [user-adjudicated 2026-07-07], fed by the
        r11.58 evidence object instead of raw package names (the
        KB-name-only predecessor was structurally blind on the
        RollupFix-named OSes and would have hard-failed 2019/2022/2025
        media whose LCU HAD applied):
          - Server2016: the LCU package name carries the KB id --
            applied when Evidence.LcuKbId equals the expected KB, or
            the measured build reaches the expected build.
          - Server2019/2022/2025: no KB id exists in package names;
            applied when the measured build reaches the expected
            TargetBuildAfterUpdate (two-part compare). Without an
            expected build the verdict is INDETERMINATE (Warn), never
            a silent Pass.
        Mismatch stays a HARD verification failure [DECIDED
        2026-07-02, user].
    .OUTPUTS
        pscustomobject: Applied / Check / Expected / Actual / Status / Notes
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$OsKey,
        [Parameter(Mandatory)] [string]$ExpectedKbId,
        [AllowEmptyString()] [string]$ExpectedBuild = '',
        [Parameter(Mandatory)] [object]$Evidence
    )
    $expB = ConvertTo-TwoPartBuild -BuildString $ExpectedBuild
    # Normalise: live [version], JSON {Major,Minor} object, REPL hashtable,
    # or string all become a two-part [version].
    $measured = ConvertFrom-InspectionBuildValue -Value $Evidence.Build
    $applied = $false
    $indeterminate = $false
    if ($OsKey -eq 'Server2016') {
        # Membership match: SSU and LCU can share the top build, so
        # the evidence carries a KB SET (KbIdsAtBuild), not one id.
        $evKbs = @($Evidence.KbIdsAtBuild)
        $kbHit = (($Evidence.LcuKbId -and ($Evidence.LcuKbId -eq $ExpectedKbId)) -or ($evKbs -contains $ExpectedKbId))
        $buildHit = ($expB -and $measured -and ($measured -ge $expB))
        $applied = ($kbHit -or $buildHit)
    } else {
        if ($expB) {
            $applied = [bool]($measured -and ($measured -ge $expB))
        } else {
            $indeterminate = $true
        }
    }
    $measStr = if ($measured) { [string]$measured } else { '(none)' }
    $evKbSet = @($Evidence.KbIdsAtBuild)
    if ($OsKey -eq 'Server2016' -and ($evKbSet -contains $ExpectedKbId)) {
        $otherKb = @($evKbSet | Where-Object { $_ -ne $ExpectedKbId }) -join ','
        $evKbStr = if ($otherKb) { ('{0} (expected LCU; co-versioned packages: {1})' -f $ExpectedKbId, $otherKb) } else { $ExpectedKbId }
    } else {
        $joinedKb = $evKbSet -join ','
        $evKbStr = if ($joinedKb) { $joinedKb } elseif ($Evidence.LcuKbId) { [string]$Evidence.LcuKbId } else { '(none)' }
    }
    $notes = ('OsKey={0}; measured build={1}; TargetBuildAfterUpdate={2}; evidence KB={3}; registry/kernel are authoritative for OS build, servicing-stack package revisions are separate evidence' -f `
        $OsKey, $measStr, $(if ($ExpectedBuild) { $ExpectedBuild } else { '(none)' }), $evKbStr)
    if ($indeterminate) {
        return [pscustomobject]@{
            Applied  = $false
            Check    = 'LcuTargetApplied'
            Expected = ('LCU {0} at TargetBuildAfterUpdate' -f $ExpectedKbId)
            Actual   = 'Indeterminate'
            Status   = 'Warn'
            Notes    = ($notes + '; no TargetBuildAfterUpdate recorded and this OS has no KB id in package names')
        }
    }
    return [pscustomobject]@{
        Applied  = $applied
        Check    = 'LcuTargetApplied'
        Expected = ('LCU {0} applied (build >= {1})' -f $ExpectedKbId, $(if ($ExpectedBuild) { $ExpectedBuild } else { 'n/a' }))
        Actual   = $(if ($applied) { 'Applied' } else { 'NotApplied' })
        Status   = $(if ($applied) { 'Pass' } else { 'Fail' })
        Notes    = $notes
    }
}


function Get-WinRePostServicingEvidence {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$InstallWim,
        [Parameter(Mandatory)][int[]]$Indexes,
        [Parameter(Mandatory)][string]$OsKey,
        [AllowEmptyString()][string]$ExpectedBuild,
        [AllowEmptyString()][string]$ExpectedSafeOsKb,
        [AllowEmptyString()][string]$ExpectedSafeOsFileName,
        [string[]]$ExpectedServicingStackKbs=@(),
        [Parameter(Mandatory)][string]$WorkRoot,
        [Parameter(Mandatory)][string]$LogDir
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $extractMount = Join-Path $WorkRoot 'work\verify_winre_parent'
    $winreMount   = Join-Path $WorkRoot 'work\verify_winre_mount'
    $tempWinre    = Join-Path $WorkRoot 'work\verify_winre.wim'
    foreach ($idx in $Indexes) {
        $parentMounted = $false
        try {
            if (Test-Path -LiteralPath $extractMount) { Remove-Item -LiteralPath $extractMount -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $extractMount -Force | Out-Null
            Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters @{ ImagePath=$InstallWim; Index=$idx; Path=$extractMount; ReadOnly=$true; ErrorAction='Stop'; LogPath=(Join-Path $LogDir ('verify_winre_parent_idx{0}.log' -f $idx)) } | Out-Null
            $parentMounted=$true
            $src = Join-Path $extractMount 'Windows\System32\Recovery\Winre.wim'
            if (-not (Test-Path -LiteralPath $src)) { throw ('WinRE missing in install.wim index {0}' -f $idx) }
            Copy-Item -LiteralPath $src -Destination $tempWinre -Force
            $hash=(Get-FileHash -LiteralPath $tempWinre -Algorithm SHA256).Hash.ToLower()
            $records.Add([pscustomobject]@{ Index=$idx; Present=$true; Sha256=$hash; ErrorMessage=$null }) | Out-Null
        } catch {
            $records.Add([pscustomobject]@{ Index=$idx; Present=$false; Sha256=$null; ErrorMessage=$_.Exception.Message }) | Out-Null
        } finally {
            if ($parentMounted) { try { Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path=$extractMount; Discard=$true; ErrorAction='Stop' } | Out-Null } catch { $null=$_ } }
        }
    }
    $validHashes=@($records | Where-Object { $_.Present -and $_.Sha256 } | ForEach-Object { $_.Sha256 } | Sort-Object -Unique)
    $deep=$null
    if ($validHashes.Count -eq 1 -and (Test-Path -LiteralPath $tempWinre)) {
        $mounted=$false
        try {
            if (Test-Path -LiteralPath $winreMount) { Remove-Item -LiteralPath $winreMount -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $winreMount -Force | Out-Null
            Invoke-DismCmdlet -CommandName 'Mount-WindowsImage' -Parameters @{ ImagePath=$tempWinre; Index=1; Path=$winreMount; ReadOnly=$true; ErrorAction='Stop'; LogPath=(Join-Path $LogDir 'verify_winre_deep_mount.log') } | Out-Null
            $mounted=$true
            $src=Get-WimBuildSources -MountPath $winreMount
            $packages=@(Invoke-DismCmdlet -CommandName 'Get-WindowsPackage' -Parameters @{ Path=$winreMount; ErrorAction='Stop' })
            $pending=@($packages | Where-Object { ([string]$_.PackageState) -match 'Pending' } | ForEach-Object { [string]$_.PackageName })
            $kbMatches=@($src.PackageNames | Where-Object { $ExpectedSafeOsKb -and ([string]$_ -match [regex]::Escape($ExpectedSafeOsKb)) })
            $stackKbMatches=@()
            foreach($stackKb in @($ExpectedServicingStackKbs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)) {
                $stackKbMatches += @($src.PackageNames | Where-Object { ([string]$_) -match [regex]::Escape([string]$stackKb) } | ForEach-Object {
                    [pscustomobject]@{KbId=[string]$stackKb;PackageName=[string]$_}
                })
            }
            $safePackages=@($packages | Where-Object { ([string]$_.PackageName) -match '^Package_for_SafeOSDU~' } | ForEach-Object { [pscustomobject]@{PackageName=[string]$_.PackageName;PackageState=[string]$_.PackageState;Version=(([string]$_.PackageName -split '~~')[-1])} })
            $ssuPackages=@($packages | Where-Object { ([string]$_.PackageName) -match '^(Package_for_)?ServicingStack|^Package_for_ServicingStack_' } | ForEach-Object { [pscustomobject]@{PackageName=[string]$_.PackageName;PackageState=[string]$_.PackageState;Version=(([string]$_.PackageName -split '~~')[-1])} })
            $rollupPackages=@($packages | Where-Object { ([string]$_.PackageName) -match 'RollupFix' } | ForEach-Object { [pscustomobject]@{PackageName=[string]$_.PackageName;PackageState=[string]$_.PackageState;Version=(([string]$_.PackageName -split '~~')[-1])} })
            $dismOutcomes=@()
            $outcomePath=Join-Path $LogDir 'dism_outcomes.jsonl'
            if(Test-Path -LiteralPath $outcomePath){
                foreach($line in @(Get-Content -LiteralPath $outcomePath -ErrorAction SilentlyContinue)){
                    if([string]::IsNullOrWhiteSpace($line)){continue}
                    try{$rec=$line|ConvertFrom-Json}catch{continue}
                    $context=[string]$rec.Context;$recKb=if($rec.PSObject.Properties['KbId']){[string]$rec.KbId}else{''}
                    if(($ExpectedSafeOsFileName -and $context -eq $ExpectedSafeOsFileName) -or ($ExpectedSafeOsKb -and $recKb -eq $ExpectedSafeOsKb)){$dismOutcomes+=,$rec}
                }
            }
            $ev = switch ($OsKey) {
                'Server2016' { Resolve-LcuEvidence_Server2016 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild }
                'Server2019' { Resolve-LcuEvidence_Server2019 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild }
                'Server2022' { Resolve-LcuEvidence_Server2022 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild }
                'Server2025' { Resolve-LcuEvidence_Server2025 -PackageNames $src.PackageNames -RegistryBuild $src.RegistryBuild -KernelBuild $src.KernelBuild }
            }
            $deep=[pscustomobject]@{
                Build=$ev.Build; RegistryBuild=$src.RegistryBuild; KernelBuild=$src.KernelBuild; ExpectedBuild=$ExpectedBuild
                SafeOsKb=$ExpectedSafeOsKb; ExpectedSafeOsFileName=$ExpectedSafeOsFileName; SafeOsKbPackageMatches=$kbMatches
                ExpectedServicingStackKbs=@($ExpectedServicingStackKbs); ServicingStackKbPackageMatches=@($stackKbMatches)
                SafeOsPackages=$safePackages; ServicingStackPackages=$ssuPackages; RollupFixPackages=$rollupPackages
                SafeOsDismOutcomes=$dismOutcomes; PendingPackages=$pending; PackageNames=@($src.PackageNames)
            }
        } finally {
            if ($mounted) { try { Invoke-DismCmdlet -CommandName 'Dismount-WindowsImage' -Parameters @{ Path=$winreMount; Discard=$true; ErrorAction='Stop' } | Out-Null } catch { $null=$_ } }
        }
    }
    return [pscustomobject]@{ Indexes=$records.ToArray(); UniqueHashes=$validHashes; AllHashesEqual=($records.Count -eq $Indexes.Count -and @($records.ToArray() | Where-Object { -not $_.Present }).Count -eq 0 -and $validHashes.Count -eq 1); DeepInspection=$deep }
}

function Get-WinReServicingVerificationDecision {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$DeepInspection,
        [AllowEmptyString()][string]$ExpectedOsBuild=''
    )
    $safe=@($DeepInspection.SafeOsPackages | Where-Object { ([string]$_.PackageState) -match '^(Installed|Superseded)$' })
    $stackPackages=@($DeepInspection.ServicingStackPackages | Where-Object { ([string]$_.PackageState) -match '^(Installed|Superseded)$' })
    $stackKbMatches=@($DeepInspection.ServicingStackKbPackageMatches)
    $pending=@($DeepInspection.PendingPackages)
    $outcomes=@($DeepInspection.SafeOsDismOutcomes)
    $outcomeSuccess=@($outcomes | Where-Object { $_.Evidence -and ([string]$_.Evidence.OperationStatus) -in @('Ok','OkAfterRetry','WinReServicingStackKnownIssue') }).Count -gt 0
    $effectiveCandidates=@([string]$DeepInspection.KernelBuild)
    $effectiveCandidates+=@($safe | ForEach-Object { [string]$_.Version })
    $effectiveCandidates+=@($DeepInspection.RollupFixPackages | ForEach-Object { [string]$_.Version })
    $effectiveCandidates+=@($stackPackages | ForEach-Object { [string]$_.Version })
    $effectiveCandidates+=@([string]$DeepInspection.RegistryBuild)
    $effective=$null
    foreach($candidate in $effectiveCandidates){if([string]::IsNullOrWhiteSpace($candidate)){continue};try{$v=[version]$candidate}catch{continue};if(-not $effective -or $v -gt $effective){$effective=$v}}
    $requireOutcome=-not [string]::IsNullOrWhiteSpace([string]$DeepInspection.ExpectedSafeOsFileName)
    $stackPass=($stackPackages.Count -gt 0 -or $stackKbMatches.Count -gt 0)
    $safePass=($safe.Count -gt 0 -and $stackPass -and $pending.Count -eq 0 -and ($outcomeSuccess -or -not $requireOutcome))
    $rollup=@($DeepInspection.RollupFixPackages)
    $osBuildApplicable=$rollup.Count -gt 0
    $osBuildPass=$true
    if($osBuildApplicable){
        $measured=ConvertFrom-InspectionBuildValue -Value ([string]$rollup[0].Version)
        $expected=ConvertTo-TwoPartBuild -BuildString $ExpectedOsBuild
        $osBuildPass=[bool]($measured -and $expected -and $measured -ge $expected)
    }
    [pscustomobject]@{
        SafeOsPresent=($safe.Count -gt 0);SafeOsPass=$safePass;PendingCount=$pending.Count
        ServicingStackPresent=$stackPass;ServicingStackPackageVersions=@($stackPackages|ForEach-Object{$_.Version})
        ServicingStackKbMatches=@($stackKbMatches|ForEach-Object{$_.KbId}|Sort-Object -Unique)
        OutcomeEvidencePresent=($outcomes.Count -gt 0);OutcomeSuccess=$outcomeSuccess
        EffectiveBuild=$(if($effective){[string]$effective}else{''})
        SafeOsPackageVersions=@($safe|ForEach-Object{$_.Version})
        OsLcuBuildApplicable=$osBuildApplicable;OsLcuBuildPass=$osBuildPass
        RollupFixVersions=@($rollup|ForEach-Object{$_.Version})
    }
}

function Invoke-VerifyPhase11_StaticVerify {
    <#
    .SYNOPSIS
        P11: Verify the output ISO without booting it. Mounts the ISO,
        verifies presence of install.wim/boot.wim/setup.exe, proves
        content identity between the shipped ISO's WIMs and the
        extracted tree (SHA-256, hard), then runs the FULL post
        media inspection over the extracted tree (every index, one
        mount each) and derives the Kb rows and the
        TargetBuildAfterUpdate hard check from the measured
        evidence. Emits P11_verification.csv +
        logs/inspection_post.json.
    #>
    Start-DebugTrace -Context 'Invoke-VerifyPhase11_StaticVerify' -PhaseId 'P11'
    try {
        if ([string]::IsNullOrEmpty($Script:OutputIsoPath)) {
            # Recover from a Verify-only run
            $monthTag = (Get-Date -Format 'yyyy-MM')
            $outName = ('{0}_{1}_Updated_{2}.iso' -f $Script:OsProfile.OsShortName, $Script:OsLanguage, $monthTag)
            $Script:OutputIsoPath = Join-Path $Script:OutputDir $outName
        }

        $rows = [System.Collections.Generic.List[object]]::new()
        $bootPolicyExceptionPath = Join-Path $Script:LogsDir 'P08_bootwim_policy_exception.json'
        $bootPolicyException = Read-ReleaseJsonFile -Path $bootPolicyExceptionPath
        $bootPolicyExceptionIssues=[System.Collections.Generic.List[string]]::new()
        if($bootPolicyException){
            if(-not ($bootPolicyException.PSObject.Properties['Active'] -and $bootPolicyException.Active)){$bootPolicyExceptionIssues.Add('Active is not true.')|Out-Null}
            if([string]$bootPolicyException.OsKey -ne [string]$Script:OsVersion){$bootPolicyExceptionIssues.Add('OsKey does not match the current run.')|Out-Null}
            if([string]$bootPolicyException.BootWimFailurePolicy -ne 'UnsupportedByPinnedSourceMedia'){$bootPolicyExceptionIssues.Add('Failure policy is not UnsupportedByPinnedSourceMedia.')|Out-Null}
            if([string]$bootPolicyException.ErrorCode -notin @('0x8007371b','0x80070032')){$bootPolicyExceptionIssues.Add('ErrorCode is outside the measured allow-list.')|Out-Null}
            if(-not ($bootPolicyException.PSObject.Properties['PreserveSourceBootWim'] -and $bootPolicyException.PreserveSourceBootWim)){$bootPolicyExceptionIssues.Add('PreserveSourceBootWim is not true.')|Out-Null}
            if(-not ($bootPolicyException.PSObject.Properties['RequiresInstallValidation'] -and $bootPolicyException.RequiresInstallValidation)){$bootPolicyExceptionIssues.Add('RequiresInstallValidation is not true.')|Out-Null}
            if(-not ($bootPolicyException.PSObject.Properties['RestoreVerified'] -and $bootPolicyException.RestoreVerified)){$bootPolicyExceptionIssues.Add('RestoreVerified is not true.')|Out-Null}
            if([string]::IsNullOrWhiteSpace([string]$bootPolicyException.SourceBootWimSha256) -or [string]$bootPolicyException.SourceBootWimSha256 -ne [string]$bootPolicyException.RestoredBootWimSha256){$bootPolicyExceptionIssues.Add('Source/restored boot.wim SHA-256 evidence is absent or mismatched.')|Out-Null}
        }
        $hasBootPolicyException = [bool]($bootPolicyException -and $bootPolicyExceptionIssues.Count -eq 0)
        function Add-VRow {
            param([string]$Check, [string]$Expected, [string]$Actual, [string]$Status, [string]$Notes)
            $rows.Add([pscustomobject]@{
                Check = $Check; Expected = $Expected; Actual = $Actual
                Status = $Status; Notes = $Notes
            }) | Out-Null
        }

        if($bootPolicyException -and -not $hasBootPolicyException){
            Add-VRow -Check 'BootWimPolicyExceptionEvidence' -Expected 'identity-consistent measured policy evidence with verified source restore' -Actual 'invalid' -Status 'Fail' -Notes ($bootPolicyExceptionIssues.ToArray() -join ' ')
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

            $setupManifestPath = Join-Path $Script:LogsDir 'setupdu_overlay_manifest.json'
            if (Test-Path -LiteralPath $setupManifestPath) {
                $setupManifest = Get-Content -LiteralPath $setupManifestPath -Raw | ConvertFrom-Json
                $setupFailures=0; $setupChecked=0
                foreach ($mrec in @($setupManifest.Records)) {
                    if ($mrec.OverriddenByBootWim) { continue }
                    $setupChecked++
                    $isoDest=Join-Path $mountedDrive ('sources\' + ([string]$mrec.RelativePath))
                    if (-not (Test-Path -LiteralPath $isoDest)) { $setupFailures++; continue }
                    $isoHash=(Get-FileHash -LiteralPath $isoDest -Algorithm SHA256).Hash.ToLower()
                    if ($isoHash -ne [string]$mrec.SourceSha256) { $setupFailures++ }
                }
                Add-VRow -Check 'SetupDuFinalManifest' -Expected ('all ' + $setupChecked + ' non-overridden files present and matching') -Actual $(if ($setupFailures -eq 0) { 'match' } else { ($setupFailures.ToString() + ' mismatch/missing') }) -Status $(if ($setupFailures -eq 0) { 'Pass' } else { 'Fail' }) -Notes $setupManifestPath
            } elseif (@($Script:ResolvedPatches | Where-Object { $_.PatchType -eq 'SetupDU' }).Count -gt 0) {
                Add-VRow -Check 'SetupDuFinalManifest' -Expected 'evidence present' -Actual 'missing' -Status 'Fail' -Notes $setupManifestPath
            }

            if ($hasInst -and -not $Script:SyntheticTestMode) {
                # Content-identity proof: the deep inspection below runs
                # over the EXTRACTED tree (DISM cannot mount a WIM living
                # on read-only ISO media); these rows prove byte identity
                # between what we inspect and what we ship. Hard Fail on
                # mismatch.
                Set-DebugStep -Step 'iso-wim-hash-equivalence'
                foreach ($pair in @(
                    @{ Name = 'install'; Iso = $installWim; Ext = (Join-Path $Script:ExtractedDir 'sources\install.wim') },
                    @{ Name = 'boot';    Iso = $bootWim;    Ext = (Join-Path $Script:ExtractedDir 'sources\boot.wim') }
                )) {
                    if (-not (Test-Path -LiteralPath $pair.Ext)) {
                        Add-VRow -Check ('IsoWimHashMatch_' + $pair.Name) -Expected 'match' `
                            -Actual 'extracted-missing' -Status 'Fail' -Notes $pair.Ext
                        continue
                    }
                    $hIso = (Get-FileHash -LiteralPath $pair.Iso -Algorithm SHA256).Hash.ToLower()
                    $hExt = (Get-FileHash -LiteralPath $pair.Ext -Algorithm SHA256).Hash.ToLower()
                    if ($hIso -eq $hExt) { $hs = 'Pass' } else { $hs = 'Fail' }
                    Add-VRow -Check ('IsoWimHashMatch_' + $pair.Name) -Expected 'match' `
                        -Actual $(if ($hIso -eq $hExt) { 'match' } else { 'MISMATCH' }) `
                        -Status $hs -Notes ('iso=' + $hIso.Substring(0, 12) + ' extracted=' + $hExt.Substring(0, 12))
                    Write-Step ('{0}.wim ISO/extracted SHA-256: {1}' -f $pair.Name, $(if ($hIso -eq $hExt) { 'match' } else { 'MISMATCH' }))
                }
            }
        }
        if ($img) {
            try { Dismount-DiskImage -ImagePath $Script:OutputIsoPath -ErrorAction SilentlyContinue | Out-Null } catch { $null = $_ }
        }

        # Step 3: full post-servicing media inspection (extracted tree;
        # content identity to the ISO proven above). The Kb rows and the
        # TargetBuildAfterUpdate hard check are derived from MEASURED
        # evidence -- the former -ImagePath enumeration was an invalid
        # Get-WindowsPackage parameter set that threw on every OS and was
        # swallowed by a catch, so those rows had never actually run.
        if (-not $Script:SyntheticTestMode -and $Script:Execute) {
            Set-DebugStep -Step 'post-inspection'
            Write-SubSection 'Step 3: Post-servicing media inspection'
            $postInsp = $null
            try {
                $postMount = Join-Path $Script:WorkRoot 'work\inspect_mount'
                $postInsp = Get-MediaInspection -OsKey $Script:OsVersion -MediaRoot $Script:ExtractedDir `
                    -Label 'post' -MountDir $postMount -LogDir $Script:LogsDir
                $postJson = Write-MediaInspectionJson -Inspection $postInsp -LogDir $Script:LogsDir
                Write-Ok ('Post-servicing inspection written: {0}' -f $postJson)
            } catch {
                Write-Caution ('Post-servicing inspection failed: {0}' -f $_.Exception.Message)
            }
            if (-not $postInsp -or $postInsp.ErrorMessage -or -not $postInsp.InstallWim.Present) {
                Add-VRow -Check 'PostInspection' -Expected 'available' -Actual 'unavailable' `
                    -Status 'Fail' -Notes $(if ($postInsp -and $postInsp.ErrorMessage) { $postInsp.ErrorMessage } else { 'inspection did not produce install.wim records' })
            } else {
                Add-VRow -Check 'PostInspection' -Expected 'available' -Actual 'available' `
                    -Status 'Pass' -Notes ('install idx: {0}; boot idx: {1}' -f @($postInsp.InstallWim.Indexes).Count, @($postInsp.BootWim.Indexes).Count)

                $pbLcuAll = @($Script:OsProfile.PatchBaseline.Lines | Where-Object { $_.Kind -eq 'LCU' -and $_.KbId })
                $expectedLcuKbAll = if ($pbLcuAll.Count -gt 0) { [string]$pbLcuAll[0].KbId } else { '' }
                $expectedBuildAll = [string]$Script:OsProfile.PatchBaseline.TargetBuildAfterUpdate
                foreach ($irec in @($postInsp.InstallWim.Indexes)) {
                    if (-not $irec -or $irec.ErrorMessage) {
                        Add-VRow -Check ('InstallIndex_' + $(if ($irec) { $irec.Index } else { 'unknown' })) -Expected 'inspectable' -Actual 'error' -Status 'Fail' -Notes $(if ($irec) { $irec.ErrorMessage } else { 'missing record' })
                        continue
                    }
                    $ir = Test-LcuTargetApplied -OsKey $Script:OsVersion -ExpectedKbId $expectedLcuKbAll -ExpectedBuild $expectedBuildAll -Evidence $irec.Evidence
                    Add-VRow -Check ('InstallIndex' + $irec.Index + '_LcuTargetApplied') -Expected $ir.Expected -Actual $ir.Actual -Status $ir.Status -Notes $ir.Notes
                    $matchingDotNet=@($Script:ResolvedPatches | Where-Object { $_.PatchType -eq 'DotNet' -and (Test-DotNetRuntimeSelector -Selector $_.RuntimeSelector -OfflineState ([pscustomobject]@{ DotNetVersion=$irec.DotNetVersion })) })
                    if ($matchingDotNet.Count -gt 0) {
                        $dnev=Get-DotNetRollupEvidence -PackageNames @($irec.PackageNames)
                        Add-VRow -Check ('InstallIndex' + $irec.Index + '_DotNetRollup') -Expected ('Present for runtime ' + $irec.DotNetVersion) -Actual $(if ($dnev.Present) { $dnev.PackageName } else { 'Absent' }) -Status $(if ($dnev.Present) { 'Pass' } else { 'Fail' }) -Notes ('matching leaf KBs: ' + (($matchingDotNet | ForEach-Object { $_.KbId }) -join ','))
                    }
                }
                $bootPolicyForVerify=Resolve-BootWimLcuPolicyValue -RawValue $Script:OsProfile.BootWimLcuPolicy
                if ($bootPolicyForVerify -eq 'enabled') {
                    if($hasBootPolicyException){
                        Add-VRow -Check 'BootWimServicingPolicy' -Expected 'LCU applied or source preserved only under an explicit measured policy exception' -Actual ('PolicyException ' + [string]$bootPolicyException.ErrorCode) -Status 'PolicyException' -Notes $bootPolicyExceptionPath
                    }
                    foreach ($brec in @($postInsp.BootWim.Indexes)) {
                        if (-not $brec -or $brec.ErrorMessage) {
                            Add-VRow -Check ('BootIndex_' + $(if ($brec) { $brec.Index } else { 'unknown' })) -Expected 'inspectable' -Actual 'error' -Status 'Fail' -Notes $(if ($brec) { $brec.ErrorMessage } else { 'missing record' })
                            continue
                        }
                        if($hasBootPolicyException){
                            $observedBootBuild=if($brec.Evidence -and $brec.Evidence.Build){[string]$brec.Evidence.Build}else{'unknown'}
                            Add-VRow -Check ('BootIndex' + $brec.Index + '_LcuTargetApplied') -Expected ('PolicyException: source build preserved; P14 Install required instead of target ' + $expectedBuildAll) -Actual $observedBootBuild -Status 'PolicyException' -Notes ([string]$bootPolicyException.Reason)
                        } else {
                            $br=Test-LcuTargetApplied -OsKey $Script:OsVersion -ExpectedKbId $expectedLcuKbAll -ExpectedBuild $expectedBuildAll -Evidence $brec.Evidence
                            Add-VRow -Check ('BootIndex' + $brec.Index + '_LcuTargetApplied') -Expected $br.Expected -Actual $br.Actual -Status $br.Status -Notes $br.Notes
                        }
                    }
                }

                $safeLine=@($Script:ResolvedPatches | Where-Object { $_.PatchType -eq 'SafeOSDU' }) | Select-Object -First 1
                $expectedStackKbs=@($Script:ResolvedPatches | Where-Object {
                    ((Get-PatchTargetsForEntry -Patch $_) -contains 'WinRE') -and
                    ((Test-PatchHasRole -Patch $_ -Role 'ServicingStackCarrier') -or (Test-PatchHasRole -Patch $_ -Role 'SourcePrerequisite')) -and
                    $_.KbId -and $_.KbId -ne 'Unknown'
                } | ForEach-Object { [string]$_.KbId } | Sort-Object -Unique)
                $installIndexesForWinRe=@($postInsp.InstallWim.Indexes | Where-Object { -not $_.ErrorMessage } | ForEach-Object { [int]$_.Index })
                $winreEv=Get-WinRePostServicingEvidence -InstallWim (Join-Path $Script:ExtractedDir 'sources\install.wim') -Indexes $installIndexesForWinRe -OsKey $Script:OsVersion -ExpectedBuild $expectedBuildAll -ExpectedSafeOsKb $(if ($safeLine) { [string]$safeLine.KbId } else { '' }) -ExpectedSafeOsFileName $(if ($safeLine) { [string]$safeLine.FileName } else { '' }) -ExpectedServicingStackKbs $expectedStackKbs -WorkRoot $Script:WorkRoot -LogDir $Script:LogsDir
                $winrePath=Join-Path $Script:LogsDir 'winre_post_verification.json'
                $winreEv | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $winrePath -Encoding UTF8
                Add-VRow -Check 'WinReHashesEqualAllInstallIndexes' -Expected 'True' -Actual ([string]$winreEv.AllHashesEqual) -Status $(if ($winreEv.AllHashesEqual) { 'Pass' } else { 'Fail' }) -Notes $winrePath
                if ($winreEv.DeepInspection) {
                    $wrDecision=Get-WinReServicingVerificationDecision -DeepInspection $winreEv.DeepInspection -ExpectedOsBuild $expectedBuildAll
                    Add-VRow -Check 'WinReServicingLevel' -Expected 'SafeOSDU installed; servicing stack present; no pending packages; successful DISM evidence' -Actual $(if($wrDecision.SafeOsPresent){'SafeOSDU=' + ($wrDecision.SafeOsPackageVersions -join ',') + '; stack=' + (($wrDecision.ServicingStackPackageVersions + $wrDecision.ServicingStackKbMatches) -join ',') + '; effective=' + $wrDecision.EffectiveBuild}else{'SafeOSDU absent'}) -Status $(if($wrDecision.SafeOsPass){'Pass'}else{'Fail'}) -Notes $winrePath
                    Add-VRow -Check 'WinReServicingStackEvidence' -Expected (($expectedStackKbs -join ',') + ' or a ServicingStack-named package') -Actual $(if($wrDecision.ServicingStackPresent){(($wrDecision.ServicingStackPackageVersions + $wrDecision.ServicingStackKbMatches) -join ',')}else{'Absent'}) -Status $(if($wrDecision.ServicingStackPresent){'Pass'}else{'Fail'}) -Notes 'Server 2016 exposes SSU KB package identities; newer media exposes ServicingStack package identities.'
                    Add-VRow -Check 'WinReBuildTarget' -Expected $(if($wrDecision.OsLcuBuildApplicable){'>= ' + $expectedBuildAll}else{'NotApplicable: WinRE is validated by SafeOSDU/SSU evidence, not the install.wim OS LCU build'}) -Actual $(if($wrDecision.OsLcuBuildApplicable){$wrDecision.RollupFixVersions -join ','}else{$wrDecision.EffectiveBuild}) -Status $(if($wrDecision.OsLcuBuildPass){'Pass'}else{'Fail'}) -Notes 'OS LCU build is checked only when a RollupFix package is actually present in WinRE.'
                    $pendingCount=[int]$wrDecision.PendingCount
                    Add-VRow -Check 'WinRePendingPackages' -Expected '0' -Actual ([string]$pendingCount) -Status $(if ($pendingCount -eq 0) { 'Pass' } else { 'Fail' }) -Notes ((@($winreEv.DeepInspection.PendingPackages)) -join ';')
                    if ($safeLine) {
                        $safeActual='package=' + ($wrDecision.SafeOsPackageVersions -join ',') + '; dismOutcome=' + $(if($wrDecision.OutcomeSuccess){'success'}elseif($wrDecision.OutcomeEvidencePresent){'failure'}else{'not-recorded'})
                        Add-VRow -Check 'WinReSafeOsDuEvidence' -Expected ([string]$safeLine.KbId) -Actual $safeActual -Status $(if($wrDecision.SafeOsPass){'Pass'}else{'Fail'}) -Notes ('Configured asset=' + [string]$safeLine.FileName + '; evidence=' + $winrePath)
                    }

                } else {
                    Add-VRow -Check 'WinReDeepInspection' -Expected 'available' -Actual 'unavailable' -Status 'Fail' -Notes $winrePath
                }

                $primaryRec = @($postInsp.InstallWim.Indexes) | Select-Object -First 1
                if ($primaryRec -and -not $primaryRec.ErrorMessage) {
                    $pkgNames = @($primaryRec.PackageNames)
                    # ---- Per-Kind verification [adjudicated 2026-07-08] ----
                    # E2E-measured (2026-07-08, all 4 OSes): KB ids appear in
                    # installed package names ONLY on Server 2016. Generic
                    # Kb_<id> presence rows were structurally Warn-locked on
                    # the RollupFix-named OSes; verification is per Kind:
                    #   LCU / Checkpoint -> LcuTargetApplied (measured build)
                    #   DotNet           -> DotNetRollupApplied (census below)
                    #   SafeOSDU / SetupDU -> not install.wim idx-1 packages
                    #                         (WinRE payload / sources files);
                    #                         excluded here, stated in scope.
                    Add-VRow -Check 'KindVerificationScope' -Expected 'documented' `
                        -Actual 'documented' -Status 'Pass' `
                        -Notes 'LCU/Checkpoint via LcuTargetApplied (measured build); DotNet via DotNetRollupApplied; SafeOSDU (WinRE payload) and SetupDU (sources files) are not verifiable as install.wim packages; Server2016 additionally verifies KB-named packages.'

                    if ($Script:OsVersion -eq 'Server2016') {
                        # Server 2016 SSU/source-prerequisite package identities
                        # normally retain their KB ids and provide useful direct
                        # evidence. LCU/Bridge/Checkpoint identity is intentionally
                        # excluded: after component cleanup/ResetBase the KB token
                        # may disappear even when the authoritative registry/kernel
                        # build proves the target LCU. LCU is already hard-gated by
                        # LcuTargetApplied above. SafeOSDU belongs to WinRE, SetupDU
                        # belongs to media\sources, and .NET is checked separately.
                        $expectedKbList = @($Script:ResolvedPatches | Where-Object {
                            $_.KbId -ne 'Unknown' -and
                            $_.PatchType -eq 'SSU' -and
                            ((Get-PatchTargetsForEntry -Patch $_) -contains 'Install')
                        } | ForEach-Object { $_.KbId } | Sort-Object -Unique)
                        foreach ($kb in $expectedKbList) {
                            $found = $false
                            foreach ($pn in $pkgNames) {
                                # psa-disable-next-line PSA2003 -- $kb is a non-null string from the resolved set
                                if ($pn -match $kb) { $found = $true; break }
                            }
                            if ($found) { $st = 'Pass'; $actualStr = 'Present' }
                            else        { $st = 'Warn'; $actualStr = 'Absent' }
                            Add-VRow -Check ('Kb_' + $kb) -Expected 'Present when package identity exposes KB' `
                                -Actual $actualStr -Status $st `
                                -Notes ('install.wim idx ' + $primaryRec.Index + '; scoped to Install-targeted OS servicing packages')
                        }
                    }

                    $primaryRuntime = [pscustomobject]@{ DotNetVersion=$primaryRec.DotNetVersion }
                    $dotNetExpected = @($Script:ResolvedPatches | Where-Object {
                        $_.PatchType -eq 'DotNet' -and
                        (Test-DotNetRuntimeSelector -Selector $_.RuntimeSelector -OfflineState $primaryRuntime)
                    })
                    if ($dotNetExpected.Count -ge 1) {
                        $dotNetEv = Get-DotNetRollupEvidence -PackageNames $pkgNames
                        if ($dotNetEv.Present) {
                            Add-VRow -Check 'DotNetRollupApplied' -Expected ('Present for runtime ' + $primaryRec.DotNetVersion) `
                                -Actual 'Present' -Status 'Pass' `
                                -Notes ('install.wim idx ' + $primaryRec.Index + '; ' + $dotNetEv.PackageName + ' (version ' + $dotNetEv.Version + '); matching leaf KBs=' + (($dotNetExpected | ForEach-Object { $_.KbId }) -join ','))
                        } else {
                            Add-VRow -Check 'DotNetRollupApplied' -Expected ('Present for runtime ' + $primaryRec.DotNetVersion) `
                                -Actual 'Absent' -Status 'Fail' `
                                -Notes ('install.wim idx ' + $primaryRec.Index + '; runtime-matching .NET leaf was applied but no Package_for_DotNetRollup* package is visible')
                        }
                    } else {
                        Add-VRow -Check 'DotNetRollupApplied' -Expected 'not applicable to detected runtime' `
                            -Actual ([string]$primaryRec.DotNetVersion) -Status 'Pass' `
                            -Notes ('install.wim idx ' + $primaryRec.Index + '; no configured .NET leaf matches this runtime')
                    }
                    # TargetBuildAfterUpdate hard check [DECIDED 2026-07-02,
                    # user]: per-OS evidence comparator. Runs only
                    # when the resolved set actually intended the baseline
                    # LCU (defensive, unchanged).
                    $pbLcu = @()
                    if ($Script:OsProfile -and $Script:OsProfile.PSObject.Properties['PatchBaseline'] -and
                        $Script:OsProfile.PatchBaseline -and
                        $Script:OsProfile.PatchBaseline.PSObject.Properties['Lines']) {
                        $pbLcu = @($Script:OsProfile.PatchBaseline.Lines |
                            Where-Object { $_.Kind -eq 'LCU' -and $_.KbId })
                    }
                    $expectedKbIds = @($Script:ResolvedPatches | Where-Object { $_.KbId -ne 'Unknown' } | ForEach-Object { $_.KbId })
                    if ($pbLcu.Count -ge 1 -and ($expectedKbIds -contains $pbLcu[0].KbId)) {
                        $tbauExpected = ''
                        if ($Script:OsProfile.PatchBaseline.PSObject.Properties['TargetBuildAfterUpdate']) {
                            $tbauExpected = [string]$Script:OsProfile.PatchBaseline.TargetBuildAfterUpdate
                        }
                        $tbauRow = Test-LcuTargetApplied -OsKey $Script:OsVersion `
                            -ExpectedKbId $pbLcu[0].KbId -ExpectedBuild $tbauExpected `
                            -Evidence $primaryRec.Evidence
                        Add-VRow -Check $tbauRow.Check -Expected $tbauRow.Expected `
                            -Actual $tbauRow.Actual -Status $tbauRow.Status -Notes $tbauRow.Notes
                        if ($tbauRow.Status -eq 'Pass') {
                            Write-Ok ('Baseline LCU {0} applied ({1}).' -f $pbLcu[0].KbId, $tbauRow.Notes)
                        } elseif ($tbauRow.Status -eq 'Warn') {
                            Write-Caution ('Baseline LCU {0}: {1}.' -f $pbLcu[0].KbId, $tbauRow.Notes)
                        } else {
                            Write-Fail ('Baseline LCU {0} NOT applied ({1}).' -f $pbLcu[0].KbId, $tbauRow.Notes)
                        }
                    }
                } else {
                    Add-VRow -Check 'PostInspectionPrimaryIndex' -Expected 'inspectable' -Actual 'error' `
                        -Status 'Fail' -Notes $(if ($primaryRec) { $primaryRec.ErrorMessage } else { 'no index records' })
                }
            }
        }

        # SetupBinarySync: media \sources setup binaries must
        # be byte-identical to the serviced boot.wim idx2's (MS
        # media-dynamic-update: "If these binaries aren't identical,
        # Windows Setup will fail during installation"). Measured
        # failure 2026-07-11 (2016/2022/2025 pre-edition "media
        # driver missing"); P08S is the fix, this row proves it held.
        if ((Test-Path -Path variable:postInsp) -and $postInsp -and -not $postInsp.ErrorMessage -and $postInsp.BootWim.Present) {
            $sbIdx2 = @($postInsp.BootWim.Indexes) | Where-Object { $_.Index -eq 2 } | Select-Object -First 1
            if ($sbIdx2 -and -not $sbIdx2.ErrorMessage) {
                $sbBuild = $null
                if ($sbIdx2.Evidence -and $sbIdx2.Evidence.Build) {
                    $sbV = ConvertFrom-InspectionBuildValue -Value $sbIdx2.Evidence.Build
                    if ($sbV) { $sbBuild = $sbV.Major }
                }
                $sbPlan = Get-SetupBinarySyncPlan -BuildNumber $sbBuild
                foreach ($sbFile in @($sbPlan.Files)) {
                    $sbSlot  = if ($sbFile -eq 'setup.exe') { 'SetupExe' } else { 'SetupHostExe' }
                    $sbWim   = $sbIdx2.$sbSlot
                    $sbMedia = $postInsp.MediaSetupBinaries.$sbSlot
                    $sbNotes = ('boot.wim idx2: size={0} time={1} sha={2}; media: size={3} time={4} sha={5}' -f `
                        $(if ($sbWim) { $sbWim.SizeBytes } else { 'n/a' }), $(if ($sbWim) { $sbWim.LastWriteTimeUtc } else { 'n/a' }), $(if ($sbWim -and $sbWim.Sha256) { $sbWim.Sha256.Substring(0, 12) } else { 'n/a' }), `
                        $(if ($sbMedia) { $sbMedia.SizeBytes } else { 'n/a' }), $(if ($sbMedia) { $sbMedia.LastWriteTimeUtc } else { 'n/a' }), $(if ($sbMedia -and $sbMedia.Sha256) { $sbMedia.Sha256.Substring(0, 12) } else { 'n/a' }))
                    if ($sbWim -and $sbWim.Present -and $sbMedia -and $sbMedia.Present -and $sbWim.Sha256 -and $sbWim.Sha256 -eq $sbMedia.Sha256) {
                        Add-VRow -Check ('SetupBinarySync_' + $sbFile) -Expected 'media SHA-256 == boot.wim idx2' `
                            -Actual 'identical' -Status 'Pass' -Notes $sbNotes
                        Write-Ok ('SetupBinarySync {0}: media is byte-identical to boot.wim idx2.' -f $sbFile)
                    } elseif ($sbWim -and -not $sbWim.Present -and $sbFile -eq 'setuphost.exe') {
                        Add-VRow -Check ('SetupBinarySync_' + $sbFile) -Expected 'media SHA-256 == boot.wim idx2' `
                            -Actual 'source-absent' -Status 'Warn' -Notes ('planned by build gate but absent in boot.wim idx2; ' + $sbNotes)
                        Write-Caution ('SetupBinarySync {0}: absent in boot.wim idx2.' -f $sbFile)
                    } elseif($hasBootPolicyException) {
                        Add-VRow -Check ('SetupBinarySync_' + $sbFile) -Expected 'PolicyException: source boot.wim preserved; P14 Install must prove the effective Setup path' `
                            -Actual 'MISMATCH' -Status 'PolicyException' -Notes ('The mismatch remains explicit and is not accepted as a static pass. ' + $sbNotes)
                        Write-Caution ('SetupBinarySync {0}: media does not match the restored source boot.wim under the measured policy exception; P14 Install validation is mandatory.' -f $sbFile)
                    } else {
                        Add-VRow -Check ('SetupBinarySync_' + $sbFile) -Expected 'media SHA-256 == boot.wim idx2' `
                            -Actual 'MISMATCH' -Status 'Fail' -Notes ('Setup will fail during installation per MS media-dynamic-update; ' + $sbNotes)
                        Write-Fail ('SetupBinarySync {0}: media does NOT match boot.wim idx2 -- the output ISO will fail before edition selection.' -f $sbFile)
                    }
                }
            } else {
                Add-VRow -Check 'SetupBinarySync' -Expected 'boot.wim idx2 inspectable' -Actual 'not inspectable' `
                    -Status 'Warn' -Notes 'sync could not be verified; see BootWim index records'
            }
        }

        $csvPath = Join-Path $Script:LogsDir 'P11_verification.csv'
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        Write-Ok ('Wrote: {0}' -f $csvPath)

        $failed = @($rows | Where-Object { $_.Status -eq 'Fail' })
        $policyExceptionRows=@($rows | Where-Object { $_.Status -eq 'PolicyException' })
        if ($failed.Count -gt 0) {
            throw ('P11 verification failed: {0} hard failures.' -f $failed.Count)
        }
        $p11Status=$(if($policyExceptionRows.Count -gt 0){'PolicyException'}else{'Pass'})

        $patchManifestPath = Join-Path $Script:LogsDir 'resolved_patch_manifest.json'
        Save-CanonicalJsonFile -InputObject (New-ResolvedPatchEvidenceManifest) -Path $patchManifestPath -Depth 16
        $identity = Get-ReleaseEvidenceIdentity
        $p11EvidencePath = Join-Path $Script:LogsDir 'P11_static_verification.json'
        # Do not wrap Generic.List[object] in @(...). PowerShell issue #27558
        # throws 'Argument types do not match' for New-Object-created lists.
        # r12.17 uses constructor-created lists globally and reads Count directly.
        $p11Evidence = [pscustomobject][ordered]@{
            SchemaVersion='P11-static-verification/1.0'
            Status=$p11Status
            CreatedAtUtc=([datetime]::UtcNow.ToString('o'))
            Identity=$identity
            VerificationCsvPath=$csvPath
            VerificationCsvSha256=(Get-FileSha256OrEmpty -Path $csvPath)
            PostInspectionPath=(Join-Path $Script:LogsDir 'inspection_post.json')
            PostInspectionSha256=(Get-FileSha256OrEmpty -Path (Join-Path $Script:LogsDir 'inspection_post.json'))
            RowCount=$rows.Count
            FailureCount=0
            PolicyExceptionCount=$policyExceptionRows.Count
            PolicyExceptionEvidencePath=$(if($hasBootPolicyException){$bootPolicyExceptionPath}else{''})
            PolicyExceptionEvidenceSha256=$(if($hasBootPolicyException){Get-FileSha256OrEmpty -Path $bootPolicyExceptionPath}else{''})
        }
        Save-CanonicalJsonFile -InputObject $p11Evidence -Path $p11EvidencePath -Depth 16
        Write-ReleaseEvidenceMarker -Name 'P11.ok' -Identity $identity -EvidencePath $p11EvidencePath -Status $p11Status | Out-Null
    } finally {
        Stop-DebugTrace
    }
}

# ============================================================
# Phase P12: Verify PCA2023 readiness (Verify group, ALWAYS-RUNS)
# ============================================================
# This phase ALWAYS runs as part of the Verify group, regardless of
# whether P10 ran or was skipped (-SkipPca2023BootManager). The
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
        $outputCheck = Test-OutputIsoPca2023Readiness -ExtractedMediaPath $extractedPath -ConversionSkipReason (Get-P10SkipReason)
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
        $mdLines = [System.Collections.Generic.List[string]]::new()
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
        $mdLines.Add('- GitHub: [microsoft/secureboot_objects Make2023BootableMedia.ps1](https://github.com/microsoft/secureboot_objects/blob/v1.6.5/scripts/windows/Make2023BootableMedia.ps1)') | Out-Null
        $mdLines.Add('') | Out-Null
        Set-Content -LiteralPath $mdPath -Value ($mdLines -join "`n") -Encoding UTF8 -Force
        Write-Step ('Snapshot Markdown: {0}' -f $mdPath)

        $policy = Get-Pca2023CompliancePolicy
        $compliance = Test-Pca2023PolicyCompliance -OutputCheck $outputCheck -Policy $policy
        $freshness = Get-AuxiliaryFreshnessAssessment
        $staticVerification = Get-StaticVerificationAssessment
        $bootValidation = Get-BootValidationAssessment
        $staticEligible = $staticVerification.Eligible -and $compliance.ReleaseEligible -and $freshness.IsFresh
        $requiresInstallValidation=[bool]($staticVerification.PSObject.Properties['RequiresInstallValidation'] -and $staticVerification.RequiresInstallValidation)
        $bootValidationEligibleForRelease=($bootValidation.Eligible -and (-not $requiresInstallValidation -or [string]$bootValidation.Mode -eq 'Install'))
        $reasons = [System.Collections.Generic.List[string]]::new()
        if (-not $staticVerification.Eligible -and $staticVerification.Reason) { $reasons.Add([string]$staticVerification.Reason) | Out-Null }
        foreach ($reason in @($compliance.Reasons)) { if ($reason) { $reasons.Add([string]$reason) | Out-Null } }
        foreach ($item in @($freshness.Issues)) {
            $reasons.Add(('{0} freshness {1} {2}: {3} (release={4}; baseline={5}).' -f $freshness.Status,$item.Kind,$item.KbId,$item.Issue,$item.ReleaseMonth,$item.BaselineMonth)) | Out-Null
        }
        if (-not $bootValidation.Eligible -and $bootValidation.Reason) { $reasons.Add($bootValidation.Reason) | Out-Null }
        if($requiresInstallValidation -and $bootValidation.Eligible -and [string]$bootValidation.Mode -ne 'Install'){ $reasons.Add('The boot.wim policy exception requires P14 Install validation; BootOnly evidence cannot close it.') | Out-Null }
        $releaseEligible = $staticEligible -and $bootValidationEligibleForRelease
        $releaseStatus = if ($releaseEligible) { 'ReleaseReady' } elseif ($staticEligible -and $requiresInstallValidation) { 'Candidate-InstallTestRequired' } elseif ($staticEligible -and $bootValidation.Status -eq 'ReviewRequired') { 'BootEvidenceReviewRequired' } elseif ($staticEligible) { 'Candidate-BootTestRequired' } else { 'NotEligible' }
        $Script:ReleaseEligibility = [pscustomobject][ordered]@{
            SchemaVersion='release-eligibility/1.3'
            RunId=$Script:RunId
            BuildSucceeded=$true
            StaticVerificationStatus=$staticVerification.Status
            Pca2023Compliance=$(if ($compliance.ReleaseEligible) { 'Pass' } else { 'Fail' })
            Pca2023Policy=$policy
            AuxiliaryFreshness=$freshness.Status
            AuxiliaryApplicability=$freshness.ApplicabilityStatus
            AuxiliaryApplicableItemCount=$freshness.ApplicableItemCount
            AuxiliaryNotApplicableItemCount=$freshness.NotApplicableItemCount
            StaticEligible=$staticEligible
            BootTestStatus=$bootValidation.Status
            BootEvidenceEligible=$bootValidation.Eligible
            BootTestEligible=$bootValidationEligibleForRelease
            BootValidationRequired=($staticEligible -and -not $bootValidationEligibleForRelease)
            RequiresInstallValidation=$requiresInstallValidation
            StaticPolicyException=($staticVerification.Status -eq 'PolicyException')
            StaticPolicyExceptionReason=$(if($staticVerification.Status -eq 'PolicyException'){$staticVerification.Reason}else{''})
            ReleaseStatus=$releaseStatus
            ReleaseEligible=$releaseEligible
            Reasons=$reasons.ToArray()
        }
        $identity = Get-ReleaseEvidenceIdentity
        $assessmentPath = Join-Path $Script:LogsDir 'P12_release_assessment.json'
        $assessment = [pscustomobject][ordered]@{
            SchemaVersion='P12-release-assessment/1.2'
            CreatedAtUtc=([datetime]::UtcNow.ToString('o'))
            Identity=$identity
            StaticVerification=$staticVerification
            Pca2023Compliance=$compliance
            AuxiliaryFreshness=$freshness
            BootValidation=$bootValidation
            ReleaseEligibility=$Script:ReleaseEligibility
        }
        Save-CanonicalJsonFile -InputObject $assessment -Path $assessmentPath -Depth 18
        $eligibilityPath=Join-Path $Script:LogsDir 'release_eligibility.json'
        Save-CanonicalJsonFile -InputObject $Script:ReleaseEligibility -Path $eligibilityPath -Depth 12
        Save-ReleaseEvidenceIndex | Out-Null
        Write-Step ('PCA2023 policy: {0}; StaticEligible={1}; BootTest={2}; ReleaseEligible={3}' -f $policy, $staticEligible, $bootValidation.Status, $releaseEligible)
        if (-not $staticEligible) {
            Write-ReleaseEvidenceMarker -Name 'P12.failed' -Identity $identity -EvidencePath $assessmentPath -Status 'Fail' | Out-Null
            $Script:DeferredVerificationFailure = ('P12 static release evidence failed: {0}' -f (($reasons.ToArray()) -join '; '))
            Write-Fail $Script:DeferredVerificationFailure
        } else {
            Write-ReleaseEvidenceMarker -Name 'P12.ok' -Identity $identity -EvidencePath $assessmentPath -Status 'Pass' | Out-Null
        }
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

        if ($Script:ReleaseEligibility) {
            Write-SubSection 'Release Eligibility'
            Write-Step ('BuildSucceeded          : {0}' -f $Script:ReleaseEligibility.BuildSucceeded)
            Write-Step ('StaticVerificationStatus: {0}' -f $Script:ReleaseEligibility.StaticVerificationStatus)
            Write-Step ('Pca2023Compliance       : {0} ({1})' -f $Script:ReleaseEligibility.Pca2023Compliance, $Script:ReleaseEligibility.Pca2023Policy)
            Write-Step ('AuxiliaryFreshness      : {0}' -f $Script:ReleaseEligibility.AuxiliaryFreshness)
            if ($Script:ReleaseEligibility.PSObject.Properties['AuxiliaryApplicability']) { Write-Step ('AuxiliaryApplicability  : {0} (applicable={1}; notApplicable={2})' -f $Script:ReleaseEligibility.AuxiliaryApplicability,$Script:ReleaseEligibility.AuxiliaryApplicableItemCount,$Script:ReleaseEligibility.AuxiliaryNotApplicableItemCount) }
            Write-Step ('StaticEligible          : {0}' -f $Script:ReleaseEligibility.StaticEligible)
            Write-Step ('BootTestStatus          : {0}' -f $Script:ReleaseEligibility.BootTestStatus)
            Write-Step ('BootTestEligible        : {0}' -f $Script:ReleaseEligibility.BootTestEligible)
            if ($Script:ReleaseEligibility.PSObject.Properties['BootValidationRequired']) { Write-Step ('BootValidationRequired  : {0}' -f $Script:ReleaseEligibility.BootValidationRequired) }
            Write-Step ('ReleaseStatus           : {0}' -f $Script:ReleaseEligibility.ReleaseStatus)
            Write-Step ('ReleaseEligible         : {0}' -f $Script:ReleaseEligibility.ReleaseEligible)
            if ($Script:ReleaseEligibility.PSObject.Properties['HyperVValidation']) {
                Write-Step ('HyperVValidation      : {0}' -f $Script:ReleaseEligibility.HyperVValidation)
            }
            foreach ($reason in @($Script:ReleaseEligibility.Reasons)) { Write-Step ('  - {0}' -f $reason) }
        }

        # ---- Media inspection diff + observe-first cross-checks ----
        # Requires both artifacts of the same run: P06 wrote
        # inspection_pre.json, P11 wrote inspection_post.json.
        $preJsonPath  = Join-Path $Script:LogsDir 'inspection_pre.json'
        $postJsonPath = Join-Path $Script:LogsDir 'inspection_post.json'
        if ((Test-Path -LiteralPath $preJsonPath) -and (Test-Path -LiteralPath $postJsonPath)) {
            Set-DebugStep -Step 'inspection-diff'
            Write-SubSection 'Media Inspection Diff (pre -> post)'
            try {
                $preObj  = Get-Content -LiteralPath $preJsonPath -Raw | ConvertFrom-Json
                $postObj = Get-Content -LiteralPath $postJsonPath -Raw | ConvertFrom-Json
                $diff = Compare-MediaInspection -Pre $preObj -Post $postObj
                $diffPath = Join-Path $Script:LogsDir 'inspection_diff.json'
                $diff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $diffPath -Encoding UTF8
                foreach ($w in @($diff.Wims)) {
                    foreach ($ix in @($w.Indexes)) {
                        $bb = if ($ix.BuildBefore) { $ix.BuildBefore } else { '(none)' }
                        $ba = if ($ix.BuildAfter)  { $ix.BuildAfter }  else { '(none)' }
                        Write-Step ('  {0} idx {1}: build {2} -> {3}; packages {4} -> {5}; 2024-4B prereq {6} -> {7}' -f `
                            $w.Wim, $ix.Index, $bb, $ba, $ix.PackageCountBefore, $ix.PackageCountAfter, $ix.PrereqBefore, $ix.PrereqAfter)
                    }
                }
                Write-Ok ('Inspection diff written: {0}' -f $diffPath)

                # observe-first: measured vs declared. Warnings are
                # RECORDED (console + errors.jsonl), never gated here.
                $obsPolicy = Resolve-BootWimLcuPolicyValue -RawValue $Script:OsProfile.BootWimLcuPolicy
                $obsBridgeMin = $null
                if ($Script:OsProfile.PSObject.Properties['PatchBaseline'] -and $Script:OsProfile.PatchBaseline -and
                    $Script:OsProfile.PatchBaseline.PSObject.Properties['BridgeLcu'] -and $Script:OsProfile.PatchBaseline.BridgeLcu -and
                    $Script:OsProfile.PatchBaseline.BridgeLcu.PSObject.Properties['MinimumImageServicingStack']) {
                    $obsBridgeMin = [string]$Script:OsProfile.PatchBaseline.BridgeLcu.MinimumImageServicingStack
                }
                $preInstall0 = @($preObj.InstallWim.Indexes) | Select-Object -First 1
                $preBoot0    = @($preObj.BootWim.Indexes) | Select-Object -First 1
                $postBoot0   = @($postObj.BootWim.Indexes) | Select-Object -First 1
                $findings = Get-InspectionCrossChecks -BootWimLcuPolicy $obsPolicy -BridgeMinimumStack $obsBridgeMin `
                    -PreInstallBuild $(if ($preInstall0 -and $preInstall0.Evidence) { $preInstall0.Evidence.Build } else { $null }) `
                    -PreBootBuild $(if ($preBoot0 -and $preBoot0.Evidence) { $preBoot0.Evidence.Build } else { $null }) `
                    -PostBootBuild $(if ($postBoot0 -and $postBoot0.Evidence) { $postBoot0.Evidence.Build } else { $null })
                foreach ($fd in @($findings)) {
                    if ($fd.Level -eq 'Warning') {
                        Write-Caution ('observe-first [{0}]: {1}' -f $fd.Kind, $fd.Message)
                        Add-ErrorJsonlEntry -Phase 'P13' -Kind 'warning' -Properties @{
                            subsystem = 'observe-first'; check = $fd.Kind; message = $fd.Message
                        }
                    } else {
                        Write-Step ('observe-first [{0}]: {1}' -f $fd.Kind, $fd.Message)
                    }
                }
            } catch {
                Write-Caution ('Inspection diff failed: {0}' -f $_.Exception.Message)
            }
        }

        if ($Script:DeferredVerificationFailure) {
            New-Item -ItemType File -Path (Join-Path $Script:MarkersDir 'P13.failed') -Force | Out-Null
            throw $Script:DeferredVerificationFailure
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
            Write-Host ('        {0,-12} {1,-20} {2}' -f $osKey, '(missing)', '(no Pca2023 block)') -ForegroundColor DarkGray
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

function Build-ConfigSkeletonFromSeed {
    <#
    .SYNOPSIS
        Lay a SEED profile (data/seed/seed-Server<os>.json) into the full
        config shape, with the DERIVED regions as empty placeholders in
        their canonical key positions.
    .DESCRIPTION
        The single new structural step of A00 RebuildDataset (SPEC B.14.1).
        The seed carries every SEED region (Schema/OsKey/PatchModel, Common,
        the PatchBaseline envelope, Pca2023, AutoRefreshPolicy, and each
        language's DisplayName/Iso/VolumeLabelPrefix). This function copies
        those through and adds empty placeholders for the DERIVED regions --
        PatchBaseline.Lines and its refresh stamps, every
        LanguageSpecificPatches block, and _meta -- positioned so the normal
        refresh path fills them in place: A01 RefreshAllBaselines (Force)
        populates Lines / LanguageSpecificPatches / stamps, and
        Save-ConfigWithBaseline fills _meta. Building the placeholders in
        canonical order keeps the rebuilt config byte-aligned with the
        committed structure (only the regenerated content differs).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] $Seed)

    # TargetBuildAfterUpdate is DERIVED (the LCU Line's InScope.build,
    # filled wherever Lines are written) and is therefore initialized
    # empty here, never copied from seed. The seed PatchBaseline envelope
    # carries Schema + ChecksumAlgorithm + (optionally) BridgeLcu; every
    # envelope member must have a live reader -- reader-less seed fields
    # rot silently (history: CHANGELOG, tag 'tbau-derived-lcu-verify').
    $patchBaseline = [ordered]@{
        Schema                 = $Seed.PatchBaseline.Schema
        TargetBuildAfterUpdate = ''
        ChecksumAlgorithm      = $Seed.PatchBaseline.ChecksumAlgorithm
        LastVerifiedDate       = ''
        LastVerifiedBy         = ''
        PatchTuesdayOfBaseline = ''
        Lines                  = @()
    }
    # BridgeLcu is a SEED envelope member (static servicing policy,
    # axis-3 floor bridge; reader: ConvertTo-BridgeLcuResolvedPatch
    # via both P02 ResolvedPatches writers). Copied through verbatim,
    # positioned after ChecksumAlgorithm to match the committed
    # canonical key order; omitted entirely when the seed lacks it.
    if ($Seed.PatchBaseline.PSObject.Properties['BridgeLcu'] -and $Seed.PatchBaseline.BridgeLcu) {
        $withBridge = [ordered]@{}
        foreach ($k in $patchBaseline.Keys) {
            $withBridge[$k] = $patchBaseline[$k]
            if ($k -eq 'ChecksumAlgorithm') {
                $withBridge['BridgeLcu'] = $Seed.PatchBaseline.BridgeLcu
            }
        }
        $patchBaseline = $withBridge
    }

    $languageSpecific = [ordered]@{}
    foreach ($entry in $Seed.LanguageSpecific.PSObject.Properties) {
        $languageSpecific[$entry.Name] = [ordered]@{
            DisplayName             = $entry.Value.DisplayName
            Iso                     = $entry.Value.Iso
            VolumeLabelPrefix       = $entry.Value.VolumeLabelPrefix
            LanguageSpecificPatches = [ordered]@{
                LanguagePacks          = @()
                LxpUpdates             = @()
                DotNetLanguagePacks    = @()
                LastVerifiedDate       = ''
                LastVerifiedBy         = ''
                PatchTuesdayOfBaseline = ''
            }
        }
    }

    return [ordered]@{
        Schema            = $Seed.Schema
        OsKey             = $Seed.OsKey
        Common            = $Seed.Common
        PatchBaseline     = $patchBaseline
        Pca2023           = $Seed.Pca2023
        AutoRefreshPolicy = $Seed.AutoRefreshPolicy
        LanguageSpecific  = $languageSpecific
        _meta             = ''
        PatchModel        = $Seed.PatchModel
    }
}

function Invoke-AdminPhaseA00_RebuildDataset {
    <#
    .SYNOPSIS
        Canonical rebuild entry point for the data/ dataset (SPEC B.14.1).
        Rebuilds data/config-Server*.json from the committed seeds
        (data/seed/seed-Server*.json) plus upstream caches, runnable from
        empty (no pre-existing config required). Honours -PatchMonth and
        -OnlyOs. An osLessAction (takes no -OsVersion).
    .DESCRIPTION
        Stages, in order:
          0. Validate seeds -- each in-scope seed exists, parses, and its
             OsKey matches the filename.
          1. Snapshots      -- Invoke-AdminPhaseA03_RefreshSnapshots fills
             the upstream caches under data/.
          2. Build config   -- Build-ConfigSkeletonFromSeed lays each seed
             into the config shape with empty DERIVED placeholders, written
             to data/config-Server<os>.json.
          3. Fill DERIVED   -- Invoke-AdminPhaseA01_RefreshAllBaselines runs
             in Force mode, populating PatchBaseline.Lines, every
             LanguageSpecificPatches, the refresh stamps and _meta in place.
          4. Verify         -- each built config exists and carries a
             non-empty PatchBaseline.Lines.
        This action is a pure orchestrator: it owns no DebugTrace of its own
        (A03 and A01 each manage theirs sequentially). Stage 1/3 perform
        network acquisition, so the whole action is long-running and is run
        detached + polled per the data-generation hazard policy, never
        synchronously inside an interactive turn.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Write-SubSection 'A00 RebuildDataset'

    if ([string]::IsNullOrEmpty($Script:PatchMonth)) {
        throw 'RebuildDataset requires -PatchMonth <yyyy-MM>: the rebuild is pinned to a patch month.'
    }
    $dataRoot = Join-Path $Script:ScriptRoot 'data'
    $seedRoot = Join-Path $dataRoot 'seed'
    if (-not (Test-Path -LiteralPath $seedRoot)) {
        throw ('Seed root not found: {0}' -f $seedRoot)
    }

    $allOsKeys = @('Server2016', 'Server2019', 'Server2022', 'Server2025')
    $targetOsKeys = $allOsKeys
    if ($Script:OnlyOs) { $targetOsKeys = @($Script:OnlyOs) }

    # ---- Stage 0: validate seeds ----
    Write-SubSection 'Stage 0: Validate seeds'
    $seeds = [ordered]@{}
    foreach ($osKey in $targetOsKeys) {
        $seedFile = Join-Path $seedRoot ('seed-' + $osKey + '.json')
        if (-not (Test-Path -LiteralPath $seedFile)) {
            throw ('Seed not found: {0} (the dataset cannot be rebuilt without it).' -f $seedFile)
        }
        $seed = Get-Content -LiteralPath $seedFile -Raw -Encoding UTF8 | ConvertFrom-CanonicalJson
        if ($seed.OsKey -ne $osKey) {
            throw ('Seed OsKey mismatch in {0}: OsKey="{1}" expected "{2}".' -f $seedFile, $seed.OsKey, $osKey)
        }
        $seeds[$osKey] = $seed
        Write-Ok ('Seed OK: {0}' -f $seedFile)
    }

    # ---- Stage 1: snapshots (caches) ----
    Write-SubSection 'Stage 1: RefreshSnapshots (caches)'
    Invoke-AdminPhaseA03_RefreshSnapshots

    # ---- Stage 2: build config skeletons from seeds ----
    Write-SubSection 'Stage 2: Build config from seed'
    foreach ($osKey in $targetOsKeys) {
        $cfgPath  = Join-Path $dataRoot ('config-' + $osKey + '.json')
        $skeleton = Build-ConfigSkeletonFromSeed -Seed $seeds[$osKey]
        Save-CanonicalJsonFile -InputObject $skeleton -Path $cfgPath -Depth 32
        Write-Ok ('Config skeleton written: {0}' -f $cfgPath)
    }

    # ---- Stage 3: fill DERIVED groups via the normal refresh (Force) ----
    Write-SubSection 'Stage 3: RefreshAllBaselines (Force)'
    $previousMode = $Script:Mode
    $Script:Mode = 'Force'
    try {
        $refreshOk = Invoke-AdminPhaseA01_RefreshAllBaselines
    } finally {
        $Script:Mode = $previousMode
    }
    if (-not $refreshOk) {
        throw 'RebuildDataset: RefreshAllBaselines reported unresolved groups; dataset is incomplete.'
    }

    # ---- Stage 4: verify ----
    Write-SubSection 'Stage 4: Verify'
    $allOk = $true
    foreach ($osKey in $targetOsKeys) {
        $cfgPath = Join-Path $dataRoot ('config-' + $osKey + '.json')
        if (-not (Test-Path -LiteralPath $cfgPath)) {
            Write-Caution ('Missing built config: {0}' -f $cfgPath)
            $allOk = $false
            continue
        }
        $built = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-CanonicalJson
        $lineCount = @($built.PatchBaseline.Lines).Count
        if ($lineCount -lt 1) {
            Write-Caution ('{0}: PatchBaseline.Lines is empty after rebuild.' -f $osKey)
            $allOk = $false
        } else {
            Write-Ok ('{0}: {1} PatchBaseline Line(s).' -f $osKey, $lineCount)
        }
    }
    if (-not $allOk) {
        throw 'RebuildDataset: one or more configs did not rebuild cleanly (see cautions above).'
    }
    Write-Ok 'RebuildDataset complete.'
    return $true
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

        $reportRows = [System.Collections.Generic.List[object]]::new()
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
        #                              (or $null when the Config lacks a Pca2023 block)
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
                ManualGroups     = [System.Collections.Generic.List[string]]::new()
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
                                                                              -PatchMonth $patchMonth `
                                                                              -MaxRetries 3)
                                    $patchCount = $patches.Count
                                    if (-not $Script:DryRun -and $patchCount -gt 0) {
                                        $raw.PatchBaseline.Lines = $patches
                                        # DERIVED TargetBuildAfterUpdate: must be set wherever
                                        # Lines are (re)written -- this A00/A01 path AND the
                                        # in-memory refresh writeback both derive via the
                                        # single pure helper (a writer that skips this ships
                                        # an empty value; T31 pins both call sites).
                                        $raw.PatchBaseline.TargetBuildAfterUpdate = Get-TargetBuildFromLines -Lines $patches
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
            # Tracks the config-schema generation this classification
            # describes (v3.0, the Catalog data-source generation).
            Schema       = '3.0'
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
        Two sub-steps, each independently fault-tolerant:

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
        Write-SubSection '[1/2] release-info (Microsoft Learn)'
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
        Write-SubSection '[2/2] .NET Framework CU (Microsoft Learn)'
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
        # Summary block (mirrors A01's "Summary" rendering for parity)
        # ============================================================
        Show-RefreshSnapshotsSummary `
            -ReleaseInfo $releaseInfoResult `
            -DotNetCu    $dotnetResult `
            -PatchMonth  $patchMonth `
            -LatestPt    $latestPt `
            -OkOverall   $okOverall

        # CSV report (parity with A01_RefreshAllBaselines_report.csv)
        try {
            $reportPath = Join-Path $Script:LogsDir 'A03_RefreshSnapshots_report.csv'
            $reportRows = [System.Collections.Generic.List[object]]::new()
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
    Write-Host '  [2] Patch Tuesday timeline'
    Write-Host ('        This run baseline   : {0}  (Patch Month = {1})' -f $LatestPt, $PatchMonth)
    Write-Host ''
    Write-Host '  [3] Run outcome'
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

function Restore-BootWimFromSourceIso {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DestinationPath)
    if (-not (Test-Path -LiteralPath $Script:IsoLocalPath -PathType Leaf)) {
        throw ('Source ISO required to restore boot.wim is missing: {0}' -f $Script:IsoLocalPath)
    }
    $img = Mount-DiskImage -ImagePath $Script:IsoLocalPath -StorageType ISO -PassThru -ErrorAction Stop
    try {
        Start-Sleep -Seconds 1
        $vol = $img | Get-Volume
        if (-not $vol.DriveLetter) { throw 'Mounted source ISO has no drive letter.' }
        $src = ($vol.DriveLetter + ':\sources\boot.wim')
        if (-not (Test-Path -LiteralPath $src)) { throw ('Source ISO boot.wim missing: {0}' -f $src) }
        Copy-Item -LiteralPath $src -Destination $DestinationPath -Force
    } finally {
        Dismount-DiskImage -ImagePath $Script:IsoLocalPath -ErrorAction SilentlyContinue | Out-Null
    }
}


function Set-ResumePatchProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Patch,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )
    if ($Patch.PSObject.Properties[$Name]) {
        $Patch.$Name = $Value
    } else {
        $Patch | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Restore-ResolvedPatchAssetsForResume {
    <#
    .SYNOPSIS
        Rehydrate P02 runtime patch objects from the measured P04/P11 evidence
        and the patch payloads retained under the existing WorkRoot.
    .DESCRIPTION
        P01/P02 intentionally rebuild runtime objects from immutable config.
        On -ResumeFromPhase P08/P09 that leaves monthly auxiliary entries in
        their pre-P04 metadata-only state.  P09 therefore used to reject an
        existing Setup DU even though the previous run had resolved, hashed,
        downloaded, and applied it.

        This function restores only identities that are independently bound by:
          - one P04 Catalog row for the same OS, KB, and servicing type;
          - one prior resolved-patch manifest row for the same file;
          - one exact local file below <WorkRoot>\patches\<OS>;
          - a SHA-256 match against the prior manifest.

        Missing, duplicate, mismatched, non-HTTPS, unexpected-host, or
        out-of-workspace evidence fails closed.  No network lookup is performed
        and no payload is silently substituted during resume.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][ValidateSet('P08','P09')][string]$PhaseId)

    $catalogPath = Join-Path $Script:LogsDir 'P04_catalog_crosscheck.json'
    $manifestPath = Join-Path $Script:LogsDir 'resolved_patch_manifest.json'
    foreach ($requiredPath in @($catalogPath,$manifestPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw ('Resume refused: required measured patch evidence is missing: {0}' -f $requiredPath)
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Script:MarkersDir 'P04.ok') -PathType Leaf)) {
        throw 'Resume refused: P04.ok is missing; resolved patch assets cannot be trusted.'
    }

    $catalogRows = @(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-CanonicalJson)
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-CanonicalJson
    if (-not $manifest -or -not $manifest.PSObject.Properties['Patches']) {
        throw ('Resume refused: resolved patch manifest is invalid: {0}' -f $manifestPath)
    }

    $currentBaselineId = if ($Script:OsProfile -and $Script:OsProfile.PatchBaseline) { [string]$Script:OsProfile.PatchBaseline.BaselineId } else { '' }
    foreach ($identityCheck in @(
        [pscustomobject]@{ Name='OsKey'; Expected=[string]$Script:OsVersion; Actual=[string]$manifest.OsKey },
        [pscustomobject]@{ Name='OsLanguage'; Expected=[string]$Script:OsLanguage; Actual=[string]$manifest.OsLanguage },
        [pscustomobject]@{ Name='BaselineId'; Expected=$currentBaselineId; Actual=[string]$manifest.BaselineId }
    )) {
        if ([string]::IsNullOrWhiteSpace($identityCheck.Actual) -or $identityCheck.Expected -ne $identityCheck.Actual) {
            throw ('Resume refused: patch manifest {0} mismatch (expected="{1}" actual="{2}").' -f $identityCheck.Name,$identityCheck.Expected,$identityCheck.Actual)
        }
    }

    $osPatchDir = Join-Path $Script:PatchesDir $Script:OsVersion
    if (-not (Test-Path -LiteralPath $osPatchDir -PathType Container)) {
        throw ('Resume refused: OS patch directory is missing: {0}' -f $osPatchDir)
    }
    $osPatchRoot = [System.IO.Path]::GetFullPath($osPatchDir).TrimEnd('\') + '\'
    $restored = [System.Collections.Generic.List[object]]::new()

    foreach ($patch in @($Script:ResolvedPatches)) {
        if (-not $patch -or [string]::IsNullOrWhiteSpace([string]$patch.KbId)) { continue }
        $kbId = [string]$patch.KbId
        $patchType = Get-PatchEntryType -Patch $patch
        $catalogMatches = @($catalogRows | Where-Object {
            [string]$_.KbId -eq $kbId -and [string]$_.Kind -eq $patchType -and
            [string]$_.OsKey -eq [string]$Script:OsVersion
        })
        if ($catalogMatches.Count -ne 1) {
            throw ('Resume refused: expected exactly one P04 Catalog evidence row for {0}/{1}; found {2}.' -f $patchType,$kbId,$catalogMatches.Count)
        }
        $catalog = $catalogMatches[0]
        if ([bool]$catalog.MetadataOnly) {
            throw ('Resume refused: P04 evidence still marks {0}/{1} as metadata-only.' -f $patchType,$kbId)
        }

        $fileName = [string]$catalog.FileName
        if ([string]::IsNullOrWhiteSpace($fileName) -or [System.IO.Path]::GetFileName($fileName) -ne $fileName) {
            throw ('Resume refused: unsafe or empty Catalog file name for {0}/{1}: "{2}".' -f $patchType,$kbId,$fileName)
        }
        $source = [string]$catalog.Source
        try { $sourceUri = [uri]$source } catch { throw ('Resume refused: invalid Catalog source URI for {0}/{1}: {2}' -f $patchType,$kbId,$source) }
        # PowerShell variable names are case-insensitive.  Do not use `$host`
        # here because it collides with the read-only automatic variable `$Host`.
        $sourceHost = $sourceUri.DnsSafeHost.ToLowerInvariant()
        if ($sourceUri.Scheme -ne 'https' -or
            ($sourceHost -notmatch '(^|\.)download\.windowsupdate\.com$' -and $sourceHost -notmatch '(^|\.)delivery\.mp\.microsoft\.com$')) {
            throw ('Resume refused: untrusted Catalog source host for {0}/{1}: {2}' -f $patchType,$kbId,$sourceUri.Host)
        }

        $manifestMatches = @($manifest.Patches | Where-Object {
            [string]$_.KbId -eq $kbId -and [string]$_.FileName -eq $fileName
        })
        if ($manifestMatches.Count -ne 1) {
            throw ('Resume refused: expected exactly one prior manifest row for {0}/{1}/{2}; found {3}.' -f $patchType,$kbId,$fileName,$manifestMatches.Count)
        }
        $manifestRow = $manifestMatches[0]
        $expectedAssetSha256 = [string]$manifestRow.LocalAssetSha256
        if ($expectedAssetSha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw ('Resume refused: prior manifest has no valid local SHA-256 for {0}/{1}.' -f $patchType,$kbId)
        }
        if ($catalog.PSObject.Properties['UpdateId'] -and $catalog.UpdateId -and
            $manifestRow.PSObject.Properties['UpdateId'] -and $manifestRow.UpdateId -and
            [string]$catalog.UpdateId -ne [string]$manifestRow.UpdateId) {
            throw ('Resume refused: UpdateId mismatch between P04 and prior manifest for {0}/{1}.' -f $patchType,$kbId)
        }
        if ($patch.PSObject.Properties['UpdateId'] -and $patch.UpdateId -and $catalog.UpdateId -and
            [string]$patch.UpdateId -ne [string]$catalog.UpdateId) {
            throw ('Resume refused: current config UpdateId disagrees with measured P04 evidence for {0}/{1}.' -f $patchType,$kbId)
        }

        $preferredPath = Get-PatchLocalPath -Kind $patchType -FileName $fileName
        $localMatches = @()
        if (Test-Path -LiteralPath $preferredPath -PathType Leaf) {
            $localMatches = @((Get-Item -LiteralPath $preferredPath -Force))
        } else {
            $localMatches = @(Get-ChildItem -LiteralPath $osPatchDir -Recurse -File -Force -ErrorAction Stop | Where-Object { $_.Name -ceq $fileName })
        }
        if ($localMatches.Count -ne 1) {
            throw ('Resume refused: expected exactly one local payload for {0}/{1}/{2}; found {3}.' -f $patchType,$kbId,$fileName,$localMatches.Count)
        }
        $localPath = [System.IO.Path]::GetFullPath($localMatches[0].FullName)
        if (-not $localPath.StartsWith($osPatchRoot,[System.StringComparison]::OrdinalIgnoreCase)) {
            throw ('Resume refused: local payload escaped the OS patch workspace: {0}' -f $localPath)
        }
        $actualAssetSha256 = (Get-FileHash -LiteralPath $localPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualAssetSha256 -ne $expectedAssetSha256.ToLowerInvariant()) {
            throw ('Resume refused: local SHA-256 mismatch for {0}/{1}. expected={2} actual={3}' -f $patchType,$kbId,$expectedAssetSha256,$actualAssetSha256)
        }

        $hashes = @{}
        if ($patch.PSObject.Properties['ExpectedHashes'] -and $patch.ExpectedHashes) {
            foreach ($key in $patch.ExpectedHashes.Keys) { $hashes[$key] = $patch.ExpectedHashes[$key] }
        }
        $hashes['sha-256'] = $actualAssetSha256
        Test-PatchIntegrity -FilePath $localPath -ExpectedHashes $hashes | Out-Null

        Set-ResumePatchProperty -Patch $patch -Name 'Source' -Value $source
        Set-ResumePatchProperty -Patch $patch -Name 'FileName' -Value $fileName
        Set-ResumePatchProperty -Patch $patch -Name 'FileNameOrigin' -Value 'ResumeEvidence'
        Set-ResumePatchProperty -Patch $patch -Name 'LocalPath' -Value $localPath
        Set-ResumePatchProperty -Patch $patch -Name 'UpdateId' -Value ([string]$catalog.UpdateId)
        Set-ResumePatchProperty -Patch $patch -Name 'ExpectedHashes' -Value $hashes
        Set-ResumePatchProperty -Patch $patch -Name 'IsMetadataOnly' -Value $false
        Set-ResumePatchProperty -Patch $patch -Name 'State' -Value 'ResolvedFromResumeEvidence'
        foreach ($field in @('CatalogClassification','CatalogProducts','CatalogSelectionBasis','CatalogObservedMetadataStatus','CatalogScopedIdentityVerified','CatalogScopedIdentityBasis','CatalogScopedArchitecture','CatalogScopedRawSha256','CatalogScopedParseBasis')) {
            if ($catalog.PSObject.Properties[$field]) {
                Set-ResumePatchProperty -Patch $patch -Name $field -Value $catalog.$field
            }
        }
        $restored.Add([pscustomobject][ordered]@{
            PatchType=$patchType; KbId=$kbId; UpdateId=[string]$catalog.UpdateId
            FileName=$fileName; LocalPath=$localPath; LocalAssetSha256=$actualAssetSha256
            SourceHost=$sourceUri.Host
        }) | Out-Null
    }

    if ($restored.Count -ne @($Script:ResolvedPatches).Count) {
        throw ('Resume refused: restored patch count {0} does not equal runtime patch count {1}.' -f $restored.Count,@($Script:ResolvedPatches).Count)
    }
    $Script:PatchPlan = Build-PatchPlan -Patches $Script:ResolvedPatches
    $result = [pscustomobject][ordered]@{
        SchemaVersion='resume-patch-state/1.0'; PhaseId=$PhaseId
        RestoredAtUtc=[datetime]::UtcNow.ToString('o')
        OsKey=[string]$Script:OsVersion; OsLanguage=[string]$Script:OsLanguage
        BaselineId=$currentBaselineId; CatalogEvidencePath=$catalogPath
        PriorManifestPath=$manifestPath; RestoredPatchCount=$restored.Count
        Patches=$restored.ToArray()
    }
    $resumePatchStatePath = Join-Path $Script:LogsDir ('resume-{0}-patch-state.json' -f $PhaseId.ToLowerInvariant())
    Save-CanonicalJsonFile -InputObject $result -Path $resumePatchStatePath -Depth 10
    Write-Ok ('Resume patch assets rehydrated and verified: {0} patch(es); evidence: {1}' -f $restored.Count,$resumePatchStatePath)
    return $result
}

function Initialize-ResumeBuildState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('P08','P09')][string]$PhaseId,
        [switch]$ValidateOnly
    )
    Write-SubSection ('Resume validation: {0}' -f $PhaseId)
    $mounted = @(Invoke-DismCmdlet -CommandName 'Get-WindowsImage' -Parameters @{ Mounted=$true; ErrorAction='SilentlyContinue' })
    if ($mounted.Count -gt 0) { throw 'Resume refused: one or more WIM images are currently mounted. Run DISM /Cleanup-Wim first.' }

    $installWim = Join-Path $Script:ExtractedDir 'sources\install.wim'
    $bootWim = Join-Path $Script:ExtractedDir 'sources\boot.wim'
    foreach ($required in @($installWim,$bootWim)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw ('Resume prerequisite missing: {0}' -f $required) }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Script:MarkersDir 'P07.ok'))) { throw 'Resume refused: P07.ok is missing.' }

    # Validate and restore patch state before changing any WIM or marker so a
    # failed resume attempt leaves the previous measured build untouched.
    $resumePatchState = Restore-ResolvedPatchAssetsForResume -PhaseId $PhaseId

    if ($PhaseId -eq 'P08') {
        $stateBackup = Join-Path $Script:StateDir 'p08-backup\boot.wim.pre-p08'
        $canRestoreFromBackup = Test-Path -LiteralPath $stateBackup -PathType Leaf
        if (-not $canRestoreFromBackup) {
            # Validate that the source ISO needed by Restore-BootWimFromSourceIso
            # still exists before a real resume is allowed to mutate boot.wim.
            $sourceIsoCandidate = [string]$Script:IsoPathResolved
            if ([string]::IsNullOrWhiteSpace($sourceIsoCandidate) -or -not (Test-Path -LiteralPath $sourceIsoCandidate -PathType Leaf)) {
                throw ('Resume refused: neither the P08 boot.wim backup nor the source ISO is available. backup={0}; iso={1}' -f $stateBackup,$sourceIsoCandidate)
            }
        }
        if ($ValidateOnly) {
            Write-Step $(if ($canRestoreFromBackup) { 'Resume preflight: P08 boot.wim transaction backup is available; no restore was performed.' } else { 'Resume preflight: source ISO is available for P08 boot.wim restore; no restore was performed.' })
        } else {
            if ($canRestoreFromBackup) {
                Write-Step 'Restoring boot.wim from the P08 transaction backup.'
                Copy-Item -LiteralPath $stateBackup -Destination $bootWim -Force
            } else {
                Write-Step 'No P08 backup exists; restoring boot.wim from the source ISO.'
                Restore-BootWimFromSourceIso -DestinationPath $bootWim
            }
            Remove-Item -LiteralPath (Join-Path $Script:MarkersDir 'P08.ok') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $Script:MarkersDir 'P08S.ok') -Force -ErrorAction SilentlyContinue
        }
    } else {
        if (-not (Test-Path -LiteralPath (Join-Path $Script:MarkersDir 'P08.ok'))) {
            throw 'Resume refused: P08.ok is missing.'
        }
        $syncEvidence = Join-Path $Script:LogsDir 'setup_binaries_sync.json'
        if (-not (Test-Path -LiteralPath $syncEvidence -PathType Leaf)) {
            throw 'Resume refused: setup_binaries_sync.json is missing.'
        }
        $p08sMarker = Join-Path $Script:MarkersDir 'P08S.ok'
        if (-not (Test-Path -LiteralPath $p08sMarker -PathType Leaf)) {
            # r12.04 wrote the authoritative JSON evidence but did not create
            # a P08S marker. Preflight reports the normalization without
            # changing the workspace; the real resume creates it once.
            if ($ValidateOnly) {
                Write-Caution 'Resume preflight: P08S.ok is absent, but setup_binaries_sync.json exists. A real resume will create the compatibility marker.'
            } else {
                Write-Caution 'P08S.ok is absent, but setup_binaries_sync.json exists; accepting r12.04 legacy evidence and creating the marker.'
                New-Item -ItemType File -Path $p08sMarker -Force | Out-Null
            }
        }
    }

    $Script:WimIndexInventory = @(
        @(Invoke-DismCmdlet -CommandName 'Get-WindowsImage' -Parameters @{ ImagePath=$installWim }) | ForEach-Object {
            [pscustomobject]@{ Wim='install.wim'; ImageIndex=$_.ImageIndex; ImageName=$_.ImageName; ImageSize=$_.ImageSize }
        }
        @(Invoke-DismCmdlet -CommandName 'Get-WindowsImage' -Parameters @{ ImagePath=$bootWim }) | ForEach-Object {
            [pscustomobject]@{ Wim='boot.wim'; ImageIndex=$_.ImageIndex; ImageName=$_.ImageName; ImageSize=$_.ImageSize }
        }
    )
    $evPath = Join-Path $Script:LogsDir ('resume-{0}.json' -f $PhaseId.ToLower())
    Save-CanonicalJsonFile -InputObject ([pscustomobject]@{
        Timestamp=(Get-Date).ToString('o'); ResumeFrom=$PhaseId; OsVersion=$Script:OsVersion
        InstallWimSha256=(Get-FileHash -LiteralPath $installWim -Algorithm SHA256).Hash.ToLower()
        BootWimSha256=(Get-FileHash -LiteralPath $bootWim -Algorithm SHA256).Hash.ToLower()
        RestoredPatchStatePath=(Join-Path $Script:LogsDir ('resume-{0}-patch-state.json' -f $PhaseId.ToLowerInvariant()))
        RestoredPatchCount=$resumePatchState.RestoredPatchCount
        Inventory=$Script:WimIndexInventory
    }) -Path $evPath -Depth 8
    Write-Ok ('Resume state validated: {0}' -f $evPath)
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
    # P10 runs by default (readiness-driven) and self-skips on
    # -SkipPca2023BootManager or the Server 2025 gate; keeping it in
    # the standard pipeline keeps the pipeline-level wiring consistent
    # with the phase-level gates.
    $standardFull = if ($Script:SyntheticTestMode) {
        [string[]]@('P01','P02','P03','P04','P07','P08','P08S','P09','P10','P11','P12','P13')
    } else {
        [string[]]@('P01','P02','P03','P04','P05','P06','P07','P08','P08S','P09','P10','P11','P12','P13')
    }
    if ($Script:RunHyperVValidation -and -not $Script:SyntheticTestMode) { $standardFull = [string[]]@(@($standardFull | Where-Object { $_ -ne 'P13' }) + @('P14','P13')) }
    $standardPrepare = if ($Script:SyntheticTestMode) {
        [string[]]@('P01','P02','P03','P04')
    } else {
        [string[]]@('P01','P02','P03','P04','P05','P06')
    }

    switch ($ActionName) {
        'Prepare'                 { return $standardPrepare }
        'Build'                   { return [string[]]@('P07','P08','P08S','P09','P10') }
        'Verify'                  { return [string[]]@('P11','P12','P13') }
        'PrepareBuildVerify'      { return $standardFull }
        'All'                     { if ($standardFull -contains 'P14') { return $standardFull }; return [string[]]@(@($standardFull | Where-Object { $_ -ne 'P13' }) + @('P14','P13')) }
        'BootTest'                { return [string[]]@('P14') }
        'Cleanup'                 { return [string[]]@() }
        'ListPhases'              { return [string[]]@() }
        'GenerateManifest'        { return [string[]]@('P01','P02','P03') }
        'RebuildDataset'           { return [string[]]@('A00') }
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
            # The phase function's finally block may already have closed its
            # trace frame with the default success outcome before this runner
            # receives the re-thrown exception. Correct the authoritative
            # per-phase registry and append an explicit failure event so raw
            # debugtrace.jsonl cannot misleadingly end with success only.
            if ($Script:DebugTracePhaseRegistry.ContainsKey($entry.Id)) {
                $phaseReg = $Script:DebugTracePhaseRegistry[$entry.Id]
                $phaseReg.Outcome = 'failure'
                $phaseReg.EndedAt = Get-Date
                $failedStep = '(phase runner)'
                if ($phaseReg.Frame -and $phaseReg.Frame.PSObject.Properties['Step']) { $failedStep = [string]$phaseReg.Frame.Step }
                $phaseReg.FailureRef = [pscustomobject]@{
                    FailedStep = $failedStep
                    ExType = $_.Exception.GetType().FullName
                    ExMessage = [string]$_.Exception.Message
                    InnerType = $(if ($_.Exception.InnerException) { $_.Exception.InnerException.GetType().FullName } else { $null })
                    InnerMessage = $(if ($_.Exception.InnerException) { [string]$_.Exception.InnerException.Message } else { $null })
                    FullyQualifiedId = [string]$_.FullyQualifiedErrorId
                    ScriptStackTrace = [string]$_.ScriptStackTrace
                }
                # Stop-DebugTrace may already have retired the phase frame as
                # success in the phase function's finally block.  The registry
                # keeps the same frame reference, so correct the completed-frame
                # outcome as well.
                if ($phaseReg.Frame) {
                    $phaseReg.Frame.Outcome = 'failure'
                    $phaseReg.Frame.EndedAt = $phaseReg.EndedAt
                    $phaseReg.Frame.DurationMs = [int]($phaseReg.EndedAt - $phaseReg.Frame.StartTime).TotalMilliseconds
                }
            }
            _DebugTrace_WriteJsonlLine ([pscustomobject]@{
                ts = _DebugTrace_Now
                kind = 'phase.outcome'
                phase = $entry.Id
                outcome = 'failure'
                msg = [string]$_.Exception.Message
            })
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
# Phase P14: optional Hyper-V validation
# ============================================================
function Invoke-VerifyPhase14_HyperVValidation {
    [CmdletBinding()]
    param()
    Start-DebugTrace -Context 'Invoke-VerifyPhase14_HyperVValidation' -PhaseId 'P14'
    try {
        if ($Action -eq 'BootTest' -or -not $Script:ReleaseEligibility -or -not $Script:OutputIsoPath) {
            Initialize-BootTestState
        }
        $identity = Get-ReleaseEvidenceIdentity
        $path = Join-Path $Script:LogsDir 'P14_hyperv_validation.json'

        # Approval is a second, explicit operation over an already captured
        # BootOnly evidence file. It never reruns or silently replaces evidence.
        if ($Script:BootEvidenceApprovalPath) {
            if($Script:ReleaseEligibility -and $Script:ReleaseEligibility.PSObject.Properties['RequiresInstallValidation'] -and $Script:ReleaseEligibility.RequiresInstallValidation){
                throw 'BootOnly approval cannot satisfy the active boot.wim policy exception. Run P14 with -HyperVValidationMode Install.'
            }
            $approvalPath = Resolve-RelativeToScript $Script:BootEvidenceApprovalPath
            $existing = Read-ReleaseJsonFile -Path $path
            if (-not $existing -or [string]$existing.Mode -ne 'BootOnly' -or -not $existing.Identity) {
                throw 'Boot evidence approval requires an existing identity-bound BootOnly P14_hyperv_validation.json.'
            }
            $existingIdentity = Test-ReleaseEvidenceIdentity -Expected $existing.Identity -Actual $identity
            if (-not $existingIdentity.Match) { throw ('Boot evidence identity mismatch: {0}' -f ($existingIdentity.Mismatches -join '; ')) }
            $artifactCheck = Test-BootEvidenceArtifacts -Evidence $existing
            if (-not $artifactCheck.Valid) { throw ('Boot evidence artifacts are not approvable: {0}' -f ($artifactCheck.Issues -join '; ')) }
            $approval = Test-BootEvidenceApproval -ApprovalPath $approvalPath -EvidencePath $path -Identity $identity
            if (-not $approval.Valid) { throw ('Boot evidence approval rejected: {0}' -f $approval.Reason) }
            $approvalEvidencePath = Join-Path $Script:LogsDir 'P14_boot_evidence_approval.json'
            Save-CanonicalJsonFile -InputObject ([pscustomobject][ordered]@{
                SchemaVersion='P14-boot-approval/1.0'; Identity=$identity
                Approval=$approval.Approval; ApprovedEvidencePath=$path
                ApprovedEvidenceSha256=(Get-FileSha256OrEmpty -Path $path)
            }) -Path $approvalEvidencePath -Depth 14
            Write-ReleaseEvidenceMarker -Name 'P14.ok' -Identity $identity -EvidencePath $path -Status 'Pass' -ApprovalPath $approvalEvidencePath | Out-Null
            Remove-Item -LiteralPath (Join-Path $Script:MarkersDir 'P14.review-required') -Force -ErrorAction SilentlyContinue
            $Script:ReleaseEligibility | Add-Member -NotePropertyName HyperVValidation -NotePropertyValue 'BootEvidenceApproved' -Force
            $Script:ReleaseEligibility.BootTestStatus='Pass'
            $Script:ReleaseEligibility.BootTestEligible=$true
            $Script:ReleaseEligibility | Add-Member -NotePropertyName BootValidationRequired -NotePropertyValue $false -Force
            $Script:ReleaseEligibility.ReleaseEligible=[bool]$Script:ReleaseEligibility.StaticEligible
            $Script:ReleaseEligibility.ReleaseStatus=$(if($Script:ReleaseEligibility.ReleaseEligible){'ReleaseReady'}else{'NotEligible'})
            $Script:ReleaseEligibility.Reasons=@($Script:ReleaseEligibility.Reasons | Where-Object { $_ -notlike '*boot/install validation*' -and $_ -notlike '*Boot evidence*' })
            Save-CanonicalJsonFile -InputObject $Script:ReleaseEligibility -Path (Join-Path $Script:LogsDir 'release_eligibility.json') -Depth 12
            Save-ReleaseEvidenceIndex | Out-Null
            Write-Ok ('P14 BootOnly evidence approved: {0}' -f $approvalEvidencePath)
            return
        }

        $result=Invoke-HyperVBootTest -Mode $Script:HyperVValidationMode
        $result | Add-Member -NotePropertyName Identity -NotePropertyValue $identity -Force
        $screenEvidence = @($result.Screenshots | ForEach-Object {
            [pscustomobject]@{Path=[string]$_;Sha256=(Get-FileSha256OrEmpty -Path ([string]$_))}
        })
        $result | Add-Member -NotePropertyName ScreenshotEvidence -NotePropertyValue $screenEvidence -Force
        Save-CanonicalJsonFile -InputObject $result -Path $path -Depth 16
        if (-not $result.Success) { throw ('P14 Hyper-V validation failed: {0}' -f ($result.Reasons -join '; ')) }

        if ($result.Mode -eq 'BootOnly') {
            Write-ReleaseEvidenceMarker -Name 'P14.review-required' -Identity $identity -EvidencePath $path -Status 'ReviewRequired' | Out-Null
            Remove-Item -LiteralPath (Join-Path $Script:MarkersDir 'P14.ok') -Force -ErrorAction SilentlyContinue
            if ($Script:ReleaseEligibility) {
                $Script:ReleaseEligibility | Add-Member -NotePropertyName HyperVValidation -NotePropertyValue 'BootEvidenceCaptured' -Force
                $Script:ReleaseEligibility.BootTestStatus='ReviewRequired'
                $Script:ReleaseEligibility.BootTestEligible=$false
                $Script:ReleaseEligibility | Add-Member -NotePropertyName BootValidationRequired -NotePropertyValue $true -Force
                $Script:ReleaseEligibility.ReleaseEligible=$false
                $Script:ReleaseEligibility.ReleaseStatus=$(if($Script:ReleaseEligibility.StaticEligible -and $Script:ReleaseEligibility.PSObject.Properties['RequiresInstallValidation'] -and $Script:ReleaseEligibility.RequiresInstallValidation){'Candidate-InstallTestRequired'}elseif($Script:ReleaseEligibility.StaticEligible){'BootEvidenceReviewRequired'}else{'NotEligible'})
                $Script:ReleaseEligibility.Reasons=@($Script:ReleaseEligibility.Reasons | Where-Object { $_ -notlike '*boot/install validation*' }) + @('BootOnly screenshots require explicit operator approval before release.')
            }
            Write-Caution ('P14 BootOnly evidence captured but not release-approved: {0}' -f $path)
        } else {
            Write-ReleaseEvidenceMarker -Name 'P14.ok' -Identity $identity -EvidencePath $path -Status 'Pass' | Out-Null
            Remove-Item -LiteralPath (Join-Path $Script:MarkersDir 'P14.review-required') -Force -ErrorAction SilentlyContinue
            if ($Script:ReleaseEligibility) {
                $Script:ReleaseEligibility | Add-Member -NotePropertyName HyperVValidation -NotePropertyValue 'InstallValidated' -Force
                $Script:ReleaseEligibility.BootTestStatus='Pass'
                $Script:ReleaseEligibility.BootTestEligible=$true
                $Script:ReleaseEligibility | Add-Member -NotePropertyName BootValidationRequired -NotePropertyValue $false -Force
                $Script:ReleaseEligibility.ReleaseEligible=[bool]$Script:ReleaseEligibility.StaticEligible
                $Script:ReleaseEligibility.ReleaseStatus=$(if($Script:ReleaseEligibility.ReleaseEligible){'ReleaseReady'}else{'NotEligible'})
                $Script:ReleaseEligibility.Reasons=@($Script:ReleaseEligibility.Reasons | Where-Object { $_ -notlike '*boot/install validation*' -and $_ -notlike '*BootOnly screenshots*' })
            }
            Write-Ok ('P14 Install validation passed: {0}' -f $path)
        }
        if ($Script:ReleaseEligibility) {
            Save-CanonicalJsonFile -InputObject $Script:ReleaseEligibility -Path (Join-Path $Script:LogsDir 'release_eligibility.json') -Depth 12
            Save-ReleaseEvidenceIndex | Out-Null
        }
    } finally { Stop-DebugTrace }
}

function Convert-Rgb565ThumbnailToBmp {
    <#
    .SYNOPSIS
        Pure: RGB565 thumbnail bytes (Msvm GetVirtualSystemThumbnailImage)
        -> 16bpp BI_BITFIELDS .bmp bytes. GDI-free. Mirror of the
        boot-verification tool set's converter, kept local so this
        script stays single-file.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)] [byte[]]$PixelData,
        [Parameter(Mandatory)] [int]$Width,
        [Parameter(Mandatory)] [int]$Height
    )
    $rowBytes = $Width * 2
    $stride   = [int]([math]::Ceiling($rowBytes / 4.0) * 4)
    $imgSize  = $stride * $Height
    $hdr = 14 + 40 + 12
    $ms = New-Object System.IO.MemoryStream
    $w  = New-Object System.IO.BinaryWriter($ms)
    $w.Write([byte[]](0x42, 0x4D)); $w.Write([uint32]($hdr + $imgSize)); $w.Write([uint32]0); $w.Write([uint32]$hdr)
    $w.Write([uint32]40); $w.Write([int32]$Width); $w.Write([int32]$Height); $w.Write([uint16]1); $w.Write([uint16]16)
    $w.Write([uint32]3); $w.Write([uint32]$imgSize); $w.Write([int32]2835); $w.Write([int32]2835); $w.Write([uint32]0); $w.Write([uint32]0)
    $w.Write([uint32]0xF800); $w.Write([uint32]0x07E0); $w.Write([uint32]0x001F)
    $pad = New-Object byte[] ($stride - $rowBytes)
    for ($y = $Height - 1; $y -ge 0; $y--) {
        $w.Write($PixelData, $y * $rowBytes, $rowBytes)
        if ($pad.Length -gt 0) { $w.Write($pad) }
    }
    $w.Flush()
    return $ms.ToArray()
}

function New-RandomValidationPassword {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $bytes = New-Object byte[] 18
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ('P14!' + [Convert]::ToBase64String($bytes))
}

function Invoke-HyperVBootTest {
    <#
    .SYNOPSIS
        P14 worker. BootOnly captures Gen2 MicrosoftWindows Secure Boot
        console thumbnails for explicit operator review. Install performs an
        unattended evaluation installation and strictly validates build,
        edition, Secure Boot, WinRE, pending packages and pending reboot state.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([ValidateSet('BootOnly','Install')][string]$Mode='BootOnly')

    Write-SubSection ('Hyper-V validation ({0}; Gen2 MicrosoftWindows Secure Boot)' -f $Mode)
    if (-not $Script:OutputIsoPath -or -not (Test-Path -LiteralPath $Script:OutputIsoPath)) {
        throw 'No identity-validated output ISO is available to Hyper-V validation.'
    }
    $vmName = ('UpdateWsi_P14_' + (Get-Date -Format 'yyyyMMddHHmmss'))
    $validationRoot = Join-Path $Script:WorkRoot 'hyperv-validation'
    $vmDir = Join-Path $validationRoot $vmName
    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
    $vhdPath = Join-Path $vmDir ($vmName + '.vhdx')
    $answerIso = $null
    $answerDir = $null
    $guestPassword = New-RandomValidationPassword
    $shots = [System.Collections.Generic.List[string]]::new()
    $reasons = [System.Collections.Generic.List[string]]::new()
    $guestEvidence = $null
    $state = 'Unknown'
    $created = $false
    $expectedBuild = if ($Script:OsProfile -and $Script:OsProfile.PatchBaseline) { [string]$Script:OsProfile.PatchBaseline.TargetBuildAfterUpdate } else { '' }
    $expectedEdition = if ($Script:OsProfile -and $Script:OsProfile.PSObject.Properties['Edition']) { [string]$Script:OsProfile.Edition } else { '' }

    try {
        Set-DebugStep -Step 'create-vm'
        New-VHD -Path $vhdPath -SizeBytes 64GB -Dynamic | Out-Null
        New-VM -Name $vmName -Generation 2 -MemoryStartupBytes 4GB -VHDPath $vhdPath -Path $vmDir | Out-Null
        $created = $true
        Set-VMProcessor -VMName $vmName -Count 2 | Out-Null
        Add-VMDvdDrive -VMName $vmName -Path $Script:OutputIsoPath | Out-Null
        $dvd = Get-VMDvdDrive -VMName $vmName | Select-Object -First 1

        if ($Mode -eq 'Install') {
            $answerDir = Join-Path $vmDir 'answer'
            New-Item -ItemType Directory -Path $answerDir -Force | Out-Null
            $answerXml = Join-Path $answerDir 'Autounattend.xml'
            $imageIndex = if ($Script:OsProfile -and $Script:OsProfile.InstallWimIndex) { [int]$Script:OsProfile.InstallWimIndex } else { 4 }
            $lang = if ($Script:OsLanguage) { [string]$Script:OsLanguage } else { 'en-us' }
            $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>$lang</UILanguage></SetupUILanguage>
      <InputLocale>$lang</InputLocale><SystemLocale>$lang</SystemLocale><UILanguage>$lang</UILanguage><UserLocale>$lang</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DiskConfiguration><Disk wcm:action="add"><DiskID>0</DiskID><WillWipeDisk>true</WillWipeDisk>
        <CreatePartitions>
          <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition>
          <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
          <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
        </CreatePartitions>
        <ModifyPartitions>
          <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
          <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
        </ModifyPartitions>
      </Disk></DiskConfiguration>
      <ImageInstall><OSImage><InstallFrom><MetaData wcm:action="add"><Key>/IMAGE/INDEX</Key><Value>$imageIndex</Value></MetaData></InstallFrom><InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo></OSImage></ImageInstall>
      <UserData><AcceptEula>true</AcceptEula></UserData>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE><HideEULAPage>true</HideEULAPage><ProtectYourPC>3</ProtectYourPC></OOBE>
      <UserAccounts><AdministratorPassword><Value>$guestPassword</Value><PlainText>true</PlainText></AdministratorPassword></UserAccounts>
    </component>
  </settings>
</unattend>
"@
            Set-Content -LiteralPath $answerXml -Value $xml -Encoding UTF8
            $answerIso = Join-Path $vmDir 'answer.iso'
            $p14Oscdimg = Resolve-OscdimgPath
            if (-not $p14Oscdimg) { throw 'oscdimg.exe is required to create the P14 answer ISO.' }
            & $p14Oscdimg -n -m $answerDir $answerIso | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $answerIso)) { throw 'Could not create Hyper-V answer ISO.' }
            Add-VMDvdDrive -VMName $vmName -Path $answerIso | Out-Null
        }

        Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows | Out-Null
        Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter | Out-Null
        Start-VM -Name $vmName | Out-Null

        Set-DebugStep -Step 'boot-and-observe'
        $t0 = Get-Date
        foreach ($sec in @(30,90,180)) {
            $wait = $sec - [int](New-TimeSpan -Start $t0 -End (Get-Date)).TotalSeconds
            if ($wait -gt 0) { Start-Sleep -Seconds $wait }
            try {
                $ns='root\virtualization\v2'
                $vm=Get-CimInstance -Namespace $ns -ClassName Msvm_ComputerSystem -Filter ("ElementName='{0}'" -f $vmName)
                $svc=Get-CimInstance -Namespace $ns -ClassName Msvm_VirtualSystemManagementService
                $r=Invoke-CimMethod -InputObject $svc -MethodName GetVirtualSystemThumbnailImage -Arguments @{ HeightPixels=[uint16]480; WidthPixels=[uint16]640; TargetSystem=$vm }
                if ($r -and $r.ReturnValue -eq 0 -and $r.ImageData) {
                    $bmp=Convert-Rgb565ThumbnailToBmp -PixelData ([byte[]]$r.ImageData) -Width 640 -Height 480
                    $shotPath=Join-Path $Script:LogsDir ('P14_console_{0}s.bmp' -f $sec)
                    [System.IO.File]::WriteAllBytes($shotPath,$bmp); $shots.Add($shotPath) | Out-Null
                    Write-Step ('Console screenshot at {0}s: {1}' -f $sec,$shotPath)
                }
            } catch { Write-Caution ('Console screenshot at {0}s failed: {1}' -f $sec,$_.Exception.Message) }
        }
        $state=[string](Get-VM -Name $vmName).State

        if ($Mode -eq 'Install') {
            Set-DebugStep -Step 'wait-for-install'
            $cred=New-Object System.Management.Automation.PSCredential('Administrator',(ConvertTo-SecureString $guestPassword -AsPlainText -Force))
            $deadline=(Get-Date).AddMinutes(60)
            while ((Get-Date) -lt $deadline -and -not $guestEvidence) {
                Start-Sleep -Seconds 30
                try {
                    $guestEvidence=Invoke-Command -VMName $vmName -Credential $cred -ErrorAction Stop -ScriptBlock {
                        $cv=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
                        $secure=$false; try { $secure=Confirm-SecureBootUEFI } catch { $secure=$false }
                        $reagent=(reagentc.exe /info | Out-String)
                        $winReEnabled=($LASTEXITCODE -eq 0) -and ($reagent -match '(?im)Windows RE status\s*:\s*Enabled|Windows RE の状態\s*:\s*有効')
                        $pendingPackages=@(Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageState -eq 'InstallPending' }).Count
                        $pendingReboot=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
                        [pscustomobject]@{
                            Build=('{0}.{1}' -f $cv.CurrentBuildNumber,$cv.UBR)
                            Edition=$cv.EditionID
                            SecureBoot=$secure
                            WinReEnabled=$winReEnabled
                            WinReInfo=$reagent
                            PendingPackageCount=[int]$pendingPackages
                            PendingReboot=[bool]$pendingReboot
                            Timestamp=(Get-Date).ToString('o')
                        }
                    }
                } catch { $guestEvidence=$null }
            }
            if (-not $guestEvidence) {
                $reasons.Add('Unattended installation did not become reachable through PowerShell Direct within the validation window.') | Out-Null
            } else {
                $buildPass=$false
                if ([string]::IsNullOrWhiteSpace($expectedBuild)) { $reasons.Add('Expected TargetBuildAfterUpdate is unavailable.') | Out-Null }
                else { try { $buildPass=([version]$guestEvidence.Build -ge [version]$expectedBuild) } catch { $buildPass=$false } }
                if (-not $buildPass) { $reasons.Add(('Installed build {0} is below expected build {1}.' -f $guestEvidence.Build,$expectedBuild)) | Out-Null }
                if ($expectedEdition -and ([string]$guestEvidence.Edition -notlike ('*' + $expectedEdition + '*'))) { $reasons.Add(('Installed edition {0} does not match expected edition {1}.' -f $guestEvidence.Edition,$expectedEdition)) | Out-Null }
                if (-not $guestEvidence.SecureBoot) { $reasons.Add('Installed guest reported Secure Boot disabled.') | Out-Null }
                if (-not $guestEvidence.WinReEnabled) { $reasons.Add('Installed guest did not report Windows RE enabled.') | Out-Null }
                if ([int]$guestEvidence.PendingPackageCount -ne 0) { $reasons.Add(('Installed guest has {0} InstallPending packages.' -f $guestEvidence.PendingPackageCount)) | Out-Null }
                if ([bool]$guestEvidence.PendingReboot) { $reasons.Add('Installed guest has a pending reboot condition.') | Out-Null }
            }
        } elseif ($shots.Count -eq 0) {
            $reasons.Add('No console screenshots were captured.') | Out-Null
        } else {
            $reasons.Add('BootOnly evidence requires explicit operator approval; screenshots never directly produce ReleaseReady.') | Out-Null
        }

        $success = if ($Mode -eq 'Install') { [bool]($guestEvidence -and $reasons.Count -eq 0) } else { $shots.Count -gt 0 }
        return [pscustomobject][ordered]@{
            SchemaVersion='P14-hyperv-validation/1.1'
            Success=$success; Mode=$Mode; VmName=$vmName; VmState=$state
            OutputIsoPath=$Script:OutputIsoPath
            OutputIsoSha256=(Get-FileSha256OrEmpty -Path $Script:OutputIsoPath)
            ExpectedBuild=$expectedBuild; ExpectedEdition=$expectedEdition
            Screenshots=$shots.ToArray(); GuestEvidence=$guestEvidence
            RequiresOperatorReview=($Mode -eq 'BootOnly'); Reasons=$reasons.ToArray()
        }
    } finally {
        $guestPassword=$null
        if ($created) {
            try { Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null } catch { $null=$_ }
            try { Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue | Out-Null } catch { $null=$_ }
        }
        if ($answerIso -and (Test-Path -LiteralPath $answerIso)) { Remove-Item -LiteralPath $answerIso -Force -ErrorAction SilentlyContinue }
        if ($answerDir -and (Test-Path -LiteralPath $answerDir)) { Remove-Item -LiteralPath $answerDir -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $vhdPath) { Remove-Item -LiteralPath $vhdPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $vmDir) { Remove-Item -LiteralPath $vmDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

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

# Optional -LogFile transcript. Transcript creation is deliberately delayed
# until after -CleanWorkRoot has completed and the workspace directories have
# been recreated. This prevents a workspace-contained transcript from being
# deleted immediately after Start-Transcript.
$Script:TranscriptStarted = $false
function Start-RunTranscript {
    [CmdletBinding()]
    param()
    if (-not $Script:LogFile -or $Script:TranscriptStarted) { return }
    $logParent = [System.IO.Path]::GetDirectoryName($Script:LogFile)
    if (-not (Test-Path -LiteralPath $logParent)) {
        New-Item -ItemType Directory -Path $logParent -Force | Out-Null
    }
    try {
        # psa-disable-next-line PSA3005 -- Start-Transcript has no -LiteralPath parameter; -Path is the only option in PS 5.1/7
        Start-Transcript -Path $Script:LogFile -Append -Force | Out-Null
        $Script:TranscriptStarted = $true
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
# invariants (e.g. that `Select-CanonicalPatchFile` filters out the
# Express LCU variant). It is intentionally a
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

# Quick branch for actions that do not need workspace init
if ($Action -eq 'ListPhases') {
    Show-EntryBanner
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
    if ($Script:CleanWorkRoot -and (Test-Path -LiteralPath $Script:WorkRoot)) {
        if (Test-DangerousPath -Path $Script:WorkRoot) {
            throw ('Refusing to clean dangerous path: {0}' -f $Script:WorkRoot)
        }
        Remove-Item -LiteralPath $Script:WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Initialize-RuntimeDirectories -Directory @($Script:WorkRoot, $Script:LogsDir)
    Start-RunTranscript
    Show-EntryBanner
    Write-Step ('Pca2023OnlyMode: inspecting {0}' -f $IsoPath)

    # Mount ISO and copy to a scratch dir (we need write access to
    # mount the contained WIMs).
    $scratch = Join-Path $Script:WorkRoot ('pca2023-only\run-{0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().Id))
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
    if ($Script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { $null = $_ }
        $Script:TranscriptStarted = $false
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

Initialize-RuntimeDirectories -Directory @($Script:WorkRoot, $Script:OutputDir, $Script:SourceDir, $Script:IsoSourceDir, $Script:ExtractedDir, $Script:PatchesDir, $Script:ManifestsDir, (Join-Path $Script:WorkRoot 'work'), $Script:TempDir, $Script:ScratchDir, $Script:LogsDir, $Script:DiagDir, $Script:MarkersDir, $Script:StateDir, $script:CatCache)
Start-RunTranscript
Show-EntryBanner

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
    } elseif ($Script:RequestedResumeFromPhase) {
        if ($Script:RequestedResumeFromPhase -eq 'P08') {
            $phaseList = [string[]]@('P01','P02','P08','P08S','P09','P10','P11','P12','P13')
        } else {
            $phaseList = [string[]]@('P01','P02','P09','P10','P11','P12','P13')
        }
    } else {
        $phaseList = Get-PhaseListByAction -ActionName $Action
    }

    # Opt-in Defender exclusions for the servicing run (fail-closed; removed
    # in the finally below).
    Enable-ManagedDefenderExclusion

    if ($phaseList.Count -gt 0) {
        if ($Script:RequestedResumeFromPhase) {
            Invoke-PhaseRunner -PhaseIds @('P01','P02')
            Initialize-ResumeBuildState -PhaseId $Script:RequestedResumeFromPhase -ValidateOnly:$Script:ResumePreflightOnly
            if ($Script:ResumePreflightOnly) {
                Write-Ok ('Resume preflight passed for {0}; no build phase was executed.' -f $Script:RequestedResumeFromPhase)
            } else {
                $remaining = @($phaseList | Where-Object { $_ -notin @('P01','P02') })
                if ($remaining.Count -gt 0) { Invoke-PhaseRunner -PhaseIds $remaining }
            }
        } else {
            Invoke-PhaseRunner -PhaseIds $phaseList
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
