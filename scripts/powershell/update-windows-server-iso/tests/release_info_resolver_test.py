#!/usr/bin/env python3
"""T10: Resolve-PatchSetFromReleaseInfo discovery-phase regression test.

Validates `Get-PatchSetFromReleaseInfoDiscovery` -- the offline,
pure-cache half of the new r07.0 Step 2b refresher path -- against
synthetic caches built from the fresh 2026-05-26 data captures.

The test deliberately exercises ONLY the cache-reading discovery
function, not the orchestrator `Resolve-PatchSetFromReleaseInfo`
itself (which performs live Catalog URL resolution and therefore
requires network I/O). The URL-resolver narrowing layer is already
covered by T9.

For each scenario the harness:
  1. Writes the scenario's `release_info_cache` and `dotnet_cu_cache`
     to a temp -DataDir.
  2. Calls `Add-DynamicUpdateCacheEntry` for each DU entry in the
     scenario so the per-OS DU cache files exist in the same dir.
  3. Calls `Get-PatchSetFromReleaseInfoDiscovery` and asserts the
     resulting (Type, KbId) pairs match the scenario's expectation.

Plus two ad-hoc checks:
  - Missing-caches scenario returns 0 records (defensive default).
  - Invalid PatchMonth ("2026/05") is rejected with a clear error.

Run from the project root:

    python3 tests/release_info_resolver_test.py
"""
from __future__ import annotations

import json
import pathlib
import shutil
import sys
import tempfile
from typing import Any, Dict, List

TESTS_DIR = pathlib.Path(__file__).resolve().parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

FIXTURE_DIR  = TESTS_DIR / "fixtures" / "release_info_resolver"
SCRIPT_PATH  = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"


def write_cache(path: pathlib.Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def normalize_list(value: Any) -> List[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def check(label: str, got: Any, expected: Any, p: int, f: int) -> tuple[int, int]:
    if got == expected:
        print(f"{PASS}  {label}: {expected}")
        return p + 1, f
    print(f"{FAIL}  {label}:")
    print(f"        got      = {got!r}")
    print(f"        expected = {expected!r}")
    return p, f + 1


def main() -> int:
    if not FIXTURE_DIR.is_dir():
        print(f"  SKIP: missing fixture dir {FIXTURE_DIR}")
        return 0
    scenarios_path = FIXTURE_DIR / "scenarios.json"
    if not scenarios_path.is_file():
        print(f"  SKIP: missing {scenarios_path}")
        return 0
    fixture = json.loads(scenarios_path.read_text(encoding="utf-8"))

    print(f"Fixture: {scenarios_path.relative_to(TESTS_DIR)}")
    print(f"  release_info_cache : {len(fixture['release_info_cache']['MonthlyReleases'])} monthly rows")
    print(f"  dotnet_cu_cache    : {len(fixture['dotnet_cu_cache']['Months'])} month entries")
    print(f"  du_entries_by_os   : {sum(len(v) for v in fixture['du_entries_by_os'].values())} DU entries across {len(fixture['du_entries_by_os'])} OSes")
    print(f"  queries            : {len(fixture['queries'])} discovery queries")
    print()

    passed = 0
    failed = 0

    tmp_root = pathlib.Path(tempfile.mkdtemp(prefix="t10-release-info-resolver-"))
    try:
        with PSSession(SCRIPT_PATH) as ps:
            # --- Phase 1: populate shared caches for all queries ---
            shared_dir = tmp_root / "shared"
            shared_dir.mkdir(parents=True)
            write_cache(shared_dir / "cache-release-info.json", fixture["release_info_cache"])
            write_cache(shared_dir / "cache-dotnet-cu.json",    fixture["dotnet_cu_cache"])
            for os_key, entries in fixture["du_entries_by_os"].items():
                for entry in entries:
                    ps.invoke(
                        "Add-DynamicUpdateCacheEntry",
                        OsVersion=os_key,
                        DataDir=str(shared_dir),
                        Entry=entry,
                    )

            # --- Phase 2: run each discovery query ---
            for q in fixture["queries"]:
                print(f"=== Discovery: {q['os']} {q['patch_month']} -- {q['description']} ===")
                records = normalize_list(
                    ps.invoke(
                        "Get-PatchSetFromReleaseInfoDiscovery",
                        OsVersion=q["os"],
                        PatchMonth=q["patch_month"],
                        DataDir=str(shared_dir),
                    )
                )
                got_types = sorted(r.get("Type") for r in records)
                got_kbs   = sorted(r.get("KbId") for r in records)
                exp_types = sorted(q["expected_types"])
                exp_kbs   = sorted(q["expected_kbs"])
                passed, failed = check(
                    f"{q['os']} {q['patch_month']} record count",
                    len(records), len(exp_types), passed, failed,
                )
                passed, failed = check(
                    f"{q['os']} {q['patch_month']} Types (sorted)",
                    got_types, exp_types, passed, failed,
                )
                passed, failed = check(
                    f"{q['os']} {q['patch_month']} KbIds (sorted)",
                    got_kbs, exp_kbs, passed, failed,
                )
                # SourceCache routing sanity: every LCU comes from release-info,
                # every DotNet.Runtime from dotnet-cu, every DU from dynamic-update.
                expected_sources = {
                    "LCU": "release-info",
                    "DotNet.Runtime": "dotnet-cu",
                    "DynamicUpdate.Setup": "dynamic-update",
                    "DynamicUpdate.SafeOs": "dynamic-update",
                }
                wrong_source = []
                for r in records:
                    exp_src = expected_sources.get(r.get("Type"))
                    if exp_src and r.get("SourceCache") != exp_src:
                        wrong_source.append((r.get("Type"), r.get("SourceCache"), exp_src))
                if not wrong_source:
                    passed, failed = check(
                        f"{q['os']} {q['patch_month']} SourceCache routing",
                        "all-correct", "all-correct", passed, failed,
                    )
                else:
                    print(f"{FAIL}  {q['os']} {q['patch_month']} SourceCache routing: {wrong_source}")
                    failed += 1
                print()

            # --- Phase 3: missing-cache defensive default ---
            print("=== Defensive: empty data dir returns 0 records ===")
            empty_dir = tmp_root / "empty"
            empty_dir.mkdir()
            records_empty = normalize_list(
                ps.invoke(
                    "Get-PatchSetFromReleaseInfoDiscovery",
                    OsVersion="Server2025",
                    PatchMonth="2026-05",
                    DataDir=str(empty_dir),
                )
            )
            passed, failed = check(
                "Empty data dir -> 0 records",
                len(records_empty), 0, passed, failed,
            )

            # --- Phase 4: invalid PatchMonth rejected ---
            print()
            print("=== Defensive: invalid PatchMonth is rejected ===")
            try:
                ps.invoke(
                    "Get-PatchSetFromReleaseInfoDiscovery",
                    OsVersion="Server2025",
                    PatchMonth="2026/05",
                    DataDir=str(shared_dir),
                )
                print(f"{FAIL}  Invalid PatchMonth was accepted (should have thrown)")
                failed += 1
            except Exception as exc:
                if "PatchMonth" in str(exc):
                    print(f"{PASS}  Invalid PatchMonth correctly rejected")
                    passed += 1
                else:
                    print(f"{FAIL}  Threw unexpected error: {exc}")
                    failed += 1
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)

    print()
    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
