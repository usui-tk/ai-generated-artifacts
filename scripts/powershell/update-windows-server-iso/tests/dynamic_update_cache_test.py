#!/usr/bin/env python3
"""T8: Dynamic Update 36-month cache regression test.

Drives the PowerShell DU cache functions through three scenarios
defined in tests/fixtures/dynamic_update_cache/scenarios.json, which
were pre-computed in Python from a mix of live Microsoft Update
Catalog probes captured on 2026-05-26 (for the "happy path"
entries) and synthetic older months (to exercise the 36-month
window trim).

Three scenarios:
  1. server2025_live_then_setup_empty -- live SafeOs entries for
     2026-03/04/05 plus an empty-marker Setup entry; verifies
     Get-LatestDynamicUpdate picks the latest in-window SafeOs and
     returns null for Setup.
  2. server2022_with_old_synthetic    -- live Server 2022 DU
     entries plus three older synthetic entries (2022-12, 2022-06,
     2021-04); verifies Remove-DynamicUpdateOutsideWindow trims
     anything earlier than 2023-06 (the 36-month boundary at
     2026-05-26).
  3. upsert_same_key_latest_wins      -- two adds with the same
     (PatchMonth, DuType); verifies the second supersedes the
     first (idempotent upsert behaviour).

Plus two ad-hoc scenarios:
  4. cross-OS isolation        -- writes to Server2025 do not
     affect Server2022 and vice versa.
  5. missing-file empty cache  -- Get-DynamicUpdateCache returns
     a fresh empty cache when the file does not exist; never throws.

Run from the project root:

    python3 tests/dynamic_update_cache_test.py
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

FIXTURE_DIR  = TESTS_DIR / "fixtures" / "dynamic_update_cache"
SCRIPT_PATH  = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"

# Anchor the window deterministically at the day of fresh-data capture
# so the assertions do not drift with the wall clock.
FROZEN_NOW = "2026-05-26T00:00:00Z"


def load_scenarios() -> Dict[str, Any]:
    return json.loads((FIXTURE_DIR / "scenarios.json").read_text(encoding="utf-8"))


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
    scenarios_doc = load_scenarios()
    scenarios = scenarios_doc["scenarios"]

    print(f"Fixtures: {FIXTURE_DIR.relative_to(TESTS_DIR)}/scenarios.json")
    print(f"Window  : {scenarios_doc['window_months']} months anchored at {FROZEN_NOW}")
    print()

    passed = 0
    failed = 0

    tmp_root = pathlib.Path(tempfile.mkdtemp(prefix="t8-du-cache-"))
    try:
        with PSSession(SCRIPT_PATH) as ps:
            # --- Scenarios from the fixture ---
            for sc in scenarios:
                name = sc["name"]
                os_v = sc["os"]
                # Fresh temp dir per scenario
                scen_dir = tmp_root / name
                scen_dir.mkdir(parents=True, exist_ok=True)

                print(f"=== Scenario: {name} (os={os_v}) ===")

                for entry in sc["add_entries"]:
                    ps.invoke(
                        "Add-DynamicUpdateCacheEntry",
                        OsVersion=os_v,
                        DataDir=str(scen_dir),
                        Entry=entry,
                    )

                if "expected_entry_count_after_adds" in sc:
                    cache = ps.invoke(
                        "Get-DynamicUpdateCache",
                        OsVersion=os_v,
                        DataDir=str(scen_dir),
                    )
                    entries = cache.get("Entries") or []
                    if not isinstance(entries, list):
                        entries = [entries]
                    passed, failed = check(
                        "Entry count after adds (upsert)",
                        len(entries),
                        sc["expected_entry_count_after_adds"],
                        passed, failed,
                    )

                for q in sc["queries"]:
                    latest = ps.invoke(
                        "Get-LatestDynamicUpdate",
                        OsVersion=os_v,
                        DuType=q["du_type"],
                        Now=FROZEN_NOW,
                        DataDir=str(scen_dir),
                    )
                    if q["expected_latest_patch_month"] is None:
                        passed, failed = check(
                            f"latest [{q['du_type']}] is null",
                            latest is None,
                            True,
                            passed, failed,
                        )
                    else:
                        passed, failed = check(
                            f"latest [{q['du_type']}] PatchMonth",
                            latest.get("PatchMonth") if latest else None,
                            q["expected_latest_patch_month"],
                            passed, failed,
                        )
                        passed, failed = check(
                            f"latest [{q['du_type']}] KbId",
                            latest.get("KbId") if latest else None,
                            q["expected_latest_kb_id"],
                            passed, failed,
                        )

                trimmed = ps.invoke(
                    "Remove-DynamicUpdateOutsideWindow",
                    OsVersion=os_v,
                    Now=FROZEN_NOW,
                    DataDir=str(scen_dir),
                )
                trimmed_entries = trimmed.get("Entries") or []
                if not isinstance(trimmed_entries, list):
                    trimmed_entries = [trimmed_entries]
                kept_months = sorted({e["PatchMonth"] for e in trimmed_entries})
                passed, failed = check(
                    "Trim keeps (sorted unique PatchMonths)",
                    kept_months,
                    list(sc["trim_keeps"]),
                    passed, failed,
                )
                print()

            # --- Ad-hoc: cross-OS isolation ---
            print("=== Scenario: cross-OS isolation ===")
            iso_dir = tmp_root / "isolation"
            iso_dir.mkdir(parents=True, exist_ok=True)
            ps.invoke(
                "Add-DynamicUpdateCacheEntry",
                OsVersion="Server2025",
                DataDir=str(iso_dir),
                Entry={
                    "PatchMonth": "2026-05",
                    "DuType":     "DynamicUpdate.SafeOs",
                    "Success":    True,
                    "KbId":       "KB5087588",
                },
            )
            ps.invoke(
                "Add-DynamicUpdateCacheEntry",
                OsVersion="Server2022",
                DataDir=str(iso_dir),
                Entry={
                    "PatchMonth": "2026-05",
                    "DuType":     "DynamicUpdate.Bare",
                    "Success":    True,
                    "KbId":       "KB5087595",
                },
            )
            c25 = ps.invoke("Get-DynamicUpdateCache", OsVersion="Server2025", DataDir=str(iso_dir))
            c22 = ps.invoke("Get-DynamicUpdateCache", OsVersion="Server2022", DataDir=str(iso_dir))
            e25 = c25.get("Entries") or []
            e22 = c22.get("Entries") or []
            if not isinstance(e25, list): e25 = [e25]
            if not isinstance(e22, list): e22 = [e22]
            passed, failed = check("Server2025 entry count",  len(e25),                  1, passed, failed)
            passed, failed = check("Server2022 entry count",  len(e22),                  1, passed, failed)
            passed, failed = check("Server2025 KbId of [0]",  e25[0].get("KbId"), "KB5087588", passed, failed)
            passed, failed = check("Server2022 KbId of [0]",  e22[0].get("KbId"), "KB5087595", passed, failed)
            print()

            # --- Ad-hoc: missing file returns empty cache ---
            print("=== Scenario: missing-file empty cache ===")
            empty_dir = tmp_root / "empty"
            empty_dir.mkdir(parents=True, exist_ok=True)
            empty = ps.invoke("Get-DynamicUpdateCache", OsVersion="Server2025", DataDir=str(empty_dir))
            empty_entries = empty.get("Entries") or []
            if not isinstance(empty_entries, list): empty_entries = [empty_entries]
            passed, failed = check("Empty cache OsVersion",     empty.get("OsVersion"),     "Server2025", passed, failed)
            passed, failed = check("Empty cache Entries.Count", len(empty_entries),         0,            passed, failed)
            passed, failed = check("Empty cache WindowMonths",  empty.get("WindowMonths"),  36,           passed, failed)
            none_latest = ps.invoke(
                "Get-LatestDynamicUpdate",
                OsVersion="Server2025",
                DuType="DynamicUpdate.SafeOs",
                Now=FROZEN_NOW,
                DataDir=str(empty_dir),
            )
            passed, failed = check("Latest on empty cache is null", none_latest is None, True, passed, failed)

            # --- Ad-hoc: invalid PatchMonth rejected ---
            print()
            print("=== Scenario: PatchMonth validation ===")
            inv_dir = tmp_root / "invalid"
            inv_dir.mkdir(parents=True, exist_ok=True)
            try:
                ps.invoke(
                    "Add-DynamicUpdateCacheEntry",
                    OsVersion="Server2025",
                    DataDir=str(inv_dir),
                    Entry={"PatchMonth": "2026/05", "DuType": "DynamicUpdate.Setup"},
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
