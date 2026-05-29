"""
T14: wsusscn2 EOS/ESU deny-list warned-exclusion test (offline).

Exercises the deny-list branch of the Stage 3 scope filter
(ConvertFrom-OfflineSyncPackage) against a dedicated fixture, verifying
the allow-overrides exclusion contract of SPEC B.19.7 / B.19.7.1 in the
PowerShell implementation. This is the executable check that the
PowerShell deny-list filter matches the reference `classify_scope`
semantics in wsusscn2_scope_invariants_test.py.

The fixture (tests/fixtures/wsusscn2/deny-list-package.xml) has four
bundles, all recent and SecurityUpdate-classified:

  * D1: deny-only Server 2012 R2          -> excluded + counted
  * D2: overlap Server 2012 R2 + 2016     -> ADMITTED (allow-overrides)
  * D3: deny-only Server 2008             -> excluded + counted
  * D4: unknown product GUID              -> excluded, NOT counted
                                             (no deny GUID; silent reject)

Verified:
  * Stats.UpdatesInScope counts only the overlap bundle.
  * Stats.EosEsuBundlesExcluded counts exactly the deny-only bundles
    (NOT the unknown-product bundle).
  * Stats.EosEsuFamiliesExcluded names the excluded OS families.
  * The overlap bundle is admitted and retains both its deny and allow
    Product GUIDs (the deny-overrides trap is avoided).
  * The deny-only and unknown bundles are absent from the output.

Runs offline; no wsusscn2.cab download or 7-Zip invocation.

Invocation:
    python3 wsusscn2_deny_list_test.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
SUBPROJECT_DIR = TEST_DIR.parent
SCRIPT_PATH = SUBPROJECT_DIR / "Update-WindowsServerIso.ps1"
FIXTURE_DIR = TEST_DIR / "fixtures" / "wsusscn2"
PACKAGE_XML = FIXTURE_DIR / "deny-list-package.xml"

PINNED_NOW = "2026-05-28T00:00:00Z"

# Fixture GUIDs (lowercase, as canonicalised by the parser)
ALLOW_2016 = "569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5"
DENY_2012R2 = "d31bd4c3-d872-41c9-a2e7-231f372588cb"
ID_D1 = "d0000001-0000-0000-0000-000000000001"
ID_D2 = "d0000001-0000-0000-0000-000000000002"
ID_D3 = "d0000001-0000-0000-0000-000000000003"
ID_D4 = "d0000001-0000-0000-0000-000000000004"


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


def _as_list(value):
    """ConvertTo-Json renders a 1-element array as a scalar object; normalise."""
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def run_powershell_parser(out_path: Path) -> dict:
    """Invoke PowerShell to load the script, run Stage 3 against the deny
    fixture, and return the deserialised ConvertFrom result object.
    """
    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null
$pinnedNow = [datetime]::ParseExact("{PINNED_NOW}","yyyy-MM-ddTHH:mm:ssZ",
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
$result = ConvertFrom-OfflineSyncPackage -PackageXmlPath {PACKAGE_XML} -Now $pinnedNow
$result | ConvertTo-Json -Depth 12 | Set-Content -Path {out_path} -Encoding utf8
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads(out_path.read_text(encoding="utf-8"))


def main() -> int:
    print("T14: wsusscn2 EOS/ESU deny-list warned-exclusion")
    print(f"  fixture: {PACKAGE_XML}")
    print()

    r = TestResult()

    r.assert_true("01 deny fixture exists and is non-empty",
                  PACKAGE_XML.exists() and PACKAGE_XML.stat().st_size > 100)

    print()
    print("Running PowerShell Stage 3 (scope filter) against deny fixture...")
    with tempfile.TemporaryDirectory() as tmp:
        out_path = Path(tmp) / "actual.json"
        result = run_powershell_parser(out_path)
    print()

    stats = result.get("Stats", {})
    updates = _as_list(result.get("Updates"))
    in_scope_ids = {str(u.get("UpdateId", "")).lower() for u in updates}

    # ---- Scope counts ----
    r.assert_eq("02 Stats.UpdatesInScope == 1 (only the overlap bundle)",
                stats.get("UpdatesInScope"), 1)
    r.assert_eq("03 Stats.EosEsuBundlesExcluded == 2 (deny-only D1, D3)",
                stats.get("EosEsuBundlesExcluded"), 2)
    r.assert_eq("04 Stats.EosEsuFamiliesExcluded == ['Server2008','Server2012R2']",
                sorted(_as_list(stats.get("EosEsuFamiliesExcluded"))),
                ["Server2008", "Server2012R2"])

    # ---- Admit / exclude identity ----
    r.assert_true("05 overlap bundle D2 admitted (allow-overrides)",
                  ID_D2 in in_scope_ids, f"in_scope={in_scope_ids}")
    r.assert_true("06 deny-only bundle D1 (Server 2012 R2) excluded",
                  ID_D1 not in in_scope_ids)
    r.assert_true("07 deny-only bundle D3 (Server 2008) excluded",
                  ID_D3 not in in_scope_ids)
    r.assert_true("08 unknown-product bundle D4 excluded (and not counted as EOS/ESU)",
                  ID_D4 not in in_scope_ids)

    # ---- Allow-overrides: admitted overlap keeps both GUIDs ----
    d2 = next((u for u in updates if str(u.get("UpdateId", "")).lower() == ID_D2), None)
    d2_prods = {str(g).lower() for g in _as_list(d2.get("ProductGuids"))} if d2 else set()
    r.assert_true("09 admitted overlap bundle retains its allow GUID (2016)",
                  ALLOW_2016 in d2_prods, f"prods={d2_prods}")
    r.assert_true("10 admitted overlap bundle retains its deny GUID (2012 R2) - deny-overrides trap avoided",
                  DENY_2012R2 in d2_prods, f"prods={d2_prods}")

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
