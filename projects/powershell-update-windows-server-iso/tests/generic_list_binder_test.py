#!/usr/bin/env python3
"""T51: Generic.List binder & collection-materialization guard (offline).

Pins the r12.17 / r12.64 incident class: PowerShell 7.4+ can throw
'Argument types do not match' when a ``[System.Collections.Generic.List
[object]]`` containing PSCustomObject instances is materialized through
the array subexpression ``@(...)`` or constructed through ``New-Object``.
The repository rule is constructor creation (``::new()``) plus explicit
``.ToArray()`` materialization. This contract holds the script to that
rule statically and proves the safe pattern behaviorally under the
pinned pwsh.

Specification source: the r12.75 distribution's required suite, axes
R1217 / R1264 (input-only per the standing ruling; logic re-authored,
code not copied), plus the R1264 collection-shape rows deferred from T49
per the ledger. The real-environment-validated r12.75 script is the
specification baseline (code-anchored testing); the script is untouched.
The distribution's revision-floor rows are DROP (T40 pins the exact
ScriptVersion). Function-uniqueness for the oscdimg set is pinned in
T49; this contract pins collection-handling content.

Class: B (behaviour pins). Justification: the binder hazard and the
materialization discipline live in script code; no declared data
surface expresses them.

What this asserts:

  1. **Construction rule (r12.17).** The active script never constructs
     Generic.List through New-Object.
  2. **P11 evidence counting (r12.17).** P11 evidence takes RowCount
     from the Generic.List Count property directly; the failing
     array-subexpression form is absent.
  3. **oscdimg resolver collections (r12.64).** The repository-reference
     resolver uses constructor-created List[object]/List[string] and
     materializes records and errors through explicit typed ToArray();
     the forbidden array-subexpression forms are absent; the
     repository-resolution schema was advanced for the fix
     (secureboot-objects-oscdimg-resolution/1.1). The local-candidate
     resolver uses constructor-created List[string] and returns a typed
     ToArray(); the forbidden subexpression return is absent.
  4. **Safe-pattern runtime (r12.17/r12.64).** Under the pinned pwsh, a
     constructor-created List[object] holding PSCustomObject rows
     materializes through ToArray() with order and properties
     preserved and groups correctly; a List[string] materializes with
     both paths preserved; the exact r12.17 P11 evidence shape builds
     with RowCount from .Count.

Run:  python3 tests/generic_list_binder_test.py
Deps: pwsh on PATH (same dependency class as T40/T47/T48/T50/T52).
"""
from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"

DRIVER = r'''
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Name,[bool]$Ok,[string]$Detail='') {
    $results.Add([pscustomobject]@{Name=$Name;Ok=$Ok;Detail=$Detail}) | Out-Null
}
function Run-Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; Add-Result $Name $true }
    catch { Add-Result $Name $false ([string]$_.Exception.Message) }
}
function Expect([bool]$Cond,[string]$Why) { if (-not $Cond) { throw $Why } }
function Expect-Eq($Actual,$Expected,[string]$Why) {
    if ($Actual -ne $Expected) { throw "$Why expected=[$Expected] actual=[$Actual]" }
}

Run-Check 'constructor-created List[object] of PSCustomObjects materializes via ToArray' {
    $list = [System.Collections.Generic.List[object]]::new()
    $list.Add([pscustomobject]@{ Name = 'alpha' }) | Out-Null
    $list.Add([pscustomobject]@{ Name = 'beta' }) | Out-Null
    $materialized = [object[]]$list.ToArray()
    Expect-Eq $materialized.Count 2 'materialized count'
    Expect-Eq ([string]$materialized[0].Name) 'alpha' 'first element'
    Expect-Eq ([string]$materialized[1].Name) 'beta' 'second element'
}
Run-Check 'the r12.64 repository-record shape survives typed ToArray and grouping' {
    $records = [System.Collections.Generic.List[object]]::new()
    $records.Add([pscustomobject][ordered]@{ Name = 'main'; Hash = ('a' * 64) }) | Out-Null
    $records.Add([pscustomobject][ordered]@{ Name = 'release'; Hash = ('a' * 64) }) | Out-Null
    $recordArray = [object[]]$records.ToArray()
    Expect-Eq $recordArray.Count 2 'record count'
    Expect-Eq ([string]$recordArray[0].Name) 'main' 'first record name'
    Expect-Eq ([string]$recordArray[1].Name) 'release' 'second record name'
    $groups = @($recordArray | Group-Object Hash)
    Expect-Eq $groups.Count 1 'identity group count'
}
Run-Check 'a List[string] materializes both candidate paths via typed ToArray' {
    $paths = [System.Collections.Generic.List[string]]::new()
    $paths.Add('C:\one\oscdimg.exe') | Out-Null
    $paths.Add('C:\two\oscdimg.exe') | Out-Null
    $pathArray = [string[]]$paths.ToArray()
    Expect-Eq $pathArray.Count 2 'path count'
}
Run-Check 'the exact r12.17 P11 evidence shape builds with RowCount from .Count' {
    $rows = [System.Collections.Generic.List[object]]::new()
    $rows.Add([pscustomobject]@{ Check='IsoExists'; Status='Pass' }) | Out-Null
    $identity = [pscustomobject]@{ RunId='fixture'; OutputIsoSha256='fixture' }
    $p11Evidence = [pscustomobject][ordered]@{
        SchemaVersion='P11-static-verification/1.0'
        Status='Pass'
        Identity=$identity
        RowCount=$rows.Count
        FailureCount=0
    }
    Expect-Eq ([int]$p11Evidence.RowCount) 1 'RowCount'
    Expect-Eq ([string]$p11Evidence.Status) 'Pass' 'Status'
}

$results | ConvertTo-Json -Depth 4
'''


