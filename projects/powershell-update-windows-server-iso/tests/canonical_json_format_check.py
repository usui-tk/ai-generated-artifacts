#!/usr/bin/env python3
"""Part C quality gate: every JSON file in this subproject MUST be in
canonical format (SPEC Part B.23).

Walks ``data/`` and ``tests/`` under the subproject root and, for each
``*.json`` file, re-serialises it through ``canonical_json_dumps`` and
compares the bytes against the on-disk file. If any file differs, the
script prints the file path plus a short diff hint and exits with a
non-zero status.

The check is intentionally hostile to noise: a single mis-indented file
fails the gate. Reformatting is a separate, scoped activity (one
script-driven commit per migration cycle, not a drive-by edit).

Run from the project root::

    python3 tests/canonical_json_format_check.py

Exit codes:
    0 -- all files in canonical format
    1 -- one or more files not in canonical format (paths printed)
    2 -- runtime error (test infrastructure issue)
"""
from __future__ import annotations

import json
import pathlib
import sys
from collections import OrderedDict
from typing import List, Tuple

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent

sys.path.insert(0, str(TESTS_DIR))
from common.canonical_json import canonical_json_dumps  # type: ignore  # noqa: E402

# Maximum depth used to re-serialise. The deepest known schema is
# the PatchBaseline.Patches[].DownloadHistory[] chain in
# config-Server*.json, which currently bottoms out at depth 7-8.
# Using 32 gives plenty of headroom without changing the canonical
# format (depth only affects when ConvertTo-Json TRUNCATES; once the
# tree fits, depth is invisible in the output).
CHECK_DEPTH = 32

# Directories to walk. Restrict to the subproject's own JSON files;
# do NOT walk parent or sibling directories (sibling-isolation policy).
SCAN_DIRS = [
    SUBPROJECT_ROOT / "data",
    SUBPROJECT_ROOT / "tests" / "fixtures",
    SUBPROJECT_ROOT / "tests" / "snapshots",
]

# Files explicitly excluded from the check (per-file justifications).
# Add to this list with a clear reason in code review.
EXCLUDED = set()  # type: set[pathlib.Path]


def find_target_files() -> List[pathlib.Path]:
    """Return the sorted list of *.json files to check."""
    out: List[pathlib.Path] = []
    for d in SCAN_DIRS:
        if not d.is_dir():
            continue
        out.extend(p for p in d.rglob("*.json") if p not in EXCLUDED)
    return sorted(out)


def check_one(path: pathlib.Path) -> Tuple[bool, str]:
    """Return (ok, diagnostic). ok is True if the file is canonical."""
    try:
        raw = path.read_bytes()
    except OSError as exc:
        return False, f"read failed: {exc}"

    # Parse the file. If it does not even parse as JSON it fails the
    # check; a non-parseable file in data/ or tests/fixtures/ is a
    # separate bug class but the format gate is the right place to
    # surface it.
    try:
        obj = json.loads(raw.decode("utf-8"), object_pairs_hook=OrderedDict)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return False, f"JSON parse failed: {exc}"

    # Re-serialise through the canonical writer
    expected = canonical_json_dumps(obj, depth=CHECK_DEPTH, trailing_newline=True)
    expected_bytes = expected.encode("utf-8")

    if raw == expected_bytes:
        return True, ""

    # Build a short, useful diagnostic. Show the first differing
    # byte offset and surrounding context.
    delta = len(raw) - len(expected_bytes)
    sign = "+" if delta > 0 else ""
    msg_lines = [
        f"size: on-disk {len(raw):,} vs canonical {len(expected_bytes):,} "
        f"({sign}{delta:+,} bytes)"
    ]

    # First differing byte
    minlen = min(len(raw), len(expected_bytes))
    diff_offset = next((i for i in range(minlen) if raw[i] != expected_bytes[i]), minlen)
    if diff_offset < minlen:
        # Show 40 bytes before and after, ASCII-friendly
        start = max(0, diff_offset - 40)
        end_disk = min(len(raw), diff_offset + 40)
        end_canon = min(len(expected_bytes), diff_offset + 40)
        try:
            disk_ctx = raw[start:end_disk].decode("utf-8", errors="replace")
            canon_ctx = expected_bytes[start:end_canon].decode("utf-8", errors="replace")
            msg_lines.append(f"first diff at byte {diff_offset:,}")
            msg_lines.append(f"  on-disk   : ...{disk_ctx!r}...")
            msg_lines.append(f"  canonical : ...{canon_ctx!r}...")
        except UnicodeDecodeError:
            msg_lines.append(f"first diff at byte {diff_offset:,} (binary)")
    else:
        # One is a prefix of the other (trailing newline missing, etc.)
        tail_disk = raw[minlen:][:60]
        tail_canon = expected_bytes[minlen:][:60]
        if tail_disk:
            msg_lines.append(f"on-disk has extra tail: {tail_disk!r}")
        if tail_canon:
            msg_lines.append(f"canonical has extra tail: {tail_canon!r}")

    return False, "\n        ".join(msg_lines)


def main() -> int:
    targets = find_target_files()
    if not targets:
        print("  No JSON files found under data/, tests/fixtures/, tests/snapshots/", file=sys.stderr)
        return 2

    print(f"  Checking {len(targets)} JSON files for canonical format compliance (SPEC Part B.23)")
    print()

    passed = 0
    failed: List[Tuple[pathlib.Path, str]] = []

    for path in targets:
        rel = path.relative_to(SUBPROJECT_ROOT)
        ok, diagnostic = check_one(path)
        if ok:
            passed += 1
            print(f"  PASS  {rel}")
        else:
            failed.append((path, diagnostic))
            print(f"  FAIL  {rel}")
            print(f"        {diagnostic}")

    print()
    print(f"  Summary: {passed} passed, {len(failed)} failed, {len(targets)} total")
    if failed:
        print()
        print("  Remediation: re-serialise each failed file through")
        print("    - tests/common/canonical_json.save_canonical_json_file (Python), or")
        print("    - Save-CanonicalJsonFile (PowerShell, in Update-WindowsServerIso.ps1)")
        print("  Both produce byte-identical output (SPEC Part B.23 parity contract, verified by T11).")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
