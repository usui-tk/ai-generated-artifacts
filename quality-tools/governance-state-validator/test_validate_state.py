#!/usr/bin/env python3
"""Tests for validate_state.py.

A validation gate is only trustworthy if it actually fails on bad input, so each
test builds a tiny synthetic repo tree (real governance schemas + crafted state)
and asserts that the corresponding check fires (or stays green for the happy
path). Runtime: python3 + jsonschema. Run: python3 test_validate_state.py
"""

import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

from validate_state import validate, _canonical_line, canon_norm_hash  # noqa: E402

# Region body of the synthetic unit; its correct ADR 0015 hash is computed at
# runtime so the happy path never goes stale if the normalizer is revised (the
# FIXED contract is pinned separately by the golden vectors GV-1..GV-5 below).
_FOO_BODY = "function Foo { param($X) $X }"
_FOO_HASH = canon_norm_hash(_FOO_BODY)

MARKER = (
    "\ufeff# >>> CANONICAL unit_id={uid} version={ver} hash={hsh} "
    "policy={pol} binding={bnd} >>>\r\n"
    "function Foo {{ param($X) $X }}\r\n"
    "# <<< CANONICAL unit_id={uid} <<<\r\n"
)

# Golden vectors (GV) — the FIXED ADR 0015 contract. These are hardcoded on
# purpose: any drift in a reuse-by-copy normalizer (validator / restamp /
# scanner) is caught by a GV mismatch. GV-2 and GV-3 share a hash, proving
# comment differences cancel (strip-then-collapse).
GOLDEN_VECTORS = [
    ("GV-1 empty", "", "e3b0c44298fc1c14"),
    ("GV-2 simple", "function Foo { $X }", "f36eed9db4380dae"),
    ("GV-3 comment-cancels",
     "function Foo {\n    # a comment\n    $X\n}", "f36eed9db4380dae"),
    ("GV-4 string-literal",
     'function Bar { Write-Output "hello world" }', "f8749da115ef182a"),
    ("GV-5 here-string",
     'function Baz {\n    $t = @"\nline1\nline2\n"@\n    $t\n}',
     "a65ca2f4b74efce1"),
]

BASE_RECORD = {
    "schema_version": "1",
    "unit_id": "pwsh.helper.foo",
    "kind": "powershell-helper",
    "canonical_location": "reference-code/powershell/Public/Foo.ps1",
    "canonical_version": "0.1.0",
    "change_policy": "canonical",
    "binding_mode": "follow-latest",
    "consumers": [],
    "tested": False,
    "platform_scope": "cross-platform",
}


def build_root(manifest_lines, marker_ver="0.1.0", write_canon=True,
               canon_extra=None, tests_extra=None, marker_hash=None,
               marker_policy="canonical", marker_binding="follow-latest"):
    root = tempfile.mkdtemp(prefix="gsv-test-")
    os.makedirs(os.path.join(root, "governance", "schema"))
    os.makedirs(os.path.join(root, "governance", "state"))
    pub = os.path.join(root, "reference-code", "powershell", "Public")
    os.makedirs(pub)
    for name in ("manifest.schema.json", "observation.schema.json"):
        shutil.copy(os.path.join(REPO_ROOT, "governance", "schema", name),
                    os.path.join(root, "governance", "schema", name))
    with open(os.path.join(root, "governance", "state", "manifest.jsonl"),
              "w", newline="\n") as handle:
        handle.write("\n".join(manifest_lines) + "\n")
    if write_canon:
        with open(os.path.join(pub, "Foo.ps1"), "wb") as handle:
            handle.write(MARKER.format(uid="pwsh.helper.foo", ver=marker_ver,
                                       hsh=marker_hash or _FOO_HASH,
                                       pol=marker_policy,
                                       bnd=marker_binding).encode("utf-8"))
    for extra in (canon_extra or []):
        with open(os.path.join(pub, extra), "wb") as handle:
            handle.write(MARKER.format(uid="pwsh.helper.x", ver="0.1.0",
                                       hsh=_FOO_HASH, pol="canonical",
                                       bnd="follow-latest").encode("utf-8"))
    # Non-unit files under the canon tree (tests/) must NOT be treated as units
    # (ADR 0011 manifest-master): create them to prove they are not flagged.
    for extra in (tests_extra or []):
        tests_dir = os.path.join(root, "reference-code", "powershell", "tests")
        os.makedirs(tests_dir, exist_ok=True)
        with open(os.path.join(tests_dir, extra), "wb") as handle:
            handle.write(b"\xef\xbb\xbf# test scaffolding, not a managed unit\r\n")
    return root


