#!/usr/bin/env python3
"""T33: Bridge-LCU contract (offline; TestHarness REPL + committed data).

Pins the r11.53 `bridge-lcu` invariants that fix the 2026-07-05 Server
2022 E2E failure (P07 `0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED`:
the EVAL media's in-image servicing stack 20348.587 cannot open the
current combined LCU). Microsoft's documented remedy (per-KB pages,
e.g. KB5094128) is to install KB5030216-or-later on the offline media
FIRST -- the bridge LCU, modelled as the SEED envelope
`PatchBaseline.BridgeLcu` and applied unconditionally as sub-phase
`I0.BridgeLcu` [DECIDED 2026-07-06, A1].

Assertions:
  1. `ConvertTo-BridgeLcuResolvedPatch` materialises the envelope as a
     ResolvedPatches entry: PatchType 'BridgeLcu', ApplyOrder 0, sha-1
     ExpectedHashes from Digest, LocalPath in the FLAT per-OS folder
     (outside the `cu` checkpoint-discovery subfolder).
  2. `Build-PatchPlan` routes 'BridgeLcu' to Install ONLY (never Boot /
     WinRE -- WinPE re-enters the LCU-servicing constraints; WinRE is
     serviced by SSU + SafeOS DU).
  3. `Build-InstallApplySequence` emits `I0.BridgeLcu` FIRST, carrying
     the bridge, with the target LCU still in I3.
  4. Committed data: seed-Server2022 + config-Server2022 carry an
     identical BridgeLcu envelope (KB5030216, floor 20348.1960, MS
     evidence URL); Digest is the base64 form of the SHA-1 hex embedded
     in the Catalog FileName (cross-encoding self-consistency).
  5. Scope pin: no other OS carries a BridgeLcu envelope today.

Exit code 0 on full pass, 1 on any failure.
"""
from __future__ import annotations

import base64
import json
import pathlib
import re
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"
DATA_DIR = SUBPROJECT_ROOT / "data"

PASS = "  PASS"
FAIL = "  FAIL"


def check(label: str, ok: bool, detail: str, p: int, f: int) -> tuple[int, int]:
    if ok:
        print(f"{PASS}  {label}: {detail}")
        return p + 1, f
    print(f"{FAIL}  {label}: {detail}")
    return p, f + 1


