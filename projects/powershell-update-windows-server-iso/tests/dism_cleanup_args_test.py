#!/usr/bin/env python3
"""T24 - Get-DismCleanupArgumentList argument-vector regression test.

Guards two things:

1. The operator-precedence trap that silently broke the offline
   ``dism.exe /Cleanup-Image`` pass. The vector used to be built as
   ``@('/Image:' + $MountPath, '/Cleanup-Image', ...)``; PowerShell binds the
   comma operator tighter than ``+``, so the trailing array was stringified
   (space-joined) into the ``/Image:`` value, collapsing the whole vector into
   a SINGLE argument and yielding dism.exe exit 1639. The fix builds the
   vector with ``"/Image:$MountPath"`` (interpolation, no ``+``).

2. The ``/ResetBase`` default. ``/ResetBase`` is very slow per index, so it is
   OFF by default (the cleanup is ``/Cleanup-Image /StartComponentCleanup``
   only) and is appended only when ``-IncludeResetBase`` is set.

Runs anywhere (pure string construction; no DISM, no mounted image).
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


def as_list(result):
    return result if isinstance(result, list) else [result]


def main() -> int:
    mount = r"D:\UpdateWsi-Server2016\work\mount_install"
    default_expected = [f"/Image:{mount}", "/Cleanup-Image", "/StartComponentCleanup"]
    reset_expected = default_expected + ["/ResetBase"]

    with PSSession(SCRIPT_PATH) as ps:
        default_args = as_list(ps.invoke("Get-DismCleanupArgumentList", MountPath=mount))
        reset_args = as_list(ps.invoke("Get-DismCleanupArgumentList", MountPath=mount, IncludeResetBase=True))

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

    # Default mode: /ResetBase OFF, three discrete tokens
    check("default vector is exactly /Cleanup-Image /StartComponentCleanup (no /ResetBase)",
          default_args == default_expected, repr(default_args))
    check("default vector has no /ResetBase token",
          "/ResetBase" not in default_args, repr(default_args))

    # Opt-in mode: -IncludeResetBase appends /ResetBase as the 4th token
    check("-IncludeResetBase appends /ResetBase as a fourth discrete token",
          reset_args == reset_expected, repr(reset_args))

    # Bug signature (both modes): no token may contain an embedded space
    spaced = [a for a in (default_args + reset_args) if " " in str(a)]
    check("no token contains an embedded space (collapse signature)",
          not spaced, repr(spaced))

    print()
    print(f"  {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
