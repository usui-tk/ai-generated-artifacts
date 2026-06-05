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

# 16) front-matter provenance pin
check("front-matter missing keys -> finding",
      G.check_front_matter("---\ntitle: x\n---\nbody") != [])
check("front-matter with provenance keys -> pass",
      G.check_front_matter("---\ncanonical_source: governance/spec/powershell.md\ncanonical_version: 0.1.0\n---\nbody") == [])
check("no front-matter -> 0 findings", G.check_front_matter("# just a template\nbody") == [])

# ---- report ----
passed = sum(1 for _, ok in _checks if ok)
total = len(_checks)
for name, ok in _checks:
    if not ok:
        print("FAIL: %s" % name)
print("%d/%d checks passed" % (passed, total))
sys.exit(0 if passed == total else 1)
