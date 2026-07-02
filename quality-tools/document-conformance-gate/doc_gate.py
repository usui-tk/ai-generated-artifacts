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
  * doc-level YAML front-matter doc-provenance pin (ADR 0019: layer-1-format /
    layer-2-template / rendered), when present.
  * C6 ADR<->SPEC cross-reference integrity over the LIVE governance corpus
    (ADR 0014 §4.10): every accepted ADR's governs target resolves to a real
    SPEC.md section by its canonical (lowercase) anchor and that section
    back-references the ADR; superseded/deprecated ADRs are not live governing
    refs; supersedes/superseded_by are symmetric. governs=[] is a carve-out for
    process/meta ADRs. Runs on a full manifest verify (not for --path subsets).
  * C9 version coupling (ADR 0022): for a HASH-model doc-region whose unit_id
    resolves (longest dotted prefix) to a manifest doc-region unit, a
    binding=follow-latest marker's version= MUST equal that unit's manifest
    canonical_version; a binding=pin marker may lag but must never exceed it.
    Closes the proven 2026-06-11 spec-region promotion hole (a manifest-only
    version write passed every gate silently). Runs in both the default
    (manifest) mode and --path mode (consumer SPECs carry the vendored copies).

Design (ADR 0003): single-file, stdlib-only, no cross-reference. Tool boundary
(ADR 0020 step 4): this gate owns ALL doc-region inspection; the governance-state
validator and canon-hash-restamp are NOT extended to markdown.

Usage:
  doc_gate.py --root . [--check]     verify; exit 1 if any finding
  doc_gate.py --root . --stamp       rewrite hash=PENDING -> real / structural
  doc_gate.py --path FILE [...]      operate on explicit files instead of manifest
  doc_gate.py --reconstructed FILE [...]   L3 light structural conformance (ADR 0019 |7)
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


# ---- doc-provenance front-matter (ADR 0019) ------------------------------------
_DOC_PROV_KEYS = ("layer-1-format", "layer-2-template", "rendered")
# A governance-class link that is RELATIVE (not an absolute URL). Reconstructed /
# graduated doc-sets must point at governance docs by absolute URL so the link
# survives a cross-repo move (the relative->absolute rebinding policy).
_REL_GOV_LINK = re.compile(
    r"\]\(\s*(?!https?://)[^)]*?(?:AGENTS\.md|governance/|/adr/)[^)]*\)")


def _front_matter_block(text):
    """(block, error): block is None when the doc has no YAML front-matter."""
    if not text.startswith("---\n"):
        return None, None
    end = text.find("\n---", 4)
    if end == -1:
        return None, "front-matter: opening '---' has no closing '---'"
    return text[4:end], None


def _provenance_findings(block):
    """Validate the ADR 0019 doc-provenance block (doc-provenance: layer-1-format /
    layer-2-template / rendered). This replaces the earlier canonical_source /
    canonical_version keys, which did not match the ADR 0019 format."""
    keys = {ln.split(":", 1)[0].strip() for ln in block.split("\n") if ":" in ln}
    out = []
    if "doc-provenance" not in keys:
        out.append("front-matter has no 'doc-provenance:' block (ADR 0019)")
    missing = [k for k in _DOC_PROV_KEYS if k not in keys]
    if missing:
        out.append("doc-provenance missing key(s): %s" % ", ".join(missing))
    return out


def check_front_matter(text):
    """If a doc carries YAML front-matter, require the ADR 0019 doc-provenance pin.
    Marker-led L2 templates / the spec-home carry no front-matter -> no-op."""
    block, err = _front_matter_block(text)
    if err:
        return [err]
    if block is None:
        return []
    return ["front-matter: " + e for e in _provenance_findings(block)]


