#!/usr/bin/env python3
"""Tests for scanner.py (P3.6 offline scanner tests).

P3 builds + fixture-tests the scanner; its first real run is P6 (consumers carry
no vendored markers until vendoring). So every branch is exercised against a
synthetic repo tree, not a live consumer:
  - region/match, region/drift, region/forked-frozen
  - whole-tool (null convention, drift n/a)
  - F1: every record stamps runtime.duckdb == "n/a"
  - F4: a malformed marker -> drift "unknown" (no crash, in-enum)
  - GV-1..5: the normalizer matches the fixed ADR 0015 contract (shared with the
    validator/restamp copies)
  - schema conformance: every emitted line validates against observation.schema.json
    and is canonical-JSON (the #3 gate the scanner's output must pass)

Runtime: python3 + jsonschema. Run: python3 test_scanner.py
"""

import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

from scanner import scan, canon_norm_hash, _canonical_line, extract_region  # noqa: E402

# A canonical region body and its correct hash (computed live, so the happy path
# never goes stale; the FIXED contract is pinned by GV-1..5 below).
CANON_BODY = "function Foo {\n    param($X)\n    $X\n}"
CANON_HASH = canon_norm_hash(CANON_BODY)

CANON_FILE = (
    "\ufeff# >>> CANONICAL unit_id=pwsh.helper.foo version=1.0.0 hash={hsh} "
    "policy=canonical binding=follow-latest >>>\r\n"
    "function Foo {{\r\n    param($X)\r\n    $X\r\n}}\r\n"
    "# <<< CANONICAL unit_id=pwsh.helper.foo <<<\r\n"
)

# Golden vectors GV-1..5: the FIXED ADR 0015 contract, shared with the validator
# self-test. A drift in this reuse-by-copy normalizer is caught here.
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


def _manifest_line(unit_id, kind, loc, consumers, policy="canonical",
                   binding="follow-latest", version="1.0.0"):
    rec = {
        "schema_version": "1", "unit_id": unit_id, "kind": kind,
        "canonical_location": loc, "canonical_version": version,
        "change_policy": policy, "binding_mode": binding,
        "consumers": consumers, "tested": True, "platform_scope": "cross-platform",
    }
    return _canonical_line(rec)


def build_root(consumer_body=None, consumer_marker_hash=None,
               consumer_policy="canonical", malformed=False, whole_tool=True):
    """Build a synthetic repo: one region unit (canon) + optional consumer + an
    optional whole-tool unit."""
    root = tempfile.mkdtemp(prefix="scanner-test-")
    pub = os.path.join(root, "reference-code", "powershell", "Public")
    os.makedirs(pub)
    state = os.path.join(root, "governance", "state")
    os.makedirs(state)
    # canon region unit
    with open(os.path.join(pub, "Foo.ps1"), "wb") as h:
        h.write(CANON_FILE.format(hsh=CANON_HASH).encode("utf-8"))

    lines = []
    consumers = []
    if consumer_body is not None:
        cpath = "scripts/consumer/Use-Foo.ps1"
        abs = os.path.join(root, cpath)
        os.makedirs(os.path.dirname(abs), exist_ok=True)
        if malformed:
            # BEGIN marker with no END -> malformed pair (F4)
            content = ("\ufeff# >>> CANONICAL unit_id=pwsh.helper.foo "
                       "version=1.0.0 hash=deadbeefdeadbeef policy=canonical "
                       "binding=follow-latest >>>\r\n" + consumer_body + "\r\n")
        else:
            content = (
                "\ufeff# >>> CANONICAL unit_id=pwsh.helper.foo version=1.0.0 "
                "hash=%s policy=%s binding=follow-latest >>>\r\n%s\r\n"
                "# <<< CANONICAL unit_id=pwsh.helper.foo <<<\r\n"
                % (consumer_marker_hash or CANON_HASH, consumer_policy,
                   consumer_body))
        with open(abs, "wb") as h:
            h.write(content.encode("utf-8"))
        consumers = [{"consumer": "demo-consumer", "path": cpath}]

    lines.append(_manifest_line("pwsh.helper.foo", "powershell-helper",
                                "reference-code/powershell/Public/Foo.ps1",
                                consumers))
    if whole_tool:
        lines.append(_manifest_line(
            "tool.scanner", "tool",
            "quality-tools/canonical-drift-scanner/scanner.py", []))

    with open(os.path.join(state, "manifest.jsonl"), "w", newline="\n") as h:
        h.write("\n".join(lines) + "\n")
    return root


def rows_for(**kw):
    root = build_root(**kw)
    try:
        return list(scan(root, "testrepo", "deadbeef"))
    finally:
        shutil.rmtree(root)


