#Requires -Version 5.1
<#
.SYNOPSIS
    Collects read-only post-installation evidence for Windows Server
    validation and operational verification.

.DESCRIPTION
    Collects the installed OS identity, UBR, kernel versions, servicing stack,
    installed update packages, the complete Windows Server feature inventory,
    .NET Framework feature and registry state, Secure Boot certificate rollout
    state, firmware variables, TPM-WMI events, firmware mode, WinRE status,
    pending-reboot state, problematic PnP devices, BCD output, disk layout,
    EFI System Partition boot-file evidence and an MSInfo32 report.

    This stable top-level filename is a supported project artifact whose
    purpose is independent of any particular test campaign. The
    collector revision is recorded inside its evidence instead of in the
    filename. At completion, the collector prints a color-coded assessment
    report with PASS, FAIL, REVIEW and INFO results for important items, the
    final result, exit code and evidence artifact paths.

    Before full evidence collection starts, the collector requires an
    explicit confirmation that the installed Windows Server guest has been
    restarted at least once after the initial post-install boot. The mandatory
    startup notice is always displayed. Interactive runs prompt for YES/NO;
    unattended runs can use -ConfirmPostInstallRestart as the explicit
    operator assertion. Current pending-reboot state is checked before full
    collection and any pending or unreadable state stops the collection with
    exit code 2. Boot-history events are collected as corroborating evidence,
    but are not treated as authoritative proof because Windows Setup itself can
    reboot the machine during installation. Pending-reboot state is checked a
    second time at the end of a successful collection to detect state changes
    that occur while the collector is running.

    The script does not install updates or change the installed operating
    system. EFI System Partition inspection and MSInfo32 collection are
    enabled by default. ESP inspection temporarily assigns an unused drive
    letter with mountvol, reads evidence, and removes the drive letter in a
    finally block. Secure Boot diagnostics are read-only: no registry value is
    changed, no scheduled task is started and no firmware variable is written.
    Microsoft Secure Boot rollout scripts are inventoried using observed file
    metadata, SHA-256 and Authenticode information. No cross-version reference
    hash is applied because Microsoft can distribute different script content
    by Windows release and servicing level.

    Exit code 0 means that collection and validation completed without a
    detected issue. Exit code 2 means that evidence was created but at least
    one validation item failed, one collection item requires review, or an
    operational review condition was detected, or the mandatory startup
    prerequisite was not met. Exit code 1 means a fatal collector error.

    The installed Windows Server release is detected automatically from the
    running system by correlating Win32_OperatingSystem ProductType and Caption
    with the CurrentVersion ProductName, InstallationType and CurrentBuild
    registry values. The detected Server2016, Server2019, Server2022 or
    Server2025 key is written to the evidence and included in the ZIP name.

    No ISO, WIM, ESD, VHD or VHDX file is included in the evidence ZIP.

.PARAMETER OutputRoot
    Directory under which a timestamped evidence directory and ZIP are created.
    The only permitted locations are the directory containing this script and
    C:\Temp. When omitted, the script directory is used.

.PARAMETER InspectEsp
    Temporarily mounts the EFI System Partition to inspect bootmgfw.efi,
    bootmgr.efi, boot.stl, bootx64.efi and the BCD store. Enabled by default.
    Specify -InspectEsp:$false only when ESP inspection must be disabled.

.PARAMETER IncludeMsInfo32
    Runs msinfo32 /report and includes the text report. Enabled by default.
    Specify -IncludeMsInfo32:$false only when collection must be disabled.

.PARAMETER ConfirmPostInstallRestart
    Explicitly confirms, for non-interactive or automated execution, that the
    guest OS has been restarted at least once after the initial post-install
    boot. When omitted, the collector prompts for YES/NO before collecting full
    evidence. This parameter does not bypass pending-reboot verification.

.EXAMPLE
    .\Collect-WindowsServerPostInstallEvidence.ps1

.EXAMPLE
    .\Collect-WindowsServerPostInstallEvidence.ps1 `
        -OutputRoot 'C:\Temp'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$InspectEsp = $true,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeMsInfo32 = $true,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmPostInstallRestart
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:SchemaVersion = 'windows-server-post-install-evidence/1.10'
$script:CollectorVersion = 'r12'

function Get-UtcTimestamp {
    [CmdletBinding()]
    param()
    return [datetime]::UtcNow.ToString('o')
}

function Write-PostInstallRestartPrerequisiteBanner {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '================================================================================================================' -ForegroundColor Yellow
    Write-Host ' MANDATORY POST-INSTALL RESTART PRECONDITION' -ForegroundColor Yellow
    Write-Host '================================================================================================================' -ForegroundColor Yellow
    Write-Host ' Before collecting validation evidence, complete Windows Server installation and restart the guest OS at least'
    Write-Host ' once after the initial post-install boot. Run this collector only after that restart has completed.'
    Write-Host ''
    Write-Host ' The collector will stop before full evidence collection when:'
    Write-Host '   - the restart has not been explicitly confirmed;'
    Write-Host '   - CBS / Windows Update / PendingFileRenameOperations reports any pending reboot; or'
    Write-Host '   - pending-reboot registry state cannot be read reliably.'
    Write-Host ''
    Write-Host ' System boot events are recorded as corroborating evidence only. Windows Setup can reboot during installation,'
    Write-Host ' so a raw count of boot events is not authoritative proof of the required post-install restart.'
    Write-Host '================================================================================================================' -ForegroundColor Yellow
    Write-Host ''
}

function Get-PostInstallRestartConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ConfirmedByParameter
    )

    if ($ConfirmedByParameter) {
        return [pscustomobject][ordered]@{
            Confirmed = $true
            Source = 'ConfirmPostInstallRestartParameter'
            Response = 'YES'
            PromptAttemptCount = 0
            ErrorMessage = $null
        }
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $response = [string](Read-Host 'Have you restarted Windows Server at least once after the initial post-install boot? Type YES or NO')
        }
        catch {
            $lastError = $_.Exception.Message
            break
        }

        $normalized = $response.Trim().ToUpperInvariant()
        if ($normalized -eq 'YES') {
            return [pscustomobject][ordered]@{
                Confirmed = $true
                Source = 'InteractivePrompt'
                Response = 'YES'
                PromptAttemptCount = $attempt
                ErrorMessage = $null
            }
        }
        if ($normalized -eq 'NO') {
            return [pscustomobject][ordered]@{
                Confirmed = $false
                Source = 'InteractivePrompt'
                Response = 'NO'
                PromptAttemptCount = $attempt
                ErrorMessage = $null
            }
        }

        Write-Warning 'Please type exactly YES or NO.'
    }

    return [pscustomobject][ordered]@{
        Confirmed = $false
        Source = 'InteractivePromptUnavailableOrInvalid'
        Response = $null
        PromptAttemptCount = if ($null -ne $lastError) { 0 } else { 3 }
        ErrorMessage = if ($null -ne $lastError) {
            "Interactive confirmation failed: $lastError. For unattended execution, restart the guest OS first and rerun with -ConfirmPostInstallRestart."
        }
        else {
            'A valid YES/NO confirmation was not provided after three attempts.'
        }
    }
}

function Get-BootHistoryEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$OperatingSystem
    )

    $installDate = Get-PropertyValue -InputObject $OperatingSystem -Name 'InstallDate'
    $lastBootUpTime = Get-PropertyValue -InputObject $OperatingSystem -Name 'LastBootUpTime'
    $queryErrors = New-Object 'System.Collections.Generic.List[string]'
    $events = New-Object 'System.Collections.Generic.List[object]'

    $queries = @(
        [pscustomobject]@{ Name='KernelGeneralBoot'; LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12; Kind='BootStart' },
        [pscustomobject]@{ Name='EventLogServiceStart'; LogName='System'; ProviderName='EventLog'; Id=6005; Kind='BootCorroboration' },
        [pscustomobject]@{ Name='WindowsVersionAtBoot'; LogName='System'; ProviderName='EventLog'; Id=6009; Kind='BootCorroboration' },
        [pscustomobject]@{ Name='NormalRestartInitiated'; LogName='System'; ProviderName='User32'; Id=1074; Kind='RestartInitiated' }
    )

    foreach ($query in $queries) {
        try {
            $found = @(
                Get-WinEvent -FilterHashtable @{
                    LogName = $query.LogName
                    ProviderName = $query.ProviderName
                    Id = [int]$query.Id
                } -MaxEvents 64 -ErrorAction Stop
            )
            foreach ($event in $found) {
                $events.Add([pscustomobject][ordered]@{
                    QueryName = $query.Name
                    Kind = $query.Kind
                    Id = [int]$event.Id
                    ProviderName = [string]$event.ProviderName
                    TimeCreated = if ($event.TimeCreated) { $event.TimeCreated.ToString('o') } else { $null }
                    RecordId = if ($null -ne $event.RecordId) { [long]$event.RecordId } else { $null }
                })
            }
        }
        catch {
            # An empty event set is not a collector error. Other failures are
            # retained as evidence, but boot history is corroboration-only and
            # never overrides the explicit restart confirmation + reboot gate.
            if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound') {
                $queryErrors.Add("$($query.Name): $($_.Exception.Message)")
            }
        }
    }

    $eventArray = @($events.ToArray() | Sort-Object TimeCreated -Descending)
    $afterInstall = if ($null -ne $installDate) {
        @($eventArray | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.TimeCreated) -and
            ([datetime]$_.TimeCreated) -ge ([datetime]$installDate)
        })
    }
    else { @() }

    $bootStartAfterInstall = @($afterInstall | Where-Object Kind -eq 'BootStart')
    $restartInitiatedAfterInstall = @($afterInstall | Where-Object Kind -eq 'RestartInitiated')
    $corroboration = if ($bootStartAfterInstall.Count -ge 2 -or $restartInitiatedAfterInstall.Count -ge 1) {
        'Observed'
    }
    elseif ($queryErrors.Count -gt 0) {
        'Unknown'
    }
    else {
        'NotObserved'
    }

    return [pscustomobject][ordered]@{
        Authority = 'CorroborationOnly'
        GateAuthority = $false
        InstallDate = if ($null -ne $installDate) { ([datetime]$installDate).ToString('o') } else { $null }
        LastBootUpTime = if ($null -ne $lastBootUpTime) { ([datetime]$lastBootUpTime).ToString('o') } else { $null }
        Corroboration = $corroboration
        BootStartEventCountAfterInstallDate = $bootStartAfterInstall.Count
        NormalRestartEventCountAfterInstallDate = $restartInitiatedAfterInstall.Count
        EventCount = $eventArray.Count
        QueryComplete = [bool]($queryErrors.Count -eq 0)
        QueryErrors = $queryErrors.ToArray()
        Events = $eventArray
        Interpretation = 'Event IDs 12/6005/6009/1074 are reboot-history evidence only. Setup-driven reboots can occur before first post-install validation, so event counts are not an authoritative prerequisite gate.'
    }
}

function Resolve-StartupPreflightDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$RestartConfirmation,
        [Parameter(Mandatory = $true)] [object]$PendingReboot,
        [Parameter(Mandatory = $true)] [object]$BootHistory
    )

    $reasons = New-Object 'System.Collections.Generic.List[string]'
    if ($RestartConfirmation.Confirmed -ne $true) {
        $reasons.Add('The required post-install restart was not explicitly confirmed.')
    }
    if ($PendingReboot.CollectionComplete -ne $true) {
        $reasons.Add('Pending-reboot state could not be read completely.')
    }
    elseif ([string]$PendingReboot.Classification -ne 'None') {
        $reasons.Add("Pending reboot is currently present (classification=$($PendingReboot.Classification)).")
    }

    $allowed = (
        $RestartConfirmation.Confirmed -eq $true -and
        $PendingReboot.CollectionComplete -eq $true -and
        [string]$PendingReboot.Classification -eq 'None'
    )

    return [pscustomobject][ordered]@{
        AllowedToCollect = [bool]$allowed
        RequiredRestartConfirmed = [bool]$RestartConfirmation.Confirmed
        PendingRebootClear = [bool](
            $PendingReboot.CollectionComplete -eq $true -and
            [string]$PendingReboot.Classification -eq 'None'
        )
        BootHistoryCorroboration = [string]$BootHistory.Corroboration
        BootHistoryIsAuthoritative = $false
        Reasons = $reasons.ToArray()
    }
}

function Get-PropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Get-FileEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$SkipHash,

        [Parameter(Mandatory = $false)]
        [switch]$SkipAuthenticode
    )

    $result = [pscustomobject][ordered]@{
        Path = $Path
        FileName = $null
        Extension = $null
        Present = $false
        SizeBytes = $null
        CreationTimeUtc = $null
        LastWriteTimeUtc = $null
        Attributes = $null
        IsReadOnly = $null
        FileVersion = $null
        ProductVersion = $null
        FileDescription = $null
        CompanyName = $null
        OriginalFilename = $null
        Sha256 = $null
        HashSkipped = [bool]$SkipHash
        HashErrorMessage = $null
        AuthenticodeStatus = $null
        AuthenticodeStatusMessage = $null
        SignatureType = $null
        IsOsBinary = $null
        SignerSubject = $null
        SignerIssuer = $null
        SignerThumbprint = $null
        SignerNotBefore = $null
        SignerNotAfter = $null
        SignerIsMicrosoft = $null
        SignerIndicatesWindowsUefiCa2023 = $null
        SignerIndicatesWindowsProductionPca2011 = $null
        TimeStamperSubject = $null
        TimeStamperIssuer = $null
        TimeStamperThumbprint = $null
        TimeStamperNotBefore = $null
        TimeStamperNotAfter = $null
        AuthenticodeSkipped = [bool]$SkipAuthenticode
        AuthenticodeErrorMessage = $null
        ReadErrorMessage = $null
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $result
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $result.Path = $item.FullName
        $result.FileName = [string]$item.Name
        $result.Extension = [string]$item.Extension
        $result.Present = $true
        $result.SizeBytes = [int64]$item.Length
        $result.CreationTimeUtc = $item.CreationTimeUtc.ToString('o')
        $result.LastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        $result.Attributes = [string]$item.Attributes
        $result.IsReadOnly = [bool]$item.IsReadOnly

        try {
            $versionInfo = $item.VersionInfo
            if ($null -ne $versionInfo) {
                $result.FileVersion = [string]$versionInfo.FileVersion
                $result.ProductVersion = [string]$versionInfo.ProductVersion
                $result.FileDescription = [string]$versionInfo.FileDescription
                $result.CompanyName = [string]$versionInfo.CompanyName
                $result.OriginalFilename = [string]$versionInfo.OriginalFilename
            }
        }
        catch {
            # Version information is optional for data files such as BCD.
        }

        if (-not $SkipHash) {
            try {
                $result.Sha256 = (
                    Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop
                ).Hash.ToLowerInvariant()
            }
            catch {
                $result.HashErrorMessage = $_.Exception.Message
            }
        }

        if (-not $SkipAuthenticode) {
            try {
                $signature = Get-AuthenticodeSignature -LiteralPath $item.FullName -ErrorAction Stop
                $result.AuthenticodeStatus = [string]$signature.Status
                $result.AuthenticodeStatusMessage = [string]$signature.StatusMessage
                $result.SignatureType = [string](Get-PropertyValue -InputObject $signature -Name 'SignatureType')
                $isOsBinaryValue = Get-PropertyValue -InputObject $signature -Name 'IsOSBinary'
                if ($null -ne $isOsBinaryValue) {
                    $result.IsOsBinary = [bool]$isOsBinaryValue
                }
                if ($null -ne $signature.SignerCertificate) {
                    $result.SignerSubject = [string]$signature.SignerCertificate.Subject
                    $result.SignerIssuer = [string]$signature.SignerCertificate.Issuer
                    $result.SignerThumbprint = [string]$signature.SignerCertificate.Thumbprint
                    $result.SignerNotBefore = $signature.SignerCertificate.NotBefore.ToString('o')
                    $result.SignerNotAfter = $signature.SignerCertificate.NotAfter.ToString('o')
                    $signerIdentity = (
                        [string]$signature.SignerCertificate.Subject + ' | ' +
                        [string]$signature.SignerCertificate.Issuer
                    )
                    $result.SignerIsMicrosoft = ($signerIdentity -match 'Microsoft')
                    $result.SignerIndicatesWindowsUefiCa2023 = (
                        $signerIdentity -match 'Windows UEFI CA 2023'
                    )
                    $result.SignerIndicatesWindowsProductionPca2011 = (
                        $signerIdentity -match 'Windows Production PCA 2011'
                    )
                }

                $timeStamperCertificate = Get-PropertyValue `
                    -InputObject $signature `
                    -Name 'TimeStamperCertificate'
                if ($null -ne $timeStamperCertificate) {
                    $result.TimeStamperSubject = [string]$timeStamperCertificate.Subject
                    $result.TimeStamperIssuer = [string]$timeStamperCertificate.Issuer
                    $result.TimeStamperThumbprint = [string]$timeStamperCertificate.Thumbprint
                    $result.TimeStamperNotBefore = $timeStamperCertificate.NotBefore.ToString('o')
                    $result.TimeStamperNotAfter = $timeStamperCertificate.NotAfter.ToString('o')
                }
            }
            catch {
                $result.AuthenticodeErrorMessage = $_.Exception.Message
            }
        }
    }
    catch {
        $result.ReadErrorMessage = $_.Exception.Message
    }

    return $result
}

function Read-CapturedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [string]::Empty
    }

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        return [string]::Empty
    }

    return [string]$content
}

function Invoke-CapturedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ArgumentList = @()
    )

    $arguments = @()
    if ($null -ne $ArgumentList) {
        $arguments = @($ArgumentList)
    }

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $startParameters = @{
            FilePath = $FilePath
            Wait = $true
            PassThru = $true
            NoNewWindow = $true
            RedirectStandardOutput = $stdout
            RedirectStandardError = $stderr
            ErrorAction = 'Stop'
        }

        # Windows PowerShell 5.1 rejects Start-Process -ArgumentList @().
        # Omit the parameter completely when invoking an argument-less command.
        if ($arguments.Count -gt 0) {
            $startParameters['ArgumentList'] = $arguments
        }

        $process = Start-Process @startParameters

        return [pscustomobject][ordered]@{
            FilePath = $FilePath
            Arguments = @($arguments)
            Started = $true
            Succeeded = ([int]$process.ExitCode -eq 0)
            ExitCode = [int]$process.ExitCode
            StdOut = Read-CapturedText -Path $stdout
            StdErr = Read-CapturedText -Path $stderr
            ErrorMessage = $null
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            FilePath = $FilePath
            Arguments = @($arguments)
            Started = $false
            Succeeded = $false
            ExitCode = $null
            StdOut = Read-CapturedText -Path $stdout
            StdErr = Read-CapturedText -Path $stderr
            ErrorMessage = $_.Exception.Message
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

function Test-PendingFileRenameAdvisoryCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath
    )

    # PendingFileRenameOperations stores NT-style paths. The observed updater
    # entries can include the *1 prefix used by the registry representation.
    # Normalize only those syntactic prefixes; do not canonicalize or broaden
    # the allow-list because an unknown operation must remain fail-closed.
    $normalized = $SourcePath -replace '^(?:\*1)?\\\?\?\\', ''
    $patterns = @(
        '(?i)^[A-Z]:\\Windows\\SystemTemp\\MicrosoftEdgeUpdate\.exe\.old\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$',
        '(?i)^[A-Z]:\\Windows\\SystemTemp\\CopilotUpdate\.exe\.old\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$',
        '(?i)^[A-Z]:\\Program Files \(x86\)\\Microsoft\\EdgeUpdate\\[0-9][^\\]*$'
    )

    foreach ($pattern in $patterns) {
        if ($normalized -match $pattern) {
            return [pscustomobject][ordered]@{
                IsAdvisory = $true
                NormalizedSource = $normalized
                Reason = 'RecognizedMicrosoftUpdaterCleanup'
            }
        }
    }

    return [pscustomobject][ordered]@{
        IsAdvisory = $false
        NormalizedSource = $normalized
        Reason = 'UnrecognizedPendingFileOperation'
    }
}

function Convert-PendingFileRenameOperationsEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    $rawValues = @()
    if ($null -ne $Value) {
        if ($Value -is [System.Array]) {
            $rawValues = @($Value | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } })
        }
        else {
            $rawValues = @([string]$Value)
        }
    }

    $records = New-Object 'System.Collections.Generic.List[object]'
    $malformed = (($rawValues.Count % 2) -ne 0)
    for ($index = 0; $index -lt $rawValues.Count; $index += 2) {
        $source = [string]$rawValues[$index]
        $hasTarget = (($index + 1) -lt $rawValues.Count)
        $target = if ($hasTarget) { [string]$rawValues[$index + 1] } else { $null }
        $operation = if (-not $hasTarget) {
            'Malformed'
        }
        elseif ([string]::IsNullOrEmpty($target)) {
            'Delete'
        }
        else {
            'RenameOrMove'
        }

        $advisory = [pscustomobject][ordered]@{
            IsAdvisory = $false
            NormalizedSource = ($source -replace '^(?:\*1)?\\\?\?\\', '')
            Reason = if ($operation -eq 'Malformed') { 'MalformedPair' } else { 'NotEligibleForAdvisoryClassification' }
        }
        if ($operation -eq 'Delete' -and -not [string]::IsNullOrWhiteSpace($source)) {
            $advisory = Test-PendingFileRenameAdvisoryCleanup -SourcePath $source
        }

        $records.Add([pscustomobject][ordered]@{
            PairIndex = [int]($index / 2)
            Source = $source
            Target = $target
            Operation = $operation
            NormalizedSource = $advisory.NormalizedSource
            AdvisoryCleanup = [bool]$advisory.IsAdvisory
            ClassificationReason = [string]$advisory.Reason
        }) | Out-Null
    }

    $advisoryCount = @($records | Where-Object AdvisoryCleanup).Count
    $blockingCount = @($records | Where-Object { -not $_.AdvisoryCleanup }).Count
    return [pscustomobject][ordered]@{
        RawValueCount = $rawValues.Count
        PairCount = $records.Count
        Malformed = [bool]$malformed
        AdvisoryOperationCount = $advisoryCount
        BlockingOperationCount = $blockingCount
        AdvisoryCleanupOnly = [bool]($records.Count -gt 0 -and -not $malformed -and $blockingCount -eq 0)
        Records = $records.ToArray()
    }
}

function Resolve-PendingRebootClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [bool]$CbsPending,
        [Parameter(Mandatory = $true)] [bool]$WindowsUpdatePending,
        [Parameter(Mandatory = $true)] [bool]$PendingFileRenamePresent,
        [Parameter(Mandatory = $true)] [object]$PendingFileRenameEvidence,
        [Parameter(Mandatory = $true)] [ValidateRange(0, 2147483647)] [int]$ReadErrorCount
    )

    $pfroAdvisory = [bool](
        $PendingFileRenamePresent -and
        $PendingFileRenameEvidence.AdvisoryCleanupOnly
    )
    $pfroBlocking = [bool](
        $PendingFileRenamePresent -and
        -not $PendingFileRenameEvidence.AdvisoryCleanupOnly
    )
    $blockingPending = [bool]($CbsPending -or $WindowsUpdatePending -or $pfroBlocking)
    $advisoryPending = [bool](-not $blockingPending -and $pfroAdvisory)
    $classification = if ($blockingPending) {
        'Blocking'
    }
    elseif ($advisoryPending) {
        'Advisory'
    }
    elseif ($ReadErrorCount -gt 0) {
        'Unknown'
    }
    else {
        'None'
    }

    return [pscustomobject][ordered]@{
        RebootPending = [bool]($blockingPending -or $advisoryPending)
        BlockingRebootPending = $blockingPending
        AdvisoryRebootPending = $advisoryPending
        Classification = $classification
    }
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
        $errorMessage = $null
        try {
            $pathPresent = Test-Path -LiteralPath $check.Path -ErrorAction Stop
            if ($null -eq $check.ValueName) {
                $present = [bool]$pathPresent
            }
            elseif ($pathPresent) {
                # Read the registry key first and inspect the property bag. An
                # absent optional value is a normal "not pending" condition;
                # access/read failures are separately preserved as evidence.
                $propertyBag = Get-ItemProperty -LiteralPath $check.Path -ErrorAction Stop
                $property = $propertyBag.PSObject.Properties[$check.ValueName]
                if ($null -ne $property) {
                    $value = $property.Value
                    if ($check.Name -eq 'PendingFileRenameOperations') {
                        $parsed = Convert-PendingFileRenameOperationsEvidence -Value $value
                        $present = ($parsed.RawValueCount -gt 0)
                    }
                    else {
                        $present = ($null -ne $value)
                    }
                }
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            $present = $false
        }

        [pscustomobject][ordered]@{
            Name = $check.Name
            Present = [bool]$present
            Value = $value
            ErrorMessage = $errorMessage
        }
    }

    $cbs = @($results | Where-Object Name -eq 'CBSRebootPending' | Select-Object -First 1)
    $wu = @($results | Where-Object Name -eq 'WindowsUpdateRebootRequired' | Select-Object -First 1)
    $pfroCheck = @($results | Where-Object Name -eq 'PendingFileRenameOperations' | Select-Object -First 1)
    $pfro = if ($pfroCheck.Count -gt 0 -and $pfroCheck[0].Present) {
        Convert-PendingFileRenameOperationsEvidence -Value $pfroCheck[0].Value
    }
    else {
        Convert-PendingFileRenameOperationsEvidence -Value $null
    }

    $readErrors = @($results | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ErrorMessage) })
    $cbsPending = ($cbs.Count -gt 0 -and $cbs[0].Present)
    $wuPending = ($wu.Count -gt 0 -and $wu[0].Present)
    $pfroPresent = ($pfroCheck.Count -gt 0 -and $pfroCheck[0].Present)
    $classification = Resolve-PendingRebootClassification `
        -CbsPending ([bool]$cbsPending) `
        -WindowsUpdatePending ([bool]$wuPending) `
        -PendingFileRenamePresent ([bool]$pfroPresent) `
        -PendingFileRenameEvidence $pfro `
        -ReadErrorCount $readErrors.Count

    return [pscustomobject][ordered]@{
        RebootPending = [bool]$classification.RebootPending
        BlockingRebootPending = [bool]$classification.BlockingRebootPending
        AdvisoryRebootPending = [bool]$classification.AdvisoryRebootPending
        Classification = [string]$classification.Classification
        CollectionComplete = [bool]($readErrors.Count -eq 0)
        ReadErrorCount = $readErrors.Count
        PendingFileRenameOperations = $pfro
        Checks = @($results)
    }
}

