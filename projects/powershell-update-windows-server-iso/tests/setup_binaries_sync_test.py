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
        cases = [
            (26100, ["setup.exe", "setuphost.exe"]),
            (27000, ["setup.exe", "setuphost.exe"]),
            (20348, ["setup.exe"]),
            (17763, ["setup.exe"]),
            (14393, ["setup.exe"]),
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
            "setuphost.exe joins the plan at 26100+ only", ok, detail, passed, failed)
        plan = ps.invoke("Get-SetupBinarySyncPlan", BuildNumber=None)
        files = plan["Files"] if isinstance(plan["Files"], list) else [plan["Files"]]
        passed, failed = check(
            "unknown build -> setup.exe only, with a stated reason",
            files == ["setup.exe"] and "unknown" in str(plan["Reason"]),
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
    lists_ok = (
        code.count("'P08','P08S','P09'") == 4  # two standardFull variants + Build action + the r12.05 ResumeFromPhase list
    )
    passed, failed = check(
        "P08S wired into the standard pipelines, the Build action and the ResumeFromPhase list (4 lists, r12.05)",
        lists_ok, f"count={code.count(chr(39) + 'P08' + chr(39) + ',' + chr(39) + 'P08S' + chr(39))}", passed, failed)

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
        "version bumped to r12.24 evidence-audit-and-pca2023-verdict-provenance",
        "update-wsi-2026.07.19-r12.24" in code and "'evidence-audit-and-pca2023-verdict-provenance'" in code,
        "bump pin failed", passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
