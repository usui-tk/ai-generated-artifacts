#!/usr/bin/env python3
"""Seed contract gate (SPEC B.14.2 SEED/DERIVED boundary).

Makes the SEED/DERIVED boundary *mechanically coordinated with the schema*,
so the data pipeline cannot silently drop or mis-place a field. This is the
durable guard against the class of defect found while building A00: the seed
extraction had treated ``PatchBaseline`` as one DERIVED unit and dropped its
SEED envelope, because the boundary was hand-derived from the coarse
``$Script:OsConfigFieldGroups`` group classification instead of being checked
field-by-field against ``schema/config.schema.json``.

What this gate asserts
----------------------
1. COVERAGE -- every field declared in ``schema/config.schema.json`` (top-level
   and inside each structured object) is accounted for as exactly one of:
     * SEED    -- admitted by ``schema/config-seed.schema.json``, or
     * DERIVED -- listed in the DERIVED table below.
   No field may be UNCLASSIFIED (would be silently dropped from the seed) and
   none may be in BOTH (a contradiction). A new field added to the config
   schema without classifying it fails this gate loudly.
2. NO SEED-EXTRA -- the seed schema admits no field the config schema does not
   declare (the seed is a strict projection, never a superset).
3. PROJECTION CONSISTENCY -- the SEED definitions the seed schema reuses
   (``Common`` / ``Pca2023`` / ``AutoRefreshPolicy``) are byte-equal to the
   config schema's, and ``PatchBaselineSeed`` is exactly the config schema's
   ``PatchBaseline`` envelope with the DERIVED members forbidden.
4. SEED-FILE CONFORMANCE -- every ``data/seed/seed-Server*.json`` validates
   against ``schema/config-seed.schema.json`` (reusing the project's
   stdlib draft-07-subset validator from ``config_schema_test``).

The DERIVED table is the single hand-maintained half of the classification;
its basis is what the script actually *generates* at rebuild, not opinion:
  * ``PatchBaseline.Lines``                    <- Invoke-CatalogPatchSetRefresh
  * ``PatchBaseline`` refresh stamps           <- written at refresh
  * ``PatchBaseline.TargetBuildAfterUpdate``   <- the LCU Line InScope.build (r11.46)
        (LastVerifiedDate / LastVerifiedBy / PatchTuesdayOfBaseline)
  * ``LanguageEntry.LanguageSpecificPatches``  <- Resolve-LanguageSpecificPatchesFromCatalog
  * top-level ``_meta``                        <- Save-ConfigWithBaseline

Exit codes: 0 -- all assertions pass; 1 -- one or more fail.

Run from the project root::

    python3 tests/seed_contract_test.py
"""
from __future__ import annotations

import json
import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
SCHEMA_DIR = SUBPROJECT_ROOT / "schema"
SEED_DIR = SUBPROJECT_ROOT / "data" / "seed"
CONFIG_SCHEMA = SCHEMA_DIR / "config.schema.json"
SEED_SCHEMA = SCHEMA_DIR / "config-seed.schema.json"

# Reuse the project's stdlib-only draft-07-subset validator (no jsonschema dep).
sys.path.insert(0, str(TESTS_DIR))
from config_schema_test import _validate  # type: ignore  # noqa: E402

PASS = "PASS"
FAIL = "FAIL"

# DERIVED table -- the hand-maintained half of the classification (see module
# docstring for the per-field generation basis). Keyed by the structured-object
# name used in the inventory below; values are the field names that are
# regenerated and therefore MUST NOT appear in the seed.
DERIVED = {
    "(top-level)": {"_meta"},
    # TargetBuildAfterUpdate moved SEED -> DERIVED at r11.46 (refresh
    # writeback derives it from the LCU Line InScope.build; audit F2).
    "PatchBaseline": {"Lines", "PatchTuesdayOfBaseline", "LastVerifiedDate", "LastVerifiedBy", "TargetBuildAfterUpdate"},
    "LanguageEntry": {"LanguageSpecificPatches"},
    "Common": set(),
    "Pca2023": set(),
    "AutoRefreshPolicy": set(),
}

# Map each structured object to (config-schema location, seed-schema location).
# A location is a callable returning that object's ``properties`` key set.


def _props(node) -> set:
    return set(node.get("properties", {}).keys())


