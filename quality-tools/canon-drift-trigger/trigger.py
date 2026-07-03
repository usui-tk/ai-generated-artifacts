#!/usr/bin/env python3
"""canon-drift-trigger - the machine change trigger (ADR 0011 principle 3-machine).

Reads the canonical-drift scanner's observation records and, for every observation
that records a real region body drift, emits a *structured change request* on stdout.
This is the machine entry point of the single change-management process (ADR 0011 3):
"for the machine trigger (scanner) it auto-files the change request".

SCOPE (P7a: ADR 0011 3-AI + 4 are now IMPLEMENTED here - ADR 0027):
  * THREE TRIGGERS, ONE PROCESS (ADR 0011 3). Machine: drift observations ->
    change requests (the original path). Human/AI (reconcile-back, ADR 0007 3):
    the `propose` subcommand turns a consumer-side finding into a structured
    change request - the judgement is human/AI, the recording is the tool.
  * DECISION GATE (ADR 0011 4), in series BEFORE the quality gate. Every request
    carries a `decision` block: kind -> SemVer level -> tier, plus the
    MACHINE-MEASURED impact (consumer blast radius from the manifest's
    consumers[] + marker placements - computable since P6/P7 vendoring; the
    `impact` subcommand exposes the same measurement standalone). Tier rules
    (ADR 0011 4, confirmed at P7a.1 against the realized topology):
      patch (bug-fix)            -> trivial decision
      minor (enhancement/feature)-> medium decision
      major (breaking)           -> heavy decision: REFUSED unless the request
        enumerates affected consumers (auto-computed), a migration plan
        (--migration) and a full ADR reference (--adr).
    The approval ACT is the existing [AUTH] + the Git commit (no duplicate
    sign-off, ADR 0011 4/AUTH); machine drift requests carry a computed impact
    with kind=null -> decision.status="pending-decision" until a human
    classifies kind.
  * EMIT-ONLY / NO NEW STORE (unchanged; ADR 0011 5). Output goes to stdout;
    nothing is written under governance/state/. The append-only proposals
    ledger is the P8 cold-loop deliverable, not this tool's.
  * CONTRACT PINNED (this was the named P7a deferral). The change-request shape
    is now owned and pinned by its consumer, the decision gate: request_version
    1.0.0, contract_status "pinned-P7a".

Drift payloads are derived only from the observation's drift/identity fields.
DEP-3 fork fields (forwarded / applied_upstream / change_reason / reason_class)
belong to the fork flow and are NOT consumed here. region_locator is passed
through opaquely.

Single-file, stdlib-only (ADR 0003 standalone-tool principle; shared *logic* - the
canonical-JSON emitter - is reuse-by-copy, not an import).
"""

import argparse
import glob
import json
import sys

TRIGGER_VERSION = "1.1.0"

# Pinned at P7a by the contract owner (the decision gate) - ADR 0027.
REQUEST_VERSION = "1.0.0"

# Routing constants (ADR 0011 3/4: decision gate -> quality gate -> CRUD).
CLASSIFICATION = "marker-coupled"
PROPOSED_ROUTE = "decision-gate -> quality gates -> coupled write (promote) / restamp"

# Contract markers (the P3a deferral is RESOLVED; keep the resolution visible).
CONTRACT_STATUS = "pinned-P7a"
CONSUMER_STATUS = "decision-gate(P7a)"

# ADR 0011 4: change kind -> SemVer level -> decision tier (confirmed P7a.1).
KIND_TO_SEMVER = {"bug-fix": "patch", "enhancement": "minor",
                  "feature": "minor", "breaking": "major"}
SEMVER_TO_TIER = {"patch": "trivial", "minor": "medium", "major": "heavy"}

# Marker frames: reuse-by-copy (ADR 0003) of the validator's code frame and
# doc_gate's doc frame - placement counting only (no hash/version semantics here).
import re
_CODE_MARK = re.compile(r"# >>> CANONICAL unit_id=(\S+) version=\S+ hash=\S+ "
                        r"policy=\S+ binding=\S+ >>>")
_DOC_MARK = re.compile(r"<!--\s*>>>\s*CANONICAL\s+unit_id=(\S+)\s+version=\S+"
                       r"\s+hash=\S+\s+policy=\S+\s+binding=\S+\s*>>>\s*-->")


def _canonical_line(record):
    """Canonical-JSON line: key-sorted, compact separators, ensure_ascii=False.
    Reuse-by-copy of the scanner/validator _canonical_line (check F contract)."""
    return json.dumps(record, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False)


