#!/usr/bin/env python3
"""T40: Setup-binary sync contract (P08S + P11 SetupBinarySync), offline.

Root cause this arc closes [measured 2026-07-11]: P08 serviced
boot.wim (the Setup engine) while media \\sources\\setup.exe /
setuphost.exe stayed at shipped versions; per Microsoft's
media-dynamic-update guidance these must be identical or "Windows
Setup will fail during installation" -- and it did (2016/2022/2025
failed before edition selection; 2019 escaped only via its pinned-old
boot.wim). What this test pins:

  1. REPL (pure/pure-ish functions via the TestHarness):
     - Get-SetupBinarySyncPlan build gates: setuphost.exe joins the
       plan at 26100+ ONLY; unknown build degrades to setup.exe-only
       with a stated reason (never a guess).
     - Get-SetupBinaryFileEvidence: measured size + SHA-256 +
       ISO-8601 UTC timestamp for a real file; Present=false shape
       for a missing path (no throw).
     - New-SetupBinarySyncRecord: expectation-carrying record shape;
       invalid Action rejected.
  2. Structure pins (text): P08S registered between P08 and P09 and
     wired into every pipeline list; the phase verifies the copy by
     SHA-256 and hard-fails on mismatch; it clears the ISO-extracted
     ReadOnly attribute before copying; evidence artifacts
     (P08S_setup_binaries_sync.csv / setup_binaries_sync.json) are
     written; inspection collects SetupExe/SetupHostExe for boot
     images and MediaSetupBinaries for the media root; P11 emits
     SetupBinarySync_* rows and grades a mismatch Fail.

O7 supersession [2026-08-07, re-impl phase C]: the P08S pipeline-wiring
pin was originally a global token-count proxy
(``code.count("'P08','P08S','P09'")``) whose expected value broke at
r12.35 when the resume layer legitimately added a fifth wiring site
(adjudicated option A: count 4 -> 5 with provenance). This file now
carries the deferred option-B rework instead: a structural invariant
(every quoted phase-ID list literal of three or more elements that
contains both P08 and P09 must wire P08S strictly between them --
two-element constructs such as parameter ValidateSets are exempt by
the length discriminator) plus per-site pins for the five known
pipeline lists. A legitimately added new pipeline list that wires
P08S correctly no longer breaks the contract; a list that drops or
misorders P08S fails with a specific diagnosis.

Run:  python3 tests/setup_binaries_sync_test.py
Deps: pwsh on PATH (same as T31/T37/T38).
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import sys
import tempfile

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SUBPROJECT_ROOT / "tests"))

from common.ps_invoke import PSSession, PSHarnessError  # type: ignore  # noqa: E402

SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def main() -> int:
    passed = failed = 0
    code = SCRIPT_PATH.read_text(encoding="utf-8-sig")

    with PSSession(SCRIPT_PATH) as ps:
        print("=== 1. Get-SetupBinarySyncPlan build gates ===")
        # r12.72 T39 revision: the sync SET became build-independent BY
        # DESIGN — Microsoft final media Dynamic Update copies setup.exe
        # AND setuphost.exe from serviced WinPE for every supported OS;
        # the 26100 threshold moved from the plan to the REQUIREMENT
        # (SetupHostRequired: missing setuphost.exe throws on 26100+,
        # tolerated below when genuinely absent from boot.wim index 2).
        # Pins re-derived from the measured r12.72 surface and verified
        # byte-identical at the r12.75 terminal frame.
        cases = [
            (26100, ["setup.exe", "setuphost.exe"]),
            (27000, ["setup.exe", "setuphost.exe"]),
            (20348, ["setup.exe", "setuphost.exe"]),
            (17763, ["setup.exe", "setuphost.exe"]),
            (14393, ["setup.exe", "setuphost.exe"]),
        ]
        ok = True
        detail = ""
        for build, expect in cases:
            plan = ps.invoke("Get-SetupBinarySyncPlan", BuildNumber=build)
            files = plan["Files"] if isinstance(plan["Files"], list) else [plan["Files"]]
            if files != expect:
                ok = False
                detail = f"build {build}: {files!r} != {expect!r}"
                break
        passed, failed = check(
            "every build plans setup.exe + setuphost.exe (build-independent set)",
            ok, detail, passed, failed)
        passed, failed = check(
            "the 26100 threshold lives in SetupHostRequired, and a required-but-missing setuphost fails",
            "$result.SetupHostRequired = [bool]($imageVersion -ge [version]'10.0.26100.0')" in code
            and "requires sources\\setuphost.exe, but it is missing." in code,
            "requirement gate pinned", passed, failed)
        plan = ps.invoke("Get-SetupBinarySyncPlan", BuildNumber=None)
        files = plan["Files"] if isinstance(plan["Files"], list) else [plan["Files"]]
        passed, failed = check(
            "unknown build -> both files planned, with a stated reason",
            files == ["setup.exe", "setuphost.exe"] and "unknown" in str(plan["Reason"]),
            f"got={plan!r}", passed, failed)

        print("=== 2. Get-SetupBinaryFileEvidence ===")
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".bin", delete=False) as tf:
            payload = b"setup-binary-sync-fixture\n" * 8
            tf.write(payload)
            tmp = tf.name
        try:
            ev = ps.invoke("Get-SetupBinaryFileEvidence", Path=tmp)
            expect_sha = hashlib.sha256(payload).hexdigest()
            iso8601 = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")
            passed, failed = check(
                "real file: Present + exact size + exact SHA-256 + ISO-8601 UTC timestamp",
                ev["Present"] is True and ev["SizeBytes"] == len(payload)
                and ev["Sha256"] == expect_sha and iso8601.match(str(ev["LastWriteTimeUtc"])),
                f"got={ev!r}", passed, failed)
        finally:
            pathlib.Path(tmp).unlink(missing_ok=True)
        ev = ps.invoke("Get-SetupBinaryFileEvidence", Path="/nonexistent/p08s/setup.exe")
        passed, failed = check(
            "missing path: Present=false shape, no throw",
            ev["Present"] is False and ev["Sha256"] is None and ev["SizeBytes"] is None,
            f"got={ev!r}", passed, failed)

        print("=== 3. New-SetupBinarySyncRecord ===")
        src = {"Path": "x", "Present": True, "SizeBytes": 10, "LastWriteTimeUtc": "t", "Sha256": "aa"}
        before = {"Path": "y", "Present": True, "SizeBytes": 9, "LastWriteTimeUtc": "t0", "Sha256": "bb"}
        rec = ps.invoke("New-SetupBinarySyncRecord", FileName="setup.exe",
                        Action="copied", Source=src, MediaBefore=before,
                        MediaAfter=src, Notes="n")
        passed, failed = check(
            "record carries file, action, source, media before/after",
            rec["FileName"] == "setup.exe" and rec["Action"] == "copied"
            and rec["Source"]["Sha256"] == "aa" and rec["MediaBefore"]["Sha256"] == "bb"
            and rec["MediaAfter"]["Sha256"] == "aa",
            f"got={rec!r}", passed, failed)
        thrown = False
        try:
            ps.invoke("New-SetupBinarySyncRecord", FileName="setup.exe",
                      Action="silently-mutated", Source=src, MediaBefore=before)
        except PSHarnessError:
            thrown = True
        passed, failed = check(
            "invalid Action rejected (the vocabulary is closed)",
            thrown, "no error raised", passed, failed)

    print("=== 4. Structure pins: phase wiring ===")
    reg = re.search(
        r"Id='P08';.*\n\s*\[pscustomobject\]@\{ Id='P08S';\s+Name='SyncSetupBinaries';\s+Group='Build';.*\n\s*\[pscustomobject\]@\{ Id='P09';",
        code)
    passed, failed = check(
        "P08S registered between P08 and P09 (Build group)",
        bool(reg), "registry order pin failed", passed, failed)
    # O7 option-B rework [2026-08-07]: structural invariant + per-site
    # pins replace the former global token-count proxy (see header).
    bad_lists = []
    for m in re.finditer(r"(?:'P\d{2}[A-Z]?'\s*,\s*)+'P\d{2}[A-Z]?'", code):
        ids = re.findall(r"'(P\d{2}[A-Z]?)'", m.group(0))
        if len(ids) < 3 or "P08" not in ids or "P09" not in ids:
            continue
        if ("P08S" not in ids
                or not ids.index("P08") < ids.index("P08S") < ids.index("P09")):
            line = code.count("\n", 0, m.start()) + 1
            bad_lists.append(f"line {line}: {ids!r}")
    passed, failed = check(
        "every pipeline phase list containing P08 and P09 wires P08S strictly between them",
        not bad_lists, "; ".join(bad_lists), passed, failed)

    anchor = "$standardFull = if ($Script:SyntheticTestMode) {"
    idx = code.find(anchor)
    window = code[idx:idx + 400] if idx >= 0 else ""
    passed, failed = check(
        "P08S wired into both standardFull pipeline variants (synthetic + normal)",
        idx >= 0 and window.count("'P08','P08S','P09'") == 2,
        f"anchor found={idx >= 0}, wired variants={window.count(chr(39) + 'P08' + chr(39) + ',' + chr(39) + 'P08S' + chr(39) + ',' + chr(39) + 'P09' + chr(39))}",
        passed, failed)
    passed, failed = check(
        "P08S wired into the Build action list (P07..P10)",
        bool(re.search(r"'Build'\s*\{\s*return \[string\[\]\]@\('P07','P08','P08S','P09','P10'\)\s*\}", code)),
        "Build action list pin failed", passed, failed)
    resume_idx = code.find("$Script:RequestedResumeFromPhase -eq 'P08'")
    resume_window = code[resume_idx:resume_idx + 300] if resume_idx >= 0 else ""
    passed, failed = check(
        "P08S wired into the ResumeFromPhase P08 list (r12.05)",
        resume_idx >= 0
        and "@('P01','P02','P08','P08S','P09','P10','P11','P12','P13')" in resume_window,
        "ResumeFromPhase list pin failed", passed, failed)
    prefix_idx = code.find("function Reset-ResumeDownstreamState")
    prefix_window = code[prefix_idx:prefix_idx + 400] if prefix_idx >= 0 else ""
    passed, failed = check(
        "P08S wired into the resume downstream-cleanup prefix list (r12.35)",
        prefix_idx >= 0
        and "@('P08','P08S','P09','P10','P11','P12','P13','P14')" in prefix_window,
        "downstream-cleanup prefix list pin failed", passed, failed)

    print("=== 5. Structure pins: explicit-sync contract ===")
    fn = code[code.find("function Invoke-BuildPhase08S_SyncSetupBinaries"):]
    fn = fn[:fn.find("\nfunction ", 10)]
    passed, failed = check(
        "post-copy SHA-256 verification is a hard failure",
        "post-copy verification FAILED" in fn and "throw" in fn,
        "verification pin failed", passed, failed)
    passed, failed = check(
        "ISO-extracted ReadOnly attribute is cleared before copying",
        "IsReadOnly" in fn, "readonly pin failed", passed, failed)
    passed, failed = check(
        "evidence artifacts written (CSV + JSON), read-only mount discarded",
        "P08S_setup_binaries_sync.csv" in fn and "setup_binaries_sync.json" in fn
        and "Discard = $true" in fn,
        "artifact pin failed", passed, failed)
    passed, failed = check(
        "before/after console evidence lines (boot.wim side, media BEFORE, media AFTER)",
        "media BEFORE" in fn and "media AFTER" in fn and "boot.wim idx2 side" in fn,
        "console evidence pin failed", passed, failed)

    passed, failed = check(
        "boot.wim-side binaries stashed; P09 reapplies them after a Setup DU overlay (MS order: boot.wim copies win)",
        "p08s_setup_binaries" in fn
        and "reapply-setup-binaries" in code
        and "reapplied boot.wim copy after Setup DU overlay" in code,
        "stash/reapply pin failed", passed, failed)

    print("=== 6. Structure pins: inspection + P11 ===")
    passed, failed = check(
        "inspection collects SetupExe/SetupHostExe for boot images and MediaSetupBinaries for the media root",
        "SetupExe      = $null" in code and "$rec.SetupExe     = Get-SetupBinaryFileEvidence" in code
        and "MediaSetupBinaries" in code
        and "$insp.MediaSetupBinaries.SetupExe" in code,
        "inspection pin failed", passed, failed)
    passed, failed = check(
        "P11 emits SetupBinarySync_* rows and grades a mismatch Fail",
        "SetupBinarySync_" in code and "-Actual 'MISMATCH' -Status 'Fail'" in code,
        "P11 pin failed", passed, failed)
    passed, failed = check(
        "version bumped to r12.76 (tag: psa-error-debt-drain)",
        "update-wsi-2026.08.08-r12.76" in code and "'psa-error-debt-drain'" in code,
        "bump pin failed", passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
