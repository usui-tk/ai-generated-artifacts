#!/usr/bin/env python3
"""T37: per-OS LCU evidence engine contract (offline, REPL).

Pins the r11.58 `per-os-evidence` engine that replaced the
KB-name-only Get-LcuVersionFromInstallWim (structurally blind on every
RollupFix-named OS: the 2026-07-07 E2E produced false '(none)'
verdicts on 2019/2022/2025 media whose LCU had applied status=Ok,
mis-skipping P10 and mis-failing P12).

Assertions (all via PSSession REPL; package-name path -- the
registry/kernel acquisition is host-only and covered by E2E):
  1. ConvertTo-TwoPartBuild: 4-part -> 2-part; null/garbage -> null.
  2. Resolve-LcuEvidence_Server2016: KB-named package yields KbId AND
     build; floor 14393.6897 boundary (.6897 True / .6896 False).
  3. Resolve-LcuEvidence_Server2019: RollupFix~~17763.* yields build,
     KbId null; floor 17763.5696 boundary.
  4. Resolve-LcuEvidence_Server2022: the EXACT 2026-07 E2E package
     name (20348.5256.1.13) -> build 20348.5256, prereq True; a
     below-floor 20348.2401 -> False. Foreign-OS names ignored.
  5. Resolve-LcuEvidence_Server2025: multiple RollupFix packages
     (checkpoint model) -> highest build wins; any 26100 meets prereq.
  6. Consensus: registry+package agreement -> BuildSourcesAgree True,
     registry preferred; disagreement -> False; single source -> False
     (agreement needs >= 2 sources).
  7. Dispatcher: unknown OsKey throws.

Exit code 0 on full pass, 1 on any failure.
"""
from __future__ import annotations

import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"


def vstr(v):
    """[version] serializes over the REPL as {Major, Minor, ...}."""
    if isinstance(v, dict) and "Major" in v:
        return f"{v['Major']}.{v['Minor']}"
    return None if v is None else str(v)

WSUS = "31bf3856ad364e35"


def check(label, ok, detail, p, f):
    if ok:
        print(f"{PASS}  {label}: {detail}")
        return p + 1, f
    print(f"{FAIL}  {label}: {detail}")
    return p, f + 1


