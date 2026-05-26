#!/usr/bin/env python3
"""T7: .NET CU parser regression test.

Validates that the PowerShell implementation of
ConvertFrom-DotNetCuIndexMarkdown and ConvertFrom-DotNetCuMarkdown
produces the same parsed output as the Python reference parser when
fed the snapshots under tests/snapshots/dotnet_cu/.

The reference data was captured live from learn.microsoft.com on
2026-05-26 and defines the EXPECTED behavior. (Earlier r06 Phase 2
PoC snapshots reflected an older page structure -- index entries
had the date inside the link brackets; the "Summary tables" section
appeared before "Known issues" rather than after -- and were
superseded once the live captures landed. The historical PoC
investigation is recorded in docs/history/dotnet-cu-report.md.)

Run from the project root:

    python3 tests/dotnet_cu_parser_test.py
"""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Any, Dict, List

TESTS_DIR = pathlib.Path(__file__).resolve().parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SNAPSHOT_DIR = TESTS_DIR / "snapshots" / "dotnet_cu"
FIXTURE_DIR  = TESTS_DIR / "fixtures" / "dotnet_cu"
SCRIPT_PATH  = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"


def load_json(path: pathlib.Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_list(value: Any) -> List[Any]:
    """PowerShell ConvertTo-Json may serialize a single-element array as a
    bare object. Wrap into a list if needed."""
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def call_index_parser(ps: PSSession, md_path: pathlib.Path) -> Dict[str, Any]:
    md = md_path.read_text(encoding="utf-8")
    return ps.invoke("ConvertFrom-DotNetCuIndexMarkdown", Markdown=md)


def call_month_parser(ps: PSSession, md_path: pathlib.Path) -> Dict[str, Any]:
    md = md_path.read_text(encoding="utf-8")
    return ps.invoke("ConvertFrom-DotNetCuMarkdown", Markdown=md)


def call_os_label_mapper(ps: PSSession, label: str) -> str:
    return ps.invoke("ConvertFrom-DotNetCuOsLabel", Label=label) or ""


def check(label: str, got: Any, expected: Any, passed_count: int, failed_count: int) -> tuple[int, int]:
    if got == expected:
        print(f"{PASS}  {label}: {expected}")
        return passed_count + 1, failed_count
    print(f"{FAIL}  {label}:")
    print(f"        got      = {got!r}")
    print(f"        expected = {expected!r}")
    return passed_count, failed_count + 1


def main() -> int:
    # Bail out gracefully if assets are missing (e.g. partial checkout).
    if not SNAPSHOT_DIR.is_dir():
        print(f"  SKIP: missing snapshot dir {SNAPSHOT_DIR}")
        return 0
    if not FIXTURE_DIR.is_dir():
        print(f"  SKIP: missing fixture dir {FIXTURE_DIR}")
        return 0

    index_snapshot = SNAPSHOT_DIR / "index.md"
    m05_snapshot   = SNAPSHOT_DIR / "2026-05-12-may-cumulative-update.md"
    m04_snapshot   = SNAPSHOT_DIR / "2026-04-14-april-cumulative-update.md"
    index_ref      = FIXTURE_DIR  / "index.json"
    m05_ref        = FIXTURE_DIR  / "month-2026-05.json"
    m04_ref        = FIXTURE_DIR  / "month-2026-04.json"

    for p in (index_snapshot, m05_snapshot, m04_snapshot, index_ref, m05_ref, m04_ref):
        if not p.is_file():
            print(f"  SKIP: missing required asset {p}")
            return 0

    ref_index = load_json(index_ref)
    ref_m05   = load_json(m05_ref)
    ref_m04   = load_json(m04_ref)

    print(f"Reference dir : {FIXTURE_DIR.relative_to(TESTS_DIR)}")
    print(f"Snapshot  dir : {SNAPSHOT_DIR.relative_to(TESTS_DIR)}")
    print()

    passed = 0
    failed = 0

    with PSSession(SCRIPT_PATH) as ps:
        parsed_index = call_index_parser(ps, index_snapshot)
        parsed_m05   = call_month_parser(ps, m05_snapshot)
        parsed_m04   = call_month_parser(ps, m04_snapshot)
        # OS-label mapper spot checks (one production-scope, one non-scope).
        ol_2022 = call_os_label_mapper(ps, "Windows Server 2022")
        ol_2019 = call_os_label_mapper(ps, "Windows 10 1809 and Windows Server 2019")
        ol_none = call_os_label_mapper(ps, "Some Unrelated Label")

    # ---- Index parser checks ----
    print("Index parser:")

    passed, failed = check(
        "Index EntryCount",
        parsed_index.get("EntryCount"),
        ref_index["entry_count"],
        passed, failed,
    )
    passed, failed = check(
        "Index EarliestDate",
        parsed_index.get("EarliestDate"),
        ref_index["earliest_date"],
        passed, failed,
    )
    passed, failed = check(
        "Index LatestDate",
        parsed_index.get("LatestDate"),
        ref_index["latest_date"],
        passed, failed,
    )
    passed, failed = check(
        "Index Kinds (sorted)",
        sorted(normalize_list(parsed_index.get("Kinds"))),
        sorted(ref_index["kinds"]),
        passed, failed,
    )

    # Entry-level deep equality. PowerShell PascalCase -> snake_case mapping.
    ps_entries = normalize_list(parsed_index.get("Entries"))
    ref_entries = ref_index["entries"]
    if len(ps_entries) == len(ref_entries):
        mism = []
        for i, (pe, re_) in enumerate(zip(ps_entries, ref_entries)):
            if pe.get("DateText")    != re_["date_text"]:    mism.append((i, "date_text"))
            if pe.get("Date")        != re_["date"]:         mism.append((i, "date"))
            if pe.get("Kind")        != re_["kind"]:         mism.append((i, "kind"))
            if pe.get("RelativeUrl") != re_["relative_url"]: mism.append((i, "relative_url"))
            if pe.get("AbsoluteUrl") != re_["absolute_url"]: mism.append((i, "absolute_url"))
        if mism:
            print(f"{FAIL}  Index entries field-by-field: {len(mism)} mismatches")
            for i, fld in mism[:3]:
                print(f"        entry[{i}].{fld}")
            failed += 1
        else:
            print(f"{PASS}  Index entries field-by-field: all {len(ps_entries)} entries match")
            passed += 1
    else:
        print(f"{FAIL}  Index entries length: got {len(ps_entries)}, expected {len(ref_entries)}")
        failed += 1

    # Edge: typo entry present and date parsed to empty string.
    typo = [e for e in ps_entries if e.get("DateText", "").startswith("Octber")]
    if len(typo) == 1 and typo[0].get("Date", None) == "":
        print(f"{PASS}  Index typo entry preserved with empty Date")
        passed += 1
    else:
        print(f"{FAIL}  Index typo entry handling: got {typo!r}")
        failed += 1

    # ---- Month parser checks ----
    print()
    print("Month parser (2026-05):")

    passed, failed = check(
        "2026-05 EntryCountTotal",
        parsed_m05.get("EntryCountTotal"),
        ref_m05["entry_count_total"],
        passed, failed,
    )
    passed, failed = check(
        "2026-05 EntryCountRecognised",
        parsed_m05.get("EntryCountRecognised"),
        ref_m05["entry_count_recognised"],
        passed, failed,
    )

    # rows_per_os: PowerShell returns an ordered hashtable; ConvertTo-Json emits it as a dict.
    ps_rpo = parsed_m05.get("RowsPerOs") or {}
    if isinstance(ps_rpo, list):
        # Defensive: if it serialized as a list of {Key, Value}, flatten it.
        ps_rpo = {item.get("Key"): item.get("Value") for item in ps_rpo if isinstance(item, dict)}
    passed, failed = check(
        "2026-05 RowsPerOs",
        ps_rpo,
        ref_m05["rows_per_os"],
        passed, failed,
    )

    # Server2022 block deep check on 2026-05
    ps_blocks_05 = normalize_list(parsed_m05.get("Entries"))
    s2022 = next((b for b in ps_blocks_05 if b.get("OsNormalised") == "Server2022"), None)
    ref_s2022 = next((b for b in ref_m05["entries"] if b["os_normalised"] == "Server2022"), None)
    if s2022 is None or ref_s2022 is None:
        print(f"{FAIL}  Server2022 block not found in one side")
        failed += 1
    else:
        ok = (
            s2022.get("OsLabel")      == ref_s2022["os_label"] and
            s2022.get("OsOfferingKb") == ref_s2022["os_offering_kb"] and
            len(normalize_list(s2022.get("Rows"))) == len(ref_s2022["rows"])
        )
        if ok:
            # Also check row content
            ps_rows = normalize_list(s2022.get("Rows"))
            row_ok = all(
                ps_rows[j].get("DotNetVersions") == ref_s2022["rows"][j]["dotnet_versions"]
                and ps_rows[j].get("KbId")       == ref_s2022["rows"][j]["kb_id"]
                for j in range(len(ps_rows))
            )
            if row_ok:
                print(f"{PASS}  2026-05 Server2022 block: label, offering KB, all rows")
                passed += 1
            else:
                print(f"{FAIL}  2026-05 Server2022 rows: content mismatch")
                failed += 1
        else:
            print(f"{FAIL}  2026-05 Server2022 block: label/offering/row count mismatch")
            failed += 1

    # ---- Month parser checks for 2026-04 (cross-month regression) ----
    print()
    print("Month parser (2026-04, regression):")
    passed, failed = check(
        "2026-04 EntryCountTotal",
        parsed_m04.get("EntryCountTotal"),
        ref_m04["entry_count_total"],
        passed, failed,
    )
    passed, failed = check(
        "2026-04 EntryCountRecognised",
        parsed_m04.get("EntryCountRecognised"),
        ref_m04["entry_count_recognised"],
        passed, failed,
    )
    ps_rpo_04 = parsed_m04.get("RowsPerOs") or {}
    if isinstance(ps_rpo_04, list):
        ps_rpo_04 = {item.get("Key"): item.get("Value") for item in ps_rpo_04 if isinstance(item, dict)}
    passed, failed = check(
        "2026-04 RowsPerOs",
        ps_rpo_04,
        ref_m04["rows_per_os"],
        passed, failed,
    )

    # ---- OS label mapper checks ----
    print()
    print("OS label mapper:")
    passed, failed = check("Mapper: Windows Server 2022 -> Server2022", ol_2022, "Server2022", passed, failed)
    passed, failed = check("Mapper: 'Windows 10 1809 and Windows Server 2019' -> Server2019", ol_2019, "Server2019", passed, failed)
    passed, failed = check("Mapper: unrecognised label -> '' (empty)", ol_none, "", passed, failed)

    print()
    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
