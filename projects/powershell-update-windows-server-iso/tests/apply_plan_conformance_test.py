#!/usr/bin/env python3
"""T41: apply-plan declaration conformance (D-contract, offline, no REPL).

Anchor: `ServicingModel.ApplyPlans` + `PatchBaseline.Lines[].Roles` +
`PatchBaseline.Lines[].TargetsByRole` -- all `CanonicalV4Fields`.

What this asserts: the servicing declaration in each committed config is
internally coherent and complete. Every role a Line claims has declared
targets; every declared target lane has an apply plan; every lane's plan is
strictly ordered and its steps declare roles or are known image-only steps;
and every role routed to a lane is consumable by some step of that lane's
plan (a role no step consumes is a silent no-op).

Why pure data: the declaration IS the contract. If it is incoherent, no
runtime behaviour can be correct, and asserting behaviour first would only
report the symptom.

Why it is a D-contract: the routing matrix used to be four hand-written
per-OS branches asserting Microsoft's servicing model directly (bridge LCU on
2022 only; Setup DU on the uup-checkpoint OS only; SafeOS DU per generation).
Each was a claim baked into the test. They are now declared per Line, so this
contract reads them. Nothing per-OS is hardcoded below.

Supersedes the routing / apply-map halves of the retired T27 / T32 / T33.

Convergence: IN-FORCE wherever the configs carry `ServicingModel.ApplyPlans`
and `Lines[].TargetsByRole`; NOT-YET before that.

Deferred: behavioural routing conformance. `Get-ConfiguredBootWimUpdateModel`
falls back to `FullLCU` when no OS profile is loaded, so driving
`Build-PatchPlan` from a bare TestHarness session tests a default rather than
the declaration. A D-contract must establish the same declaration context the
runtime uses; that contract is authored separately.

Run from the project root:

    python3 tests/apply_plan_conformance_test.py
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

# Lane vocabulary. "Media" is the declared name of the lane the runtime plan
# calls "Setup"; the mapping is part of the contract and is stated, not
# silently absorbed.
LANES = ("Install", "Boot", "WinRE", "Media")

# Steps that consume no role: they act on the image or the media, not on a
# package.
ROLELESS_STEPS = {"Cleanup", "Export", "ExportRecovery", "Redistribute",
                  "CopySetupExe", "CopySetupHost", "CopyBootManager",
                  "BuildIso"}


def check(label, ok, detail, p, f):
    print(f"{PASS if ok else FAIL}  {label}: {detail}")
    return (p + 1, f) if ok else (p, f + 1)


def main() -> int:
    passed = failed = skipped = 0

    print("=" * 72)
    print("T41 apply-plan declaration conformance (D-contract)")
    print("=" * 72)

    for fname in CONFIGS:
        fpath = DATA_DIR / fname
        if not fpath.exists():
            print(f"{FAIL}  {fname}: not found under data/")
            failed += 1
            continue
        cfg = json.loads(fpath.read_text(encoding="utf-8-sig"))
        sm = cfg.get("ServicingModel") or {}
        plans = sm.get("ApplyPlans") or {}
        lines = (cfg.get("PatchBaseline") or {}).get("Lines") or []
        anchored = [ln for ln in lines if ln.get("TargetsByRole")]

        if not plans or not anchored:
            print(f"{SKIP}  {fname}: NOT-YET -- ApplyPlans={bool(plans)}, "
                  f"anchored Lines={len(anchored)}")
            skipped += 1
            continue

        print(f"=== {fname} ===")

        declared_lanes = set(plans)
        routed_lanes = {t for ln in anchored
                        for tl in (ln.get("TargetsByRole") or {}).values()
                        for t in (tl or [])}
        passed, failed = check(
            f"{fname}: every routed lane has an apply plan",
            routed_lanes <= declared_lanes,
            f"routed={sorted(routed_lanes)} planned={sorted(declared_lanes)}",
            passed, failed)
        unknown = routed_lanes - set(LANES)
        passed, failed = check(
            f"{fname}: lane vocabulary is known",
            not unknown,
            f"unknown={sorted(unknown)}" if unknown else "all known",
            passed, failed)

        for ln in anchored:
            kind = ln.get("Kind")
            roles = set(ln.get("Roles") or [])
            tbr = ln.get("TargetsByRole") or {}
            passed, failed = check(
                f"{fname} {kind}: Roles and TargetsByRole agree",
                roles == set(tbr),
                f"Roles={sorted(roles)} keys={sorted(tbr)}", passed, failed)
            empty = [r for r, t in tbr.items() if not t]
            passed, failed = check(
                f"{fname} {kind}: every role declares at least one target",
                not empty,
                f"roles with no target: {empty}" if empty else "all populated",
                passed, failed)

        for lane, steps in plans.items():
            orders = [s.get("Order") for s in steps]
            passed, failed = check(
                f"{fname} {lane}: apply plan is strictly ordered",
                orders == sorted(orders) and len(set(orders)) == len(orders),
                f"orders={orders}", passed, failed)
            bad = [s.get("Step") for s in steps
                   if not s.get("Roles")
                   and s.get("Step") not in ROLELESS_STEPS]
            passed, failed = check(
                f"{fname} {lane}: steps declare roles or are known "
                f"image-only steps",
                not bad,
                f"undeclared roleless steps: {bad}" if bad else "ok",
                passed, failed)
            no_cond = [s.get("Step") for s in steps if not s.get("Condition")]
            passed, failed = check(
                f"{fname} {lane}: every step declares a Condition",
                not no_cond,
                f"missing: {no_cond}" if no_cond else "all declared",
                passed, failed)

        for ln in anchored:
            for role, targets in (ln.get("TargetsByRole") or {}).items():
                for lane in targets or []:
                    steps = plans.get(lane) or []
                    consumers = [s.get("Step") for s in steps
                                 if role in (s.get("Roles") or [])]
                    passed, failed = check(
                        f"{fname} {ln.get('Kind')}/{role} -> {lane}: "
                        f"consumed by a step",
                        bool(consumers),
                        f"step(s)={consumers}" if consumers
                        else f"no step in the {lane} plan consumes {role!r}",
                        passed, failed)

        model = sm.get("PackageRoleModel")
        multi = [ln.get("Kind") for ln in anchored
                 if len(ln.get("Roles") or []) > 1]
        passed, failed = check(
            f"{fname}: PackageRoleModel is declared",
            bool(model), f"PackageRoleModel={model!r}", passed, failed)
        if multi:
            passed, failed = check(
                f"{fname}: multi-role assets are permitted by the model",
                model == "OneAssetMayServeMultipleRoles",
                f"multi-role Lines={multi} under model={model!r}",
                passed, failed)
        print()

    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total"
          + (f", {skipped} NOT-YET" if skipped else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
