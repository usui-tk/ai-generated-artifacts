#!/usr/bin/env python3
"""T36: P08 plan-scope + WinRE has-work contract (offline).

Pins the r11.56 `p08-plan-scope` fixes for the 2026-07-07 Server 2019
E2E failure ("Cannot index into a null array" at the inline WinRE
Where-Object): on the BootWimLcuPolicy=disabled path, the r11.54
restructure had captured `$plan = Get-OrInitPatchPlan` inside the
non-disabled branch, so the WinRE section dereferenced an undefined
$plan; wrapping it produced @($null) and the Where-Object scriptblock
indexed into $null.PSObject.

Assertions:
  1. REPL: `Test-WimSequenceHasWork` (pure, null-hardened) --
     $null sequence -> False; @($null) -> False (the exact crash
     shape); cleanup-marker-only -> False; empty-Patches -> False;
     one real patch -> True; patch after a $null slot -> True.
  2. Structure: inside Invoke-BuildPhase08_PatchBootWim, the single
     `$plan = Get-OrInitPatchPlan` assignment occurs BEFORE the
     `if ($bootPolicy -eq 'disabled')` branch (shared by boot loop and
     WinRE section); the WinRE section calls Test-WimSequenceHasWork
     and no longer hosts the inline crash-prone Where-Object; the
     has-work decision precedes the install.wim mount.

Exit code 0 on full pass, 1 on any failure.
"""
from __future__ import annotations

import pathlib
import re
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"

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

    print("=== 1. Test-WimSequenceHasWork (REPL) ===")
    cleanup = {"Name": "W4.Cleanup", "IsCleanupMarker": True, "Patches": []}
    real = {"Name": "W1.SSU", "Patches": [{"KbId": "KB5094141"}]}
    empty = {"Name": "W3.SafeOsDU", "Patches": []}
    cases = [
        ("null sequence", None, False),
        ("@($null) element (the 2019 crash shape)", [None], False),
        ("cleanup marker only", [cleanup], False),
        ("empty-Patches sub-phases", [empty, cleanup], False),
        ("one real patch", [real, cleanup], True),
        ("real patch after a $null slot", [None, real], True),
    ]
    with PSSession(SCRIPT_PATH) as ps:
        for label, seq, expect in cases:
            got = ps.invoke("Test-WimSequenceHasWork", Sequence=seq)
            passed, failed = check(
                label, bool(got) == expect,
                f"got={got!r} expected={expect}", passed, failed)

    print("=== 2. P08 structure pins ===")
    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")
    m = re.search(
        r"function Invoke-BuildPhase08_PatchBootWim \{(.*?)\r?\nfunction ",
        text, re.S)
    body = m.group(1) if m else ""
    passed, failed = check(
        "P08 body extracted", bool(body), f"len={len(body)}", passed, failed)

    plan_pos = body.find("$plan = Get-OrInitPatchPlan")
    branch_pos = body.find("if ($bootPolicy -eq 'disabled')")
    passed, failed = check(
        "single $plan assignment, hoisted above the policy branch",
        body.count("$plan = Get-OrInitPatchPlan") == 1
        and 0 <= plan_pos < branch_pos,
        f"count={body.count('$plan = Get-OrInitPatchPlan')} "
        f"plan@{plan_pos} branch@{branch_pos}", passed, failed)

    haswork_pos = body.find("Test-WimSequenceHasWork -Sequence $winReSequence")
    mount_pos = body.find("Invoke-WimMountSafe -ImagePath $installWim")
    passed, failed = check(
        "WinRE has-work decision precedes the install.wim mount",
        0 <= haswork_pos < mount_pos,
        f"haswork@{haswork_pos} mount@{mount_pos}", passed, failed)

    passed, failed = check(
        "inline crash-prone Where-Object is gone from the WinRE section",
        "$winReHasWork = ($winReSequence | Where-Object" not in body,
        "inline pipeline absent", passed, failed)

    print()
    print(f"  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