def _iter_observations(paths):
    """Yield observation records (dicts) from one or more JSONL files."""
    for p in paths:
        with open(p, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                yield json.loads(line)


def is_actionable(obs):
    """A drift observation is actionable iff it records a real region body drift.
    Only granularity=region + drift=drift qualifies; match / n-a / unknown /
    forked-frozen / whole-tool produce no request."""
    return obs.get("granularity") == "region" and obs.get("drift") == "drift"


def to_change_request(obs):
    """Derive a thin, provisional change-request payload from a drift observation.

    Derived ONLY from drift/identity fields. DEP-3 fork fields are intentionally not
    read. region_locator is copied through opaquely. kind/impact are left null
    (human-assessed per ADR 0011 4 impact-measurement-maturity clause; not computed -
    consumer blast radius needs registered consumers, P6/P7)."""
    return {
        "request_version": REQUEST_VERSION,
        "request_kind": "canon-drift",
        # provenance
        "source_run_id": obs.get("run_id"),
        "source_commit": obs.get("commit"),
        "observed_at": obs.get("observed_at"),
        "repo": obs.get("repo"),
        # identity
        "unit_id": obs.get("unit_id"),
        "consumer": obs.get("consumer"),
        "path": obs.get("path"),
        "region_locator": obs.get("region_locator"),   # opaque pass-through
        "change_policy": obs.get("change_policy"),
        "binding_mode": obs.get("binding_mode"),
        "canonical_version": obs.get("canonical_version"),
        # drift evidence
        "canonical_hash_norm": obs.get("canonical_hash_norm"),
        "observed_hash_norm": obs.get("observed_hash_norm"),
        "observed_hash_raw": obs.get("observed_hash_raw"),
        "hash_what": obs.get("hash_what"),
        # routing (deferred path; not applied here)
        "classification": CLASSIFICATION,
        "proposed_route": PROPOSED_ROUTE,
        # decision block is attached by build_requests(root=...) - kind stays
        # human-assessed (ADR 0011 3-machine), impact is machine-measured
        # tracked contract state (resolution visible)
        "contract_status": CONTRACT_STATUS,
        "consumer_status": CONSUMER_STATUS,
    }


# ---- P7a: machine impact measurement + the decision gate (ADR 0011 3-AI/4) ----
def _load_manifest_rows(root):
    import os
    rows = {}
    path = os.path.join(root, "governance", "state", "manifest.jsonl")
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rec = json.loads(line)
                rows[rec["unit_id"]] = rec
    return rows


def _count_unit_markers(root, rel, unit_id):
    """Count BEGIN markers in a file whose unit_id equals unit_id or is a dotted
    child of it (both frames; placement counting only)."""
    import os
    with open(os.path.join(root, rel), encoding="utf-8") as fh:
        text = fh.read()
    n = 0
    for rx in (_CODE_MARK, _DOC_MARK):
        for mid in rx.findall(text):
            if mid == unit_id or mid.startswith(unit_id + "."):
                n += 1
    return n


def measure_impact(root, unit_id):
    """MACHINE-MEASURED consumer blast radius (ADR 0011 4: computed from the
    registered consumers, never estimated). Returns the impact dict embedded in
    decision blocks and printed by the `impact` subcommand."""
    rows = _load_manifest_rows(root)
    if unit_id not in rows:
        raise KeyError("no manifest row for unit_id %r" % unit_id)
    row = rows[unit_id]
    consumers = row.get("consumers") or []
    placements = []
    home = row.get("canonical_location")
    import os
    if home and os.path.isfile(os.path.join(root, home)):
        n = _count_unit_markers(root, home, unit_id)
        if n:
            placements.append({"role": "home", "path": home, "markers": n})
    for c in consumers:
        cp = c.get("path")
        if cp and os.path.isfile(os.path.join(root, cp)):
            placements.append({"role": "consumer", "consumer": c.get("consumer"),
                               "path": cp,
                               "markers": _count_unit_markers(root, cp, unit_id)})
    return {
        "unit_id": unit_id,
        "kind_of_unit": row.get("kind"),
        "canonical_version": row.get("canonical_version"),
        "consumer_count": len(consumers),
        "consumers": sorted({c.get("consumer") for c in consumers if c.get("consumer")}),
        "placements": placements,
        "total_markers": sum(p["markers"] for p in placements),
    }


def build_decision(kind, impact, auth=None, migration=None, adr=None):
    """The decision gate (ADR 0011 4): kind -> SemVer level -> tier; heavy tier
    REFUSED unless affected consumers are enumerated (they are - machine-measured)
    AND a migration plan AND a full-ADR reference are supplied.
    Returns (decision, error): exactly one is None."""
    if kind is None:
        return ({"status": "pending-decision", "kind": None, "semver_level": None,
                 "tier": None, "impact": impact}, None)
    if kind not in KIND_TO_SEMVER:
        return (None, "unknown change kind %r (expected one of: %s)"
                % (kind, ", ".join(sorted(KIND_TO_SEMVER))))
    level = KIND_TO_SEMVER[kind]
    tier = SEMVER_TO_TIER[level]
    decision = {"status": "decided", "kind": kind, "semver_level": level,
                "tier": tier, "impact": impact,
                "approval": "[AUTH] + git commit (ADR 0011 4/5)"}
    if auth:
        decision["auth_ref"] = auth
    if tier == "heavy":
        missing = []
        if not impact.get("consumers"):
            missing.append("affected-consumer enumeration (impact.consumers)")
        if not migration:
            missing.append("--migration <plan>")
        if not adr:
            missing.append("--adr <id> (full-ADR path, ADR 0011 4)")
        if missing:
            return (None, "heavy decision (breaking/major) REFUSED - missing: %s"
                    % "; ".join(missing))
        decision["migration"] = migration
        decision["adr"] = adr
    return (decision, None)


def build_proposal(root, unit_id, kind, summary, auth=None, migration=None,
                   adr=None):
    """The AI/human-driven (reconcile-back) trigger (ADR 0011 3-AI + ADR 0007 3):
    a consumer-side finding -> ONE structured change request with a decided
    decision block. Returns (request, error)."""
    try:
        impact = measure_impact(root, unit_id)
    except (KeyError, OSError) as exc:
        return (None, str(exc))
    if kind is None:
        return (None, "propose requires --kind (the human/AI judgement being "
                "recorded; ADR 0011 3)")
    decision, err = build_decision(kind, impact, auth=auth, migration=migration,
                                   adr=adr)
    if err:
        return (None, err)
    return ({
        "request_version": REQUEST_VERSION,
        "request_kind": "reconcile-back",
        "unit_id": unit_id,
        "summary": summary,
        "classification": CLASSIFICATION,
        "proposed_route": PROPOSED_ROUTE,
        "decision": decision,
        "contract_status": CONTRACT_STATUS,
        "consumer_status": CONSUMER_STATUS,
    }, None)


def build_requests(observations, root=None):
    """Pure transform: observations -> sorted list of change-request payloads.
    One request per actionable (unit_id, consumer, region) drift; stable order.
    With a root, each request's decision block carries the machine-measured
    impact (kind stays null -> status pending-decision, ADR 0011 3-machine/4)."""
    reqs = [to_change_request(o) for o in observations if is_actionable(o)]
    if root is not None:
        for r in reqs:
            try:
                impact = measure_impact(root, r.get("unit_id"))
            except (KeyError, OSError):
                impact = None
            r["decision"], _ = build_decision(None, impact)
    reqs.sort(key=lambda r: (r.get("unit_id") or "", r.get("consumer") or "",
                             r.get("region_locator") or ""))
    return reqs


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Change trigger + decision gate (ADR 0011 3/3-AI/4; ADR 0027): "
                    "drift observations or reconcile-back findings -> structured, "
                    "decision-gated change requests (emit-only).")
    ap.add_argument("--observations",
                    help="Path or glob to scanner observation JSONL file(s) "
                         "(the machine trigger path).")
    ap.add_argument("--root", default=None,
                    help="Repo root; enables machine impact measurement.")
    ap.add_argument("--version", action="version",
                    version="canon-drift-trigger %s" % TRIGGER_VERSION)
    sub = ap.add_subparsers(dest="cmd")

    p_imp = sub.add_parser("impact", help="machine-measured consumer blast radius "
                           "for a unit (ADR 0011 4)")
    p_imp.add_argument("--unit-id", required=True)

    p_pro = sub.add_parser("propose", help="AI/human reconcile-back trigger: emit ONE "
                           "decision-gated change request (ADR 0011 3-AI/4)")
    p_pro.add_argument("--unit-id", required=True)
    p_pro.add_argument("--kind", required=True,
                       choices=sorted(KIND_TO_SEMVER))
    p_pro.add_argument("--summary", required=True)
    p_pro.add_argument("--auth", default=None,
                       help="in-session [AUTH] reference (recorded, not a "
                            "duplicate sign-off)")
    p_pro.add_argument("--migration", default=None,
                       help="migration plan (REQUIRED for the heavy tier)")
    p_pro.add_argument("--adr", default=None,
                       help="full-ADR reference (REQUIRED for the heavy tier)")

    args = ap.parse_args(argv)
    out = sys.stdout

    if args.cmd == "impact":
        root = args.root or "."
        try:
            impact = measure_impact(root, args.unit_id)
        except (KeyError, OSError) as exc:
            sys.stderr.write("impact: %s\n" % exc)
            return 1
        out.write(_canonical_line(impact) + "\n")
        return 0

    if args.cmd == "propose":
        root = args.root or "."
        request, err = build_proposal(root, args.unit_id, args.kind, args.summary,
                                      auth=args.auth, migration=args.migration,
                                      adr=args.adr)
        if err:
            sys.stderr.write("propose: REFUSED - %s\n" % err)
            return 1
        out.write(_canonical_line(request) + "\n")
        sys.stderr.write("emitted 1 decision-gated change request (tier=%s; "
                         "emit-only; no state written)\n"
                         % request["decision"]["tier"])
        return 0

    if not args.observations:
        ap.error("--observations is required for the machine (drift) path, or use "
                 "a subcommand (impact / propose)")

    paths = sorted(glob.glob(args.observations))
    if not paths:
        sys.stderr.write("no observation files matched: %s\n" % args.observations)
        return 1

    requests = build_requests(_iter_observations(paths), root=args.root)
    for r in requests:
        out.write(_canonical_line(r) + "\n")
    sys.stderr.write("emitted %d change-request(s) from %d file(s) "
                     "(emit-only; no state written)\n" % (len(requests), len(paths)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
