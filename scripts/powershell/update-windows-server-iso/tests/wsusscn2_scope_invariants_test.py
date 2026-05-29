#!/usr/bin/env python3
"""wsusscn2 scope-invariants gate (SPEC B.19.7 allow-list / B.19.9 deny-list).

Validates the *scope contract* of the Layer 2 dependency database
(`data/wsusscn2-database.json`) and the T12 fixture
(`tests/fixtures/wsusscn2/expected-output.json`) against the empirically
established EOS/ESU exclusion model. It also unit-tests the allow-overrides
classification logic on synthetic cases.

Why this exists
---------------
Reverse-engineering of a real wsusscn2.cab (2026-05-12) established three
facts that govern which Server updates may enter the ISO-integration scope:

  1. (Recency / fallback, SPEC B.19.7) The newest in-scope LCU per supported
     OS is always retrievable; older months fall out of scope through normal
     supersession, bounded by the RecencyMonths window (default 24, 36
     settable, -1 disables). The invariant tested here is the floor of that
     behaviour: every allow-listed OS has at least one in-scope update.

  2. (EOS persistence, SPEC B.19.9) End-of-support OS product GUIDs
     (2008/2008 R2/2012/2012 R2) persist in wsusscn2 with live, payload-
     bearing updates indefinitely; EOS does NOT remove them from the cab.
     They must therefore be actively excluded, not assumed absent.

  3. (ESU integrated management, SPEC B.19.9) ESU monthly rollups for
     2012/2012 R2 (e.g. KB5087471, KB5063950, KB5063906) are carried in the
     same cab with the same leaf/bundle shape and the same SecurityUpdates
     classification as in-scope LCUs. The ONLY robust discriminator is the
     Product GUID. KB number, payload extension (.cab), and classification
     are all identical to in-scope LCUs and cannot be used to tell them
     apart.

The exclusion model is allow-overrides (NOT deny-overrides): an update is
in scope iff it carries at least one ALLOW Product GUID. An update carrying
ONLY deny-list GUIDs is excluded. An update carrying BOTH (e.g. the
multi-OS MSRT bundle KB890830, which legitimately applies to 2012 R2 AND
2016/2019) is admitted, because it is a valid update for the in-scope OS.
Empirically, 33 such "overlap" updates exist in the real cab; deny-overrides
would wrongly drop them.

Design constraints
------------------
Standard-library only (same rule as psa.py / config_schema_test.py). This
test executes NO PowerShell and downloads nothing: it is a pure data-driven
contract check over committed JSON plus synthetic in-memory cases. The
PowerShell implementation of the deny-list filter lands in a later session;
this gate fixes the contract that implementation must satisfy.

Invocation:
    python3 wsusscn2_scope_invariants_test.py
"""

from __future__ import annotations

import json
import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
DATA_DIR = SUBPROJECT_ROOT / "data"
LAYER2_PATH = DATA_DIR / "wsusscn2-database.json"
FIXTURE_PATH = TESTS_DIR / "fixtures" / "wsusscn2" / "expected-output.json"

# ---------------------------------------------------------------------------
# Scope GUID tables (lowercase). Verified against a real wsusscn2.cab
# (2026-05-12, sha256 e51d4b5a...) and cross-referenced with the WSUS
# Offline community product-GUID list. SPEC B.19.7 / B.19.9.
# ---------------------------------------------------------------------------

# ALLOW-list: supported, ISO-integration-eligible Server OS product GUIDs.
ALLOW_PRODUCT_GUIDS = {
    "569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5": "Windows Server 2016",
    "f702a48c-919b-45d6-9aef-ca4248d50397": "Windows Server 2019",
    "71718f13-7324-4b0f-8f9e-2ca9dc978e53": "Windows Server 2022",
    "b256987d-4693-4c87-955d-dbb9341205eb": "Windows Server 2025",
}

# DENY-list: EOS / ESU-only Server OS product GUIDs. Present in wsusscn2 with
# live payload-bearing updates (incl. ESU monthly rollups) but out of ISO
# integration scope. Explicit deny is defence-in-depth on top of the
# allow-list and makes the intent auditable.
DENY_PRODUCT_GUIDS = {
    "ba0ae9cc-5f01-40b4-ac3f-50192b5d6aaf": "Windows Server 2008",
    "fdfe8200-9d98-44ba-a12a-772282bf60ef": "Windows Server 2008 R2",
    "a105a108-7c9b-4518-bbbe-73f0fe30012b": "Windows Server 2012",
    "d31bd4c3-d872-41c9-a2e7-231f372588cb": "Windows Server 2012 R2",
}

