#!/usr/bin/env python3
"""T54: source-file format contract for both deliverables (offline).

Mechanises SPEC section A.2: script sources are UTF-8 with BOM and CRLF
line endings, and non-ASCII characters are confined to intentional data
or string literals -- identifiers, keywords, code and comments are
ASCII. SPEC names the static-analysis gate as the enforcer; this
contract is the repository-side half of that enforcement, covering the
part the analyzer cannot express positionally.

Why this contract exists. The CI source-format step used to reject any
byte above 0x7F anywhere in the main script. That rule is stricter than
SPEC section A.2 and had drifted away from the deliverable: the script
legitimately carries Japanese Catalog display-name aliases, a Japanese
oscdimg qualification case name, and a Japanese ReAgentc status pattern
-- all inside string literals, all required for ja-jp media handling.
The analyzer rule PSA7003 cannot substitute for a per-position check
because it reports one finding anchored at the FIRST non-ASCII
occurrence in a file; a suppression on that one line silences the rule
for every later occurrence, so its silence is not evidence that the
remaining occurrences are sanctioned.

Class: B (behaviour/structure pins). Justification: the source-file
format is a property of the artifact bytes and their parse, not of any
declared data surface.

What this asserts, per deliverable:

  1. **Encoding.** The file begins with the UTF-8 BOM (EF BB BF).
  2. **Line endings.** Every LF is preceded by CR (no bare LF), and at
     least one CRLF is present. CR bytes are counted with an exact byte
     count, never a shell-quoted grep.
  3. **Non-ASCII placement.** Every character above U+007F lies inside a
     string-literal token as classified by the PowerShell parser
     itself. Non-ASCII in code, identifiers or comments fails, and the
     failure names the line, column and code point.
  4. **Parse.** The file parses without errors under the pinned pwsh --
     a precondition for assertion 3 to be meaningful, asserted
     explicitly rather than assumed.

Non-ASCII placement is judged by the authoritative parser
(System.Management.Automation.Language.Parser), not by a hand-rolled
quote scanner. Characters outside the Basic Multilingual Plane would
occupy two UTF-16 units in the parser's offsets; the driver reports
them as unsanctioned rather than guessing, which fails closed.

Run:  python3 tests/source_format_test.py
Deps: pwsh on PATH (same dependency class as T40/T47/T48/T50/T51/T52).
"""
from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent

TARGETS = (
    "Update-WindowsServerIso.ps1",
    "Collect-WindowsServerPostInstallEvidence.ps1",
)

# String-token kinds recognised by the PowerShell tokenizer. Non-ASCII is
# sanctioned inside these and nowhere else. Comment is deliberately
# absent: SPEC section A.12 puts the documentation language of code
# comments at English/ASCII.
DRIVER = r'''
param([Parameter(Mandatory)][string]$Path)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$stringKinds = @(
    'StringLiteral', 'StringExpandable',
    'HereStringLiteral', 'HereStringExpandable'
)

$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $Path, [ref]$tokens, [ref]$errors)

$parseErrorCount = 0
if ($null -ne $errors) { $parseErrorCount = $errors.Count }

# Collect the offset spans of every string token, so a non-ASCII
# position can be tested for containment.
$spans = [System.Collections.Generic.List[object]]::new()
foreach ($t in $tokens) {
    if ($stringKinds -contains [string]$t.Kind) {
        $spans.Add([pscustomobject]@{
            Start = [int]$t.Extent.StartOffset
            End   = [int]$t.Extent.EndOffset
        }) | Out-Null
    }
}
$spanArray = [object[]]$spans.ToArray()

# Read the text the same way the parser did (BOM stripped by .NET), so
# character offsets line up with the token extents.
$text = [System.IO.File]::ReadAllText($Path)

$unsanctioned = [System.Collections.Generic.List[object]]::new()
$total = 0
$line = 1
$col = 1
for ($i = 0; $i -lt $text.Length; $i++) {
    $ch = $text[$i]
    if ($ch -eq [char]10) { $line++; $col = 1; continue }
    if ($ch -eq [char]13) { continue }
    if ([int][char]$ch -gt 127) {
        $total++
        $inside = $false
        foreach ($s in $spanArray) {
            if ($i -ge $s.Start -and $i -lt $s.End) { $inside = $true; break }
        }
        if (-not $inside) {
            $unsanctioned.Add([pscustomobject]@{
                Line      = $line
                Column    = $col
                CodePoint = ('U+{0:X4}' -f [int][char]$ch)
            }) | Out-Null
        }
    }
    $col++
}

[pscustomobject]@{
    ParseErrorCount   = $parseErrorCount
    StringTokenCount  = $spanArray.Count
    NonAsciiTotal     = $total
    Unsanctioned      = [object[]]$unsanctioned.ToArray()
} | ConvertTo-Json -Depth 4 -Compress
'''


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def run_driver(pwsh: str, target: pathlib.Path):
    with tempfile.TemporaryDirectory() as td:
        driver = pathlib.Path(td) / "t54_driver.ps1"
        driver.write_text(DRIVER, encoding="utf-8")
        proc = subprocess.run(
            [pwsh, "-NoProfile", "-File", str(driver), "-Path", str(target)],
            capture_output=True, text=True, timeout=180)
    if proc.returncode != 0:
        return None, (f"rc={proc.returncode} "
                      f"stderr={proc.stderr.strip()[:300]!r}")
    try:
        return json.loads(proc.stdout), ""
    except json.JSONDecodeError:
        return None, f"non-JSON output: {proc.stdout.strip()[:200]!r}"