function Get-RegistryKeySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $result = [pscustomobject][ordered]@{
        Path = $Path
        Present = $false
        Available = $false
        ErrorMessage = $null
        Values = [pscustomobject][ordered]@{}
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        $values = [ordered]@{}
        foreach ($name in @($key.GetValueNames() | Sort-Object)) {
            $value = $key.GetValue(
                $name,
                $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
            )
            $values[$name] = [pscustomobject][ordered]@{
                Type = [string]$key.GetValueKind($name)
                Value = $value
            }
        }

        $result.Present = $true
        $result.Available = $true
        $result.Values = [pscustomobject]$values
    }
    catch {
        $result.Present = $true
        $result.ErrorMessage = $_.Exception.Message
    }

    return $result
}

function Get-NamedRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Snapshot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$DefaultValue = $null
    )

    if ($null -eq $Snapshot -or -not $Snapshot.Available) {
        return $DefaultValue
    }

    $property = $Snapshot.Values.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }

    return $property.Value.Value
}

function Convert-RegistryFileTimeValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $fileTime = $null
        if ($Value -is [byte[]] -and $Value.Length -ge 8) {
            $fileTime = [BitConverter]::ToInt64($Value, 0)
        }
        elseif ($Value -is [long] -or $Value -is [int64]) {
            $fileTime = [int64]$Value
        }

        if ($null -ne $fileTime -and $fileTime -gt 0) {
            return [DateTime]::FromFileTimeUtc($fileTime).ToString('o')
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-Sha256HexFromBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Copy-ByteRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [int]$Offset,

        [Parameter(Mandatory = $true)]
        [int]$Count
    )

    if ($Offset -lt 0 -or $Count -lt 0 -or ($Offset + $Count) -gt $Bytes.Length) {
        throw "Byte range is outside the source buffer. Offset=$Offset Count=$Count Length=$($Bytes.Length)"
    }

    $result = New-Object byte[] $Count
    [Array]::Copy($Bytes, $Offset, $result, 0, $Count)
    return ,$result
}

function Resolve-EfiSignatureTypeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [guid]$SignatureType
    )

    switch ($SignatureType.ToString().ToLowerInvariant()) {
        'a5c059a1-94e4-4aa7-87b5-ab155c2bf072' { return 'X509' }
        'c1c41626-504c-4092-aca9-41f936934328' { return 'SHA256' }
        '826ca512-cf10-4ac9-b187-be01496631bd' { return 'SHA1' }
        '0b6e5233-a65c-44c9-9407-d9ab83bfc8bd' { return 'SHA224' }
        'ff3e5307-9fd0-48c9-85f1-8ad56c701e01' { return 'SHA384' }
        '093e0fae-a6c4-4f50-9f1b-d41e2b89c19a' { return 'SHA512' }
        default { return 'Unknown' }
    }
}

function Convert-EfiSignatureDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $lists = New-Object 'System.Collections.Generic.List[object]'
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $offset = 0
    $listIndex = 0

    while ($offset -lt $Bytes.Length) {
        $remaining = $Bytes.Length - $offset
        if ($remaining -lt 28) {
            $tail = Copy-ByteRange -Bytes $Bytes -Offset $offset -Count $remaining
            if (@($tail | Where-Object { $_ -ne 0 }).Count -gt 0) {
                $errors.Add("Trailing data is shorter than an EFI_SIGNATURE_LIST header at offset $offset.")
            }
            break
        }

        try {
            $typeBytes = Copy-ByteRange -Bytes $Bytes -Offset $offset -Count 16
            $signatureType = New-Object -TypeName System.Guid -ArgumentList (,$typeBytes)
            $signatureListSize = [BitConverter]::ToUInt32($Bytes, $offset + 16)
            $signatureHeaderSize = [BitConverter]::ToUInt32($Bytes, $offset + 20)
            $signatureSize = [BitConverter]::ToUInt32($Bytes, $offset + 24)

            if ($signatureListSize -lt 28) {
                throw "Invalid SignatureListSize $signatureListSize at offset $offset."
            }
            if (($offset + [int64]$signatureListSize) -gt $Bytes.Length) {
                throw "Signature list at offset $offset exceeds the variable length."
            }
            if ($signatureSize -lt 16) {
                throw "Invalid SignatureSize $signatureSize at offset $offset."
            }

            $listEnd = $offset + [int]$signatureListSize
            $entryOffset = $offset + 28 + [int]$signatureHeaderSize
            if ($entryOffset -gt $listEnd) {
                throw "SignatureHeaderSize exceeds the signature list at offset $offset."
            }

            $entryCount = 0
            while (($entryOffset + [int]$signatureSize) -le $listEnd) {
                $ownerBytes = Copy-ByteRange -Bytes $Bytes -Offset $entryOffset -Count 16
                $owner = New-Object -TypeName System.Guid -ArgumentList (,$ownerBytes)
                $dataLength = [int]$signatureSize - 16
                $signatureData = Copy-ByteRange -Bytes $Bytes -Offset ($entryOffset + 16) -Count $dataLength
                $typeName = Resolve-EfiSignatureTypeName -SignatureType $signatureType

                $certificateSubject = $null
                $certificateIssuer = $null
                $certificateThumbprint = $null
                $certificateSha256 = $null
                $certificateNotBefore = $null
                $certificateNotAfter = $null
                $certificateError = $null
                $knownCertificateNames = New-Object 'System.Collections.Generic.List[string]'

                if ($typeName -eq 'X509') {
                    try {
                        $certificate = New-Object `
                            -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 `
                            -ArgumentList (,$signatureData)
                        try {
                            $certificateSubject = [string]$certificate.Subject
                            $certificateIssuer = [string]$certificate.Issuer
                            $certificateThumbprint = [string]$certificate.Thumbprint
                            $certificateSha256 = Get-Sha256HexFromBytes -Bytes $certificate.RawData
                            $certificateNotBefore = $certificate.NotBefore.ToString('o')
                            $certificateNotAfter = $certificate.NotAfter.ToString('o')

                            $certificateIdentity = $certificateSubject + ' | ' + $certificateIssuer
                            foreach ($knownName in @(
                                'Windows UEFI CA 2023',
                                'Microsoft Corporation UEFI CA 2011',
                                'Microsoft UEFI CA 2023',
                                'Microsoft Option ROM UEFI CA 2023',
                                'Microsoft Corporation KEK 2K CA 2023',
                                'Microsoft Corporation KEK CA 2011',
                                'Microsoft Windows Production PCA 2011'
                            )) {
                                if ($certificateIdentity -match [regex]::Escape($knownName)) {
                                    $knownCertificateNames.Add($knownName)
                                }
                            }
                        }
                        finally {
                            $certificate.Dispose()
                        }
                    }
                    catch {
                        $certificateError = $_.Exception.Message
                    }
                }

                $entries.Add(
                    [pscustomobject][ordered]@{
                        ListIndex = $listIndex
                        EntryIndex = $entryCount
                        SignatureType = $signatureType.ToString()
                        SignatureTypeName = $typeName
                        SignatureOwner = $owner.ToString()
                        DataSizeBytes = $dataLength
                        DataSha256 = Get-Sha256HexFromBytes -Bytes $signatureData
                        HashValue = if ($typeName -match '^SHA') {
                            ([BitConverter]::ToString($signatureData)).Replace('-', '').ToLowerInvariant()
                        } else { $null }
                        CertificateSubject = $certificateSubject
                        CertificateIssuer = $certificateIssuer
                        CertificateThumbprint = $certificateThumbprint
                        CertificateSha256 = $certificateSha256
                        CertificateNotBefore = $certificateNotBefore
                        CertificateNotAfter = $certificateNotAfter
                        KnownCertificateNames = $knownCertificateNames.ToArray()
                        CertificateParseError = $certificateError
                    }
                )

                $entryCount++
                $entryOffset += [int]$signatureSize
            }

            if ($entryOffset -ne $listEnd) {
                $errors.Add("Signature list $listIndex has $($listEnd - $entryOffset) unparsed byte(s).")
            }

            $lists.Add(
                [pscustomobject][ordered]@{
                    ListIndex = $listIndex
                    Offset = $offset
                    SignatureType = $signatureType.ToString()
                    SignatureTypeName = Resolve-EfiSignatureTypeName -SignatureType $signatureType
                    SignatureListSize = [uint32]$signatureListSize
                    SignatureHeaderSize = [uint32]$signatureHeaderSize
                    SignatureSize = [uint32]$signatureSize
                    EntryCount = $entryCount
                }
            )

            $offset = $listEnd
            $listIndex++
        }
        catch {
            $errors.Add($_.Exception.Message)
            break
        }
    }

    return [pscustomobject][ordered]@{
        ParseComplete = ($errors.Count -eq 0)
        ErrorMessages = $errors.ToArray()
        ListCount = $lists.Count
        EntryCount = $entries.Count
        Lists = $lists.ToArray()
        Entries = $entries.ToArray()
    }
}

function Get-SecureBootVariableEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EvidenceDirectory
    )

    $secureBootDirectory = Join-Path $EvidenceDirectory 'secureboot'
    New-Item -ItemType Directory -Path $secureBootDirectory -Force | Out-Null

    $variables = New-Object 'System.Collections.Generic.List[object]'
    foreach ($variableName in @('PK', 'KEK', 'db', 'dbx')) {
        $variableResult = [pscustomobject][ordered]@{
            Name = $variableName
            Available = $false
            ErrorMessage = $null
            Attributes = $null
            ByteLength = 0
            Sha256 = $null
            RelativeBinaryPath = $null
            AsciiCertificateNameMatches = @()
            SignatureDatabase = $null
        }

        try {
            $uefiVariable = Get-SecureBootUEFI $variableName -ErrorAction Stop
            $bytesValue = Get-PropertyValue -InputObject $uefiVariable -Name 'Bytes'
            if ($null -eq $bytesValue) {
                throw "Get-SecureBootUEFI returned no Bytes property for $variableName."
            }

            $bytes = [byte[]]$bytesValue
            $relativePath = 'secureboot\uefi-{0}.bin' -f $variableName.ToLowerInvariant()
            $binaryPath = Join-Path $EvidenceDirectory $relativePath
            [System.IO.File]::WriteAllBytes($binaryPath, $bytes)

            $asciiText = [System.Text.Encoding]::ASCII.GetString($bytes)
            $asciiMatches = New-Object 'System.Collections.Generic.List[string]'
            foreach ($knownName in @(
                'Windows UEFI CA 2023',
                'Microsoft Corporation UEFI CA 2011',
                'Microsoft UEFI CA 2023',
                'Microsoft Option ROM UEFI CA 2023',
                'Microsoft Corporation KEK 2K CA 2023',
                'Microsoft Corporation KEK CA 2011',
                'Microsoft Windows Production PCA 2011'
            )) {
                if ($asciiText -match [regex]::Escape($knownName)) {
                    $asciiMatches.Add($knownName)
                }
            }

            $variableResult.Available = $true
            $variableResult.Attributes = [string](Get-PropertyValue -InputObject $uefiVariable -Name 'Attributes')
            $variableResult.ByteLength = $bytes.Length
            $variableResult.Sha256 = Get-Sha256HexFromBytes -Bytes $bytes
            $variableResult.RelativeBinaryPath = $relativePath
            $variableResult.AsciiCertificateNameMatches = $asciiMatches.ToArray()
            $variableResult.SignatureDatabase = Convert-EfiSignatureDatabase -Bytes $bytes
        }
        catch {
            $variableResult.ErrorMessage = $_.Exception.Message
        }

        $variables.Add($variableResult)
    }

    $presenceDefinitions = @(
        [pscustomobject]@{ Key = 'WindowsUefiCa2023InDb'; Variable = 'db'; Name = 'Windows UEFI CA 2023' },
        [pscustomobject]@{ Key = 'MicrosoftCorporationUefiCa2011InDb'; Variable = 'db'; Name = 'Microsoft Corporation UEFI CA 2011' },
        [pscustomobject]@{ Key = 'MicrosoftUefiCa2023InDb'; Variable = 'db'; Name = 'Microsoft UEFI CA 2023' },
        [pscustomobject]@{ Key = 'MicrosoftOptionRomUefiCa2023InDb'; Variable = 'db'; Name = 'Microsoft Option ROM UEFI CA 2023' },
        [pscustomobject]@{ Key = 'MicrosoftCorporationKek2KCa2023InKek'; Variable = 'KEK'; Name = 'Microsoft Corporation KEK 2K CA 2023' }
    )

    $presence = [ordered]@{}
    foreach ($definition in $presenceDefinitions) {
        $variable = @($variables | Where-Object { $_.Name -eq $definition.Variable } | Select-Object -First 1)
        $presentByAscii = $false
        $presentByCertificate = $false
        if ($variable.Count -gt 0 -and $variable[0].Available) {
            $presentByAscii = (@($variable[0].AsciiCertificateNameMatches) -contains $definition.Name)
            if ($null -ne $variable[0].SignatureDatabase) {
                $presentByCertificate = (@(
                    $variable[0].SignatureDatabase.Entries | Where-Object {
                        @($_.KnownCertificateNames) -contains $definition.Name
                    }
                ).Count -gt 0)
            }
        }

        $presence[$definition.Key] = [pscustomobject][ordered]@{
            Variable = $definition.Variable
            CertificateName = $definition.Name
            Present = [bool]($presentByAscii -or $presentByCertificate)
            PresentByAsciiScan = [bool]$presentByAscii
            PresentByParsedCertificate = [bool]$presentByCertificate
        }
    }

    $thirdPartyRequired = [bool]$presence['MicrosoftCorporationUefiCa2011InDb'].Present
    $directRequirementsSatisfied = (
        $presence['WindowsUefiCa2023InDb'].Present -and
        $presence['MicrosoftCorporationKek2KCa2023InKek'].Present -and
        (
            -not $thirdPartyRequired -or
            (
                $presence['MicrosoftUefiCa2023InDb'].Present -and
                $presence['MicrosoftOptionRomUefiCa2023InDb'].Present
            )
        )
    )

    $db = @($variables | Where-Object Name -eq 'db' | Select-Object -First 1)
    $kek = @($variables | Where-Object Name -eq 'KEK' | Select-Object -First 1)

    return [pscustomobject][ordered]@{
        Variables = $variables.ToArray()
        CertificatePresence = [pscustomobject]$presence
        ThirdParty2023CertificatesRequired = $thirdPartyRequired
        DirectRequirementsSatisfied = [bool]$directRequirementsSatisfied
        RequiredVariablesAvailable = [bool](
            $db.Count -gt 0 -and $db[0].Available -and
            $kek.Count -gt 0 -and $kek[0].Available
        )
    }
}

