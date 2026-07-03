#!/usr/bin/env python3
"""reconciliation-loop (cold path) - scheduled drift aggregation + proposals ledger.

The P8 deliverable (ADR 0028). The COLD half of the two-path model:
  * The HOT path (the per-phase/per-PR gate battery) blocks merges, stays
    stdlib-only, and treats scanner run logs as transient (never staged).
  * The COLD path (this tool, driven by the scheduled workflow) OBSERVES,
    AGGREGATES and PROPOSES - and NEVER mutates the canonical. Its only write
    surface is governance/state/reconciliation/ (enforced in code) plus the
    observation master that the scheduled scanner run emits.

What `run` does:
  1. Aggregate the observation JSONL set with DuckDB (the SOLE DuckDB consumer
     in the repository; version stamped into the report) by unit x drift
     status, with a reason_class breakdown where present.
  2. Derive decision-gated change requests by SUBPROCESSING the canon-drift
     trigger (single-sourcing the pinned request contract 1.0.0, ADR 0027 -
     requests arrive with machine-measured impact + status pending-decision).
  3. Append NEW proposals to the append-only ledger proposals.jsonl. The
     skip-key is a content hash over the drift identity+evidence, so a
     re-observed unchanged drift is NOT re-proposed (P8.3).
  4. Regenerate the derived report (report.json canonical-JSON + report.md)
     and the ledger view summary.md - regenerated artifacts, never hand-edited.

What `decide` does (the human act, P8.3/P8.4):
  Appends a DECISION RECORD referencing a proposal_id (accepted / rejected).
  Proposals are never edited in place - append-only is byte-verifiable. An
  ACCEPTED proposal then follows the normal human-gated mutation flow
  (promote / restamp + full battery); this tool has NO write path into the
  canon, the manifest, or any marker file.

Single-file; stdlib + duckdb (cold-path-only dependency, ADR 0010/0028).
"""

import argparse
import glob
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

COLDLOOP_VERSION = "1.0.0"

REC_DIR = os.path.join("governance", "state", "reconciliation")
LEDGER = os.path.join(REC_DIR, "proposals.jsonl")
REPORT_JSON = os.path.join(REC_DIR, "report.json")
REPORT_MD = os.path.join(REC_DIR, "report.md")
SUMMARY_MD = os.path.join(REC_DIR, "summary.md")

# skip-key identity+evidence fields (P8.3: content hash - unchanged re-observed
# drift is not re-proposed; a CHANGED observed hash is a new proposal).
_SKIP_FIELDS = ("unit_id", "consumer", "region_locator",
                "canonical_hash_norm", "observed_hash_norm")


def _canonical_line(record):
    """Reuse-by-copy of the suite's canonical-JSON emitter (ADR 0003)."""
    return json.dumps(record, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False)


def _utc_now():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _out_path(root, rel):
    """Every write goes below governance/state/reconciliation/ - enforced."""
    assert rel.startswith(REC_DIR), "write outside the cold-path surface: %s" % rel
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def load_ledger(root):
    """(records, proposal_index, decided_ids): the append-only ledger state."""
    records = []
    path = os.path.join(root, LEDGER)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line:
                    records.append(json.loads(line))
    proposals = {r["proposal_id"]: r for r in records
                 if r.get("record_type") == "proposal"}
    decided = {r["proposal_id"] for r in records
               if r.get("record_type") == "decision"}
    return records, proposals, decided


def skip_key(request):
    basis = {k: request.get(k) for k in _SKIP_FIELDS}
    return hashlib.sha256(_canonical_line(basis).encode("utf-8")).hexdigest()[:16]


def derive_requests(root, observations_glob):
    """Subprocess the canon-drift trigger (single source of the pinned request
    contract). Returns a list of request dicts (drift-actionable only)."""
    trigger = os.path.join(root, "quality-tools", "canon-drift-trigger",
                           "trigger.py")
    if not os.path.isfile(trigger):
        raise RuntimeError("trigger not found at %s - refusing (fail-safe; the "
                           "request contract is owned there)" % trigger)
    proc = subprocess.run(
        [sys.executable, trigger, "--observations", observations_glob,
         "--root", root],
        capture_output=True, text=True, cwd=root)
    if proc.returncode != 0:
        raise RuntimeError("trigger failed: %s" % proc.stderr.strip())
    return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]


