# Changelog

All notable changes to `Update-WindowsServerIso.ps1` (and its
companion files in this project directory) are documented in this
file. Per the repository-wide policy documented in the root
[`SPEC.md`](../../../SPEC.md), CI workflow changes are recorded here
too — not inside `.github/workflows/` — because this project is the
CI target.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The script version is held in `$Script:ScriptVersion` near the top of
the script and follows the
`update-wsi-<YYYY.MM.DD>-r<NN>` pattern.

## [Unreleased]

## [update-wsi-2026.05.26-r07.0] - 2026-05-26

**r07.0 — Phase 3 implementation (release-info-driven refresher; breaking change).**

This is the consolidated r07.0 release that ships the SPEC.md Phase 3
architecture defined in section B.23. Per SPEC B.23.10 the directory
rename, schema bump and refresher rewrite are mutually dependent and
ship as one atomic release; reviewers should treat the whole r07.0
section below as a single coherent change. The release was assembled
incrementally across six commits, each individually quality-gated;
those commits are listed top-down below for traceability.

The minor-version jump from r05 to r07 (skipping r06 as a code release)
follows SemVer for breaking changes: `Resolve-PatchSetFromCatalog` and
`Get-CatalogQueryTemplate` have been deleted, three new cache file
types under `data/` have appeared, and the Config schema field set has
gained the `Common.CatalogTitleTokens` extension. r06.0 stays
exclusively a documentation release (the SPEC + PoC effort committed in
`2935dbd` and `36f4d65`).

The Patch-Tuesday-driven cache refresh automation (SPEC B.23.7 step 1-4
automated) is **NOT** included in r07.0 per SPEC B.23.10; r07.0 ships
manual-trigger only and the automation is deferred to r07.x.

Cumulative quality-gate status at release: psa.py 0 / 0 / 0,
PSScriptAnalyzer 0 findings, PowerShell parse OK, T2 13 / T3 10 /
T6 13 / T7 16 / T8 20 / T9 18 / T10 18 = **108 / 108 assertions pass**.

### r07.0 Step 3 - Version bump and r07.0 finalisation (this release)

Mechanical release-finalisation commit. No behavioural change; the
preceding Step 1 + 2a + 2b set is what r07.0 actually ships.

- `$Script:ScriptVersion` bumped from `update-wsi-2026.05.25-r05.1`
  to `update-wsi-2026.05.26-r07.0`. The script's identity string
  now reflects the SemVer minor-jump documented in SPEC B.23.10.
- `SPEC.md` section B.23.10's "(current)" marker moved from r05.1
  to r07.0. Other r05.1 references in SPEC remain because they
  document historical behaviour or comparisons that motivate the
  r07.0 design; they are not "current version" claims.
- `CHANGELOG.md` `[Unreleased]` block sealed into
  `[update-wsi-2026.05.26-r07.0] - 2026-05-26` with this release
  header. A fresh empty `[Unreleased]` block is added on top for
  future r07.x work.

Quality-gate status: psa.py 0 / 0 / 0, PSScriptAnalyzer 0 findings,
PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13, T7 16/16,
T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108 PASS unchanged
from Step 2b Commit 4.

### r07.0 Step 2b (Refresher main-path migration part) - Cache-driven Resolve-PatchSetFromReleaseInfo replaces Title-scrape discovery (this release)

This commit lands the **second half** of the Step 2b work scheduled
in SPEC.md section B.23.1. The r05.1-era `Resolve-PatchSetFromCatalog`
function and its `Get-CatalogQueryTemplate` helper are **deleted**;
a new cache-driven `Resolve-PatchSetFromReleaseInfo` takes over,
backed by an offline-testable `Get-PatchSetFromReleaseInfoDiscovery`
helper. This is the atomic completion of SPEC B.23.1's "complete
migration" decision: KB discovery is no longer a Title-string
heuristic against the Microsoft Update Catalog; the Catalog now
serves as a **URL resolver only** (KB → download URL plus
supersedence). DU discovery continues via the Step 2a 36-month
cache (now consumed by the new function); LCU discovery comes from
the Step 2a release-info parser; .NET CU discovery comes from the
Step 2a .NET CU parser. URL-resolver narrowing uses the Step 2b
Commit 3 Config-driven `Test-CatalogTitleMatch` helper.

**Important: the discovery layer was validated against synthetic
caches whose shapes were lifted verbatim from the fresh
2026-05-26 captures** under `tests/snapshots/dotnet_cu/` and
`tests/fixtures/dynamic_update_cache/probe-results.json`. No PoC
fixture was consulted. Live observations grounded three
implementation choices:

1. **Server 2022 / Server 2019 .NET CU multi-row** per SPEC B.23.5
   B-2: the live monthly pages list two `.NET Framework` rows
   under "Windows Server 2022" (one for 4.8, one for 4.8.1) and
   under "Windows 10 1809 and Windows Server 2019" (one for 4.7.2,
   one for 4.8). `Get-PatchSetFromReleaseInfoDiscovery` emits ONE
   discovery record per row, so each becomes its own PatchBaseline
   entry. T10 asserts this against a synthetic cache that mirrors
   the live shape.
2. **Server 2025 Setup DU suspended since 2025-12** per SPEC
   B.23.6: the discovery function does NOT emit a DynamicUpdate.Setup
   record when the per-OS DU cache has no in-window entry. The
   test scenario for 2025-12 (no matching caches) returns zero
   records, confirming the defensive path.
3. **Combined LCU + bundled SSU** per SPEC B.23.5 B-1: the new
   orchestrator passes the LCU's full Catalog file list through
   `Select-AllCanonicalPatchFiles` rather than the
   single-file picker, so an LCU UpdateId carrying both an
   LCU.msu and an SSU.msu emits two PatchBaseline entries (one
   with Type=LCU and IsCombined=$true, one with Type=SSU as
   classified by filename heuristic in
   `Convert-CatalogPatchToBaselineEntry`).

**Deleted PowerShell functions**:

- `Resolve-PatchSetFromCatalog` -- 311 lines. The r05.1 Title-string
  scraper. Its responsibility moves to
  `Resolve-PatchSetFromReleaseInfo`.
- `Get-CatalogQueryTemplate` -- 84 lines. The hardcoded per-OS
  query-template + title-token table. SSU/LCU/DU/.NET query
  templates are no longer needed (discovery moved to caches); the
  TitleTokens portion was already moved to Config + helpers in
  Step 2b Commit 3, so the entire function is now dead code.

**New PowerShell functions** (added before
`Resolve-LanguageSpecificPatchesFromCatalog` to keep the catalog
scrapers grouped, with the new release-info path immediately
above):

- `Get-PatchSetFromReleaseInfoDiscovery` -- pure-cache lookup,
  reads `data/cache-release-info.json` (LCU),
  `data/cache-dotnet-cu.json` (.NET CU), and
  `data/cache-du-<OsVersion>.json` (DU) via the existing
  Step 2a path helpers. Performs no network I/O. Accepts
  `-DataDir` for tests so T10 can exercise it against a temp
  directory. Validates `-PatchMonth` against
  `Test-DynamicUpdatePatchMonth` (the YYYY-MM regex helper from
  Step 2a). Returns `pscustomobject[]` with fields
  `Type` / `KbId` / `UpdateId` / `SourceCache` / `SourceRow` /
  `DiscoveryNote`.
- `Resolve-PatchSetFromReleaseInfo` -- orchestrator. Same signature
  as the deleted `Resolve-PatchSetFromCatalog` (OsVersion,
  OsLanguage, PatchMonth, MaxRetries), plus the new optional
  `-DataDir` for test isolation. Returns the same PatchBaseline
  entry shape as the deleted function. SSU emerges from the
  LCU's Catalog bundle via filename heuristic; standalone-SSU
  discovery is intentionally omitted (Microsoft has embedded
  SSU in LCU for current monthly releases per SPEC B.23.5 B-1).

**Caller migration** (three sites, single-line rename each):

- Refresher dispatch table (the
  `PatchBaseline.NeutralPatches.Refresher` registry near the top
  of the script): `'Resolve-PatchSetFromCatalog'` ->
  `'Resolve-PatchSetFromReleaseInfo'`.
- P03 RefreshPatchBaseline phase: the
  `Invoke-SetupPhase03_RefreshPatchBaseline` worker that runs
  during `-Action PrepareSet` now calls
  `Resolve-PatchSetFromReleaseInfo`.
- A01 RefreshAllBaselines admin phase: the
  `Invoke-AdminPhaseA01_RefreshAllBaselines` worker that runs
  during `-Action RefreshAllBaselines` now dispatches to
  `Resolve-PatchSetFromReleaseInfo` for OSes whose field-group
  Refresher matches.

The new function's parameter list is a strict superset of the old
(adds `-DataDir`); existing call sites need no parameter changes.
Net effect on the call graph is a single function-name swap.

**Test surface** changes:

- T3 (`tests/powershell_harness.py`) removed three test cases
  that targeted `Get-CatalogQueryTemplate` (Server2022 dual
  TitleTokens, per-OS Type coverage, Server2022 QueryTemplate
  no-comma form). The function no longer exists. TitleTokens
  coverage is taken over by T9 against the new
  `Get-CatalogTitleTokenList` helper. T3 now reports 10 assertions
  (down from 13); no other T3 case changed.
- T10 (`tests/release_info_resolver_test.py`) new. 18 assertions
  across four discovery scenarios (Server 2025 / 2022 / 2019 for
  2026-05, plus Server 2025 for 2025-12 with no matching caches)
  plus defensive cases (empty data dir, invalid PatchMonth).
  Fixture file is
  `tests/fixtures/release_info_resolver/scenarios.json`,
  shape-matched to the live 2026-05-26 captures.

**No PoC code or fixtures consulted**. T10's fixture KBs, OS
labels and DU UpdateIds were taken from the live captures used
by T7 (`tests/snapshots/dotnet_cu/`) and T8
(`tests/fixtures/dynamic_update_cache/probe-results.json`). The
historical PoC scripts and `tests/snapshots/poc_*/`,
`tests/fixtures/poc_*/` directories were not touched.

**Refresher main path NOW switched**. The migration that SPEC
B.23.1 schedules is complete: KB discovery is cache-driven (LCU
from release-info, .NET CU from .NET CU parser, DU from per-OS
36-month cache), and the Microsoft Update Catalog is consulted
only as a URL resolver. The combined Step 2a + Step 2b set is now
ready for `-Action RefreshAllBaselines` end-to-end runs against
the new path; the only remaining r07.0 schedulable item is the
Patch-Tuesday-triggered cache refresh automation (SPEC B.23.7
step 1-4), which is deferred to r07.x per SPEC B.23.10.

**Net code delta**: -395 lines (deleted 311 + 84) + 395 lines
(added 200 for Resolve-PatchSetFromReleaseInfo + 195 for the
discovery helper). The deletion and addition are intentionally
proportional so the diff is reviewable as one atomic migration.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 **10/10** (down from
13), T6 13/13, T7 16/16, T8 20/20, T9 18/18, T10 **18/18**.
Cumulative: 108/108 assertions.

### r07.0 Step 2b (URL-resolver narrowing part) - Config-driven Catalog title token disambiguation (previous release)

This commit lands the **first half** of the Step 2b work scheduled
in SPEC.md section B.23.1. New PowerShell helpers move the per-OS
Microsoft Update Catalog `TitleTokens` list out of hardcoded
PowerShell tables and into the OS Config (`data/config-Server*.json`,
field `Common.CatalogTitleTokens`), and add a single narrow-filter
predicate that combines those positive tokens with a hardcoded
negative exclusion list. The next commit (Step 2b part 2) will
replace `Resolve-PatchSetFromCatalog` with
`Resolve-PatchSetFromReleaseInfo` and delete the bulk of the
Catalog Title-string discovery code; this commit prepares the
ground by formalising the URL-resolver narrowing surface that
the new caller will consume.

**Important: the design and the tokens themselves were validated
against fresh live Microsoft Update Catalog data captured on
2026-05-26**, not lifted from any PoC fixture. Two specific live
observations grounded the implementation:

1. **Same-KB client-variant fan-out for Server 2016 / 2019**. A
   bare KB query for Server 2019's .NET CU (KB5087066) returns
   three hits: one for `Windows Server 2019` and two for
   `Windows 10 Version 1809` (the matching client-OS kernel).
   Server 2016 / Windows 10 1607 shows the same fan-out. The
   `Common.CatalogTitleTokens = ["Windows Server 2019"]` for
   Server 2019 (and the analogous Server 2016 entry) correctly
   rejects the Windows 10 client variants without needing a
   negative token.
2. **ARM64 contamination on Server 2025 .NET CU**. The live
   Catalog returns both `for x64` and `for arm64` variants of
   the same KB; the hardcoded
   `$Script:CatalogTitleNegativeTokens = @('Windows 11', 'arm64')`
   list rejects the ARM64 variant case-insensitively.

**New PowerShell functions** (added to
`Update-WindowsServerIso.ps1` immediately before the existing
`Get-CatalogQueryTemplate`, inside the Microsoft Update Catalog
scraper section):

- `Get-CatalogTitleTokenList -OsVersion <name>` -- reads the OS
  Config and returns the `Common.CatalogTitleTokens` array.
  Returns an empty array when the field is absent (the SPEC
  default; the URL resolver then accepts the first matching hit).
  Tolerant of missing Config files (returns empty rather than
  throwing) so the function is safe to call from defensive paths.
- `Test-CatalogTitleMatch -OsVersion <name> -Title <title>` --
  predicate. Returns `$true` when the title matches the OS, i.e.
  contains ANY of the OS's positive tokens AND contains NONE of
  the `$Script:CatalogTitleNegativeTokens` negative tokens.
  Case-insensitive substring matching throughout. When the
  positive list is empty the predicate is permissive (still
  honours the negative list).

**New Script-level variable**:

- `$Script:CatalogTitleNegativeTokens = @('Windows 11', 'arm64')`
  -- the OS-uniform negative exclusion list. Hardcoded
  intentionally per SPEC B.23.2 because these exclusions are
  uniform across all in-scope OSes (every Server build rejects
  the Windows 11 client OS and the ARM64 architecture variant).

**Refactor of `Get-CatalogQueryTemplate`**: the per-OS
`TitleTokens` array literals were replaced with
`@(Get-CatalogTitleTokenList -OsVersion '<name>')` calls. The
function's return shape is unchanged -- `TitleTokens` is still a
`[string[]]` -- so all existing callers (Resolve-PatchSetFromCatalog
in particular) continue to work without changes. The Server2022
in-line comment was updated to point at SPEC B.23.2 and the
Config field as the source of truth.

**Behavioural delta from hardcoded -> Config-driven**:

- Server 2025: hardcoded list had 1 token; Config has 2.
  Permissive expansion -- old matches still match.
- Server 2022: hardcoded list had 2 tokens (both comma forms);
  Config has 3 (adds `Windows Server 2022`). Permissive expansion.
- Server 2019 / 2016: identical content in hardcoded and Config
  (single-token lists). No behavioural change.

In every case the refactor STRICTLY EXPANDS coverage and never
narrows it, so no existing successful Catalog scrape can become
a failure on the new path. (Future Microsoft naming changes can
now be absorbed by editing the Config file, not by shipping a
new PowerShell release.)

**Refresher main path NOT changed**. `Resolve-PatchSetFromCatalog`
and its callers (P03 RefreshPatchBaseline phase and A01
RefreshAllBaselines admin phase) continue to drive
-Action RefreshAllBaselines unchanged. Step 2b part 2 will
introduce `Resolve-PatchSetFromReleaseInfo` and delete the
Catalog Title-string discovery code in a single atomic commit.

**OS Configs NOT changed by this commit**. The
`Common.CatalogTitleTokens` field was already present in all
four `data/config-Server*.json` files (apparently pre-populated
during SPEC B.23.2 authoring). The values match what live data
2026-05-26 validates as correct, so no Config edits were needed.
T9 protects the values against future drift.

**New regression test**: `tests/catalog_title_tokens_test.py`
(T9). Covers 18 assertions across: per-OS token sourcing from
all four `data/config-Server*.json` (4 assertions), missing-Config
defensive empty-list default (1 assertion), and 13 live-captured
narrow-filter cases including positive matches for all four
OSes, same-KB client-variant rejection (Windows 10 1607 / 1809),
negative-token exclusion (arm64, Windows 11), and Server 2022's
both comma forms. **All 18 assertions pass** under PowerShell
7.4 on Ubuntu 24.

**New files committed to the repo**:

- `tests/fixtures/catalog_title_tokens/expected-tokens.json` --
  the per-OS expected token lists (the assertion ground truth
  for `Get-CatalogTitleTokenList`).
- `tests/fixtures/catalog_title_tokens/narrow-filter-cases.json`
  -- 13 live-captured Catalog hit titles with the expected
  match decision per OS. Each case is annotated with a
  description explaining which token or negative exclusion
  drives the decision.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13,
T7 16/16, T8 20/20, T9 18/18. Cumulative: 93/93 assertions.

### r07.0 Step 2a (DU 36-month cache part) - Per-OS Dynamic Update cache and 36-month window selection (previous release)

This commit lands the **third half** of the Step 2a work scheduled
in SPEC.md section B.23.1. New PowerShell functions maintain a
per-OS Dynamic Update cache file (`data/cache-du-Server<NNNN>.json`)
that records Microsoft Update Catalog probe results across a
36-month rolling window, and select the latest in-window
successful publish at ISO-build time. The cache decouples
ISO-build runs from live Catalog scraping for DU discovery; an
out-of-band, Patch-Tuesday-triggered refresh action will
populate the cache in a later commit. The existing Refresher
main path (`Resolve-PatchSetFromCatalog`) is **untouched** and
continues to drive `-Action RefreshAllBaselines`. The Catalog
URL-resolver narrowing remains scheduled for Step 2b.

**Important: the design was validated against live Microsoft
Update Catalog probes captured on 2026-05-26**, not against the
single-month PoC fixture under
`tests/fixtures/poc_dynamic_update/probe-results.json`. Twelve
`(OS, DU type, patch month)` combinations were probed across
2026-05 / 2026-04 / 2026-03. The live results confirmed SPEC
§B.23.6:

- **Server 2025 Setup DU**: 0 hits for all three months, with
  the canonical `id="ctl00_catalogBody_noResultText"` marker
  present in the HTML. This matches "Suspended since 2025-12,
  5+ months" in the §B.23.6 cadence table.
- **Server 2025 SafeOs DU**: published monthly
  (KB5087588 / KB5082237 / KB5078794).
