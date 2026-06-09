"""
T21: SSU -> LCU prerequisite end-to-end pipeline test (offline, Linux).

Reproduces the real-world Server 2016 0x800f0823
(CBS_E_NEW_SERVICING_STACK_REQUIRED) failure entirely on Linux, without a
Windows host or DISM. An LCU (catalogued as KB5087537) requires a separate
servicing-stack update (SSU, KB5088064) as a prerequisite; when the provided
servicing stack predates the SSU, the LCU install fails on a real machine.
The servicing-readiness gate is supposed to PREDICT that failure (SsTooOld);
this test drives the whole chain end-to-end and asserts it does.

Pipeline exercised (all real PowerShell functions, run under pwsh on Linux):

  1. build_ssu_prereq_package_xml()        committed fixture freshness guard
  2. ConvertFrom-OfflineSyncPackage         Stage 3 parse of the package.xml
  3. New-ServicingDependencyDatabase        Stage 4 Layer 2 DB serialisation
  4. Update-ServicingStackFromMeta          M1 servicing-stack populate, using
                                            the 2016-separate CBS leaf fixture
                                            (requiredSs 10.0.14393.7692)
  5. Test-PatchServicingReadinessFromGraph  the P06 readiness gate

Assertions:
  * the parsed DB carries the SSU + LCU bundles with the KB in the payload URL;
  * SS populate sets the LCU's requiredServicingStackVersion / separate model;
  * provided SS < required (RTM 10.0.14393.0) -> SsTooOld / OverallStatus Fail
    (this is the offline equivalent of the on-host 0x800f0823);
  * provided SS >= required (10.0.14393.7692) -> Pass / OverallStatus Pass.

The cab/7-Zip extraction wrapper is NOT exercised (covered by live monthly CI);
all inputs here are text/object, so the chain is fully deterministic offline.

Invocation:
    python3 servicing_dependency_ssu_prereq_pipeline_test.py
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
SUBPROJECT_DIR = TEST_DIR.parent
SCRIPT_PATH = SUBPROJECT_DIR / "Update-WindowsServerIso.ps1"
FIXTURE_DIR = TEST_DIR / "fixtures" / "servicing-dependency"
PACKAGE_XML = FIXTURE_DIR / "ssu-prereq" / "package.xml"
CBS_LEAF_2016 = FIXTURE_DIR / "cbs" / "leaf-2016-separate.xml"

# The provided servicing stack of a stock Server 2016 image (RTM) and the
# stack the SSU (KB5088064) delivers, as encoded in the 2016-separate CBS leaf.
PROVIDED_SS_RTM = "10.0.14393.0"
REQUIRED_SS = "10.0.14393.7692"


def _load_builder():
    """Import the fixture builder by file path (tests/ is not a package)."""
    spec = importlib.util.spec_from_file_location(
        "ssu_fixture_builder", TEST_DIR / "common" / "servicing_dependency_fixture_builder.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


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
    """Run the full parse -> DB -> SS-populate -> readiness chain under pwsh."""
    db_path = out_path / "db.json"
    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null

$result = ConvertFrom-OfflineSyncPackage -PackageXmlPath '{PACKAGE_XML}' -Now '2026-05-28T00:00:00Z'
$null = New-ServicingDependencyDatabase -ParseResult $result -OutputPath '{db_path}'
$doc = Get-Content -Raw '{db_path}' | ConvertFrom-Json

# Servicing-stack populate: the LCU bundle (rev 991120) maps to its leaf
# (rev 991104), whose CBS metadata is the 2016-separate fixture leaf. The SSU
# bundle has no leaf meta supplied and is therefore left untouched.
$leafByRev = @{{ '991120' = '991104' }}
$metaMap   = @{{ '991104' = (Get-Content -Raw '{CBS_LEAF_2016}') }}
$summary = Update-ServicingStackFromMeta -Document $doc -LeafMetaByRevision $metaMap -LeafRevisionByUpdateRevision $leafByRev

$lcu = $doc.updates | Where-Object {{ $_.revisionId -eq '991120' }}
$ssu = $doc.updates | Where-Object {{ $_.revisionId -eq '991110' }}

# Persist the populated DB so the readiness gate reads the SS fields.
$doc | ConvertTo-Json -Depth 32 | Set-Content -Path '{db_path}' -Encoding utf8

$patch = @([pscustomobject]@{{ KbId = 'KB5087537'; OsKey = 'S2016' }})
$tooOld = Test-PatchServicingReadinessFromGraph -ResolvedPatches $patch -DatabasePath '{db_path}' -WimMountState ([pscustomobject]@{{ ProvidedServicingStackVersion = '{PROVIDED_SS_RTM}' }})
$ok     = Test-PatchServicingReadinessFromGraph -ResolvedPatches $patch -DatabasePath '{db_path}' -PolicyOverride @{{ S2016 = '{REQUIRED_SS}' }}

function _vmap($r) {{
    $m = [ordered]@{{}}
    foreach ($v in $r.PatchVerdicts) {{
        $m[$v.KbId] = [ordered]@{{ verdict = $v.Verdict; model = $v.ServicingStackModel; req = $v.RequiredServicingStackVersion; prov = $v.ProvidedServicingStackVersion }}
    }}
    return $m
}}

[ordered]@{{
    parsedUrls   = @($doc.updates | ForEach-Object {{ @($_.payloadUrls) }})
    parsedRevs   = @($doc.updates | ForEach-Object {{ $_.revisionId }})
    populated    = $summary.Populated
    skipped      = $summary.Skipped
    lcuModel     = $lcu.servicingStackModel
    lcuReq       = $lcu.requiredServicingStackVersion
    ssuModel     = $ssu.servicingStackModel
    tooOld       = [ordered]@{{ available = $tooOld.Available; overall = $tooOld.OverallStatus; verdicts = (_vmap $tooOld) }}
    ok           = [ordered]@{{ available = $ok.Available; overall = $ok.OverallStatus; verdicts = (_vmap $ok) }}
}} | ConvertTo-Json -Depth 10 | Set-Content -Path '{out_path / "result.json"}' -Encoding utf8
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=180,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads((out_path / "result.json").read_text(encoding="utf-8"))


def main() -> int:
    print("T21: SSU -> LCU prerequisite end-to-end pipeline (0x800f0823 prediction)")
    print()

    r = TestResult()

    # ---- 00 fixtures present + builder freshness guard --------------------
    r.assert_true("00 fixture package.xml present", PACKAGE_XML.exists())
    r.assert_true("01 CBS leaf-2016-separate.xml present", CBS_LEAF_2016.exists())

    builder = _load_builder()
    expected_xml = builder.build_ssu_prereq_package_xml()
    committed_xml = PACKAGE_XML.read_text(encoding="utf-8")
    r.assert_true(
        "02 committed package.xml matches build_ssu_prereq_package_xml()",
        committed_xml == expected_xml,
        "fixture drifted from builder; regenerate via "
        "`python3 -m tests.common.servicing_dependency_fixture_builder`",
    )

    print()
    print("Running PowerShell parse -> DB -> SS-populate -> readiness...")
    with tempfile.TemporaryDirectory() as tmp:
        out = run_powershell(Path(tmp))
    print()

    # ---- Stage 3/4 parse: both Server 2016 bundles in scope, KB in URL ----
    revs = [str(x) for x in out["parsedRevs"]]
    flat_urls = " ".join(
        u for sub in out["parsedUrls"] for u in (sub if isinstance(sub, list) else [sub])
    ).lower()
    r.assert_true("03 SSU bundle (rev 991110) parsed in scope", "991110" in revs)
    r.assert_true("04 LCU bundle (rev 991120) parsed in scope", "991120" in revs)
    r.assert_eq("05 exactly two in-scope bundles", len(revs), 2)
    r.assert_true("06 LCU payload URL carries kb5087537", "kb5087537" in flat_urls)
    r.assert_true("07 SSU payload URL carries kb5088064", "kb5088064" in flat_urls)

    # ---- M1 servicing-stack populate -------------------------------------
    r.assert_eq("08 populated count == 1 (LCU only)", out["populated"], 1)
    r.assert_eq("09 skipped count == 1 (SSU has no leaf meta)", out["skipped"], 1)
    r.assert_eq("10 LCU servicingStackModel == separate", out["lcuModel"], "separate")
    r.assert_eq("11 LCU requiredServicingStackVersion populated", out["lcuReq"], REQUIRED_SS)

    # ---- readiness gate: the 0x800f0823 prediction -----------------------
    too_old = out["tooOld"]
    v_too = too_old["verdicts"]["KB5087537"]
    r.assert_true("12 readiness available (DB present + SS known)", too_old["available"])
    r.assert_eq("13 provided RTM SS -> verdict SsTooOld", v_too["verdict"], "SsTooOld")
    r.assert_eq("14 provided RTM SS -> OverallStatus Fail (predicts 0x800f0823)",
                too_old["overall"], "Fail")
    r.assert_eq("15 verdict carries provided SS from WimMountState", v_too["prov"], PROVIDED_SS_RTM)
    r.assert_eq("16 verdict carries required SS", v_too["req"], REQUIRED_SS)

    ok = out["ok"]
    v_ok = ok["verdicts"]["KB5087537"]
    r.assert_eq("17 provided adequate SS -> verdict Pass", v_ok["verdict"], "Pass")
    r.assert_eq("18 provided adequate SS -> OverallStatus Pass", ok["overall"], "Pass")
    r.assert_eq("19 verdict carries provided SS from PolicyOverride", v_ok["prov"], REQUIRED_SS)

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
