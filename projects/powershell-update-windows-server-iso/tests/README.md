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
| `catalog_fixture_test.py` (T2) | Offline regression test against saved HTML fixtures under `fixtures/<patch-month>/`; deterministic | After every parser change; on every CI run | No  |
| `powershell_harness.py`   (T3) | Drives `Update-WindowsServerIso.ps1 -Action TestHarness` to unit-test PowerShell functions from Python | After every PS function change in the catalog / patch-selection layers | No  |
| `eval_iso_probe.py`       (T4) | HTTP Range-GET against each `data/config-Server<N>.json` Iso URL; reports size + Last-Modified | When the Microsoft Evaluation Center publishes a new snapshot; before release | Yes |
| `release_info_parser_test.py` (T6) | Offline regression test for the PowerShell `ConvertFrom-ReleaseInfoMarkdown` parser against the PoC fixture; asserts row counts and per-OS coverage | After every change to the release-info parser or its helpers; on every CI run | No  |
| `dotnet_cu_parser_test.py` (T7) | Offline regression test for `ConvertFrom-DotNetCuIndexMarkdown` and `ConvertFrom-DotNetCuMarkdown` against live-captured snapshots under `tests/snapshots/dotnet_cu/` (independent of the PoC fixtures); 16 assertions covering entry counts, date range, per-OS row counts, per-entry deep equality, typo handling, and OS-label mapping | After every change to the .NET CU parsers, the OS-label mapper, or the fetch/cache pipeline; on every CI run | No  |
| `canonical_json_test.py` (T11) | Offline byte-level parity test between `ConvertTo-CanonicalJson` / `Save-CanonicalJsonFile` (PowerShell, in `Update-WindowsServerIso.ps1`) and `canonical_json_dumps` / `save_canonical_json_file` (Python, in `tests/common/canonical_json.py`); 26 assertions covering primitives (12), collections (8), Unicode (3), real-world `data/*.json` shapes (2), and file-level save (1). Verifies the SPEC Part B.23 byte-level parity contract for `data/*.json` and `tests/fixtures/*.json` files. | After every change to `ConvertTo-CanonicalJson`, `Save-CanonicalJsonFile`, or `tests/common/canonical_json.py`; on every CI run | No  |
| `catalog_patchset_builder_test.py` (T27) | Offline b3 config-dataset builder: drives `ConvertTo-ConfigLines` through the TestHarness REPL against the committed layer-1 raw fixture (`fixtures/catalog_raw/resolve-2026-06.json`) to BUILD `PatchBaseline.Lines[]` without live Catalog I/O -- restores the pre-D2 offline construction path. 14 assertions: per-OS Kinds match the `PatchModel` allowed set, every Line carries a `Digest`, the uup-checkpoint OS builds a `SetupDU` Line at `ApplyOrder` 5. | After every change to `ConvertTo-ConfigLines`, the b3 transform, or the raw fixture; on every CI run | No  |
| `canonical_json_format_check.py` (Part C gate) | Offline format compliance check for every `*.json` file under `data/`, `tests/fixtures/`, and `tests/snapshots/`. Re-serialises each file through `canonical_json_dumps` and fails if the bytes diverge. Implements SPEC §C.3.4. | On every commit that adds or modifies a JSON file in the three scanned directories; on every CI run | No  |
| `config_schema_test.py` (config schema gate) | Offline schema-conformance check. A stdlib-only draft-07-subset validator that checks every `data/config-Server*.json` against `schema/config.schema.json` (forbids the legacy `Patches` property, requires `NeutralPatches`), with a targeted r10.4 regression guard against `Patches` reappearing. 14 assertions. No T number — schema gate, mirroring the format-gate convention. | On every commit that touches `data/config-Server*.json` or `schema/config.schema.json`; on every CI run | No  |
| `seed_contract_test.py` (seed contract gate) | Offline SEED/DERIVED-boundary gate (SPEC B.14.2). Mechanically coordinates the data pipeline with the schema: asserts every `schema/config.schema.json` field is classified as exactly one of SEED (admitted by `schema/config-seed.schema.json`) or DERIVED (a declared table grounded in what the refreshers generate), with no unclassified field, no overlap, and no seed-extra; checks the seed schema is a faithful projection (shared definitions byte-equal; `PatchBaselineSeed` = the `PatchBaseline` envelope); and validates every `data/seed/seed-Server*.json` against the seed schema (reusing the `config_schema_test` validator). 17 assertions. No T number — schema gate. Guards against a config-schema field being silently dropped from the seed. | On every commit that touches `schema/config*.json` or `data/seed/`; on every CI run | No  |

## Quick start

```bash
# Offline tests - safe to run anywhere
cd tests/
python3 catalog_fixture_test.py            # T2: 13 assertions on saved HTML
python3 powershell_harness.py              # T3: 7 PS function-level assertions
python3 canonical_json_test.py             # T11: 26 PS/Python byte-level parity assertions
python3 removed_live_wua_guard_test.py                 # T20: 21 removed-live-WUA static-guard assertions
python3 canonical_json_format_check.py     # Part C: every JSON file in canonical format
python3 config_schema_test.py              # config schema gate: data/config-Server*.json vs v2.1 schema
python3 seed_contract_test.py              # seed contract gate: SEED/DERIVED boundary coordinated with the schema

# Live tests - require network access to Microsoft endpoints
python3 catalog_probe.py --check all       # T1: hits live Catalog (~7 checks)
python3 catalog_probe.py --snapshot        # T1: saves snapshots/last_probe.json
python3 eval_iso_probe.py                  # T4: hits 4 OS Iso CDN URLs
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
  removed_live_wua_guard_test.py         T20 (removed-live-WUA static guard: functions/params absent + P06 gate wired, 21 assertions)
  catalog_patchset_builder_test.py       T27 (offline b3 dataset builder: ConvertTo-ConfigLines from captured raw -> PatchBaseline.Lines incl. SetupDU @ ApplyOrder 5, 14 assertions)
  common/
    __init__.py              package marker
    catalog_client.py        urllib HTTP fetcher with retry-jitter
    html_parsers.py          Catalog HTML regex extractors (mirror of PS)
    ps_invoke.py             PSSession context manager for TestHarness REPL
    snapshot.py              JSON snapshot read/write + diff
    canonical_json.py        Python reference for SPEC Part B.23 canonical JSON (used by T11)
  fixtures/
    2026-05/
      server2016_lcu_search.html
      server2019_lcu_search.html
      server2019_dotnet_search.html  # umbrella .NET CU regression input
      server2022_lcu_search.html     # comma-less title regression input
      server2025_lcu_search.html
      sample_scopedview.html         # supersedence parse input
      expected.json                  # parsed expectations for T2
    config-guard/
      bad-config-ssu-empty-url.json  # Type=SSU with empty DownloadUrl: the T23 negative fixture
    catalog_raw/
      resolve-2026-06.json           # captured layer-1 { os; lines[] } incl. a SetupDU line: T27 offline-build input
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
`Update-WindowsServerIso.ps1` (`ConvertFrom-ReleaseInfoMarkdown`,
`ConvertFrom-DotNetCuMarkdown`; the release-info discovery/resolver
pair was later removed in the data-source migration), regression
coverage moved to T6/T7 above, and the historical reports were moved to
`docs/history/`. The `poc_<topic>_*` naming convention itself is
preserved in SPEC.md §B.22.2 as a reserved pattern for any future
PoC investigation.