def run():
    cases = []
    schema = json.load(open(os.path.join(
        REPO_ROOT, "governance", "schema", "observation.schema.json")))
    from jsonschema import Draft7Validator
    Draft7Validator.check_schema(schema)
    validator = Draft7Validator(schema)

    def all_conform(rows):
        for r in rows:
            errs = list(validator.iter_errors(r))
            if errs:
                return False, errs
            if _canonical_line(r) != _canonical_line(json.loads(_canonical_line(r))):
                return False, "non-canonical"
        return True, None

    # region/match: consumer body identical to canon.
    rows = rows_for(consumer_body="function Foo {\r\n    param($X)\r\n    $X\r\n}")
    region = [r for r in rows if r["granularity"] == "region"]
    ok, _ = all_conform(rows)
    cases.append(("region match -> drift=match",
                  len(region) == 1 and region[0]["drift"] == "match" and ok))

    # region/drift: consumer body changed.
    rows = rows_for(consumer_body="function Foo {\r\n    param($X)\r\n    $X + 1\r\n}")
    region = [r for r in rows if r["granularity"] == "region"]
    ok, _ = all_conform(rows)
    cases.append(("region changed -> drift=drift",
                  len(region) == 1 and region[0]["drift"] == "drift" and ok))

    # region/forked-frozen: policy=forked -> not compared.
    rows = rows_for(consumer_body="function Foo {\r\n    $totally = 'different'\r\n}",
                    consumer_policy="forked")
    region = [r for r in rows if r["granularity"] == "region"]
    ok, _ = all_conform(rows)
    cases.append(("forked -> drift=forked-frozen",
                  len(region) == 1 and region[0]["drift"] == "forked-frozen" and ok))

    # whole-tool: null convention, drift n/a.
    rows = rows_for(consumer_body=None)
    wt = [r for r in rows if r["granularity"] == "whole-tool"]
    ok, _ = all_conform(rows)
    nulls_ok = wt and all(
        wt[0][f] is None for f in ("region_locator", "canonical_version",
                                   "canonical_hash_norm", "observed_hash_norm",
                                   "observed_hash_raw", "hash_what"))
    cases.append(("whole-tool -> null fields + drift=n/a",
                  bool(wt) and wt[0]["drift"] == "n/a" and nulls_ok and ok))

    # F1: every record stamps runtime.duckdb == "n/a".
    rows = rows_for(consumer_body="function Foo {\r\n    param($X)\r\n    $X\r\n}")
    cases.append(("F1 runtime.duckdb == 'n/a' on every record",
                  all(r["runtime"]["duckdb"] == "n/a" for r in rows)))

    # F4: malformed marker -> drift=unknown (no crash, in-enum, schema-valid).
    rows = rows_for(consumer_body="function Foo { $X }", malformed=True)
    region = [r for r in rows if r["granularity"] == "region"]
    ok, _ = all_conform(rows)
    cases.append(("F4 malformed marker -> drift=unknown (conformant)",
                  len(region) == 1 and region[0]["drift"] == "unknown" and ok))

    # region_locator final form (P6): a real consumer inlines MANY regions in one
    # file; extract_region selects the region by unit_id (not "one pair per file").
    _mk = ("# >>> CANONICAL unit_id=%s version=1.0.0 hash=%s policy=canonical "
           "binding=follow-latest >>>\r\n%s\r\n# <<< CANONICAL unit_id=%s <<<")
    _foo = ("pwsh.helper.foo", "0" * 16, "function Foo {\r\n    $A\r\n}", "pwsh.helper.foo")
    _bar = ("pwsh.helper.bar", "1" * 16, "function Bar {\r\n    $B\r\n}", "pwsh.helper.bar")
    multi = (_mk % _foo) + "\r\n\r\n" + (_mk % _bar)
    bfoo, _mf, lfoo = extract_region(multi, "pwsh.helper.foo")
    bbar, _mb, lbar = extract_region(multi, "pwsh.helper.bar")
    cases.append(("region_locator: multi-region selects foo by unit_id (symbol-anchored)",
                  bfoo == "function Foo {\n    $A\n}" and lfoo == "marker:pwsh.helper.foo@fn:Foo"))
    cases.append(("region_locator: multi-region selects bar by unit_id",
                  bbar == "function Bar {\n    $B\n}" and lbar == "marker:pwsh.helper.bar@fn:Bar"))
    # F4 enumerated indeterminate conditions: duplicate unit_id, and absent unit_id.
    dup = (_mk % _foo) + "\r\n" + (_mk % _foo)
    cases.append(("F4 duplicate unit_id marker in one file -> indeterminate",
                  extract_region(dup, "pwsh.helper.foo") == (None, None, None)))
    cases.append(("F4 absent unit_id -> indeterminate",
                  extract_region(multi, "pwsh.helper.nope") == (None, None, None)))

    # Schema conformance + canonical-JSON across a mixed run.
    rows = rows_for(consumer_body="function Foo {\r\n    param($X)\r\n    $X\r\n}")
    ok, detail = all_conform(rows)
    cases.append(("emitted rows are schema-valid + canonical-JSON (#3 gate)", ok))

    # Golden vectors.
    for name, body, expected in GOLDEN_VECTORS:
        cases.append(("golden vector %s" % name, canon_norm_hash(body) == expected))

    passed = 0
    for name, ok in cases:
        print("[%s] %s" % ("PASS" if ok else "FAIL", name))
        passed += int(ok)
    print("\n%d/%d checks passed" % (passed, len(cases)))
    return 0 if passed == len(cases) else 1


if __name__ == "__main__":
    sys.exit(run())
