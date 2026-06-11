#!/usr/bin/env python3
"""T25 - Get-DismExportArgumentList argument-vector regression test.

The default Export-Image /Compress:max pass (Export-InstallWimCompressed)
recovers the install.wim size that the now-default-off /ResetBase used to
reclaim, without the per-index /ResetBase time cost. This test asserts the
pure argument builder produces five discrete tokens in order, targets the
requested source index, requests /Compress:max, and -- the precedence-collapse
signature this project has been bitten by -- contains no embedded spaces.

Runs anywhere (pure string construction; no DISM, no WIM).
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
    src = r"D:\UpdateWsi-Server2016\source\extracted\sources\install.wim"
    dst = r"D:\UpdateWsi-Server2016\source\extracted\sources\install.wim.optimized.wim"
    index = 3
    expected = [
        "/Export-Image",
        f"/SourceImageFile:{src}",
        f"/SourceIndex:{index}",
        f"/DestinationImageFile:{dst}",
        "/Compress:max",
    ]

    scratch = r"D:\UpdateWsi-Server2016\work\scratch"
    with PSSession(SCRIPT_PATH) as ps:
        args = as_list(ps.invoke(
            "Get-DismExportArgumentList",
            SourceWim=src, SourceIndex=index, DestinationWim=dst,
        ))
        scratch_args = as_list(ps.invoke(
            "Get-DismExportArgumentList",
            SourceWim=src, SourceIndex=index, DestinationWim=dst, ScratchDir=scratch,
        ))

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

    check("vector is exactly the five /Export-Image tokens in order",
          args == expected, repr(args))
    check("requests /Compress:max",
          "/Compress:max" in args, repr(args))
    check(f"targets the requested source index (/SourceIndex:{index})",
          f"/SourceIndex:{index}" in args, repr(args))
    check("-ScratchDir appends /ScratchDir:<path> as one token",
          f"/ScratchDir:{scratch}" in scratch_args, repr(scratch_args))
    check("/ScratchDir omitted when -ScratchDir not supplied",
          not any(str(a).startswith("/ScratchDir:") for a in args), repr(args))
    spaced = [a for a in (args + scratch_args) if " " in str(a)]
    check("no token contains an embedded space (collapse signature)",
          not spaced, repr(spaced))

    print()
    print(f"  {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
