#!/usr/bin/env python3
"""T43: baseline-Line integrity and identity declaration (D-contract, offline).

Anchors: `PatchBaseline.Lines[].Integrity` and `.Roles` (`CanonicalV4Fields`),
with `.Digest` / `.Sha256` / `.ApplyOrder` recognised as the compatibility
path declared in `Compatibility.LegacyFieldsRetained`.

What this asserts:

  1. **Integrity is the canonical carrier.** Where a Line declares
     `Integrity.Sha1`, its legacy flat `Digest` must agree with it -- the two
     surfaces may coexist during the compatibility window but must never
     disagree, because a disagreement means one of them is stale and the
     runtime's choice of source becomes load-bearing by accident. Same for
     `Integrity.Sha256` vs the flat `Sha256`.
  2. **A hash declares its encoding.** `Encoding` must be stated, and where a
     hex rendering is also carried it must be the same value in the other
     encoding. This is the r11.44 base64-vs-hex boundary defect, re-expressed
     against the canonical field instead of against the flat one.
  3. **Every Line carries enough identity to be resolved.** Under the r12
     model the download URL is *resolved at runtime* from the Microsoft
     Update Catalog under `DiscoveryPolicy`; committing one would be the
     hard-coded staleness hazard the model exists to avoid. What must be
     declared is identity: a `KbId` plus at least one of `UpdateId` /
     `FileName` / `PackageId` for the resolver to key on. A `DownloadUrl`, if
     present, is a cached resolution and not a requirement.
     This replaces the retired rule "every Kind=SSU has a non-empty
     DownloadUrl", which assumed both that a standalone SSU always exists and
     that URLs live in the committed dataset -- two assumptions of the
     superseded offline-dataset model.
     Where a Line declares `ParentKbId` it names the Catalog *umbrella* that
     carries it (the .NET CU umbrella pattern), which is by design NOT a
     sibling baseline Line -- so the contract asserts the identity is
     well-formed, not that it is present in the baseline.
  4. **`State` is declared and drives the integrity requirement**: a Line
     frozen or further along must carry SHA-256; a Line still in discovery
     need not.

Why it is a D-contract: the retired T23 asserted a per-OS `PatchModel` ⇔ SSU
matrix and a mandatory standalone download URL; the retired T29 pinned two
specific script lines. Both stated Microsoft's packaging model in the test.
The model is now declared per Line, so this contract reads it.

Supersedes the retired T23 and the wiring half of T29. The base64/hex boundary
behaviour of `ConvertTo-HexDigestString` is model-independent and stays in
T29's surviving rows.

Convergence: IN-FORCE wherever `Lines[].Integrity` exists; NOT-YET before.

Run from the project root:

    python3 tests/line_integrity_declaration_test.py
"""
from __future__ import annotations

import base64
import binascii
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

# States at or beyond which a SHA-256 is required. Read from the declared
# vocabulary rather than invented: these are the states ValidationPolicy's
# RequireSha256BeforeFreeze gates on.
FROZEN_STATES = {"Frozen", "E3Validated", "E4Validated", "E5Validated",
                 "Approved", "Reviewed"}

ALGORITHMS = ("Sha1", "Sha256")


def check(label, ok, detail, p, f):
    print(f"{PASS if ok else FAIL}  {label}: {detail}")
    return (p + 1, f) if ok else (p, f + 1)


def to_hex(value, encoding):
    """Normalise a declared hash value to lowercase hex, or None."""
    if not value:
        return None
    enc = (encoding or "").lower()
    try:
        if enc == "base64":
            return binascii.hexlify(base64.b64decode(value)).decode().lower()
        if enc in ("hex", ""):
            v = str(value).strip().lower()
            int(v, 16)
            return v
    except (binascii.Error, ValueError):
        return None
    return None


