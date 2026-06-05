#!/usr/bin/env python3
"""Document-conformance gate (TF e).

Implements the ADR 0020 doc-region contract over the documentation doc-set
(the spec home and the doc-set templates):

  * doc-region normalized hash for the VERBATIM-CANONICAL content models
    (common-fixed, vendored): strip HTML comments -> LF -> trim trailing
    whitespace -> collapse blank-line runs -> SHA-256 -> first 16 hex.
  * STRUCTURAL conformance (no hash pin) for common-parameterized / specific /
    mixed: marker present, unit_id resolves to a real L1 doc-format item,
    policy=structural, body non-empty.
  * marker coherence (open/close pairing + unit_id agreement, no duplicates).
  * L1 item-membership (marker unit_id maps to a real L1 item; family segment
    stripped: spec.powershell.part-a.X -> spec.part-a.X).
  * doc-level YAML front-matter provenance pin (ADR 0019), when present.

Design (ADR 0003): single-file, stdlib-only, no cross-reference. Tool boundary
(ADR 0020 step 4): this gate owns ALL doc-region inspection; the governance-state
validator and canon-hash-restamp are NOT extended to markdown.

Usage:
  doc_gate.py --root . [--check]     verify; exit 1 if any finding
  doc_gate.py --root . --stamp       rewrite hash=PENDING -> real / structural
  doc_gate.py --path FILE [...]      operate on explicit files instead of manifest
"""
import argparse
import hashlib
import json
import os
import re
import sys

FAMILIES = {"powershell", "bash", "python"}
HASH_MODELS = {"common-fixed", "vendored"}
STRUCTURAL_MODELS = {"common-parameterized", "specific", "mixed"}

_OPEN = re.compile(
    r"<!--\s*>>>\s*CANONICAL\s+unit_id=(?P<unit_id>\S+)\s+version=(?P<version>\S+)"
    r"\s+hash=(?P<hash>\S+)\s+policy=(?P<policy>\S+)\s+binding=(?P<binding>\S+)\s*>>>\s*-->"
)
_CLOSE = re.compile(r"<!--\s*<<<\s*CANONICAL\s+unit_id=(?P<unit_id>\S+)\s*<<<\s*-->")
_HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
_HEX16 = re.compile(r"^[0-9a-f]{16}$")
STRUCTURAL_SENTINEL = "NONE"


# ---- ADR 0020 step 1: doc-region normalized hash -------------------------------
def doc_region_norm_hash(body):
    """Normalized SHA-256 (first 16 hex) of a doc-region body per ADR 0020.

    (a) drop HTML comments (authoring notes / FILL / ASSEMBLE directives), then
    (b) collapse every run of whitespace - including newlines - to one space and
    strip, the same whitespace convention as the ADR 0015 code hash.
    """
    text = _HTML_COMMENT.sub("", body)                 # (a) drop HTML comments
    normalized = re.sub(r"\s+", " ", text).strip()     # (b) collapse all whitespace
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:16]


# ---- marker parsing + coherence ------------------------------------------------
class Region:
    __slots__ = ("unit_id", "version", "hash", "policy", "binding",
                 "body", "open_ln", "close_ln")

    def __init__(self, m, open_ln):
        self.unit_id = m["unit_id"]
        self.version = m["version"]
        self.hash = m["hash"]
        self.policy = m["policy"]
        self.binding = m["binding"]
        self.body = ""
        self.open_ln = open_ln
        self.close_ln = None


def parse_markers(text):
    """Return (regions, errors). Detects pairing, nesting and duplicate errors."""
    lines = text.split("\n")
    regions, errors, stack, seen = [], [], [], set()
    for i, ln in enumerate(lines, 1):
        mo = _OPEN.search(ln)
        if mo:
            if stack:
                errors.append("line %d: nested CANONICAL open (unit_id=%s) inside %s"
                              % (i, mo.group("unit_id"), stack[-1].unit_id))
            stack.append(Region(mo.groupdict(), i))
            continue
        mc = _CLOSE.search(ln)
        if mc:
            if not stack:
                errors.append("line %d: CANONICAL close (unit_id=%s) with no open"
                              % (i, mc.group("unit_id")))
                continue
            r = stack.pop()
            if mc.group("unit_id") != r.unit_id:
                errors.append("line %d: close unit_id=%s does not match open unit_id=%s"
                              % (i, mc.group("unit_id"), r.unit_id))
            r.close_ln = i
            r.body = "\n".join(lines[r.open_ln:i - 1])
            if r.unit_id in seen:
                errors.append("line %d: duplicate region unit_id=%s in file"
                              % (i, r.unit_id))
            seen.add(r.unit_id)
            regions.append(r)
    for r in stack:
        errors.append("line %d: CANONICAL open (unit_id=%s) never closed"
                      % (r.open_ln, r.unit_id))
    return regions, errors


# ---- L1 doc-format membership --------------------------------------------------
def load_l1(root):
    path = os.path.join(root, "governance", "doc-format", "doc-format.jsonl")
    items = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rec = json.loads(line)
                items[rec["item_id"]] = rec
    return items


def map_unit_to_l1(unit_id):
    """Strip a family segment (powershell|bash|python) to get the L1 item id."""
    return ".".join(seg for seg in unit_id.split(".") if seg not in FAMILIES)