def aggregate(files):
    """DuckDB aggregation (the sole DuckDB consumer): totals by drift status,
    unit x status rows, reason_class breakdown. Returns (aggregate_dict,
    duckdb_version)."""
    import duckdb  # cold-path-only dependency (ADR 0010/0028)
    con = duckdb.connect()  # in-memory; disposable by construction (*.duckdb is
                            # gitignored for any on-disk variant)
    filelist = "[" + ",".join("'%s'" % f.replace("'", "''") for f in files) + "]"
    src = "read_json_auto(%s, format='newline_delimited')" % filelist
    totals = {row[0]: row[1] for row in con.execute(
        "SELECT drift, count(*) FROM %s GROUP BY drift ORDER BY drift" % src
    ).fetchall()}
    by_unit = [{"unit_id": r[0], "drift": r[1], "count": r[2]}
               for r in con.execute(
        "SELECT unit_id, drift, count(*) FROM %s GROUP BY unit_id, drift "
        "ORDER BY unit_id, drift" % src).fetchall()]
    # The scanner omits null fields entirely (canonical absent-if-null), so a
    # drift-free corpus may have NO reason_class column at all - probe the
    # inferred schema before querying it (found on the first real-tree run).
    cols = {r[0] for r in con.execute("DESCRIBE SELECT * FROM %s" % src).fetchall()}
    reason = ([{"reason_class": r[0], "count": r[1]} for r in con.execute(
        "SELECT reason_class, count(*) FROM %s WHERE reason_class IS NOT NULL "
        "GROUP BY reason_class ORDER BY reason_class" % src).fetchall()]
        if "reason_class" in cols else [])
    return ({"totals_by_drift": totals, "by_unit": by_unit,
             "reason_class_breakdown": reason},
            duckdb.__version__)


def _write_reports(root, agg, duckdb_version, files, appended, ledger_state):
    records, proposals, decided = ledger_state
    open_props = [p for pid, p in sorted(proposals.items()) if pid not in decided]
    report = {
        "coldloop_version": COLDLOOP_VERSION,
        "duckdb_version": duckdb_version,
        "generated_at": _utc_now(),
        "observation_files": [os.path.relpath(f, root).replace(os.sep, "/")
                              for f in files],
        "aggregate": agg,
        "proposals_appended_this_run": appended,
        "proposals_open": len(open_props),
        "proposals_decided": len(decided),
    }
    with open(_out_path(root, REPORT_JSON), "w", encoding="utf-8",
              newline="\n") as fh:
        fh.write(_canonical_line(report) + "\n")

    md = ["# Reconciliation report (regenerated - do not hand-edit)", "",
          "- coldloop %s / DuckDB %s / generated %s (UTC)"
          % (COLDLOOP_VERSION, duckdb_version, report["generated_at"]),
          "- observation files: %d / proposals appended this run: %d / open: %d"
          % (len(files), appended, len(open_props)), "",
          "## Totals by drift status", ""]
    md += ["- `%s`: %d" % (k, v) for k, v in sorted(agg["totals_by_drift"].items())] or ["- (no observations)"]
    md += ["", "## Drift rows (unit x status, drift only)", ""]
    drift_rows = [r for r in agg["by_unit"] if r["drift"] == "drift"]
    if drift_rows:
        md += ["| unit_id | count |", "|:--|--:|"]
        md += ["| `%s` | %d |" % (r["unit_id"], r["count"]) for r in drift_rows]
    else:
        md += ["(no drift - consumers in sync)"]
    if agg["reason_class_breakdown"]:
        md += ["", "## reason_class breakdown", ""]
        md += ["- `%s`: %d" % (r["reason_class"], r["count"])
               for r in agg["reason_class_breakdown"]]
    with open(_out_path(root, REPORT_MD), "w", encoding="utf-8",
              newline="\n") as fh:
        fh.write("\n".join(md) + "\n")
    _write_summary_only(root, ledger_state)


