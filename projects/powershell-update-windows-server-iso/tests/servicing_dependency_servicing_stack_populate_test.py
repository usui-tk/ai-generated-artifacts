"""
T18: wsusscn2 servicing-stack populate test (offline, pure halves).

Exercises the I/O-free halves of the M1 servicing-stack populate
(M1 part 5b, r11.10; SPEC B.19.13.0):

  * Select-OfflineSyncLcuLeafRevision - choose a bundle's LCU leaf revision
    from the Stage 3 LeafRevisionIds: single -> that one; multiple ->
    the leaf whose revision id is the closest below the bundle's own
    (LCU emitted just before its bundle); none below -> the greatest;
    empty -> null.
  * Update-ServicingStackFromMeta - given a Layer 2 document, a
    revision->CBS-text map, and a bundle-revision->leaf-revision map,
    populate requiredServicingStackVersion / providedServicingStackVersion
    / servicingStackModel on each update (via Get-OfflineSyncServicingStackInfo),
    leaving updates with no leaf metadata unchanged.

The 7-Zip extraction wrapper (Invoke-OfflineSyncLeafServicingStackExtract) is
deliberately NOT exercised here; it is the only cab/7-Zip-touching part
and is covered by the live monthly CI. These pure functions take text /
object inputs and are unit-testable offline, reusing the same minimised
real-cab CBS fixtures as T15.

Cases:
  Select: single, closest-below, none-below->max, empty->null
  Populate: 2016 leaf -> separate + requiredSs; 2022 -> combined (null);
            2025 -> checkpoint (null); a bundle whose leaf meta is absent
            -> skipped, fields untouched; providedServicingStackVersion
            always null (resolved later at readiness-check time).

Invocation:
    python3 servicing_dependency_servicing_stack_populate_test.py
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
    f2016 = CBS_DIR / "leaf-2016-separate.xml"
    f2022 = CBS_DIR / "leaf-2022-combined.xml"
    f2025 = CBS_DIR / "leaf-2025-checkpoint.xml"
    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null

# ---- Select-OfflineSyncLcuLeafRevision ----
$sel = [ordered]@{{
    single        = (Select-OfflineSyncLcuLeafRevision -BundleRevisionId '100' -LeafRevisionIds @('99'))
    closest_below = (Select-OfflineSyncLcuLeafRevision -BundleRevisionId '45255709' -LeafRevisionIds @('45255700','45255708','45255600'))
    none_below    = (Select-OfflineSyncLcuLeafRevision -BundleRevisionId '100' -LeafRevisionIds @('200','150','300'))
    empty         = (Select-OfflineSyncLcuLeafRevision -BundleRevisionId '100' -LeafRevisionIds @())
}}

# ---- Update-ServicingStackFromMeta ----
# Document with four bundles: 2016/2022/2025 have leaf meta; the fourth has
# a leaf revision with no metadata in the map (skipped).
$doc = [pscustomobject]@{{ updates = @(
    [pscustomobject]@{{ revisionId = '1001'; kbIds = @('5066666') }}
    [pscustomobject]@{{ revisionId = '1002'; kbIds = @('5077777') }}
    [pscustomobject]@{{ revisionId = '1003'; kbIds = @('5088888') }}
    [pscustomobject]@{{ revisionId = '1004'; kbIds = @('5099999') }}
) }}
$leafByRev = @{{ '1001'='9001'; '1002'='9002'; '1003'='9003'; '1004'='9004' }}
$metaMap = @{{
    '9001' = (Get-Content -Raw '{f2016}')
    '9002' = (Get-Content -Raw '{f2022}')
    '9003' = (Get-Content -Raw '{f2025}')
}}  # note: 9004 absent -> update 1004 skipped
$summary = Update-ServicingStackFromMeta -Document $doc -LeafMetaByRevision $metaMap -LeafRevisionByUpdateRevision $leafByRev

$ups = [ordered]@{{}}
foreach ($u in $doc.updates) {{
    $ups[$u.revisionId] = [ordered]@{{
        model = $u.servicingStackModel
        req   = $u.requiredServicingStackVersion
        hasProv = ($u.PSObject.Properties['providedServicingStackVersion'] -ne $null)
        prov  = $u.providedServicingStackVersion
        hasModel = ($u.PSObject.Properties['servicingStackModel'] -ne $null)
    }}
}}
[ordered]@{{ sel=$sel; populated=$summary.Populated; skipped=$summary.Skipped; ups=$ups }} | ConvertTo-Json -Depth 8 | Set-Content -Path {out_path} -Encoding utf8
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads(out_path.read_text(encoding="utf-8"))


def main() -> int:
    print("T18: wsusscn2 servicing-stack populate (pure halves)")
    print()

    r = TestResult()
    for f in ("leaf-2016-separate.xml", "leaf-2022-combined.xml", "leaf-2025-checkpoint.xml"):
        r.assert_true(f"00 fixture {f} present", (CBS_DIR / f).exists())

    print()
    print("Running PowerShell pure populate functions...")
    with tempfile.TemporaryDirectory() as tmp:
        out = run_powershell(Path(tmp) / "out.json")
    print()

    sel = out["sel"]
    ups = out["ups"]

    # ---- Select-OfflineSyncLcuLeafRevision ----
    r.assert_eq("01 single leaf -> that leaf", sel["single"], "99")
    r.assert_eq("02 multiple -> closest below bundle rev", sel["closest_below"], "45255708")
    r.assert_eq("03 none below -> greatest leaf rev", sel["none_below"], "300")
    r.assert_true("04 empty leaf list -> null", sel["empty"] in (None, ""))

    # ---- Update-ServicingStackFromMeta ----
    r.assert_eq("05 populated count == 3", out["populated"], 3)
    r.assert_eq("06 skipped count == 1 (leaf meta absent)", out["skipped"], 1)

    r.assert_eq("07 1001 -> separate", ups["1001"]["model"], "separate")
    r.assert_eq("08 1001 -> requiredSs 10.0.14393.7692", ups["1001"]["req"], "10.0.14393.7692")
    r.assert_eq("09 1002 -> combined", ups["1002"]["model"], "combined")
    r.assert_true("10 1002 -> requiredSs null", ups["1002"]["req"] in (None, ""))
    r.assert_eq("11 1003 -> checkpoint", ups["1003"]["model"], "checkpoint")
    r.assert_true("12 1003 -> requiredSs null", ups["1003"]["req"] in (None, ""))

    # providedServicingStackVersion is always set (to null) on populated updates
    r.assert_true("13 1001 providedServicingStackVersion present and null",
                  ups["1001"]["hasProv"] and ups["1001"]["prov"] in (None, ""))

    # ---- Skipped update untouched ----
    r.assert_true("14 1004 (no leaf meta) -> servicingStackModel NOT added",
                  not ups["1004"]["hasModel"])

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
