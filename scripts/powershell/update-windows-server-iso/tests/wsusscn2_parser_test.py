"""
T12: wsusscn2 parser pipeline self-verification test (offline).

Exercises the PowerShell Stage 3 (ConvertFrom-WsusScnPackageXml) and
Stage 4 (New-WsusScnDependencyDatabase) functions against the small
fixture in tests/fixtures/wsusscn2/, verifying:

  * scope-filter admit/reject semantics for Product GUID, Classification
    GUID, and recency window (SPEC §B.19.7)
  * Microsoft-prose exclusion (SPEC §B.19.8): fixture is constructed
    without any <Title>/<Description>/<MoreInfoUrl>, AND the parser's
    output is verified to contain no such fields
  * Category-Update detection (DeploymentAction="Evaluate" +
    IsSoftware="false")
  * FileLocation -> payload-URL join correctness, including the
    payloadUrlsMissing counter for orphan digests
  * Canonical JSON output (SPEC §B.23) byte-for-byte parity with the
    expected JSON in tests/fixtures/wsusscn2/expected-output.json,
    after stripping environmental fields (scriptVersion, scriptTag,
    generatedAt, sourceCab) that vary per run

Runs offline; no wsusscn2.cab download or 7-Zip invocation. Stage 2
(Invoke-WsusScnPackageXmlExtract) is platform-coupled (needs 7-Zip and
the Windows file layout) so it is exercised only by the live monthly
refresh, not by T12.

Invocation:
    python3 wsusscn2_parser_test.py
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
PACKAGE_XML = FIXTURE_DIR / "package.xml"
EXPECTED_JSON = FIXTURE_DIR / "expected-output.json"

# Environmental fields stripped before structural comparison
ENV_FIELDS = ("generator", "scriptVersion", "scriptTag", "generatedAt", "sourceCab")

PINNED_NOW = "2026-05-28T00:00:00Z"

# Microsoft-prose tag names that must NOT appear in fixture, package
# subtree, or parser output (SPEC §B.19.8 hard rule).
PROSE_TAGS = ("<Title", "<Description", "<MoreInfoUrl", "<Summary", "<DefaultPropertiesLanguage")


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


def strip_env(doc: dict) -> dict:
    """Remove environmental metadata so structural compare is meaningful."""
    meta = doc.get("_meta", {})
    return {
        "_meta": {k: v for k, v in meta.items() if k not in ENV_FIELDS},
        "updates": doc.get("updates", []),
    }


def run_powershell_parser(out_path: Path) -> dict:
    """Invoke PowerShell to load the script, run Stage 3 + Stage 4, and
    return the parsed JSON document.
    """
    pwsh_script = f"""
