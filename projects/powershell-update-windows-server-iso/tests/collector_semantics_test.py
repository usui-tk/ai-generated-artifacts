#!/usr/bin/env python3
"""T48: Collector semantics contract (behavioral, offline via pwsh).

Second half of the Collector coverage gap (artifact/identity half: T47).
Verifies the r10 -> r12 hardening arc of
`Collect-WindowsServerPostInstallEvidence.ps1` behaviorally: the
functions under test are extracted from the Collector's own AST and
exercised against fixtures whose values are measured post-install facts
from the four-OS ja-jp runs.

Specification source: the r12.75 distribution's required suite, axes
R1273 / R1274 / R1275 (input-only per the standing ruling; logic
re-authored, code not copied). Ledger: TEST-REIMPL-LEDGER.csv rows for
those axes. The real-environment-validated r12.75 Collector is the
specification baseline (code-anchored testing); the Collector itself is
untouched and every expected value below encodes its measured behavior.

Class: B (behaviour pins). Justification: pending-reboot classification,
restart-preflight gating and Secure Boot evidence semantics live in
Collector code; no declared data surface expresses them.

What this asserts:

  1. **Pending-reboot discrimination (r10).** The measured Server
     2022/2025 first-boot updater-cleanup PFRO shapes classify as
     Advisory; unknown operations, rename/move pairs and malformed data
     stay fail-closed (Blocking); CBS / Windows Update pending always
     override an advisory PFRO; registry read errors yield Unknown
     without asserting a confirmed pending reboot.
  2. **Secure Boot event-field parsing (r10).** Blank label fields in
     the measured 1801/1808 ja-jp event shapes stay null instead of
     consuming the next label; populated fields are retained; a latest
     1808 is recognized as completion.
  3. **Restart preflight (r11).** Explicit confirmation is required
     (parameter provenance recorded); any Advisory / Blocking / Unknown
     startup pending-reboot state blocks full collection; boot-history
     evidence corroborates but is never authoritative. Structurally,
     pending-reboot state is captured at startup AND rechecked later,
     and the preflight decision precedes Secure Boot collection.
  4. **Secure Boot evidence semantics (r12).** WindowsUEFICA2023Capable
     is reference-only (value 2 never becomes status authority; a
     missing value stays unavailable); the measured WinCS query shape
     parses, and WinCS state Disabled under UEFICA2023Status=Updated
     means not-required rather than incomplete, with UEFICA2023Status
     as the status authority; in the full assessment a stale historical
     1808 cannot override a newer 1801, the measured 2022/2025 Updated
     shape confirms completion with its three evidence sources, the
     measured 2019 monitoring divergence stays conservative, and
     Authenticode primary-signer observations remain diagnostic-only.

Run:  python3 tests/collector_semantics_test.py
Deps: pwsh on PATH (same dependency class as T40/T47).
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
COLLECTOR_PATH = SUBPROJECT_ROOT / "Collect-WindowsServerPostInstallEvidence.ps1"

# Functions under test, extracted from the Collector AST by the driver.
FUNCTIONS_UNDER_TEST = [
    "Get-PropertyValue",
    "Test-PendingFileRenameAdvisoryCleanup",
    "Convert-PendingFileRenameOperationsEvidence",
    "Resolve-PendingRebootClassification",
    "Get-SecureBootEventFieldValue",
    "Get-SecureBootRolloutStatus",
    "Resolve-StartupPreflightDecision",
    "Get-PostInstallRestartConfirmation",
    "Get-WindowsUefiCa2023CapableInterpretation",
    "Convert-WinCsSecureBootQueryOutput",
    "Get-WinCsSecureBootInterpretation",
    "Get-SecureBootAssessment",
]

DRIVER = r'''
param([Parameter(Mandatory)][string]$CollectorPath)
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

$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($CollectorPath,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) { throw 'Collector parse errors' }
foreach ($n in $FunctionNames) {
    $defs=@($ast.FindAll({param($x)$x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true))
    if ($defs.Count -ne 1) { throw "function $n definition count $($defs.Count)" }
    Invoke-Expression $defs[0].Extent.Text
}
$pendingCallSites=@($ast.FindAll({param($x)$x -is [System.Management.Automation.Language.CommandAst] -and $x.GetCommandName() -eq 'Get-PendingRebootEvidence'},$true)).Count

# ---- 1. Pending-reboot discrimination (measured PFRO shapes) ----
$pfr2022=@(
 '*1\??\C:\Windows\SystemTemp\MicrosoftEdgeUpdate.exe.old{AB8FD611-DB75-41F6-A683-1AC6BBA73876}','',
 '*1\??\C:\Program Files (x86)\Microsoft\EdgeUpdate\1.3.135.41','')
$pfr2025=@(
 '*1\??\C:\Windows\SystemTemp\MicrosoftEdgeUpdate.exe.old{80AAB89E-6C31-4DE8-A65A-D8D19BA22EB4}','',
 '*1\??\C:\Windows\SystemTemp\CopilotUpdate.exe.old{19200B3B-DD50-4AD0-BA0C-452643EA6062}','',
 '*1\??\C:\Program Files (x86)\Microsoft\EdgeUpdate\1.3.215.9','')

Run-Check 'measured 2022 updater cleanup classifies Advisory' {
    $p=Convert-PendingFileRenameOperationsEvidence -Value $pfr2022
    Expect-Eq $p.PairCount 2 'pair count'
    Expect-Eq $p.AdvisoryOperationCount 2 'advisory count'
    Expect-Eq $p.BlockingOperationCount 0 'blocking count'
    Expect ([bool]$p.AdvisoryCleanupOnly) 'not advisory-only'
    $c=Resolve-PendingRebootClassification -CbsPending:$false -WindowsUpdatePending:$false -PendingFileRenamePresent:$true -PendingFileRenameEvidence $p -ReadErrorCount 0
    Expect-Eq $c.Classification 'Advisory' 'classification'
    Expect ($c.RebootPending -and $c.AdvisoryRebootPending -and -not $c.BlockingRebootPending) 'advisory flags inconsistent'
}
Run-Check 'measured 2025 updater cleanup classifies Advisory' {
    $p=Convert-PendingFileRenameOperationsEvidence -Value $pfr2025
    Expect-Eq $p.PairCount 3 'pair count'
    Expect ([bool]$p.AdvisoryCleanupOnly) 'not advisory-only'
    $c=Resolve-PendingRebootClassification -CbsPending:$false -WindowsUpdatePending:$false -PendingFileRenamePresent:$true -PendingFileRenameEvidence $p -ReadErrorCount 0
    Expect-Eq $c.Classification 'Advisory' 'classification'
}
Run-Check 'unknown file operation stays Blocking (fail-closed)' {
    $u=Convert-PendingFileRenameOperationsEvidence -Value @('*1\??\C:\Windows\System32\critical.dll','')
    Expect (-not $u.AdvisoryCleanupOnly) 'unknown op allow-listed'
    $c=Resolve-PendingRebootClassification -CbsPending:$false -WindowsUpdatePending:$false -PendingFileRenamePresent:$true -PendingFileRenameEvidence $u -ReadErrorCount 0
    Expect-Eq $c.Classification 'Blocking' 'classification'
    Expect ([bool]$c.BlockingRebootPending) 'blocking flag'
}
Run-Check 'rename/move pair is not advisory' {
    $r=Convert-PendingFileRenameOperationsEvidence -Value @('*1\??\C:\Temp\source.bin','*1\??\C:\Temp\target.bin')
    Expect (-not $r.AdvisoryCleanupOnly) 'rename treated as advisory'
}
Run-Check 'malformed PFRO data fails closed' {
    $m=Convert-PendingFileRenameOperationsEvidence -Value @('*1\??\C:\Windows\SystemTemp\MicrosoftEdgeUpdate.exe.old{AB8FD611-DB75-41F6-A683-1AC6BBA73876}')
    Expect ($m.Malformed -and -not $m.AdvisoryCleanupOnly) 'malformed not fail-closed'
}
Run-Check 'CBS and Windows Update override advisory PFRO' {
    $p=Convert-PendingFileRenameOperationsEvidence -Value $pfr2022
    $c1=Resolve-PendingRebootClassification -CbsPending:$true -WindowsUpdatePending:$false -PendingFileRenamePresent:$true -PendingFileRenameEvidence $p -ReadErrorCount 0
    Expect-Eq $c1.Classification 'Blocking' 'CBS override'
    $c2=Resolve-PendingRebootClassification -CbsPending:$false -WindowsUpdatePending:$true -PendingFileRenamePresent:$true -PendingFileRenameEvidence $p -ReadErrorCount 0
    Expect-Eq $c2.Classification 'Blocking' 'WU override'
}
Run-Check 'registry read error yields Unknown, not a confirmed pending reboot' {
    $e=Convert-PendingFileRenameOperationsEvidence -Value $null
    $c=Resolve-PendingRebootClassification -CbsPending:$false -WindowsUpdatePending:$false -PendingFileRenamePresent:$false -PendingFileRenameEvidence $e -ReadErrorCount 1
    Expect-Eq $c.Classification 'Unknown' 'classification'
    Expect (-not $c.RebootPending) 'uncertainty reported as pending'
}

# ---- 2. Secure Boot event-field parsing (measured event shapes) ----
$updateType='Windows UEFI CA 2023 (DB), Option ROM CA 2023 (DB), 3P UEFI CA 2023 (DB), KEK 2023, Boot Manager (2023)'
Run-Check '1801 with blank fields keeps null values' {
    $ev=[pscustomobject]@{
        Id=1801;TimeCreated='2026-08-07T09:30:00+09:00'
        Message="update pending`r`nDeviceAttributes: `r`nBucketId: `r`nBucketConfidenceLevel: `r`nUpdateType: `r`nhttps://go.microsoft.com/fwlink/?linkid=2301018"
        EventData=[pscustomobject]@{DeviceAttributes='';BucketId='';BucketConfidenceLevel='';UpdateType=''}
    }
    $r=Get-SecureBootRolloutStatus -EventEvidence ([pscustomobject]@{Available=$true;Events=@($ev)}) -UefiCa2023Status $null
    Expect-Eq $r.BucketId $null 'BucketId consumed next label'
    Expect-Eq $r.Confidence $null 'Confidence consumed next label'
    Expect-Eq $r.UpdateType $null 'UpdateType not null'
}
Run-Check '1808 with blank bucket but populated UpdateType retains it and completes' {
    $ev=[pscustomobject]@{
        Id=1808;TimeCreated='2026-08-07T09:40:00+09:00'
        Message="updated`r`nDeviceAttributes: `r`nBucketId: `r`nBucketConfidenceLevel: `r`nUpdateType: $updateType`r`nhttps://go.microsoft.com/fwlink/?linkid=2301018"
        EventData=[pscustomobject]@{DeviceAttributes='';BucketId='';BucketConfidenceLevel='';UpdateType=$updateType}
    }
    $r=Get-SecureBootRolloutStatus -EventEvidence ([pscustomobject]@{Available=$true;Events=@($ev)}) -UefiCa2023Status 'Updated'
    Expect-Eq $r.BucketId $null 'BucketId'
    Expect-Eq $r.Confidence $null 'Confidence'
    Expect-Eq $r.UpdateType $updateType 'UpdateType lost'
    Expect ([bool]$r.UpdateCompleteByRegistryOrLatestEvent) 'completion not recognized'
}
Run-Check 'populated 1808 fields are retained' {
    $bucket='4e22d051e8c143d2875b9d16ef2241c7ec548985a21e5073126d3c1f9bf53bb2'
    $ev=[pscustomobject]@{
        Id=1808;TimeCreated='2026-08-07T09:20:00+09:00'
        Message="BucketId: $bucket`r`nBucketConfidenceLevel: High Confidence`r`nUpdateType: $updateType"
        EventData=[pscustomobject]@{BucketId=$bucket;BucketConfidenceLevel='High Confidence';UpdateType=$updateType}
    }
    $r=Get-SecureBootRolloutStatus -EventEvidence ([pscustomobject]@{Available=$true;Events=@($ev)}) -UefiCa2023Status 'Updated'
    Expect-Eq $r.BucketId $bucket 'BucketId'
    Expect-Eq $r.Confidence 'High Confidence' 'Confidence'
    Expect-Eq $r.UpdateType $updateType 'UpdateType'
}

# ---- 3. Restart preflight (r11 decision matrix) ----
function New-PendingFixture([string]$Classification,[bool]$Complete=$true) {
    [pscustomobject]@{
        Classification=$Classification;CollectionComplete=$Complete
        RebootPending=($Classification -in @('Advisory','Blocking'))
        BlockingRebootPending=($Classification -eq 'Blocking')
        AdvisoryRebootPending=($Classification -eq 'Advisory')
    }
}
$bootObserved=[pscustomobject]@{Corroboration='Observed'}
$bootNotObserved=[pscustomobject]@{Corroboration='NotObserved'}
$yes=[pscustomobject]@{Confirmed=$true;Source='Fixture'}
$no=[pscustomobject]@{Confirmed=$false;Source='Fixture'}

Run-Check 'parameter confirmation records provenance' {
    $c=Get-PostInstallRestartConfirmation -ConfirmedByParameter
    Expect ([bool]$c.Confirmed) 'not confirmed'
    Expect-Eq $c.Source 'ConfirmPostInstallRestartParameter' 'provenance'
}
Run-Check 'confirmed + clear state passes without boot-history corroboration' {
    $d=Resolve-StartupPreflightDecision -RestartConfirmation $yes -PendingReboot (New-PendingFixture 'None') -BootHistory $bootNotObserved
    Expect ([bool]$d.AllowedToCollect) 'blocked'
    Expect (-not [bool]$d.BootHistoryIsAuthoritative) 'boot history authoritative'
}
Run-Check 'missing confirmation blocks collection' {
    $d=Resolve-StartupPreflightDecision -RestartConfirmation $no -PendingReboot (New-PendingFixture 'None') -BootHistory $bootObserved
    Expect (-not [bool]$d.AllowedToCollect) 'allowed without confirmation'
}
Run-Check 'Advisory and Blocking pending states block collection' {
    foreach ($cls in @('Advisory','Blocking')) {
        $d=Resolve-StartupPreflightDecision -RestartConfirmation $yes -PendingReboot (New-PendingFixture $cls) -BootHistory $bootObserved
        Expect (-not [bool]$d.AllowedToCollect) "$cls did not block"
    }
}
Run-Check 'unreadable pending state fails closed' {
    $d=Resolve-StartupPreflightDecision -RestartConfirmation $yes -PendingReboot (New-PendingFixture 'Unknown' $false) -BootHistory $bootObserved
    Expect (-not [bool]$d.AllowedToCollect) 'Unknown did not block'
}
Run-Check 'pending reboot captured at startup AND rechecked later' {
    Expect ($pendingCallSites -ge 2) "call sites = $pendingCallSites"
}

# ---- 4. Secure Boot evidence semantics (r12) ----
Run-Check 'WindowsUEFICA2023Capable=2 is reference-only, never status authority' {
    $c=Get-WindowsUefiCa2023CapableInterpretation -Value 2
    Expect ([bool]$c.Available) 'value 2 did not parse'
    Expect-Eq $c.Value 2 'numeric value'
    Expect-Eq $c.Meaning 'WindowsUefiCa2023PresentInDbAndBootingFrom2023SignedBootManager' 'meaning'
    Expect ([bool]$c.ReferenceOnly) 'not marked reference-only'
    Expect (-not [bool]$c.AuthoritativeStatusSignal) 'became authoritative'
    Expect ([bool]$c.BootManager2023ReferenceEvidence) 'no reference evidence'
}
Run-Check 'missing WindowsUEFICA2023Capable stays unavailable without failing' {
    $c=Get-WindowsUefiCa2023CapableInterpretation -Value $null
    Expect (-not [bool]$c.Available) 'missing value reported available'
}
$winCsText=@'
Flag: F33E0C8E
  Current Configuration: F33E0C8E001
  State: Disabled
  Pending Configuration: None
  Pending Action: None
  CVE: CVE-2026-21265
  FwLink: https://aka.ms/getsecureboot
  Available Configurations:
    F33E0C8E001
    F33E0C8E002
'@
Run-Check 'measured WinCS query shape parses' {
    $p=Convert-WinCsSecureBootQueryOutput -Text $winCsText
    Expect ([bool]$p.Parsed) 'not parsed'
    Expect-Eq $p.CurrentConfiguration 'F33E0C8E001' 'current configuration'
    Expect-Eq $p.State 'Disabled' 'state'
    Expect-Eq $p.PendingConfiguration 'None' 'pending configuration'
    Expect-Eq $p.PendingAction 'None' 'pending action'
    Expect-Eq $p.CVE 'CVE-2026-21265' 'CVE'
    Expect-Eq @($p.AvailableConfigurations).Count 2 'available configurations'
}
Run-Check 'WinCS Disabled under Updated means not-required; UEFICA2023Status stays authority' {
    $p=Convert-WinCsSecureBootQueryOutput -Text $winCsText
    $i=Get-WinCsSecureBootInterpretation -ParsedQuery $p -UefiCa2023Status 'Updated'
    Expect-Eq $i.Meaning 'NotRequiredCertificatesAlreadyUpdated' 'meaning'
    Expect (-not [bool]$i.IsCompletionSignal) 'WinCS became a completion signal'
    Expect-Eq $i.StatusAuthority 'UEFICA2023Status' 'status authority'
    Expect (-not [bool]$i.RequiresActionBasedOnWinCsAlone) 'WinCS alone requested action'
}
function New-EspFixture {
    [pscustomobject]@{
        CollectionComplete=$true
        Files=@([pscustomobject]@{
            Path='S:\EFI\Microsoft\Boot\bootmgfw.efi';Present=$true
            SignerSubject='CN=Microsoft Windows Production PCA 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
            SignerIndicatesWindowsUefiCa2023=$false
            SignerIndicatesWindowsProductionPca2011=$true
        })
    }
}
function New-SecureBootFixture([string]$Status,$Capable,[int]$LatestEventId,[object[]]$Events) {
    [pscustomobject]@{
        Enabled=$true
        MicrosoftMonitoringStatus=$(if ($Status -eq 'Updated') {'WithoutIssue'} else {'WithIssueOrIncomplete'})
        Registry=[pscustomobject]@{
            UEFICA2023Status=$Status;WindowsUEFICA2023Capable=$Capable
            WindowsUEFICA2023CapableInterpretation=(Get-WindowsUefiCa2023CapableInterpretation -Value $Capable)
            UEFICA2023Error=$null;UEFICA2023ErrorEvent=$null
        }
        FirmwareVariables=[pscustomobject]@{RequiredVariablesAvailable=$true;DirectRequirementsSatisfied=$true}
        Events=[pscustomobject]@{Events=@($Events)}
        RolloutStatus=[pscustomobject]@{
            LatestEventId=$LatestEventId;BucketId=$null;Confidence=$null;UpdateType=$null
            RebootPending=$false;MissingKek=$false
        }
    }
}
Run-Check 'stale historical 1808 does not override a newer 1801' {
    $events=@(
        [pscustomobject]@{Id=1808;TimeCreated='2026-08-07T10:00:00+09:00'},
        [pscustomobject]@{Id=1801;TimeCreated='2026-08-07T11:00:00+09:00'})
    $a=Get-SecureBootAssessment -SecureBoot (New-SecureBootFixture 'NotStarted' $null 1801 $events) -Esp (New-EspFixture)
    Expect (-not [bool]$a.MicrosoftCompletionConfirmed) 'stale 1808 confirmed completion'
    Expect ([bool]$a.HistoricalEvent1808Observed) 'historical 1808 not recorded'
    Expect (-not [bool]$a.LatestCompletionEventIs1808) 'latest-completion flag wrong'
    Expect-Eq $a.State 'NotStartedOrNoValue' 'state'
    Expect (@(@($a.InformationalFindings) -match 'Historical event 1808 evidence exists').Count -gt 0) 'diagnostic not retained'
}
Run-Check 'measured 2022/2025 Updated shape confirms with its evidence sources' {
    $events=@(
        [pscustomobject]@{Id=1808;TimeCreated='2026-08-07T11:32:00+09:00'},
        [pscustomobject]@{Id=1808;TimeCreated='2026-08-07T09:40:00+09:00'})
    $a=Get-SecureBootAssessment -SecureBoot (New-SecureBootFixture 'Updated' 2 1808 $events) -Esp (New-EspFixture)
    Expect ([bool]$a.MicrosoftCompletionConfirmed) 'Updated state not confirmed'
    Expect ([bool]$a.BootManager2023EvidenceConfirmed) 'boot-manager 2023 evidence not confirmed'
    foreach ($src in @('RegistryUEFICA2023StatusUpdated','LatestTpmWmiEvent1808','WindowsUEFICA2023CapableReferenceValue2')) {
        Expect (@($a.BootManager2023EvidenceSources) -contains $src) "missing evidence source $src"
    }
    Expect-Eq $a.BootManagerAuthenticodeAssessmentScope 'DiagnosticOnlyPrimarySignerReturnedByGetAuthenticodeSignature' 'authenticode scope'
    Expect (-not [bool]$a.BootManagerAuthenticodePrimarySignerIndicatesWindowsUefiCa2023) 'PCA2011 signer indicated 2023'
    Expect ([bool]$a.BootManagerAuthenticodePrimarySignerIndicatesWindowsProductionPca2011) 'PCA2011 diagnostic lost'
    Expect (@(@($a.InformationalFindings) -match 'primary signer selected').Count -eq 0) 'misleading signer warning emitted'
}
Run-Check 'measured 2019 monitoring divergence stays conservative' {
    $events=@([pscustomobject]@{Id=1801;TimeCreated='2026-08-07T11:30:00+09:00'})
    $a=Get-SecureBootAssessment -SecureBoot (New-SecureBootFixture 'NotStarted' $null 1801 $events) -Esp (New-EspFixture)
    Expect (-not [bool]$a.MicrosoftCompletionConfirmed) 'divergence inferred completion'
    Expect-Eq $a.State 'NotStartedOrNoValue' 'state'
    Expect (@(@($a.InformationalFindings) -match 'monitoring-state divergence').Count -gt 0) 'divergence information lost'
}

$results | ConvertTo-Json -Depth 4
'''

# Static structural pins verified from Python (text-level).
STATIC_PINS = [
    ("restart-confirmation switch declared", "[switch]$ConfirmPostInstallRestart"),
    ("mandatory restart precondition banner present",
     "MANDATORY POST-INSTALL RESTART PRECONDITION"),
    ("interactive YES/NO confirmation prompt present", "Type YES or NO"),
    ("startup-preflight evidence artifact written", "startup-preflight.json"),
    ("precondition failure records collection skipped",
     "FullEvidenceCollectionStarted = $false"),
    ("successful run records collection started",
     "FullEvidenceCollectionStarted = $true"),
]


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def main() -> int:
    passed = failed = 0

    print("=" * 72)
    print("T48 Collector semantics contract")
    print("=" * 72)

    text = COLLECTOR_PATH.read_text(encoding="utf-8-sig")

    for name, needle in STATIC_PINS:
        passed, failed = check(name, needle in text,
                               f"marker missing: {needle}", passed, failed)

    i_pre = text.find("$startupDecision = Resolve-StartupPreflightDecision")
    i_sb = text.find("$secureBoot = Get-SecureBootEvidence")
    passed, failed = check(
        "preflight decision precedes Secure Boot collection",
        i_pre >= 0 and i_sb > i_pre,
        f"indexes: preflight={i_pre} secureboot={i_sb}", passed, failed)

    for fn in FUNCTIONS_UNDER_TEST:
        n = len(re.findall(r"(?m)^\s*function\s+" + re.escape(fn) + r"\b", text))
        passed, failed = check(
            f"semantics function defined exactly once: {fn}",
            n == 1, f"definition count = {n}", passed, failed)

    pwsh = shutil.which("pwsh")
    if pwsh is None:
        passed, failed = check("behavioral driver", False,
                               "pwsh not on PATH (required, as for T40)",
                               passed, failed)
    else:
        with tempfile.TemporaryDirectory() as td:
            driver = pathlib.Path(td) / "t48_driver.ps1"
            names = ",".join(f"'{n}'" for n in FUNCTIONS_UNDER_TEST)
            driver.write_text(DRIVER.replace("__FUNCTION_NAMES__", names),
                              encoding="utf-8")
            proc = subprocess.run(
                [pwsh, "-NoProfile", "-File", str(driver),
                 "-CollectorPath", str(COLLECTOR_PATH)],
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
