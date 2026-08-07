#!/usr/bin/env python3
"""T52: Final-writer media authority contract (behavioral, offline via pwsh).

Pins the P09/P10/P11 last-writer authority model of
`Update-WindowsServerIso.ps1` behaviorally: the functions under test are
extracted from the script's own AST and exercised against measured
fixtures, with DISM mocked for the WinPE media-sync runtime group.

Specification source: the r12.75 distribution's required suite, axes
R1262 / R1271 / R1272 (input-only per the standing ruling; logic
re-authored, code not copied). Ledger: TEST-REIMPL-LEDGER.csv rows for
those axes. The real-environment-validated r12.75 script is the
specification baseline (code-anchored testing); the script is untouched
and every expected value below encodes its measured behavior. The
distribution's package revision-floor rows are DROP (T40 pins the exact
ScriptVersion instead).

Class: B (behaviour pins). Justification: final-writer authority,
identity/digest binding and evidence gating live in script code; no
declared data surface expresses them.

What this asserts:

  1. **Retained media-sync surface (r12.62, static).** The P09 WinPE
     final-media synchronization arc remains present: sync/identity/
     export functions, their schema versions, the P08/P09/P11 evidence
     artifact names, and the r12.62 cleanup defer wiring. P09
     explicitly creates/verifies the standard EFI boot manager and the
     root bootmgr.efi (r12.72).
  2. **WinPE media-sync runtime (r12.62, mock DISM).** With boot.wim
     index 2 mocked at build 26100, the sync succeeds with zero
     failures, requires setuphost.exe, byte-matches every one of the
     seven semantic media targets to its WinPE source, categorizes
     setup binaries / boot managers / boot.stl correctly, and the
     separator-normalized standard boot-manager target set is exactly
     the four Microsoft alias paths. (Measured platform note: on
     Windows the case-insensitive alias de-dup collapses the raw
     record list to 4 boot-manager rows; on Linux pwsh the discovered
     '/'-form and declared '\\'-form of the same alias both survive,
     so the raw count is 5 while the normalized-unique set is
     identical. The contract pins the platform-invariant set.)
  3. **P10 write-set authority binding (r12.72).** The P10 last-writer
     evidence binds each tracked path to its final authority: a
     byte-changed firmware boot manager to P10Pca2023Overlay, an
     unchanged root bootmgr.efi to P09WinPeSyncRetained, and boot.stl
     always to P10BootStlSync, with exactly two override authorities.
  4. **P11 final-identity evidence gating (r12.62 -> r12.72).** The
     final ISO is verified against P09 authority except where explicit
     successful P10 write evidence establishes a later authority:
     valid evidence is consumed (both overrides), while absent,
     required-but-missing, tampered-ISO and stale-evidence states are
     all rejected.
  5. **Server 2022 reviewed-pinned identity (r12.71/r12.72).** A
     reviewed-pinned Catalog row whose exact configured filename
     carries the SHA-1 digest is Verified in PinnedReviewedIdentity
     mode with the ExactConfiguredFileNameDigest binding; a digest-less
     filename stays fail-closed; the P04 selector emits the explicit
     ConfiguredSha1OrFileNameDigest token for such a filename; and the
     full Setup-DU package authority gate reaches Trusted with the
     pinned-identity success status.
  6. **Server 2019 final Setup-binary authority (r12.72).** The final
     Setup-DU media verification uses P09 WinPE authority for setup
     binaries (never the earlier DU hash), counts the three authority
     classes, rejects byte tampering after P09, and rejects a boot.wim
     override claim without matching successful P09 evidence.
  7. **Setup-DU final manifest validation (r12.72).** An unsupported
     P09 evidence schema and a traversal RelativePath are rejected.

Run:  python3 tests/media_authority_test.py
Deps: pwsh on PATH (same dependency class as T40/T47/T48).
"""
from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"

