#!/usr/bin/env python3
"""T12: Offline b3 config-dataset builder / regression test.

Restores the offline initial-dataset construction capability for the
Catalog (b3) data-source. Before the b3 migration, the release-info
producer could be driven from Python against saved fixtures (T10) so the
config baseline could be (re)built WITHOUT live network I/O. The b3
producer (``Resolve-Os`` -> ``Invoke-CatalogPatchSetRefresh``) performs
live Catalog scraping, and no Python-drivable offline builder was carried
forward -- so Claude could no longer construct the dataset offline. This
test restores that path.

It exercises ONLY the deterministic transform half of the b3 producer:

  ``ConvertTo-ConfigLines -OsResolved <raw> -PatchModel <model>``

which is exactly the ``-RawResolved`` injection point the orchestrator
``Resolve-CatalogPatchSetForOs`` documents ("live Resolve-Os in
production; the captured fixture in tests"). The live acquisition
(``Resolve-Os``: Search-Catalog + DownloadDialog) is intentionally NOT
run here -- it requires network I/O and is covered by the live probe
(T1). The captured raw fixture stands in for that acquisition.

For each OS the harness:
  1. Reads the captured layer-1 raw object ``{ os; lines[] }`` from the
     fixture (``fixtures/catalog_raw/resolve-<month>.json``).
  2. Calls ``ConvertTo-ConfigLines`` through the TestHarness REPL to BUILD
     the v3.0 ``PatchBaseline.Lines[]`` for that OS, offline.
  3. Asserts the built Line set: the Kinds match the PatchModel's allowed
     set (no Forbidden Kind leaks through), every Line carries a Digest
     (the v3.0 primary integrity key), and -- for the UUP-checkpoint OS
     (Server 2025) -- a SetupDU Line is produced at ApplyOrder 5.

The fixture's SetupDU raw line carries the real 24H2 Setup DU title/KB
(KB5095966) with placeholder download url/digest; the real values are
filled by a live refresh. The purpose here is to prove the transform
builds the dataset offline, including the SetupDU Kind.

Run from the project root:

    python3 tests/catalog_patchset_builder_test.py
"""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Any, Dict, List

TESTS_DIR = pathlib.Path(__file__).resolve().parent

sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

FIXTURE_PATH = TESTS_DIR / "fixtures" / "catalog_raw" / "resolve-2026-06.json"
SCRIPT_PATH  = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"

# PatchModel per OS (mirrors data/config-Server<N>.json#/PatchModel).
MODEL_BY_OS: Dict[str, str] = {
    "2016": "separate-ssu",
    "2019": "embedded-ssu",
    "2022": "embedded-ssu-du",
    "2025": "uup-checkpoint",
}

# The Kinds each PatchModel is expected to emit (the applyMap domain;
# Forbidden / placeholder Kinds are dropped by the transform). This is the
# v3.0 baseline shape the offline build must reproduce.
EXPECTED_KINDS: Dict[str, set] = {
    "2016": {"SSU", "LCU"},
    "2019": {"LCU", "DotNet"},
    "2022": {"LCU", "DotNet", "SafeOSDU"},
    "2025": {"SSU", "LCU", "DotNet", "SafeOSDU", "SetupDU"},
}


def normalize_list(value: Any) -> List[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def check(label: str, ok: bool, detail: str, p: int, f: int) -> tuple[int, int]:
    if ok:
        print(f"{PASS}  {label}: {detail}")
        return p + 1, f
    print(f"{FAIL}  {label}: {detail}")
    return p, f + 1


def main() -> int:
    if not FIXTURE_PATH.is_file():
        print(f"  SKIP: missing fixture {FIXTURE_PATH}")
        return 0
    raw = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

    print(f"Fixture: {FIXTURE_PATH.relative_to(TESTS_DIR)}")
    for os_key in MODEL_BY_OS:
        kinds = [ln["kind"] for ln in raw[os_key]["lines"]]
        print(f"  raw {os_key}: {kinds}")
    print()

    passed = 0
    failed = 0

    with PSSession(SCRIPT_PATH) as ps:
        for os_key, model in MODEL_BY_OS.items():
            print(f"=== Build {os_key} (PatchModel={model}) ===")
            built = normalize_list(
                ps.invoke(
                    "ConvertTo-ConfigLines",
                    OsResolved=raw[os_key],
                    PatchModel=model,
                )
            )
            kinds = [ln.get("Kind") for ln in built]

            # 1. The transform produced a non-empty baseline offline.
            passed, failed = check(
                f"{os_key} built offline", len(built) > 0,
                f"{len(built)} Line(s): {kinds}", passed, failed)

            # 2. Kinds match the PatchModel's allowed set (no Forbidden leak).
            got_set = set(kinds)
            passed, failed = check(
                f"{os_key} Kinds match model", got_set == EXPECTED_KINDS[os_key],
                f"{sorted(got_set)} (expected {sorted(EXPECTED_KINDS[os_key])})",
                passed, failed)

            # 3. Every built Line carries a Digest (v3.0 primary key).
            no_digest = [ln.get("Kind") for ln in built if not ln.get("Digest")]
            passed, failed = check(
                f"{os_key} all Lines have Digest", len(no_digest) == 0,
                "all set" if not no_digest else f"missing on {no_digest}",
                passed, failed)

            # 4. UUP-checkpoint OS builds a SetupDU Line at ApplyOrder 5.
            if os_key == "2025":
                setup = [ln for ln in built if ln.get("Kind") == "SetupDU"]
                passed, failed = check(
                    "2025 SetupDU Line built", len(setup) == 1,
                    f"{len(setup)} SetupDU Line(s)", passed, failed)
                if len(setup) == 1:
                    passed, failed = check(
                        "2025 SetupDU ApplyOrder", setup[0].get("ApplyOrder") == 5,
                        f"ApplyOrder={setup[0].get('ApplyOrder')} (expected 5), "
                        f"KbId={setup[0].get('KbId')}", passed, failed)
            print()

    print(f"==== RESULT: {passed} passed, {failed} failed ====")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
