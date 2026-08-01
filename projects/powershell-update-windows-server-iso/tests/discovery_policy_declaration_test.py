#!/usr/bin/env python3
"""T46: discovery-policy declaration conformance (D-contract, offline).

Anchor: `DiscoveryPolicy` -- `CatalogAliases`, `SearchProfiles`,
`ReleaseChannel`, `ExcludePreview`, `DynamicUpdateSelection` and companions.

This is the declaration half of the replacement for the retired T28 (Setup DU
Forbid matrix) and the scheduled replacement for T30 (Setup DU discriminator).
The behavioural half -- does a live Catalog resolution actually honour these
profiles -- belongs to the live-network tier alongside T1 and T4, because
under the r12 model discovery *is* an online operation. Writing it as an
offline text scan, as an earlier draft of T28 did, verifies the resolver's
source code rather than the resolver.

What this asserts:

  1. **Every Kind that appears in the baseline has a search profile.** A Kind
     the pipeline must resolve but for which no discovery rule is declared is
     the silent-starvation shape this project has been bitten by before.
  2. **Every profile names a query strategy and an architecture.** A profile
     without a strategy is a title-string heuristic waiting to be invented at
     the call site.
  3. **Filter rules are lists of non-empty strings**, and the include and
     exclude sets do not contradict each other (a term required and forbidden
     at the same time can never match).
  4. **Catalog aliases are declared for the OS naming split.** Microsoft
     renamed the product between Server 2019 and Server 2022 ("Windows Server
     2019" vs "Microsoft server operating system, version 21H2"), so a single
     OS token cannot address all four generations. The alias table is the
     declared answer; this contract checks it exists and carries a build
     family to key on -- it does not restate which name belongs to which OS,
     because that is precisely the per-OS knowledge the series moved into data.
  5. **The Setup DU profile carries an exclusion rule.** Discovery by title on
     the Catalog is a known fragility surface; the profile's
     `ProductsMustNotContain` is the structural guard against a neighbouring
     Dynamic Update product being selected. Its presence is the contract; the
     specific terms are read, not asserted.

Supersedes the retired T28. T30 stays SUPERSEDED-PENDING until the
live-network half is authored: this contract shows the exclusion rule is
declared, not that a resolution honours it.

Convergence: IN-FORCE wherever `DiscoveryPolicy.SearchProfiles` exists.

Run from the project root:

    python3 tests/discovery_policy_declaration_test.py
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

INCLUDE_RULES = ("TitleMustContain", "ProductsMustContain",
                 "ClassificationMustBe")
EXCLUDE_RULES = ("RejectTitleContains", "ProductsMustNotContain")
ALL_RULES = INCLUDE_RULES + EXCLUDE_RULES

# Kinds that are resolved by a prerequisite declaration rather than by a
# discovery search, so they need no SearchProfile of their own.
PREREQUISITE_KINDS = {"Checkpoint", "CheckpointChain", "BridgeLCU", "BridgeLcu"}


def check(label, ok, detail, p, f):
    print(f"{PASS if ok else FAIL}  {label}: {detail}")
    return (p + 1, f) if ok else (p, f + 1)


def main() -> int:
    passed = failed = skipped = 0

    print("=" * 72)
    print("T46 discovery-policy declaration conformance (D-contract)")
    print("=" * 72)

    for fname in CONFIGS:
        fpath = DATA_DIR / fname
        if not fpath.exists():
            print(f"{FAIL}  {fname}: not found under data/")
            failed += 1
            continue
        cfg = json.loads(fpath.read_text(encoding="utf-8-sig"))
        dp = cfg.get("DiscoveryPolicy") or {}
        profiles = dp.get("SearchProfiles") or {}
        if not profiles:
            print(f"{SKIP}  {fname}: NOT-YET -- no DiscoveryPolicy."
                  f"SearchProfiles declared")
            skipped += 1
            continue

        print(f"=== {fname} ===")
        lines = (cfg.get("PatchBaseline") or {}).get("Lines") or []
        kinds = {ln.get("Kind") for ln in lines if ln.get("Kind")}
        need = {k for k in kinds if k not in PREREQUISITE_KINDS}

        passed, failed = check(
            f"{fname}: every discoverable baseline Kind has a search profile",
            need <= set(profiles),
            f"baseline Kinds={sorted(kinds)} profiled={sorted(profiles)}"
            + (f" MISSING={sorted(need - set(profiles))}"
               if need - set(profiles) else ""),
            passed, failed)

        aliases = dp.get("CatalogAliases") or {}
        passed, failed = check(
            f"{fname}: Catalog aliases are declared for the OS naming split",
            bool(aliases.get("OsUpdate")) and bool(aliases.get("DynamicUpdate")),
            f"OsUpdate={str(aliases.get('OsUpdate'))[:44]!r} "
            f"DynamicUpdate={str(aliases.get('DynamicUpdate'))[:44]!r}",
            passed, failed)
        passed, failed = check(
            f"{fname}: a build family is declared to key resolution on",
            bool(str(aliases.get("BuildFamily") or "").strip()),
            f"BuildFamily={aliases.get('BuildFamily')!r}", passed, failed)

        for key in ("ReleaseChannel", "ExcludePreview", "DynamicUpdateSelection",
                    "DotNetSelection"):
            passed, failed = check(
                f"{fname}: {key} is declared",
                key in dp, f"{key}={dp.get(key)!r}", passed, failed)

        for kind in sorted(profiles):
            prof = profiles[kind] or {}
            tag = f"{fname} {kind}"
            passed, failed = check(
                f"{tag}: declares a query strategy",
                bool(prof.get("QueryStrategy")),
                f"QueryStrategy={prof.get('QueryStrategy')!r}", passed, failed)
            passed, failed = check(
                f"{tag}: declares an architecture",
                bool(prof.get("Architecture")),
                f"Architecture={prof.get('Architecture')!r}", passed, failed)

            malformed = [r for r in ALL_RULES if r in prof
                         and (not isinstance(prof[r], list)
                              or not prof[r]
                              or any(not isinstance(t, str) or not t.strip()
                                     for t in prof[r]))]
            passed, failed = check(
                f"{tag}: filter rules are non-empty string lists",
                not malformed,
                f"malformed={malformed}" if malformed
                else f"rules={[r for r in ALL_RULES if r in prof]}",
                passed, failed)

            inc = {t for r in INCLUDE_RULES for t in (prof.get(r) or [])}
            exc = {t for r in EXCLUDE_RULES for t in (prof.get(r) or [])}
            clash = sorted(inc & exc)
            passed, failed = check(
                f"{tag}: include and exclude rules do not contradict",
                not clash,
                f"required and forbidden: {clash}" if clash else "consistent",
                passed, failed)

        if "SetupDU" in profiles:
            prof = profiles["SetupDU"]
            excl = [r for r in EXCLUDE_RULES if prof.get(r)]
            passed, failed = check(
                f"{fname} SetupDU: carries an exclusion rule against "
                f"neighbouring products",
                bool(excl),
                f"declared exclusions={{" + ", ".join(
                    f"{r}={prof[r]}" for r in excl) + "}"
                if excl else "no exclusion rule -- a neighbouring Dynamic "
                             "Update product can be selected",
                passed, failed)
        print()

    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total"
          + (f", {skipped} NOT-YET" if skipped else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