- **Server 2022 DU**: published monthly (KB5087595 / KB5082243;
  the 2026-03 probe failed with a transient SSL error and was
  retried via the fixture's synthetic entries).
- **Server 2019 Setup DU**: 0 hits for all three months,
  confirming the "feature-update windows only" annotation in
  §B.23.6.

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-DotNetCuCache` and the Microsoft Update Catalog
scraper section):

- `Get-DynamicUpdateCachePath` — path resolver per OS; accepts
  an optional `-DataDir` for tests.
- `New-EmptyDynamicUpdateCache` — fresh empty cache object for
  an OS with no persisted file yet.
- `Get-DynamicUpdateCache` — read the per-OS cache; **does not**
  throw on missing-file (returns an empty cache instead). This
  matches the "latest known good" stance from §B.23.6: an ISO
  build never aborts because a Patch-Tuesday refresh has not
  yet run for a given OS.
- `Save-DynamicUpdateCache` — persist with UTF-8 + LF + no-BOM,
  same conventions as the other r07.0 caches.
- `Test-DynamicUpdatePatchMonth` — validate `YYYY-MM` format.
- `Add-DynamicUpdateCacheEntry` — append-or-upsert one probe
  result. Same `(PatchMonth, DuType)` replaces in place
  (verified by the `upsert_same_key_latest_wins` T8 scenario);
  arrays use `@(...)` and Add-Member -Force pattern to avoid
  ConvertTo-Json single-element flattening.
- `ConvertTo-DynamicUpdatePatchMonthSortKey` — convert
  `YYYY-MM` to integer (yyyy*100+mm) for fast comparisons.
- `Get-DynamicUpdateWindowEarliestPatchMonth` — compute the
  earliest in-window month relative to a reference date;
  inclusive 36-month range (for `Now=2026-05` the earliest
  in-window month is 2023-06).
- `Get-LatestDynamicUpdate` — select the latest in-window
  successful entry for a given `(OsVersion, DuType)`; returns
  `$null` when no in-window entry has `Success=$true`. Window
  is anchored by `-Now` (default UTC now); tests pass a fixed
  `-Now` for reproducible assertions.
- `Remove-DynamicUpdateOutsideWindow` — drop entries earlier
  than the window; renamed from the proposed
  `Remove-DynamicUpdateOlderThan36Months` to satisfy
  PSScriptAnalyzer PSA6003's singular-noun rule (the "36" is
  baked into `Get-DynamicUpdateWindowEarliestPatchMonth`'s
  default).

**New Script-level variables**:

- `$Script:DynamicUpdateCacheWindowMonths = 36`
- `$Script:DynamicUpdateCacheSchema = '1.0'`

**Refresher main path NOT changed**. The existing Catalog scrape
in `Resolve-PatchSetFromCatalog` is unaffected. The DU cache is
populated and consumed by a separate code path that this commit
adds the data primitives for, but does not yet wire into a
production action; that wiring is scheduled for Step 2b.

**Testability hooks**. Every cache function accepts an optional
`-DataDir` parameter (default `''`) so T8 can route writes to a
temp directory without polluting `data/`. `Get-LatestDynamicUpdate`
and `Remove-DynamicUpdateOutsideWindow` accept an optional
`-Now` parameter (default `[datetime]::UtcNow`) so window
assertions are reproducible regardless of the wall clock. The
production path passes neither parameter and the defaults
restore the production behaviour exactly.

**Idempotent upsert**. `Add-DynamicUpdateCacheEntry` overwrites
any existing entry with the same `(PatchMonth, DuType)`. This
matters because the Patch-Tuesday refresh may probe the same
month multiple times during a single refresh cycle; only the
most recent probe should survive.

**Cross-OS isolation**. The per-OS cache file separation means
writes to `cache-du-Server2025.json` never affect
`cache-du-Server2022.json` and vice versa. Verified by the
`cross-OS isolation` scenario in T8.

**New files committed to the repo**:

- `tests/fixtures/dynamic_update_cache/probe-results.json` —
  the live Microsoft Update Catalog probe output from
  2026-05-26 (12 probe attempts, 8 successful, 1 SSL-error
  transient, 3 expected-empty confirmations per §B.23.6).
- `tests/fixtures/dynamic_update_cache/scenarios.json` —
  Python-generated reference scenarios combining the live probe
  entries with synthetic older months, plus the expected
  outcomes that PowerShell must reproduce.

**New regression test**: `tests/dynamic_update_cache_test.py`
(T8). Covers 20 assertions across three fixture scenarios
(server2025_live_then_setup_empty, server2022_with_old_synthetic,
upsert_same_key_latest_wins) plus three ad-hoc scenarios
(cross-OS isolation, missing-file empty cache, PatchMonth
validation rejection). Each scenario uses an isolated temp
directory via the `-DataDir` parameter and anchors the window
at `Now=2026-05-26T00:00:00Z`. **All 20 assertions pass** under
PowerShell 7.4 on Ubuntu 24.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13,
T7 16/16, T8 20/20.

### r07.0 Step 2a (.NET CU part) - PowerShell parser and aggregated raw/cache for the .NET Framework release-notes (previous release)

This commit lands the **second half** of the Step 2a work
scheduled in SPEC.md section B.23.1. New PowerShell functions
fetch and parse the Microsoft Learn `.NET Framework release
information` index plus every monthly cumulative-update
release-notes page it references, writing an aggregated raw JSON
and a parsed cache JSON under `data/`. The existing Refresher
main path (`Resolve-PatchSetFromCatalog`) is **untouched** and
continues to drive `-Action RefreshAllBaselines`. The Dynamic
Update 36-month cache (per-OS `cache-du-Server<NNNN>.json`) and
the Catalog URL-resolver narrowing are scheduled for subsequent
r07.0 commits.

**Important: the data captured for the new parser was fetched
live from learn.microsoft.com on 2026-05-26**, not lifted from
the PoC snapshots under `tests/snapshots/poc_dotnet_cu/`. Doing
so surfaced two PoC-era assumptions that no longer hold against
current Microsoft Learn pages:

1. The index page now formats each entry as
   `- <DATE> - [<KIND>](<URL>)` (the date is **outside** the
   bracket pair and only the kind text is linked). The original
   PoC regex expected `- [<DATE> - <KIND>](<URL>)` and would
   match zero entries on the current page.
2. The monthly pages now place `## Summary tables` AFTER
   `## Known issues in this release`. The original PoC parser
   used `## Known issues` as the stop-marker for the
   tables-region walk, which on the current page would close the
   region before it ever opened. The new parser starts at
   `## Summary tables` and walks to the next `## ` heading or
   end-of-document.

The parser also tolerates the `**New Release**` badge that the
most-recent entry on the index carries, and preserves entries
whose strict %B date parse fails (the live index contains a
2024-10 entry typed "Octber 22, 2024" upstream).

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-ReleaseInfoCache` and the Microsoft Update Catalog
scraper section):

- `Get-DotNetCuRawPath` / `Get-DotNetCuCachePath` — path resolvers
  for the two new files under `data/`.
- `ConvertFrom-DotNetCuOsLabel` — maps the raw OS label printed
  in the release-notes table to a normalised short name (e.g.
  "Microsoft server operating system, version 24H2" -> `Server2025`).
  Order-sensitive substring matching: longer joint labels
  ("Windows 10 1607 and Windows Server 2016") win against the
  shorter pattern they contain.
- `Split-DotNetCuMarkdownFrontMatter` — strips the leading YAML
  block from a `?accept=text/markdown` response.
- `ConvertFrom-DotNetCuIndexMarkdown` — parses the index page;
  returns `EntryCount` / `Kinds` / `EarliestDate` / `LatestDate`
  / `Entries[]` with per-entry `DateText` / `Date` / `Kind` /
  `RelativeUrl` / `AbsoluteUrl`.
- `ConvertFrom-DotNetCuMarkdown` — parses a monthly page; emits
  `EntryCountTotal` / `EntryCountRecognised` / `RowsPerOs`
  (ordered hashtable) / `Entries[]` with per-OS-block `OsLabel`
  / `OsNormalised` / `OsOfferingKb` / `Rows[]`. Multiple
  sub-tables under the same `## Summary tables` heading are
  handled (current 2026-05 pages list three: Cumulative update,
  Security and quality rollup, .NET Framework 3.5 product
  update).
- `Invoke-DotNetCuFetch` — HTTPS fetch of the index URL plus
  every monthly URL it lists. Aggregates the bodies + HTTP
  headers + fetch timestamps into `data/raw-dotnet-cu.json`
  (UTF-8, LF, no-BOM). Per-month fetch failures are recorded as
  `Ok=false` entries with the error message so a single broken
  month does not lose the whole refresh.
- `Update-DotNetCuCache` — reads `raw-dotnet-cu.json`, runs both
  parsers, writes `data/cache-dotnet-cu.json`. Returns the cache
  path.
- `Get-DotNetCuCache` — reads `cache-dotnet-cu.json` for
  Refresher consumers. Throws if the file is missing.

**New Script-level variables**:

- `$Script:DotNetCuIndexUrl` — the index URL with the
  `?accept=text/markdown` query.
- `$Script:DotNetCuUrlBase` — used by the index parser to
  reconstruct absolute URLs from relative paths.
- `$Script:DotNetCuUserAgent` — a descriptive User-Agent string
  identifying this subproject.
- `$Script:DotNetCuOsLongToShort` — an ordered hashtable mapping
  the long OS label substrings to the short names.

**Refresher main path NOT changed**. The existing path
(`Resolve-PatchSetFromCatalog`, `Get-CatalogQueryTemplate`,
`Get-UpdateIdFromCatalog`, the Refresher action workers) is
unaffected by this commit. Switching the Refresher to consume
`cache-dotnet-cu.json` instead of live-scraping is scheduled for
a later r07.0 commit (Step 2b).

**New files committed to the repo**:

- `data/` — no production cache file is committed in this
  commit; production runs that invoke `Invoke-DotNetCuFetch` will
  write `raw-dotnet-cu.json` and `cache-dotnet-cu.json` on demand
  under the Patch-Tuesday-triggered model (SPEC.md §B.23.7).
- `tests/snapshots/dotnet_cu/index.md` — live capture of the
  Microsoft Learn `.NET Framework release information` index
  page (`?accept=text/markdown`) on 2026-05-26.
- `tests/snapshots/dotnet_cu/2026-05-12-may-cumulative-update.md`
  — live capture of the May 2026 monthly CU page.
- `tests/snapshots/dotnet_cu/2026-04-14-april-cumulative-update.md`
  — live capture of the April 2026 monthly CU page.
- The three `.meta.json` siblings carrying `captured_at`,
  `source_url`, `user_agent`, and `byte_count`.
- `tests/fixtures/dotnet_cu/index.json`,
  `tests/fixtures/dotnet_cu/month-2026-05.json`,
  `tests/fixtures/dotnet_cu/month-2026-04.json` — the Python
  reference parser output that defines what the PowerShell
  parsers must reproduce.

**New regression test**: `tests/dotnet_cu_parser_test.py` (T7).
Covers 16 assertions across the index parser (EntryCount,
EarliestDate, LatestDate, Kinds, per-entry deep equality across
all 29 entries, typo-entry preservation), the monthly parser
(EntryCountTotal, EntryCountRecognised, RowsPerOs, Server2022
block deep check, cross-month regression on 2026-04), and the
OS-label mapper (two production-scope labels plus an
unrecognised one). Runs against the fresh snapshots/fixtures
described above and is intentionally independent of the PoC
fixtures under `tests/snapshots/poc_dotnet_cu/`. **All 16
assertions pass** under PowerShell 7.4 on Ubuntu 24.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13, T7
16/16. The PoC scripts and PoC snapshot/fixture directories are
unchanged.

### r07.0 Step 2a (release-info part) - PowerShell port of the release-info parser (previous release)

This commit lands the **first half** of the Step 2 work scheduled
in SPEC.md section B.23.1. New PowerShell functions parse the
Microsoft Learn Windows Server release-info Markdown into
structured cache data; the existing Refresher main path
(`Resolve-PatchSetFromCatalog`) is **untouched** and continues
to drive `-Action RefreshAllBaselines`. The .NET CU parser, the
Dynamic Update 36-month cache, and the Catalog URL-resolver
narrowing are scheduled for subsequent r07.0 commits.

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-OsConfigPath` and the Catalog scraper section):

- `Get-DataDirectoryPath` / `Get-ReleaseInfoRawPath`
  / `Get-ReleaseInfoRawMetaPath` / `Get-ReleaseInfoCachePath` —
  path resolvers for the three new files under `data/`.
- `Invoke-ReleaseInfoFetch` — HTTPS fetch of
  `https://learn.microsoft.com/.../windows-server-release-info?accept=text/markdown`
  using `Invoke-WebRequest -UseBasicParsing` with a descriptive
  User-Agent. Writes the Markdown body to
  `data/raw-release-info.md` (UTF-8, LF, no-BOM) and the HTTP
  headers + fetch timestamp to `data/raw-release-info.meta.json`.
- `Split-ReleaseInfoTableRow` / `Test-ReleaseInfoTableSeparator`
  / `ConvertFrom-ReleaseInfoUpdateType` /
  `ConvertFrom-ReleaseInfoKbCell` — small parser helpers that
  mirror the PoC Python implementations in
  `tests/poc_release_info_02_parse.py`.
- `ConvertFrom-ReleaseInfoMarkdown` — main parser. Returns a
  `pscustomobject` with two properties (`MonthlyReleases`,
  `HotpatchCalendar`) containing per-OS rows. Header text and
  column counts are checked strictly; any drift in Microsoft's
  table layout is reported via `Write-Warn` and the offending
  row is skipped (the offline regression test will then surface
  the count delta).
- `Update-ReleaseInfoCache` — reads `data/raw-release-info.md`,
  parses it, derives per-OS row counts, and writes
  `data/cache-release-info.json` (UTF-8, LF, no-BOM, JSON
  Depth 32).
- `Get-ReleaseInfoCache` — reads
  `data/cache-release-info.json` and returns the deserialised
  object. Refresher consumers in a later commit will use this
  to avoid re-parsing on every build.

**Schema of `data/cache-release-info.json`** (Schema 1.0):

```jsonc
{
  "Schema":            "1.0",
  "GeneratedAt":       "<ISO 8601 UTC>",
  "SourceUrl":         "https://learn.microsoft.com/...",
  "RawMarkdownPath":   "raw-release-info.md",
  "MonthlyRowCount":   471,
  "HotpatchRowCount":  62,
  "PerOsMonthlyCounts":  { "Server2016": 187, "Server2019": 165, "Server2022": 89,  "Server2025": 30 },
  "PerOsHotpatchCounts": { "Server2025": 26, "Server2022": 36 },
  "MonthlyReleases":   [ { "OsShortName": "Server2025", ... }, ... ],
  "HotpatchCalendar":  [ { "OsShortName": "Server2025", "CalendarYear": 2026, ... }, ... ]
}
```

**Constants and tables** added at script scope:

- `$Script:ReleaseInfoUrl`
- `$Script:ReleaseInfoUserAgent`
- `$Script:ReleaseInfoLongToShort`     (Markdown OS header → OsShortName)
- `$Script:ReleaseInfoMonthNameToNumber`
- `$Script:ReleaseInfoMonthlyHeaders`  (expected column names for the monthly release tables)
- `$Script:ReleaseInfoHotpatchHeaders` (expected column names for the Hotpatch calendar tables)

**Tests**

- New T6 `tests/release_info_parser_test.py`: invokes
  `ConvertFrom-ReleaseInfoMarkdown` via the existing TestHarness
  protocol against the PoC snapshot
  `tests/snapshots/poc_release_info/release-info-2026-05-25.md`
  and compares the output against the PoC fixture
  `tests/fixtures/poc_release_info/release-info.json`. The PoC
  fixture was generated by `tests/poc_release_info_02_parse.py`
  during r06.0 Phase 2 and is the reference truth for this
  port. T6 verifies: total monthly row count (471), total
  Hotpatch row count (62), per-OS monthly counts (Server2016=187,
  Server2019=165, Server2022=89, Server2025=30), per-OS Hotpatch
  counts (Server2025=26, Server2022=36), KbId-parse coverage
  per OS, and IsBaseline detection in the Hotpatch table.

**Not in this commit** (deferred to subsequent r07.0 steps):

- `Resolve-PatchSetFromReleaseInfo` (the new Refresher main
  path that consumes `cache-release-info.json`) — Step 2b.
- `.NET CU` parser and `data/cache-dotnet-cu.json` — Step 2a-2
  (next r07.0 commit).
- `Dynamic Update` 36-month cache (`data/cache-du-Server*.json`)
  — Step 2a-2 or Step 2a-3.
- `Get-DownloadUrlForKb` (Catalog URL resolver narrowed to
  KB-only lookup) — Step 2b.
- Deletion of the old `Resolve-PatchSetFromCatalog` KB-discovery
  logic — Step 2b.
- New `RefreshSnapshots` / `InspectBaseline` Actions, the
  `stage5__data-snapshot.yml` workflow, and the ScriptVersion
  bump to `r07.0` — Step 3.

**Quality gates verified for this commit**

- `psa.py Update-WindowsServerIso.ps1`: 0 errors / 0 warnings / 0 info
- PSScriptAnalyzer (pwsh 7 Linux): 0 errors / 0 warnings / 0 info
- T2 `catalog_fixture_test.py`: 13/13 PASS
- T3 `powershell_harness.py`: 13/13 PASS
- **T6 `release_info_parser_test.py`: 13/13 PASS** (new)
- `.ps1`: UTF-8 BOM + CRLF + ASCII-only (verified)
- `.md` / `.json`: UTF-8 + LF + no-BOM (verified)

### r07.0 Step 1 - data/ migration and DotNet type breaking change (this release)

This is the **first commit of the r07.0 implementation** of the
Phase 3 architecture decisions captured in SPEC.md §B.23. Two
mechanical changes ship in this step; the production code paths
(release-info parser, .NET CU parser, DU cache, URL resolver, new
Actions) come in the following r07.0 commits.

**Changes**

- **Directory rename: `Config/` → `data/` with `config-` filename
  prefix.** All four `Config/Server<N>.json` files are moved to
  `data/config-Server<N>.json`. This is the layout codified in
  SPEC.md §B.23.3 and is the foundation for the upcoming
  `cache-*` and `raw-*` sibling files. The `Config/` directory
  itself is removed.

- **New optional config field: `Common.CatalogTitleTokens`.** Each
  `data/config-Server<N>.json` gains an array of strings used by
  the future Catalog URL resolver to disambiguate KB-only Search.aspx
  responses. Values are sourced from PoC-B evidence in r06.0:

  | OS          | Tokens                                                                                              |
  | ----------- | --------------------------------------------------------------------------------------------------- |
  | Server 2016 | `["Windows Server 2016"]`                                                                           |
  | Server 2019 | `["Windows Server 2019"]`                                                                           |
  | Server 2022 | `["Microsoft server operating system version 21H2", "Microsoft server operating system, version 21H2", "Windows Server 2022"]` |
  | Server 2025 | `["Microsoft server operating system version 24H2", "Windows Server 2025"]`                         |

  The field is additive within Schema 2.1; consumers that do not
  recognise it ignore it (no Schema bump). See SPEC.md §B.23.2
  for the rationale and §B.23.4 for the schema-version stance.

- **Breaking change: `Type=DotNet` split into `DotNet.Runtime`
  + `DotNet.OsLevel`.** The PatchBaseline `Type` enumeration now
  distinguishes the per-runtime KB (applied to install.wim) from
  the OS-offering KB (recorded for traceability but not applied
  to any WIM). All in-tree code paths that referenced `'DotNet'`
  now reference `'DotNet.Runtime'`. The `Get-PatchType` classifier
  routes `.NET`-bearing filenames to `DotNet.Runtime` because the
  OS-offering KB never has an on-disk payload. The `PatchTargetMap`
  declares `DotNet.OsLevel` with an empty target array, so an
  OS-offering KB recorded in a future baseline cleanly skips
  WIM application. See SPEC.md §B.23.8 for the design rationale
  and §B.14b for the updated Type enumeration.

- **`Get-ConfigProfile` rejects legacy baselines.** A config-load
  attempt that finds `Type='DotNet'` entries in `PatchBaseline.Patches[]`
  now fails fast with a precise error pointing at SPEC.md §B.23.8
  and instructing the operator to re-run `-Action RefreshAllBaselines`.
  No automatic migration shim ships; r07.0 is a breaking change
  by design.

**Documentation updates**

- `SPEC.md §B.22.1` directory layout: rewritten in current-state
  voice with a historical note for the pre-r07.0 `Config/`
  layout.
- `SPEC.md §B.22.2` filename prefix rules: collapsed the r06.x /
  r07.0+ split rows into the post-r07.0 layout; the historical
  Phase 3 design narrative remains in §B.23.3.
- `SPEC.md §B.10` JSON example: example `Type` values updated
  to show both `DotNet.Runtime` and `DotNet.OsLevel` rows.
- `SPEC.md §B.14b` Type enumeration: the comment that lists all
  legal Type values now reads `... | DotNet.Runtime | DotNet.OsLevel
  | DotNet.LangPack | ...`.
- `SPEC.md §B.12` (P07 Install target table): added a row for
  `DotNet.OsLevel` showing `(none)` targets.
- `README.md` / `README.ja.md` / `TESTING.md` / `tests/README.md`
  / `tests/eval_iso_probe.py`: all references to `Config/...`
  paths updated to `data/config-...` paths.
- `.github/workflows/stage1__linux.yml` /
  `stage4__monthly-refresh.yml`: path-filter and PR-creation
  patterns updated to `data/**` and `data/config-*.json`.

**Tests**

- `tests/powershell_harness.py` (T3): the
  `Get-CatalogQueryTemplate per-OS Type coverage` and
  `Select-AllCanonicalPatchFiles dual-link case` tests are
  updated to expect `'DotNet.Runtime'` rather than `'DotNet'`.

**Baseline lint cleanup (PSScriptAnalyzer)**

Three pre-existing PSScriptAnalyzer findings were carried over
from earlier commits and resolved as part of Step 1 so the
project's stated "0 errors / 0 warnings / 0 information findings"
quality gate is actually enforced going forward:

- `PSAvoidAssignmentToAutomaticVariable`:
  `foreach ($pid in $installedIds)` renamed to
  `foreach ($packageId in $installedIds)` to avoid shadowing
  the read-only `$pid` automatic variable.
- `PSReviewUnusedParameter`: `Select-AllCanonicalPatchFiles`
  now honours its `$PatchType` parameter by mirroring the
  `DotNet.Runtime`-specific ndp scoring boost that
  `Select-CanonicalPatchFile` already had, making the
  multi-file picker behave consistently with the single-file
  picker when umbrella .NET CU KBs return multiple siblings.
- `PSUseDeclaredVarsMoreThanAssignments`: the unused
  `$regOut` capture from `reg.exe load` was changed to
  `$null = & reg.exe load ...` since success is determined
  by `$LASTEXITCODE` alone.

**Quality gates verified for this commit**

- `psa.py Update-WindowsServerIso.ps1`: 0 errors / 0 warnings / 0 info
- T2 `catalog_fixture_test.py`: 13/13 PASS
- T3 `powershell_harness.py`: 13/13 PASS
- `.ps1`: UTF-8 BOM + CRLF + ASCII-only (verified)
- `.md`: UTF-8 + LF + no-BOM (verified)
- `.json`: UTF-8 + LF + no-BOM (verified)

**Not in this Step 1**

- Script version is still `update-wsi-2026.05.25-r05.1`. The
  `r07.0` version bump happens in the final r07.0 commit.
- `Resolve-PatchSetFromReleaseInfo`, `Get-DownloadUrlForKb`, the
  release-info / .NET CU / DU caches, the `RefreshSnapshots` and
  `InspectBaseline` Actions, and the `stage5__data-snapshot.yml`
  workflow all arrive in subsequent r07.0 commits per the §B.23
  design.

### r06.0 Phase 2 - PoC: online patch metadata acquisition (this release)

This Phase 2 deliverable is **PoC scripts and a written report**,
plus a new normative SPEC.md §B.22 ("File organisation and naming
conventions") that codifies how PoC artefacts coexist with the
production code and the T1-T5 regression suite under the subproject
directory. As with Phase 1, this release contains **no script
(`.ps1`) changes and no on-disk Config schema changes**.

**Driver**. r06.0 Phase 1 left open the empirical question:
*does the Microsoft Learn Windows Server release-info page provide
enough authentication-free metadata to drive the Refresher,
replacing the brittle Microsoft Update Catalog title-string
heuristics catalogued in SPEC.md §D.19 / §D.20 / §D.21?* Phase 2's
PoC answers that question with measured data from 471 monthly
release rows and 62 hotpatch calendar entries.

**SPEC changes**:

- `SPEC.md` §B.22 ("File organisation and naming conventions")
  added. Five subsections:
  - **B.22.1** Directory layout (`Config/`, `tests/`, `docs/` as
    the only first-class children).
  - **B.22.2** Filename prefix rules (`poc_<topic>_<step>_<verb>.py`
    for PoC Python; `poc-<topic>-<purpose>.md` for PoC Markdown).
  - **B.22.3** Worked examples mapping filenames to classes.
  - **B.22.4** Out-of-scope clarifications.
- `SPEC.md` Part G adjunct ("PoC scripts under `tests/`") added,
  cross-referencing the new conventions and listing the current
  PoC inventory.

**PoC artefacts added** (all disposable per B.22):

```
tests/
├── poc_release_info_01_fetch.py    fetch the Markdown
├── poc_release_info_02_parse.py    parse into JSON
├── poc_release_info_03_analyse.py  write CSV + JSON analyses
├── snapshots/poc_release_info/
│   ├── .gitattributes
│   ├── release-info-2026-05-25.md       (68 KB raw Markdown)
│   └── release-info-2026-05-25.meta.json
└── fixtures/poc_release_info/
    ├── release-info.json                (parsed structured form)
    ├── update-type-summary.csv          (YYYY-MM x OS x letter pivot)
    ├── baseline-month-detection.json    (Server 2025/2022 hotpatch calendar)
    ├── letter-frequency.json
    └── coverage-summary.json
docs/
├── README.md                            (docs/ directory guide)
└── poc/
    ├── poc-release-info-readme.md       (how to run the PoC)
    └── poc-release-info-report.md       (findings + Phase 3 recommendations)
```

**PoC findings (summary)**:

- The `?accept=text/markdown` content-negotiation switch returns
  the source Markdown verbatim, 68 KB, no authentication. The page
  is GitHub-backed (`MicrosoftDocs/windows-release-pr`), so its
  format stability is reviewable.
- Monthly release coverage is comprehensive: 117 months for
  Server 2016, 92 for Server 2019, 58 for Server 2022, 20 for
  Server 2025, with zero gaps for the latter three.
- The previously-uncatalogued **"Windows Server hotpatch calendar"**
  section provides authoritative Baseline-vs-Hotpatch month
  labelling for Server 2022 and Server 2025, including
  forward-looking unreleased months. This single discovery answers
  the "how do we know which Server 2025 LCUs are baseline months"
  question without scraping technical blogs.
- The release-info page does NOT cover .NET Framework CU,
  Dynamic Update.Setup, Dynamic Update.SafeOs, or language packs.
  Those Types stay on the Catalog scrape path for Phase 3, but the
  Catalog query can be keyed by KB number (from release-info)
  rather than by Title-string heuristics, removing most of
  SPEC.md §D.19 / §D.20 from the surface area.

The full report including five Phase 3 recommendations and four
open questions is in
[`docs/poc/poc-release-info-report.md`](./docs/poc/poc-release-info-report.md).

**Not in this Phase 2**:

- No `Update-WindowsServerIso.ps1` changes. `$Script:ScriptVersion`
  stays at `update-wsi-2026.05.25-r05.1`.
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes. The PoC scripts share the `tests/` directory
  by file-organisation convention but do not participate in the
  T-numbered regression suite.
- No Phase 3 code or design. Phase 3 is driven by the report's
  recommendations and is a separate work item.

#### r06.0 Phase 2 Part 2 — full Phase 2 coverage (this release)

The first cut of Phase 2 above shipped the `release_info` PoC
with three scripts but deferred three of the original PoC
questions (B, E, F) to Phase 3 as "open questions". Part 2
closes those gaps within Phase 2 so that the deliverable matches
the original Phase 2 scope.

**New PoC artefacts**:

- `tests/poc_release_info_04_resolve.py` — answers PoC-B by
  resolving 8 representative (OS, KB) pairs from the parsed
  release-info data through the Microsoft Update Catalog
  (Search.aspx → DownloadDialog.aspx). Verdict: 8/8 succeed
  with KB-only input; OS-naming requires both the
  `Windows Server NNNN` and `Microsoft server operating system
  version NNHN` tokens to disambiguate hits.
- `tests/poc_dotnet_cu_*.py` (new topic) — answers PoC-E by
  fetching and parsing the Microsoft Learn
  `.NET Framework cumulative update` release-notes pages.
  Verdict: the pages are served as Markdown via
  `?accept=text/markdown` and provide an authoritative per-OS x
  per-.NET-version KB table.
- `tests/poc_dynamic_update_01_probe.py` (new topic) — answers
  PoC-F by probing the Catalog with the same query templates as
  `Get-CatalogQueryTemplate`. Verdict: Server 2022 DU.SafeOs and
  Server 2025 DU.SafeOs are reliably discoverable; Server 2025
  DU.Setup has been absent from the Catalog for 5+ consecutive
  months (2025-12 through 2026-04), which the Phase 3 Refresher
  must treat as a soft signal rather than an error.

**New PoC documentation**:

- `docs/poc/poc-dotnet-cu-report.md` (full findings for PoC-E)
- `docs/poc/poc-dynamic-update-report.md` (full findings for PoC-F)
- `docs/poc/poc-release-info-report.md` updated with three
  `(revisited)` subsections that close PoC-B / E / F by linking
  to the new reports.

**SPEC changes**:

- `SPEC.md` §B.21.2 (.NET CU multiplicity by OS) amended to
  record the upstream-source per-OS file counts alongside the
  existing production-telemetry counts, and to explain the
  Server 2016 discrepancy (production sees 1 file; upstream
  release-notes lists 2 KBs).
- `SPEC.md` Part G adjunct updated to reflect the three current
  PoC topics (`release_info`, `dotnet_cu`, `dynamic_update`)
  instead of just one.

**Key empirical findings beyond the original Phase 2 questions**:

- Microsoft Update Catalog publishes Server 2022/2025 LCUs under
  the name "Microsoft server operating system version NNHN"
  (not "Windows Server NNNN"); the Phase 3 resolver must accept
  both token forms.
- Every Server 2025 LCU resolution returns 2 download URLs: the
  LCU itself plus `KB5043080` (the Servicing Stack baseline).
  This empirically validates the "no standalone SSU" claim in
  SPEC.md §B.21.1 for the Server 2025 row.
- SPEC.md §B.21.2 had a Server 2016 .NET CU file count of 1
  derived from r05.1 telemetry; the upstream
  `.NET Framework cumulative update` release-notes table for
  2026-04 lists 2 distinct KBs for Server 2016. The Phase 3
  Refresher should consume from release-notes (not the umbrella
  KB scrape) to surface the missing sibling.

**Still not in this Phase 2**:

- No `Update-WindowsServerIso.ps1` changes (still r05.1).
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes.

### r06.0 Phase 3 Architecture — SPEC-only: r07.0 design baseline (this release)

This Phase 3 deliverable is the **SPEC consolidation** of the
eleven architecture decisions taken during a 2026-05-25 design
session, building on the Phase 2 PoC findings. As with Phase 1
and Phase 2 Part 2, this release contains **no script (`.ps1`)
changes and no on-disk Config schema changes**.

**Driver**. Phase 2 (especially Part 2's PoC-B/E/F follow-up)
turned up enough hard data to answer the open questions that
§B.21.5 "Future work" had deliberately deferred. Rather than
go straight to implementation, this phase records *what r07.0
will look like* as a normative SPEC section so the implementation
PR can be reviewed against a written design, not against the
chat history of a design call.

**New SPEC section**: **§B.23 Phase 3 Architecture (r07.0+,
normative)** documents the eleven decisions as MADR-style
Decision Records:

| Subsection | Topic                                          | Decision                                                |
| ---------- | ---------------------------------------------- | ------------------------------------------------------- |
| §B.23.1    | Refresher architecture                         | Complete migration to release-info / .NET release-notes |
| §B.23.2    | Catalog Title token matching                   | Config-driven via `CatalogTitleTokens` field            |
| §B.23.3    | Data directory layout                          | `data/` flat with `config-` / `cache-` / `raw-` prefix  |
| §B.23.4    | Schema versioning                              | Stay at 2.1; no Schema 2.2                              |
| §B.23.5    | SSU separation and .NET CU multiplicity        | Filename-based SSU detection; both .NET siblings always |
| §B.23.6    | DU lookback                                    | 36-month rolling cache; latest publish wins             |
| §B.23.7    | Update lifecycle                               | Patch-Tuesday-triggered; Git-tracked                    |
| §B.23.8    | PatchBaseline Type subdivision                 | `DotNet` → `DotNet.Runtime` + new `DotNet.OsLevel`; breaking |
| §B.23.9    | release-info vs Catalog conflicts              | release-info is the absolute truth source               |
| §B.23.10   | r07.0 release granularity                      | Single r07.0 release; r06.x is docs-only                |
| §B.23.11   | `-PreferBaselineMonthLcu`                      | Deferred to Phase 4+                                    |

**Existing SPEC sections amended for cross-reference**:

- §B.21.5 (Future work) now states that the Schema 2.2 sketch is
  **NOT adopted**; per-OS knowledge moves into Config-driven or
  cache-driven mechanisms instead. Cross-references §B.23.
- §B.22.1 (Directory layout) adds an r07.0 migration note: the
  `Config/` directory will be renamed to `data/` per §B.23.3.
- §B.22.2 (Filename prefix rules) adds three new rows for the
  r07.0+ `config-` / `cache-` / `raw-` prefixes.

**Headline architecture points**:

1. **Catalog becomes a URL resolver, not a discovery source.**
   KB numbers harvested from release-info are passed to the
   Catalog to obtain `.msu` URLs; Title-string heuristics for
   discovery are deleted.
2. **`Config/` directory becomes `data/` with three filename
   prefixes** (`config-`, `cache-`, `raw-`). All upstream snapshot
   data is committed to the repository alongside the human-edited
   configs, with Git as the history mechanism (no date in
   filenames).
3. **Schema 2.1 is preserved.** The optional `CatalogTitleTokens`
   field is an additive Schema 2.1 extension; no Schema 2.2 is
   cut.
4. **`Type=DotNet` is deprecated and removed** in favour of
   `DotNet.Runtime` (per-runtime KB, applied to WIM) and
   `DotNet.OsLevel` (OS-offering KB, recorded only). r07.0 is a
   breaking change for any baseline carrying the legacy value;
   no migration shim ships.
5. **DU sources from a 36-month rolling Catalog probe cache.**
   The latest publish within the window wins; absence is logged
   as a warning, not an error. This absorbs PoC-F's finding
   that Server 2025 DU.Setup has been suspended since 2025-12.
6. **release-info is the absolute truth source.** Catalog
   contradictions either (a) stop the build (release-info has a
   KB the Catalog can't resolve) or (b) are ignored (Catalog has
   a KB release-info doesn't list).

**Release plan**:

- r06.0 (this release): SPEC-only documentation, no code changes.
- r07.0 (future release): full Phase 3 implementation per §B.23.
  Breaking change for any baseline carrying `Type=DotNet`.

**Open questions deferred to a third design round** (operations
specifics, not architecture):

- ~~Automated Patch-Tuesday-triggered snapshot refresh in CI~~
  → Resolved: stage5 + stage4 two-stage automation per §B.23.14
- ~~`-PatchMonth` argument for past-month refresh~~
  → Resolved: read-only `-Action InspectBaseline -PatchMonth`
  per §B.23.13
- ~~Server 2022 dynamic baseline-month detection (CY2024 August
  anomaly)~~ → Resolved: parser records baseline-months verbatim
  including anomalies per §B.23.12
- ~~PoC scripts CI promotion to T6-T8~~ → Resolved: PoCs promoted
  to T6-T8 as part of §B.23.14

All third-round questions resolved in this release. The Phase 3
SPEC is now complete; r07.0 implementation work can proceed.

**Third-round additions to §B.23** (this release adds):

| Subsection | Topic                                              | Decision                                                |
| ---------- | -------------------------------------------------- | ------------------------------------------------------- |
| §B.23.12   | Server 2022 baseline-month detection                | Strictly data-driven; authoritative source wins        |
| §B.23.13   | Past-month inspection                               | Read-only `-Action InspectBaseline -PatchMonth YYYY-MM` |
| §B.23.14   | CI structure                                        | Two-stage automation; stage5 (snapshot) + stage4 (baseline regenerate); PoC → T6-T8 |

Additionally, §B.6 (Action → Phase Mapping) gains a new
`InspectBaseline` row, and §B.23.7's "out of scope" disclaimer
on CI automation is upgraded to "in scope per §B.23.14".

**Still not in this Phase 3**:

- No `Update-WindowsServerIso.ps1` changes (still r05.1).
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes.
- No `data/` directory yet (rename happens in r07.0).
- No `stage5__data-snapshot.yml` yet (added in r07.0).

### r06.0 Phase 1 - Spec-only: OS Update Type Matrix

This Phase 1 deliverable is SPEC-only and intentionally contains
**no script (.ps1) changes and no on-disk Config schema changes**.
It exists to make the until-now implicit per-OS update Type
assumptions normative, which is a prerequisite for the upcoming
PoC that will validate whether Microsoft's online metadata
sources can replace the Catalogue Title-string heuristics.

**Driver**. Production telemetry from the 2026-05 Patch Tuesday
refresh (r05.1) and a design review highlighted that Server
2016/2019/2022/2025 do not actually share a uniform set of
patch Types: SSU is standalone for 2016/2019 but folded into
the LCU for 2022/2025; .NET CU file multiplicity varies per
OS; Hotpatch exists only as an online-runtime mechanism on
Server 2025 and has no offline-image equivalent. None of this
was written down anywhere normative; the Refresher's behaviour
was a side effect of "Catalogue happened to return zero results
for SSU on Server 2025".

**Changes**:

- `SPEC.md` §B.21 ("Update Type Matrix per OS generation") added
  with five subsections:
  - **B.21.1** The matrix itself: a 4-OS x 8-Type table with
    cell values of `Required` / `Optional` / `N/A` / `Possible`.
  - **B.21.2** .NET CU multiplicity per OS, with the exact
    file counts observed in 2026-05 telemetry (1, 2, 2, 1 for
    Server 2016/2019/2022/2025 respectively).
  - **B.21.3** Combined LCU package detection: the two
    independent signals (Catalogue-side: SSU query returns 0
    hits; Title-side: "combined SSU and LCU" wording) and how
    `IsCombined` is annotated on PatchBaseline entries.
  - **B.21.4** Hotpatch declared out of scope for offline
    image servicing (it is an online-runtime mechanism via
    Azure Arc; no `Add-WindowsPackage` equivalent exists).
    Includes informational note that a future
    `-PreferBaselineMonthLcu` switch could help Server 2025
    machines that want to enroll in Hotpatch.
  - **B.21.5** Future work: candidate `Common.UpdateTypePolicy`
    sub-block for a hypothetical Schema 2.2, explicitly marked
    "NOT YET ADOPTED -- contingent on PoC".
- `SPEC.md` §D.2 ("SSU before LCU") amended with an
  OS-generation note pointing to §B.21.
- `SPEC.md` §D.21 ("Umbrella KBs") amended with a reference to
  §B.21.2 for the expected per-OS file count.

**Not in this Phase 1**:

- No `Update-WindowsServerIso.ps1` changes. `$Script:ScriptVersion`
  stays at `update-wsi-2026.05.25-r05.1`. The script's runtime
  behaviour is unchanged; only the documentation now states
  explicitly what the script was already doing implicitly.
- No `Config/<OsKey>.json` schema changes. Schema stays at
  v2.0 / v2.1 as accepted by r05.0.
- No PoC code yet. Phase 2 will introduce a separate PoC
  directory to validate the online-metadata sources
  (release-info Markdown, Hotpatch baseline-month detection,
  alternative sources for .NET / Dynamic Update).

### Planned (r06 Phase 2)

- PoC for online patch metadata acquisition without
  authentication. Targets: Microsoft Learn
  `windows-server-release-info` (Markdown rendering),
  Hotpatch baseline-month detection, alternative sources for
  .NET / Dynamic Update.
- Outcome: a written report (under `scripts/poc/` or a similar
  location) recommending which sources can replace which parts
  of `Resolve-PatchSetFromCatalog`'s Title-string heuristics.

### Planned (r06 Phase 3, PoC-driven)

- Config Schema v2.2 design (only if Phase 2 demonstrates
  feasibility): a `Common.UpdateTypePolicy` sub-block that
  codifies §B.21.1 per-OS, plus per-Type metadata such as
  `ExpectedFileCount`.
- Patch Manifest Engine: an interface that lets the Refresher
  prefer online-metadata sources for KB-number resolution and
  fall back to Catalogue scraping only for MSU/CAB URL
  resolution.

### Planned (M4 - carryover from earlier roadmap)
- Server 2025 real `LCUExpandViaMum=true` code path. LCU on 2025 ships
  as a MUM/CAB bundle that must be expanded with `expand.exe -F:*`
  before `Add-WindowsPackage` is invoked.

### Planned (M5 - carryover from earlier roadmap)
- Stage 4 CI workflow (`catalog-health`): monthly scheduled run of
  `Resolve-PatchSetFromCatalog` that opens a PR with the resulting
  `Config/<OsKey>.json` diff for human review. Catches Microsoft
  Update Catalogue HTML structure changes within 30 days.

## [update-wsi-2026.05.25-r05.1] - 2026-05-25

Two production-fix changes surfaced by the first real r05.0
`-Action RefreshAllBaselines` run against the 2026-05 Patch Tuesday
release:

### Fixed - KbId/FileName mismatch in PatchBaseline.NeutralPatches

When Microsoft publishes a single "umbrella" CU whose `UpdateId`
attaches multiple `.msu` files (typical for .NET cumulative updates
and for some LCUs that bundle a checkpoint CU's payload), the
previous patch-resolution loop reused the umbrella Title-derived
KbId for every attached file. That produced PatchBaseline entries
where the recorded `KbId` did not match the actual `FileName`:

```json
// Server2019.json, May 2026 baseline (BEFORE this fix)
{ "KbId": "KB5088864", "FileName": "windows10.0-kb5087066-x64-ndp48_...msu" },
{ "KbId": "KB5088864", "FileName": "windows10.0-kb5087061-x64_...msu" }
//        ^^^^^^^^^^                              ^^^^^^^^^^
//        umbrella Title KB     actual payload KB encoded in file name
```

Three symptoms were observed in the 2026-05 production output:

- **Server2019 / Server2022 .NET CU**: two identical-KbId entries
  attached to two distinct .msu files (4.8 + 4.8.1 runtimes).
- **Server2025 LCU**: `KbId=KB5087539` (umbrella Title) with
  `FileName=windows11.0-kb5043080-x64_...msu` (checkpoint CU payload).
- **Server2022 Dynamic Update**: `Setup` and `SafeOs` queries
  resolved to the same `UpdateId` because the OS-title narrowing
  step did not separate them by intent.

This release adds two fixes:

1. **New helper `Get-KbIdFromPatchFileName`** that parses
   `kb#######` out of the standard Microsoft file-name patterns
   (`windows10.0-kb5087537-x64_...`, `windows11.0-kb5087588-x64_...`,
   `...-ndp48_...`, `...-ndp481_...`, etc.). Returns the KB id in
   canonical upper-case form; returns `''` for file names that do
   not contain a `kb` token so the caller can fall back to the
   umbrella Title.
2. **`Resolve-PatchSetFromCatalog` per-file KbId**: the
   `foreach ($primary in $primaries)` loop now derives the
   per-file KbId via `Get-KbIdFromPatchFileName` (falling back to
   the Title-derived KbId if the file name has no kb token). Each
   entry now reflects its actual payload KB.
3. **Setup/SafeOs disambiguation post-filter**: for the 21H2/24H2
   Dynamic Update queries whose `QueryTemplate` is shared, an
   additional title-keyword filter ("Setup Dynamic Update" vs
   "Safe OS Dynamic Update" / "SafeOS") is applied after the
   OS-title narrowing so the two queries no longer collide on
   the same UpdateId.

The fix is fully backward compatible: existing PatchBaseline.json
files keep loading, and the FileName + DownloadUrl fields (which
P04 FetchAssets actually uses for download) were already correct;
only the KbId label is updated.

### Added - Rich `-Action RefreshAllBaselines` console summary

`Show-RefreshAllBaselinesSummary` now renders a seven-section
end-of-run summary block that consolidates everything an operator
needs to file a baseline-refresh ticket without re-reading the full
progress log. The block is console-only (no extra files written),
which keeps CI log capture trivial. Sections:

  1. **Field-group decisions** - same counts as before
     (Skip / Manual / Monthly / InitialFill).
  2. **Per-OS patch composition** - one row per OS showing the
     final NeutralPatches count, file count, and a `Type=N` map
     across SSU/LCU/DotNet/DynamicUpdate.* buckets.
  3. **KB delta vs previous PatchBaseline** - per-OS
     `+ added (n)`, `- removed (n)`, `= unchanged (n)` lines with
     the actual KB ids, computed against the BeforePatches
     snapshot captured at the start of the OS loop.
  4. **Manual fill required** - the operator follow-up list,
     grouped by OS so each ticket / diff can be scoped per-OS.
  5. **Pca2023 readiness** - per-OS RequiredByDefault flag and
     RequiredUpdateLevelKb (Schema 2.1 only; Schema 2.0 configs
     are flagged with "(no Pca2023 block)").
  6. **Patch Tuesday timeline** - this run's baseline plus the
     next two upcoming Patch Tuesdays so the next refresh window
     is visible at a glance.
  7. **Run outcome** - explicit Status + Exit code statement
     (`OK` / exit 0, `PARTIAL` / exit 2, `FAILED` / exit 1) so
     CI dashboards do not need to parse return values to know
     whether a run was clean.

Implementation notes:

- The OS loop now captures a deep-clone `BeforePatches` snapshot
  via `ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json` so
  later in-place mutations to `$raw` cannot retroactively poison
  the "before" set.
- The new collector hashtable (`$osSummaries`) is keyed by OsKey
  and aggregates BeforePatches / AfterPatches / Changed /
  ErrorCount / ManualGroups / Pca2023 reference / PreviousVerified
  for every OS processed in the run, even those skipped due to
  Schema mismatch (skipped OSes appear with `(Schema 2.0)` in
  section 5).
- `Manual` decisions add the affected group path to
  `osSummaries[$osKey].ManualGroups`, which section 4 then walks.
- `Refresher failed` exceptions increment
  `osSummaries[$osKey].ErrorCount`. Section 7 inspects the
  overall `$okOverall` aggregate to decide between PARTIAL and
  FAILED status.

## [update-wsi-2026.05.25-r05.0] - 2026-05-25

Major version bump for two distinct (but coordinated) changes:
**(1)** complete integer renumbering of all phase IDs (removing the
historical 0.5-step inserts), **(2)** Secure Boot / PCA2023 boot
manager support per Microsoft KB 5053484 (`Make2023BootableMedia.ps1`).
Both are breaking changes for operators who reference Phase IDs by
name or who have wired specific Phase-IDs into their own runbooks.

### Breaking changes

- **Phase ID renumbering** (no aliases, no deprecation warnings).
  Old IDs (`P02.5`, `P04.5`, `P03`, `P04`, `P05`, `P06`, `P07`, `P08`,
  `P09`) are now invalid - the dispatcher will reject `-PhaseIds
  'P02.5'` style invocations. The new mapping:

  | Old ID | New ID | Phase name |
  |:---:|:---:|---|
  | P01    | **P01** | Initialize (unchanged) |
  | P02    | **P02** | ResolveInputs (unchanged) |
  | P02.5  | **P03** | RefreshPatchBaseline |
  | P03    | **P04** | FetchAssets |
  | P04    | **P05** | ExpandIso |
  | P04.5  | **P06** | ValidatePatchSet |
  | P05    | **P07** | PatchInstallWim |
  | P06    | **P08** | PatchBootWim |
  | P07    | **P09** | AssembleIso |
  | (new)  | **P10** | ConvertPca2023BootManager (Build, default-skip) |
  | P08    | **P11** | StaticVerify |
  | (new)  | **P12** | VerifyPca2023Readiness (Verify, always-runs) |
  | P09    | **P13** | FinalReport |
  | A01    | **A01** | RefreshAllBaselines (unchanged) |
  | A02    | **A02** | DumpFieldClassification (unchanged) |

- **Action mapping internal updates** (Action names unchanged):
  - `Prepare` -> `P01, P02, P03, P04, P05, P06`
  - `Build`   -> `P07, P08, P09, P10`
  - `Verify`  -> `P11, P12, P13`
  - `All` / `PrepareBuildVerify` -> all phases above
  - `GenerateManifest` -> `P01, P02, P03`

- **Function name renames** (script-internal; affects any caller
  that referenced these by reflection or `Get-Command`):
  - `Invoke-SetupPhase02_5_RefreshPatchBaseline` -> `Invoke-SetupPhase03_RefreshPatchBaseline`
  - `Invoke-FetchPhase03_FetchAssets` -> `Invoke-FetchPhase04_FetchAssets`
  - `Invoke-PlanPhase04_ExpandIso` -> `Invoke-PlanPhase05_ExpandIso`
  - `Invoke-PlanPhase04_5_ValidatePatchSet` -> `Invoke-PlanPhase06_ValidatePatchSet`
  - `Invoke-BuildPhase05_PatchInstallWim` -> `Invoke-BuildPhase07_PatchInstallWim`
  - `Invoke-BuildPhase06_PatchBootWim` -> `Invoke-BuildPhase08_PatchBootWim`
  - `Invoke-BuildPhase07_AssembleIso` -> `Invoke-BuildPhase09_AssembleIso`
  - `Invoke-VerifyPhase08_StaticVerify` -> `Invoke-VerifyPhase11_StaticVerify`
  - `Invoke-ReportPhase09_FinalReport` -> `Invoke-ReportPhase13_FinalReport`

- **Config schema bump 2.0 -> 2.1**. All four `Config/<OsKey>.json`
  files gain a new top-level `Pca2023` block. Existing readers that
  hard-code the field set will need a one-line tolerance update.

- **CSV filename change**: P11 StaticVerify now writes
  `logs/P11_verification.csv` instead of the legacy
  `logs/P08_verification.csv`.

### Added

- **P10 ConvertPca2023BootManager phase** (Build group, optional).
  Rewrites the output ISO's boot manager to be signed via the
  "Windows UEFI CA 2023" certificate chain instead of the legacy
  "Windows Production PCA 2011" chain. Required for booting under
  Secure Boot firmware that has revoked PCA2011 trust (post 2026-06
  expiry, BlackLotus CVE-2023-24932 mitigation rollout).

  - **Internal implementation**: `Convert-WimBootToPca2023Signed`
    is a PSA-clean re-implementation of Microsoft's
    `Make2023BootableMedia.ps1#Copy-2023BootBins` logic from
    `microsoft/secureboot_objects` (Version 1.4, 2026-03-13).
    Differences from upstream: Context-bag state instead of
    `$global:WIM_*`, structured logging via `Write-Step`, `throw`
    instead of `exit`, `[Parameter(Mandatory)]` shorthand,
    Verb-Noun PSA compliance.

  - **External script option**: `-Pca2023ScriptPath <path>` invokes
    a user-supplied `Make2023BootableMedia.ps1` instead of the
    internal helper, for operators who need to track Microsoft's
    upstream script version directly.

  - **Multi-layered opt-in**: requires `-EnablePca2023BootManager`
    at minimum; Server 2025 additionally requires
    `-ForcePca2023OnServer2025` because certified Server 2025
    server platforms include the 2023 certificates in firmware
    (KB 5053484 does not list Server 2025 in its supported-OS
    set).

  - **Pre-flight gates**:
    - silent skip if `-EnablePca2023BootManager` not set
    - silent skip if OsKey=Server2025 without `-ForcePca2023OnServer2025`
    - silent skip if pre-flight readiness Health = 'Healthy' (already PCA2023)
    - throw if Health = 'Critical' (source media < 2024-04-09 LCU)

- **P12 VerifyPca2023Readiness phase** (Verify group, always-runs).
  Read-only inspection of the produced ISO; emits JSON + Markdown
  reports under `<WorkRoot>/pca2023/`. Three-tier diagnostic:
  - Tier 1: File-existence checks on `boot.wim:\Windows\Boot\EFI_EX\`
    staging directories (the 2024-4B presence signal)
  - Tier 2: `Get-WindowsPackage` LCU month detection on install.wim
    and boot.wim (the 2024-4B integration level)
  - Tier 3: `Get-AuthenticodeSignature` chain walk on
    `efi\boot\bootx64.efi` (the actual firmware-visible signer
    identity)

- **9 new SecureBoot helper functions** in the script:
  - `Get-LcuVersionFromInstallWim` (DISM `Get-WindowsPackage` wrapper)
  - `Get-WimSystemHiveValue` (offline SYSTEM hive read via `reg.exe load`)
  - `Test-Pca2023AuthenticodeChain` (X509Chain walk for cert classification)
  - `Get-IsoBootCertReadiness` (per-ISO inventory assembler)
  - `Get-Pca2023ReadinessSnapshot` (top-level snapshot with Health 4-value)
  - `Show-Pca2023ReadinessSnapshot` (`-Compact` + full console renderer)
  - `Format-Pca2023ReadinessForReport` (StringBuilder text formatter)
  - `Get-OrEnsurePca2023Snapshot` (idempotent cache accessor)
  - `Convert-WimBootToPca2023Signed` (Microsoft `Copy-2023BootBins` reimpl)

- **`-Pca2023OnlyMode` short-circuit**: takes an existing ISO via
  `-IsoPath` and runs ONLY P12 against it. No download, no patching,
  no ISO re-assembly. For forensic inspection of pre-built ISOs.
  Output JSON goes to `$env:TEMP\updwsi_pca2023only_<pid>\`.

- **3 new T3 smoke tests** in `tests/powershell_harness.py` covering
  the SecureBoot helpers' error paths
  (`Test-Pca2023AuthenticodeChain` missing-file,
  `Get-LcuVersionFromInstallWim` missing-mount,
  `Format-Pca2023ReadinessForReport` null-snapshot safety).

- **SPEC.md sections**:
  - B.18 (PCA2023 boot manager support)
  - B.19 (`-Pca2023OnlyMode` standalone inspection)
  - B.20 (Build-group optional phase exception)
  - D.22 (Secure Boot baseline considerations / lessons learned)

### Changed

- **All 9 phase function definitions renumbered** to integer Phase
  IDs (the renumbering side of this major bump). Function bodies
  unchanged; only the names + the `Start-DebugTrace -PhaseId 'PNN'`
  arguments + the `$Script:PhaseRegistry` rows update.

- **381 Phase ID literals renamed** across the script body (215),
  CHANGELOG/README/SPEC/TESTING (163), and tests/ (3). All `'P02.5'`,
  `'P04.5'`, `'P03'`...`'P09'` quote-wrapped string literals are
  rewritten to their new integer IDs. Markdown body text mentions
  of `P02.5`, `P04.5`, `P03`...`P09` are also rewritten.

- **`$Script:PhaseRegistry`** gains P10 (`ConvertPca2023BootManager`,
  Build) and P12 (`VerifyPca2023Readiness`, Verify) entries.

- **`Resolve-PhasesForAction`** internal mapping updated to reflect
  new integer phase IDs and added P10 / P12 placement (Build / Verify
  groups respectively).

- **P13 FinalReport** now includes a Compact-form PCA2023 readiness
  summary inline (after Log locations, before the `.markers/P13.ok`
  marker write). The detail JSON + Markdown remain in
  `<WorkRoot>/pca2023/` for machine consumers.

- **Per-OS PCA2023 defaults** baked into
  `Config/<OsKey>.json#/Pca2023`:
  - Server2016/2019: `RequiredByDefault=true`, MinDate=`2024-04-09`
  - Server2022: `RequiredByDefault=true`, MinDate=`2025-02-11`
    (per Lenovo lp2353.pdf 20348.2227 baseline requirement)
  - Server2025: `RequiredByDefault=false` (firmware-provided 2023 certs)

### Internal

- Stage A / Stage B internal work organisation:
  - Stage A = pure phase ID renumbering. The script was renamed in
    bulk and ran clean (psa.py 0/0/0, PSScriptAnalyzer 0, T2
    13/13 PASS, T3 7/7 PASS) before any new code was written.
  - Stage B = SecureBoot feature implementation on top of the
    renumbered Stage A baseline.
  - The final r05.0 release ZIP is a single artifact even though
    the internal work was two-staged.

- Custom Python tool `stage_a_renumber_v2.py` for the bulk Phase ID
  rewrite. Uses an opaque-token two-pass strategy to safely handle
  chained renames (where old `'P03'` -> new `'P04'` and old `'P04'`
  -> new `'P05'` would otherwise collide). The token form is
  `XOPAQUEXX<two-digit>XX` which by construction never matches a
  `\bP\d\d\b` regex.

- `read_bytes` / `write_bytes` are used throughout the rewrite tool
  to preserve CRLF line endings on `.ps1` files (Python's `read_text`
  / `write_text` normalise CR/LF, which would have violated the
  `.gitattributes` `*.ps1 text eol=crlf` policy).

### Added (post-Stage-B integration from microsoft/secureboot_objects)

The following six improvements were folded into the r05.0 release
after a second-pass audit of the upstream Microsoft repository
(microsoft/secureboot_objects @ main). They are NOT bug fixes;
they are quality / documentation upgrades surfaced by the audit.

- **oscdimg.exe SHA-256 supply-chain integrity check** (`Resolve-OscdimgExe`).
  After locating `oscdimg.exe`, the function now compares the binary's
  SHA-256 against Microsoft's reference hash for the current
  architecture (AMD64 / ARM64 / x86), lifted verbatim from
  `Make2023BootableMedia.ps1#$global:oscdimg_known_hashes` Version 1.4.
  Mismatch is ADVISORY (warning only), because ADK-installed binaries
  may legitimately differ across ADK versions. The check still detects
  the high-impact failure mode: a malicious binary swap on the host
  running the script.

- **NTFS filesystem check in workspace preflight** (`Assert-WorkspacePreflight`).
  Adds a "Check 3" after the disk-space check: confirms the drive
  hosting `-WorkRoot` is formatted as NTFS. WIM mount and DISM
  operations rely on NTFS-only reparse-point / per-stream-metadata
  semantics; ReFS or FAT32 produce silent corruption. Mirrors
  Microsoft's own
  `Make2023BootableMedia.ps1#Initialize-StagingDirectory` enforcement.
  Skipped under `-DryRun` and on non-Windows pwsh hosts (synthetic CI).

- **SPEC.md D.23 — UEFI Secure Boot defaults templates (informational)**.
  New section documenting the five reference templates from
  `microsoft/secureboot_objects/Templates/` (`MicrosoftOnly`,
  `MicrosoftAndOptionRoms`, `MicrosoftAndThirdParty`,
  `MostCompatible`, `LegacyFirmwareDefaults`) and how target firmware
  template choice affects whether to run P10. These templates describe
  firmware-layer Secure Boot variables and are out of scope for direct
  consumption, but operators need to understand them to interpret P12
  output correctly. Includes a per-template "PCA2023 media required?"
  decision matrix.

- **SPEC.md D.22 — KB 5053484 official scope + `-MediaPath` form
  details**. Promoted from a fuzzy "Microsoft KB documentation" link
  to an explicit "Applies To" enumeration (Server 2012/R2/2016/2019/2022
  + Windows 10/11 client SKUs; Server 2025 deliberately not listed)
  and a documented narrowing rationale (upstream `-MediaPath` accepts
  ISO / directory / network share; this project's pipeline operates on
  the extracted-tree form only for repeatability and auditability).
  README.md and README.ja.md gain a one-paragraph summary of the same.

- **T3 schema-validation tests** (`tests/powershell_harness.py`).
  Three new tests modelled on
  `microsoft/secureboot_objects/scripts/test_validate_dbx_references.py`
  7-axis pattern (absent / empty / invalid JSON / missing field /
  ...). Coverage added:
  1. `Get-IsoBootCertReadiness` non-existent media → `.Available=$false`
     + `.ErrorMessage` mentions boot.wim
  2. `Get-IsoBootCertReadiness` schema completeness — the error-path
     inventory must still carry every documented snapshot field so
     P12 JSON serialization / P13 summary never AttributeError
  3. `Get-Pca2023ReadinessSnapshot` Health enum constraint — must be
     one of `{Healthy, Warning, Critical, Unknown}` even on the
     error path; never `$null` or free-form string

- **`.markdownlint.yaml` configuration file**. New project-root
  markdown lint config adapted from
  `microsoft/secureboot_objects/.markdownlint.yaml`. Adjusted for
  this project's conventions: line_length=120, code_blocks=false,
  tables=false; MD024 (duplicate headings) and MD041 (must-open-
  with-heading) disabled per Keep a Changelog and tests/README
  conventions. The file is opt-in for contributors who run
  markdownlint locally; CI is not yet wired to enforce it.

### Fixed (Schema v2.1 loader, post-publication regression)

The Stage A renumber and Stage B Pca2023 feature work bumped the
Config schema from v2.0 to v2.1 in all four `Config/Server*.json`
files, but **did not** update the `Get-ConfigProfile` loader's
schema-acceptance check, which remained `-eq '2.0'` and rejected
all four r05.0 Configs at runtime. The first `-Action
PrepareBuildVerify` smoke test (Stage 2 Smoke3) failed at P02
ResolveInputs with:

```
[X] Phase P02 (ResolveInputs) failed: Config Server2019.json has
    Schema="2.1"; expected "2.0". Legacy schemas are not supported.
```

Two loaders are now updated to accept both schemas:

- **`Get-ConfigProfile`** (the main per-OS loader called from P02
  ResolveInputs and from every Action that needs OS data) now
  accepts `Schema ∈ {'2.0', '2.1'}`. When `Schema == '2.1'`, the
  `Pca2023` block is also required (per SPEC.md B.10); when
  `Schema == '2.0'`, no Pca2023 block is required — preserving
  full backward compatibility with Configs predating r05.0.

- **`Invoke-AdminAction_RefreshAllBaselines`'s loader** (used by
  Action A01 to walk all four Configs for baseline refresh) is
  updated symmetrically. It also accepts both schemas but does
  not require `Pca2023` (the action only touches `PatchBaseline`
  fields, so the Pca2023 block is orthogonal).

The error message now lists all accepted schemas explicitly
(`expected one of: 2.0, 2.1`), so future schema bumps will produce
a self-documenting error indicating exactly which versions the
running script supports.

### Fixed (CI workflow remediation, r04.x carryover)

Audit of the most recent CI run on `main` (`1aa96df`, STAGE 1
Linux checks #12) surfaced two pre-existing problems that were
about to make the next push fail; both are fixed in r05.0:

- **STAGE 1 Config JSON validator was still using Schema v1 keys**
  (`OsName`, `OsShortName`, `Build`, `Architecture`, `Languages`
  at top level). Schema v2.0 (introduced in r03) restructured these
  under `Common/PatchBaseline/LanguageSpecific`, and Schema v2.1
  (r05.0) added the `Pca2023` block. The validator therefore failed
  with `FAIL: Server2016.json missing top-level "OsName"` and
  exited 1, which cascaded into "psa.sarif not produced" and
  "pssa.sarif not produced" errors in downstream steps. The
  validator has been rewritten to accept Schema 2.0 (warned) and
  2.1 (required), to verify the `Common.*` fields, and to enforce
  the `Pca2023` block presence when `Schema == 2.1`.

- **Embedded em dash (U+2014) in `Assert-WorkspacePreflight`** broke
  the BOM + CRLF + ASCII-only validator at line 2195. The character
  was introduced during Stage B Step 3 (NTFS check) and is now
  replaced with two ASCII hyphens. The validator now passes again
  (416,708 bytes, ASCII-only).

### Changed (CI infrastructure modernisation, r05.0)

Coordinated bump of all GitHub Actions to Node 24-compatible
versions ahead of the 2026-09-16 Node 20 removal deadline and the
December 2026 CodeQL Action v3 deprecation. Affects all 8 workflow
files (update-windows-server-iso STAGE 1-4, download-speakerdeck
STAGE 1-3, psa.py CI):

| Action | Was | Now |
|---|:---:|:---:|
| `actions/checkout` | `@v4` | `@v5` |
| `actions/setup-python` | `@v5` | `@v6` |
| `actions/upload-artifact` | `@v4` | `@v5` |
| `github/codeql-action/upload-sarif` | `@v3` | `@v4` |
| `peter-evans/create-pull-request` | `@v7` | `@v8` |
| `actions/cache` | `@v4` | `@v4` (unchanged - current) |
| `microsoft/psscriptanalyzer-action` | `@v1.1` | `@v1.1` (no v2 released) |

Additionally, `setup-python` now pins to **`python-version: '3.12'`**
instead of the previous `'3.x'`. The latter was resolving to
CPython 3.14.x on the GitHub-hosted Ubuntu 24.04 runner, which
has not been validated against psa.py + the T1-T5 self-
verification tool suite. Pinning to 3.12 (the version the project
has run its full test matrix on) restores deterministic behaviour
and forms an explicit upgrade point — bumping it requires running
the test matrix locally on the target Python version first.

Workflow comments referencing old phase IDs (`P02.5`, `P04.5`,
`P02/P03/P04`, `P08 verify`, "P01 through P09") are also updated
to the r05.0 phase numbering (`P03`, `P06`, `P02/P04/P05`,
`P11 verify`, "P01 through P13").

### Added (CI runner diagnostic pre-flight, r05.0)

Following review of the failed Stage 1 run from commit `1aa96df`,
each CI workflow gains a `[Diag] Runner environment snapshot` step
at the start of the job. The goal is to make triage tractable when
scheduled (Stage 4 cron) or flaky failures occur — every failed run
should carry enough information to diagnose runner-side drift
without re-running the job.

The diagnostic step captures (per stage):

| Stage | Diagnostic information |
|---|---|
| **Stage 1 / psa.py CI (Linux)** | `uname -a`, Python version, `pwsh` presence, CWD, key env vars, repo layout |
| **Stage 2 (Windows)** | `$PSVersionTable`, `Get-ExecutionPolicy -List`, console encoding, identity + admin check, env vars, oscdimg.exe presence at canonical ADK paths |
| **Stage 3 (Windows)** | Same as Stage 2 + free disk space on `C:` |
| **Stage 4 (Windows)** | PSVersion, ExecutionPolicy, identity, env vars |

Each diagnostic step uses `$ErrorActionPreference = 'Continue'`
(or `set +e` for bash) so a missing tool does not tank the
diagnostic step — the goal is to record what IS available.

Additionally, **all** non-diagnostic Windows PowerShell steps
across Stages 2, 3, and 4 are uniformly hardened with:

- `$ErrorActionPreference = 'Stop'` — prevents silent error
  swallowing (PS 5.1's default is `Continue`).
- `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` —
  prevents PS 5.1's legacy ANSI code-page default from mangling
  non-ASCII characters in log streams or `$GITHUB_*` files.
- `defaults.run.working-directory: ${{ github.workspace }}` at the
  job level — anchors relative paths to the checkout root rather
  than to a surprising platform-default location.

Background reference material is captured in
`documents/ci-engineering/github-actions-windows-powershell-guide.md`
(new file in this release). SPEC.md gains a new §C.5c documenting
the diagnostic-step contract.

## [update-wsi-2026.05.25-r04.4] - 2026-05-25

### Added - Self-verification tool suite (`tests/`)

A new `tests/` subdirectory ships alongside `Update-WindowsServerIso.ps1`
holding five Python-based self-verification tools. They exist because
the three live-test bugs fixed in r04.3 had a common root cause -
silent Microsoft-side change in the Catalog HTML / data that no
purely-static analysis could catch - and the project needed a way
for both Claude and human operators to confirm the script's
Microsoft-side assumptions still hold before AND after any change.

The tool suite:

| Tool | Purpose | Network? |
|---|---|:---:|
| `catalog_probe.py`        (T1) | Live Microsoft Update Catalog probe (search, supersedence panel, title-format per OS); diffs vs `snapshots/last_probe.json` | Yes |
| `catalog_fixture_test.py` (T2) | Offline regression test against saved HTML fixtures (`fixtures/2026-05/`); 13 assertions including bug-2 and bug-3 regressions | No |
| `powershell_harness.py`   (T3) | Python-side driver that invokes PowerShell functions via the new `-Action TestHarness` REPL; 7 assertions on Get-CatalogQueryTemplate, Select-AllCanonicalPatchFiles, etc. | No |
| `eval_iso_probe.py`       (T4) | HTTP Range-GET against each `Config/Server<N>.json#/.../Iso/Url`; reports MB + Last-Modified per OS | Yes |
| `wsusscn2_probe.py`       (T5) | HTTP probe of `wsusscn2.cab`; warns when the cab is older than 60 days | Yes |

All tools use **standard-library Python only** (no `pip install`
required), matching the dependency policy already set by
`scripts/python/powershell-static-analyzer/psa.py`.

The directory layout:

```
tests/
  README.md                    -- per-tool usage + when-to-run guide
  catalog_probe.py             -- T1
  catalog_fixture_test.py      -- T2
  powershell_harness.py        -- T3
  eval_iso_probe.py            -- T4
  wsusscn2_probe.py            -- T5
  common/
    catalog_client.py          -- urllib HTTP fetcher with retry-with-jitter
    html_parsers.py            -- Catalog HTML extractors (intentionally
                                  mirrors the PS regexes)
    ps_invoke.py               -- PSSession context manager driving the
                                  -Action TestHarness REPL
    snapshot.py                -- JSON snapshot read/write + diff_dict()
  fixtures/2026-05/            -- 6 HTML files (~331 KB) + expected.json
  snapshots/                   -- T1 output (last_probe.json) lives here
```

### Added - `-Action TestHarness` (script REPL hook)

The PowerShell script gains a new dispatcher branch `-Action TestHarness`,
placed before `Show-EntryBanner` so no banner contaminates stdout.
It loads all function definitions in the current session, then drains
stdin one JSON line at a time, parsing requests of the form
`{"fn":"<FunctionName>","args":{ ... }}` and emitting JSON responses
of the form `{"ok":true,"fn":"...","result": ...}` or
`{"ok":false,"error":"<message>","fn":"..."}`. The REPL exits on
EOF.

This is the entry point for T3 (`tests/powershell_harness.py`).
It is not intended for human invocation; the `-Action` help text
explicitly says so.

`-Action TestHarness` is added to the `osLessActions` set
(no `-OsVersion` required) and to the workspace-preflight skip list
(no Config / 100 GB requirement).

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,695 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- All 5 self-verification tools pass live + offline runs:
  - T1: 7/7 checks, snapshot persisted
  - T2: 13/13 fixture assertions
  - T3: 7/7 PowerShell function assertions
  - T4: 8/8 Iso endpoints (Server2016 endpoint host rejects Range/HEAD;
    treated as "unprobable, not broken")
  - T5: detects `host_not_allowed` egress in restricted environments
    and reports exit 3 (NOT 2), so the operator can tell apart
    "Microsoft outage" from "execution environment blocks the host"

### Compatibility

- `ScriptVersion` bumped to `update-wsi-2026.05.25-r04.4`;
  `ScriptTag` is `self-verification-tools-and-test-harness`.
- No behaviour change for any production Action (Prepare / Build /
  Verify / PrepareBuildVerify / RefreshAllBaselines / Cleanup etc.).
  The TestHarness branch is reached only by an explicit
  `-Action TestHarness` invocation.

## [update-wsi-2026.05.25-r04.3] - 2026-05-25

### Fixed - `NeutralPatches[].Type` mis-classification

Live first-pass test of `-Action RefreshAllBaselines` (2026-05 cycle)
exposed that the `Type` field on every Catalogue-derived
`NeutralPatches` entry was being computed by file-name heuristics in
`Get-PatchType`, even though the calling code in
`Resolve-PatchSetFromCatalog` already knew the authoritative Type
from the Catalogue search query (`SSU` / `LCU` / `DotNet` /
`DynamicUpdate.SafeOs` / `DynamicUpdate.Setup`). The heuristic
broke whenever the file name lacked the expected token (e.g. SSU
file names containing only `kb<N>` with no `servicingstack`
substring; SafeOS DU file names with `kb<N>` but no `safeos`;
.NET CU sub-files without `ndp<N>` or `.net`). Affected real
2026-05 entries were:

| OS | KbId | Title type | Wrong `Type` | Correct `Type` |
|---|---|---|---|---|
| Server2016 | KB5088064 | Servicing Stack Update | `LCU` | `SSU` |
| Server2019 | KB5088864 | Cumulative Update for .NET Framework | `LCU` | `DotNet` |
| Server2025 | KB5087588 | Safe OS Dynamic Update | `LCU` | `DynamicUpdate.SafeOs` |

The Type-routing in `$Script:PatchTargetMap` (SPEC §B.12) depends on
this field to send each patch to the right WIM-target sub-phase
(SPEC §B.14), so the mis-classification would have made install.wim
patching ineffective on a live ISO build.

**Fix**: added `-KnownType` parameter to
`Convert-CatalogPatchToBaselineEntry`. When the caller passes a
non-empty string (which `Resolve-PatchSetFromCatalog` now does
unconditionally via `-KnownType $q.Type`), the function uses that
value verbatim instead of running the file-name heuristic. The
heuristic remains as the fallback path for the empty-`KnownType`
case (preserving backwards compatibility for ad-hoc or test
callers). `Resolve-LanguageSpecificPatchesFromCatalog` was reviewed
and already constructed its entries with `Type = $q.Type` directly,
so no change was needed on the LSP side.

### Fixed - Server2022 Catalogue narrow filter returned zero results

Live first-pass test also exposed that **every** Server 2022 query
fell through `Resolve-PatchSetFromCatalog`'s narrow filter with
zero hits, producing an empty `PatchBaseline.NeutralPatches`
array for `Config/Server2022.json`. Microsoft Update Catalogue has
since dropped the comma in Server 2022 update titles
("Microsoft server operating system, version 21H2" →
"Microsoft server operating system version 21H2", matching the
Server 2025 / 24H2 format). The hard-coded TitleToken used
`[regex]::Escape($titleToken)` (literal match including the
comma), so the new comma-less titles failed to narrow.

**Fix**: `Get-CatalogQueryTemplate` Server2022 branch and
`Get-LanguagePackQueryTemplate` `osTitleTokens` now accept BOTH the
comma-less and the historical comma form via an OR-matched
`TitleTokens` array. The actual `Search.aspx` query strings were
also updated to the current (comma-less) form because that is
what the live Catalogue listings display. The new structure is
robust against any future Microsoft re-edit that flips the format
back.

Verification: live `-Action RefreshAllBaselines -DryRun -OnlyOs
Server2022` now resolves 5 patch entries (LCU + 2 .NET files +
supersedence-dedup of 3 stale .NET candidates), versus 0 before
the fix.

### Fixed - umbrella .NET CU lost N-1 sub-files

Live first-pass test exposed that umbrella .NET Cumulative Update
KBs (e.g. Server 2019 KB5088864 which bundles 4.7.2 and 4.8) lost
all but one MSU when `Select-CanonicalPatchFile` was called: the
function is designed to return a single best file, and there is no
genuine ranking between two ndp-runtime variants of the same
umbrella KB, so the second .msu was silently dropped. Effect: on
an install.wim that contains the dropped runtime, the .NET CU
would have been a no-op and the corresponding CVEs would have
remained unpatched.

**Fix**: added `Select-AllCanonicalPatchFiles` (companion to the
existing single-file picker). It applies the same scoring rules
(so Express / Delta / PSF / metadata are still rejected) but
returns every link that scored > 0. `Resolve-PatchSetFromCatalog`
now routes `Type='DotNet'` queries through the multi-file picker
and emits one `NeutralPatches` entry per surviving file, all
keyed off the same umbrella KB / UpdateId / Title. SSU / LCU /
SafeOS / Setup DU queries continue to use the single-file picker
since Microsoft publishes a single canonical file per UpdateId
for those types.

Verification: live `-Action RefreshAllBaselines -DryRun -OnlyOs
Server2022` for 2026-05 now keeps two .NET .msu files
(`...-x64-ndp481_...msu` and `...-x64-ndp48_...msu`) on the
KB5088862 umbrella entry, where r04.2 would have kept only one.

### Added - `Assert-WorkspacePreflight` (preflight check)

New mandatory preflight that runs before the Action dispatcher.
Two checks, both fatal:

1. **Config presence**. The four canonical
   `Config/Server<N>.json` files (Server2016, Server2019,
   Server2022, Server2025) must exist alongside the script. The
   check fails fast with a list of any missing files, so the run
   does not proceed into the Catalogue scrape only to throw a
   less-helpful "config not found" error in P02 / A01.
2. **Drive free space**. The drive backing `-WorkRoot` must have
   at least **100 GB** free. This is the documented minimum for
   an end-to-end `PrepareBuildVerify` run for one OS (input ISO
   ~7 GB + extracted source ~7 GB + mounted WIM scratch ~15 GB +
   patches ~10 GB + output ISO ~7 GB + DISM headroom). The disk
   check is skipped under `-DryRun` because dry runs do not
   actually write large files.

Preflight is placed **before** the Action dispatcher (rather than
inside P01) so that Admin actions like `-Action RefreshAllBaselines`
and `-Action DumpFieldClassification` (which never run P01) are
also protected. It is intentionally skipped for `-Action ListPhases`
(quick branch that exits without any workspace contact),
`-Action Cleanup` (whose entire purpose is to remove a
partially-built workspace), `-EnvironmentInfoOnly` (the user
explicitly asked for the env dump only), and `-SkipEnvCheck`
(operator override).

The existing P01 Step 4 disk-space check is retained as
informational only; the authoritative 100 GB enforcement happens
in the preflight, and Step 4 now only emits a warning when free
space is below 100 GB (which can only occur if `-SkipEnvCheck`
bypassed the preflight).

### Changed - `-WorkRoot` default is now script-relative

The default value of `-WorkRoot` has changed from the absolute
`C:\Temp\Workspace_UpdateWsi` to the script-relative
`Workspace_UpdateWsi`. The existing `Resolve-RelativeToScript`
helper resolves the relative path against `$Script:ScriptRoot`
(i.e. the directory containing `Update-WindowsServerIso.ps1`),
producing a workspace that lives next to the script tree by
default. Operators who relied on the old `C:\Temp\...` default
should pass `-WorkRoot 'C:\Temp\Workspace_UpdateWsi'` explicitly
or update their automation; the absolute-path override is
unchanged and still works.

The new default plays well with the preflight Config-presence
check above: when the workspace is script-relative, the
`Config/` directory checked by preflight is the same `Config/`
directory shipped with the script.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,627 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Live smoke `RefreshAllBaselines -DryRun -OnlyOs Server2025`:
  exit 2 (Manual fill expected), preflight passes, all 5 patch
  Types resolve correctly, supersedence dedup excludes one
  .NET 3.5+4.8.1 false-positive (unchanged from r04.2 behaviour).
- Live smoke `RefreshAllBaselines -DryRun -OnlyOs Server2022`:
  preflight passes, **5 patch entries resolve** (vs 0 in r04.2
  due to bug 2), the umbrella .NET CU keeps both ndp-runtime
  MSUs (vs 1 in r04.2 due to bug 3).

### Compatibility

- Existing `Config/Server<N>.json` files are unchanged in
  structure (Schema v2.0). r04.3 just produces correct `Type`
  fields and an extra .NET entry for umbrella KBs on the next
  `-Action RefreshAllBaselines` run.
- Operators who depended on the old `-WorkRoot` default need to
  either accept the new script-relative location or pass
  `-WorkRoot` explicitly.
- `ScriptVersion` is bumped to `update-wsi-2026.05.25-r04.3`;
  `ScriptTag` is `live-test-fixes-and-preflight-checks`.

## Documentation maintenance - 2026-05-24

### Added - `TESTING.md`

Created `TESTING.md` for this sub-project to align with the
repository-wide governance documented in the root [`README.md`](../../../README.md)
"Language Policy" section, which lists `TESTING.md` among the
sub-project documents that are maintained in English only. The
sister project `download-speakerdeck-oracle4engineer/` has carried
a `TESTING.md` from the start; adding one here brings this project
to parity.

Contents:

- **Section 0** — Verification status summary table
- **Section 1** — Static analysis gate (psa.py + PSScriptAnalyzer
  invocation and expected output)
- **Section 2** — Unit tests for the deterministic helpers
  (PatchPlan engine, sub-phase sequence builders,
  supersedence-aware deduplication; 14 test cases total)
- **Section 3** — Synthetic smoke tests 1 through 7 with command
  lines and acceptance criteria
- **Section 4** — Live Microsoft Update Catalogue verification
  (read-only network calls)
- **Section 5** — Operator-pending: real ISO integration. This
  section is intentionally a placeholder because the maintainer
  has no suitable Windows host with DISM access. The acceptance
  criteria are documented; the results table is empty until an
  operator runs the procedure end-to-end and submits results via PR.
- **Section 6** — Continuous integration coverage including the
  Stage 4 monthly-refresh workflow's role as a continuous
  verification of the Catalogue scrape paths
- **Section 7** — Discovered bugs and fix history (cross-references
  to the per-release CHANGELOG entries)

### Changed - sub-project `README.md` and `README.ja.md`

Both READMEs now list `TESTING.md` in the "Folder layout" /
「フォルダ構成」block and end with a paragraph pointing readers
to it ("If you want to know what has been verified and what is
still operator-pending, read TESTING.md").

### Changed - root `README.md` and `README.ja.md` (CI section)

The Continuous Integration section in both root READMEs was
updated to reflect the four `update-windows-server-iso` workflows
introduced in r03 and r03.1:

- The intro line changed from "four GitHub Actions workflows" to
  "eight GitHub Actions workflows" (the Japanese equivalent
  changed from "4 本" to "8 本").
- Four new rows were added to the badge table:
  Update-WindowsServerIso STAGE 1 (Linux), STAGE 2 (Windows),
  STAGE 3 (Synthetic full pipeline), STAGE 4 (Monthly baseline
  refresh).
- A new paragraph immediately after the badge table explains the
  Stage 4 workflow's distinctive `cron`-on-the-15th schedule, its
  PR-creation behaviour when `Config/Server*.json` baselines drift
  from the live Microsoft Update Catalogue state, and its
  classification as an operations workflow (not a quality gate;
  failures do not block other workflows).

These updates close a documentation gap that opened when the
Update-WindowsServerIso project was first added to the repository:
the per-sub-project STAGE 4 workflow existed in `.github/workflows/`
and was already documented in this project's CHANGELOG, but the
root READMEs had not been refreshed to reflect the new total
workflow count.

### Quality

- `psa.py` and PSScriptAnalyzer baselines are unchanged from
  r04.2 because no source code was modified. This is a
  documentation-only maintenance pass.
- `ScriptVersion` is **not** bumped; this entry follows the
  same precedent as the sister project's r21 cleanup commit
  (documentation-only changes do not require a script version
  change).

## [update-wsi-2026.05.24-r04.2] - 2026-05-24

### Added - Supersedence-aware Catalogue patch selection

`Resolve-PatchSetFromCatalog` (in `.build_part08c_catalog_scraper.ps1`)
now resolves the case where the OS-aware Catalogue search returns
multiple candidates for a single patch Type. Previously this case
silently picked `narrowed[0]` (sort-stable but with no real-world
meaning), which could let a wrong KB through when:

- The same monthly slot has both a preview and a final entry
- A neighbouring KB (e.g. a ".NET Framework 3.5 and 4.8.1 Cumulative
  Update") matches the OS Title token used in the LCU query
- Catalogue HTML structure changes confuse the narrowing predicate

The new logic invokes `Get-SupersedenceFromCatalog` for each
non-Preview narrowed candidate, then calls the new
`Select-LatestPatchBySupersedence` helper to keep only the latest
survivor. Excluded candidates are recorded in
`$Script:LastSupersedenceExclusions` for the caller's diagnostic CSV.

Supersedence lookup is only triggered when the narrowed candidate
count exceeds 1; the single-candidate case bypasses the extra HTTP
calls.

### Added - `Select-LatestPatchBySupersedence` helper

New module `.build_part09d_supersedence.ps1` (~200 lines) implements
the deduplication logic:

| Input cardinality | Behaviour |
|-------------------|-----------|
| 0 candidates | Returns `Best=$null`, `Excluded=@()` |
| 1 candidate  | Returns that candidate as Best |
| 2+ candidates | Exclusion pass: any candidate whose KbId or UpdateId appears in another candidate's `Supersedes` array is dropped; if exactly one survivor remains, it is the Best; if multiple survivors remain, sort descending by Title (Catalogue titles start with `YYYY-MM` so lexicographic desc = newest) and pick the first, marking the rest as `Ambiguous; chose newest by title` |
| Edge case (all candidates excluded each other) | Fall back to the first input candidate with a warning |

Each excluded entry carries `Type`, `ExcludedKbId`, `ExcludedTitle`,
`SupersededByKbId`, `SupersededByTitle`, `MatchedToken`, and a
human-readable `Reason` suitable for CSV emission.

### Added - `Get-KbIdFromUpdateTitle` helper

Small utility that extracts the `KB######` substring from a
Catalogue update title using the canonical `(KB\d{6,7})` pattern.
Returns an empty string when no KB id is present.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,368 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Select-LatestPatchBySupersedence` (5/5 PASS):
    * Two candidates with cand2 superseding cand1 -> cand1 excluded
    * Single candidate -> passthrough, no exclusion
    * Two candidates without supersedence relation -> ambiguous, title-desc tiebreak
    * Supersedes contains UpdateId (not KbId) -> substring match still works
    * Empty input -> Best=$null
- Unit tests for `Get-KbIdFromUpdateTitle`: extracts from canonical titles, returns empty for non-matches.
- Live Smoke 5 (`-Action RefreshAllBaselines -DryRun -OnlyOs Server2025`)
  exercises the supersedence path on real Microsoft Update Catalogue
  data and correctly excludes a stray .NET 3.5+4.8.1 candidate that
  the LCU OS-aware query had picked up as a false positive.

### Changed - Documentation cleanup

References to the deferred ".NET 3.5 Feature on Demand" item have
been removed from CHANGELOG and SPEC. The feature is no longer in
scope: Microsoft's recommended deployment path for .NET 3.5 is to
enable it after image deployment via `Install-WindowsFeature
NET-Framework-Core` (or `Add-WindowsCapability -Online`), not to
embed it in the image.

### Compatibility

- No schema change. Config files (`Config/Server*.json`) and the
  PatchPlan hashtable shape are unchanged from r04.1.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04.2`;
  `ScriptTag` is `supersedence-aware-patch-selection`.
- Existing single-candidate Catalogue queries see no behaviour
  change (the extra `Get-SupersedenceFromCatalog` calls only fire
  when narrowing leaves 2 or more candidates).

### Out of scope (deferred to a future release)

- Setup binaries servicing via pending.xml (Setup DU). Microsoft
  Server LTSC editions rarely publish Setup DU, and verification
  requires a Windows host running setup.exe, so this is not
  high-leverage for our use case.
- Per-language Optional Components for WinRE.
- ISO release detection refresher for `LanguageSpecific.<lang>.Iso`.
- Python JSON Schema validator that consumes the
  `DumpFieldClassification` output.

## [update-wsi-2026.05.24-r04.1] - 2026-05-24

### Added - Microsoft media-dynamic-update servicing sub-phase engine

The PatchPlan engine introduced in r04 now emits ordered sub-phase
sequences (per-WIM-target) that reproduce Microsoft's official
servicing sequence end-to-end:

**install.wim sequence** (with twice-apply when language packs are
present):

| Sub-phase                    | Patches              | Notes |
|------------------------------|----------------------|-------|
| I1.SSU                       | SSU                  | servicing stack first |
| I2.LanguagePack              | LP / LXP / DotNet LP | must precede LCU |
| I3.LCU.FirstPass             | LCU                  | after LP per Microsoft |
| I4.DotNet                    | .NET CU              | |
| I5.DynamicUpdate.Component   | DU.Component         | |
| I6.CleanupAndExport          | (marker)             | DISM cleanup hook |
| I7.LCU.SecondPass            | LCU (re-applied)     | only when LP injected; requires remount |

**boot.wim sequence** (no twice-apply needed):

| Sub-phase | Patches | Notes |
|---|---|---|
| B1.SSU              | SSU         | |
| B2.LanguagePack     | LP          | recovery UI language |
| B3.LCU              | LCU         | |
| B4.CleanupAndExport | (marker)    | |

**WinRE.wim sequence** (Safe OS DU replaces LCU per Microsoft):

| Sub-phase | Patches | Notes |
|---|---|---|
| W1.SSU              | SSU                  | (combined LCU acts as SSU surrogate) |
| W2.LanguagePack     | LP                   | recovery UI |
| W3.SafeOsDU         | DynamicUpdate.SafeOs | WinRE-only LCU substitute |
| W4.CleanupAndExport | (marker)             | Export /Compress:Recovery |

### Added - LCU twice-apply (I7.LCU.SecondPass)

Per Microsoft's documented rationale: when a language pack is
injected into install.wim, the LP can shadow files that the LCU
delivered on its first pass, leaving the LCU partially un-applied.
The fix is to re-apply the LCU AFTER the WIM has been
dismounted+committed+exported. The engine emits I7 only when
language packs are actually present in the plan; otherwise the
single-pass flow is preserved (no wasted remount).

The P07 worker honours the I7.RequiresRemount = $true flag by
dismounting after I1-I6, then re-mounting the now-serviced
install.wim for the I7 sub-phase, then dismounting again.

### Added - Full WinRE servicing worker

P08's WinRE block now reads the WinReSequence (W1.SSU -> W2.LP ->
W3.SafeOsDU -> W4.CleanupAndExport) from the cached PatchPlan and
applies each sub-phase against the WinRE.wim it extracted from
install.wim. The serviced WinRE is then copied back into the
install.wim mount so the surrounding install.wim dismount commits
the change. Skips the WinRE mount entirely when the sequence is
empty.

### Added - Invoke-PatchSubPhase common helper

A single helper drives the per-sub-phase apply loop for all three
sequences (Install / Boot / WinRE). It handles DryRun, missing
LocalPath, and Add-WindowsPackage failures uniformly, emits per-
patch result rows for the CSV inventory, and writes structured
error records via Add-ErrorJsonlEntry on failure.

### Added - Build-{Install,Boot,WinRe}ApplySequence builders

These three helpers (in .build_part09c_patchplan.ps1) bucket the
flat patch list per Type and emit the ordered sub-phase array. The
mapping logic (which Type belongs to which sub-phase, when to emit
I7, etc.) is centralised here so future tweaks (e.g. adding a new
SafeOS DU lane to install.wim) only touch one place.

### Changed - P07 / P08 worker control flow

Both phase workers now consume sub-phase sequences instead of a
flat patch list. The legacy `Get-PatchListForInstall|Boot|WinReWim`
helpers (introduced in r04) remain in place for backwards
compatibility with diagnostic consumers; the workers themselves
no longer iterate them. CSV inventory rows now include the new
`SubPhase` column.

P07's install.wim block iterates the install sequence in order;
when a sub-phase has RequiresRemount = $true it is deferred into
a second-pass buffer that runs after the first dismount completes.
This produces a 1-mount or 2-mount pattern depending on whether
language packs are present, matching the Microsoft sequence
exactly.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,112 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Sub-phase engine unit tests (5/5 PASS):
    * I7 NOT emitted when no LP in plan
    * I7 emitted with RequiresRemount=$true when LP present
    * boot.wim sequence: B1.SSU -> B2.LP -> B3.LCU -> B4.cleanup
    * WinRE sequence: W1.SSU -> W2.LP -> W3.SafeOsDU -> W4.cleanup (LCU is NOT in WinRE)
    * Empty input -> skeleton sub-phases all present, all empty
- Smoke 3 (Synthetic+DryRun): PatchPlan summary now shows all three
  sub-phase sequences end-to-end.

### Compatibility

- No schema change. PatchTargetMap and PatchDependencyPolicy from
  r04 are unchanged.
- The PatchPlan hashtable gains three new keys (InstallSequence,
  BootSequence, WinReSequence) but the legacy lane keys
  (Install / Boot / WinRE / Setup) are still present and still
  hold the flat sorted lists.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04.1`;
  `ScriptTag` is `lcu-twice-winre-and-lp-injection`.

### Out of scope (deferred to a future release)

- Setup binaries servicing via pending.xml (Setup DU).
- Per-language Optional Components for WinRE.

## [update-wsi-2026.05.24-r04] - 2026-05-24

### Added - WIM-target-aware patch plan engine

A new module (`.build_part09c_patchplan.ps1`) introduces the
`Build-PatchPlan` function that converts the flat
`$Script:ResolvedPatches` array into a target-aware plan with four
lanes:

| Target | Receives |
|--------|----------|
| Install | every patch whose Type maps to "Install" |
| Boot    | every patch whose Type maps to "Boot"    |
| WinRE   | every patch whose Type maps to "WinRE"   |
| Setup   | every patch whose Type maps to "Setup"   |

The mapping is centralised in the new `$Script:PatchTargetMap`
constant in `.build_part03_helpers.ps1`. Following Microsoft's
media-dynamic-update guidance:

| Patch Type              | Targets                  |
|-------------------------|--------------------------|
| SSU                     | Install + Boot + WinRE   |
| LCU                     | Install + Boot           |
| DotNet                  | Install                  |
| DynamicUpdate.Component | Install                  |
| DynamicUpdate.SafeOs    | WinRE                    |
| DynamicUpdate.Setup     | Setup                    |
| LanguagePack            | Install + WinRE          |
| LXP                     | Install                  |
| DotNet.LangPack         | Install                  |

Unknown Types fall back to `[Install]` with a one-time warning per
unique unknown Type.

P02 (`ResolveInputs`) now builds the plan and prints a per-target
summary at the end of the phase. P07 and P08 retain their legacy
`Get-PatchListForInstall|Boot|WinReWim` helpers; these now delegate
to the cached plan so existing call sites stay unchanged.

### Added - Pre-apply dependency closure check

A new helper, `Test-PatchDependencyClosureOnMount`, runs inside the
P07 install.wim and P08 boot.wim apply loops immediately after the
WIM mount and just before the first `Add-WindowsPackage` call. For
each patch whose `RequiresKbIds` is non-empty, it enumerates the
mounted image via `Get-WindowsPackage` and verifies that every
required KB is already present (`PackageIdentity` substring match
against the recorded KB ID).

The check is governed by `$Script:PatchDependencyPolicy`, default
`'Strict'`. Strict mode throws on the first unsatisfied
prerequisite, aborting the run before DISM emits the cryptic
0x800f0823 servicing-stack precondition error. The alternate
`'Warn'` mode logs a warning and continues; there is no CLI flag
yet, but the variable can be set from a wrapper script.

`-DryRun` short-circuits the check with a notice (no real mount to
enumerate against).

### Changed - Patch selection helpers delegate to PatchPlan

The legacy `Get-PatchListForInstallWim` / `Get-PatchListForBootWim`
helpers in `.build_part12_phase05_06_07.ps1` are now thin wrappers
that read from the cached `$Script:PatchPlan`. A new
`Get-PatchListForWinReWim` helper is added for completeness; the
WinRE worker itself is delivered in a follow-up release together
with the LCU twice-apply pattern and language-pack injection.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (6,700 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Build-PatchPlan`:
    * Typical monthly patch set (SSU/LCU/.NET/SafeOS/Setup) routes
      to the expected lanes
    * LP/LXP correctly differentiated (LP -> Install+WinRE; LXP ->
      Install only)
    * Unknown Type falls back to Install with warning
    * Empty input handled gracefully
- All existing smoke tests still pass; Smoke 5 (live Catalogue
  scrape against Server2025 / 2026-05) resolves 3 patches and the
  combined-LCU detection still fires.

### Compatibility

- Schema v2.0 is unchanged. The new mapping lives in script code
  rather than in the Config files, so adding a new patch Type only
  requires editing `$Script:PatchTargetMap`.
- Existing PatchBaseline entries continue to work; the engine
  reads `.Type`, `.KbId`, `.ApplyOrder`, `.RequiresKbIds` and
  ignores everything else.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04`;
  `ScriptTag` is `wim-target-aware-patch-plan`.

### Out of scope (deferred to the next release in the r04 line)

- LCU twice-apply sequence in P07 around language-pack injection.
- WinRE.wim mount / service / dismount worker in P08.
- Language Pack injection on install.wim and WinRE.wim.

## [update-wsi-2026.05.24-r03.1] - 2026-05-24

### Added - Stage 4 CI workflow: monthly baseline refresh

A new GitHub Actions workflow,
`.github/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml`,
runs `-Action RefreshAllBaselines` on a schedule and opens an
automated pull request whenever the `Config/Server*.json` baselines
change. This completes the runtime story for r03's admin action:
baseline maintenance now happens without any human invocation.

Schedule: 02:00 UTC on the 15th of every month. Patch Tuesday is the
second Tuesday (8th-14th of the month); waiting until the 15th gives
Microsoft a 1-7 day window for late re-publications and Catalogue
indexing to settle.

Manual invocation: `workflow_dispatch` with four inputs:
- `mode`         : Monthly / Initial / Force (default: Monthly)
- `onlyOs`       : Server2016 / 2019 / 2022 / 2025 or blank for all
- `onlyLanguage` : en-us / ja-jp or blank for all
- `dryRun`       : true / false (default: false)

The workflow accepts the PowerShell exit code semantics established
in r03: 0 (clean) and 2 (some Manual fields remain) are treated as
success; 1 (orchestrator failure) and anything else fails the run.

PR contents:
- Title: `chore(uwsi): monthly baseline refresh (run #<id>)`
- Branch: `auto/uwsi-baseline-refresh-<id>` (deleted after merge)
- Files: only `scripts/powershell/update-windows-server-iso/Config/*.json`
- Labels: `automated`, `update-windows-server-iso`, `baseline-refresh`
- Body includes the run parameters, exit code, modified-file list,
  and a reviewer checklist for verifying combined-LCU flags and
  PatchTuesdayOfBaseline correctness.

Artefacts:
- `A01_RefreshAllBaselines_report.csv` (per-group decision matrix)
- `debugtrace.jsonl` (script-side trace)

both uploaded to the workflow run with 30-day retention.

A GitHub Actions step summary (`$env:GITHUB_STEP_SUMMARY`) is
always written, even on failure, so the maintainer can see at a
glance what happened without diving into logs.

### Notes

- The PowerShell script body itself is unchanged from r03; r03.1 is
  purely an operations release. `ScriptVersion` is bumped to
  `update-wsi-2026.05.24-r03.1` so workflow runs and PR commit
  messages identify the operations level distinctly from r03.
- `ScriptTag` is `stage4-monthly-refresh-ci`.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings.
- All existing smoke tests still pass.
- YAML syntax validated via PyYAML (8 steps).

### Compatibility

- Pure additive change: a new file under `.github/workflows/`. The
  three existing workflows (Stage 1 Linux / Stage 2 Windows / Stage 3
  synthetic-pipeline) are untouched.

### Out of scope (deferred to r04 onward)

Per the "未実装機能の全体マップ" review, the next deliverables are:
- r04: Microsoft-official servicing sequence compliance
  (WIM-target-aware patch plan; LCU twice-apply; pre-apply
   Get-WindowsPackage dependency closure check; WinRE servicing;
   per-WIM AppliesTo metadata; Language Pack injection in P07).
- r05: Supersedes-based superseded KB auto-removal; ISO-release
  refresher; Python JSON Schema validator.

## [update-wsi-2026.05.24-r03] - 2026-05-24

### BREAKING - Config Schema v2.0 (no migration path)

The Config/Server*.json data model has been redesigned with a 3-tier
hierarchy. There is NO migration sidecar; r02.x configs are rejected
by Get-ConfigProfile with a clear error message. Configs must be
either authored manually as v2.0 or generated by RefreshAllBaselines.

The new layout separates three concerns:
- `Common`           : OS-wide constants (build, edition, WIM index)
- `PatchBaseline`    : neutral patches (SSU/LCU/.NET CU/DU.*) shared
                       across all languages
- `LanguageSpecific` : per-language ISO source + LP / LXP / .NET LP

Adding a new language now requires only one node under
`LanguageSpecific` plus listing it in `Common.SupportedLanguages`.

Each field group carries a verification marker:
- `Common._VerifiedDate` / `Common._VerifiedBy`
- `PatchBaseline.LastVerifiedDate` / `LastVerifiedBy`
- `LanguageSpecific.<lang>.Iso._VerifiedDate` / `_VerifiedBy`
- `LanguageSpecific.<lang>.LanguageSpecificPatches.LastVerifiedDate`
   / `LastVerifiedBy` / `PatchTuesdayOfBaseline`

An empty `_VerifiedDate` flags the group as "unresolved" for the
RefreshAllBaselines decision matrix.

### Added - `Action.RefreshAllBaselines` (Admin phase A01)

```
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -DryRun
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Initial
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Force
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyOs Server2025
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyLanguage ja-jp
```

Three operating modes:

| Mode    | What gets refreshed |
|---------|---------------------|
| Initial | Every field group whose `_VerifiedDate` is empty |
| Monthly | Field groups whose Cadence is `PatchTuesday` AND whose recorded `PatchTuesdayOfBaseline` is older than the latest Patch Tuesday (default) |
| Force   | Every field group, regardless of verification state or cadence |

For each field group the decision is one of: `Skip` (verified and
current), `InitialFill` (auto-fill an empty group, requires
Refresher), `Monthly` (auto-refresh due to new Patch Tuesday), or
`Manual` (no Refresher available, group must be populated by hand).

A CSV report is emitted to
`<WorkRoot>/logs/A01_RefreshAllBaselines_report.csv` with the
per-group decision; the on-screen summary groups counts by decision
type. Exit codes: 0 (all OK), 1 (one or more Refresher calls failed),
2 (some fields require manual fill).

### Added - `Action.DumpFieldClassification` (Admin phase A02)

Emits `<WorkRoot>/logs/A02_FieldClassification.json` containing the
`$Script:OsConfigFieldGroups` constant, intended for downstream
Python tooling (a future JSON Schema validator). No Catalogue
network access is required.

### Added - Field classification constant

`$Script:OsConfigFieldGroups` is a top-level constant declared in
`.build_part03_helpers.ps1` that maps each logical field group to a
Cadence (Stable / PatchTuesday / IsoRelease) and an optional
Refresher function name. Adding a new field group is a one-line
addition followed by either implementing a new Refresher or leaving
it Manual.

### Added - Per-language patch scraper

New helper `Resolve-LanguageSpecificPatchesFromCatalog` queries
Microsoft Update Catalog for Language Pack, LXP, and .NET Framework
Language Pack matching `OsVersion` + `OsLanguage` + `PatchMonth`.
Best-effort: empty results are treated as "verified absence" rather
than failures, because Microsoft does not publish LP / LXP for every
OS x month combo. Reuses `Select-CanonicalPatchFile` from r02.5 for
file picking.

### Fixed - Stage 2 Smoke 3 (Synthetic+DryRun) failed at P05

`New-SyntheticTestIso` produces a structurally-degenerate ISO9660
image (4-byte placeholder boot files wrapped by oscdimg.exe) that
`Mount-DiskImage` in P05 rejects as "file or directory is corrupted".
Stage 3 (Synthetic+Execute) already bypassed P05 by going straight
to P07; this aligns Stage 2 Smoke 3 with that flow by removing
`P05` and `P06` from `PrepareBuildVerify` / `All` when
`$Script:SyntheticTestMode -eq $true`. No behaviour change for
non-synthetic runs.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (6,344 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Smoke 1 (`-Action ListPhases`): exit 0; A01 / A02 registered;
  Actions section lists `RefreshAllBaselines : A01` and
  `DumpFieldClassification : A02`.
- Smoke 2 (`-EnvironmentInfoOnly`): exit 0; P01 only.
- Smoke 3 (`-SyntheticTestMode -DryRun`): P01 SKIPPED -> P02 DONE ->
  P03 DONE (skip) -> P04 DONE (synthetic ISO) -> P07 ... (P05 /
  P06 are correctly absent from the phase list on Windows).
- Smoke 4 (`-Action DumpFieldClassification`): exit 0; JSON written.
- Smoke 5 (`-Action RefreshAllBaselines -DryRun -OnlyOs Server2025`):
  exit 2 (DryRun + unresolved Iso fields); all 4 field groups
  produce the expected decision (Common=Skip, PatchBaseline=Monthly,
  Iso=Manual x2, LangSpecificPatches=Monthly x2).
- Smoke 6 (`-Mode Force -OnlyLanguage ja-jp`): Force overrides Skip
  for verified Common (-> Manual); OnlyLanguage filters out en-us.
- Smoke 7 (`-Mode Initial`): same decisions as Monthly for this
  baseline (PatchTuesdayOfBaseline empty -> Monthly).

### Compatibility

- This is a destructive schema change. r02.x Configs will be
  rejected. Authoring new Configs by hand is supported; the easiest
  path is to start from a v2.0 Config in this repo and adjust the
  `Common.Build` / `LanguageSpecific.<lang>.Iso.Url` fields.
- `ScriptVersion` is `update-wsi-2026.05.24-r03`;
  `ScriptTag` is `schema-v2-and-refresh-all-baselines`.

### Out of scope (deferred to r04 Option Z)

- WIM-target-aware patch plan (install/boot/winre per-target patch
  lists per Microsoft media-dynamic-update sequence).
- LCU twice-apply pattern around language-pack injection.
- Pre-apply Get-WindowsPackage dependency closure check.

## [update-wsi-2026.05.24-r02.5] - 2026-05-24

### Fixed - Catalogue search precision + multi-file disambiguation (Option X)

r02 introduced Microsoft Update Catalogue scraping (P03) with three
quality issues that this release fixes. The fixes are based on
Microsoft's official media-dynamic-update guidance plus a review of
WIM Witch, WimWizard, and WIM-Tools reference implementations.

**Problem A - OS-version-aware Catalogue query templates.**
Previously, queries used a loose token like `"servicing stack update
Windows Server 2022"`. Microsoft's actual Catalogue Title pattern for
Server 2022 is `"... Servicing Stack Update for Microsoft server
operating system, version 21H2"` (with a literal comma) and requires
a `Product` / `Description` disambiguator to separate Setup-DU from
SafeOS-DU. The previous loose match could conflate multiple OS
versions in results. Replaced with `Get-CatalogQueryTemplate` which
returns the exact Title patterns documented in
https://learn.microsoft.com/windows/deployment/update/media-dynamic-update,
per OS version (2016 / 2019 / 2022 / 2025).

**Problem B - Combined LCU detection.**
Since 2021 Microsoft embeds the SSU into the LCU and publishes
standalone SSUs only "in rare cases of a breaking change"
(Microsoft Learn quote). The previous code's
`RequiresKbIds = $ssuKbs` assignment treated SSU as always-present
and could falsely report "missing SSU" in P06 validation. Added
`Test-IsCombinedLcuTitle` (explicit marker check) and a structural
detector inside `Resolve-PatchSetFromCatalog` that treats
"SSU search returned zero AND LCU search returned non-zero" as a
combined-LCU month. In combined months, the LCU entry is annotated
with `IsCombined=$true` and its `RequiresKbIds` is left empty.

**Problem C - Multi-file Catalogue selection.**
The previous code did `$primary = $links[0]`, which for .NET
Cumulative Updates and other multi-file packages was a coin toss
between Full, Express, and Delta variants. Picking Express / Delta
breaks `Add-WindowsPackage` because differential packages require a
base. Replaced with `Select-CanonicalPatchFile`, a scoring-based
picker that rejects `express`, `delta`, `psf`, and metadata text
files outright, and prefers `.msu > .cab`, matching architecture,
and (for .NET) matching `ndp<version>` markers.

### Added

- `Get-CatalogQueryTemplate` (~150 lines): OS-specific Catalogue
  Title templates + optional Product / Description filters.
- `Get-CatalogQueryUrl` (~30 lines): builds a Search.aspx URL with
  quoted Product / Description filter tokens.
- `Test-IsCombinedLcuTitle` (~15 lines): title-level combined marker.
- `Select-CanonicalPatchFile` (~80 lines): scoring-based file picker.
- LCU entries now carry an `IsCombined` boolean property in
  PatchBaseline; all patch entries carry a `Variant = 'Full'` string
  (placeholder for r03's `Variants[]` array).

### Changed

- `Resolve-PatchSetFromCatalog` reworked as a two-pass orchestrator:
  pass 1 runs all per-type Catalogue searches and records narrowed
  candidates; the combined-LCU detector runs on the aggregate; pass 2
  resolves the single canonical download file per surviving candidate
  via `Select-CanonicalPatchFile`. Eliminates `$primary = $links[0]`.
- Server 2019 / 2016 queries no longer include `DynamicUpdate.Setup`
  or `DynamicUpdate.SafeOs` (Microsoft does not publish those monthly
  for the older Server LTSC SKUs; they only appear during feature-
  update windows). `Test-PatchBaselineUsable` continues to accept
  partial sets so this is not a regression.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,611 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Select-CanonicalPatchFile` and
  `Get-CatalogQueryTemplate` pass:
    * full + express -> selects full
    * delta only -> returns null
    * Server 2022 template contains comma form
    * .NET CU with ndp48 prefers the ndp48 variant

### Compatibility

- PatchBaseline schema remains at "1.0". The new `IsCombined` and
  `Variant` fields are added via `Add-Member -Force` so existing
  `Save-ConfigWithBaseline` rewrites them as ordinary JSON properties.
- Existing r02.4 Configs are read transparently; missing
  `IsCombined`/`Variant` fields default to `$false`/`'Full'` when
  consumed by P04/P06/P07.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r02.5`;
  `ScriptTag` is `catalog-multifile-and-combined-lcu`.

### Out of scope (deferred to r03 Option Y / Z)

- WIM-target-aware patch plan (install/boot/winre per-target
  patch lists per Microsoft media-dynamic-update sequence).
- LCU twice-apply pattern around language-pack injection.
- Language Pack acquisition per `OsLanguage`.
- Pre-apply `Get-WindowsPackage` dependency closure check.

## [update-wsi-2026.05.24-r02.4] - 2026-05-24

### Fixed - `-EnvironmentInfoOnly` smoke test failed on Windows runner

The `-EnvironmentInfoOnly` switch is intended to be a CI-friendly
"dump PowerShell environment info and exit 0" smoke flag. It was
working in spirit (the Step 0 environment dump did print, with a
message `EnvironmentInfoOnly requested; exiting after env dump.`)
but it was NOT actually exiting the script. The reason: P01's check
issued a bare `return`, which only leaves the phase function. The
phase runner then proceeded to P02 (`ResolveInputs`), which throws
`-OsVersion is required for P02 (...)` because the smoke caller
deliberately omits `-OsVersion`. Stage 2 reported exit code 1.

This was a latent bug present since r01. It was hidden in early
Stage 2 runs because the run-level summary did not surface P02's
internal throw clearly; the recent Stage 2 logs in r02.3 made the
P02 failure visible, which is how it was caught.

Fix: add an `EnvironmentInfoOnly` early branch in the main entry
point that pins `$phaseList = @('P01')` before dispatching. P02+
are simply not in the dispatch list, so the post-P01 flow runs the
normal phase-summary tail and the script exits 0. The pre-existing
`return` inside `Invoke-SetupPhase01_Initialize` still works as a
graceful exit point for Step 0; nothing else in P01 fires.

This complements (rather than replaces) the existing
`Action -eq 'ListPhases'` and `Action -eq 'Cleanup'` early-exit
branches, matching the same idiom.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.

### Compatibility

- Surface behaviour change is localised to `-EnvironmentInfoOnly`:
  it now exits 0 cleanly after P01 instead of erroring out in P02.
  No other code path is affected.
- `ScriptVersion` bumped to `update-wsi-2026.05.24-r02.4`;
  `ScriptTag` is `environment-info-only-early-exit`.

## [update-wsi-2026.05.24-r02.3] - 2026-05-24

### Fixed - legacy error-helper cleanup (inherited from r01)

`Update-WindowsServerIso.ps1` carried three latent API signature
mismatches inherited from r01 that did not show up in the smoke tests
because they only surface on a failure path under specific conditions.
Fixing them now so the next genuine failure produces a readable error
message instead of a misleading "parameter not found" secondary error.

- `Add-ErrorJsonlEntry`: the function body was a verbatim copy from
  the SpeakerDeck downloader project that produced this script's
  scaffold. It took a single `-Item` parameter and serialised
  SpeakerDeck-specific fields (`DeckUrl`, `PublishDate`, etc.).
  Both call sites in this script
  (`Invoke-BuildPhase07_PatchInstallWim`'s `Add-WindowsPackage` catch,
  and `Invoke-PhaseRunner`'s top-level phase catch) instead pass
  `-Phase / -Kind / -Properties` for a generic phase-failure record.
  The two surfaces had been silently incompatible since r01.
  Rewrote `Add-ErrorJsonlEntry` to the actual contract the callers
  use: `-Phase <PNN> -Kind <label> -Properties <hashtable>`, merging
  the hashtable into a fixed-schema JSON object with reserved-key
  protection.
- `Enable-DebugTraceFileOutput`: the function declares `-Directory`
  but was called with `-LogsDir`. Fixed at the call site in the
  top-level script body.
- `Enable-AutoExportOnPhaseFailure`: declares `-OutputDirectory`
  but was called with `-DiagDir`. Fixed at the call site.

### Removed - SpeakerDeck-downloader dead code

The following functions were inherited verbatim from the SpeakerDeck
downloader scaffold and were never referenced by any ISO Updater code
path. Removed to eliminate confusion and reduce surface area:

- `Get-FailureCategory` (HTTP / IO / WebException categorisation
  tailored for SpeakerDeck failures).
- `Write-FailureDiagnostic` (per-deck plain-text dump under
  `$Script:FailedDir`, a variable that this script never sets).

A stale reference to `Write-FailureDiagnostic` in a comment inside
`.build_part04_debugtrace.ps1` was also cleaned up.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.
- Line count: 5,452 -> 5,310 (-142, all dead-code removal).
- All 11 `Start-DebugTrace` call sites use `-Context <fn> -PhaseId <PNN>`.
- All 2 `Add-ErrorJsonlEntry` call sites use `-Phase / -Kind / -Properties`.
- All `Enable-*` debug-trace setup calls use the correct parameter names.

### Compatibility

- Pure cleanup release: behaviour is identical for the successful
  pipeline (no `Add-ErrorJsonlEntry` calls occur on the happy path).
- The first observed change will be in the on-disk format of
  `<WorkRoot>/logs/<...>_errors.jsonl` when a phase actually fails:
  it now contains the intended `phase` / `kind` / caller-supplied
  diagnostic properties instead of the previous (never-reached)
  SpeakerDeck-shaped record.
- `ScriptVersion` bumped to `update-wsi-2026.05.24-r02.3`;
  `ScriptTag` is `legacy-error-helper-cleanup`.

## [update-wsi-2026.05.24-r02.2] - 2026-05-24

### Fixed — Stage 2 smoke-test failure introduced by r02

r02.1 cleared the PSScriptAnalyzer findings, but the Stage 2 job still
exited 1 because Smoke test 3 (`-Action PrepareBuildVerify
-SyntheticTestMode -DryRun -SkipEnvCheck`) hit a fatal error inside the
new phase P03. Root cause: when `Start-DebugTrace` was called from the
two new phase workers I introduced in r02, the wrong parameter name
`-PhaseName` was used. The correct name (used by every other phase in
this script) is `-Context`. PowerShell 5.1's partial-match logic
reported the failure as "A parameter cannot be found that matches
parameter name 'Phase'." because `-PhaseId` and `-PhaseName` collide
on the same prefix.

- `Invoke-SetupPhase03_RefreshPatchBaseline`:
  `Start-DebugTrace -PhaseName 'P02.5_RefreshPatchBaseline' -PhaseId 'P03'`
  becomes
  `Start-DebugTrace -Context 'Invoke-SetupPhase03_RefreshPatchBaseline' -PhaseId 'P03'`
  (mirrors the call shape used by P01 through P13).
- `Invoke-PlanPhase06_ValidatePatchSet`:
  `Start-DebugTrace -PhaseName 'P04.5_ValidatePatchSet' -PhaseId 'P06'`
  becomes
  `Start-DebugTrace -Context 'Invoke-PlanPhase06_ValidatePatchSet' -PhaseId 'P06'`.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,452 lines).
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.
- All 11 `Start-DebugTrace` call sites now use the canonical
  `-Context <function-name> -PhaseId <PNN>` shape.

### Compatibility

- Pure parameter-name fix in two new functions; no behavioural or
  schema change. r02.1 callers see no surface-level difference.
- `ScriptVersion` is bumped from `update-wsi-2026.05.24-r02.1` to
  `update-wsi-2026.05.24-r02.2`. The `r02.2` suffix communicates a
  second fix-up release of the r02 line.

## [update-wsi-2026.05.24-r02.1] - 2026-05-24

### Fixed — Stage 2 PSScriptAnalyzer (Windows PS 5.1) findings

r02 (`50fdb0f`) passed Stage 1 (Linux pwsh 7 + psa.py 0/0/0) but
failed Stage 2 (Windows PS 5.1 + microsoft/psscriptanalyzer-action)
on three rule categories that psa.py does not enforce. r02.1 addresses
all of them while keeping psa.py at 0/0/0.

- **`PSAvoidUsingBrokenHashAlgorithms`** (Severity = Error; the actual
  cause of the Stage 2 exit-code-1 failure) at `Test-PatchIntegrity`'s
  L2a/L2b SHA-1 checks. The function intentionally uses SHA-1 to
  sanity-check the SHA-1 hashes Microsoft Update Catalogue publishes
  alongside its patches, with SHA-256 (L2c) and Authenticode signatures
  (L3) as the real trust anchors. The previous `# psa-disable-line
  PSA5003 -- MS Catalog SHA-1` comments are a psa.py-specific
  suppression and do not affect the upstream `PSAvoidUsing*` rule.
  Replaced with a function-level
  `[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
       'PSAvoidUsingBrokenHashAlgorithms', '', Justification = '...')]`
  which is the canonical PSScriptAnalyzer suppression mechanism.
- **`PSUseDeclaredVarsMoreThanAssignments`** (Severity = Warning) at
  `Invoke-HyperVBootTest`'s `$vm = New-VM ...` assignment. The local
  `$vm` was never read again (subsequent operations use the VM name).
  Replaced with `New-VM ... | Out-Null` to match the surrounding
  Hyper-V calls' style.
- **`PSUseOutputTypeCorrectly`** (Severity = Information; x9 instances)
  at `Get-PhaseListByAction`'s nine `return @(...)` arms. PSSA
  cannot infer that an unannotated `@('a','b')` collection literal
  conforms to the declared `[OutputType([string[]])]`. Each `return`
  is now cast explicitly: `return [string[]]@('P01', 'P02', ...)`.

### Fixed — preventive (not yet observed on CI)

Local PSScriptAnalyzer 1.25.0 also surfaces one `PSReviewUnusedParameter`
warning (`$OsLanguage` declared but unused) inside
`Resolve-PatchSetFromCatalog`. CI's psscriptanalyzer-action@v1.1
appears to ship an earlier PSSA build that does not include this rule,
but to avoid future surprises the parameter is now used by an
informational `Write-Step` call at the head of the function.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,452 lines).
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning / Information.

### Compatibility

- Pure additive / mechanical changes: no behavioural difference from
  r02 at runtime.
- `ScriptVersion` is bumped from `update-wsi-2026.06.10-r02` to
  `update-wsi-2026.05.24-r02.1`; the `r02.1` suffix communicates a
  fix-up release of the r02 line.

## [update-wsi-2026.06.10-r02] - 2026-06-10

### Added — dynamic baseline (M2)

- New parameter `-PatchMonth yyyy-MM` to scope the Catalogue search
  (default: current month's Patch Tuesday).
- New parameter `-SkipDynamicPatchRefresh` to bypass P03 even when
  the baseline is stale (offline / air-gapped runs).
- New parameter `-UseBaselineOnly` to forbid all Catalogue access
  and use `PatchBaseline.Patches` strictly as-is.
- New phase **P03 RefreshPatchBaseline**: when
  `PatchTuesdayOfBaseline < Get-LatestPatchTuesday()`, scrape the
  Microsoft Update Catalogue for the target month (SSU + LCU +
  DynamicUpdate.Setup + DynamicUpdate.Component + DynamicUpdate.SafeOs
  + .NET CU), populate `PatchBaseline.Patches`, and write back to
  `Config/<OsKey>.json` atomically.
- Three scraper helpers (`Get-UpdateIdFromCatalog`,
  `Get-DownloadLinkFromCatalog`, `Get-SupersedenceFromCatalog`) that
  use `-UseBasicParsing` for Windows PowerShell 5.1 compatibility,
  set a polite User-Agent, and apply up to `ScrapeRetries` retries
  with jitter on transient HTTP failures.
- `Resolve-PatchSetFromCatalog` orchestrator that issues per-patch-type
  Catalogue queries, filters by OS title token + `x64` architecture,
  and auto-links each LCU's `RequiresKbIds` to the SSU(s) found in
  the same pass.
- Patch Tuesday calculator (`Get-PatchTuesdayForMonth`,
  `Get-LatestPatchTuesday`) with a 1-day buffer to avoid same-day
  edge cases (SPEC §D.15).

### Added — dependency validation (M3)

- New parameter `-WsusScnCabPath` to point at a pre-staged
  `wsusscn2.cab` instead of triggering an automatic download.
- New parameter `-IgnorePatchValidation` to demote P06 failure
  from abort to warning (NOT recommended for production).
- New phase **P06 ValidatePatchSet**: after the install.wim is
  extracted, optionally download (initial run OR cache older than
  current Patch Tuesday) and run a Windows Update Agent COM API
  offline scan with `Microsoft.Update.Session` against the supplied
  patch set. On any missing required patch: ABORT.
- Four diagnostic files emitted under `<WorkRoot>/diag/<timestamp>/`
  on validation failure:
    - `validation_summary.json` (top-level result + missing list)
    - `validation_detail.csv` (one row per patch with Provided / RequiredByWUA / DownloadHint)
    - `wsusscn2_scan_raw.json` (full raw WUA output)
    - `dependency_graph.json` (KB Requires / Supersedes adjacency)
- Diagnostic files are always emitted on detected-missing, regardless
  of `-IgnorePatchValidation`.

### Changed

- ScriptVersion: `update-wsi-2026.06.10-r02`,
  ScriptTag: `dynamic-baseline-and-wsusscn2-validation`.
- Banner unchanged: "Windows Server ISO Updater".
- P02 ResolveInputs: the patch-source resolution chain now also accepts
  "PatchBaseline-driven" when no explicit source (`-PatchUrls` /
  `-PatchDirectory` / `-ManifestPath`) is supplied AND
  `PatchBaseline.Patches` is non-empty (or `-AutoDetectLatestPatches`
  is set, in which case P03 will populate it).
- Phase registry: 11 entries (was 9). Action mappings updated to
  include P03 before P04 and P06 between P05 and P07.
- `Action GenerateManifest` now runs P01, P02, P03 (real Catalogue
  scrape that writes back to Config) instead of the r01 placeholder.

### Configuration

- `Config/Server201[6/9].json`, `Config/Server202[2/5].json` extended:
  - Added `PatchBaseline` node (Schema 1.0) with `TargetBuildAfterUpdate`,
    `PatchTuesdayOfBaseline`, `LastVerifiedDate`, `LastVerifiedBy`,
    `VerificationMethod`, `VerifiedOsLanguages`, `ChecksumAlgorithm`,
    `Patches`, `ExcludeKbList`, and `WsusScnCab`.
  - Added `AutoRefreshPolicy` node with `Mode`, `WritebackToConfig`,
    `FallbackOnScrapeFailure`, `ScrapeRetries`.
  - `AutoDetectKnownGood` marked deprecated (kept for r01 compatibility).
  - Server 2025 `ExcludeKbList` populated with KB5043080 (Checkpoint
    Cumulative Update; not required for OS install).

### Quality

- **psa.py**: 0 errors / 0 warnings / 0 info on the
  combined 5,447-line script (was 4,093 lines in r01).
- All r02 helpers have `[OutputType()]` declarations.
- All `r02`-anchored revision tags removed from script body comments
  (PSAP0003 / PSAP0005 compliant — revision history is here in the
  CHANGELOG, not in source comments).
- New `$matches` auto-variable usage in the Catalogue scraper replaced
  with explicit `[regex]::Match(...).Groups[N].Value` to satisfy
  PSA2002 (SPEC §D.17).

### Compatibility

- r01-format `Config/<OsKey>.json` files load unchanged (the `PatchBaseline`
  node is optional from the loader's perspective; if absent at load
  time, P03 will create it on first scrape).
- All r01 command lines (`-Action`, `-IsoPath`, `-PatchDirectory`,
  `-ManifestPath`, `-SyntheticTestMode -DryRun`, etc.) continue to
  work identically.

### Known limitations

- The Catalogue scraper depends on the current HTML structure of
  catalog.update.microsoft.com. A Microsoft-side change will break
  the scraper; the `AutoRefreshPolicy.FallbackOnScrapeFailure`
  setting controls the recovery behaviour.
- `Invoke-WuaOfflineScan` scans the local Windows host's installed
  image against the offline catalog; it is NOT a true WIM-level
  scan (SPEC §D.18). The validator's findings remain a strong signal
  for dependency completeness in practice.
- M5 (monthly Stage 4 catalog-health workflow) is not yet implemented.
- M4 (Server 2025 MUM/CAB LCU expand) is still a placeholder.

## [update-wsi-2026.05.24-r01] - 2026-05-24

### Added — script

- Initial MVP (M1 milestone) of `Update-WindowsServerIso.ps1`.
- 4,093-line single-file PowerShell script. UTF-8 with BOM, CRLF
  line endings, ASCII-only source bytes.
- Nine-phase pipeline (P01..P13) driven by a registry of
  `pscustomobject` entries and dispatched by `Invoke-PhaseRunner`.
- Sandbox-by-default semantics; destructive operations require
  `-Execute`.
- Synthetic test mode (`-SyntheticTestMode`) for CI: builds a tiny
  non-bootable ISO without downloading any Microsoft asset.
- Hyper-V Gen2 boot smoke test (`-Action BootTest`).
- Four OS configuration profiles under `Config/`:
  `Server2016.json`, `Server2019.json`, `Server2022.json`,
  `Server2025.json`. Per-language entries for en-us and ja-jp.
- Three-layer patch integrity check (filename SHA-1, content SHA-256,
  Authenticode signature) in `Test-PatchIntegrity`.
- DISM mount lifecycle hardened with OSDBuilder-style cleanup and
  10 s + 30 s retry in `Invoke-WimMountSafe` /
  `Invoke-WimDismountSafe` (see SPEC §D.1).
- `0x800f081e` and `0x800f0a13` suppression as Warning per
  documented heuristics in `Add-WindowsPackageWithRetry`
  (SPEC §D.8, §D.9).
- Three-tier boot file fallback chain (`etfsboot.com`, `efisys.bin`)
  in `Resolve-EtfsbootCom` / `Resolve-EfisysBin` (SPEC §D.4).
- Debug Trace Facility with JSONL output on failure, reused verbatim
  from the companion in-house script
  [`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1).

### Added — configuration files

- `.psa.config.json` — psa.py project configuration. Enables all
  PSAP00xx opt-in rules. Lists every Microsoft in-box cmdlet used by
  this script in `psa2010_known_cmdlets` so that the undefined-call
  rule stays silent.
- `PSScriptAnalyzerSettings.psd1` — PSScriptAnalyzer settings.
  Excludes `PSAvoidUsingWriteHost` (operator-facing UX uses the
  Write-Step / Write-Ok wrappers), `PSUseShouldProcessForStateChangingFunctions`
  (script is invoked via `.\` not as a module), and
  `PSUseCmdletBinding` (top-level CmdletBinding already in place).

### Added — documentation

- `README.md` — English primary user documentation, including
  required `## ⚠️ Disclaimer` and `## License` sections.
- `README.ja.md` — Japanese mirror of `README.md`.
- `SPEC.md` — authoritative developer / LLM specification.
  Inherits Part A from the
  [Download-SpeakerDeck SPEC](../download-speakerdeck-oracle4engineer/SPEC.md);
  Part B contains this script's unique contract (workspace layout,
  output naming, OS profile schema, per-phase contracts,
  action→phase mapping, ISO filename patterns, integrity check,
  synthetic mode); Part C is the quality-gate checklist;
  Part D is the catalogue of known pitfalls.
- `CHANGELOG.md` — this file.

### Added — CI workflows (at repo root `.github/workflows/`)

- `scripts__powershell__update-windows-server-iso__stage1__linux.yml`
  — Stage 1, Linux: `psa.py` + PSScriptAnalyzer in pwsh 7, BOM /
  CRLF / ASCII guard, Config JSON parse check.
- `scripts__powershell__update-windows-server-iso__stage2__windows.yml`
  — Stage 2, Windows: PSScriptAnalyzer in PS 5.1, parse-only check,
  read-only smoke modes (`ListPhases`, `EnvironmentInfoOnly`,
  `-SyntheticTestMode -DryRun`).
- `scripts__powershell__update-windows-server-iso__stage3__synthetic.yml`
  — Stage 3, Windows: ADK install (cached), full
  `-SyntheticTestMode` pipeline with `-Execute`. **No ISO artifact is
  ever uploaded**; only logs and diag are persisted as 14-day
  artifacts.

### Quality

- **psa.py**: 0 errors, 0 warnings, 0 info on
  `Update-WindowsServerIso.ps1`.
- All 13 advanced helper functions declare `[OutputType()]`.
- All top-level `param()` variables are accessed via `$Script:`
  from nested functions (PSA2001 compliance).
- No `Split-Path -LiteralPath ... -Parent` (PowerShell 5.1 ja-JP
  AmbiguousParameterSet workaround applied via
  `[System.IO.Path]::GetDirectoryName`).
- No `$args` shadowing (renamed to `$dismArgs` in
  `Invoke-DismCleanup`).
- All inline `# psa-disable-line` annotations carry an explicit
  justification.

### Compatibility

- Windows PowerShell 5.1: required base.
- PowerShell 7.x: also supported.
- Server 2016 / 2019 / 2022 / 2025: all supported.
- en-us and ja-jp ISOs: all supported.

### Known limitations

- `-AutoDetectLatestPatches` is a placeholder; populate Config
  `AutoDetectKnownGood` manually for now. Real implementation lands
  in M2.
- Server 2025 `LCUExpandViaMum=true` is configured but the actual
  expand-via-MUM code path is a future work item (M3).
- x86 and ARM64 are out of scope.
- BootTest requires a local Windows 11 host with Hyper-V; CI cannot
  exercise nested virtualisation.
- The Microsoft Update Catalogue scraper is local-only and not run
  in CI.