def main() -> int:
    passed = 0
    failed = 0

    cfg2022 = json.loads((DATA_DIR / "config-Server2022.json").read_text(encoding="utf-8"))
    seed2022 = json.loads((DATA_DIR / "seed" / "seed-Server2022.json").read_text(encoding="utf-8"))
    bridge = (cfg2022.get("PatchBaseline") or {}).get("BridgeLcu")

    print("=== 4. Committed data contract (checked first; REPL cases reuse it) ===")
    passed, failed = check(
        "config-Server2022 carries a BridgeLcu envelope",
        isinstance(bridge, dict), f"present={bridge is not None}", passed, failed)
    if not isinstance(bridge, dict):
        print(f"\n  Summary: {passed} passed, {failed + 1} failed (aborting: no envelope)")
        return 1

    passed, failed = check(
        "seed and config envelopes are identical",
        (seed2022.get("PatchBaseline") or {}).get("BridgeLcu") == bridge,
        "seed == config", passed, failed)
    passed, failed = check(
        "bridge is KB5030216 with the documented floor",
        bridge.get("KbId") == "KB5030216"
        and bridge.get("MinimumImageServicingStack") == "20348.1960",
        f"KbId={bridge.get('KbId')} floor={bridge.get('MinimumImageServicingStack')}",
        passed, failed)
    passed, failed = check(
        "evidence URL is an MS primary source",
        "support.microsoft.com" in (bridge.get("EvidenceUrl") or ""),
        f"EvidenceUrl={bridge.get('EvidenceUrl')}", passed, failed)
    m = re.search(r"_([0-9a-f]{40})\.msu$", bridge.get("FileName") or "")
    digest_ok = False
    if m:
        digest_ok = base64.b64encode(bytes.fromhex(m.group(1))).decode() == bridge.get("Digest")
    passed, failed = check(
        "Digest is the base64 of the FileName-embedded SHA-1",
        bool(m) and digest_ok,
        f"FileName sha1={m.group(1) if m else '?'} Digest={bridge.get('Digest')}",
        passed, failed)
    passed, failed = check(
        "DownloadUrl serves the same FileName",
        (bridge.get("DownloadUrl") or "").endswith("/" + (bridge.get("FileName") or "?")),
        f"DownloadUrl tail matches FileName", passed, failed)

    print("=== 5. Scope pin: only Server 2022 carries a bridge today ===")
    for os_key in ("2016", "2019", "2025"):
        cfg = json.loads((DATA_DIR / f"config-Server{os_key}.json").read_text(encoding="utf-8"))
        passed, failed = check(
            f"config-Server{os_key} has no BridgeLcu",
            "BridgeLcu" not in (cfg.get("PatchBaseline") or {}),
            "absent", passed, failed)

    with PSSession(SCRIPT_PATH) as ps:
        ps.invoke("Set-Variable", Name="OsVersion", Scope="Script",
                  Value="Server2022")

        print("=== 1. ConvertTo-BridgeLcuResolvedPatch shape ===")
        entry = ps.invoke("ConvertTo-BridgeLcuResolvedPatch", BridgeLcu=bridge)
        passed, failed = check(
            "PatchType/ApplyOrder/KbId",
            entry.get("PatchType") == "BridgeLcu" and entry.get("ApplyOrder") == 0
            and entry.get("KbId") == "KB5030216",
            f"PatchType={entry.get('PatchType')} ApplyOrder={entry.get('ApplyOrder')}",
            passed, failed)
        norm = str(entry.get("LocalPath")).replace("/", "\\")
        passed, failed = check(
            "LocalPath is FLAT (outside cu\\)",
            "\\cu\\" not in norm and norm.endswith(bridge["FileName"]),
            f"LocalPath={entry.get('LocalPath')}", passed, failed)
        hashes = entry.get("ExpectedHashes") or {}
        passed, failed = check(
            "sha-1 ExpectedHashes carried from Digest",
            hashes.get("sha-1") == bridge["Digest"],
            f"sha-1={hashes.get('sha-1')}", passed, failed)

        print("=== 2. Build-PatchPlan routing ===")
        patches = [
            {"KbId": "KB5030216", "PatchType": "BridgeLcu", "ApplyOrder": 0},
            {"KbId": "KB5094128", "PatchType": "LCU", "ApplyOrder": 1},
        ]
        plan = ps.invoke("Build-PatchPlan", Patches=patches)
        counts = plan.get("_TargetCounts") or {}
        passed, failed = check(
            "BridgeLcu routed to Install only",
            counts.get("Install") == 2 and counts.get("Boot") == 1
            and counts.get("WinRE") == 0,
            f"_TargetCounts={counts}", passed, failed)
        passed, failed = check(
            "BridgeLcu is a KNOWN Type",
            "BridgeLcu" not in list(plan.get("_UnknownTypes") or []),
            f"_UnknownTypes={plan.get('_UnknownTypes')}", passed, failed)

        print("=== 3. I0.BridgeLcu sub-phase ordering ===")
        seq = plan.get("InstallSequence") or []
        names = [sp.get("Name") for sp in seq]
        passed, failed = check(
            "I0.BridgeLcu is the FIRST install sub-phase",
            bool(names) and names[0] == "I0.BridgeLcu",
            f"sequence={names}", passed, failed)
        i0 = seq[0] if seq else {}
        i0_kbs = [p.get("KbId") for p in (i0.get("Patches") or [])]
        passed, failed = check(
            "I0 carries exactly the bridge",
            i0_kbs == ["KB5030216"],
            f"I0 patches={i0_kbs}", passed, failed)
        i3 = next((sp for sp in seq if sp.get("Name") == "I3.LCU.FirstPass"), {})
        i3_kbs = [p.get("KbId") for p in (i3.get("Patches") or [])]
        passed, failed = check(
            "target LCU stays in I3.LCU.FirstPass",
            i3_kbs == ["KB5094128"],
            f"I3 patches={i3_kbs}", passed, failed)

    print()
    print(f"  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
