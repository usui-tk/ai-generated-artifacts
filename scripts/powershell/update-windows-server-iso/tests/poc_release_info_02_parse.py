#!/usr/bin/env python3
"""PoC release-info, step 2: parse the saved Markdown into structured JSON.

Part of the r06 Phase 2 PoC tracked in `docs/poc/poc-release-info-report.md`.

The release-info page contains two distinct table flavours:
  1. Monthly release tables under "## Windows Server release history":
       | Servicing option | Update type | Availability date | Build | KB article |
  2. Hotpatch calendar tables under "## Windows Server hotpatch calendar":
       | Month | Update type | Type | Availability date | Build | KB article |

The parser is deliberately strict: any column-count drift or header
text drift causes a clear error message. That makes the parser an
early-warning system for Microsoft-side format changes -- if the
parser breaks, the human reviews the diff before any downstream
automation kicks in.

Output: `tests/fixtures/poc_release_info/release-info.json`.
See SPEC.md §B.22 for the file-organisation rules this script obeys.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
from dataclasses import asdict, dataclass, field
from typing import Iterable

# This script sits at tests/poc_release_info_02_parse.py.
TESTS_DIR = pathlib.Path(__file__).resolve().parent
SNAPSHOT_DIR = TESTS_DIR / "snapshots" / "poc_release_info"
FIXTURE_DIR = TESTS_DIR / "fixtures" / "poc_release_info"

OS_HEADER_REGEX = re.compile(
    r"\*\*Windows Server (\d{4})\s*\(OS build (\d+)\)\*\*", re.IGNORECASE
)

# Match "[KB1234567](url)" or bare "KB1234567"
KB_LINK_REGEX = re.compile(r"\[?KB(\d{4,7})\]?\(?([^)]*)\)?")

# Monthly release table header
EXPECTED_MONTHLY_HEADERS = (
    "Servicing option",
    "Update type",
    "Availability date",
    "Build",
    "KB article",
)

# Hotpatch calendar table header
EXPECTED_HOTPATCH_HEADERS = (
    "Month",
    "Update type",
    "Type",
    "Availability date",
    "Build",
    "KB article",
)


@dataclass
class MonthlyRelease:
    """One row from a per-OS monthly release table."""

    os_short_name: str  # 'Server2016' / 'Server2019' / 'Server2022' / 'Server2025'
    os_build: str  # '14393', '17763', '20348', '26100'
    servicing_option: str  # 'LTSC' or 'LTSB'
    update_type: str  # e.g. '2026-04 B' or '2026-01 OOB'
    update_type_year: int
    update_type_month: int
    update_type_letter: str  # 'A' / 'B' / 'C' / 'D' / 'E' / 'OOB'
    availability_date: str  # 'YYYY-MM-DD'
    build_after_update: str  # full build string, e.g. '20348.5024'
    kb_id: str  # 'KB5091157'
    kb_url: str  # documentation URL or '' if absent

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class HotpatchEntry:
    """One row from the 'Windows Server hotpatch calendar' tables.

    Microsoft publishes a forward-looking calendar for Server 2022 /
    Server 2025 in the hotpatch section of the release-info page.
    Each entry is labelled either 'Baseline (Restart)' or 'Hotpatch'
    in the 'Type' column. Future months in the calendar year have
    empty Availability date / Build / KB fields; the parser keeps
    them so the calendar shape is visible end-to-end.
    """

    os_short_name: str
    os_build: str
    calendar_year: int
    month_name: str  # 'January' .. 'December'
    month_number: int  # 1-12
    update_type: str  # e.g. '2026.05 B'
    hotpatch_type: str  # 'Baseline (Restart)' or 'Hotpatch'
    is_baseline: bool
    availability_date: str  # 'YYYY-MM-DD' or '' for future months
    build_after_update: str  # may be '' for future months
    kb_id: str  # may be '' for future months
    kb_url: str

    def to_dict(self) -> dict:
        return asdict(self)


LONG_TO_SHORT = {
    "Windows Server 2025": "Server2025",
    "Windows Server 2022": "Server2022",
    "Windows Server 2019 (version 1809)": "Server2019",
    "Windows Server 2019": "Server2019",
    "Windows Server 2016 (version 1607)": "Server2016",
    "Windows Server 2016": "Server2016",
}

MONTH_NAME_TO_NUMBER = {
    "January": 1, "February": 2, "March": 3, "April": 4,
    "May": 5, "June": 6, "July": 7, "August": 8,
    "September": 9, "October": 10, "November": 11, "December": 12,
}


def find_latest_snapshot() -> pathlib.Path | None:
    if not SNAPSHOT_DIR.is_dir():
        return None
    candidates = sorted(SNAPSHOT_DIR.glob("release-info-*.md"))
    return candidates[-1] if candidates else None


def split_table_row(line: str) -> list[str]:
    parts = [c.strip() for c in line.split("|")]
    if parts and parts[0] == "":
        parts = parts[1:]
    if parts and parts[-1] == "":
        parts = parts[:-1]
    return parts


def is_table_separator(line: str) -> bool:
    stripped = line.strip()
    if not stripped.startswith("|"):
        return False
    cells = split_table_row(stripped)
    return bool(cells) and all(re.fullmatch(r":?-+:?", c) for c in cells)


def parse_update_type(label: str) -> tuple[int, int, str]:
    """Decompose '2026-04 OOB' / '2026-04 B' into (year, month, letter)."""
    m = re.fullmatch(r"(\d{4})-(\d{2})\s+(OOB|[A-E])", label.strip())
    if not m:
        return (0, 0, "?")
    return (int(m.group(1)), int(m.group(2)), m.group(3))


def parse_kb_cell(cell: str) -> tuple[str, str]:
    cell = cell.strip()
    if not cell:
        return ("", "")
    m = KB_LINK_REGEX.search(cell)
    if not m:
        return ("", "")
    kb_id = f"KB{m.group(1)}"
    kb_url = m.group(2).strip()
    return (kb_id, kb_url)


def iter_release_tables(lines: list[str]):
    """Yield (kind, os_short_name, os_build, context, rows) for each
    table the parser recognises.

    `kind` is 'monthly' for tables under "## Windows Server release
    history" and 'hotpatch' for tables under "## Windows Server
    hotpatch calendar". `context` carries the calendar year for
    hotpatch tables.
    """
    section = ""
    current_os: tuple[str, str] | None = None
    current_year: int = 0

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("## Windows Server release history"):
            section = "release-history"
            current_os = None
            i += 1
            continue
        if stripped.startswith("## Windows Server hotpatch calendar"):
            section = "hotpatch-calendar"
            current_os = None
            i += 1
            continue
        if stripped.startswith("## ") and section in (
            "release-history",
            "hotpatch-calendar",
        ):
            section = ""
            current_os = None

        m_os = OS_HEADER_REGEX.search(stripped)
        if m_os and section in ("release-history", "hotpatch-calendar"):
            os_year = m_os.group(1)
            os_build = m_os.group(2)
            long_name = f"Windows Server {os_year}"
            os_short_name = LONG_TO_SHORT.get(long_name)
            current_os = (os_short_name, os_build) if os_short_name else None
            i += 1
            continue

        m_yr = re.fullmatch(r"\*\*Calendar year (\d{4})\*\*", stripped)
        if m_yr and section == "hotpatch-calendar":
            current_year = int(m_yr.group(1))
            i += 1
            continue

        if stripped.startswith("|") and current_os:
            header_cells = split_table_row(stripped)
            sep_idx = i + 1
            if sep_idx >= len(lines) or not is_table_separator(lines[sep_idx]):
                i += 1
                continue

            if (
                section == "release-history"
                and tuple(header_cells) == EXPECTED_MONTHLY_HEADERS
            ):
                kind = "monthly"
                context: dict = {}
            elif (
                section == "hotpatch-calendar"
                and tuple(header_cells) == EXPECTED_HOTPATCH_HEADERS
            ):
                kind = "hotpatch"
                context = {"calendar_year": current_year}
            else:
                print(
                    f"  warn: unrecognised table header in section "
                    f"{section!r} for {current_os[0]}: {header_cells!r}",
                    file=sys.stderr,
                )
                i = sep_idx
                continue

            rows: list[list[str]] = []
            k = sep_idx + 1
            while k < len(lines):
                rl = lines[k]
                if not rl.lstrip().startswith("|"):
                    break
                rows.append(split_table_row(rl))
                k += 1

            yield (kind, current_os[0], current_os[1], context, rows)
            i = k
            continue

        i += 1


def parse_monthly_table(
    os_short_name: str, os_build: str, rows: list[list[str]]
) -> list[MonthlyRelease]:
    parsed: list[MonthlyRelease] = []
    for row in rows:
        if len(row) != len(EXPECTED_MONTHLY_HEADERS):
            print(
                f"  warn: skipping monthly row with {len(row)} columns "
                f"for {os_short_name}: {row!r}",
                file=sys.stderr,
            )
            continue
        servicing_option, update_type, availability_date, build_after, kb_cell = row
        year, month, letter = parse_update_type(update_type)
        kb_id, kb_url = parse_kb_cell(kb_cell)
        parsed.append(
            MonthlyRelease(
                os_short_name=os_short_name,
                os_build=os_build,
                servicing_option=servicing_option,
                update_type=update_type,
                update_type_year=year,
                update_type_month=month,
                update_type_letter=letter,
                availability_date=availability_date,
                build_after_update=build_after,
                kb_id=kb_id,
                kb_url=kb_url,
            )
        )
    return parsed


def parse_hotpatch_table(
    os_short_name: str, os_build: str, calendar_year: int, rows: list[list[str]]
) -> list[HotpatchEntry]:
    parsed: list[HotpatchEntry] = []
    for row in rows:
        # Strip trailing empty cells (some hotpatch rows have one).
        while len(row) > len(EXPECTED_HOTPATCH_HEADERS) and row[-1] == "":
            row = row[:-1]
        if len(row) != len(EXPECTED_HOTPATCH_HEADERS):
            print(
                f"  warn: skipping hotpatch row with {len(row)} columns "
                f"for {os_short_name}: {row!r}",
                file=sys.stderr,
            )
            continue
        (
            month_name,
            update_type,
            hotpatch_type,
            availability_date,
            build_after,
            kb_cell,
        ) = row
        month_number = MONTH_NAME_TO_NUMBER.get(month_name, 0)
        kb_id, kb_url = parse_kb_cell(kb_cell)
        is_baseline = "baseline" in hotpatch_type.lower()
        parsed.append(
            HotpatchEntry(
                os_short_name=os_short_name,
                os_build=os_build,
                calendar_year=calendar_year,
                month_name=month_name,
                month_number=month_number,
                update_type=update_type,
                hotpatch_type=hotpatch_type,
                is_baseline=is_baseline,
                availability_date=availability_date,
                build_after_update=build_after,
                kb_id=kb_id,
                kb_url=kb_url,
            )
        )
    return parsed


def main() -> int:
    snapshot = find_latest_snapshot()
    if snapshot is None:
        print(
            "ERROR: no snapshot found under "
            f"{SNAPSHOT_DIR.relative_to(TESTS_DIR)}/. "
            "Run poc_release_info_01_fetch.py first.",
            file=sys.stderr,
        )
        return 1
    print(f"Reading: {snapshot.relative_to(TESTS_DIR)}")
    text = snapshot.read_text(encoding="utf-8")
    lines = text.splitlines()

    monthly_releases: list[MonthlyRelease] = []
    hotpatch_entries: list[HotpatchEntry] = []
    per_os_monthly: dict[str, int] = {}
    per_os_hotpatch: dict[str, int] = {}

    for kind, os_short_name, os_build, context, rows in iter_release_tables(lines):
        if kind == "monthly":
            ms = parse_monthly_table(os_short_name, os_build, rows)
            monthly_releases.extend(ms)
            per_os_monthly[os_short_name] = per_os_monthly.get(os_short_name, 0) + len(ms)
            print(f"  monthly {os_short_name} (build {os_build}): {len(ms)} rows")
        elif kind == "hotpatch":
            hp = parse_hotpatch_table(
                os_short_name, os_build, context["calendar_year"], rows
            )
            hotpatch_entries.extend(hp)
            per_os_hotpatch[os_short_name] = per_os_hotpatch.get(os_short_name, 0) + len(hp)
            print(
                f"  hotpatch {os_short_name} (build {os_build}, "
                f"CY{context['calendar_year']}): {len(hp)} rows"
            )

    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    out = {
        "source_snapshot": str(snapshot.relative_to(TESTS_DIR)),
        "monthly_row_count": len(monthly_releases),
        "hotpatch_row_count": len(hotpatch_entries),
        "per_os_monthly_counts": per_os_monthly,
        "per_os_hotpatch_counts": per_os_hotpatch,
        "releases": [r.to_dict() for r in monthly_releases],
        "hotpatch_calendar": [r.to_dict() for r in hotpatch_entries],
    }
    out_path = FIXTURE_DIR / "release-info.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print()
    print(f"Wrote: {out_path.relative_to(TESTS_DIR)}")
    print(f"  monthly releases: {len(monthly_releases):,}")
    print(f"  hotpatch entries: {len(hotpatch_entries):,}")
    print()
    print("OK. Next: python3 poc_release_info_03_analyse.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
