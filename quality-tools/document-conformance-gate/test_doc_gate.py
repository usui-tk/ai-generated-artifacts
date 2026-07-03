#!/usr/bin/env python3
"""Self-contained tests for doc_gate.py (stdlib only). Run: python3 test_doc_gate.py"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import doc_gate as G  # noqa: E402

# Synthetic L1 (independent of the live doc-format.jsonl) covering each model.
L1 = {
    "readme.disclaimer": {"content_model": "common-fixed"},
    "spec.part-a.logging": {"content_model": "vendored"},
    "readme.parameters": {"content_model": "specific"},
    "readme.why-exists": {"content_model": "common-parameterized"},
    "contributing.body": {"content_model": "mixed"},
}

_checks = []


def check(name, cond):
    _checks.append((name, bool(cond)))


def _region(unit_id, version, h, policy, binding, body):
    return ("<!-- >>> CANONICAL unit_id=%s version=%s hash=%s policy=%s binding=%s >>> -->\n"
            "%s\n"
            "<!-- <<< CANONICAL unit_id=%s <<< -->\n" % (unit_id, version, h, policy, binding, body, unit_id))


def _write(text):
    fd, path = tempfile.mkstemp(suffix=".md")
    os.close(fd)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


# 1) norm-hash ignores HTML comments
b1 = "Line one.\n<!-- a FILL comment -->\nLine two."
b2 = "Line one.\nLine two."
check("norm-hash strips HTML comments", G.doc_region_norm_hash(b1) == G.doc_region_norm_hash(b2))

# 2) norm-hash collapses blank runs + trims trailing ws + is 16 hex
b3 = "alpha   \n\n\n\nbeta"
b4 = "alpha\n\nbeta"
h = G.doc_region_norm_hash(b3)
check("norm-hash collapses blanks + trims ws", h == G.doc_region_norm_hash(b4))
check("norm-hash is 16 lowercase hex", len(h) == 16 and all(c in "0123456789abcdef" for c in h))

# 3) unit_id -> L1 family strip
check("map strips powershell segment",
      G.map_unit_to_l1("spec.powershell.part-a.logging") == "spec.part-a.logging")
check("map strips bash segment",
      G.map_unit_to_l1("readme.bash.x") == "readme.x")
check("map leaves family-independent id intact",
      G.map_unit_to_l1("readme.disclaimer") == "readme.disclaimer")

# 4) parse: balanced pair, body captured
regs, errs = G.parse_markers(_region("readme.disclaimer", "0.1.0", "PENDING", "canonical", "follow-latest", "Body text here."))
check("parse balanced pair (1 region, 0 errors)", len(regs) == 1 and not errs)
check("parse captures body", regs and regs[0].body.strip() == "Body text here.")

# 5) parse: unclosed open -> error
_, e_open = G.parse_markers("<!-- >>> CANONICAL unit_id=x version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->\nbody")
check("parse flags unclosed open", any("never closed" in e for e in e_open))

# 6) parse: close unit_id mismatch -> error
mism = ("<!-- >>> CANONICAL unit_id=a version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->\nb\n"
        "<!-- <<< CANONICAL unit_id=b <<< -->\n")
_, e_mis = G.parse_markers(mism)
check("parse flags close/open unit_id mismatch", any("does not match" in e for e in e_mis))

# 7) parse: duplicate unit_id -> error
dup = (_region("dupe", "0.1.0", "PENDING", "canonical", "follow-latest", "x")
       + _region("dupe", "0.1.0", "PENDING", "canonical", "follow-latest", "y"))
_, e_dup = G.parse_markers(dup)
check("parse flags duplicate unit_id", any("duplicate region" in e for e in e_dup))

# 8) common-fixed with CORRECT hash -> 0 findings
body = "Canonical disclaimer text."
good = G.doc_region_norm_hash(body)
p = _write(_region("readme.disclaimer", "0.1.0", good, "canonical", "follow-latest", body))
check("common-fixed correct hash -> pass", G.check_file(p, L1, "f.md") == [])

# 9) common-fixed with WRONG hash -> drift finding
p = _write(_region("readme.disclaimer", "0.1.0", "0000000000000000", "canonical", "follow-latest", body))
check("common-fixed wrong hash -> drift", any("hash drift" in f for f in G.check_file(p, L1, "f.md")))

# 10) common-fixed PENDING -> needs-stamping finding
p = _write(_region("readme.disclaimer", "0.1.0", "PENDING", "canonical", "follow-latest", body))
check("common-fixed PENDING -> needs stamping", any("needs stamping" in f for f in G.check_file(p, L1, "f.md")))

# 11) vendored treated as hash (correct -> pass)
vbody = "Vendored Part A logging region."
p = _write(_region("spec.powershell.part-a.logging", "0.1.0", G.doc_region_norm_hash(vbody), "canonical", "follow-latest", vbody))
check("vendored correct hash -> pass (family-stripped membership)", G.check_file(p, L1, "f.md") == [])

# 12) structural (specific) policy=structural hash=NONE -> pass
p = _write(_region("readme.parameters", "0.1.0", "NONE", "structural", "follow-latest", "Project-specific parameters."))
check("structural specific NONE/structural -> pass", G.check_file(p, L1, "f.md") == [])

# 13) structural region carrying a hash instead of NONE -> finding
p = _write(_region("readme.why-exists", "0.1.0", "abcdef0123456789", "canonical", "follow-latest", "Why."))
fnd = G.check_file(p, L1, "f.md")
check("structural with non-NONE hash -> finding", any("expected hash=NONE" in f or "expected policy=structural" in f for f in fnd))

# 14) unit_id not in L1 -> membership finding
p = _write(_region("readme.nonexistent", "0.1.0", "PENDING", "canonical", "follow-latest", "x"))
check("unknown unit_id -> membership finding", any("does not exist" in f for f in G.check_file(p, L1, "f.md")))

# 15) stamp: PENDING common-fixed -> computed hash; structural -> NONE/structural
mixed_doc = (_region("readme.disclaimer", "0.1.0", "PENDING", "canonical", "follow-latest", body)
             + _region("readme.parameters", "0.1.0", "PENDING", "canonical", "follow-latest", "Params."))
p = _write(mixed_doc)
n, errs = G.stamp_file(p, L1)
after = G.check_file(p, L1, "f.md")
check("stamp resolves PENDING (>=2 changed, 0 residual findings)", n >= 2 and after == [])

# 16) front-matter doc-provenance pin (ADR 0019)
check("front-matter without doc-provenance -> finding",
      G.check_front_matter("---\ntitle: x\n---\nbody") != [])
_PROV = "---\ndoc-provenance:\n  layer-1-format: 1.0.0\n  layer-2-template: 1.0.0\n  rendered: 2026-06-06\n---\nbody"
check("front-matter with doc-provenance block -> pass", G.check_front_matter(_PROV) == [])
check("front-matter missing a doc-provenance key -> finding",
      any("missing key" in f for f in
          G.check_front_matter("---\ndoc-provenance:\n  layer-1-format: 1.0.0\n  rendered: 2026-06-06\n---\nb")))
check("no front-matter -> 0 findings", G.check_front_matter("# just a template\nbody") == [])

# ---- report ----
# --- C6: ADR<->SPEC cross-reference integrity (live corpus, ADR 0014 §4.10) ---
check("spec-anchor lowercases + hyphenates",
      G._spec_anchor("Machinery") == "machinery" and G._spec_anchor("Analysis layer") == "analysis-layer")
_fm = G._parse_adr_front_matter(
    '---\nid: 0009\nstatus: accepted\ngoverns: ["governance/SPEC.md \u00a7machinery"]\n'
    'supersedes: []\nsuperseded_by: null\n---\nbody')
check("front-matter parses governs list", _fm["governs"] == ["governance/SPEC.md \u00a7machinery"])
check("front-matter null list-field -> []", _fm["superseded_by"] == [])


def _mkroot(adrs, spec):
    root = tempfile.mkdtemp()
    os.makedirs(os.path.join(root, "governance", "adr"))
    for nm, txt in adrs.items():
        with open(os.path.join(root, "governance", "adr", nm), "w", encoding="utf-8") as fh:
            fh.write(txt)
    with open(os.path.join(root, "governance", "SPEC.md"), "w", encoding="utf-8") as fh:
        fh.write(spec)
    return root


def _adr(i, status="accepted", governs='["governance/SPEC.md \u00a7machinery"]', sup="[]", supby="null"):
    return ("---\nid: %s\nstatus: %s\ngoverns: %s\nsupersedes: %s\nsuperseded_by: %s\n---\nText.\n"
            % (i, status, governs, sup, supby))


# SPEC with a direct back-ref (0009) and one inside a ## subsection (0010) to exercise level-aware bodies
_SPEC = ("# SPEC\n\n## Machinery\n\nGoverned by [ADR 0009](./adr/0009.md).\n\n"
         "### Sub thing\n\nGoverned by [ADR 0010](./adr/0010.md).\n\n## Other\n\nbody\n")
check("C6 clean corpus -> 0 findings",
      G.check_adr_spec_xref(_mkroot({"0009.md": _adr("0009"), "0010.md": _adr("0010")}, _SPEC)) == [])
check("C6 level-aware: back-ref in ## subsection is in-scope",
      not any("0010" in f for f in
              G.check_adr_spec_xref(_mkroot({"0009.md": _adr("0009"), "0010.md": _adr("0010")}, _SPEC))))
check("C6 catches §Machinery casing drift (F5)",
      any("0009" in f and "canonical anchor" in f for f in
          G.check_adr_spec_xref(_mkroot({"0009.md": _adr("0009", governs='["governance/SPEC.md \u00a7Machinery"]')}, _SPEC))))
check("C6 catches missing bidirectional back-ref",
      any("0099" in f and "back-reference" in f for f in
          G.check_adr_spec_xref(_mkroot({"0099.md": _adr("0099")}, _SPEC))))
check("C6 catches superseded ADR still live in SPEC",
      any("0009" in f and "superseded" in f for f in
          G.check_adr_spec_xref(_mkroot({"0009.md": _adr("0009", status="superseded")}, _SPEC))))
check("C6 catches asymmetric supersedes/superseded_by",
      any("asymmetric" in f for f in
          G.check_adr_spec_xref(_mkroot({"0009.md": _adr("0009", sup='["0010"]'), "0010.md": _adr("0010")}, _SPEC))))
check("C6 governs=[] carve-out -> no finding for that ADR",
      not any("0005" in f for f in
              G.check_adr_spec_xref(_mkroot({"0005.md": _adr("0005", governs="[]")}, _SPEC))))
check("C6 catches governs path that does not exist",
      any("does not exist" in f for f in
          G.check_adr_spec_xref(_mkroot({"0012.md": _adr("0012", governs='["reference-code/nope/missing.ps1"]')}, _SPEC))))

# L3 reconstructed (ADR 0019 |7): provenance / bilingual lock-step / encoding / abs-link
_L3 = tempfile.mkdtemp()


def _wf3(rel, text, raw=False):
    p = os.path.join(_L3, rel)
    if raw:
        with open(p, "wb") as fh:
            fh.write(text)
    else:
        with open(p, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
    return rel


_wf3("README.md", _PROV + "\nSee [guide](https://example.com).\n")
_wf3("README.ja.md", _PROV + "\nガイドは [guide](https://example.com)。\n")
_wf3("SPEC.md", _PROV + "\nspec body\n")
check("L3 clean reconstructed set -> 0 findings",
      G.check_reconstructed(["README.md", "README.ja.md", "SPEC.md"], _L3) == [])
_wf3("NOFM.md", "no front matter here\n")
check("L3 missing provenance -> finding",
      any("missing YAML front-matter" in f for f in G.check_reconstructed(["NOFM.md"], _L3)))
_wf3("RELLINK.md", _PROV + "\nsee [agents](../AGENTS.md) and [adr](governance/adr/0014.md)\n")
check("L3 relative governance link -> finding",
      any("absolute URL" in f for f in G.check_reconstructed(["RELLINK.md"], _L3)))
_wf3("README.md", _PROV.replace("layer-2-template: 1.0.0", "layer-2-template: 2.0.0") + "\nx\n")
check("L3 bilingual lock-step mismatch -> finding",
      any("bilingual lock-step" in f for f in
          G.check_reconstructed(["README.md", "README.ja.md"], _L3)))
_wf3("CRLF.md", (_PROV + "\nx\n").replace("\n", "\r\n").encode("utf-8"), raw=True)
check("L3 CRLF -> finding",
      any("CRLF" in f for f in G.check_reconstructed(["CRLF.md"], _L3)))

# 21b) Derived L3 mode (ADR 0031): the file set derives from the manifest's
#      kind=project rows (maturity incubating+), pinned-*.md discovery.
import json as _json  # noqa: E402
_DRV = tempfile.mkdtemp()
os.makedirs(os.path.join(_DRV, "governance", "state"))
os.makedirs(os.path.join(_DRV, "projects", "alpha", "sub"))
os.makedirs(os.path.join(_DRV, "projects", "beta"))
os.makedirs(os.path.join(_DRV, "projects", "hollow"))


def _prow(uid, loc, mat):
    return _json.dumps({"schema_version": "1", "unit_id": uid,
                        "kind": "project", "canonical_location": loc,
                        "maturity": mat, "consumers": []})


def _wdrv(rel, text):
    p = os.path.join(_DRV, rel)
    with open(p, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


with open(os.path.join(_DRV, "governance", "state", "manifest.jsonl"), "w",
          encoding="utf-8", newline="") as fh:
    fh.write(_prow("project.alpha", "projects/alpha", "governed") + "\n")
    fh.write(_prow("project.beta", "projects/beta", "sandbox") + "\n")
_wdrv("projects/alpha/README.md", _PROV + "\nSee [g](https://example.com).\n")
_wdrv("projects/alpha/README.ja.md", _PROV + "\n\u30ac\u30a4\u30c9\u3002\n")
_wdrv("projects/alpha/sub/NOTES.md", _PROV + "\npinned subdir doc\n")
_wdrv("projects/alpha/RESULTS.md", "no front matter - stream-local artifact\n")
_wdrv("projects/beta/README.md", _PROV + "\nsandbox doc - exempt\n")
_files, _finds, _np = G.derive_reconstructed(_DRV)
check("derived L3: pinned *.md discovered (incl. subdir), unpinned excluded",
      _files == ["projects/alpha/README.ja.md", "projects/alpha/README.md",
                 "projects/alpha/sub/NOTES.md"] and _finds == [])
check("derived L3: sandbox project rows are exempt (ADR 0024 gate table)",
      _np == 1 and not any("beta" in f for f in _files))
check("derived L3 end-to-end: main() with no FILE args scans the derived set",
      G.main(["--root", _DRV, "--reconstructed"]) == 0)
with open(os.path.join(_DRV, "governance", "state", "manifest.jsonl"), "a",
          encoding="utf-8", newline="") as fh:
    fh.write(_prow("project.hollow", "projects/hollow", "governed") + "\n")
_files2, _finds2, _np2 = G.derive_reconstructed(_DRV)
check("derived L3: covered project with zero pinned docs -> finding "
      "(the old zero-file-PASS footgun is closed)",
      _np2 == 2 and any("project.hollow" in f for f in _finds2)
      and G.main(["--root", _DRV, "--reconstructed"]) == 1)

# 22) C9 version coupling (ADR 0022) - closes the proven spec-region hole
_UNITS = {"spec.powershell.part-a": {"unit_id": "spec.powershell.part-a",
                                     "kind": "spec-region",
                                     "canonical_version": "1.0.0"}}
_VOK = _region("spec.powershell.part-a.logging", "1.0.0",
               G.doc_region_norm_hash("Body."), "canonical", "follow-latest", "Body.")
p = _write(_VOK)
check("C9 follow-latest equal -> pass",
      G.check_file(p, L1, "f.md", _UNITS) == [])
_VNG = _region("spec.powershell.part-a.logging", "0.1.0",
               G.doc_region_norm_hash("Body."), "canonical", "follow-latest", "Body.")
p = _write(_VNG)
check("C9 follow-latest mismatch -> version-coupling finding (the 2026-06-11 hole)",
      any("version coupling broken" in f for f in G.check_file(p, L1, "f.md", _UNITS)))
check("C9 without a manifest map (units=None) -> no coupling finding",
      G.check_file(p, L1, "f.md", None) == [] and G.check_file(p, L1, "f.md") == [])
_VPINLAG = _region("spec.powershell.part-a.logging", "0.1.0",
                   G.doc_region_norm_hash("Body."), "canonical", "pin", "Body.")
p = _write(_VPINLAG)
check("C9 pin lagging behind manifest -> pass (a pin may lag)",
      G.check_file(p, L1, "f.md", _UNITS) == [])
_VPINAHEAD = _region("spec.powershell.part-a.logging", "2.0.0",
                     G.doc_region_norm_hash("Body."), "canonical", "pin", "Body.")
p = _write(_VPINAHEAD)
check("C9 pin ahead of manifest -> finding (a pin may lag, never lead)",
      any("exceeds the manifest" in f for f in G.check_file(p, L1, "f.md", _UNITS)))
_VUNREG = _region("readme.disclaimer", "0.1.0",
                  G.doc_region_norm_hash("Body."), "canonical", "follow-latest", "Body.")
p = _write(_VUNREG)
check("C9 unit_id with no registered manifest prefix -> skipped (template-internal L1 marker)",
      G.check_file(p, L1, "f.md", _UNITS) == [])

passed = sum(1 for _, ok in _checks if ok)
total = len(_checks)
for name, ok in _checks:
    if not ok:
        print("FAIL: %s" % name)
print("%d/%d checks passed" % (passed, total))
sys.exit(0 if passed == total else 1)