def main() -> int:
    passed = failed = skipped = 0

    print("=" * 72)
    print("T43 baseline-Line integrity declaration (D-contract)")
    print("=" * 72)

    for fname in CONFIGS:
        fpath = DATA_DIR / fname
        if not fpath.exists():
            print(f"{FAIL}  {fname}: not found under data/")
            failed += 1
            continue
        cfg = json.loads(fpath.read_text(encoding="utf-8-sig"))
        lines = (cfg.get("PatchBaseline") or {}).get("Lines") or []
        anchored = [ln for ln in lines if ln.get("Integrity")]

        if not anchored:
            print(f"{SKIP}  {fname}: NOT-YET -- no Lines[].Integrity declared")
            skipped += 1
            continue

        print(f"=== {fname} ({len(anchored)}/{len(lines)} Lines anchored) ===")

        for ln in anchored:
            kind = ln.get("Kind")
            kb = ln.get("KbId")
            tag = f"{fname} {kind}({kb})"
            integ = ln.get("Integrity") or {}

            # 1/2. canonical vs legacy agreement, and encoding discipline
            for alg in ALGORITHMS:
                node = integ.get(alg)
                if not node:
                    continue
                enc = node.get("Encoding")
                passed, failed = check(
                    f"{tag}: Integrity.{alg} declares its encoding",
                    bool(enc), f"Encoding={enc!r}", passed, failed)
                canon = to_hex(node.get("Value"), enc)
                passed, failed = check(
                    f"{tag}: Integrity.{alg} value decodes under its encoding",
                    canon is not None,
                    f"Value={str(node.get('Value'))[:24]!r} Encoding={enc!r}",
                    passed, failed)
                if node.get("Hex") and canon:
                    passed, failed = check(
                        f"{tag}: Integrity.{alg} Hex matches Value",
                        str(node["Hex"]).lower() == canon,
                        f"Hex={str(node['Hex'])[:20]}... canon={canon[:20]}...",
                        passed, failed)
                legacy = ln.get("Digest") if alg == "Sha1" else ln.get("Sha256")
                if legacy and canon:
                    legacy_hex = (to_hex(legacy, "base64")
                                  or to_hex(legacy, "hex"))
                    passed, failed = check(
                        f"{tag}: legacy {'Digest' if alg == 'Sha1' else 'Sha256'}"
                        f" agrees with Integrity.{alg}",
                        legacy_hex == canon,
                        f"legacy={str(legacy_hex)[:20]}... "
                        f"canonical={canon[:20]}...", passed, failed)

            # 3. resolvability by declared identity, not by a committed URL
            keys = [k for k in ("UpdateId", "FileName", "PackageId")
                    if ln.get(k)]
            passed, failed = check(
                f"{tag}: carries a KB identity",
                bool(kb) and str(kb).upper().startswith("KB"),
                f"KbId={kb!r}", passed, failed)
            passed, failed = check(
                f"{tag}: carries a resolver key beyond the KB number",
                bool(keys),
                f"resolver keys={keys}" if keys
                else "no UpdateId / FileName / PackageId to resolve on",
                passed, failed)
            parent = ln.get("ParentKbId")
            if parent:
                passed, failed = check(
                    f"{tag}: ParentKbId is a well-formed umbrella identity",
                    str(parent).upper().startswith("KB")
                    and str(parent)[2:].isdigit(),
                    f"ParentKbId={parent!r} (Catalog umbrella; by design not a "
                    f"sibling baseline Line)", passed, failed)

            # 4. State gates the integrity requirement
            state = ln.get("State")
            passed, failed = check(
                f"{tag}: State is declared",
                bool(state), f"State={state!r}", passed, failed)
            if state in FROZEN_STATES:
                sha256 = (integ.get("Sha256") or {}).get("Value") \
                    or ln.get("Sha256")
                passed, failed = check(
                    f"{tag}: a {state} Line carries SHA-256",
                    bool(sha256),
                    "present" if sha256 else "absent under a frozen state",
                    passed, failed)

            # Roles remain the routing key; a Line with no role is unroutable.
            passed, failed = check(
                f"{tag}: declares at least one role",
                bool(ln.get("Roles")), f"Roles={ln.get('Roles')}",
                passed, failed)
        print()

    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total"
          + (f", {skipped} NOT-YET" if skipped else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
