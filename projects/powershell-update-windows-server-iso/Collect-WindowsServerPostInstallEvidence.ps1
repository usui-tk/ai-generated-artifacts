#Requires -Version 5.1
<#
.SYNOPSIS
    Collects read-only post-installation evidence for Windows Server
    validation and operational verification.

.DESCRIPTION
    Collects the installed OS identity, UBR, kernel versions, servicing stack,
    installed update packages, Secure Boot state, firmware mode, WinRE status,
    pending-reboot state, problematic PnP devices, BCD output, disk layout and
    optional EFI System Partition boot-file evidence.

    This stable top-level filename is a supported project artifact whose
    purpose is independent of any particular test campaign. The
    collector revision is recorded inside its evidence instead of in the
    filename.

    The script does not install updates or change the installed operating
    system. When -InspectEsp is specified, it temporarily assigns an unused
    drive letter to the EFI System Partition with mountvol, reads evidence,
    and removes the drive letter in a finally block.

    No ISO, WIM, ESD, VHD or VHDX file is included in the evidence ZIP.

.PARAMETER OutputRoot
    Directory under which a timestamped evidence directory and ZIP are created.

.PARAMETER ExpectedOsVersion
    Optional expected Windows Server OS key. A mismatch is recorded as a
    validation failure but evidence collection continues.

.PARAMETER InspectEsp
    Temporarily mounts the EFI System Partition to inspect bootmgfw.efi,
    bootmgr.efi, boot.stl and the BCD store.

.PARAMETER IncludeMsInfo32
    Runs msinfo32 /report and includes the text report.

.EXAMPLE
    .\Collect-WindowsServerPostInstallEvidence.ps1 `
        -OutputRoot 'C:\WindowsServerEvidence' `
        -ExpectedOsVersion Server2025 `
        -InspectEsp `
        -IncludeMsInfo32
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = 'C:\WindowsServerEvidence',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Server2016', 'Server2019', 'Server2022', 'Server2025')]
    [string]$ExpectedOsVersion,

    [Parameter(Mandatory = $false)]
    [switch]$InspectEsp,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeMsInfo32
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:SchemaVersion = 'windows-server-post-install-evidence/1.0'
$script:CollectorVersion = 'r2'

function Get-UtcTimestamp {
    [CmdletBinding()]
    param()
    return [datetime]::UtcNow.ToString('o')
}

function Get-FileEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            Path = $Path
            Present = $false
            SizeBytes = $null
            FileVersion = $null
            ProductVersion = $null
            Sha256 = $null
            AuthenticodeStatus = $null
            SignerSubject = $null
        }
    }

    $item = Get-Item -LiteralPath $Path -Force
    $versionInfo = $null
    try { $versionInfo = $item.VersionInfo } catch { $versionInfo = $null }

    $signature = $null
    try { $signature = Get-AuthenticodeSignature -LiteralPath $item.FullName } catch { $signature = $null }

    return [pscustomobject][ordered]@{
        Path = $item.FullName
        Present = $true
        SizeBytes = [int64]$item.Length
        FileVersion = if ($versionInfo) { [string]$versionInfo.FileVersion } else { $null }
        ProductVersion = if ($versionInfo) { [string]$versionInfo.ProductVersion } else { $null }
        Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        AuthenticodeStatus = if ($signature) { [string]$signature.Status } else { $null }
        SignerSubject = if ($signature -and $signature.SignerCertificate) {
            [string]$signature.SignerCertificate.Subject
        } else {
            $null
        }
    }
}

function Invoke-CapturedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @()
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        return [pscustomobject][ordered]@{
            FilePath = $FilePath
            Arguments = @($ArgumentList)
            ExitCode = [int]$process.ExitCode
            StdOut = if (Test-Path -LiteralPath $stdout) {
                [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
            } else { '' }
            StdErr = if (Test-Path -LiteralPath $stderr) {
                [string](Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
            } else { '' }
        }
    }
    finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Get-FreeDriveLetter {
    [CmdletBinding()]
    param()

    $used = @(
        Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name.ToUpperInvariant() }
    )

    foreach ($letter in ([char[]]'ZYXWVUTSRQPONMLKJIHGFED')) {
        $value = [string]$letter
        if ($used -notcontains $value) {
            return $value
        }
    }

    throw 'No unused drive letter is available for temporary ESP inspection.'
}

