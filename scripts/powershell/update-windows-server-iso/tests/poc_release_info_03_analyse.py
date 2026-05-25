#!/usr/bin/env python3
"""PoC release-info, step 3: analyse the parsed JSON against SPEC.md §B.21.

Part of the r06 Phase 2 PoC tracked in `docs/poc/poc-release-info-report.md`.

Writes four analysis artefacts that together form the empirical
evidence backing the recommendations in the PoC report:

  fixtures/poc_release_info/update-type-summary.csv
    Pivot table: rows are 'YYYY-MM', columns are OS short names, cell
    is the comma-joined list of Update type letters published that
    month.

  fixtures/poc_release_info/baseline-month-detection.json
    Server 2025 / 2022 Hotpatch baseline months, computed both
    authoritatively (from the hotpatch_calendar table) and from
    an inferred {1, 4, 7, 10} rule applied to the monthly B
    releases. The two paths can be cross-checked.

  fixtures/poc_release_info/letter-frequency.json
    Per-OS frequency of A / B / C / D / E / OOB letters.

  fixtures/poc_release_info/coverage-summary.json
    Date-range coverage per OS plus a gap list.

See SPEC.md §B.22 for the file-organisation rules this script obeys.
"""
from __future__ import annotations

import collections
import csv
import json
import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
FIXTURE_DIR = TESTS_DIR / "fixtures" / "poc_release_info"

# Server 2025 Hotpatch baseline months are 1/4/7/10. See:
#   https://techcommunity.microsoft.com/blog/azurearcblog/.../4521251
#   "Baseline month: In January, April, July, and October, devices
#    install the monthly cumulative security update and must restart..."
HOTPATCH_BASELINE_MONTHS = (1, 4, 7, 10)


def load_parsed() -> dict:
    path = FIXTURE_DIR / "release-info.json"
    if not path.is_file():
        print(
            f"ERROR: {path.relative_to(TESTS_DIR)} not found. "
            "Run poc_release_info_02_parse.py first.",
            file=sys.stderr,
        )
        sys.exit(1)
    return json.loads(path.read_text(encoding="utf-8"))


def write_update_type_summary_csv(releases: list[dict]) -> pathlib.Path:
    by_month_os: dict[tuple[str, str], list[str]] = collections.defaultdict(list)
    for r in releases:
        y = r["update_type_year"]
        m = r["update_type_month"]
        if y == 0 or m == 0:
            continue
        ym = f"{y:04d}-{m:02d}"
        os_key = r["os_short_name"]
        letter = r["update_type_letter"]
        by_month_os[(ym, os_key)].append(letter)

    os_columns = ["Server2016", "Server2019", "Server2022", "Server2025"]
    all_months = sorted({k[0] for k in by_month_os})

    out_path = FIXTURE_DIR / "update-type-summary.csv"
    with out_path.open("w", encoding="utf-8", newline="") as fh:
        # Force LF line endings; the repo's *.csv convention is LF.
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["YearMonth"] + os_columns)
        for ym in all_months:
            row = [ym]
            for os_key in os_columns:
                letters = sorted(set(by_month_os.get((ym, os_key), [])))
                row.append(",".join(letters))
            w.writerow(row)
    return out_path


def write_baseline_month_detection(releases: list[dict], parsed: dict) -> pathlib.Path:
    """Identify Server 2025 / 2022 Hotpatch baseline months via two paths.

    Authoritative source: the hotpatch_calendar table that the
    release-info page publishes explicitly (with 'Baseline (Restart)'
    vs 'Hotpatch' labels).

    Inferred fallback: monthly B releases whose month is in
    HOTPATCH_BASELINE_MONTHS. Useful as a cross-check; not the
    primary source.
    """
    out: dict = {
        "hotpatch_baseline_months_documented": list(HOTPATCH_BASELINE_MONTHS),
        "authoritative_source": "release-info hotpatch_calendar table",
        "calendar": {},
        "inferred_from_monthly_b_releases": {},
    }

    calendar = parsed.get("hotpatch_calendar", [])
    by_os: dict[str, list[dict]] = collections.defaultdict(list)
    for entry in calendar:
        by_os[entry["os_short_name"]].append(entry)
    for os_key, entries in by_os.items():
        entries_sorted = sorted(
            entries, key=lambda e: (e["calendar_year"], e["month_number"])
        )
        baselines = [e for e in entries_sorted if e["is_baseline"]]
        hotpatches = [e for e in entries_sorted if not e["is_baseline"]]
        out["calendar"][os_key] = {
            "row_count": len(entries_sorted),
            "baseline_count": len(baselines),
            "hotpatch_count": len(hotpatches),
            "earliest_calendar_year": min(e["calendar_year"] for e in entries_sorted),
            "latest_calendar_year": max(e["calendar_year"] for e in entries_sorted),
            "baseline_months_observed": sorted({e["month_number"] for e in baselines}),
            "hotpatch_months_observed": sorted({e["month_number"] for e in hotpatches}),
            "entries": entries_sorted,
        }

    for os_key in ("Server2025", "Server2022"):
        inferred: list[dict] = []
        for r in releases:
            if r["os_short_name"] != os_key:
                continue
            if r["update_type_letter"] != "B":
                continue
            is_baseline = r["update_type_month"] in HOTPATCH_BASELINE_MONTHS
            inferred.append(
                {
                    "year_month": (
                        f"{r['update_type_year']:04d}-"
                        f"{r['update_type_month']:02d}"
                    ),
                    "availability_date": r["availability_date"],
                    "kb_id": r["kb_id"],
                    "build_after_update": r["build_after_update"],
                    "is_hotpatch_baseline_month": is_baseline,
                }
            )
        inferred.sort(key=lambda x: x["year_month"])
        out["inferred_from_monthly_b_releases"][os_key] = {
            "row_count": len(inferred),
            "baseline_month_count": sum(
                1 for r in inferred if r["is_hotpatch_baseline_month"]
            ),
            "rows": inferred,
        }

    out_path = FIXTURE_DIR / "baseline-month-detection.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    return out_path