# ---- L3 reconstructed class-(B) doc-set: light structural conformance ----------
# ADR 0014/0019 |7: L1/L3 are governed by LIGHT structural conformance (provenance
# presence, bilingual README lock-step, encoding, governance-link absoluteness) - NOT
# the marker/hash machinery, which is vendored-region-only (ADR 0019 |88). A
# reconstructed class-(B) doc-set carries NO markers, so it is verified HERE rather
# than by the per-region check_file path.
def check_reconstructed(paths, root):
    findings = []
    prov_by_name = {}
    for rel in paths:
        with open(os.path.join(root, rel), "rb") as fh:
            raw = fh.read()
        if raw.startswith(b"\xef\xbb\xbf"):
            findings.append("%s: has a UTF-8 BOM (L3 docs are BOM-less)" % rel)
        if b"\r\n" in raw:
            findings.append("%s: contains CRLF (L3 docs use LF)" % rel)
        text = raw.decode("utf-8", "replace")
        block, err = _front_matter_block(text)
        if err:
            findings.append("%s: %s" % (rel, err))
        elif block is None:
            findings.append("%s: missing YAML front-matter doc-provenance block (ADR 0019)" % rel)
        else:
            findings += ["%s: %s" % (rel, e) for e in _provenance_findings(block)]
            prov_by_name[os.path.basename(rel)] = block
        for m in _REL_GOV_LINK.finditer(text):
            findings.append("%s: governance-class link must be an absolute URL "
                            "(cross-repo policy): %s" % (rel, m.group(0).strip()[:70]))
    if "README.md" in prov_by_name and "README.ja.md" in prov_by_name:
        if prov_by_name["README.md"] != prov_by_name["README.ja.md"]:
            findings.append("README.md / README.ja.md doc-provenance front-matter differ "
                            "(ADR 0019 bilingual lock-step)")
    return findings


# ---- per-file check ------------------------------------------------------------
def check_file(path, l1, rel, units=None):
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
            continue
        findings += check_version_coupling(r, item, units, rel)
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


# ---- C9: doc-region version coupling (ADR 0022) ---------------------------------
# The 2026-06-11 throwaway-clone experiment proved that NO gate coupled a
# doc-region marker's version= to the manifest canonical_version for the
# spec-region kind: `canon-manifest-tool update --version 1.0.0` on
# spec.powershell.part-a returned OK, validator A-G reported 0 findings and this
# gate PASSED, leaving manifest 1.0.0 vs 42 markers 0.1.0. The governance-state
# validator's D/G stay reference-code-scoped (ADR 0020), so this gate owns the
# doc-side coupling. Rule (ADR 0022): for a HASH-model region whose unit_id
# resolves to a manifest doc-region unit, binding=follow-latest -> marker
# version == manifest canonical_version; binding=pin -> marker version may lag
# but must not exceed it (the pin branch is encoded even though no doc-region
# uses pin today).
DOC_REGION_KINDS = ("spec-region",)