def main() -> int:
    passed = failed = 0

    print("=" * 72)
    print("T54 Source-file format contract (SPEC A.2)")
    print("=" * 72)

    pwsh = shutil.which("pwsh")

    for name in TARGETS:
        target = SUBPROJECT_ROOT / name
        print(f"\n-- {name}")

        passed, failed = check(
            f"{name}: deliverable is present",
            target.is_file(), "file not found", passed, failed)
        if not target.is_file():
            continue

        raw = target.read_bytes()

        passed, failed = check(
            f"{name}: begins with the UTF-8 BOM",
            raw[:3] == b"\xef\xbb\xbf",
            f"first bytes are {raw[:3]!r}", passed, failed)

        body = raw[3:] if raw[:3] == b"\xef\xbb\xbf" else raw
        cr = body.count(b"\r")
        lf = body.count(b"\n")
        crlf = body.count(b"\r\n")

        passed, failed = check(
            f"{name}: at least one CRLF pair is present",
            crlf > 0, "no CRLF pair found", passed, failed)
        passed, failed = check(
            f"{name}: no bare LF (every LF is preceded by CR)",
            lf == crlf, f"LF={lf} CRLF={crlf} (bare LF={lf - crlf})",
            passed, failed)
        passed, failed = check(
            f"{name}: no stray CR outside CRLF pairs",
            cr == crlf, f"CR={cr} CRLF={crlf} (stray CR={cr - crlf})",
            passed, failed)

        if pwsh is None:
            passed, failed = check(
                f"{name}: non-ASCII placement", False,
                "pwsh not on PATH (required, as for T40)", passed, failed)
            continue

        data, err = run_driver(pwsh, target)
        if data is None:
            passed, failed = check(
                f"{name}: parser driver", False, err, passed, failed)
            continue

        passed, failed = check(
            f"{name}: parses without errors under the pinned pwsh",
            int(data["ParseErrorCount"]) == 0,
            f"{data['ParseErrorCount']} parse error(s)", passed, failed)

        passed, failed = check(
            f"{name}: the parser yielded string tokens to judge against",
            int(data["StringTokenCount"]) > 0,
            "no string tokens found -- containment test would be vacuous",
            passed, failed)

        bad = data["Unsanctioned"] or []
        if isinstance(bad, dict):
            bad = [bad]
        detail = "; ".join(
            f"line {b['Line']} col {b['Column']} {b['CodePoint']}"
            for b in bad[:8])
        if len(bad) > 8:
            detail += f"; ... ({len(bad)} total)"
        passed, failed = check(
            f"{name}: every non-ASCII character lies inside a string "
            f"literal ({data['NonAsciiTotal']} measured)",
            len(bad) == 0, detail or "unsanctioned occurrences present",
            passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, "
          f"{passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
