# New-EvidenceDataVhdx.ps1
# Build the EVIDENCE data VHDX for install-depth cells: a small NTFS
# volume carrying autounattend.xml (token-substituted from the
# template), the collector + common library, and run-collect.cmd
# (locates its own drive via %~d0, runs the collector, writes results
# back to the same volume, then shuts the guest down). The target ISO
# is NEVER modified -- Windows Setup picks autounattend.xml from any
# attached volume's root.
#
# SAFETY: the answer file WIPES DISK 0 unconditionally. Attach this
# VHDX only to disposable verification VMs (README states the same).

#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [int]$ImageIndex,
    # Deliberate plain text: the value is written verbatim into
    # autounattend.xml (Setup requires it in clear) for a disposable
    # verification VM's documented test credential; SecureString here
    # would only pretend to protect it.
    [Parameter(Mandatory)] [string]$AdminPassword, # psa-disable-line PSA5001 -- plain text required by autounattend; disposable test credential
    [string]$UiLanguage = 'ja-JP',
    [string]$InputLocale = '0411:00000411',
    [uint64]$SizeBytes = 2GB
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
$template = Join-Path $here 'autounattend-template.xml'
if (-not (Test-Path -LiteralPath $template)) { throw ('template not found: {0}' -f $template) }
if (Test-Path -LiteralPath $Path) { throw ('refusing to overwrite existing VHDX: {0}' -f $Path) }

$xml = Get-Content -LiteralPath $template -Raw
$xml = $xml.Replace('{{IMAGE_INDEX}}', [string]$ImageIndex)
$xml = $xml.Replace('{{ADMIN_PASSWORD}}', $AdminPassword)
$xml = $xml.Replace('{{UI_LANG}}', $UiLanguage)
$xml = $xml.Replace('{{INPUT_LOCALE}}', $InputLocale)
if ($xml -match '\{\{[A-Z_]+\}\}') { throw 'unsubstituted token remains in autounattend.xml' }

if (-not $PSCmdlet.ShouldProcess($Path, 'Create EVIDENCE data VHDX')) { return }
New-VHD -Path $Path -SizeBytes $SizeBytes -Dynamic | Out-Null
$disk = Mount-VHD -Path $Path -Passthru | Get-Disk
try {
    $disk | Initialize-Disk -PartitionStyle GPT -PassThru |
        New-Partition -UseMaximumSize -AssignDriveLetter |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel 'EVIDENCE' -Confirm:$false | Out-Null
    $vol = Get-Partition -DiskNumber $disk.Number | Get-Volume | Where-Object FileSystemLabel -eq 'EVIDENCE'
    $root = ($vol.DriveLetter + ':\')
    $scripts = Join-Path $root 'scripts'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'results') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'autounattend.xml') -Value $xml -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $here 'Export-InstalledSystemEvidence.ps1') -Destination $scripts -Force
    Copy-Item -LiteralPath (Join-Path $here 'BootVerification.Common.ps1') -Destination $scripts -Force
    $cmdLines = @(
        '@echo off'
        'rem run-collect.cmd -- launched by autounattend FirstLogonCommands.'
        'rem %~d0 is THIS volume (the EVIDENCE VHDX), wherever it mounted.'
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Export-InstalledSystemEvidence.ps1" -OutDir "%~d0\results" > "%~d0\results\collector_console.log" 2>&1'
        'shutdown.exe /s /t 30 /c "boot-verification evidence collected"'
    )
    # cmd files require CRLF.
    [System.IO.File]::WriteAllText((Join-Path $scripts 'run-collect.cmd'), (($cmdLines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
    Write-Host ('EVIDENCE VHDX ready: {0} (autounattend index={1}, UI={2})' -f $Path, $ImageIndex, $UiLanguage)
} finally {
    Dismount-VHD -Path $Path
}
