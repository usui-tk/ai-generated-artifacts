# Invoke-IsoBootVerification.ps1
# Host-side harness for the ISO boot-verification matrix (T1..T12).
# See README.md in this folder for the rig recipe and the full flow.
#
# Depth 'boot' cells: create/drive the VM, capture console screenshots
# at fixed offsets, record a ledger entry with Outcome=pending-operator
# (a human confirms Setup-UI vs boot-failure from the .bmp files --
# VM State=Running is NOT a boot verdict and is never used as one).
# Depth 'install' cells: wait for the unattended install to power the
# VM off, then read the collected evidence from the data VHDX; the
# presence of installed_evidence.json IS the automated verdict.
#
# Requires: Windows host with the Hyper-V module, elevated.

#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidatePattern('^T([1-9]|1[0-2])$')] [string]$Cell,
    [Parameter(Mandatory)] [string]$IsoPath,
    # STD cells create an ephemeral VM; REV cells drive an EXISTING,
    # already-revoked rig VM prepared per README (its per-VM NVRAM
    # carries db=+2023 / dbx=+PCA2011).
    [string]$RigVmName,
    [string]$ResultsDir = (Join-Path (Split-Path -Parent $PSCommandPath) 'results'),
    # install-depth cells only: the evidence data VHDX built by
    # New-EvidenceDataVhdx.ps1 (attached as a second disk).
    [string]$DataVhdxPath,
    [int]$MemoryGB = 8,
    [int[]]$ScreenshotSecond = @(30, 90, 180),
    [int]$InstallTimeoutMinutes = 180,
    [switch]$KeepVm
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) 'BootVerification.Common.ps1')

$cellMap = Get-BootVerificationCellMap
$spec = $cellMap[$Cell]
if (-not (Test-Path -LiteralPath $IsoPath)) { throw ('ISO not found: {0}' -f $IsoPath) }
if ($spec.Rig -eq 'REV' -and -not $RigVmName) {
    throw ('{0} runs on the revoked rig: pass -RigVmName (see README, rig recipe).' -f $Cell)
}
if ($spec.Depth -eq 'install' -and -not $DataVhdxPath) {
    throw ('{0} is an install-depth cell: pass -DataVhdxPath (build one with New-EvidenceDataVhdx.ps1).' -f $Cell)
}
New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $ResultsDir ('{0}_{1}' -f $Cell, $stamp)
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$ephemeral = ($spec.Rig -eq 'STD')
$vmName = if ($ephemeral) { ('IsoBootVerify_{0}_{1}' -f $Cell, $stamp) } else { $RigVmName }
$vhdPath = $null
$addedDvd = $false
$attachedData = $false