def checks_present(findings):
    return {check for check, _ in findings}


def run():
    cases = []

    # Happy path -> 0 findings.
    root = build_root([_canonical_line(BASE_RECORD)])
    findings, _, _ = validate(root, quiet=True)
    cases.append(("happy-path green", findings == [], findings))
    shutil.rmtree(root)

    # A: schema violation (change_policy not in enum).
    bad = dict(BASE_RECORD, change_policy="bogus")
    root = build_root([_canonical_line(bad)])
    findings, _, _ = validate(root, quiet=True)
    cases.append(("A schema enum violation caught", "A" in checks_present(findings),
                  findings))
    shutil.rmtree(root)

    # C: canonical_location missing on disk.
    root = build_root([_canonical_line(BASE_RECORD)], write_canon=False)
    findings, _, _ = validate(root, quiet=True)
    cases.append(("C missing canonical_location caught",
                  "C" in checks_present(findings), findings))
    shutil.rmtree(root)

    # D: manifest<->marker version mismatch.
    root = build_root([_canonical_line(BASE_RECORD)], marker_ver="9.9.9")
    findings, _, _ = validate(root, quiet=True)
    cases.append(("D version mismatch caught", "D" in checks_present(findings),
                  findings))
    shutil.rmtree(root)

    # E: orphan canon file not registered in manifest.
    root = build_root([_canonical_line(BASE_RECORD)], canon_extra=["Orphan.ps1"])
    findings, _, _ = validate(root, quiet=True)
    cases.append(("E orphan canon file caught", "E" in checks_present(findings),
                  findings))
    shutil.rmtree(root)

    # E (manifest-master, ADR 0011 §1): a file under tests/ is NOT a managed unit
    # and must NOT be flagged, even though it lives under the canon tree.
    root = build_root([_canonical_line(BASE_RECORD)],
                      tests_extra=["Canon.Smoke.Tests.ps1", "CanonSessionState.ps1"])
    findings, _, _ = validate(root, quiet=True)
    cases.append(("E tests/ file not flagged (manifest-master)",
                  "E" not in checks_present(findings) and findings == [],
                  findings))
    shutil.rmtree(root)

    # F: non-canonical (not key-sorted) line.
    unsorted = json.dumps(BASE_RECORD, sort_keys=False, separators=(",", ":"))
    root = build_root([unsorted])
    findings, _, _ = validate(root, quiet=True)
    cases.append(("F non-canonical line caught", "F" in checks_present(findings),
                  findings))
    shutil.rmtree(root)

    # G: stale marker hash (the P3.0 bug class). A marker whose hash does not
    # match the recomputed canonical hash must fire G.
    root = build_root([_canonical_line(BASE_RECORD)],
                      marker_hash="deadbeefdeadbeef")
    findings, _, _ = validate(root, quiet=True)
    cases.append(("G stale marker hash caught", "G" in checks_present(findings),
                  findings))
    shutil.rmtree(root)

    # D: marker policy disagrees with the manifest default.
    root = build_root([_canonical_line(BASE_RECORD)], marker_policy="forked")
    findings, _, _ = validate(root, quiet=True)
    cases.append(("D policy mismatch caught", "D" in checks_present(findings),
                  findings))
    shutil.rmtree(root)

    # D: marker binding disagrees with the manifest default.
    root = build_root([_canonical_line(BASE_RECORD)], marker_binding="pin")
    findings, _, _ = validate(root, quiet=True)
    cases.append(("D binding mismatch caught", "D" in checks_present(findings),
                  findings))
    shutil.rmtree(root)

    # Golden vectors: the FIXED ADR 0015 hash contract. A normalizer drift in
    # any reuse-by-copy implementation is caught here.
    for name, body, expected in GOLDEN_VECTORS:
        cases.append(("golden vector %s" % name,
                      canon_norm_hash(body) == expected,
                      "%s != %s" % (canon_norm_hash(body), expected)))

    passed = 0
    for name, ok, findings in cases:
        status = "PASS" if ok else "FAIL"
        print("[%s] %s" % (status, name))
        if not ok:
            print("       findings=%r" % findings)
        passed += int(ok)
    print("\n%d/%d checks passed" % (passed, len(cases)))
    return 0 if passed == len(cases) else 1


if __name__ == "__main__":
    sys.exit(run())
