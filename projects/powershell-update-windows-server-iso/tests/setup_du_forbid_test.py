#!/usr/bin/env python3
"""T28: Resolve-SetupDu Forbid-branch unit test (offline).

``Resolve-SetupDu`` is the Setup Dynamic Update (b3) acquisition resolver,
the sibling of ``Resolve-SafeOsDu``. Setup DU is published ONLY for the
UUP-checkpoint OS (Server 2025 / 24H2); the separate-ssu / embedded-ssu /
embedded-ssu-du models FORBID it, so only the 2025 branch of ``Resolve-Os``
requests it.

The 2025 happy path (live Catalog acquisition: ``Search-Catalog`` +
``Resolve-CatalogDownload``) is exercised offline by T27 against a captured
fixture. This test pins the complementary half -- the deterministic Forbid
branch that every non-2025 OS must hit. It needs no network and no fixture:
for ``-OsKey != '2025'`` the function returns the empty "no line" marker
before any Catalog call.

For each non-2025 OS the harness calls ``Resolve-SetupDu`` through the
TestHarness REPL and asserts the returned Line is the empty SetupDU marker:
``kind == 'SetupDU'``, no files, no Catalog row (``catalogUid`` / ``kb``
null), and a ``note`` that records the Forbid reason and the OS key.

Run from the project root:

    python3 tests/setup_du_forbid_test.py
"""
from __future__ import annotations

import pathlib
import sys
from typing import Any

TESTS_DIR = pathlib.Path(__file__).resolve().parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SCRIPT_PATH = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"

# Every non-uup-checkpoint OS must FORBID a SetupDU line.
FORBID_OS = ("2016", "2019", "2022")


def check(label: str, ok: bool, detail: str, p: int, f: int) -> tuple[int, int]:
    if ok:
        print(f"{PASS}  {label}: {detail}")
        return p + 1, f
    print(f"{FAIL}  {label}: {detail}")
    return p, f + 1


def main() -> int:
    passed = 0
    failed = 0
    with PSSession(SCRIPT_PATH) as ps:
        for os_key in FORBID_OS:
            line: Any = ps.invoke("Resolve-SetupDu", OsKey=os_key)

            passed, failed = check(
                f"{os_key} kind",
                isinstance(line, dict) and line.get("kind") == "SetupDU",
                f"kind={line.get('kind')!r} (expected 'SetupDU')" if isinstance(line, dict)
                else f"unexpected result type {type(line).__name__}",
                passed, failed)

            files = (line.get("files") if isinstance(line, dict) else None) or []
            passed, failed = check(
                f"{os_key} no files",
                files == [],
                f"files={files!r} (expected [])",
                passed, failed)

            cat_uid = line.get("catalogUid") if isinstance(line, dict) else "?"
            kb = line.get("kb") if isinstance(line, dict) else "?"
            passed, failed = check(
                f"{os_key} no catalog row",
                cat_uid is None and kb is None,
                f"catalogUid={cat_uid!r} kb={kb!r} (expected null/null)",
                passed, failed)

            note = (line.get("note") if isinstance(line, dict) else "") or ""
            passed, failed = check(
                f"{os_key} Forbid note",
                "Forbid" in note and os_key in note,
                f"note={note!r}",
                passed, failed)

    print()
    print(f"  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
