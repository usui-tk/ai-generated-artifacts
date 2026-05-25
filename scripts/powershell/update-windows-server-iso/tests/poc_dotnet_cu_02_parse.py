#!/usr/bin/env python3
"""PoC dotnet_cu, step 2: fetch a representative monthly CU page
and parse its (OS -> .NET version -> KB) summary table.

This validates that the per-month .NET CU page is parseable by the
same Markdown-table approach used for the Windows Server release-info
page. The output is the per-OS KB-count breakdown that SPEC.md
§B.21.2 codified normatively (and which the production telemetry in
r05.1 indicated was per-OS variable).

We hit ONE representative month (2026-04, the most recent regular
cumulative update at the time the PoC was authored). Other months
can be processed identically by changing TARGET_MONTH_URL or by
iterating over the index produced by step 1.

Output:
  tests/snapshots/poc_dotnet_cu/<filename>.md
  tests/fixtures/poc_dotnet_cu/sample-month.json
"""
from __future__ import annotations

import datetime
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field

# Pick the most recent regular cumulative update (not the preview).
TARGET_MONTH_URL = (
    "https://learn.microsoft.com/en-us/dotnet/framework/"
    "release-notes/2026/04-14-april-cumulative-update?accept=text/markdown"
)

USER_AGENT = (
    "ai-generated-artifacts/poc-dotnet-cu "
    "(+https://github.com/usui-tk/ai-generated-artifacts)"
)

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SNAPSHOT_DIR = TESTS_DIR / "snapshots" / "poc_dotnet_cu"
FIXTURE_DIR = TESTS_DIR / "fixtures" / "poc_dotnet_cu"

# A row that names the OS looks like "| **Windows Server 2022** | **[5084071](...)** |"
# or "| **Microsoft server operating system, version 24H2** |  |"
# A row that names the .NET version looks like
# "| .NET Framework 3.5, 4.8 | [5082427](...) |"
OS_ROW_REGEX = re.compile(
    r"^\|\s*\*\*([^|*]+?)\*\*\s*\|\s*(?:\*\*)?\[?KB?(\d{4,7})?\]?\(?[^|]*\)?\s*\|"
)
OS_ROW_NAME_REGEX = re.compile(r"^\|\s*\*\*([^|*]+?)\*\*\s*\|")
DOTNET_ROW_REGEX = re.compile(
    r"^\|\s*\.NET Framework\s+([^|]+?)\s*\|\s*\[?(\d{4,7})\]?\(?[^|]*\)?\s*\|"
)
KB_IN_CELL = re.compile(r"\[?(\d{4,7})\]?\(?[^|]*\)?")


@dataclass
class DotNetEntry:
    os_label: str  # raw label as printed in the table
    os_normalised: str  # 'Server2016' / 'Server2019' / ... if recognised, else ''
    os_offering_kb: str  # KB on the OS row (the offering KB, optional)
    rows: list = field(default_factory=list)  # list of {dotnet_versions, kb_id}

    def to_dict(self) -> dict:
        return asdict(self)


OS_NORMALISE = [
    # (substring to match in label, normalised short name)
    ("Microsoft server operating system, version 24H2", "Server2025"),
    ("Microsoft server operating system version 24H2", "Server2025"),
    ("Microsoft server operating system, version 23H2", "Server23H2"),
    ("Microsoft server operating system version 23H2", "Server23H2"),
    ("Windows Server 2022", "Server2022"),
    ("Windows 10 1809 and Windows Server 2019", "Server2019"),
    ("Windows Server 2019", "Server2019"),
    ("Windows 10 1607 and Windows Server 2016", "Server2016"),
    ("Windows Server 2016", "Server2016"),
    ("Windows Server 2012 R2", "Server2012R2"),
    ("Windows Server 2012", "Server2012"),
]


def normalise_os(label: str) -> str:
    for pat, short in OS_NORMALISE:
        if pat in label:
            return short
    return ""


def fetch(url: str, timeout: int = 30) -> tuple[bytes, dict]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read()
        headers = {k.lower(): v for k, v in resp.headers.items()}
    return body, headers


def derive_snapshot_name(url: str) -> str:
    # 2026/04-14-april-cumulative-update -> 2026-04-14-april-cumulative-update
    path = url.split("/release-notes/", 1)[1].split("?", 1)[0]
    return path.replace("/", "-") + ".md"


