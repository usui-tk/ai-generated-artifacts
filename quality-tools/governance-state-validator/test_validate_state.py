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

from validate_state import validate, _canonical_line  # noqa: E402

MARKER = (
    "\ufeff# >>> CANONICAL unit_id={uid} version={ver} hash=deadbeefdeadbeef "
    "policy=canonical binding=follow-latest >>>\r\n"
    "function Foo {{ param($X) $X }}\r\n"
    "# <<< CANONICAL unit_id={uid} <<<\r\n"
)

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
}


def build_root(manifest_lines, marker_ver="0.1.0", write_canon=True,
               canon_extra=None):
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
            handle.write(MARKER.format(uid="pwsh.helper.foo",
                                       ver=marker_ver).encode("utf-8"))
    for extra in (canon_extra or []):
        with open(os.path.join(pub, extra), "wb") as handle:
            handle.write(MARKER.format(uid="pwsh.helper.x", ver="0.1.0")
                         .encode("utf-8"))
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

    # F: non-canonical (not key-sorted) line.
    unsorted = json.dumps(BASE_RECORD, sort_keys=False, separators=(",", ":"))
    root = build_root([unsorted])
    findings, _, _ = validate(root, quiet=True)
    cases.append(("F non-canonical line caught", "F" in checks_present(findings),
                  findings))
    shutil.rmtree(root)

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