def main() -> int:
    p = 0
    f = 0
    with PSSession(SCRIPT_PATH) as ps:
        print("=== 1. ConvertTo-TwoPartBuild ===")
        got = ps.invoke("ConvertTo-TwoPartBuild", BuildString="20348.5256.1.13")
        p, f = check("4-part collapses to 2-part", vstr(got) == "20348.5256", f"got={got!r}", p, f)
        got = ps.invoke("ConvertTo-TwoPartBuild", BuildString=None)
        p, f = check("null in -> null out", got is None, f"got={got!r}", p, f)
        got = ps.invoke("ConvertTo-TwoPartBuild", BuildString="garbage")
        p, f = check("garbage in -> null out", got is None, f"got={got!r}", p, f)

        print("=== 2. Server 2016 resolver (KB-named LCU) ===")
        names16 = [
            f"Package_for_KB5094141~{WSUS}~amd64~~14393.9234.1.8",
            f"Microsoft-Windows-Foundation-Package~{WSUS}~amd64~~10.0.14393.0",
        ]
        ev = ps.invoke("Resolve-LcuEvidence_Server2016", PackageNames=names16)
        p, f = check(
            "KbId + build extracted from package name",
            ev.get("LcuKbId") == "KB5094141" and vstr(ev.get("Build")) == "14393.9234"
            and ev.get("MeetsPca2023Prereq") is True,
            f"KbId={ev.get('LcuKbId')} Build={ev.get('Build')} prereq={ev.get('MeetsPca2023Prereq')}", p, f)
        ev = ps.invoke("Resolve-LcuEvidence_Server2016",
                       PackageNames=[f"Package_for_KB5036899~{WSUS}~amd64~~14393.6897.1.1"])
        p, f = check("floor boundary: 14393.6897 meets", ev.get("MeetsPca2023Prereq") is True,
                     f"prereq={ev.get('MeetsPca2023Prereq')}", p, f)
        ev = ps.invoke("Resolve-LcuEvidence_Server2016",
                       PackageNames=[f"Package_for_KB5094141~{WSUS}~amd64~~14393.9234.1.2",
                                     f"Package_for_KB5094122~{WSUS}~amd64~~14393.9234.1.8"])
        kbs = ev.get("KbIdsAtBuild") or []
        if isinstance(kbs, str):
            kbs = [kbs]
        p, f = check(
            "SSU + LCU at the SAME build (the 2026-07-08 E2E shape): BOTH KB ids carried",
            sorted(kbs) == ["KB5094122", "KB5094141"] and vstr(ev.get("Build")) == "14393.9234",
            f"KbIdsAtBuild={kbs!r}", p, f)
        ev = ps.invoke("Resolve-LcuEvidence_Server2016",
                       PackageNames=[f"Package_for_KB5035855~{WSUS}~amd64~~14393.6796.1.1"])
        p, f = check("floor boundary: 14393.6796 does NOT meet", ev.get("MeetsPca2023Prereq") is False,
                     f"prereq={ev.get('MeetsPca2023Prereq')}", p, f)

        print("=== 3. Server 2019 resolver (RollupFix; no KB id) ===")
        ev = ps.invoke("Resolve-LcuEvidence_Server2019",
                       PackageNames=[f"Package_for_RollupFix~{WSUS}~amd64~~17763.8880.1.5"])
        p, f = check(
            "build from RollupFix name; KbId is null",
            ev.get("LcuKbId") is None and vstr(ev.get("Build")) == "17763.8880"
            and ev.get("MeetsPca2023Prereq") is True,
            f"KbId={ev.get('LcuKbId')} Build={ev.get('Build')}", p, f)
        ev = ps.invoke("Resolve-LcuEvidence_Server2019",
                       PackageNames=[f"Package_for_RollupFix~{WSUS}~amd64~~17763.5576.1.1"])
        p, f = check("floor boundary: 17763.5576 does NOT meet", ev.get("MeetsPca2023Prereq") is False,
                     f"prereq={ev.get('MeetsPca2023Prereq')}", p, f)

        print("=== 4. Server 2022 resolver (the 2026-07 E2E shape) ===")
        names22 = [
            f"Package_for_RollupFix~{WSUS}~amd64~~20348.5256.1.13",
            f"Package_for_RollupFix~{WSUS}~amd64~~17763.8880.1.5",  # foreign OS: ignored
            f"Microsoft-Windows-ServerCore-Package~{WSUS}~amd64~~10.0.20348.587",
        ]
        ev = ps.invoke("Resolve-LcuEvidence_Server2022", PackageNames=names22)
        p, f = check(
            "20348.5256 detected; foreign-OS RollupFix ignored; prereq True",
            vstr(ev.get("Build")) == "20348.5256" and ev.get("MeetsPca2023Prereq") is True,
            f"Build={ev.get('Build')} prereq={ev.get('MeetsPca2023Prereq')}", p, f)
        ev = ps.invoke("Resolve-LcuEvidence_Server2022",
                       PackageNames=[f"Package_for_RollupFix~{WSUS}~amd64~~20348.2401.1.1"])
        p, f = check("floor boundary: 20348.2401 does NOT meet (floor .2402)",
                     ev.get("MeetsPca2023Prereq") is False,
                     f"prereq={ev.get('MeetsPca2023Prereq')}", p, f)
        ev = ps.invoke("Resolve-LcuEvidence_Server2022", PackageNames=[])
        p, f = check("no packages -> null build, prereq False",
                     ev.get("Build") is None and ev.get("MeetsPca2023Prereq") is False,
                     f"Build={ev.get('Build')} prereq={ev.get('MeetsPca2023Prereq')}", p, f)

        print("=== 5. Server 2025 resolver (checkpoint model) ===")
        names25 = [
            f"Package_for_RollupFix~{WSUS}~amd64~~26100.1742.1.10",
            f"Package_for_RollupFix~{WSUS}~amd64~~26100.4652.1.24",
            f"Package_for_RollupFix~{WSUS}~amd64~~26100.2314.1.4",
        ]
        ev = ps.invoke("Resolve-LcuEvidence_Server2025", PackageNames=names25)
        p, f = check(
            "highest of multiple RollupFix builds wins; 26100 meets prereq",
            vstr(ev.get("Build")) == "26100.4652" and ev.get("MeetsPca2023Prereq") is True,
            f"Build={ev.get('Build')} Notes={ev.get('Notes')!r}", p, f)

        print("=== 6. Source consensus ===")
        ev = ps.invoke("Resolve-LcuEvidence_Server2022",
                       PackageNames=[f"Package_for_RollupFix~{WSUS}~amd64~~20348.5256.1.13"],
                       RegistryBuild="20348.5256", KernelBuild="20348.5256")
        p, f = check("3-source agreement: agree True, registry preferred",
                     ev.get("BuildSourcesAgree") is True and vstr(ev.get("Build")) == "20348.5256",
                     f"agree={ev.get('BuildSourcesAgree')}", p, f)
        ev = ps.invoke("Resolve-LcuEvidence_Server2022",
                       PackageNames=[f"Package_for_RollupFix~{WSUS}~amd64~~20348.5256.1.13"],
                       RegistryBuild="20348.4529")
        p, f = check("registry/package disagreement: agree False, registry wins the Build slot",
                     ev.get("BuildSourcesAgree") is False and vstr(ev.get("Build")) == "20348.4529",
                     f"agree={ev.get('BuildSourcesAgree')} Build={ev.get('Build')}", p, f)
        ev = ps.invoke("Resolve-LcuEvidence_Server2022",
                       PackageNames=[f"Package_for_RollupFix~{WSUS}~amd64~~20348.5256.1.13"])
        p, f = check("single source: agree False (needs >= 2 sources)",
                     ev.get("BuildSourcesAgree") is False,
                     f"agree={ev.get('BuildSourcesAgree')}", p, f)

        print("=== 7. Dispatcher ===")
        try:
            ps.invoke("Get-ImageLcuEvidence", OsKey="Server2012R2", MountPath="C:\\nonexistent")
            p, f = check("unknown OsKey throws", False, "no exception raised", p, f)
        except Exception as exc:  # noqa: BLE001
            p, f = check("unknown OsKey throws", "unknown OsKey" in str(exc),
                         f"exc={str(exc)[:80]!r}", p, f)

    print()
    print(f"  Summary: {p} passed, {f} failed, {p + f} total")
    return 0 if f == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
