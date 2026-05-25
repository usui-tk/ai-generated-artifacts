#!/usr/bin/env python3
"""PoC release-info, step 4: resolve KB -> (UpdateId, DownloadUrl) via Catalog.

Part of the r06 Phase 2 PoC tracked in `docs/poc/poc-release-info-report.md`.

This is PoC-B from the original Phase 2 plan. It answers:
  "Can the KB numbers harvested from release-info be turned into
   actual .msu / .cab download URLs via Microsoft Update Catalog,
   using only the KB as input (no Title-string heuristics)?"

Strategy:
  1. Pick a small but representative sample of (OS, KB) pairs from
     the parsed release-info data:
       - one current LCU per OS (2026-04 B from each)
       - one OOB row to stress superseding logic
       - one Hotpatch baseline LCU (Server2025 CY2026 January)
  2. For each sample, hit catalog.update.microsoft.com Search.aspx
     with just the KB as the query (no architecture, no OS name).
  3. From the results, identify the right hit by matching the
     OS short name in the search-hit Title (Server 2025 / Server 2022
     / etc.). This is the URL-resolver use case: Title is used as a
     disambiguator, not a discovery field.
  4. Resolve the UpdateId to one or more direct download URLs via
     DownloadDialog.aspx and verify the file name looks correct.

The script writes a structured JSON record of per-sample success or
failure plus a summary verdict (works / partially works / does not
work). The PoC report is updated separately from the verdict.

Output: tests/fixtures/poc_release_info/resolve-sample.json

See SPEC.md §B.22 for the file-organisation rules this script obeys.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
import time
from dataclasses import asdict, dataclass, field
from typing import Optional

TESTS_DIR = pathlib.Path(__file__).resolve().parent

# Re-use the existing T1/T2 common modules so we look exactly like
# the production scraper to Microsoft's servers.
sys.path.insert(0, str(TESTS_DIR))
from common import catalog_client  # noqa: E402
from common import html_parsers  # noqa: E402

FIXTURE_DIR = TESTS_DIR / "fixtures" / "poc_release_info"


@dataclass
class ResolveSample:
    """One (OS, KB) pair to be resolved through the Catalog."""

    label: str  # human-readable purpose, e.g. "Server2025 2026-04 B LCU"
    os_short_name: str
    os_title_match: str  # substring expected in the Title to identify the right hit
    kb_id: str
    # Optional filter: when set, the Catalog often returns several
    # search hits per KB (e.g. arm64, x64, .NET 3.5+4.x). We accept
    # the first hit whose Title contains os_title_match AND, if set,
    # arch_token.
    arch_token: Optional[str] = "x64"


@dataclass
class ResolveResult:
    """Outcome of resolving one ResolveSample."""

    sample: dict
    search_hit_count: int = 0
    search_hits: list = field(default_factory=list)  # list of {title, update_id}
    chosen_update_id: str = ""
    chosen_title: str = ""
    download_url_count: int = 0
    download_urls: list = field(default_factory=list)
    file_names: list = field(default_factory=list)
    success: bool = False
    notes: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


def load_releases() -> list[dict]:
    """Load monthly_releases from the Phase 2 parsed JSON."""
    parsed_path = FIXTURE_DIR / "release-info.json"
    if not parsed_path.is_file():
        print(
            f"ERROR: {parsed_path.relative_to(TESTS_DIR)} not found. "
            "Run poc_release_info_02_parse.py first.",
            file=sys.stderr,
        )
        sys.exit(1)
    parsed = json.loads(parsed_path.read_text(encoding="utf-8"))
    return parsed["releases"]


def build_samples(releases: list[dict]) -> list[ResolveSample]:
    """Pick a small representative sample.

    The sample is intentionally small (8 KBs) because each KB hits
    Microsoft's Catalog twice (Search + DownloadDialog), and we
    want to be polite. The choices cover:
      - current Patch Tuesday LCU per OS (4 KBs)
      - one OOB to test supersedence
      - one Hotpatch baseline LCU for Server 2025
      - one historical (pre-Hotpatch-calendar) Server 2025 LCU
      - one Server 2019 .NET CU lookalike (production knows this
        used to return the umbrella KB; we want to see what the
        Catalog returns when only the KB is supplied)
    """
    samples: list[ResolveSample] = []
    by_key: dict[tuple[str, str, str], dict] = {}
    for r in releases:
        k = (
            r["os_short_name"],
            f"{r['update_type_year']:04d}-{r['update_type_month']:02d}",
            r["update_type_letter"],
        )
        by_key[k] = r

    def add(label: str, os_key: str, year_month: str, letter: str,
            title_match: str, arch: Optional[str] = "x64") -> None:
        r = by_key.get((os_key, year_month, letter))
        if r and r["kb_id"]:
            samples.append(
                ResolveSample(
                    label=label,
                    os_short_name=os_key,
                    os_title_match=title_match,
                    kb_id=r["kb_id"],
                    arch_token=arch,
                )
            )

    # Current Patch Tuesday LCUs (2026-04 B for each OS)
    add("Server2025 2026-04 B LCU (current)", "Server2025", "2026-04", "B", "Server 2025")
    add("Server2022 2026-04 B LCU (current)", "Server2022", "2026-04", "B", "Server 2022")
    add("Server2019 2026-04 B LCU (current)", "Server2019", "2026-04", "B", "Server 2019")
    add("Server2016 2026-04 B LCU (current)", "Server2016", "2026-04", "B", "Server 2016")

    # OOB stress test (Server 2025 2026-04 OOB = KB5091157)
    add("Server2025 2026-04 OOB", "Server2025", "2026-04", "OOB", "Server 2025")

    # Hotpatch baseline LCU (Server 2025 2026-01 B = the January
    # baseline; same KB the hotpatch calendar's "January Baseline"
    # row points at)
    add("Server2025 2026-01 B (Hotpatch baseline)", "Server2025", "2026-01", "B", "Server 2025")

    # A historical row from before the Hotpatch calendar existed
    add("Server2025 2024-11 B (early life)", "Server2025", "2024-11", "B", "Server 2025")

    # Server 2019 LCU known to coexist with .NET CU naming on the
    # Catalog (r05.1 production telemetry caught this).
    add("Server2019 2026-03 B", "Server2019", "2026-03", "B", "Server 2019")

    return samples


def resolve_one(sample: ResolveSample, delay_seconds: float = 2.0) -> ResolveResult:
    """Hit Search.aspx for the KB, narrow by Title, then DownloadDialog."""
    result = ResolveResult(sample=asdict(sample))

    # --- 1) Search.aspx --------------------------------------------
    url = catalog_client.search_url(sample.kb_id)
    print(f"  [{sample.label}] GET {url}")
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
    result.search_hits = [
        {"title": h.title, "update_id": h.update_id} for h in hits
    ]

    if not hits:
        result.notes = "no search hits"
        return result

    # --- 2) Narrow by Title ---------------------------------------
    # IMPORTANT empirical finding: Microsoft Catalog publishes the
    # Server 2022 and Server 2025 LCU under the name "Microsoft server
    # operating system version <NNHN>" rather than "Windows Server
    # <NNNN>". The os_title_match alternatives field carries every
    # acceptable name token so this disambiguator covers both naming
    # schemes uniformly.
    match_tokens = [sample.os_title_match.lower()]
    if sample.os_short_name == "Server2025":
        match_tokens.extend(["24h2"])  # Microsoft server operating system version 24H2
    elif sample.os_short_name == "Server2022":
        match_tokens.extend(["21h2"])  # Microsoft server operating system version 21H2

    candidates = [
        h for h in hits
        if any(tok in h.title.lower() for tok in match_tokens)
    ]

    # Server 2025/2022 share their name with the Windows 11 client SKU
    # in the Catalog. Exclude any hit whose title says "Windows 11" so
    # we do not pick the client LCU by mistake.
    candidates = [
        h for h in candidates
        if "windows 11" not in h.title.lower()
    ]

    if sample.arch_token:
        narrowed = [
            h for h in candidates
            if sample.arch_token.lower() in h.title.lower()
        ]
        if narrowed:
            candidates = narrowed

    # Prefer the shortest Title -- the umbrella .NET CU and the
    # combined LCU sometimes both match; the shorter Title is
    # almost always the LCU we want.
    if not candidates:
        result.notes = (
            f"no candidates matched os_title_match="
            f"{sample.os_title_match!r} (and arch="
            f"{sample.arch_token!r})"
        )
        return result

    candidates.sort(key=lambda h: len(h.title))
    chosen = candidates[0]
    result.chosen_update_id = chosen.update_id
    result.chosen_title = chosen.title

    time.sleep(delay_seconds)  # polite delay before second Catalog hit

    # --- 3) DownloadDialog.aspx -----------------------------------
    dd_url = catalog_client.download_dialog_url(chosen.update_id)
    print(f"  [{sample.label}] POST DownloadDialog UpdateId={chosen.update_id}")
    # The production PS code uses POST; the Python catalog_client.fetch
    # supports a `post_body` shim. We replicate the form payload exactly.
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
    result.download_urls = urls
    # Derive filenames from the URLs for quick eyeballing
    result.file_names = [u.rsplit("/", 1)[-1] for u in urls]
    result.success = bool(urls)
    if not urls:
        result.notes = "DownloadDialog returned no URLs"
    return result


def main() -> int:
    releases = load_releases()
    samples = build_samples(releases)

    print(f"Resolving {len(samples)} sample (OS, KB) pairs via Catalog ...")
    print()
    results: list[ResolveResult] = []
    for i, s in enumerate(samples, 1):
        print(f"[{i}/{len(samples)}] {s.label}: KB={s.kb_id}")
        results.append(resolve_one(s))
        if i < len(samples):
            time.sleep(2.0)  # be polite between samples too
        print()

    # Summary verdict
    n_ok = sum(1 for r in results if r.success)
    n_fail = len(results) - n_ok
    verdict = (
        "works"
        if n_ok == len(results)
        else "partially works"
        if n_ok > 0
        else "does not work"
    )

    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    out_path = FIXTURE_DIR / "resolve-sample.json"
    out = {
        "sample_count": len(samples),
        "success_count": n_ok,
        "failure_count": n_fail,
        "verdict": verdict,
        "results": [r.to_dict() for r in results],
    }
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")

    print("Summary")
    print("-------")
    for r in results:
        sym = "OK" if r.success else "NG"
        print(
            f"  {sym}  {r.sample['label']}: "
            f"hits={r.search_hit_count}, "
            f"urls={r.download_url_count}"
            + (f", notes={r.notes!r}" if r.notes else "")
        )
    print()
    print(f"Verdict: {verdict} ({n_ok}/{len(results)} samples succeeded)")
    print(f"Wrote {out_path.relative_to(TESTS_DIR)}")
    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
