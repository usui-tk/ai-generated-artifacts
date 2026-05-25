#!/usr/bin/env python3
"""PoC dotnet_cu, step 1: fetch the .NET Framework release-notes
index page and discover all monthly CU URLs.

Part of the r06 Phase 2 PoC tracked in
`docs/poc/poc-dotnet-cu-report.md`.

This is PoC-E from the original Phase 2 plan. It answers:
  "Are the .NET Framework cumulative-update release-notes pages
   served as machine-readable Markdown like the Windows Server
   release-info page, and do they include a structured
   (OS -> .NET version -> KB) table that the Refresher could
   consume?"

Strategy:
  1. Fetch the release-notes index
     (learn.microsoft.com/en-us/dotnet/framework/release-notes/
      release-notes?accept=text/markdown). This page links to
     every monthly CU page back to 2024.
  2. Save the raw Markdown snapshot.
  3. Extract the list of per-month CU page URLs and the dates
     they correspond to.
  4. Optionally fetch one or two sample monthly pages to confirm
     they too return as Markdown.

The index discovery is enough to answer the "can we mechanise
the .NET CU lookup" question. The detailed table-parsing for a
single month is in step 2.

Output:
  tests/snapshots/poc_dotnet_cu/release-notes-index-YYYY-MM-DD.md
  tests/snapshots/poc_dotnet_cu/release-notes-index-YYYY-MM-DD.meta.json
  tests/fixtures/poc_dotnet_cu/release-notes-index.json

See SPEC.md §B.22 for the file-organisation rules this script obeys.
"""
from __future__ import annotations

import datetime
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

INDEX_URL = (
    "https://learn.microsoft.com/en-us/dotnet/framework/"
    "release-notes/release-notes?accept=text/markdown"
)

USER_AGENT = (
    "ai-generated-artifacts/poc-dotnet-cu "
    "(+https://github.com/usui-tk/ai-generated-artifacts)"
)

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SNAPSHOT_DIR = TESTS_DIR / "snapshots" / "poc_dotnet_cu"
FIXTURE_DIR = TESTS_DIR / "fixtures" / "poc_dotnet_cu"

# Bullet entries on the index look like:
#   - [April 14, 2026 - cumulative update](2026/04-14-april-cumulative-update)
# or:
#   - [October 28, 2025 - cumulative update preview](2025/10-28-october-cumulative-update-preview)
ENTRY_REGEX = re.compile(
    r"^\s*-\s+\[([A-Z][a-z]+ \d{1,2},\s+\d{4})\s*-\s*([^\]]+)\]"
    r"\(([^)]+)\)\s*$",
    re.MULTILINE,
)


def fetch(url: str, timeout: int = 30) -> tuple[bytes, dict]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read()
        headers = {k.lower(): v for k, v in resp.headers.items()}
    return body, headers


def main() -> int:
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Fetching: {INDEX_URL}")
    try:
        body, headers = fetch(INDEX_URL)
    except urllib.error.URLError as exc:
        print(f"ERROR: fetch failed: {exc}", file=sys.stderr)
        return 1

    today = datetime.date.today().isoformat()
    snapshot_path = SNAPSHOT_DIR / f"release-notes-index-{today}.md"
    snapshot_path.write_bytes(body)

    meta_path = SNAPSHOT_DIR / f"release-notes-index-{today}.meta.json"
    meta = {
        "fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "url": INDEX_URL,
        "user_agent": USER_AGENT,
        "byte_count": len(body),
        "response_headers": {
            k: headers.get(k)
            for k in (
                "content-type",
                "content-length",
                "etag",
                "last-modified",
                "cache-control",
            )
            if k in headers
        },
    }
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")

    text = body.decode("utf-8", errors="replace")
    print(f"  -> snapshot: {snapshot_path.relative_to(TESTS_DIR)}")
    print(f"     bytes        : {len(body):,}")
    print(f"     Content-Type : {meta['response_headers'].get('content-type', '?')}")
    print()

    # Extract monthly entries
    matches = ENTRY_REGEX.findall(text)
    entries = []
    for date_str, kind, rel_url in matches:
        try:
            dt = datetime.datetime.strptime(date_str, "%B %d, %Y").date()
        except ValueError:
            try:
                dt = datetime.datetime.strptime(date_str, "%b %d, %Y").date()
            except ValueError:
                dt = None
        entries.append(
            {
                "date_text": date_str,
                "date": dt.isoformat() if dt else "",
                "kind": kind.strip(),
                "relative_url": rel_url.strip(),
                "absolute_url": (
                    "https://learn.microsoft.com/en-us/dotnet/framework/"
                    "release-notes/" + rel_url.strip()
                ),
            }
        )

    out = {
        "source_snapshot": str(snapshot_path.relative_to(TESTS_DIR)),
        "entry_count": len(entries),
        "kinds": sorted({e["kind"] for e in entries}),
        "earliest_date": min((e["date"] for e in entries if e["date"]), default=""),
        "latest_date": max((e["date"] for e in entries if e["date"]), default=""),
        "entries": entries,
    }
    index_path = FIXTURE_DIR / "release-notes-index.json"
    index_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")

    print(f"  -> index    : {index_path.relative_to(TESTS_DIR)}")
    print(f"     entries     : {len(entries)}")
    print(f"     date range  : {out['earliest_date']} ... {out['latest_date']}")
    print(f"     kinds       : {out['kinds']}")
    print()
    print("OK. Next: python3 poc_dotnet_cu_02_parse.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
