#!/usr/bin/env python3
"""reference-health-gate: offline reference-integrity gate for the Layer-0 root docs.

The G3(a) deliverable (ADR 0026). Restructurings (directory moves, workflow renames)
had accumulated silent residue in the Layer-0 root documents - dead CI badges pointing
at deleted workflow filenames, broken relative links, stale location text - because
every existing gate scopes itself to manifest-registered units (doc_gate) or
reference-code (validator/scanner): the root docs sat in a verification blind spot.
This gate closes it with three offline, machine-decidable checks:

  R1. relative link targets  - every relative Markdown link/image target in a scoped
                               file resolves to an existing repo path (fragments (#...)
                               stripped; absolute http(s)/mailto links out of scope).
  R2. workflow references    - every referenced GitHub Actions workflow filename
                               (matched in `.github/workflows/<name>.yml` paths AND in
                               `actions/workflows/<name>.yml` badge/action URLs, which
                               are absolute URLs but decidable offline by filename)
                               exists under .github/workflows/.
  R5. STATUS currency probe  - inside STATUS.md's two current-truth zones (the
                               `| Current phase |` table row and the `Gates green`
                               paragraph) every "<N> rows" / "<N> manifest rows" claim
                               equals the ACTUAL manifest.jsonl row count. This is the
                               single-fact machine probe for the index==body failure
                               class (2026-07-02: the table said 83 while the header
                               narrative said 84). Historical zones (History /
                               Phase-progress / prose) are deliberately NOT probed.

Scope (D7): the repo-root `*.md` files + `.github/*.md`. Project-level docs are owned
by doc_gate (--path/--reconstructed) and the per-project streams; ALL-md scanning was
rejected as a false-positive source (e.g. forensic history legitimately cites retired
paths). Prose path staleness in scoped files is likewise out of gate scope (not
machine-decidable against forensic/history text) - named as a review-owned limitation
in governance/gate-coverage.md.

Runtime: python3 stdlib only. Exit 0 when no findings, 1 otherwise.

Usage:
    python3 refcheck.py [--root <repo-root>]
"""

import argparse
import glob
import json
import os
import re
import sys

# Relative Markdown link/image target: ](<target>) where target carries no scheme.
# The capture stops at ')', whitespace, or '#' (fragment); titles after a space are
# tolerated by construction.
_REL_LINK = re.compile(r"\]\((?!https?://|mailto:)([^)#\s]+)")
# A referenced workflow filename, in a repo path or an absolute badge/actions URL.
_WORKFLOW = re.compile(r"(?:\.github/workflows|actions/workflows)/([A-Za-z0-9_.\-]+\.ya?ml)")
# "<N> rows" / "<N> manifest rows" claims (markdown bold tolerated between parts).
_ROWS_CLAIM = re.compile(r"(\d+)(?:\*\*)?\s+(?:manifest\s+)?rows\b")

STATUS_REL = os.path.join("governance", "project-management", "STATUS.md")
MANIFEST_REL = os.path.join("governance", "state", "manifest.jsonl")


def scoped_files(root):
    """Layer-0 scope (D7): root *.md + .github/*.md, sorted, repo-relative."""
    paths = sorted(glob.glob(os.path.join(root, "*.md"))
                   + glob.glob(os.path.join(root, ".github", "*.md")))
    return [os.path.relpath(p, root) for p in paths]


def check_relative_links(root, rel, text):
    """R1: every relative link/image target resolves to an existing path."""
    findings = []
    base = os.path.dirname(os.path.join(root, rel))
    for target in _REL_LINK.findall(text):
        resolved = os.path.normpath(os.path.join(base, target))
        if not os.path.exists(resolved):
            findings.append("R1 %s: relative link target does not exist: %s"
                            % (rel, target))
    return findings


def check_workflow_refs(root, rel, text):
    """R2: every referenced workflow filename exists under .github/workflows/."""
    findings = []
    for name in sorted(set(_WORKFLOW.findall(text))):
        if not os.path.isfile(os.path.join(root, ".github", "workflows", name)):
            findings.append("R2 %s: referenced workflow does not exist: "
                            ".github/workflows/%s" % (rel, name))
    return findings


def _manifest_row_count(root):
    path = os.path.join(root, MANIFEST_REL)
    if not os.path.isfile(path):
        return None
    count = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                json.loads(line)  # malformed JSONL is the validator's finding; surface early
                count += 1
    return count


def _current_truth_zones(status_text):
    """Yield (zone_name, zone_text): the `| Current phase |` table row and the
    `Gates green` paragraph (up to the next blank line)."""
    lines = status_text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("| Current phase"):
            yield ("Current-phase row", line)
        if line.startswith("Gates green"):
            block = []
            for later in lines[i:]:
                if later.strip() == "":
                    break
                block.append(later)
            yield ("Gates-green paragraph", "\n".join(block))


def check_status_currency(root):
    """R5: row-count claims in STATUS's current-truth zones equal the manifest."""
    status_path = os.path.join(root, STATUS_REL)
    if not os.path.isfile(status_path):
        return []  # no STATUS (fixture roots): nothing to probe
    actual = _manifest_row_count(root)
    if actual is None:
        return []
    findings = []
    with open(status_path, encoding="utf-8") as handle:
        text = handle.read()
    for zone, zone_text in _current_truth_zones(text):
        for claim in _ROWS_CLAIM.findall(zone_text):
            if int(claim) != actual:
                findings.append("R5 %s: %s claims %s rows but manifest.jsonl has %d"
                                % (os.path.normpath(STATUS_REL).replace(os.sep, "/"),
                                   zone, claim, actual))
    return findings


def run(root, quiet=False):
    findings = []
    files = scoped_files(root)
    for rel in files:
        with open(os.path.join(root, rel), encoding="utf-8") as handle:
            text = handle.read()
        findings += check_relative_links(root, rel, text)
        findings += check_workflow_refs(root, rel, text)
    findings += check_status_currency(root)
    if not quiet:
        for finding in findings:
            print("FINDING: %s" % finding)
        if findings:
            print("\nrefcheck: FAIL - %d finding(s) across %d scoped file(s)."
                  % (len(findings), len(files)))
        else:
            print("refcheck: PASS - 0 findings across %d scoped file(s)."
                  % len(files))
    return findings


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Offline reference-integrity gate for the Layer-0 root docs "
                    "(ADR 0026).")
    parser.add_argument("--root", default=".", help="repo root (default: .)")
    args = parser.parse_args(argv)
    return 1 if run(args.root) else 0


if __name__ == "__main__":
    sys.exit(main())