# Known ESU / EOS KB numbers that must NEVER appear in an in-scope payload
# URL. Drawn from the 2026-05-12 cab investigation and community KB lists.
# (KB890830 is deliberately NOT here: it is the multi-OS MSRT bundle that
# also carries an allow-list GUID and is legitimately in scope.)
ESU_EOS_KB_BLOCKLIST = {
    "5087471": "Server 2012 R2 Monthly Rollup (ESU) 2026-05",
    "5082126": "Server 2012 R2 Monthly Rollup (ESU) 2026-04",
    "5078775": "Server 2012 R2 Monthly Rollup (ESU) 2026-03",
    "5075970": "Server 2012 R2 Monthly Rollup (ESU) 2026-02",
    "5063950": "Server 2012 R2 ESU 2025-08",
    "5063906": "Server 2012 ESU 2025-08",
}


# ---------------------------------------------------------------------------
# The contract function under test: allow-overrides classification.
# This is the reference semantics the PowerShell deny-list filter must match
# in a later session. SPEC B.19.9.
# ---------------------------------------------------------------------------

def classify_scope(product_guids):
    """Return 'in-scope' or 'excluded' for a set/list of Product GUIDs,
    applying allow-overrides semantics.

    in-scope  iff at least one ALLOW guid is present
    excluded  otherwise (this includes the deny-only case and the
              no-known-guid case)
    """
    guids = {g.lower() for g in product_guids}
    has_allow = any(g in ALLOW_PRODUCT_GUIDS for g in guids)
    return "in-scope" if has_allow else "excluded"


# ---------------------------------------------------------------------------
# Test infrastructure (mirrors config_schema_test.py / wsusscn2_parser_test.py)
# ---------------------------------------------------------------------------

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


def _load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def _payload_kbs(update):
    """Extract bare KB digits from an update's payloadUrls."""
    import re
    kbs = set()
    for url in (update.get("payloadUrls") or []):
        for m in re.finditer(r"kb(\d+)", url, re.IGNORECASE):
            kbs.add(m.group(1))
    return kbs


# ---------------------------------------------------------------------------
# Section A: GUID-table self-consistency (pure, no data files)
# ---------------------------------------------------------------------------

def check_guid_tables(r):
    print("Section A: scope GUID-table self-consistency")
    # A1: allow and deny are disjoint
    overlap = set(ALLOW_PRODUCT_GUIDS) & set(DENY_PRODUCT_GUIDS)
    r.assert_eq("A1 allow-list and deny-list are disjoint", overlap, set())
    # A2: all GUIDs lowercase canonical
    all_lower = all(g == g.lower() for g in
                    list(ALLOW_PRODUCT_GUIDS) + list(DENY_PRODUCT_GUIDS))
    r.assert_true("A2 all scope GUIDs are lowercase-canonical", all_lower)
    # A3: expected membership
    r.assert_eq("A3 allow-list has exactly 4 supported Server OS",
                len(ALLOW_PRODUCT_GUIDS), 4)
    r.assert_eq("A4 deny-list has exactly 4 EOS/ESU Server OS",
                len(DENY_PRODUCT_GUIDS), 4)


# ---------------------------------------------------------------------------
# Section B: allow-overrides classification logic (synthetic cases)
# ---------------------------------------------------------------------------

def check_classification_logic(r):
    print()
    print("Section B: allow-overrides classification logic (synthetic)")
    ws2016 = "569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5"
    ws2019 = "f702a48c-919b-45d6-9aef-ca4248d50397"
    ws2012r2 = "d31bd4c3-d872-41c9-a2e7-231f372588cb"
    ws2012 = "a105a108-7c9b-4518-bbbe-73f0fe30012b"

    # B1: pure in-scope LCU (2016 only) -> in-scope
    r.assert_eq("B1 in-scope LCU (2016 only) -> in-scope",
                classify_scope([ws2016]), "in-scope")
    # B2: ESU-only rollup (2012 R2 only) -> excluded
    r.assert_eq("B2 ESU rollup (2012 R2 only) -> excluded",
                classify_scope([ws2012r2]), "excluded")
    # B3: ESU-only rollup (2012 only) -> excluded
    r.assert_eq("B3 ESU rollup (2012 only) -> excluded",
                classify_scope([ws2012]), "excluded")
    # B4: multi-OS overlap (2012 R2 + 2016, e.g. MSRT KB890830) -> in-scope
    #     This is the deny-overrides trap: must NOT be excluded.
    r.assert_eq("B4 overlap bundle (2012 R2 + 2016) -> in-scope (allow wins)",
                classify_scope([ws2012r2, ws2016]), "in-scope")
    # B5: overlap with all four EOS + one allow -> in-scope
    r.assert_eq("B5 overlap (all 4 deny + 2019) -> in-scope (allow wins)",
                classify_scope(list(DENY_PRODUCT_GUIDS) + [ws2019]), "in-scope")
    # B6: empty / unknown product -> excluded
    r.assert_eq("B6 no known product GUID -> excluded",
                classify_scope([]), "excluded")
    # B7: case-insensitivity (uppercase allow GUID) -> in-scope
    r.assert_eq("B7 uppercase allow GUID is recognised -> in-scope",
                classify_scope([ws2016.upper()]), "in-scope")


