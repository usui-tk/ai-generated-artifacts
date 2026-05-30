"""
T15: wsusscn2 servicing-stack extraction test (offline).

Exercises the two pure functions added in M1 part 2 (r11.6) that turn a
per-package CBS metadata blob into the servicing-stack facts the Phase 2c
readiness check needs (SPEC B.19.13):

  * Resolve-OfflineSyncRevisionToCab - maps a revision id to the per-package
    cab that holds its c/<revisionId> metadata, using the index.xml
    CABLIST RANGESTART boundaries (greatest RANGESTART <= revision).
  * Get-OfflineSyncServicingStackInfo - reads a leaf's CBS metadata and
    derives requiredServicingStackVersion + servicingStackModel
    ('separate' | 'combined' | 'checkpoint').

The CBS fixtures are minimised real leaves from the 2026-05 cab:
  * leaf-2016-separate.xml   -> separate,   requiredSs 10.0.14393.7692
  * leaf-2022-combined.xml   -> combined,   requiredSs null (6.0.0.0 nominal)
  * leaf-2025-checkpoint.xml -> checkpoint, requiredSs null (no CBS meta)

The index.xml fixture is a trimmed CABLIST that reproduces the real
RANGESTART boundary behaviour, including the exact-boundary case.

Runs offline; the functions take text input, so no wsusscn2.cab download
or 7-Zip invocation is needed.

Invocation:
    python3 wsusscn2_servicing_stack_test.py
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
CBS_DIR = TEST_DIR / "fixtures" / "servicing-dependency" / "cbs"

# A trimmed CABLIST that preserves real RANGESTART boundary semantics.
# package2.cab starts at 0, package3 at 605, package74 at 44562114.
INDEX_XML = (
    '<INDEX VERSION="1"><CABLIST XOR="0">'
    '<CAB NAME="package.cab" />'
    '<CAB NAME="package2.cab" RANGESTART="0" FILESDIR="1" />'
    '<CAB NAME="package3.cab" RANGESTART="605" />'
    '<CAB NAME="package74.cab" RANGESTART="44562114" />'
    '</CABLIST></INDEX>'
)


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
    """Load the script and drive the two functions, emitting a JSON result."""
    f2016 = CBS_DIR / "leaf-2016-separate.xml"
    f2022 = CBS_DIR / "leaf-2022-combined.xml"
    f2025 = CBS_DIR / "leaf-2025-checkpoint.xml"
    idx = INDEX_XML.replace("'", "''")
    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null
$idx = '{idx}'
$resolve = [ordered]@{{}}
# exact boundary (44562114 -> package74), one below boundary (44562113 -> package3),
# the 2016/2022 real leaf revs, and the small 2025 rev.
$resolve['exact_boundary'] = Resolve-OfflineSyncRevisionToCab -IndexXml $idx -RevisionId 44562114
$resolve['below_boundary'] = Resolve-OfflineSyncRevisionToCab -IndexXml $idx -RevisionId 44562113
$resolve['rev_45255708']   = Resolve-OfflineSyncRevisionToCab -IndexXml $idx -RevisionId 45255708
$resolve['rev_295']        = Resolve-OfflineSyncRevisionToCab -IndexXml $idx -RevisionId 295
$resolve['rev_zero']       = Resolve-OfflineSyncRevisionToCab -IndexXml $idx -RevisionId 0

function _ss($p) {{
    $r = Get-OfflineSyncServicingStackInfo -CbsMetaXml (Get-Content -Raw $p)
    return [ordered]@{{
        model    = $r.ServicingStackModel
        required = $r.RequiredServicingStackVersion
        inline   = $r.InlineServicingStackPackage
    }}
}}
$ss = [ordered]@{{
    s2016 = _ss '{f2016}'
    s2022 = _ss '{f2022}'
    s2025 = _ss '{f2025}'
    empty = (Get-OfflineSyncServicingStackInfo -CbsMetaXml '' | Select-Object -Property ServicingStackModel,RequiredServicingStackVersion | ForEach-Object {{ [ordered]@{{ model = $_.ServicingStackModel; required = $_.RequiredServicingStackVersion }} }})
}}
[ordered]@{{ resolve = $resolve; ss = $ss }} | ConvertTo-Json -Depth 8 | Set-Content -Path {out_path} -Encoding utf8
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads(out_path.read_text(encoding="utf-8"))


def main() -> int:
    print("T15: wsusscn2 servicing-stack extraction")
    print(f"  cbs fixtures: {CBS_DIR}")
    print()

    r = TestResult()

    for f in ("leaf-2016-separate.xml", "leaf-2022-combined.xml", "leaf-2025-checkpoint.xml"):
        r.assert_true(f"00 fixture {f} present", (CBS_DIR / f).exists())

    print()
    print("Running PowerShell servicing-stack functions...")
    with tempfile.TemporaryDirectory() as tmp:
        out = run_powershell(Path(tmp) / "out.json")
    print()

    resolve = out["resolve"]
    ss = out["ss"]

    # ---- Resolve-OfflineSyncRevisionToCab ----
    r.assert_eq("01 revision == RANGESTART boundary maps to that cab (44562114 -> package74)",
                resolve["exact_boundary"], "package74.cab")
    r.assert_eq("02 revision one below boundary maps to prior cab (44562113 -> package3)",
                resolve["below_boundary"], "package3.cab")
    r.assert_eq("03 real 2016 leaf revision (45255708) maps to package74",
                resolve["rev_45255708"], "package74.cab")
    r.assert_eq("04 small revision (295) maps to first ranged cab (package2)",
                resolve["rev_295"], "package2.cab")
    r.assert_eq("05 revision 0 maps to package2 (RANGESTART=0)",
                resolve["rev_zero"], "package2.cab")

    # ---- Get-OfflineSyncServicingStackInfo: 2016 separate ----
    r.assert_eq("06 2016 leaf -> servicingStackModel 'separate'",
                ss["s2016"]["model"], "separate")
    r.assert_eq("07 2016 leaf -> requiredServicingStackVersion 10.0.14393.7692",
                ss["s2016"]["required"], "10.0.14393.7692")

    # ---- 2022 combined ----
    r.assert_eq("08 2022 leaf -> servicingStackModel 'combined'",
                ss["s2022"]["model"], "combined")
    r.assert_eq("09 2022 leaf -> requiredServicingStackVersion null (6.0.0.0 nominal)",
                ss["s2022"]["required"], None)
    r.assert_eq("10 2022 leaf -> inline Package_for_ServicingStack_5120 detected",
                ss["s2022"]["inline"], "Package_for_ServicingStack_5120")

    # ---- 2025 checkpoint ----
    r.assert_eq("11 2025 leaf -> servicingStackModel 'checkpoint'",
                ss["s2025"]["model"], "checkpoint")
    r.assert_eq("12 2025 leaf -> requiredServicingStackVersion null",
                ss["s2025"]["required"], None)

    # ---- empty input is treated as checkpoint (no CBS meta), never throws ----
    r.assert_eq("13 empty CBS meta -> checkpoint, required null",
                (ss["empty"]["model"], ss["empty"]["required"]), ("checkpoint", None))

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
