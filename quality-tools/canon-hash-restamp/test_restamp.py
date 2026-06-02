#!/usr/bin/env python3
"""Tests for restamp.py.

A write-side tool must (a) detect a stale hash, (b) fix exactly it on --write,
(c) leave the body/version/policy/binding/BOM/CRLF byte-identical, and (d) report
in-sync afterwards. Each test builds a tiny synthetic canon tree. Runtime:
python3 (stdlib only). Run: python3 test_restamp.py
"""

import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from restamp import scan, main, canon_norm_hash, MARKER_BEGIN  # noqa: E402

BODY = "function Foo { param($X) $X }"
GOOD = canon_norm_hash(BODY)

UNIT = (
    "\ufeff# >>> CANONICAL unit_id=pwsh.helper.foo version=1.0.0 hash={hsh} "
    "policy=canonical binding=follow-latest >>>\r\n"
    "function Foo {{ param($X) $X }}\r\n"
    "# <<< CANONICAL unit_id=pwsh.helper.foo <<<\r\n"
)


def build(hsh):
    root = tempfile.mkdtemp(prefix="restamp-test-")
    pub = os.path.join(root, "reference-code", "powershell", "Public")
    os.makedirs(pub)
    with open(os.path.join(pub, "Foo.ps1"), "wb") as handle:
        handle.write(UNIT.format(hsh=hsh).encode("utf-8"))
    return root


def run():
    cases = []

    # 1. scan() detects a stale hash.
    root = build("deadbeefdeadbeef")
    rows = list(scan(root, "powershell"))
    stale = rows[0][2] != rows[0][3]
    cases.append(("scan detects stale hash", stale))

    # 2. --write fixes exactly the hash; body & other fields byte-identical.
    before = open(os.path.join(root, "reference-code", "powershell",
                               "Public", "Foo.ps1"), "rb").read()
    main(["--root", root, "--write"])
    after = open(os.path.join(root, "reference-code", "powershell",
                              "Public", "Foo.ps1"), "rb").read()
    # only the 16-hex hash token differs
    diff_ok = (before.replace(b"deadbeefdeadbeef", GOOD.encode()) == after)
    cases.append(("write fixes only the hash token (BOM/CRLF/body intact)",
                  diff_ok))

    # 3. after write, scan reports in sync.
    rows = list(scan(root, "powershell"))
    cases.append(("scan in sync after write", rows[0][2] == rows[0][3]))
    shutil.rmtree(root)

    # 4. an already-correct tree needs no rewrite (--check exits 0).
    root = build(GOOD)
    rc = main(["--root", root, "--check"])
    cases.append(("check exits 0 when in sync", rc == 0))
    shutil.rmtree(root)

    passed = 0
    for name, ok in cases:
        print("[%s] %s" % ("PASS" if ok else "FAIL", name))
        passed += int(ok)
    print("\n%d/%d checks passed" % (passed, len(cases)))
    return 0 if passed == len(cases) else 1


if __name__ == "__main__":
    sys.exit(run())