def op_run(args):
    root = args.root
    files = sorted(glob.glob(os.path.join(root, args.observations))
                   if not os.path.isabs(args.observations)
                   else glob.glob(args.observations))
    agg, duck_ver = (aggregate(files) if files else
                     ({"totals_by_drift": {}, "by_unit": [],
                       "reason_class_breakdown": []}, None))
    if duck_ver is None:
        import duckdb
        duck_ver = duckdb.__version__

    appended = 0
    if files:
        requests = derive_requests(root, args.observations)
        _, proposals, _ = load_ledger(root)
        known = {p["skip_key"] for p in proposals.values()}
        new_lines = []
        for req in requests:
            key = skip_key(req)
            if key in known:
                continue
            known.add(key)
            new_lines.append(_canonical_line({
                "record_type": "proposal",
                "proposal_id": "prop-%s-%s" % (_utc_now(), key),
                "skip_key": key,
                "first_seen": _utc_now(),
                "request": req,
            }))
        if new_lines:
            with open(_out_path(root, LEDGER), "a", encoding="utf-8",
                      newline="\n") as fh:
                for line in new_lines:
                    fh.write(line + "\n")
            appended = len(new_lines)

    ledger_state = load_ledger(root)
    _write_reports(root, agg, duck_ver, files, appended, ledger_state)
    print("coldloop run: %d observation file(s); %d proposal(s) appended; "
          "%d open / %d decided; reports regenerated (cold path - nothing "
          "canonical touched)."
          % (len(files), appended,
             len([1 for pid in ledger_state[1] if pid not in ledger_state[2]]),
             len(ledger_state[2])))
    return 0


def op_decide(args):
    root = args.root
    records, proposals, decided = load_ledger(root)
    pid = args.proposal_id
    if pid not in proposals:
        sys.stderr.write("decide: REFUSED - unknown proposal_id %r\n" % pid)
        return 1
    if pid in decided:
        sys.stderr.write("decide: REFUSED - %s already has a decision record "
                         "(append-only ledger: decisions are never edited)\n" % pid)
        return 1
    record = {"record_type": "decision", "proposal_id": pid,
              "status": args.status, "auth_ref": args.auth,
              "decided_at": _utc_now()}
    if args.note:
        record["note"] = args.note
    with open(_out_path(root, LEDGER), "a", encoding="utf-8", newline="\n") as fh:
        fh.write(_canonical_line(record) + "\n")
    ledger_state = load_ledger(root)
    # regenerate ONLY the ledger view (the scan report belongs to `run`)
    _write_summary_only(root, ledger_state)
    print("decision appended: %s -> %s (the mutation itself, if accepted, "
          "follows the normal human-gated flow)" % (pid, args.status))
    return 0


def _write_summary_only(root, ledger_state):
    """Regenerate the ledger view summary.md (shared by run + decide)."""
    records, proposals, decided = ledger_state
    open_props = [p for pid, p in sorted(proposals.items()) if pid not in decided]
    smd = ["# Proposals ledger - open items (regenerated view)", "",
           "- open: %d / decided: %d / ledger records: %d"
           % (len(open_props), len(decided), len(records)), ""]
    if open_props:
        smd += ["| proposal_id | unit_id | first_seen | tier/status |", "|:--|:--|:--|:--|"]
        for p in open_props:
            req = p.get("request", {})
            dec = req.get("decision") or {}
            smd += ["| `%s` | `%s` | %s | %s |"
                    % (p["proposal_id"], req.get("unit_id"), p.get("first_seen"),
                       dec.get("tier") or dec.get("status"))]
    else:
        smd += ["(no open proposals)"]
    smd += ["", "Decide with: `python3 quality-tools/reconciliation-loop/"
            "coldloop.py decide --proposal-id <id> --status accepted|rejected "
            "--auth <ref>` - decisions are APPENDED records; an accepted "
            "proposal then follows the normal human-gated mutation flow "
            "(promote / restamp + the full battery)."]
    with open(_out_path(root, SUMMARY_MD), "w", encoding="utf-8",
              newline="\n") as fh:
        fh.write("\n".join(smd) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Reconciliation cold loop (P8, ADR 0028): aggregate + "
                    "propose; humans decide; never mutates the canonical.")
    ap.add_argument("--root", default=".")
    ap.add_argument("--version", action="version",
                    version="reconciliation-loop %s" % COLDLOOP_VERSION)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_run = sub.add_parser("run", help="aggregate observations (DuckDB) + append "
                           "new proposals + regenerate reports")
    p_run.add_argument("--observations", required=True,
                       help="glob (relative to --root) of observation JSONL files")
    p_run.set_defaults(func=op_run)

    p_dec = sub.add_parser("decide", help="append a human decision record for a "
                           "proposal (append-only; P8.3/P8.4)")
    p_dec.add_argument("--proposal-id", required=True)
    p_dec.add_argument("--status", required=True, choices=("accepted", "rejected"))
    p_dec.add_argument("--auth", required=True,
                       help="in-session [AUTH] / approval reference")
    p_dec.add_argument("--note", default=None)
    p_dec.set_defaults(func=op_decide)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
