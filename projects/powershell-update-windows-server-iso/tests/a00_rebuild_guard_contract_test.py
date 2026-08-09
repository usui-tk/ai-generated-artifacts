#!/usr/bin/env python3
"""T57: A00 fail-closed guard placement contract.

Pins the r12.90 mitigation of the fourth-audit finding N4-01: until
the v4 seed migration lands, `A00 RebuildDataset` must refuse — in
Stage 0, before any config file is written — whenever a committed
seed's declared `Schema` differs from the canonical current config
schema version. This test asserts the guard's existence, its
canonical-version anchor, and its ordering ahead of the Stage 2
config write inside the A00 orchestrator, so a refactor cannot
silently drop or reorder the mitigation while the underlying defect
(pre-v4 seeds, v3-copying builder, line-count-only Stage 4) is still
open (TESTING 7.0a).

Also pins the factual precondition the guard exists for: the four
committed seeds still declare the legacy `"3.0"` shape. When the v4
seed-migration campaign lands, this test is expected to be revised
in the same change set that retires the guard — the seed-shape pin
below failing is the designed signal that the revision is due, not a
defect in the dataset.

Class: B (structural pin over the main script and the seed dataset).

Run:  python3 tests/a00_rebuild_guard_contract_test.py
Deps: none (pure text scan; no pwsh, no network).
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"
SEED_DIR = SUBPROJECT_ROOT / "data" / "seed"

GUARD_MARKER = "RebuildDataset is fail-closed"
CANONICAL_ANCHOR = "$canonicalCurrentSchema = '4.0'"
A00_FUNC = "function Invoke-AdminPhaseA00_RebuildDataset"
STAGE2_WRITE = "Save-CanonicalJsonFile"
NEXT_FUNC_RE = re.compile(r"^function\s+", re.MULTILINE)


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def main():
    print("T57: A00 fail-closed guard placement contract")
    passed = failed = 0

    passed, failed = check(
        "script present", SCRIPT.is_file(), "main script not found",
        passed, failed)
    if not SCRIPT.is_file():
        print("\n  Summary: aborted")
        return 1

    text = SCRIPT.read_bytes().decode("utf-8-sig", errors="replace")

    idx = text.find(A00_FUNC)
    passed, failed = check(
        "A00 orchestrator function present", idx >= 0,
        f"{A00_FUNC!r} not found", passed, failed)
    if idx < 0:
        print("\n  Summary: aborted")
        return 1

    nxt = NEXT_FUNC_RE.search(text, idx + 10)
    body = text[idx:nxt.start()] if nxt else text[idx:]

    g = body.find(GUARD_MARKER)
    passed, failed = check(
        "fail-closed guard present inside A00",
        g >= 0, f"marker {GUARD_MARKER!r} not in the A00 body",
        passed, failed)
    passed, failed = check(
        "guard anchors the canonical current schema version",
        CANONICAL_ANCHOR in body,
        f"{CANONICAL_ANCHOR!r} not in the A00 body", passed, failed)

    w = body.find(STAGE2_WRITE)
    passed, failed = check(
        "Stage 2 config write present inside A00",
        w >= 0, f"{STAGE2_WRITE!r} not in the A00 body", passed, failed)
    passed, failed = check(
        "guard precedes the Stage 2 config write",
        0 <= g < w, f"guard at {g}, write at {w}", passed, failed)

    # The guard exists because the committed seeds are still pre-v4.
    # When the migration lands, revise this test together with the
    # guard retirement (see the module docstring).
    for os_key in ("Server2016", "Server2019", "Server2022", "Server2025"):
        seed = SEED_DIR / f"seed-{os_key}.json"
        ok = seed.is_file()
        declared = None
        if ok:
            declared = json.loads(seed.read_text(encoding="utf-8")).get("Schema")
        passed, failed = check(
            f"seed {os_key} still declares the legacy 3.0 shape "
            "(guard precondition)",
            ok and declared == "3.0",
            f"file={ok} declared={declared!r} -- if the v4 migration "
            "landed, revise this test with the guard retirement",
            passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, "
          f"{passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
