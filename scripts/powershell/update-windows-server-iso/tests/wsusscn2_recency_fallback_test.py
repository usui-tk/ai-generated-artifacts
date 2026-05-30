"""
T17: wsusscn2 recency-fallback test (offline).

Exercises the recency fallback in Test-PatchServicingReadinessFromGraph
(M1 part 4, r11.8; SPEC B.19.7.2 / handoff section 2.4): when a configured
KB is not in scope (pruned by the recency window or otherwise absent),
the readiness check falls back to the newest in-scope LCU for that OS
family and reports the miss as supersession (a newer in-scope build
exists), not as a data gap. The fallback is only taken when the OS family
is resolvable and actually has an in-scope LCU; otherwise the verdict
stays NotInDatabase.

Drives the function against fixtures/servicing-dependency/recency-fallback-database.json:
  rev 2001  Server 2016 LCU, 2026-03-10, requiredSs 10.0.14393.7000
  rev 2002  Server 2016 LCU, 2026-05-11, requiredSs 10.0.14393.7692  (newest 2016)
  rev 2003  Server 2022 LCU, 2026-05-11, combined                    (newest 2022)

Cases:
  A  out-of-scope KB, OsKey 'Server2016'        -> Superseded, falls back to KB5066666 (newest 2016), model separate
  B  out-of-scope KB, free-form 'WinServer2022' -> Superseded, falls back to KB5077777 (newest 2022), model combined
  C  out-of-scope KB, no OsKey                   -> NotInDatabase (cannot resolve a family)
  D  out-of-scope KB, unknown family 'Server2099'-> NotInDatabase (no in-scope LCU for family)
  E  in-scope KB (KB5066666) present directly    -> Pass (fallback path NOT taken; direct match wins)

Runs offline; the function's only I/O is reading the Layer 2 JSON.

Invocation:
    python3 wsusscn2_recency_fallback_test.py
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
DB_PATH = TEST_DIR / "fixtures" / "servicing-dependency" / "recency-fallback-database.json"


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
$db = '{DB_PATH}'
$patches = @(
  [pscustomobject]@{{ KbId='KB5099999'; OsKey='Server2016' }}      # out of scope, family 2016 -> fallback
  [pscustomobject]@{{ KbId='KB5099998'; OsKey='WinServer2022' }}   # out of scope, free-form 2022 -> fallback
  [pscustomobject]@{{ KbId='KB5099997'; OsKey='' }}                 # out of scope, no OsKey -> NotInDatabase
  [pscustomobject]@{{ KbId='KB5099996'; OsKey='Server2099' }}       # out of scope, unknown family -> NotInDatabase
  [pscustomobject]@{{ KbId='KB5066666'; OsKey='Server2016' }}       # in scope -> Pass (direct match)
)
$r = Test-PatchServicingReadinessFromGraph -ResolvedPatches $patches -DatabasePath $db
$m = [ordered]@{{}}
foreach ($v in $r.PatchVerdicts) {{
    $m[$v.KbId] = [ordered]@{{ verdict=$v.Verdict; model=$v.ServicingStackModel; req=$v.RequiredServicingStackVersion; superseded=$v.Superseded; updateId=$v.UpdateId; notes=$v.Notes }}
}}
[ordered]@{{ overall=$r.OverallStatus; verdicts=$m }} | ConvertTo-Json -Depth 8 | Set-Content -Path {out_path} -Encoding utf8
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads(out_path.read_text(encoding="utf-8"))


def main() -> int:
    print("T17: wsusscn2 recency fallback")
    print(f"  database: {DB_PATH}")
    print()

    r = TestResult()
    r.assert_true("00 recency-fallback DB fixture present", DB_PATH.exists())

    print()
    print("Running PowerShell Test-PatchServicingReadinessFromGraph...")
    with tempfile.TemporaryDirectory() as tmp:
        out = run_powershell(Path(tmp) / "out.json")
    print()

    v = out["verdicts"]

    # ---- Case A: 2016 family fallback -> Superseded, newest 2016 LCU ----
    r.assert_eq("01 KB5099999 out-of-scope 2016 -> Superseded (recency fallback)", v["KB5099999"]["verdict"], "Superseded")
    r.assert_eq("02 KB5099999 Superseded flag true", v["KB5099999"]["superseded"], True)
    r.assert_eq("03 KB5099999 falls back to newest 2016 LCU updateId (rev 2002)", v["KB5099999"]["updateId"], "00000000-0000-0000-0000-0000000017a2")
    r.assert_eq("04 KB5099999 fallback surfaces newest 2016 required SS", v["KB5099999"]["req"], "10.0.14393.7692")
    r.assert_eq("05 KB5099999 fallback surfaces model separate", v["KB5099999"]["model"], "separate")
    r.assert_true("06 KB5099999 note cites recency fallback + target KB5066666", "KB5066666" in v["KB5099999"]["notes"] and "recency fallback" in v["KB5099999"]["notes"])

    # ---- Case B: free-form OsKey token resolves to Server2022 ----
    r.assert_eq("07 KB5099998 free-form OsKey -> Superseded (2022 fallback)", v["KB5099998"]["verdict"], "Superseded")
    r.assert_eq("08 KB5099998 falls back to newest 2022 LCU updateId (rev 2003)", v["KB5099998"]["updateId"], "00000000-0000-0000-0000-0000000017a3")
    r.assert_eq("09 KB5099998 model combined (2022)", v["KB5099998"]["model"], "combined")

    # ---- Case C/D: no fallback target -> NotInDatabase ----
    r.assert_eq("10 KB5099997 no OsKey -> NotInDatabase", v["KB5099997"]["verdict"], "NotInDatabase")
    r.assert_eq("11 KB5099996 unknown family -> NotInDatabase", v["KB5099996"]["verdict"], "NotInDatabase")

    # ---- Case E: in-scope KB resolves directly -> Pass (fallback not taken) ----
    r.assert_eq("12 KB5066666 in scope -> Pass (direct match, no fallback)", v["KB5066666"]["verdict"], "Pass")
    r.assert_eq("13 KB5066666 not flagged superseded", v["KB5066666"]["superseded"], False)

    # ---- Roll-up: NotInDatabase present -> Fail ----
    r.assert_eq("14 OverallStatus Fail (two NotInDatabase present)", out["overall"], "Fail")

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