# Subject functions: defined exactly once and extracted by the driver.
CATALOG_AUTHORITY_FUNCTIONS = [
    "Test-IsCatalogPlaceholderFileName",
    "Get-PatchConfiguredCatalogIdentity",
    "Convert-CatalogSha1HexToBase64",
    "Select-CatalogCandidateAsset",
    "Get-CatalogIdentityEvidenceAssessment",
    "Get-SetupDuPackageAuthority",
    "Resolve-SafeMediaRelativePath",
    "Test-SetupDuFinalMediaManifest",
]
MEDIA_AUTHORITY_FUNCTIONS = [
    "Sync-ServicedWinPeMediaFiles",
    "Test-FinalWinPeMediaIdentity",
    "Get-P10MediaWriteSnapshot",
    "New-P10MediaWriteSetEvidence",
    "Get-PathRelativeToRootInvariant",
    "New-WinPeMediaSyncRecord",
]
# Dependency closure extracted for the driver (not separately pinned
# here): file-evidence helpers and the canonical JSON reader used by
# Test-FinalWinPeMediaIdentity.
DEPENDENCY_FUNCTIONS = [
    "Get-SetupBinaryFileEvidence",
    "Get-FileSha256OrEmpty",
    "Read-ReleaseJsonFile",
    "ConvertFrom-CanonicalJson",
    "_CanonicalJson_SkipWs",
    "_CanonicalJson_ParseValue",
    "_CanonicalJson_ParseObject",
    "_CanonicalJson_ParseArray",
    "_CanonicalJson_ParseString",
    "_CanonicalJson_ParseNumber",
    "_CanonicalJson_ParseBool",
    "_CanonicalJson_ParseNull",
]

# Retained r12.62+ media-sync surface and the r12.72 explicit P09
# boot-manager creation pins. The needles are facts of the artifact
# under test, verified against the script text.
STATIC_PINS = [
    ("P09 media-sync function retained", "function Sync-ServicedWinPeMediaFiles"),
    ("P09 sync schema declared",
     "SchemaVersion                   = 'winpe-media-final-sync/1.0'"),
    ("P09 sync evidence artifact name retained", "P09_winpe_media_sync.json"),
    ("P11 final-identity function retained", "function Test-FinalWinPeMediaIdentity"),
    ("P11 final-identity schema declared",
     "SchemaVersion = 'winpe-media-final-identity/1.1'"),
    ("P11 verification row wired", "Add-VRow -Check 'WinPeMediaIdentity'"),
    ("P11 identity evidence artifact name retained", "P11_winpe_media_identity.json"),
    ("P08 boot.wim export function retained", "function Export-BootWimCompressed"),
    ("P08 export evidence artifact name retained", "P08_bootwim_export.json"),
    ("r12.62 cleanup defer wiring retained",
     "-IncludeDefer:($Defer -and $Script:ResetBaseOnCleanup)"),
    ("P09 explicitly creates/verifies EFI Microsoft bootmgfw.efi",
     "RelativePath = 'EFI\\Microsoft\\Boot\\bootmgfw.efi'"),
    ("P09 explicitly creates/verifies root bootmgr.efi",
     "RelativePath = 'bootmgr.efi'"),
]