def parse_table_blocks(text: str):
    """Yield (os_label, os_offering_kb, sub_rows) tuples.

    A "table block" in the .NET CU pages consists of one OS row
    (where the OS name is bolded) followed by zero or more .NET
    Framework version rows. The OS row optionally has an offering
    KB; the .NET version rows always have a KB.

    The parser walks line by line because the table layout is too
    irregular for a single regex.
    """
    lines = text.splitlines()
    current: DotNetEntry | None = None
    in_summary_section = False

    for line in lines:
        # Heuristic: the relevant tables come after the "## Summary
        # tables" or "## Summary of what's new" heading on the page.
        if line.startswith("## Summary tables"):
            in_summary_section = True
            continue
        if line.startswith("## Known issues") or line.startswith("Collaborate with us"):
            in_summary_section = False
            if current:
                yield current
                current = None
            continue
        if not in_summary_section:
            continue

        # OS row?
        m_name = OS_ROW_NAME_REGEX.match(line)
        if m_name:
            if current:
                yield current
            label = m_name.group(1).strip()
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            offering_kb = ""
            if len(cells) >= 2:
                m_kb = re.search(r"(\d{4,7})", cells[1])
                if m_kb:
                    offering_kb = "KB" + m_kb.group(1)
            current = DotNetEntry(
                os_label=label,
                os_normalised=normalise_os(label),
                os_offering_kb=offering_kb,
                rows=[],
            )
            continue

        # .NET version row?
        m_net = DOTNET_ROW_REGEX.match(line)
        if m_net and current:
            current.rows.append(
                {
                    "dotnet_versions": m_net.group(1).strip(),
                    "kb_id": "KB" + m_net.group(2),
                }
            )

    if current:
        yield current


def main() -> int:
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Fetching: {TARGET_MONTH_URL}")
    try:
        body, headers = fetch(TARGET_MONTH_URL)
    except urllib.error.URLError as exc:
        print(f"ERROR: fetch failed: {exc}", file=sys.stderr)
        return 1

    snapshot_name = derive_snapshot_name(TARGET_MONTH_URL)
    snapshot_path = SNAPSHOT_DIR / snapshot_name
    snapshot_path.write_bytes(body)
    meta_path = snapshot_path.with_suffix(".meta.json")
    meta = {
        "fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "url": TARGET_MONTH_URL,
        "user_agent": USER_AGENT,
        "byte_count": len(body),
        "response_headers": {
            k: headers.get(k)
            for k in ("content-type", "content-length", "etag", "last-modified")
            if k in headers
        },
    }
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print(f"  -> snapshot: {snapshot_path.relative_to(TESTS_DIR)}")
    print(f"     {len(body):,} bytes")
    print(f"     content-type: {meta['response_headers'].get('content-type', '?')}")
    print()

    text = body.decode("utf-8", errors="replace")
    entries = list(parse_table_blocks(text))

    # Filter to OS labels we recognise as in-scope
    recognised = [e for e in entries if e.os_normalised]
    print("Parsed table blocks (recognised OS only):")
    print()
    for e in recognised:
        print(
            f"  {e.os_normalised:>14s}  ({e.os_label!r})"
            f"    offering KB = {e.os_offering_kb or '-':<10s}"
            f"    .NET rows = {len(e.rows)}"
        )
        for r in e.rows:
            print(f"      .NET {r['dotnet_versions']:<36s} -> {r['kb_id']}")
    print()

    out = {
        "source_snapshot": str(snapshot_path.relative_to(TESTS_DIR)),
        "target_url": TARGET_MONTH_URL,
        "entry_count_total": len(entries),
        "entry_count_recognised": len(recognised),
        # Per-OS .NET row count -- this is the empirical answer to
        # SPEC.md §B.21.2 ".NET CU file multiplicity by OS"
        "rows_per_os": {
            e.os_normalised: len(e.rows) for e in recognised if e.os_normalised
        },
        "entries": [e.to_dict() for e in entries],
    }
    out_path = FIXTURE_DIR / "sample-month.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out_path.relative_to(TESTS_DIR)}")
    print()
    print("Per-OS .NET CU row count for the sample month:")
    for k, v in out["rows_per_os"].items():
        print(f"  {k:>14s}: {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