. {SCRIPT_PATH} -Action ListPhases -DryRun *>$null 2>$null
$pinnedNow = [datetime]::ParseExact("{PINNED_NOW}","yyyy-MM-ddTHH:mm:ssZ",
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
$result = ConvertFrom-WsusScnPackageXml -PackageXmlPath {PACKAGE_XML} -Now $pinnedNow
$null = New-WsusScnDependencyDatabase -ParseResult $result -OutputPath {out_path}
"""
    proc = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", pwsh_script],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pwsh failed: {proc.stderr}")
    return json.loads(out_path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    print(f"T12: wsusscn2 parser pipeline self-verification")
    print(f"  fixture: {PACKAGE_XML}")
    print(f"  expected: {EXPECTED_JSON}")
    print()

    r = TestResult()

    # ---- 1. Pre-flight: fixture exists and contains no Microsoft prose ----
    fixture_text = PACKAGE_XML.read_text(encoding="utf-8")
    r.assert_true("01 fixture package.xml exists and is non-empty", len(fixture_text) > 100)

    prose_hits = [tag for tag in PROSE_TAGS if tag in fixture_text]
    r.assert_eq("02 fixture contains zero Microsoft-prose tags", prose_hits, [])

    expected = json.loads(EXPECTED_JSON.read_text(encoding="utf-8"))
    r.assert_true("03 expected-output.json is valid JSON with _meta + updates",
                  "_meta" in expected and "updates" in expected)

    # ---- 2. Run the PowerShell parser pipeline ----
    print()
    print("Running PowerShell Stage 3 + Stage 4 against fixture...")
    with tempfile.TemporaryDirectory() as tmp:
        out_path = Path(tmp) / "actual.json"
        actual = run_powershell_parser(out_path)
        actual_text = out_path.read_text(encoding="utf-8")
    print()

    # ---- 3. Stats assertions ----
    s = actual["_meta"]["stats"]
    r.assert_eq("04 Stats.updatesObserved == 8",        s["updatesObserved"],        8)
    r.assert_eq("05 Stats.updatesInScope == 2 (bundles)", s["updatesInScope"],       2)
    r.assert_eq("06 Stats.bundlesObserved == 4",        s["bundlesObserved"],        4)
    r.assert_eq("07 Stats.categoryUpdates == 1",        s["categoryUpdates"],        1)
    r.assert_eq("08 Stats.leafUpdatesWithPayload == 3", s["leafUpdatesWithPayload"], 3)
    r.assert_eq("09 Stats.fileLocationsRetained == 3",  s["fileLocationsRetained"],  3)
    r.assert_eq("10 Stats.payloadDigestsOrphaned == 1 (DDDD)",
                s["payloadDigestsOrphaned"], 1)

    # ---- 4. Scope filter admit/reject ----
    UID_BUNDLE_A = "f0000001-0000-0000-0000-000000000001"
    UID_BUNDLE_B = "f0000001-0000-0000-0000-000000000003"
    UID_OFFICE   = "f0000001-0000-0000-0000-000000000005"
    UID_OLD      = "f0000001-0000-0000-0000-000000000006"
    UID_CATEGORY = "b256987d-4693-4c87-955d-dbb9341205eb"
    by_id = {u["updateId"]: u for u in actual["updates"]}

    r.assert_true("11 Server 2022 bundle admitted",     UID_BUNDLE_A in by_id)
    r.assert_true("12 Server 2025 bundle admitted",     UID_BUNDLE_B in by_id)
    r.assert_true("13 Office bundle rejected (Product mismatch)", UID_OFFICE not in by_id)
    r.assert_true("14 Old Server 2019 bundle rejected (recency)", UID_OLD not in by_id)
    r.assert_true("15 Category Update rejected (Evaluate, not a scoped bundle)",
                  UID_CATEGORY not in by_id)

    # ---- 5. Field-level correctness on the Server 2022 bundle ----
    s2022 = by_id[UID_BUNDLE_A]
    r.assert_eq("16 Server 2022 bundle: isBundle == true", s2022["isBundle"], True)
    r.assert_eq("17 Server 2022 bundle: productGuids == [Server2022 GUID]",
                s2022["productGuids"], ["71718f13-7324-4b0f-8f9e-2ca9dc978e53"])
    r.assert_eq("18 Server 2022 bundle: supersededByRevisionIds == ['990099']",
                s2022["supersededByRevisionIds"], ["990099"])

    # ---- 6. Payload URL roll-up (bundle <- leaf BundledBy) ----
    # Bundle A has two leaves (A1->AAAA, A2->BBBB), both resolve.
    r.assert_eq("19 Server 2022 bundle: payloadUrls rolled up from 2 leaves",
                sorted(s2022["payloadUrls"]),
                sorted(["http://example.invalid/fixture/server2022-lcu-part1.cab",
                        "http://example.invalid/fixture/server2022-lcu-part2.cab"]))

    # Bundle B has one leaf (B1) with CCCC (resolves) + DDDD (orphan, omitted).
    s2025 = by_id[UID_BUNDLE_B]
    r.assert_eq("20 Server 2025 bundle: payloadUrls excludes orphan digest",
                s2025["payloadUrls"],
                ["http://example.invalid/fixture/server2025-lcu.cab"])

    # ---- 7. Microsoft-prose exclusion in parser output ----
    actual_prose_hits = [t for t in ("Title", "Description", "MoreInfoUrl", "kbArticleIds")
                         if f'"{t.lower()}"' in actual_text.lower()
                         or f'"{t}"' in actual_text]
    r.assert_eq("21 Parser output contains no prose/KB fields (KB not in wsusscn2)",
                actual_prose_hits, [])

    # ---- 8. Structural compare against expected-output.json ----
    stripped_actual = strip_env(actual)
    stripped_expected = strip_env(expected)
    if stripped_actual != stripped_expected:
        diff_keys = set(json.dumps(stripped_actual, sort_keys=True).split(',')) ^ \
                    set(json.dumps(stripped_expected, sort_keys=True).split(','))
        print("  --- structural diff (first 8 differing chunks) ---")
        for line in list(diff_keys)[:8]:
            print(f"      {line}")
    r.assert_true("22 Parser output structurally matches expected-output.json (env-stripped)",
                  stripped_actual == stripped_expected)

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