DRIVER = r'''
param([Parameter(Mandatory)][string]$ScriptPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$FunctionNames = @(__FUNCTION_NAMES__)
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Name,[bool]$Ok,[string]$Detail='') {
    $results.Add([pscustomobject]@{Name=$Name;Ok=$Ok;Detail=$Detail}) | Out-Null
}
function Run-Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; Add-Result $Name $true }
    catch { Add-Result $Name $false ([string]$_.Exception.Message) }
}
function Expect([bool]$Cond,[string]$Why) { if (-not $Cond) { throw $Why } }
function Expect-Eq($Actual,$Expected,[string]$Why) {
    if ($Actual -ne $Expected) { throw "$Why expected=[$Expected] actual=[$Actual]" }
}
function ConvertTo-NormalizedMediaPath([string]$Path) {
    return $Path.Replace('\','/').ToLowerInvariant()
}
function Write-FixtureBytes([string]$Path,[byte[]]$Bytes) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllBytes($Path,$Bytes)
}
function Get-FixtureHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) { throw 'script parse errors' }
foreach ($n in $FunctionNames) {
    $defs=@($ast.FindAll({param($x)$x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true))
    if ($defs.Count -ne 1) { throw "function $n definition count $($defs.Count)" }
    Invoke-Expression $defs[0].Extent.Text
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('t52-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$Script:LogsDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Path $Script:LogsDir -Force | Out-Null

# Mock only the DISM boundary; every other dependency is the extracted
# production implementation. boot.wim index 2 reports build 26100 and the
# mount surfaces the five WinPE authority sources.
function Invoke-DismCmdlet {
    param([string]$CommandName,[hashtable]$Parameters)
    if ($CommandName -eq 'Get-WindowsImage') {
        return [pscustomobject]@{ Version = '10.0.26100.33158' }
    }
    if ($CommandName -eq 'Mount-WindowsImage') {
        $m = $Parameters.Path
        foreach ($pair in @(
            @('sources/setup.exe','serviced-setup'),
            @('sources/setuphost.exe','serviced-setuphost'),
            @('Windows/Boot/EFI/bootmgfw.efi','serviced-bootmgfw'),
            @('Windows/Boot/EFI/bootmgr.efi','serviced-bootmgr'),
            @('Windows/Boot/EFI/boot.stl','serviced-bootstl')
        )) {
            Write-FixtureBytes -Path (Join-Path $m $pair[0]) -Bytes ([Text.Encoding]::ASCII.GetBytes($pair[1]))
        }
        return
    }
    if ($CommandName -eq 'Dismount-WindowsImage') { return }
    throw ('Unexpected DISM command in fixture: {0}' -f $CommandName)
}

try {

# ---- 1. WinPE media-sync runtime (r12.62 semantics, mock DISM) ----
$syncMedia = Join-Path $root 'sync/media'
$syncWork = Join-Path $root 'sync/work'
Write-FixtureBytes -Path (Join-Path $syncMedia 'sources/boot.wim') -Bytes ([byte[]](1,2,3))
foreach ($pair in @(
    @('sources/setup.exe','stale-setup'),
    @('sources/setuphost.exe','stale-setuphost'),
    @('EFI/Boot/bootx64.efi','stale-critical'),
    @('EFI/Microsoft/Boot/bootmgfw.efi','stale-standard'),
    @('bootmgr.efi','stale-root-manager'),
    @('EFI/Microsoft/Boot/bootmgr.efi','stale-standard-manager'),
    @('EFI/Microsoft/Boot/boot.stl','stale-stl')
)) {
    Write-FixtureBytes -Path (Join-Path $syncMedia $pair[0]) -Bytes ([Text.Encoding]::ASCII.GetBytes($pair[1]))
}
$sync = Sync-ServicedWinPeMediaFiles -ExtractedMediaPath $syncMedia -WorkRoot $syncWork
Run-Check 'sync succeeds with zero failures against the mocked WinPE authority' {
    Expect ([bool]$sync.Success) ('sync failed: ' + [string]$sync.ErrorMessage)
    Expect-Eq ([int]$sync.FailureCount) 0 'failure count'
}
Run-Check 'boot.wim index 2 build 26100 requires setuphost.exe' {
    Expect ([bool]$sync.SetupHostRequired) 'SetupHostRequired not set at 26100'
}
Run-Check 'all seven semantic media targets are byte-matched to their WinPE source' {
    $byPath = @{}
    foreach ($rec in @($sync.Records)) {
        $byPath[(ConvertTo-NormalizedMediaPath ([string]$rec.RelativePath))] = $rec
    }
    foreach ($p in @(
        'sources/setup.exe','sources/setuphost.exe',
        'efi/boot/bootx64.efi','efi/microsoft/boot/bootmgfw.efi',
        'bootmgr.efi','efi/microsoft/boot/bootmgr.efi',
        'efi/microsoft/boot/boot.stl'
    )) {
        Expect ($byPath.ContainsKey($p)) ('missing sync record: ' + $p)
        Expect ([bool]$byPath[$p].MatchesSource) ('sync mismatch: ' + $p)
    }
}
Run-Check 'normalized standard boot-manager target set is exactly the four aliases' {
    $observed = @($sync.Records | Where-Object { $_.Category -eq 'StandardBootManager' } |
        ForEach-Object { ConvertTo-NormalizedMediaPath ([string]$_.RelativePath) } |
        Sort-Object -Unique)
    $expected = @('bootmgr.efi','efi/boot/bootx64.efi',
                  'efi/microsoft/boot/bootmgfw.efi','efi/microsoft/boot/bootmgr.efi')
    Expect-Eq ($observed -join ';') ($expected -join ';') 'standard boot-manager set'
}
Run-Check 'setup binaries and boot.stl carry their authority categories' {
    foreach ($rec in @($sync.Records)) {
        $norm = ConvertTo-NormalizedMediaPath ([string]$rec.RelativePath)
        if ($norm -like 'sources/*.exe') { Expect-Eq ([string]$rec.Category) 'SetupBinary' ('category: ' + $norm) }
        if ($norm -eq 'efi/microsoft/boot/boot.stl') { Expect-Eq ([string]$rec.Category) 'SecureBootTrustList' ('category: ' + $norm) }
    }
}

# ---- 2/3. P10 write-set authority binding and P11 evidence gating ----
$extracted = Join-Path $root 'authority/extracted'
$iso = Join-Path $root 'authority/iso'
New-Item -ItemType Directory -Path $extracted,$iso -Force | Out-Null
$authorityPaths = [ordered]@{
    'sources\setup.exe'              = [byte[]](1..64)
    'sources\setuphost.exe'          = [byte[]](65..128)
    'EFI\Boot\bootx64.efi'           = [byte[]](129..192)
    'bootmgr.efi'                    = [byte[]](193..240)
    'EFI\Microsoft\Boot\boot.stl'    = [byte[]](241..255)
}
foreach ($entry in $authorityPaths.GetEnumerator()) {
    $resolved = Resolve-SafeMediaRelativePath -RootPath $extracted -RelativePath $entry.Key
    Write-FixtureBytes -Path $resolved.FullPath -Bytes $entry.Value
}
$p09Records = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $authorityPaths.GetEnumerator()) {
    $resolved = Resolve-SafeMediaRelativePath -RootPath $extracted -RelativePath $entry.Key
    $item = Get-Item -LiteralPath $resolved.FullPath
    $hash = Get-FixtureHash $resolved.FullPath
    $category = if ($entry.Key -like 'sources*') { 'SetupBinary' }
                elseif ($entry.Key -like '*boot.stl') { 'SecureBootTrustList' }
                else { 'StandardBootManager' }
    $p09Records.Add([pscustomobject]@{
        RelativePath = $entry.Key; Category = $category
        SourceRole = 'P09 fixture'; Required = $true
        Success = $true; MatchesSource = $true
        SourcePath = ('fixture:' + $entry.Key)
        SourceSizeBytes = [int64]$item.Length; SourceSha256 = $hash
        AfterSizeBytes = [int64]$item.Length; AfterSha256 = $hash
    }) | Out-Null
}
$p09 = [pscustomobject]@{
    SchemaVersion = 'winpe-media-final-sync/1.0'
    Success = $true; ErrorMessage = ''
    Records = $p09Records.ToArray()
}
$p09Path = Join-Path $root 'authority/P09_winpe_media_sync.json'
$p09 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $p09Path -Encoding UTF8

$before = Get-P10MediaWriteSnapshot -ExtractedMediaPath $extracted
$bootPath = (Resolve-SafeMediaRelativePath -RootPath $extracted -RelativePath 'EFI\Boot\bootx64.efi').FullPath
$stlPath = (Resolve-SafeMediaRelativePath -RootPath $extracted -RelativePath 'EFI\Microsoft\Boot\boot.stl').FullPath
Write-FixtureBytes -Path $bootPath -Bytes ([byte[]](10..100))
Write-FixtureBytes -Path $stlPath -Bytes ([byte[]](101..180))
$stlHash = Get-FixtureHash $stlPath
$bootStl = [pscustomobject]@{
    SchemaVersion = 'pca2023-boot-stl-sync/1.0'
    Success = $true; MatchesSource = $true
    SourceSha256 = $stlHash; DestinationSha256After = $stlHash
}
$p10 = New-P10MediaWriteSetEvidence -ExtractedMediaPath $extracted -BeforeSnapshot $before -BootStlSyncEvidence $bootStl
Run-Check 'P10 write-set evidence creation succeeds' {
    Expect ([bool]$p10.Success) ('P10 write-set failed: ' + [string]$p10.ErrorMessage)
}
Run-Check 'P10 records exactly two override authorities' {
    Expect-Eq ([int]$p10.OverrideCount) 2 'override count'
}
Run-Check 'byte-changed firmware boot manager binds to P10Pca2023Overlay' {
    $row = @($p10.Records | Where-Object RelativePath -ieq 'EFI\Boot\bootx64.efi')
    Expect-Eq ($row.Count) 1 'bootx64 record count'
    Expect-Eq ([string]$row[0].FinalAuthority) 'P10Pca2023Overlay' 'bootx64 authority'
}
Run-Check 'unchanged root bootmgr.efi retains P09 authority' {
    $row = @($p10.Records | Where-Object RelativePath -ieq 'bootmgr.efi')
    Expect-Eq ($row.Count) 1 'bootmgr record count'
    Expect-Eq ([string]$row[0].FinalAuthority) 'P09WinPeSyncRetained' 'bootmgr authority'
}
Run-Check 'boot.stl always binds to P10BootStlSync authority' {
    $row = @($p10.Records | Where-Object RelativePath -ieq 'EFI\Microsoft\Boot\boot.stl')
    Expect-Eq ($row.Count) 1 'boot.stl record count'
    Expect-Eq ([string]$row[0].FinalAuthority) 'P10BootStlSync' 'boot.stl authority'
}
$p10Path = Join-Path $root 'authority/P10_media_write_set.json'
$p10 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $p10Path -Encoding UTF8

Get-ChildItem -LiteralPath $extracted -Force | Copy-Item -Destination $iso -Recurse -Force
Run-Check 'P11 accepts the final ISO under valid explicit P10 authority evidence' {
    $pass = Test-FinalWinPeMediaIdentity -MountedIsoRoot $iso -ExtractedMediaPath $extracted `
        -SyncEvidencePath $p09Path -P10WriteEvidencePath $p10Path -RequireP10WriteEvidence
    Expect ([bool]$pass.MatchesExpected) ('valid P10 authority rejected: ' + [string]$pass.ErrorMessage)
    Expect-Eq ([int]$pass.FailureCount) 0 'failure count'
    Expect-Eq ([int]$pass.P10OverrideCount) 2 'consumed override count'
}
Run-Check 'P11 rejects changed media without explicit P10 authority evidence' {
    $noEvidence = Test-FinalWinPeMediaIdentity -MountedIsoRoot $iso -ExtractedMediaPath $extracted `
        -SyncEvidencePath $p09Path
    Expect (-not [bool]$noEvidence.MatchesExpected) 'accepted without P10 evidence'
}
Run-Check 'P11 rejects a required-but-missing P10 evidence file' {
    $missing = Test-FinalWinPeMediaIdentity -MountedIsoRoot $iso -ExtractedMediaPath $extracted `
        -SyncEvidencePath $p09Path -P10WriteEvidencePath (Join-Path $root 'authority/missing.json') -RequireP10WriteEvidence
    Expect (-not [bool]$missing.MatchesExpected) 'missing required P10 evidence accepted'
}
Run-Check 'P11 rejects a tampered final ISO boot manager (single failing record)' {
    $isoBoot = (Resolve-SafeMediaRelativePath -RootPath $iso -RelativePath 'EFI\Boot\bootx64.efi').FullPath
    $original = [IO.File]::ReadAllBytes($isoBoot)
    Write-FixtureBytes -Path $isoBoot -Bytes ([byte[]](1,2,3,4))
    try {
        $tampered = Test-FinalWinPeMediaIdentity -MountedIsoRoot $iso -ExtractedMediaPath $extracted `
            -SyncEvidencePath $p09Path -P10WriteEvidencePath $p10Path -RequireP10WriteEvidence
        Expect (-not [bool]$tampered.MatchesExpected) 'tampered ISO accepted'
        Expect-Eq ([int]$tampered.FailureCount) 1 'tamper failure count'
    } finally {
        Write-FixtureBytes -Path $isoBoot -Bytes $original
    }
}
Run-Check 'P11 rejects stale P10 evidence after extracted-media mutation' {
    $originalBoot = [IO.File]::ReadAllBytes($bootPath)
    Write-FixtureBytes -Path $bootPath -Bytes ([byte[]](5,6,7,8))
    try {
        $stale = Test-FinalWinPeMediaIdentity -MountedIsoRoot $iso -ExtractedMediaPath $extracted `
            -SyncEvidencePath $p09Path -P10WriteEvidencePath $p10Path -RequireP10WriteEvidence
        Expect (-not [bool]$stale.MatchesExpected) 'stale P10 evidence accepted'
    } finally {
        Write-FixtureBytes -Path $bootPath -Bytes $originalBoot
    }
}

# ---- 4. Server 2022 reviewed-pinned identity (measured E2E shape) ----
$updateId = '78746602-33c6-4ac9-b485-1a0f7e690ff8'
$fileName = 'windows10.0-kb5079518-x64_d450321f7b43e6d3f94d47d65ca5067f5ccb4efb.cab'
$pinnedRecord = [pscustomobject]@{
    Kind = 'SetupDU'; KbId = 'KB5079518'; UpdateId = $updateId; FileName = $fileName
    CatalogScopedIdentityVerified = $false
    CatalogScopedIdentityBasis = 'NotRequiredInPinnedIdentityMode'
    CatalogScopedArchitecture = 'x64'
    CatalogScopedRawSha256 = ''
    CatalogScopedParseBasis = 'BypassedSearchAndScopedView'
    CatalogPinnedIdentityVerified = $true
    CatalogPinnedIdentityBasis = 'ReviewedUpdateId+ExactFileName+ConfiguredDigest'
    CatalogSelectionBasis = 'ConfiguredUpdateId+ConfiguredFileName+PinnedReviewedIdentity'
    MetadataOnly = $false
    Source = ('https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2026/07/' + $fileName)
}
Run-Check 'reviewed-pinned row with digest-bearing filename is Verified in pinned mode' {
    $assessment = Get-CatalogIdentityEvidenceAssessment -Record $pinnedRecord
    Expect ([bool]$assessment.Verified) 'pinned evidence rejected'
    Expect-Eq ([string]$assessment.Mode) 'PinnedReviewedIdentity' 'assessment mode'
    Expect-Eq ([string]$assessment.PinnedIdentityDigestBinding) 'ExactConfiguredFileNameDigest' 'digest binding'
}
Run-Check 'reviewed-pinned row without a digest-bearing filename stays fail-closed' {
    $unsafe = $pinnedRecord | Select-Object *
    $unsafe.FileName = 'windows10.0-kb5079518-x64.cab'
    $assessment = Get-CatalogIdentityEvidenceAssessment -Record $unsafe
    Expect (-not [bool]$assessment.Verified) 'digest-less filename accepted'
}
Run-Check 'selector emits the explicit filename-digest token for a pinned filename' {
    $patch = [pscustomobject]@{ KbId='KB5079518'; UpdateId=$updateId; FileName=$fileName; IsMetadataOnly=$false }
    $candidate = [pscustomobject]@{
        Row = [pscustomobject]@{ uid=$updateId; PinnedIdentityVerified=$true; ScopedIdentityVerified=$false }
        File = [pscustomobject]@{ fileName=$fileName; digest=''; sha256='' }
    }
    $selected = Select-CatalogCandidateAsset -Patch $patch -Candidates @($candidate)
    Expect ([string]$selected.SelectionBasis -match '(^|\+)ConfiguredSha1OrFileNameDigest(\+|$)') `
        ('digest token missing from SelectionBasis: ' + [string]$selected.SelectionBasis)
}
Run-Check 'full Setup-DU authority gate reaches Trusted with pinned-identity status' {
    $packagePath = Join-Path $Script:LogsDir $fileName
    [IO.File]::WriteAllBytes($packagePath,[byte[]](1..127))
    $packageHash = Get-FixtureHash $packagePath
    @($pinnedRecord) | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $Script:LogsDir 'P04_catalog_crosscheck.json') -Encoding UTF8
    $authorityPatch = [pscustomobject]@{
        PatchType = 'SetupDU'; KbId = 'KB5079518'; UpdateId = $updateId; FileName = $fileName
        LocalPath = $packagePath; Source = [string]$pinnedRecord.Source
        ExpectedHashes = @{ 'sha-256' = $packageHash }
    }
    $authority = Get-SetupDuPackageAuthority -Patch $authorityPatch
    Expect ([bool]$authority.Trusted) ('authority untrusted: ' + [string]$authority.Status)
    Expect-Eq ([string]$authority.Status) 'CatalogPinnedIdentityAndLocalHashVerified' 'authority status'
}

# ---- 5. Server 2019 final Setup-binary authority (measured shape) ----
$duRoot = Join-Path $root 'setupdu'
$duSources = Join-Path $duRoot 'sources'
New-Item -ItemType Directory -Path $duSources -Force | Out-Null
$setupBytes = [byte[]](1..100)
$hostBytes = [byte[]](101..200)
$normalBytes = [byte[]](201..250)
Write-FixtureBytes -Path (Join-Path $duSources 'setup.exe') -Bytes $setupBytes
Write-FixtureBytes -Path (Join-Path $duSources 'setuphost.exe') -Bytes $hostBytes
Write-FixtureBytes -Path (Join-Path $duSources 'normal.dll') -Bytes $normalBytes
$setupHash = Get-FixtureHash (Join-Path $duSources 'setup.exe')
$hostHash = Get-FixtureHash (Join-Path $duSources 'setuphost.exe')
$normalHash = Get-FixtureHash (Join-Path $duSources 'normal.dll')
$duManifest = [pscustomobject]@{ Records = @(
    [pscustomobject]@{ RelativePath='setup.exe'; Decision='SkipOverriddenByBootWim'; OverriddenByBootWim=$true; ExpectedPresentAfter=$true; ExpectedSha256After=('b'*64) },
    [pscustomobject]@{ RelativePath='setuphost.exe'; Decision='Apply'; OverriddenByBootWim=$false; ExpectedPresentAfter=$true; ExpectedSha256After=('a'*64) },
    [pscustomobject]@{ RelativePath='normal.dll'; Decision='Apply'; OverriddenByBootWim=$false; ExpectedPresentAfter=$true; ExpectedSha256After=$normalHash },
    [pscustomobject]@{ RelativePath='fr-fr\excluded.dll.mui'; Decision='SkipLanguageResource'; OverriddenByBootWim=$false; ExpectedPresentAfter=$false; ExpectedSha256After='' }
) }
$duSync = [pscustomobject]@{
    SchemaVersion = 'winpe-media-final-sync/1.0'; Success = $true; ErrorMessage = ''
    Records = @(
        [pscustomobject]@{ RelativePath='sources\setup.exe'; Category='SetupBinary'; Success=$true; MatchesSource=$true; SourceSizeBytes=[int64]$setupBytes.Length; AfterSizeBytes=[int64]$setupBytes.Length; SourceSha256=$setupHash; AfterSha256=$setupHash },
        [pscustomobject]@{ RelativePath='sources\setuphost.exe'; Category='SetupBinary'; Success=$true; MatchesSource=$true; SourceSizeBytes=[int64]$hostBytes.Length; AfterSizeBytes=[int64]$hostBytes.Length; SourceSha256=$hostHash; AfterSha256=$hostHash }
    )
}
Run-Check 'final verification passes with P09 governing both setup binaries' {
    $final = Test-SetupDuFinalMediaManifest -MountedIsoRoot $duRoot -SetupManifest $duManifest -WinPeSyncEvidence $duSync
    Expect ([bool]$final.MatchesExpected) ('final authority fixture failed: ' + [string]$final.ErrorMessage)
    Expect-Eq ([int]$final.WinPeFinalAuthorityCount) 2 'P09 final-authority count'
    Expect-Eq ([int]$final.SetupDuAuthorityCount) 1 'Setup-DU authority count'
    Expect-Eq ([int]$final.ExcludedLanguageCount) 1 'excluded-language count'
}
Run-Check 'byte tampering after P09 is rejected' {
    Write-FixtureBytes -Path (Join-Path $duSources 'setuphost.exe') -Bytes ([byte[]](1,2,3))
    try {
        $tampered = Test-SetupDuFinalMediaManifest -MountedIsoRoot $duRoot -SetupManifest $duManifest -WinPeSyncEvidence $duSync
        Expect (-not [bool]$tampered.MatchesExpected) 'tampered setuphost accepted'
    } finally {
        Write-FixtureBytes -Path (Join-Path $duSources 'setuphost.exe') -Bytes $hostBytes
    }
}
Run-Check 'a boot.wim override claim without matching P09 evidence is rejected' {
    $partialSync = [pscustomobject]@{
        SchemaVersion = 'winpe-media-final-sync/1.0'; Success = $true; ErrorMessage = ''
        Records = @($duSync.Records[1])
    }
    $missing = Test-SetupDuFinalMediaManifest -MountedIsoRoot $duRoot -SetupManifest $duManifest -WinPeSyncEvidence $partialSync
    Expect (-not [bool]$missing.MatchesExpected) 'override without P09 evidence accepted'
}

# ---- 6. Setup-DU final manifest validation guards ----
Run-Check 'unsupported P09 evidence schema is rejected' {
    $badSync = [pscustomobject]@{ SchemaVersion='bad/1'; Success=$true; Records=@() }
    $badSchema = Test-SetupDuFinalMediaManifest -MountedIsoRoot $duRoot -SetupManifest $duManifest -WinPeSyncEvidence $badSync
    Expect (-not [bool]$badSchema.MatchesExpected) 'unsupported schema accepted'
}
Run-Check 'traversal RelativePath in the Setup-DU manifest is rejected' {
    $unsafeManifest = [pscustomobject]@{ Records = @(
        [pscustomobject]@{ RelativePath='..\escape.dll'; Decision='Apply'; OverriddenByBootWim=$false; ExpectedPresentAfter=$false; ExpectedSha256After='' }
    ) }
    $unsafe = Test-SetupDuFinalMediaManifest -MountedIsoRoot $duRoot -SetupManifest $unsafeManifest -WinPeSyncEvidence $null
    Expect (-not [bool]$unsafe.MatchesExpected) 'traversal path accepted'
}

} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

$results | ConvertTo-Json -Depth 4
'''


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def main() -> int:
    passed = failed = 0

    print("=" * 72)
    print("T52 final-writer media authority contract")
    print("=" * 72)

    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")

    for name, needle in STATIC_PINS:
        passed, failed = check(name, needle in text,
                               f"marker missing: {needle}", passed, failed)

    for fn in CATALOG_AUTHORITY_FUNCTIONS + MEDIA_AUTHORITY_FUNCTIONS:
        n = len(re.findall(r"(?m)^\s*function\s+" + re.escape(fn) + r"\b", text))
        passed, failed = check(
            f"authority function defined exactly once: {fn}",
            n == 1, f"definition count = {n}", passed, failed)

    pwsh = shutil.which("pwsh")
    if pwsh is None:
        passed, failed = check("behavioral driver", False,
                               "pwsh not on PATH (required, as for T40)",
                               passed, failed)
    else:
        all_functions = (CATALOG_AUTHORITY_FUNCTIONS + MEDIA_AUTHORITY_FUNCTIONS
                         + DEPENDENCY_FUNCTIONS)
        with tempfile.TemporaryDirectory() as td:
            driver = pathlib.Path(td) / "t52_driver.ps1"
            names = ",".join(f"'{n}'" for n in all_functions)
            driver.write_text(DRIVER.replace("__FUNCTION_NAMES__", names),
                              encoding="utf-8")
            proc = subprocess.run(
                [pwsh, "-NoProfile", "-File", str(driver),
                 "-ScriptPath", str(SCRIPT_PATH)],
                capture_output=True, text=True, timeout=300)
        if proc.returncode != 0:
            passed, failed = check(
                "behavioral driver", False,
                f"rc={proc.returncode} stderr={proc.stderr.strip()[:300]!r}",
                passed, failed)
        else:
            try:
                rows = json.loads(proc.stdout)
            except json.JSONDecodeError:
                rows = None
            if rows is None:
                passed, failed = check(
                    "behavioral driver", False,
                    f"non-JSON output: {proc.stdout.strip()[:200]!r}",
                    passed, failed)
            else:
                if isinstance(rows, dict):
                    rows = [rows]
                for row in rows:
                    passed, failed = check(
                        row.get("Name", "<unnamed>"),
                        bool(row.get("Ok")),
                        str(row.get("Detail", ""))[:300],
                        passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, "
          f"{passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
