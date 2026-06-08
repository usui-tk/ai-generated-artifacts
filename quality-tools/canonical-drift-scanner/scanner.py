#!/usr/bin/env python3
"""Canonical-drift scanner (P3; quality-tools machinery, whole-tool unit #9).

Extracts the inlined canonical regions a consumer carries, recomputes their
normalized hashes (ADR 0015), compares to the canon at the version the marker
claims, and emits one observation record per scanned instance against the SOLE
output contract `governance/schema/observation.schema.json` (#8). It is the
mechanical realization of Topic-D drift detection (baseline §5 P3).

Design (ADR 0003): single-file, stdlib-only, no-cross-reference. The normalizer,
marker parser, and canonical-JSON emitter below are REUSE-BY-COPY of the
governance-state validator / canon-hash-restamp (which copy them from psa.py's
PSA8001 tokenizer); conformance of every copy to the one contract is pinned by
the golden vectors GV-1..5 in test_scanner.py (a shared TEST contract, not a
shared import). The hash width is 16 hex (ADR 0015), deliberately not unified
with psa.py PSA8001's 12-hex relative-comparison hash.

Field pins this scanner depends on (ADR 0016):
  F1: runtime.duckdb = "n/a" before P8 (DuckDB is P8-only, ADR 0002).
  F3: granularity is DERIVED from kind (the manifest carries no granularity):
        powershell-helper / bash-region / spec-region -> region
        python-helper / python-tool / tool            -> whole-tool
        governance-doc -> out of this scanner's body-hash-drift scope (ADR 0014)
  F4: drift="unknown" is the determinability fallback for a region the scanner
        located but could not resolve to a comparison result. The PRECISE trigger
        conditions are pinned at P6 (see the P6-investigation notes at the foot of
        this file); P3 reserves the value and emits it on the minimal cases below.

Scope (ADR 0016 F2): P3 builds + fixture-tests this scanner. Its FIRST REAL RUN is
P6 - consumers carry no vendored markers until vendoring (manifest consumers[] is
empty until P6/P7). Running it against a repo with no consumer regions yields only
whole-tool rows (the registered tools) and is expected at P3.

Usage:
    python3 scanner.py --root <repo-root> --repo <name> [--out <dir>] [--stdout]
"""

import argparse
import datetime
import glob
import hashlib
import json
import os
import re
import sys

SCANNER_VERSION = "0.1.0"

# kind -> granularity derivation (ADR 0016 F3). "region" => body-hash-drift path;
# "whole-tool" => whole-tool null convention (baseline §4.4). governance-doc is
# out of this scanner's scope (ADR 0014 §2): rendered class-(B) docs carry no
# per-file hash/marker and are governed by the document-conformance gate.
KIND_GRANULARITY = {
    "powershell-helper": "region",
    "bash-region": "region",
    "python-helper": "whole-tool",
    "python-tool": "whole-tool",
    "tool": "whole-tool",
    # "governance-doc" and "spec-region": out of scope (handled by the
    # document-conformance gate / doc_gate --path). Those carry HTML-comment
    # doc-region markers ("<!-- >>> CANONICAL ... -->") whose hashes doc_gate
    # recomputes against the spec home; this scanner parses only the
    # "# >>> CANONICAL" hash-comment markers of code regions (ADR 0014). The
    # spec-region scope was pinned here at P6a, the first run with a real spec
    # consumer (download-speakerdeck SPEC.md), which made the split concrete.
}

MARKER_BEGIN = re.compile(
    r"# >>> CANONICAL unit_id=(\S+) version=(\S+) hash=(\S+) "
    r"policy=(\S+) binding=(\S+) >>>"
)
MARKER_END = re.compile(r"# <<< CANONICAL unit_id=(\S+) <<<")


