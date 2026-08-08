#!/usr/bin/env python3
"""T42: servicing-model declaration conformance (D-contract, offline, no REPL).

Anchors, all `CanonicalV4Fields` or their declared companions:
  - `PatchBaseline.SourcePrerequisites[]` (+ `.Condition`, `.Asset`)
  - `ServicingModel.SourcePrerequisitePolicy`
  - `Common.BootWimUpdateModel`
  - `ValidationPolicy`

What this asserts:

  1. **Source prerequisites are uniformly shaped.** The Server 2022 bridge LCU
     and the Server 2016 legacy SSU are the same structure with a different
     `Condition.Mode`. Every prerequisite declares roles, targets, a condition
     mode from the known vocabulary, a non-empty detection list, and an asset
     with an identity.
  2. **Floors live in the declaration.** A mode that compares against a floor
     must declare the floor it compares against. This replaces the four
     hardcoded 2024-4B build constants the retired T37 carried.
  3. **The boot model and the Line routing agree.** `Common.BootWimUpdateModel`
     selects how boot.wim is serviced; the Lines' `TargetsByRole` must route
     the Boot lane consistently with that selection. This is the check that
     catches a legacy field and a canonical field disagreeing.
  4. **The validation policy is well-formed** and its evidence-bound flags are
     identified, so an E-contract lane can consume them rather than a sandbox
     pretending to prove them.

Why it is a D-contract: everything above used to be per-OS knowledge written
into tests -- "2022 needs a bridge LCU", "2016's floor is 14393.6897",
"2019 disables boot.wim LCU servicing". All of it is now declared, so this
contract reads the declaration instead of restating Microsoft's model.

Supersedes the retired T31, T34, T37 and the envelope half of T33.

Convergence: IN-FORCE wherever `PatchBaseline.SourcePrerequisites` and
`ValidationPolicy` exist; NOT-YET before that.

Run from the project root:

    python3 tests/servicing_model_declaration_test.py
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

# Condition modes seen in the terminal declaration. A mode outside this set is
# not a failure of the config -- it is a signal that this contract has fallen
# behind the declaration and must be extended deliberately.
# Two classes, because the shape obligations differ:
#   - STATIC_ASSET_MODES resolve against the image and carry a committed asset,
#     so they must declare how to detect the condition and what to apply.
#   - RUNTIME_RESOLVED_MODES are satisfied from another package's download set
#     at resolve time (Server 2025's checkpoint comes bundled with its target
#     LCU), so a committed asset would be a hard-coded staleness hazard -- the
#     declaration says so explicitly. Requiring an Asset here would be the old
#     epistemology creeping back in.
STATIC_ASSET_MODES = {
    "IfServicingStackBelow",
    "IfImageOrServicingStackBelowFloor",
}
RUNTIME_RESOLVED_MODES = {
    "ResolveFromTargetLcuDownloadSet",
}
KNOWN_MODES = STATIC_ASSET_MODES | RUNTIME_RESOLVED_MODES

# Vocabulary migration. r12.37 ("all-os-version-decision-hardening") renamed
# the condition-mode vocabulary; revisions before it declare the predecessor
# names for the SAME semantics. A predecessor name is NOT a violation -- it is
# an earlier point on the same axis, and reporting it as a failure would be the
# convergence model's central mistake (judging an intermediate revision against
# the terminal's vocabulary rather than describing its distance from it).
#
# Measured across the series: predecessors hold r12.00 .. r12.36b, terminal
# vocabulary from r12.37 onward, with no revision mixing the two.
PREDECESSOR_MODES = {
    "IfLatestSsuNotApplicableOrPackageAbsent": "IfServicingStackBelow",
    "IfPackageAbsent": "IfServicingStackBelow",
    "IfSourceBelowFloor": "IfImageOrServicingStackBelowFloor",
}


def normalise_mode(mode):
    """Return (terminal_mode, is_predecessor)."""
    if mode in PREDECESSOR_MODES:
        return PREDECESSOR_MODES[mode], True
    return mode, False

# Modes whose semantics require a declared numeric floor to compare against.
FLOOR_MODES = {"IfImageOrServicingStackBelowFloor"}
FLOOR_KEYS = ("MinimumImageBuild", "MinimumServicingStack")

# ValidationPolicy flags that can only be discharged by runtime / E2E evidence.
# They are recorded, never asserted from a sandbox.
EVIDENCE_BOUND = {"RequireE4BeforeApproval", "RequireE5BeforeApproval"}


def check(label, ok, detail, p, f):
    print(f"{PASS if ok else FAIL}  {label}: {detail}")
    return (p + 1, f) if ok else (p, f + 1)


def boot_roles(lines):
    """Roles that the declaration routes to the Boot lane."""
    out = set()
    for ln in lines:
        for role, targets in (ln.get("TargetsByRole") or {}).items():
            if "Boot" in (targets or []):
                out.add(role)
    return out


def main() -> int:
    passed = failed = skipped = 0
    evidence_rows = []

    print("=" * 72)
    print("T42 servicing-model declaration conformance (D-contract)")
    print("=" * 72)

    for fname in CONFIGS:
        fpath = DATA_DIR / fname
        if not fpath.exists():
            print(f"{FAIL}  {fname}: not found under data/")
            failed += 1
            continue
        cfg = json.loads(fpath.read_text(encoding="utf-8-sig"))
        pb = cfg.get("PatchBaseline") or {}
        prereqs = pb.get("SourcePrerequisites")
        vp = cfg.get("ValidationPolicy")
        lines = pb.get("Lines") or []
        sm = cfg.get("ServicingModel") or {}

        if prereqs is None and vp is None:
            print(f"{SKIP}  {fname}: NOT-YET -- neither SourcePrerequisites "
                  f"nor ValidationPolicy declared")
            skipped += 1
            continue

        print(f"=== {fname} ===")

        # --- 1/2. Source prerequisites -----------------------------------
        passed, failed = check(
            f"{fname}: SourcePrerequisitePolicy is declared",
            bool(sm.get("SourcePrerequisitePolicy")),
            f"policy={sm.get('SourcePrerequisitePolicy')!r}", passed, failed)

        for pr in (prereqs or []):
            pid = pr.get("PrerequisiteId") or "<unnamed>"
            passed, failed = check(
                f"{fname} {pid}: carries id, kind and KB identity",
                bool(pr.get("PrerequisiteId") and pr.get("Kind")
                     and pr.get("KbId")),
                f"Kind={pr.get('Kind')!r} KbId={pr.get('KbId')!r}",
                passed, failed)
            passed, failed = check(
                f"{fname} {pid}: declares roles and targets",
                bool(pr.get("Roles")) and bool(pr.get("Targets")),
                f"Roles={pr.get('Roles')} Targets={pr.get('Targets')}",
                passed, failed)

            cond = pr.get("Condition") or {}
            raw_mode = cond.get("Mode")
            mode, is_pred = normalise_mode(raw_mode)
            passed, failed = check(
                f"{fname} {pid}: condition mode is on the known axis",
                mode in KNOWN_MODES,
                (f"Mode={raw_mode!r} (pre-r12.37 name for {mode!r}) "
                 f"-- CONVERGING" if is_pred else f"Mode={raw_mode!r}")
                if mode in KNOWN_MODES
                else f"Mode={raw_mode!r} -- extend the vocabulary deliberately",
                passed, failed)
            if mode in STATIC_ASSET_MODES and not is_pred:
                passed, failed = check(
                    f"{fname} {pid}: declares a non-empty detection list",
                    bool(cond.get("Detection")),
                    f"Detection={cond.get('Detection')}", passed, failed)
            elif mode in RUNTIME_RESOLVED_MODES:
                passed, failed = check(
                    f"{fname} {pid}: runtime-resolved mode names its source",
                    bool(cond.get("TargetKb")),
                    f"TargetKb={cond.get('TargetKb')!r} "
                    f"ApplicationMode={cond.get('ApplicationMode')!r}",
                    passed, failed)
            if mode in FLOOR_MODES and not is_pred:
                have = [k for k in FLOOR_KEYS if cond.get(k)]
                passed, failed = check(
                    f"{fname} {pid}: floor-comparing mode declares its floor",
                    bool(have),
                    f"declared floors={{" +
                    ", ".join(f"{k}={cond.get(k)!r}" for k in have) + "}"
                    if have else "no floor declared for a floor-comparing mode",
                    passed, failed)

            asset = pr.get("Asset")
            if mode in STATIC_ASSET_MODES and not is_pred:
                a = asset or {}
                passed, failed = check(
                    f"{fname} {pid}: asset carries a resolvable identity",
                    bool(a.get("KbId") and a.get("FileName")),
                    f"KbId={a.get('KbId')!r} FileName="
                    f"{str(a.get('FileName'))[:48]!r}", passed, failed)
            elif mode in RUNTIME_RESOLVED_MODES:
                passed, failed = check(
                    f"{fname} {pid}: runtime-resolved prerequisite pins no "
                    f"static asset",
                    asset is None,
                    "Asset=null as declared" if asset is None
                    else "a static Asset is pinned under a runtime-resolved "
                         "mode -- the declaration warns this must not be "
                         "hard-coded indefinitely",
                    passed, failed)

        # --- 3. Boot model vs Line routing -------------------------------
        common = cfg.get("Common") or {}
        model = common.get("BootWimUpdateModel")
        routed = boot_roles(lines)
        if model:
            if model == "SafeOSDU":
                ok = "SafeOSDU" in routed and "FinalLCU" not in routed
                detail = (f"BootWimUpdateModel=SafeOSDU, Boot-routed roles="
                          f"{sorted(routed)}")
            elif model == "FullLCU":
                ok = "FinalLCU" in routed and "SafeOSDU" not in routed
                detail = (f"BootWimUpdateModel=FullLCU, Boot-routed roles="
                          f"{sorted(routed)}")
            else:
                ok = False
                detail = f"unknown BootWimUpdateModel={model!r}"
            passed, failed = check(
                f"{fname}: boot model and Boot-lane routing agree", ok,
                detail, passed, failed)
        else:
            # No explicit model: the runtime default is FullLCU, so the
            # declaration must be consistent with that default or it is
            # relying on an implicit value that contradicts its own routing.
            ok = "SafeOSDU" not in routed
            passed, failed = check(
                f"{fname}: implicit boot model (FullLCU default) matches "
                f"the routing",
                ok,
                f"no BootWimUpdateModel declared; Boot-routed roles="
                f"{sorted(routed)}", passed, failed)

        # --- 4. Validation policy ----------------------------------------
        if vp is not None:
            non_bool = [k for k, v in vp.items() if not isinstance(v, bool)]
            passed, failed = check(
                f"{fname}: ValidationPolicy flags are boolean",
                not non_bool,
                f"non-boolean: {non_bool}" if non_bool else
                f"{len(vp)} flag(s)", passed, failed)
            bound = sorted(k for k in vp if k in EVIDENCE_BOUND and vp[k])
            evidence_rows.append((fname, bound))
            passed, failed = check(
                f"{fname}: evidence-bound flags are identified",
                True,
                f"E-contract lane owns: {bound}" if bound
                else "none asserted", passed, failed)
        print()

    if evidence_rows:
        print("=== E-contract handoff (recorded, not asserted here) ===")
        for fname, bound in evidence_rows:
            print(f"  {fname}: {', '.join(bound) if bound else '(none)'}")
        print()

    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total"
          + (f", {skipped} NOT-YET" if skipped else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