function Convert-EventDataToObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$EventRecord
    )

    $data = [ordered]@{}
    try {
        [xml]$eventXml = $EventRecord.ToXml()
        $index = 0

        # Some TPM-WMI events contain EventData/Data nodes, while simple
        # informational events (for example event 1034) may contain no Data
        # node at all. SelectNodes avoids StrictMode property errors when an
        # optional XML element is absent.
        $eventDataNodes = @(
            $eventXml.SelectNodes(
                "/*[local-name()='Event']/*[local-name()='EventData']/*[local-name()='Data']"
            )
        )
        foreach ($node in $eventDataNodes) {
            $nameAttribute = $node.Attributes['Name']
            $name = if ($null -ne $nameAttribute) { [string]$nameAttribute.Value } else { $null }
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = 'Data{0}' -f $index
            }
            if ($data.Contains($name)) {
                $name = '{0}_{1}' -f $name, $index
            }
            $data[$name] = [string]$node.InnerText
            $index++
        }

        # A provider can use UserData instead of EventData. Preserve leaf
        # values without treating the absence of EventData as a parse failure.
        $userDataNodes = @(
            $eventXml.SelectNodes(
                "/*[local-name()='Event']/*[local-name()='UserData']//*[not(*)]"
            )
        )
        foreach ($node in $userDataNodes) {
            $name = [string]$node.LocalName
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = 'UserData{0}' -f $index
            }
            if ($data.Contains($name)) {
                $name = '{0}_{1}' -f $name, $index
            }
            $data[$name] = [string]$node.InnerText
            $index++
        }
    }
    catch {
        $data['ParseError'] = $_.Exception.Message
    }

    return [pscustomobject]$data
}

function Get-SecureBootEventEvidence {
    [CmdletBinding()]
    param()

    $eventIds = @(
        1032, 1033, 1034, 1036, 1037, 1042, 1043, 1044, 1045,
        1795, 1796, 1797, 1798, 1799, 1800, 1801, 1802, 1803, 1808
    )

    $result = [pscustomobject][ordered]@{
        Available = $false
        ErrorMessage = $null
        EventCount = 0
        CountsById = @()
        LatestEvent = $null
        LatestRolloutEvent = $null
        Events = @()
    }

    try {
        $rawEvents = @()
        try {
            $rawEvents = @(
                Get-WinEvent -FilterHashtable @{
                    LogName = 'System'
                    ProviderName = 'Microsoft-Windows-TPM-WMI'
                    Id = $eventIds
                } -MaxEvents 200 -ErrorAction Stop
            )
        }
        catch {
            if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound') {
                throw
            }
        }

        $events = @(
            $rawEvents |
                Sort-Object TimeCreated -Descending |
                ForEach-Object {
                    [pscustomobject][ordered]@{
                        Id = [int]$_.Id
                        TimeCreated = if ($_.TimeCreated) { $_.TimeCreated.ToString('o') } else { $null }
                        ProviderName = [string]$_.ProviderName
                        Level = [string]$_.LevelDisplayName
                        RecordId = [long]$_.RecordId
                        Message = [string]$_.Message
                        EventData = Convert-EventDataToObject -EventRecord $_
                    }
                }
        )

        $result.Available = $true
        $result.EventCount = $events.Count
        $result.CountsById = @(
            foreach ($id in $eventIds) {
                [pscustomobject][ordered]@{
                    Id = $id
                    Count = @($events | Where-Object Id -eq $id).Count
                }
            }
        )
        $result.LatestEvent = @($events | Select-Object -First 1)
        if ($result.LatestEvent.Count -eq 0) { $result.LatestEvent = $null } else { $result.LatestEvent = $result.LatestEvent[0] }
        $latestRollout = @($events | Where-Object { $_.Id -in @(1801, 1808) } | Select-Object -First 1)
        $result.LatestRolloutEvent = if ($latestRollout.Count -gt 0) { $latestRollout[0] } else { $null }
        $result.Events = @($events)
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
    }

    return $result
}

function Get-SecureBootEventFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Event,

        [Parameter(Mandatory = $true)]
        [string[]]$Names,

        [Parameter(Mandatory = $false)]
        [string[]]$MessagePatterns = @()
    )

    if ($null -eq $Event) { return $null }

    foreach ($name in $Names) {
        $value = Get-PropertyValue -InputObject $Event.EventData -Name $name
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }

    $message = [string](Get-PropertyValue -InputObject $Event -Name 'Message')
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        foreach ($pattern in $MessagePatterns) {
            if ($message -match $pattern) {
                $candidate = if ($Matches.ContainsKey(1)) {
                    [string]$Matches[1]
                }
                else {
                    [string]$Matches[0]
                }
                $candidate = $candidate.Trim()
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    return $candidate
                }
            }
        }
    }

    return $null
}

function Get-SecureBootRolloutStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$EventEvidence,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$UefiCa2023Status
    )

    $events = @($EventEvidence.Events)
    $rolloutIds = @(1795, 1796, 1800, 1801, 1802, 1803, 1808)
    $rolloutEvents = @(
        $events | Where-Object { $_.Id -in $rolloutIds } |
            Sort-Object TimeCreated -Descending
    )
    $latest = @($rolloutEvents | Select-Object -First 1)
    $latestEvent = if ($latest.Count -gt 0) { $latest[0] } else { $null }
    $bucketCandidates = @(
        $rolloutEvents | Where-Object { $_.Id -in @(1801, 1808) } |
            Sort-Object TimeCreated -Descending
    )
    $bucketEvent = if ($bucketCandidates.Count -gt 0) { $bucketCandidates[0] } else { $null }

    $bucketId = Get-SecureBootEventFieldValue -Event $bucketEvent `
        -Names @('BucketId', 'BucketID') `
        -MessagePatterns @('(?m)^BucketId:[ \t]*([^\r\n]*)[ \t]*$')
    $confidence = Get-SecureBootEventFieldValue -Event $bucketEvent `
        -Names @('BucketConfidenceLevel', 'Confidence') `
        -MessagePatterns @('(?m)^BucketConfidenceLevel:[ \t]*([^\r\n]*)[ \t]*$')
    $updateType = Get-SecureBootEventFieldValue -Event $bucketEvent `
        -Names @('UpdateType') `
        -MessagePatterns @('(?m)^UpdateType:[ \t]*([^\r\n]*)[ \t]*$')
    $skipReason = Get-SecureBootEventFieldValue -Event $bucketEvent `
        -Names @('SkipReason') `
        -MessagePatterns @('(?m)^SkipReason:[ \t]*([^\r\n]*)[ \t]*$')
    $knownIssueFromSkipReason = $null
    if (-not [string]::IsNullOrWhiteSpace($skipReason) -and $skipReason -match '(KI_\d+)') {
        $knownIssueFromSkipReason = $Matches[1]
    }

    $latest1795 = @($rolloutEvents | Where-Object Id -eq 1795 | Select-Object -First 1)
    $latest1796 = @($rolloutEvents | Where-Object Id -eq 1796 | Select-Object -First 1)
    $latest1802 = @($rolloutEvents | Where-Object Id -eq 1802 | Select-Object -First 1)

    $event1795 = if ($latest1795.Count -gt 0) { $latest1795[0] } else { $null }
    $event1796 = if ($latest1796.Count -gt 0) { $latest1796[0] } else { $null }
    $event1802 = if ($latest1802.Count -gt 0) { $latest1802[0] } else { $null }

    $event1795ErrorCode = Get-SecureBootEventFieldValue -Event $event1795 `
        -Names @('ErrorCode', 'Status', 'NtStatus') `
        -MessagePatterns @('(?:error|code|status)[:\s]*(0x[0-9A-Fa-f]+|[0-9A-Fa-f]{8})')
    $event1796ErrorCode = Get-SecureBootEventFieldValue -Event $event1796 `
        -Names @('ErrorCode', 'Status', 'NtStatus') `
        -MessagePatterns @('(?:error|code|status)[:\s]*(0x[0-9A-Fa-f]+|[0-9A-Fa-f]{8})')
    $knownIssueId = Get-SecureBootEventFieldValue -Event $event1802 `
        -Names @('SkipReason', 'KnownIssueId') `
        -MessagePatterns @('(KI_\d+)')
    if (-not [string]::IsNullOrWhiteSpace($knownIssueId) -and $knownIssueId -match '(KI_\d+)') {
        $knownIssueId = $Matches[1]
    }

    $latestEventId = if ($null -ne $latestEvent) { [int]$latestEvent.Id } else { $null }
    $updateComplete = (
        $latestEventId -eq 1808 -or
        $UefiCa2023Status -eq 'Updated'
    )

    $count = [ordered]@{}
    foreach ($id in $rolloutIds) {
        $count[[string]$id] = @($rolloutEvents | Where-Object Id -eq $id).Count
    }

    return [pscustomobject][ordered]@{
        Available = [bool]$EventEvidence.Available
        LatestEventId = $latestEventId
        LatestEventTime = if ($null -ne $latestEvent) { $latestEvent.TimeCreated } else { $null }
        LatestCompletionOrPendingEventId = if ($null -ne $bucketEvent) { [int]$bucketEvent.Id } else { $null }
        LatestCompletionOrPendingEventTime = if ($null -ne $bucketEvent) { $bucketEvent.TimeCreated } else { $null }
        BucketId = $bucketId
        Confidence = $confidence
        UpdateType = $updateType
        SkipReason = $skipReason
        SkipReasonKnownIssue = $knownIssueFromSkipReason
        EventCounts = [pscustomobject]$count
        Event1795ErrorCode = $event1795ErrorCode
        Event1796ErrorCode = $event1796ErrorCode
        KnownIssueId = $knownIssueId
        RebootPending = [bool](-not $updateComplete -and $count['1800'] -gt 0)
        MissingKek = [bool](-not $updateComplete -and $count['1803'] -gt 0)
        UpdateCompleteByRegistryOrLatestEvent = [bool]$updateComplete
    }
}

function Get-WindowsUefiCa2023CapableInterpretation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    $numericValue = $null
    $validNumericValue = $false
    if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
        try {
            $numericValue = [uint32]$Value
            $validNumericValue = $true
        }
        catch {
            $validNumericValue = $false
        }
    }

    $meaning = if (-not $validNumericValue) {
        'NotReportedOrUnparseable'
    }
    elseif ($numericValue -eq 0) {
        'WindowsUefiCa2023NotPresentInDb'
    }
    elseif ($numericValue -eq 1) {
        'WindowsUefiCa2023PresentInDb'
    }
    elseif ($numericValue -eq 2) {
        'WindowsUefiCa2023PresentInDbAndBootingFrom2023SignedBootManager'
    }
    else {
        'UnknownReferenceValue'
    }

    return [pscustomobject][ordered]@{
        Available = [bool]$validNumericValue
        Value = if ($validNumericValue) { [uint32]$numericValue } else { $null }
        Meaning = $meaning
        ReferenceOnly = $true
        AuthoritativeStatusSignal = $false
        StatusAuthority = 'UEFICA2023Status'
        BootManager2023ReferenceEvidence = [bool]($validNumericValue -and $numericValue -eq 2)
    }
}

function Convert-WinCsSecureBootQueryOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Text
    )

    $fields = [ordered]@{
        Flag = $null
        CurrentConfiguration = $null
        State = $null
        PendingConfiguration = $null
        PendingAction = $null
        CVE = $null
        FwLink = $null
    }
    $availableConfigurations = New-Object 'System.Collections.Generic.List[string]'
    $inAvailableConfigurations = $false

    foreach ($rawLine in @(([string]$Text) -split "`r?`n")) {
        $line = [string]$rawLine
        if ($line -match '^\s*Available Configurations:\s*$') {
            $inAvailableConfigurations = $true
            continue
        }
        if ($inAvailableConfigurations -and $line -match '^\s+(F[0-9A-Fa-f]{8,})\s*$') {
            $availableConfigurations.Add($Matches[1]) | Out-Null
            continue
        }
        $inAvailableConfigurations = $false
        if ($line -match '^\s*([^:]+):[ \t]*(.*?)[ \t]*$') {
            $name = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            switch -Regex ($name) {
                '^Flag$' { $fields.Flag = $value; break }
                '^Current Configuration$' { $fields.CurrentConfiguration = $value; break }
                '^State$' { $fields.State = $value; break }
                '^Pending Configuration$' { $fields.PendingConfiguration = $value; break }
                '^Pending Action$' { $fields.PendingAction = $value; break }
                '^CVE$' { $fields.CVE = $value; break }
                '^FwLink$' { $fields.FwLink = $value; break }
            }
        }
    }

    return [pscustomobject][ordered]@{
        Parsed = [bool](-not [string]::IsNullOrWhiteSpace($fields.Flag) -or -not [string]::IsNullOrWhiteSpace($fields.State))
        Flag = $fields.Flag
        CurrentConfiguration = $fields.CurrentConfiguration
        State = $fields.State
        PendingConfiguration = $fields.PendingConfiguration
        PendingAction = $fields.PendingAction
        CVE = $fields.CVE
        FwLink = $fields.FwLink
        AvailableConfigurations = $availableConfigurations.ToArray()
    }
}

function Get-WinCsSecureBootInterpretation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$ParsedQuery,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$UefiCa2023Status
    )

    $state = [string](Get-PropertyValue -InputObject $ParsedQuery -Name 'State')
    $meaning = if ($UefiCa2023Status -eq 'Updated') {
        'NotRequiredCertificatesAlreadyUpdated'
    }
    elseif ($state -eq 'Enabled') {
        'DeploymentConfigurationEnabled'
    }
    elseif ($state -eq 'Disabled') {
        'DeploymentConfigurationDisabled'
    }
    elseif ([string]::IsNullOrWhiteSpace($state)) {
        'NotAvailableOrUnparsed'
    }
    else {
        'DeploymentConfigurationStateObserved'
    }

    return [pscustomobject][ordered]@{
        Purpose = 'DeploymentConfigurationOnly'
        State = if ([string]::IsNullOrWhiteSpace($state)) { $null } else { $state }
        Meaning = $meaning
        IsCompletionSignal = $false
        AuthoritativeStatusSignal = $false
        StatusAuthority = 'UEFICA2023Status'
        RequiresActionBasedOnWinCsAlone = $false
    }
}

function Get-SecureBootScheduledTaskEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EvidenceDirectory
    )

    $result = [pscustomobject][ordered]@{
        QueryAvailable = $false
        Found = $false
        Enabled = $null
        State = $null
        LastRunTime = $null
        LastTaskResult = $null
        NextRunTime = $null
        RelativeXmlPath = $null
        Source = $null
        ErrorMessage = $null
    }

    try {
        Import-Module ScheduledTasks -ErrorAction Stop
        $task = Get-ScheduledTask `
            -TaskPath '\Microsoft\Windows\PI\' `
            -TaskName 'Secure-Boot-Update' `
            -ErrorAction SilentlyContinue
        $result.QueryAvailable = $true
        $result.Source = 'ScheduledTasks'

        if ($null -ne $task) {
            $result.Found = $true
            $result.Enabled = [bool](Get-PropertyValue -InputObject $task.Settings -Name 'Enabled' -DefaultValue $false)
            $result.State = [string](Get-PropertyValue -InputObject $task -Name 'State')

            $taskInfo = Get-ScheduledTaskInfo -InputObject $task -ErrorAction SilentlyContinue
            if ($null -ne $taskInfo) {
                $result.LastRunTime = if ($taskInfo.LastRunTime) { $taskInfo.LastRunTime.ToString('o') } else { $null }
                $result.LastTaskResult = Get-PropertyValue -InputObject $taskInfo -Name 'LastTaskResult'
                $result.NextRunTime = if ($taskInfo.NextRunTime) { $taskInfo.NextRunTime.ToString('o') } else { $null }
            }

            try {
                $taskXml = Export-ScheduledTask -InputObject $task -ErrorAction Stop
                $relativePath = 'secureboot\secure-boot-update-task.xml'
                $taskXml | Set-Content -LiteralPath (Join-Path $EvidenceDirectory $relativePath) -Encoding UTF8
                $result.RelativeXmlPath = $relativePath
            }
            catch {
                # Task metadata is still useful when XML export is unavailable.
            }
        }
    }
    catch {
        try {
            $query = Invoke-CapturedCommand `
                -FilePath "$env:SystemRoot\System32\schtasks.exe" `
                -ArgumentList @('/Query', '/TN', '\Microsoft\Windows\PI\Secure-Boot-Update', '/XML')
            $result.QueryAvailable = $query.Started
            $result.Source = 'schtasks.exe'
            if ($query.Started -and $query.ExitCode -eq 0) {
                $result.Found = $true
                $relativePath = 'secureboot\secure-boot-update-task.xml'
                $query.StdOut | Set-Content -LiteralPath (Join-Path $EvidenceDirectory $relativePath) -Encoding UTF8
                $result.RelativeXmlPath = $relativePath
            }
            else {
                $result.ErrorMessage = $query.ErrorMessage
            }
        }
        catch {
            $result.ErrorMessage = $_.Exception.Message
        }
    }

    return $result
}

function Get-WinCsSecureBootEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$UefiCa2023Status
    )

    $paths = @(
        (Join-Path $env:SystemRoot 'System32\WinCsFlags.exe'),
        (Join-Path $env:SystemRoot 'SysWOW64\WinCsFlags.exe')
    )
    $path = @($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)

    if ($path.Count -eq 0) {
        $parsed = Convert-WinCsSecureBootQueryOutput -Text $null
        return [pscustomobject][ordered]@{
            Available = $false
            Path = $null
            Key = 'F33E0C8E002'
            Query = $null
            Parsed = $parsed
            Interpretation = Get-WinCsSecureBootInterpretation -ParsedQuery $parsed -UefiCa2023Status $UefiCa2023Status
        }
    }

    $query = Invoke-CapturedCommand `
        -FilePath $path[0] `
        -ArgumentList @('/query', '--key', 'F33E0C8E002')
    $parsed = Convert-WinCsSecureBootQueryOutput -Text ([string]$query.StdOut)

    return [pscustomobject][ordered]@{
        Available = $true
        Path = $path[0]
        Key = 'F33E0C8E002'
        Query = $query
        Parsed = $parsed
        Interpretation = Get-WinCsSecureBootInterpretation -ParsedQuery $parsed -UefiCa2023Status $UefiCa2023Status
    }
}

function Get-SecureBootScriptInventory {
    [CmdletBinding()]
    param()

    $directoryPaths = @(
        (Join-Path $env:SystemRoot 'SecureBoot\Scripts'),
        (Join-Path $env:SystemRoot 'SecureBoot\ExampleRolloutScripts')
    )

    $directories = New-Object 'System.Collections.Generic.List[object]'
    $files = New-Object 'System.Collections.Generic.List[object]'

    foreach ($directoryPath in $directoryPaths) {
        $present = Test-Path -LiteralPath $directoryPath -PathType Container
        $directoryRecord = [pscustomobject][ordered]@{
            Path = $directoryPath
            Present = [bool]$present
            EnumerationSucceeded = $null
            FileCount = 0
            ErrorMessage = $null
        }
        $directories.Add($directoryRecord)

        if (-not $present) {
            continue
        }

        $directoryFiles = @()
        try {
            $directoryFiles = @(
                Get-ChildItem -LiteralPath $directoryPath -Recurse -File -ErrorAction Stop |
                    Sort-Object FullName
            )
            $directoryRecord.EnumerationSucceeded = $true
            $directoryRecord.FileCount = $directoryFiles.Count
        }
        catch {
            $directoryRecord.EnumerationSucceeded = $false
            $directoryRecord.ErrorMessage = $_.Exception.Message
            continue
        }

        foreach ($file in $directoryFiles) {
            $skipAuthenticode = ($file.Extension -notin @('.ps1', '.psm1', '.psd1', '.exe', '.dll', '.sys', '.efi'))
            $evidence = Get-FileEvidence -Path $file.FullName -SkipAuthenticode:$skipAuthenticode
            $files.Add(
                [pscustomobject][ordered]@{
                    RootDirectory = $directoryPath
                    RelativePath = $file.FullName.Substring($directoryPath.Length).TrimStart('\')
                    File = $evidence
                }
            )
        }
    }

    $directoryArray = $directories.ToArray()
    $fileArray = $files.ToArray()
    $signatureEligibleFiles = @(
        $fileArray | Where-Object { -not $_.File.AuthenticodeSkipped }
    )
    $validMicrosoftSignedFiles = @(
        $signatureEligibleFiles | Where-Object {
            $_.File.AuthenticodeStatus -eq 'Valid' -and
            $_.File.SignerIsMicrosoft -eq $true
        }
    )
    $invalidSignatureFiles = @(
        $signatureEligibleFiles | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.File.AuthenticodeStatus) -and
            $_.File.AuthenticodeStatus -ne 'Valid'
        }
    )
    $unexpectedSignerFiles = @(
        $signatureEligibleFiles | Where-Object {
            $_.File.AuthenticodeStatus -eq 'Valid' -and
            $_.File.SignerIsMicrosoft -ne $true
        }
    )
    $directoryEnumerationIssues = @(
        $directoryArray | Where-Object {
            $_.Present -and $_.EnumerationSucceeded -ne $true
        }
    )
    $collectionIssueFiles = @(
        $fileArray | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.File.ReadErrorMessage) -or
            -not [string]::IsNullOrWhiteSpace($_.File.HashErrorMessage) -or
            -not [string]::IsNullOrWhiteSpace($_.File.AuthenticodeErrorMessage) -or
            [string]::IsNullOrWhiteSpace($_.File.Sha256) -or
            (-not $_.File.AuthenticodeSkipped -and
                [string]::IsNullOrWhiteSpace($_.File.AuthenticodeStatus))
        }
    )

    return [pscustomobject][ordered]@{
        InventoryPolicy = [pscustomobject][ordered]@{
            Purpose = 'Record observed file metadata, SHA-256 and Authenticode information.'
            BaselineHashComparisonEnabled = $false
            CrossOperatingSystemHashComparisonPerformed = $false
            HashInterpretation = 'SHA-256 identifies the observed file; it is not compared with a file collected from another Windows release or servicing level.'
            MissingDirectoryIsValidationFailure = $false
        }
        Directories = $directoryArray
        Files = $fileArray
        Summary = [pscustomobject][ordered]@{
            PresentDirectoryCount = @($directoryArray | Where-Object { $_.Present }).Count
            FileCount = $fileArray.Count
            SignatureEligibleFileCount = $signatureEligibleFiles.Count
            ValidMicrosoftSignedFileCount = $validMicrosoftSignedFiles.Count
            InvalidSignatureFileCount = $invalidSignatureFiles.Count
            UnexpectedSignerFileCount = $unexpectedSignerFiles.Count
            DirectoryEnumerationIssueCount = $directoryEnumerationIssues.Count
            CollectionIssueFileCount = $collectionIssueFiles.Count
            CollectionIssueCount = ($directoryEnumerationIssues.Count + $collectionIssueFiles.Count)
        }
        DetectScriptPresent = [bool](@(
            $fileArray | Where-Object { $_.RelativePath -ieq 'Detect-SecureBootCertUpdateStatus.ps1' }
        ).Count -gt 0)
    }
}

function Get-SecureBootEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EvidenceDirectory
    )

    $mainSnapshot = Get-RegistryKeySnapshot `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
    $stateSnapshot = Get-RegistryKeySnapshot `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
    $servicingSnapshot = Get-RegistryKeySnapshot `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing'
    $deviceAttributesSnapshot = Get-RegistryKeySnapshot `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes'

    $enabled = $null
    $supported = $false
    $stateSource = $null
    $stateError = $null
    try {
        $enabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
        $supported = $true
        $stateSource = 'Confirm-SecureBootUEFI'
    }
    catch {
        $stateError = $_.Exception.Message
        $registryEnabled = Get-NamedRegistryValue `
            -Snapshot $stateSnapshot `
            -Name 'UEFISecureBootEnabled'
        if ($null -ne $registryEnabled) {
            $enabled = ([int]$registryEnabled -ne 0)
            $supported = $true
            $stateSource = 'RegistryFallback'
        }
    }

    $registryEvidence = [pscustomobject][ordered]@{
        Main = $mainSnapshot
        State = $stateSnapshot
        Servicing = $servicingSnapshot
        DeviceAttributes = $deviceAttributesSnapshot
        AvailableUpdates = Get-NamedRegistryValue -Snapshot $mainSnapshot -Name 'AvailableUpdates'
        AvailableUpdatesHex = if ($null -ne (Get-NamedRegistryValue -Snapshot $mainSnapshot -Name 'AvailableUpdates')) {
            '0x{0:X}' -f [uint32](Get-NamedRegistryValue -Snapshot $mainSnapshot -Name 'AvailableUpdates')
        } else { $null }
        AvailableUpdatesPolicy = Get-NamedRegistryValue -Snapshot $mainSnapshot -Name 'AvailableUpdatesPolicy'
        AvailableUpdatesPolicyHex = if ($null -ne (Get-NamedRegistryValue -Snapshot $mainSnapshot -Name 'AvailableUpdatesPolicy')) {
            '0x{0:X}' -f [uint32](Get-NamedRegistryValue -Snapshot $mainSnapshot -Name 'AvailableUpdatesPolicy')
        } else { $null }
        HighConfidenceOptOut = Get-NamedRegistryValue -Snapshot $mainSnapshot -Name 'HighConfidenceOptOut'
        MicrosoftUpdateManagedOptIn = Get-NamedRegistryValue -Snapshot $mainSnapshot -Name 'MicrosoftUpdateManagedOptIn'
        UEFICA2023Status = [string](Get-NamedRegistryValue -Snapshot $servicingSnapshot -Name 'UEFICA2023Status')
        WindowsUEFICA2023Capable = Get-NamedRegistryValue -Snapshot $servicingSnapshot -Name 'WindowsUEFICA2023Capable'
        WindowsUEFICA2023CapableInterpretation = Get-WindowsUefiCa2023CapableInterpretation -Value (
            Get-NamedRegistryValue -Snapshot $servicingSnapshot -Name 'WindowsUEFICA2023Capable'
        )
        UEFICA2023Error = Get-NamedRegistryValue -Snapshot $servicingSnapshot -Name 'UEFICA2023Error'
        UEFICA2023ErrorEvent = Get-NamedRegistryValue -Snapshot $servicingSnapshot -Name 'UEFICA2023ErrorEvent'
        OEMManufacturerName = [string](Get-NamedRegistryValue -Snapshot $deviceAttributesSnapshot -Name 'OEMManufacturerName')
        OEMModelSystemFamily = [string](Get-NamedRegistryValue -Snapshot $deviceAttributesSnapshot -Name 'OEMModelSystemFamily')
        OEMModelNumber = [string](Get-NamedRegistryValue -Snapshot $deviceAttributesSnapshot -Name 'OEMModelNumber')
        FirmwareVersion = [string](Get-NamedRegistryValue -Snapshot $deviceAttributesSnapshot -Name 'FirmwareVersion')
        FirmwareReleaseDate = [string](Get-NamedRegistryValue -Snapshot $deviceAttributesSnapshot -Name 'FirmwareReleaseDate')
        OSArchitecture = [string](Get-NamedRegistryValue -Snapshot $deviceAttributesSnapshot -Name 'OSArchitecture')
        CanAttemptUpdateAfterUtc = Convert-RegistryFileTimeValue -Value (
            Get-NamedRegistryValue -Snapshot $deviceAttributesSnapshot -Name 'CanAttemptUpdateAfter'
        )
    }

    $variables = Get-SecureBootVariableEvidence -EvidenceDirectory $EvidenceDirectory
    $events = Get-SecureBootEventEvidence
    $rolloutStatus = Get-SecureBootRolloutStatus `
        -EventEvidence $events `
        -UefiCa2023Status $registryEvidence.UEFICA2023Status
    $task = Get-SecureBootScheduledTaskEvidence -EvidenceDirectory $EvidenceDirectory
    $winCs = Get-WinCsSecureBootEvidence -UefiCa2023Status $registryEvidence.UEFICA2023Status
    $scriptInventory = Get-SecureBootScriptInventory

    return [pscustomobject][ordered]@{
        Supported = $supported
        Enabled = $enabled
        StateSource = $stateSource
        StateErrorMessage = $stateError
        Registry = $registryEvidence
        FirmwareVariables = $variables
        Events = $events
        RolloutStatus = $rolloutStatus
        ScheduledTask = $task
        WinCs = $winCs
        MicrosoftScriptInventory = $scriptInventory
        Methodology = [pscustomobject][ordered]@{
            Mode = 'ReadOnlyInventory'
            MicrosoftSecureBootObjectsRepository = 'https://github.com/microsoft/secureboot_objects'
            MicrosoftGuidanceKb = 'KB5062713'
            DetectionScriptObserved = 'Detect-SecureBootCertUpdateStatus.ps1'
            ScriptInventoryDirectories = @(
                '%SystemRoot%\SecureBoot\Scripts',
                '%SystemRoot%\SecureBoot\ExampleRolloutScripts'
            )
            FirmwareVariablesRead = @('PK', 'KEK', 'db', 'dbx')
            FirmwareVariablesWritten = $false
            RegistryValuesChanged = $false
            ScheduledTasksStarted = $false
        }
        Assessment = $null
        MicrosoftMonitoringStatus = if (
            $enabled -eq $true -and
            $registryEvidence.UEFICA2023Status -eq 'Updated'
        ) { 'WithoutIssue' } elseif ($enabled -eq $false) {
            'NotApplicableSecureBootDisabled'
        } else {
            'WithIssueOrIncomplete'
        }
    }
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

function Get-WindowsFeatureEvidence {
    [CmdletBinding()]
    param()

    $items = @()
    $source = $null
    $errorMessage = $null

    try {
        Import-Module ServerManager -ErrorAction Stop
        $source = 'Get-WindowsFeature'
        $items = @(
            Get-WindowsFeature -ErrorAction Stop |
                Sort-Object Name |
                ForEach-Object {
                    [pscustomobject][ordered]@{
                        Name = [string](Get-PropertyValue -InputObject $_ -Name 'Name')
                        DisplayName = [string](Get-PropertyValue -InputObject $_ -Name 'DisplayName')
                        Description = [string](Get-PropertyValue -InputObject $_ -Name 'Description')
                        Installed = [bool](Get-PropertyValue -InputObject $_ -Name 'Installed' -DefaultValue $false)
                        InstallState = [string](Get-PropertyValue -InputObject $_ -Name 'InstallState')
                        FeatureType = [string](Get-PropertyValue -InputObject $_ -Name 'FeatureType')
                        Parent = [string](Get-PropertyValue -InputObject $_ -Name 'Parent')
                        Depth = Get-PropertyValue -InputObject $_ -Name 'Depth'
                        Source = 'Get-WindowsFeature'
                    }
                }
        )
    }
    catch {
        $serverManagerError = $_.Exception.Message
        try {
            $source = 'Get-WindowsOptionalFeature'
            $items = @(
                Get-WindowsOptionalFeature -Online -ErrorAction Stop |
                    Sort-Object FeatureName |
                    ForEach-Object {
                        $state = [string](Get-PropertyValue -InputObject $_ -Name 'State')
                        [pscustomobject][ordered]@{
                            Name = [string](Get-PropertyValue -InputObject $_ -Name 'FeatureName')
                            DisplayName = [string](Get-PropertyValue -InputObject $_ -Name 'FeatureName')
                            Description = $null
                            Installed = ($state -eq 'Enabled')
                            InstallState = $state
                            FeatureType = 'OptionalFeature'
                            Parent = $null
                            Depth = $null
                            Source = 'Get-WindowsOptionalFeature'
                        }
                    }
            )
        }
        catch {
            $errorMessage = (
                "ServerManager query failed: $serverManagerError; " +
                "DISM optional feature query failed: $($_.Exception.Message)"
            )
        }
    }

    $dotNetItems = @(
        $items | Where-Object {
            $_.Name -match '^(NET-|NetFx|WCF-|Web-Asp-Net)' -or
            $_.DisplayName -match '\.NET Framework|ASP\.NET|Windows Communication Foundation|WCF'
        }
    )

    $isInstalled = {
        param([object]$Feature)
        return (
            $Feature.Installed -eq $true -or
            $Feature.InstallState -in @('Installed', 'Enabled')
        )
    }

    $netFx3Installed = @(
        $dotNetItems | Where-Object {
            $_.Name -in @('NET-Framework-Core', 'NetFx3') -and (& $isInstalled $_)
        }
    ).Count -gt 0
    $netFx4Installed = @(
        $dotNetItems | Where-Object {
            (
                $_.Name -match '^NET-Framework-45-(Core|Features)$' -or
                $_.Name -match '^NetFx4'
            ) -and (& $isInstalled $_)
        }
    ).Count -gt 0

    return [pscustomobject][ordered]@{
        Available = [bool]($null -eq $errorMessage)
        Source = $source
        ErrorMessage = $errorMessage
        FeatureCount = $items.Count
        InstalledFeatureCount = @($items | Where-Object { & $isInstalled $_ }).Count
        Features = @($items)
        DotNetFeatures = @($dotNetItems)
        DotNetFeatureState = [pscustomobject][ordered]@{
            FeatureInventoryAvailable = [bool]($null -eq $errorMessage)
            NetFx3Installed = [bool]$netFx3Installed
            NetFx4Installed = [bool]$netFx4Installed
            NetFx3FeatureNames = @(
                $dotNetItems | Where-Object { $_.Name -in @('NET-Framework-Core', 'NetFx3') } |
                    Select-Object -ExpandProperty Name
            )
            NetFx4FeatureNames = @(
                $dotNetItems | Where-Object {
                    $_.Name -match '^NET-Framework-45-(Core|Features)$' -or
                    $_.Name -match '^NetFx4'
                } | Select-Object -ExpandProperty Name
            )
            InstalledDotNetFeatureNames = @(
                $dotNetItems | Where-Object { & $isInstalled $_ } | Select-Object -ExpandProperty Name
            )
            DetectionBasis = 'Windows Server feature state; registry is used as a secondary version and consistency check.'
        }
    }
}

function Resolve-DotNetReleaseVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Release
    )

    if ($null -eq $Release) { return $null }
    $value = [int64]$Release
    if ($value -ge 533320) { return '4.8.1 or later' }
    if ($value -ge 528040) { return '4.8' }
    if ($value -ge 461808) { return '4.7.2' }
    if ($value -ge 461308) { return '4.7.1' }
    if ($value -ge 460798) { return '4.7' }
    if ($value -ge 394802) { return '4.6.2' }
    if ($value -ge 394254) { return '4.6.1' }
    if ($value -ge 393295) { return '4.6' }
    if ($value -ge 379893) { return '4.5.2' }
    if ($value -ge 378675) { return '4.5.1' }
    if ($value -ge 378389) { return '4.5' }
    return 'Unknown pre-4.5 release key'
}

function Get-DotNetFrameworkEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$WindowsFeatures
    )

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5',
        'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Client',
        'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\NET Framework Setup\NDP\v3.5',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\NET Framework Setup\NDP\v4\Client',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\NET Framework Setup\NDP\v4\Full'
    )

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $errors = New-Object 'System.Collections.Generic.List[string]'

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        try {
            $properties = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $release = Get-PropertyValue -InputObject $properties -Name 'Release'
            $entries.Add(
                [pscustomobject][ordered]@{
                    RegistryPath = $path
                    Install = Get-PropertyValue -InputObject $properties -Name 'Install'
                    Version = [string](Get-PropertyValue -InputObject $properties -Name 'Version')
                    Release = $release
                    ResolvedReleaseVersion = Resolve-DotNetReleaseVersion -Release $release
                    ServicePack = Get-PropertyValue -InputObject $properties -Name 'SP'
                    Servicing = Get-PropertyValue -InputObject $properties -Name 'Servicing'
                    InstallPath = [string](Get-PropertyValue -InputObject $properties -Name 'InstallPath')
                    TargetVersion = [string](Get-PropertyValue -InputObject $properties -Name 'TargetVersion')
                }
            )
        }
        catch {
            $errors.Add("$path : $($_.Exception.Message)")
        }
    }

    $netFx35RegistryInstalled = @(
        $entries | Where-Object {
            $_.RegistryPath -match '\\v3\.5$' -and
            ($_.Install -eq 1 -or -not [string]::IsNullOrWhiteSpace($_.Version))
        }
    ).Count -gt 0
    $netFx4FullEntries = @(
        $entries | Where-Object {
            $_.RegistryPath -match '\\v4\\Full$' -and
            ($_.Install -eq 1 -or $null -ne $_.Release)
        }
    )
    $netFx4RegistryInstalled = $netFx4FullEntries.Count -gt 0

    $consistencyFindings = New-Object 'System.Collections.Generic.List[string]'
    if ($WindowsFeatures.Available) {
        if ($WindowsFeatures.DotNetFeatureState.NetFx3Installed -and -not $netFx35RegistryInstalled) {
            $consistencyFindings.Add(
                '.NET Framework 3.5 is enabled as a Windows feature but no matching installed registry entry was found.'
            )
        }
        if ($WindowsFeatures.DotNetFeatureState.NetFx4Installed -and -not $netFx4RegistryInstalled) {
            $consistencyFindings.Add(
                '.NET Framework 4.x is enabled as a Windows feature but the v4 Full registry release key was not found.'
            )
        }
    }

    return [pscustomobject][ordered]@{
        Available = ($errors.Count -eq 0)
        ErrorMessages = $errors.ToArray()
        WindowsFeatureState = $WindowsFeatures.DotNetFeatureState
        RegistryState = [pscustomobject][ordered]@{
            NetFx35RegistryCheckApplicable = [bool]$WindowsFeatures.DotNetFeatureState.NetFx3Installed
            NetFx4RegistryCheckApplicable = [bool]$WindowsFeatures.DotNetFeatureState.NetFx4Installed
            NetFx35Installed = [bool]$netFx35RegistryInstalled
            NetFx4FullInstalled = [bool]$netFx4RegistryInstalled
            NetFx4HighestRelease = if ($netFx4FullEntries.Count -gt 0) {
                @($netFx4FullEntries | Measure-Object -Property Release -Maximum).Maximum
            } else { $null }
            NetFx4ResolvedVersion = if ($netFx4FullEntries.Count -gt 0) {
                Resolve-DotNetReleaseVersion -Release (
                    @($netFx4FullEntries | Measure-Object -Property Release -Maximum).Maximum
                )
            } else { $null }
        }
        ConsistencyFindings = $consistencyFindings.ToArray()
        Entries = $entries.ToArray()
    }
}

function Get-SecureBootAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$SecureBoot,

        [Parameter(Mandatory = $true)]
        [object]$Esp
    )

    $bootManager = @(
        $Esp.Files | Where-Object { $_.Path -match '\\bootmgfw\.efi$' } | Select-Object -First 1
    )
    $bootManagerPresent = ($bootManager.Count -gt 0 -and $bootManager[0].Present)

    # Get-AuthenticodeSignature exposes one selected signer certificate. It
    # does not provide an authoritative inventory of every embedded signature
    # in a multiply signed EFI image. Keep it as diagnostic evidence only.
    $bootManagerPrimarySigner2023 = (
        $bootManagerPresent -and
        $bootManager[0].SignerIndicatesWindowsUefiCa2023 -eq $true
    )
    $bootManagerPrimarySigner2011 = (
        $bootManagerPresent -and
        $bootManager[0].SignerIndicatesWindowsProductionPca2011 -eq $true
    )
    $bootManagerPrimarySignerSubject = if ($bootManagerPresent) {
        [string](Get-PropertyValue -InputObject $bootManager[0] -Name 'SignerSubject')
    }
    else { $null }

    $findings = New-Object 'System.Collections.Generic.List[string]'
    $information = New-Object 'System.Collections.Generic.List[string]'
    $statusUpdated = ($SecureBoot.Registry.UEFICA2023Status -eq 'Updated')
    $latestRolloutEventId = Get-PropertyValue -InputObject $SecureBoot.RolloutStatus -Name 'LatestEventId'
    $latestCompletionEventIs1808 = ($latestRolloutEventId -eq 1808)
    $event1808Count = @(
        $SecureBoot.Events.Events | Where-Object { $_.Id -eq 1808 }
    ).Count
    $event1799Count = @(
        $SecureBoot.Events.Events | Where-Object { $_.Id -eq 1799 }
    ).Count
    $historicalEvent1808Observed = ($event1808Count -gt 0)

    # Microsoft completion semantics are current-state based: either the
    # deployment registry status is Updated, or the latest rollout event is
    # 1808. A stale historical 1808 must never override a newer pending/error
    # event such as 1801.
    $currentMicrosoftCompletionSignal = [bool]($statusUpdated -or $latestCompletionEventIs1808)

    $capableInterpretation = Get-PropertyValue `
        -InputObject $SecureBoot.Registry `
        -Name 'WindowsUEFICA2023CapableInterpretation'
    if ($null -eq $capableInterpretation) {
        $capableInterpretation = Get-WindowsUefiCa2023CapableInterpretation `
            -Value (Get-PropertyValue -InputObject $SecureBoot.Registry -Name 'WindowsUEFICA2023Capable')
    }

    $bootManager2023EvidenceSources = New-Object 'System.Collections.Generic.List[string]'
    if ($statusUpdated) { $bootManager2023EvidenceSources.Add('RegistryUEFICA2023StatusUpdated') | Out-Null }
    if ($latestCompletionEventIs1808) { $bootManager2023EvidenceSources.Add('LatestTpmWmiEvent1808') | Out-Null }
    if ([bool](Get-PropertyValue -InputObject $capableInterpretation -Name 'BootManager2023ReferenceEvidence' -DefaultValue $false)) {
        $bootManager2023EvidenceSources.Add('WindowsUEFICA2023CapableReferenceValue2') | Out-Null
    }
    if ($event1799Count -gt 0) { $bootManager2023EvidenceSources.Add('TpmWmiEvent1799Observed') | Out-Null }
    if ($bootManagerPrimarySigner2023) { $bootManager2023EvidenceSources.Add('AuthenticodePrimarySignerWindowsUefiCa2023') | Out-Null }
    $bootManager2023EvidenceConfirmed = ($bootManager2023EvidenceSources.Count -gt 0)

    if ($statusUpdated -and $SecureBoot.FirmwareVariables.RequiredVariablesAvailable -and -not $SecureBoot.FirmwareVariables.DirectRequirementsSatisfied) {
        $findings.Add(
            'UEFICA2023Status is Updated, but the directly inspected db/KEK certificate set does not satisfy the Microsoft 2023 requirements.'
        )
    }

    if ($event1799Count -gt 0) {
        $information.Add(
            'TPM-WMI event 1799 confirms installation of a boot manager signed by Windows UEFI CA 2023.'
        )
    }

    if ($historicalEvent1808Observed -and -not $latestCompletionEventIs1808 -and -not $statusUpdated) {
        $information.Add(
            'Historical event 1808 evidence exists, but it is not treated as current rollout completion because the latest rollout event is not 1808 and UEFICA2023Status is not Updated.'
        )
    }

    if ($null -ne $SecureBoot.Registry.UEFICA2023Error) {
        $findings.Add("UEFICA2023Error is present: $($SecureBoot.Registry.UEFICA2023Error)")
    }
    if ($null -ne $SecureBoot.Registry.UEFICA2023ErrorEvent) {
        $findings.Add("UEFICA2023ErrorEvent is present: $($SecureBoot.Registry.UEFICA2023ErrorEvent)")
    }

    $errorEventCount = @(
        $SecureBoot.Events.Events | Where-Object {
            $_.Id -in @(1033, 1795, 1796, 1797, 1798, 1802, 1803)
        }
    ).Count
    if ($errorEventCount -gt 0 -and -not $currentMicrosoftCompletionSignal) {
        $findings.Add("$errorEventCount Secure Boot update error/block event(s) are present.")
    }
    if ($SecureBoot.RolloutStatus.RebootPending) {
        $findings.Add('Secure Boot certificate rollout event 1800 indicates that a restart is still required.')
    }
    if ($SecureBoot.RolloutStatus.MissingKek) {
        $findings.Add('Secure Boot certificate rollout event 1803 indicates that a matching KEK update was not found.')
    }
    if ($latestCompletionEventIs1808 -and -not $statusUpdated) {
        $information.Add('Latest event 1808 indicates certificate completion although UEFICA2023Status is not Updated.')
    }

    $microsoftCompletionConfirmed = [bool](
        $SecureBoot.Enabled -eq $true -and
        $currentMicrosoftCompletionSignal
    )
    $directFirmwareCertificatesConfirmed = [bool](
        $SecureBoot.FirmwareVariables.RequiredVariablesAvailable -and
        $SecureBoot.FirmwareVariables.DirectRequirementsSatisfied
    )

    if (
        $latestRolloutEventId -eq 1801 -and
        $directFirmwareCertificatesConfirmed -and
        -not $microsoftCompletionConfirmed
    ) {
        $information.Add(
            'The latest Microsoft rollout event is 1801 while direct firmware-variable inspection already satisfies the required 2023 certificate set. This is retained as a Microsoft monitoring-state divergence; rollout completion is not inferred from the direct observation alone.'
        )
    }

    $state = if ($SecureBoot.Enabled -ne $true) {
        'NotApplicableOrDisabled'
    }
    elseif ($microsoftCompletionConfirmed -and $directFirmwareCertificatesConfirmed -and $Esp.CollectionComplete) {
        'UpdatedAndFirmwareCertificatesDirectlyVerified'
    }
    elseif ($microsoftCompletionConfirmed) {
        'UpdatedByMicrosoftState'
    }
    elseif ($SecureBoot.Registry.UEFICA2023Status -eq 'InProgress') {
        'InProgress'
    }
    elseif ([string]::IsNullOrWhiteSpace($SecureBoot.Registry.UEFICA2023Status) -or $SecureBoot.Registry.UEFICA2023Status -eq 'NotStarted') {
        'NotStartedOrNoValue'
    }
    else {
        'UnknownOrError'
    }

    return [pscustomobject][ordered]@{
        State = $state
        MicrosoftMonitoringStatus = $SecureBoot.MicrosoftMonitoringStatus
        RegistryStatusUpdated = [bool]$statusUpdated
        LatestRolloutEventId = $latestRolloutEventId
        LatestCompletionEventIs1808 = [bool]$latestCompletionEventIs1808
        HistoricalEvent1808Observed = [bool]$historicalEvent1808Observed
        RolloutBucketId = $SecureBoot.RolloutStatus.BucketId
        RolloutConfidence = $SecureBoot.RolloutStatus.Confidence
        RolloutUpdateType = $SecureBoot.RolloutStatus.UpdateType
        RolloutRebootPending = [bool]$SecureBoot.RolloutStatus.RebootPending
        RolloutMissingKek = [bool]$SecureBoot.RolloutStatus.MissingKek
        Event1808Count = [int]$event1808Count
        Event1799Count = [int]$event1799Count
        MicrosoftCompletionConfirmed = [bool]$microsoftCompletionConfirmed
        MicrosoftCompletionEvidence = @(
            if ($statusUpdated) { 'RegistryUEFICA2023StatusUpdated' }
            if ($latestCompletionEventIs1808) { 'LatestTpmWmiEvent1808' }
        )
        DirectCertificateRequirementsSatisfied = [bool]$SecureBoot.FirmwareVariables.DirectRequirementsSatisfied
        DirectFirmwareCertificatesConfirmed = [bool]$directFirmwareCertificatesConfirmed
        BootManagerPresent = [bool]$bootManagerPresent
        BootManager2023EvidenceConfirmed = [bool]$bootManager2023EvidenceConfirmed
        BootManager2023EvidenceSources = $bootManager2023EvidenceSources.ToArray()
        WindowsUEFICA2023CapableInterpretation = $capableInterpretation
        BootManagerAuthenticodePrimarySignerSubject = $bootManagerPrimarySignerSubject
        BootManagerAuthenticodePrimarySignerIndicatesWindowsUefiCa2023 = [bool]$bootManagerPrimarySigner2023
        BootManagerAuthenticodePrimarySignerIndicatesWindowsProductionPca2011 = [bool]$bootManagerPrimarySigner2011
        BootManagerAuthenticodeAssessmentScope = 'DiagnosticOnlyPrimarySignerReturnedByGetAuthenticodeSignature'
        BootManagerAuthenticodeDiagnosticNote = 'Get-AuthenticodeSignature returns a selected primary signer and is retained as diagnostic evidence only; Microsoft rollout completion is evaluated from UEFICA2023Status and the latest rollout event.'
        # Retain legacy property names for consumers, but make their diagnostic
        # scope explicit through BootManagerSignerAssessmentScope.
        BootManagerPrimarySignerIndicatesWindowsUefiCa2023 = [bool]$bootManagerPrimarySigner2023
        BootManagerPrimarySignerIndicatesWindowsProductionPca2011 = [bool]$bootManagerPrimarySigner2011
        BootManagerSignedByWindowsUefiCa2023 = [bool]$bootManagerPrimarySigner2023
        BootManagerSignedByWindowsProductionPca2011 = [bool]$bootManagerPrimarySigner2011
        BootManagerSignerAssessmentScope = 'DiagnosticOnlyPrimarySignerReturnedByGetAuthenticodeSignature'
        ConsistencyFindings = $findings.ToArray()
        InformationalFindings = $information.ToArray()
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
        CollectionComplete = $false
        DriveLetter = $driveLetter
        ErrorMessage = $null
        Files = @()
        BcdStore = $null
    }

    try {
        $mount = Invoke-CapturedCommand -FilePath "$env:SystemRoot\System32\mountvol.exe" `
            -ArgumentList @("$driveLetter`:", '/S')

        if (-not $mount.Started -or $mount.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $root -PathType Container)) {
            throw "mountvol /S failed. Started=$($mount.Started); ExitCode=$($mount.ExitCode); Error=$($mount.ErrorMessage); $($mount.StdErr)"
        }
        $mounted = $true
        $result.Available = $true

        $fileDefinitions = @(
            [pscustomobject]@{ RelativePath = 'EFI\Microsoft\Boot\bootmgfw.efi'; SkipHash = $false; SkipAuthenticode = $false },
            [pscustomobject]@{ RelativePath = 'EFI\Microsoft\Boot\bootmgr.efi'; SkipHash = $false; SkipAuthenticode = $false },
            [pscustomobject]@{ RelativePath = 'EFI\Microsoft\Boot\boot.stl'; SkipHash = $false; SkipAuthenticode = $false },
            # The active BCD hive can be locked by the operating system.
            # Record its metadata and query it with bcdedit instead of trying
            # to hash or Authenticode-validate a non-PE registry hive.
            [pscustomobject]@{ RelativePath = 'EFI\Microsoft\Boot\BCD'; SkipHash = $true; SkipAuthenticode = $true },
            [pscustomobject]@{ RelativePath = 'EFI\Boot\bootx64.efi'; SkipHash = $false; SkipAuthenticode = $false }
        )

        $result.Files = @(
            foreach ($definition in $fileDefinitions) {
                Get-FileEvidence `
                    -Path (Join-Path $root $definition.RelativePath) `
                    -SkipHash:$definition.SkipHash `
                    -SkipAuthenticode:$definition.SkipAuthenticode
            }
        )

        $bcdPath = Join-Path $root 'EFI\Microsoft\Boot\BCD'
        if (Test-Path -LiteralPath $bcdPath -PathType Leaf) {
            $result.BcdStore = Invoke-CapturedCommand `
                -FilePath "$env:SystemRoot\System32\bcdedit.exe" `
                -ArgumentList @('/store', $bcdPath, '/enum', 'all', '/v')
        }

        $fileReadFailures = @(
            $result.Files | Where-Object {
                -not $_.Present -or
                -not [string]::IsNullOrWhiteSpace($_.ReadErrorMessage) -or
                (-not $_.HashSkipped -and (
                    [string]::IsNullOrWhiteSpace($_.Sha256) -or
                    -not [string]::IsNullOrWhiteSpace($_.HashErrorMessage)
                )) -or
                (-not $_.AuthenticodeSkipped -and (
                    [string]::IsNullOrWhiteSpace($_.AuthenticodeStatus) -or
                    -not [string]::IsNullOrWhiteSpace($_.AuthenticodeErrorMessage)
                ))
            }
        )

        $bcdQuerySucceeded = (
            $null -ne $result.BcdStore -and
            $result.BcdStore.Started -and
            $result.BcdStore.Succeeded
        )

        $result.CollectionComplete = (
            $fileReadFailures.Count -eq 0 -and
            $bcdQuerySucceeded
        )

        if (-not $result.CollectionComplete) {
            $details = New-Object 'System.Collections.Generic.List[string]'
            if ($fileReadFailures.Count -gt 0) {
                $details.Add("$($fileReadFailures.Count) ESP file evidence item(s) were incomplete.")
            }
            if (-not $bcdQuerySucceeded) {
                $details.Add('The offline BCD store query did not complete successfully.')
            }
            $result.ErrorMessage = [string]::Join(' ', $details)
        }
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
    }
    finally {
        if ($mounted) {
            $unmount = Invoke-CapturedCommand -FilePath "$env:SystemRoot\System32\mountvol.exe" `
                -ArgumentList @("$driveLetter`:", '/D')
            if (-not $unmount.Started -or $unmount.ExitCode -ne 0) {
                $cleanupMessage = "mountvol /D cleanup failed. Started=$($unmount.Started); ExitCode=$($unmount.ExitCode); Error=$($unmount.ErrorMessage); $($unmount.StdErr)"
                $result.CollectionComplete = $false
                if ([string]::IsNullOrWhiteSpace($result.ErrorMessage)) {
                    $result.ErrorMessage = $cleanupMessage
                }
                else {
                    $result.ErrorMessage = $result.ErrorMessage + ' ' + $cleanupMessage
                }
            }
        }
    }

    return $result
}


