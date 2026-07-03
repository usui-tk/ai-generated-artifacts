#!/usr/bin/env python3
"""Self-test for the reconciliation cold loop (coldloop.py). Fixture trees per
case; requires duckdb (the cold path's sole extra dependency, ADR 0028)."""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import coldloop as C  # noqa: E402

TRIGGER_SRC = os.path.join(HERE, "..", "canon-drift-trigger", "trigger.py")


def build_root():
    """Fixture: manifest (one doc-region unit, 2 consumers with markers so the
    trigger's impact measurement works) + the real trigger copied in + one
    observation file containing 1 drift + 2 non-drift rows."""
    root = tempfile.mkdtemp(prefix="coldloop_")
    os.makedirs(os.path.join(root, "governance", "state"))
    os.makedirs(os.path.join(root, "governance", "spec"))
    os.makedirs(os.path.join(root, "quality-tools", "canon-drift-trigger"))
    shutil.copy(TRIGGER_SRC,
                os.path.join(root, "quality-tools", "canon-drift-trigger",
                             "trigger.py"))
    mark = ("<!-- >>> CANONICAL unit_id=spec.demo.part-a.x version=1.0.0 "
            "hash=0123456789abcdef policy=canonical binding=follow-latest >>> -->\n"
            "body\n<!-- <<< CANONICAL unit_id=spec.demo.part-a.x <<< -->\n")
    with open(os.path.join(root, "governance", "spec", "d.md"), "w",
              newline="\n") as fh:
        fh.write(mark)
    for proj in ("pa", "pb"):
        os.makedirs(os.path.join(root, "projects", proj))
        with open(os.path.join(root, "projects", proj, "SPEC.md"), "w",
                  newline="\n") as fh:
            fh.write(mark)
    rows = [{"unit_id": "spec.demo.part-a", "kind": "spec-region",
             "canonical_location": "governance/spec/d.md",
             "canonical_version": "1.0.0",
             "consumers": [{"consumer": "pa", "path": "projects/pa/SPEC.md"},
                           {"consumer": "pb", "path": "projects/pb/SPEC.md"}]}]
    with open(os.path.join(root, "governance", "state", "manifest.jsonl"),
              "w", newline="\n") as fh:
        for rec in rows:
            fh.write(C._canonical_line(rec) + "\n")
    write_observations(root, observed="feedfeedfeedfeed")
    return root


def obs_row(root, drift, observed, unit="spec.demo.part-a", consumer="pa",
            reason=None):
    row = {"schema_version": "1", "run_id": "run-t", "commit": "deadbee",
            "observed_at": "20260703T000000Z", "repo": "fixture",
            "unit_id": unit, "granularity": "region", "kind": "spec-region",
            "consumer": consumer, "path": "projects/%s/SPEC.md" % consumer,
            "region_locator": "%s.x" % unit, "change_policy": "canonical",
            "binding_mode": "follow-latest", "canonical_version": "1.0.0",
            "canonical_hash_norm": "0123456789abcdef",
            "observed_hash_norm": observed, "observed_hash_raw": observed,
            "hash_what": "region-body", "drift": drift}
    if reason is not None:
        row["reason_class"] = reason
    return row


def write_observations(root, observed):
    obs_dir = os.path.join(root, "governance", "state", "observations",
                           "repo=fixture", "date=2026-07-03")
    os.makedirs(obs_dir, exist_ok=True)
    with open(os.path.join(obs_dir, "run-t.jsonl"), "w", newline="\n") as fh:
        fh.write(C._canonical_line(obs_row(root, "drift", observed)) + "\n")
        fh.write(C._canonical_line(obs_row(root, "match", "0123456789abcdef",
                                           consumer="pb")) + "\n")
        fh.write(C._canonical_line(
            obs_row(root, "n-a", "0123456789abcdef", unit="tool.x")) + "\n")
        # NOTE: no row carries reason_class -> the inferred schema has NO such
        # column (the real scanner omits null fields; first-real-run lesson)


GLOB = os.path.join("governance", "state", "observations", "repo=*",
                    "date=*", "*.jsonl")
_checks = []


def check(name, ok):
    _checks.append((name, ok))
    print("[%s] %s" % ("PASS" if ok else "FAIL", name))


def run_cli(root, *args):
    return subprocess.run([sys.executable, os.path.join(HERE, "coldloop.py"),
                           "--root", root] + list(args),
                          capture_output=True, text=True)


def read_ledger_bytes(root):
    p = os.path.join(root, C.LEDGER)
    return open(p, "rb").read() if os.path.isfile(p) else b""


# 1) run: appends ONE proposal (drift only), wrapping the PINNED request contract.
root = build_root()
manifest_before = open(os.path.join(root, "governance/state/manifest.jsonl"),
                       "rb").read()
