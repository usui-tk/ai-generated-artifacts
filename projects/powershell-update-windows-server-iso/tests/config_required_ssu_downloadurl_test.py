"""
T23: required-SSU DownloadUrl static guard (offline, pure Python).

Catches the exact data defect behind the real-machine Server 2016 failure: a
servicing-stack update (Type 'SSU') listed in a config's NeutralPatches with an
empty DownloadUrl. Such an SSU can never be staged, so the LCU that depends on
it installs without its prerequisite and DISM fails on the host with
CBS_E_NEW_SERVICING_STACK_REQUIRED (0x800f0823).

This is a static contract check (no PowerShell, no network): it is the cheap
CI-side counterpart to the readiness gate exercised by T21/T22. T21/T22 prove
the gate would PREDICT the failure given correct inputs; T23 ensures the input
config itself never ships an unstageable required SSU in the first place.

Rule: every NeutralPatch whose Type is 'SSU' (case-insensitive) MUST carry a
non-empty DownloadUrl.

Coverage:
  * the bad-config fixture (one SSU with an empty URL) is flagged;
  * the same config with the URL filled is clean;
  * every committed data/config-Server*.json is clean (so populating one with an
    empty-URL SSU later will fail this guard in CI).

Invocation:
    python3 config_required_ssu_downloadurl_test.py
"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
SUBPROJECT_DIR = TEST_DIR.parent
DATA_DIR = SUBPROJECT_DIR / "data"
BAD_CONFIG = TEST_DIR / "fixtures" / "config-guard" / "bad-config-ssu-empty-url.json"


def find_required_ssu_without_downloadurl(config: dict) -> list[str]:
    """Return KbIds of NeutralPatches that are SSUs with an empty DownloadUrl.

    An SSU is a servicing-stack prerequisite; with no DownloadUrl it cannot be
    staged, which leads to a downstream 0x800f0823 on the target host.
    """
    violations: list[str] = []
    for patch in config.get("NeutralPatches") or []:
        ptype = (patch.get("Type") or "").strip().upper()
        url = (patch.get("DownloadUrl") or "").strip()
        if ptype == "SSU" and not url:
            violations.append(patch.get("KbId") or "<no KbId>")
    return violations


class TestResult:
    def __init__(self):
        self.passed = 0
        self.failed = []

    def assert_eq(self, name, actual, expected):
        if actual == expected:
            self.passed += 1
            print(f"  [PASS] {name}")
        else:
            self.failed.append((name, f"expected={expected!r} actual={actual!r}"))
            print(f"  [FAIL] {name}: expected={expected!r} actual={actual!r}")

    def assert_true(self, name, cond, detail=""):
        if cond:
            self.passed += 1
            print(f"  [PASS] {name}")
        else:
            self.failed.append((name, detail or "condition false"))
            print(f"  [FAIL] {name}: {detail or 'condition false'}")

    def summary(self):
        total = self.passed + len(self.failed)
        print()
        print(f"Summary: {self.passed} passed, {len(self.failed)} failed, {total} total")
        return 0 if not self.failed else 1


def main() -> int:
    print("T23: required-SSU DownloadUrl static guard")
    print()

    r = TestResult()

    # ---- the bad-config fixture is flagged -------------------------------
    r.assert_true("00 bad-config fixture present", BAD_CONFIG.exists())
    bad = json.loads(BAD_CONFIG.read_text(encoding="utf-8"))
    bad_violations = find_required_ssu_without_downloadurl(bad)
    r.assert_eq("01 bad-config flags exactly one SSU", len(bad_violations), 1)
    r.assert_true("02 bad-config flags KB5088064", "KB5088064" in bad_violations,
                  f"violations={bad_violations}")

    # ---- the same config with the URL filled is clean --------------------
    good = copy.deepcopy(bad)
    for patch in good["NeutralPatches"]:
        if (patch.get("Type") or "").upper() == "SSU":
            patch["DownloadUrl"] = "http://example.invalid/fixture/windows10.0-kb5088064-x64.cab"
    r.assert_eq("03 filled-URL config is clean", find_required_ssu_without_downloadurl(good), [])

    # whitespace-only URL is treated as empty
    ws = copy.deepcopy(bad)
    for patch in ws["NeutralPatches"]:
        if (patch.get("Type") or "").upper() == "SSU":
            patch["DownloadUrl"] = "   "
    r.assert_eq("04 whitespace-only URL still flagged", len(find_required_ssu_without_downloadurl(ws)), 1)

    # a non-SSU patch with an empty URL is NOT this guard's concern
    non_ssu = {"NeutralPatches": [{"Type": "LCU", "KbId": "KB5087537", "DownloadUrl": ""}]}
    r.assert_eq("05 empty URL on a non-SSU patch is not flagged",
                find_required_ssu_without_downloadurl(non_ssu), [])

    # ---- every committed config is clean ---------------------------------
    configs = sorted(DATA_DIR.glob("config-Server*.json"))
    r.assert_true("06 at least one committed config found", len(configs) > 0,
                  f"no config-Server*.json under {DATA_DIR}")
    for cfg_path in configs:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        v = find_required_ssu_without_downloadurl(cfg)
        r.assert_eq(f"07 {cfg_path.name} has no empty-URL SSU", v, [])

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
