#!/usr/bin/env python3
"""Governance-state validation gate.

Validates the committed governance state (governance/state/*.jsonl) against the
governance schemas (governance/schema/*.schema.json) and checks the cross-tier
invariants that the schemas alone cannot express:

  A. manifest schema       - every manifest.jsonl record validates against
                             manifest.schema.json (draft-07).
  B. observation schema     - every observations/**/*.jsonl record validates
                             against observation.schema.json (skipped when no
                             observation files exist yet, e.g. before P3).
  C. canonical_location     - every manifest record's canonical_location file
                             exists on disk.
  D. manifest<->marker       - for kind=powershell-helper, the canonical_location
                             file carries a canonical marker whose unit_id,
                             version, policy, and binding match the manifest
                             record (manifest is the single source of truth; the
                             marker claims sync against it).
  G. marker hash integrity   - the marker's hash= equals the canonical normalized
                             hash recomputed from the region body (ADR 0015:
                             strip comments/strings -> collapse whitespace ->
                             sha256[:16]). A read-side check (ADR 0011 principle
                             1): it catches a stale/hand-edited hash regardless of
                             how the edit arose, including a mis-stamping tool. It
                             is the interim metadata guardrail until the ADR 0011
                             CRUD tool (P3a) makes the write path tool-only.
  E. canon coverage          - the set of canon unit files in the unit home
                             (reference-code/<family>/{Public,Private}) is in
                             bijection with the powershell-helper manifest records
                             (no orphan unit-home file, no dangling record).
                             Manifest-master (ADR 0011 §1): non-unit areas
                             (tests/, .psm1/.psd1 scaffolding) are not managed
                             units and are not enumerated.
  F. canonical JSONL format  - every state record is canonical-JSON: key-sorted,
                             compact separators, one record per line.

Runtime: python3 + jsonschema (the sanctioned artifact-gate runtime; governance
SPEC machinery / baseline section 8.2). Exit 0 if all checks pass, 1 otherwise.

Usage:
    python3 validate_state.py [--root <repo-root>] [--quiet]
"""

import argparse
import glob
import json
import os
import re
import sys

MARKER_BEGIN = re.compile(
    r"# >>> CANONICAL unit_id=(\S+) version=(\S+) hash=(\S+) "
    r"policy=(\S+) binding=(\S+) >>>"
)
MARKER_END = re.compile(r"# <<< CANONICAL unit_id=(\S+) <<<")


# ---------------------------------------------------------------------------
# Canonical normalized-hash contract (ADR 0015; governance/SPEC.md Machinery).
#
# strip_strings_and_comments below is REUSE-BY-COPY of psa.py's PSA8001
# tokenizer (ADR 0003: tools are single-file, stdlib-only, no-cross-reference -
# they do not import sibling project code; shared logic travels as a verified
# copy, not an import). Conformance of every copy to the one contract is pinned
# by the golden vectors in test_validate_state.py (GV-1..GV-5), not by sharing
# code. The hash WIDTH here is 16 hex (the canonical marker/observation hash);
# psa.py's own PSA8001 uses a 12-hex relative-comparison hash for a different
# purpose and is intentionally NOT unified with this one.
# ---------------------------------------------------------------------------
def _strip_strings_and_comments(text):
    out = []
    i, n = 0, len(text)
    in_sq = in_dq = in_lc = in_bc = in_here_sq = in_here_dq = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ''
        if c == '\n':
            out.append('\n')
            if in_lc:
                in_lc = False
            i += 1
            continue
        if in_lc:
            out.append(' '); i += 1; continue
        if in_bc:
            if c == '#' and nxt == '>':
                out.append('  '); in_bc = False; i += 2; continue
            out.append(' '); i += 1; continue
        if in_here_sq:
            if c == "'" and nxt == '@':
                out.append('  '); in_here_sq = False; i += 2; continue
            out.append(' '); i += 1; continue
        if in_here_dq:
            if c == '"' and nxt == '@':
                out.append('  '); in_here_dq = False; i += 2; continue
            if c == '$':
                out.append('$'); i += 1
                while i < n and (text[i].isalnum() or text[i] in '_:'):
                    out.append(text[i]); i += 1
                continue
            out.append(' '); i += 1; continue
        if in_sq:
            if c == "'":
                if nxt == "'":
                    out.append('  '); i += 2; continue
                in_sq = False; out.append(' '); i += 1; continue
            out.append(' '); i += 1; continue
        if in_dq:
            if c == '`':
                if i + 1 < n:
                    out.append('  '); i += 2
                else:
                    out.append(' '); i += 1
                continue
            if c == '"':
                if nxt == '"':
                    out.append('  '); i += 2; continue
                in_dq = False; out.append(' '); i += 1; continue
            if c == '$':
                out.append('$'); i += 1
                if i < n and text[i] == '{':
                    out.append('{'); i += 1
                    while i < n and text[i] != '}':
                        out.append(text[i]); i += 1
                    if i < n:
                        out.append('}'); i += 1
                    continue
                while i < n and (text[i].isalnum() or text[i] in '_:'):
                    out.append(text[i]); i += 1
                continue
            out.append(' '); i += 1; continue
        if c == '@' and nxt == "'":
            out.append('  '); in_here_sq = True; i += 2; continue
        if c == '@' and nxt == '"':
            out.append('  '); in_here_dq = True; i += 2; continue
        if c == '<' and nxt == '#':
            out.append('  '); in_bc = True; i += 2; continue
        if c == '#':
            out.append(' '); in_lc = True; i += 1; continue
        if c == "'":
            in_sq = True; out.append(' '); i += 1; continue
        if c == '"':
            in_dq = True; out.append(' '); i += 1; continue
        out.append(c); i += 1
    return ''.join(out)


