#!/usr/bin/env python3
"""PoC dynamic_update, step 1: probe the Microsoft Update Catalog for
the Setup / Safe OS Dynamic Update packages for each in-scope OS.

Part of the r06 Phase 2 PoC tracked in
`docs/poc/poc-dynamic-update-report.md`.

This is PoC-F from the original Phase 2 plan. It answers:
  "Are Dynamic Update.Setup and Dynamic Update.SafeOs packages
   reliably discoverable via the Catalog using just the OS-aware
   query templates baked into r05.x, or do we need a different
   mechanism for Phase 3?"

Strategy:
  Hit Search.aspx with the canonical query strings that the
  production code uses (see Get-CatalogQueryTemplate in
  Update-WindowsServerIso.ps1). For each (OS x DU type) pair,
  record:
    - Number of search hits returned
    - Which hits passed the Title filter
    - Whether DownloadDialog returned at least one .cab / .msu

The PoC does NOT exercise Product / Description filtering --
those are server-side filters the Catalog applies only when the
user clicks an "Add to basket" dropdown. They are not part of
Search.aspx output. So this PoC is intentionally a stricter
test than production: production filters by Product after the
search; the PoC checks whether Title alone is enough.

Output: tests/fixtures/poc_dynamic_update/probe-results.json
"""
from __future__ import annotations

import json
import pathlib
import sys
import time
from dataclasses import asdict, dataclass, field

TESTS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR))
from common import catalog_client  # noqa: E402
from common import html_parsers  # noqa: E402

FIXTURE_DIR = TESTS_DIR / "fixtures" / "poc_dynamic_update"

# Same patch month used by the release-info PoC, so cross-check is easy
PATCH_MONTH = "2026-04"


@dataclass
class Probe:
    label: str
    os_short_name: str
    du_type: str  # 'DynamicUpdate.Setup' or 'DynamicUpdate.SafeOs'
    query: str
    title_substr: list  # any of these substrings, lowercase, must appear
    title_excludes: list = field(default_factory=list)  # exclusion tokens, lowercase


@dataclass
class ProbeResult:
    probe: dict
    search_hit_count: int = 0
    matching_hit_count: int = 0
    matching_hits: list = field(default_factory=list)
    chosen_update_id: str = ""
    chosen_title: str = ""
    download_url_count: int = 0
    file_names: list = field(default_factory=list)
    success: bool = False
    notes: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


def build_probes() -> list[Probe]:
    m = PATCH_MONTH
    probes: list[Probe] = []

    # Server 2025: "Setup Dynamic Update" / "Safe OS Dynamic Update"
    probes.append(
        Probe(
            label="Server2025 DU.Setup (2026-04)",
            os_short_name="Server2025",
            du_type="DynamicUpdate.Setup",
            query=(f"{m} Setup Dynamic Update for Microsoft server "
                   f"operating system version 24H2"),
            title_substr=["setup dynamic update", "24h2"],
            title_excludes=["safe os", "safeos"],
        )
    )
    probes.append(
        Probe(
            label="Server2025 DU.SafeOs (2026-04)",
            os_short_name="Server2025",
            du_type="DynamicUpdate.SafeOs",
            query=(f"{m} Safe OS Dynamic Update for Microsoft server "
                   f"operating system version 24H2"),
            title_substr=["safe os dynamic update", "24h2"],
            title_excludes=[],
        )
    )

    # Server 2022: bare "Dynamic Update" -- only Product/Description
    # disambiguates which is Setup vs SafeOs.
    probes.append(
        Probe(
            label="Server2022 DU.* (2026-04, bare query)",
            os_short_name="Server2022",
            du_type="DynamicUpdate.*",
            query=(f"{m} Dynamic Update for Microsoft server "
                   f"operating system version 21H2"),
            title_substr=["dynamic update", "21h2"],
            title_excludes=[],
        )
    )

    # Server 2019: production code declares "no Setup/SafeOs DU
    # in monthly cadence; only on feature-update windows" -- the
    # PoC will check that the query indeed returns ZERO hits as
    # an empirical confirmation.
    probes.append(
        Probe(
            label="Server2019 DU.Setup (2026-04) -- expected EMPTY",
            os_short_name="Server2019",
            du_type="DynamicUpdate.Setup",
            query=(f"{m} Setup Dynamic Update for Windows Server 2019"),
            title_substr=["setup dynamic update", "server 2019"],
            title_excludes=["safe os"],
        )
    )

    # Server 2016: same expectation as 2019.
    probes.append(
        Probe(
            label="Server2016 DU.Setup (2026-04) -- expected EMPTY",
            os_short_name="Server2016",
            du_type="DynamicUpdate.Setup",
            query=(f"{m} Setup Dynamic Update for Windows Server 2016"),
            title_substr=["setup dynamic update", "server 2016"],
            title_excludes=["safe os"],
        )
    )

    return probes


