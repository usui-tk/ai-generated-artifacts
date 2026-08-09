#!/usr/bin/env python3
"""T56: research-reference drift guard over current normative files.

Mechanises the alignment-audit Phase 3 guard (finding family F-18 with
the recurrence-prevention clauses of F-03/F-05/F-07/F-12/F-14/F-15):
statement families that the 2026-08 research-alignment remediation
removed from the current normative surface must not be reintroduced.
The guard scans only current normative files and rejects known
superseded phrasings; it does not convert the research report into
executable policy, and it asserts nothing about servicing behavior.

Scope. Scanned files: SPEC.md, README.md, README.ja.md, TESTING.md,
tests/README.md, and the main script (comments included). Excluded
from scanning entirely: CHANGELOG.md (history is preserved verbatim),
fixtures, and the research report itself (it owns its superseded
record). Excluded inside scanned Markdown files: sections whose
heading names them Historical/Superseded, sections opening with a
superseded Status marker, and paragraphs opening with an emphasised
Superseded/Historical/Supersession label -- those regions exist to
preserve the superseded record and are allowed to quote it.

Statement families rejected (each anchored to the audit finding that
retired it):

  1. Server 2016 Setup-Dynamic-Update non-existence claims (F-03).
  2. Generation-based / by-design update-kind absence claims, and the
     retired Forbidden-Kind-axis phrasing of the P06 consistency check,
     in English or Japanese (F-04; the runtime enforces Required Kinds
     and state-driven integrity only).
  3. Stale research paths -- `research/windows-servicing` without the
     `documents/` prefix (F-02).
  4. Digest-as-primary-key claims, cross-surface or Catalog (F-07).
  5. Universal boot.wim no-LCU claims (F-05). The bare phrase
     "structurally impossible" is NOT sufficient: the script uses it
     legitimately about derived-value staleness, so that phrase only
     counts when boot.wim appears in the nearby context window.
  6. PCA2023 boot-manager "re-sign" claims, English or Japanese (F-12).

A companion lightweight check pins the STAGE 3 trigger documentation
(F-14/F-15 recurrence prevention): the synthetic workflow's `on:`
triggers are read from the workflow file and must be exactly
`workflow_dispatch`, and the TESTING.md "Current trigger" paragraph
must state the dispatch-only status. Either surface changing alone
trips this test, forcing the two to move together.

Every pattern family and every exclusion rule is first proven against
built-in synthetic samples (the machinery's own negative controls) so
that a silent regex or exclusion regression cannot turn the repository
scan vacuous.

Class: B (behaviour/structure pins over the documentation surface).

Run:  python3 tests/research_reference_drift_test.py
Deps: none (pure text scan; no pwsh, no network).
"""
from __future__ import annotations

import pathlib
import re
import sys

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO_ROOT = SUBPROJECT_ROOT.parent.parent

SCAN_TARGETS = (
    "SPEC.md",
    "README.md",
    "README.ja.md",
    "TESTING.md",
    "tests/README.md",
    "Update-WindowsServerIso.ps1",
)

STAGE3_WORKFLOW = (
    ".github/workflows/"
    "projects__powershell-update-windows-server-iso__stage3__synthetic.yml"
)

# Context window (lines either side) for compound patterns; also the
# proximity used for the boot.wim qualifier of family 5.
CONTEXT_WINDOW = 5

# "\u518d\u7f72\u540d" is the Japanese noun for the retired re-sign
# claim (README.ja counterpart of family 6); kept as an escape so the
# test source stays ASCII.
RESIGN_JA = "\u518d\u7f72\u540d"

# "\u5fc5\u9808/\u7981\u6b62 Kind" is the Japanese rendering of the
# retired required/forbidden-Kind phrasing (README.ja counterpart of
# the family-2 Forbidden-axis sub-pattern); kept as escapes likewise.
FORBID_KINDS_JA = "\u5fc5\u9808/\u7981\u6b62\\s*Kind"

# family id -> (label, [simple regexes], [compound regexes])
# A compound regex only produces a finding when the qualifier regex
# also matches within CONTEXT_WINDOW lines of the hit.
FAMILIES = (
    ("F1-2016-setupdu-absence", [
        r"(?i)no\s+Setup\s+Dynamic\s+Update",
        r"(?i)Setup\s+Dynamic\s+Update\s+(?:does\s+not|doesn'?t)\s+exist",
    ], []),
    ("F2-generation-based-absence", [
        r"(?i)by-design\s+absen",
        r"(?i)per-generation\s+absen",
        r"(?i)generation-based\s+absen",
        r"(?i)required\s*/\s*forbidden\s+Kinds?",
        r"(?i)forbidden\s+Kinds?",
        FORBID_KINDS_JA,
    ], []),
    ("F3-stale-research-path", [
        r"(?<!documents/)research/windows-servicing",
    ], []),
    ("F4-digest-primary-key", [
        r"(?i)cross-surface\s+primary\s+key",
        r"(?i)Catalog\s+primary\s+key",
    ], []),
    ("F5-universal-bootwim-no-lcu", [
        r"(?i)cannot\s+be\s+LCU-serviced",
    ], [
        (r"(?i)structurally\s+impossible", r"(?i)boot\.wim"),
    ]),
    ("F6-pca-resign", [
        r"(?i)\bre-sign",
        re.escape(RESIGN_JA),
    ], []),
)

HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
STATUS_SUPERSEDED_RE = re.compile(r"(?i)\*\*status\*\*.*superseded")
PARA_LABEL_RE = re.compile(
    r"^\s*>?\s*\*{1,2}[^*\n]*?(?i:superseded|supersession|historical)")


def markdown_excluded(lines):
    """Return a per-line exclusion mask for a Markdown file.

    A line is excluded when it belongs to (a) a section whose heading
    text contains Historical/Superseded, (b) a section whose first few
    non-blank body lines carry a superseded **Status** marker, or
    (c) a paragraph whose first line opens with an emphasised
    Superseded/Supersession/Historical label.
    """
    n = len(lines)
    mask = [False] * n

    headings = []
    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if m:
            headings.append((i, len(m.group(1)), m.group(2)))

    for idx, (start, level, text) in enumerate(headings):
        end = n
        for j, lvl, _t in headings[idx + 1:]:
            if lvl <= level:
                end = j
                break
        marked = ("superseded" in text.lower()
                  or "historical" in text.lower())
        if not marked:
            seen = 0
            for k in range(start + 1, end):
                if not lines[k].strip():
                    continue
                if STATUS_SUPERSEDED_RE.search(lines[k]):
                    marked = True
                    break
                seen += 1
                if seen >= 6:
                    break
        if marked:
            for k in range(start, end):
                mask[k] = True

    i = 0
    while i < n:
        if lines[i].strip():
            j = i
            while j < n and lines[j].strip():
                j += 1
            if PARA_LABEL_RE.match(lines[i]):
                for k in range(i, j):
                    mask[k] = True
            i = j
        else:
            i += 1
    return mask


def scan_lines(lines, mask):
    """Scan text lines against every family; return finding tuples."""
    findings = []
    for family, simple, compound in FAMILIES:
        for pat in simple:
            rx = re.compile(pat)
            for i, line in enumerate(lines):
                if mask[i]:
                    continue
                if rx.search(line):
                    findings.append((i + 1, family, line.strip()[:70]))
        for pat, qualifier in compound:
            rx = re.compile(pat)
            qx = re.compile(qualifier)
            for i, line in enumerate(lines):
                if mask[i]:
                    continue
                if not rx.search(line):
                    continue
                lo = max(0, i - CONTEXT_WINDOW)
                hi = min(len(lines), i + CONTEXT_WINDOW + 1)
                if any(qx.search(lines[k]) for k in range(lo, hi)):
                    findings.append((i + 1, family, line.strip()[:70]))
    return findings


def scan_file(path: pathlib.Path):
    raw = path.read_bytes()
    text = raw.decode("utf-8-sig", errors="replace")
    lines = text.split("\n")
    if path.suffix.lower() in (".md", ".markdown"):
        mask = markdown_excluded(lines)
    else:
        mask = [False] * len(lines)
    return scan_lines(lines, mask)


def workflow_on_keys(text: str):
    """Extract the top-level trigger keys of the workflow `on:` block."""
    lines = text.split("\n")
    keys = []
    in_on = False
    for line in lines:
        if line.rstrip() == "on:":
            in_on = True
            continue
        if in_on:
            if line.strip() and not line.startswith(" "):
                break
            m = re.match(r"^  ([A-Za-z_][A-Za-z0-9_]*):", line)
            if m:
                keys.append(m.group(1))
    return keys


# ---------------------------------------------------------------------------
# Built-in machinery negative controls (synthetic samples).
# ---------------------------------------------------------------------------

SYNTHETIC_POSITIVES = {
    "F1-2016-setupdu-absence":
        "For Server 2016, no Setup Dynamic Update exists at all.",
    "F2-generation-based-absence":
        "the by-design absences per OS generation",
    "F3-stale-research-path":
        "see research/windows-servicing/notes for details",
    "F4-digest-primary-key":
        "the Digest is the cross-surface primary key",
    "F5-universal-bootwim-no-lcu":
        "boot.wim cannot be LCU-serviced at all",
    "F6-pca-resign":
        "the phase re-signs the boot manager",
}

SYNTHETIC_COMPOUND_POSITIVE = [
    "servicing boot.wim with the update is",
    "structurally impossible for every release",
]

SYNTHETIC_COMPOUND_NEGATIVE = [
    "deriving the value at every write makes",
    "staleness structurally impossible here",
]

