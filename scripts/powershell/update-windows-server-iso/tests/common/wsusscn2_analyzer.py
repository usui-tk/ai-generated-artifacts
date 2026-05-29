"""wsusscn2_analyzer - schema-discovery helper for wsusscn2 package.xml.

This module exists to give the test infrastructure a stable surface for
inspecting a real ``wsusscn2.cab`` Master XML without coupling the
PowerShell production parser (``ConvertFrom-OfflineSyncPackage`` in
``Update-WindowsServerIso.ps1``) to it. The analyzer is **not** a parity
reference for the production parser; that role belongs to
``wsusscn2_fixture_builder.py``. Instead, the analyzer offers:

- **Two-step 7-Zip extraction** of ``package.xml`` from ``wsusscn2.cab``
  via ``subprocess`` (Linux container friendly). Mirrors the production
  Stage 2 pipeline (SPEC §B.19.9.1) but is implementation-independent.
- **Tag-count census** over the Master XML for parity with Phase 5 v4
  observations (``<Update>``, ``<SupersededBy>``, ``<FileLocation>``,
  ``<Title>`` / ``<Description>`` / ``<MoreInfoUrl>`` = 0).
- **Category GUID frequency** by ``<Category Type="...">`` value, used
  to discover the script-scope tables that populate
  ``$Script:OfflineSyncOsCategoryGuids`` / ``$Script:OfflineSyncCategoryGuidNameMap``
  / ``$Script:OfflineSyncUpdateClassificationGuids`` (SPEC §B.19.7).
- **Update sampling** by classification / family / SupersededBy
  presence, used by the fixture builder to pick representative
  entries for the committed fixture.
- **Microsoft-prose verification** (SPEC §B.19.8) -- the hard-rule
  check that none of the human-readable tags appear in the Master XML.

The analyzer is standard-library-only and pip-install-free, matching
the existing ``tests/common/`` convention (see ``__init__.py``).

Run as a CLI for quick exploration::

    python3 -m tests.common.wsusscn2_analyzer extract /path/to/wsusscn2.cab /tmp/work
    python3 -m tests.common.wsusscn2_analyzer summary /tmp/work/stage2/package.xml
    python3 -m tests.common.wsusscn2_analyzer guids   /tmp/work/stage2/package.xml
    python3 -m tests.common.wsusscn2_analyzer prose   /tmp/work/stage2/package.xml
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional, Tuple


# Master XML uses an XML namespace; ElementTree's iterparse exposes it.
WSUSSCN_NS = "http://schemas.microsoft.com/msus/2004/02/OfflineSync"
NS = {"ms": WSUSSCN_NS}

# Microsoft-prose tags that SPEC §B.19.8 forbids from the layer-2 output.
# These are the tag names that, when grepped against the Master XML, MUST
# return zero hits -- the parser's whitelist design is then a redundancy on
# top of the source not even containing them.
MICROSOFT_PROSE_TAGS = (
    "<Title>",
    "<Description>",
    "<MoreInfoUrl>",
    "<SupportUrl>",
    "<ReleaseNotes>",
    "<MsrcSeverity>",
    "<KBArticleID>",  # KB number lives in <FileLocation> URL, not as a tag
)


@dataclass
class UpdateRecord:
    """A parsed <Update> element. Read by the analyzer; not committed to disk."""
    update_id: str
    revision_id: int
    revision_number: int
    is_bundle: bool
    is_leaf: bool
    deployment_action: Optional[str]
    creation_date: str
    prerequisites: List[str] = field(default_factory=list)        # UpdateId GUIDs
    superseded_by: List[int] = field(default_factory=list)         # RevisionId integers
    bundled_by: List[int] = field(default_factory=list)            # RevisionId integers
    payload_file_ids: List[str] = field(default_factory=list)      # opaque File @Id
    categories: Dict[str, str] = field(default_factory=dict)       # Type -> GUID


@dataclass
class FileLocationRecord:
    """A parsed <FileLocation> element."""
    file_id: str
    url: str
    kb_id: Optional[str]      # extracted via kb(\d+) regex on the URL
    arch: Optional[str]       # extracted via the filename pattern


# URL pattern: ``...windows10.0-kb5087537-x64.cab`` -> kb='5087537', arch='x64'
# The KB number is lower-cased ``kb`` followed by digits in the path component.
_KB_RE = re.compile(r"kb(\d+)", re.IGNORECASE)
_ARCH_RE = re.compile(r"-(x64|x86|arm64)\b", re.IGNORECASE)


# ---------------------------------------------------------------------------
# Stage 2 reference: two-step 7-Zip extraction
# ---------------------------------------------------------------------------

def extract_package_xml(
    cab_path: Path,
    work_dir: Path,
    seven_zip: str = "7z",
) -> Path:
    """Extract ``package.xml`` from ``wsusscn2.cab`` via two-step 7-Zip.

    Mirrors the production parser's Stage 2 pipeline (SPEC §B.19.9.1) at
    the subprocess level. Uses two separate output directories to avoid
    the ``expand.exe`` self-overwrite class of failure documented in the
    research notes (§2.5).

    Parameters
    ----------
    cab_path : Path
        Path to the source ``wsusscn2.cab``.
    work_dir : Path
        Directory under which ``stage1/`` and ``stage2/`` are created.
    seven_zip : str, optional
        7-Zip binary name. Defaults to ``"7z"`` for Linux containers.

    Returns
    -------
    Path
        Absolute path to the extracted ``package.xml``.
    """
    cab_path = Path(cab_path).resolve()
    work_dir = Path(work_dir).resolve()
    if not cab_path.is_file():
        raise FileNotFoundError(f"wsusscn2.cab not found: {cab_path}")
    work_dir.mkdir(parents=True, exist_ok=True)

    stage1 = work_dir / "stage1"
    stage2 = work_dir / "stage2"
    stage1.mkdir(exist_ok=True)
    stage2.mkdir(exist_ok=True)

    # Stage 1: wsusscn2.cab -> package.cab
    subprocess.run(
        [seven_zip, "x", str(cab_path), f"-o{stage1}",
         "-ir!package.cab", "-y", "-bsp0", "-bso0"],
        check=True,
    )
    inner_cab = stage1 / "package.cab"
    if not inner_cab.is_file():
        raise RuntimeError(f"Stage 1 produced no package.cab in {stage1}")

    # Stage 2: package.cab -> package.xml
    subprocess.run(
        [seven_zip, "x", str(inner_cab), f"-o{stage2}",
         "-ir!package.xml", "-y", "-bsp0", "-bso0"],
        check=True,
    )
    pkg_xml = stage2 / "package.xml"
    if not pkg_xml.is_file():
        raise RuntimeError(f"Stage 2 produced no package.xml in {stage2}")
    return pkg_xml


# ---------------------------------------------------------------------------
# Tag-count census (substring count over the raw text)
# ---------------------------------------------------------------------------

def tag_count_summary(package_xml: Path) -> Dict[str, int]:
    """Count selected tag occurrences over the Master XML.

    Operates on the raw file text using ``str.count`` -- this is faster and
    simpler than streaming-parsing when we only need totals. The counts are
    intended for the Phase 5 v4 parity check (``<Update>`` ~= 136,102,
    ``<SupersededBy>`` ~= 14,059, ``<FileLocation>`` ~= 97,051) and for the
    Microsoft-prose hard-rule check (those tags should all be 0).
    """
    text = Path(package_xml).read_text(encoding="utf-8")
    targets = list(MICROSOFT_PROSE_TAGS) + [
        "<Update ",
        "<Prerequisites>",
        "<SupersededBy>",
        "<BundledBy>",
        "<PayloadFiles>",
        "<FileLocation ",
        "<Categories>",
        "<Category ",
    ]
    return {tag: text.count(tag) for tag in targets}


def microsoft_prose_check(package_xml: Path) -> Dict[str, int]:
    """SPEC §B.19.8 hard-rule check: prose tags must not appear.

    Returns
    -------
    Dict[str, int]
        Mapping from tag name to occurrence count. A passing check is one
        where every value is 0.
    """
    text = Path(package_xml).read_text(encoding="utf-8")
    return {tag: text.count(tag) for tag in MICROSOFT_PROSE_TAGS}


# ---------------------------------------------------------------------------
# Streaming iter: <Update> and <FileLocation>
# ---------------------------------------------------------------------------

def iter_updates(package_xml: Path) -> Iterator[UpdateRecord]:
    """Stream-parse <Update> elements via ElementTree.iterparse.

    Uses ``iterparse(events=("end",))`` so memory stays low even on the
    full 108 MB Master XML; each element is cleared after yielding.
    """
    pkg = Path(package_xml)
    # Strip namespace from tag names for ergonomic comparisons. Each
    # element's .tag is "{...}Update"; we slice to "Update".
    for _, elem in ET.iterparse(str(pkg), events=("end",)):
        if not elem.tag.endswith("}Update") and elem.tag != "Update":
            continue
        # Local-name match without namespace stripping cost: compare suffix.
        if not (elem.tag.endswith("}Update") or elem.tag == "Update"):
            elem.clear()
            continue
        rec = _parse_update_element(elem)
        if rec is not None:
            yield rec
        # Free this element's memory now that it has been yielded.
        elem.clear()


def _parse_update_element(elem: ET.Element) -> Optional[UpdateRecord]:
    """Translate an <Update> ET.Element into an UpdateRecord."""
    rid_str = elem.get("RevisionId")
    if rid_str is None:
        return None
    try:
        rid = int(rid_str)
    except ValueError:
        return None
    rec = UpdateRecord(
        update_id=elem.get("UpdateId", ""),
        revision_id=rid,
        revision_number=int(elem.get("RevisionNumber", "0")),
        is_bundle=(elem.get("IsBundle", "false").lower() == "true"),
        is_leaf=(elem.get("IsLeaf", "false").lower() == "true"),
        deployment_action=elem.get("DeploymentAction"),
        creation_date=elem.get("CreationDate", ""),
    )
    for child in elem:
        tag = _localname(child.tag)
        if tag == "Prerequisites":
            for u in child:
                if _localname(u.tag) == "UpdateId":
                    gid = u.get("Id")
                    if gid:
                        rec.prerequisites.append(gid)
        elif tag == "SupersededBy":
            for r in child:
                if _localname(r.tag) == "Revision":
                    rid2 = r.get("Id")
                    if rid2 is not None:
                        try:
                            rec.superseded_by.append(int(rid2))
                        except ValueError:
                            pass
        elif tag == "BundledBy":
            for r in child:
                if _localname(r.tag) == "Revision":
                    rid2 = r.get("Id")
                    if rid2 is not None:
                        try:
                            rec.bundled_by.append(int(rid2))
                        except ValueError:
                            pass
        elif tag == "PayloadFiles":
            for f in child:
                if _localname(f.tag) == "File":
                    fid = f.get("Id")
                    if fid:
                        rec.payload_file_ids.append(fid)
        elif tag == "Categories":
            for c in child:
                if _localname(c.tag) == "Category":
                    typ = c.get("Type", "")
                    gid = c.get("Id", "")
                    if typ and gid:
                        rec.categories[typ] = gid
        # All other child tags (Languages, ...) are intentionally ignored
        # -- this implements the whitelist parsing pattern (SPEC §B.19.8).
    return rec


def iter_file_locations(package_xml: Path) -> Iterator[FileLocationRecord]:
    """Stream-parse <FileLocation> elements via ElementTree.iterparse."""
    for _, elem in ET.iterparse(str(Path(package_xml)), events=("end",)):
        if not (elem.tag.endswith("}FileLocation") or elem.tag == "FileLocation"):
            continue
        fid = elem.get("Id")
        url = elem.get("Url", "")
        if not fid or not url:
            elem.clear()
            continue
        kb_match = _KB_RE.search(url)
        arch_match = _ARCH_RE.search(url)
        rec = FileLocationRecord(
            file_id=fid,
            url=url,
            kb_id=kb_match.group(1) if kb_match else None,
            arch=arch_match.group(1).lower() if arch_match else None,
        )
        elem.clear()
        yield rec


def _localname(tag: str) -> str:
    """Strip the ``{namespace}`` prefix from an ElementTree tag name."""
    if "}" in tag:
        return tag.rsplit("}", 1)[1]
    return tag


# ---------------------------------------------------------------------------
# Category GUID census
# ---------------------------------------------------------------------------

def category_guid_frequency(
    package_xml: Path,
) -> Dict[str, Counter]:
    """Count Category GUIDs by Type.

    Returns
    -------
    Dict[str, Counter]
        Mapping from Category Type (e.g. ``"UpdateClassification"``,
        ``"Product"``, ``"ProductFamily"``, ``"Company"``) to a Counter
        of GUID strings to occurrence counts.
    """
    by_type: Dict[str, Counter] = {}
    for u in iter_updates(package_xml):
        for typ, guid in u.categories.items():
            by_type.setdefault(typ, Counter())[guid] += 1
    return by_type


# ---------------------------------------------------------------------------
# Sampling: pick representative Updates for fixture generation
# ---------------------------------------------------------------------------

def sample_representatives(
    package_xml: Path,
    classification_guids: Dict[str, str],
    product_family_guids: Dict[str, str],
    max_per_bucket: int = 2,
) -> Dict[str, List[UpdateRecord]]:
    """Sample a small representative subset of <Update> entries.

    Picks up to ``max_per_bucket`` entries per (classification, family)
    pair where the Categories block matches, **and** the Update is a
    Bundle (Bundle is the one that carries Categories). Also picks a
    handful of Standalone entries (per family) that are bundled by the
    sampled Bundles, so the fixture exercises the BundledBy/PayloadFiles
    join. Also tries to include at least one entry with non-empty
    <SupersededBy> per classification.

    Parameters
    ----------
    package_xml : Path
        Path to the Master XML.
    classification_guids : Dict[str, str]
        Mapping of canonical name (e.g. ``"LCU"``) to the GUID string
        the analyzer should treat as that classification.
    product_family_guids : Dict[str, str]
        Mapping of canonical name (e.g. ``"WindowsServer2016"``) to
        the ProductFamily GUID.
    max_per_bucket : int, optional
        Sampling cap per (classification, family) bucket.

    Returns
    -------
    Dict[str, List[UpdateRecord]]
        Keys: ``"bundles"``, ``"standalones"``, ``"superseded"``.
    """
    classification_lookup = {g: n for n, g in classification_guids.items()}
    family_lookup = {g: n for n, g in product_family_guids.items()}

    buckets: Dict[Tuple[str, str], List[UpdateRecord]] = {}
    superseded_pool: Dict[str, List[UpdateRecord]] = {}
    bundle_revision_ids: set[int] = set()
    standalones: List[UpdateRecord] = []

    # Pass 1: pick Bundles by (classification, family). Note bundle_revision_ids
    # for the Standalone pass.
    for u in iter_updates(package_xml):
        if not u.is_bundle:
            continue
        cls_guid = u.categories.get("UpdateClassification")
        fam_guid = u.categories.get("ProductFamily")
        if cls_guid not in classification_lookup:
            continue
        if fam_guid not in family_lookup:
            continue
        bucket_key = (classification_lookup[cls_guid], family_lookup[fam_guid])
        bucket = buckets.setdefault(bucket_key, [])
        if len(bucket) < max_per_bucket:
            bucket.append(u)
            bundle_revision_ids.add(u.revision_id)
        # Track up to one Superseded sample per classification
        if u.superseded_by:
            superseded_pool.setdefault(classification_lookup[cls_guid], []).append(u)

    # Pass 2: pick a few Standalone entries that point to the chosen Bundles.
    # Standalones don't carry Categories so we can't filter on family there.
    chosen_bundles = {b.revision_id for blist in buckets.values() for b in blist}
    standalone_limit_per_bundle = 2
    standalone_count_per_bundle: Dict[int, int] = {}
    for u in iter_updates(package_xml):
        if u.is_bundle:
            continue
        for parent in u.bundled_by:
            if parent in chosen_bundles:
                seen = standalone_count_per_bundle.get(parent, 0)
                if seen < standalone_limit_per_bundle:
                    standalones.append(u)
                    standalone_count_per_bundle[parent] = seen + 1
                break

    # Reduce superseded_pool to at most one per classification.
    superseded: List[UpdateRecord] = []
    for cls_name, pool in superseded_pool.items():
        if pool:
            superseded.append(pool[0])

    return {
        "bundles": [b for blist in buckets.values() for b in blist],
        "standalones": standalones,
        "superseded": superseded,
    }


# ---------------------------------------------------------------------------
# CLI entry point for manual exploration
# ---------------------------------------------------------------------------

def _cli() -> int:
    parser = argparse.ArgumentParser(
        description="wsusscn2.cab schema-discovery helper",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_extract = sub.add_parser("extract", help="Two-step 7-Zip extract to work_dir/")
    p_extract.add_argument("cab", help="Path to wsusscn2.cab")
    p_extract.add_argument("work", help="Work directory (will create stage1/stage2)")

    p_summary = sub.add_parser("summary", help="Tag-count summary")
    p_summary.add_argument("xml", help="Path to package.xml")

    p_guids = sub.add_parser("guids", help="Category GUID frequency by Type")
    p_guids.add_argument("xml", help="Path to package.xml")
    p_guids.add_argument("--top", type=int, default=10, help="Show top N GUIDs per Type")

    p_prose = sub.add_parser("prose", help="Microsoft-prose absence check (SPEC §B.19.8)")
    p_prose.add_argument("xml", help="Path to package.xml")

    args = parser.parse_args()

    if args.cmd == "extract":
        pkg = extract_package_xml(Path(args.cab), Path(args.work))
        print(f"Extracted: {pkg}  ({pkg.stat().st_size:,} bytes)")
        return 0

    if args.cmd == "summary":
        counts = tag_count_summary(Path(args.xml))
        for tag, n in counts.items():
            print(f"  {tag:25s} {n:>10,}")
        return 0

    if args.cmd == "guids":
        freq = category_guid_frequency(Path(args.xml))
        for typ in sorted(freq.keys()):
            cnt = freq[typ]
            print(f"--- Type=\"{typ}\" ({sum(cnt.values()):,} entries, "
                  f"{len(cnt)} distinct GUIDs) ---")
            for guid, n in cnt.most_common(args.top):
                print(f"  {n:>8,}  {guid}")
            if len(cnt) > args.top:
                print(f"  ... ({len(cnt) - args.top} more GUIDs not shown)")
            print()
        return 0

    if args.cmd == "prose":
        counts = microsoft_prose_check(Path(args.xml))
        ok = all(n == 0 for n in counts.values())
        for tag, n in counts.items():
            print(f"  {tag:25s} {n}")
        print()
        print("PASS: no Microsoft prose tags in Master XML"
              if ok else "FAIL: Microsoft prose tags found!")
        return 0 if ok else 1

    return 2


if __name__ == "__main__":
    sys.exit(_cli())
