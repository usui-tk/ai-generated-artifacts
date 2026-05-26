#!/usr/bin/env python3
"""T9: Config-driven Catalog title-token regression test.

Validates the URL-resolver narrowing helpers added in r07.0 Step 2b
(Commit 3): `Get-CatalogTitleTokenList` reads the per-OS Config and
`Test-CatalogTitleMatch` applies the positive + negative filter
against a candidate Microsoft Update Catalog hit title.

The reference data was captured live from
https://www.catalog.update.microsoft.com on 2026-05-26 and recorded
under tests/fixtures/catalog_title_tokens/narrow-filter-cases.json
together with the expected accept/reject decision per OS. T9
re-applies the PowerShell helpers and asserts the outcome matches
the reference.

Run from the project root:

    python3 tests/catalog_title_tokens_test.py
"""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Any

TESTS_DIR = pathlib.Path(__file__).resolve().parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

FIXTURE_DIR  = TESTS_DIR / "fixtures" / "catalog_title_tokens"
SCRIPT_PATH  = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"


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
    cases_path = FIXTURE_DIR / "narrow-filter-cases.json"
    tokens_ref_path = FIXTURE_DIR / "expected-tokens.json"
    if not cases_path.is_file() or not tokens_ref_path.is_file():
        print(f"  SKIP: missing required fixtures under {FIXTURE_DIR}")
        return 0

    cases       = json.loads(cases_path.read_text(encoding="utf-8"))
    tokens_ref  = json.loads(tokens_ref_path.read_text(encoding="utf-8"))

    print(f"Fixtures: {FIXTURE_DIR.relative_to(TESTS_DIR)}")
    print(f"  expected-tokens.json   : {len(tokens_ref)} OSes")
    print(f"  narrow-filter-cases.json: {len(cases['cases'])} title cases")
    print()

    passed = 0
    failed = 0

    with PSSession(SCRIPT_PATH) as ps:
        # Phase 1: Get-CatalogTitleTokenList returns Config values
        print("=== Get-CatalogTitleTokenList (Config sourcing) ===")
        for os_key in ("Server2025", "Server2022", "Server2019", "Server2016"):
            tokens = ps.invoke("Get-CatalogTitleTokenList", OsVersion=os_key)
            if tokens is None:
                tokens = []
            if not isinstance(tokens, list):
                tokens = [tokens]
            expected = tokens_ref.get(os_key, [])
            passed, failed = check(f"{os_key} tokens (sorted)",
                                   sorted(tokens), sorted(expected),
                                   passed, failed)

        # Phase 2: missing-Config defensive default
        print()
        print("=== Get-CatalogTitleTokenList defensive default ===")
        # An OsVersion that doesn't have a Config file -> empty array
        nonexistent = ps.invoke("Get-CatalogTitleTokenList", OsVersion="ServerNonexistent9999")
        if nonexistent is None:
            nonexistent_list = []
        elif isinstance(nonexistent, list):
            nonexistent_list = nonexistent
        else:
            nonexistent_list = [nonexistent]
        passed, failed = check("Missing-Config OS -> empty list",
                               nonexistent_list, [],
                               passed, failed)

        # Phase 3: Test-CatalogTitleMatch against live cases
        print()
        print("=== Test-CatalogTitleMatch (positive + negative filter) ===")
        for case in cases["cases"]:
            got = ps.invoke("Test-CatalogTitleMatch",
                            OsVersion=case["os"],
                            Title=case["title"])
            passed, failed = check(
                f'{case["os"]}: {case["description"]}',
                bool(got), bool(case["expected_match"]),
                passed, failed,
            )

    print()
    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
