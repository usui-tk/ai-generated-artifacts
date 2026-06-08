#!/usr/bin/env python3
"""T6: release-info parser regression test.

Validates that the PowerShell implementation of ConvertFrom-ReleaseInfoMarkdown
(plus helpers) produces the same row counts and per-OS breakdown that the
reference Python parser produced for the same input snapshot.

The reference fixture is at fixtures/release_info/release-info.json;
it was generated from snapshots/release_info/release-info-<date>.md
during the r06 Phase 2 investigation (since then the parser logic has
been promoted into Update-WindowsServerIso.ps1 and the legacy Python
scripts have been retired -- see docs/history/release-info-report.md
for the historical record). This test reads the same snapshot,
invokes the PowerShell parser via the harness, and compares the
result against the reference JSON.

Run from the project root:

    python3 tests/release_info_parser_test.py
"""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Any, Dict, List

TESTS_DIR = pathlib.Path(__file__).resolve().parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SNAPSHOT_DIR = TESTS_DIR / "snapshots" / "release_info"
FIXTURE_PATH = TESTS_DIR / "fixtures" / "release_info" / "release-info.json"
SCRIPT_PATH = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"


def find_latest_snapshot() -> pathlib.Path | None:
    if not SNAPSHOT_DIR.is_dir():
        return None
    candidates = sorted(SNAPSHOT_DIR.glob("release-info-*.md"))
    if not candidates:
        return None
    # Skip .meta.json files; only return the .md snapshot itself
    md = [c for c in candidates if c.suffix == ".md"]
    return md[-1] if md else None


def load_reference() -> Dict[str, Any]:
    return json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))


def run_powershell_parse(ps: PSSession, markdown_path: pathlib.Path) -> Dict[str, Any]:
    """Invoke ConvertFrom-ReleaseInfoMarkdown via the harness, returning
    a dict with MonthlyReleases / HotpatchCalendar arrays."""
    md = markdown_path.read_text(encoding="utf-8")
    return ps.invoke("ConvertFrom-ReleaseInfoMarkdown", Markdown=md)


def main() -> int:
    snapshot = find_latest_snapshot()
    if snapshot is None:
        print(f"  SKIP: no snapshot under {SNAPSHOT_DIR}")
        return 0

    if not FIXTURE_PATH.is_file():
        print(f"  SKIP: no reference fixture at {FIXTURE_PATH}")
        return 0

    reference = load_reference()
    print(f"Reference: {FIXTURE_PATH.relative_to(TESTS_DIR)}")
    print(f"Snapshot:  {snapshot.relative_to(TESTS_DIR)}")
    print()

    with PSSession(SCRIPT_PATH) as ps:
        parsed = run_powershell_parse(ps, snapshot)

    passed = 0
    failed = 0

    # Test 1: total monthly count
    monthly = parsed.get("MonthlyReleases") or []
    if not isinstance(monthly, list):
        monthly = [monthly]
    ref_monthly = int(reference["monthly_row_count"])
    if len(monthly) == ref_monthly:
        print(f"{PASS}  Monthly row count: {len(monthly)} (matches reference)")
        passed += 1
    else:
        print(f"{FAIL}  Monthly row count: got {len(monthly)}, expected {ref_monthly}")
        failed += 1

    # Test 2: total hotpatch count
    hotpatch = parsed.get("HotpatchCalendar") or []
    if not isinstance(hotpatch, list):
        hotpatch = [hotpatch]
    ref_hotpatch = int(reference["hotpatch_row_count"])
    if len(hotpatch) == ref_hotpatch:
        print(f"{PASS}  Hotpatch row count: {len(hotpatch)} (matches reference)")
        passed += 1
    else:
        print(f"{FAIL}  Hotpatch row count: got {len(hotpatch)}, expected {ref_hotpatch}")
        failed += 1

    # Test 3+: per-OS monthly counts
    counts: Dict[str, int] = {}
    for row in monthly:
        key = row.get("OsShortName", "")
        counts[key] = counts.get(key, 0) + 1
    for os_key, ref_count in reference["per_os_monthly_counts"].items():
        got = counts.get(os_key, 0)
        if got == ref_count:
            print(f"{PASS}  Monthly count for {os_key}: {got}")
            passed += 1
        else:
            print(f"{FAIL}  Monthly count for {os_key}: got {got}, expected {ref_count}")
            failed += 1

    # Test 7+: per-OS hotpatch counts
    hp_counts: Dict[str, int] = {}
    for row in hotpatch:
        key = row.get("OsShortName", "")
        hp_counts[key] = hp_counts.get(key, 0) + 1
    for os_key, ref_count in reference["per_os_hotpatch_counts"].items():
        got = hp_counts.get(os_key, 0)
        if got == ref_count:
            print(f"{PASS}  Hotpatch count for {os_key}: {got}")
            passed += 1
        else:
            print(f"{FAIL}  Hotpatch count for {os_key}: got {got}, expected {ref_count}")
            failed += 1

    # Test 9: at least one row carries a non-empty KbId for each OS
    # (sanity check that parse_kb_cell ported correctly)
    for os_key in reference["per_os_monthly_counts"]:
        nonzero = [r for r in monthly
                   if r.get("OsShortName") == os_key
                   and r.get("KbId", "").startswith("KB")]
        if nonzero:
            print(f"{PASS}  KbId parsing for {os_key}: {len(nonzero)} rows have a KbId")
            passed += 1
        else:
            print(f"{FAIL}  KbId parsing for {os_key}: no rows had a KbId")
            failed += 1

    # Test 13: at least one row carries IsBaseline=true (sanity check
    # the hotpatch parser tagged baselines correctly)
    baselines = [r for r in hotpatch if r.get("IsBaseline")]
    if baselines:
        print(f"{PASS}  Hotpatch baseline detection: {len(baselines)} baseline rows")
        passed += 1
    else:
        print(f"{FAIL}  Hotpatch baseline detection: 0 baseline rows")
        failed += 1

    print()
    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
