#!/usr/bin/env python3
"""T44: compatibility-declaration self-verification (D-contract, offline).

Anchor: `Compatibility.LegacyFieldsRetained` / `Compatibility.CanonicalV4Fields`.

This is the meta-contract that makes the whole declaration model
self-verifying, and it is the one that would have prevented the merge-#1
misclassifications. The config states which fields are legacy and which are
canonical; this contract holds the repository to that statement:

  1. Every field named in `CanonicalV4Fields` is actually present. A canonical
     field that is declared but absent means the config claims a model it does
     not implement.
  2. Every field named in `LegacyFieldsRetained` that is present has a
     canonical counterpart also present. A legacy field surviving *alone* is
     not compatibility -- it is the old model still load-bearing.
  3. `LegacySchema` and `Schema` are both declared and differ, so the
     compatibility window is explicit rather than implied.
  4. The two lists are disjoint. A field cannot be both the legacy path and
     the canonical one.

Why this matters for the merge: a test that asserts a field listed in
`LegacyFieldsRetained` is asserting the superseded model. This contract makes
that detectable mechanically instead of by review.

Convergence: IN-FORCE wherever `Compatibility` exists; NOT-YET before.

Run from the project root:

    python3 tests/compatibility_declaration_test.py
"""
from __future__ import annotations

import json
import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
DATA_DIR = TESTS_DIR.parent / "data"

PASS = "  PASS"
FAIL = "  FAIL"
SKIP = "  SKIP"

CONFIGS = ("config-Server2016.json", "config-Server2019.json",
           "config-Server2022.json", "config-Server2025.json")

# Legacy field -> the canonical surface that must also be present for the
# retention to be a compatibility path rather than a survival of the old
# model. Derived from the declaration itself, stated here so a mapping that
# stops holding is visible rather than silent.
LEGACY_TO_CANONICAL = {
    "PatchModel": "ServicingModel",
    "Common.BootWimLcuPolicy": "ServicingModel",
    "PatchBaseline.Lines[].Digest": "PatchBaseline.Lines[].Integrity",
    "PatchBaseline.Lines[].Sha256": "PatchBaseline.Lines[].Integrity",
    "PatchBaseline.Lines[].ApplyOrder": "ServicingModel",
    "Common.InstallWimIndex": "ServicingModel",
}


def check(label, ok, detail, p, f):
    print(f"{PASS if ok else FAIL}  {label}: {detail}")
    return (p + 1, f) if ok else (p, f + 1)


def resolve(cfg, path):
    """Resolve a dotted declaration path, supporting the Lines[] element form."""
    node = cfg
    for part in path.split("."):
        if part.endswith("[]"):
            key = part[:-2]
            if not isinstance(node, dict) or key not in node:
                return None, False
            node = node[key]
            if not isinstance(node, list) or not node:
                return None, False
            node = node[0]
            continue
        if not isinstance(node, dict) or part not in node:
            return None, False
        node = node[part]
    return node, True


def main() -> int:
    passed = failed = skipped = 0

    print("=" * 72)
    print("T44 compatibility-declaration self-verification (D-contract)")
    print("=" * 72)

    for fname in CONFIGS:
        fpath = DATA_DIR / fname
        if not fpath.exists():
            print(f"{FAIL}  {fname}: not found under data/")
            failed += 1
            continue
        cfg = json.loads(fpath.read_text(encoding="utf-8-sig"))
        compat = cfg.get("Compatibility")
        if not compat:
            print(f"{SKIP}  {fname}: NOT-YET -- no Compatibility declaration")
            skipped += 1
            continue

        print(f"=== {fname} ===")
        legacy = list(compat.get("LegacyFieldsRetained") or [])
        canon = list(compat.get("CanonicalV4Fields") or [])

        passed, failed = check(
            f"{fname}: the compatibility window is explicit",
            bool(compat.get("LegacySchema")) and bool(cfg.get("Schema"))
            and compat.get("LegacySchema") != cfg.get("Schema"),
            f"Schema={cfg.get('Schema')!r} LegacySchema="
            f"{compat.get('LegacySchema')!r}", passed, failed)

        overlap = sorted(set(legacy) & set(canon))
        passed, failed = check(
            f"{fname}: legacy and canonical lists are disjoint",
            not overlap,
            f"overlap={overlap}" if overlap else "disjoint", passed, failed)

        for field in canon:
            _, present = resolve(cfg, field)
            passed, failed = check(
                f"{fname}: canonical field present -- {field}",
                present,
                "present" if present
                else "declared canonical but absent from the config",
                passed, failed)

        for field in legacy:
            _, present = resolve(cfg, field)
            if not present:
                # A legacy field already gone is the desired end state.
                passed, failed = check(
                    f"{fname}: legacy field already retired -- {field}",
                    True, "absent", passed, failed)
                continue
            counterpart = LEGACY_TO_CANONICAL.get(field)
            if counterpart is None:
                passed, failed = check(
                    f"{fname}: legacy field has a mapped counterpart -- {field}",
                    False,
                    "no canonical counterpart mapped -- extend "
                    "LEGACY_TO_CANONICAL deliberately", passed, failed)
                continue
            _, canon_present = resolve(cfg, counterpart)
            passed, failed = check(
                f"{fname}: legacy field is a compatibility path -- {field}",
                canon_present,
                f"canonical counterpart {counterpart} "
                f"{'present' if canon_present else 'ABSENT -- the legacy field '
                                                  'is still load-bearing'}",
                passed, failed)
        print()

    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total"
          + (f", {skipped} NOT-YET" if skipped else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
