#!/usr/bin/env python3
"""T39: boot-verification tool-set contract (offline).

What this pins and why:

  1. Syntax: every .ps1 under tools/boot-verification parses clean
     (ParseFile, 0 errors) -- the tools run on the user's Windows
     host, so parse errors must be caught here, not there.
  2. The pure functions in BootVerification.Common.ps1 behave:
     - Convert-Rgb565ToBmpByte emits a structurally valid 16bpp
       BI_BITFIELDS .bmp with bottom-up row order (deterministic
       2x2 fixture) -- this is the screenshot path's foundation.
     - ConvertFrom-EfiSignatureList walks a synthetic signature list
       (entry count, data slicing) and degrades to zero entries on
       garbage instead of throwing -- a damaged variable must not
       kill the rig check.
     - Test-SecureBootSubjectPresence recognises the two
       load-bearing subjects.
     - Get-BootVerificationCellMap pins the adjudicated matrix
       semantics (T6 decides the Healthy upgrade; T8/T9 EXPECT
       boot-failure; T10 is the automated install cell).
     - New-BootVerificationLedgerEntry stores expectation next to
       observation and rejects unknown cells.
  3. The autounattend template is well-formed XML, carries all four
     substitution tokens, and wipes disk 0 EXPLICITLY (the safety
     warning depends on that being true).
  4. Structure pins across the tool set and the main script: the
     Secure Boot template is MicrosoftWindows everywhere (the old
     MicrosoftUEFICertificateAuthority choice is gone), 'VM State =
     Running' is documented as a non-verdict, and the README keeps
     the T9-first rule and the KB5025885 mitigation values.

Run:  python3 tests/boot_verification_tools_test.py
Deps: pwsh on PATH (same as T31/T37/T38).
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = SUBPROJECT_ROOT / "tools" / "boot-verification"
MAIN = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"
COMMON = TOOLS / "BootVerification.Common.ps1"

PS1_FILES = [
    "BootVerification.Common.ps1",
    "Invoke-IsoBootVerification.ps1",
    "New-EvidenceDataVhdx.ps1",
    "Export-InstalledSystemEvidence.ps1",
    "Test-SecureBootRigState.ps1",
]


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def run_pwsh(snippet: str) -> tuple[int, str]:
    """One-shot pwsh: dot-source Common, run the snippet, return JSON text."""
    script = f". '{COMMON}'\n{snippet}"
    r = subprocess.run(
        ["pwsh", "-NoProfile", "-NonInteractive", "-Command", script],
        capture_output=True, text=True, timeout=120,
    )
    return r.returncode, (r.stdout or "").strip()


def main() -> int:
    passed = failed = 0

    print("=== 1. ParseFile: every tool script parses clean ===")
    names = ";".join(f"'{TOOLS / n}'" for n in PS1_FILES)
    rc, out = run_pwsh(
        "$m=@{}; foreach($p in @(" + names.replace(";", ",") + ")){"
        "$e=$null;$t=$null;"
        "[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)|Out-Null;"
        "$m[(Split-Path -Leaf $p)]=$e.Count};"
        "$m|ConvertTo-Json -Compress"
    )
    errs = json.loads(out) if rc == 0 and out else {}
    for n in PS1_FILES:
        passed, failed = check(
            f"{n} parses with 0 errors",
            errs.get(n) == 0, f"errors={errs.get(n)!r} rc={rc}", passed, failed)

    print("=== 2. Convert-Rgb565ToBmpByte (deterministic 2x2) ===")
    # Pixels top-down: row0 = [0xF800(red), 0x07E0(green)], row1 = [0x001F(blue), 0xFFFF(white)]
    rc, out = run_pwsh(
        "$px=[byte[]](0x00,0xF8, 0xE0,0x07, 0x1F,0x00, 0xFF,0xFF);"
        "$bmp=Convert-Rgb565ToBmpByte -PixelData $px -Width 2 -Height 2;"
        "@{Len=$bmp.Length;Magic=('{0:X2}{1:X2}' -f $bmp[0],$bmp[1]);"
        "Bpp=[BitConverter]::ToUInt16($bmp,28);Comp=[BitConverter]::ToUInt32($bmp,30);"
        "Row0=('{0:X2}{1:X2}' -f $bmp[66],$bmp[67])}|ConvertTo-Json -Compress"
    )
    bmp = json.loads(out) if rc == 0 and out else {}
    passed, failed = check(
        "BMP shape: magic/16bpp/BI_BITFIELDS/size (66 header + 2 rows x 4B)",
        bmp.get("Magic") == "424D" and bmp.get("Bpp") == 16
        and bmp.get("Comp") == 3 and bmp.get("Len") == 66 + 8,
        f"got={bmp!r}", passed, failed)
    passed, failed = check(
        "bottom-up row order: file's first pixel row is the source's LAST (blue 0x001F)",
        bmp.get("Row0") == "1F00", f"Row0={bmp.get('Row0')!r}", passed, failed)

    print("=== 3. ConvertFrom-EfiSignatureList ===")
    rc, out = run_pwsh(
        "$garbage=[byte[]](1..40|ForEach-Object{[byte]255});"
        "$g=@(ConvertFrom-EfiSignatureList -Bytes $garbage).Count;"
        # synthetic list: random type GUID, header 0, sigsize 20 (16 owner + 4 data), 2 sigs
        "$guid=[guid]'11111111-2222-3333-4444-555555555555';"
        "$ms=New-Object System.IO.MemoryStream;$w=New-Object System.IO.BinaryWriter($ms);"
        "$w.Write($guid.ToByteArray());$w.Write([uint32](28+2*20));$w.Write([uint32]0);$w.Write([uint32]20);"
        "$w.Write((New-Object byte[] 16));$w.Write([byte[]](9,9,9,9));"
        "$w.Write((New-Object byte[] 16));$w.Write([byte[]](7,7,7,7));$w.Flush();"
        "$e=@(ConvertFrom-EfiSignatureList -Bytes $ms.ToArray());"
        "@{Garbage=$g;Count=$e.Count;D0=(@($e[0].Data) -join ',');D1=(@($e[1].Data) -join ',')}|ConvertTo-Json -Compress"
    )
    esl = json.loads(out) if rc == 0 and out else {}
    passed, failed = check(
        "garbage bytes degrade to 0 entries (no throw)",
        esl.get("Garbage") == 0, f"got={esl!r}", passed, failed)
    passed, failed = check(
        "synthetic 2-signature list: both entries walked, data sliced after the owner GUID",
        esl.get("Count") == 2 and esl.get("D0") == "9,9,9,9" and esl.get("D1") == "7,7,7,7",
        f"got={esl!r}", passed, failed)

    print("=== 4. Subject presence verdict ===")
    rc, out = run_pwsh(
        "$s=@('CN=Microsoft Windows Production PCA 2011, O=Microsoft','CN=Windows UEFI CA 2023');"
        "$f=Test-SecureBootSubjectPresence -Subjects $s;"
        "$n=Test-SecureBootSubjectPresence -Subjects @('CN=Something Else');"
        "@{H11=$f.Has2011;H23=$f.Has2023;N11=$n.Has2011;N23=$n.Has2023}|ConvertTo-Json -Compress"
    )
    subj = json.loads(out) if rc == 0 and out else {}
    passed, failed = check(
        "PCA2011 + 2023 CA recognised; unrelated subject matches neither",
        subj.get("H11") is True and subj.get("H23") is True
        and subj.get("N11") is False and subj.get("N23") is False,
        f"got={subj!r}", passed, failed)

    print("=== 5. Cell map + ledger semantics ===")
    rc, out = run_pwsh(
        "$m=Get-BootVerificationCellMap;"
        "$e=New-BootVerificationLedgerEntry -Cell T6 -IsoPath 'x.iso' -VmName 'rig';"
        "$thrown=$false; try { New-BootVerificationLedgerEntry -Cell T99 -IsoPath 'x' -VmName 'v' | Out-Null } catch { $thrown=$true };"
        "@{T6Rig=$m['T6'].Rig;T6Exp=$m['T6'].Expected;T8Exp=$m['T8'].Expected;T9Exp=$m['T9'].Expected;"
        "T10Depth=$m['T10'].Depth;T10Exp=$m['T10'].Expected;"
        "LOut=$e.Outcome;LExp=$e.Expected;Thrown=$thrown}|ConvertTo-Json -Compress"
    )
    cm = json.loads(out) if rc == 0 and out else {}
    passed, failed = check(
        "adjudicated matrix pinned: T6=REV/reaches-setup, T8+T9 EXPECT boot-failure, T10=install",
        cm.get("T6Rig") == "REV" and cm.get("T6Exp") == "reaches-setup"
        and cm.get("T8Exp") == "boot-failure" and cm.get("T9Exp") == "boot-failure"
        and cm.get("T10Depth") == "install" and cm.get("T10Exp") == "install-completes",
        f"got={cm!r}", passed, failed)
    passed, failed = check(
        "ledger entry: boot-depth default Outcome=pending-operator, expectation stored, unknown cell throws",
        cm.get("LOut") == "pending-operator" and cm.get("LExp") == "reaches-setup"
        and cm.get("Thrown") is True,
        f"got={cm!r}", passed, failed)

    print("=== 6. autounattend template ===")
    xml_text = (TOOLS / "autounattend-template.xml").read_text(encoding="utf-8")
    ok_xml = True
    try:
        ET.fromstring(xml_text)
    except ET.ParseError as ex:
        ok_xml = False
        detail = str(ex)
    else:
        detail = ""
    passed, failed = check("template is well-formed XML", ok_xml, detail, passed, failed)
    tokens = ["{{IMAGE_INDEX}}", "{{ADMIN_PASSWORD}}", "{{UI_LANG}}", "{{INPUT_LOCALE}}"]
    passed, failed = check(
        "all four substitution tokens present + explicit disk-0 wipe declared",
        all(t in xml_text for t in tokens) and "<WillWipeDisk>true</WillWipeDisk>" in xml_text,
        "missing token or wipe flag", passed, failed)

    print("=== 7. Structure pins (template choice; honest verdicts; README rules) ===")
    harness = (TOOLS / "Invoke-IsoBootVerification.ps1").read_text(encoding="utf-8-sig")
    main_code = MAIN.read_text(encoding="utf-8-sig")
    import re
    third_party_used = re.compile(r"Set-VMFirmware[^\n]*MicrosoftUEFICertificateAuthority")
    passed, failed = check(
        "Secure Boot template is MicrosoftWindows everywhere; the third-party template is never PASSED to Set-VMFirmware (naming it in the defect rationale is fine)",
        "SecureBootTemplate MicrosoftWindows" in harness
        and "SecureBootTemplate MicrosoftWindows" in main_code
        and not third_party_used.search(harness)
        and not third_party_used.search(main_code),
        "template pin failed", passed, failed)
    passed, failed = check(
        "VM state is never a boot verdict: harness states it; main enforces it structurally (r12.04)",
        # Harness keeps the explicit disclaimer; since r12.04 the main
        # BootTest expresses the same honesty STRUCTURALLY -- Success is
        # derived from guest evidence (Install) or forces operator review
        # (BootOnly), never from the recorded VmState.
        "NOT a verdict" in harness
        and "RequiresOperatorReview=($Mode -eq 'BootOnly')" in main_code
        and "screenshots alone are not InstallValidated evidence" in main_code
        and "[bool]($guestEvidence -and $guestEvidence.SecureBoot)" in main_code,
        "honesty pin failed", passed, failed)
    readme = (TOOLS / "README.md").read_text(encoding="utf-8")
    passed, failed = check(
        "README keeps the T9-first rule and the KB5025885 mitigation values (0x40/0x100/0x80)",
        "T9 before T5-T8" in readme and all(v in readme for v in ("0x40", "0x100", "0x80")),
        "README pin failed", passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, {passed + failed} total")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