def probe_one(p: Probe, delay_seconds: float = 2.0) -> ProbeResult:
    result = ProbeResult(probe=asdict(p))
    url = catalog_client.search_url(p.query)
    print(f"  [{p.label}]")
    print(f"    Q: {p.query!r}")
    try:
        resp = catalog_client.fetch(url)
    except Exception as exc:
        result.notes = f"search fetch failed: {exc}"
        return result
    if resp.status != 200:
        result.notes = f"search HTTP {resp.status}"
        return result

    hits = html_parsers.extract_search_hits(resp.body)
    result.search_hit_count = len(hits)

    matching = []
    for h in hits:
        title_lc = h.title.lower()
        if not all(s in title_lc for s in p.title_substr):
            continue
        if any(s in title_lc for s in p.title_excludes):
            continue
        matching.append(h)
    result.matching_hit_count = len(matching)
    result.matching_hits = [
        {"title": h.title, "update_id": h.update_id} for h in matching
    ]

    if not matching:
        # For probes labelled "expected EMPTY", zero hits is success.
        if "expected EMPTY" in p.label:
            result.success = True
            result.notes = (
                f"0 matching hits -- confirms Server 2019/2016 do not "
                f"publish Setup DU in monthly cadence"
            )
        else:
            result.notes = (
                f"no matching hits among {len(hits)} raw search hits"
            )
        return result

    # Prefer shortest Title (skip umbrella entries)
    matching.sort(key=lambda h: len(h.title))
    chosen = matching[0]
    result.chosen_update_id = chosen.update_id
    result.chosen_title = chosen.title

    time.sleep(delay_seconds)

    dd_url = catalog_client.download_dialog_url(chosen.update_id)
    post_body = (
        '{"size":0,"UpdateID":"' + chosen.update_id + '",'
        '"UpdateIDInfo":"' + chosen.update_id + '"}'
    )
    try:
        dd_resp = catalog_client.fetch(
            dd_url,
            method="POST",
            data=("updateIDs=[" + post_body + "]").encode("utf-8"),
            extra_headers={
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
    except Exception as exc:
        result.notes = f"download dialog fetch failed: {exc}"
        return result
    if dd_resp.status != 200:
        result.notes = f"download dialog HTTP {dd_resp.status}"
        return result

    urls = html_parsers.extract_download_urls(dd_resp.body)
    result.download_url_count = len(urls)
    result.file_names = [u.rsplit("/", 1)[-1] for u in urls]
    result.success = bool(urls)
    if not urls:
        result.notes = "DownloadDialog returned no URLs"
    return result


def main() -> int:
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    probes = build_probes()
    print(f"Probing Microsoft Update Catalog for {len(probes)} DU queries ...")
    print()
    results: list[ProbeResult] = []
    for i, p in enumerate(probes, 1):
        print(f"[{i}/{len(probes)}]")
        results.append(probe_one(p))
        if i < len(probes):
            time.sleep(2.0)
        print()

    n_ok = sum(1 for r in results if r.success)

    out_path = FIXTURE_DIR / "probe-results.json"
    out_path.write_text(
        json.dumps(
            {
                "patch_month": PATCH_MONTH,
                "probe_count": len(probes),
                "success_count": n_ok,
                "results": [r.to_dict() for r in results],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    print("Summary")
    print("-------")
    for r in results:
        sym = "OK" if r.success else "NG"
        first_fn = r.file_names[0] if r.file_names else "-"
        print(
            f"  {sym}  {r.probe['label']}: "
            f"hits={r.search_hit_count}, matching={r.matching_hit_count}, "
            f"urls={r.download_url_count}, file1={first_fn}"
            + (f", notes={r.notes!r}" if r.notes else "")
        )
    print()
    print(f"Wrote {out_path.relative_to(TESTS_DIR)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
