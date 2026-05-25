#!/usr/bin/env python3
"""PoC release-info, step 1: fetch the Microsoft Learn release-info page.

Part of the r06 Phase 2 PoC tracked in `docs/poc/poc-release-info-report.md`.

The Microsoft Learn rendering pipeline supports a `?accept=text/markdown`
content-negotiation switch on every documentation URL. Appending it to
the Windows Server release-info URL returns the source Markdown table
verbatim, which is much more stable than scraping the rendered HTML.

No authentication is required. The PoC is conservative about HTTP
politeness (single request, descriptive User-Agent, 30-second timeout).

Output lands under `tests/snapshots/poc_release_info/`. See SPEC.md
§B.22 for the file-organisation rules this script obeys.
"""
from __future__ import annotations

import datetime
import json
import pathlib
import sys
import urllib.error
import urllib.request

URL = (
    "https://learn.microsoft.com/en-us/windows/release-health/"
    "windows-server-release-info?accept=text/markdown"
)

USER_AGENT = (
    "ai-generated-artifacts/poc-release-info "
    "(+https://github.com/usui-tk/ai-generated-artifacts)"
)

# This script sits at tests/poc_release_info_01_fetch.py. The snapshot
# directory is a peer of tests/, namely tests/snapshots/poc_release_info/.
SNAPSHOT_DIR = (
    pathlib.Path(__file__).resolve().parent
    / "snapshots"
    / "poc_release_info"
)


def fetch(url: str, timeout: int = 30) -> tuple[bytes, dict]:
    """Fetch URL and return (body_bytes, response_headers_dict)."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read()
        headers = {k.lower(): v for k, v in resp.headers.items()}
    return body, headers


def main() -> int:
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Fetching: {URL}")
    print(f"User-Agent: {USER_AGENT}")
    print()

    try:
        body, headers = fetch(URL)
    except urllib.error.URLError as exc:
        print(f"ERROR: fetch failed: {exc}", file=sys.stderr)
        return 1

    today = datetime.date.today().isoformat()
    snapshot_path = SNAPSHOT_DIR / f"release-info-{today}.md"
    snapshot_path.write_bytes(body)

    meta_path = SNAPSHOT_DIR / f"release-info-{today}.meta.json"
    meta = {
        "fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "url": URL,
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

    rel = snapshot_path.relative_to(pathlib.Path(__file__).resolve().parent)
    rel_meta = meta_path.relative_to(pathlib.Path(__file__).resolve().parent)
    print(f"  -> snapshot: {rel}")
    print(f"     {len(body):,} bytes")
    print(f"  -> metadata: {rel_meta}")
    print(f"     content-type: {meta['response_headers'].get('content-type', '?')}")
    print()
    print("OK. Next: python3 poc_release_info_02_parse.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