function Get-PendingRebootEvidence {
    [CmdletBinding()]
    param()

    $checks = @(
        [pscustomobject]@{
            Name = 'CBSRebootPending'
            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            ValueName = $null
        },
        [pscustomobject]@{
            Name = 'WindowsUpdateRebootRequired'
            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            ValueName = $null
        },
        [pscustomobject]@{
            Name = 'PendingFileRenameOperations'
            Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
            ValueName = 'PendingFileRenameOperations'
        }
    )

    $results = foreach ($check in $checks) {
        $present = $false
        $value = $null
        if ($null -eq $check.ValueName) {
            $present = Test-Path -LiteralPath $check.Path
        }
        elseif (Test-Path -LiteralPath $check.Path) {
            try {
                $value = (Get-ItemProperty -LiteralPath $check.Path -Name $check.ValueName -ErrorAction Stop).$($check.ValueName)
                $present = ($null -ne $value)
            }
            catch {
                $present = $false
            }
        }

        [pscustomobject][ordered]@{
            Name = $check.Name
            Present = [bool]$present
            Value = $value
        }
    }

    return [pscustomobject][ordered]@{
        RebootPending = (@($results | Where-Object Present).Count -gt 0)
        Checks = @($results)
    }
}

function Get-SecureBootEvidence {
    [CmdletBinding()]
    param()

    $result = [pscustomobject][ordered]@{
        Supported = $false
        Enabled = $null
        ErrorMessage = $null
    }

    try {
        $result.Enabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
        $result.Supported = $true
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
    }

    return $result
}

function Get-InstalledPackageEvidence {
    [CmdletBinding()]
    param()

    try {
        $packages = @(Get-WindowsPackage -Online -ErrorAction Stop)
        $interesting = @(
            $packages | Where-Object {
                $_.PackageName -match 'RollupFix|ServicingStack|SafeOSDU|DotNetRollup|NetFx'
            } | Sort-Object PackageName
        )

        return [pscustomobject][ordered]@{
            Available = $true
            ErrorMessage = $null
            Packages = @(
                $interesting | ForEach-Object {
                    [pscustomobject][ordered]@{
                        PackageName = [string]$_.PackageName
                        PackageState = [string]$_.PackageState
                        ReleaseType = [string]$_.ReleaseType
                        InstallTime = if ($_.InstallTime) { $_.InstallTime.ToString('o') } else { $null }
                    }
                }
            )
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            Available = $false
            ErrorMessage = $_.Exception.Message
            Packages = @()
        }
    }
}

function Get-EspEvidence {
    [CmdletBinding()]
    param()

    $driveLetter = Get-FreeDriveLetter
    $root = '{0}:\' -f $driveLetter
    $mounted = $false

    $result = [pscustomobject][ordered]@{
        Requested = $true
        Available = $false
        DriveLetter = $driveLetter
        ErrorMessage = $null
        Files = @()
        BcdStore = $null
    }

    try {
        $mount = Invoke-CapturedCommand -FilePath "$env:SystemRoot\System32\mountvol.exe" `
            -ArgumentList @("$driveLetter`:", '/S')

        if ($mount.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $root -PathType Container)) {
            throw "mountvol /S failed. ExitCode=$($mount.ExitCode); $($mount.StdErr)"
        }
        $mounted = $true
        $result.Available = $true

        $relativePaths = @(
            'EFI\Microsoft\Boot\bootmgfw.efi',
            'EFI\Microsoft\Boot\bootmgr.efi',
            'EFI\Microsoft\Boot\boot.stl',
            'EFI\Microsoft\Boot\BCD',
            'EFI\Boot\bootx64.efi'
        )

        $result.Files = @(
            foreach ($relativePath in $relativePaths) {
                Get-FileEvidence -Path (Join-Path $root $relativePath)
            }
        )

        $bcdPath = Join-Path $root 'EFI\Microsoft\Boot\BCD'
        if (Test-Path -LiteralPath $bcdPath -PathType Leaf) {
            $result.BcdStore = Invoke-CapturedCommand `
                -FilePath "$env:SystemRoot\System32\bcdedit.exe" `
                -ArgumentList @('/store', $bcdPath, '/enum', 'all', '/v')
        }
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
    }
    finally {
        if ($mounted) {
            $null = Invoke-CapturedCommand -FilePath "$env:SystemRoot\System32\mountvol.exe" `
                -ArgumentList @("$driveLetter`:", '/D')
        }
    }

    return $result
}

