#!/usr/bin/env python3
"""T34: BootWimLcuPolicy contract (offline; committed data + TestHarness REPL).

Pins the r11.54 `bootwim-policy` model: the boolean
`Common.EnableBootWimUpdate` is retired (destructive rename, no shim)
in favour of the per-OS tri-state `Common.BootWimLcuPolicy`
(enabled | disabled | tolerate). The 2026-07-05 4-OS E2E proved
boot.wim LCU-serviceability is a property of each OS's committed
source media, not a global truth:

  2016 -> enabled   (WinPE 1607 accepts the LCU; PCA2023 staging set
                     EFI_EX/FONTS_EX/DVD_EX materialises, closing V3)
  2019 -> disabled  (EVAL media structurally closed: 0x80070032 at CBS
                     finalize; the 2026-06-12 D1 probe closed all
                     6 variants)
  2022 -> tolerate  (P07 axis-3 failure masked P08; serviceability
                     unmeasured -- attempt, downgrade to Caution,
                     dismount -Discard, continue)
  2025 -> enabled   (26100 WinPE; r11.52 checkpoint-model target-only
                     apply)

Assertions:
  1. Data matrix: every config + seed carries the expected policy and
     no `EnableBootWimUpdate` anywhere in Common.
  2. Schema: Common.BootWimLcuPolicy enum == {enabled,disabled,tolerate}
     in BOTH schemas (byte-equal Common is separately enforced by the
     seed contract gate); `EnableBootWimUpdate` is gone.
  3. REPL: `Resolve-BootWimLcuPolicyValue` passes through the three
     valid values (case-insensitively), defaults empty/missing to
     'disabled', and throws a typed error on unknown values.

Exit code 0 on full pass, 1 on any failure.
"""
from __future__ import annotations

import json
import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession, PSHarnessError  # type: ignore  # noqa: E402

SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"
DATA_DIR = SUBPROJECT_ROOT / "data"
SCHEMA_DIR = SUBPROJECT_ROOT / "schema"

EXPECTED_POLICY = {
    "2016": "enabled",
    "2019": "disabled",
    "2022": "tolerate",
    "2025": "enabled",
}

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

    print("=== 1. Committed data matrix ===")
    for os_key, expected in EXPECTED_POLICY.items():
        for path in (DATA_DIR / f"config-Server{os_key}.json",
                     DATA_DIR / "seed" / f"seed-Server{os_key}.json"):
            common = json.loads(path.read_text(encoding="utf-8")).get("Common") or {}
            passed, failed = check(
                f"{path.name} BootWimLcuPolicy",
                common.get("BootWimLcuPolicy") == expected
                and "EnableBootWimUpdate" not in common,
                f"policy={common.get('BootWimLcuPolicy')} "
                f"(expected {expected}; retired flag absent="
                f"{'EnableBootWimUpdate' not in common})", passed, failed)

    print("=== 2. Schema contract ===")
    for schema_name in ("config.schema.json", "config-seed.schema.json"):
        sch = json.loads((SCHEMA_DIR / schema_name).read_text(encoding="utf-8"))
        props = sch["definitions"]["Common"]["properties"]
        pol = props.get("BootWimLcuPolicy") or {}
        passed, failed = check(
            f"{schema_name} Common.BootWimLcuPolicy enum",
            sorted(pol.get("enum") or []) == ["disabled", "enabled", "tolerate"]
            and "EnableBootWimUpdate" not in props,
            f"enum={pol.get('enum')} retired-absent="
            f"{'EnableBootWimUpdate' not in props}", passed, failed)

    print("=== 3. Resolve-BootWimLcuPolicyValue (REPL) ===")
    with PSSession(SCRIPT_PATH) as ps:
        for raw, expect in (("enabled", "enabled"), ("disabled", "disabled"),
                            ("tolerate", "tolerate"), ("Tolerate", "tolerate"),
                            ("", "disabled")):
            got = ps.invoke("Resolve-BootWimLcuPolicyValue", RawValue=raw)
            passed, failed = check(
                f"RawValue={raw!r} -> {expect}", got == expect,
                f"got={got!r}", passed, failed)
        try:
            ps.invoke("Resolve-BootWimLcuPolicyValue", RawValue="yes")
            passed, failed = check("unknown value throws", False,
                                   "no error raised", passed, failed)
        except PSHarnessError as exc:
            passed, failed = check(
                "unknown value throws a typed error",
                "unknown value 'yes'" in str(exc),
                f"error={exc}", passed, failed)

    print()
    print(f"  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