function Get-NormalizedDirectoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if (-not [string]::Equals($fullPath, $root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $fullPath = $fullPath.TrimEnd('\', '/')
    }

    return $fullPath
}

function Resolve-OutputRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$RequestedPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptDirectory
    )

    $normalizedScriptDirectory = Get-NormalizedDirectoryPath -Path $ScriptDirectory
    $normalizedTempDirectory = Get-NormalizedDirectoryPath -Path 'C:\Temp'

    $resolvedPath = if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        $normalizedScriptDirectory
    }
    else {
        Get-NormalizedDirectoryPath -Path $RequestedPath
    }

    $isScriptDirectory = [string]::Equals(
        $resolvedPath,
        $normalizedScriptDirectory,
        [System.StringComparison]::OrdinalIgnoreCase
    )
    $isTempDirectory = [string]::Equals(
        $resolvedPath,
        $normalizedTempDirectory,
        [System.StringComparison]::OrdinalIgnoreCase
    )

    if (-not $isScriptDirectory -and -not $isTempDirectory) {
        throw (
            "OutputRoot must be either the script directory '$normalizedScriptDirectory' " +
            "or 'C:\Temp'. Requested: '$resolvedPath'."
        )
    }

    return $resolvedPath
}

function Resolve-WindowsServerIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$CurrentVersion,

        [Parameter(Mandatory = $true)]
        [object]$OperatingSystem
    )

    $productName = [string](Get-PropertyValue -InputObject $CurrentVersion -Name 'ProductName')
    $editionId = [string](Get-PropertyValue -InputObject $CurrentVersion -Name 'EditionID')
    $installationType = [string](Get-PropertyValue -InputObject $CurrentVersion -Name 'InstallationType')
    $caption = [string](Get-PropertyValue -InputObject $OperatingSystem -Name 'Caption')
    $productTypeValue = Get-PropertyValue -InputObject $OperatingSystem -Name 'ProductType'
    $productType = if ($null -ne $productTypeValue) { [int]$productTypeValue } else { $null }

    $currentBuild = [string](Get-PropertyValue -InputObject $CurrentVersion -Name 'CurrentBuild')
    if ([string]::IsNullOrWhiteSpace($currentBuild)) {
        $currentBuild = [string](Get-PropertyValue -InputObject $CurrentVersion -Name 'CurrentBuildNumber')
    }

    $buildMap = @{
        '14393' = 'Server2016'
        '17763' = 'Server2019'
        '20348' = 'Server2022'
        '26100' = 'Server2025'
    }

    $buildMappedVersion = $null
    if (-not [string]::IsNullOrWhiteSpace($currentBuild) -and $buildMap.ContainsKey($currentBuild)) {
        $buildMappedVersion = [string]$buildMap[$currentBuild]
    }

    $nameText = @($caption, $productName) -join ' | '
    $nameMappedVersion = $null
    foreach ($year in @('2016', '2019', '2022', '2025')) {
        if ($nameText -match $year) {
            $nameMappedVersion = 'Server{0}' -f $year
            break
        }
    }

    # ProductType 2/3 are server OS values. ProductName/Caption and
    # InstallationType are retained as independent corroborating signals.
    $serverByProductType = ($productType -eq 2 -or $productType -eq 3)
    $serverByName = ($caption -match 'Windows Server' -or $productName -match 'Windows Server')
    $serverByInstallationType = ($installationType -match '^Server(?: Core)?$')
    $isWindowsServer = ($serverByProductType -or $serverByName -or $serverByInstallationType)

    $versionConflict = (
        -not [string]::IsNullOrWhiteSpace($buildMappedVersion) -and
        -not [string]::IsNullOrWhiteSpace($nameMappedVersion) -and
        $buildMappedVersion -ne $nameMappedVersion
    )

    $resolvedVersion = 'Unknown'
    $detectionMethod = 'None'
    $confidence = 'None'

    if ($isWindowsServer -and -not [string]::IsNullOrWhiteSpace($buildMappedVersion)) {
        $resolvedVersion = $buildMappedVersion
        $detectionMethod = if (-not [string]::IsNullOrWhiteSpace($nameMappedVersion)) {
            'BuildNumberAndProductIdentity'
        }
        else {
            'BuildNumberAndServerSignals'
        }
        $confidence = if ($versionConflict) { 'Conflict' } else { 'High' }
    }
    elseif ($isWindowsServer -and -not [string]::IsNullOrWhiteSpace($nameMappedVersion)) {
        $resolvedVersion = $nameMappedVersion
        $detectionMethod = 'ProductIdentityFallback'
        $confidence = 'Medium'
    }

    $supportedVersions = @('Server2016', 'Server2019', 'Server2022', 'Server2025')
    $isSupportedVersion = ($supportedVersions -contains $resolvedVersion)

    $messages = New-Object 'System.Collections.Generic.List[string]'
    if (-not $isWindowsServer) {
        $messages.Add(
            "The running operating system was not identified as Windows Server. " +
            "Caption='$caption'; ProductName='$productName'; InstallationType='$installationType'; ProductType='$productType'."
        )
    }
    if ([string]::IsNullOrWhiteSpace($currentBuild)) {
        $messages.Add('The Windows CurrentBuild/CurrentBuildNumber value could not be obtained.')
    }
    elseif ([string]::IsNullOrWhiteSpace($buildMappedVersion)) {
        $messages.Add("CurrentBuild '$currentBuild' is not mapped to a supported project Windows Server version.")
    }
    if ($versionConflict) {
        $messages.Add(
            "Windows Server version signals conflict: build '$currentBuild' maps to " +
            "'$buildMappedVersion', while product identity maps to '$nameMappedVersion'."
        )
    }
    if ($isWindowsServer -and -not $isSupportedVersion) {
        $messages.Add("The detected Windows Server version '$resolvedVersion' is not supported by this collector revision.")
    }

    return [pscustomobject][ordered]@{
        OsVersionKey = $resolvedVersion
        IsWindowsServer = [bool]$isWindowsServer
        IsSupportedVersion = [bool]$isSupportedVersion
        DetectionComplete = [bool](
            $isWindowsServer -and
            $isSupportedVersion -and
            -not [string]::IsNullOrWhiteSpace($currentBuild) -and
            -not $versionConflict
        )
        DetectionMethod = $detectionMethod
        Confidence = $confidence
        VersionConflict = [bool]$versionConflict
        CurrentBuild = $currentBuild
        BuildMappedVersion = $buildMappedVersion
        NameMappedVersion = $nameMappedVersion
        Caption = $caption
        ProductName = $productName
        EditionId = $editionId
        InstallationType = $installationType
        ProductType = $productType
        ServerSignals = [pscustomobject][ordered]@{
            ProductType = [bool]$serverByProductType
            ProductIdentity = [bool]$serverByName
            InstallationType = [bool]$serverByInstallationType
        }
        ValidationMessages = $messages.ToArray()
    }
}


