"""
T16: wsusscn2 Phase 2c readiness verdict test (offline).

Exercises Test-PatchServicingReadinessFromGraph (M1 part 3, r11.7), the
three-check servicing-stack readiness model (SPEC B.19.13 / B.19.13.1):

  1. Presence            - KB resolves to an in-scope Layer 2 update.
  2. SS version compare  - separate OS only; provided SS < required SS
                           -> SsTooOld (the 0x800f0823 predictor).
  3. Supersession        - matched update is superseded by an in-scope
                           revision -> Superseded.

Verdict precedence: NotInDatabase > SsTooOld > Superseded > Pass.

Drives the function against fixtures/servicing-dependency/readiness-database.json,
whose five updates cover:
  rev 1001  2016 separate, requiredSs 10.0.14393.7692, not superseded
  rev 1002  2022 combined  (SS N/A)
  rev 1003  2025 checkpoint (SS N/A)
  rev 1004  2016 separate, superseded by in-scope rev 1001
  rev 1005  2016 separate, supersededBy rev 9999999 which is OUT of scope

Cases:
  A  separate, provided < required           -> SsTooOld / OverallStatus Fail
  B  separate, provided >= required (policy)  -> Pass
  C  combined / checkpoint                    -> Pass (SS skipped, N/A note)
  D  superseded by in-scope rev               -> Superseded / Warning
  E  supersededBy out-of-scope rev only       -> not superseded -> Pass
  F  KB absent from DB                         -> NotInDatabase / Fail
  G  missing DB file                           -> Available False / Unknown

Runs offline; the function's only I/O is reading the Layer 2 JSON, so no
wsusscn2.cab download or 7-Zip invocation is needed.

Invocation:
    python3 servicing_dependency_readiness_verdict_test.py
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
DB_PATH = TEST_DIR / "fixtures" / "servicing-dependency" / "readiness-database.json"


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


def run_powershell(out_path: Path, missing_db: Path) -> dict:
    """Drive the verdict function over several scenarios; emit JSON."""
    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null
$db = '{DB_PATH}'

# Case A/C/D/E/F together: provided 10.0.14393.7000 (older than 2016 req 7692).
$patches = @(
  [pscustomobject]@{{ KbId='KB5066666'; OsKey='S2016' }}   # separate, too old -> SsTooOld
  [pscustomobject]@{{ KbId='KB5077777'; OsKey='S2022' }}   # combined -> Pass (N/A)
  [pscustomobject]@{{ KbId='KB5088888'; OsKey='S2025' }}   # checkpoint -> Pass (N/A)
  [pscustomobject]@{{ KbId='KB5099999'; OsKey='S2016' }}   # superseded in-scope -> Superseded
  [pscustomobject]@{{ KbId='KB5000001'; OsKey='S2016' }}   # not in DB -> NotInDatabase
)
$wim = [pscustomobject]@{{ ProvidedServicingStackVersion = '10.0.14393.7000' }}
$rA = Test-PatchServicingReadinessFromGraph -ResolvedPatches $patches -DatabasePath $db -WimMountState $wim

# Case E (isolated): KB5055555 with NO provided SS supplied. supersededBy is
# only an out-of-scope revision, and with no provided SS the separate-model
# SS comparison is skipped -> the patch is Pass (not Superseded, not SsTooOld).
$rE = Test-PatchServicingReadinessFromGraph -ResolvedPatches @([pscustomobject]@{{ KbId='KB5055555'; OsKey='S2019' }}) -DatabasePath $db

# Case B: provided >= required via PolicyOverride keyed by OsKey.
$rB = Test-PatchServicingReadinessFromGraph -ResolvedPatches @([pscustomobject]@{{ KbId='KB5066666'; OsKey='S2016' }}) -DatabasePath $db -PolicyOverride @{{ S2016 = '10.0.14393.8000' }}

# Case G: missing DB.
$rG = Test-PatchServicingReadinessFromGraph -ResolvedPatches @([pscustomobject]@{{ KbId='KB1' }}) -DatabasePath '{missing_db}'

function _vmap($r) {{
    $m = [ordered]@{{}}
    foreach ($v in $r.PatchVerdicts) {{ $m[$v.KbId] = [ordered]@{{ verdict=$v.Verdict; model=$v.ServicingStackModel; req=$v.RequiredServicingStackVersion; prov=$v.ProvidedServicingStackVersion; superseded=$v.Superseded }} }}
    return $m
}}
[ordered]@{{
  A = [ordered]@{{ available=$rA.Available; overall=$rA.OverallStatus; shaLen=($rA.DatabaseSha256.Length); genAt=$rA.DatabaseGeneratedAt; verdicts=(_vmap $rA) }}
  B = [ordered]@{{ overall=$rB.OverallStatus; verdicts=(_vmap $rB) }}
  E = [ordered]@{{ overall=$rE.OverallStatus; verdicts=(_vmap $rE) }}
  G = [ordered]@{{ available=$rG.Available; overall=$rG.OverallStatus; reasons=$rG.Reasons }}
}} | ConvertTo-Json -Depth 8 | Set-Content -Path {out_path} -Encoding utf8
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads(out_path.read_text(encoding="utf-8"))


def main() -> int:
    print("T16: wsusscn2 Phase 2c readiness verdict")
    print(f"  database: {DB_PATH}")
    print()

    r = TestResult()
    r.assert_true("00 readiness DB fixture present", DB_PATH.exists())

    print()
    print("Running PowerShell Test-PatchServicingReadinessFromGraph...")
    with tempfile.TemporaryDirectory() as tmp:
        out = run_powershell(Path(tmp) / "out.json", Path(tmp) / "no-such-db.json")
    print()

    A = out["A"]
    va = A["verdicts"]

    # ---- Top-level availability + provenance ----
    r.assert_eq("01 Available true for present DB", A["available"], True)
    r.assert_eq("02 OverallStatus Fail (an SsTooOld + a NotInDatabase present)", A["overall"], "Fail")
    r.assert_eq("03 DatabaseSha256 is a 64-hex digest", A["shaLen"], 64)
    r.assert_eq("04 DatabaseGeneratedAt surfaced from _meta", A["genAt"], "2026-05-12T00:00:00Z")

    # ---- Case A: separate, provided < required -> SsTooOld ----
    r.assert_eq("05 KB5066666 separate provided<required -> SsTooOld", va["KB5066666"]["verdict"], "SsTooOld")
    r.assert_eq("06 KB5066666 model separate", va["KB5066666"]["model"], "separate")
    r.assert_eq("07 KB5066666 required SS surfaced", va["KB5066666"]["req"], "10.0.14393.7692")
    r.assert_eq("08 KB5066666 provided SS from WimMountState", va["KB5066666"]["prov"], "10.0.14393.7000")

    # ---- Case C: combined / checkpoint -> Pass (SS N/A) ----
    r.assert_eq("09 KB5077777 combined -> Pass (SS N/A)", va["KB5077777"]["verdict"], "Pass")
    r.assert_eq("10 KB5088888 checkpoint -> Pass (SS N/A)", va["KB5088888"]["verdict"], "Pass")

    # ---- Case D: superseded by in-scope -> Superseded ----
    r.assert_eq("11 KB5099999 superseded by in-scope rev -> Superseded", va["KB5099999"]["verdict"], "Superseded")
    r.assert_eq("12 KB5099999 Superseded flag true", va["KB5099999"]["superseded"], True)

    # ---- Case E: supersededBy out-of-scope only, no provided SS -> Pass ----
    ve = out["E"]["verdicts"]
    r.assert_eq("13 KB5055555 supersededBy out-of-scope rev -> not Superseded", ve["KB5055555"]["superseded"], False)
    r.assert_eq("14 KB5055555 no provided SS -> Pass (SS check skipped, no in-scope successor)", ve["KB5055555"]["verdict"], "Pass")

    # ---- Case F: KB absent -> NotInDatabase ----
    r.assert_eq("15 KB5000001 absent -> NotInDatabase", va["KB5000001"]["verdict"], "NotInDatabase")

    # ---- Case B: provided >= required (policy override) -> Pass ----
    r.assert_eq("16 Case B OverallStatus Pass", out["B"]["overall"], "Pass")
    r.assert_eq("17 KB5066666 provided(policy)>=required -> Pass", out["B"]["verdicts"]["KB5066666"]["verdict"], "Pass")
    r.assert_eq("18 KB5066666 provided SS from PolicyOverride", out["B"]["verdicts"]["KB5066666"]["prov"], "10.0.14393.8000")

    # ---- Case G: missing DB -> Unknown ----
    r.assert_eq("19 missing DB -> Available false", out["G"]["available"], False)
    r.assert_eq("20 missing DB -> OverallStatus Unknown", out["G"]["overall"], "Unknown")

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
