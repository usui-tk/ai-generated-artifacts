# PoC Report: Online Patch Metadata Acquisition (`release_info` topic)

**Phase**: r06 Phase 2
**Date**: 2026-05-25
**Snapshot**: `tests/snapshots/poc_release_info/release-info-2026-05-25.md` (68,360 bytes)
**Source URL**: `https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info?accept=text/markdown`

Companion: [`poc-release-info-readme.md`](./poc-release-info-readme.md)
(how to reproduce the runs that produced this report).

## TL;DR

The Microsoft Learn release-info page, served as plain Markdown via
`?accept=text/markdown`, is a **viable authentication-free metadata
source** for Windows Server LCU KB numbers, build numbers, and the
Hotpatch baseline calendar. It is **not** a complete source: .NET
Framework CU, Dynamic Update.Setup, Dynamic Update.SafeOs, and the
language-specific patches are **not present** and need a separate
mechanism (most likely the existing Update Catalog scrape, restricted
to URL resolution rather than KB discovery).

The page also contains a previously-uncatalogued (by us) **Hotpatch
calendar table** that publishes the full year of baseline-vs-hotpatch
month assignments for Server 2025 and Server 2022, including
forward-looking entries for months Microsoft has scheduled but not
yet released. This single discovery resolves PoC question D entirely.

Recommended Phase 3 architecture, in one sentence: the Refresher
loads the release-info Markdown to confirm what KB numbers exist for
each OS each month, then asks the Catalog only for the MSU / CAB
download URL keyed by that KB -- eliminating most of the title-string
heuristics catalogued in SPEC.md §D.19 / §D.20 / §D.21.

## Data observed

### Monthly release table coverage

| OS          | Earliest published month | Latest published month | Months covered | Gaps |
| ----------- | ------------------------ | ---------------------- | -------------- | ---- |
| Server 2016 | 2016-08                  | 2026-05                | 117            | 1    |
| Server 2019 | 2018-10                  | 2026-05                | 92             | 0    |
| Server 2022 | 2021-08                  | 2026-05                | 58             | 0    |
| Server 2025 | 2024-10                  | 2026-05                | 20             | 0    |

The single Server 2016 gap is in 2016-09 (the GA month had no
patches published in that month). Server 2019 / 2022 / 2025 have
zero gaps across their entire publishing history, which is a strong
signal that the release-info page is the *primary* place Microsoft
tracks "what was the LCU this month".

### Hotpatch calendar table coverage

| OS          | Calendar years available | Baseline rows | Hotpatch rows | Baseline months observed |
| ----------- | ------------------------ | ------------- | ------------- | ------------------------ |
| Server 2025 | CY2024 ... CY2026        | 8             | 18            | 1, 4, 7, 10              |
| Server 2022 | CY2024 ... CY2026        | 13            | 23            | 1, 4, 7, **8**, 10       |

The "8" in the Server 2022 baseline months is a single historical
anomaly: CY2024 August was labelled "Baseline (Restart)" in the
calendar, while CY2025 August and CY2026 August are "Hotpatch" as
expected. The most likely explanation is that Microsoft adjusted
the Server 2022 baseline cadence between CY2024 and CY2025 to align
with the canonical Jan/Apr/Jul/Oct pattern. The PoC concludes that
**the authoritative baseline-month list is the per-row `Type` field**,
not a fixed `{1, 4, 7, 10}` constant.

### Update type letter frequency

| OS          | Total rows | B (Patch Tuesday) | OOB | C (preview) | D | A | E |
| ----------- | ---------- | ----------------- | --- | ----------- | - | - | - |
| Server 2016 | 187        | 118 (63.1%)       | 32  | 32          | 3 | 1 | 1 |
| Server 2019 | 165        | 92 (55.8%)        | 31  | 36          | 5 | 1 | 0 |
| Server 2022 | 89         | 57 (64.0%)        | 17  | 15          | 0 | 0 | 0 |
| Server 2025 | 30         | 19 (63.3%)        | 10  | 0           | 0 | 1 | 0 |

Reading the table together with SPEC.md §B.21.1:

* "B" letters appear in every covered month for every OS in scope,
  which is consistent with `LCU = Required, monthly`.
* "OOB" presence varies; the data confirms `Out-of-band = Possible`.
  Server 2025 has a notably high OOB share (10 of 30 rows) because
  its 20-month publishing history overlaps with a period of unusual
  out-of-band activity (Secure Boot certificate rollover, WSUS
  CVE-2025-59287 advisories, .NET Framework 4.8.1 hotfixes).
* "C" and "D" are preview rollups (Microsoft documentation calls
  these "non-security preview updates"). They are not security
  updates and the ISO Factory should ignore them entirely. The data
  shows Server 2025 has *zero* C or D rows -- Microsoft appears to
  have discontinued the preview-rollup cadence for the 24H2-based
  Server line, which simplifies the Phase 3 filter.
* The single "E" row on Server 2016 is `2016-08 E` (KB3176938 dated
  2016-08-31), an early-life-of-OS artifact. The parser handles it
  but downstream logic can safely ignore E entries as historical.

## PoC questions: results

### Question A: Markdown rendering works

