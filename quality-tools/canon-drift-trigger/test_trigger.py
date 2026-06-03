#!/usr/bin/env python3
"""Fixture tests for canon-drift-trigger (P3a.2).

Builds synthetic observation records (shaped like the scanner's output, conforming to
observation.schema.json) and exercises the trigger's pure transform plus its emit-only /
no-state / no-CRUD guarantees. Stdlib-only; no network, no real repo needed for the
transform tests.
"""

import io
import json
import os
import subprocess
import sys
import tempfile
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_trigger():
    spec = importlib.util.spec_from_file_location(
        "trigger", os.path.join(HERE, "trigger.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


T = _load_trigger()

_checks = 0
_fail = 0


def check(cond, msg):
    global _checks, _fail
    _checks += 1
    if not cond:
        _fail += 1
        print("  FAIL: %s" % msg)
    else:
        print("  ok:   %s" % msg)


def region_obs(unit_id="ps.helper.foo", consumer="proj-a", drift="drift",
               region_locator="marker:ps.helper.foo@L10-L42", **over):
    """A region observation shaped like the scanner emits."""
    o = {
        "schema_version": "1", "run_id": "run-1", "observed_at": "2026-06-03T00:00:00Z",
        "runtime": {"os": "linux", "python": "3.12.0", "duckdb": "n/a"},
        "repo": "ai-generated-artifacts", "commit": "deadbeef",
        "unit_id": unit_id, "granularity": "region", "kind": "powershell-helper",
        "consumer": consumer, "path": "projects/%s/Foo.ps1" % consumer,
        "change_policy": "canonical", "binding_mode": "follow-latest",
        "region_locator": region_locator, "canonical_version": "1.0.0",
        "canonical_hash_norm": "aaaa1111", "observed_hash_norm": "bbbb2222",
        "observed_hash_raw": "cccc3333", "hash_what": "region-body",
        "drift": drift,
    }
    o.update(over)
    return o


def whole_tool_obs(unit_id="tool.canonical-drift-scanner"):
    return {
        "schema_version": "1", "run_id": "run-1", "observed_at": "2026-06-03T00:00:00Z",
        "runtime": {"os": "linux", "python": "3.12.0", "duckdb": "n/a"},
        "repo": "ai-generated-artifacts", "commit": "deadbeef",
        "unit_id": unit_id, "granularity": "whole-tool", "kind": "tool",
        "consumer": unit_id, "path": "quality-tools/x/x.py",
        "change_policy": "canonical", "binding_mode": "follow-latest",
        "region_locator": None, "canonical_version": None,
        "canonical_hash_norm": None, "observed_hash_norm": None,
        "observed_hash_raw": None, "hash_what": None, "drift": "n/a",
    }


print("test_trigger.py")

# 1. a drift region observation -> exactly one request with derived fields
reqs = T.build_requests([region_obs()])
check(len(reqs) == 1, "1: one drift region observation -> one request")
r = reqs[0]
check(r["unit_id"] == "ps.helper.foo" and r["consumer"] == "proj-a",
      "1: identity fields carried through")
check(r["observed_hash_norm"] == "bbbb2222" and r["canonical_hash_norm"] == "aaaa1111",
      "1: drift-evidence hashes carried through")

# 2. non-drift region drift states -> no request
for d in ("match", "n/a", "unknown", "forked-frozen"):
    check(T.build_requests([region_obs(drift=d)]) == [],
          "2: drift=%s region -> no request" % d)

# 3. whole-tool (drift n/a) -> no request
check(T.build_requests([whole_tool_obs()]) == [], "3: whole-tool -> no request")

# 4. region_locator passed through opaquely (two distinct forms)
for loc in ("marker:ps.helper.foo@L10-L42", "BEGIN@120:END@180"):
    rr = T.build_requests([region_obs(region_locator=loc)])
    check(rr[0]["region_locator"] == loc, "4: region_locator pass-through (%s)" % loc)

# 5. DEP-3 fork fields present on the observation are NOT consumed
obs_with_fork = region_obs(forwarded="pending", applied_upstream="1.2.3",
                           change_reason="some fork reason", reason_class="security")
fr = T.build_requests([obs_with_fork])[0]
forkfields = ("forwarded", "applied_upstream", "change_reason", "reason_class")
check(all(k not in fr for k in forkfields),
      "5: DEP-3 fork fields not reflected in the request")

# 6. kind/impact are null (maturity clause, not computed)
check(fr["kind"] is None and fr["impact"] is None, "6: kind/impact left null")

# 7. determinism + stable sort
many = [region_obs(unit_id="ps.helper.z", consumer="c2"),
        region_obs(unit_id="ps.helper.a", consumer="c2"),
        region_obs(unit_id="ps.helper.a", consumer="c1")]
out1 = "\n".join(T._canonical_line(x) for x in T.build_requests(many))
out2 = "\n".join(T._canonical_line(x) for x in T.build_requests(list(reversed(many))))
check(out1 == out2, "7: deterministic, input-order-independent output")
order = [(x["unit_id"], x["consumer"]) for x in T.build_requests(many)]
check(order == sorted(order), "7: output sorted by (unit_id, consumer)")

# 8. classification + routing = marker-coupled / deferred path (boundary check)
check(r["classification"] == "marker-coupled", "8: classification = marker-coupled")
check("decision-gate(P7a)" in r["proposed_route"] and "coupled write" in r["proposed_route"],
      "8: proposed_route points to the deferred path (no immediate CRUD op)")

# 9. tracked-deferral markers present (keep the deferral detectable)
check(r["contract_status"] == "provisional-unpinned"
      and r["consumer_status"] == "none-until-P7a-decision-gate",
      "9: tracked-deferral markers present")

# 10. canonical-JSON conformance (round-trip + stable key order)
line = T._canonical_line(r)
check(json.loads(line) == r, "10: canonical line round-trips")
check(line == T._canonical_line(json.loads(line)), "10: canonical key order stable")

# 11. emit-only end-to-end: run as a subprocess against a temp observations file;
#     assert it writes ONLY stdout and creates no sibling files.
with tempfile.TemporaryDirectory() as td:
    obs_path = os.path.join(td, "run.jsonl")
    with open(obs_path, "w", encoding="utf-8") as fh:
        fh.write(T._canonical_line(region_obs()) + "\n")
        fh.write(T._canonical_line(region_obs(drift="match")) + "\n")
        fh.write(T._canonical_line(whole_tool_obs()) + "\n")
    before = set(os.listdir(td))
    proc = subprocess.run(
        [sys.executable, os.path.join(HERE, "trigger.py"), "--observations", obs_path],
        capture_output=True, text=True)
    after = set(os.listdir(td))
    check(proc.returncode == 0, "11: CLI exit 0")
    emitted = [l for l in proc.stdout.splitlines() if l.strip()]
    check(len(emitted) == 1, "11: only the one drift row produced a request")
    check(after == before, "11: emit-only - no files created beside the input")

# 12. multiple consumers drifting the same unit -> one request per consumer
multi = [region_obs(unit_id="ps.helper.shared", consumer="proj-a"),
         region_obs(unit_id="ps.helper.shared", consumer="proj-b")]
mr = T.build_requests(multi)
check(len(mr) == 2 and {x["consumer"] for x in mr} == {"proj-a", "proj-b"},
      "12: one request per (unit, consumer) drift")

print("\n%d/%d checks passed" % (_checks - _fail, _checks))
sys.exit(1 if _fail else 0)
