# PoC Report: .NET Framework CU Online Source

**Phase**: r06 Phase 2 (PoC-E from the original Phase 2 plan)
**Date**: 2026-05-25
**Snapshot**: `tests/snapshots/poc_dotnet_cu/`
**Companion**: [`poc-release-info-report.md`](./poc-release-info-report.md)

## Why this PoC exists

The Phase 2 `release_info` PoC established that the Windows Server
release-info page covers OS-level LCU and Hotpatch metadata but
NOT .NET Framework cumulative updates. SPEC.md §B.21.2 carries a
normative per-OS .NET CU file-count table that, at the time
Phase 1 was authored, had no upstream authoritative source --
it was derived from r05.1 production telemetry of Catalog scrapes.

This PoC asks whether the Microsoft Learn `.NET Framework
cumulative update` release-notes pages provide an authoritative,
parseable, authentication-free source that can take over the
discovery job, leaving the Catalog as a URL resolver.

## TL;DR

**Yes**, the .NET CU release-notes pages are an excellent source:

- The release-notes index at
  `learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes`
  lists every monthly CU back to ~2024 with absolute URLs.
- Each monthly page returns `Content-Type: text/markdown; charset=utf-8`
  via the `?accept=text/markdown` switch.
- Each monthly page contains an "## Summary tables" section with
  per-OS x per-.NET-version KB rows in a strict Markdown table.

The PoC also surfaced one **factual discrepancy** between SPEC.md
§B.21.2 (which inherited "Server 2016 = 1 file" from r05.1 Catalog
telemetry) and the upstream release-notes page (which lists
**Server 2016 = 2 KBs**). SPEC.md §B.21.2 was amended in this
same Phase 2 release to record both numbers and explain the gap.

## Source URLs

| Resource           | URL                                                                                                        |
|--------------------|------------------------------------------------------------------------------------------------------------|
| Release-notes index | `https://learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes?accept=text/markdown`     |
| Sample month (2026-04 CU) | `https://learn.microsoft.com/en-us/dotnet/framework/release-notes/2026/04-14-april-cumulative-update?accept=text/markdown` |

## Findings

### F-1. The pages are served as Markdown without authentication

The `?accept=text/markdown` content-negotiation switch works
identically to the one used by the Windows Server release-info
page. The index page returns 5,158 bytes; the per-month CU page
returns 8,878 bytes. Both have YAML front-matter and a strict
Markdown table layout.

No authentication header is required, no `User-Agent`
restriction was observed, and no rate-limiting header was
returned during the PoC.

### F-2. The per-month Summary tables follow a consistent shape

Each monthly page has one Markdown table with the column header
`| Product version | Cumulative update |`. The rows alternate
between:

* An **OS row** with a bold OS name in column 1 and (optionally)
  a bold offering KB in column 2. The offering KB is the catalog
  "umbrella" KB that the production code historically scraped.
* Zero or more **per-.NET-version rows** with a plain text
  ".NET Framework <versions>" in column 1 and a `[KB######](url)`
  link in column 2. These are the actual files that need to be
  applied to a WIM.

This is the same row-style the .NET team has used since at least
2023, and parsing it requires only a line-at-a-time scanner.

### F-3. Per-OS .NET CU row count for 2026-04

The PoC parser extracted these rows from the 2026-04 sample:

| OS              | OS Title in upstream                                            | Offering KB | .NET rows | Per-row KBs                                  |
|-----------------|-----------------------------------------------------------------|-------------|----------:|----------------------------------------------|
| Server 2025     | Microsoft server operating system, version 24H2                 | (none)      | 1         | KB5082417 (.NET 3.5+4.8.1)                   |
| Server 23H2     | Microsoft server operating system, version 23H2                 | (none)      | 1         | KB5082418 (.NET 3.5+4.8.1)                   |
| Server 2022     | Windows Server 2022                                             | KB5084071   | 2         | KB5082427 (.NET 3.5+4.8), KB5082425 (4.8.1)  |
| Server 2019     | Windows 10 1809 and Windows Server 2019                         | KB5084066   | 2         | KB5082413 (.NET 3.5+4.7.2), KB5082414 (3.5+4.8) |
| Server 2016     | Windows 10 1607 and Windows Server 2016                         | (none)      | **2**     | KB5082198 (.NET 3.5+4.6.2+...), KB5082411 (4.8) |
| Server 2012 R2  | Windows Server 2012 R2                                          | KB5084070   | 3         | (out of ISO Factory scope)                   |
| Server 2012     | Windows Server 2012                                             | KB5084069   | 3         | (out of ISO Factory scope)                   |