# --- reuse-by-copy: ADR 0015 normalizer (psa.py PSA8001 tokenizer) ----------
# Conformance to the one contract is pinned by golden vectors GV-1..5; this is a
# verified copy, not an import (ADR 0003 no-cross-reference).
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
    """ADR 0015 canonical normalized hash: strip comments/strings -> collapse
    whitespace -> sha256 truncated to 16 hex. Encoding-neutral."""
    clean = _strip_strings_and_comments(region_body_text)
    normalized = re.sub(r'\s+', ' ', clean).strip()
    return hashlib.sha256(normalized.encode('utf-8')).hexdigest()[:16]


HASH_WHAT = "region-body; comments/strings->ws; ws-runs->single space"
# --- end reuse-by-copy ------------------------------------------------------


def _canonical_line(record):
    """Canonical-JSON line: key-sorted, compact separators, ensure_ascii=False.
    Reuse-by-copy of the validator's _canonical_line (check F contract)."""
    return json.dumps(record, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False)


def _read_text(path):
    with open(path, encoding="utf-8-sig") as handle:  # strips BOM
        return handle.read()


def extract_region(text, unit_id):
    """Return (region_body, marker_dict, locator) for the marker pair in `text`
    whose unit_id == `unit_id`, else (None, None, None).

    A real consumer file inlines MANY vendored regions (dozens of helper bodies
    in one .ps1; many doc regions in one SPEC), so the region to compare is
    selected by `unit_id` rather than by assuming a single marker pair per file
    (region_locator final form, pinned at P6 - see foot of file).

    Indeterminate (None, None, None) - the F4 drift="unknown" triggers - when the
    unit_id's BEGIN marker is absent (0 matches), appears more than once in the
    same file (ambiguous duplicate), or has no matching END marker after it.

    locator (final form, P6): symbol/context-anchored - the unit_id plus the
    enclosing function name parsed from the region body - so a region re-finds
    across edits even as raw line numbers drift run-to-run (ADR 0014 §4
    "locate by symbol/context, not line number").
    """
    lines = text.splitlines()
    begins = [i for i, l in enumerate(lines)
              if (m := MARKER_BEGIN.match(l)) and m.group(1) == unit_id]
    if len(begins) != 1:
        return None, None, None  # absent (0) or ambiguous duplicate (>1) -> F4
    bi = begins[0]
    ei = None
    for j in range(bi + 1, len(lines)):
        me = MARKER_END.match(lines[j])
        if me and me.group(1) == unit_id:
            ei = j
            break
    if ei is None:
        return None, None, None  # BEGIN with no matching END -> F4
    m = MARKER_BEGIN.match(lines[bi])
    marker = {
        "unit_id": m.group(1), "version": m.group(2), "hash": m.group(3),
        "policy": m.group(4), "binding": m.group(5),
    }
    body = "\n".join(lines[bi + 1:ei])
    sym = None
    for bl in lines[bi + 1:ei]:
        s = bl.strip()
        if s.startswith("function "):
            sym = s[len("function "):].split("{")[0].split("(")[0].strip()
            break
    locator = ("marker:%s@fn:%s" % (unit_id, sym)) if sym else ("marker:%s" % unit_id)
    return body, marker, locator


def canonical_norm_hash_of_unit(root, manifest_by_id, unit_id):
    """Normalized hash of the CANONICAL region at HEAD for a region unit. P3
    compares the consumer's claimed/recomputed hash against the canon currently
    in the tree (binding=follow-latest semantics). The deeper 'is the marker's
    pinned version still latest?' question is the cold loop's job (P8); resolving
    a pinned historical body is a P6 investigation item (see foot of file)."""
    rec = manifest_by_id.get(unit_id)
    if not rec:
        return None
    loc = rec.get("canonical_location")
    if not loc:
        return None
    abs_loc = os.path.join(root, loc)
    if not os.path.exists(abs_loc):
        return None
    body, _marker, _locator = extract_region(_read_text(abs_loc), unit_id)
    if body is None:
        return None
    return canon_norm_hash(body)


def _derive_granularity(kind):
    return KIND_GRANULARITY.get(kind)  # None => out of scope (e.g. governance-doc)


