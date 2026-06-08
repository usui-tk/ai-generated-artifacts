#!/usr/bin/env python3
"""T11: JSON Canonical Serialization byte-level parity test.

Validates that ConvertTo-CanonicalJson (PowerShell, in
Update-WindowsServerIso.ps1) and canonical_json_dumps (Python, in
tests/common/canonical_json.py) emit byte-identical output for the same
logical input, across the value-shape matrix the data/*.json and
tests/fixtures/*.json files actually exercise.

The byte-level guarantee is the contract that lets either runtime
edit a JSON data file without producing a spurious git diff. The
contract is normative in SPEC Part B.23.

Test matrix (each case is one logical input compared via both runtimes):

    Primitives:  empty string, ASCII string, string with quote/backslash,
                 string with embedded newline/tab, large integer, float,
                 scientific notation, true/false, null

    Collections: empty object, empty array, single-element object,
                 single-element array, mixed object, nested object,
                 array of arrays, array of objects

    Unicode:     Japanese characters, emoji, mixed ASCII + non-ASCII

    Real-world:  shape of a config-Server*.json NeutralPatches entry,
                 shape of a cache-release-info.json snapshot

Run from the project root::

    python3 tests/canonical_json_test.py
"""
from __future__ import annotations

import json
import pathlib
import sys
from collections import OrderedDict
from typing import Any, List, Tuple

TESTS_DIR = pathlib.Path(__file__).resolve().parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402
from common.canonical_json import canonical_json_dumps  # type: ignore  # noqa: E402

SCRIPT_PATH = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"


# ----------------------------------------------------------------------
# Test cases
#
# Each case is (label, python_object, depth). The PowerShell side
# receives the same logical input through the TestHarness JSON wire
# format. Use OrderedDict (not plain dict) in Python so key order is
# preserved across JSON marshalling for the PowerShell side too.
# ----------------------------------------------------------------------

def _build_cases() -> List[Tuple[str, Any, int]]:
    cases: List[Tuple[str, Any, int]] = []

    # Primitives
    cases.append(("primitive: empty string", OrderedDict([("v", "")]), 5))
    cases.append(("primitive: ASCII string", OrderedDict([("v", "hello world")]), 5))
    cases.append(("primitive: string with quotes",
                  OrderedDict([("v", 'has "quote" in it')]), 5))
    cases.append(("primitive: string with backslash",
                  OrderedDict([("v", "C:\\path\\to\\file")]), 5))
    cases.append(("primitive: string with newline and tab",
                  OrderedDict([("v", "line1\nline2\there")]), 5))
    cases.append(("primitive: max int64",
                  OrderedDict([("v", 9223372036854775807)]), 5))
    cases.append(("primitive: float",
                  OrderedDict([("v", 3.14)]), 5))
    cases.append(("primitive: scientific notation",
                  OrderedDict([("v", 1e100)]), 5))
    cases.append(("primitive: negative scientific",
                  OrderedDict([("v", 1.5e-10)]), 5))
    cases.append(("primitive: true",
                  OrderedDict([("v", True)]), 5))
    cases.append(("primitive: false",
                  OrderedDict([("v", False)]), 5))
    cases.append(("primitive: null",
                  OrderedDict([("v", None)]), 5))

    # Collections
    cases.append(("collection: empty object",
                  OrderedDict([("v", OrderedDict())]), 5))
    cases.append(("collection: empty array",
                  OrderedDict([("v", [])]), 5))
    cases.append(("collection: single-element object",
                  OrderedDict([("v", OrderedDict([("k", 1)]))]), 5))
    cases.append(("collection: single-element array",
                  OrderedDict([("v", [42])]), 5))
    cases.append(("collection: mixed object",
                  OrderedDict([
                      ("s", "text"), ("i", 1), ("b", True), ("n", None),
                      ("arr", [1, 2, 3]),
                  ]), 5))
    cases.append(("collection: nested object",
                  OrderedDict([
                      ("outer", OrderedDict([
                          ("inner", OrderedDict([
                              ("deep", "value"),
                          ])),
                      ])),
                  ]), 10))
    cases.append(("collection: array of arrays",
                  OrderedDict([("v", [[1, 2], [3, 4], [5, 6]])]), 10))
    cases.append(("collection: array of objects",
                  OrderedDict([("v", [
                      OrderedDict([("kb", "KB1"), ("type", "SSU")]),
                      OrderedDict([("kb", "KB2"), ("type", "LCU")]),
                  ])]), 10))

    # Unicode
    cases.append(("unicode: Japanese",
                  OrderedDict([("v", "日本語テスト")]), 5))
    cases.append(("unicode: emoji",
                  OrderedDict([("v", "🚀")]), 5))
    cases.append(("unicode: mixed",
                  OrderedDict([("v", "Hello, 世界 🌍 !")]), 5))

    # Real-world shape: a NeutralPatches entry from config-Server2016.json
    cases.append((
        "real-world: NeutralPatches entry shape",
        OrderedDict([
            ("Type", "SSU"),
            ("KbId", "KB5088064"),
            ("Title", ""),
            ("UpdateId", "d0f1761f-c762-4764-8443-8c567f6929a2"),
            ("FileName", "windows10.0-kb5088064-x64.msu"),
            ("SizeBytes", 0),
            ("ReleaseDate", "2026-05-12"),
            ("Supersedes", []),
            ("RequiresKbIds", []),
            ("ApplyOrder", 1),
            ("IsCombined", False),
            ("_DependencyVerifiedSource", "manual-r09-step2a"),
        ]),
        5,
    ))

    # Real-world shape: cache-release-info.json header
    cases.append((
        "real-world: cache file header shape",
        OrderedDict([
            ("Schema", "1.0"),
            ("GeneratedAt", "2026-05-26T06:31:11.5569634Z"),
            ("SourceUrl", "https://learn.microsoft.com/en-us/path"),
            ("Entries", [
                OrderedDict([
                    ("Os", "Server2025"),
                    ("Version", "21H2"),
                    ("Build", 26100),
                ]),
            ]),
        ]),
        10,
    ))

    return cases