def extract_function(text: str, name: str) -> str:
    m = re.search(r"(?m)^function %s\b" % re.escape(name), text)
    if m is None:
        return ""
    i = text.index("{", m.start())
    depth = 0
    j = i
    while j < len(text):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return text[m.start():j + 1]


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def main() -> int:
    passed = failed = 0

    print("=" * 72)
    print("T51 Generic.List binder & collection-materialization guard")
    print("=" * 72)

    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")

    passed, failed = check(
        "no New-Object Generic.List construction in the active script",
        not re.search(r"New-Object\s+'?System\.Collections\.Generic\.List\[[^\]]+\]'?",
                      text),
        "New-Object construction found", passed, failed)
    passed, failed = check(
        "P11 evidence takes RowCount from the List Count property directly",
        "RowCount=$rows.Count" in text,
        "direct Count usage missing", passed, failed)
    passed, failed = check(
        "the failing P11 array-subexpression count form is absent",
        "RowCount=@($rows).Count" not in text,
        "forbidden form present", passed, failed)

    rep = extract_function(text, "Resolve-OscdimgRepositoryReferences")
    passed, failed = check(
        "repository resolver constructs List[object] via ::new()",
        "[System.Collections.Generic.List[object]]::new()" in rep,
        "constructor creation missing", passed, failed)
    passed, failed = check(
        "repository resolver constructs List[string] via ::new()",
        "[System.Collections.Generic.List[string]]::new()" in rep,
        "constructor creation missing", passed, failed)
    passed, failed = check(
        "repository records are materialized through explicit typed ToArray",
        "$recordArray = [object[]]$records.ToArray()" in rep,
        "record materialization missing", passed, failed)
    passed, failed = check(
        "repository errors are materialized through explicit typed ToArray",
        "$errorArray = [string[]]$errors.ToArray()" in rep,
        "error materialization missing", passed, failed)
    passed, failed = check(
        "forbidden record array-subexpression is absent from the repository resolver",
        "Records = @($records)" not in rep,
        "forbidden form present", passed, failed)
    passed, failed = check(
        "forbidden error array-subexpression is absent from the repository resolver",
        "Errors = @($errors)" not in rep,
        "forbidden form present", passed, failed)
    passed, failed = check(
        "repository-resolution schema advanced for the collection-contract fix",
        "SchemaVersion = 'secureboot-objects-oscdimg-resolution/1.1'" in rep,
        "schema pin missing", passed, failed)

    loc = extract_function(text, "Get-OscdimgLocalCandidatePaths")
    passed, failed = check(
        "local-candidate resolver constructs List[string] via ::new()",
        "[System.Collections.Generic.List[string]]::new()" in loc,
        "constructor creation missing", passed, failed)
    passed, failed = check(
        "local-candidate resolver returns an explicit typed ToArray",
        "return [string[]]$list.ToArray()" in loc,
        "typed return missing", passed, failed)
    passed, failed = check(
        "forbidden local-candidate subexpression return is absent",
        "return @($list)" not in loc,
        "forbidden form present", passed, failed)

    pwsh = shutil.which("pwsh")
    if pwsh is None:
        passed, failed = check("behavioral driver", False,
                               "pwsh not on PATH (required, as for T40)",
                               passed, failed)
    else:
        with tempfile.TemporaryDirectory() as td:
            driver = pathlib.Path(td) / "t51_driver.ps1"
            driver.write_text(DRIVER, encoding="utf-8")
            proc = subprocess.run(
                [pwsh, "-NoProfile", "-File", str(driver)],
                capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            passed, failed = check(
                "behavioral driver", False,
                f"rc={proc.returncode} stderr={proc.stderr.strip()[:300]!r}",
                passed, failed)
        else:
            try:
                rows = json.loads(proc.stdout)
            except json.JSONDecodeError:
                rows = None
            if rows is None:
                passed, failed = check(
                    "behavioral driver", False,
                    f"non-JSON output: {proc.stdout.strip()[:200]!r}",
                    passed, failed)
            else:
                if isinstance(rows, dict):
                    rows = [rows]
                for row in rows:
                    passed, failed = check(
                        row.get("Name", "<unnamed>"),
                        bool(row.get("Ok")),
                        str(row.get("Detail", ""))[:300],
                        passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, "
          f"{passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