try {
    if ($ephemeral) {
        if ($PSCmdlet.ShouldProcess($vmName, 'Create ephemeral Gen2 Secure Boot VM')) {
            $vhdPath = Join-Path $runDir ($vmName + '.vhdx')
            New-VHD -Path $vhdPath -SizeBytes 64GB -Dynamic | Out-Null
            New-VM -Name $vmName -Generation 2 -MemoryStartupBytes ([int64]$MemoryGB * 1GB) -VHDPath $vhdPath -Path $runDir | Out-Null
            Set-VMProcessor -VMName $vmName -Count 2 | Out-Null
            Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter | Out-Null
            Add-VMDvdDrive -VMName $vmName -Path $IsoPath | Out-Null
            $dvd = Get-VMDvdDrive -VMName $vmName | Select-Object -First 1
            # MicrosoftWindows is the correct template for Windows
            # media (the previous MicrosoftUEFICertificateAuthority
            # choice is the third-party UEFI CA template).
            Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows | Out-Null
        }
    } else {
        # Rig VM: never recreate; mount the ISO and put the DVD first.
        # The rig's REVOKED NVRAM (per-VM .vmgs) is the whole point --
        # it survives disk swaps but NOT VM recreation.
        $vm = Get-VM -Name $vmName
        if ($vm.State -ne 'Off') { throw ('Rig VM {0} must be Off before a cell run (current: {1}).' -f $vmName, $vm.State) }
        $dvd = Get-VMDvdDrive -VMName $vmName | Select-Object -First 1
        if (-not $dvd) {
            Add-VMDvdDrive -VMName $vmName -Path $IsoPath | Out-Null
            $addedDvd = $true
            $dvd = Get-VMDvdDrive -VMName $vmName | Select-Object -First 1
        } else {
            Set-VMDvdDrive -VMName $vmName -ControllerNumber $dvd.ControllerNumber -ControllerLocation $dvd.ControllerLocation -Path $IsoPath | Out-Null
        }
        if ($spec.Depth -eq 'install' -and $DataVhdxPath) {
            Add-VMHardDiskDrive -VMName $vmName -Path $DataVhdxPath | Out-Null
            $attachedData = $true
        }
        Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd | Out-Null
    }

    Write-Host ('[{0}] {1} -- starting VM {2}' -f $Cell, $spec.Note, $vmName)
    Start-VM -Name $vmName | Out-Null

    $shots = New-Object System.Collections.Generic.List[string]
    $t0 = Get-Date
    foreach ($sec in ($ScreenshotSecond | Sort-Object)) {
        $wait = $sec - [int](New-TimeSpan -Start $t0 -End (Get-Date)).TotalSeconds
        if ($wait -gt 0) { Start-Sleep -Seconds $wait }
        $shotPath = Join-Path $runDir ('console_{0}s.bmp' -f $sec)
        $saved = Save-VmConsoleScreenshot -VmName $vmName -OutPath $shotPath
        if ($saved) { $shots.Add($saved) | Out-Null; Write-Host ('  screenshot: {0}' -f $saved) }
        else        { Write-Warning ('  screenshot at {0}s unavailable' -f $sec) }
    }

    $outcome = 'pending-operator'
    $detail  = 'Review the console screenshots: Setup UI => reaches-setup; firmware/Secure Boot error screen => boot-failure. VM State is NOT a verdict.'

    if ($spec.Depth -eq 'install') {
        Write-Host ('  waiting for the unattended install to power the VM off (timeout {0} min)...' -f $InstallTimeoutMinutes)
        $deadline = (Get-Date).AddMinutes($InstallTimeoutMinutes)
        while ((Get-VM -Name $vmName).State -ne 'Off' -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 60
            $mins = [int](New-TimeSpan -Start $t0 -End (Get-Date)).TotalMinutes
            if (($mins % 15) -eq 0) {
                $p = Save-VmConsoleScreenshot -VmName $vmName -OutPath (Join-Path $runDir ('console_{0}m.bmp' -f $mins))
                if ($p) { $shots.Add($p) | Out-Null }
            }
        }
        if ((Get-VM -Name $vmName).State -ne 'Off') {
            $outcome = 'timeout'
            $detail  = ('VM did not power off within {0} minutes; inspect the last screenshot.' -f $InstallTimeoutMinutes)
            Stop-VM -Name $vmName -TurnOff -Force | Out-Null
        } else {
            # Automated verdict: the evidence JSON on the data VHDX.
            if ($attachedData) {
                Remove-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -ControllerNumber (Get-VMHardDiskDrive -VMName $vmName | Where-Object Path -eq $DataVhdxPath).ControllerNumber -ControllerLocation (Get-VMHardDiskDrive -VMName $vmName | Where-Object Path -eq $DataVhdxPath).ControllerLocation | Out-Null
                $attachedData = $false
            }
            $mnt = Mount-VHD -Path $DataVhdxPath -Passthru -ReadOnly | Get-Disk | Get-Partition | Get-Volume | Where-Object FileSystemLabel -eq 'EVIDENCE' | Select-Object -First 1
            try {
                $evid = if ($mnt) { Join-Path ($mnt.DriveLetter + ':') 'results\installed_evidence.json' } else { $null }
                if ($evid -and (Test-Path -LiteralPath $evid)) {
                    Copy-Item -LiteralPath $evid -Destination (Join-Path $runDir 'installed_evidence.json') -Force
                    $txt = [System.IO.Path]::ChangeExtension($evid, '.txt')
                    if (Test-Path -LiteralPath $txt) { Copy-Item -LiteralPath $txt -Destination $runDir -Force }
                    $outcome = 'install-completes'
                    $detail  = 'installed_evidence.json collected from the EVIDENCE VHDX.'
                } else {
                    $outcome = 'install-failed'
                    $detail  = 'VM powered off but no installed_evidence.json was written; inspect screenshots and setup logs.'
                }
            } finally {
                Dismount-VHD -Path $DataVhdxPath -ErrorAction SilentlyContinue
            }
        }
    }

    $entry = New-BootVerificationLedgerEntry -Cell $Cell -IsoPath $IsoPath -VmName $vmName `
        -Screenshots $shots.ToArray() -Outcome $outcome -Detail $detail
    $ledger = Join-Path $ResultsDir 'ledger.jsonl'
    ($entry | ConvertTo-Json -Depth 4 -Compress) | Add-Content -LiteralPath $ledger -Encoding UTF8
    $entry | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'entry.json') -Encoding UTF8
    Write-Host ('[{0}] recorded: Outcome={1} (expected: {2}) -> {3}' -f $Cell, $outcome, $spec.Expected, $ledger)
    Write-Host ('    run dir: {0}' -f $runDir)
} finally {
    try {
        if ($spec.Depth -eq 'boot') {
            Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null
        }
        if ($ephemeral -and -not $KeepVm) {
            Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue | Out-Null
            if ($vhdPath -and (Test-Path -LiteralPath $vhdPath)) {
                Remove-Item -LiteralPath $vhdPath -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $ephemeral) {
            if ($attachedData) {
                Get-VMHardDiskDrive -VMName $vmName | Where-Object Path -eq $DataVhdxPath | Remove-VMHardDiskDrive -ErrorAction SilentlyContinue
            }
            if ($addedDvd) {
                Get-VMDvdDrive -VMName $vmName | Where-Object Path -eq $IsoPath | Remove-VMDvdDrive -ErrorAction SilentlyContinue
            } else {
                Get-VMDvdDrive -VMName $vmName | Where-Object Path -eq $IsoPath | Set-VMDvdDrive -Path $null -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Warning ('cleanup: {0}' -f $_.Exception.Message)
    } # psa-disable-line PSA3004 -- best-effort teardown; the run dir and ledger already persist the evidence
}