def load_manifest_units(root):
    """unit_id -> row for manifest units that own doc-regions. None when the
    manifest is absent (fixture / non-repo roots): C9 then degrades to a no-op."""
    mpath = os.path.join(root, "governance", "state", "manifest.jsonl")
    if not os.path.exists(mpath):
        return None
    units = {}
    with open(mpath, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rec = json.loads(line)
                if rec.get("kind") in DOC_REGION_KINDS:
                    units[rec["unit_id"]] = rec
    return units


def _resolve_unit(unit_id, units):
    """Longest dotted-prefix match: spec.powershell.part-a.logging resolves to
    the manifest row spec.powershell.part-a. None when no prefix is registered
    (e.g. template-internal L1 markers such as readme.disclaimer)."""
    segs = unit_id.split(".")
    for n in range(len(segs), 0, -1):
        cand = ".".join(segs[:n])
        if cand in units:
            return units[cand]
    return None


def _semver_tuple(v):
    try:
        return tuple(int(x) for x in v.split("."))
    except ValueError:
        return None


def check_version_coupling(region, item, units, rel):
    """C9 findings for one parsed region (already L1-resolved as `item`)."""
    if units is None or item["content_model"] not in HASH_MODELS:
        return []
    row = _resolve_unit(region.unit_id, units)
    if row is None:
        return []
    want = row["canonical_version"]
    have = region.version
    if region.binding == "follow-latest":
        if have != want:
            return ["%s: %s version coupling broken (marker=%s manifest=%s, "
                    "binding=follow-latest requires equality; ADR 0022)"
                    % (rel, region.unit_id, have, want)]
        return []
    if region.binding == "pin":
        ht, wt = _semver_tuple(have), _semver_tuple(want)
        if ht is None or wt is None:
            return ["%s: %s version not SemVer-comparable (marker=%s manifest=%s)"
                    % (rel, region.unit_id, have, want)]
        if ht > wt:
            return ["%s: %s pinned marker version exceeds the manifest "
                    "canonical_version (marker=%s manifest=%s; a pin may lag, "
                    "never lead; ADR 0022)" % (rel, region.unit_id, have, want)]
        return []
    return ["%s: %s unknown binding=%s (expected follow-latest|pin)"
            % (rel, region.unit_id, region.binding)]


# ---- C6: ADR <-> SPEC cross-reference integrity (LIVE corpus) ------------------
# TR-TPLCANON-3 C6 extended from templates to the live governance/adr/ +
# governance/SPEC.md corpus, implementing the baseline ADR 0014 §4.10 MANDATORY
# ADR<->SPEC integrity gate. doc_gate owns doc inspection (ADR 0020); the
# governance-state validator stays reference-code-scoped, so this check lives here.
_SPEC_REF = re.compile(r"governance/SPEC\.md\s+\u00a7(?P<anchor>\S+)")
_LIVE = ("accepted",)


def _parse_adr_front_matter(text):
    fm = {"id": None, "status": None, "governs": [], "supersedes": [], "superseded_by": []}
    if not text.startswith("---\n"):
        return fm
    end = text.find("\n---", 4)
    block = text[4:end] if end != -1 else text[4:]
    for ln in block.split("\n"):
        if ":" not in ln:
            continue
        key, val = ln.split(":", 1)
        key, val = key.strip(), val.strip()
        if key in ("id", "status"):
            fm[key] = val.strip('"').strip("'")
        elif key in ("governs", "supersedes", "superseded_by"):
            inner = val.strip()
            if inner.startswith("[") and inner.endswith("]"):
                fm[key] = [x.strip().strip('"').strip("'")
                           for x in inner[1:-1].split(",") if x.strip()]
            # else: null / ~ / empty / scalar -> leave as the [] default
    return fm


def _spec_anchor(header):
    """GitHub-style anchor for a heading: lowercase, drop punctuation, spaces -> hyphens."""
    h = re.sub(r"[^\w\s-]", "", header.strip().lower())
    return re.sub(r"\s+", "-", h)


def _load_spec_sections(root):
    """anchor -> section body, where a section spans its heading through the line
    before the next heading of the SAME-OR-HIGHER level (so '## Machinery' includes
    its '###' subsections, where governing back-references commonly live)."""
    with open(os.path.join(root, "governance", "SPEC.md"), encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    heads = []  # (line_idx, level, anchor)
    for i, ln in enumerate(lines):
        m = re.match(r"^(#{1,6})\s+(.*)$", ln)
        if m:
            heads.append((i, len(m.group(1)), _spec_anchor(m.group(2))))
    sections = {}
    for j, (idx, level, anchor) in enumerate(heads):
        end = len(lines)
        for k in range(j + 1, len(heads)):
            if heads[k][1] <= level:
                end = heads[k][0]
                break
        sections[anchor] = "\n".join(lines[idx:end])
    return sections


def check_adr_spec_xref(root):
    """ADR 0014 §4.10 integrity: governs-resolves, bidirectional back-ref,
    superseded-not-live, supersedes/superseded_by symmetry. governs=[] is a
    deliberate carve-out (process/meta ADRs that govern no SPEC section)."""
    findings = []
    adr_dir = os.path.join(root, "governance", "adr")
    if not os.path.isdir(adr_dir):
        return findings
    sections = _load_spec_sections(root)
    with open(os.path.join(root, "governance", "SPEC.md"), encoding="utf-8") as fh:
        spec_text = fh.read()
    adrs = {}
    for name in sorted(os.listdir(adr_dir)):
        if name.endswith(".md"):
            with open(os.path.join(adr_dir, name), encoding="utf-8") as fh:
                fm = _parse_adr_front_matter(fh.read())
            if fm["id"]:
                adrs[fm["id"]] = fm
    for aid, fm in sorted(adrs.items()):
        backref = re.compile(r"adr/0*%s\b|ADR\s+0*%s\b" % (aid.lstrip("0") or "0", aid.lstrip("0") or "0"))
        if fm["status"] in _LIVE:
            for tgt in fm["governs"]:                       # (1)+(2)
                m = _SPEC_REF.search(tgt)
                if m:
                    anchor = m.group("anchor")
                    if anchor not in sections:
                        findings.append("ADR %s: governs 'SPEC.md \u00a7%s' but no SPEC section "
                                        "has that canonical anchor (have: %s)"
                                        % (aid, anchor, ", ".join(sorted(sections))))
                    elif not backref.search(sections[anchor]):
                        findings.append("ADR %s: governs 'SPEC.md \u00a7%s' but that section does "
                                        "not back-reference the ADR (bidirectional link broken)"
                                        % (aid, anchor))
                else:
                    p = tgt.split("\u00a7")[0].strip()
                    if "/" in p and not os.path.exists(os.path.join(root, p)):
                        findings.append("ADR %s: governs path '%s' does not exist" % (aid, p))
        elif fm["status"] in ("superseded", "deprecated"):  # (3)
            if backref.search(spec_text):
                findings.append("ADR %s is %s but is still referenced by the live SPEC.md "
                                "(a superseded ADR must not be a current governing ref)"
                                % (aid, fm["status"]))
        for other in fm["supersedes"]:                      # (4)
            o = adrs.get(other)
            if o is None:
                findings.append("ADR %s supersedes unknown ADR %s" % (aid, other))
            elif aid not in o["superseded_by"]:
                findings.append("ADR %s supersedes %s but %s.superseded_by omits %s (asymmetric)"
                                % (aid, other, other, aid))
        for other in fm["superseded_by"]:
            o = adrs.get(other)
            if o is None:
                findings.append("ADR %s.superseded_by lists unknown ADR %s" % (aid, other))
            elif aid not in o["supersedes"]:
                findings.append("ADR %s.superseded_by lists %s but %s.supersedes omits %s (asymmetric)"
                                % (aid, other, other, aid))
    return findings


def main(argv=None):
    ap = argparse.ArgumentParser(description="Document-conformance gate (ADR 0020).")
    ap.add_argument("--root", default=".")
    ap.add_argument("--stamp", action="store_true",
                    help="rewrite hash=PENDING -> real (canonical) / NONE (structural)")
    ap.add_argument("--path", nargs="*", default=None,
                    help="explicit files (relative to --root); default: manifest md units")
    ap.add_argument("--reconstructed", nargs="*", default=None, metavar="FILE",
                    help="L3 light structural conformance over a reconstructed class-(B) "
                         "doc-set (ADR 0019 |7: provenance + bilingual lock-step + encoding "
                         "+ absolute governance links); files relative to --root")
    args = ap.parse_args(argv)
    root = args.root
    l1 = load_l1(root)
    rels = args.path if args.path is not None else discover_files(root)

    if args.reconstructed is not None:
        findings = check_reconstructed(args.reconstructed, root)
        n = len(args.reconstructed)
        if findings:
            for f in findings:
                print("FINDING: " + f)
            print("doc-gate: %d L3 finding(s) across %d file(s)." % (len(findings), n))
            return 1
        print("doc-gate: L3 PASS - 0 findings across %d file(s)." % n)
        return 0

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
    units = load_manifest_units(root)
    for rel in rels:
        findings += check_file(os.path.join(root, rel), l1, rel, units)
    if args.path is None:
        # C6: ADR<->SPEC integrity over the live corpus (ADR 0014 §4.10), run on a
        # full manifest verify (not when an explicit --path subset is given).
        findings += check_adr_spec_xref(root)
    if findings:
        for f in findings:
            print("FINDING: " + f)
        print("doc-gate: %d finding(s) across %d file(s)." % (len(findings), len(rels)))
        return 1
    print("doc-gate: PASS - 0 findings across %d file(s)." % len(rels))
    return 0


if __name__ == "__main__":
    sys.exit(main())
