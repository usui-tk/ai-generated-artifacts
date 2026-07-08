# Test-SecureBootRigState.ps1
# Guest-side rig verifier. Run INSIDE a candidate rig VM after the
# KB5025885 mitigations. Verdict: the VM is a valid REVOKED rig only
# when db carries 'Windows UEFI CA 2023' AND dbx carries
# 'Microsoft Windows Production PCA 2011' (as an X.509 entry).

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$OutJson = ''
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) 'BootVerification.Common.ps1')

$db  = (Get-SecureBootUEFI -Name db).Bytes
$dbx = (Get-SecureBootUEFI -Name dbx).Bytes
$dbSubjects  = @(Get-SecureBootCertSubject -Entries (ConvertFrom-EfiSignatureList -Bytes $db))
$dbxSubjects = @(Get-SecureBootCertSubject -Entries (ConvertFrom-EfiSignatureList -Bytes $dbx))
$dbFlags  = Test-SecureBootSubjectPresence -Subjects $dbSubjects
$dbxFlags = Test-SecureBootSubjectPresence -Subjects $dbxSubjects

$state = [pscustomobject]@{
    Schema           = 'rig-state/1'
    CollectedAt      = (Get-Date).ToString('o')
    SecureBootEnabled = (Confirm-SecureBootUEFI)
    DbHas2023        = $dbFlags.Has2023
    DbHas2011        = $dbFlags.Has2011
    DbxHas2011Cert   = $dbxFlags.Has2011
    DbSubjects       = $dbSubjects
    DbxCertSubjects  = $dbxSubjects
    RigReady         = ($dbFlags.Has2023 -and $dbxFlags.Has2011)
}
if ($OutJson) {
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutJson -Encoding UTF8
}
$state | Format-List SecureBootEnabled, DbHas2023, DbHas2011, DbxHas2011Cert, RigReady
if ($state.RigReady) {
    Write-Host 'RIG READY: this VM firmware trusts the 2023 CA and REVOKES PCA2011.' -ForegroundColor Green
} else {
    Write-Host 'NOT a revoked rig yet: apply/verify the KB5025885 mitigations (see README).' -ForegroundColor Yellow
}
