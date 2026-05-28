# Self-verification tools for `Update-WindowsServerIso.ps1`

This directory holds Python-based self-verification tools that exist
specifically to support **`Update-WindowsServerIso.ps1`**. They are
not generic test tools and are not part of the wider repository's
`scripts/python/` tooling - they belong with the PowerShell script
they verify and live in the same directory tree.

The tools exist because three of the bugs fixed in r04.3 (see
[`../CHANGELOG.md`](../CHANGELOG.md) and SPEC §D.19 / §D.20 / §D.21)
were caused by **silent Microsoft-side changes** that no static
analysis or pure unit test could have detected:

- Microsoft dropped a comma from Server 2022 update titles, so the
  TitleToken narrow filter started returning zero hits.
- Microsoft started attaching multiple `.msu` files to one .NET CU
  `UpdateId`, and the single-file picker silently dropped the
  second runtime.
- The `Get-PatchType` filename heuristic was always lossy; the
  Catalogue's authoritative Type bucket was being thrown away.

To catch the next variant of these classes of bug before they reach
production, this directory ships five tools, summarised below.

## Tool inventory

| Tool | What it does | When to run | Network? |
|---|---|---|:---:|
| `catalog_probe.py`        (T1) | Live Microsoft Update Catalog probe; asserts each known scrape pattern still yields > 0 hits, diffs against snapshot | Before / after editing any Catalogue-related helper; in CI monthly | Yes |
| `catalog_fixture_test.py` (T2) | Offline regression test against saved HTML fixtures under `fixtures/<patch-month>/`; deterministic | After every parser or TitleToken change; on every CI run | No  |
| `powershell_harness.py`   (T3) | Drives `Update-WindowsServerIso.ps1 -Action TestHarness` to unit-test PowerShell functions from Python | After every PS function change in the catalog / patch-selection layers | No  |
| `eval_iso_probe.py`       (T4) | HTTP Range-GET against each `data/config-Server<N>.json` Iso URL; reports size + Last-Modified | When the Microsoft Evaluation Center publishes a new snapshot; before release | Yes |
| `wsusscn2_probe.py`       (T5) | HTTP probe of `wsusscn2.cab`; warns when the cab is older than 60 days | Before running P06 ValidatePatchSet; on every CI monthly refresh | Yes |
| `release_info_parser_test.py` (T6) | Offline regression test for the PowerShell `ConvertFrom-ReleaseInfoMarkdown` parser against the PoC fixture; asserts row counts and per-OS coverage | After every change to the release-info parser or its helpers; on every CI run | No  |
| `dotnet_cu_parser_test.py` (T7) | Offline regression test for `ConvertFrom-DotNetCuIndexMarkdown` and `ConvertFrom-DotNetCuMarkdown` against live-captured snapshots under `tests/snapshots/dotnet_cu/` (independent of the PoC fixtures); 16 assertions covering entry counts, date range, per-OS row counts, per-entry deep equality, typo handling, and OS-label mapping | After every change to the .NET CU parsers, the OS-label mapper, or the fetch/cache pipeline; on every CI run | No  |
| `dynamic_update_cache_test.py` (T8) | Offline regression test for the Dynamic Update 36-month cache subsystem; drives `Add-DynamicUpdateCacheEntry`, `Get-DynamicUpdateCache`, `Get-LatestDynamicUpdate`, `Remove-DynamicUpdateOutsideWindow` through three fixture scenarios (mixing live Catalog probe results from 2026-05-26 with synthetic older months) plus three ad-hoc scenarios (cross-OS isolation, missing-file empty cache, PatchMonth validation); 20 assertions, isolated via `-DataDir` and anchored via `-Now` | After every change to the DU cache functions or the 36-month window logic; on every CI run | No  |
| `catalog_title_tokens_test.py` (T9) | Offline regression test for the URL-resolver Config-driven narrowing; drives `Get-CatalogTitleTokenList` against all four OS configs (verifies sourcing + missing-Config defensive default) and `Test-CatalogTitleMatch` through 13 live-captured Catalog title cases (positive matches, same-KB client-variant rejection, `arm64` / `Windows 11` negative exclusion); 18 assertions | After every change to `Common.CatalogTitleTokens` in any OS config, or to the narrow-filter helpers; on every CI run | No  |
| `release_info_resolver_test.py` (T10) | Offline regression test for the Refresher main-path migration; drives `Get-PatchSetFromReleaseInfoDiscovery` through four scenarios (Server 2025/2022/2019 full set + no-match month) plus defensive cases (empty data dir, invalid PatchMonth). Synthetic fixtures derived from live 2026-05-26 captures cover SPEC B.23.5 B-2 multi-row .NET CU per OS and SPEC B.23.6 absence-of-DU; 18 assertions | After every change to `Resolve-PatchSetFromReleaseInfo`, the discovery helper, or any of the three caches it reads; on every CI run | No  |
| `canonical_json_test.py` (T11) | Offline byte-level parity test between `ConvertTo-CanonicalJson` / `Save-CanonicalJsonFile` (PowerShell, in `Update-WindowsServerIso.ps1`) and `canonical_json_dumps` / `save_canonical_json_file` (Python, in `tests/common/canonical_json.py`); 26 assertions covering primitives (12), collections (8), Unicode (3), real-world `data/*.json` shapes (2), and file-level save (1). Verifies the SPEC Part B.23 byte-level parity contract for `data/*.json` and `tests/fixtures/*.json` files. | After every change to `ConvertTo-CanonicalJson`, `Save-CanonicalJsonFile`, or `tests/common/canonical_json.py`; on every CI run | No  |
| `wsusscn2_parser_test.py` (T12) | Offline self-verification of the wsusscn2 parser pipeline Stages 3 and 4. Drives `ConvertFrom-WsusScnPackageXml` + `New-WsusScnDependencyDatabase` against the small committed fixture `fixtures/wsusscn2/package.xml`, then structurally compares against `fixtures/wsusscn2/expected-output.json` (after stripping environmental `scriptVersion` / `scriptTag` / `generatedAt` / `sourceCab` fields). 22 assertions covering: stats parity, scope-filter admit/reject (Product/Classification/recency), Category-Update detection, FileLocation -> payload-URL join with orphan-digest accounting, Microsoft-prose absence in both fixture and parser output (SPEC §B.19.8 hard rule). | After every change to Stage 3 or Stage 4 of the wsusscn2 parser pipeline, the scope-filter GUID tables, or the `tests/common/wsusscn2_fixture_builder.py` helper; on every CI run | No  |
| `wsusscn2_layer1_test.py` (T13) | Offline self-verification of the Phase 2b2/2b3 Layer 1 writeback helper `Update-Layer1DependencyVerification`. Drives the parser against the T12 fixture, then calls the helper against a tempdir-cloned `data/config-Server*.json` skeleton. 15 assertions covering: stub-config setup pre-flight, Run-1 counts (`UpdatedCount=2`, `UnchangedCount=0`, `MissingCount=2`), field-level correctness of `_DependencyVerifiedUpdateId` / `_DependencyVerifiedRevisionId` / `_DependencyVerifiedCreationDate` on Server 2022 and Server 2025, missing-OS hygiene (no spurious writeback for Server 2016/2019), existing-field preservation (`OsKey`), and idempotent Run-2 (`UpdatedCount=0`, `UnchangedCount=2`). The test never touches the repository's real `data/`. | After every change to `Update-Layer1DependencyVerification`, the `$Script:WsusScnOsCategoryGuids` table, or the A04 wrapper's Layer 1 callout site; on every CI run | No  |
| `canonical_json_format_check.py` (Part C gate) | Offline format compliance check for every `*.json` file under `data/`, `tests/fixtures/`, and `tests/snapshots/`. Re-serialises each file through `canonical_json_dumps` and fails if the bytes diverge. Implements SPEC §C.3.4. | On every commit that adds or modifies a JSON file in the three scanned directories; on every CI run | No  |

