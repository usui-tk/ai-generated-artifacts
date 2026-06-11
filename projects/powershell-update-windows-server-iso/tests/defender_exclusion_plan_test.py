#!/usr/bin/env python3
"""T26 - Windows Defender exclusion pure-helper tests (-UseDefenderExclusions).

Covers the three PURE helpers behind the opt-in Defender-exclusion feature
(r11.26); the Add-/Remove-MpPreference / Get-MpComputerStatus wrappers are
Windows-only and not exercised here (same boundary as the DISM cmdlet tests):

  * Get-DefenderManagedExclusionSet - the canonical managed set (WorkRoot path
    + the four servicing process names).
  * Get-DefenderExclusionPlan       - "add only what is absent" set difference,
    case-insensitive and trailing-slash-insensitive for paths.
  * Get-DefenderExclusionDecision   - fail-closed gate: apply ONLY when every
    prerequisite is positively satisfied; any unmet/unknown ($null) -> skip.

Runs anywhere (pure logic; no Defender, no Windows).
"""
from __future__ import annotations

import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SCRIPT_PATH = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def main() -> int:
    wr = r"D:\UpdateWsi-Server2016"
    procs = ["dism.exe", "DismHost.exe", "TiWorker.exe", "TrustedInstaller.exe"]

    with PSSession(SCRIPT_PATH) as ps:
        mset = ps.invoke("Get-DefenderManagedExclusionSet", WorkRoot=wr)

        plan_absent = ps.invoke(
            "Get-DefenderExclusionPlan",
            DesiredPaths=[wr], DesiredProcesses=procs,
        )
        plan_path_present = ps.invoke(
            "Get-DefenderExclusionPlan",
            DesiredPaths=[wr], DesiredProcesses=procs,
            ExistingPaths=[wr.lower() + "\\"], ExistingProcesses=[],
        )
        plan_proc_present = ps.invoke(
            "Get-DefenderExclusionPlan",
            DesiredPaths=[wr], DesiredProcesses=["dism.exe", "DismHost.exe"],
            ExistingPaths=[], ExistingProcesses=["DISM.EXE"],
        )

        dec_ok = ps.invoke(
            "Get-DefenderExclusionDecision",
            CommandsAvailable=True, ServiceRunning=True,
            RealTimeEnabled=True, TamperProtected=False, RunningMode="Normal",
        )
        # RealTime unknown: omit RealTimeEnabled -> $null
        dec_rt_unknown = ps.invoke(
            "Get-DefenderExclusionDecision",
            CommandsAvailable=True, ServiceRunning=True,
            TamperProtected=False, RunningMode="Normal",
        )
        dec_tamper_on = ps.invoke(
            "Get-DefenderExclusionDecision",
            CommandsAvailable=True, ServiceRunning=True,
            RealTimeEnabled=True, TamperProtected=True, RunningMode="Normal",
        )
        dec_passive = ps.invoke(
            "Get-DefenderExclusionDecision",
            CommandsAvailable=True, ServiceRunning=True,
            RealTimeEnabled=True, TamperProtected=False, RunningMode="Passive",
        )
        # Mode unknown: omit RunningMode -> $null
        dec_mode_unknown = ps.invoke(
            "Get-DefenderExclusionDecision",
            CommandsAvailable=True, ServiceRunning=True,
            RealTimeEnabled=True, TamperProtected=False,
        )
        dec_no_cmd = ps.invoke(
            "Get-DefenderExclusionDecision",
            CommandsAvailable=False, ServiceRunning=True,
            RealTimeEnabled=True, TamperProtected=False, RunningMode="Normal",
        )
        dec_no_svc = ps.invoke(
            "Get-DefenderExclusionDecision",
            CommandsAvailable=True, ServiceRunning=False,
            RealTimeEnabled=True, TamperProtected=False, RunningMode="Normal",
        )

    passed = 0
    failed = 0

    def check(label, cond, detail=""):
        nonlocal passed, failed
        if cond:
            print(f"{PASS}  {label}")
            passed += 1
        else:
            print(f"{FAIL}  {label}{(' -> ' + detail) if detail else ''}")
            failed += 1

    # --- managed set ---
    check("managed set: paths = [WorkRoot]",
          as_list(mset.get("Paths")) == [wr], repr(mset.get("Paths")))
    check("managed set: processes = the four servicing process names",
          as_list(mset.get("Processes")) == procs, repr(mset.get("Processes")))

    # --- plan: add only what is absent ---
    check("plan: nothing present -> add WorkRoot path",
          as_list(plan_absent.get("PathsToAdd")) == [wr], repr(plan_absent.get("PathsToAdd")))
    check("plan: nothing present -> add all four processes",
          as_list(plan_absent.get("ProcessesToAdd")) == procs, repr(plan_absent.get("ProcessesToAdd")))
    check("plan: path already present (case/slash-insensitive) -> not re-added",
          as_list(plan_path_present.get("PathsToAdd")) == [], repr(plan_path_present.get("PathsToAdd")))
    check("plan: process already present (case-insensitive) -> only the absent one added",
          as_list(plan_proc_present.get("ProcessesToAdd")) == ["DismHost.exe"],
          repr(plan_proc_present.get("ProcessesToAdd")))

    # --- decision: fail-closed ---
    check("decision: all prerequisites satisfied -> Apply", dec_ok.get("Apply") is True, repr(dec_ok))
    check("decision: real-time unknown ($null) -> skip", dec_rt_unknown.get("Apply") is False, repr(dec_rt_unknown))
    check("decision: Tamper Protection on -> skip", dec_tamper_on.get("Apply") is False, repr(dec_tamper_on))
    check("decision: AMRunningMode Passive -> skip", dec_passive.get("Apply") is False, repr(dec_passive))
    check("decision: AMRunningMode unknown ($null) -> skip", dec_mode_unknown.get("Apply") is False, repr(dec_mode_unknown))
    check("decision: commands unavailable -> skip", dec_no_cmd.get("Apply") is False, repr(dec_no_cmd))
    check("decision: WinDefend not running -> skip", dec_no_svc.get("Apply") is False, repr(dec_no_svc))

    print()
    print(f"  {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
