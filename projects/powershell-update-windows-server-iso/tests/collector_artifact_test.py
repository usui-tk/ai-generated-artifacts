#!/usr/bin/env python3
"""T47: Collector artifact & identity contract (offline).

The Collector (`Collect-WindowsServerPostInstallEvidence.ps1`) became this
project's second deliverable at r12.69 and had no repository-side
regression coverage. This contract is the first half of closing that gap
(the semantics half is T48).

Specification source: the r12.75 distribution's required regression suite,
axes R1269 / R1270 / R1275 (input-only per the standing ruling; logic
re-authored here, code not copied). Ledger: TEST-REIMPL-LEDGER.csv rows
R1269 (3 groups), R1270 static groups, R1275 exact-pin row. The
real-environment-validated r12.75 Collector is the specification baseline
(code-anchored testing): every expectation below is read from, and pinned
to, what the shipped artifact measurably declares.

Class: B (behaviour/structure pins). Justification: the Collector's
identity constants, parameter defaults and evidence-function inventory are
script-declared, not expressible through the project's config declaration
surfaces, so a D-contract has no anchor here.

What this asserts:

  1. **Deliverable identity.** The supported artifact exists at the
     project root and the retired project-context filename does not.
  2. **Exact version-pair pin.** `CollectorVersion` = 'r13' AND
     `SchemaVersion` = 'windows-server-post-install-evidence/1.10',
     pinned exactly (T40-style). The distribution's own suite used
     floor pins (">= r9" etc.); under this repository's governance the
     current pair is pinned and advanced deliberately at each Collector
     release, so an unreviewed identity drift fails closed.
  3. **Project-neutral evidence contract.** Error schema, artifact
     prefix, OS-tokenized artifact naming template; no project-context
     "E2E" terminology remains.
  4. **Retirement guards.** The pre-r9 cross-version baseline contract
     surfaces (ExpectedOsVersion, ReferencePackage, ReferenceSha256,
     MatchesReferenceSha256) stay absent, and cross-version baseline
     hash comparison stays explicitly disabled.
  5. **Collection posture.** ESP and MSInfo32 inspection default-on;
     the C:\\Temp output contract and the OutputRoot restriction are
     present; read-only ESP access goes through mountvol.
  6. **No network access.** The Collector performs no web requests --
     it is an offline evidence tool by design.
  7. **Parse gate.** The Collector parses cleanly under the PowerShell
     parser (extends the per-session battery, which previously parsed
     only the main script).

Run:  python3 tests/collector_artifact_test.py
Deps: pwsh on PATH for the parse gate (same dependency class as T40).
"""
from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
COLLECTOR_PATH = SUBPROJECT_ROOT / "Collect-WindowsServerPostInstallEvidence.ps1"
RETIRED_PATH = SUBPROJECT_ROOT / "Collect-WindowsServerE2EEvidence.ps1"

# Exact identity pair for the current Collector release. Advance BOTH
# values deliberately, in a reviewed commit, when a new Collector
# revision lands (T40-style release pin; supersedes the distribution
# suite's floor pins by governance decision, ledger rows R1270/R1275).
EXPECTED_COLLECTOR_VERSION = "r13"
EXPECTED_SCHEMA_VERSION = "windows-server-post-install-evidence/1.10"

# Evidence-function inventory (r9 minimum contract, retained at r12).
EVIDENCE_FUNCTIONS = [
    "Resolve-WindowsServerIdentity",
    "Get-WindowsFeatureEvidence",
    "Get-DotNetFrameworkEvidence",
    "Get-SecureBootVariableEvidence",
    "Get-SecureBootEventEvidence",
    "Get-SecureBootScheduledTaskEvidence",
    "Get-SecureBootScriptInventory",
    "Get-PostInstallAssessmentItems",
]

# Pre-r9 cross-version baseline surfaces that must remain retired.
RETIRED_TOKENS = [
    "ExpectedOsVersion",
    "ReferencePackage",
    "ReferenceSha256",
    "MatchesReferenceSha256",
]


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def function_definition_count(text: str, name: str) -> int:
    return len(re.findall(r"(?m)^\s*function\s+" + re.escape(name) + r"\b", text))


def parse_gate(passed, failed):
    pwsh = shutil.which("pwsh")
    if pwsh is None:
        return check("collector parse gate", False,
                     "pwsh not on PATH (required, as for T40)", passed, failed)
    ps = (
        "$t=$null;$e=$null;"
        "[void][System.Management.Automation.Language.Parser]::ParseFile("
        f"'{COLLECTOR_PATH}',[ref]$t,[ref]$e);"
        "Write-Output @($e).Count"
    )
    proc = subprocess.run([pwsh, "-NoProfile", "-Command", ps],
                          capture_output=True, text=True, timeout=120)
    ok = proc.returncode == 0 and proc.stdout.strip() == "0"
    return check("collector parse gate", ok,
                 f"rc={proc.returncode} errors={proc.stdout.strip()!r} "
                 f"stderr={proc.stderr.strip()[:200]!r}", passed, failed)