## Quick start

```bash
# Offline tests - safe to run anywhere
cd tests/
python3 catalog_fixture_test.py            # T2: 13 assertions on saved HTML
python3 powershell_harness.py              # T3: 7 PS function-level assertions
python3 canonical_json_test.py             # T11: 26 PS/Python byte-level parity assertions
python3 wsusscn2_parser_test.py            # T12: 22 wsusscn2 parser pipeline assertions
python3 wsusscn2_layer1_test.py            # T13: 15 Layer 1 writeback helper assertions
python3 canonical_json_format_check.py     # Part C: every JSON file in canonical format

# Live tests - require network access to Microsoft endpoints
python3 catalog_probe.py --check all       # T1: hits live Catalog (~7 checks)
python3 catalog_probe.py --snapshot        # T1: saves snapshots/last_probe.json
python3 eval_iso_probe.py                  # T4: hits 4 OS Iso CDN URLs
python3 wsusscn2_probe.py                  # T5: hits wsusscn2.cab endpoint
```

## What Claude (or a human operator) should do, when

### "I want to change a parser regex in `Update-WindowsServerIso.ps1`"

1. Run `python3 catalog_fixture_test.py` first - confirm the existing
   fixtures still parse 100% with the current code (baseline).
2. Edit the regex (in `common/html_parsers.py` AND in the matching PS
   function - they are intentionally duplicated for redundancy).