def main() -> int:
    passed = 0
    failed = 0

    def check(ok: bool, label: str, detail: str = "") -> None:
        nonlocal passed, failed
        if ok:
            passed += 1
            print(f"  {PASS}  {label}")
        else:
            failed += 1
            print(f"  {FAIL}  {label}" + (f"  -- {detail}" if detail else ""))

    if not CONFIG_SCHEMA.exists() or not SEED_SCHEMA.exists():
        print(f"  {FAIL}  schema file(s) missing under {SCHEMA_DIR}")
        print("  Summary: 0 passed, 1 failed, 1 total")
        return 1

    cfg = json.loads(CONFIG_SCHEMA.read_text(encoding="utf-8"))
    seed = json.loads(SEED_SCHEMA.read_text(encoding="utf-8"))
    cdefs = cfg.get("definitions", {})
    sdefs = seed.get("definitions", {})

    # Authoritative inventory (config schema) vs what the seed schema admits.
    inventory = {
        "(top-level)": _props(cfg),
        "Common": _props(cdefs.get("Common", {})),
        "PatchBaseline": _props(cdefs.get("PatchBaseline", {})),
        "Pca2023": _props(cdefs.get("Pca2023", {})),
        "AutoRefreshPolicy": _props(cdefs.get("AutoRefreshPolicy", {})),
        "LanguageEntry": _props(cdefs.get("LanguageEntry", {})),
    }
    seed_admits = {
        "(top-level)": _props(seed),
        "Common": _props(sdefs.get("Common", {})),
        "PatchBaseline": _props(sdefs.get("PatchBaselineSeed", {})),
        "Pca2023": _props(sdefs.get("Pca2023", {})),
        "AutoRefreshPolicy": _props(sdefs.get("AutoRefreshPolicy", {})),
        "LanguageEntry": _props(sdefs.get("SeedLanguageEntry", {})),
    }

    # 1+2. COVERAGE + NO-OVERLAP + NO-SEED-EXTRA, per structured object.
    for obj, fields in inventory.items():
        seedset = seed_admits[obj]
        derset = DERIVED[obj]
        unclassified = fields - seedset - derset
        overlap = seedset & derset
        seed_extra = seedset - fields
        check(
            not (unclassified or overlap or seed_extra),
            f"coverage[{obj}]: every config-schema field is SEED xor DERIVED",
            f"unclassified={sorted(unclassified)} overlap={sorted(overlap)} seed_extra={sorted(seed_extra)}",
        )

    # 3. PROJECTION CONSISTENCY -- shared SEED definitions byte-equal to config schema.
    for name in ("Common", "Pca2023", "AutoRefreshPolicy"):
        check(
            sdefs.get(name) == cdefs.get(name),
            f"projection[{name}]: seed definition is byte-equal to config schema",
        )
    # PatchBaselineSeed = config PatchBaseline envelope, with DERIVED members forbidden.
    pbs = sdefs.get("PatchBaselineSeed", {})
    env = set(inventory["PatchBaseline"]) - DERIVED["PatchBaseline"]
    check(_props(pbs) == env, "projection[PatchBaselineSeed]: equals the PatchBaseline envelope",
          f"got={sorted(_props(pbs))} expected={sorted(env)}")
    check(pbs.get("additionalProperties") is False,
          "projection[PatchBaselineSeed]: additionalProperties:false forbids Lines + stamps")
    # SeedLanguageEntry = LanguageEntry minus the DERIVED LanguageSpecificPatches.
    sle = sdefs.get("SeedLanguageEntry", {})
    expected_le = set(inventory["LanguageEntry"]) - DERIVED["LanguageEntry"]
    check(_props(sle) == expected_le, "projection[SeedLanguageEntry]: LanguageEntry minus LanguageSpecificPatches",
          f"got={sorted(_props(sle))} expected={sorted(expected_le)}")

    # 4. SEED-FILE CONFORMANCE -- every seed file validates against the seed schema.
    seed_files = sorted(SEED_DIR.glob("seed-Server*.json"))
    check(len(seed_files) > 0, "seed files present under data/seed/")
    for sf in seed_files:
        try:
            obj = json.loads(sf.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            check(False, f"conformance[{sf.name}]: parseable JSON", str(exc))
            continue
        errors: list = []
        _validate(obj, seed, seed, "", errors)
        check(not errors, f"conformance[{sf.name}]: validates against config-seed.schema.json",
              "; ".join(errors[:3]))

    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
