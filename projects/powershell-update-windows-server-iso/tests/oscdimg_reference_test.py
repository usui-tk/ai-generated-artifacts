#!/usr/bin/env python3
"""T49: oscdimg reference & qualification contract (offline).

First contract protecting the declared tool-reference file adopted at
r12.63 (`data/tool-references/oscdimg-reference.json`) and the oscdimg
resolution/qualification machinery around it.

Specification source: the r12.75 distribution's required suite, axes
R1263 / R1264 (input-only per the standing ruling; logic re-authored,
code not copied). Ledger: TEST-REIMPL-LEDGER.csv rows for those axes.
The real-environment-validated r12.75 code is the specification baseline
(code-anchored testing); the script and the declared file are untouched
and every expectation below is read from what they measurably declare.

Class: mixed.
  D-half — anchor `data/tool-references/oscdimg-reference.json`: the
  declared file's internal coherence and formats. Deliberately NOT
  asserted here: the declared VALUES themselves (ADK family, servicing
  KB, the concrete SHA-256s). The declared file is the value authority;
  duplicating its values into a test is the staleness hazard the
  declaration model exists to avoid (ledger row R1263/DROP). The one
  exact pin is the file's own SchemaVersion, advanced deliberately per
  release (T40/T47 style).
  B-half — AST/structure pins the declaration cannot express: the
  host-non-modification posture of the retired ADK auto-install path,
  the retirement of its runtime advisory messages, the
  qualification-required wiring of ISO assembly, the resolver/evidence
  schema identities, and the Microsoft-script reference parser's
  behavior (exercised on a self-authored synthetic fixture).

What this asserts:

  1. **Declared-file coherence (D).** SchemaVersion pinned exactly;
     ExpectedAdkFamily is version-shaped and ExpectedAdkServicingKb is
     KB-shaped (formats, not values); at least two AMD64 repository
     references, each with a 64-hex lowercase ExpectedSha256 and a
     Microsoft Symbol Server URL for oscdimg.exe; at least two
     qualified identities, each with a 64-hex digest.
  2. **Host non-modification (B, AST).** The legacy ADK fallback
     executes nothing (no Start-Process), references no installer URL
     variable anywhere in executable code, carries no adksetup.exe
     string constant, and states its non-modification behavior. The
     retired auto-install / hash-advisory runtime messages do not
     survive as string constants.
  3. **Qualification wiring (B).** New-BootableIso requires functional
     qualification and records the functional status and the resolver
     evidence path; P01 preserves machine-readable resolver-failure
     evidence with its schema; the resolution / functional-
     qualification / boot-assembly / repository-resolution / failure
     schema identities are declared; the three reference names and the
     qualification evidence keys are present; the script consumes the
     declared reference file by its path.
  4. **Reference parser behavior (B).** The Microsoft-script text
     parser extracts the symbol-store key, lowercases the expected
     hash, and captures the script version and date — verified on a
     synthetic fixture authored for this test.

Run:  python3 tests/oscdimg_reference_test.py
Deps: pwsh on PATH for the AST/behavior half (same class as T40/T48).
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
REFERENCE_PATH = SUBPROJECT_ROOT / "data" / "tool-references" / "oscdimg-reference.json"

# Exact schema pin for the declared file's current release; advance
# deliberately in a reviewed commit when the reference schema evolves.
EXPECTED_REFERENCE_SCHEMA = "oscdimg-reference/1.0"

OSCDIMG_FUNCTIONS = [
    "Get-OscdimgReferenceConfiguration",
    "Get-OscdimgPeEvidence",
    "Get-OscdimgAuthenticodeEvidence",
    "Get-OscdimgAdkRegistrationEvidence",
    "Resolve-OscdimgRepositoryReferences",
    "Get-OscdimgManagedRepositoryCandidates",
    "Get-OscdimgCandidateEvidence",
    "Invoke-OscdimgFunctionalQualification",
    "Get-OscdimgReferenceFromMicrosoftScriptText",
    "Get-OscdimgLocalCandidatePaths",
]

SCHEMA_IDS = [
    "oscdimg-resolution/2.0",
    "oscdimg-functional-qualification/1.0",
    "iso-boot-assembly/1.1",
    "secureboot-objects-oscdimg-resolution/1.1",
    "oscdimg-resolution-failure/1.0",
]

STATIC_MARKERS = [
    ("resolver-failure evidence artifact", "oscdimg-resolution-failure.json"),
    ("reference name: bundled main", "LatestMainForMake2023BootableMedia"),
    ("reference name: GitHub release", "LatestGitHubRelease"),
    ("reference name: Symbol Server", "MicrosoftPublicSymbolServer"),
    ("qualification key: patch registration", "ExpectedPatchRegistrationDetected"),
    ("qualification key: repository hash match", "RepositoryReferenceHashMatch"),
    ("qualification key: repeat-ISO identity", "RepeatIsoHashIdentical"),
    ("legacy wrapper states non-modification", "no longer modifies the host"),
    ("declared reference file consumed by path", "oscdimg-reference.json"),
    ("declared reference directory referenced", "tool-references"),
]

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SYMBOL_URL_PREFIX = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/"

DRIVER = r'''
param([Parameter(Mandatory)][string]$ScriptPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
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
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) { throw 'script parse errors' }
function Get-FunctionAstOnce([string]$Name) {
    $d=@($ast.FindAll({param($x)$x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $Name},$true))
    if ($d.Count -ne 1) { throw "function $Name definition count $($d.Count)" }
    return $d[0]
}

Run-Check 'legacy ADK fallback executes nothing (no Start-Process)' {
    $f=Get-FunctionAstOnce 'Install-WindowsAdkFallback'
    $n=@($f.FindAll({param($x)$x -is [System.Management.Automation.Language.CommandAst] -and $x.GetCommandName() -ieq 'Start-Process'},$true)).Count
    Expect-Eq $n 0 'Start-Process call sites'
}
Run-Check 'no installer-URL variable in executable code (whole script)' {
    $n=@($ast.FindAll({param($x)$x -is [System.Management.Automation.Language.VariableExpressionAst] -and $x.VariablePath.UserPath -ieq 'Script:AdkInstallerUrl'},$true)).Count
    Expect-Eq $n 0 'Script:AdkInstallerUrl references'
}
Run-Check 'no adksetup.exe string constant in the legacy fallback' {
    $f=Get-FunctionAstOnce 'Install-WindowsAdkFallback'
    $n=@($f.FindAll({param($x)$x -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $x.Value -match '(?i)adksetup\.exe'},$true)).Count
    Expect-Eq $n 0 'adksetup.exe string constants'
}
Run-Check 'retired advisory messages absent from runtime string constants' {
    $strings=@($ast.FindAll({param($x)$x -is [System.Management.Automation.Language.StringConstantExpressionAst]},$true))
    foreach ($forbidden in @(
        'auto-installing the Windows ADK Deployment Tools',
        'oscdimg.exe SHA-256 differs from the Microsoft reference value')) {
        $n=@($strings | Where-Object { $_.Value.Contains($forbidden) }).Count
        Expect-Eq $n 0 "forbidden message present: $forbidden"
    }
}
Run-Check 'New-BootableIso requires functional qualification and records evidence' {
    $t=(Get-FunctionAstOnce 'New-BootableIso').Extent.Text
    Expect ($t.Contains('-RequireFunctionalQualification')) 'qualification not required'
    Expect ($t.Contains('OscdimgFunctionalStatus')) 'functional status not recorded'
    Expect ($t.Contains('OscdimgResolutionEvidencePath')) 'resolver evidence path not recorded'
}
Run-Check 'P01 preserves resolver-failure evidence with its schema' {
    $t=(Get-FunctionAstOnce 'Invoke-SetupPhase01_Initialize').Extent.Text
    Expect ($t.Contains('oscdimg-resolution-failure.json')) 'failure artifact not preserved'
    Expect ($t.Contains("SchemaVersion = 'oscdimg-resolution-failure/1.0'")) 'failure schema missing'
}
Run-Check 'Microsoft-script reference parser extracts key, hash, version, date' {
    $f=Get-FunctionAstOnce 'Get-OscdimgReferenceFromMicrosoftScriptText'
    Invoke-Expression $f.Extent.Text
    # Synthetic fixture authored for this contract (values are arbitrary;
    # only the FORMAT mirrors the Microsoft script this parser targets).
    $fixture=@'
Version : 9.9
Date    : 2026-01-02
function Download-Oscdimg {
 $archUrls = @{
  "AMD64" = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/0AB1C2D3E4F5000/oscdimg.exe"
 }
}
$global:oscdimg_known_hashes = @{
 "AMD64" = "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"
}
'@
    $p=Get-OscdimgReferenceFromMicrosoftScriptText -Text $fixture -ReferenceName t49 -RepositoryRef t49
    Expect-Eq $p.SymbolStoreKey '0AB1C2D3E4F5000' 'symbol-store key'
    Expect-Eq $p.ExpectedSha256 '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' 'hash not lowercased'
    Expect-Eq $p.ScriptVersion '9.9' 'script version'
    Expect-Eq $p.ScriptDate '2026-01-02' 'script date'
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
    print("T49 oscdimg reference & qualification contract")
    print("=" * 72)

    # ---- D-half: declared-file coherence -----------------------------------
    passed, failed = check(
        "declared reference file present", REFERENCE_PATH.is_file(),
        f"missing: {REFERENCE_PATH}", passed, failed)
    if REFERENCE_PATH.is_file():
        ref = json.loads(REFERENCE_PATH.read_text(encoding="utf-8-sig"))
        passed, failed = check(
            f"reference SchemaVersion pinned exactly '{EXPECTED_REFERENCE_SCHEMA}'",
            ref.get("SchemaVersion") == EXPECTED_REFERENCE_SCHEMA,
            f"measured: {ref.get('SchemaVersion')!r}", passed, failed)
        fam = str(ref.get("ExpectedAdkFamily", ""))
        passed, failed = check(
            "ExpectedAdkFamily is version-shaped (value not duplicated here)",
            re.fullmatch(r"\d+\.\d+\.\d+\.\d+", fam) is not None,
            f"measured: {fam!r}", passed, failed)
        kb = str(ref.get("ExpectedAdkServicingKb", ""))
        passed, failed = check(
            "ExpectedAdkServicingKb is KB-shaped (value not duplicated here)",
            re.fullmatch(r"KB\d+", kb) is not None,
            f"measured: {kb!r}", passed, failed)
        amd64 = [r for r in ref.get("RepositoryReferences", [])
                 if r.get("Architecture") == "AMD64"]
        passed, failed = check(
            "at least two AMD64 repository references",
            len(amd64) >= 2, f"measured: {len(amd64)}", passed, failed)
        for i, r in enumerate(amd64):
            sha = str(r.get("ExpectedSha256", ""))
            url = str(r.get("SymbolUrl", ""))
            passed, failed = check(
                f"repository reference #{i + 1} ExpectedSha256 is 64-hex lowercase",
                SHA256_RE.fullmatch(sha) is not None,
                f"measured: {sha!r}", passed, failed)
            passed, failed = check(
                f"repository reference #{i + 1} SymbolUrl targets the Symbol Server",
                url.startswith(SYMBOL_URL_PREFIX),
                f"measured: {url!r}", passed, failed)
        quals = ref.get("QualifiedIdentities", [])
        passed, failed = check(
            "at least two qualified identities",
            len(quals) >= 2, f"measured: {len(quals)}", passed, failed)
        for i, q in enumerate(quals):
            sha = str(q.get("Sha256", ""))
            passed, failed = check(
                f"qualified identity #{i + 1} Sha256 is 64-hex lowercase",
                SHA256_RE.fullmatch(sha) is not None,
                f"measured: {sha!r}", passed, failed)

    # ---- B-half statics: script text ---------------------------------------
    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")
    for fn in OSCDIMG_FUNCTIONS:
        n = len(re.findall(r"(?m)^\s*function\s+" + re.escape(fn) + r"\b", text))
        passed, failed = check(
            f"oscdimg function defined exactly once: {fn}",
            n == 1, f"definition count = {n}", passed, failed)
    for sid in SCHEMA_IDS:
        passed, failed = check(
            f"schema identity declared: {sid}",
            sid in text, "schema id missing", passed, failed)
    for name, needle in STATIC_MARKERS:
        passed, failed = check(name, needle in text,
                               f"marker missing: {needle}", passed, failed)

    # ---- B-half AST/behavior: pwsh driver ----------------------------------
    pwsh = shutil.which("pwsh")
    if pwsh is None:
        passed, failed = check("AST/behavior driver", False,
                               "pwsh not on PATH (required, as for T40)",
                               passed, failed)
    else:
        with tempfile.TemporaryDirectory() as td:
            driver = pathlib.Path(td) / "t49_driver.ps1"
            driver.write_text(DRIVER, encoding="utf-8")
            proc = subprocess.run(
                [pwsh, "-NoProfile", "-File", str(driver),
                 "-ScriptPath", str(SCRIPT_PATH)],
                capture_output=True, text=True, timeout=300)
        if proc.returncode != 0:
            passed, failed = check(
                "AST/behavior driver", False,
                f"rc={proc.returncode} stderr={proc.stderr.strip()[:300]!r}",
                passed, failed)
        else:
            try:
                rows = json.loads(proc.stdout)
            except json.JSONDecodeError:
                rows = None
            if rows is None:
                passed, failed = check(
                    "AST/behavior driver", False,
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