def main() -> int:
    passed = failed = 0

    print("=" * 72)
    print("T47 Collector artifact & identity contract")
    print("=" * 72)

    # 1. Deliverable identity ------------------------------------------------
    passed, failed = check(
        "supported artifact present at project root",
        COLLECTOR_PATH.is_file(),
        f"missing: {COLLECTOR_PATH}", passed, failed)
    passed, failed = check(
        "retired project-context filename absent",
        not RETIRED_PATH.exists(),
        f"retired file present: {RETIRED_PATH}", passed, failed)
    if not COLLECTOR_PATH.is_file():
        print(f"\n  Summary: {passed} passed, {failed} failed, "
              f"{passed + failed} total")
        return 1

    text = COLLECTOR_PATH.read_text(encoding="utf-8-sig")

    # 2. Exact version-pair pin ---------------------------------------------
    m_ver = re.search(
        r"\$script:CollectorVersion\s*=\s*'(?P<v>[^']+)'", text)
    m_sch = re.search(
        r"\$script:SchemaVersion\s*=\s*'(?P<v>[^']+)'", text)
    passed, failed = check(
        f"CollectorVersion pinned exactly '{EXPECTED_COLLECTOR_VERSION}'",
        m_ver is not None and m_ver.group("v") == EXPECTED_COLLECTOR_VERSION,
        f"measured: {m_ver.group('v') if m_ver else '<absent>'}",
        passed, failed)
    passed, failed = check(
        f"SchemaVersion pinned exactly '{EXPECTED_SCHEMA_VERSION}'",
        m_sch is not None and m_sch.group("v") == EXPECTED_SCHEMA_VERSION,
        f"measured: {m_sch.group('v') if m_sch else '<absent>'}",
        passed, failed)

    # 3. Project-neutral evidence contract ----------------------------------
    passed, failed = check(
        "error schema declared",
        "windows-server-post-install-evidence-error/1.0" in text,
        "error schema id missing", passed, failed)
    passed, failed = check(
        "artifact output prefix declared",
        "windows-server-post-install-evidence-" in text,
        "artifact prefix missing", passed, failed)
    passed, failed = check(
        "OS-tokenized artifact naming template present",
        "windows-server-post-install-evidence-{0}-{1}-{2}" in text,
        "naming template missing", passed, failed)
    passed, failed = check(
        "usage example uses the supported filename",
        ".\\Collect-WindowsServerPostInstallEvidence.ps1" in text,
        "supported-filename example missing", passed, failed)
    passed, failed = check(
        "no project-context E2E terminology",
        re.search(r"(?i)\be2e\b", text) is None,
        "E2E terminology found", passed, failed)

    # 4. Retirement guards ---------------------------------------------------
    for token in RETIRED_TOKENS:
        passed, failed = check(
            f"retired surface absent: {token}",
            token not in text,
            f"retired token present: {token}", passed, failed)
    passed, failed = check(
        "cross-version baseline hash comparison explicitly disabled",
        "BaselineHashComparisonEnabled = $false" in text,
        "explicit-disable marker missing", passed, failed)

    # 5. Collection posture --------------------------------------------------
    passed, failed = check(
        "ESP inspection enabled by default (Skip-form opt-out)",
        "[switch]$SkipEspInspection," in text
        and "[switch]$InspectEsp" not in text,
        "SkipEspInspection opt-out switch missing or legacy default-on"
        " switch still present", passed, failed)
    passed, failed = check(
        "MSInfo32 enabled by default (Skip-form opt-out)",
        "[switch]$SkipMsInfo32," in text
        and "[switch]$IncludeMsInfo32" not in text,
        "SkipMsInfo32 opt-out switch missing or legacy default-on"
        " switch still present", passed, failed)
    passed, failed = check(
        "C:\\Temp output contract present",
        "Get-NormalizedDirectoryPath -Path 'C:\\Temp'" in text,
        "C:\\Temp contract missing", passed, failed)
    passed, failed = check(
        "OutputRoot restriction stated",
        "OutputRoot must be either the script directory" in text,
        "OutputRoot restriction missing", passed, failed)
    passed, failed = check(
        "read-only ESP access via mountvol",
        "mountvol.exe" in text,
        "mountvol support missing", passed, failed)
    for fn in EVIDENCE_FUNCTIONS:
        n = function_definition_count(text, fn)
        passed, failed = check(
            f"evidence function defined exactly once: {fn}",
            n == 1, f"definition count = {n}", passed, failed)

    # 6. No network access ---------------------------------------------------
    passed, failed = check(
        "no network access surfaces",
        re.search(r"(?i)Invoke-WebRequest|Invoke-RestMethod|"
                  r"System\.Net\.WebClient", text) is None,
        "network access surface found", passed, failed)

    # 7. Parse gate ----------------------------------------------------------
    passed, failed = parse_gate(passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, "
          f"{passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