**Answer: Yes.** The endpoint returns `Content-Type: text/markdown;
charset=utf-8` and the body is the source Markdown table verbatim,
no HTML wrappers. The `?accept=text/markdown` switch is a
documented Microsoft Learn content-negotiation feature. No
authentication, no rate-limiting headers observed, no User-Agent
restrictions encountered during this PoC.

The page YAML front-matter exposes `gitcommit` and `git_commit_id`
fields pointing to
`https://github.com/MicrosoftDocs/windows-release-pr/blob/live/windows/release-information/windows-server-release-info.md`,
which means the entire page is version-controlled by Microsoft in a
public GitHub repo. A future hardening step could pin to a specific
commit hash for reproducibility.

### Question B: Markdown parses deterministically

**Answer: Yes.** The release-info page uses two distinct table
layouts:

1. The monthly release tables under "## Windows Server release
   history", with header
   `| Servicing option | Update type | Availability date | Build | KB article |`.
2. The hotpatch calendar tables under "## Windows Server hotpatch
   calendar", with header
   `| Month | Update type | Type | Availability date | Build | KB article |`.

Both are easily parsed by `poc_release_info_02_parse.py` (~290 lines
of standard-library Python, no external dependencies). The parser
validates header text exactly and refuses to continue if Microsoft
changes the column order or names, which is the desired behaviour
(human review of the diff before downstream automation kicks in).

### Question C: Update types match SPEC.md §B.21.1

**Answer: Mostly yes, with documented refinements.**

The data confirms the spirit of SPEC.md §B.21.1: every OS has
monthly B releases, OOB is possible but rare, preview rollups exist
for older OSes and not Server 2025. But two findings warrant
amending the SPEC text in Phase 3:

* SPEC.md §B.21.1's "SSU (standalone)" row is **not validatable from
  release-info alone**. The release-info page lists only LCU / OOB
  / preview entries, not SSU packages. The earlier finding that the
  2026-05 r05.1 baseline had no Server 2019 SSU entry could not be
  cross-checked against release-info because there is nothing to
  cross-check against. Resolution: keep SSU presence detection on
  the Catalog path; Phase 3 should not promise that release-info
  validates SSU.

* SPEC.md §B.21.1's "Hotpatch" row for Server 2022 currently reads
  "Azure Edition only". The hotpatch calendar table covers
  **non-Azure-Edition Server 2022** as well (the calendar is
  published as a generic Server 2022 table). Phase 3 should refine
  this cell to "Datacenter: Azure Edition (always) + Standard /
  Datacenter (via Azure Arc subscription)".

### Question D: Hotpatch baseline detection

**Answer: Yes, and the release-info hotpatch calendar is the
authoritative source.**

The PoC's `poc_release_info_03_analyse.py` extracts the calendar
table for both Server 2022 and Server 2025, including future months
that Microsoft has scheduled but not yet released
(`availability_date` and `kb_id` are empty for unreleased rows).