# ----------------------------------------------------------------------
# Comparison
# ----------------------------------------------------------------------

def compare_one(ps: PSSession, label: str, py_obj: Any, depth: int) -> bool:
    """Return True if PS and Python produce byte-identical output."""
    # Python side
    py_out = canonical_json_dumps(py_obj, depth=depth, trailing_newline=False)

    # PowerShell side. The harness wire format is JSON, so the
    # OrderedDict is automatically converted to a JSON object on the
    # wire; the PowerShell side receives it as a PSCustomObject, which
    # preserves property order. We pass NoTrailingNewline so the output
    # matches our Python call (trailing_newline=False).
    ps_out = ps.invoke(
        "ConvertTo-CanonicalJson",
        InputObject=py_obj,
        Depth=depth,
        NoTrailingNewline=True,
    )

    if ps_out == py_out:
        print(f"{PASS}  {label}")
        return True

    print(f"{FAIL}  {label}")
    print(f"        Python ({len(py_out)} chars): {py_out!r}")
    print(f"        PS     ({len(ps_out)} chars): {ps_out!r}")
    # Show first diverging character to make debugging painless
    for i, (a, b) in enumerate(zip(py_out, ps_out)):
        if a != b:
            print(f"        First diff at offset {i}: Python={a!r} PS={b!r}")
            break
    else:
        if len(py_out) != len(ps_out):
            shorter = min(len(py_out), len(ps_out))
            longer = py_out if len(py_out) > len(ps_out) else ps_out
            print(f"        Length differs; extra tail: {longer[shorter:]!r}")
    return False


# ----------------------------------------------------------------------
# File-level test: Save-CanonicalJsonFile + Python save_canonical_json_file
# ----------------------------------------------------------------------

def compare_save(ps: PSSession, tmpdir: pathlib.Path) -> bool:
    """Verify Save-CanonicalJsonFile and save_canonical_json_file produce
    the same bytes on disk for a representative real-world object."""
    from common.canonical_json import save_canonical_json_file  # type: ignore

    obj = OrderedDict([
        ("Schema", "2.1"),
        ("Patches", [
            OrderedDict([("KbId", "KB1"), ("ApplyOrder", 1)]),
            OrderedDict([("KbId", "KB2"), ("ApplyOrder", 2)]),
        ]),
    ])

    py_path = tmpdir / "py_out.json"
    ps_path = tmpdir / "ps_out.json"

    save_canonical_json_file(obj, py_path, depth=5)
    ps.invoke("Save-CanonicalJsonFile", InputObject=obj,
              Path=str(ps_path), Depth=5)

    py_bytes = py_path.read_bytes()
    ps_bytes = ps_path.read_bytes()

    if py_bytes == ps_bytes:
        print(f"{PASS}  Save-CanonicalJsonFile byte-level parity ({len(py_bytes)} bytes)")
        return True
    print(f"{FAIL}  Save-CanonicalJsonFile byte-level parity")
    print(f"        Python: {py_bytes!r}")
    print(f"        PS    : {ps_bytes!r}")
    return False


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

def main() -> int:
    import tempfile

    if not SCRIPT_PATH.exists():
        print(f"  Script not found: {SCRIPT_PATH}", file=sys.stderr)
        return 2

    cases = _build_cases()
    passed = 0
    failed = 0

    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = pathlib.Path(tmpdir_str)
        with PSSession(SCRIPT_PATH) as ps:
            for label, obj, depth in cases:
                if compare_one(ps, label, obj, depth):
                    passed += 1
                else:
                    failed += 1
            if compare_save(ps, tmpdir):
                passed += 1
            else:
                failed += 1

    total = passed + failed
    print()
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