3. Re-run `python3 catalog_fixture_test.py` - assert nothing broke.
4. Run `python3 catalog_probe.py --check all` - confirm the new
   regex still works against live Microsoft HTML.
5. If steps 3 and 4 both pass, the change is safe.

### "I want to change `Get-CatalogQueryTemplate` (TitleTokens or query
strings)"

1. Run `python3 powershell_harness.py` - confirm current tests pass.
2. Edit the template.
3. Re-run `python3 powershell_harness.py`.
4. Add a new test case in `powershell_harness.py` covering the new
   token/query if the change is non-trivial.
5. Run `python3 catalog_probe.py --check title-format` - confirm
   live Catalog still narrows correctly.

### "I want to verify the Server 2025 evaluation ISO is still hosted"

```bash
python3 eval_iso_probe.py --os Server2025
```

The probe reports each URL's HTTP status, total size in MB, and
`Last-Modified`. If the size drops dramatically (~< 100 MB), the CDN
likely de-listed the snapshot and `data/config-Server2025.json#/.../Iso/Url`
needs to be refreshed by hand against the Microsoft Evaluation Center
[https://www.microsoft.com/evalcenter/](https://www.microsoft.com/evalcenter/).

### "I want to verify Microsoft has not changed Catalogue HTML structure
this month"

```bash
python3 catalog_probe.py --check all --patch-month 2026-05 --snapshot
```

The probe writes `snapshots/last_probe.json`. Compare with the prior
snapshot in `git diff` to see what changed. If meaningful drift is
reported, follow SPEC §D.19 / §D.20 to update the affected
PS function.

### "I am writing a brand-new Catalogue-related helper and want to test
it from Python"

1. Add the function to `Update-WindowsServerIso.ps1`.
2. Run `python3 -c "from common.ps_invoke import PSSession;
   with PSSession('../Update-WindowsServerIso.ps1') as ps: print(ps.invoke('YourNewFunction', YourArg='value'))"`
   for a manual smoke test.
3. Add a `test_*` function in `powershell_harness.py` for permanent coverage.

## Refreshing fixtures (`fixtures/<patch-month>/`)

Fixtures are snapshots of the live Microsoft Update Catalog HTML at a
specific point in time. They are checked into Git so the offline
regression test (T2) is deterministic. To refresh them for a new
patch month:

```bash
# 1. Run T1 with the new month to confirm Catalog is queryable
python3 catalog_probe.py --check all --patch-month 2026-06

# 2. Re-collect fixtures with the bundled helper (see fixtures/README.md)
#    The collector hits Search.aspx for each OS / Type combination
#    and writes one .html file per query + an expected.json with the
#    parsed results that T2 will then assert against.
```

The `fixtures/2026-05/` set was generated this way during r04.4
implementation and serves as both the regression baseline AND the
documented "this is what 2026-05 Catalogue listings looked like"
historical record.

## Dependency policy

These tools use **only the Python standard library**. No
`pip install` is required - they run on every system that has
Python 3.10 or newer. This matches the dependency policy of
[`../../python/powershell-static-analyzer/psa.py`](../../python/powershell-static-analyzer/psa.py),
which sets the precedent for "standard-library-only Python tooling
in this repository".

PowerShell-side: the tools require either `pwsh` (PowerShell 7+) or
Windows `powershell`. `pwsh` is preferred and the only one tested
on Linux; `powershell` (Windows 5.1) works on Windows hosts.

## File layout

```
tests/
  README.md                  this file
  catalog_probe.py           T1
  catalog_fixture_test.py    T2
  powershell_harness.py      T3
  eval_iso_probe.py          T4
  wsusscn2_probe.py          T5
  wsusscn2_parser_test.py    T12 (Stage 3 + Stage 4 self-verification, 22 assertions)
  wsusscn2_layer1_test.py    T13 (Phase 2b2/2b3 Layer 1 writeback helper, 15 assertions)
  common/
    __init__.py              package marker
    catalog_client.py        urllib HTTP fetcher with retry-jitter
    html_parsers.py          Catalog HTML regex extractors (mirror of PS)
    ps_invoke.py             PSSession context manager for TestHarness REPL
    snapshot.py              JSON snapshot read/write + diff
    canonical_json.py        Python reference for SPEC Part B.23 canonical JSON (used by T11)
    wsusscn2_analyzer.py     wsusscn2.cab schema-discovery helper (CLI + library; used by the Phase 2b1 investigation, see research/windows-servicing §2.4.1 / §5.7 / §6.4)
    wsusscn2_fixture_builder.py  Generator for the T12 fixture (`fixtures/wsusscn2/package.xml` + `expected-output.json`); CLI + library
  fixtures/
    2026-05/
      server2016_lcu_search.html
      server2019_lcu_search.html
      server2019_dotnet_search.html  # umbrella .NET CU regression input
      server2022_lcu_search.html     # comma-less title regression input
      server2025_lcu_search.html
      sample_scopedview.html         # supersedence parse input
      expected.json                  # parsed expectations for T2
    wsusscn2/
      package.xml                    # minimal hand-crafted Master XML for T12
      expected-output.json           # canonical-JSON expected parser output for T12
  snapshots/
    .gitkeep
    last_probe.json          (written by T1 --snapshot)
```

## How these tools relate to CI

T2 (offline) is the only tool that runs reliably in CI without
external dependencies; it should be the gate for every PR. T1, T4,
T5 are appropriate for the monthly CI workflow
(`stage4__monthly-refresh.yml`) where they catch Microsoft-side
drift early. T3 requires a `pwsh`-capable runner, which CI Stage 1
already has, so T3 also belongs in that workflow.

## Retired r06 Phase 2 PoC (r07.0)

Earlier releases hosted a `poc_<topic>_<step>_<verb>.py` family
here that drove the Phase 2 investigation behind the §B.23
architecture. As of r07.0 those scripts have been retired: their
parser / resolver logic was promoted into
`Update-WindowsServerIso.ps1` (`Get-PatchSetFromReleaseInfoDiscovery`,
`ConvertFrom-ReleaseInfoMarkdown`, `ConvertFrom-DotNetCuMarkdown`,
`Resolve-PatchSetFromReleaseInfo`), regression coverage moved to
T6-T10 above, and the historical reports were moved to
`docs/history/`. The `poc_<topic>_*` naming convention itself is
preserved in SPEC.md §B.22.2 as a reserved pattern for any future
PoC investigation.

