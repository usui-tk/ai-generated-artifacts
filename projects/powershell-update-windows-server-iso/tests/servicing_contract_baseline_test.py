#!/usr/bin/env python3
"""T45: servicing-contract-baseline integrity (D-contract, offline).

Anchor: `data/servicing-contract-baselines.json` -- an instrument the r12
series authored for itself. Its stated purpose:

    "Fail closed when any OS-specific servicing contract or component changes
     without an explicitly reviewed baseline update."

It pins, per OS, a contract revision plus SHA-256 digests of the contract and
its components (target map, apply sequence, verification, discovery, .NET,
setup, observation). This contract holds the file to the shape it declares
and to agreement with the configs it pins.

What this asserts:

  1. The instrument declares its own schema version and purpose.
  2. Every OS that has a committed config has a contract entry, and no entry
     exists for an OS that has none.
  3. Each entry's `ContractRevision` is well formed and names its own OS.
  4. Every declared digest is a lowercase 64-character SHA-256.
  5. `Sha256` and `ContractSha256` agree where both are present -- they are
     two names for the same pin, and a divergence means one is stale.
  6. Every OS in one entry declares the same digest component set as the
     others: a component present for three OSes and absent for the fourth is
     the per-OS special-casing this series set out to remove.
  7. **[extension, 2026-08-07, re-impl phase D]** The script-computed
     component hashes agree with the declared baseline: the canonical-JSON
     contract constructors are extracted from the script's own AST under
     the pinned pwsh, `Get-ServicingContractComponentHashes` is evaluated
     for every OS, and each of the eight component digests must equal the
     declared value. This closes the loop the first six assertions leave
     open — that the declared file matches itself is necessary but not
     sufficient; the pin is that the *script* still computes what the file
     declares. Specification source: distribution axis R1252 (ADOPT-D —
     the assertion is anchored on the declared instrument, not on
     distribution test code). This extension adds a pwsh dependency to
     what was previously a pure-Python contract (same dependency class as
     T40/T47/T48/T50/T51/T52).

Convergence: **NOT-YET before r12.44**, where the instrument was introduced;
IN-FORCE from r12.44 onward. This is the model's first measured NOT-YET: the
contract is not failing on the earlier revisions, it simply has no anchor
there yet. Recorded rather than judged.

Run from the project root:

    python3 tests/servicing_contract_baseline_test.py

Deps: pwsh on PATH (extension section; the declaration-shape sections
remain pure Python).
"""
from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

TESTS_DIR = pathlib.Path(__file__).resolve().parent
DATA_DIR = TESTS_DIR.parent / "data"
BASELINE_PATH = DATA_DIR / "servicing-contract-baselines.json"
SCRIPT_PATH = TESTS_DIR.parent / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"
SKIP = "  SKIP"

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REVISION_RE = re.compile(r"^(Server\d{4})-r(\d+)$")

# The eight component digests the instrument declares per OS (the legacy
# 'Sha256' alias is checked against ContractSha256 by assertion 5).
COMPONENT_FIELDS = [
    "ContractSha256", "TargetMapSha256", "SequenceSha256",
    "VerificationSha256", "ObservationSha256", "DiscoverySha256",
    "DotNetSha256", "SetupSha256",
]
CONTRACT_OSES = ["Server2016", "Server2019", "Server2022", "Server2025"]
# The canonical-JSON / contract function set the extension driver
# extracts from the script AST.
CONTRACT_FUNCTIONS = [
    "_CanonicalJson_WriteString", "_CanonicalJson_WriteNumber",
    "_CanonicalJson_WriteObject", "_CanonicalJson_WriteArray",
    "_CanonicalJson_WriteValue", "ConvertTo-CanonicalJson",
    "Get-CanonicalObjectSha256",
    "New-Server2016ServicingContract", "New-Server2019ServicingContract",
    "New-Server2022ServicingContract", "New-Server2025ServicingContract",
    "Get-ServicingContract", "Get-ServicingContractHash",
    "Get-ServicingContractComponentHashes",
]

DRIVER = r'''
param([Parameter(Mandatory)][string]$ScriptPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$FunctionNames = @(__FUNCTION_NAMES__)
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) { throw 'script parse errors' }
foreach ($n in $FunctionNames) {
    $defs=@($ast.FindAll({param($x)$x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true))
    if ($defs.Count -ne 1) { throw "function $n definition count $($defs.Count)" }
    Invoke-Expression $defs[0].Extent.Text
}
$out = [ordered]@{}
foreach ($os in @('Server2016','Server2019','Server2022','Server2025')) {
    $hashes = Get-ServicingContractComponentHashes -Contract (Get-ServicingContract -OsKey $os)
    $entry = [ordered]@{}
    foreach ($field in @('ContractSha256','TargetMapSha256','SequenceSha256','VerificationSha256','ObservationSha256','DiscoverySha256','DotNetSha256','SetupSha256')) {
        $entry[$field] = [string]$hashes.$field
    }
    $out[$os] = $entry
}
[pscustomobject]$out | ConvertTo-Json -Depth 4
'''


def check(label, ok, detail, p, f):
    print(f"{PASS if ok else FAIL}  {label}: {detail}")
    return (p + 1, f) if ok else (p, f + 1)


