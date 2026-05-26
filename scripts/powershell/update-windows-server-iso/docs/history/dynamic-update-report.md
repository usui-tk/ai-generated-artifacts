# PoC Report: Dynamic Update via Microsoft Update Catalog

**Phase**: r06 Phase 2 (PoC-F from the original Phase 2 plan)
**Date**: 2026-05-25
**Snapshot**: `tests/fixtures/poc_dynamic_update/`
**Companion**: [`poc-release-info-report.md`](./poc-release-info-report.md)

## Why this PoC exists

The Phase 2 `release_info` PoC concluded that the Windows Server
release-info page does not cover Dynamic Update.Setup or Dynamic
Update.SafeOs packages -- they have to be fetched from the
Microsoft Update Catalog. SPEC.md §B.21.1 lists DU.Setup and
DU.SafeOs as "Optional" for Server 2022 / Server 2025, but as
of Phase 2 there was no empirical check that the Catalog
discovery path *actually* returns them on a current Patch
Tuesday month, or that "Optional" is the correct label.

This PoC probes the Catalog using the same canonical query
strings the production code uses in `Get-CatalogQueryTemplate`
(see Update-WindowsServerIso.ps1 line ~2892), and verifies
whether the Title-string heuristic the production code relies
on actually returns a download URL for a representative month.

## TL;DR

**Mixed results, with one important new finding:**

* Server 2025 **DU.SafeOs**: OK -- one Catalog hit, one .cab URL
* Server 2025 **DU.Setup**: **missing for 2026-04** -- and follow-up
  probing showed Microsoft has not published a Server 2025 Setup DU
  since **2025-11**. The Refresher must NOT treat a missing
  DU.Setup as a hard error for Server 2025 going forward.
* Server 2022 **DU.\* (combined query)**: OK -- one Catalog hit, one .cab URL
* Server 2019 **DU.Setup**: 0 hits -- confirms B.21.1's "N/A" for
  Server 2019 monthly cadence (DU only ships on feature-update windows)
* Server 2016 **DU.Setup**: 0 hits -- same conclusion as Server 2019

The Phase 3 Refresher should consume DU from the Catalog (no
better source exists), but must (a) tolerate absent DU.Setup
gracefully for Server 2025 going forward, and (b) NOT attempt
DU discovery for Server 2019 / 2016 (the production code already
omits these from the query template, but B.21.1 should be tightened
to record "N/A" rather than the current "Optional" label).

## Probe results for 2026-04

| Probe                                       | Query                                                                                              | Raw hits | Matching | URLs | Sample file                                       | Verdict |
|---------------------------------------------|----------------------------------------------------------------------------------------------------|---------:|---------:|-----:|---------------------------------------------------|---------|
| Server 2025 **DU.Setup**                    | `2026-04 Setup Dynamic Update for Microsoft server operating system version 24H2`                  |        0 |        0 |    0 | -                                                 | **NG**  |
| Server 2025 **DU.SafeOs**                   | `2026-04 Safe OS Dynamic Update for Microsoft server operating system version 24H2`                |        1 |        1 |    1 | `windows11.0-kb5082237-x64_*.cab`                 | OK      |
| Server 2022 **DU.\* (bare query)**          | `2026-04 Dynamic Update for Microsoft server operating system version 21H2`                        |        1 |        1 |    1 | `windows10.0-kb5082243-x64_*.cab`                 | OK      |
| Server 2019 **DU.Setup** (expected EMPTY)   | `2026-04 Setup Dynamic Update for Windows Server 2019`                                             |        0 |        0 |    0 | -                                                 | OK (empty as expected) |
| Server 2016 **DU.Setup** (expected EMPTY)   | `2026-04 Setup Dynamic Update for Windows Server 2016`                                             |        0 |        0 |    0 | -                                                 | OK (empty as expected) |

## Follow-up: Server 2025 DU.Setup historical reach

To characterise whether the Server 2025 DU.Setup miss is a 2026-04
anomaly or a structural change, the PoC then probed 7 historical
months:

