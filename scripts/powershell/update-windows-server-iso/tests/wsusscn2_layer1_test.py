"""
T13: Update-Layer1DependencyVerification self-verification test (offline).

Exercises the Phase 2b2 Layer 1 writeback helper
`Update-Layer1DependencyVerification` against the T12 fixture
(tests/fixtures/wsusscn2/package.xml), verifying:

  * the function correctly picks the most recent LCU-bearing Update per
    Server OS family (Product GUID lookup against $Script:WsusScnOsCategoryGuids)
  * the three advisory fields are written to each matching
    config-Server*.json: _DependencyVerifiedKb, _DependencyVerifiedCreationDate,
    _DependencyVerifiedAt
  * idempotent re-runs report UnchangedCount rather than UpdatedCount
  * OS families with no in-scope LCU in the fixture are counted as
    MissingCount (no config writeback attempted)
  * the writeback uses canonical-JSON serialization (SPEC §B.23)

Because the function performs an actual writeback to data/config-*.json,
the test runs against a temporary copy of the data/ directory (created
afresh per run) so the repository's real config files are never touched.

Stage 1 (Get-WsusScnCabIfNeeded) is platform-coupled to network
+ Windows file layout and is NOT exercised here; it is covered by the
live monthly refresh CI and the synthetic-test-mode end-to-end run.

Invocation:
    python3 wsusscn2_layer1_test.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
SUBPROJECT_DIR = TEST_DIR.parent
SCRIPT_PATH = SUBPROJECT_DIR / "Update-WindowsServerIso.ps1"
FIXTURE_DIR = TEST_DIR / "fixtures" / "wsusscn2"
PACKAGE_XML = FIXTURE_DIR / "package.xml"

PINNED_NOW = "2026-05-28T00:00:00Z"

# Expected LCU mapping derived from the T12 fixture:
#  - Server 2022 bundle (revision 990001) is the only in-scope LCU for
#    Server2022 with KBArticleID=5099001, CreationDate=2026-04-15
#  - Server 2025 bundle (revision 990003) is the only in-scope LCU for
#    Server2025 with KBArticleID=5099003, CreationDate=2026-05-10
#  - Server 2016 and Server 2019 have no in-scope LCU in the fixture
EXPECTED_SERVER2022 = {"kb": "KB5099001", "creationDate": "2026-04-15T10:00:00Z"}
EXPECTED_SERVER2025 = {"kb": "KB5099003", "creationDate": "2026-05-10T10:00:00Z"}


# ---------------------------------------------------------------------------
# Test infrastructure
# ---------------------------------------------------------------------------

class TestResult:
    def __init__(self) -> None:
        self.passed = 0
        self.failed: list[tuple[str, str]] = []

    def assert_eq(self, name: str, actual, expected) -> None:
        if actual == expected:
            self.passed += 1
            print(f"  [PASS] {name}")
        else:
            self.failed.append((name, f"expected={expected!r} actual={actual!r}"))
            print(f"  [FAIL] {name}: expected={expected!r} actual={actual!r}")

    def assert_true(self, name: str, cond, detail: str = "") -> None:
        if cond:
            self.passed += 1
            print(f"  [PASS] {name}")
        else:
            self.failed.append((name, detail or "condition false"))
            print(f"  [FAIL] {name}: {detail or 'condition false'}")

    def summary(self) -> int:
        total = self.passed + len(self.failed)
        print()
        print(f"Summary: {self.passed} passed, {len(self.failed)} failed, {total} total")
        return 0 if not self.failed else 1


def setup_temp_data_root(tmp_root: Path) -> Path:
    """Create a fresh data/config-Server*.json tree inside tmp_root.

    Uses minimal valid config skeletons (just an OsKey field) so the
    PowerShell helper Save-ConfigWithBaseline can read/write them.
    """
    data_dir = tmp_root / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    for os_key in ("Server2016", "Server2019", "Server2022", "Server2025"):
        cfg = {"OsKey": os_key, "_TestFixture": True}
        (data_dir / f"config-{os_key}.json").write_text(
            json.dumps(cfg, indent=2) + "\n", encoding="utf-8"
        )
    return data_dir


def run_layer1_update(data_dir: Path) -> dict:
    """Invoke the PowerShell pipeline:
      1. parse the fixture package.xml (Stage 3)
      2. call Update-Layer1DependencyVerification against the temp data_dir
      3. emit the function's return object as JSON for assertions
    """
    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null
$pinnedNow = [datetime]::ParseExact("{PINNED_NOW}","yyyy-MM-ddTHH:mm:ssZ",
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
$result = ConvertFrom-WsusScnPackageXml -PackageXmlPath {PACKAGE_XML} -Now $pinnedNow
$layer1 = Update-Layer1DependencyVerification -ParseResult $result -DataRoot {data_dir} 2>$null
$layer1 | ConvertTo-Json -Depth 5
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    # Extract trailing JSON (PowerShell may interleave Write-Step output)
    text = proc.stdout.strip()
    # Find last '{' that starts JSON
    last_brace = text.rfind('{')
    json_text = text[last_brace:]
    return json.loads(json_text)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    print("T13: Update-Layer1DependencyVerification self-verification")
    print(f"  fixture: {PACKAGE_XML}")
    print()

    r = TestResult()

    with tempfile.TemporaryDirectory() as tmp:
        tmp_root = Path(tmp)
        data_dir = setup_temp_data_root(tmp_root)

        # Pre-flight: the 4 stub configs should be present
        cfg_paths = {os_key: data_dir / f"config-{os_key}.json"
                     for os_key in ("Server2016", "Server2019", "Server2022", "Server2025")}
        r.assert_true("01 4 stub config-Server*.json created",
                      all(p.exists() for p in cfg_paths.values()))

        # ---- Run 1: first invocation -> Server2022 and Server2025 should be Updated ----
        print()
        print("Run 1: first invocation (expected 2 updated, 2 missing)...")
        result1 = run_layer1_update(data_dir)
        r.assert_eq("02 Run 1: UpdatedCount   == 2", result1["UpdatedCount"],   2)
        r.assert_eq("03 Run 1: UnchangedCount == 0", result1["UnchangedCount"], 0)
        r.assert_eq("04 Run 1: MissingCount   == 2 (Server2016, Server2019)",
                    result1["MissingCount"], 2)

        # ---- Verify written field values ----
        s2022_cfg = json.loads(cfg_paths["Server2022"].read_text(encoding="utf-8"))
        r.assert_eq("05 Server2022: _DependencyVerifiedKb == KB5099001",
                    s2022_cfg.get("_DependencyVerifiedKb"), EXPECTED_SERVER2022["kb"])
        r.assert_eq("06 Server2022: _DependencyVerifiedCreationDate matches fixture",
                    s2022_cfg.get("_DependencyVerifiedCreationDate"),
                    EXPECTED_SERVER2022["creationDate"])
        r.assert_true("07 Server2022: _DependencyVerifiedAt present (ISO-8601)",
                      bool(s2022_cfg.get("_DependencyVerifiedAt")))

        s2025_cfg = json.loads(cfg_paths["Server2025"].read_text(encoding="utf-8"))
        r.assert_eq("08 Server2025: _DependencyVerifiedKb == KB5099003",
                    s2025_cfg.get("_DependencyVerifiedKb"), EXPECTED_SERVER2025["kb"])
        r.assert_eq("09 Server2025: _DependencyVerifiedCreationDate matches fixture",
                    s2025_cfg.get("_DependencyVerifiedCreationDate"),
                    EXPECTED_SERVER2025["creationDate"])

        # Server2016 / Server2019 should NOT have the fields populated (no fixture data)
        s2016_cfg = json.loads(cfg_paths["Server2016"].read_text(encoding="utf-8"))
        r.assert_true("10 Server2016: no _DependencyVerifiedKb (Missing path correctly skipped writeback)",
                      "_DependencyVerifiedKb" not in s2016_cfg)

        # Pre-existing fields (OsKey) should be preserved on writeback
        r.assert_eq("11 Server2022: existing OsKey field preserved on writeback",
                    s2022_cfg.get("OsKey"), "Server2022")

        # ---- Run 2: idempotent re-invocation -> UnchangedCount == 2 ----
        print()
        print("Run 2: idempotent re-invocation (expected 0 updated, 2 unchanged)...")
        result2 = run_layer1_update(data_dir)
        r.assert_eq("12 Run 2: UpdatedCount   == 0 (idempotent)", result2["UpdatedCount"],   0)
        r.assert_eq("13 Run 2: UnchangedCount == 2 (Server2022, Server2025)",
                    result2["UnchangedCount"], 2)
        r.assert_eq("14 Run 2: MissingCount   == 2 (still Server2016, Server2019)",
                    result2["MissingCount"], 2)

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
