"""
wsusscn2 fixture builder for T12 (parser pipeline tests).

Generates a *minimal* package.xml that mirrors the REAL wsusscn2 Master
XML structure (verified empirically against the 2026-05-12 production
fetch) and exercises every control-flow path in the PowerShell Stage 3
parser (`ConvertFrom-OfflineSyncPackage`) and Stage 4 serializer
(`New-ServicingDependencyDatabase`).

Real wsusscn2 structure modelled here:
  * Updates carry NO KB article number (KB lives in the Catalog).
  * A BUNDLE update (IsBundle="true") carries the Product/Classification
    Categories but NO payload of its own.
  * LEAF updates (DeploymentAction="Bundle") carry the actual payload via
    <PayloadFiles><File Id="<digest>"/> and point UP at their bundle via
    <BundledBy><Revision Id="<bundle-revision-id>"/>.
  * <FileLocations><FileLocation Id="<digest>" Url="..."/> maps a payload
    digest to its download URL.
  * <SupersededBy><Revision Id="..."/> lists superseding revisions.
  * Microsoft prose tags (<Title>/<Description>/<MoreInfoUrl>) never
    appear; the parser's positive allowlist enforces their exclusion.

The fixture models:
  Bundle A  (Server 2022, SecurityUpdates, in-scope) rev=990001
            <- Leaf A1 (payload digest AAAA, resolves) bundledBy 990001
            <- Leaf A2 (payload digest BBBB, resolves) bundledBy 990001
  Bundle B  (Server 2025, SecurityUpdates, in-scope) rev=990003
            <- Leaf B1 (payload digest CCCC resolves + DDDD orphan) bundledBy 990003
  Bundle C  (Server 2025 Category, Evaluate) rev=990004  -> rejected (not a bundle scope match: no Classification)
  Bundle D  (Office product, SecurityUpdates, in-scope-by-class only) rev=990005 -> rejected (Product mismatch)
  Bundle E  (Server 2019, UpdateRollups, OLD 2022 date) rev=990006 -> rejected (recency)

Expected in-scope bundles: A (rev 990001) + B (rev 990003) = 2
  A.payloadUrls = [URL_AAAA, URL_BBBB]   (2 leaves resolve)
  B.payloadUrls = [URL_CCCC]             (DDDD is orphan -> omitted)

Usage:
    python3 -m tests.common.servicing_dependency_fixture_builder --out-dir tests/fixtures/servicing-dependency
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

# Canonical GUIDs (must match $Script:OfflineSyncOsCategoryGuids /
# $Script:OfflineSyncUpdateClassificationGuids in the PowerShell script).
GUID_SERVER_2016 = "569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5"
GUID_SERVER_2019 = "f702a48c-919b-45d6-9aef-ca4248d50397"
GUID_SERVER_2022 = "71718f13-7324-4b0f-8f9e-2ca9dc978e53"
GUID_SERVER_2025 = "b256987d-4693-4c87-955d-dbb9341205eb"

GUID_CLASS_SECURITY = "0fa1201d-4330-4fa8-8ae9-b877473b6441"
GUID_CLASS_ROLLUPS = "28bc880e-0592-4cbf-8f95-c79b17911d5f"

GUID_COMPANY_MICROSOFT = "56309036-4c77-4dd9-951a-99ee9c246a94"
GUID_FAMILY_WINDOWS = "6964aab4-c5b5-43bd-a17d-ffb4346a8e1d"

GUID_OFFICE = "477b856e-65c4-4473-b621-a8b230bb70d9"  # out-of-scope product

PINNED_NOW = "2026-05-28T00:00:00Z"

# Bundle revision ids (string integers, as in real wsusscn2)
_REV_BUNDLE_A = "990001"   # Server 2022 SecurityUpdates bundle (in-scope)
_REV_BUNDLE_B = "990003"   # Server 2025 SecurityUpdates bundle (in-scope)
_REV_CATEGORY = "990004"   # Server 2025 Category (Evaluate) - rejected
_REV_OFFICE   = "990005"   # Office bundle - rejected (product)
_REV_OLD      = "990006"   # Server 2019 old bundle - rejected (recency)

# Update ids (lowercase GUIDs)
_UID_BUNDLE_A = "f0000001-0000-0000-0000-000000000001"
_UID_LEAF_A1  = "f0000001-0000-0000-0000-0000000000a1"
_UID_LEAF_A2  = "f0000001-0000-0000-0000-0000000000a2"
_UID_BUNDLE_B = "f0000001-0000-0000-0000-000000000003"
_UID_LEAF_B1  = "f0000001-0000-0000-0000-0000000000b1"
_UID_CATEGORY = GUID_SERVER_2025
_UID_OFFICE   = "f0000001-0000-0000-0000-000000000005"
_UID_OLD      = "f0000001-0000-0000-0000-000000000006"

# Payload digests (sha1-base64-like opaque strings)
_DIGEST_A1 = "fixture-digest-aaaa"
_DIGEST_A2 = "fixture-digest-bbbb"
_DIGEST_B1 = "fixture-digest-cccc"
_DIGEST_ORPHAN = "fixture-digest-dddd"   # on Leaf B1 but absent from FileLocations

# Payload URLs
_URL_A1 = "http://example.invalid/fixture/server2022-lcu-part1.cab"
_URL_A2 = "http://example.invalid/fixture/server2022-lcu-part2.cab"
_URL_B1 = "http://example.invalid/fixture/server2025-lcu.cab"

# --- SSU -> LCU prerequisite scenario (Server 2016, separate model) ---------
# Models the real-world Server 2016 case where an LCU (catalogued as KB5087537)
# requires a separate servicing-stack update (SSU, KB5088064) as a prerequisite.
# When the provided servicing stack predates the SSU, the LCU install fails on a
# real host with CBS_E_NEW_SERVICING_STACK_REQUIRED (0x800f0823). This fixture
# lets the readiness gate predict that failure entirely offline on Linux. KB
# numbers live only in these comments / payload URLs - real wsusscn2 Updates
# never carry a KB article number. UpdateIds are synthetic (the f0000003-* block)
# and do not collide with the T12 fixture (f0000001-* / f0000002 unused).
_REV_SSU_BUNDLE = "991110"   # SSU bundle (Server 2016 SecurityUpdates, in-scope)
_REV_SSU_LEAF   = "991102"   # SSU leaf (revision < bundle, real wsusscn2 shape)
_REV_LCU_BUNDLE = "991120"   # LCU bundle (Server 2016 SecurityUpdates, in-scope)
_REV_LCU_LEAF   = "991104"   # LCU leaf (revision < bundle)
_UID_SSU_BUNDLE = "f0000003-0000-0000-0000-000000000001"
_UID_SSU_LEAF   = "f0000003-0000-0000-0000-0000000000a1"
_UID_LCU_BUNDLE = "f0000003-0000-0000-0000-000000000002"
_UID_LCU_LEAF   = "f0000003-0000-0000-0000-0000000000a2"
_DIGEST_SSU = "fixture-digest-ssu1"
_DIGEST_LCU = "fixture-digest-lcu1"
# KB number embedded in the payload URL so the readiness KB->update matcher
# (payloadUrls regex 'kb(\\d+)') can map a ResolvedPatch to the parsed update.
_URL_SSU = "http://example.invalid/fixture/windows10.0-kb5088064-x64.cab"
_URL_LCU = "http://example.invalid/fixture/windows10.0-kb5087537-x64.cab"


def _render_update(
    *,
    update_id: str,
    revision_id: str,
    revision_number: str,
    creation_date: str,
    is_bundle: bool = False,
    is_leaf: bool = True,
    deployment_action: str | None = None,
    categories: list[tuple[str, str]] | None = None,
    prerequisites: list[str] | None = None,
    superseded_by_revs: list[str] | None = None,
    bundled_by_revs: list[str] | None = None,
    payload_digests: list[str] | None = None,
) -> str:
    """Render a single <Update> element matching real wsusscn2 shape."""
    attrs = [
        f'CreationDate="{creation_date}"',
        'DefaultLanguage="en"',
        f'UpdateId="{update_id}"',
        f'RevisionNumber="{revision_number}"',
        f'RevisionId="{revision_id}"',
        f'IsLeaf="{str(is_leaf).lower()}"',
    ]
    if is_bundle:
        attrs.append('IsBundle="true"')
    if deployment_action:
        attrs.append(f'DeploymentAction="{deployment_action}"')

    children: list[str] = []
    if prerequisites:
        children.append('<Prerequisites>')
        for uid in prerequisites:
            children.append(f'<UpdateId Id="{uid}" />')
        children.append('</Prerequisites>')
    if categories:
        children.append('<Categories>')
        for ctype, cid in categories:
            children.append(f'<Category Type="{ctype}" Id="{cid}" />')
        children.append('</Categories>')
    if superseded_by_revs:
        children.append('<SupersededBy>')
        for rid in superseded_by_revs:
            children.append(f'<Revision Id="{rid}" />')
        children.append('</SupersededBy>')
    if bundled_by_revs:
        children.append('<BundledBy>')
        for rid in bundled_by_revs:
            children.append(f'<Revision Id="{rid}" />')
        children.append('</BundledBy>')
    if payload_digests:
        children.append('<PayloadFiles>')
        for d in payload_digests:
            children.append(f'<File Id="{d}" />')
        children.append('</PayloadFiles>')

    if not children:
        return f'<Update {" ".join(attrs)} />'
    return f'<Update {" ".join(attrs)}>{"".join(children)}</Update>'


def build_package_xml() -> str:
    """Construct the package.xml content as a Python str (no Microsoft prose)."""
    parts: list[str] = []
    parts.append('<?xml version="1.0" encoding="utf-8"?>')
    parts.append(
        '<OfflineSyncPackage xmlns="http://schemas.microsoft.com/msus/2004/02/OfflineSync"'
        ' MinimumClientVersion="5.8.0.2678"'
        ' PackageId="fixture-pkg-uuid"'
        ' ProtocolVersion="1.20"'
        ' SourceId="fixture-src-uuid">'
    )
    parts.append('<Updates>')

    # Bundle A: Server 2022 SecurityUpdates, in-scope (no payload of its own)
    parts.append(_render_update(
        update_id=_UID_BUNDLE_A, revision_id=_REV_BUNDLE_A, revision_number="100",
        creation_date="2026-04-15T10:00:00Z", is_bundle=True,
        categories=[
            ("Product", GUID_SERVER_2022),
            ("UpdateClassification", GUID_CLASS_SECURITY),
            ("Company", GUID_COMPANY_MICROSOFT),
            ("ProductFamily", GUID_FAMILY_WINDOWS),
        ],
        prerequisites=["abbc52a5-f900-4365-bde0-ca43667c25b3"],
        superseded_by_revs=["990099"],
    ))
    # Leaf A1: payload AAAA, bundledBy A
    parts.append(_render_update(
        update_id=_UID_LEAF_A1, revision_id="990011", revision_number="100",
        creation_date="2026-04-15T10:00:00Z", deployment_action="Bundle",
        bundled_by_revs=[_REV_BUNDLE_A], payload_digests=[_DIGEST_A1],
    ))
    # Leaf A2: payload BBBB, bundledBy A
    parts.append(_render_update(
        update_id=_UID_LEAF_A2, revision_id="990012", revision_number="100",
        creation_date="2026-04-15T10:00:00Z", deployment_action="Bundle",
        bundled_by_revs=[_REV_BUNDLE_A], payload_digests=[_DIGEST_A2],
    ))

    # Bundle B: Server 2025 SecurityUpdates, in-scope
    parts.append(_render_update(
        update_id=_UID_BUNDLE_B, revision_id=_REV_BUNDLE_B, revision_number="100",
        creation_date="2026-05-10T10:00:00Z", is_bundle=True,
        categories=[
            ("Product", GUID_SERVER_2025),
            ("UpdateClassification", GUID_CLASS_SECURITY),
        ],
    ))
    # Leaf B1: payload CCCC (resolves) + DDDD (orphan), bundledBy B
    parts.append(_render_update(
        update_id=_UID_LEAF_B1, revision_id="990013", revision_number="100",
        creation_date="2026-05-10T10:00:00Z", deployment_action="Bundle",
        bundled_by_revs=[_REV_BUNDLE_B], payload_digests=[_DIGEST_B1, _DIGEST_ORPHAN],
    ))

    # Category C: Server 2025 Category (Evaluate, no Classification) -> rejected
    parts.append(_render_update(
        update_id=_UID_CATEGORY, revision_id=_REV_CATEGORY, revision_number="50",
        creation_date="2024-10-01T18:44:45Z", is_bundle=False,
        deployment_action="Evaluate",
        prerequisites=[GUID_FAMILY_WINDOWS],
    ))

    # Bundle D: Office product (out-of-scope), SecurityUpdates -> rejected (product)
    parts.append(_render_update(
        update_id=_UID_OFFICE, revision_id=_REV_OFFICE, revision_number="100",
        creation_date="2026-04-15T10:00:00Z", is_bundle=True,
        categories=[
            ("Product", GUID_OFFICE),
            ("UpdateClassification", GUID_CLASS_SECURITY),
        ],
    ))

    # Bundle E: Server 2019 UpdateRollups but OLD (2022) -> rejected (recency)
    parts.append(_render_update(
        update_id=_UID_OLD, revision_id=_REV_OLD, revision_number="100",
        creation_date="2022-01-15T10:00:00Z", is_bundle=True,
        categories=[
            ("Product", GUID_SERVER_2019),
            ("UpdateClassification", GUID_CLASS_ROLLUPS),
        ],
    ))

    parts.append('</Updates>')

    # FileLocations: AAAA, BBBB, CCCC resolve; DDDD intentionally absent (orphan)
    parts.append('<FileLocations>')
    parts.append(f'<FileLocation Id="{_DIGEST_A1}" Url="{_URL_A1}" />')
    parts.append(f'<FileLocation Id="{_DIGEST_A2}" Url="{_URL_A2}" />')
    parts.append(f'<FileLocation Id="{_DIGEST_B1}" Url="{_URL_B1}" />')
    parts.append('</FileLocations>')

    parts.append('</OfflineSyncPackage>')
    return '\n'.join(parts) + '\n'


def build_ssu_prereq_package_xml() -> str:
    """Construct a package.xml modelling a Server 2016 SSU -> LCU prerequisite.

    Two in-scope Server 2016 bundles: an SSU (KB5088064) and an LCU (KB5087537)
    whose leaf declares the SSU bundle as a prerequisite. Feeding the produced
    Layer 2 DB through the servicing-stack populate step (CBS leaf
    leaf-2016-separate.xml -> requiredServicingStackVersion 10.0.14393.7692,
    model 'separate') and then Test-PatchServicingReadinessFromGraph reproduces
    the 0x800f0823 prediction (SsTooOld) entirely offline. No Microsoft prose.
    """
    parts: list[str] = []
    parts.append('<?xml version="1.0" encoding="utf-8"?>')
    parts.append(
        '<OfflineSyncPackage xmlns="http://schemas.microsoft.com/msus/2004/02/OfflineSync"'
        ' MinimumClientVersion="5.8.0.2678"'
        ' PackageId="fixture-ssu-prereq-uuid"'
        ' ProtocolVersion="1.20"'
        ' SourceId="fixture-src-uuid">'
    )
    parts.append('<Updates>')

    # SSU bundle (Server 2016 SecurityUpdates, in-scope) - the prerequisite.
    parts.append(_render_update(
        update_id=_UID_SSU_BUNDLE, revision_id=_REV_SSU_BUNDLE, revision_number="100",
        creation_date="2026-05-10T10:00:00Z", is_bundle=True,
        categories=[
            ("Product", GUID_SERVER_2016),
            ("UpdateClassification", GUID_CLASS_SECURITY),
        ],
    ))
    # SSU leaf: payload SSU, bundledBy SSU bundle.
    parts.append(_render_update(
        update_id=_UID_SSU_LEAF, revision_id=_REV_SSU_LEAF, revision_number="100",
        creation_date="2026-05-10T10:00:00Z", deployment_action="Bundle",
        bundled_by_revs=[_REV_SSU_BUNDLE], payload_digests=[_DIGEST_SSU],
    ))

    # LCU bundle (Server 2016 SecurityUpdates, in-scope) - requires the SSU.
    parts.append(_render_update(
        update_id=_UID_LCU_BUNDLE, revision_id=_REV_LCU_BUNDLE, revision_number="100",
        creation_date="2026-05-12T10:00:00Z", is_bundle=True,
        categories=[
            ("Product", GUID_SERVER_2016),
            ("UpdateClassification", GUID_CLASS_SECURITY),
        ],
    ))
    # LCU leaf: payload LCU, bundledBy LCU bundle, prerequisite = SSU bundle.
    parts.append(_render_update(
        update_id=_UID_LCU_LEAF, revision_id=_REV_LCU_LEAF, revision_number="100",
        creation_date="2026-05-12T10:00:00Z", deployment_action="Bundle",
        bundled_by_revs=[_REV_LCU_BUNDLE], payload_digests=[_DIGEST_LCU],
        prerequisites=[_UID_SSU_BUNDLE],
    ))

    parts.append('</Updates>')

    parts.append('<FileLocations>')
    parts.append(f'<FileLocation Id="{_DIGEST_SSU}" Url="{_URL_SSU}" />')
    parts.append(f'<FileLocation Id="{_DIGEST_LCU}" Url="{_URL_LCU}" />')
    parts.append('</FileLocations>')

    parts.append('</OfflineSyncPackage>')
    return '\n'.join(parts) + '\n'


def build_expected_output() -> dict[str, Any]:
    """Expected env-stripped parser output for the fixture above."""
    return {
        "_meta": {
            "scope": {
                "productGuids": [
                    GUID_SERVER_2016, GUID_SERVER_2019, GUID_SERVER_2022, GUID_SERVER_2025,
                ],
                "classificationGuids": [
                    GUID_CLASS_SECURITY, GUID_CLASS_ROLLUPS,
                    "68c5b0a3-d1a6-4553-ae49-01d3a7827828",
                    "e6cf1350-c01b-414d-a61f-263d14d133b4",
                    "cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83",
                ],
                "recencyMonths": 24,
                "now": PINNED_NOW,
            },
            "stats": {
                "updatesObserved": 8,
                "updatesInScope": 2,
                "bundlesObserved": 4,
                "categoryUpdates": 1,
                "leafUpdatesWithPayload": 3,
                "fileLocationsObserved": 3,
                "fileLocationsRetained": 3,
                "payloadDigestsOrphaned": 1,
            },
        },
        "updates": [
            {
                "updateId": _UID_BUNDLE_A,
                "revisionId": _REV_BUNDLE_A,
                "revisionNumber": "100",
                "creationDate": "2026-04-15T10:00:00Z",
                "isBundle": True,
                "isLeaf": True,
                "deploymentAction": None,
                "productGuids": [GUID_SERVER_2022],
                "classificationGuids": [GUID_CLASS_SECURITY],
                "companyGuids": [GUID_COMPANY_MICROSOFT],
                "productFamilyGuids": [GUID_FAMILY_WINDOWS],
                "prerequisiteUpdateIds": ["abbc52a5-f900-4365-bde0-ca43667c25b3"],
                "supersededByRevisionIds": ["990099"],
                "payloadFileDigests": [_DIGEST_A1, _DIGEST_A2],
                "payloadUrls": [_URL_A1, _URL_A2],
            },
            {
                "updateId": _UID_BUNDLE_B,
                "revisionId": _REV_BUNDLE_B,
                "revisionNumber": "100",
                "creationDate": "2026-05-10T10:00:00Z",
                "isBundle": True,
                "isLeaf": True,
                "deploymentAction": None,
                "productGuids": [GUID_SERVER_2025],
                "classificationGuids": [GUID_CLASS_SECURITY],
                "companyGuids": [],
                "productFamilyGuids": [],
                "prerequisiteUpdateIds": [],
                "supersededByRevisionIds": [],
                "payloadFileDigests": [_DIGEST_B1, _DIGEST_ORPHAN],
                "payloadUrls": [_URL_B1],
            },
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=Path("tests/fixtures/servicing-dependency"))
    parser.add_argument("--print-only", action="store_true")
    args = parser.parse_args()

    xml_text = build_package_xml()
    expected = build_expected_output()

    if args.print_only:
        sys.stdout.write(xml_text)
        return 0

    args.out_dir.mkdir(parents=True, exist_ok=True)
    xml_path = args.out_dir / "package.xml"
    json_path = args.out_dir / "expected-output.json"
    xml_path.write_bytes(xml_text.encode("utf-8"))

    from tests.common.canonical_json import save_canonical_json_file
    save_canonical_json_file(expected, json_path, depth=32)

    print(f"Wrote {xml_path} ({xml_path.stat().st_size:,} bytes)")
    print(f"Wrote {json_path} ({json_path.stat().st_size:,} bytes)")

    ssu_dir = args.out_dir / "ssu-prereq"
    ssu_dir.mkdir(parents=True, exist_ok=True)
    ssu_xml_path = ssu_dir / "package.xml"
    ssu_xml_path.write_bytes(build_ssu_prereq_package_xml().encode("utf-8"))
    print(f"Wrote {ssu_xml_path} ({ssu_xml_path.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