def main() -> int:
    passed = failed = 0

    print("=" * 72)
    print("T45 servicing-contract-baseline integrity (D-contract)")
    print("=" * 72)

    if not BASELINE_PATH.exists():
        print(f"{SKIP}  NOT-YET -- {BASELINE_PATH.name} is not committed at "
              f"this revision")
        print("  Summary: 0 passed, 0 failed, 0 total, 1 NOT-YET")
        return 0

    doc = json.loads(BASELINE_PATH.read_text(encoding="utf-8-sig"))

    passed, failed = check(
        "instrument declares its schema version",
        bool(doc.get("SchemaVersion")),
        f"SchemaVersion={doc.get('SchemaVersion')!r}", passed, failed)
    passed, failed = check(
        "instrument declares its purpose",
        bool(doc.get("Purpose")),
        (str(doc.get("Purpose"))[:70] + "...") if doc.get("Purpose")
        else "absent", passed, failed)

    contracts = doc.get("Contracts") or {}
    committed = {p.stem.replace("config-", "")
                 for p in DATA_DIR.glob("config-Server*.json")}
    passed, failed = check(
        "every committed OS config has a baseline entry",
        committed <= set(contracts),
        f"configs={sorted(committed)} entries={sorted(contracts)}",
        passed, failed)
    passed, failed = check(
        "no baseline entry without a committed config",
        set(contracts) <= committed,
        f"orphans={sorted(set(contracts) - committed)}"
        if set(contracts) - committed else "none", passed, failed)

    # Digest component sets must be uniform across OSes.
    digest_keys = {
        os_key: sorted(k for k in entry if k.endswith("Sha256"))
        for os_key, entry in contracts.items()
    }
    uniform = len({tuple(v) for v in digest_keys.values()}) <= 1
    passed, failed = check(
        "all OSes declare the same digest component set",
        uniform,
        json.dumps({k: len(v) for k, v in digest_keys.items()})
        if uniform else json.dumps(digest_keys), passed, failed)

    for os_key in sorted(contracts):
        entry = contracts[os_key] or {}
        rev = entry.get("ContractRevision")
        m = REVISION_RE.match(str(rev or ""))
        passed, failed = check(
            f"{os_key}: ContractRevision is well formed",
            m is not None, f"ContractRevision={rev!r}", passed, failed)
        if m:
            passed, failed = check(
                f"{os_key}: ContractRevision names its own OS",
                m.group(1) == os_key,
                f"declared={m.group(1)} entry={os_key}", passed, failed)

        bad = {k: v for k, v in entry.items()
               if k.endswith("Sha256") and not SHA256_RE.match(str(v or ""))}
        passed, failed = check(
            f"{os_key}: every declared digest is a lowercase SHA-256",
            not bad,
            f"malformed={sorted(bad)}" if bad
            else f"{len([k for k in entry if k.endswith('Sha256')])} digest(s)",
            passed, failed)

        if entry.get("Sha256") and entry.get("ContractSha256"):
            passed, failed = check(
                f"{os_key}: Sha256 and ContractSha256 agree",
                entry["Sha256"] == entry["ContractSha256"],
                f"{str(entry['Sha256'])[:16]}... vs "
                f"{str(entry['ContractSha256'])[:16]}...", passed, failed)

    # 7. Extension: the script still computes what the file declares.
    pwsh = shutil.which("pwsh")
    if pwsh is None:
        passed, failed = check(
            "script-computed component hashes cross-check", False,
            "pwsh not on PATH (required for the extension, as for T40)",
            passed, failed)
    else:
        with tempfile.TemporaryDirectory() as td:
            driver = pathlib.Path(td) / "t45_driver.ps1"
            names = ",".join(f"'{n}'" for n in CONTRACT_FUNCTIONS)
            driver.write_text(DRIVER.replace("__FUNCTION_NAMES__", names),
                              encoding="utf-8")
            proc = subprocess.run(
                [pwsh, "-NoProfile", "-File", str(driver),
                 "-ScriptPath", str(SCRIPT_PATH)],
                capture_output=True, text=True, timeout=120)
        computed = None
        if proc.returncode == 0:
            try:
                computed = json.loads(proc.stdout)
            except json.JSONDecodeError:
                computed = None
        passed, failed = check(
            "contract constructors extracted and evaluated under pwsh",
            computed is not None,
            f"rc={proc.returncode} "
            f"stderr={proc.stderr.strip()[:200]!r}"
            if computed is None else f"{len(computed)} OS entr(ies)",
            passed, failed)
        if computed is not None:
            for os_key in CONTRACT_OSES:
                declared = contracts.get(os_key, {})
                actual = computed.get(os_key, {})
                mism = [f for f in COMPONENT_FIELDS
                        if str(actual.get(f, "")) != str(declared.get(f, ""))]
                passed, failed = check(
                    f"{os_key}: script-computed component hashes match the "
                    f"declared baseline",
                    not mism,
                    f"mismatched={mism}" if mism
                    else f"{len(COMPONENT_FIELDS)} component digest(s)",
                    passed, failed)

    print()
    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
