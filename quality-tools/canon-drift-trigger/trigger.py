#!/usr/bin/env python3
"""canon-drift-trigger - the machine change trigger (ADR 0011 principle 3-machine).

Reads the canonical-drift scanner's observation records and, for every observation
that records a real region body drift, emits a *structured change request* on stdout.
This is the machine entry point of the single change-management process (ADR 0011 3):
"for the machine trigger (scanner) it auto-files the change request".

SCOPE / DEFERRALS (deliberate, made detectable - not an oversight):
  * EMIT-ONLY. This tool turns a drift observation into a change-request payload and
    prints it. It does NOT apply anything: the decision gate ("should we take this
    change?", ADR 0011 4) and the coordinated manifest-row+marker write (the
    "unit-record coupled write") are DEFERRED - the gate to P7a, the coupled write to
    P6/P7. A drift is a region *body* change, so every drift-driven request is
    classification="marker-coupled" and is routed to that deferred path; the tool never
    proposes an immediately-appliable manifest op (consistent with the P3a.1 CRUD-tool
    write-path boundary, which refuses marker-coupled manifest writes).
  * NO NEW STORE. Output goes to stdout only; nothing is written under governance/state/
    (ADR 0011 5: the audit trail is the Git commit + CHANGELOG, plus the P8 ledger -
    no second operation-log store).
  * PROVISIONAL CONTRACT. The change-request payload shape is intentionally NOT pinned
    to a schema file here. Its real consumer is the P7a decision gate, which owns the
    contract; pinning it now would prematurely fix a contract against a consumer that
    does not yet exist. Each payload therefore carries contract_status / consumer_status
    markers so the deferral stays visible and cannot be silently "promoted".
  * REAL RUN IS P6. The scanner's first real run (against vendored consumers carrying
    markers) is P6; until then this trigger is built and fixture-tested only.

The payload is derived only from the observation's drift/identity fields. The DEP-3
fork fields (forwarded / applied_upstream / change_reason / reason_class) belong to the
fork / reconcile-back flow (P6.6 / P7a), not to the machine drift trigger, and are NOT
consumed here. region_locator is passed through opaquely (its final internal form is
pinned at P6); this tool does not parse it.

Single-file, stdlib-only (ADR 0003 standalone-tool principle; shared *logic* - the
canonical-JSON emitter - is reuse-by-copy, not an import).
"""

import argparse
import glob
import json
import sys

TRIGGER_VERSION = "0.1.0"

# Provisional change-request shape marker. NOT a pinned schema (see module docstring):
# the P7a decision gate owns the real contract.
REQUEST_VERSION = "0.1.0-provisional"

# Routing constants (the deferred path this trigger feeds; ADR 0011 3/4).
CLASSIFICATION = "marker-coupled"
PROPOSED_ROUTE = "decision-gate(P7a) -> unit-record coupled write(P6/P7)"

# Tracked-deferral markers (keep the deferral detectable; see module docstring).
CONTRACT_STATUS = "provisional-unpinned"
CONSUMER_STATUS = "none-until-P7a-decision-gate"


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
        # undecided here (maturity clause)
        "kind": None,
        "impact": None,
        # tracked deferral (keep visible)
        "contract_status": CONTRACT_STATUS,
        "consumer_status": CONSUMER_STATUS,
    }


def build_requests(observations):
    """Pure transform: observations -> sorted list of change-request payloads.
    One request per actionable (unit_id, consumer, region) drift; stable order."""
    reqs = [to_change_request(o) for o in observations if is_actionable(o)]
    reqs.sort(key=lambda r: (r.get("unit_id") or "", r.get("consumer") or "",
                             r.get("region_locator") or ""))
    return reqs


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Machine change trigger: scanner drift observations -> "
                    "structured change requests (emit-only; ADR 0011 3-machine).")
    ap.add_argument("--observations", required=True,
                    help="Path or glob to scanner observation JSONL file(s).")
    ap.add_argument("--version", action="version",
                    version="canon-drift-trigger %s" % TRIGGER_VERSION)
    args = ap.parse_args(argv)

    paths = sorted(glob.glob(args.observations))
    if not paths:
        sys.stderr.write("no observation files matched: %s\n" % args.observations)
        return 1

    requests = build_requests(_iter_observations(paths))
    out = sys.stdout
    for r in requests:
        out.write(_canonical_line(r) + "\n")
    sys.stderr.write("emitted %d change-request(s) from %d file(s) "
                     "(emit-only; no state written)\n" % (len(requests), len(paths)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