function New-AssessmentItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PASS', 'FAIL', 'REVIEW', 'INFO')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Detail = ''
    )

    return [pscustomobject][ordered]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
    }
}

function Get-PostInstallAssessmentItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$OsIdentity,
        [Parameter(Mandatory = $true)] [string]$DetectedOsKey,
        [Parameter(Mandatory = $true)] [string]$FullBuild,
        [Parameter(Mandatory = $true)] [object]$Packages,
        [Parameter(Mandatory = $true)] [object]$WindowsFeatures,
        [Parameter(Mandatory = $true)] [object]$DotNetFramework,
        [Parameter(Mandatory = $true)] [object]$SecureBoot,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]]$KernelFiles,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]]$ProblemDevices,
        [Parameter(Mandatory = $true)] [object]$PendingReboot,
        [Parameter(Mandatory = $true)] [object]$Reagent,
        [Parameter(Mandatory = $true)] [object]$BcdCurrent,
        [Parameter(Mandatory = $true)] [object]$BcdBootManager,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]]$DiskEvidence,
        [Parameter(Mandatory = $true)] [object]$Esp,
        [Parameter(Mandatory = $true)] [object]$SystemInfo,
        [Parameter(Mandatory = $true)] [object]$MsInfo32,
        [Parameter(Mandatory = $true)] [bool]$InspectEspRequested,
        [Parameter(Mandatory = $true)] [bool]$MsInfo32Requested,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [string[]]$ValidationFailures,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [string[]]$CollectionFailures,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [string[]]$ReviewFindings
    )

    $items = New-Object 'System.Collections.Generic.List[object]'

    $osStatus = if ($OsIdentity.DetectionComplete) { 'PASS' } else { 'FAIL' }
    $items.Add((New-AssessmentItem -Name 'Operating system identity' -Status $osStatus -Detail (
        '{0}; build {1}; confidence {2}' -f $DetectedOsKey, $FullBuild, $OsIdentity.Confidence
    )))

    $packageStatus = if ($Packages.Available) { 'PASS' } else { 'REVIEW' }
    $packageDetail = if ($Packages.Available) {
        '{0} relevant servicing package(s) recorded' -f @($Packages.Packages).Count
    }
    else {
        [string]$Packages.ErrorMessage
    }
    $items.Add((New-AssessmentItem -Name 'Servicing packages' -Status $packageStatus -Detail $packageDetail))

    $featureStatus = if ($WindowsFeatures.Available) { 'PASS' } else { 'REVIEW' }
    $featureDetail = if ($WindowsFeatures.Available) {
        '{0}; installed {1} of {2}' -f $WindowsFeatures.Source, $WindowsFeatures.InstalledFeatureCount, $WindowsFeatures.FeatureCount
    }
    else {
        [string]$WindowsFeatures.ErrorMessage
    }
    $items.Add((New-AssessmentItem -Name 'Windows Server features' -Status $featureStatus -Detail $featureDetail))

    $dotNetFindings = @($DotNetFramework.ConsistencyFindings)
    $dotNetStatus = if (-not $DotNetFramework.Available) {
        'REVIEW'
    }
    elseif ($dotNetFindings.Count -gt 0) {
        'FAIL'
    }
    else {
        'PASS'
    }
    $netFx3State = if ($WindowsFeatures.DotNetFeatureState.NetFx3Installed) { 'Enabled' } else { 'Disabled' }
    $netFx4State = if ($WindowsFeatures.DotNetFeatureState.NetFx4Installed) { 'Enabled' } else { 'Disabled' }
    $netFx4Version = [string]$DotNetFramework.RegistryState.NetFx4ResolvedVersion
    if ([string]::IsNullOrWhiteSpace($netFx4Version)) { $netFx4Version = 'not detected' }
    $dotNetDetail = 'NetFx3={0}; NetFx4={1}; registry version={2}' -f $netFx3State, $netFx4State, $netFx4Version
    if ($dotNetFindings.Count -gt 0) {
        $dotNetDetail += '; ' + [string]::Join(' | ', $dotNetFindings)
    }
    $items.Add((New-AssessmentItem -Name '.NET Framework' -Status $dotNetStatus -Detail $dotNetDetail))

    $secureBootStatus = if ($SecureBoot.Supported -and $SecureBoot.Enabled -eq $true) { 'PASS' } else { 'FAIL' }
    $secureBootDetail = 'supported={0}; enabled={1}' -f $SecureBoot.Supported, $SecureBoot.Enabled
    $items.Add((New-AssessmentItem -Name 'UEFI Secure Boot' -Status $secureBootStatus -Detail $secureBootDetail))

    $secureBootFindings = @($SecureBoot.Assessment.ConsistencyFindings)
    $rolloutStatus = if ($SecureBoot.Enabled -ne $true) {
        'INFO'
    }
    elseif ($secureBootFindings.Count -gt 0) {
        'FAIL'
    }
    elseif ($SecureBoot.Assessment.MicrosoftCompletionConfirmed) {
        'PASS'
    }
    else {
        'INFO'
    }
    $rolloutDetail = 'state={0}; registry={1}; latest event={2}; direct certificates={3}' -f `
        $SecureBoot.Assessment.State,
        $SecureBoot.Registry.UEFICA2023Status,
        $SecureBoot.Assessment.LatestRolloutEventId,
        $SecureBoot.Assessment.DirectFirmwareCertificatesConfirmed
    if ($secureBootFindings.Count -gt 0) {
        $rolloutDetail += '; ' + [string]::Join(' | ', $secureBootFindings)
    }
    $items.Add((New-AssessmentItem -Name 'Secure Boot 2023 rollout' -Status $rolloutStatus -Detail $rolloutDetail))

    $firmwareVariableStatus = if ($SecureBoot.Enabled -ne $true) {
        'INFO'
    }
    elseif ($SecureBoot.FirmwareVariables.RequiredVariablesAvailable) {
        'PASS'
    }
    else {
        'REVIEW'
    }
    $firmwareVariableDetail = 'db/KEK available={0}; direct requirements={1}' -f `
        $SecureBoot.FirmwareVariables.RequiredVariablesAvailable,
        $SecureBoot.FirmwareVariables.DirectRequirementsSatisfied
    $items.Add((New-AssessmentItem -Name 'Secure Boot firmware variables' -Status $firmwareVariableStatus -Detail $firmwareVariableDetail))

    $scriptInventory = $SecureBoot.MicrosoftScriptInventory
    $scriptInventoryStatus = if ($scriptInventory.Summary.FileCount -eq 0) {
        'INFO'
    }
    elseif ($scriptInventory.Summary.InvalidSignatureFileCount -gt 0 -or
        $scriptInventory.Summary.UnexpectedSignerFileCount -gt 0) {
        'FAIL'
    }
    elseif ($scriptInventory.Summary.CollectionIssueCount -gt 0) {
        'REVIEW'
    }
    else {
        'PASS'
    }
    $scriptInventoryDetail = if ($scriptInventory.Summary.FileCount -eq 0) {
        'Microsoft rollout script directory not present; optional inventory item'
    }
    else {
        'files={0}; valid Microsoft signatures={1}; invalid signatures={2}; unexpected signers={3}; collection issues={4}; baseline hash comparison=disabled' -f `
            $scriptInventory.Summary.FileCount,
            $scriptInventory.Summary.ValidMicrosoftSignedFileCount,
            $scriptInventory.Summary.InvalidSignatureFileCount,
            $scriptInventory.Summary.UnexpectedSignerFileCount,
            $scriptInventory.Summary.CollectionIssueCount
    }
    $items.Add((New-AssessmentItem -Name 'Microsoft Secure Boot scripts' -Status $scriptInventoryStatus -Detail $scriptInventoryDetail))

    $invalidKernelSignatures = @(
        $KernelFiles | Where-Object { $_.Present -and $_.AuthenticodeStatus -ne 'Valid' }
    )
    $incompleteKernelEvidence = @(
        $KernelFiles | Where-Object {
            -not $_.Present -or
            [string]::IsNullOrWhiteSpace($_.Sha256) -or
            -not [string]::IsNullOrWhiteSpace($_.HashErrorMessage) -or
            [string]::IsNullOrWhiteSpace($_.AuthenticodeStatus) -or
            -not [string]::IsNullOrWhiteSpace($_.AuthenticodeErrorMessage)
        }
    )
    $kernelStatus = if ($invalidKernelSignatures.Count -gt 0) {
        'FAIL'
    }
    elseif ($incompleteKernelEvidence.Count -gt 0) {
        'REVIEW'
    }
    else {
        'PASS'
    }
    $kernelDetail = '{0} file(s); invalid signatures={1}; incomplete={2}' -f `
        @($KernelFiles).Count, $invalidKernelSignatures.Count, $incompleteKernelEvidence.Count
    $items.Add((New-AssessmentItem -Name 'Kernel and boot signatures' -Status $kernelStatus -Detail $kernelDetail))

    $deviceStatus = if (@($ProblemDevices).Count -eq 0) { 'PASS' } else { 'FAIL' }
    $items.Add((New-AssessmentItem -Name 'Problem devices' -Status $deviceStatus -Detail (
        '{0} problematic device(s)' -f @($ProblemDevices).Count
    )))

    $rebootStatus = if ($PendingReboot.BlockingRebootPending) {
        'FAIL'
    }
    elseif ($PendingReboot.AdvisoryRebootPending -or -not $PendingReboot.CollectionComplete) {
        'REVIEW'
    }
    else {
        'PASS'
    }
    $items.Add((New-AssessmentItem -Name 'Pending reboot' -Status $rebootStatus -Detail (
        'pending={0}; classification={1}; PFRO pairs={2}; advisory={3}; blocking={4}; readErrors={5}' -f `
            $PendingReboot.RebootPending,
            $PendingReboot.Classification,
            $PendingReboot.PendingFileRenameOperations.PairCount,
            $PendingReboot.PendingFileRenameOperations.AdvisoryOperationCount,
            $PendingReboot.PendingFileRenameOperations.BlockingOperationCount,
            $PendingReboot.ReadErrorCount
    )))

    $winReStatus = if ($Reagent.Started -and $Reagent.Succeeded) { 'PASS' } else { 'REVIEW' }
    $items.Add((New-AssessmentItem -Name 'Windows Recovery Environment' -Status $winReStatus -Detail (
        'reagentc started={0}; exit code={1}' -f $Reagent.Started, $Reagent.ExitCode
    )))

    $bcdStatus = if (
        $BcdCurrent.Started -and $BcdCurrent.Succeeded -and
        $BcdBootManager.Started -and $BcdBootManager.Succeeded
    ) { 'PASS' } else { 'REVIEW' }
    $items.Add((New-AssessmentItem -Name 'Boot configuration data' -Status $bcdStatus -Detail (
        'current exit={0}; bootmgr exit={1}' -f $BcdCurrent.ExitCode, $BcdBootManager.ExitCode
    )))

    $systemInfoStatus = if ($SystemInfo.Started -and $SystemInfo.Succeeded) { 'PASS' } else { 'REVIEW' }
    $items.Add((New-AssessmentItem -Name 'System information command' -Status $systemInfoStatus -Detail (
        'systeminfo started={0}; exit code={1}' -f $SystemInfo.Started, $SystemInfo.ExitCode
    )))

    $diskStatus = if (@($DiskEvidence).Count -gt 0) { 'PASS' } else { 'REVIEW' }
    $diskDetail = if (@($DiskEvidence).Count -gt 0) {
        '{0} disk(s) recorded' -f @($DiskEvidence).Count
    }
    else {
        'No disk evidence was collected'
    }
    $items.Add((New-AssessmentItem -Name 'Disk layout' -Status $diskStatus -Detail $diskDetail))

    $espStatus = if (-not $InspectEspRequested) {
        'INFO'
    }
    elseif ($Esp.Available -and $Esp.CollectionComplete) {
        'PASS'
    }
    else {
        'REVIEW'
    }
    $espDetail = if (-not $InspectEspRequested) {
        'Disabled by caller'
    }
    else {
        'available={0}; complete={1}; files={2}' -f $Esp.Available, $Esp.CollectionComplete, @($Esp.Files).Count
    }
    $items.Add((New-AssessmentItem -Name 'EFI System Partition' -Status $espStatus -Detail $espDetail))

    $msInfoStatus = if (-not $MsInfo32Requested) {
        'INFO'
    }
    elseif ($MsInfo32.Available -and $null -ne $MsInfo32.ExitCode -and [int]$MsInfo32.ExitCode -eq 0) {
        'PASS'
    }
    else {
        'REVIEW'
    }
    $msInfoDetail = if (-not $MsInfo32Requested) {
        'Disabled by caller'
    }
    else {
        'available={0}; exit code={1}' -f $MsInfo32.Available, $MsInfo32.ExitCode
    }
    $items.Add((New-AssessmentItem -Name 'MSInfo32 report' -Status $msInfoStatus -Detail $msInfoDetail))

    $validationStatus = if (@($ValidationFailures).Count -eq 0) { 'PASS' } else { 'FAIL' }
    $validationDetail = if (@($ValidationFailures).Count -eq 0) {
        'No validation failure was detected'
    }
    else {
        '{0} validation failure(s)' -f @($ValidationFailures).Count
    }
    $items.Add((New-AssessmentItem -Name 'Validation checks' -Status $validationStatus -Detail $validationDetail))

    $collectionStatus = if (@($CollectionFailures).Count -eq 0) { 'PASS' } else { 'REVIEW' }
    $collectionDetail = if (@($CollectionFailures).Count -eq 0) {
        'All required evidence collections completed'
    }
    else {
        '{0} collection issue(s)' -f @($CollectionFailures).Count
    }
    $items.Add((New-AssessmentItem -Name 'Collection completeness' -Status $collectionStatus -Detail $collectionDetail))

    $reviewStatus = if (@($ReviewFindings).Count -eq 0) { 'PASS' } else { 'REVIEW' }
    $reviewDetail = if (@($ReviewFindings).Count -eq 0) {
        'No operational review finding was detected'
    }
    else {
        '{0} operational review finding(s)' -f @($ReviewFindings).Count
    }
    $items.Add((New-AssessmentItem -Name 'Operational review findings' -Status $reviewStatus -Detail $reviewDetail))

    return $items.ToArray()
}

function Get-AssessmentReportLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$AssessmentItems,
        [Parameter(Mandatory = $true)] [string]$OverallStatus,
        [Parameter(Mandatory = $true)] [int]$ExitCode,
        [Parameter(Mandatory = $true)] [string]$EvidenceDirectory,
        [Parameter(Mandatory = $true)] [string]$ZipPath
    )

    $passCount = @($AssessmentItems | Where-Object { $_.Status -eq 'PASS' }).Count
    $failCount = @($AssessmentItems | Where-Object { $_.Status -eq 'FAIL' }).Count
    $reviewCount = @($AssessmentItems | Where-Object { $_.Status -eq 'REVIEW' }).Count
    $infoCount = @($AssessmentItems | Where-Object { $_.Status -eq 'INFO' }).Count
    $displayStatus = switch ($OverallStatus) {
        'Pass' { 'PASS' }
        'Fail' { 'FAIL' }
        'ReviewRequired' { 'REVIEW REQUIRED' }
        'PreconditionNotMet' { 'PRECONDITION NOT MET' }
        'FatalError' { 'FATAL ERROR' }
        default { $OverallStatus.ToUpperInvariant() }
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('')
    $lines.Add('================================================================================================================')
    $lines.Add(' WINDOWS SERVER POST-INSTALL VALIDATION REPORT')
    $lines.Add('================================================================================================================')
    foreach ($item in $AssessmentItems) {
        $statusLabel = ('[{0}]' -f $item.Status).PadRight(9)
        $lines.Add(('{0}{1,-34} {2}' -f $statusLabel, $item.Name, $item.Detail))
    }
    $lines.Add('----------------------------------------------------------------------------------------------------------------')
    $lines.Add(('RESULT COUNTS : PASS={0}  FAIL={1}  REVIEW={2}  INFO={3}' -f $passCount, $failCount, $reviewCount, $infoCount))
    $lines.Add(('FINAL RESULT  : {0}' -f $displayStatus))
    $lines.Add(('EXIT CODE     : {0}' -f $ExitCode))
    $lines.Add(('EVIDENCE DIR  : {0}' -f $EvidenceDirectory))
    $lines.Add(('EVIDENCE ZIP  : {0}' -f $ZipPath))
    $lines.Add('================================================================================================================')
    return $lines.ToArray()
}

function Write-AssessmentConsoleReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$AssessmentItems,
        [Parameter(Mandatory = $true)] [string]$OverallStatus,
        [Parameter(Mandatory = $true)] [int]$ExitCode,
        [Parameter(Mandatory = $true)] [string]$EvidenceDirectory,
        [Parameter(Mandatory = $true)] [string]$ZipPath
    )

    Write-Host ''
    Write-Host '================================================================================================================' -ForegroundColor Cyan
    Write-Host ' WINDOWS SERVER POST-INSTALL VALIDATION REPORT' -ForegroundColor Cyan
    Write-Host '================================================================================================================' -ForegroundColor Cyan

    foreach ($item in $AssessmentItems) {
        $color = switch ($item.Status) {
            'PASS' { 'Green' }
            'FAIL' { 'Red' }
            'REVIEW' { 'Yellow' }
            default { 'Cyan' }
        }
        $statusLabel = ('[{0}]' -f $item.Status).PadRight(9)
        Write-Host $statusLabel -NoNewline -ForegroundColor $color
        Write-Host ('{0,-34} {1}' -f $item.Name, $item.Detail)
    }

    $passCount = @($AssessmentItems | Where-Object { $_.Status -eq 'PASS' }).Count
    $failCount = @($AssessmentItems | Where-Object { $_.Status -eq 'FAIL' }).Count
    $reviewCount = @($AssessmentItems | Where-Object { $_.Status -eq 'REVIEW' }).Count
    $infoCount = @($AssessmentItems | Where-Object { $_.Status -eq 'INFO' }).Count
    $displayStatus = switch ($OverallStatus) {
        'Pass' { 'PASS' }
        'Fail' { 'FAIL' }
        'ReviewRequired' { 'REVIEW REQUIRED' }
        'PreconditionNotMet' { 'PRECONDITION NOT MET' }
        'FatalError' { 'FATAL ERROR' }
        default { $OverallStatus.ToUpperInvariant() }
    }
    $finalColor = switch ($OverallStatus) {
        'Pass' { 'Green' }
        'Fail' { 'Red' }
        'FatalError' { 'Red' }
        default { 'Yellow' }
    }

    Write-Host '----------------------------------------------------------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ('RESULT COUNTS : PASS={0}  FAIL={1}  REVIEW={2}  INFO={3}' -f $passCount, $failCount, $reviewCount, $infoCount)
    Write-Host 'FINAL RESULT  : ' -NoNewline
    Write-Host $displayStatus -ForegroundColor $finalColor
    Write-Host ('EXIT CODE     : {0}' -f $ExitCode)
    Write-Host ('EVIDENCE DIR  : {0}' -f $EvidenceDirectory)
    Write-Host ('EVIDENCE ZIP  : {0}' -f $ZipPath)
    Write-Host '================================================================================================================' -ForegroundColor Cyan
}

$scriptDirectory = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Get-NormalizedDirectoryPath -Path $PSScriptRoot
}
else {
    Get-NormalizedDirectoryPath -Path (Get-Location).ProviderPath
}
$resolvedOutputRoot = Resolve-OutputRoot -RequestedPath $OutputRoot -ScriptDirectory $scriptDirectory
New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null

# Resolve the installed Windows Server version before naming the evidence
# artifact. This replaces the former caller-supplied expected-version value.
$identityPreflightError = $null
$cvPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$cv = $null
$os = $null
$osIdentity = $null
try {
    $cv = Get-ItemProperty -LiteralPath $cvPath -ErrorAction Stop
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $osIdentity = Resolve-WindowsServerIdentity -CurrentVersion $cv -OperatingSystem $os
}
catch {
    $identityPreflightError = $_.Exception.Message
    $osIdentity = [pscustomobject][ordered]@{
        OsVersionKey = 'Unknown'
        IsWindowsServer = $false
        IsSupportedVersion = $false
        DetectionComplete = $false
        DetectionMethod = 'PreflightFailure'
        Confidence = 'None'
        VersionConflict = $false
        CurrentBuild = $null
        BuildMappedVersion = $null
        NameMappedVersion = $null
        Caption = $null
        ProductName = $null
        EditionId = $null
        InstallationType = $null
        ProductType = $null
        ServerSignals = [pscustomobject][ordered]@{
            ProductType = $false
            ProductIdentity = $false
            InstallationType = $false
        }
        ValidationMessages = @("Operating system identity preflight failed: $identityPreflightError")
    }
}

$detectedOsKey = [string]$osIdentity.OsVersionKey
$artifactOsToken = if (
    [string]::IsNullOrWhiteSpace($detectedOsKey) -or
    $detectedOsKey -notmatch '^Server(?:2016|2019|2022|2025)$'
) {
    'UnknownWindowsServer'
}
else {
    $detectedOsKey
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$evidenceName = 'windows-server-post-install-evidence-{0}-{1}-{2}' -f `
    $artifactOsToken, $script:CollectorVersion, $timestamp
$evidenceDir = Join-Path $resolvedOutputRoot $evidenceName
$zipPath = Join-Path $resolvedOutputRoot ($evidenceName + '.zip')
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

$transcriptPath = Join-Path $evidenceDir 'transcript.log'
Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null

$exitCode = 0
$summary = $null
$assessmentItems = @()
$fatalErrorMessage = $null
try {
    Write-Host '============================================================'
    Write-Host (' Windows Server Post-Install Evidence Collector {0}' -f $script:CollectorVersion)
    Write-Host '============================================================'
    Write-Host "Detected OS       : $detectedOsKey"
    Write-Host "Detection method  : $($osIdentity.DetectionMethod)"
    Write-Host "Detection confidence: $($osIdentity.Confidence)"
    Write-Host "Evidence directory: $evidenceDir"

    if (-not [string]::IsNullOrWhiteSpace($identityPreflightError)) {
        throw "Operating system identity preflight failed: $identityPreflightError"
    }

    do {
        Write-PostInstallRestartPrerequisiteBanner
        $restartConfirmation = Get-PostInstallRestartConfirmation -ConfirmedByParameter:$ConfirmPostInstallRestart
        $bootHistory = Get-BootHistoryEvidence -OperatingSystem $os
        $pendingRebootAtStart = Get-PendingRebootEvidence
        $startupDecision = Resolve-StartupPreflightDecision `
            -RestartConfirmation $restartConfirmation `
            -PendingReboot $pendingRebootAtStart `
            -BootHistory $bootHistory
        $startupPreflight = [pscustomobject][ordered]@{
            SchemaVersion = 'windows-server-post-install-startup-preflight/1.0'
            GeneratedAtUtc = Get-UtcTimestamp
            RestartConfirmation = $restartConfirmation
            PendingRebootAtStart = $pendingRebootAtStart
            BootHistory = $bootHistory
            Decision = $startupDecision
        }
        $startupPreflight | ConvertTo-Json -Depth 16 |
            Set-Content -LiteralPath (Join-Path $evidenceDir 'startup-preflight.json') -Encoding UTF8

        Write-Host ('Post-install restart confirmed : {0} ({1})' -f $restartConfirmation.Confirmed, $restartConfirmation.Source)
        Write-Host ('Startup pending reboot         : {0}' -f $pendingRebootAtStart.Classification)
        Write-Host ('Boot history corroboration     : {0} (informational only)' -f $bootHistory.Corroboration)

        if (-not $startupDecision.AllowedToCollect) {
            $preflightItems = New-Object 'System.Collections.Generic.List[object]'
            $preflightItems.Add((New-AssessmentItem `
                -Name 'Post-install restart confirmation' `
                -Status $(if ($restartConfirmation.Confirmed) { 'PASS' } else { 'REVIEW' }) `
                -Detail $(if ($restartConfirmation.Confirmed) { 'Explicitly confirmed' } else { 'Restart not confirmed; reboot the guest OS and rerun the collector' })))

            $pendingStatus = if ($pendingRebootAtStart.CollectionComplete -ne $true) {
                'REVIEW'
            }
            elseif ($pendingRebootAtStart.BlockingRebootPending) {
                'FAIL'
            }
            elseif ($pendingRebootAtStart.RebootPending) {
                'REVIEW'
            }
            else {
                'PASS'
            }
            $preflightItems.Add((New-AssessmentItem `
                -Name 'Startup pending reboot gate' `
                -Status $pendingStatus `
                -Detail ('classification={0}; collectionComplete={1}' -f $pendingRebootAtStart.Classification, $pendingRebootAtStart.CollectionComplete)))
            $preflightItems.Add((New-AssessmentItem `
                -Name 'Boot history corroboration' `
                -Status 'INFO' `
                -Detail ('{0}; bootStartAfterInstall={1}; normalRestartAfterInstall={2}; not authoritative' -f `
                    $bootHistory.Corroboration, $bootHistory.BootStartEventCountAfterInstallDate, $bootHistory.NormalRestartEventCountAfterInstallDate)))

            $assessmentItems = $preflightItems.ToArray()
            $reviewMessages = New-Object 'System.Collections.Generic.List[string]'
            foreach ($reason in @($startupDecision.Reasons)) { $reviewMessages.Add([string]$reason) }
            $reviewMessages.Add('Full post-install evidence collection was intentionally not started. Restart the guest OS if needed, wait for the reboot to complete, and rerun the collector.')
            $summary = [pscustomobject][ordered]@{
                SchemaVersion = $script:SchemaVersion
                CollectorVersion = $script:CollectorVersion
                GeneratedAtUtc = Get-UtcTimestamp
                DetectedOsVersion = $detectedOsKey
                OperatingSystemDetection = $osIdentity
                OverallStatus = 'PreconditionNotMet'
                AssessmentItems = @($assessmentItems)
                ValidationFailures = @()
                CollectionFailures = @()
                ReviewFindings = $reviewMessages.ToArray()
                StartupPreflight = $startupPreflight
                FullEvidenceCollectionStarted = $false
            }
            $summary | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath (Join-Path $evidenceDir 'summary.json') -Encoding UTF8
            @(
                "SchemaVersion: $($summary.SchemaVersion)"
                "CollectorVersion: $($summary.CollectorVersion)"
                "GeneratedAtUtc: $($summary.GeneratedAtUtc)"
                'OverallStatus: PreconditionNotMet'
                "DetectedOsVersion: $detectedOsKey"
                "PostInstallRestartConfirmed: $($restartConfirmation.Confirmed)"
                "StartupPendingRebootClassification: $($pendingRebootAtStart.Classification)"
                "BootHistoryCorroboration: $($bootHistory.Corroboration)"
                'FullEvidenceCollectionStarted: False'
                ''
                'Reasons:'
                @($reviewMessages | ForEach-Object { "  - $_" })
            ) | Set-Content -LiteralPath (Join-Path $evidenceDir 'summary.txt') -Encoding UTF8
            Get-AssessmentReportLines `
                -AssessmentItems @($assessmentItems) `
                -OverallStatus 'PreconditionNotMet' `
                -ExitCode 2 `
                -EvidenceDirectory $evidenceDir `
                -ZipPath $zipPath |
                Set-Content -LiteralPath (Join-Path $evidenceDir 'assessment-report.txt') -Encoding UTF8
            $exitCode = 2
            Write-Warning 'Mandatory startup precondition was not met. Full evidence collection was not started.'
            break
        }

        Write-Host 'Startup precondition: PASS. Beginning full evidence collection.' -ForegroundColor Green
        Write-Host ''

        $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS
    $baseBoard = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
    $computerProduct = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue

    $currentBuild = [string]$osIdentity.CurrentBuild
    $ubrValue = Get-PropertyValue -InputObject $cv -Name 'UBR'
    $ubr = if ($null -ne $ubrValue) { [int]$ubrValue } else { $null }
    $fullBuild = if ($null -ne $ubr) { '{0}.{1}' -f $currentBuild, $ubr } else { $currentBuild }


    $secureBoot = Get-SecureBootEvidence -EvidenceDirectory $evidenceDir
    $packages = Get-InstalledPackageEvidence
    $windowsFeatures = Get-WindowsFeatureEvidence
    $dotNetFramework = Get-DotNetFrameworkEvidence -WindowsFeatures $windowsFeatures

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
            CollectionComplete = $false
            DriveLetter = $null
            ErrorMessage = $null
            Files = @()
            BcdStore = $null
        }
    }

    $secureBoot.Assessment = Get-SecureBootAssessment -SecureBoot $secureBoot -Esp $esp

    $msInfo = [pscustomobject][ordered]@{
        Requested = [bool]$IncludeMsInfo32
        Available = $false
        ExitCode = $null
        ErrorMessage = $null
        RelativePath = $null
    }
    if ($IncludeMsInfo32) {
        $msInfoPath = Join-Path $evidenceDir 'msinfo32.txt'
        $msInfo.RelativePath = 'msinfo32.txt'
        try {
            $msInfoProcess = Start-Process -FilePath "$env:SystemRoot\System32\msinfo32.exe" `
                -ArgumentList @('/report', ('"{0}"' -f $msInfoPath)) `
                -Wait `
                -PassThru `
                -ErrorAction Stop
            $msInfo.ExitCode = [int]$msInfoProcess.ExitCode
            $msInfo.Available = (Test-Path -LiteralPath $msInfoPath -PathType Leaf)
            if ($msInfoProcess.ExitCode -ne 0) {
                $msInfo.ErrorMessage = "msinfo32 returned exit code $($msInfoProcess.ExitCode)."
                Write-Warning $msInfo.ErrorMessage
            }
            elseif (-not $msInfo.Available) {
                $msInfo.ErrorMessage = 'msinfo32 completed without creating the requested report.'
                Write-Warning $msInfo.ErrorMessage
            }
        }
        catch {
            $msInfo.ErrorMessage = $_.Exception.Message
            Write-Warning "msinfo32 collection failed: $($msInfo.ErrorMessage)"
        }
    }

    # Recheck immediately before final assessment so that a background
    # servicing/updater transition during evidence collection cannot be hidden
    # by the clean startup snapshot.
    $pendingReboot = Get-PendingRebootEvidence

    $validationFailures = New-Object 'System.Collections.Generic.List[string]'
    $collectionFailures = New-Object 'System.Collections.Generic.List[string]'
    $reviewFindings = New-Object 'System.Collections.Generic.List[string]'

    foreach ($message in @($osIdentity.ValidationMessages)) {
        $validationFailures.Add([string]$message)
    }
    if (-not $secureBoot.Supported -or $secureBoot.Enabled -ne $true) {
        $validationFailures.Add('UEFI Secure Boot is not confirmed as enabled.')
    }
    if ($problemDevices.Count -gt 0) {
        $validationFailures.Add("$($problemDevices.Count) problematic PnP device(s) detected.")
    }
    if ($pendingReboot.BlockingRebootPending) {
        $validationFailures.Add(
            'A blocking pending reboot condition was detected (CBS, Windows Update, or an unrecognized/malformed PendingFileRenameOperations entry).'
        )
    }
    elseif ($pendingReboot.AdvisoryRebootPending) {
        $reviewFindings.Add(
            'PendingFileRenameOperations contains only recognized Microsoft Edge/Copilot updater cleanup deletions. Restart the server and rerun the collector; this is an operational stabilization condition rather than an ISO validation failure.'
        )
    }
    if (-not $pendingReboot.CollectionComplete) {
        $collectionFailures.Add(
            "Pending-reboot evidence collection was incomplete: $($pendingReboot.ReadErrorCount) registry read error(s)."
        )
    }

    $invalidKernelSignatures = @(
        $kernelFiles | Where-Object {
            $_.Present -and $_.AuthenticodeStatus -ne 'Valid'
        }
    )
    if ($invalidKernelSignatures.Count -gt 0) {
        $validationFailures.Add(
            "$($invalidKernelSignatures.Count) kernel/boot file signature(s) were not valid."
        )
    }

    if ($InspectEsp -and $esp.CollectionComplete) {
        $invalidEspSignatures = @(
            $esp.Files | Where-Object {
                $_.Present -and
                -not $_.AuthenticodeSkipped -and
                $_.Path -match '\.efi$' -and
                $_.AuthenticodeStatus -ne 'Valid'
            }
        )
        if ($invalidEspSignatures.Count -gt 0) {
            $validationFailures.Add(
                "$($invalidEspSignatures.Count) ESP EFI signature(s) were not valid."
            )
        }
    }

    foreach ($finding in @($dotNetFramework.ConsistencyFindings)) {
        $validationFailures.Add($finding)
    }
    foreach ($finding in @($secureBoot.Assessment.ConsistencyFindings)) {
        $validationFailures.Add($finding)
    }

    $secureBootScriptInventory = $secureBoot.MicrosoftScriptInventory
    if ($secureBootScriptInventory.Summary.InvalidSignatureFileCount -gt 0) {
        $validationFailures.Add(
            "$($secureBootScriptInventory.Summary.InvalidSignatureFileCount) Microsoft Secure Boot rollout script signature(s) were not valid."
        )
    }
    if ($secureBootScriptInventory.Summary.UnexpectedSignerFileCount -gt 0) {
        $validationFailures.Add(
            "$($secureBootScriptInventory.Summary.UnexpectedSignerFileCount) Secure Boot rollout script(s) had a valid signature from a non-Microsoft signer."
        )
    }
    if ($secureBootScriptInventory.Summary.CollectionIssueCount -gt 0) {
        $collectionFailures.Add(
            "$($secureBootScriptInventory.Summary.CollectionIssueCount) Secure Boot rollout script inventory item(s) were incomplete."
        )
    }

    if (-not $packages.Available) {
        $collectionFailures.Add("Installed package collection failed: $($packages.ErrorMessage)")
    }
    if (-not $windowsFeatures.Available) {
        $collectionFailures.Add("Windows feature collection failed: $($windowsFeatures.ErrorMessage)")
    }
    if (-not $dotNetFramework.Available) {
        $collectionFailures.Add(
            "One or more .NET Framework registry queries failed: " +
            [string]::Join(' | ', $dotNetFramework.ErrorMessages)
        )
    }
    if ($secureBoot.Enabled -eq $true -and -not $secureBoot.FirmwareVariables.RequiredVariablesAvailable) {
        $collectionFailures.Add('Secure Boot db/KEK firmware variables were not fully collected.')
    }
    if (-not $secureBoot.Events.Available) {
        $collectionFailures.Add("Secure Boot TPM-WMI event collection failed: $($secureBoot.Events.ErrorMessage)")
    }
    if (-not $reagent.Started -or -not $reagent.Succeeded) {
        $collectionFailures.Add('reagentc /info did not complete successfully.')
    }
    if (-not $bcdCurrent.Started -or -not $bcdCurrent.Succeeded) {
        $collectionFailures.Add('bcdedit for the current boot loader did not complete successfully.')
    }
    if (-not $bcdBootMgr.Started -or -not $bcdBootMgr.Succeeded) {
        $collectionFailures.Add('bcdedit for Windows Boot Manager did not complete successfully.')
    }
    if (-not $systemInfo.Started -or -not $systemInfo.Succeeded) {
        $collectionFailures.Add('systeminfo did not complete successfully.')
    }
    if ($diskEvidence.Count -eq 0) {
        $collectionFailures.Add('Disk evidence was not collected.')
    }
    if ($InspectEsp -and (-not $esp.Available -or -not $esp.CollectionComplete)) {
        $message = if ([string]::IsNullOrWhiteSpace($esp.ErrorMessage)) {
            'ESP evidence collection was incomplete.'
        }
        else {
            "ESP evidence collection was incomplete: $($esp.ErrorMessage)"
        }
        $collectionFailures.Add($message)
    }
    if ($IncludeMsInfo32 -and (
        -not $msInfo.Available -or
        $null -eq $msInfo.ExitCode -or
        [int]$msInfo.ExitCode -ne 0
    )) {
        $message = if ([string]::IsNullOrWhiteSpace($msInfo.ErrorMessage)) {
            'MSInfo32 report collection was incomplete.'
        }
        else {
            "MSInfo32 report collection was incomplete: $($msInfo.ErrorMessage)"
        }
        $collectionFailures.Add($message)
    }

    $kernelCollectionFailures = @(
        $kernelFiles | Where-Object {
            -not $_.Present -or
            [string]::IsNullOrWhiteSpace($_.Sha256) -or
            -not [string]::IsNullOrWhiteSpace($_.HashErrorMessage) -or
            [string]::IsNullOrWhiteSpace($_.AuthenticodeStatus) -or
            -not [string]::IsNullOrWhiteSpace($_.AuthenticodeErrorMessage)
        }
    )
    if ($kernelCollectionFailures.Count -gt 0) {
        $collectionFailures.Add(
            "$($kernelCollectionFailures.Count) kernel/boot file evidence item(s) were incomplete."
        )
    }

    $assessmentItems = @(
        New-AssessmentItem `
            -Name 'Post-install restart prerequisite' `
            -Status 'PASS' `
            -Detail ('confirmed={0}; startupPending={1}; bootHistory={2} (corroboration only)' -f `
                $restartConfirmation.Source, $pendingRebootAtStart.Classification, $bootHistory.Corroboration)
        Get-PostInstallAssessmentItems `
            -OsIdentity $osIdentity `
            -DetectedOsKey $detectedOsKey `
            -FullBuild $fullBuild `
            -Packages $packages `
            -WindowsFeatures $windowsFeatures `
            -DotNetFramework $dotNetFramework `
            -SecureBoot $secureBoot `
            -KernelFiles @($kernelFiles) `
            -ProblemDevices @($problemDevices) `
            -PendingReboot $pendingReboot `
            -Reagent $reagent `
            -BcdCurrent $bcdCurrent `
            -BcdBootManager $bcdBootMgr `
            -DiskEvidence @($diskEvidence) `
            -Esp $esp `
            -SystemInfo $systemInfo `
            -MsInfo32 $msInfo `
            -InspectEspRequested ([bool]$InspectEsp) `
            -MsInfo32Requested ([bool]$IncludeMsInfo32) `
            -ValidationFailures $validationFailures.ToArray() `
            -CollectionFailures $collectionFailures.ToArray() `
            -ReviewFindings $reviewFindings.ToArray()
    )

    $overallStatus = if ($validationFailures.Count -gt 0) {
        'Fail'
    }
    elseif ($collectionFailures.Count -gt 0 -or $reviewFindings.Count -gt 0) {
        'ReviewRequired'
    }
    else {
        'Pass'
    }

    $summary = [pscustomobject][ordered]@{
        SchemaVersion = $script:SchemaVersion
        CollectorVersion = $script:CollectorVersion
        GeneratedAtUtc = Get-UtcTimestamp
        DetectedOsVersion = $detectedOsKey
        OperatingSystemDetection = $osIdentity
        OverallStatus = $overallStatus
        AssessmentItems = @($assessmentItems)
        ValidationFailures = $validationFailures.ToArray()
        CollectionFailures = $collectionFailures.ToArray()
        ReviewFindings = $reviewFindings.ToArray()
        StartupPreflight = $startupPreflight
        FullEvidenceCollectionStarted = $true
        PendingRebootAtStart = $pendingRebootAtStart
        OperatingSystem = [pscustomobject][ordered]@{
            Caption = [string]$os.Caption
            ProductName = [string](Get-PropertyValue -InputObject $cv -Name 'ProductName')
            EditionId = [string](Get-PropertyValue -InputObject $cv -Name 'EditionID')
            InstallationType = [string](Get-PropertyValue -InputObject $cv -Name 'InstallationType')
            DisplayVersion = [string](Get-PropertyValue -InputObject $cv -Name 'DisplayVersion')
            ReleaseId = [string](Get-PropertyValue -InputObject $cv -Name 'ReleaseId')
            CurrentBuild = $currentBuild
            Ubr = $ubr
            FullBuild = $fullBuild
            BuildLabEx = [string](Get-PropertyValue -InputObject $cv -Name 'BuildLabEx')
            OsArchitecture = [string]$os.OSArchitecture
            SystemDirectory = [string]$os.SystemDirectory
            WindowsDirectory = [string]$os.WindowsDirectory
            InstallDate = if ($os.InstallDate) { $os.InstallDate.ToString('o') } else { $null }
            LastBootUpTime = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString('o') } else { $null }
        }
        ComputerSystem = [pscustomobject][ordered]@{
            Manufacturer = [string](Get-PropertyValue -InputObject $computer -Name 'Manufacturer')
            Model = [string](Get-PropertyValue -InputObject $computer -Name 'Model')
            SystemFamily = [string](Get-PropertyValue -InputObject $computer -Name 'SystemFamily')
            SystemSkuNumber = [string](Get-PropertyValue -InputObject $computer -Name 'SystemSKUNumber')
            SystemVersion = [string](Get-PropertyValue -InputObject $computerProduct -Name 'Version')
            SystemUuid = [string](Get-PropertyValue -InputObject $computerProduct -Name 'UUID')
            SystemType = [string](Get-PropertyValue -InputObject $computer -Name 'SystemType')
            HypervisorPresent = [bool](Get-PropertyValue -InputObject $computer -Name 'HypervisorPresent' -DefaultValue $false)
            TotalPhysicalMemoryBytes = [uint64](Get-PropertyValue -InputObject $computer -Name 'TotalPhysicalMemory' -DefaultValue 0)
        }
        Firmware = [pscustomobject][ordered]@{
            Manufacturer = [string](Get-PropertyValue -InputObject $bios -Name 'Manufacturer')
            Name = [string](Get-PropertyValue -InputObject $bios -Name 'Name')
            Version = [string](Get-PropertyValue -InputObject $bios -Name 'SMBIOSBIOSVersion')
            ReleaseDate = if (Get-PropertyValue -InputObject $bios -Name 'ReleaseDate') { (Get-PropertyValue -InputObject $bios -Name 'ReleaseDate').ToString('o') } else { $null }
            BaseBoardManufacturer = [string](Get-PropertyValue -InputObject $baseBoard -Name 'Manufacturer')
            BaseBoardProduct = [string](Get-PropertyValue -InputObject $baseBoard -Name 'Product')
            BaseBoardVersion = [string](Get-PropertyValue -InputObject $baseBoard -Name 'Version')
            SecureBoot = $secureBoot
        }
        KernelFiles = @($kernelFiles)
        InstalledPackages = $packages
        WindowsFeatures = $windowsFeatures
        DotNetFramework = $dotNetFramework
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
        MsInfo32 = $msInfo
    }

    $jsonPath = Join-Path $evidenceDir 'summary.json'
    $summary | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $textPath = Join-Path $evidenceDir 'summary.txt'
    @(
        "SchemaVersion: $($summary.SchemaVersion)"
        "GeneratedAtUtc: $($summary.GeneratedAtUtc)"
        "OverallStatus: $($summary.OverallStatus)"
        "DetectedOsVersion: $detectedOsKey"
        "OsDetectionMethod: $($osIdentity.DetectionMethod)"
        "OsDetectionConfidence: $($osIdentity.Confidence)"
        "OsDetectionComplete: $($osIdentity.DetectionComplete)"
        "OS: $($summary.OperatingSystem.Caption)"
        "Build: $fullBuild"
        "BuildLabEx: $($summary.OperatingSystem.BuildLabEx)"
        "WindowsFeatureSource: $($windowsFeatures.Source)"
        "InstalledWindowsFeatureCount: $($windowsFeatures.InstalledFeatureCount)"
        "NetFx3FeatureInstalled: $($windowsFeatures.DotNetFeatureState.NetFx3Installed)"
        "NetFx4FeatureInstalled: $($windowsFeatures.DotNetFeatureState.NetFx4Installed)"
        "DotNetRegistryEntryCount: $($dotNetFramework.Entries.Count)"
        "DotNet4ResolvedVersion: $($dotNetFramework.RegistryState.NetFx4ResolvedVersion)"
        "Firmware: $($summary.Firmware.Manufacturer) / $($summary.Firmware.Version)"
        "SecureBootSupported: $($secureBoot.Supported)"
        "SecureBootEnabled: $($secureBoot.Enabled)"
        "UEFICA2023Status: $($secureBoot.Registry.UEFICA2023Status)"
        "SecureBootLatestRolloutEventId: $($secureBoot.RolloutStatus.LatestEventId)"
        "SecureBootRolloutBucketId: $($secureBoot.RolloutStatus.BucketId)"
        "SecureBootRolloutConfidence: $($secureBoot.RolloutStatus.Confidence)"
        "SecureBootRolloutUpdateType: $($secureBoot.RolloutStatus.UpdateType)"
        "SecureBoot2023Assessment: $($secureBoot.Assessment.State)"
        "SecureBootDirectCertificateRequirementsSatisfied: $($secureBoot.FirmwareVariables.DirectRequirementsSatisfied)"
        "SecureBootMicrosoftCompletionConfirmed: $($secureBoot.Assessment.MicrosoftCompletionConfirmed)"
        "SecureBootEvent1808Count: $($secureBoot.Assessment.Event1808Count)"
        "SecureBootEvent1799Count: $($secureBoot.Assessment.Event1799Count)"
        "SecureBootScriptInventoryFileCount: $($secureBoot.MicrosoftScriptInventory.Summary.FileCount)"
        "SecureBootScriptInventoryValidMicrosoftSignedFileCount: $($secureBoot.MicrosoftScriptInventory.Summary.ValidMicrosoftSignedFileCount)"
        "SecureBootScriptBaselineHashComparisonEnabled: $($secureBoot.MicrosoftScriptInventory.InventoryPolicy.BaselineHashComparisonEnabled)"
        "WindowsUEFICA2023Capable: $($secureBoot.Registry.WindowsUEFICA2023Capable)"
        "WindowsUEFICA2023CapableMeaning: $($secureBoot.Registry.WindowsUEFICA2023CapableInterpretation.Meaning)"
        "WindowsUEFICA2023CapableStatusAuthority: $($secureBoot.Registry.WindowsUEFICA2023CapableInterpretation.StatusAuthority)"
        "WinCsState: $($secureBoot.WinCs.Parsed.State)"
        "WinCsMeaning: $($secureBoot.WinCs.Interpretation.Meaning)"
        "WinCsIsCompletionSignal: $($secureBoot.WinCs.Interpretation.IsCompletionSignal)"
        "BootManager2023EvidenceConfirmed: $($secureBoot.Assessment.BootManager2023EvidenceConfirmed)"
        "BootManager2023EvidenceSources: $(@($secureBoot.Assessment.BootManager2023EvidenceSources) -join ', ')"
        "BootManagerAuthenticodePrimarySignerSubject: $($secureBoot.Assessment.BootManagerAuthenticodePrimarySignerSubject)"
        "BootManagerAuthenticodeAssessmentScope: $($secureBoot.Assessment.BootManagerAuthenticodeAssessmentScope)"
        "ProblemDeviceCount: $($problemDevices.Count)"
        "PostInstallRestartConfirmationSource: $($restartConfirmation.Source)"
        "PostInstallRestartConfirmed: $($restartConfirmation.Confirmed)"
        "BootHistoryCorroboration: $($bootHistory.Corroboration)"
        "BootStartEventCountAfterInstallDate: $($bootHistory.BootStartEventCountAfterInstallDate)"
        "NormalRestartEventCountAfterInstallDate: $($bootHistory.NormalRestartEventCountAfterInstallDate)"
        "PendingRebootAtStart: $($pendingRebootAtStart.RebootPending)"
        "PendingRebootAtStartClassification: $($pendingRebootAtStart.Classification)"
        "PendingReboot: $($pendingReboot.RebootPending)"
        "PendingRebootClassification: $($pendingReboot.Classification)"
        "PendingRebootBlocking: $($pendingReboot.BlockingRebootPending)"
        "PendingRebootAdvisory: $($pendingReboot.AdvisoryRebootPending)"
        "WinRE ExitCode: $($reagent.ExitCode)"
        "ESP Inspected: $($esp.Requested)"
        "ESP Available: $($esp.Available)"
        "ESP CollectionComplete: $($esp.CollectionComplete)"
        "MSInfo32 Requested: $($msInfo.Requested)"
        "MSInfo32 Available: $($msInfo.Available)"
        ""
        "Assessment items:"
        @($assessmentItems | ForEach-Object { "  [$($_.Status)] $($_.Name): $($_.Detail)" })
        ""
        "Validation failures:"
        $(if ($validationFailures.Count -eq 0) { '  none' } else {
            @($validationFailures | ForEach-Object { "  - $_" })
        })
        ""
        "Collection failures:"
        $(if ($collectionFailures.Count -eq 0) { '  none' } else {
            @($collectionFailures | ForEach-Object { "  - $_" })
        })
        ""
        "Review findings:"
        $(if ($reviewFindings.Count -eq 0) { '  none' } else {
            @($reviewFindings | ForEach-Object { "  - $_" })
        })
        ""
        "Informational findings:"
        $(if (@($secureBoot.Assessment.InformationalFindings).Count -eq 0) { '  none' } else {
            @($secureBoot.Assessment.InformationalFindings | ForEach-Object { "  - $_" })
        })
    ) | Set-Content -LiteralPath $textPath -Encoding UTF8

    Get-AssessmentReportLines `
        -AssessmentItems @($assessmentItems) `
        -OverallStatus $summary.OverallStatus `
        -ExitCode $(if ($validationFailures.Count -gt 0 -or $collectionFailures.Count -gt 0 -or $reviewFindings.Count -gt 0) { 2 } else { 0 }) `
        -EvidenceDirectory $evidenceDir `
        -ZipPath $zipPath |
        Set-Content -LiteralPath (Join-Path $evidenceDir 'assessment-report.txt') -Encoding UTF8

    $problemDevices | Export-Csv -LiteralPath (Join-Path $evidenceDir 'problem-devices.csv') `
        -NoTypeInformation -Encoding UTF8
    $hotFixes | Export-Csv -LiteralPath (Join-Path $evidenceDir 'hotfixes.csv') `
        -NoTypeInformation -Encoding UTF8
    $windowsFeatures.Features | Export-Csv `
        -LiteralPath (Join-Path $evidenceDir 'windows-features.csv') `
        -NoTypeInformation -Encoding UTF8
    $windowsFeatures.DotNetFeatures | Export-Csv `
        -LiteralPath (Join-Path $evidenceDir 'dotnet-windows-features.csv') `
        -NoTypeInformation -Encoding UTF8
    $secureBoot.Events | ConvertTo-Json -Depth 15 |
        Set-Content -LiteralPath (Join-Path $evidenceDir 'secureboot-events.json') -Encoding UTF8
    $secureBoot.RolloutStatus | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $evidenceDir 'secureboot-rollout-status.json') -Encoding UTF8
    $secureBoot.FirmwareVariables | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $evidenceDir 'secureboot-variables.json') -Encoding UTF8
    $secureBoot.MicrosoftScriptInventory.Files | ForEach-Object {
        [pscustomobject][ordered]@{
            RootDirectory = $_.RootDirectory
            RelativePath = $_.RelativePath
            FullPath = $_.File.Path
            FileName = $_.File.FileName
            Extension = $_.File.Extension
            Present = $_.File.Present
            SizeBytes = $_.File.SizeBytes
            CreationTimeUtc = $_.File.CreationTimeUtc
            LastWriteTimeUtc = $_.File.LastWriteTimeUtc
            Attributes = $_.File.Attributes
            IsReadOnly = $_.File.IsReadOnly
            FileVersion = $_.File.FileVersion
            ProductVersion = $_.File.ProductVersion
            FileDescription = $_.File.FileDescription
            CompanyName = $_.File.CompanyName
            OriginalFilename = $_.File.OriginalFilename
            Sha256 = $_.File.Sha256
            HashErrorMessage = $_.File.HashErrorMessage
            AuthenticodeStatus = $_.File.AuthenticodeStatus
            AuthenticodeStatusMessage = $_.File.AuthenticodeStatusMessage
            SignatureType = $_.File.SignatureType
            IsOsBinary = $_.File.IsOsBinary
            SignerSubject = $_.File.SignerSubject
            SignerIssuer = $_.File.SignerIssuer
            SignerThumbprint = $_.File.SignerThumbprint
            SignerNotBefore = $_.File.SignerNotBefore
            SignerNotAfter = $_.File.SignerNotAfter
            SignerIsMicrosoft = $_.File.SignerIsMicrosoft
            TimeStamperSubject = $_.File.TimeStamperSubject
            TimeStamperIssuer = $_.File.TimeStamperIssuer
            TimeStamperThumbprint = $_.File.TimeStamperThumbprint
            TimeStamperNotBefore = $_.File.TimeStamperNotBefore
            TimeStamperNotAfter = $_.File.TimeStamperNotAfter
            AuthenticodeErrorMessage = $_.File.AuthenticodeErrorMessage
            ReadErrorMessage = $_.File.ReadErrorMessage
        }
    } | Export-Csv `
        -LiteralPath (Join-Path $evidenceDir 'secureboot-script-inventory.csv') `
        -NoTypeInformation -Encoding UTF8

    if ($validationFailures.Count -gt 0 -or $collectionFailures.Count -gt 0 -or $reviewFindings.Count -gt 0) {
        $exitCode = 2
    }
    } while ($false)
}
catch {
    $exitCode = 1
    $fatalErrorMessage = $_.Exception.Message
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

    # Create checksums only after the transcript is closed. Otherwise the
    # transcript changes after hashing and its recorded digest is invalid.
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

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
    Compress-Archive -LiteralPath $evidenceDir -DestinationPath $zipPath -CompressionLevel Optimal

    if ($null -ne $summary) {
        Write-AssessmentConsoleReport `
            -AssessmentItems @($summary.AssessmentItems) `
            -OverallStatus $summary.OverallStatus `
            -ExitCode $exitCode `
            -EvidenceDirectory $evidenceDir `
            -ZipPath $zipPath

        if (@($summary.ValidationFailures).Count -gt 0) {
            Write-Host ''
            Write-Host 'Validation failure details:' -ForegroundColor Red
            foreach ($message in @($summary.ValidationFailures)) {
                Write-Host "  - $message" -ForegroundColor Red
            }
        }
        if (@($summary.CollectionFailures).Count -gt 0) {
            Write-Host ''
            Write-Host 'Collection review details:' -ForegroundColor Yellow
            foreach ($message in @($summary.CollectionFailures)) {
                Write-Host "  - $message" -ForegroundColor Yellow
            }
        }
        if (@($summary.ReviewFindings).Count -gt 0) {
            Write-Host ''
            Write-Host 'Operational review details:' -ForegroundColor Yellow
            foreach ($message in @($summary.ReviewFindings)) {
                Write-Host "  - $message" -ForegroundColor Yellow
            }
        }
    }
    else {
        $fatalItems = @(
            New-AssessmentItem `
                -Name 'Collector execution' `
                -Status 'FAIL' `
                -Detail $(if ([string]::IsNullOrWhiteSpace($fatalErrorMessage)) { 'Fatal collector error' } else { $fatalErrorMessage })
        )
        Write-AssessmentConsoleReport `
            -AssessmentItems $fatalItems `
            -OverallStatus 'FatalError' `
            -ExitCode $exitCode `
            -EvidenceDirectory $evidenceDir `
            -ZipPath $zipPath
    }
}

exit $exitCode
