"""
T20: Removed-live-WUA static guard (offline).

r11.19 retired P06's live Windows Update Agent (WUA) offline scan and
repurposed P06 into a single, default-ON, blocking servicing-readiness
gate against the wsusscn2 Layer 2 database. This static guard scans the
script text and fails if any of the removed symbols are reintroduced, or
if the new gate loses its blocking wiring. It complements T16
(servicing_dependency_readiness_verdict_test.py), which exercises the
verdict -> block mapping at the Test-PatchServicingReadinessFromGraph
level (block-on-absence, block-on-Fail, warn-on-Superseded, pass).

Pure text scan: no pwsh, no network, no fixtures.

Invocation:
    python3 removed_live_wua_guard_test.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
SCRIPT_PATH = TEST_DIR.parent / "Update-WindowsServerIso.ps1"

# Symbols retired in r11.19 (P06 Stage 1 / live-WUA only).
REMOVED_FUNCTIONS = (
    "Invoke-WuaOfflineScan",
    "Compare-PatchSetVsWuaScan",
    "Export-PatchValidationReport",
)
REMOVED_PARAMS = (
    "IgnorePatchValidation",
    "EnableDependencyCheck",
)
# Diagnostic report files only ever written by Export-PatchValidationReport.
REMOVED_DIAG_FILES = (
    "validation_summary.json",
    "validation_detail.csv",
    "wsusscn2_scan_raw.json",
    "dependency_graph.json",
)


class TestResult:
    def __init__(self):
        self.passed = 0
        self.failed = []

    def check(self, name, cond, detail=""):
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


def main() -> int:
    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")
    r = TestResult()

    # 1. Removed functions: no definition and no reference anywhere.
    for fn in REMOVED_FUNCTIONS:
        r.check(
            f"function definition absent: {fn}",
            f"function {fn} " not in text,
            "definition still present",
        )
        r.check(
            f"no reference at all: {fn}",
            text.count(fn) == 0,
            f"{text.count(fn)} occurrence(s) remain",
        )

    # 2. Removed parameters: no decl and no $-reference anywhere.
    for p in REMOVED_PARAMS:
        r.check(
            f"parameter absent: -{p}",
            f"${p}" not in text,
            f"{text.count('$' + p)} reference(s) remain",
        )

    # 3. Old phase function name fully replaced.
    r.check(
        "old phase function name absent: Invoke-PlanPhase06_ValidatePatchSet",
        "Invoke-PlanPhase06_ValidatePatchSet" not in text,
        "old name still present",
    )

    # 4. New phase function defined exactly once.
    r.check(
        "new phase function defined once: Invoke-PlanPhase06_ValidatePatchServicing",
        text.count("function Invoke-PlanPhase06_ValidatePatchServicing {") == 1,
        "expected exactly one definition",
    )

    # 5. PhaseRegistry P06 row points at the new name + phase name.
    p06_rows = [ln for ln in text.splitlines() if "Id='P06'" in ln]
    r.check("PhaseRegistry has exactly one P06 row", len(p06_rows) == 1,
            f"found {len(p06_rows)}")
    if len(p06_rows) == 1:
        row = p06_rows[0]
        r.check("P06 row Name='ValidatePatchServicing'",
                "Name='ValidatePatchServicing'" in row, row.strip())
        r.check("P06 row Func='Invoke-PlanPhase06_ValidatePatchServicing'",
                "Func='Invoke-PlanPhase06_ValidatePatchServicing'" in row, row.strip())

    # 6. New gate is actually wired and blocking (not a no-op).
    r.check("gate calls Test-PatchServicingReadinessFromGraph",
            "Test-PatchServicingReadinessFromGraph -ResolvedPatches" in text,
            "readiness call missing")
    r.check("gate sources $Script:ResolvedPatches",
            "$Script:ResolvedPatches" in text,
            "resolved-patches source missing")
    r.check("gate blocks on Layer 2 absence (-not $readiness.Available throw path)",
            text.count("-not $readiness.Available") == 1,
            "absence block path missing or duplicated")
    r.check("gate blocks on OverallStatus Fail",
            text.count("$readiness.OverallStatus -eq 'Fail'") == 1,
            "Fail block path missing or duplicated")

    # 7. Diagnostic report files no longer emitted by the script.
    for f in REMOVED_DIAG_FILES:
        r.check(f"diag report file no longer emitted: {f}",
                text.count(f) == 0,
                f"{text.count(f)} occurrence(s) remain")

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
