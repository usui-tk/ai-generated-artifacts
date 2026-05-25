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
| `eval_iso_probe.py`       (T4) | HTTP Range-GET against each `Config/Server<N>.json` Iso URL; reports size + Last-Modified | When the Microsoft Evaluation Center publishes a new snapshot; before release | Yes |
| `wsusscn2_probe.py`       (T5) | HTTP probe of `wsusscn2.cab`; warns when the cab is older than 60 days | Before running P04.5 ValidatePatchSet; on every CI monthly refresh | Yes |

## Quick start

```bash
# Offline tests - safe to run anywhere
cd tests/
python3 catalog_fixture_test.py            # T2: 13 assertions on saved HTML
python3 powershell_harness.py              # T3: 7 PS function-level assertions

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
likely de-listed the snapshot and `Config/Server2025.json#/.../Iso/Url`
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
  common/
    __init__.py              package marker
    catalog_client.py        urllib HTTP fetcher with retry-jitter
    html_parsers.py          Catalog HTML regex extractors (mirror of PS)
    ps_invoke.py             PSSession context manager for TestHarness REPL
    snapshot.py              JSON snapshot read/write + diff
  fixtures/
    2026-05/
      server2016_lcu_search.html
      server2019_lcu_search.html
      server2019_dotnet_search.html  # umbrella .NET CU regression input
      server2022_lcu_search.html     # comma-less title regression input
      server2025_lcu_search.html
      sample_scopedview.html         # supersedence parse input
      expected.json                  # parsed expectations for T2
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