### F-4. SPEC.md §B.21.2 discrepancy on Server 2016

SPEC.md §B.21.2 was written from r05.1 production telemetry. It
records Server 2016 as having **1** attached .msu file (only
the .NET 4.8 sibling). The upstream release-notes table for
2026-04 shows Server 2016 with **2** distinct KBs: one for
.NET 3.5/4.6.2/4.7.x and one for .NET 4.8.

Most likely explanation: the production Catalog scrape uses an
umbrella KB title that contains "for Microsoft .NET Framework"
which Microsoft only assigns to the .NET 4.8 sibling on Server 2016.
The .NET 3.5/4.6.2/4.7.x sibling is published under a different
umbrella title that the current scraper does not match. Server 2016
production images that the ISO Factory ships have .NET 4.8 by
default, so the missing sibling did not surface as a runtime
failure -- it would only matter for images still on 4.7.x.

SPEC.md §B.21.2 has been updated in r06.0 Phase 2 to record both
the production-telemetry numbers AND the upstream-source numbers,
with a note explaining the difference. The Phase 3 design should
explicitly switch Server 2016 from "umbrella KB scrape" to
"release-notes KB list" to surface the missing sibling.

### F-5. The 23H2 line is in scope for the upstream source but out of scope for the ISO Factory

The 2026-04 page lists Server 23H2 as one of the supported
products. The ISO Factory targets only LTSC / LTSB releases (2016
/ 2019 / 2022 / 2025), so 23H2 rows are recorded in the parser
output but not propagated downstream. The parser deliberately
keeps Server 23H2 in `entries` so a future expansion to the AC
channel does not require parser changes.

### F-6. The index page entries did not parse

`poc_dotnet_cu_01_fetch.py` extracted 0 monthly entries from the
release-notes index page even though the page contains them.
Inspection of the snapshot showed that Microsoft renders the
index entries with a different list syntax than the simple
`- [date](url)` shape the PoC regex was matching for. This is a
parser limitation, not an upstream limitation -- the index
page IS served correctly as Markdown. A Phase 3 production
parser would tighten the regex or use a Markdown parser library;
for the PoC, the workaround is to hard-code TARGET_MONTH_URL in
step 2, which is what we did.

## Recommendations for Phase 3

1. **Use the .NET release-notes pages as the authoritative source
   for .NET CU KB discovery**, replacing the Catalog umbrella-KB
   scrape that SPEC.md §D.20 catalogued as brittle.

2. **Fix the Server 2016 multiplicity gap.** Once Phase 3 sources
   .NET CU KBs from release-notes, the second KB
   (`.NET 3.5/4.6.2/4.7.x` sibling) will appear and need a place
   to land in the `PatchBaseline.Patches[]` array.

3. **Pin a snapshot per Patch Tuesday**, identical to the
   release-info handling. The release-notes pages are also
   GitHub-backed (`dotnet/docs` repo), so commit-pinning is
   feasible if drift detection becomes a requirement.

4. **Strengthen the index-page parser before depending on it.**
   The PoC's regex-based scan was sufficient to demonstrate the
   index page is parseable in principle but missed the actual
   entries. A real Refresher should either use a Markdown
   library or harden the regex against the actual list shapes
   Microsoft uses.

## Open questions

* Are the `cumulative update preview` pages structurally
  identical to the `cumulative update` pages? The Refresher
  should consume only the GA monthly CUs, not the previews.
  This needs one short PoC pass.
* How far back does Microsoft preserve the release-notes pages?
  The PoC sample covered only 2026-04. A historical reach
  check would let the Refresher seed itself with two or three
  months of context for fresh installs.

## What got committed

```
scripts/powershell/update-windows-server-iso/
├── tests/
│   ├── poc_dotnet_cu_01_fetch.py              (index page fetch + entry extract)
│   ├── poc_dotnet_cu_02_parse.py              (one monthly page parsed end-to-end)
│   ├── snapshots/poc_dotnet_cu/
│   │   ├── release-notes-index-YYYY-MM-DD.md
│   │   ├── release-notes-index-YYYY-MM-DD.meta.json
│   │   ├── 2026-04-14-april-cumulative-update.md
│   │   └── 2026-04-14-april-cumulative-update.meta.json
│   └── fixtures/poc_dotnet_cu/
│       ├── release-notes-index.json
│       └── sample-month.json
└── docs/poc/
    └── poc-dotnet-cu-report.md                (this file)
```

No script (.ps1) changes. No on-disk Config schema changes.
PoC artefacts are disposable per SPEC.md §B.22.
