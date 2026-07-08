# Export-InstalledSystemEvidence.ps1
# Guest-side evidence collector. Run INSIDE the freshly installed OS
# (launched automatically by the autounattend FirstLogonCommands via
# run-collect.cmd on the EVIDENCE data VHDX, or manually). Writes
# installed_evidence.json (+ .txt) in a vocabulary aligned with the
# build pipeline's inspection_post.json so media claims and installed
# reality can be diffed.
#
# Known limitation (recorded in the JSON): the boot-manager signature
# is read with Get-AuthenticodeSignature, which follows catalog /
# cross-cert paths and can under-report LCU-materialised PCA2023
# embedded signatures; treat 'SignerChainText' as advisory and the
# db/dbx + boot success as the primary evidence.

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$OutDir
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path -Parent $PSCommandPath) 'BootVerification.Common.ps1')

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

function Get-RegValueSafe {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

$cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$os = [ordered]@{
    CurrentBuildNumber = Get-RegValueSafe $cv 'CurrentBuildNumber'
    UBR                = Get-RegValueSafe $cv 'UBR'
    Build              = $null
    EditionID          = Get-RegValueSafe $cv 'EditionID'
    DisplayVersion     = Get-RegValueSafe $cv 'DisplayVersion'
    ProductName        = Get-RegValueSafe $cv 'ProductName'
    CollectedAt        = (Get-Date).ToString('o')
    ComputerName       = $env:COMPUTERNAME
}
if ($os.CurrentBuildNumber -and $null -ne $os.UBR) { $os.Build = ('{0}.{1}' -f $os.CurrentBuildNumber, $os.UBR) }

# ---- Secure Boot state -------------------------------------------------
$sb = [ordered]@{
    SecureBootEnabled = $null
    DbSubjects  = @(); DbxCertSubjects = @()
    DbHas2011 = $null; DbHas2023 = $null; DbxHas2011 = $null
    UEFICA2023Status = Get-RegValueSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' 'UEFICA2023Status'
    UEFICA2023Error  = Get-RegValueSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' 'UEFICA2023Error'
    AvailableUpdates = $null
    Notes = 'DbxCertSubjects lists only X.509 entries; hash-type revocations are counted, not listed.'
}
$au = Get-RegValueSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot' 'AvailableUpdates'
if ($null -ne $au) { $sb.AvailableUpdates = ('0x{0:x}' -f [int]$au) }
try { $sb.SecureBootEnabled = Confirm-SecureBootUEFI } catch { $null = $_ }
try {
    $db = (Get-SecureBootUEFI -Name db).Bytes
    $sb.DbSubjects = @(Get-SecureBootCertSubject -Entries (ConvertFrom-EfiSignatureList -Bytes $db))
    $flags = Test-SecureBootSubjectPresence -Subjects $sb.DbSubjects
    $sb.DbHas2011 = $flags.Has2011; $sb.DbHas2023 = $flags.Has2023
} catch { $null = $_ }
try {
    $dbx = (Get-SecureBootUEFI -Name dbx).Bytes
    $sb.DbxCertSubjects = @(Get-SecureBootCertSubject -Entries (ConvertFrom-EfiSignatureList -Bytes $dbx))
    $flags = Test-SecureBootSubjectPresence -Subjects $sb.DbxCertSubjects
    $sb.DbxHas2011 = $flags.Has2011
} catch { $null = $_ }

# ---- Boot manager on the ESP -------------------------------------------
$bm = [ordered]@{ EspLetter = $null; BootMgFwPath = $null; SignerChainText = $null; SignatureStatus = $null; Notes = 'Get-AuthenticodeSignature can under-report embedded PCA2023 signatures (catalog path); advisory only.' }
try {
    $letter = 'S'
    mountvol "$letter`:" /S 2>$null
    $p = "$letter`:\EFI\Microsoft\Boot\bootmgfw.efi"
    if (Test-Path -LiteralPath $p) {
        $bm.EspLetter = $letter; $bm.BootMgFwPath = $p
        $sig = Get-AuthenticodeSignature -FilePath $p
        $bm.SignatureStatus = [string]$sig.Status
        if ($sig.SignerCertificate) {
            $chainParts = @($sig.SignerCertificate.Subject, $sig.SignerCertificate.Issuer)
            $bm.SignerChainText = ($chainParts -join ' | ')
        }
    }
    mountvol "$letter`:" /D 2>$null
} catch { $null = $_ }

# ---- Packages / hotfixes / .NET ----------------------------------------
$pk = [ordered]@{ HotFixKbIds = @(); DotNetRollupPackages = @(); RollupFixPackages = @() }
try { $pk.HotFixKbIds = @(Get-HotFix | ForEach-Object { [string]$_.HotFixID } | Sort-Object) } catch { $null = $_ }
try {
    $pkgs = & dism.exe /english /online /get-packages 2>$null | Where-Object { $_ -match '^Package Identity' }
    foreach ($line in $pkgs) {
        $name = ($line -split ':', 2)[1].Trim()
        if ($name -match '^Package_for_DotNetRollup') { $pk.DotNetRollupPackages += $name }
        if ($name -match '^Package_for_RollupFix')    { $pk.RollupFixPackages += $name }
    }
} catch { $null = $_ }
$dotNetRelease = Get-RegValueSafe 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release'

# ---- WinRE / setup log ---------------------------------------------------
$winre = [ordered]@{ ReagentcInfo = @() }
try { $winre.ReagentcInfo = @((& reagentc.exe /info 2>$null) | ForEach-Object { [string]$_ } | Where-Object { $_ -match '\S' }) } catch { $null = $_ }
$setupLog = [ordered]@{ SetupActTail = @() }
try {
    $sa = Join-Path $env:WINDIR 'Panther\setupact.log'
    if (Test-Path -LiteralPath $sa) { $setupLog.SetupActTail = @(Get-Content -LiteralPath $sa -Tail 60) }
} catch { $null = $_ }

$evidence = [pscustomobject]@{
    Schema      = 'installed-evidence/1'
    Os          = [pscustomobject]$os
    SecureBoot  = [pscustomobject]$sb
    BootManager = [pscustomobject]$bm
    Packages    = [pscustomobject]$pk
    DotNetRelease = $dotNetRelease
    WinRe       = [pscustomobject]$winre
    SetupLog    = [pscustomobject]$setupLog
}
$jsonPath = Join-Path $OutDir 'installed_evidence.json'
$evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$sbLine = ('SecureBoot={0} DbHas2023={1} DbxHas2011={2}' -f $sb.SecureBootEnabled, $sb.DbHas2023, $sb.DbxHas2011)
@(
    ('Installed evidence  {0}' -f (Get-Date))
    ('Build      : {0} ({1} {2})' -f $os.Build, $os.ProductName, $os.EditionID)
    ('SecureBoot : {0}' -f $sbLine)
    ('BootMgr    : {0} [{1}]' -f $bm.SignerChainText, $bm.SignatureStatus)
    ('HotFix     : {0}' -f (@($pk.HotFixKbIds) -join ', '))
    ('DotNet pkg : {0}' -f (@($pk.DotNetRollupPackages) -join ', '))
) | Set-Content -LiteralPath (Join-Path $OutDir 'installed_evidence.txt') -Encoding UTF8
Write-Host ('evidence written: {0}' -f $jsonPath)
