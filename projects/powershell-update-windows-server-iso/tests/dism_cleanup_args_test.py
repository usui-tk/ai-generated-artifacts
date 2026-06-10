#!/usr/bin/env python3
"""T24 - Get-DismCleanupArgumentList argument-vector regression test.

Guards the operator-precedence trap that silently broke the offline
``dism.exe /Cleanup-Image`` pass. The cleanup vector used to be built as::

    @('/Image:' + $MountPath, '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase')

PowerShell binds the comma operator tighter than ``+``, so this parsed as
``'/Image:' + ($MountPath, '/Cleanup-Image', ...)`` -- the trailing array was
stringified (space-joined) into the ``/Image:`` value, collapsing the whole
vector into a SINGLE argument. dism.exe then received one malformed ``/Image:``
token with no servicing command and failed with exit code 1639 ("the
command-line is missing a required servicing command"). The DISM CLI logging
made the command look correct, because the build log joins the argument array
with spaces -- only ``dism.log`` (which quoted the entire string as one
argument) exposed the collapse.

The fix moved construction into the pure ``Get-DismCleanupArgumentList`` helper using
``"/Image:$MountPath"`` (interpolation, no ``+``). This test invokes that
helper through the PowerShell harness and asserts the vector stays at four
discrete tokens, the first targets the mount path, the servicing tokens follow
in order, and -- the bug signature -- no token contains an embedded space.

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


def main() -> int:
    mount = r"D:\UpdateWsi-Server2016\work\mount_install"
    expected = [
        f"/Image:{mount}",
        "/Cleanup-Image",
        "/StartComponentCleanup",
        "/ResetBase",
    ]

    with PSSession(SCRIPT_PATH) as ps:
        result = ps.invoke("Get-DismCleanupArgumentList", MountPath=mount)

    # The harness serialises a [string[]] as a JSON array; a hypothetical
    # single-token collapse would deserialise as a lone string instead.
    args = result if isinstance(result, list) else [result]

    passed = 0
    failed = 0

    # Test 1: discrete-token count (the collapse produced 1, the fix produces 4)
    if len(args) == 4:
        print(f"{PASS}  token count is 4 (vector did not collapse)")
        passed += 1
    else:
        print(f"{FAIL}  token count is {len(args)}, expected 4: {args!r}")
        failed += 1

    # Test 2: first token is exactly the /Image: target (nothing glued on)
    if args and args[0] == expected[0]:
        print(f"{PASS}  arg[0] is the clean /Image: target")
        passed += 1
    else:
        got = args[0] if args else "<none>"
        print(f"{FAIL}  arg[0] should be {expected[0]!r}, got {got!r}")
        failed += 1

    # Test 3: servicing tokens follow, in order
    if args[1:] == expected[1:]:
        print(f"{PASS}  servicing tokens follow in order")
        passed += 1
    else:
        print(f"{FAIL}  tail should be {expected[1:]!r}, got {args[1:]!r}")
        failed += 1

    # Test 4: bug signature - no token may contain an embedded space
    spaced = [a for a in args if " " in str(a)]
    if not spaced:
        print(f"{PASS}  no token contains an embedded space")
        passed += 1
    else:
        print(f"{FAIL}  token(s) contain embedded spaces (collapse signature): {spaced!r}")
        failed += 1

    print()
    print(f"  {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
