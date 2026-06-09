"""
T22: SSU -> LCU readiness verdict unit test (offline, fast).

A fast, pipeline-free companion to T21. Instead of building a Layer 2 DB from
a package.xml, it drives the readiness gate
(Test-PatchServicingReadinessFromGraph) directly against a hand-authored Layer 2
fixture that models the Server 2016 LCU (catalogued as KB5087537): a 'separate'
servicing-stack model with requiredServicingStackVersion 10.0.14393.7692 (the
stack delivered by the SSU, KB5088064).

Varying only the provided servicing stack exercises the SS-compare verdict
boundary that predicts the on-host 0x800f0823 failure:

  * provided RTM 10.0.14393.0        (too old) -> SsTooOld / OverallStatus Fail
  * provided 10.0.14393.7691 (one below)       -> SsTooOld / OverallStatus Fail
  * provided 10.0.14393.7692 (exactly required)-> Pass     / OverallStatus Pass
  * provided 10.0.14393.8000 (newer)           -> Pass     / OverallStatus Pass

T21 proves the whole parse -> DB -> populate -> readiness chain end-to-end; this
test isolates the verdict boundary so a regression there fails fast without the
PowerShell parse/populate stages.

Invocation:
    python3 servicing_dependency_ssu_prereq_readiness_test.py
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
DB_FIXTURE = TEST_DIR / "fixtures" / "servicing-dependency" / "ssu-prereq-readiness-database.json"

REQUIRED_SS = "10.0.14393.7692"


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


def run_powershell(out_path: Path) -> dict:
    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null

$db = '{DB_FIXTURE}'
$patch = @([pscustomobject]@{{ KbId = 'KB5087537'; OsKey = 'S2016' }})

$rtm   = Test-PatchServicingReadinessFromGraph -ResolvedPatches $patch -DatabasePath $db -WimMountState ([pscustomobject]@{{ ProvidedServicingStackVersion = '10.0.14393.0' }})
$below = Test-PatchServicingReadinessFromGraph -ResolvedPatches $patch -DatabasePath $db -WimMountState ([pscustomobject]@{{ ProvidedServicingStackVersion = '10.0.14393.7691' }})
$exact = Test-PatchServicingReadinessFromGraph -ResolvedPatches $patch -DatabasePath $db -PolicyOverride @{{ S2016 = '10.0.14393.7692' }}
$newer = Test-PatchServicingReadinessFromGraph -ResolvedPatches $patch -DatabasePath $db -PolicyOverride @{{ S2016 = '10.0.14393.8000' }}

function _one($r) {{
    $v = $r.PatchVerdicts | Where-Object {{ $_.KbId -eq 'KB5087537' }} | Select-Object -First 1
    return [ordered]@{{ available = $r.Available; overall = $r.OverallStatus; verdict = $v.Verdict; model = $v.ServicingStackModel; req = $v.RequiredServicingStackVersion; prov = $v.ProvidedServicingStackVersion }}
}}

[ordered]@{{
    rtm   = (_one $rtm)
    below = (_one $below)
    exact = (_one $exact)
    newer = (_one $newer)
}} | ConvertTo-Json -Depth 8 | Set-Content -Path '{out_path / "result.json"}' -Encoding utf8
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads((out_path / "result.json").read_text(encoding="utf-8"))


def main() -> int:
    print("T22: SSU -> LCU readiness verdict unit (SS-compare boundary)")
    print()

    r = TestResult()
    r.assert_true("00 readiness DB fixture present", DB_FIXTURE.exists())

    db = json.loads(DB_FIXTURE.read_text(encoding="utf-8"))
    r.assert_eq("01 fixture has one update", len(db["updates"]), 1)
    r.assert_eq("02 fixture LCU requiredServicingStackVersion", db["updates"][0]["requiredServicingStackVersion"], REQUIRED_SS)
    r.assert_eq("03 fixture LCU model separate", db["updates"][0]["servicingStackModel"], "separate")

    print()
    print("Running PowerShell Test-PatchServicingReadinessFromGraph...")
    with tempfile.TemporaryDirectory() as tmp:
        out = run_powershell(Path(tmp))
    print()

    # provided RTM (too old) -> SsTooOld / Fail
    r.assert_eq("04 RTM provided -> verdict SsTooOld", out["rtm"]["verdict"], "SsTooOld")
    r.assert_eq("05 RTM provided -> OverallStatus Fail", out["rtm"]["overall"], "Fail")
    r.assert_eq("06 RTM provided -> model separate", out["rtm"]["model"], "separate")
    r.assert_eq("07 RTM provided -> required SS reported", out["rtm"]["req"], REQUIRED_SS)

    # provided one build below required -> SsTooOld / Fail
    r.assert_eq("08 one-below provided -> verdict SsTooOld", out["below"]["verdict"], "SsTooOld")
    r.assert_eq("09 one-below provided -> OverallStatus Fail", out["below"]["overall"], "Fail")

    # provided exactly required -> Pass / Pass
    r.assert_eq("10 exact provided -> verdict Pass", out["exact"]["verdict"], "Pass")
    r.assert_eq("11 exact provided -> OverallStatus Pass", out["exact"]["overall"], "Pass")
    r.assert_eq("12 exact provided -> provided SS reported", out["exact"]["prov"], REQUIRED_SS)

    # provided newer than required -> Pass / Pass
    r.assert_eq("13 newer provided -> verdict Pass", out["newer"]["verdict"], "Pass")
    r.assert_eq("14 newer provided -> OverallStatus Pass", out["newer"]["overall"], "Pass")

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