rc = run_cli(root, "run", "--observations", GLOB)
records, proposals, decided = C.load_ledger(root)
prop = list(proposals.values())[0] if proposals else None
check("run appends exactly 1 proposal (drift only)",
      rc.returncode == 0 and len(proposals) == 1 and not decided)
check("proposal wraps the pinned request contract (1.0.0, pending-decision)",
      prop is not None
      and prop["request"]["request_version"] == "1.0.0"
      and prop["request"]["decision"]["status"] == "pending-decision"
      and prop["request"]["decision"]["impact"]["consumer_count"] == 2)

# 2) reports regenerated with the DuckDB version stamp + correct counts.
rep = json.load(open(os.path.join(root, C.REPORT_JSON), encoding="utf-8"))
check("report.json: duckdb version stamped + totals correct",
      rep["duckdb_version"] and rep["aggregate"]["totals_by_drift"].get("drift") == 1
      and rep["aggregate"]["totals_by_drift"].get("match") == 1
      and rep["proposals_appended_this_run"] == 1)
check("report.md + summary.md regenerated",
      os.path.isfile(os.path.join(root, C.REPORT_MD))
      and "prop-" in open(os.path.join(root, C.SUMMARY_MD), encoding="utf-8").read())

# 3) skip-key dedup: identical re-run appends nothing; ledger bytes = prefix.
before = read_ledger_bytes(root)
rc = run_cli(root, "run", "--observations", GLOB)
after = read_ledger_bytes(root)
check("re-run of unchanged drift appends nothing (skip-key dedup)",
      rc.returncode == 0 and after == before)

# 4) a CHANGED observed hash is a NEW proposal (content-hash key).
write_observations(root, observed="beefbeefbeefbeef")
rc = run_cli(root, "run", "--observations", GLOB)
records, proposals, decided = C.load_ledger(root)
check("changed evidence -> new proposal appended",
      rc.returncode == 0 and len(proposals) == 2)

# 5) decide appends a decision record; prior bytes are a strict prefix
#    (append-only, byte-verified); unknown / double decide refused.
before = read_ledger_bytes(root)
pid = sorted(proposals)[0]
rc = run_cli(root, "decide", "--proposal-id", pid, "--status", "accepted",
             "--auth", "session-2026-07-03")
after = read_ledger_bytes(root)
check("decide appends (prior ledger bytes are a strict prefix)",
      rc.returncode == 0 and after.startswith(before) and len(after) > len(before))
rc2 = run_cli(root, "decide", "--proposal-id", pid, "--status", "rejected",
              "--auth", "x")
rc3 = run_cli(root, "decide", "--proposal-id", "prop-nope", "--status",
              "accepted", "--auth", "x")
check("double-decide and unknown-id are refused",
      rc2.returncode == 1 and "already has a decision" in rc2.stderr
      and rc3.returncode == 1)

# 6) write boundary: manifest/canon untouched; all outputs under reconciliation/.
manifest_after = open(os.path.join(root, "governance/state/manifest.jsonl"),
                      "rb").read()
rec_dir = os.path.join(root, C.REC_DIR)
outputs = set(os.listdir(rec_dir))
check("cold path never touches the manifest (byte-identical)",
      manifest_after == manifest_before)
check("all outputs live under governance/state/reconciliation/",
      outputs == {"proposals.jsonl", "report.json", "report.md", "summary.md"})
shutil.rmtree(root)

# 7) empty observations -> zero report, no ledger created.
root = build_root()
shutil.rmtree(os.path.join(root, "governance", "state", "observations"))
rc = run_cli(root, "run", "--observations", GLOB)
rep = json.load(open(os.path.join(root, C.REPORT_JSON), encoding="utf-8"))
check("empty observations -> zero-report, no proposals file",
      rc.returncode == 0 and rep["aggregate"]["totals_by_drift"] == {}
      and not os.path.isfile(os.path.join(root, C.LEDGER)))
shutil.rmtree(root)

# 8) a corpus WITH reason_class populates the breakdown (fork-flow fields).
root = build_root()
obs_dir = os.path.join(root, "governance", "state", "observations",
                       "repo=fixture", "date=2026-07-03")
with open(os.path.join(obs_dir, "run-u.jsonl"), "w", newline="\n") as fh:
    fh.write(C._canonical_line(obs_row(root, "drift", "cafecafecafecafe",
                                       consumer="pb",
                                       reason="consumer-local-fix")) + "\n")
rc = run_cli(root, "run", "--observations", GLOB)
rep = json.load(open(os.path.join(root, C.REPORT_JSON), encoding="utf-8"))
check("reason_class breakdown populated when the column exists",
      rc.returncode == 0
      and rep["aggregate"]["reason_class_breakdown"] ==
          [{"reason_class": "consumer-local-fix", "count": 1}])
shutil.rmtree(root)

passed = sum(1 for _, ok in _checks if ok)
print("\n%d/%d checks passed" % (passed, len(_checks)))
sys.exit(0 if passed == len(_checks) else 1)