def canon_norm_hash(region_body_text):
    """ADR 0015 canonical normalized hash of a region body.

    Normalize (comments/strings -> whitespace, then collapse all whitespace
    runs to a single space, strip ends), then sha256 truncated to 16 hex.
    Encoding-neutral: BOM/CRLF/LF differences cancel.
    """
    import hashlib
    clean = _strip_strings_and_comments(region_body_text)
    normalized = re.sub(r'\s+', ' ', clean).strip()
    return hashlib.sha256(normalized.encode('utf-8')).hexdigest()[:16]


def marker_region_body(text):
    """Return the region body (lines strictly between the BEGIN and END marker
    lines, LF-joined), or None if the file does not carry exactly one well-formed
    marker pair. *text* must already be BOM-stripped (read via utf-8-sig)."""
    lines = text.splitlines()
    begins = [i for i, l in enumerate(lines) if MARKER_BEGIN.match(l)]
    ends = [i for i, l in enumerate(lines) if MARKER_END.match(l)]
    if len(begins) != 1 or len(ends) != 1 or ends[0] <= begins[0]:
        return None
    return "\n".join(lines[begins[0] + 1:ends[0]])


def _load_schema(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _read_text(path):
    # utf-8-sig transparently strips a leading BOM (canon .ps1 files carry one).
    with open(path, encoding="utf-8-sig") as handle:
        return handle.read()


def _canonical_line(record):
    return json.dumps(record, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False)


def _iter_jsonl(path):
    with open(path, encoding="utf-8") as handle:
        for lineno, raw in enumerate(handle, start=1):
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            yield lineno, line


def validate(root, quiet=False):
    from jsonschema import Draft7Validator

    findings = []

    def fail(check, msg):
        findings.append((check, msg))

    schema_dir = os.path.join(root, "governance", "schema")
    state_dir = os.path.join(root, "governance", "state")
    manifest_path = os.path.join(state_dir, "manifest.jsonl")

    manifest_schema = _load_schema(os.path.join(schema_dir,
                                                 "manifest.schema.json"))
    Draft7Validator.check_schema(manifest_schema)
    manifest_validator = Draft7Validator(manifest_schema)

    manifest_records = []

    # --- A. manifest schema + F. format (manifest) ---
    if not os.path.exists(manifest_path):
        fail("A", "governance/state/manifest.jsonl is missing")
    else:
        for lineno, line in _iter_jsonl(manifest_path):
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                fail("A", "manifest.jsonl line %d: invalid JSON (%s)"
                     % (lineno, exc))
                continue
            for err in manifest_validator.iter_errors(record):
                fail("A", "manifest.jsonl line %d: %s" % (lineno, err.message))
            if line != _canonical_line(record):
                fail("F", "manifest.jsonl line %d: not canonical JSON "
                          "(expected key-sorted compact)" % lineno)
            manifest_records.append(record)

    # --- B. observation schema + F. format (observations) ---
    obs_schema_path = os.path.join(schema_dir, "observation.schema.json")
    obs_files = sorted(glob.glob(os.path.join(state_dir, "observations",
                                              "**", "*.jsonl"), recursive=True))
    if obs_files:
        obs_schema = _load_schema(obs_schema_path)
        Draft7Validator.check_schema(obs_schema)
        obs_validator = Draft7Validator(obs_schema)
        for obs_path in obs_files:
            rel = os.path.relpath(obs_path, root)
            for lineno, line in _iter_jsonl(obs_path):
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as exc:
                    fail("B", "%s line %d: invalid JSON (%s)"
                         % (rel, lineno, exc))
                    continue
                for err in obs_validator.iter_errors(record):
                    fail("B", "%s line %d: %s" % (rel, lineno, err.message))
                if line != _canonical_line(record):
                    fail("F", "%s line %d: not canonical JSON" % (rel, lineno))
    elif not quiet:
        print("  (B) no observation files yet - skipped")

    # --- C. canonical_location existence + D. manifest<->marker coherence ---
    registered_ps1 = set()
    for record in manifest_records:
        loc = record.get("canonical_location")
        unit_id = record.get("unit_id")
        if not loc:
            continue
        abs_loc = os.path.join(root, loc)
        if not os.path.exists(abs_loc):
            fail("C", "%s: canonical_location does not exist (%s)"
                 % (unit_id, loc))
            continue
        if record.get("kind") == "powershell-helper":
            registered_ps1.add(os.path.normpath(loc))
            text = _read_text(abs_loc)
            match = MARKER_BEGIN.search(text)
            if not match:
                fail("D", "%s: no canonical marker in %s" % (unit_id, loc))
                continue
            marker_id, marker_ver = match.group(1), match.group(2)
            marker_hash = match.group(3)
            marker_policy, marker_binding = match.group(4), match.group(5)
            if marker_id != unit_id:
                fail("D", "%s: marker unit_id mismatch (marker=%s)"
                     % (unit_id, marker_id))
            if marker_ver != record.get("canonical_version"):
                fail("D", "%s: version mismatch (manifest=%s marker=%s)"
                     % (unit_id, record.get("canonical_version"), marker_ver))
            if marker_policy != record.get("change_policy"):
                fail("D", "%s: policy mismatch (manifest=%s marker=%s)"
                     % (unit_id, record.get("change_policy"), marker_policy))
            if marker_binding != record.get("binding_mode"):
                fail("D", "%s: binding mismatch (manifest=%s marker=%s)"
                     % (unit_id, record.get("binding_mode"), marker_binding))
            # --- G. marker hash integrity (ADR 0015) ---
            body = marker_region_body(text)
            if body is None:
                fail("G", "%s: malformed marker pair (cannot extract region "
                          "body) in %s" % (unit_id, loc))
            else:
                expected = canon_norm_hash(body)
                if marker_hash != expected:
                    fail("G", "%s: stale marker hash (marker=%s recomputed=%s) "
                              "in %s" % (unit_id, marker_hash, expected, loc))

    # --- E. canon coverage (bijection unit-home files <-> powershell-helper rows) ---
    # Manifest-master (ADR 0011 §1): the unit set is what the manifest registers,
    # not whatever sits under the canon tree. The on-disk side of the bijection is
    # therefore the UNIT HOME only - Public/ and Private/ - where canonical units
    # live. Non-unit areas under reference-code/<family>/ (tests/, and the
    # .psm1/.psd1 module scaffolding per ADR 0010) are not managed units and are
    # not enumerated here; an unregistered file is flagged only when it sits in the
    # unit home. This is a positive definition of the managed set, not an exclusion
    # list bolted onto a whole-tree glob.
    canon_files = set()
    for home in ("Public", "Private"):
        home_glob = os.path.join(root, "reference-code", "powershell", home,
                                 "**", "*.ps1")
        canon_files |= {os.path.normpath(os.path.relpath(p, root))
                        for p in glob.glob(home_glob, recursive=True)}
    for orphan in sorted(canon_files - registered_ps1):
        fail("E", "canon unit-home file not registered in manifest: %s" % orphan)
    for dangling in sorted(registered_ps1 - canon_files):
        fail("E", "manifest powershell-helper location has no canon file: %s"
             % dangling)

    return findings, len(manifest_records), len(canon_files)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=".",
                        help="repo root (default: current directory)")
    parser.add_argument("--quiet", action="store_true",
                        help="suppress the per-check skip notes")
    args = parser.parse_args(argv)

    root = os.path.abspath(args.root)
    findings, n_records, n_canon = validate(root, quiet=args.quiet)

    print("==== governance-state-validator ====")
    print("root          : %s" % root)
    print("manifest rows : %d" % n_records)
    print("canon files   : %d" % n_canon)

    if findings:
        print("\nFAIL: %d finding(s)" % len(findings))
        for check, msg in findings:
            print("  [%s] %s" % (check, msg))
        return 1
    print("\nPASS: 0 findings (A-G all green)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