# ---------------------------------------------------------------------------
# Section C: contract over a loaded Layer 2 document
# ---------------------------------------------------------------------------

def check_layer2_doc(r, prefix, doc):
    scope = doc.get("_meta", {}).get("scope", {})
    scope_prod = {g.lower() for g in scope.get("productGuids", [])}
    updates = doc.get("updates", [])

    # C1: scope.productGuids contains NO deny-list GUID
    deny_in_scope = scope_prod & set(DENY_PRODUCT_GUIDS)
    r.assert_eq(f"{prefix} scope.productGuids excludes all deny-list GUIDs",
                deny_in_scope, set())

    # C2: scope.productGuids is a subset of the allow-list
    unknown = scope_prod - set(ALLOW_PRODUCT_GUIDS)
    r.assert_eq(f"{prefix} scope.productGuids subset of allow-list",
                unknown, set())

    # C3: every in-scope update carries at least one allow-list GUID
    #     (equivalently: classify_scope == 'in-scope' for all)
    bad = [u.get("updateId", "?")[:8] for u in updates
           if classify_scope(u.get("productGuids", [])) != "in-scope"]
    r.assert_eq(f"{prefix} every update classifies in-scope (allow-overrides)",
                bad, [])

    # C4: no in-scope update carries ONLY deny-list GUIDs
    deny_only = []
    for u in updates:
        guids = {g.lower() for g in u.get("productGuids", [])}
        if guids and guids <= set(DENY_PRODUCT_GUIDS):
            deny_only.append(u.get("updateId", "?")[:8])
    r.assert_eq(f"{prefix} no update is deny-only (EOS/ESU leak)",
                deny_only, [])

    # C5: no in-scope payload references a known ESU/EOS blocklist KB
    leaked = []
    for u in updates:
        for kb in _payload_kbs(u):
            if kb in ESU_EOS_KB_BLOCKLIST:
                leaked.append((u.get("updateId", "?")[:8], kb))
    r.assert_eq(f"{prefix} no in-scope payload references an ESU/EOS KB",
                leaked, [])

    return scope_prod, updates


# ---------------------------------------------------------------------------
# Section D: recency / fallback floor (production only)
# ---------------------------------------------------------------------------

def check_recency_floor(r, scope_prod, updates):
    print()
    print("Section D: recency/fallback floor (production)")
    # D1: at least one in-scope update exists per allow-listed OS that is in
    #     this document's scope. This is the floor of the SPEC B.19.7
    #     fallback guarantee: the newest patch per supported OS is always
    #     retrievable. (Only checked for OS actually present in scope.)
    per_os = {g: 0 for g in scope_prod}
    for u in updates:
        for g in (u.get("productGuids") or []):
            gl = g.lower()
            if gl in per_os:
                per_os[gl] += 1
    missing = [ALLOW_PRODUCT_GUIDS.get(g, g) for g, n in per_os.items() if n == 0]
    r.assert_eq("D1 each scoped allow-list OS has >=1 in-scope update",
                missing, [])
    # D2: recencyMonths is one of the supported settings (24 / 36 / -1)
    #     -1 disables; positive values bound the creation-date window.
    # (read from production doc scope below in main)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("wsusscn2 scope-invariants gate (EOS/ESU deny-list, allow-overrides)")
    print(f"  layer2:  {LAYER2_PATH}")
    print(f"  fixture: {FIXTURE_PATH}")
    print()

    r = TestResult()

    check_guid_tables(r)
    check_classification_logic(r)

    # Production document (real, monthly-refreshed data)
    print()
    print("Section C: contract over production data/wsusscn2-database.json")
    prod = _load(LAYER2_PATH)
    prod_scope, prod_updates = check_layer2_doc(r, "C-prod", prod)

    # Fixture document (fixed, reproducible)
    print()
    print("Section C: contract over fixture expected-output.json")
    fix = _load(FIXTURE_PATH)
    check_layer2_doc(r, "C-fix", fix)

    # Recency floor + recencyMonths setting (production)
    check_recency_floor(r, prod_scope, prod_updates)
    recency = prod.get("_meta", {}).get("scope", {}).get("recencyMonths")
    r.assert_true("D2 recencyMonths is a supported setting (24/36/-1)",
                  recency in (24, 36, -1),
                  f"recencyMonths={recency!r}")

    return r.summary()


if __name__ == "__main__":
    sys.exit(main())