def _run_id(now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    return now.strftime("%Y%m%dT%H%M%SZ")


def scan(root, repo, commit, now=None):
    """Yield observation records (dicts) for the repo at root. P3 behavior:
    iterate manifest units; for each region unit, walk its consumers[] and emit a
    region observation per inlined instance; emit a whole-tool row per whole-tool
    unit. With empty consumers[] (pre-P6) only whole-tool rows are produced."""
    manifest_path = os.path.join(root, "governance", "state", "manifest.jsonl")
    records = []
    if os.path.exists(manifest_path):
        for raw in open(manifest_path, encoding="utf-8"):
            if raw.strip():
                records.append(json.loads(raw))
    by_id = {r["unit_id"]: r for r in records}

    run_id = _run_id(now)
    observed_at = (now or datetime.datetime.now(datetime.timezone.utc)).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    runtime = {
        "python": "%d.%d.%d" % sys.version_info[:3],
        "duckdb": "n/a",                # ADR 0016 F1 (DuckDB is P8-only)
        "scanner_version": SCANNER_VERSION,
    }

    def base(unit_id, kind, granularity, consumer, path):
        return {
            "schema_version": "1", "run_id": run_id, "observed_at": observed_at,
            "runtime": runtime, "repo": repo, "commit": commit,
            "unit_id": unit_id, "granularity": granularity, "kind": kind,
            "consumer": consumer, "path": path,
            "change_policy": by_id[unit_id].get("change_policy"),
            "binding_mode": by_id[unit_id].get("binding_mode"),
        }

    for rec in records:
        unit_id = rec["unit_id"]
        kind = rec.get("kind")
        gran = _derive_granularity(kind)
        if gran is None:
            continue  # out of this scanner's scope (e.g. governance-doc, ADR 0014)

        if gran == "whole-tool":
            # whole-tool null convention (baseline §4.4): no marker/hash, drift n/a.
            obs = base(unit_id, kind, "whole-tool",
                       consumer=unit_id, path=rec.get("canonical_location"))
            obs.update({
                "region_locator": None, "canonical_version": None,
                "canonical_hash_norm": None, "observed_hash_norm": None,
                "observed_hash_raw": None, "hash_what": None, "drift": "n/a",
            })
            yield obs
            continue

        # region unit: one observation per inlined consumer instance.
        canon_norm = canonical_norm_hash_of_unit(root, by_id, unit_id)
        for c in rec.get("consumers", []):
            consumer, cpath = c.get("consumer"), c.get("path")
            abs_path = os.path.join(root, cpath) if cpath else None
            obs = base(unit_id, kind, "region", consumer, cpath)
            if not abs_path or not os.path.exists(abs_path):
                # located the registration but not the file -> indeterminate (F4).
                obs.update(_unknown_region(canon_norm))
                yield obs
                continue
            body, marker, locator = extract_region(_read_text(abs_path), unit_id)
            if body is None:
                # malformed/absent marker pair -> indeterminate (F4 fallback).
                obs.update(_unknown_region(canon_norm))
                yield obs
                continue
            obs_norm = canon_norm_hash(body)
            obs_raw = hashlib.sha256(body.encode("utf-8")).hexdigest()
            policy = marker.get("policy")
            if policy == "forked":
                drift = "forked-frozen"        # frozen, not compared (§4.5)
            elif canon_norm is None:
                drift = "unknown"              # cannot resolve the canon side (F4)
            else:
                drift = "match" if obs_norm == canon_norm else "drift"
            obs.update({
                "region_locator": locator,
                "canonical_version": marker.get("version"),
                "canonical_hash_norm": canon_norm if canon_norm is not None else obs_norm,
                "observed_hash_norm": obs_norm,
                "observed_hash_raw": obs_raw,
                "hash_what": HASH_WHAT,
                "drift": drift,
            })
            yield obs


def _unknown_region(canon_norm):
    """F4 determinability fallback for a region instance that could not be
    resolved to a comparison result. region granularity requires non-null
    string hash fields, so emit sentinels; drift='unknown'."""
    return {
        "region_locator": "unresolved",
        "canonical_version": "unknown",
        "canonical_hash_norm": canon_norm if canon_norm is not None else "unknown",
        "observed_hash_norm": "unknown",
        "observed_hash_raw": "unknown",
        "hash_what": HASH_WHAT,
        "drift": "unknown",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=".")
    parser.add_argument("--repo", default="ai-generated-artifacts")
    parser.add_argument("--commit", default="WORKTREE")
    parser.add_argument("--out", default=None,
                        help="observations dir root (default: <root>/governance/state/observations)")
    parser.add_argument("--stdout", action="store_true",
                        help="print observations to stdout instead of writing files")
    args = parser.parse_args(argv)
    root = os.path.abspath(args.root)

    rows = list(scan(root, args.repo, args.commit))
    lines = [_canonical_line(r) for r in rows]

    if args.stdout:
        for line in lines:
            print(line)
    else:
        run_id = rows[0]["run_id"] if rows else _run_id()
        date = run_id[:4] + "-" + run_id[4:6] + "-" + run_id[6:8]
        out_root = args.out or os.path.join(root, "governance", "state",
                                            "observations")
        out_dir = os.path.join(out_root, "repo=%s" % args.repo, "date=%s" % date)
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, "run-%s.jsonl" % run_id)
        with open(out_path, "w", newline="\n") as handle:
            for line in lines:
                handle.write(line + "\n")
        print("wrote %d observation(s) -> %s"
              % (len(rows), os.path.relpath(out_path, root)))

    from collections import Counter
    counts = Counter(r["drift"] for r in rows)
    print("drift summary: %s" % dict(counts))
    return 0


