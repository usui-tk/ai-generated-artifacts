#!/usr/bin/env python3
"""T56: research-reference drift guard over current normative files (v2).

Mechanises the alignment-audit Phase 3 guard (finding family F-18 with
the recurrence-prevention clauses of F-03/F-05/F-07/F-12/F-14/F-15)
and, since the 2026-08-09 re-audit remediation, the re-audit's
recurrence clauses as well (R-01 through R-04, R-06 and the retired
CLI aliases of R-02): statement families that the remediation removed
from the current normative surface must not be reintroduced. The
guard scans only current normative files; it does not convert the
research report into executable policy, and it asserts nothing about
servicing behavior.

Why v2 exists (measured v1 defect, recorded honestly). The v1 scanner
matched patterns line by line against raw text. The 2026-08-09
re-audit then found a live stale norm in SPEC C.3.3 that v1 could not
see, for two measured reasons: the phrase wrapped across a hard line
break between its words, and inline code markup (backticks) sat
between words that the patterns joined with plain whitespace. v2
therefore scans NORMALIZED LOGICAL BLOCKS: Markdown paragraphs (and
PowerShell comment blocks) are joined into one string, code markup
characters are stripped, and whitespace runs are collapsed, before
any pattern is applied. Findings are attributed to the block's first
line. PowerShell code lines (non-comment) are still scanned line by
line with the v1 proximity window.

Scope. Scanned files: SPEC.md, README.md, README.ja.md, TESTING.md,
tests/README.md, and the main script (comments included). Excluded
from scanning entirely: CHANGELOG.md (history is preserved verbatim),
fixtures, and the research report itself. Excluded inside scanned
Markdown files: sections whose heading names them
Historical/Superseded, sections opening with a superseded Status
marker, and paragraphs opening with an emphasised
Superseded/Historical/Supersession label -- those regions preserve
the superseded record and are allowed to quote it.

Statement families rejected (audit finding in brackets):

  1. Server 2016 Setup-Dynamic-Update non-existence claims (F-03).
  2. Generation-based / by-design update-kind absence claims, and the
     retired Forbidden-Kind-axis phrasing of the P06 consistency
     check, in English or Japanese (F-04, re-audit R-01; the runtime
     enforces Required Kinds and state-driven integrity only).
  3. Stale research paths -- `research/windows-servicing` without the
     `documents/` prefix (F-02).
  4. Digest-as-primary-key claims, cross-surface or Catalog (F-07).
  5. Universal boot.wim no-LCU claims (F-05). The bare phrase
     "structurally impossible" counts only when boot.wim appears in
     the same block (the script uses the phrase legitimately about
     derived-value staleness).
  6. PCA2023 boot-manager "re-sign" claims, English or Japanese (F-12).
  7. Universal WinRE no-LCU claims (F-05/F-06 boundary, re-audit
     R-04): the "never ... LCU" phrasing counts only with WinRE in
     the same block, so that release-specific routing statements
     remain expressible.
  8. Universal digest-mandatory claims (F-08, re-audit R-01): the
     "non-empty digest for every line" phrasing, superseded by the
     state-driven B.19.2 table.

A retired-CLI-alias check (re-audit R-02) additionally rejects the
retired invocation aliases (the two former internal names for the
public -OsVersion / -OsLanguage parameters) anywhere in the Markdown
normative files. The main script is deliberately out of this check's
scope: its internal helper functions legitimately use those names as
private parameter identifiers.

A companion lightweight check pins the STAGE 3 trigger documentation
(F-14/F-15 recurrence prevention): the synthetic workflow's `on:`
triggers must be exactly `workflow_dispatch`, and the TESTING.md
"Current trigger" paragraph must state the dispatch-only status.
Either surface changing alone trips this test.

Every pattern family, the alias check and every exclusion rule is
first proven against built-in synthetic samples (including
wrapped-phrase and markup-split positives reproducing the measured
v1 miss) so a scanner regression cannot turn the repository scan
vacuous silently.

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

# The retired-alias check runs over the Markdown normative files only
# (see the docstring for why the script is excluded).
ALIAS_CHECK_TARGETS = tuple(t for t in SCAN_TARGETS if t.endswith(".md"))

STAGE3_WORKFLOW = (
    ".github/workflows/"
    "projects__powershell-update-windows-server-iso__stage3__synthetic.yml"
)

# Proximity window (lines either side) for compound patterns on
# PowerShell CODE lines; block scope is used everywhere else.
CONTEXT_WINDOW = 5

# "\u518d\u7f72\u540d" is the Japanese noun for the retired re-sign
# claim (README.ja counterpart of family 6); kept as an escape so the
# test source stays ASCII.
RESIGN_JA = "\u518d\u7f72\u540d"

# "\u5fc5\u9808/\u7981\u6b62 Kind" is the Japanese rendering of the
# retired required/forbidden-Kind phrasing (README.ja counterpart of
# the family-2 Forbidden-axis sub-pattern); kept as escapes likewise.
FORBID_KINDS_JA = "\u5fc5\u9808/\u7981\u6b62\\s*Kind"

# family id -> (label, [simple regexes], [compound (pattern, qualifier)])
# Patterns are applied to NORMALIZED block text (markup stripped,
# whitespace collapsed) for blocks, and to raw lines for PowerShell
# code lines. A compound pattern produces a finding only when the
# qualifier also matches the same block (or the proximity window, for
# PowerShell code lines).
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
        RESIGN_JA,
    ], []),
    ("F7-winre-universal-no-lcu", [], [
        (r"(?i)never\s+(?:receives?\s+)?an?\s+LCU", r"(?i)winre"),
    ]),
    ("F8-universal-digest-mandatory", [
        r"(?i)non-empty\s+Digest",
    ], []),
)

RETIRED_ALIAS_RE = re.compile(r"-OsKey\b|-OsLang\b")

HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
STATUS_SUPERSEDED_RE = re.compile(r"(?i)\*\*status\*\*.*superseded")
PARA_LABEL_RE = re.compile(
    r"^\s*>?\s*\*{1,2}[^*\n]*?(?i:superseded|supersession|historical)")


def normalize(text):
    """Strip code/emphasis markup and collapse whitespace runs."""
    text = text.replace("`", "").replace("*", "")
    return re.sub(r"\s+", " ", text).strip()


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


def markdown_blocks(lines, mask):
    """Yield (start_line_1based, normalized_paragraph_text) for every
    non-excluded Markdown paragraph."""
    n = len(lines)
    i = 0
    while i < n:
        if lines[i].strip():
            j = i
            while j < n and lines[j].strip():
                j += 1
            if not mask[i]:
                yield i + 1, normalize("\n".join(lines[i:j]))
            i = j
        else:
            i += 1


def ps1_comment_blocks(lines):
    """Yield (start_line_1based, normalized_comment_block_text) for
    every contiguous run of comment lines in a PowerShell source."""
    n = len(lines)
    i = 0
    while i < n:
        if lines[i].lstrip().startswith("#"):
            j = i
            body = []
            while j < n and lines[j].lstrip().startswith("#"):
                body.append(lines[j].lstrip().lstrip("#"))
                j += 1
            yield i + 1, normalize("\n".join(body))
            i = j
        else:
            i += 1


def scan_block_text(start, text, findings):
    """Apply every family to one normalized block; append findings."""
    for family, simple, compound in FAMILIES:
        for pat in simple:
            if re.search(pat, text):
                findings.append((start, family, text[:70]))
        for pat, qualifier in compound:
            if re.search(pat, text) and re.search(qualifier, text):
                findings.append((start, family, text[:70]))


def scan_markdown(lines):
    mask = markdown_excluded(lines)
    findings = []
    for start, text in markdown_blocks(lines, mask):
        scan_block_text(start, text, findings)
    return findings, mask


def scan_ps1(lines):
    findings = []
    # comment blocks: normalized block scope (wrap-safe)
    for start, text in ps1_comment_blocks(lines):
        scan_block_text(start, text, findings)
    # code lines: raw line scope with the proximity window, so string
    # payloads are still covered without comment double-reporting
    for family, simple, compound in FAMILIES:
        for pat in simple:
            rx = re.compile(pat)
            for i, line in enumerate(lines):
                if line.lstrip().startswith("#"):
                    continue
                if rx.search(line):
                    findings.append((i + 1, family, line.strip()[:70]))
        for pat, qualifier in compound:
            rx = re.compile(pat)
            qx = re.compile(qualifier)
            for i, line in enumerate(lines):
                if line.lstrip().startswith("#"):
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
        findings, _mask = scan_markdown(lines)
        return findings
    return scan_ps1(lines)


def scan_retired_aliases(path: pathlib.Path):
    """Reject retired CLI aliases in a Markdown normative file."""
    lines = path.read_text(encoding="utf-8").split("\n")
    mask = markdown_excluded(lines)
    hits = []
    for i, line in enumerate(lines):
        if mask[i]:
            continue
        m = RETIRED_ALIAS_RE.search(line)
        if m:
            hits.append((i + 1, m.group(0), line.strip()[:70]))
    return hits


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
    "F8-universal-digest-mandatory":
        "every entry carries a non-empty Digest value",
}

# The measured v1 miss, reproduced: the phrase wraps across a line
# break AND backticks sit between the words. v2 must detect both
# families in this one paragraph.
SYNTHETIC_WRAPPED_POSITIVE = [
    "under the declared PatchModel each required Kind must be present, no forbidden",
    "`Kind` may appear, and each `Lines[]` row then carries a non-empty `Digest`.",
]

SYNTHETIC_F7_POSITIVE = [
    "NOT sent to WinRE here: WinRE stays serviced by",
    "SSU plus SafeOS DU, never an LCU.",
]

SYNTHETIC_F7_NEGATIVE = [
    "that lane never receives an LCU under the bridge",
    "ordering rule for install.wim.",
]

SYNTHETIC_F8_NEGATIVE = [
    "a pre-resolution line may legitimately carry no",
    "digest value yet under the state-driven table.",
]

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


def scan_md_sample(lines):
    findings, _ = scan_markdown(lines)
    return findings


def main():
    print("T56: research-reference drift guard (v2)")
    passed = failed = 0

    # -- machinery self-test: every simple family fires on its sample
    for family, sample in SYNTHETIC_POSITIVES.items():
        got = scan_md_sample([sample])
        hit = any(f[1] == family for f in got)
        passed, failed = check(
            f"machinery: family {family} detects its synthetic sample",
            hit, f"no finding from sample {sample!r}", passed, failed)

    # -- family-2 Forbidden-axis sub-patterns (English and Japanese)
    for sample in ("throws with the required/forbidden Kinds",
                   "the Forbidden Kinds for that model",
                   "\u5fc5\u9808/\u7981\u6b62 Kind \u3068\u5171\u306b"):
        got = scan_md_sample([sample])
        hit = any(f[1] == "F2-generation-based-absence" for f in got)
        passed, failed = check(
            "machinery: family F2 Forbidden-axis sub-pattern fires on "
            f"sample {sample[:30]!r}",
            hit, "no finding", passed, failed)

    # -- the measured v1 miss: wrapped + backtick-split phrase must now
    #    be seen by BOTH families in one normalized paragraph
    got = scan_md_sample(SYNTHETIC_WRAPPED_POSITIVE)
    fams = {f[1] for f in got}
    passed, failed = check(
        "machinery: wrapped/markup-split phrase detected by family F2",
        "F2-generation-based-absence" in fams,
        f"families seen {sorted(fams)!r}", passed, failed)
    passed, failed = check(
        "machinery: wrapped/markup-split phrase detected by family F8",
        "F8-universal-digest-mandatory" in fams,
        f"families seen {sorted(fams)!r}", passed, failed)

    # -- family 7: WinRE qualifier required
    got = scan_md_sample(SYNTHETIC_F7_POSITIVE)
    passed, failed = check(
        "machinery: family F7 fires with WinRE in the block",
        any(f[1] == "F7-winre-universal-no-lcu" for f in got),
        "compound pattern did not fire", passed, failed)
    got = scan_md_sample(SYNTHETIC_F7_NEGATIVE)
    passed, failed = check(
        "machinery: family F7 stays silent without WinRE",
        not any(f[1] == "F7-winre-universal-no-lcu" for f in got),
        f"unexpected findings {got!r}", passed, failed)

    # -- family 7 on a PowerShell comment block (wrap-safe path)
    got = scan_ps1(["    # " + SYNTHETIC_F7_POSITIVE[0],
                    "    # " + SYNTHETIC_F7_POSITIVE[1]])
    passed, failed = check(
        "machinery: family F7 fires across a wrapped ps1 comment block",
        any(f[1] == "F7-winre-universal-no-lcu" for f in got),
        "comment-block join did not detect", passed, failed)

    # -- family 8: state-driven wording is NOT a finding
    got = scan_md_sample(SYNTHETIC_F8_NEGATIVE)
    passed, failed = check(
        "machinery: family F8 stays silent on state-driven wording",
        not any(f[1] == "F8-universal-digest-mandatory" for f in got),
        f"unexpected findings {got!r}", passed, failed)

    # -- family 5 compound: fires with boot.wim context, silent without
    got = scan_md_sample(SYNTHETIC_COMPOUND_POSITIVE)
    passed, failed = check(
        "machinery: bare-phrase family 5 fires with boot.wim in block",
        any(f[1] == "F5-universal-bootwim-no-lcu" for f in got),
        "compound pattern did not fire", passed, failed)
    got = scan_md_sample(SYNTHETIC_COMPOUND_NEGATIVE)
    passed, failed = check(
        "machinery: bare-phrase family 5 stays silent without boot.wim",
        not got, f"unexpected findings {got!r}", passed, failed)

    # -- retired-alias machinery: positives flagged, publics not
    tmp = SUBPROJECT_ROOT / "tests"
    alias_pos = RETIRED_ALIAS_RE.search("-OsKey Server2019") is not None
    alias_pos2 = RETIRED_ALIAS_RE.search("-OsLang ja-jp") is not None
    alias_neg = RETIRED_ALIAS_RE.search(
        "-OsVersion Server2019 -OsLanguage ja-jp") is None
    passed, failed = check(
        "machinery: retired-alias regex flags both retired aliases",
        alias_pos and alias_pos2, "retired alias not flagged",
        passed, failed)
    passed, failed = check(
        "machinery: retired-alias regex accepts the public parameters",
        alias_neg, "public parameter falsely flagged", passed, failed)

    # -- exclusion rules on the synthetic document
    lines = SYNTHETIC_EXCLUSION_DOC
    mask = markdown_excluded(lines)
    got = scan_md_sample(lines)
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

    # -- retired-alias scan over the Markdown normative files
    for rel in ALIAS_CHECK_TARGETS:
        target = SUBPROJECT_ROOT / rel
        if not target.is_file():
            continue
        hits = scan_retired_aliases(target)
        detail = "; ".join(
            f"line {ln} {tok} {snip!r}" for ln, tok, snip in hits[:6])
        passed, failed = check(
            f"alias: {rel} carries no retired CLI alias",
            not hits, detail or "hits present", passed, failed)

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