This means an ISO Factory wanting to honour "build from a
baseline-month LCU when possible" (SPEC.md §B.21.4) can read the
calendar directly. It does not need to compute baseline-vs-hotpatch
from a fixed `{1, 4, 7, 10}` rule, which would have given a wrong
answer for CY2024 August Server 2022 (see "Hotpatch calendar
coverage" above).

### Question E: .NET / Dynamic Update / Language Pack

**Answer: Not present in release-info.** This is a definitive
*absence*, not a parser limitation. The release-info page tracks
only the OS-level cumulative LCU (and the hotpatch calendar); .NET
Framework cumulative updates, Dynamic Update.Setup, Dynamic
Update.SafeOs, and language packs each have their own release
cadence and are published in different documentation locations:

* **.NET Framework CU**: monthly KB pages under
  `https://learn.microsoft.com/dotnet/framework/release-notes/`,
  e.g. the "April 2026 cumulative update" page. This is parseable,
  but not in Markdown table form -- the .NET pages list per-runtime
  KBs in plain prose. Not yet investigated by this PoC.
* **Dynamic Update.Setup / SafeOs**: these are not published on a
  dedicated Microsoft Learn page; they appear only on individual
  KB pages and on the Microsoft Update Catalog. Catalog scraping
  remains the primary mechanism here.
* **Language Pack**: similar to Dynamic Update -- only on Catalog.

Phase 3 should therefore plan for a **hybrid Refresher**:
release-info for LCU/Hotpatch, Catalog for .NET CU and DU and
language packs (using the KB from release-info as the seed for the
Catalog query, so the title-string heuristics in the Catalog path
can be reduced or removed). Investigating whether the .NET
release-notes pages provide a stable Markdown table is a Phase 3
task; out of scope for this PoC.

### Question F: Format stability

**Answer: Strong stability signal from the GitHub-backed source.**

The page metadata (YAML front-matter) shows the source file is
`windows/release-information/windows-server-release-info.md` in the
`MicrosoftDocs/windows-release-pr` GitHub repo. Cross-referencing
commit IDs over time (a Phase 3 follow-up task) would let us detect
structural changes within 24 hours by polling `/commits` for that
file.

The parser was written in a single afternoon against the snapshot
captured in this PoC, and required only one fix (handling the
hotpatch calendar's 6-column header in addition to the monthly
table's 5-column header). The historical 'E' letter in some 2016-08
Server 2016 rows was also handled with a one-line regex change.
These are the kinds of edge cases that argue for keeping the parser
strict and review-driven rather than tolerant of arbitrary
structural drift.

## Recommendations for Phase 3

These are recommendations, not commitments. Phase 3 design decisions
belong in their own discussion.

1. **Add a release-info Refresher path alongside the Catalog
   Refresher.** The release-info path provides KB numbers and build
   numbers per OS per month, with the hotpatch calendar as an
   authoritative bonus. The Catalog Refresher stays but becomes the
   *URL resolver* (given a KB, find the MSU/CAB download URL)
   rather than the *KB discoverer* (given a month, find titled
   strings that look like LCUs). This removes most of SPEC.md §D.19
   and §D.20 from the surface area.

2. **Do not modify Schema 2.1 in Phase 3 unless necessary.** The
   candidate `Common.UpdateTypePolicy` block sketched in SPEC.md
   §B.21.5 is still useful for documenting per-OS expectations, but
   the release-info Markdown approach makes per-OS quirks visible at
   runtime without needing on-disk policy. A minimal Schema 2.2
   might add only a single `Common.HotpatchCadence` enum:
   `not-applicable` (Server 2016 / 2019) vs `quarterly-via-azure-arc`
   (Server 2022 / 2025).

3. **Treat .NET CU and Dynamic Update separately.** Their discovery
   cannot be moved off Catalog scraping by release-info alone.
   Phase 3 should investigate whether the .NET release-notes pages
   (under `learn.microsoft.com/dotnet/framework/`) have a similar
   Markdown rendering and structured tables; if yes, those can be
   added to the release-info-style data path. If no, Catalog
   scraping stays in place for .NET as well, and the Refresher uses
   release-info LCU KB numbers as a sanity check that the right
   Patch Tuesday was scraped.

4. **Pin to a Markdown snapshot per Patch Tuesday.** Microsoft
   updates the live page within a few hours of Patch Tuesday. A CI
   workflow could fetch the page, commit the snapshot into the repo
   under `tests/snapshots/poc_release_info/`, and only then run the
   Refresher. This gives reproducible runs even if Microsoft
   restructures the page mid-month.

5. **Hotpatch ISO integration remains out of scope.** The PoC
   confirmed that the hotpatch calendar is queryable, but nothing
   in the data suggests that hotpatch packages can be
   `Add-WindowsPackage`'d into a mounted offline WIM. SPEC.md §B.21.4's
   conclusion ("Hotpatch is out of scope for the offline image")
   stands. The hotpatch calendar is useful only for the future
   `-PreferBaselineMonthLcu` switch contemplated in SPEC.md §B.21.4
   -- the ISO Factory can build a Server 2025 image from a
   Jan/Apr/Jul/Oct baseline LCU so a fresh deploy can enrol in
   hotpatching without an immediate baseline-update reboot.

## Open questions for Phase 3

These were *not* answered by this PoC and would be the first items
on a Phase 3 PoC-2:

* Are the `.NET Framework release notes` pages
  (`learn.microsoft.com/dotnet/framework/release-notes/`) served as
  Markdown via the same `?accept=text/markdown` switch, and do they
  have stable structured tables?
* Is there a release-info-equivalent page for Dynamic Update
  packages, or is the only authoritative source the Microsoft
  Update Catalog?
* What is the Update Catalog query latency for "find UpdateId by
  exact KB number" (i.e., the URL-resolver use case)? The r05.x
  `Get-UpdateIdFromCatalog` already does this; Phase 3 should
  measure the additional load that the new architecture would put
  on the Catalog.
* Does the release-info Markdown ever change between Patch Tuesday
  and the following week? The single PoC snapshot cannot answer
  this; one weekly snapshot for two months would.

## What got committed where

This Phase 2 PoC is intentionally self-contained, and obeys the
file-organisation rules in SPEC.md §B.22:

```
scripts/powershell/update-windows-server-iso/
├── tests/
│   ├── poc_release_info_01_fetch.py
│   ├── poc_release_info_02_parse.py
│   ├── poc_release_info_03_analyse.py
│   ├── snapshots/poc_release_info/
│   │   ├── .gitattributes
│   │   ├── release-info-2026-05-25.md       (raw Markdown, 68 KB)
│   │   └── release-info-2026-05-25.meta.json
│   └── fixtures/poc_release_info/
│       ├── release-info.json                (parsed structured form)
│       ├── update-type-summary.csv
│       ├── baseline-month-detection.json
│       ├── letter-frequency.json
│       └── coverage-summary.json
└── docs/poc/
    ├── poc-release-info-readme.md           (how to run)
    └── poc-release-info-report.md           (this file)
```

No changes to `Update-WindowsServerIso.ps1`. No changes to any
`Config/<OsKey>.json`. No changes to the T1-T5 regression tests.
The PoC artefacts can be deleted in a single `rm -rf` of the
listed paths once Phase 3 is implemented or abandoned.