if __name__ == "__main__":
    sys.exit(main())


# ===========================================================================
# P6-INVESTIGATION NOTES (deferred decisions; advisory scope, per the user).
# These are the points P3 cannot close on documents alone; each names WHAT to
# decide and HOW to investigate it at P6 (the scanner's first real run, once
# consumers carry vendored markers).
#
# (1) region_locator final form.
#     WHAT: the observation `region_locator` carries provenance for a region;
#       the schema permits "marker id / BEGIN-END / line span". P3 emits a
#       provisional "marker:<unit_id>@L<begin>-L<end>". The final form must be
#       stable enough to re-find a region across edits.
#     HOW (P6): inspect how vendored markers actually sit in real consumers
#       (Update-WindowsServerIso.ps1, Download-SpeakerDeck.ps1) - whether line
#       numbers drift run-to-run (they will, as consumers evolve), confirming a
#       symbol/context-anchored locator (e.g. marker unit_id + enclosing function
#       name) is preferable to a raw line span. Cross-check with ADR 0014 §4's
#       "locate $ks by symbol/context, not line number" precedent. Decide the
#       canonical locator grammar then.
#
# (2) drift="unknown" precise trigger conditions (ADR 0016 F4).
#     WHAT: P3 reserves `unknown` and emits it for (a) a registered consumer file
#       that is missing, and (b) a malformed/absent marker pair. The COMPLETE set
#       of indeterminate conditions is open.
#     HOW (P6): from real consumer scans, enumerate the failure modes that
#       actually occur - e.g. duplicate markers in one file, a marker whose
#       unit_id is not in the manifest, an unresolvable pinned canonical version
#       (binding=pin to a version no longer in the tree), a normalizer error.
#       Classify each as `unknown` vs a hard gate failure, and pin the list.
#
# (3) bash normalization profile.
#     WHAT: P3 ships only the `powershell` normalizer (ADR 0015). `bash-region`
#       units need a shell-appropriate normalizer (comments, line-continuations,
#       here-docs) before bash drift can be hashed.
#     HOW (P6/SPINE-2): when a 2nd bash consumer makes reference-code/bash/ real,
#       study ol-aws's shell idioms (build-ol-aws-ami.sh) to define the bash
#       profile, then add golden vectors for it (the same shared-test-contract
#       mechanism that pins the powershell profile). Until then, bash regions are
#       out of scope by construction (no bash canon home yet).
# ===========================================================================