function Resolve-ProjectOsKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Caption,

        [Parameter(Mandatory = $true)]
        [string]$Build
    )

    if ($Caption -match '2016' -or $Build -eq '14393') { return 'Server2016' }
    if ($Caption -match '2019' -or $Build -eq '17763') { return 'Server2019' }
    if ($Caption -match '2022' -or $Build -eq '20348') { return 'Server2022' }
    if ($Caption -match '2025' -or $Build -eq '26100') { return 'Server2025' }
    return 'Unknown'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$evidenceName = 'windows-server-post-install-evidence-{0}-{1}' -f $script:CollectorVersion, $timestamp
$evidenceDir = Join-Path ([System.IO.Path]::GetFullPath($OutputRoot)) $evidenceName
$zipPath = "$evidenceDir.zip"
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

$transcriptPath = Join-Path $evidenceDir 'transcript.log'
Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null

$exitCode = 0
try {
    Write-Host '============================================================'
    Write-Host ' Windows Server Post-Install Evidence Collector r2'
    Write-Host '============================================================'
    Write-Host "Evidence directory: $evidenceDir"

    $cvPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $cv = Get-ItemProperty -LiteralPath $cvPath
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS

    $currentBuild = [string]$cv.CurrentBuild
    if ([string]::IsNullOrWhiteSpace($currentBuild)) {
        $currentBuild = [string]$cv.CurrentBuildNumber
    }
    $ubr = if ($null -ne $cv.UBR) { [int]$cv.UBR } else { $null }
    $fullBuild = if ($null -ne $ubr) { '{0}.{1}' -f $currentBuild, $ubr } else { $currentBuild }
    $detectedOsKey = Resolve-ProjectOsKey -Caption ([string]$os.Caption) -Build $currentBuild

    $osKeyMatches = $true
    if (-not [string]::IsNullOrWhiteSpace($ExpectedOsVersion)) {
        $osKeyMatches = ($ExpectedOsVersion -eq $detectedOsKey)
    }

    $secureBoot = Get-SecureBootEvidence
    $pendingReboot = Get-PendingRebootEvidence
    $packages = Get-InstalledPackageEvidence

    $problemDevices = @(
        Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_.ConfigManagerErrorCode -and [int]$_.ConfigManagerErrorCode -ne 0 } |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Name = [string]$_.Name
                    PnpDeviceId = [string]$_.PNPDeviceID
                    ConfigManagerErrorCode = [int]$_.ConfigManagerErrorCode
                    Status = [string]$_.Status
                }
            }
    )

    $kernelFiles = @(
        Get-FileEvidence -Path (Join-Path $env:SystemRoot 'System32\ntoskrnl.exe')
        Get-FileEvidence -Path (Join-Path $env:SystemRoot 'System32\kernel32.dll')
        Get-FileEvidence -Path (Join-Path $env:SystemRoot 'System32\winload.efi')
        Get-FileEvidence -Path (Join-Path $env:SystemRoot 'System32\winresume.efi')
    )

    $reagent = Invoke-CapturedCommand -FilePath "$env:SystemRoot\System32\reagentc.exe" -ArgumentList @('/info')
    $bcdCurrent = Invoke-CapturedCommand -FilePath "$env:SystemRoot\System32\bcdedit.exe" -ArgumentList @('/enum', '{current}', '/v')
    $bcdBootMgr = Invoke-CapturedCommand -FilePath "$env:SystemRoot\System32\bcdedit.exe" -ArgumentList @('/enum', '{bootmgr}', '/v')
    $systemInfo = Invoke-CapturedCommand -FilePath "$env:SystemRoot\System32\systeminfo.exe"

    $hotFixes = @(
        Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
            Sort-Object HotFixID |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    HotFixId = [string]$_.HotFixID
                    Description = [string]$_.Description
                    InstalledOn = if ($_.InstalledOn) { [string]$_.InstalledOn } else { $null }
                }
            }
    )

    $diskEvidence = @()
    try {
        $diskEvidence = @(
            Get-Disk -ErrorAction Stop | ForEach-Object {
                [pscustomobject][ordered]@{
                    Number = [int]$_.Number
                    FriendlyName = [string]$_.FriendlyName
                    PartitionStyle = [string]$_.PartitionStyle
                    OperationalStatus = @($_.OperationalStatus | ForEach-Object { [string]$_ })
                    HealthStatus = [string]$_.HealthStatus
                    SizeBytes = [int64]$_.Size
                }
            }
        )
    }
    catch {
        $diskEvidence = @()
    }

    $esp = if ($InspectEsp) {
        Get-EspEvidence
    }
    else {
        [pscustomobject][ordered]@{
            Requested = $false
            Available = $false
            DriveLetter = $null
            ErrorMessage = $null
            Files = @()
            BcdStore = $null
        }
    }

    if ($IncludeMsInfo32) {
        $msInfoPath = Join-Path $evidenceDir 'msinfo32.txt'
        $msInfoProcess = Start-Process -FilePath "$env:SystemRoot\System32\msinfo32.exe" `
            -ArgumentList @('/report', $msInfoPath) `
            -Wait `
            -PassThru
        if ($msInfoProcess.ExitCode -ne 0) {
            Write-Warning "msinfo32 returned exit code $($msInfoProcess.ExitCode)."
        }
    }

    $validationFailures = [System.Collections.Generic.List[string]]::new()
    if (-not $osKeyMatches) {
        $validationFailures.Add(
            "Expected OS key '$ExpectedOsVersion' but detected '$detectedOsKey'."
        )
    }
    if (-not $secureBoot.Supported -or $secureBoot.Enabled -ne $true) {
        $validationFailures.Add('UEFI Secure Boot is not confirmed as enabled.')
    }
    if ($problemDevices.Count -gt 0) {
        $validationFailures.Add("$($problemDevices.Count) problematic PnP device(s) detected.")
    }
    if ($pendingReboot.RebootPending) {
        $validationFailures.Add('A pending reboot condition was detected.')
    }

    $summary = [pscustomobject][ordered]@{
        SchemaVersion = $script:SchemaVersion
        CollectorVersion = $script:CollectorVersion
        GeneratedAtUtc = Get-UtcTimestamp
        ExpectedOsVersion = $ExpectedOsVersion
        DetectedOsVersion = $detectedOsKey
        ExpectedOsVersionMatches = $osKeyMatches
        OverallStatus = if ($validationFailures.Count -eq 0) { 'Pass' } else { 'ReviewRequired' }
        ValidationFailures = @($validationFailures)
        OperatingSystem = [pscustomobject][ordered]@{
            Caption = [string]$os.Caption
            ProductName = [string]$cv.ProductName
            EditionId = [string]$cv.EditionID
            InstallationType = [string]$cv.InstallationType
            DisplayVersion = [string]$cv.DisplayVersion
            ReleaseId = [string]$cv.ReleaseId
            CurrentBuild = $currentBuild
            Ubr = $ubr
            FullBuild = $fullBuild
            BuildLabEx = [string]$cv.BuildLabEx
            OsArchitecture = [string]$os.OSArchitecture
            SystemDirectory = [string]$os.SystemDirectory
            WindowsDirectory = [string]$os.WindowsDirectory
            LastBootUpTime = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString('o') } else { $null }
        }
        ComputerSystem = [pscustomobject][ordered]@{
            Manufacturer = [string]$computer.Manufacturer
            Model = [string]$computer.Model
            SystemType = [string]$computer.SystemType
            HypervisorPresent = [bool]$computer.HypervisorPresent
            TotalPhysicalMemoryBytes = [uint64]$computer.TotalPhysicalMemory
        }
        Firmware = [pscustomobject][ordered]@{
            Manufacturer = [string]$bios.Manufacturer
            Name = [string]$bios.Name
            Version = [string]$bios.SMBIOSBIOSVersion
            ReleaseDate = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('o') } else { $null }
            SecureBoot = $secureBoot
        }
        KernelFiles = @($kernelFiles)
        InstalledPackages = $packages
        HotFixes = @($hotFixes)
        WinRe = $reagent
        PendingReboot = $pendingReboot
        ProblemDevices = @($problemDevices)
        ProblemDeviceCount = $problemDevices.Count
        BcdCurrent = $bcdCurrent
        BcdBootManager = $bcdBootMgr
        Disks = @($diskEvidence)
        Esp = $esp
        SystemInfo = $systemInfo
    }

    $jsonPath = Join-Path $evidenceDir 'summary.json'
    $summary | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $textPath = Join-Path $evidenceDir 'summary.txt'
    @(
        "SchemaVersion: $($summary.SchemaVersion)"
        "GeneratedAtUtc: $($summary.GeneratedAtUtc)"
        "OverallStatus: $($summary.OverallStatus)"
        "ExpectedOsVersion: $ExpectedOsVersion"
        "DetectedOsVersion: $detectedOsKey"
        "OS: $($summary.OperatingSystem.Caption)"
        "Build: $fullBuild"
        "BuildLabEx: $($summary.OperatingSystem.BuildLabEx)"
        "Firmware: $($summary.Firmware.Manufacturer) / $($summary.Firmware.Version)"
        "SecureBootSupported: $($secureBoot.Supported)"
        "SecureBootEnabled: $($secureBoot.Enabled)"
        "ProblemDeviceCount: $($problemDevices.Count)"
        "PendingReboot: $($pendingReboot.RebootPending)"
        "WinRE ExitCode: $($reagent.ExitCode)"
        "ESP Inspected: $($esp.Requested)"
        "ESP Available: $($esp.Available)"
        ""
        "Validation failures:"
        $(if ($validationFailures.Count -eq 0) { '  none' } else {
            @($validationFailures | ForEach-Object { "  - $_" })
        })
    ) | Set-Content -LiteralPath $textPath -Encoding UTF8

    $problemDevices | Export-Csv -LiteralPath (Join-Path $evidenceDir 'problem-devices.csv') `
        -NoTypeInformation -Encoding UTF8
    $hotFixes | Export-Csv -LiteralPath (Join-Path $evidenceDir 'hotfixes.csv') `
        -NoTypeInformation -Encoding UTF8

    $checksums = @(
        Get-ChildItem -LiteralPath $evidenceDir -Recurse -File |
            Where-Object { $_.Name -ne 'checksums.csv' } |
            Sort-Object FullName |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    RelativePath = $_.FullName.Substring($evidenceDir.Length).TrimStart('\')
                    SizeBytes = [int64]$_.Length
                    Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
    )
    $checksums | Export-Csv -LiteralPath (Join-Path $evidenceDir 'checksums.csv') `
        -NoTypeInformation -Encoding UTF8

    if ($validationFailures.Count -gt 0) {
        $exitCode = 2
    }
}
catch {
    $exitCode = 1
    $errorRecord = [pscustomobject][ordered]@{
        SchemaVersion = 'windows-server-post-install-evidence-error/1.0'
        GeneratedAtUtc = Get-UtcTimestamp
        Message = $_.Exception.Message
        FullyQualifiedErrorId = $_.FullyQualifiedErrorId
        ScriptStackTrace = $_.ScriptStackTrace
    }
    $errorRecord | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $evidenceDir 'fatal-error.json') -Encoding UTF8
    Write-Error $_
}
finally {
    try { Stop-Transcript | Out-Null } catch {}

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
    Compress-Archive -LiteralPath $evidenceDir -DestinationPath $zipPath -CompressionLevel Optimal

    Write-Host ''
    Write-Host "Evidence directory: $evidenceDir"
    Write-Host "Evidence ZIP      : $zipPath"
    Write-Host "Exit code         : $exitCode"
}

exit $exitCode
