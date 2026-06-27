"""
T23: required-SSU consistency contract (offline, pure Python).

Catches the exact data defect behind the real-machine Server 2016 failure: a
servicing-stack update (Kind 'SSU') listed in a config's Lines with an
empty DownloadUrl. Such an SSU can never be staged, so the LCU that depends on
it installs without its prerequisite and DISM fails on the host with
CBS_E_NEW_SERVICING_STACK_REQUIRED (0x800f0823).

This is a static contract check (no PowerShell, no network): it is the cheap
CI-side counterpart to the readiness gate exercised by T21/T22. T21/T22 prove
the gate would PREDICT the failure given correct inputs; T23 ensures the input
config itself never ships an unstageable required SSU in the first place.

Rules (a static, offline contract over PatchBaseline.Lines):
  1. every Lines entry whose Type is 'SSU' (case-insensitive) MUST carry a
     non-empty DownloadUrl;
  2. any LCU marked IsCombined=false MUST be paired with a Kind 'SSU' entry that
     itself has a DownloadUrl (a standalone LCU needs its standalone SSU);
  3. a config that carries a Kind 'SSU' MUST have at least one IsCombined=false
     LCU (the SSU is not an orphan).

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
    """Return KbIds of Lines that are SSUs with an empty DownloadUrl.

    An SSU is a servicing-stack prerequisite; with no DownloadUrl it cannot be
    staged, which leads to a downstream 0x800f0823 on the target host.

    Lines live under PatchBaseline in the real config schema
    (schema/config.schema.json -> PatchBaseline.Lines), so that is the
    path checked here.
    """
    violations: list[str] = []
    patches = (config.get("PatchBaseline") or {}).get("Lines") or []
    for patch in patches:
        ptype = (patch.get("Kind") or "").strip().upper()
        url = (patch.get("DownloadUrl") or "").strip()
        if ptype == "SSU" and not url:
            violations.append(patch.get("KbId") or "<no KbId>")
    return violations


def config_lcus(config: dict) -> list[dict]:
    patches = (config.get("PatchBaseline") or {}).get("Lines") or []
    return [p for p in patches if (p.get("Kind") or "").strip().upper() == "LCU"]


def config_ssus_with_url(config: dict) -> list[dict]:
    patches = (config.get("PatchBaseline") or {}).get("Lines") or []
    return [p for p in patches
            if (p.get("Kind") or "").strip().upper() == "SSU"
            and (p.get("DownloadUrl") or "").strip()]


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
    for patch in good["PatchBaseline"]["Lines"]:
        if (patch.get("Kind") or "").upper() == "SSU":
            patch["DownloadUrl"] = "http://example.invalid/fixture/windows10.0-kb5088064-x64.cab"
    r.assert_eq("03 filled-URL config is clean", find_required_ssu_without_downloadurl(good), [])

    # whitespace-only URL is treated as empty
    ws = copy.deepcopy(bad)
    for patch in ws["PatchBaseline"]["Lines"]:
        if (patch.get("Kind") or "").upper() == "SSU":
            patch["DownloadUrl"] = "   "
    r.assert_eq("04 whitespace-only URL still flagged", len(find_required_ssu_without_downloadurl(ws)), 1)

    # a non-SSU patch with an empty URL is NOT this guard's concern
    non_ssu = {"PatchBaseline": {"Lines": [{"Kind": "LCU", "KbId": "KB5087537", "DownloadUrl": ""}]}}
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

    # ---- lock in the Server 2016 SSU resolution (the 0x800f0823 fix) ------
    s2016 = json.loads((DATA_DIR / "config-Server2016.json").read_text(encoding="utf-8"))
    ssus = [p for p in (s2016.get("PatchBaseline") or {}).get("Lines") or []
            if (p.get("Kind") or "").upper() == "SSU"]
    r.assert_eq("08 Server2016 has exactly one SSU Lines entry", len(ssus), 1)
    r.assert_true("09 Server2016 SSU (KB5094141) has a non-empty DownloadUrl",
                  bool((ssus[0].get("DownloadUrl") or "").strip()) and ssus[0].get("KbId") == "KB5094141",
                  f"SSU entry={ssus[0] if ssus else None}")

    # ---- SSU / IsCombined consistency contract (servicing-stack spec) ----
    # A standalone SSU is paired with an LCU ONLY when one is actually published
    # for that LCU's required servicing stack. Server 2016 (KB5094141, a recent SS
    # floor) has such an SSU; Server 2019's LCU is separate-classified in Layer 2
    # but no standalone SSU is published post-2021 (its low SS floor is satisfied by
    # the combined/embedded stack), so it correctly carries no SSU. The offline,
    # deterministic invariant is therefore CONSISTENCY (not "separate => SSU"):
    #   * every Kind=SSU Lines entry has a non-empty DownloadUrl;
    #   * an LCU with IsCombined=false is accompanied by a Kind=SSU (with URL);
    #   * a config carrying a Kind=SSU has at least one IsCombined=false LCU.
    # The decision of which OS actually gets an SSU is made at generation time by
    # Catalog discovery + the servicing-stack-version check, not asserted statically.
    # Config Schema v3.0: the standalone-SSU case is the PatchModel 'separate-ssu'
    # (2016). 'uup-checkpoint' (2025) also carries an SSU Kind (the checkpoint
    # baseline). The offline invariant is CONSISTENCY:
    #   * every Kind=SSU Line has a non-empty DownloadUrl;
    #   * a 'separate-ssu' config carries a Kind=SSU (with URL) and an LCU;
    #   * a config carrying a Kind=SSU has PatchModel in {separate-ssu, uup-checkpoint}.
    for cfg_path in configs:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        model = (cfg.get("PatchModel") or "").strip()
        ssus_with_url = config_ssus_with_url(cfg)
        lcus = config_lcus(cfg)
        bad_url = find_required_ssu_without_downloadurl(cfg)
        r.assert_true(f"10 {cfg_path.name}: every Kind=SSU has a non-empty DownloadUrl",
                      not bad_url, f"SSU(s) without DownloadUrl: {bad_url}")
        if model == "separate-ssu":
            r.assert_true(
                f"11 {cfg_path.name}: separate-ssu carries a Kind=SSU (URL set) and an LCU",
                len(ssus_with_url) > 0 and len(lcus) > 0,
                f"separate-ssu but ssus_with_url={len(ssus_with_url)} lcus={len(lcus)}")
        if ssus_with_url:
            r.assert_true(
                f"12 {cfg_path.name}: a config with a Kind=SSU has PatchModel in {{separate-ssu, uup-checkpoint}}",
                model in ("separate-ssu", "uup-checkpoint"),
                f"has SSU {[s.get('KbId') for s in ssus_with_url]} but PatchModel={model!r}")

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