def write_letter_frequency(releases: list[dict]) -> pathlib.Path:
    freq: dict[str, collections.Counter] = collections.defaultdict(
        collections.Counter
    )
    for r in releases:
        freq[r["os_short_name"]][r["update_type_letter"]] += 1

    out: dict = {}
    for os_key, counter in freq.items():
        total = sum(counter.values())
        out[os_key] = {
            "total_rows": total,
            "letters": dict(
                sorted(counter.items(), key=lambda kv: kv[1], reverse=True)
            ),
            "letter_share_pct": {
                k: round(100 * v / total, 1) for k, v in counter.items()
            },
        }

    out_path = FIXTURE_DIR / "letter-frequency.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    return out_path


def write_coverage_summary(releases: list[dict]) -> pathlib.Path:
    by_os: dict[str, set[str]] = collections.defaultdict(set)
    for r in releases:
        y, m = r["update_type_year"], r["update_type_month"]
        if y == 0 or m == 0:
            continue
        by_os[r["os_short_name"]].add(f"{y:04d}-{m:02d}")

    out: dict = {}
    for os_key, months in by_os.items():
        sorted_months = sorted(months)
        earliest = sorted_months[0]
        latest = sorted_months[-1]

        ey, em = (int(x) for x in earliest.split("-"))
        ly, lm = (int(x) for x in latest.split("-"))
        gaps: list[str] = []
        y, m = ey, em
        while (y, m) <= (ly, lm):
            ym = f"{y:04d}-{m:02d}"
            if ym not in months:
                gaps.append(ym)
            m += 1
            if m > 12:
                m = 1
                y += 1

        out[os_key] = {
            "earliest_published_month": earliest,
            "latest_published_month": latest,
            "months_covered": len(months),
            "gap_count": len(gaps),
            "gaps": gaps,
        }

    out_path = FIXTURE_DIR / "coverage-summary.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    return out_path


def main() -> int:
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    parsed = load_parsed()
    releases = parsed["releases"]

    print(
        f"Analysing {len(releases):,} release rows from "
        f"{parsed['source_snapshot']}"
    )
    print()

    p1 = write_update_type_summary_csv(releases)
    print(f"  -> {p1.relative_to(TESTS_DIR)}")
    p2 = write_baseline_month_detection(releases, parsed)
    print(f"  -> {p2.relative_to(TESTS_DIR)}")
    p3 = write_letter_frequency(releases)
    print(f"  -> {p3.relative_to(TESTS_DIR)}")
    p4 = write_coverage_summary(releases)
    print(f"  -> {p4.relative_to(TESTS_DIR)}")

    print()
    print("Headline numbers:")
    cov = json.loads(p4.read_text(encoding="utf-8"))
    for os_key in ("Server2016", "Server2019", "Server2022", "Server2025"):
        if os_key not in cov:
            continue
        c = cov[os_key]
        print(
            f"  {os_key}: {c['months_covered']} months covered "
            f"({c['earliest_published_month']} -> {c['latest_published_month']}), "
            f"{c['gap_count']} gap(s)"
        )

    baseline = json.loads(p2.read_text(encoding="utf-8"))
    print()
    print("Hotpatch calendar coverage (authoritative source):")
    for os_key in ("Server2025", "Server2022"):
        cal = baseline.get("calendar", {}).get(os_key, {})
        if not cal:
            continue
        print(
            f"  {os_key}: CY{cal['earliest_calendar_year']}..{cal['latest_calendar_year']}, "
            f"{cal['baseline_count']} baseline + {cal['hotpatch_count']} hotpatch rows, "
            f"baseline-months observed = {cal['baseline_months_observed']}"
        )

    print()
    print(
        "OK. Open the fixtures/poc_release_info/ files for the full "
        "picture, then read docs/poc/poc-release-info-report.md for "
        "the PoC conclusions."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
