"""
wsusscn2 Layer 2 schema gate (offline, stdlib-only).

Validates the committed Layer 2 dependency database
(data/servicing-dependency-database.json) against its authoritative JSON Schema
(schema/servicing-dependency-database.schema.json), and asserts the M1 data-quality
invariants that the schema alone cannot express. This is the gate that
keeps the shipped, cab-derived Layer 2 in sync with the contract as the
M1 increments populate it.

No T-number: it is a data gate, mirroring the config-schema-gate and
canonical-format-gate convention. It reuses the draft-07-subset validator
shipped in config_schema_test.py so there is a single validator
implementation in the suite.

Checks:
  * The committed DB validates against the schema (0 errors).
  * _meta carries the shared data-contract identity (dataContractId +
    dataContractVersion) and portable provenance (sourceCab.sourceUrl,
    no filesystem path; scope.evaluatedAt).
  * Every update carries a kbIds array (M1 populate), and the KB tokens
    are bare numeric strings (no 'KB' prefix, SPEC B.19.8).
  * The Microsoft-prose hard rule (SPEC B.19.8): the serialized document
    contains none of the forbidden prose markers.
  * servicing-stack fields, when present, use the allowed enum for
    servicingStackModel and are null or string for the version fields
    (forward-compatible with the later SS-population increment).

Invocation:
    python3 wsusscn2_layer2_schema_test.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
SUBPROJECT_DIR = TEST_DIR.parent
SCHEMA_PATH = SUBPROJECT_DIR / "schema" / "servicing-dependency-database.schema.json"
DB_PATH = SUBPROJECT_DIR / "data" / "servicing-dependency-database.json"

# Reuse the single draft-07-subset validator in the suite.
sys.path.insert(0, str(TEST_DIR))
import config_schema_test as cst  # noqa: E402

# Microsoft-prose markers that MUST NOT appear in the committed Layer 2
# (SPEC B.19.8 hard rule).
PROSE_MARKERS = (
    "Cumulative Update",
    "Servicing Stack Update",
    "Security Update for",
    "applies to",
    '"title"',
    '"description"',
    '"moreInfoUrl"',
)


class TestResult:
    def __init__(self):
        self.passed = 0
        self.failed = []

    def assert_eq(self, name, actual, expected):
        if actual == expected:
            self.passed += 1
            print(f"  [PASS] {name}")
        else:
            self.failed.append((name, f"expected={expected!r} actual={actual!r}"))
            print(f"  [FAIL] {name}: expected={expected!r} actual={actual!r}")

    def assert_true(self, name, cond, detail=""):
        if cond:
            self.passed += 1
            print(f"  [PASS] {name}")
        else:
            self.failed.append((name, detail or "condition false"))
            print(f"  [FAIL] {name}: {detail or 'condition false'}")

    def summary(self):
        total = self.passed + len(self.failed)
        print()
        print(f"Summary: {self.passed} passed, {len(self.failed)} failed, {total} total")
        return 0 if not self.failed else 1


def main() -> int:
    print("wsusscn2 Layer 2 schema gate")
    print(f"  schema: {SCHEMA_PATH}")
    print(f"  data:   {DB_PATH}")
    print()

    r = TestResult()

    r.assert_true("01 schema file exists", SCHEMA_PATH.exists())
    r.assert_true("02 committed Layer 2 database exists", DB_PATH.exists())
    if not (SCHEMA_PATH.exists() and DB_PATH.exists()):
        return r.summary()

    raw = DB_PATH.read_text(encoding="utf-8")
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    db = json.loads(raw)

    # ---- 1. Full schema validation ----
    errors = cst.validate_instance(db, schema)
    if errors:
        print("  --- schema validation errors (first 10) ---")
        for e in errors[:10]:
            print(f"      {e}")
    r.assert_eq("03 committed Layer 2 validates against schema (0 errors)", errors, [])

    meta = db.get("_meta", {})

    # ---- 2. Data-contract identity ----
    r.assert_true("04 _meta.dataContractId present", bool(meta.get("dataContractId")))
    r.assert_true("05 _meta.dataContractVersion present", isinstance(meta.get("dataContractVersion"), int))

    # ---- 3. Portable provenance ----
    src = meta.get("sourceCab", {})
    r.assert_true("06 _meta.sourceCab.sourceUrl present", bool(src.get("sourceUrl")))
    r.assert_true("07 _meta.sourceCab carries no filesystem path", "path" not in src)
    r.assert_true("08 _meta.scope.evaluatedAt present", bool(meta.get("scope", {}).get("evaluatedAt")))
    r.assert_true("09 _meta.scope carries no legacy 'now' field", "now" not in meta.get("scope", {}))

    updates = db.get("updates", [])
    r.assert_true("10 database has at least one in-scope update", len(updates) > 0)

    # ---- 4. kbIds populate + numeric form ----
    all_have_kbids = all("kbIds" in u for u in updates)
    r.assert_true("11 every update carries a kbIds array (M1 populate)", all_have_kbids)

    bad_kb = []
    for u in updates:
        for kb in (u.get("kbIds") or []):
            if not (isinstance(kb, str) and kb.isdigit()):
                bad_kb.append((u.get("revisionId"), kb))
    r.assert_eq("12 all kbIds are bare numeric strings (no 'KB' prefix; SPEC B.19.8)", bad_kb, [])

    nonempty = sum(1 for u in updates if u.get("kbIds"))
    r.assert_true("13 at least one update has a recovered KB id",
                  nonempty > 0, f"non-empty kbIds count={nonempty}")

    # ---- 5. Microsoft-prose hard rule ----
    prose_hits = [m for m in PROSE_MARKERS if m in raw]
    r.assert_eq("14 no Microsoft-prose markers in committed Layer 2 (SPEC B.19.8)", prose_hits, [])

    # ---- 6. servicing-stack fields, when present, are well-formed ----
    bad_model = []
    bad_ver = []
    for u in updates:
        if "servicingStackModel" in u:
            if u["servicingStackModel"] not in ("separate", "combined", "checkpoint", None):
                bad_model.append((u.get("revisionId"), u["servicingStackModel"]))
        for f in ("requiredServicingStackVersion", "providedServicingStackVersion"):
            if f in u and not (u[f] is None or isinstance(u[f], str)):
                bad_ver.append((u.get("revisionId"), f, u[f]))
    r.assert_eq("15 servicingStackModel (when present) uses the allowed enum", bad_model, [])
    r.assert_eq("16 servicing-stack version fields (when present) are null or string", bad_ver, [])

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
