#!/usr/bin/env python3
"""Canon marker hash re-stamp tool (write-side; ADR 0015).

Recomputes each canonical unit's marker `hash=` from its region body using the
ADR 0015 canonical normalized-hash contract, and (in --write mode) rewrites the
marker BEGIN line in place. This is the TOOL-MEDIATED write path for marker
hashes during the interim before the ADR 0011 CRUD tool (P3a). It pairs with the
governance-state validator's read-side check G: writes go through this tool,
results are independently re-verified by the validator (recompute + compare).

Design (ADR 0003): single-file, stdlib-only, no-cross-reference. The normalizer
below is reuse-by-copy of psa.py's PSA8001 tokenizer; conformance to the one
contract is pinned by the golden vectors shared with the validator self-test, not
by importing shared code. Only the BEGIN-line `hash=` field is ever rewritten:
the region body, the version/policy/binding fields, BOM, and CRLF line endings
are left byte-identical. Re-stamping is metadata-only and never a code change.

Usage:
    python3 restamp.py --root <repo-root> [--check | --write] [--family powershell]

    --check  (default)  report any unit whose marker hash != recomputed hash;
                        exit 1 if any drift is found, 0 if all in sync.
    --write             rewrite drifted marker hashes in place; exit 0.
"""

import argparse
import hashlib
import os
import re
import sys


# ---------------------------------------------------------------------------
# Canonical normalized-hash contract (ADR 0015) - reuse-by-copy of psa.py's
# PSA8001 tokenizer. WIDTH = 16 hex (canonical marker hash). See the validator
# header for the no-cross-reference rationale; golden vectors pin conformance.
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
    clean = _strip_strings_and_comments(region_body_text)
    normalized = re.sub(r'\s+', ' ', clean).strip()
    return hashlib.sha256(normalized.encode('utf-8')).hexdigest()[:16]


MARKER_BEGIN = re.compile(
    r"# >>> CANONICAL unit_id=(\S+) version=(\S+) hash=(\S+) "
    r"policy=(\S+) binding=(\S+) >>>"
)
MARKER_END = re.compile(r"# <<< CANONICAL unit_id=(\S+) <<<")


def _region_body_from_lines(lines):
    begins = [i for i, l in enumerate(lines) if MARKER_BEGIN.match(l)]
    ends = [i for i, l in enumerate(lines) if MARKER_END.match(l)]
    if len(begins) != 1 or len(ends) != 1 or ends[0] <= begins[0]:
        return None, None, None
    return begins[0], ends[0], "\n".join(lines[begins[0] + 1:ends[0]])


def scan(root, family):
    """Yield (unit_id, rel_path, old_hash, new_hash, begin_idx) per unit."""
    base = os.path.join(root, "reference-code", family)
    for home in ("Public", "Private"):
        home_dir = os.path.join(base, home)
        if not os.path.isdir(home_dir):
            continue
        for fn in sorted(os.listdir(home_dir)):
            if not fn.endswith(".ps1"):
                continue
            path = os.path.join(home_dir, fn)
            with open(path, encoding="utf-8-sig") as handle:
                text = handle.read()
            lines = text.splitlines()
            bi, _, body = _region_body_from_lines(lines)
            if body is None:
                yield (fn, os.path.relpath(path, root), None, None, None)
                continue
            m = MARKER_BEGIN.match(lines[bi])
            yield (m.group(1), os.path.relpath(path, root),
                   m.group(3), canon_norm_hash(body), bi)


def rewrite(root, rel_path, old_hash, new_hash):
    """Rewrite only the hash= token on the BEGIN line; preserve BOM and CRLF
    by operating on bytes and replacing only the hash substring."""
    abs_path = os.path.join(root, rel_path)
    with open(abs_path, "rb") as handle:
        raw = handle.read()
    needle = ("hash=%s " % old_hash).encode("utf-8")
    repl = ("hash=%s " % new_hash).encode("utf-8")
    if raw.count(needle) != 1:
        raise SystemExit("restamp: expected exactly one '%s' in %s (found %d)"
                         % (needle.decode(), rel_path, raw.count(needle)))
    with open(abs_path, "wb") as handle:
        handle.write(raw.replace(needle, repl, 1))


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=".")
    parser.add_argument("--family", default="powershell")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true",
                      help="report drift only (default); exit 1 if any drift")
    mode.add_argument("--write", action="store_true",
                      help="rewrite drifted marker hashes in place")
    args = parser.parse_args(argv)
    root = os.path.abspath(args.root)

    drift, malformed, total = [], [], 0
    for unit_id, rel, old, new, _bi in scan(root, args.family):
        total += 1
        if old is None:
            malformed.append((unit_id, rel))
        elif old != new:
            drift.append((unit_id, rel, old, new))

    print("==== canon-hash-restamp (%s) ====" % args.family)
    print("units scanned : %d" % total)
    print("in sync       : %d" % (total - len(drift) - len(malformed)))
    print("drifted       : %d" % len(drift))
    if malformed:
        print("malformed     : %d" % len(malformed))
        for unit_id, rel in malformed:
            print("  [malformed] %s (%s)" % (unit_id, rel))

    if args.write:
        for unit_id, rel, old, new in drift:
            rewrite(root, rel, old, new)
            print("  [rewrote] %s  %s -> %s" % (unit_id, old, new))
        print("\nDONE: re-stamped %d marker hash(es); bodies unchanged."
              % len(drift))
        return 1 if malformed else 0

    for unit_id, rel, old, new in drift:
        print("  [drift] %s  marker=%s recomputed=%s  (%s)"
              % (unit_id, old, new, rel))
    if drift or malformed:
        print("\nDRIFT: %d hash(es) out of sync (run with --write to fix)."
              % len(drift))
        return 1
    print("\nIN SYNC: all marker hashes match the ADR 0015 contract.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