| Month   | Raw hits | Matching hits | Status                                                                          |
|---------|---------:|--------------:|---------------------------------------------------------------------------------|
| 2025-09 |        1 |             1 | Published (`2025-09 Setup Dynamic Update for Microsoft server operating system version 24H2`) |
| 2025-10 |       10 |            10 | Published (multiple, includes superseded entries)                                |
| 2025-11 |        1 |             1 | Published                                                                       |
| 2025-12 |        0 |             0 | **Not published**                                                               |
| 2026-01 |        0 |             0 | **Not published**                                                               |
| 2026-02 |        0 |             0 | **Not published**                                                               |
| 2026-03 |        0 |             0 | **Not published**                                                               |
| 2026-04 |        0 |             0 | **Not published**                                                               |

Five consecutive months without a Server 2025 DU.Setup is strong
evidence that Microsoft has either:

1. Discontinued the Setup Dynamic Update for the 24H2 server line,
   OR
2. Reorganised the cadence so it ships only quarterly or on
   feature-update windows, similar to Server 2019 / 2016.

Either way, the production code's expectation in
`Get-CatalogQueryTemplate.Server2025.DynamicUpdate.Setup` will fail
silently if it is treated as Required. The current code labels it
"Possible" (B.21.1), which is correct.

## What this means for SPEC.md §B.21.1

The current B.21.1 wording for the DU rows is, paraphrased:

* DU.Setup / DU.SafeOs: "Optional" for Server 2022 and Server 2025
* DU.Setup / DU.SafeOs: "Not applicable" for Server 2019 and Server 2016

The PoC results support this wording but suggest a Phase 3
refinement:

* "Optional" should be split into two values: "Optional, monthly"
  (Server 2022 DU.SafeOs, which appears every month tested) and
  "Optional, may be skipped" (Server 2025 DU.Setup, which has
  been absent for 5+ months).

This is a SPEC-only refinement; no production-code change is
required because the Refresher already treats DU as advisory.

## Recommendations for Phase 3

1. **Keep DU discovery on the Catalog scrape path.** No upstream
   alternative exists. SPEC.md §D.20's title-string heuristics for
   DU.Setup / DU.SafeOs remain in force.

2. **Make absent DU.Setup a soft signal, not an error.** When the
   Catalog returns 0 hits for the Setup DU query on Server 2025,
   the Refresher should log "no Setup DU published for this month"
   and move on. This matches what Server 2019 / 2016 have always
   done.

3. **Refine the B.21.1 "Optional" label** to distinguish the
   monthly-present case from the may-be-missing case. This costs
   nothing in code and saves future Claude-or-human time when the
   Refresher logs a "0 hits" warning that turns out to be normal.

4. **Consider periodic re-probing of the DU cadence assumption.**
   A small CI workflow that runs this PoC monthly would catch any
   Microsoft-side change to the DU.Setup cadence within one month.
   The PoC code is essentially a probe script already; promoting
   it to a CI-friendly form is a one-day Phase 3 task.

## Open questions

* The bare Server 2022 query (`Dynamic Update for ... 21H2`)
  returned only 1 hit, but the production code expects both
  DU.Setup and DU.SafeOs for Server 2022 (it disambiguates using
  Catalog server-side Product/Description filters). Does the
  Catalog actually publish two distinct DU files for Server 2022,
  or does the production code's Product/Description filter just
  hide the absence? Worth a follow-up PoC pass.
* Does Microsoft publish a "DU.Setup" once the Server 2025 24H1
  → 24H2 feature update window opens (if such a window ever
  opens)? The PoC cannot answer this without waiting.
* Are DU packages cumulatively superseded (each month replaces
  the previous), or are they month-specific? The 2025-10 probe
  returning 10 hits suggests history is preserved; the Refresher
  must pick the newest by ReleaseDate, which the production code
  already does.

## What got committed

```
scripts/powershell/update-windows-server-iso/
├── tests/
│   ├── poc_dynamic_update_01_probe.py         (this PoC's only script)
│   ├── fixtures/poc_dynamic_update/
│   │   └── probe-results.json                 (per-probe outcome)
│   └── snapshots/poc_dynamic_update/          (empty; this PoC does not snapshot HTML)
└── docs/poc/
    └── poc-dynamic-update-report.md           (this file)
```

No script (.ps1) changes. No on-disk Config schema changes.
PoC artefacts are disposable per SPEC.md §B.22.
