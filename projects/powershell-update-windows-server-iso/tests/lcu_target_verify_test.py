#!/usr/bin/env python3
"""T31: TargetBuildAfterUpdate derived-field contract + LCU-applied comparator.

Until r11.46 ``PatchBaseline.TargetBuildAfterUpdate`` (TBAU) was a SEED
field: hand-maintained, read by nothing at runtime, and stale on all four
OSes (the 2025 seed said ``26100.32522`` -- the May build -- against a
resolved June LCU of ``26100.32995``; audit F2). Its sibling dead fields
``VerificationMethod`` (written, never read) and ``ExcludeKbList``
(never read, and the 2025 entry mis-described the checkpoint SSU
KB5043080 as unnecessary while ``Lines[]`` applies it at ApplyOrder 1)
were retired in the same pass.

r11.46 makes TBAU DERIVED -- the refresh writeback sets it from the LCU
Line's Catalog-captured ``InScope.build`` -- and gives it a consumer: the
new pure comparator ``Test-LcuTargetApplied``, wired into P11
StaticVerify as a HARD Fail row (the applied LCU package IS the
build-attainment marker) [DECIDED 2026-07-02, user].

This test pins four layers:

1. **Comparator behavior** (TestHarness REPL): present / absent /
   case-insensitive matching over realistic ``Package_for_KB...`` names,
   empty package list, and the build annotation in ``Notes``.
2. **Data contract**: every committed ``data/config-Server*.json`` has
   ``TargetBuildAfterUpdate == <LCU Line>.InScope.build``, and neither
   config nor seed files carry the retired fields.
3. **Schema contract**: the seed schema's ``PatchBaselineSeed`` is down
   to ``Schema`` + ``ChecksumAlgorithm`` (with ``additionalProperties:
   false``, so a stale seed fails loudly), and the config schema no
   longer defines the retired fields.
4. **Static wiring**: the refresh derives TBAU from ``InScope.build``,
   P11 calls ``Test-LcuTargetApplied``, and no CODE line still touches
   ``VerificationMethod`` / ``ExcludeKbList``.

Run from the project root:

    python3 tests/lcu_target_verify_test.py
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
PROJECT_DIR = TESTS_DIR.parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SCRIPT_PATH = PROJECT_DIR / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"

PKGS_WITH_LCU = [
    "Microsoft-Windows-Foundation-Package~31bf3856ad364e35~amd64~~10.0.26100.1",
    "Package_for_ServicingStack_32900~31bf3856ad364e35~amd64~~26100.32900.1.0",
    "Package_for_KB5095960~31bf3856ad364e35~amd64~~26100.32995.1.13",
]
PKGS_WITHOUT_LCU = [
    "Microsoft-Windows-Foundation-Package~31bf3856ad364e35~amd64~~10.0.26100.1",
    "Package_for_KB5043080~31bf3856ad364e35~amd64~~26100.1.1.5",
]


def check(label: str, ok: bool, detail: str, p: int, f: int) -> tuple[int, int]:
    if ok:
        print(f"{PASS}  {label}: {detail}")
        return p + 1, f
    print(f"{FAIL}  {label}: {detail}")
    return p, f + 1


def main() -> int:
    passed = 0
    failed = 0

    # 1. comparator behavior
    with PSSession(SCRIPT_PATH) as ps:
        r = ps.invoke("Test-LcuTargetApplied", ExpectedKbId="KB5095960",
                      ExpectedBuild="26100.32995", PackageNames=PKGS_WITH_LCU)
        passed, failed = check(
            "LCU present -> Pass",
            r.get("Applied") is True and r.get("Status") == "Pass"
            and r.get("Actual") == "Present",
            f"Status={r.get('Status')!r} Actual={r.get('Actual')!r}",
            passed, failed)
        passed, failed = check(
            "build annotated in Notes",
            "26100.32995" in (r.get("Notes") or ""),
            f"Notes={r.get('Notes')!r}", passed, failed)

        r = ps.invoke("Test-LcuTargetApplied", ExpectedKbId="KB5095960",
                      ExpectedBuild="26100.32995", PackageNames=PKGS_WITHOUT_LCU)
        passed, failed = check(
            "LCU absent -> Fail",
            r.get("Applied") is False and r.get("Status") == "Fail"
            and r.get("Actual") == "Absent",
            f"Status={r.get('Status')!r} Actual={r.get('Actual')!r}",
            passed, failed)

        r = ps.invoke("Test-LcuTargetApplied", ExpectedKbId="kb5095960",
                      ExpectedBuild="", PackageNames=PKGS_WITH_LCU)
        passed, failed = check(
            "case-insensitive KB match; empty build annotated",
            r.get("Status") == "Pass"
            and "no TargetBuildAfterUpdate" in (r.get("Notes") or ""),
            f"Status={r.get('Status')!r} Notes={r.get('Notes')!r}",
            passed, failed)

        r = ps.invoke("Test-LcuTargetApplied", ExpectedKbId="KB5095960",
                      ExpectedBuild="26100.32995", PackageNames=[])
        passed, failed = check(
            "empty package list -> Fail",
            r.get("Status") == "Fail",
            f"Status={r.get('Status')!r}", passed, failed)

        # derivation helper: LCU with InScope.build -> that build; no LCU -> ''
        lines = [
            {"Kind": "SSU", "InScope": {"build": "26100.1"}},
            {"Kind": "LCU", "InScope": {"build": "26100.32995",
                                        "files": ["a.msu"]}},
        ]
        got = ps.invoke("Get-TargetBuildFromLines", Lines=lines)
        passed, failed = check(
            "Get-TargetBuildFromLines picks the LCU InScope.build",
            got == "26100.32995", f"got={got!r}", passed, failed)
        got = ps.invoke("Get-TargetBuildFromLines",
                        Lines=[{"Kind": "SafeOSDU", "InScope": None}])
        passed, failed = check(
            "Get-TargetBuildFromLines without an LCU -> empty",
            got in ("", None), f"got={got!r}", passed, failed)

    # 2. data contract over committed configs + seeds
    for cfg in sorted(PROJECT_DIR.glob("data/config-Server*.json")):
        d = json.loads(cfg.read_text(encoding="utf-8"))
        pb = d.get("PatchBaseline", {})
        lcu = [ln for ln in pb.get("Lines", [])
               if ln.get("Kind") == "LCU"
               and (ln.get("InScope") or {}).get("build")]
        if lcu:
            expected = lcu[0]["InScope"]["build"]
            passed, failed = check(
                f"{cfg.name} TBAU == LCU InScope.build",
                pb.get("TargetBuildAfterUpdate") == expected,
                f"TBAU={pb.get('TargetBuildAfterUpdate')!r} "
                f"InScope.build={expected!r}", passed, failed)
        passed, failed = check(
            f"{cfg.name} carries no retired fields",
            "VerificationMethod" not in pb and "ExcludeKbList" not in pb,
            f"keys={sorted(pb.keys())}", passed, failed)

    for seed in sorted(PROJECT_DIR.glob("data/seed/seed-Server*.json")):
        d = json.loads(seed.read_text(encoding="utf-8"))
        pbs = d.get("PatchBaseline", {})
        passed, failed = check(
            f"{seed.name} PatchBaseline is Schema+ChecksumAlgorithm only",
            sorted(pbs.keys()) == ["ChecksumAlgorithm", "Schema"],
            f"keys={sorted(pbs.keys())}", passed, failed)

    # 3. schema contract
    seed_schema = json.loads(
        (PROJECT_DIR / "schema" / "config-seed.schema.json")
        .read_text(encoding="utf-8"))
    pbs_def = seed_schema["definitions"]["PatchBaselineSeed"]
    passed, failed = check(
        "seed schema PatchBaselineSeed reduced + closed",
        sorted(pbs_def["properties"].keys()) == ["ChecksumAlgorithm", "Schema"]
        and pbs_def.get("additionalProperties") is False,
        f"props={sorted(pbs_def['properties'].keys())} "
        f"addProps={pbs_def.get('additionalProperties')}", passed, failed)

    config_schema = json.loads(
        (PROJECT_DIR / "schema" / "config.schema.json")
        .read_text(encoding="utf-8"))
    pb_def = config_schema["definitions"]["PatchBaseline"]
    passed, failed = check(
        "config schema keeps TBAU, drops retired fields",
        "TargetBuildAfterUpdate" in pb_def["properties"]
        and "VerificationMethod" not in pb_def["properties"]
        and "ExcludeKbList" not in pb_def["properties"],
        f"props={sorted(pb_def['properties'].keys())}", passed, failed)

    # 4. static wiring over CODE lines (comments may cite the old names)
    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")
    code_lines = [ln for ln in text.splitlines()
                  if not ln.lstrip().startswith("#")]
    code = "\n".join(code_lines)

    passed, failed = check(
        "BOTH Lines writers derive TBAU via Get-TargetBuildFromLines",
        re.search(r"\$tbau\s*=\s*Get-TargetBuildFromLines\s+-Lines\s+@\(\$newPatches\)",
                  code) is not None
        and re.search(
            r"\$raw\.PatchBaseline\.TargetBuildAfterUpdate\s*=\s*"
            r"Get-TargetBuildFromLines\s+-Lines\s+\$patches", code) is not None,
        "refresh writeback + A00/A01 chokepoint both wired "
        "(the first A00 run shipped an empty TBAU; this pins both writers)",
        passed, failed)

    passed, failed = check(
        "P11 calls Test-LcuTargetApplied",
        re.search(r"Test-LcuTargetApplied\s+-ExpectedKbId", code) is not None,
        "call site present", passed, failed)

    offenders = [ln.strip()[:90] for ln in code_lines
                 if "VerificationMethod" in ln or "ExcludeKbList" in ln]
    passed, failed = check(
        "no CODE line touches VerificationMethod / ExcludeKbList",
        offenders == [],
        "clean" if not offenders else f"found: {offenders!r}",
        passed, failed)

    print()
    print(f"  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
