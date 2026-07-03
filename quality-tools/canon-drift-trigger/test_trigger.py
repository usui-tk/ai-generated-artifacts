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

# 6. drift payloads carry no top-level kind/impact placeholders (P7a: the
#    decision block owns them; without a root there is no decision block)
check("kind" not in fr and "impact" not in fr and "decision" not in fr,
      "6: no stale placeholders; decision block only with a root")

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
check("decision-gate" in r["proposed_route"] and
      ("promote" in r["proposed_route"] or "coupled write" in r["proposed_route"]),
      "8: proposed_route = decision gate -> gates -> coupled write path")

# 9. contract markers reflect the P7a resolution (pinned by its owner)
check(r["contract_status"] == "pinned-P7a"
      and r["consumer_status"] == "decision-gate(P7a)"
      and r["request_version"] == "1.0.0",
      "9: contract pinned at P7a (request_version 1.0.0)")

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

# ---- P7a: impact measurement + the decision gate (ADR 0011 3-AI/4; ADR 0027) ----
import os, shutil, tempfile

def build_impact_root():
    """Minimal repo fixture: one doc-region unit (home + 2 consumers) and one
    code unit (home + 1 consumer) with countable markers."""
    root = tempfile.mkdtemp(prefix="trigger_impact_")
    os.makedirs(os.path.join(root, "governance", "state"))
    os.makedirs(os.path.join(root, "governance", "spec"))
    os.makedirs(os.path.join(root, "projects", "pa"))
    os.makedirs(os.path.join(root, "projects", "pb"))
    doc_mark = ("<!-- >>> CANONICAL unit_id=spec.bash.part-a.x version=1.0.0 "
                "hash=0123456789abcdef policy=canonical binding=follow-latest >>> -->\n"
                "body\n<!-- <<< CANONICAL unit_id=spec.bash.part-a.x <<< -->\n")
    code_mark = ("# >>> CANONICAL unit_id=ps.helper.get-x version=1.0.0 "
                 "hash=0123456789abcdef policy=canonical binding=follow-latest >>>\n"
                 "# body\n")
    with open(os.path.join(root, "governance", "spec", "d.md"), "w") as fh:
        fh.write(doc_mark * 2)   # 2 regions at home
    for proj in ("pa", "pb"):
        with open(os.path.join(root, "projects", proj, "SPEC.md"), "w") as fh:
            fh.write(doc_mark * 2)
    with open(os.path.join(root, "projects", "pa", "s.ps1"), "w") as fh:
        fh.write(code_mark)
    rows = [
        {"unit_id": "spec.demo.part-a", "kind": "spec-region",
         "canonical_location": "governance/spec/d.md", "canonical_version": "1.0.0",
         "consumers": [{"consumer": "pa", "path": "projects/pa/SPEC.md"},
                       {"consumer": "pb", "path": "projects/pb/SPEC.md"}]},
        {"unit_id": "ps.helper.get-x", "kind": "powershell-helper",
         "canonical_location": "projects/pa/s.ps1", "canonical_version": "1.0.0",
         "consumers": [{"consumer": "pa", "path": "projects/pa/s.ps1"}]},
    ]
    # the doc unit's markers use the unit prefix spec.bash.part-a.x on purpose?
    # No - align the fixture: rewrite home/consumers with the registered prefix.
    doc_mark2 = doc_mark.replace("spec.bash.part-a.x", "spec.demo.part-a.x")
    with open(os.path.join(root, "governance", "spec", "d.md"), "w") as fh:
        fh.write(doc_mark2 * 2)
    for proj in ("pa", "pb"):
        with open(os.path.join(root, "projects", proj, "SPEC.md"), "w") as fh:
            fh.write(doc_mark2 * 2)
    with open(os.path.join(root, "governance", "state", "manifest.jsonl"), "w") as fh:
        for rec in rows:
            fh.write(T._canonical_line(rec) + "\n")
    return root

root = build_impact_root()

# 12. impact: doc unit -> 2 consumers, home+consumer placements, marker totals
imp = T.measure_impact(root, "spec.demo.part-a")
check(imp["consumer_count"] == 2 and imp["consumers"] == ["pa", "pb"]
      and imp["total_markers"] == 6
      and [p["role"] for p in imp["placements"]] == ["home", "consumer", "consumer"],
      "12: impact machine-measured from consumers[] + marker placements")

# 13. impact: code-frame markers are counted too; unknown unit raises
imp2 = T.measure_impact(root, "ps.helper.get-x")
check(imp2["total_markers"] >= 1, "13a: code-frame placements counted")
try:
    T.measure_impact(root, "no.such.unit")
    check(False, "13b: unknown unit raises")
except KeyError:
    check(True, "13b: unknown unit raises")

# 14. decision tiers: kind -> SemVer -> tier (ADR 0011 4, confirmed P7a.1)
d, e = T.build_decision("bug-fix", imp)
check(e is None and d["semver_level"] == "patch" and d["tier"] == "trivial",
      "14a: bug-fix -> patch -> trivial")
d, e = T.build_decision("enhancement", imp)
check(e is None and d["tier"] == "medium", "14b: enhancement -> minor -> medium")

# 15. heavy tier REFUSED without migration+ADR; accepted with both (+ consumers)
d, e = T.build_decision("breaking", imp)
check(d is None and "REFUSED" in e and "--migration" in e and "--adr" in e,
      "15a: breaking without migration/ADR refused")
d, e = T.build_decision("breaking", imp, migration="steps...", adr="0099")
check(e is None and d["tier"] == "heavy" and d["impact"]["consumers"] == ["pa", "pb"]
      and d["migration"] == "steps..." and d["adr"] == "0099",
      "15b: heavy path carries enumerated consumers + migration + ADR")

# 16. propose: emits ONE decision-gated reconcile-back request; bad kind refused
req, e = T.build_proposal(root, "spec.demo.part-a", "bug-fix", "fix wording",
                          auth="session-2026-07-03")
check(e is None and req["request_kind"] == "reconcile-back"
      and req["decision"]["status"] == "decided"
      and req["decision"]["tier"] == "trivial"
      and req["request_version"] == "1.0.0"
      and req["decision"]["auth_ref"] == "session-2026-07-03",
      "16a: propose emits a decided reconcile-back request")
req, e = T.build_proposal(root, "spec.demo.part-a", "weird-kind", "x")
check(req is None and "unknown change kind" in e, "16b: unknown kind refused")

# 17. machine drift requests with a root carry computed impact, kind pending
obs = region_obs(unit_id="spec.demo.part-a", consumer="pa")
mr = T.build_requests([obs], root=root)[0]
check(mr["decision"]["status"] == "pending-decision"
      and mr["decision"]["kind"] is None
      and mr["decision"]["impact"]["consumer_count"] == 2,
      "17: drift request = computed impact + kind pending human decision")

shutil.rmtree(root)

print("\n%d/%d checks passed" % (_checks - _fail, _checks))
sys.exit(1 if _fail else 0)