# ---- front-matter provenance pin (ADR 0019) ------------------------------------
def check_front_matter(text):
    """If a doc carries YAML front-matter, require the ADR 0019 provenance pin."""
    if not text.startswith("---\n"):
        return []  # no front-matter (e.g. a template) -> nothing to check
    end = text.find("\n---", 4)
    if end == -1:
        return ["front-matter: opening '---' has no closing '---'"]
    block = text[4:end]
    keys = {ln.split(":", 1)[0].strip() for ln in block.split("\n") if ":" in ln}
    missing = [k for k in ("canonical_source", "canonical_version") if k not in keys]
    if missing:
        return ["front-matter: missing provenance key(s): %s" % ", ".join(missing)]
    return []


# ---- per-file check ------------------------------------------------------------
def check_file(path, l1, rel):
    findings = []
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    findings += ["%s: %s" % (rel, e) for e in check_front_matter(text)]
    regions, errors = parse_markers(text)
    findings += ["%s: %s" % (rel, e) for e in errors]
    for r in regions:
        l1_id = map_unit_to_l1(r.unit_id)
        item = l1.get(l1_id)
        if item is None:
            findings.append("%s: region unit_id=%s maps to L1 item '%s' which does not exist"
                            % (rel, r.unit_id, l1_id))
            continue
        cm = item["content_model"]
        if cm in HASH_MODELS:
            if r.policy != "canonical":
                findings.append("%s: %s is %s -> expected policy=canonical (got %s)"
                                % (rel, r.unit_id, cm, r.policy))
            want = doc_region_norm_hash(r.body)
            if r.hash == "PENDING":
                findings.append("%s: %s hash=PENDING (needs stamping; expected %s)"
                                % (rel, r.unit_id, want))
            elif not _HEX16.match(r.hash):
                findings.append("%s: %s hash=%s is not a 16-hex doc-region hash"
                                % (rel, r.unit_id, r.hash))
            elif r.hash != want:
                findings.append("%s: %s hash drift (marker=%s computed=%s)"
                                % (rel, r.unit_id, r.hash, want))
        elif cm in STRUCTURAL_MODELS:
            if r.policy != "structural":
                findings.append("%s: %s is %s -> expected policy=structural (got %s)"
                                % (rel, r.unit_id, cm, r.policy))
            if r.hash != STRUCTURAL_SENTINEL:
                findings.append("%s: %s is structural -> expected hash=%s (got %s)"
                                % (rel, r.unit_id, STRUCTURAL_SENTINEL, r.hash))
            if r.body.strip() == "":
                findings.append("%s: %s structural region body is empty" % (rel, r.unit_id))
        else:
            findings.append("%s: %s L1 content_model=%s is not classified by ADR 0020"
                            % (rel, r.unit_id, cm))
    return findings


# ---- stamp ---------------------------------------------------------------------
def stamp_file(path, l1):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    regions, errors = parse_markers(text)
    if errors:
        return 0, errors
    changed = 0
    for r in regions:
        item = l1.get(map_unit_to_l1(r.unit_id))
        if item is None:
            continue
        cm = item["content_model"]
        if cm in HASH_MODELS:
            new_hash, new_policy = doc_region_norm_hash(r.body), "canonical"
        elif cm in STRUCTURAL_MODELS:
            new_hash, new_policy = STRUCTURAL_SENTINEL, "structural"
        else:
            continue
        if r.hash != new_hash or r.policy != new_policy:
            old = ("<!-- >>> CANONICAL unit_id=%s version=%s hash=%s policy=%s binding=%s >>> -->"
                   % (r.unit_id, r.version, r.hash, r.policy, r.binding))
            new = ("<!-- >>> CANONICAL unit_id=%s version=%s hash=%s policy=%s binding=%s >>> -->"
                   % (r.unit_id, r.version, new_hash, new_policy, r.binding))
            if old in text:
                text = text.replace(old, new, 1)
                changed += 1
    if changed:
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
    return changed, []


# ---- file discovery via manifest -----------------------------------------------
def discover_files(root):
    mpath = os.path.join(root, "governance", "state", "manifest.jsonl")
    paths = []
    with open(mpath, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if rec.get("kind") in ("template", "spec-region"):
                loc = rec.get("canonical_location")
                if loc and loc.endswith(".md"):
                    paths.append(loc)
    return sorted(set(paths))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Document-conformance gate (ADR 0020).")
    ap.add_argument("--root", default=".")
    ap.add_argument("--stamp", action="store_true",
                    help="rewrite hash=PENDING -> real (canonical) / NONE (structural)")
    ap.add_argument("--path", nargs="*", default=None,
                    help="explicit files (relative to --root); default: manifest md units")
    args = ap.parse_args(argv)
    root = args.root
    l1 = load_l1(root)
    rels = args.path if args.path is not None else discover_files(root)

    if args.stamp:
        total = 0
        for rel in rels:
            n, errs = stamp_file(os.path.join(root, rel), l1)
            total += n
            for e in errs:
                print("STAMP-SKIP %s: %s" % (rel, e))
            if n:
                print("stamped %d region(s) in %s" % (n, rel))
        print("doc-gate: stamped %d region(s) across %d file(s)." % (total, len(rels)))
        return 0

    findings = []
    for rel in rels:
        findings += check_file(os.path.join(root, rel), l1, rel)
    if findings:
        for f in findings:
            print("FINDING: " + f)
        print("doc-gate: %d finding(s) across %d file(s)." % (len(findings), len(rels)))
        return 1
    print("doc-gate: PASS - 0 findings across %d file(s)." % len(rels))
    return 0


if __name__ == "__main__":
    sys.exit(main())
