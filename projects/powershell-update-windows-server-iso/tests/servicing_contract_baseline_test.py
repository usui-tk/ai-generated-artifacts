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

Convergence: **NOT-YET before r12.44**, where the instrument was introduced;
IN-FORCE from r12.44 onward. This is the model's first measured NOT-YET: the
contract is not failing on the earlier revisions, it simply has no anchor
there yet. Recorded rather than judged.

Run from the project root:

    python3 tests/servicing_contract_baseline_test.py
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
DATA_DIR = TESTS_DIR.parent / "data"
BASELINE_PATH = DATA_DIR / "servicing-contract-baselines.json"

PASS = "  PASS"
FAIL = "  FAIL"
SKIP = "  SKIP"

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REVISION_RE = re.compile(r"^(Server\d{4})-r(\d+)$")


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

    print()
    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
