"""
T19: wsusscn2 data-contract consistency test (offline).

Exercises Test-DataContractConsistency (M1 part 6, r11.10), the
cross-cutting data-quality check wired into A04 RefreshDependencyDatabase.
Every generated artifact stamps the Script's shared data-contract
identity (dataContractId + dataContractVersion) into its _meta; this
function classifies each artifact and rolls up the worst status.

Per-artifact Status:
  Current - id matches and version equals the Script's epoch.
  Stale   - id matches but version is older, OR _meta present but
            unstamped (a pre-contract artifact).
  Refuse  - version is newer than this script understands.
  Foreign - dataContractId present but not this family GUID.
  Unknown - file has no _meta (not a contract-bearing artifact).
OverallStatus is the worst across artifacts; Unknown does not worsen it.

The test writes small synthetic JSON artifacts into a tempdir (it never
touches the repository's real data/) and asserts the classification and
roll-up, plus the directory-expansion behaviour (a directory argument
expands to its *.json files) used by the A04 wiring.

The committed data/servicing-dependency-database.json is additionally checked to be
classified Current (it was regenerated under the current contract).

Invocation:
    python3 wsusscn2_data_contract_test.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
SUBPROJECT_DIR = TEST_DIR.parent
SCRIPT_PATH = SUBPROJECT_DIR / "Update-WindowsServerIso.ps1"
DB_PATH = SUBPROJECT_DIR / "data" / "servicing-dependency-database.json"


def _script_contract():
    """Read the Script's DataContractId / DataContractVersion from the .ps1."""
    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")
    gid = re.search(r"\$Script:DataContractId\s*=\s*'([0-9a-fA-F-]+)'", text)
    ver = re.search(r"\$Script:DataContractVersion\s*=\s*(\d+)", text)
    return gid.group(1), int(ver.group(1))


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


def run_powershell(tmp: Path, out_path: Path, cid: str, ver: int) -> dict:
    # Build synthetic artifacts covering each status.
    def write(name, meta):
        (tmp / name).write_text(json.dumps({"_meta": meta, "updates": []}), encoding="utf-8")

    write("current.json", {"dataContractId": cid, "dataContractVersion": ver})
    write("stale-older.json", {"dataContractId": cid, "dataContractVersion": ver - 1})
    write("stale-unstamped.json", {"generator": "x"})  # _meta present, no contract stamp
    write("refuse.json", {"dataContractId": cid, "dataContractVersion": ver + 1})
    write("foreign.json", {"dataContractId": "00000000-0000-0000-0000-000000000000", "dataContractVersion": ver})
    (tmp / "no-meta.json").write_text(json.dumps({"updates": []}), encoding="utf-8")

    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null

function _one($p) {{
    $r = Test-DataContractConsistency -Path @($p)
    return $r.Files[0].Status
}}

$indiv = [ordered]@{{
    current        = (_one '{tmp / "current.json"}')
    stale_older    = (_one '{tmp / "stale-older.json"}')
    stale_unstamped= (_one '{tmp / "stale-unstamped.json"}')
    refuse         = (_one '{tmp / "refuse.json"}')
    foreign        = (_one '{tmp / "foreign.json"}')
    no_meta        = (_one '{tmp / "no-meta.json"}')
}}

# Directory expansion + roll-up over the whole synthetic dir.
$all = Test-DataContractConsistency -Path @('{tmp}')
$dirOverall = $all.OverallStatus
$dirCount = $all.Files.Count

# Current-only subset rolls up to Current.
$curOnly = Test-DataContractConsistency -Path @('{tmp / "current.json"}','{tmp / "no-meta.json"}')

# The committed Layer 2 DB should classify Current.
$db = Test-DataContractConsistency -Path @('{DB_PATH}')

[ordered]@{{
    indiv = $indiv
    dirOverall = $dirOverall
    dirCount = $dirCount
    curOnlyOverall = $curOnly.OverallStatus
    dbStatus = $db.Files[0].Status
}} | ConvertTo-Json -Depth 6 | Set-Content -Path {out_path} -Encoding utf8
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads(out_path.read_text(encoding="utf-8"))


def main() -> int:
    print("T19: wsusscn2 data-contract consistency")
    print()

    r = TestResult()
    cid, ver = _script_contract()
    r.assert_true("00 read Script data-contract id/version", bool(cid) and ver >= 1)

    print()
    print("Running PowerShell Test-DataContractConsistency...")
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        out = run_powershell(tmp, tmp / "out.json", cid, ver)
    print()

    iv = out["indiv"]
    r.assert_eq("01 matching id + epoch -> Current", iv["current"], "Current")
    r.assert_eq("02 matching id, older version -> Stale", iv["stale_older"], "Stale")
    r.assert_eq("03 _meta present but unstamped -> Stale", iv["stale_unstamped"], "Stale")
    r.assert_eq("04 newer version -> Refuse", iv["refuse"], "Refuse")
    r.assert_eq("05 different id family -> Foreign", iv["foreign"], "Foreign")
    r.assert_eq("06 no _meta -> Unknown", iv["no_meta"], "Unknown")

    # Roll-up over the whole dir contains Refuse + Foreign -> worst is Fail-class.
    r.assert_true("07 directory argument expanded to all *.json (6 files)",
                  out["dirCount"] == 6, f"count={out['dirCount']}")
    r.assert_true("08 mixed dir rolls up to a worst status of Refuse or Foreign",
                  out["dirOverall"] in ("Refuse", "Foreign"))

    # Current + Unknown rolls up to Current (Unknown must not worsen).
    r.assert_eq("09 Current + Unknown rolls up to Current", out["curOnlyOverall"], "Current")

    # Committed DB is Current.
    r.assert_eq("10 committed Layer 2 DB classifies Current", out["dbStatus"], "Current")

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
