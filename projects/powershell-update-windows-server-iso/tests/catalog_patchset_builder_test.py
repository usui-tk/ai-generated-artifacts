#!/usr/bin/env python3
"""T27: Offline b3 config-dataset builder / regression test.

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

The fixture's SetupDU raw line is a VERBATIM 2026-07-02 live-Catalog
capture of the 2026-06 Setup DU (KB5095966, uid 3401a3ef-...), including
the real Products value ``Windows 10 and later Dynamic Update`` -- the
prior fixture fabricated a ``Setup Dynamic Update`` products string that
does not exist on the live surface, which is exactly what certified the
never-matching resolver filter (audit F1). Fixture fields are captured,
never authored.

This test also pins the r11.45 silent-starvation guard: rule (1) of
``ConvertTo-ConfigLines`` drops an empty (0-file) line ONLY when its
Kind is outside the PatchModel's apply map; an empty IN-MODEL Kind
(e.g. a starved 2025 SetupDU) must HARD-FAIL instead of silently
producing a degraded dataset [DECIDED 2026-07-02, user].

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
from common.ps_invoke import PSSession, PSHarnessError  # type: ignore  # noqa: E402

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

        # 5. Silent-starvation guard (r11.45): an EMPTY in-model Kind must
        #    HARD-FAIL; an empty out-of-model Kind still drops silently.
        print("=== Guard: empty in-model Kind hard-fails ===")
        import copy
        starved = copy.deepcopy(raw["2025"])
        for ln in starved["lines"]:
            if ln["kind"] == "SetupDU":
                ln["files"] = []
                ln["inScope"] = {"files": []}
        try:
            ps.invoke("ConvertTo-ConfigLines",
                      OsResolved=starved, PatchModel="uup-checkpoint")
            passed, failed = check(
                "2025 starved SetupDU hard-fails", False,
                "no exception raised (silent drop resurfaced)", passed, failed)
        except PSHarnessError as exc:
            msg = str(exc)
            passed, failed = check(
                "2025 starved SetupDU hard-fails",
                "resolved 0 files" in msg and "SetupDU" in msg,
                f"error={msg[:140]!r}", passed, failed)

        # 2016's raw carries empty .NET / SafeOSDU lines (by-design absences,
        # OUT of separate-ssu's apply map) -- those must STILL drop silently.
        built_2016 = normalize_list(
            ps.invoke("ConvertTo-ConfigLines",
                      OsResolved=raw["2016"], PatchModel="separate-ssu"))
        passed, failed = check(
            "2016 out-of-model empties still drop silently",
            {ln.get("Kind") for ln in built_2016} == EXPECTED_KINDS["2016"],
            f"Kinds={sorted({ln.get('Kind') for ln in built_2016})}",
            passed, failed)
        print()

    print(f"==== RESULT: {passed} passed, {failed} failed ====")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
