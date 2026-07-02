#!/usr/bin/env python3
"""canon-manifest-tool: the tool-mediated write path for governance/state/manifest.jsonl.

This is the P3a.1 deliverable of ADR 0011 (canon change-management governance),
principle 2: the manifest master is mutated ONLY through a self-validating CRUD tool,
so a mutation can never leave the master in an invalid state. Once this tool exists,
direct manifest edits stop and the ADR 0015 |6 interim metadata guardrail is superseded.

WRITE-PATH BOUNDARY (P3a design decision).
This tool owns the *manifest write path* only: it creates / updates / deletes rows in
governance/state/manifest.jsonl. It does NOT write the in-code markers (a region unit's
version / policy / binding / hash in reference-code/.../*.ps1). The coordinated
"manifest row + its marker" write -- the named-deferred `unit-record coupled write` --
is investigated and built when the first real marker-coupled change flows through the
process (P6/P7 reconcile-back / vendoring), per ADR 0017 (do not finalize a design
against no real artifact). Until then, a marker-coupled change requested here is REFUSED
by self-validation (the validator's checks D/G/E catch the resulting marker drift and the
op is rolled back) -- the boundary is enforced by the existing gate, not by a special case.

DISCIPLINE.
  * Every mutation is transactional: snapshot the file bytes, apply, write atomically,
    run the governance-state validator (as a subprocess -- a black-box sibling-tool
    invocation, not a code import, per the ADR 0003 standalone-tool principle), and
    ROLL BACK to the snapshot if the validator reports any finding. The on-disk master
    is therefore never left invalid after this tool returns.
  * Writes are canonical-JSON (key-sorted, compact separators, ensure_ascii=False),
    one record per line, reuse-by-copy of the scanner's _canonical_line (ADR 0003).
  * Light, stdlib-only pre-checks give fast user-facing errors; the subprocess validator
    is the authoritative gate (it owns the schema check A and the cross-tier checks C-G).

Runtime: python3 (stdlib only). The validator subprocess additionally needs jsonschema
(the sanctioned artifact-gate runtime).

Usage:
    python3 tool.py --root <repo-root> register   --unit-id <id> --kind <k> --location <p> \
        --version <v> --change-policy <cp> --binding <bm> --platform-scope <ps> \
        [--tested true|false] [--maturity <m>] [--consumer consumer=<c>,path=<p> ...]
    python3 tool.py --root <repo-root> register   --unit-id <id> --kind project \
        --location <projects/dir> --maturity sandbox|incubating|governed|archived
        (kind=project is a lifecycle record, ADR 0024: maturity replaces the
        region-unit fields; --version/--change-policy/--binding/--platform-scope
        are rejected)
    python3 tool.py --root <repo-root> update     --unit-id <id> [--tested true|false] \
        [--version <v>] [--change-policy <cp>] [--binding <bm>] [--platform-scope <ps>] \
        [--location <p>] [--maturity <m>] [--add-consumer consumer=<c>,path=<p> ...] [--clear-consumers]
    python3 tool.py --root <repo-root> deregister --unit-id <id>
    python3 tool.py --root <repo-root> list

Global flags: --root (default "."), --validator <path>
              (default <root>/quality-tools/governance-state-validator/validate_state.py),
              --dry-run (show the resulting row(s); do not write or validate).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

# --- enums / pattern mirrored from governance/schema/manifest.schema.json -------------
KINDS = ("powershell-helper", "spec-region", "governance-doc", "bash-region",
         "tool", "python-helper", "python-tool", "template", "project")
MATURITIES = ("sandbox", "incubating", "governed", "archived")
CHANGE_POLICIES = ("canonical", "vendored-upstream-first", "forked")
BINDING_MODES = ("follow-latest", "pin")
PLATFORM_SCOPES = ("cross-platform", "windows-enhanced", "windows-only")
UNIT_ID_RE = re.compile(r"^[a-z0-9]+(\.[a-z0-9-]+)+$")
REQUIRED = ("schema_version", "unit_id", "kind", "canonical_location",
            "canonical_version", "change_policy", "binding_mode", "consumers",
            "tested", "platform_scope")
# kind=project rows (ADR 0024) are lifecycle records: maturity replaces the
# region-unit fields (mirrors the manifest.schema.json allOf branch).
PROJECT_REQUIRED = ("schema_version", "unit_id", "kind", "canonical_location",
                    "consumers", "maturity")
SCHEMA_VERSION = "1"


# --- canonical-JSON line: reuse-by-copy of scanner.py _canonical_line (ADR 0003) -------
def _canonical_line(record):
    """Canonical-JSON line: key-sorted, compact separators, ensure_ascii=False.
    Byte-for-byte reuse-by-copy of the scanner/observation emitter (ADR 0003)."""
    return json.dumps(record, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False)


# --- manifest I/O ----------------------------------------------------------------------
def manifest_path(root):
    return os.path.join(root, "governance", "state", "manifest.jsonl")


def load_manifest(path):
    """Return an ordered list of records (dicts). One canonical-JSON object per line."""
    records = []
    with open(path, encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except ValueError as exc:
                raise SystemExit("manifest: line %d is not valid JSON: %s"
                                 % (lineno, exc))
    return records


def render_manifest(records):
    """Render the full manifest text (canonical line per record, trailing newline)."""
    return "".join(_canonical_line(r) + "\n" for r in records)


def write_manifest_atomic(path, text):
    """Atomic replace: write a temp file in the same dir, fsync, os.replace."""
    directory = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".manifest.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


# --- light, stdlib-only pre-checks (fast errors; validator is authoritative) -----------
def precheck_record(record, existing, *, is_new):
    """Return a list of human-readable problems (empty list == ok)."""
    problems = []
    is_project = record.get("kind") == "project"
    for field in (PROJECT_REQUIRED if is_project else REQUIRED):
        if field not in record:
            problems.append("missing required field: %s" % field)
    uid = record.get("unit_id", "")
    if uid and not UNIT_ID_RE.match(uid):
        problems.append("unit_id %r does not match the schema pattern" % uid)
    if record.get("kind") not in KINDS:
        problems.append("kind %r not in %s" % (record.get("kind"), KINDS))
    if "maturity" in record and record.get("maturity") not in MATURITIES:
        problems.append("maturity %r not in %s" % (record.get("maturity"), MATURITIES))
    if is_project:
        # lifecycle record (ADR 0024): the region-unit fields must be ABSENT
        for field in ("canonical_version", "change_policy", "binding_mode",
                      "tested", "platform_scope"):
            if field in record:
                problems.append("kind=project row must not carry %s "
                                "(lifecycle record, ADR 0024)" % field)
    else:
        if record.get("change_policy") not in CHANGE_POLICIES:
            problems.append("change_policy %r not in %s"
                            % (record.get("change_policy"), CHANGE_POLICIES))
        if record.get("binding_mode") not in BINDING_MODES:
            problems.append("binding_mode %r not in %s"
                            % (record.get("binding_mode"), BINDING_MODES))
        if record.get("platform_scope") not in PLATFORM_SCOPES:
            problems.append("platform_scope %r not in %s"
                            % (record.get("platform_scope"), PLATFORM_SCOPES))
        if not isinstance(record.get("tested"), bool):
            problems.append("tested must be a boolean")
    if not isinstance(record.get("consumers"), list):
        problems.append("consumers must be an array")
    if is_new:
        ids = {r["unit_id"] for r in existing}
        locs = {r["canonical_location"] for r in existing}
        if uid in ids:
            problems.append("unit_id %r is already registered" % uid)
        if record.get("canonical_location") in locs:
            problems.append("canonical_location %r is already registered"
                            % record.get("canonical_location"))
    return problems


def parse_consumer(spec):
    """Parse 'consumer=<c>,path=<p>' into {'consumer': c, 'path': p}."""
    parts = dict(kv.split("=", 1) for kv in spec.split(",") if "=" in kv)
    if "consumer" not in parts or "path" not in parts:
        raise SystemExit("--consumer expects 'consumer=<id>,path=<file>' (got %r)" % spec)
    return {"consumer": parts["consumer"], "path": parts["path"]}


# --- self-validation (subprocess; authoritative) ---------------------------------------
def default_validator(root):
    return os.path.join(root, "quality-tools", "governance-state-validator",
                        "validate_state.py")


def run_validator(validator, root):
    """Run the governance-state validator. Return (rc, combined_output)."""
    if not os.path.isfile(validator):
        return (127, "validator not found at %s -- refusing to write unverified "
                "(fail-safe)" % validator)
    proc = subprocess.run([sys.executable, validator, "--root", root],
                          capture_output=True, text=True)
    return (proc.returncode, proc.stdout + proc.stderr)


# --- transactional apply ---------------------------------------------------------------
def transact(root, validator, new_records, *, dry_run):
    """Write new_records, validate, roll back on any finding. Return (ok, message)."""
    path = manifest_path(root)
    new_text = render_manifest(new_records)
    if dry_run:
        return (True, "[dry-run] would write %d rows; not validating" % len(new_records))
    with open(path, "rb") as handle:
        snapshot = handle.read()
    write_manifest_atomic(path, new_text)
    rc, out = run_validator(validator, root)
    if rc != 0:
        # roll back: restore the exact original bytes.
        with open(path, "wb") as handle:
            handle.write(snapshot)
        tail = "\n".join(out.strip().splitlines()[-12:])
        return (False, "REFUSED: the validator reported findings, so the change was "
                "rolled back (master unchanged). This is expected for a marker-coupled "
                "change -- that write path is the deferred `unit-record coupled write` "
                "(P6/P7).\n--- validator output (tail) ---\n%s" % tail)
    return (True, "OK: change applied and validated (validator: 0 findings).")


# --- operations ------------------------------------------------------------------------
def op_register(root, validator, args):
    records = load_manifest(manifest_path(root))
    if args.kind == "project":
        # lifecycle record (ADR 0024): maturity replaces the region-unit fields.
        rejected = [f for f, v in (("--version", args.version),
                                   ("--change-policy", args.change_policy),
                                   ("--binding", args.binding),
                                   ("--platform-scope", args.platform_scope))
                    if v is not None]
        if rejected:
            return (False, "register pre-check failed:\n  - kind=project takes no %s "
                    "(lifecycle record, ADR 0024)" % ", ".join(rejected))
        if args.maturity is None:
            return (False, "register pre-check failed:\n  - kind=project requires "
                    "--maturity (ADR 0024)")
        record = {
            "schema_version": SCHEMA_VERSION,
            "unit_id": args.unit_id,
            "kind": args.kind,
            "canonical_location": args.location,
            "maturity": args.maturity,
            "consumers": [parse_consumer(c) for c in (args.consumer or [])],
        }
    else:
        missing = [f for f, v in (("--version", args.version),
                                  ("--change-policy", args.change_policy),
                                  ("--binding", args.binding),
                                  ("--platform-scope", args.platform_scope))
                   if v is None]
        if missing:
            return (False, "register pre-check failed:\n  - kind=%s requires %s"
                    % (args.kind, ", ".join(missing)))
        record = {
            "schema_version": SCHEMA_VERSION,
            "unit_id": args.unit_id,
            "kind": args.kind,
            "canonical_location": args.location,
            "canonical_version": args.version,
            "change_policy": args.change_policy,
            "binding_mode": args.binding,
            "consumers": [parse_consumer(c) for c in (args.consumer or [])],
            "tested": (args.tested == "true"),
            "platform_scope": args.platform_scope,
        }
        if args.maturity is not None:
            record["maturity"] = args.maturity
    problems = precheck_record(record, records, is_new=True)
    if problems:
        return (False, "register pre-check failed:\n  - " + "\n  - ".join(problems))
    records.append(record)
    return transact(root, validator, records, dry_run=args.dry_run)


def op_update(root, validator, args):
    records = load_manifest(manifest_path(root))
    idx = next((i for i, r in enumerate(records)
                if r["unit_id"] == args.unit_id), None)
    if idx is None:
        return (False, "update: no row with unit_id %r" % args.unit_id)
    record = dict(records[idx])
    if args.tested is not None:
        record["tested"] = (args.tested == "true")
    if args.version is not None:
        record["canonical_version"] = args.version
    if args.change_policy is not None:
        record["change_policy"] = args.change_policy
    if args.binding is not None:
        record["binding_mode"] = args.binding
    if args.platform_scope is not None:
        record["platform_scope"] = args.platform_scope
    if args.location is not None:
        record["canonical_location"] = args.location
    if args.maturity is not None:
        record["maturity"] = args.maturity
    if args.clear_consumers:
        record["consumers"] = []
    for spec in (args.add_consumer or []):
        record["consumers"] = record.get("consumers", []) + [parse_consumer(spec)]
    problems = precheck_record(record, records, is_new=False)
    if problems:
        return (False, "update pre-check failed:\n  - " + "\n  - ".join(problems))
    records[idx] = record
    return transact(root, validator, records, dry_run=args.dry_run)


def op_deregister(root, validator, args):
    records = load_manifest(manifest_path(root))
    kept = [r for r in records if r["unit_id"] != args.unit_id]
    if len(kept) == len(records):
        return (False, "deregister: no row with unit_id %r" % args.unit_id)
    return transact(root, validator, kept, dry_run=args.dry_run)


def op_list(root, validator, args):
    records = load_manifest(manifest_path(root))
    for r in records:
        print(_canonical_line(r))
    return (True, "%d rows." % len(records))


# --- CLI -------------------------------------------------------------------------------
def build_parser():
    parser = argparse.ArgumentParser(
        description="Tool-mediated CRUD for governance/state/manifest.jsonl (ADR 0011 |2).",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=".", help="repo root (default: .)")
    parser.add_argument("--validator", default=None,
                        help="path to validate_state.py (default: under --root)")
    parser.add_argument("--dry-run", action="store_true",
                        help="show the resulting rows; do not write or validate")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_reg = sub.add_parser("register", help="add a new managed-unit row")
    p_reg.add_argument("--unit-id", required=True)
    p_reg.add_argument("--kind", required=True, choices=KINDS)
    p_reg.add_argument("--location", required=True)
    p_reg.add_argument("--version", default=None,
                       help="required for every kind except project (ADR 0024)")
    p_reg.add_argument("--change-policy", choices=CHANGE_POLICIES, default=None)
    p_reg.add_argument("--binding", choices=BINDING_MODES, default=None)
    p_reg.add_argument("--platform-scope", choices=PLATFORM_SCOPES, default=None)
    p_reg.add_argument("--tested", choices=("true", "false"), default="false")
    p_reg.add_argument("--maturity", choices=MATURITIES, default=None,
                       help="required for kind=project; optional elsewhere (ADR 0024)")
    p_reg.add_argument("--consumer", action="append",
                       help="consumer=<id>,path=<file> (repeatable)")
    p_reg.set_defaults(func=op_register)

    p_upd = sub.add_parser("update", help="modify fields of an existing row")
    p_upd.add_argument("--unit-id", required=True)
    p_upd.add_argument("--tested", choices=("true", "false"), default=None)
    p_upd.add_argument("--version", default=None)
    p_upd.add_argument("--change-policy", choices=CHANGE_POLICIES, default=None)
    p_upd.add_argument("--binding", choices=BINDING_MODES, default=None)
    p_upd.add_argument("--platform-scope", choices=PLATFORM_SCOPES, default=None)
    p_upd.add_argument("--location", default=None)
    p_upd.add_argument("--maturity", choices=MATURITIES, default=None)
    p_upd.add_argument("--add-consumer", action="append",
                       help="consumer=<id>,path=<file> (repeatable)")
    p_upd.add_argument("--clear-consumers", action="store_true")
    p_upd.set_defaults(func=op_update)

    p_dereg = sub.add_parser("deregister", help="remove a row by unit_id")
    p_dereg.add_argument("--unit-id", required=True)
    p_dereg.set_defaults(func=op_deregister)

    p_list = sub.add_parser("list", help="print all rows (read-only)")
    p_list.set_defaults(func=op_list)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    root = args.root
    validator = args.validator or default_validator(root)
    ok, message = args.func(root, validator, args)
    print(message)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
