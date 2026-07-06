#!/usr/bin/env python3
"""T32: Checkpoint placement + routing contract (offline, TestHarness REPL).

Pins the r11.52 `checkpoint-model` invariants that fixed the 2026-07-05
Server 2025 E2E failure (0x80073712: the GA checkpoint KB5043080, then
mislabelled Kind='SSU', was force-applied to a NEWER boot.wim):

  1. `Get-PatchLocalPath` lands Kind 'LCU' and 'Checkpoint' in the
     dedicated `cu` discovery subfolder (`patches\\<OS>\\cu\\`) and every
     other Kind in the flat per-OS folder. Rationale: Add-WindowsPackage
     is invoked with the TARGET cumulative update only and DISM uses the
     PackagePath FOLDER to discover prerequisite checkpoint MSUs;
     Microsoft requires that ONLY the target CU and its checkpoints be
     present in that folder (MS Learn 'Checkpoint cumulative updates and
     the Microsoft Update Catalog'; per-KB DISM guidance, e.g. the
     KB5094126 page).

  2. `Build-PatchPlan` routes a Kind='Checkpoint' entry to NO WIM target
     (it is never applied standalone) and does NOT report it as an
     unknown Type. The LCU keeps its Install+Boot routing.

  3. `Test-PatchModelConsistency` for 'uup-checkpoint' REQUIRES the
     Checkpoint Kind and FORBIDS the SSU Kind (the runtime mirror of the
     schema's discriminated union).

Exit code 0 on full pass, 1 on any failure (offline gate convention).
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


def check(label: str, ok: bool, detail: str, p: int, f: int) -> tuple[int, int]:
    if ok:
        print(f"{PASS}  {label}: {detail}")
        return p + 1, f
    print(f"{FAIL}  {label}: {detail}")
    return p, f + 1


def main() -> int:
    passed = 0
    failed = 0

    with PSSession(SCRIPT_PATH) as ps:
        # TestHarness runs OS-less; pin the script-scope OS token the
        # path helper composes with.
        ps.invoke("Set-Variable", Name="OsVersion", Scope="Script",
                  Value="Server2025")

        print("=== 1. Get-PatchLocalPath landing folders ===")
        cases = [
            ("LCU", "windows11.0-kb5094125-x64_test.msu", True),
            ("Checkpoint", "windows11.0-kb5043080-x64_test.msu", True),
            ("SSU", "windows10.0-kb5094141-x64_test.msu", False),
            ("DotNet", "windows11.0-kb5087051-x64-ndp481_test.msu", False),
            ("SafeOSDU", "windows11.0-kb5094150-x64_test.cab", False),
            ("SetupDU", "windows11.0-kb5095966-x64_test.cab", False),
        ]
        for kind, fname, in_cu in cases:
            got = ps.invoke("Get-PatchLocalPath", Kind=kind, FileName=fname)
            norm = str(got).replace("/", "\\")
            has_cu = "\\cu\\" in norm
            tail_ok = norm.endswith("\\" + fname) or norm.endswith("/" + fname) or norm.endswith(fname)
            passed, failed = check(
                f"{kind} lands {'in' if in_cu else 'outside'} cu\\",
                has_cu == in_cu and tail_ok,
                f"path={got}", passed, failed)

        print("=== 2. Build-PatchPlan routing ===")
        patches = [
            {"KbId": "KB5043080", "PatchType": "Checkpoint", "ApplyOrder": 1},
            {"KbId": "KB5094125", "PatchType": "LCU", "ApplyOrder": 2},
        ]
        plan = ps.invoke("Build-PatchPlan", Patches=patches)
        counts = plan.get("_TargetCounts") or {}
        passed, failed = check(
            "Checkpoint routed to no target",
            counts.get("Install") == 1 and counts.get("Boot") == 1
            and counts.get("WinRE") == 0 and counts.get("Setup") == 0,
            f"_TargetCounts={counts} (LCU-only in Install/Boot)", passed, failed)
        unknown = plan.get("_UnknownTypes") or []
        passed, failed = check(
            "Checkpoint is a KNOWN Type (no unknown-Type warning)",
            "Checkpoint" not in list(unknown),
            f"_UnknownTypes={unknown}", passed, failed)
        install_kbs = [p.get("KbId") for p in (plan.get("Install") or [])]
        passed, failed = check(
            "Install slice carries the LCU only",
            install_kbs == ["KB5094125"],
            f"Install={install_kbs}", passed, failed)

        print("=== 3. uup-checkpoint consistency rules ===")
        good_lines = [
            {"Kind": "Checkpoint", "KbId": "KB5043080", "Digest": "x"},
            {"Kind": "LCU", "KbId": "KB5094125", "Digest": "x"},
            {"Kind": "DotNet", "KbId": "KB5087051", "Digest": "x"},
            {"Kind": "SafeOSDU", "KbId": "KB5094150", "Digest": "x"},
            {"Kind": "SetupDU", "KbId": "KB5095966", "Digest": "x"},
        ]
        res = ps.invoke("Test-PatchModelConsistency", OsKey="Server2025",
                        PatchModel="uup-checkpoint", Lines=good_lines)
        passed, failed = check(
            "Checkpoint-shaped Lines are consistent",
            bool(res.get("IsConsistent")),
            f"Errors={res.get('Errors')}", passed, failed)

        ssu_lines = [dict(ln) for ln in good_lines]
        ssu_lines[0] = {"Kind": "SSU", "KbId": "KB5043080", "Digest": "x"}
        res = ps.invoke("Test-PatchModelConsistency", OsKey="Server2025",
                        PatchModel="uup-checkpoint", Lines=ssu_lines)
        errs = [str(e) for e in (res.get("Errors") or [])]
        passed, failed = check(
            "SSU Kind is forbidden AND Checkpoint required",
            (not res.get("IsConsistent"))
            and any("forbidden Kind 'SSU'" in e for e in errs)
            and any("missing required Kind 'Checkpoint'" in e for e in errs),
            f"Errors={errs}", passed, failed)

    print()
    print(f"  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
