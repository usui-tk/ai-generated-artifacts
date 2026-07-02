#!/usr/bin/env python3
"""T30: Setup-DU discriminator unit test (offline, real captured rows).

FACT (reference architecture memo, resolution-recipes section; re-verified
against the live Microsoft Update Catalog on 2026-07-02): a Setup Dynamic
Update row's Products column carries ONLY ``Windows 10 and later Dynamic
Update`` -- there is NO ``Setup Dynamic Update`` product category. Only the
SafeOS DU carries a dedicated product string (``Windows Safe OS Dynamic
Update``). The r11.38 resolver assumed SafeOS/Setup symmetry and filtered
on ``products.Contains('Setup Dynamic Update')``, which could never match a
live row; the 2025 SetupDU line silently starved for weeks while every
gate stayed green (audit F1). The discriminator is therefore the TITLE,
implemented as the pure ``Select-SetupDuCandidate`` (r11.45).

This test drives ``Select-SetupDuCandidate`` through the TestHarness REPL
against ROWS CAPTURED VERBATIM from the live Catalog (Search.aspx,
2026-07-02) -- the same-month server row, older server months, the
Windows 11 client x64/arm64 rows, and the SafeOS server row -- and pins:

1. the server 24H2 Setup-DU rows are selected (and ONLY those);
2. the Windows 11 client rows are excluded (no 'server operating system');
3. the arm64 row is excluded;
4. the SafeOS DU row is excluded (title lacks 'Setup Dynamic Update');
5. the F1 regression fact itself: the REAL server Setup-DU products value
   does NOT contain the string 'Setup Dynamic Update' -- so a
   products-based discriminator can never come back.

Run from the project root:

    python3 tests/setup_du_discriminator_test.py
"""
from __future__ import annotations

import pathlib
import sys
from typing import Any, Dict, List

TESTS_DIR = pathlib.Path(__file__).resolve().parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SCRIPT_PATH = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"

# Rows captured verbatim from the live Catalog Search.aspx on 2026-07-02
# (query: 'Setup Dynamic Update ...' / 'Safe OS Dynamic Update ...').
SERVER_2026_06 = {
    "title": ("2026-06 Setup Dynamic Update for Microsoft server operating "
              "system version 24H2 for x64-based Systems (KB5095966)"),
    "products": "Windows 10 and later Dynamic Update",
}
SERVER_2025_11 = {
    "title": ("2025-11 Setup Dynamic Update for Microsoft server operating "
              "system version 24H2 for x64-based Systems (KB5072617)"),
    "products": "Windows 10 and later Dynamic Update",
}
WIN11_X64 = {
    "title": ("2026-06 Setup Dynamic Update for Windows 11, version 24H2 "
              "for x64-based Systems (KB5102558)"),
    "products": "Windows 10 and later Dynamic Update",
}
WIN11_ARM64 = {
    "title": ("2026-06 Setup Dynamic Update for Windows 11, version 24H2 "
              "for arm64-based Systems (KB5102558)"),
    "products": "Windows 10 and later Dynamic Update",
}
SAFEOS_SERVER = {
    "title": ("2026-06 Safe OS Dynamic Update for Microsoft server operating "
              "system version 24H2 for x64-based Systems (KB5094150)"),
    "products": "Windows Safe OS Dynamic Update, Windows 10 and later Dynamic Update",
}

ALL_ROWS: List[Dict[str, str]] = [
    SERVER_2026_06, WIN11_ARM64, WIN11_X64, SERVER_2025_11, SAFEOS_SERVER,
]


def check(label: str, ok: bool, detail: str, p: int, f: int) -> tuple[int, int]:
    if ok:
        print(f"{PASS}  {label}: {detail}")
        return p + 1, f
    print(f"{FAIL}  {label}: {detail}")
    return p, f + 1


def titles(result: Any) -> List[str]:
    if result is None:
        return []
    rows = result if isinstance(result, list) else [result]
    return [r.get("title", "") for r in rows if isinstance(r, dict)]


def main() -> int:
    passed = 0
    failed = 0

    with PSSession(SCRIPT_PATH) as ps:
        got = titles(ps.invoke("Select-SetupDuCandidate",
                               Rows=ALL_ROWS, VersionToken="24H2"))

        passed, failed = check(
            "selects exactly the server 24H2 Setup-DU rows",
            sorted(got) == sorted([SERVER_2026_06["title"], SERVER_2025_11["title"]]),
            f"selected {len(got)} row(s): {[t[:60] for t in got]}",
            passed, failed)

        passed, failed = check(
            "Windows 11 client x64 row excluded",
            WIN11_X64["title"] not in got,
            "no 'server operating system' in title", passed, failed)

        passed, failed = check(
            "arm64 row excluded",
            WIN11_ARM64["title"] not in got,
            "arm64 filtered", passed, failed)

        passed, failed = check(
            "SafeOS DU server row excluded",
            SAFEOS_SERVER["title"] not in got,
            "title lacks 'Setup Dynamic Update'", passed, failed)

        # Empty input must return an empty candidate set, not blow up.
        got_empty = titles(ps.invoke("Select-SetupDuCandidate",
                                     Rows=[], VersionToken="24H2"))
        passed, failed = check(
            "empty row set yields empty candidates",
            got_empty == [],
            f"got {got_empty!r}", passed, failed)

        # Wrong version token selects nothing (the 21H2 guard: 2022 has NO
        # Setup DU at all -- catalog count 0, reference memo).
        got_21h2 = titles(ps.invoke("Select-SetupDuCandidate",
                                    Rows=ALL_ROWS, VersionToken="21H2"))
        passed, failed = check(
            "21H2 token selects nothing (2022 has no Setup DU)",
            got_21h2 == [],
            f"got {len(got_21h2)} row(s)", passed, failed)

    # F1 regression fact pinned at the data level: the REAL server Setup-DU
    # products string contains NO 'Setup Dynamic Update' -- a products-based
    # discriminator can never work.
    passed, failed = check(
        "F1 fact: real Setup-DU products has no 'Setup Dynamic Update'",
        "Setup Dynamic Update" not in SERVER_2026_06["products"],
        f"products={SERVER_2026_06['products']!r}", passed, failed)

    # ...and the resolver source must not filter on it (static guard over
    # CODE lines only; the forensic comments may -- and do -- cite the old
    # pattern by name).
    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")
    code_lines = [ln for ln in text.splitlines()
                  if not ln.lstrip().startswith("#")]
    offenders = [ln.strip()[:100] for ln in code_lines
                 if "products.Contains('Setup Dynamic Update')" in ln]
    passed, failed = check(
        "no CODE line filters products.Contains('Setup Dynamic Update')",
        offenders == [],
        "absent from code" if not offenders else f"found: {offenders!r}",
        passed, failed)

    print()
    print(f"  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
