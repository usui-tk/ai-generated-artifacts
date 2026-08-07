#!/usr/bin/env python3
"""T35: PCA2023 default-auto parameter-surface contract (offline).

Pins the r11.55 `pca2023-default-auto` decision [DECIDED 2026-07-06]:
P10 ConvertPca2023BootManager runs BY DEFAULT (readiness-driven -- the
pre-flight snapshot's Critical/Healthy states still skip), because the
PCA2011 signing CA expired 2026-06 and a PCA2011-only boot manager is
now the exception, not the norm. The opt-in `-EnablePca2023BootManager`
is retired (destructive rename, no shim) in favour of the opt-out
`-SkipPca2023BootManager`. The Server 2025 gate is KEPT: conversion on
2025 still requires `-ForcePca2023OnServer2025` (certified 2025
platforms carry the 2023 certs in firmware).

Assertions:
  1. Script text: the retired token is gone; the param block declares
     `$SkipPca2023BootManager` and keeps `$ForcePca2023OnServer2025`;
     the P10 gate reads `$Script:SkipPca2023BootManager`; the Server
     2025 gate expression survives verbatim.
  2. REPL: `$Script:SkipPca2023BootManager` exists and defaults to
     False (P10 default-on); the retired script-scope variable is gone.

Exit code 0 on full pass, 1 on any failure.
"""
from __future__ import annotations

import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession, PSHarnessError  # type: ignore  # noqa: E402

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
    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")

    print("=== 1. Script-text surface ===")
    passed, failed = check(
        "retired token 'EnablePca2023BootManager' is gone",
        "EnablePca2023BootManager" not in text,
        f"occurrences={text.count('EnablePca2023BootManager')}", passed, failed)
    passed, failed = check(
        "param block declares $SkipPca2023BootManager",
        "[switch]   $SkipPca2023BootManager," in text,
        "declared", passed, failed)
    passed, failed = check(
        "param block keeps $ForcePca2023OnServer2025",
        "[switch]   $ForcePca2023OnServer2025," in text,
        "declared", passed, failed)
    passed, failed = check(
        "P10 gate reads the opt-out switch",
        "if ($Script:SkipPca2023BootManager) {" in text,
        "gate present", passed, failed)
    # r12.57 T39 revision: the Server 2025 force-gate was removed BY DESIGN
    # (conversion is default-on for every OS under RequirePca2023). The
    # switch survives as a deprecated compatibility slot: promoted into a
    # Deprecated* script-scope variable whose only consumer is a caution.
    # Pins re-derived from the measured r12.57 surface and verified
    # unchanged at the r12.75 terminal frame.
    passed, failed = check(
        "force switch promoted into the Deprecated compatibility slot",
        "$Script:DeprecatedForcePca2023OnServer2025 = [bool]$ForcePca2023OnServer2025"
        in text,
        "promotion present", passed, failed)
    passed, failed = check(
        "deprecation caution is wired to the Deprecated slot",
        "if ($Script:DeprecatedForcePca2023OnServer2025) {" in text
        and "'-ForcePca2023OnServer2025 is deprecated" in text,
        "caution wired", passed, failed)
    passed, failed = check(
        "retired Server 2025 force-gate is gone (default-on has no gate)",
        "if ($osKey -eq 'Server2025' -and -not $Script:ForcePca2023OnServer2025) {"
        not in text,
        "old gate absent", passed, failed)

    print("=== 2. REPL script-scope defaults ===")
    with PSSession(SCRIPT_PATH) as ps:
        v = ps.invoke("Get-Variable", Name="SkipPca2023BootManager",
                      Scope="Script", ValueOnly=True)
        # The REPL may surface the value either as the promoted [bool]
        # or as the SwitchParameter shape ({'IsPresent': ...}) depending
        # on which script-scope slot Get-Variable resolves first; both
        # must be falsy for the default-on contract.
        falsy = (v is False) or (isinstance(v, dict) and v.get("IsPresent") is False)
        passed, failed = check(
            "$Script:SkipPca2023BootManager defaults to falsy (P10 default-on)",
            falsy, f"value={v!r}", passed, failed)
        try:
            ps.invoke("Get-Variable", Name="EnablePca2023BootManager",
                      Scope="Script", ValueOnly=True)
            passed, failed = check("retired script-scope variable is gone",
                                   False, "variable still exists", passed, failed)
        except PSHarnessError as exc:
            passed, failed = check(
                "retired script-scope variable is gone",
                "EnablePca2023BootManager" in str(exc),
                "Get-Variable raised (variable absent)", passed, failed)

    print()
    print(f"  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