SYNTHETIC_EXCLUSION_DOC = [
    "## Kept model (historical)",
    "",
    "boot.wim cannot be LCU-serviced at all",
    "",
    "## Current model",
    "",
    "**Status**: **superseded at r12.00 -- retained as history.**",
    "",
    "the Digest is the cross-surface primary key",
    "",
    "# Live section",
    "",
    "*Superseded rationale note.* no Setup Dynamic Update exists",
    "for that generation, said the retired contract.",
    "",
    "documents/research/windows-servicing is the current path",
]


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def main():
    print("T56: research-reference drift guard")
    passed = failed = 0

    # -- machinery self-test: every family fires on its synthetic sample
    for family, sample in SYNTHETIC_POSITIVES.items():
        got = scan_lines([sample], [False])
        hit = any(f[1] == family for f in got)
        passed, failed = check(
            f"machinery: family {family} detects its synthetic sample",
            hit, f"no finding from sample {sample!r}", passed, failed)

    # -- family-2 Forbidden-axis sub-patterns (English and Japanese)
    for sample in ("throws with the required/forbidden Kinds",
                   "the Forbidden Kinds for that model",
                   "\u5fc5\u9808/\u7981\u6b62 Kind \u3068\u5171\u306b"):
        got = scan_lines([sample], [False])
        hit = any(f[1] == "F2-generation-based-absence" for f in got)
        passed, failed = check(
            "machinery: family F2 Forbidden-axis sub-pattern fires on "
            f"sample {sample[:30]!r}",
            hit, "no finding", passed, failed)

    # -- compound qualifier: fires with boot.wim context, stays silent
    #    without it
    got = scan_lines(SYNTHETIC_COMPOUND_POSITIVE,
                     [False] * len(SYNTHETIC_COMPOUND_POSITIVE))
    passed, failed = check(
        "machinery: bare-phrase family 5 fires with boot.wim in context",
        any(f[1] == "F5-universal-bootwim-no-lcu" for f in got),
        "compound pattern did not fire", passed, failed)
    got = scan_lines(SYNTHETIC_COMPOUND_NEGATIVE,
                     [False] * len(SYNTHETIC_COMPOUND_NEGATIVE))
    passed, failed = check(
        "machinery: bare-phrase family 5 stays silent without boot.wim",
        not got, f"unexpected findings {got!r}", passed, failed)

    # -- exclusion rules on the synthetic document
    mask = markdown_excluded(SYNTHETIC_EXCLUSION_DOC)
    got = scan_lines(SYNTHETIC_EXCLUSION_DOC, mask)
    passed, failed = check(
        "machinery: Historical heading section is excluded",
        mask[2], "line under historical heading not masked",
        passed, failed)
    passed, failed = check(
        "machinery: superseded Status-marker section is excluded",
        mask[8], "line under superseded Status marker not masked",
        passed, failed)
    passed, failed = check(
        "machinery: emphasised Superseded paragraph label is excluded",
        mask[12] and mask[13],
        "labelled paragraph not fully masked", passed, failed)
    passed, failed = check(
        "machinery: documents/-prefixed research path is not a finding",
        not any(f[1] == "F3-stale-research-path" for f in got),
        f"prefixed path flagged: {got!r}", passed, failed)
    passed, failed = check(
        "machinery: synthetic document yields zero findings overall",
        not got, f"findings {got!r}", passed, failed)

    # -- repository scan: current normative files carry no superseded
    #    statement family
    for rel in SCAN_TARGETS:
        target = SUBPROJECT_ROOT / rel
        passed, failed = check(
            f"scan: {rel} present", target.is_file(), "file not found",
            passed, failed)
        if not target.is_file():
            continue
        findings = scan_file(target)
        detail = "; ".join(
            f"line {ln} [{fam}] {snip!r}" for ln, fam, snip in findings[:6])
        if len(findings) > 6:
            detail += f"; ... ({len(findings)} total)"
        passed, failed = check(
            f"scan: {rel} carries no superseded statement family",
            not findings, detail or "findings present", passed, failed)

    # -- STAGE 3 trigger documentation pin (F-14/F-15 recurrence guard)
    wf = REPO_ROOT / STAGE3_WORKFLOW
    passed, failed = check(
        "stage3: workflow file present", wf.is_file(),
        f"missing {STAGE3_WORKFLOW}", passed, failed)
    if wf.is_file():
        keys = workflow_on_keys(wf.read_text(encoding="utf-8"))
        passed, failed = check(
            "stage3: workflow triggers are exactly workflow_dispatch",
            keys == ["workflow_dispatch"],
            f"measured trigger keys {keys!r}", passed, failed)

    testing = SUBPROJECT_ROOT / "TESTING.md"
    para = None
    if testing.is_file():
        lines = testing.read_text(encoding="utf-8").split("\n")
        starts = [i for i, ln in enumerate(lines)
                  if "**Current trigger.**" in ln]
        passed, failed = check(
            "stage3: TESTING.md has exactly one Current-trigger paragraph",
            len(starts) == 1, f"{len(starts)} occurrence(s)",
            passed, failed)
        if len(starts) == 1:
            i = starts[0]
            j = i
            while j < len(lines) and lines[j].strip():
                j += 1
            para = " ".join(lines[i:j])
    if para is not None:
        passed, failed = check(
            "stage3: TESTING.md states the dispatch-only trigger",
            "workflow_dispatch" in para and "only" in para,
            f"paragraph reads {para[:100]!r}", passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, "
          f"{passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
