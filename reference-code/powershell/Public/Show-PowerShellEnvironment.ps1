# >>> CANONICAL unit_id=pwsh.helper.show-powershellenvironment version=1.0.0 hash=3c1af882bcfbd9d1 policy=canonical binding=follow-latest >>>
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
